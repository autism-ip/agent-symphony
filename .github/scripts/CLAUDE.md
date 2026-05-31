# .github/scripts/
> L2 | 父级: ../CLAUDE.md

成员清单
validate-ci-cd-gate.sh: Bash 合约测试，校验 CI/CD workflow 入口、job 拓扑、关键命令与 action SHA pinning。

<architecture>
脚本只验证 GitHub Actions 结构契约，不替代 Elixir 的 make all；业务质量仍由 elixir/Makefile 统一裁决。
</architecture>

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
