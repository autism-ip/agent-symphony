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
| R3 | 实现 `Claude.Runner`，通过 Port 启动 `claude` CLI | P0 | ZEN-15 |
| R4 | 配置 schema 支持 `runner.type` 选择（"codex" / "claude"） | P0 | ZEN-16 |
| R5 | Claude runner 输出结构化 JSON（`###SYMPHONY_JSON###` 标记包裹） | P0 | ZEN-15 |
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

### 为什么用 `###SYMPHONY_JSON###` 标记？

Claude Code CLI 输出混合了自然语言对话和结构化结果。标记方式允许 runner 从 stdout 中提取 JSON payload，同时保留人类可读的 CLI 输出用于调试。

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
  runner = Config.settings!().runner.type |> runner_module()

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
  def start_session(issue, workspace, worker_host) do
    AppServer.start_session(issue, workspace, worker_host: worker_host)
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

### 4. Claude.Runner

```elixir
defmodule SymphonyElixir.Claude.Runner do
  @behaviour SymphonyElixir.Runner

  require Logger

  @json_start "###SYMPHONY_JSON_START###"
  @json_end "###SYMPHONY_JSON_END###"

  @impl true
  def start_session(issue, workspace, worker_host) do
    command = Config.settings!().runner.claude.command
    env = session_env(issue, workspace)

    port = open_claude_port(command, env, workspace, worker_host)

    session = %{
      port: port,
      workspace: workspace,
      worker_host: worker_host,
      issue_id: issue.id
    }

    {:ok, session}
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    Port.command(session.port, format_prompt(prompt))

    case collect_output(session.port, timeout_ms) do
      {:ok, output} -> {:ok, output, session}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stop_session(session) do
    Port.command(session.port, "exit\n")
    Port.close(session.port)
    :ok
  end

  @impl true
  def parse_result(text) do
    case extract_json(text) do
      {:ok, json} -> decode_result(json)
      :no_json -> {:ok, %{status: :success, artifacts: [%{type: :text, content: text}]}}
    end
  end
end
```

### 5. Config Schema 变更

```elixir
defmodule SymphonyElixir.Config.Schema do
  # 新增 Runner 配置
  embedded_schema do
    field :type, :string, default: "codex"
    embeds_one :codex, Codex, on_replace: :update, defaults_to_struct: true
    embeds_one :claude, Claude, on_replace: :update, defaults_to_struct: true
  end

  defmodule Claude do
    embedded_schema do
      field :command, :string, default: "claude"
      field :approval_policy, :string, default: "none"
      field :turn_timeout_ms, :integer, default: 300_000
      field :max_turns, :integer, default: 10
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

## Design Documents

- [BDD Specifications](./bdd-specs.md) — Behavior scenarios and testing strategy
- [Architecture](./architecture.md) — System architecture and component details
- [Best Practices](./best-practices.md) — Security, performance, and code quality guidelines
