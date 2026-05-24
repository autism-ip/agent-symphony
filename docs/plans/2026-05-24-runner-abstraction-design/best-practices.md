# Best Practices — Runner Abstraction

## Security

### Port 命令注入防护

Claude runner 通过 `Port.open({:spawn_executable, ...})` 启动外部进程。必须对命令和参数进行严格校验：

```elixir
# BAD — 直接拼接用户输入
command = "claude --project " <> user_input

# GOOD — 使用参数列表，shell 转义
args = ["-lc", escape_shell(command)]
Port.open({:spawn_executable, "/bin/sh"}, args: args, cd: workspace)
```

`Workspace` 模块已有 `shell_escape/1` 实现（`'"' <> String.replace(value, "'", "'\"'\"'") <> "'"`），复用之。

### Workspace 路径逃逸防护

`Workspace.validate_workspace_path/2` 已有路径安全校验（canonicalize + root prefix 检查）。Claude runner 复用同一逻辑，确保产物写入不越界。

### 产物内容校验

Artifact 写入文件前校验：
- `path` 不得包含 `..` 或绝对路径
- `content` 大小限制（默认 1MB，可配置）
- 禁止写入可执行权限文件（`.exe`, `.sh`, `.bat`）

## Performance

### Port 输出缓冲策略

Claude CLI 输出量可能极大。使用 `:line` 缓冲模式避免内存爆炸：

```elixir
Port.open({:spawn_executable, ...}, [
  {:line, 4096},      # 每行最大 4KB
  :binary,
  :exit_status,
  {:env, env_vars}
])
```

### 超时层级

| 超时类型 | 默认值 | 说明 |
|---|---|---|
| turn_timeout_ms | 300_000 | 单次 turn 最大时间 |
| stall_timeout_ms | 60_000 | 无输出视为僵死 |
| port_close_timeout_ms | 5_000 | Port.close 后等待优雅退出 |

### 并发控制

Orchestrator 的 `max_concurrent` 配置同时限制所有 runner 的总并发，无需 runner 层单独控制。

## 代码质量

### 错误处理模式

所有 runner 回调统一返回 `{:ok, ...}` / `{:error, term()}`。Error reason 使用 tagged tuple：

```elixir
{:error, {:runner_start_failed, command, exit_status}}
{:error, {:runner_timeout, :turn, timeout_ms}}
{:error, {:runner_crashed, signal}}
{:error, {:json_parse_failed, raw_text, jason_reason}}
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
