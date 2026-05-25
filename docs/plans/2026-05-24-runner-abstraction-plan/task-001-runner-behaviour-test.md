# Task 001: Runner Behaviour Test

**type:** test
**depends-on:** []

## BDD Scenarios

### Scenario: 动态选择 Codex runner
```gherkin
Given 配置 runner.type = "codex"
When 调用 Runner.adapter()
Then 返回 SymphonyElixir.Codex.Runner
```

### Scenario: 动态选择 Claude runner
```gherkin
Given 配置 runner.type = "claude"
When 调用 Runner.adapter()
Then 返回 SymphonyElixir.Claude.Runner
```

### Scenario: 默认 runner 回退
```gherkin
Given 配置 runner.type 未设置
When 调用 Runner.adapter()
Then 返回 SymphonyElixir.Codex.Runner
And 触发向后兼容警告日志
```

## What to Implement

Create test file `test/symphony_elixir/runner_test.exs` with 3 test cases covering `Runner.adapter/0` dispatch:

1. Mock config with `runner.type = "codex"` → assert returns `SymphonyElixir.Codex.Runner`
2. Mock config with `runner.type = "claude"` → assert returns `SymphonyElixir.Claude.Runner`
3. Mock config with no runner section → assert returns `SymphonyElixir.Codex.Runner` (backward compat)

## Files to Create

- `test/symphony_elixir/runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/runner_test.exs
```

All 3 tests must fail initially (modules may not exist yet) or pass if `Runner.adapter/0` is already implemented.
