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

### Scenario: 启动 Claude CLI session
```gherkin
Given 配置 claude.command = "claude --verbose"
And 一个 issue 和 workspace
When 调用 Claude.Runner.start_session
Then 通过 Port.open 启动 claude 进程
And 进程工作目录为 workspace
And 环境变量包含 SYMPHONY_ISSUE_ID
```

### Scenario: 发送 prompt 并收集输出
```gherkin
Given 一个活跃的 Claude session
When 调用 run_turn 传入 "Implement factorial function"
Then 向 Port 发送格式化的 prompt
And 收集 stdout 直到超时或检测到结束标记
And 返回完整的输出文本
```

### Scenario: 解析结构化 JSON 结果
```gherkin
Given Claude 输出包含
  """
  ###SYMPHONY_JSON_START###
  {"status":"success","artifacts":[{"type":"file","path":"src/fact.clj","content":"(defn fact ..."}]}
  ###SYMPHONY_JSON_END###
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :success, artifacts: [...]}}
```

### Scenario: 无 JSON 标记时回退到纯文本
```gherkin
Given Claude 输出为纯文本 "No changes needed"
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :success, artifacts: [%{type: :text, content: "No changes needed"}]}}
```

### Scenario: JSON 解析失败降级
```gherkin
Given Claude 输出包含无效 JSON
  """
  ###SYMPHONY_JSON_START###
  {invalid json here
  ###SYMPHONY_JSON_END###
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :success, artifacts: [%{type: :text, content: <完整原始文本>}]}}
And 记录 warning 日志
```

### Scenario: CLI 进程崩溃
```gherkin
Given 一个活跃的 Claude session
When CLI 进程意外退出
Then runner 检测 Port 状态
And 返回 {:error, {:runner_crashed, <exit_status>}}
```

### Scenario: Turn 超时
```gherkin
Given 一个活跃的 Claude session
And turn_timeout_ms = 300_000
When run_turn 执行超过 turn_timeout_ms 无结果
Then 返回 {:error, {:runner_timeout, :turn, 300_000}}
And 记录 error 日志
```

### Scenario: Stall 超时
```gherkin
Given 一个活跃的 Claude session
And stall_timeout_ms = 60_000
When CLI 超过 stall_timeout_ms 无 stdout 输出
Then 返回 {:error, {:runner_timeout, :stall, 60_000}}
And 强制关闭 Port
```

### Scenario: Runner 启动失败
```gherkin
Given 配置 claude.command = "nonexistent_binary"
When 调用 Claude.Runner.start_session
Then 返回 {:error, {:runner_start_failed, "nonexistent_binary", 127}}
```

---

## Feature: Security

### Scenario: 阻止命令注入
```gherkin
Given 配置 claude.command = "claude; rm -rf /"
When 调用 Claude.Runner.start_session
Then 命令被转义为 "'claude; rm -rf /'"
And 不会执行 rm 命令
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

### Scenario: 大输出缓冲不 OOM
```gherkin
Given Claude 单次输出超过 10MB
When 调用 collect_output
Then 使用 {:line, 4096} 缓冲模式
And 内存使用稳定在 O(1)
```

### Scenario: Port 优雅关闭
```gherkin
Given 一个活跃的 Claude session
When 调用 stop_session
Then 发送 "exit\n"
And 等待 port_close_timeout_ms（默认 5_000ms）
And 若未退出则强制 Port.close
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
- Port 进程在 `on_exit` 中强制关闭
- 环境变量在测试前后恢复
- 安全测试使用 chroot 或临时目录隔离
