# Task 008: Claude.Runner Implementation

**type:** impl
**depends-on:** ["006", "007"]

## BDD Scenarios

Same as Task 007.

## What to Implement

Create `lib/symphony_elixir/claude/runner.ex`:

1. `@behaviour SymphonyElixir.Runner`
2. `start_session/3`:
   - Read `Config.settings!().runner.claude` for command config
   - Return `{:ok, %{workspace: workspace, issue_id: issue.id, issue_title: issue.title, command: settings.command}}`
   - No process spawning
3. `run_turn/3`:
   - Build args: `["-p", prompt, "--output-format", "json", "--max-turns", to_string(settings.max_turns)]`
   - Call `System.cmd(session.command, args, cd: session.workspace, stderr_to_stdout: true, timeout: timeout_ms)`
   - `{output, 0}` → `{:ok, output, session}`
   - `{output, exit_code}` → `{:error, {:claude_exit, exit_code, output}}`
   - Catch timeout → `{:error, {:runner_timeout, :turn, timeout_ms}}`
4. `stop_session/1`: returns `:ok`
5. `parse_result/1`: delegates to `Claude.JsonParser.parse/1`

## Files to Create

- `lib/symphony_elixir/claude/runner.ex`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/claude/runner_test.exs
```

All tests green.
