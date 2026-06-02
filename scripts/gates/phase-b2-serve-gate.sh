#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() { echo "phase-b2-serve-gate: $*" >&2; exit 1; }

test -f "$ROOT/data/li-toml-config-loop/state.json" || fail "missing state.json"
test -f "$ROOT/li-httpd" || fail "missing repo wrapper: $ROOT/li-httpd"

python3 - <<'PY'
import json, pathlib, sys
state_path = pathlib.Path("data/li-toml-config-loop/state.json")
state = json.loads(state_path.read_text(encoding="utf-8"))
phase = str(state.get("phase", ""))
allowed = ("phase-b2-serve", "phase-c-retire-c", "phase-d-done")
if phase not in allowed:
    print(f"phase-b2-serve-gate: state.json phase={phase!r} (want one of {allowed})", file=sys.stderr)
    raise SystemExit(1)
PY

chmod +x "$ROOT/li-httpd" || true

# Build dependencies used by the wrapper (server + Li flatten harness).
bash "$ROOT/scripts/build-li-httpd.sh"
bash "$ROOT/scripts/build-flatten-one.sh"

CFG="$ROOT/li-tests/config/good/auth_bearer.toml"
test -f "$CFG" || fail "missing config fixture: $CFG"

PORT="39220"
if command -v curl >/dev/null 2>&1; then
  ( export LI_HTTPD_CONFIG_PIPELINE=li
    timeout 6s "$ROOT/li-httpd" serve "$CFG" ) &
  pid="$!"
  # Wait briefly for listen.
  for _ in $(seq 1 30); do
    # Fixture requires bearer auth; gate should validate the "serve" path, not auth rejection.
    if curl -fsS --max-time 0.2 -H "Authorization: Bearer dev-agent-key" \
      "http://127.0.0.1:${PORT}/index.html" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      echo "phase-b2-serve-gate: ok"
      exit 0
    fi
    sleep 0.1
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  fail "server did not respond on http://127.0.0.1:${PORT}/index.html"
fi

fail "curl not available (required for phase-b2-serve-gate)"
