#!/usr/bin/env bash
# Phase D: harness defaults to Li pipeline; Python flatten deprecated for serve paths.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { echo "phase-d-done-gate: $*" >&2; exit 1; }

test -f "$ROOT/data/li-toml-config-loop/state.json" || fail "missing state.json"
test -f "$ROOT/docs/config-pipeline.md" || fail "missing docs/config-pipeline.md"

python3 - <<'PY'
import json, pathlib, sys
state = json.loads(pathlib.Path("data/li-toml-config-loop/state.json").read_text(encoding="utf-8"))
phase = str(state.get("phase", ""))
if phase != "phase-d-done":
    print(f"phase-d-done-gate: state.json phase={phase!r} (want 'phase-d-done')", file=sys.stderr)
    raise SystemExit(1)
PY

# When benchmarks sibling exists, default harness pipeline must be Li.
BENCH="${BENCHMARKS_ROOT:-$ROOT/../benchmarks}"
if [[ -d "$BENCH/harness" ]]; then
  python3 - "$BENCH" <<'PY'
import pathlib, sys
bench = pathlib.Path(sys.argv[1])
files = [
    bench / "harness/httpd_flatten.py",
    bench / "harness/http_bench_servers.py",
    bench / "harness/exploit_http.py",
]
for p in files:
    if not p.is_file():
        print(f"phase-d-done-gate: missing {p}", file=sys.stderr)
        raise SystemExit(1)
text = (bench / "harness/httpd_flatten.py").read_text(encoding="utf-8")
if 'LI_HTTPD_CONFIG_PIPELINE", "li")' not in text and 'get("LI_HTTPD_CONFIG_PIPELINE", "li")' not in text:
    print("phase-d-done-gate: harness default pipeline is not 'li'", file=sys.stderr)
    raise SystemExit(1)
PY
fi

bash "$ROOT/scripts/config-parity-check.sh"

echo "phase-d-done-gate: OK"
