# Task 002: Runner Behaviour Implementation

**type:** impl
**depends-on:** ["001"]

## BDD Scenarios

Same as Task 001 — implement to make those tests pass.

## What to Implement

Verify/update `lib/symphony_elixir/runner.ex`:

1. `@callback start_session(issue(), workspace(), worker_host()) :: {:ok, session()} | {:error, term()}`
2. `@callback run_turn(session(), String.t(), non_neg_integer()) :: {:ok, String.t(), session()} | {:error, term()}`
3. `@callback stop_session(session()) :: :ok | {:error, term()}`
4. `@callback parse_result(String.t()) :: {:ok, result()} | {:error, term()}`
5. `adapter/0` reads `Config.settings()` and dispatches based on `runner.type`

Note: R1 is already implemented. Verify existing code satisfies the 3 BDD scenarios.

## Files to Modify

- `lib/symphony_elixir/runner.ex` (verify, minimal changes if needed)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/runner_test.exs
```

All 3 tests green.
