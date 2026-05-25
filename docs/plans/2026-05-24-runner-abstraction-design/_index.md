# Runner Abstraction Design — 2026-05-24

## Context

AgentSymphony 当前仅支持 Codex 作为 AI agent runner。`SymphonyElixir.AgentRunner` 直接硬编码调用 `Codex.AppServer` 的 `start_session/2`、`run_turn/4`、`stop_session/1`。

随着 Claude Code CLI 的引入，系统需要一个可插拔的 runner 抽象层，使得 Orchestrator 无需关心底层 agent 的实现细节。

## Requirements

### Functional Requirements

| ID | Requirement | Priority | Driver |
|---|---|---|---|
| R1 | 定义 `SymphonyElixir.Runner` behaviour，统一 runner 生命周期 | P0 | ZEN-14 |
| R2 | 实现 `Codex.Runner` 适配现有 `Codex.AppServer` | P0 | ZEN-14 |
| R3 | 实现 `Claude.Runner`，每次 `run_turn` 通过 `System.cmd` 启动 `claude` 子进程（Per-turn New Process） | P0 | ZEN-15 |
| R4 | 配置 schema 支持 `runner.type` 选择（"codex" / "claude"） | P0 | ZEN-16 |
| R5 | Claude runner 通过 `--output-format json` 原生获取结构化 JSON（`{"result": "text", "session_id": "..."}`） | P0 | ZEN-15 |
| R6 | 产物持久化：本地 workspace + Linear comment | P0 | ZEN-17 |
| R7 | Orchestrator 指标字段泛化（`codex_*` → `runner_*`） | P1 | ZEN-14 |
| R8 | E2E 测试覆盖 Codex + Claude 双 runner | P1 | ZEN-18 |

### Non-Functional Requirements

- **向后兼容**：现有 Codex 配置无需修改即可继续工作
- **测试覆盖**：新增模块达到 100% 阈值（或加入 `ignore_modules`）
- **错误处理**：runner 崩溃时优雅降级，记录日志，更新 issue 状态

## Design Rationale

### 为什么用 Behaviour 而非 Protocol？

Elixir 中 behaviour 是定义模块契约的标准方式。`SymphonyElixir.Tracker` 已经采用此模式（`@callback` + `adapter()` 动态派发），新 runner 抽象与之保持一致，降低认知负荷。

### 为什么保持 `Codex.AppServer` 不变？

`AppServer` 负责 stdio JSON-RPC 协议细节，属于稳定的底层实现。在其上包装一层 `Codex.Runner` 实现 behaviour，符合"开闭原则"——对扩展开放，对修改关闭。

### 为什么用 Per-turn New Process 而非长连接？

Claude Code CLI 原生支持 `--output-format json`，每次调用 `claude -p "prompt" --output-format json` 直接返回结构化 JSON（`{"result": "text", "session_id": "..."}`）。无需自定义标记（`###SYMPHONY_JSON_START###` 已废弃），无需维护长连接 Port。每次 `run_turn` 启动新进程，天然隔离，崩溃不影响后续 turn。

> **废弃说明**：早期设计使用的 `###SYMPHONY_JSON_START###` / `###SYMPHONY_JSON_END###` 标记方案已废弃。Claude CLI 的 `--output-format json` 是官方支持的结构化输出方式，JsonParser 应解析此原生格式。

## Detailed Design

### 1. Runner Behaviour

```elixir
defmodule SymphonyElixir.Runner do
  @type session :: term()
  @type issue :: map()
  @type workspace :: Path.t()
  @type worker_host :: String.t() | nil
  @type result :: %{status: :success | :error | :blocked, artifacts: [map()]}

  @callback start_session(issue(), workspace(), worker_host()) ::
              {:ok, session()} | {:error, term()}

  @callback run_turn(session(), String.t(), non_neg_integer()) ::
              {:ok, String.t(), session()} | {:error, term()}

  @callback stop_session(session()) :: :ok | {:error, term()}

  @callback parse_result(String.t()) :: {:ok, result()} | {:error, term()}
end
```

### 2. AgentRunner 重构

`AgentRunner.run/3` 不再直接调用 `Codex.AppServer`，改为：

```elixir
def run(issue, workspace, worker_host) do
  runner = Runner.adapter()

  with {:ok, session} <- runner.start_session(issue, workspace, worker_host),
       workflow <- Workflow.current(),
       {:ok, result_text} <- runner.run_turn(session, workflow.prompt, timeout()),
       :ok <- runner.stop_session(session),
       {:ok, result} <- runner.parse_result(result_text) do
    {:ok, result}
  else
    {:error, reason} -> handle_runner_failure(reason, issue, runner)
  end
end
```

### 3. Codex.Runner 包装层

```elixir
defmodule SymphonyElixir.Codex.Runner do
  @behaviour SymphonyElixir.Runner

  alias SymphonyElixir.Codex.AppServer

  @impl true
  def start_session(_issue, workspace, worker_host) do
    AppServer.start_session(workspace, worker_host: worker_host)
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    AppServer.run_turn(session, prompt, [], timeout: timeout_ms)
  end

  @impl true
  def stop_session(session), do: AppServer.stop_session(session)

  @impl true
  def parse_result(text), do: {:ok, %{status: :success, artifacts: [%{type: :text, content: text}]}}
end
```

### 4. Claude.Runner（Per-turn New Process）

每次 `run_turn` 启动一个新的 `claude` 子进程，通过 `--output-format json` 获取原生 JSON 输出。无长连接，无 Port 管理。

