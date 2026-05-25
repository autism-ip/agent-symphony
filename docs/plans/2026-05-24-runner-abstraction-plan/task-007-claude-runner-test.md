# Task 007: Claude.Runner Test

**type:** test
**depends-on:** ["001", "005"]

## BDD Scenarios

### Scenario: 初始化 Claude session
```gherkin
Given 配置 runner.claude.command = "claude"
And 一个 issue 和 workspace
When 调用 Claude.Runner.start_session
Then 返回 {:ok, session} 其中 session 包含 workspace, issue_id, issue_title
And 不启动任何外部进程
```

### Scenario: 通过 System.cmd 执行 turn
```gherkin
Given 一个 Claude session
When 调用 run_turn 传入 "Implement factorial function"
Then 通过 System.cmd 启动 claude 子进程，参数包含 "-p", prompt, "--output-format", "json"
And 工作目录为 session.workspace
And 返回 {:ok, json_output, session}
```

### Scenario: CLI 进程非零退出
```gherkin
Given 一个 Claude session
When CLI 进程以退出码 1 退出
Then run_turn 返回 {:error, {:claude_exit, 1, <output>}}
```

### Scenario: Turn 超时
```gherkin
Given 一个 Claude session
And turn_timeout_ms = 300_000
When System.cmd 执行超过 timeout_ms
Then 返回 {:error, {:runner_timeout, :turn, timeout_ms}}
And 子进程被自动终止
```

### Scenario: stop_session 为 no-op
```gherkin
Given 一个 Claude session
When 调用 stop_session
Then 返回 :ok
And 无需关闭任何进程（per-turn 模式无长连接）
```

## What to Create

Create test file `test/symphony_elixir/claude/runner_test.exs`:

1. Test `start_session/3` returns `{:ok, session}` with correct fields, no process spawned
2. Test `run_turn/3` calls `System.cmd` with correct args (`-p`, `--output-format json`, `--max-turns N`)
3. Test `run_turn/3` sets `cd: session.workspace` and `timeout: timeout_ms`
4. Test non-zero exit → `{:error, {:claude_exit, exit_code, output}}`
5. Test timeout → `{:error, {:runner_timeout, :turn, timeout_ms}}`
6. Test `stop_session/1` returns `:ok`

Use `Mox` to mock `System.cmd` for deterministic testing.

## Files to Create

- `test/symphony_elixir/claude/runner_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/claude/runner_test.exs
```
