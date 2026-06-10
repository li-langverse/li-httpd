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
state = json.loads(pathlib.Path("data/li-toml-config-loop/state.json").read_text(encoding="utf-8"))
phase = str(state.get("phase", ""))
allowed = ("phase-0-prep", "phase-d-done")
if phase not in allowed:
    print(f"phase-0-prep-gate: state.json phase={phase!r} (want one of {allowed})", file=sys.stderr)
    raise SystemExit(1)
PY

if ! ls "$ROOT/li-tests/config/good/"*.toml >/dev/null 2>&1; then
  echo "phase-0-prep-gate: expected at least one *.toml under li-tests/config/good/" >&2
  exit 1
fi

LI_TOML="${LI_TOML_ROOT:-$ROOT/../li-toml}"
if [[ -f "$LI_TOML/li.toml" ]]; then
  req_file "$LI_TOML/li.toml"
  req_file "$LI_TOML/li-toolchain.toml"
  req_file "$LI_TOML/src/lib.li"
fi

BENCH="${BENCHMARKS_ROOT:-$ROOT/../benchmarks}"
if [[ -d "$BENCH/harness" ]]; then
  python3 - "$BENCH" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
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

echo "phase-0-prep-gate: OK"
