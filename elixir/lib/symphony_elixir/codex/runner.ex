defmodule SymphonyElixir.Codex.Runner do
  @moduledoc """
  Runner behaviour implementation wrapping the existing `Codex.AppServer`.

  Delegates all session lifecycle operations to `AppServer`, adapting
  the unified `Runner` callback signatures to `AppServer`'s internal API.

  ## API Adaptation

  `AppServer.start_session/2` takes `(workspace, opts)` — the `issue` parameter
  from the behaviour contract is dropped since AppServer does not require it.
  """

  @behaviour SymphonyElixir.Runner

  alias SymphonyElixir.Codex.AppServer

  require Logger

  # ------------------------------------------------------------------
  # Runner callbacks
  # ------------------------------------------------------------------

  @impl true
  def start_session(issue, workspace, worker_host) do
    Logger.info("Codex.Runner starting session",
      issue_id: issue[:id] || issue["id"],
      workspace: workspace,
      worker_host: worker_host
    )

    AppServer.start_session(workspace, worker_host: worker_host)
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    case AppServer.run_turn(session, prompt, [], timeout: timeout_ms) do
      {:ok, text} -> {:ok, text, session}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stop_session(session), do: AppServer.stop_session(session)

  @impl true
  def parse_result(text) do
    {:ok, %{status: :success, artifacts: [%{type: :text, content: text}]}}
  end
end
