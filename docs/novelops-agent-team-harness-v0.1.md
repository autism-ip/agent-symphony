# NovelOps Agent Team Harness v0.1

## 1. System positioning

NovelOps is a front/back separated Agent Team Harness for AI-assisted web-novel production.

The MVP converts Douyin public hotspots into structured web-novel assets:

1. Hotspot extraction.
2. Hotspot normalization.
3. Hit-pattern and novelization analysis.
4. Title and cover-plan generation.
5. Book creation and Agent Team initialization.
6. MiniBible creation.
7. Chapter brief creation.
8. Chapter draft generation.
9. AI review.
10. Human approval, revision, or final lock.

## 2. Architecture

```text
Vercel Frontend
  ↓ HTTP API
Local Persistent Backend / Harness
  ↓
Feishu Bitable as the only database
  ↓
External tools: OpenCLI, LLM APIs, optional image APIs
```

### Frontend

- Next.js on Vercel.
- Control and observability only.
- Does not call LLMs, OpenCLI, or Feishu secrets directly.

### Backend

- Local persistent FastAPI service.
- Runs API server and worker loop.
- Owns Agent Team Harness, pipeline orchestration, OpenCLI execution, LLM calls, Feishu repository layer, approval logic, review logic, and revision logic.

### Database

- Feishu Bitable only for v0.1.
- Stores tasks, states, agent memory, artifacts, approvals, versions, review reports, and snapshots.

## 3. Backend module layout

```text
app/
  main.py
  api/routes/
  harness/
    orchestrator.py
    worker_loop.py
    step_executor.py
    dependency_resolver.py
    state_machine.py
    approval_gate.py
    retry_policy.py
    lineage.py
    task_claim.py
  agents/
    base.py
    registry.py
    runtime.py
    roles/
  tools/
    opencli_runner.py
    llm_client.py
    image_client.py
  feishu/
    client.py
    table_map.py
    repositories/
  schemas/
  prompts/
opencli-plugin/
  douyin/hotspots.ts
```

## 4. Frontend module layout

```text
app/
  dashboard/
  pipelines/
  agents/
  hotspots/
  analyses/
  title-cover/
  books/[bookId]/
  review/
  settings/
src/
  api/
  components/
  types/
```

## 5. Agent Team

### System agents

- `OrchestratorAgent`
- `TaskManagerAgent`
- `SchemaGuardAgent`
- `LoggerAgent`
- `ApprovalAgent`
- `StateSyncAgent`

### Data and analysis agents

- `DouyinHotspotCrawlerAgent`
- `HotspotNormalizeAgent`
- `HitPatternAnalysisAgent`
- `NovelizationAnalysisAgent`
- `RiskScreenAgent`

### Creation agents

- `TitleAgent`
- `CoverAgent`
- `StorySetupAgent`
- `EditorAgent`
- `WorldviewAgent`
- `MacroEnvironmentAgent`
- `PowerSystemAgent`
- `CharacterAgent`
- `ForeshadowingAgent`
- `ChapterPlannerAgent`
- `ChapterWriterAgent`
- `StyleAgent`
- `AntiAIFlavorAgent`
- `ReviewAgent`
- `RewriteAgent`

## 6. Feishu Bitable tables

1. `Agents`
2. `AgentStates`
3. `AgentRuns`
4. `PipelineRuns`
5. `StepRuns`
6. `Hotspots`
7. `HotspotAnalyses`
8. `TitleCandidates`
9. `CoverPlans`
10. `Books`
11. `ChapterBriefs`
12. `ChapterVersions`
13. `ReviewReports`
14. `RevisionTasks`
15. `AgentTeamSnapshots`
16. `ApprovalEvents`

## 7. v0.1 pipeline

```text
fetch_douyin_hotspots
normalize_hotspots
analyze_hit_pattern
analyze_novelization
risk_screen_analysis
approval_analysis
generate_titles
generate_cover_plans
approval_title_cover
create_book
init_book_agent_team
generate_mini_bible
approval_mini_bible
generate_chapter_briefs
approval_chapter_briefs
create_agent_team_snapshot
generate_chapter_draft
style_polish
anti_ai_flavor_rewrite
review_chapter
human_review
revise_or_lock_final
```

## 8. API surface

### System

- `GET /api/system/health`
- `GET /api/system/status`
- `GET /api/system/config`

### Pipelines

- `POST /api/pipelines`
- `GET /api/pipelines`
- `GET /api/pipelines/{pipeline_run_id}`
- `POST /api/pipelines/{pipeline_run_id}/pause`
- `POST /api/pipelines/{pipeline_run_id}/resume`
- `POST /api/pipelines/{pipeline_run_id}/retry`
- `POST /api/pipelines/{pipeline_run_id}/advance`

### Agents

- `GET /api/agents`
- `GET /api/agents/{agent_id}`
- `GET /api/agents/states`
- `GET /api/agents/runs`
- `GET /api/books/{book_id}/agent-team`
- `POST /api/agents/{agent_id}/run`

### Hotspots and analysis

- `POST /api/hotspots/fetch-douyin`
- `GET /api/hotspots`
- `GET /api/hotspots/{hotspot_id}`
- `POST /api/hotspots/{hotspot_id}/analyze`
- `GET /api/analyses`
- `POST /api/analyses/{analysis_id}/approve`
- `POST /api/analyses/{analysis_id}/reject`
- `POST /api/analyses/{analysis_id}/revise`

### Books and chapters

- `POST /api/books`
- `GET /api/books`
- `GET /api/books/{book_id}`
- `POST /api/books/{book_id}/init-agent-team`
- `POST /api/books/{book_id}/generate-mini-bible`
- `POST /api/books/{book_id}/generate-briefs`
- `POST /api/books/{book_id}/generate-chapter`

### Reviews and revisions

- `GET /api/reviews`
- `POST /api/reviews/{review_id}/approve`
- `POST /api/reviews/{review_id}/revise`
- `POST /api/reviews/{review_id}/reject`
- `POST /api/reviews/{review_id}/lock-final`
- `POST /api/revisions`
- `POST /api/revisions/{revision_task_id}/run`

## 9. Worker loop

The backend runs a persistent worker loop:

1. Find next runnable `StepRun` from Feishu.
2. Claim step using `lease_owner` and `lease_until`.
3. Resolve dependencies.
4. Load assigned Agent, input artifacts, and Agent state.
5. Execute Agent.
6. Validate output schema.
7. Persist output artifact.
8. Update Agent state.
9. Record `AgentRun`.
10. Update `StepRun` and `PipelineRun`.

## 10. Stability rules

- Every step must be idempotent.
- Every Agent output must pass schema validation.
- Key gates require human approval.
- Failed steps are retryable.
- Chapter drafts are versioned; no overwrite.
- OpenCLI only extracts public Douyin hotspot data.
- Frontend never stores API secrets.

## 11. v0.1 acceptance criteria

- Vercel frontend connects to local backend.
- Backend reads/writes Feishu tables.
- Pipeline can be created, paused, resumed, retried, and observed.
- Douyin hotspots can be extracted and stored.
- Hotspot analysis produces structured results.
- Title and cover plan generation works.
- Book Agent Team states are initialized.
- MiniBible and chapter brief generation works.
- First 1–3 chapter drafts can be generated.
- Review report, revision task, and final lock flow works.
