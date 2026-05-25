# Task 010: Claude JSON Parser Implementation

**type:** impl
**depends-on:** ["009"]

## BDD Scenarios

Same as Task 009.

## What to Implement

Create `lib/symphony_elixir/claude/json_parser.ex`:

1. `parse(json_text)` function:
   - `Jason.decode(json_text)` → pattern match on result
   - `%{"result" => text}` → `{:ok, %{status: :success, artifacts: [%{type: :text, content: text}]}}`
   - `%{"error" => msg}` → `{:ok, %{status: :error, artifacts: [%{type: :text, content: msg}]}}`
   - `{:error, reason}` → `{:error, {:json_decode, reason}}`

## Files to Create

- `lib/symphony_elixir/claude/json_parser.ex`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/claude/json_parser_test.exs
```

All tests green.
