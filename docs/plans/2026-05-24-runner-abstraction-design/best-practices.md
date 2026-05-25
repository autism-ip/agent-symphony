# Best Practices — Runner Abstraction

## Security

### System.cmd 命令注入防护

Claude runner 通过 `System.cmd/3` 启动外部进程。参数以列表传递，不经 shell 解释，天然防止注入：

```elixir
# GOOD — 参数列表形式，System.cmd 不经过 shell
System.cmd(settings.command, ["-p", prompt, "--output-format", "json"], cd: workspace)
```

必须校验 `settings.command` 不含 shell 元字符（`;`, `|`, `&`, `` ` `` 等），在配置加载阶段拒绝非法值。

### Workspace 路径逃逸防护

`Workspace.validate_workspace_path/2` 已有路径安全校验（canonicalize + root prefix 检查）。Claude runner 复用同一逻辑，确保产物写入不越界。

### 产物内容校验

Artifact 写入文件前校验：
- `path` 不得包含 `..` 或绝对路径
- `content` 大小限制（默认 1MB，可配置）
- 禁止写入可执行权限文件（`.exe`, `.sh`, `.bat`）

## Performance

### System.cmd 输出策略

`System.cmd/3` 自动收集全部 stdout 到内存。对于超大输出，通过 `timeout_ms` 限制执行时间防止无限增长。

### 超时层级

| 超时类型 | 默认值 | 说明 |
|---|---|---|
| turn_timeout_ms | 300_000 | 单次 turn 最大时间 |
| stall_timeout_ms | 60_000 | 无输出视为僵死（System.cmd 无此机制，由 timeout_ms 兜底） |

### 并发控制

Orchestrator 的 `max_concurrent` 配置同时限制所有 runner 的总并发，无需 runner 层单独控制。

## 代码质量

### 错误处理模式

所有 runner 回调统一返回 `{:ok, ...}` / `{:error, term()}`。Error reason 使用 tagged tuple：

```elixir
{:error, {:claude_exit, exit_code, output}}
{:error, {:runner_timeout, :turn, timeout_ms}}
{:error, {:json_decode, reason}}
```

### 日志规范

```elixir
Logger.info("Runner started", runner: "claude", issue_id: issue_id, workspace: workspace)
Logger.warning("Runner turn timeout", runner: "claude", issue_id: issue_id, timeout_ms: timeout_ms)
Logger.error("Runner crashed", runner: "claude", issue_id: issue_id, exit_status: status)
```

### 类型规范

所有公共函数添加 `@spec`，所有模块添加 `@moduledoc`。

## 兼容性

### 向后兼容承诺

- v0.1.x：顶层 `codex` 配置自动迁移到 `runner.type = "codex"`
- v0.2.0：废弃顶层 `codex`，打印 deprecation warning
- v0.3.0：移除顶层 `codex` 支持

### Config 验证

新增 `Config.Schema` validation 步骤，确保：
- `runner.type` 必须是 `"codex"` 或 `"claude"`
- `runner.claude` 仅在 `type = "claude"` 时必填
- `runner.codex` 仅在 `type = "codex"` 时必填（向后兼容期允许缺失）
