#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

req_file() {
  local p="$1"
  if [[ ! -f "$p" ]]; then
    echo "phase-0-prep-gate: missing file: $p" >&2
    exit 1
  fi
}

req_dir() {
  local p="$1"
  if [[ ! -d "$p" ]]; then
    echo "phase-0-prep-gate: missing dir: $p" >&2
    exit 1
  fi
}

req_file "$ROOT/docs/plans/2026-06-li-toml-config-migration.md"
req_file "$ROOT/data/li-toml-config-loop/state.json"
req_file "$ROOT/data/li-toml-config-loop/iteration-log.md"
req_dir "$ROOT/li-tests/config/good"

python3 - <<'PY'
import json, pathlib, sys
state_path = pathlib.Path("data/li-toml-config-loop/state.json")
state = json.loads(state_path.read_text(encoding="utf-8"))
phase = str(state.get("phase", ""))
if phase != "phase-0-prep":
    print(f"phase-0-prep-gate: state.json phase={phase!r} (want 'phase-0-prep')", file=sys.stderr)
    raise SystemExit(1)
PY

if ! ls "$ROOT/li-tests/config/good/"*.toml >/dev/null 2>&1; then
  echo "phase-0-prep-gate: expected at least one *.toml under li-tests/config/good/" >&2
  exit 1
fi

if [[ -d "$ROOT/../li-toml" ]]; then
  req_file "$ROOT/../li-toml/li.toml"
  req_file "$ROOT/../li-toml/li-toolchain.toml"
  req_file "$ROOT/../li-toml/src/lib.li"
fi

if [[ -d "$ROOT/../benchmarks" ]]; then
  python3 - <<'PY'
import pathlib, sys
root = pathlib.Path("../benchmarks")
needle = "LI_HTTPD_CONFIG_PIPELINE"
hits = []
for p in root.rglob("*.py"):
    try:
        if needle in p.read_text(encoding="utf-8", errors="ignore"):
            hits.append(str(p))
    except Exception:
        pass
if not hits:
    print("phase-0-prep-gate: benchmarks missing LI_HTTPD_CONFIG_PIPELINE wiring", file=sys.stderr)
    raise SystemExit(1)
PY
fi

echo "phase-0-prep-gate: ok"

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
