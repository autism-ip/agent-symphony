# Task 011: Security Validation Test

**type:** test
**depends-on:** []

## BDD Scenarios

### Scenario: 阻止命令注入
```gherkin
Given 配置 claude.command 包含 shell 元字符（如 ";", "|", "&"）
When 加载配置
Then Config.Schema 验证失败
And 返回 {:error, :invalid_command}
```

### Scenario: 阻止路径遍历写入 artifact
```gherkin
Given 解析结果包含 artifact.path = "../../../etc/passwd"
When 调用 ArtifactStore.save
Then 返回 {:error, {:invalid_artifact_path, "../../../etc/passwd"}}
And 不写入任何文件
```

### Scenario: 阻止写入可执行文件
```gherkin
Given 解析结果包含 artifact.path = "script.sh"
When 调用 ArtifactStore.save
Then 返回 {:error, {:forbidden_file_type, ".sh"}}
```

### Scenario: Artifact 内容大小限制
```gherkin
Given 解析结果包含 artifact.content 大小超过 1MB
When 调用 ArtifactStore.save
Then 返回 {:error, {:artifact_too_large, 1_048_576}}
```

## What to Implement

Create test file `test/symphony_elixir/security_test.exs`:

1. Config validation: reject `command` with shell metacharacters (`;`, `|`, `&`, `` ` ``)
2. Path traversal: reject `artifact.path` containing `..`
3. Executable rejection: reject `.sh`, `.exe`, `.bat` file extensions
4. Size limit: reject content > 1MB (1_048_576 bytes)

## Files to Create

- `test/symphony_elixir/security_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/security_test.exs
```
