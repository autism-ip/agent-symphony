defmodule SymphonyElixir.Claude.RunnerTest do
  @moduledoc """
  Tests for Claude.Runner (per-turn process model).

  BDD Scenario: 初始化 Claude session
    Given 配置 runner.claude.command = "claude"
    And 一个 issue 和 workspace
    When 调用 Claude.Runner.start_session
    Then 返回 {:ok, session} 其中 session 包含 workspace, issue_id, issue_title
    And 不启动任何外部进程

  BDD Scenario: 通过 System.cmd 执行 turn
    Given 一个 Claude session
    When 调用 run_turn 传入 "Implement factorial function"
    Then 通过 System.cmd 启动 claude 子进程，参数包含 "-p", prompt, "--output-format", "json"
    And 工作目录为 session.workspace
    And 返回 {:ok, json_output, session}

  BDD Scenario: CLI 进程非零退出
    Given 一个 Claude session
    When CLI 进程以退出码 1 退出
    Then run_turn 返回 {:error, {:claude_exit, 1, <output>}}

  BDD Scenario: Turn 超时
    Given 一个 Claude session
    And turn_timeout_ms = 300_000
    When System.cmd 执行超过 timeout_ms
    Then 返回 {:error, {:runner_timeout, :turn, timeout_ms}}
    And 子进程被自动终止

  BDD Scenario: stop_session 为 no-op
    Given 一个 Claude session
    When 调用 stop_session
    Then 返回 :ok
    And 无需关闭任何进程（per-turn 模式无长连接）

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: false

  alias SymphonyElixir.Claude.Runner

  @moduletag :claude_runner

  # ------------------------------------------------------------------
  # start_session — pure data, no process spawning
  # ------------------------------------------------------------------

  describe "start_session/3" do
    test "returns {:ok, session} with workspace and issue fields" do
      issue = %{id: "LIN-456", title: "Add logging"}
      workspace = "/tmp/claude-test-ws"
      worker_host = "worker-2"

      assert {:ok, session} = Runner.start_session(issue, workspace, worker_host)
      assert is_map(session)
      assert session.workspace == workspace
      assert session.issue_id == "LIN-456"
      assert session.issue_title == "Add logging"
      assert session.command == "claude"
    end

    test "does not spawn any external process" do
      before_count = length(Process.list())

      {:ok, _session} =
        Runner.start_session(%{id: "1", title: "t"}, "/tmp/ws", nil)

      after_count = length(Process.list())
      assert after_count - before_count <= 1
    end
  end

  # ------------------------------------------------------------------
  # run_turn — uses cmd_fn from session for testability
  # ------------------------------------------------------------------

  describe "run_turn/3" do
    test "calls cmd_fn with -p, --output-format json, --max-turns" do
      prompt = "Implement factorial function"
      timeout_ms = 300_000

      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        max_turns: 10,
        cmd_fn: fn command, args, opts ->
          assert command == "claude"
          assert "-p" in args
          assert prompt in args
          assert "--output-format" in args
          assert "json" in args
          assert "--max-turns" in args
          assert Keyword.get(opts, :cd) == "/tmp/ws"
          assert Keyword.get(opts, :timeout) == timeout_ms

          {~s({"result":"ok"}), 0}
        end
      }

      assert {:ok, output, ^session} = Runner.run_turn(session, prompt, timeout_ms)
      assert is_binary(output)
    end

    test "returns {:error, {:claude_exit, exit_code, output}} on non-zero exit" do
      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        max_turns: 10,
        cmd_fn: fn _cmd, _args, _opts -> {"Error: rate limited", 1} end
      }

      assert {:error, {:claude_exit, 1, "Error: rate limited"}} =
               Runner.run_turn(session, "test", 30_000)
    end

    test "returns {:error, {:runner_timeout, :turn, timeout_ms}} on timeout" do
      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        max_turns: 10,
        cmd_fn: fn _cmd, _args, _opts ->
          raise %ErlangError{original: :timeout}
        end
      }

      assert {:error, {:runner_timeout, :turn, 5_000}} =
               Runner.run_turn(session, "test", 5_000)
    end
  end

  # ------------------------------------------------------------------
  # stop_session — no-op for per-turn model
  # ------------------------------------------------------------------

  describe "stop_session/1" do
    test "returns :ok (no-op for per-turn model)" do
      session = %{workspace: "/tmp/ws", issue_id: "1", issue_title: "t"}
      assert :ok = Runner.stop_session(session)
    end
  end

  # ------------------------------------------------------------------
  # parse_result — delegates to JsonParser
  # ------------------------------------------------------------------

  describe "parse_result/1" do
    test "parses valid Claude JSON output" do
      json = "{\"result\":\"function factorial(n) { return n; }\"}"
      assert {:ok, result} = Runner.parse_result(json)
      assert result.status == :success
      assert [%{type: :text, content: content}] = result.artifacts
      assert content =~ "factorial"
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode, _}} = Runner.parse_result("not json")
    end
  end
end
