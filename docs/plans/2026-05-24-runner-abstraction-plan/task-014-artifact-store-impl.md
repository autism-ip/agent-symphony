# Task 014: Artifact Persistence Implementation

**type:** impl
**depends-on:** ["012", "013"]

## BDD Scenarios

Same as Task 013.

## What to Implement

Extend `lib/symphony_elixir/artifact_store.ex`:

1. `save(workspace, issue_id, artifacts)` — main entry point
2. For `artifact.type == :file`:
   - Validate path and size (from Task 012)
   - Create directory `workspace/.symphony/artifacts/<dir>/`
   - Write content to file
3. For `artifact.type == :comment`:
   - Call `SymphonyElixir.Tracker.create_comment(issue_id, content)`
4. Return `{:ok, saved_artifacts}` on success

## Files to Modify

- `lib/symphony_elixir/artifact_store.ex` (extend from Task 012)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/artifact_store_test.exs
```

All tests green.
