#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { echo "phase-c-retire-c-gate: $*" >&2; exit 1; }

test -f "$ROOT/data/li-toml-config-loop/state.json" || fail "missing state.json"

python3 - <<'PY'
import json, pathlib, sys
state = json.loads(pathlib.Path("data/li-toml-config-loop/state.json").read_text(encoding="utf-8"))
phase = str(state.get("phase", ""))
if phase != "phase-c-retire-c":
    print(f"phase-c-retire-c-gate: state.json phase={phase!r} (want 'phase-c-retire-c')", file=sys.stderr)
    raise SystemExit(1)
PY

test -f "$ROOT/docs/config-c-loader-freeze.md" || fail "missing docs/config-c-loader-freeze.md"
test -f "$ROOT/data/c-runtime-config-keys.freeze" || fail "missing freeze manifest"
test -f "$ROOT/li-tests/corpus/config/apply.li" || fail "missing li-tests/corpus/config/apply.li"

bash "$ROOT/scripts/lint-frozen-c-config-keys.sh"
bash "$ROOT/scripts/config-parity-check.sh"

echo "phase-c-retire-c-gate: OK"
