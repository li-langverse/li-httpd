#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
    echo "missing required dir: $p" >&2
    exit 1
  fi
}

require_nonempty_glob() {
  local pattern="$1"
  shopt -s nullglob
  local matches=($pattern)
  shopt -u nullglob
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "no files matched: $pattern" >&2
    exit 1
  fi
}

require_file "$ROOT/docs/plans/2026-06-li-toml-config-migration.md"
require_file "$ROOT/data/li-toml-config-loop/state.json"
require_file "$ROOT/data/li-toml-config-loop/iteration-log.md"

require_dir "$ROOT/li-tests/config/good"
require_dir "$ROOT/li-tests/config/bad"
require_nonempty_glob "$ROOT/li-tests/config/good/*.toml"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found (needed for later phases, allowed in phase-0 only as tool)" >&2
  exit 1
fi

echo "phase-0-prep gate: OK"

