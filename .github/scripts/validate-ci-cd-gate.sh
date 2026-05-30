#!/usr/bin/env bash
# [INPUT]: 依赖 .github/workflows/ci-cd-gate.yml 与仓库根路径
# [OUTPUT]: 对外提供 CI/CD workflow 合约校验，失败时返回非零状态
# [POS]: .github/scripts 的门禁测试脚本，被 ci-cd-contract job 调用
# [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md

set -euo pipefail

workflow=".github/workflows/ci-cd-gate.yml"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "::error file=${path}::required file is missing"
    exit 1
  fi
}

require_text() {
  local pattern="$1"
  local path="$2"
  local message="$3"

  if ! grep -Eq "$pattern" "$path"; then
    echo "::error file=${path}::${message}"
    exit 1
  fi
}

reject_file() {
  local path="$1"

  if [[ -e "$path" ]]; then
    echo "::error file=${path}::legacy split workflow must not exist"
    exit 1
  fi
}

require_file "$workflow"
reject_file ".github/workflows/make-all.yml"
reject_file ".github/workflows/pr-description-lint.yml"

require_text '^name: ci-cd-gate$' "$workflow" "workflow name must be ci-cd-gate"
require_text '^  validate-pr-description:$' "$workflow" "PR body gate job is missing"
require_text '^  make-all:$' "$workflow" "make all gate job is missing"
require_text '^  ci-cd-gate:$' "$workflow" "aggregate gate job is missing"
require_text '      - validate-pr-description' "$workflow" "aggregate gate must depend on PR body gate"
require_text '      - make-all' "$workflow" "aggregate gate must depend on make all"
require_text 'run: make all' "$workflow" "workflow must execute the Makefile quality gate"
require_text 'mix pr_body.check --file /tmp/pr_body.md' "$workflow" "workflow must validate PR body format"
require_text 'persist-credentials: false' "$workflow" "checkout must not persist credentials"
require_text 'actions/checkout@[0-9a-f]{40}' "$workflow" "checkout action must be pinned to a SHA"
require_text 'jdx/mise-action@[0-9a-f]{40}' "$workflow" "mise action must be pinned to a SHA"
require_text 'actions/cache@[0-9a-f]{40}' "$workflow" "cache action must be pinned to a SHA"

echo "CI/CD workflow contract passed"
