# .github/
> L2 | 父级: ../CLAUDE.md

成员清单
pull_request_template.md: PR 正文契约，被 ci-cd-gate.yml 的 validate-pr-description 检查消费。
workflows/: GitHub Actions workflow 目录，当前由 ci-cd-gate.yml 统一承载门禁。
scripts/: GitHub 自动化脚本目录，当前提供 CI/CD workflow 合约测试。
media/: README 演示素材目录，只承载展示资产，不参与门禁执行。

<architecture>
CI/CD 门禁保持一个入口: ci-cd-gate.yml。
ci-cd-contract 先验证 workflow 自身结构；make-all 与 validate-pr-description 保留为独立 job 名称，兼容已有 required check；ci-cd-gate 是新的聚合 required check。
</architecture>

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
