defmodule SymphonyElixir.Claude.JsonParserTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.JsonParser

  # ------------------------------------------------------------------
  # Scenario: 解析 --output-format stream-json (NDJSON) 输出
  # ------------------------------------------------------------------
  describe "parse/1 with NDJSON stream-json output" do
    test "extracts result from NDJSON with type=result line" do
      ndjson =
        ~s({"type":"system","info":"starting"}\n) <>
        ~s({"type":"assistant","message":{"content":[{"type":"text","text":"working..."}]}}\n) <>
        ~s({"type":"result","result":"Implemented factorial in src/fact.ex","session_id":"sess_abc","total_cost_usd":0.01}\n)

      assert {:ok, %{status: :success, artifacts: [%{type: :text, content: content}]}} =
               JsonParser.parse(ndjson)

      assert content == "Implemented factorial in src/fact.ex"
    end

    test "extracts error result when is_error is true" do
      ndjson =
        ~s({"type":"result","result":"Rate limit exceeded","is_error":true,"session_id":"sess_err"}\n)

      assert {:ok, %{status: :error, artifacts: [%{type: :text, content: content}]}} =
               JsonParser.parse(ndjson)

      assert content == "Rate limit exceeded"
    end

    test "falls back to assistant text when no result line" do
      ndjson =
        ~s({"type":"assistant","message":{"content":[{"type":"text","text":"partial output"}]}}\n)

      assert {:ok, %{status: :success, artifacts: [%{type: :text, content: content}]}} =
               JsonParser.parse(ndjson)

      assert content == "partial output"
    end
  end

  # ------------------------------------------------------------------
  # Scenario: 解析 --output-format json (single JSON, legacy)
  # ------------------------------------------------------------------
  describe "parse/1 with valid JSON containing result key" do
    test "extracts result text as :success status artifact" do
      json =
        Jason.encode!(%{
          "result" => "Implemented factorial in src/fact.ex",
          "session_id" => "sess_abc",
          "total_cost_usd" => 0.01
        })

      assert {:ok, %{status: :success, artifacts: [%{type: :text, content: content}]}} =
               JsonParser.parse(json)

      assert content == "Implemented factorial in src/fact.ex"
    end

    test "ignores extra fields like session_id and total_cost_usd" do
      json =
        Jason.encode!(%{
          "result" => "Done",
          "session_id" => "sess_xyz",
          "total_cost_usd" => 0.05,
          "unknown_field" => "ignored"
        })

      assert {:ok, %{status: :success, artifacts: artifacts}} = JsonParser.parse(json)
      assert length(artifacts) == 1
      assert hd(artifacts).content == "Done"
    end
  end

  # ------------------------------------------------------------------
  # Scenario: 解析错误类型 JSON
  # ------------------------------------------------------------------
  describe "parse/1 with error JSON" do
    test "extracts error text as :error status artifact" do
      json = Jason.encode!(%{"error" => "Rate limit exceeded"})

      assert {:ok, %{status: :error, artifacts: [%{type: :text, content: content}]}} =
               JsonParser.parse(json)

      assert content == "Rate limit exceeded"
    end
  end

  # ------------------------------------------------------------------
  # Scenario: 输入完全无效
  # ------------------------------------------------------------------
  describe "parse/1 with invalid input" do
    test "returns error tuple with json_decode reason" do
      assert {:error, {:json_decode, _reason}} = JsonParser.parse("not json at all")
    end
  end

  # ------------------------------------------------------------------
  # Edge cases
  # ------------------------------------------------------------------
  describe "parse/1 edge cases" do
    test "empty result string is handled gracefully" do
      json = Jason.encode!(%{"result" => ""})

      assert {:ok, %{status: :success, artifacts: [%{type: :text, content: ""}]}} =
               JsonParser.parse(json)
    end

    test "JSON with only result key and no extra fields" do
      json = Jason.encode!(%{"result" => "minimal"})

      assert {:ok, %{status: :success, artifacts: [%{type: :text, content: "minimal"}]}} =
               JsonParser.parse(json)
    end

    test "JSON with neither result nor error key returns an error" do
      json = Jason.encode!(%{"something" => "unexpected"})

      assert {:error, _reason} = JsonParser.parse(json)
    end

    test "NDJSON with no result line and no assistant text returns error" do
      ndjson = ~s({"type":"system","info":"starting"}\n)

      assert {:error, {:json_decode, :no_result_line_in_ndjson}} = JsonParser.parse(ndjson)
    end
  end
end
