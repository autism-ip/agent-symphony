defmodule SymphonyElixir.RunnerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SymphonyElixir.Runner

  # ------------------------------------------------------------------
  # Config.Schema has no `runner` field, so the "codex"/"claude" branches
  # in Runner.adapter/0 can never fire through the real config pipeline.
  # We stub Config.settings/0 via BEAM hot-code loading to exercise each
  # pattern-match branch in isolation.
  # ------------------------------------------------------------------

  setup do
    {_, original_binary, original_filename} =
      :code.get_object_code(SymphonyElixir.Config)

    on_exit(fn ->
      :code.purge(SymphonyElixir.Config)
      :code.load_binary(SymphonyElixir.Config, original_filename, original_binary)
    end)
  end

  describe "adapter/0" do
    test "returns Codex.Runner when runner.type is \"codex\"" do
      stub_config({:ok, %{runner: %{type: "codex"}}})
      assert Runner.adapter() == SymphonyElixir.Codex.Runner
    end

    test "returns Claude.Runner when runner.type is \"claude\"" do
      stub_config({:ok, %{runner: %{type: "claude"}}})
      assert Runner.adapter() == SymphonyElixir.Claude.Runner
    end

    test "returns Codex.Runner as default when runner.type is not set" do
      stub_config({:ok, %{}})
      assert Runner.adapter() == SymphonyElixir.Codex.Runner
    end
  end

  # ------------------------------------------------------------------
  # Hot-swap Config module so settings/0 reads from the process
  # dictionary.  Restored by on_exit in setup above.
  # ------------------------------------------------------------------

  defp stub_config(result) do
    Process.put(:__runner_test_mock__, result)
    :code.purge(SymphonyElixir.Config)

    Code.compile_string("""
    defmodule SymphonyElixir.Config do
      def settings, do: Process.get(:__runner_test_mock__)
    end
    """)
  end
end
