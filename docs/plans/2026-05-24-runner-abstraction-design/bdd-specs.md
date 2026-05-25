# BDD Specifications — Runner Abstraction

## Feature: Runner Behaviour

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

---

## Feature: Codex.Runner

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

---

## Feature: Claude.Runner

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

### Scenario: 解析 --output-format json 原生输出
```gherkin
Given Claude CLI 输出为
  """
  {"result":"Implemented factorial in src/fact.ex","session_id":"sess_abc","total_cost_usd":0.01}
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :success, artifacts: [%{type: :text, content: "Implemented factorial in src/fact.ex"}]}}
```

### Scenario: 解析错误类型 JSON
```gherkin
Given Claude CLI 输出为
  """
  {"error":"Rate limit exceeded"}
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :error, artifacts: [%{type: :text, content: "Rate limit exceeded"}]}}
```

### Scenario: JSON 解码失败
```gherkin
Given Claude CLI 输出为无效 JSON "not json at all"
When 调用 Claude.Runner.parse_result
Then 返回 {:error, {:json_decode, <jason_reason>}}
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

---

## Feature: Security

### Scenario: 阻止命令注入
```gherkin
Given 配置 claude.command 包含 shell 元字符（如 ";", "|", "&"）
When 加载配置
Then Config.Schema 验证失败
And 返回 {:error, :invalid_command}
```

### Scenario: 阻止路径遍历写入 artifact
```gherkin
Given 解析结果包含 artifact.path = "../../../etc/passwd"
When 调用 ArtifactStore.save
Then 返回 {:error, {:invalid_artifact_path, "../../../etc/passwd"}}
And 不写入任何文件
```

### Scenario: 阻止写入可执行文件
```gherkin
Given 解析结果包含 artifact.path = "script.sh"
When 调用 ArtifactStore.save
Then 返回 {:error, {:forbidden_file_type, ".sh"}}
```

### Scenario: Artifact 内容大小限制
```gherkin
Given 解析结果包含 artifact.content 大小超过 1MB
When 调用 ArtifactStore.save
Then 返回 {:error, {:artifact_too_large, 1_048_576}}
```

---

## Feature: Performance

### Scenario: 大输出受 timeout 保护
```gherkin
Given Claude 单次输出超过 10MB
When run_turn 执行
Then System.cmd 通过 timeout_ms 限制执行时间
And 子进程超时后被自动终止
```

---

## Feature: Artifact Persistence

### Scenario: 文件类型 artifact 写入 workspace
```gherkin
Given 解析结果包含 artifact.type = :file, path = "src/main.ex", content = "defmodule..."
And workspace = "/tmp/symphony/ISSUE-123"
When 调用 ArtifactStore.save
Then 文件写入 "/tmp/symphony/ISSUE-123/.symphony/artifacts/src/main.ex"
```

### Scenario: Comment 类型 artifact 上传 Linear
```gherkin
Given 解析结果包含 artifact.type = :comment, content = "Summary of changes"
And issue.id = "abc-123"
When 调用 ArtifactStore.save
Then Tracker.create_comment("abc-123", "Summary of changes") 被调用
```

---

## Feature: Config Schema

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

---

## Feature: Orchestrator 泛化指标

### Scenario: 指标字段统一命名
```gherkin
Given Orchestrator 处理一个 issue
When 使用 Claude runner
Then 指标存入 runner_totals（非 codex_totals）
And 限流检查使用 runner_rate_limits
```

---

## Feature: E2E — 端到端测试

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

---

## Testing Strategy

### Unit Tests
- `Runner` behaviour 契约验证（使用 Mox 或手工 mock）
- `Codex.Runner` 各 callback 的独立测试
- `Claude.Runner` 各 callback 的独立测试
- `Claude.JsonParser` 边界条件全覆盖
- `Config.Schema` 新旧配置解析
- `ArtifactStore` 路径校验与内容限制

### Integration Tests
- `AgentRunner.run/3` 与 `Codex.Runner` 集成
- `AgentRunner.run/3` 与 `Claude.Runner` 集成
- `ArtifactStore` 与 `Tracker` 集成
- `Claude.Runner` 命令转义与注入防护
- `Claude.Runner` 超时与 stall 检测

### E2E Tests
- 完整 Orchestrator 流程（Memory Tracker + mock runner）
- 配置文件驱动的 runner 切换
- Claude runner 端到端（命令注入 + 大输出 + 崩溃恢复）

### Test Isolation
- 每个测试使用独立 workspace 目录
- System.cmd 子进程在 timeout 后自动终止
- 环境变量在测试前后恢复
- 安全测试使用 chroot 或临时目录隔离
