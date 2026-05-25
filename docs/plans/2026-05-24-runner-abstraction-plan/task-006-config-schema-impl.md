# Task 006: Config Schema Implementation

**type:** impl
**depends-on:** ["005"]

## BDD Scenarios

Same as Task 005.

## What to Implement

Modify `lib/symphony_elixir/config/schema.ex`:

1. Add `Runner` embedded schema with `field :type, :string, default: "codex"`
2. Add `ClaudeConfig` embedded schema:
   - `field :command, :string, default: "claude"`
   - `field :turn_timeout_ms, :integer, default: 300_000`
   - `field :stall_timeout_ms, :integer, default: 60_000`
   - `field :max_turns, :integer, default: 10`
3. Add `embeds_one :runner, Runner` to top-level schema
4. Add `migrate_runner/1` for backward compat: when `runner` is nil but `codex` exists → `runner: %{type: "codex"}`
5. Validate `runner.type` ∈ {"codex", "claude"}
6. Validate `runner.claude.command` has no shell metacharacters

## Files to Modify

- `lib/symphony_elixir/config/schema.ex`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/config/schema_runner_test.exs
```

All tests green.
