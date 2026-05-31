# claude/
> L2 | 父级: /Users/zen/Desktop/project/agent-symphony/elixir/CLAUDE.md

成员清单
json_parser.ex: 解析 Claude CLI 的 json/stream-json stdout，输出标准 Runner result map，依赖 Jason。
runner.ex: Claude Code CLI runner，per-turn 调用 `/bin/sh` 包装的 `claude`，关闭 stdin、禁用 hooks、提取 session_id。

职责边界
claude/ 只负责 Claude CLI 适配：构造命令、执行 turn、解析输出；编排、workspace 生命周期和 issue 状态由上层 SymphonyElixir 模块持有。

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
