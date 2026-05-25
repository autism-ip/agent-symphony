defmodule SymphonyElixir.E2ERunnerTest do
  @moduledoc """
  End-to-end tests for the runner abstraction layer.

  BDD Scenario: Config 驱动的 runner 切换
    Given 配置 runner.type 为 "codex" 或 "claude"
    When 调用 Runner.adapter()
    Then 返回对应的 runner 模块

  BDD Scenario: Claude runner 完整生命周期
    Given runner.type = "claude"
    And 配置 mock cmd_fn
    When 调用 start_session → run_turn → stop_session → parse_result
    Then 返回解析后的 result

  BDD Scenario: 错误恢复
    Given runner.run_turn 返回错误
    When 调用完整生命周期
    Then 错误正确传播

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: false

  alias SymphonyElixir.Runner

  @moduletag :e2e_runner

  setup do
    {_, runner_bin, runner_fn} = :code.get_object_code(Runner)
    {_, config_bin, config_fn} = :code.get_object_code(SymphonyElixir.Config)

    on_exit(fn ->
      :code.purge(Runner)
      :code.load_binary(Runner, runner_fn, runner_bin)
      :code.purge(SymphonyElixir.Config)
      :code.load_binary(SymphonyElixir.Config, config_fn, config_bin)
    end)

    :ok
  end

  # ------------------------------------------------------------------
  # Config-driven runner switching
  # ------------------------------------------------------------------

  describe "Config-driven runner switching" do
    test "Runner.adapter() returns Codex.Runner for codex config" do
      stub_config({:ok, %{runner: %{type: "codex"}}})
      assert Runner.adapter() == SymphonyElixir.Codex.Runner
    end

    test "Runner.adapter() returns Claude.Runner for claude config" do
      stub_config({:ok, %{runner: %{type: "claude"}}})
      assert Runner.adapter() == SymphonyElixir.Claude.Runner
    end

    test "Runner.adapter() defaults to Codex.Runner" do
      stub_config({:ok, %{}})
      assert Runner.adapter() == SymphonyElixir.Codex.Runner
    end
  end

  # ------------------------------------------------------------------
  # Claude runner full lifecycle (mocked cmd_fn)
  # ------------------------------------------------------------------

  describe "Claude runner full lifecycle" do
    test "start_session → run_turn → stop_session → parse_result" do
      issue = %{id: "LIN-E2E", title: "E2E test issue"}
      workspace = "/tmp/e2e-test"
      prompt = "Write a hello world function"

      {:ok, session} = SymphonyElixir.Claude.Runner.start_session(issue, workspace, nil)
      assert session.workspace == workspace
      assert session.issue_id == "LIN-E2E"

      session = Map.put(session, :cmd_fn, fn _cmd, _args, _opts ->
        {~s[{"result":"function hello() { return 'hello world'; }"}], 0}
      end)

      assert {:ok, output, session} = SymphonyElixir.Claude.Runner.run_turn(session, prompt, 30_000)
      assert is_binary(output)
      assert output =~ "hello"

      assert :ok = SymphonyElixir.Claude.Runner.stop_session(session)

      assert {:ok, result} = SymphonyElixir.Claude.Runner.parse_result(output)
      assert result.status == :success
      assert [%{type: :text, content: content}] = result.artifacts
      assert content =~ "hello"
    end

    test "runner error propagates correctly" do
      session = %{
        workspace: "/tmp/ws",
        issue_id: "1",
        issue_title: "t",
        command: "claude",
        max_turns: 10,
        cmd_fn: fn _cmd, _args, _opts -> {"rate limited", 1} end
      }

      assert {:error, {:claude_exit, 1, "rate limited"}} =
               SymphonyElixir.Claude.Runner.run_turn(session, "test", 30_000)
    end

    test "runner timeout propagates correctly" do
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
               SymphonyElixir.Claude.Runner.run_turn(session, "test", 5_000)
    end
  end

  # ------------------------------------------------------------------
  # Codex runner integration
  # ------------------------------------------------------------------

  describe "Codex runner integration" do
    test "parse_result wraps text in success artifact" do
      text = "Implementation complete - factorial function added"

      assert {:ok, result} = SymphonyElixir.Codex.Runner.parse_result(text)
      assert result.status == :success
      assert [%{type: :text, content: ^text}] = result.artifacts
    end
  end

  # ------------------------------------------------------------------
  # Runner behaviour compliance
  # ------------------------------------------------------------------

  describe "Runner behaviour compliance" do
    test "Codex.Runner implements all callbacks" do
      Code.ensure_loaded!(SymphonyElixir.Codex.Runner)
      assert function_exported?(SymphonyElixir.Codex.Runner, :start_session, 3)
      assert function_exported?(SymphonyElixir.Codex.Runner, :run_turn, 3)
      assert function_exported?(SymphonyElixir.Codex.Runner, :stop_session, 1)
      assert function_exported?(SymphonyElixir.Codex.Runner, :parse_result, 1)
    end

    test "Claude.Runner implements all callbacks" do
      Code.ensure_loaded!(SymphonyElixir.Claude.Runner)
      assert function_exported?(SymphonyElixir.Claude.Runner, :start_session, 3)
      assert function_exported?(SymphonyElixir.Claude.Runner, :run_turn, 3)
      assert function_exported?(SymphonyElixir.Claude.Runner, :stop_session, 1)
      assert function_exported?(SymphonyElixir.Claude.Runner, :parse_result, 1)
    end
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp stub_config(result) do
    Process.put(:__e2e_test_mock__, result)
    :code.purge(SymphonyElixir.Config)

    Module.create(
      SymphonyElixir.Config,
      quote do
        def settings, do: Process.get(:__e2e_test_mock__)
      end,
      Macro.Env.location(__ENV__)
    )
  end
end
