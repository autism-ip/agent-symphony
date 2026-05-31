defmodule SymphonyElixir.Claude.RunnerTest do
  @moduledoc """
  Tests for Claude.Runner (per-turn process model).

  BDD Scenario: 初始化 Claude session
    Given 配置 runner.claude.command = "claude"
    And 一个 issue 和 workspace
    When 调用 Claude.Runner.start_session
    Then 返回 {:ok, session} 其中 session 包含 workspace, issue_id, issue_title, session_id: nil
    And 不启动任何外部进程

  BDD Scenario: 通过 System.cmd 执行 turn (NDJSON mode)
    Given 一个 Claude session
    When 调用 run_turn 传入 prompt
    Then 通过 /bin/sh 启动 claude 子进程，参数包含 --dangerously-skip-permissions, --output-format stream-json
    And stdin 被重定向到 /dev/null，用户级 hooks 被禁用
    And 工作目录为 session.workspace
    And 返回 {:ok, output, session} 其中 session.session_id 被提取

  BDD Scenario: 后续 turn 使用 --resume 恢复上下文
    Given 一个 session 带有 session_id
    When 调用 run_turn
    Then 参数包含 --resume <session_id>

  BDD Scenario: CLI 进程非零退出
    Given 一个 Claude session
    When CLI 进程以退出码 1 退出
    Then run_turn 返回 {:error, {:claude_exit, 1, <output>}}

  BDD Scenario: Turn 超时
    Given 一个 Claude session
    When System.cmd 执行超过 timeout_ms
    Then 返回 {:error, {:runner_timeout, :turn, timeout_ms}}
    And 子进程被自动终止

  BDD Scenario: stop_session 为 no-op
    Given 一个 Claude session
    When 调用 stop_session
    Then 返回 :ok

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: false

  alias SymphonyElixir.Claude.Runner

  @moduletag :claude_runner

  # ------------------------------------------------------------------
  # start_session — pure data, no process spawning
  # ------------------------------------------------------------------

  describe "start_session/3" do
    test "returns {:ok, session} with workspace, issue fields, and session_id nil" do
      issue = %{id: "LIN-456", title: "Add logging"}
      workspace = "/tmp/claude-test-ws"
      worker_host = "worker-2"

      assert {:ok, session} = Runner.start_session(issue, workspace, worker_host)
      assert is_map(session)
      assert session.workspace == workspace
      assert session.issue_id == "LIN-456"
      assert session.issue_title == "Add logging"
      assert session.command == "claude"
      assert session.session_id == nil
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
    test "calls cmd_fn with --dangerously-skip-permissions and --output-format stream-json" do
      prompt = "Implement factorial function"
      timeout_ms = 300_000
      ndjson_output = "{\"type\":\"result\",\"result\":\"ok\",\"session_id\":\"sess_abc\",\"total_cost_usd\":0.01}\n"

      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        session_id: nil,
        cmd_fn: fn command, args, opts ->
          assert command == "/bin/sh"
          assert ["-c", "exec \"$0\" \"$@\" </dev/null", "claude" | claude_args] = args
          assert "-p" in claude_args
          assert prompt in claude_args
          assert "--dangerously-skip-permissions" in claude_args
          assert "--verbose" in claude_args
          assert "--output-format" in claude_args
          assert "stream-json" in claude_args
          assert "--settings" in claude_args
          assert %{"disableAllHooks" => true} = decode_settings_arg(claude_args)
          refute "--max-turns" in claude_args
          refute "--resume" in claude_args
          assert Keyword.get(opts, :cd) == "/tmp/ws"
          assert {"CLAUDECODE", nil} in Keyword.fetch!(opts, :env)
          assert {"CLAUDE_CODE_ENTRYPOINT", nil} in Keyword.fetch!(opts, :env)
          assert {"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"} in Keyword.fetch!(opts, :env)

          {ndjson_output, 0}
        end
      }

      assert {:ok, output, updated_session} = Runner.run_turn(session, prompt, timeout_ms)
      assert is_binary(output)
      assert updated_session.session_id == "sess_abc"
    end

    test "passes --resume on subsequent turns when session_id is present" do
      ndjson_output = "{\"type\":\"result\",\"result\":\"continued\",\"session_id\":\"sess_abc\",\"total_cost_usd\":0.02}\n"

      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        session_id: "sess_abc",
        cmd_fn: fn _command, args, _opts ->
          assert ["-c", "exec \"$0\" \"$@\" </dev/null", "claude" | claude_args] = args
          assert "--resume" in claude_args
          assert "sess_abc" in claude_args

          {ndjson_output, 0}
        end
      }

      assert {:ok, _output, updated_session} = Runner.run_turn(session, "continue", 30_000)
      assert updated_session.session_id == "sess_abc"
    end

    test "returns {:error, {:claude_exit, exit_code, output}} on non-zero exit" do
      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        session_id: nil,
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
        session_id: nil,
        cmd_fn: fn _cmd, _args, _opts ->
          Process.sleep(:infinity)
        end
      }

      assert {:error, {:runner_timeout, :turn, 100}} =
               Runner.run_turn(session, "test", 100)
    end

    test "session_id remains nil when output has no result line" do
      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        session_id: nil,
        cmd_fn: fn _cmd, _args, _opts ->
          {"{\"type\":\"system\",\"info\":\"starting\"}\n", 0}
        end
      }

      assert {:ok, _output, updated_session} = Runner.run_turn(session, "test", 30_000)
      assert updated_session.session_id == nil
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
    test "parses valid Claude NDJSON output" do
      ndjson = "{\"type\":\"result\",\"result\":\"function factorial(n) { return n; }\",\"session_id\":\"sess_xyz\"}\n"
      assert {:ok, result} = Runner.parse_result(ndjson)
      assert result.status == :success
      assert [%{type: :text, content: content}] = result.artifacts
      assert content =~ "factorial"
    end

    test "parses legacy single-JSON output" do
      json = "{\"result\":\"function factorial(n) { return n; }\"}"
      assert {:ok, result} = Runner.parse_result(json)
      assert result.status == :success
      assert [%{type: :text, content: content}] = result.artifacts
      assert content =~ "factorial"
    end

    test "returns error for invalid input" do
      assert {:error, {:json_decode, _}} = Runner.parse_result("not json")
    end
  end

  defp decode_settings_arg(args) do
    index = Enum.find_index(args, &(&1 == "--settings"))
    assert is_integer(index)
    args |> Enum.at(index + 1) |> Jason.decode!()
  end
end
