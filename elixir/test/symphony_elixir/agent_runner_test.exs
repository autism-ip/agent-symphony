defmodule SymphonyElixir.AgentRunnerTest do
  @moduledoc """
  Tests for AgentRunner dynamic dispatch via Runner.adapter().

  BDD Scenario: AgentRunner 使用 Runner.adapter() 动态派发
    Given 配置 runner.type = "claude"
    And Claude.Runner 已实现
    When 调用 AgentRunner.run(issue, workspace, worker_host)
    Then 内部调用 Runner.adapter() 获取 runner
    And 内部调用 runner.start_session
    And 内部调用 runner.run_turn
    And 内部调用 runner.stop_session

  BDD Scenario: AgentRunner 错误处理
    Given 配置 runner.type = "claude"
    And runner.run_turn 返回 {:error, {:claude_exit, 1, "output"}}
    When 调用 AgentRunner.run
    Then 错误通过 raise 传播

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentRunner

  @moduletag :agent_runner_refactor

  # ------------------------------------------------------------------
  # Code inspection: verify AgentRunner uses Runner.adapter()
  # instead of hardcoding Codex.AppServer
  # ------------------------------------------------------------------

  describe "AgentRunner source code uses Runner.adapter()" do
    test "AgentRunner does not alias or call Codex.AppServer" do
      source = File.read!("lib/symphony_elixir/agent_runner.ex")
      refute source =~ "alias SymphonyElixir.Codex.AppServer",
        "AgentRunner should not alias Codex.AppServer after refactor"
      refute source =~ "AppServer.start_session",
        "AgentRunner should not call AppServer.start_session directly"
      refute source =~ "AppServer.run_turn",
        "AgentRunner should not call AppServer.run_turn directly"
      refute source =~ "AppServer.stop_session",
        "AgentRunner should not call AppServer.stop_session directly"
    end

    test "AgentRunner aliases and uses Runner.adapter()" do
      source = File.read!("lib/symphony_elixir/agent_runner.ex")
      assert source =~ "Runner",
        "AgentRunner should reference Runner module"
      assert source =~ "Runner.adapter()",
        "AgentRunner should call Runner.adapter() for dynamic dispatch"
    end

    test "AgentRunner calls runner.start_session with issue, workspace, worker_host" do
      source = File.read!("lib/symphony_elixir/agent_runner.ex")
      assert source =~ "runner.start_session(issue",
        "AgentRunner should call runner.start_session(issue, ...)"
    end

    test "AgentRunner calls runner.run_turn with session, prompt, timeout_ms" do
      source = File.read!("lib/symphony_elixir/agent_runner.ex")
      assert source =~ "runner.run_turn(session",
        "AgentRunner should call runner.run_turn(session, ...)"
    end

    test "AgentRunner calls runner.stop_session in after block" do
      source = File.read!("lib/symphony_elixir/agent_runner.ex")
      assert source =~ "runner.stop_session(session)",
        "AgentRunner should call runner.stop_session(session) in after block"
    end
  end

  # ------------------------------------------------------------------
  # Verify AgentRunner compiles without errors
  # ------------------------------------------------------------------

  describe "AgentRunner compilation" do
    test "module compiles successfully" do
      assert {:module, AgentRunner} = :code.ensure_loaded(AgentRunner)
    end

    test "run/3 function is exported" do
      assert function_exported?(SymphonyElixir.AgentRunner, :run, 3)
    end
  end
end
