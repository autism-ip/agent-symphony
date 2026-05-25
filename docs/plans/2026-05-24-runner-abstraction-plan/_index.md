# Runner Abstraction — Implementation Plan

> Design: [`docs/plans/2026-05-24-runner-abstraction-design/`](../2026-05-24-runner-abstraction-design/)
> Created: 2026-05-25
> Status: Ready for Execution

---

## Context

AgentSymphony 当前仅支持 Codex 作为 AI agent runner。`AgentRunner` 直接硬编码调用 `Codex.AppServer`。随着 Claude Code CLI 的引入，需要可插拔的 runner 抽象层。

**Current State vs Target State:**

| Dimension | Current | Target |
|---|---|---|
| Runner 接口 | 无抽象，直接调用 `Codex.AppServer` | `Runner` behaviour + `adapter/0` 动态派发 |
| Claude 支持 | 不存在 | `Claude.Runner` via `System.cmd` per-turn |
| 配置 | 顶层 `codex` 字段 | `runner.type` 嵌入式 schema + 向后兼容迁移 |
| JSON 解析 | 不存在 | `Claude.JsonParser` 解析 `--output-format json` |
| 产物持久化 | 不存在 | `ArtifactStore` 写入 workspace + Linear comment |
| 指标 | `codex_totals` / `codex_rate_limits` | `runner_totals` / `runner_rate_limits` + 旧字段别名 |
| 测试覆盖 | 无 runner 测试 | 20 tasks, 25 BDD scenarios, Red-Green workflow |

**Implementation Status:**
- R1 (Runner Behaviour): IMPLEMENTED — `runner.ex` exists with 4 callbacks + `adapter/0`
- R2 (Codex.Runner): IMPLEMENTED — `codex/runner.ex` exists, delegates to AppServer
- R3-R8 (Claude, Config, Artifacts, Metrics, E2E): ZERO — all tasks are new implementation

---

## Execution Plan

```yaml
tasks:
  - id: "001"
    subject: "Runner Behaviour Test"
    slug: "runner-behaviour-test"
    type: "test"
    depends-on: []
  - id: "002"
    subject: "Runner Behaviour Implementation"
    slug: "runner-behaviour-impl"
    type: "impl"
    depends-on: ["001"]
  - id: "003"
    subject: "Codex.Runner Verification Test"
    slug: "codex-runner-test"
    type: "test"
    depends-on: ["001"]
  - id: "004"
    subject: "Codex.Runner Implementation"
    slug: "codex-runner-impl"
    type: "impl"
    depends-on: ["003"]
  - id: "005"
    subject: "Config Schema Test"
    slug: "config-schema-test"
    type: "test"
    depends-on: []
  - id: "006"
    subject: "Config Schema Implementation"
    slug: "config-schema-impl"
    type: "impl"
    depends-on: ["005"]
  - id: "007"
    subject: "Claude.Runner Test"
    slug: "claude-runner-test"
    type: "test"
    depends-on: ["001", "005"]
  - id: "008"
    subject: "Claude.Runner Implementation"
    slug: "claude-runner-impl"
    type: "impl"
    depends-on: ["006", "007"]
  - id: "009"
    subject: "Claude JSON Parser Test"
    slug: "json-parser-test"
    type: "test"
    depends-on: []
  - id: "010"
    subject: "Claude JSON Parser Implementation"
    slug: "json-parser-impl"
    type: "impl"
    depends-on: ["009"]
  - id: "011"
    subject: "Security Validation Test"
    slug: "security-test"
    type: "test"
    depends-on: []
  - id: "012"
    subject: "Security Validation Implementation"
    slug: "security-impl"
    type: "impl"
    depends-on: ["011"]
  - id: "013"
    subject: "Artifact Persistence Test"
    slug: "artifact-store-test"
    type: "test"
    depends-on: []
  - id: "014"
    subject: "Artifact Persistence Implementation"
    slug: "artifact-store-impl"
    type: "impl"
    depends-on: ["012", "013"]
  - id: "015"
    subject: "AgentRunner Refactor Test"
    slug: "agentrunner-refactor-test"
    type: "test"
    depends-on: ["001", "003", "007"]
  - id: "016"
    subject: "AgentRunner Refactor Implementation"
    slug: "agentrunner-refactor-impl"
    type: "impl"
    depends-on: ["008", "015"]
  - id: "017"
    subject: "Metrics Generalization Test"
    slug: "metrics-test"
    type: "test"
    depends-on: []
  - id: "018"
    subject: "Metrics Generalization Implementation"
    slug: "metrics-impl"
    type: "impl"
    depends-on: ["017"]
  - id: "019"
    subject: "E2E Test"
    slug: "e2e-test"
    type: "test"
    depends-on: ["002", "004", "008", "010", "014", "016"]
  - id: "020"
    subject: "E2E Integration"
    slug: "e2e-impl"
    type: "impl"
    depends-on: ["019"]
```

