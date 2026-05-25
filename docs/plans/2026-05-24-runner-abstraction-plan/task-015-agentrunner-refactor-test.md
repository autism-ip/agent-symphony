# Task 015: AgentRunner Refactor Test

**type:** test
**depends-on:** ["001", "003", "007"]

## BDD Scenario (Integration)

### Scenario: AgentRunner 使用 Runner.adapter() 动态派发
```gherkin
Given 配置 runner.type = "claude"
And Claude.Runner 已实现
When 调用 AgentRunner.run(issue, workspace, worker_host)
Then 内部调用 Claude.Runner.start_session
And 内部调用 Claude.Runner.run_turn
And 内部调用 Claude.Runner.stop_session
And 内部调用 Claude.Runner.parse_result
And 返回解析后的 result
```

### Scenario: AgentRunner 错误处理
```gherkin
Given 配置 runner.type = "claude"
And Claude.run_turn 返回 {:error, {:claude_exit, 1, "output"}}
When 调用 AgentRunner.run
Then 返回 {:error, reason}
And issue 状态更新为错误状态
```

## What to Create

Create test file `test/symphony_elixir/agent_runner_test.exs`:

1. Mock `Runner.adapter()` to return a test double
2. Verify full lifecycle: start → run_turn → stop → parse_result
3. Verify error path: runner failure triggers error handling
4. Verify timeout path: runner timeout triggers appropriate response

## Files to Create

- `test/symphony_elixir/agent_runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/agent_runner_test.exs
```
