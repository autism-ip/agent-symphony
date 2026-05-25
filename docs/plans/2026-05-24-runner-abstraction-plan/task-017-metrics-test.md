# Task 017: Metrics Generalization Test

**type:** test
**depends-on:** []

## BDD Scenario

### Scenario: 指标字段统一命名
```gherkin
Given Orchestrator 处理一个 issue
When 使用 Claude runner
Then 指标存入 runner_totals（非 codex_totals）
And 限流检查使用 runner_rate_limits
```

## What to Create

Create test file `test/symphony_elixir/orchestrator_metrics_test.exs`:

1. Verify `runner_totals` field exists in Orchestrator state
2. Verify `runner_rate_limits` field exists in Orchestrator state
3. Verify `codex_totals` is aliased to `runner_totals` (backward compat)
4. Verify `codex_rate_limits` is aliased to `runner_rate_limits` (backward compat)

## Files to Create

- `test/symphony_elixir/orchestrator_metrics_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/orchestrator_metrics_test.exs
```