```elixir
defmodule SymphonyElixir.Claude.Runner do
  @behaviour SymphonyElixir.Runner

  require Logger

  @impl true
  def start_session(issue, workspace, _worker_host) do
    # session 仅保存上下文元数据，不持有进程/端口
    settings = Config.settings!().runner.claude
    session = %{
      workspace: workspace,
      issue_id: issue.id,
      issue_title: issue.title,
      command: settings.command
    }

    {:ok, session}
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    settings = Config.settings!().runner.claude

    args = [
      "-p", prompt,
      "--output-format", "json",
      "--max-turns", to_string(settings.max_turns)
    ]

    # session.command cached from start_session, avoids re-reading config

    opts = [
      cd: session.workspace,
      env: session_env(session),
      stderr_to_stdout: true,
      timeout: timeout_ms
    ]

    case System.cmd(session.command, args, opts) do
      {output, 0} -> {:ok, output, session}
      {output, exit_code} ->
        Logger.error("claude CLI exited #{exit_code}: #{String.slice(output, 0, 500)}")
        {:error, {:claude_exit, exit_code, output}}
    end
  end

  @impl true
  def stop_session(_session), do: :ok

  @impl true
  def parse_result(json_text) do
    # Claude CLI --output-format json 返回:
    # {"result": "text content", "session_id": "...", "total_cost_usd": 0.0, ...}
    case Jason.decode(json_text) do
      {:ok, %{"result" => result_text}} ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: result_text}]}}

      {:ok, %{"error" => error_msg}} ->
        {:ok, %{status: :error, artifacts: [%{type: :text, content: error_msg}]}}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end
end
```

### 5. Config Schema 变更

新增 `runner` 嵌入式 schema，顶层 `type` 字段选择 runner 实现。向后兼容：当 `runner` 为 nil 但 `codex` 存在时，自动生成 `runner: %{type: "codex"}`。

```elixir
defmodule SymphonyElixir.Config.Schema do
  # 新增 Runner 配置（嵌入式 schema）
  embedded_schema do
    # ... 现有字段 ...
    embeds_one :runner, Runner, on_replace: :update, defaults_to_struct: true
  end

  defmodule Runner do
    embedded_schema do
      field :type, :string, default: "codex"  # "codex" | "claude"
      embeds_one :codex, CodexConfig, on_replace: :update, defaults_to_struct: true
      embeds_one :claude, ClaudeConfig, on_replace: :update, defaults_to_struct: true
    end
  end

  defmodule ClaudeConfig do
    embedded_schema do
      field :command, :string, default: "claude"
      field :turn_timeout_ms, :integer, default: 300_000
      field :stall_timeout_ms, :integer, default: 60_000
      field :max_turns, :integer, default: 10
    end
  end

  # 向后兼容迁移
  def migrate_runner(config) do
    case {config.runner, config.codex} do
      {nil, codex} when not is_nil(codex) ->
        %{config | runner: %{type: "codex"}}
      _ ->
        config
    end
  end
end
```

### 6. Orchestrator 指标泛化

| 旧字段 | 新字段 |
|---|---|
| `codex_totals` | `runner_totals` |
| `codex_rate_limits` | `runner_rate_limits` |

保持旧字段作为别名（向后兼容一个版本周期），内部统一使用新字段。

### 7. Artifact Persistence 流程

```
Claude.Runner.run_turn/3
  └── 解析结果中的 artifacts
       ├── artifact.type == :file
       │     ├── 写入 workspace/.symphony/artifacts/
       │     └── 相对路径存入结果
       └── artifact.type == :comment
             └── 调用 Tracker.create_comment(issue_id, content)
```

### 8. Orchestrator Functional Core 提取

当前 `Orchestrator` GenServer 有 1921 行，职责混杂。采用 Functional Core 模式提取纯函数到 6 个模块，GenServer shell 缩减至约 450 行。

| 模块 | 行数 | 职责 |
|---|---|---|
| `Orchestrator.CodexTelemetry` | ~250 | Token 计费、用量统计 |
| `Orchestrator.BlockerDetector` | ~100 | Input-required 阻塞检测 |
| `Orchestrator.Reconciler` | ~230 | 状态协调、Linear 同步 |
| `Orchestrator.Dispatcher` | ~220 | Issue 选择、调度决策 |
| `Orchestrator.RetryManager` | ~200 | 重试调度、退避策略 |
| `Orchestrator.Poller` | ~80 | Timer 管理、轮询控制 |

**设计原则**：所有提取的模块为纯函数，无副作用，无 GenServer 依赖。GenServer shell 仅负责状态持有和进程生命周期，所有业务逻辑委托给 Functional Core。

### 9. Phase 1 执行计划

8 步执行计划，详见 [`docs/plans/phase-1-execution-plan.md`](../phase-1-execution-plan.md)。

| Step | Ticket | 内容 |
|---|---|---|
| 1 | ZEN-12 | Runner Behaviour 定义 |
| 2 | ZEN-13 | Codex.Runner 包装层 |
| 3 | ZEN-14 | AgentRunner 重构 + 指标泛化 |
| 4 | ZEN-15 | Claude.Runner 实现 |
| 5 | ZEN-16 | Config Schema 变更 + 向后兼容迁移 |
| 6 | ZEN-17 | Artifact Persistence |
| 7 | ZEN-18 | E2E 测试 |
| 8 | — | Orchestrator Functional Core 提取 |

## Design Documents

- [BDD Specifications](./bdd-specs.md) — Behavior scenarios and testing strategy
- [Architecture](./architecture.md) — System architecture and component details
- [Best Practices](./best-practices.md) — Security, performance, and code quality guidelines
