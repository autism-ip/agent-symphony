# Task 016: AgentRunner Refactor Implementation

**type:** impl
**depends-on:** ["008", "015"]

## BDD Scenarios

Same as Task 015.

## What to Implement

Refactor `lib/symphony_elixir/agent_runner.ex`:

1. Replace hardcoded `Codex.AppServer` calls with `Runner.adapter()` dispatch
2. `run/3` flow:
   ```elixir
   runner = Runner.adapter()
   with {:ok, session} <- runner.start_session(issue, workspace, worker_host),
        {:ok, text} <- runner.run_turn(session, prompt, timeout),
        :ok <- runner.stop_session(session),
        {:ok, result} <- runner.parse_result(text) do
     {:ok, result}
   end
   ```
3. Error handling: wrap runner failures, update issue status on error
4. Timeout: use `Config.settings!().runner.claude.turn_timeout_ms` for Claude runner

## Files to Modify

- `lib/symphony_elixir/agent_runner.ex`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/agent_runner_test.exs
```

All tests green.
