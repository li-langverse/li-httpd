#!/usr/bin/env bash
# Cursor sessionStart — remind agents of mandatory gates.
set -euo pipefail
cat <<'EOF'
Li session: read ../roadmap/docs/ecosystem/engineering-standards.md and vision-and-roadmap.md first (north star: go-to ecosystem for HPC, scientific computing, and AI).
Strict gates: functionality, security, performance. std/** = 100% coverage; lip publish >= 80%.
Perf status: https://li-langverse.github.io/benchmarks/
PR-only: feature branch + PR; never push to main/dev; do not self-merge.
Release notes: CHANGELOG + docs/release-notes/ (skill write-li-release-notes) before every merge-worthy PR.
EOF
exit 0
