# Task 013: Artifact Persistence Test

**type:** test
**depends-on:** []

## BDD Scenarios

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

## What to Create

Create test file `test/symphony_elixir/artifact_store_test.exs`:

1. Test `:file` artifact → writes to `workspace/.symphony/artifacts/<path>`
2. Test `:comment` artifact → calls `Tracker.create_comment(issue_id, content)`
3. Test nested path creation (e.g., `src/lib/main.ex`)
4. Test mixed artifact list (file + comment in same batch)

## Files to Create

- `test/symphony_elixir/artifact_store_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/artifact_store_test.exs
```
