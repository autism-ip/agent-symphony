defmodule SymphonyElixir.Runner do
  @moduledoc """
  Behaviour defining the contract for AI agent runners.

  Each runner implementation handles session lifecycle, prompt execution,
  and result parsing for a specific AI agent backend (Codex, Claude, etc.).

  ## Implementations

  - `SymphonyElixir.Codex.Runner` — wraps existing `Codex.AppServer`
  - `SymphonyElixir.Claude.Runner` — launches Claude Code CLI via System.cmd (per-turn process)

  ## Usage

      runner = SymphonyElixir.Runner.adapter()
      {:ok, session} = runner.start_session(issue, workspace, worker_host)
      {:ok, text, session} = runner.run_turn(session, prompt, timeout_ms)
      :ok = runner.stop_session(session)
      {:ok, result} = runner.parse_result(text)
  """

  @type session :: term()
  @type issue :: map()
  @type workspace :: Path.t()
  @type worker_host :: String.t() | nil
  @type result :: %{status: :success | :error | :blocked, artifacts: [map()]}

  @callback start_session(issue(), workspace(), worker_host()) ::
              {:ok, session()} | {:error, term()}

  @callback run_turn(session(), String.t(), non_neg_integer()) ::
              {:ok, String.t(), session()} | {:error, term()}

  @callback stop_session(session()) :: :ok | {:error, term()}

  @callback parse_result(String.t()) :: {:ok, result()} | {:error, term()}

  @doc "Returns the runner module based on current configuration."
  @spec adapter() :: module()
  def adapter do
    case SymphonyElixir.Config.settings() do
      {:ok, %{runner: %{type: "claude"}}} -> SymphonyElixir.Claude.Runner
      {:ok, %{runner: %{type: "codex"}}} -> SymphonyElixir.Codex.Runner
      _ -> SymphonyElixir.Codex.Runner
    end
  end
end
