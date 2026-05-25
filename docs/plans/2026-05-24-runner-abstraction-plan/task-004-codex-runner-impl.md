# Task 004: Codex.Runner Implementation

**type:** impl
**depends-on:** ["003"]

## BDD Scenarios

Same as Task 003.

## What to Implement

Verify/update `lib/symphony_elixir/codex/runner.ex`:

1. `@behaviour SymphonyElixir.Runner`
2. `start_session/3` delegates to `AppServer.start_session(workspace, worker_host: worker_host)`
3. `run_turn/3` delegates to `AppServer.run_turn(session, prompt, [], timeout: timeout_ms)`
4. `stop_session/1` delegates to `AppServer.stop_session(session)`
5. `parse_result/1` returns `{:ok, %{status: :success, artifacts: [%{type: :text, content: text}]}}`

Note: R2 is already implemented. Verify existing code satisfies the 2 BDD scenarios.

## Files to Modify

- `lib/symphony_elixir/codex/runner.ex` (verify, minimal changes if needed)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/codex/runner_test.exs
```

All tests green.
