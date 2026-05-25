# Task 020: E2E Integration

**type:** impl
**depends-on:** ["019"]

## BDD Scenarios

Same as Task 019.

## What to Implement

Wire all components together for end-to-end validation:

1. Ensure `AgentRunner.run/3` correctly dispatches to configured runner
2. Ensure `ArtifactStore.save/3` persists artifacts from runner results
3. Ensure `Orchestrator` correctly handles runner lifecycle (start → run → stop → persist)
4. Ensure error paths work: runner failure → error status → retry logic
5. Ensure config switching between codex/claude works at runtime

No new modules — this task verifies the integration of all prior tasks.

## Files to Modify

- Integration wiring only (minimal changes to connect modules)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/e2e_runner_test.exs
```

All tests green. Full suite:
```bash
cd elixir && mix test
```
