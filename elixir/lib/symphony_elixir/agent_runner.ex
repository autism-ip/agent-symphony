defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single Linear issue in its workspace using the configured runner.
  """

  require Logger
  alias SymphonyElixir.{ArtifactStore, Config, GitHub, Linear.Issue, PromptBuilder, Runner, Tracker, Workspace}

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

        run_result =
          try do
            with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host),
                 :ok <- run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
              :ok
            end
          after
            Workspace.run_after_run_hook(workspace, issue, worker_host)
          end

        case run_result do
          :ok -> attempt_delivery(issue, workspace, worker_host)
          error -> error
        end

      {:error, reason} ->
        Logger.error("Worker host setup failed for #{issue_context(issue)}: #{inspect(reason)}")
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
        do_run_codex_turns(runner, session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, 1, max_turns)
      after
        runner.stop_session(session)
      end
    end
  end

  defp do_run_codex_turns(runner, session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, turn_number, max_turns) do
    prompt = build_turn_prompt(issue, opts, turn_number, max_turns)
    timeout_ms = runner_turn_timeout(runner)

    with {:ok, text, session} <-
           runner.run_turn(session, prompt, timeout_ms) do
      Logger.info("Completed agent run for #{issue_context(issue)} workspace=#{workspace} turn=#{turn_number}/#{max_turns}")

      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          persist_artifacts(runner, workspace, refreshed_issue, text)
          Logger.info("Continuing agent run for #{issue_context(refreshed_issue)} after normal turn completion turn=#{turn_number}/#{max_turns}")

          do_run_codex_turns(
            runner,
            session,
            workspace,
            refreshed_issue,
            codex_update_recipient,
            opts,
            issue_state_fetcher,
            turn_number + 1,
            max_turns
          )

        {:continue, refreshed_issue} ->
          Logger.info("Reached agent.max_turns for #{issue_context(refreshed_issue)} with issue still active; returning control to orchestrator")
          persist_artifacts(runner, workspace, refreshed_issue, text)

          :ok

        {:done, refreshed_issue} ->
          persist_artifacts(runner, workspace, refreshed_issue, text)

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
    try do
      case runner.parse_result(text) do
        {:ok, %{artifacts: artifacts}} when is_list(artifacts) and artifacts != [] ->
          non_empty = Enum.reject(artifacts, &empty_artifact?/1)

          case non_empty do
            [] ->
              :ok

            _ ->
              case ArtifactStore.save(workspace, issue.id, non_empty) do
                :ok ->
                  :ok

                {:error, reason} ->
                  Logger.warning("Artifact persistence failed for #{issue_context(issue)}: #{inspect(reason)}")
              end
          end

        {:ok, _empty_result} ->
          :ok

        {:error, reason} ->
          Logger.warning("parse_result failed for #{issue_context(issue)}: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.warning("Artifact persistence crashed for #{issue_context(issue)}: #{inspect(e)}")
    end
  end

  defp empty_artifact?(%{type: :text, content: content}) when is_binary(content), do: String.trim(content) == ""
  defp empty_artifact?(%{type: :comment, content: content}) when is_binary(content), do: String.trim(content) == ""
  defp empty_artifact?(_artifact), do: false

  # ------------------------------------------------------------------
  # GitHub delivery (best-effort, post-run)
  # ------------------------------------------------------------------

  defp attempt_delivery(%Issue{} = issue, workspace, _worker_host) do
    case GitHub.deliver(issue, workspace) do
      {:ok, delivery} ->
        Logger.info("Delivery succeeded for #{issue_context(issue)}: pr_url=#{delivery.pr_url}")
        report_delivery(issue, delivery)
        :ok

      {:error, :no_changes} ->
        Logger.info("No changes to deliver for #{issue_context(issue)}")
        :ok

      {:error, reason} ->
        Logger.warning("Delivery failed for #{issue_context(issue)}: #{inspect(reason)}")
        :ok
    end
  end

  defp report_delivery(%Issue{id: issue_id, identifier: identifier}, delivery) do
    case Process.whereis(SymphonyElixir.Orchestrator) do
      nil ->
        :ok

      pid ->
        send(pid, {:delivery_complete, issue_id, %{
          identifier: identifier,
          pr_url: delivery.pr_url,
          pr_number: delivery.pr_number,
          branch: delivery.branch
        }})
        :ok
    end
  end
end
