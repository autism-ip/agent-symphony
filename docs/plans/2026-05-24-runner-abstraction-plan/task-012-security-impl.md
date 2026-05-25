# Task 012: Security Validation Implementation

**type:** impl
**depends-on:** ["011"]

## BDD Scenarios

Same as Task 011.

## What to Implement

1. In `Config.Schema`, add validation for `runner.claude.command`:
   - Reject if contains shell metacharacters: `;`, `|`, `&`, `` ` ``, `$`, `(`, `)`, `{`, `}`
   - Return `{:error, :invalid_command}` on validation failure

2. Create `lib/symphony_elixir/artifact_store.ex`:
   - `save(workspace, artifacts)` function
   - Validate path: reject if contains `..` or is absolute path → `{:error, {:invalid_artifact_path, path}}`
   - Validate extension: reject `.sh`, `.exe`, `.bat`, `.cmd` → `{:error, {:forbidden_file_type, ext}}`
   - Validate size: reject content > 1MB → `{:error, {:artifact_too_large, max_size}}`
   - On success: write to `workspace/.symphony/artifacts/<path>`

## Files to Create/Modify

- `lib/symphony_elixir/config/schema.ex` (add command validation)
- `lib/symphony_elixir/artifact_store.ex` (new)

## Verification

```bash
cd elixir && mix test test/symphony_elixir/security_test.exs
```

All tests green.