---

## Task File References

- [Task 001: Runner Behaviour Test](./task-001-runner-behaviour-test.md)
- [Task 002: Runner Behaviour Implementation](./task-002-runner-behaviour-impl.md)
- [Task 003: Codex.Runner Verification Test](./task-003-codex-runner-test.md)
- [Task 004: Codex.Runner Implementation](./task-004-codex-runner-impl.md)
- [Task 005: Config Schema Test](./task-005-config-schema-test.md)
- [Task 006: Config Schema Implementation](./task-006-config-schema-impl.md)
- [Task 007: Claude.Runner Test](./task-007-claude-runner-test.md)
- [Task 008: Claude.Runner Implementation](./task-008-claude-runner-impl.md)
- [Task 009: Claude JSON Parser Test](./task-009-json-parser-test.md)
- [Task 010: Claude JSON Parser Implementation](./task-010-json-parser-impl.md)
- [Task 011: Security Validation Test](./task-011-security-test.md)
- [Task 012: Security Validation Implementation](./task-012-security-impl.md)
- [Task 013: Artifact Persistence Test](./task-013-artifact-store-test.md)
- [Task 014: Artifact Persistence Implementation](./task-014-artifact-store-impl.md)
- [Task 015: AgentRunner Refactor Test](./task-015-agentrunner-refactor-test.md)
- [Task 016: AgentRunner Refactor Implementation](./task-016-agentrunner-refactor-impl.md)
- [Task 017: Metrics Generalization Test](./task-017-metrics-test.md)
- [Task 018: Metrics Generalization Implementation](./task-018-metrics-impl.md)
- [Task 019: E2E Test](./task-019-e2e-test.md)
- [Task 020: E2E Integration](./task-020-e2e-impl.md)

---

## BDD Coverage

| Feature | BDD Scenarios | Tasks | Status |
|---|---|---|---|
| Runner Behaviour | 3 (adapter codex/claude/fallback) | 001, 002 | R1 done — verify only |
| Codex.Runner | 2 (lifecycle, AppServer integration) | 003, 004 | R2 done — verify only |
| Claude.Runner | 8 (init, System.cmd, success JSON, error JSON, decode failure, non-zero exit, timeout, no-op stop) | 007, 008, 009, 010 | New |
| Security | 4 (command injection, path traversal, executable, size limit) | 011, 012 | New |
| Performance | 1 (large output timeout protection) | 007 | Covered by timeout test |
| Artifact Persistence | 2 (file write, comment upload) | 013, 014 | New |
| Config Schema | 2 (old config migration, new config parse) | 005, 006 | New |
| Metrics | 1 (field renaming) | 017, 018 | New |
| E2E | 2 (Codex flow, Claude flow) | 019, 020 | New |
| **Total** | **25** | **20** | |

---

## Dependency Chain

```
001 (behaviour test) ──→ 002 (behaviour impl)
  ├──→ 003 (codex test) ──→ 004 (codex impl)
  ├──→ 007 (claude test) ──→ 008 (claude impl) ←── 006 (config impl) ←── 005 (config test)
  └──→ 015 (agentrunner test) ──→ 016 (agentrunner impl) ←── 008

009 (json parser test) ──→ 010 (json parser impl)

011 (security test) ──→ 012 (security impl) ──┐
013 (artifact test) ─────────────────────────→ 014 (artifact impl)

017 (metrics test) ──→ 018 (metrics impl)

019 (e2e test) ←── 002, 004, 008, 010, 014, 016
  └──→ 020 (e2e impl)
```

**Parallelizable tracks:**
- Track A: Runner Behaviour (001→002) → Codex.Runner (003→004)
- Track B: Config Schema (005→006) → Claude.Runner (007→008) → AgentRunner (015→016)
- Track C: JSON Parser (009→010) — independent
- Track D: Security (011→012) + Artifact Test (013) → Artifact Impl (014 ← 012, 013)
- Track E: Metrics (017→018) — independent
- Track F: E2E (019→020) — depends on all above

---

## Execution Handoff

Three execution paths available:

### Path 1: Orchestrated Execution (Recommended)
Use `/superpowers:executing-plans` with this plan directory.

### Path 2: Direct Agent Team
Spawn parallel agents for each track (A-F). Each agent works on its track independently.

### Path 3: Manual/Serial
Execute tasks in order: 001→002→003→004→005→006→007→008→009→010→011→012→013→014→015→016→017→018→019→020
