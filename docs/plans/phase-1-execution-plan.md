# Phase 1 Execution Plan — Elixir Claude Runner

> Created: 2026-05-24
> Status: Draft
> Linear Milestone: Phase 1 — Elixir Claude Runner

---

## Table of Contents

1. [Current State Assessment](#1-current-state-assessment)
2. [Phase 1 Execution Steps](#2-phase-1-execution-steps)
3. [Orchestrator Functional Core Extraction](#3-orchestrator-functional-core-extraction)
4. [Phase 2-5 Architecture Overview](#4-phase-25-architecture-overview)
5. [Risk Assessment](#5-risk-assessment)
6. [Testing Strategy](#6-testing-strategy)

---

## 1. Current State Assessment

### What Already Exists

| File | Status | Lines | Purpose |
|---|---|---|---|
| `lib/symphony_elixir/runner.ex` | Untracked | 47 | Runner behaviour + `adapter/0` dispatch |
| `lib/symphony_elixir/codex/runner.ex` | Untracked | 50 | Codex.Runner wrapping AppServer |
| `lib/symphony_elixir/orchestrator.ex` | Tracked | 1921 | Monolithic GenServer (needs extraction) |
| `lib/symphony_elixir/agent_runner.ex` | Tracked | 203 | Hardcoded to Codex.AppServer |
| `lib/symphony_elixir/config/schema.ex` | Tracked | 557 | No `runner` section yet |
| `lib/symphony_elixir/claude/` | Empty dir | 0 | Placeholder for Claude runner |
| `docs/plans/2026-05-24-runner-abstraction-design/` | Tracked | 4 files | Design docs (architecture, BDD, best practices) |

### What Does Not Exist Yet

- `lib/symphony_elixir/claude/runner.ex` — Claude CLI runner implementation
- `lib/symphony_elixir/claude/json_parser.ex` — JSON extraction from Claude CLI output
- `lib/symphony_elixir/config/schema.ex` `Runner` embedded schema — runner config section
- Orchestrator functional core modules (6 modules)
- Tests for runner behaviour, Codex.Runner, Claude.Runner
- AgentRunner refactoring to use Runner.adapter()

### Key Architectural Decisions Already Made

1. **Per-turn process model**: Claude.Runner spawns a new process per `run_turn/3` call via `System.cmd("claude", ["-p", prompt, "--output-format", "json"], opts)`. No persistent session, no Port management.
2. **JSON output parsing**: Use Claude CLI's native `--output-format json` instead of custom `###SYMPHONY_JSON_START###` markers (design doc is outdated on this point).
3. **Stall detection**: Not available under `System.cmd` (blocking call). The `stall_timeout_ms` config field is reserved for future use if a Port-based model is adopted. Under System.cmd, only `turn_timeout_ms` (300s) applies.
4. **Turn timeout**: 300s hard timeout per turn via `System.cmd` `:timeout` option.
6. **Orchestrator extraction**: Pure functions to 6 separate modules, GenServer stays as thin shell.

---

## 2. Phase 1 Execution Steps

### Step 0: ZEN-12 — Audit (No Code Changes)

**What to do:**
Read through the full codebase and produce a concise architecture audit document.

**Files to touch:**
- CREATE `docs/ARCHITECTURE_NOTES.md`

**Key findings to document:**
- Runner integration boundary: `AgentRunner.run_codex_turns/5` directly calls `AppServer.start_session/2`, `AppServer.run_turn/4`, `AppServer.stop_session/1`
- Linear writes: Done by the agent itself via MCP tools inside the Codex session, not by Symphony
- Dashboard/status: `Orchestrator.snapshot/2` and `StatusDashboard`
- In-memory state: `Orchestrator.State` struct — lost on crash, reconstructed from Linear on restart
- Workspace lifecycle: `Workspace.create_for_issue/2`, `Workspace.remove_issue_workspaces/2`

**Dependencies:** None (first step)
**Acceptance Criteria:** Document exists, identifies runner boundary, identifies Linear write points, identifies restart/recovery behavior.
**Estimated effort:** 1-2 hours
**Risk:** Negligible — read-only task.

---

### Step 1: ZEN-13 — Run Locally (No Code Changes)

**What to do:**
Boot the existing Elixir Symphony against the real Linear project to validate the polling/dispatch pipeline works.

**Files to touch:**
- None (operational validation only)

**Steps:**
1. `cd elixir && mix deps.get` — verify deps install
2. Verify `WORKFLOW.md` already has correct `project_slug: "symphony-0c79b11b75ea"`
3. `mix run --no-halt` or `iex -S mix` — start the service
4. Observe logs for:
   - Linear poll cycle firing every 5s
   - Issue eligibility filtering
   - Workspace creation attempts
   - Codex AppServer launch (expected to fail if Codex CLI not installed — that's fine)
5. Document findings in issue notes

**Dependencies:** Step 0 (understanding of codebase)
**Acceptance Criteria:** App starts, polls Linear, reaches workspace/agent boundary.
**Estimated effort:** 1-2 hours
**Risk:** Low — may fail at Codex CLI invocation if not installed, which is expected and informative.

---

### Step 2: ZEN-14 — Commit Runner Behaviour + Codex.Runner

**What to do:**
The code for `runner.ex` and `codex/runner.ex` already exists as untracked files. This step is primarily about:
1. Adding the `Runner` config section to `Config.Schema`
2. Adding tests
3. Committing everything

**Files to touch:**
- `lib/symphony_elixir/runner.ex` — already exists, review and commit
- `lib/symphony_elixir/codex/runner.ex` — already exists, review and commit
- `lib/symphony_elixir/config/schema.ex` — ADD `Runner` embedded schema
- `test/symphony_elixir/runner_test.exs` — NEW: behaviour contract tests
- `test/symphony_elixir/codex/runner_test.exs` — NEW: Codex.Runner unit tests

**Detailed changes to `config/schema.ex`:**

```elixir
# Add inside the main schema module, after the Codex schema:

defmodule Runner do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:type, :string, default: "codex")
    embeds_one(:codex, Codex, on_replace: :update, defaults_to_struct: true)
    embeds_one(:claude, Claude, on_replace: :update, defaults_to_struct: true)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:type], empty_values: [])
    |> validate_inclusion(:type, ["codex", "claude"])
    |> cast_embed(:codex, with: &Codex.changeset/2)
    |> cast_embed(:claude, with: &Claude.changeset/2)
  end
end

defmodule Claude do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:command, :string, default: "claude")
    field(:turn_timeout_ms, :integer, default: 300_000)
    field(:stall_timeout_ms, :integer, default: 60_000)
    field(:max_turns, :integer, default: 10)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:command, :turn_timeout_ms, :stall_timeout_ms, :max_turns], empty_values: [])
    |> validate_required([:command])
    |> validate_number(:turn_timeout_ms, greater_than: 0)
    |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
    |> validate_number(:max_turns, greater_than: 0)
  end
end
```

**Add to main `embedded_schema` block:**
```elixir
embeds_one(:runner, Runner, on_replace: :update, defaults_to_struct: true)
```

**Add to `changeset/1` private function:**
```elixir
|> cast_embed(:runner, with: &Runner.changeset/2)
```

**Add backward compatibility in `finalize_settings/1`:**
When `runner` is nil but `codex` exists at top level, auto-generate `runner: %{type: "codex"}`.

**Test coverage for `runner.ex`:**
- `adapter/0` returns `Codex.Runner` when config has `runner.type = "codex"`
- `adapter/0` returns `Claude.Runner` when config has `runner.type = "claude"`
- `adapter/0` returns `Codex.Runner` when config has no `runner` section (backward compat)

**Test coverage for `codex/runner.ex`:**
- `start_session/3` delegates to `AppServer.start_session/2`
- `run_turn/3` delegates to `AppServer.run_turn/4`
- `stop_session/1` delegates to `AppServer.stop_session/1`
- `parse_result/1` returns `{:ok, %{status: :success, artifacts: [...]}}`

**Dependencies:** Step 0, Step 1
**Acceptance Criteria:**
- `mix test` passes with new tests
- `mix specs.check` passes (all public functions have @spec)
- Existing Codex path unchanged when `runner.type = "codex"` or when `runner` config is absent
- `runner.ex` and `codex/runner.ex` are tracked in git
**Estimated effort:** 3-4 hours
**Risk:** Medium — backward compatibility in config parsing is the tricky part. Must ensure existing `WORKFLOW.md` files without `runner:` section still work.

---

### Step 3: ZEN-15 — Implement Claude.Runner

**What to do:**
Build the full Claude CLI runner implementation.

**Files to touch:**
- CREATE `lib/symphony_elixir/claude/runner.ex` — main runner module
- CREATE `lib/symphony_elixir/claude/json_parser.ex` — JSON extraction from `--output-format json`
- CREATE `test/symphony_elixir/claude/runner_test.exs`
- CREATE `test/symphony_elixir/claude/json_parser_test.exs`

**`Claude.Runner` module design:**

```elixir
defmodule SymphonyElixir.Claude.Runner do
  @behaviour SymphonyElixir.Runner

  require Logger
  alias SymphonyElixir.Config

  @type session :: %{
    workspace: Path.t(),
    issue_id: String.t(),
    issue_title: String.t(),
    command: String.t()
  }

  @impl true
  def start_session(issue, workspace, _worker_host) do
    settings = Config.settings!().runner.claude
    session = %{
      workspace: workspace,
      issue_id: issue[:id] || issue["id"],
      issue_title: issue[:title] || issue["title"],
      command: settings.command
    }
    {:ok, session}
  end

  @impl true
  def run_turn(session, prompt, timeout_ms) do
    args = build_args(prompt, session.workspace, timeout_ms)
    env = session_env(session)

    case System.cmd(session.command, args, [
      cd: session.workspace,
      env: env,
      stderr_to_stdout: true,
      timeout: timeout_ms
    ]) do
      {output, 0} -> {:ok, output, session}
      {output, exit_code} ->
        Logger.error("claude CLI exited #{exit_code}: #{String.slice(output, 0, 500)}")
        {:error, {:claude_exit, exit_code, output}}
    end
  end

  # ... callbacks
end
```

**Key implementation details:**

1. **`start_session/3`**: Store config and issue metadata in session map. No process spawned.

2. **`run_turn/3`**:
   - Build CLI args: `-p "prompt" --output-format json --max-turns N --dangerously-skip-permissions`
   - Execute via `System.cmd(session.command, args, cd: workspace, env: env, timeout: timeout_ms)`
   - On exit code 0: `{:ok, output, session}`
   - On exit code != 0: `{:error, {:claude_exit, exit_code, output}}`
   - On timeout: `System.cmd` raises `:timeout` — catch and return `{:error, {:runner_timeout, :turn, timeout_ms}}`

3. **`stop_session/1`**: No-op (per-turn model has no persistent process). Return `:ok`.

4. **`parse_result/1`**: Delegate to `Claude.JsonParser.parse/1`.

**`Claude.JsonParser` module design:**

```elixir
defmodule SymphonyElixir.Claude.JsonParser do
  @moduledoc """
  Parses Claude CLI --output-format json output.

  Claude CLI with --output-format json returns a JSON object with a "result" field.
  This parser extracts that field and maps it to the Runner result format.
  """

  @spec parse(String.t()) :: {:ok, SymphonyElixir.Runner.result()} | {:error, term()}
  def parse(raw_output) when is_binary(raw_output) do
    case Jason.decode(raw_output) do
      {:ok, %{"result" => result_text}} when is_binary(result_text) ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: result_text}]}}

      {:ok, %{"result" => nil}} ->
        {:ok, %{status: :success, artifacts: []}}

      {:ok, _other} ->
        {:ok, %{status: :success, artifacts: [%{type: :text, content: raw_output}]}}

      {:error, _reason} ->
        Logger.warning("Claude CLI output is not valid JSON, treating as plain text")
        {:ok, %{status: :success, artifacts: [%{type: :text, content: raw_output}]}}
    end
  end
end
```

**Dependencies:** Step 2 (Runner behaviour exists)
**Acceptance Criteria:**
- `Claude.Runner` implements all 4 `@callback`s
- Per-turn lifecycle: start_session stores config, run_turn calls System.cmd, stop_session is no-op
- Turn timeout works (300s total → timeout error)
- Turn timeout works (300s total → error)
- CLI crash detected via exit_status
- JSON parsing handles valid JSON, missing result field, invalid JSON gracefully
- Tests pass
**Estimated effort:** 6-8 hours
**Risk:** HIGH — this is the core deliverable. Risks include:
  - Claude CLI argument format may differ from assumptions
  - `--output-format json` exact schema needs verification against real CLI
  - Port binary collection edge cases (buffered output, partial lines)
  - Environment variable propagation for API keys

---

### Step 4: ZEN-16 — Extend WORKFLOW.md Runner Configuration

**What to do:**
Update `WORKFLOW.md` with the runner config section. Update `AgentRunner` to use `Runner.adapter()` instead of hardcoded `AppServer`.

**Files to touch:**
- `WORKFLOW.md` — ADD `runner:` section to front matter
- `lib/symphony_elixir/agent_runner.ex` — REFACTOR to use `Runner.adapter()`

**WORKFLOW.md front matter addition:**

```yaml
runner:
  type: claude
  claude:
    command: claude
    turn_timeout_ms: 300000
    stall_timeout_ms: 60000
```

**AgentRunner refactoring — key changes:**

The current `run_codex_turns/5` directly calls `AppServer`. Refactor to:

```elixir
defp run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
  runner = Runner.adapter()
  max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.max_turns)
  issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)

  with {:ok, session} <- runner.start_session(issue, workspace, worker_host) do
    try do
      do_run_turns(runner, session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, 1, max_turns)
    after
      runner.stop_session(session)
    end
  end
end

defp do_run_turns(runner, session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, turn_number, max_turns) do
  prompt = build_turn_prompt(issue, opts, turn_number, max_turns)
  timeout = Config.settings!().runner.claude.turn_timeout_ms

  case runner.run_turn(session, prompt, timeout) do
    {:ok, text, updated_session} ->
      Logger.info("Completed turn for #{issue_context(issue)} turn=#{turn_number}/#{max_turns}")

      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          do_run_turns(runner, updated_session, workspace, refreshed_issue, codex_update_recipient, opts, issue_state_fetcher, turn_number + 1, max_turns)

        {:continue, _} ->
          Logger.info("Reached max_turns for #{issue_context(issue)}; returning control")
          :ok

        {:done, _} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end

    {:error, reason} ->
      Logger.error("Turn failed for #{issue_context(issue)}: #{inspect(reason)}")
      {:error, reason}
  end
end
```

**Critical compatibility note:** The existing `run_codex_turns` sends `{:codex_worker_update, issue_id, message}` messages to the orchestrator for telemetry. The Claude runner won't produce these messages since it uses a different execution model. The orchestrator's `handle_info({:codex_worker_update, ...})` clause must gracefully handle the absence of these messages (it already does — the clause pattern-matches on the message shape).

**Dependencies:** Step 2, Step 3
**Acceptance Criteria:**
- `WORKFLOW.md` has `runner:` section
- `AgentRunner` uses `Runner.adapter()` for all session operations
- `Codex.Runner` path still works end-to-end when `runner.type = "codex"`
- `Claude.Runner` path works end-to-end when `runner.type = "claude"`
- Token accounting gracefully degrades (no codex_worker_update messages from Claude)
**Estimated effort:** 3-4 hours
**Risk:** Medium — the AgentRunner refactoring must preserve all existing semantics (continuation turns, issue state checks, workspace hooks, error handling). The token accounting gap (no codex_worker_update from Claude) is acceptable for MVP.

---

### Step 5: ZEN-17 — Save Claude Runner Artifacts

**What to do:**
Persist Claude runner output to the workspace and optionally to Linear comments.

**Files to touch:**
- CREATE `lib/symphony_elixir/artifact_store.ex` — artifact persistence module
- `lib/symphony_elixir/agent_runner.ex` — ADD artifact saving after successful run_turn
- CREATE `test/symphony_elixir/artifact_store_test.exs`

**ArtifactStore module design:**

```elixir
defmodule SymphonyElixir.ArtifactStore do
  @moduledoc """
  Persists runner artifacts to workspace and Linear.
  """

  @artifact_dir ".symphony/artifacts"
  @max_artifact_size 1_048_576  # 1MB

  @spec save([map()], Path.t(), String.t()) :: :ok | {:error, term()}
  def save(artifacts, workspace, issue_id) when is_list(artifacts) do
    artifacts
    |> Enum.reduce(:ok, fn artifact, acc ->
      case save_single(artifact, workspace, issue_id) do
        :ok -> acc
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp save_single(%{type: :text, content: content}, workspace, _issue_id) do
    dir = Path.join(workspace, @artifact_dir)
    File.mkdir_p!(dir)
    path = Path.join(dir, "output-#{timestamp()}.txt")
    File.write(path, content)
  end

  defp save_single(%{type: :file, path: rel_path, content: content}, workspace, _issue_id) do
    with :ok <- validate_artifact_path(rel_path),
         :ok <- validate_artifact_size(content),
         dir = Path.join(workspace, @artifact_dir),
         :ok <- File.mkdir_p!(Path.dirname(Path.join(dir, rel_path))) do
      File.write(Path.join(dir, rel_path), content)
    end
  end

  defp save_single(%{type: :comment, content: content}, _workspace, issue_id) do
    # Post as Linear comment via Tracker
    SymphonyElixir.Tracker.create_comment(issue_id, content)
  end

  defp validate_artifact_path(path) do
    expanded = Path.expand(path)
    if String.contains?(expanded, ".."),
      do: {:error, {:invalid_artifact_path, path}},
      else: :ok
  end

  defp validate_artifact_size(content) do
    if byte_size(content) > @max_artifact_size,
      do: {:error, {:artifact_too_large, @max_artifact_size}},
      else: :ok
  end
end
```

**Integration point in AgentRunner:**
After `runner.run_turn/3` succeeds and `runner.parse_result/1` returns artifacts, call:
```elixir
ArtifactStore.save(result.artifacts, workspace, issue.id)
```

**Dependencies:** Step 3 (Claude.Runner produces artifacts), Step 4 (AgentRunner refactored)
**Acceptance Criteria:**
- Text artifacts saved to `{workspace}/.symphony/artifacts/`
- Path traversal blocked
- Size limit enforced (1MB)
- Comment artifacts posted to Linear via Tracker
- Tests pass
**Estimated effort:** 2-3 hours
**Risk:** Low — straightforward file I/O with well-defined security constraints.

---

### Step 6: Orchestrator Functional Core Extraction

**What to do:**
Extract pure functions from the 1921-line `orchestrator.ex` into 6 focused modules. The GenServer remains as a thin shell that delegates to pure functions.

**This is NOT a Linear issue but is required for maintainability and Phase 2+ work.**

**Files to touch:**
- CREATE `lib/symphony_elixir/orchestrator/codex_telemetry.ex` (~250 lines)
- CREATE `lib/symphony_elixir/orchestrator/blocker_detector.ex` (~100 lines)
- CREATE `lib/symphony_elixir/orchestrator/reconciler.ex` (~230 lines)
- CREATE `lib/symphony_elixir/orchestrator/dispatcher.ex` (~220 lines)
- CREATE `lib/symphony_elixir/orchestrator/retry_manager.ex` (~200 lines)
- CREATE `lib/symphony_elixir/orchestrator/poller.ex` (~80 lines)
- MODIFY `lib/symphony_elixir/orchestrator.ex` — reduce to ~400 lines (GenServer shell)
- CREATE tests for each extracted module

**Extraction priority (by independence and risk):**

#### 6a. `Orchestrator.CodexTelemetry` (lowest risk, highest isolation)

**Extract from orchestrator.ex:**
- `integrate_codex_update/2` (lines 1438-1466)
- `extract_token_delta/2` (lines 1619-1654)
- `compute_token_delta/4` (lines 1656-1671)
- `extract_token_usage/1` (lines 1673-1686)
- `apply_token_delta/2` (lines 1603-1617)
- `apply_codex_token_delta/2` (lines 1581-1589)
- `apply_codex_rate_limits/2` (lines 1591-1601)
- `extract_rate_limits/1` (lines 1688-1695)
- All `absolute_token_usage_from_payload`, `turn_completed_usage_from_payload`, rate limit helpers
- `integer_token_map?/1`, `get_token_usage/2`, `payload_get/2`, `map_integer_value/2`
- `running_seconds/2`

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.CodexTelemetry do
  @spec integrate_update(map(), map()) :: {map(), map()}
  def integrate_update(running_entry, update)

  @spec apply_token_delta(map(), map()) :: map()
  def apply_token_delta(totals, delta)

  @spec apply_rate_limits(map(), map()) :: map() | nil
  def apply_rate_limits(update)
end
```

#### 6b. `Orchestrator.BlockerDetector` (low risk, pure predicate)

**Extract from orchestrator.ex:**
- `input_required_blocker?/1` (lines 634-641)
- `input_required_completion_outcome/1` (lines 643-648)
- `normalize_input_required_outcome/1` (lines 650-663)
- `blocker_error/2` (lines 665-672)
- `codex_event_blocker_error/1` (lines 674-676)
- `completion_blocker_error/1` (lines 678-684)
- `codex_message_blocker_error/1` (lines 686-690)
- `codex_message_method/1` (lines 692-696)

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.BlockerDetector do
  @spec input_required?(map()) :: boolean()
  def input_required?(running_entry)

  @spec blocker_error(map(), String.t()) :: String.t()
  def blocker_error(running_entry, fallback)
end
```

#### 6c. `Orchestrator.Reconciler` (medium risk, state transitions)

**Extract from orchestrator.ex:**
- `reconcile_running_issues/1` (lines 300-323)
- `reconcile_blocked_issues/1` (lines 325-347)
- `reconcile_running_issue_states/4` (lines 385-394)
- `reconcile_issue_state/4` (lines 396-418)
- `reconcile_blocked_issue_states/4` (lines 420-429)
- `reconcile_blocked_issue_state/4` (lines 431-451)
- `reconcile_missing_running_issue_ids/3` (lines 453-473)
- `reconcile_missing_blocked_issue_ids/3` (lines 475-495)
- `reconcile_stalled_running_issues/1` (lines 557-574)
- `refresh_running_issue_state/2`, `refresh_blocked_issue_state/2`
- `terminate_running_issue/3`, `release_issue_claim/2`

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.Reconciler do
  @spec reconcile(map(), [Issue.t()], [Issue.t()]) :: map()
  def reconcile(state, active_states, terminal_states)
end
```

Note: This module returns a description of state transitions (actions to take) rather than performing side effects. The GenServer shell applies the transitions.

#### 6d. `Orchestrator.Dispatcher` (medium risk, issue selection)

**Extract from orchestrator.ex:**
- `choose_issues/2` (lines 751-764)
- `sort_issues_for_dispatch/1` (lines 766-774)
- `should_dispatch_issue?/4` (lines 786-802)
- `candidate_issue?/3` (lines 824-840)
- `issue_routable_to_worker?/1` (lines 842-846)
- `todo_issue_blocked_by_non_terminal?/2` (lines 848-863)
- `terminal_issue_state?/2`, `active_issue_state?/2`
- `state_slots_available?/2`, `running_issue_count_for_state/2`
- `available_slots/1`
- `select_worker_host/2` and worker host helpers

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.Dispatcher do
  @spec select_issues([Issue.t()], map()) :: [Issue.t()]
  def select_issues(candidates, state)

  @spec select_worker_host(map(), String.t() | nil) :: String.t() | nil | :no_worker_capacity
  def select_worker_host(state, preferred)
end
```

#### 6e. `Orchestrator.RetryManager` (medium risk, timer management)

**Extract from orchestrator.ex:**
- `schedule_issue_retry/4` (lines 1006-1043)
- `pop_retry_attempt_state/3` (lines 1045-1060)
- `handle_retry_issue/4` (lines 1062-1080)
- `handle_retry_issue_lookup/5` (lines 1082-1105)
- `retry_delay/2` (lines 1172-1178)
- `failure_retry_delay/1` (lines 1180-1183)
- `normalize_retry_attempt/1`, `next_retry_attempt_from_running/1`
- `pick_retry_*` helpers (lines 1195-1209)
- `retry_candidate_issue?/2`, `dispatch_slots_available?/2`
- `handle_active_retry/4`

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.RetryManager do
  @spec schedule_retry(map(), String.t(), integer() | nil, map()) :: {map(), reference()}
  def schedule_retry(state, issue_id, attempt, metadata)

  @spec pop_attempt(map(), String.t(), reference()) :: {:ok, integer(), map(), map()} | :missing
  def pop_attempt(state, issue_id, retry_token)

  @spec retry_delay(integer(), map()) :: non_neg_integer()
  def retry_delay(attempt, metadata)
end
```

#### 6f. `Orchestrator.Poller` (lowest risk, timer scheduling)

**Extract from orchestrator.ex:**
- `schedule_tick/2` (lines 1512-1526)
- `schedule_poll_cycle_start/0` (lines 1528-1531)
- `next_poll_in_ms/2` (lines 1533-1537)

**Module interface:**
```elixir
defmodule SymphonyElixir.Orchestrator.Poller do
  @spec schedule_tick(map(), non_neg_integer()) :: map()
  def schedule_tick(state, delay_ms)

  @spec schedule_poll_cycle(pid()) :: :ok
  def schedule_poll_cycle(pid)

  @spec next_poll_in_ms(integer() | nil, integer()) :: non_neg_integer() | nil
  def next_poll_in_ms(next_poll_due_at_ms, now_ms)
end
```

**Dependencies:** All previous steps should be done first to avoid merge conflicts
**Acceptance Criteria:**
- `orchestrator.ex` reduced to ~400-500 lines (GenServer callbacks only)
- Each extracted module has its own test file
- `mix test` passes
- `mix specs.check` passes
- `Orchestrator.snapshot/2` output unchanged (backward compatible)
**Estimated effort:** 8-12 hours
**Risk:** HIGH — orchestrator is the most complex module. Risk of breaking state machine semantics during extraction. Mitigated by: extracting one module at a time, running full test suite after each extraction, keeping the GenServer shell as the single point of truth.

---

### Step 7: ZEN-18 — End-to-End MVP Test

**What to do:**
Run one real Linear issue through the Claude runner end-to-end.

**Files to touch:**
- Possibly `test/symphony_elixir/live_e2e_test.exs` — extend existing E2E test
- `WORKFLOW.md` — verify runner config

**Steps:**
1. Create or identify a test issue in the Linear project
2. Set `runner.type = "claude"` in `WORKFLOW.md`
3. Start Symphony locally: `mix run --no-halt`
4. Observe the issue being picked up, workspace created, Claude CLI invoked
5. Verify artifacts are saved in workspace
6. Verify issue state transitions
7. Document findings

**Dependencies:** Steps 3, 4, 5 (Claude runner, AgentRunner refactor, artifact store)
**Acceptance Criteria:**
- One Linear issue processed end-to-end through Claude runner
- Claude CLI invoked successfully from workspace
- Artifacts saved
- Issue state updated (or documented why not)
- No crashes or unhandled errors
**Estimated effort:** 2-4 hours
**Risk:** Medium — depends on Claude CLI availability, API key configuration, and Linear API access. May require debugging CLI argument format, environment setup.

---

## 3. Orchestrator Functional Core Extraction

### Extraction Strategy

The extraction follows the "Functional Core, Imperative Shell" pattern:

1. **Identify pure functions** — functions that depend only on their arguments and produce no side effects
2. **Group by concern** — telemetry, blocking, reconciliation, dispatch, retry, polling
3. **Extract to modules** — each module exports pure functions with clear `@spec`
4. **GenServer delegates** — `handle_info` and `handle_call` become thin dispatchers
5. **State transitions as data** — extracted modules return action descriptions, GenServer applies them

### Before/After Line Count Estimate

| Module | Before | After |
|---|---|---|
| `orchestrator.ex` | 1921 | ~450 |
| `orchestrator/codex_telemetry.ex` | — | ~250 |
| `orchestrator/blocker_detector.ex` | — | ~100 |
| `orchestrator/reconciler.ex` | — | ~230 |
| `orchestrator/dispatcher.ex` | — | ~220 |
| `orchestrator/retry_manager.ex` | — | ~200 |
| `orchestrator/poller.ex` | — | ~80 |
| **Total** | 1921 | ~1530 |

The total line count increases (~390 lines) because each module needs `@moduledoc`, `@spec`, module boundaries, and the GenServer shell retains all `handle_info`/`handle_call` clauses. But each individual file stays well under 800 lines.

### Extraction Order Rationale

1. **CodexTelemetry first** — it is the most self-contained (pure token math), touches no other extraction target, and has the clearest input/output boundary.
2. **BlockerDetector second** — pure predicates, no state mutation, trivially testable.
3. **Reconciler third** — the largest and most complex extraction, but its output is a set of state transitions that the GenServer applies.
4. **Dispatcher fourth** — depends on state shape established by Reconciler.
5. **RetryManager fifth** — interacts with Dispatcher (needs `dispatch_slots_available?`), but the timer management is self-contained.
6. **Poller last** — smallest, simplest, no dependencies on other extractions.

---

## 4. Phase 2-5 Architecture Overview

### Phase 2: TypeScript Runner Port (ZEN-19 to ZEN-22)

**Goal:** Port the runner abstraction to TypeScript for a Node.js-based alternative.

**Dependency chain:**
- Phase 1 runner behaviour contract defines the interface
- TypeScript implementation mirrors Elixir runner but uses `child_process.spawn`
- Config parsing in TypeScript reads same `WORKFLOW.md` format

**Key risk:** TypeScript and Elixir runners must produce identical result shapes.

### Phase 3: PR Creation + Review Loop (ZEN-23 to ZEN-25)

**Goal:** After runner completes, auto-create GitHub PR and manage review feedback loop.

**Dependency chain:**
- Phase 1 artifact store provides the diff/changes
- PR creation uses GitHub API (new dependency)
- Review loop re-invokes runner with reviewer feedback as continuation prompt

**Key risk:** Review loop state management (how many rework cycles, when to stop).

### Phase 4: Multi-Agent Orchestration (ZEN-26 to ZEN-28)

**Goal:** Multiple agents working on different issues concurrently with conflict resolution.

**Dependency chain:**
- Phase 1 orchestrator extraction provides clean dispatch/reconcile boundaries
- Git conflict resolution strategy needed
- Shared resource locking (e.g., same file modified by two agents)

**Key risk:** Git merge conflicts, resource contention.

### Phase 5: Production Hardening (ZEN-29 to ZEN-31)

**Goal:** Observability, alerting, graceful degradation, operational tooling.

**Dependency chain:**
- Phase 1 telemetry extraction provides the metrics surface
- Prometheus/metrics export
- Health check endpoints
- Graceful shutdown hooks

**Key risk:** Operational complexity, monitoring gaps.

---

## 5. Risk Assessment

| Step | Risk Level | Primary Risk | Mitigation |
|---|---|---|---|
| ZEN-12 Audit | Negligible | None (read-only) | N/A |
| ZEN-13 Run Locally | Low | Codex CLI not installed | Expected; validates polling works |
| ZEN-14 Runner Behaviour | Medium | Config backward compatibility | Test with existing WORKFLOW.md |
| ZEN-15 Claude Runner | **HIGH** | CLI argument format, `--output-format json` schema | Prototype early, test against real CLI |
| ZEN-16 WORKFLOW.md | Medium | AgentRunner regression | Preserve all existing test behavior |
| ZEN-17 Artifacts | Low | Path traversal, size limits | Explicit validation, security tests |
| Orchestrator Extraction | **HIGH** | State machine semantics break | Extract one module at a time, full tests after each |
| ZEN-18 E2E MVP | Medium | External dependencies (CLI, API) | Document failures, iterate |

### Top 3 Risks Across Phase 1

1. **Claude CLI `--output-format json` exact schema is unverified.** The implementation assumes `{"result": "text", "session_id": "..."}` but the actual schema may differ. Mitigation: prototype early (Step 3), verify against real CLI before building parser.

2. **Orchestrator extraction breaks state machine.** The orchestrator has complex state transitions (running → blocked → retry → dispatch) with subtle ordering dependencies. Mitigation: extract one module at a time, run full test suite after each, keep GenServer as single source of truth.

3. **AgentRunner refactoring breaks Codex path.** The refactoring from hardcoded AppServer to Runner.adapter() must preserve all existing semantics. Mitigation: existing tests cover the Codex path; run them after every change.

---

## 6. Testing Strategy

### Unit Tests

| Module | Test File | Coverage Target |
|---|---|---|
| `Runner` | `test/symphony_elixir/runner_test.exs` | adapter/0 selection logic |
| `Codex.Runner` | `test/symphony_elixir/codex/runner_test.exs` | All 4 callbacks (mock AppServer) |
| `Claude.Runner` | `test/symphony_elixir/claude/runner_test.exs` | Port lifecycle, timeout, crash |
| `Claude.JsonParser` | `test/symphony_elixir/claude/json_parser_test.exs` | Valid/invalid/missing JSON |
| `ArtifactStore` | `test/symphony_elixir/artifact_store_test.exs` | Path validation, size limits, file/comment types |
| `Config.Schema` | Existing + extend | Runner section parsing, backward compat |
| `Orchestrator.CodexTelemetry` | `test/symphony_elixir/orchestrator/codex_telemetry_test.exs` | Token delta math, rate limits |
| `Orchestrator.BlockerDetector` | `test/symphony_elixir/orchestrator/blocker_detector_test.exs` | All blocker predicates |
| `Orchestrator.Reconciler` | `test/symphony_elixir/orchestrator/reconciler_test.exs` | State transitions |
| `Orchestrator.Dispatcher` | `test/symphony_elixir/orchestrator/dispatcher_test.exs` | Issue selection, worker host |
| `Orchestrator.RetryManager` | `test/symphony_elixir/orchestrator/retry_manager_test.exs` | Retry delays, backoff |
| `Orchestrator.Poller` | `test/symphony_elixir/orchestrator/poller_test.exs` | Tick scheduling |

### Integration Tests

| Scenario | Test File |
|---|---|
| AgentRunner + Codex.Runner | Extend `test/symphony_elixir/core_test.exs` |
| AgentRunner + Claude.Runner (mock CLI) | `test/symphony_elixir/claude/integration_test.exs` |
| Config loading with runner section | Extend `test/symphony_elixir/workspace_and_config_test.exs` |
| Full orchestrator flow with mock runner | Extend `test/symphony_elixir/orchestrator_status_test.exs` |

### E2E Tests

| Scenario | Approach |
|---|---|
| Codex end-to-end | Existing `test/symphony_elixir/live_e2e_test.exs` |
| Claude end-to-end | Manual (ZEN-18) + scripted with mock CLI |

### Test Isolation

- Each test uses unique workspace directory via `tmp_dir`
- Port processes cleaned up in `on_exit` callbacks
- Config mocked per test (no shared state)
- Linear API calls mocked via `Mox` or test doubles

### Quality Gates

```bash
mix test                    # All tests pass
mix specs.check             # All public functions have @spec
mix credo --strict          # No lint warnings
mix dialyzer                # No type errors
```

Target: `make all` passes after each step.

---

## Appendix: Dependency Graph

```
ZEN-12 (Audit)
    |
    v
ZEN-13 (Run Locally)
    |
    v
ZEN-14 (Runner Behaviour) -----------------------------------+
    |                                                         |
    v                                                         |
ZEN-15 (Claude.Runner)                                        |
    |                                                         |
    v                                                         |
ZEN-16 (WORKFLOW.md + AgentRunner) <--------------------------+
    |
    +---> ZEN-17 (Artifacts)
    |
    +---> Orchestrator Extraction (parallel)
    |
    v
ZEN-18 (E2E MVP)
```

Steps 17 and Orchestrator Extraction can proceed in parallel once Step 16 is complete.
