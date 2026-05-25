# Task 009: Claude JSON Parser Test

**type:** test
**depends-on:** []

## BDD Scenarios

### Scenario: 解析 --output-format json 原生输出
```gherkin
Given Claude CLI 输出为
  """
  {"result":"Implemented factorial in src/fact.ex","session_id":"sess_abc","total_cost_usd":0.01}
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :success, artifacts: [%{type: :text, content: "Implemented factorial in src/fact.ex"}]}}
```

### Scenario: 解析错误类型 JSON
```gherkin
Given Claude CLI 输出为
  """
  {"error":"Rate limit exceeded"}
  """
When 调用 Claude.Runner.parse_result
Then 返回 {:ok, %{status: :error, artifacts: [%{type: :text, content: "Rate limit exceeded"}]}}
```

### Scenario: JSON 解码失败
```gherkin
Given Claude CLI 输出为无效 JSON "not json at all"
When 调用 Claude.Runner.parse_result
Then 返回 {:error, {:json_decode, <jason_reason>}}
```

## What to Create

Create test file `test/symphony_elixir/claude/json_parser_test.exs`:

1. Parse valid JSON with `"result"` key → `{:ok, %{status: :success, artifacts: [...]}}`
2. Parse valid JSON with `"error"` key → `{:ok, %{status: :error, artifacts: [...]}}`
3. Parse invalid JSON → `{:error, {:json_decode, _}}`
4. Parse JSON with extra fields (session_id, total_cost_usd) → only `result` extracted
5. Parse empty result → handle gracefully

## Files to Create

- `test/symphony_elixir/claude/json_parser_test.exs`

## Verification

```bash
cd elixir && mix test test/symphony_elixir/claude/json_parser_test.exs
```
