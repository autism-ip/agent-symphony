# Task 005: Config Schema Test

**type:** test
**depends-on:** []

## BDD Scenarios

### Scenario: 旧配置自动迁移
```gherkin
Given 配置文件包含顶层 codex: {command: "codex"}
And 无 runner 配置
When 加载配置
Then runner.type = "codex"
And runner.codex.command = "codex"
```

### Scenario: 新配置正常解析
```gherkin
Given 配置文件包含 runner: {type: "claude", claude: {command: "claude"}}
When 加载配置
Then runner.type = "claude"
And runner.claude.command = "claude"
```

## What to Create

Create test file `test/symphony_elixir/config/schema_runner_test.exs`:

1. Test backward compat: old config with top-level `codex` → auto-migrates to `runner.type = "codex"`
2. Test new config: `runner: %{type: "claude", claude: %{command: "claude"}}` → parsed correctly
3. Test validation: `runner.type` must be "codex" or "claude"
4. Test ClaudeConfig defaults: `command: "claude"`, `turn_timeout_ms: 300_000`, `stall_timeout_ms: 60_000`, `max_turns: 10`

## Files to Create

- `test/symphony_elixir/config/schema_runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/config/schema_runner_test.exs
```
