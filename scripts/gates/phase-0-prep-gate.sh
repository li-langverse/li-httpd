#!/usr/bin/env bash
# Phase 0: li-toml repo scaffold + config corpus in li-httpd + plan present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "phase-0-prep-gate: $*" >&2; exit 1; }

test -f "$ROOT/docs/plans/2026-06-li-toml-config-migration.md" || fail "missing migration plan"
test -d "$ROOT/li-tests/config/good" || test -d "$ROOT/../lic-pure-https/li-tests/config_desugar/good" || \
  fail "copy config_desugar corpus to li-tests/config/{good,reject}"

# li-toml sibling or workspace clone
LI_TOML="${LI_TOML_ROOT:-$ROOT/../li-toml}"
if [[ ! -f "$LI_TOML/li.toml" ]]; then
  fail "create li-toml repo at $LI_TOML (see plan phase 0)"
fi

echo "phase-0-prep-gate: OK"
