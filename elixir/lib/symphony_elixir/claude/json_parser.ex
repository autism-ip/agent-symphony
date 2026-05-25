defmodule SymphonyElixir.Claude.JsonParser do
  @moduledoc """
  [INPUT]: JSON string from Claude CLI `--output-format json` mode
  [OUTPUT]: `{:ok, result}` or `{:error, reason}`
  [POS]: claude/ module — parses raw JSON output into Runner.result() maps
  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  @doc "Parse Claude CLI JSON output into a standardised result map."
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, %{"result" => result}} ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: result}]}}

      {:ok, %{"error" => error}} ->
        {:ok, %{status: :error, artifacts: [%{type: :text, content: error}]}}

      {:ok, _other} ->
        {:error, {:json_decode, :missing_result_or_error_key}}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end
end
