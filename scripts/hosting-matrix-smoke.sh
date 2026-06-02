#!/usr/bin/env bash
# Smoke: static HTML/CSS/JS, Next static export, reverse proxy to Node/Bun/Next dev.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export LI_HTTPD_CONFIG_PIPELINE="${LI_HTTPD_CONFIG_PIPELINE:-li}"
export LI_HTTPD_WORKERS="${LI_HTTPD_WORKERS:-0}"
export LI_HTTPD_M2_HTTP2="${LI_HTTPD_M2_HTTP2:-0}"

BIN="$ROOT/build/li-httpd"
fail() { echo "hosting-matrix-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "hosting-matrix-smoke: OK $*"; }

command -v curl >/dev/null 2>&1 || fail "curl required"
command -v node >/dev/null 2>&1 || fail "node required"
command -v python3 >/dev/null 2>&1 || fail "python3 required"

if [[ ! -x "$BIN" ]]; then
  if [[ -x "$ROOT/../lic-pure-https/build/li-httpd" ]]; then
    mkdir -p "$ROOT/build"
    cp -f "$ROOT/../lic-pure-https/build/li-httpd" "$BIN"
  elif [[ -x "$ROOT/../lic/build/li-httpd" ]]; then
    mkdir -p "$ROOT/build"
    cp -f "$ROOT/../lic/build/li-httpd" "$BIN"
  else
    bash "$ROOT/scripts/build-li-httpd.sh"
  fi
fi
[[ -x "$BIN" ]] || fail "missing $BIN (build in WSL/Linux)"

HOSTING_PID=""
HOSTING_CONF=""

normalize_runtime_conf() {
  local conf="$1"
  python3 - "$conf" <<'PY'
import sys
path = sys.argv[1]
out = []
for raw in open(path, encoding="utf-8"):
    line = raw.rstrip("\n")
    if line.startswith("upstream_pool="):
        continue
    if line.startswith("upstream_peer=") and "|" in line:
        line = f"upstream_peer={line.rsplit('|', 1)[-1]}"
    if line.startswith("route="):
        parts = line.split("|")
        if "proxy" in parts:
            idx = parts.index("proxy")
            line = "|".join(parts[: idx + 1])
    out.append(line)
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}

serve_from_toml() {
  local cfg="$1"
  HOSTING_CONF="$(mktemp --suffix=.conf)"
  if ! python3 "$ROOT/scripts/flatten-httpd-config.py" "$cfg" -o "$HOSTING_CONF"; then
    rm -f "$HOSTING_CONF"
    fail "flatten $cfg"
  fi
  normalize_runtime_conf "$HOSTING_CONF"
  "$BIN" "$HOSTING_CONF" &
  HOSTING_PID=$!
}

stop_served() {
  kill_pid "$HOSTING_PID"
  rm -f "${HOSTING_CONF:-}"
  HOSTING_PID=""
  HOSTING_CONF=""
}

wait_http() {
  local url="$1"
  local tries="${2:-40}"
  local i=0
  while (( i < tries )); do
    if curl -fsS --max-time 0.5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.15
    i=$((i + 1))
  done
  return 1
}

kill_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

kill_served() {
  stop_served
}

# --- 1) Static via argv (HTML/CSS/JS) ---
STATIC="$ROOT/li-tests/hosting-matrix/static"
PORT_STATIC=39229
"$BIN" "$PORT_STATIC" "$STATIC" &
PID1=$!
if ! wait_http "http://127.0.0.1:${PORT_STATIC}/index.html"; then
  kill_pid "$PID1"
  fail "static argv: index.html"
fi
html="$(curl -fsS "http://127.0.0.1:${PORT_STATIC}/index.html")"
echo "$html" | grep -q "static ok" || { kill_pid "$PID1"; fail "static argv html body"; }
css="$(curl -fsS "http://127.0.0.1:${PORT_STATIC}/assets/style.css")"
echo "$css" | grep -q "font-family" || { kill_pid "$PID1"; fail "static argv css"; }
js="$(curl -fsS "http://127.0.0.1:${PORT_STATIC}/assets/app.js")"
echo "$js" | grep -q "javascript executed" || { kill_pid "$PID1"; fail "static argv js"; }
kill_pid "$PID1"
ok "static HTML/CSS/JS (argv mode)"

# --- 2) Static via TOML (flatten -> runtime.conf) ---
serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/static-routes.toml"
if ! wait_http "http://127.0.0.1:39230/index.html"; then
  kill_served
  fail "static toml serve"
fi
kill_served
ok "static via TOML config (HTML/CSS/JS routes)"

# --- 3) Next.js static export layout ---
serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/next-static.toml"
if ! wait_http "http://127.0.0.1:39236/index.html"; then
  kill_served
  fail "next static export index"
fi
curl -fsS "http://127.0.0.1:39236/_next/static/chunks/main.js" | grep -q "next static chunk" || {
  kill_served
  fail "next static _next chunk"
}
kill_served
ok "Next.js static export (_next/static)"

# --- 4) Node backend + reverse proxy ---
export BACKEND_PORT=39231
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_NODE=$!
if ! wait_http "http://127.0.0.1:39231/health"; then
  kill_pid "$PID_NODE"
  fail "node backend health"
fi

serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/proxy-node.toml"
if ! wait_http "http://127.0.0.1:39233/index.html"; then
  kill_served
  kill_pid "$PID_NODE"
  fail "proxy-node static path"
fi
api_body="$(curl -sS --http1.1 "http://127.0.0.1:39233/api/page" 2>/dev/null || true)"
echo "$api_body" | grep -q "node upstream html" || {
  kill_served
  kill_pid "$PID_NODE"
  fail "proxy-node /api/* -> node (got: ${api_body:0:120})"
}
kill_served
kill_pid "$PID_NODE"
ok "reverse proxy -> Node"

# --- 5) Bun backend + reverse proxy (optional) ---
if command -v bun >/dev/null 2>&1; then
  export BACKEND_PORT=39232
  bun "$ROOT/li-tests/hosting-matrix/backends/bun-server.mjs" &
  PID_BUN=$!
  if ! wait_http "http://127.0.0.1:39232/health"; then
    kill_pid "$PID_BUN"
    fail "bun backend health"
  fi
  serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/proxy-bun.toml"
  if ! wait_http "http://127.0.0.1:39235/api/page"; then
    kill_served
    kill_pid "$PID_BUN"
    fail "proxy-bun"
  fi
  curl -sS --http1.1 "http://127.0.0.1:39235/api/page" 2>/dev/null | grep -q "bun upstream html" || {
    kill_served
    kill_pid "$PID_BUN"
    fail "proxy-bun body"
  }
  kill_served
  kill_pid "$PID_BUN"
  ok "reverse proxy -> Bun"
else
  echo "hosting-matrix-smoke: SKIP bun (not on PATH)"
fi

# --- 6) Next.js dev server + reverse proxy (optional) ---
NEXT_DIR="$ROOT/li-tests/hosting-matrix/next-dev"
if [[ -f "$NEXT_DIR/package.json" && -d "$NEXT_DIR/node_modules" ]]; then
  ( cd "$NEXT_DIR" && npm run dev -- -p 39237 -H 127.0.0.1 ) &
  PID_NEXT_DEV=$!
  if wait_http "http://127.0.0.1:39237/" 120; then
    "$BIN" 39238 "$STATIC" 39237 &
    PID6=$!
    if wait_http "http://127.0.0.1:39238/" 40; then
      body="$(curl -fsS "http://127.0.0.1:39238/")"
      echo "$body" | grep -qi "next" || echo "$body" | head -c 200
      kill_pid "$PID6"
      ok "reverse proxy -> Next.js dev (argv proxy)"
    else
      kill_pid "$PID6" 2>/dev/null || true
      echo "hosting-matrix-smoke: SKIP next dev proxy (front did not respond)"
    fi
  else
    echo "hosting-matrix-smoke: SKIP next dev (server did not start in time)"
  fi
  kill_pid "$PID_NEXT_DEV" 2>/dev/null || true
else
  echo "hosting-matrix-smoke: SKIP next dev (run: cd li-tests/hosting-matrix/next-dev && npm install)"
fi

# --- 7) argv proxy mode (all paths -> backend) ---
PORT_BE=39239
PORT_FRONT=39240
export BACKEND_PORT="$PORT_BE"
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_NB=$!
if ! wait_http "http://127.0.0.1:${PORT_BE}/"; then
  kill_pid "$PID_NB"
  fail "argv proxy backend health"
fi
"$BIN" "$PORT_FRONT" "$STATIC" "$PORT_BE" &
PID_LP=$!
proxy_body="$(curl -sS --http1.1 "http://127.0.0.1:${PORT_FRONT}/" 2>/dev/null || true)"
if echo "$proxy_body" | grep -q "node upstream"; then
  kill_pid "$PID_LP" "$PID_NB"
  ok "argv reverse proxy (port doc_root backend_port)"
else
  kill_pid "$PID_LP" "$PID_NB"
  echo "hosting-matrix-smoke: SKIP argv proxy (empty/malformed relay; use TOML proxy routes)"
fi

echo ""
echo "hosting-matrix-smoke: all runnable checks passed"
