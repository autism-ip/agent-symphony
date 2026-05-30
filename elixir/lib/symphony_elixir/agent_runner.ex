defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single Linear issue in its workspace using the configured runner.
  """

  require Logger
  alias SymphonyElixir.{ArtifactStore, Config, Linear.Issue, PromptBuilder, Runner, Tracker, Workspace}

  @type worker_host :: String.t() | nil

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, codex_update_recipient \\ nil, opts \\ []) do
    # The orchestrator owns host retries so one worker lifetime never hops machines.
    worker_host = selected_worker_host(Keyword.get(opts, :worker_host), Config.settings!().worker.ssh_hosts)

    Logger.info("Starting agent run for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
    Logger.info("Starting worker attempt for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case Workspace.create_for_issue(issue, worker_host) do
      {:ok, workspace} ->
        send_worker_runtime_info(codex_update_recipient, issue, worker_host, workspace)

        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host) do
            run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host)
          end
        after
          Workspace.run_after_run_hook(workspace, issue, worker_host)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       %{
         worker_host: worker_host,
         workspace_path: workspace
       }}
    )

    :ok
  end

  defp send_worker_runtime_info(_recipient, _issue, _worker_host, _workspace), do: :ok

  defp run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
    max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.max_turns)
    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)
    runner = Runner.adapter()

    with {:ok, session} <- runner.start_session(issue, workspace, worker_host) do
      try do
        turn_context = %{
          codex_update_recipient: codex_update_recipient,
          issue_state_fetcher: issue_state_fetcher,
          max_turns: max_turns,
          opts: opts,
          runner: runner,
          workspace: workspace
        }

        do_run_codex_turns(turn_context, session, issue, 1)
      after
        runner.stop_session(session)
      end
    end
  end

  defp do_run_codex_turns(context, session, issue, turn_number) do
    prompt = build_turn_prompt(issue, context.opts, turn_number, context.max_turns)
    timeout_ms = runner_turn_timeout(context.runner)

    with {:ok, text, session} <-
           context.runner.run_turn(session, prompt, timeout_ms) do
      Logger.info("Completed agent run for #{issue_context(issue)} workspace=#{context.workspace} turn=#{turn_number}/#{context.max_turns}")

      case continue_with_issue?(issue, context.issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < context.max_turns ->
          persist_artifacts(context.runner, context.workspace, refreshed_issue, text)
          Logger.info("Continuing agent run for #{issue_context(refreshed_issue)} after normal turn completion turn=#{turn_number}/#{context.max_turns}")

          do_run_codex_turns(context, session, refreshed_issue, turn_number + 1)

        {:continue, refreshed_issue} ->
          Logger.info("Reached agent.max_turns for #{issue_context(refreshed_issue)} with issue still active; returning control to orchestrator")
          persist_artifacts(context.runner, context.workspace, refreshed_issue, text)

          :ok

        {:done, refreshed_issue} ->
          persist_artifacts(context.runner, context.workspace, refreshed_issue, text)

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_turn_prompt(issue, opts, 1, _max_turns), do: PromptBuilder.build_prompt(issue, opts)

  defp build_turn_prompt(_issue, _opts, turn_number, max_turns) do
    """
    Continuation guidance:

    - The previous Codex turn completed normally, but the Linear issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp selected_worker_host(nil, []), do: nil

  defp selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  defp worker_host_for_log(nil), do: "local"
  defp worker_host_for_log(worker_host), do: worker_host

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  # ------------------------------------------------------------------
  # Runner-aware config helpers
  # ------------------------------------------------------------------

  defp runner_turn_timeout(SymphonyElixir.Claude.Runner) do
    Config.settings!().runner.claude.turn_timeout_ms
  end

  defp runner_turn_timeout(_runner) do
    Config.settings!().runner.codex.turn_timeout_ms
  end

  # ------------------------------------------------------------------
  # Artifact persistence (best-effort)
  # ------------------------------------------------------------------

  defp persist_artifacts(_runner, _workspace, _issue, ""), do: :ok

  defp persist_artifacts(runner, workspace, issue, text) do
    runner
    |> parsed_artifacts(issue, text)
    |> save_artifacts(workspace, issue)
  rescue
    e ->
      Logger.warning("Artifact persistence crashed for #{issue_context(issue)}: #{inspect(e)}")
  end

  defp parsed_artifacts(runner, issue, text) do
    case runner.parse_result(text) do
      {:ok, %{artifacts: artifacts}} when is_list(artifacts) ->
        {:ok, Enum.reject(artifacts, &empty_artifact?/1)}

      {:ok, _empty_result} ->
        :ok

      {:error, reason} ->
        {:warning, "parse_result failed for #{issue_context(issue)}: #{inspect(reason)}"}
    end
  end

  defp save_artifacts(:ok, _workspace, _issue), do: :ok
  defp save_artifacts({:ok, []}, _workspace, _issue), do: :ok
  defp save_artifacts({:warning, message}, _workspace, _issue), do: Logger.warning(message)

  defp save_artifacts({:ok, artifacts}, workspace, issue) do
    case ArtifactStore.save(workspace, issue.id, artifacts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Artifact persistence failed for #{issue_context(issue)}: #{inspect(reason)}")
    end
  end

  defp empty_artifact?(%{type: :text, content: content}) when is_binary(content), do: String.trim(content) == ""
  defp empty_artifact?(%{type: :comment, content: content}) when is_binary(content), do: String.trim(content) == ""
  defp empty_artifact?(_artifact), do: false
end
