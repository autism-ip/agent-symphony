# Task 003: Codex.Runner Verification Test

**type:** test
**depends-on:** ["001"]

## BDD Scenarios

### Scenario: 完整生命周期
```gherkin
Given 一个 issue 和 workspace
When 调用 Codex.Runner.start_session
And 调用 run_turn 传入 prompt
And 调用 stop_session
Then session 正常关闭
And 返回结果包含文本内容
```

### Scenario: 与 AppServer 集成
```gherkin
Given Codex.AppServer 已可用
When Codex.Runner.start_session 被调用
Then AppServer.start_session 被以相同参数调用
```

## What to Create

Create test file `test/symphony_elixir/codex/runner_test.exs`:

1. Mock `Codex.AppServer` to verify delegation calls
2. Test full lifecycle: start_session → run_turn → stop_session
3. Verify `parse_result/1` wraps text in `%{status: :success, artifacts: [...]}`

## Files to Create

- `test/symphony_elixir/codex/runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/codex/runner_test.exs
```
