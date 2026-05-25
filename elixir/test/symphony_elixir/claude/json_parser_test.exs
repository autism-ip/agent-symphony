defmodule SymphonyElixir.Claude.JsonParserTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.JsonParser

  # ------------------------------------------------------------------
  # Scenario: 解析 --output-format json 原生输出
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
  # Scenario: JSON 解码失败
  # ------------------------------------------------------------------
  describe "parse/1 with invalid JSON" do
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
  end
end
