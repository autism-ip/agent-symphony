# Architecture — Runner Abstraction

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     SymphonyElixir.Orchestrator                 │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ Poll Cycle  │  │   Dispatch   │  │  Metrics / Rate Limit  │ │
│  └──────┬──────┘  └──────┬───────┘  └────────────────────────┘ │
│         │                │                                      │
│         └────────────────┘                                      │
│                          │                                      │
│                          ▼                                      │
│              ┌─────────────────────┐                            │
│              │  AgentRunner.run/3  │                            │
│              │  (runner-agnostic)  │                            │
│              └──────────┬──────────┘                            │
└─────────────────────────┼───────────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │    Runner.adapter/0   │
              │  (基于 Config 动态派发)  │
              └───────────┬───────────┘
                          │
          ┌───────────────┼───────────────┐
          │                               │
          ▼                               ▼
┌─────────────────────┐      ┌─────────────────────┐
│ SymphonyElixir.Codex.Runner │      │ SymphonyElixir.Claude.Runner │
│  @behaviour Runner  │      │  @behaviour Runner  │
│                     │      │                     │
│  start_session ─────┼─────▶│  start_session ─────┼─────▶ Port.open(claude)
│  run_turn ──────────┼─────▶│  run_turn ──────────┼─────▶ Port.command/2
│  stop_session ──────┼─────▶│  stop_session ──────┼─────▶ Port.close/1
│  parse_result ──────┼─────▶│  parse_result ──────┼─────▶ 正则提取 JSON
└──────────┬──────────┘      └──────────┬──────────┘
           │                            │
           ▼                            ▼
┌─────────────────────┐      ┌─────────────────────┐
│ Codex.AppServer     │      │ Claude CLI Process  │
│ (stdio JSON-RPC)    │      │ (stdio text + JSON) │
└─────────────────────┘      └─────────────────────┘
```

## Module 职责矩阵

| Module | 职责 | 变更类型 |
|---|---|---|
| `SymphonyElixir.Runner` | 定义 behaviour + 动态 adapter 选择 | 新增 |
| `SymphonyElixir.Codex.Runner` | Codex 的 behaviour 实现 | 新增 |
| `SymphonyElixir.Claude.Runner` | Claude CLI 的 behaviour 实现 | 新增 |
| `SymphonyElixir.Claude.JsonParser` | 从 stdout 提取标记包裹的 JSON | 新增 |
| `SymphonyElixir.AgentRunner` | 重构为 runner-agnostic | 修改 |
| `SymphonyElixir.Config.Schema` | 新增 `runner` embeds_one | 修改 |
| `SymphonyElixir.Orchestrator` | 泛化指标字段名 | 修改 |
| `SymphonyElixir.Orchestrator.State` | 泛化字段名 | 修改 |

## 数据流：一次 Issue 处理

```
1. Orchestrator 从 Tracker 获取 candidate issues
2. 对每个 issue：
   a. Workspace.create_for_issue(issue, worker_host)
   b. Workspace.run_before_run_hook(workspace, issue, worker_host)
   c. AgentRunner.run(issue, workspace, worker_host)
      i.   runner = Runner.adapter()
      ii.  {:ok, session} = runner.start_session(issue, workspace, worker_host)
      iii. {:ok, text} = runner.run_turn(session, prompt, timeout)
      iv.  runner.stop_session(session)
      v.   {:ok, result} = runner.parse_result(text)
      vi.  ArtifactStore.save(result.artifacts, workspace, issue)
   d. Workspace.run_after_run_hook(workspace, issue, worker_host)
   e. Tracker.update_issue_state(issue.id, next_state)
```

## 错误处理层级

| 层级 | 异常类型 | 处理策略 |
|---|---|---|
| Port 层 | CLI 进程崩溃 | `Port.info/1` 检测，记录 error，更新 issue 为 failed |
| Runner 层 | `run_turn` 超时 | 关闭 session，记录 timeout，更新 issue 为 blocked |
| Parser 层 | JSON 解析失败 | 降级为纯文本结果，记录 warning |
| Artifact 层 | 文件写入失败 | 部分 artifact 失败不影响整体，记录具体失败项 |

## 配置迁移路径

```yaml
# 旧配置（自动兼容）
codex:
  command: codex
  approval_policy: auto

# 新配置
runner:
  type: claude
  claude:
    command: claude
    approval_policy: none
    max_turns: 10
```

`Config.Schema` 的 `finalize_settings/0` 负责旧配置到新配置的迁移：
- 若存在顶层 `codex` 且无 `runner`，自动生成 `runner: %{type: "codex", codex: <原有 codex 配置>}`
