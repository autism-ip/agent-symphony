defmodule SymphonyElixir.Codex.RunnerTest do
  @moduledoc """
  Tests for Codex.Runner delegation to AppServer.

  BDD Scenario: 完整生命周期
    Given 一个 issue 和 workspace
    When 调用 Codex.Runner.start_session
    And 调用 run_turn 传入 prompt
    And 调用 stop_session
    Then session 正常关闭
    And 返回结果包含文本内容

  BDD Scenario: 与 AppServer 集成
    Given Codex.AppServer 已可用
    When Codex.Runner.start_session 被调用
    Then AppServer.start_session 被以相同参数调用

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: false

  alias SymphonyElixir.Codex.Runner

  # ------------------------------------------------------------------
  # Hot-code load AppServer with a stub to verify delegation.
  # Restored by on_exit in setup.
  # ------------------------------------------------------------------

  setup do
    {_, original_binary, original_filename} =
      :code.get_object_code(SymphonyElixir.Codex.AppServer)

    on_exit(fn ->
      :code.purge(SymphonyElixir.Codex.AppServer)
      :code.load_binary(SymphonyElixir.Codex.AppServer, original_filename, original_binary)
    end)

    :ok
  end

  # ------------------------------------------------------------------
  # parse_result — no external deps, test directly
  # ------------------------------------------------------------------

  describe "parse_result/1" do
    test "wraps text in success result with text artifact" do
      text = "function factorial(n) { return n <= 1 ? 1 : n * factorial(n - 1); }"

      assert {:ok, result} = Runner.parse_result(text)
      assert result.status == :success
      assert [%{type: :text, content: ^text}] = result.artifacts
    end

    test "handles empty text" do
      assert {:ok, result} = Runner.parse_result("")
      assert result.status == :success
      assert [%{type: :text, content: ""}] = result.artifacts
    end
  end

  # ------------------------------------------------------------------
  # start_session — delegates to AppServer.start_session
  # ------------------------------------------------------------------

  describe "start_session/3" do
    test "delegates to AppServer.start_session with workspace and worker_host" do
      issue = %{id: "LIN-123", title: "Fix bug"}
      workspace = "/tmp/test-workspace"
      worker_host = "worker-1"

      stub_app_server(%{
        start_session: fn ^workspace, [worker_host: ^worker_host] ->
          {:ok, %{port: make_ref(), thread_id: "t1", workspace: workspace}}
        end
      })

      assert {:ok, session} = Runner.start_session(issue, workspace, worker_host)
      assert is_map(session)
    end

    test "propagates AppServer errors" do
      stub_app_server(%{
        start_session: fn _workspace, _opts ->
          {:error, :port_start_failed}
        end
      })

      assert {:error, :port_start_failed} =
               Runner.start_session(%{id: "1"}, "/tmp/ws", nil)
    end
  end

  # ------------------------------------------------------------------
  # run_turn — delegates to AppServer.run_turn, adapts result
  # ------------------------------------------------------------------

  describe "run_turn/3" do
    test "delegates to AppServer.run_turn and returns {:ok, text, session}" do
      session = %{port: make_ref(), thread_id: "t1", workspace: "/tmp/ws"}
      prompt = "Implement factorial"

      stub_app_server(%{
        run_turn: fn ^session, ^prompt, [], [timeout: 30_000] ->
          {:ok, %{result: "done", session_id: "s1", thread_id: "t1", turn_id: "tr1"}}
        end
      })

      assert {:ok, text, ^session} = Runner.run_turn(session, prompt, 30_000)
      assert is_binary(text) or is_map(text)
    end

    test "propagates AppServer errors" do
      session = %{port: make_ref(), thread_id: "t1", workspace: "/tmp/ws"}

      stub_app_server(%{
        run_turn: fn _session, _prompt, _issue, _opts ->
          {:error, :timeout}
        end
      })

      assert {:error, :timeout} = Runner.run_turn(session, "test", 5_000)
    end
  end

  # ------------------------------------------------------------------
  # stop_session — delegates to AppServer.stop_session
  # ------------------------------------------------------------------

  describe "stop_session/1" do
    test "delegates to AppServer.stop_session" do
      session = %{port: make_ref(), workspace: "/tmp/ws"}

      stub_app_server(%{
        stop_session: fn ^session -> :ok end
      })

      assert :ok = Runner.stop_session(session)
    end

    test "propagates AppServer errors" do
      session = %{port: make_ref()}

      stub_app_server(%{
        stop_session: fn _session -> {:error, :not_found} end
      })

      assert {:error, :not_found} = Runner.stop_session(session)
    end
  end

  # ------------------------------------------------------------------
  # Hot-swap AppServer module with a stub.
  # Uses process dictionary to capture call args.
  # ------------------------------------------------------------------

  defp stub_app_server(stubs) do
    Process.put(:__codex_runner_test_stubs__, stubs)
    :code.purge(SymphonyElixir.Codex.AppServer)

    Code.compile_string("""
    defmodule SymphonyElixir.Codex.AppServer do
      def start_session(workspace, opts) do
        stubs = Process.get(:__codex_runner_test_stubs__)
        if stubs[:start_session], do: stubs[:start_session].(workspace, opts), else: {:ok, %{}}
      end

      def run_turn(session, prompt, issue, opts) do
        stubs = Process.get(:__codex_runner_test_stubs__)
        if stubs[:run_turn], do: stubs[:run_turn].(session, prompt, issue, opts), else: {:ok, %{}}
      end

      def stop_session(session) do
        stubs = Process.get(:__codex_runner_test_stubs__)
        if stubs[:stop_session], do: stubs[:stop_session].(session), else: :ok
      end
    end
    """)
  end
end
