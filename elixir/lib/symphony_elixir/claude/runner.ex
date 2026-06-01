defmodule SymphonyElixir.Claude.Runner do
  @moduledoc """
  [INPUT]: 依赖 Runner behaviour、Config.settings!().runner.claude、System.cmd、Jason、Claude.JsonParser
  [OUTPUT]: 对外提供 start_session/3、run_turn/3、stop_session/1、parse_result/1
  [POS]: claude/ 的核心 runner 实现，per-turn 进程模型，每次 run_turn 启动独立 CLI 子进程
  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

  Runner behaviour implementation for Claude Code CLI.

  Uses a per-turn process model: each `run_turn/3` call launches an independent
  `claude` CLI subprocess via `System.cmd`, with no persistent session process.
  The subprocess is launched through a tiny `/bin/sh` wrapper so Claude sees
  `/dev/null` on stdin instead of the BEAM port pipe.

  ## CLI flags

  - `--dangerously-skip-permissions` — bypass interactive permission prompts
    that would hang in a non-interactive subprocess context.
  - `--verbose` — required by `--output-format stream-json` in `-p` mode;
    without it the CLI exits immediately with an error.
  - `--output-format stream-json` — NDJSON streaming output; each line is a
    self-contained JSON object. The final line with `type: "result"` carries
    the session ID needed for `--resume`.
  - `--settings {"disableAllHooks":true}` — user plugins may register lifecycle
    hooks that read stdin or wait on local services; the worker runner is a
    non-interactive automation boundary, so hooks are disabled per invocation.
  - `--resume <session_id>` — subsequent turns resume the prior session so
    the agent retains cross-turn context.

  ## Testability

  The `cmd_fn` stored in the session map defaults to `&System.cmd/3` but can be
  overridden for testing without external mocking libraries.
  """

  @behaviour SymphonyElixir.Runner

  alias SymphonyElixir.{Claude.JsonParser, Config, SSH}

  require Logger

  # ------------------------------------------------------------------
  # Runner callbacks
  # ------------------------------------------------------------------

  @impl true
  def start_session(issue, workspace, worker_host) do
    settings = Config.settings!().runner.claude

    Logger.info("Claude.Runner starting session",
      issue_id: issue.id,
      workspace: workspace,
      worker_host: worker_host
    )

    session = %{
      workspace: workspace,
      issue_id: issue.id,
      issue_title: issue.title,
      command: settings.command,
      worker_host: worker_host,
      max_turns: settings.max_turns,
      session_id: nil,
      cmd_fn: &System.cmd/3
    }

    {:ok, session}
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    {command, args} = command_and_args(session, prompt)

    # SSH commands handle cd internally; local commands need cd: option.
    opts =
      case session.worker_host do
        host when is_binary(host) and host != "" ->
          [stderr_to_stdout: true]

        _ ->
          [
            cd: session.workspace,
            stderr_to_stdout: true,
            env: [
              {"CLAUDECODE", nil},
              {"CLAUDE_CODE_ENTRYPOINT", nil},
              {"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"}
            ]
          ]
      end

    task =
      Task.async(fn ->
        try do
          {:ok, session.cmd_fn.(command, args, opts)}
        rescue
          e -> {:cmd_crash, e}
        catch
          kind, reason -> {:cmd_crash, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, {output, 0}}} ->
        session_id = extract_session_id(output)
        {:ok, output, %{session | session_id: session_id}}

      {:ok, {:ok, {output, exit_code}}} ->
        {:error, {:claude_exit, exit_code, output}}

      {:ok, {:cmd_crash, reason}} ->
        {:error, {:cmd_crash, reason}}

      nil ->
        {:error, {:runner_timeout, :turn, timeout_ms}}
    end
  end

  @impl true
  def stop_session(_session), do: :ok

  @impl true
  defdelegate parse_result(text), to: JsonParser, as: :parse

  # ------------------------------------------------------------------
  # CLI argument construction
  # ------------------------------------------------------------------

  defp command_and_args(session, prompt) do
    cli_args = turn_args(session, prompt)
    local_cmd = build_local_command(session.command, cli_args)

    case session.worker_host do
      host when is_binary(host) and host != "" ->
        remote_script = "cd #{shell_escape(session.workspace)} && #{local_cmd}"
        ssh_cmd = SSH.remote_shell_command(remote_script)
        {"ssh", [host, ssh_cmd]}

      _ ->
        {"/bin/sh", ["-c", "exec \"$@\" </dev/null", "--" | [session.command | cli_args]]}
    end
  end

  defp build_local_command(command, args) do
    Enum.join([command | Enum.map(args, &shell_escape/1)], " ")
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp turn_args(session, prompt) do
    base = [
      "-p",
      prompt,
      "--dangerously-skip-permissions",
      "--verbose",
      "--output-format",
      "stream-json",
      "--max-turns",
      Integer.to_string(session.max_turns),
      "--settings",
      Jason.encode!(%{"disableAllHooks" => true})
    ]

    case session.session_id do
      id when is_binary(id) and id != "" ->
        base ++ ["--resume", id]

      _ ->
        base
    end
  end

  # ------------------------------------------------------------------
  # Session ID extraction (NDJSON stream)
  # ------------------------------------------------------------------

  defp extract_session_id(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result", "session_id" => id}} when is_binary(id) -> id
        _ -> nil
      end
    end)
  end

  defp extract_session_id(_), do: nil
end
