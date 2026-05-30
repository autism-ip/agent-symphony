defmodule SymphonyElixir.Claude.Runner do
  @moduledoc """
  [INPUT]: 依赖 Runner behaviour、Config.settings!().runner.claude、System.cmd、Claude.JsonParser
  [OUTPUT]: 对外提供 start_session/3、run_turn/3、stop_session/1、parse_result/1
  [POS]: claude/ 的核心 runner 实现，per-turn 进程模型，每次 run_turn 启动独立 CLI 子进程
  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

  Runner behaviour implementation for Claude Code CLI.

  Uses a per-turn process model: each `run_turn/3` call launches an independent
  `claude` CLI subprocess via `System.cmd`, with no persistent session process.

  ## Testability

  The `cmd_fn` stored in the session map defaults to `&System.cmd/3` but can be
  overridden for testing without external mocking libraries.
  """

  @behaviour SymphonyElixir.Runner

  alias SymphonyElixir.{Claude.JsonParser, Config}

  require Logger

  # ------------------------------------------------------------------
  # Runner callbacks
  # ------------------------------------------------------------------

  @impl true
  def start_session(issue, workspace, worker_host) do
    settings = Config.settings!().runner.claude

    Logger.info("Claude.Runner starting session issue_id=#{issue.id} workspace=#{workspace} worker_host=#{worker_host || "local"}")

    session = %{
      workspace: workspace,
      issue_id: issue.id,
      issue_title: issue.title,
      command: settings.command,
      max_turns: settings.max_turns,
      worker_host: worker_host,
      cmd_fn: &System.cmd/3
    }

    {:ok, session}
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    args = [
      "-p",
      prompt,
      "--output-format",
      "json",
      "--max-turns",
      to_string(session.max_turns)
    ]

    opts = [
      cd: session.workspace,
      stderr_to_stdout: true,
      timeout: timeout_ms
    ]

    try do
      case session.cmd_fn.(session.command, args, opts) do
        {output, 0} ->
          {:ok, output, session}

        {output, exit_code} ->
          {:error, {:claude_exit, exit_code, output}}
      end
    rescue
      ErlangError ->
        {:error, {:runner_timeout, :turn, timeout_ms}}
    end
  end

  @impl true
  def stop_session(_session), do: :ok

  @impl true
  defdelegate parse_result(text), to: JsonParser, as: :parse
end
