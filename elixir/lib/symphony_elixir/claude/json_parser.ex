defmodule SymphonyElixir.Claude.JsonParser do
  @moduledoc """
  [INPUT]: Raw stdout from Claude CLI (`--output-format json` or `stream-json`)
  [OUTPUT]: `{:ok, result}` or `{:error, reason}`
  [POS]: claude/ module — parses raw CLI output into Runner.result() maps
  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

  Supports two output formats:

  - **Single JSON** (`--output-format json`): one object with `"result"` or `"error"`.
  - **NDJSON** (`--output-format stream-json`): one JSON object per line; the final
    line with `type: "result"` carries the actual result content.
  """

  @doc "Parse Claude CLI output into a standardised result map."
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      ndjson?(trimmed) -> parse_ndjson(trimmed)
      single_json?(trimmed) -> parse_single_json(trimmed)
      true -> {:error, {:json_decode, :unrecognised_format}}
    end
  end

  # ------------------------------------------------------------------
  # Format detection
  # ------------------------------------------------------------------

  defp ndjson?(trimmed) do
    case String.split(trimmed, "\n", parts: 2) do
      [first_line, _rest] ->
        case Jason.decode(first_line) do
          {:ok, %{"type" => _}} -> true
          _ -> false
        end

      [single_line] ->
        case Jason.decode(single_line) do
          {:ok, %{"type" => _}} -> true
          _ -> false
        end
    end
  end

  defp single_json?(trimmed) do
    case Jason.decode(trimmed) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # ------------------------------------------------------------------
  # Single JSON (legacy --output-format json)
  # ------------------------------------------------------------------

  defp parse_single_json(raw) do
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

  # ------------------------------------------------------------------
  # NDJSON (--output-format stream-json)
  # ------------------------------------------------------------------

  defp parse_ndjson(raw) do
    lines = String.split(raw, "\n", trim: true)

    result_line =
      Enum.find_value(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "result"} = msg} -> msg
          _ -> nil
        end
      end)

    case result_line do
      %{"is_error" => true, "result" => content} when is_binary(content) ->
        {:ok, %{status: :error, artifacts: [%{type: :text, content: content}]}}

      %{"subtype" => subtype} when subtype in ["error_max_turns", "error_during_execution", "error_max_budget_usd"] ->
        # Error subtypes may omit the "result" field entirely — extract what we can.
        content = Map.get(result_line, "result", inspect(Map.drop(result_line, ["type"])))
        {:ok, %{status: :error, artifacts: [%{type: :text, content: content}]}}

      %{"result" => content} when is_binary(content) ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: content}]}}

      %{"result" => content} ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: inspect(content)}]}}

      nil ->
        fallback = extract_assistant_text(lines)

        if fallback != "" do
          {:ok, %{status: :success, artifacts: [%{type: :text, content: fallback}]}}
        else
          {:error, {:json_decode, :no_result_line_in_ndjson}}
        end
    end
  end

  defp extract_assistant_text(lines) do
    lines
    |> Enum.reduce([], fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{"type" => "assistant", "message" => %{"content" => content}}}
        when is_list(content) ->
          text_blocks =
            content
            |> Enum.filter(&(Map.get(&1, "type") == "text"))
            |> Enum.map_join("", &Map.get(&1, "text", ""))

          [text_blocks | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end
end
