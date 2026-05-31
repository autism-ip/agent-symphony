defmodule SymphonyElixir.OrchestratorMetricsTest do
  @moduledoc """
  Tests for metrics field naming generalization.

  BDD Scenario: 指标字段统一命名
    Given Orchestrator 处理一个 issue
    When 使用 Claude runner
    Then 指标存入 runner_totals（非 codex_totals）
    And 限流检查使用 runner_rate_limits

  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use SymphonyElixir.TestSupport

  # -----------------------------------------------------------------------
  #  runner_totals — generalized naming (PASS after rename)
  # -----------------------------------------------------------------------

  describe "runner_totals" do
    test "State struct has runner_totals field" do
      state = struct!(Orchestrator.State, %{})
      assert Map.has_key?(state, :runner_totals)
    end

    test "State defaults runner_totals to nil" do
      state = struct!(Orchestrator.State, %{})
      assert state.runner_totals == nil
    end

    test "runner_totals accepts a map with token counters" do
      totals = %{
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        seconds_running: 30
      }

      state = struct!(Orchestrator.State, %{runner_totals: totals})
      assert state.runner_totals == totals
    end
  end

  # -----------------------------------------------------------------------
  #  runner_rate_limits — generalized naming (PASS after rename)
  # -----------------------------------------------------------------------

  describe "runner_rate_limits" do
    test "State struct has runner_rate_limits field" do
      state = struct!(Orchestrator.State, %{})
      assert Map.has_key?(state, :runner_rate_limits)
    end

    test "State defaults runner_rate_limits to nil" do
      state = struct!(Orchestrator.State, %{})
      assert state.runner_rate_limits == nil
    end

    test "runner_rate_limits accepts a map with rate limit info" do
      limits = %{requests_remaining: 42, resets_at: ~U[2026-01-01T00:00:00Z]}
      state = struct!(Orchestrator.State, %{runner_rate_limits: limits})
      assert state.runner_rate_limits == limits
    end
  end

  # -----------------------------------------------------------------------
  #  Backward compatibility: codex_* accessor functions
  # -----------------------------------------------------------------------

  describe "backward compatibility accessor functions" do
    test "State.codex_totals/1 reads from runner_totals" do
      totals = %{
        input_tokens: 500,
        output_tokens: 250,
        total_tokens: 750,
        seconds_running: 120
      }

      state = struct!(Orchestrator.State, %{runner_totals: totals})

      assert Orchestrator.State.codex_totals(state) == totals,
             "Expected codex_totals/1 accessor to read from runner_totals"
    end

    test "State.codex_rate_limits/1 reads from runner_rate_limits" do
      limits = %{requests_remaining: 7, resets_at: ~U[2026-06-01T00:00:00Z]}

      state = struct!(Orchestrator.State, %{runner_rate_limits: limits})

      assert Orchestrator.State.codex_rate_limits(state) == limits,
             "Expected codex_rate_limits/1 accessor to read from runner_rate_limits"
    end
  end
end
