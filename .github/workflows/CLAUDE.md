# .github/workflows/
> L2 | 父级: ../CLAUDE.md

成员清单
ci-cd-gate.yml: GitHub Actions 主门禁，触发 PR 与 main push，执行 workflow 合约测试、PR 正文校验、make all 与聚合结果检查。

<architecture>
一个 workflow 承载全部 required check 候选，避免分散文件造成分支保护漂移。
最终 required check 应设置为 ci-cd-gate；兼容期可同时保留 make-all 与 validate-pr-description。
</architecture>

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
