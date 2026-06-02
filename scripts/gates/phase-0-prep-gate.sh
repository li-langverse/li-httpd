#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_file() {
  local p="$1"
  if [[ ! -f "$p" ]]; then
    echo "missing required file: $p" >&2
    exit 1
  fi
}

require_dir() {
  local p="$1"
  if [[ ! -d "$p" ]]; then
    echo "missing required directory: $p" >&2
    exit 1
  fi
}

require_file "$repo_root/data/li-toml-config-loop/state.json"
require_file "$repo_root/data/li-toml-config-loop/iteration-log.md"
require_file "$repo_root/docs/plans/2026-06-li-toml-config-migration.md"

require_dir "$repo_root/li-tests/config/good"

good_count="$(ls -1 "$repo_root/li-tests/config/good"/*.toml 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$good_count" -lt 1 ]]; then
  echo "expected at least one .toml file in li-tests/config/good/" >&2
  exit 1
fi

echo "phase-0-prep gate: OK"

