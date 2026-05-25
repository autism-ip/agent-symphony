# Task 018: Metrics Generalization Implementation

**type:** impl
**depends-on:** ["017"]

## BDD Scenario

Same as Task 017.

## What to Implement

Modify `lib/symphony_elixir/orchestrator.ex`:

1. Rename `codex_totals` → `runner_totals` in State struct
2. Rename `codex_rate_limits` → `runner_rate_limits` in State struct
3. Add backward-compat aliases: `codex_totals` reads from `runner_totals`
4. Update all internal references to use new field names
5. Update telemetry events to use `runner_*` prefix

## Files to Modify

- `lib/symphony_elixir/orchestrator.ex`
- `lib/symphony_elixir/orchestrator/state.ex` (if exists)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/orchestrator_metrics_test.exs
```

All tests green.
