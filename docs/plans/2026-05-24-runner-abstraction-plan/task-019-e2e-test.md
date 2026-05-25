# Task 019: E2E Test

**type:** test
**depends-on:** ["002", "004", "008", "010", "014", "016"]

## BDD Scenarios

### Scenario: Codex 端到端流程
```gherkin
Given 一个 Memory Tracker 的测试 issue
And runner.type = "codex"
When Orchestrator 完整处理该 issue
Then issue 状态变更为完成
And workspace 包含预期产物
```

### Scenario: Claude 端到端流程
```gherkin
Given 一个 Memory Tracker 的测试 issue
And runner.type = "claude"
And 配置 mock claude CLI（返回固定 JSON 输出）
When Orchestrator 完整处理该 issue
Then issue 状态变更为完成
And Linear comment 包含解析后的 artifact
```

## What to Create

Create test file `test/symphony_elixir/e2e_runner_test.exs`:

1. **Codex E2E**: Mock AppServer, run full Orchestrator cycle, verify issue completion
2. **Claude E2E**: Mock System.cmd with fixed JSON output, run full cycle, verify artifacts
3. Verify config-driven runner switching works end-to-end
4. Verify error recovery: runner crash → issue marked as error → retry

## Files to Create

- `test/symphony_elixir/e2e_runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/e2e_runner_test.exs
```
