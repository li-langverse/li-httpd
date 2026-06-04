#!/usr/bin/env bash
# Smoke: static HTML/CSS/JS, Next static export, reverse proxy to Node/Bun/Next dev.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export LI_HTTPD_CONFIG_PIPELINE="${LI_HTTPD_CONFIG_PIPELINE:-li}"
export LI_HTTPD_WORKERS="${LI_HTTPD_WORKERS:-1}"
export LI_HTTPD_M2_HTTP2="${LI_HTTPD_M2_HTTP2:-0}"
export LI_HTTPD_PROXY_SNAP="${LI_HTTPD_PROXY_SNAP:-0}"
export LI_HTTPD_PROXY_C="${LI_HTTPD_PROXY_C:-1}"

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

MATRIX_PORTS=(39229 39230 39231 39232 39233 39234 39235 39236 39237 39238 39239 39240 39241 39242 39243 39244 39245 39246 39247)

port_busy() {
  local p="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti ":${p}" >/dev/null 2>&1
    return $?
  fi
  fuser "${p}/tcp" >/dev/null 2>&1
}

free_port() {
  local p="$1" timeout_sec="${2:-8}" start now elapsed
  start=$(date +%s)
  while port_busy "$p"; do
    fuser -k "${p}/tcp" >/dev/null 2>&1 || true
    if command -v lsof >/dev/null 2>&1; then
      local pids
      pids="$(lsof -ti ":${p}" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
      if [[ -n "${pids// }" ]]; then
        # shellcheck disable=SC2086
        kill -9 ${pids} >/dev/null 2>&1 || true
      fi
    fi
    port_busy "$p" || break
    now=$(date +%s)
    elapsed=$((now - start))
    if (( elapsed >= timeout_sec )); then
      echo "hosting-matrix-smoke: WARN port ${p} still busy after ${timeout_sec}s:" >&2
      fuser -v "${p}/tcp" 2>&1 | head -3 >&2 || true
      break
    fi
    sleep 0.25
  done
  sleep 0.15
}

free_matrix_ports() {
  local timeout_sec="${1:-10}"
  pkill -9 li-httpd >/dev/null 2>&1 || true
  for p in "${MATRIX_PORTS[@]}"; do
    free_port "$p" "$timeout_sec"
  done
}

free_matrix_ports 12

HOSTING_PID=""
HOSTING_CONF=""
HOSTING_LISTEN_PORT=""

serve_from_toml() {
  local cfg="$1"
  if [[ -n "${HOSTING_PID:-}" ]]; then
    kill_pid "$HOSTING_PID"
    rm -f "${HOSTING_CONF:-}"
    HOSTING_PID=""
    HOSTING_CONF=""
    if [[ -n "${HOSTING_LISTEN_PORT:-}" ]]; then
      free_port "$HOSTING_LISTEN_PORT" 8
      HOSTING_LISTEN_PORT=""
    fi
  fi
  pkill -9 li-httpd >/dev/null 2>&1 || true
  sleep 0.15
  HOSTING_CONF="$(mktemp --suffix=.conf)"
  if ! python3 "$ROOT/scripts/flatten-httpd-config.py" "$cfg" -o "$HOSTING_CONF"; then
    rm -f "$HOSTING_CONF"
    fail "flatten $cfg"
  fi
  HOSTING_LISTEN_PORT="$(grep '^listen_port=' "$HOSTING_CONF" | head -1 | cut -d= -f2- || true)"
  if [[ -n "$HOSTING_LISTEN_PORT" ]]; then
    free_port "$HOSTING_LISTEN_PORT" 8
  fi
  "$BIN" "$HOSTING_CONF" &
  HOSTING_PID=$!
}

ensure_bun() {
  if command -v bun >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$HOME/.bun/bin/bun" ]]; then
    export PATH="$HOME/.bun/bin:$PATH"
    return 0
  fi
  local bun_local="$ROOT/li-tests/hosting-matrix/backends/node_modules/.bin/bun"
  if [[ -x "$bun_local" ]]; then
    export PATH="$(dirname "$bun_local"):$PATH"
    return 0
  fi
  if command -v npm >/dev/null 2>&1 && [[ -f "$ROOT/li-tests/hosting-matrix/backends/package.json" ]]; then
    echo "hosting-matrix-smoke: installing bun locally for smoke..."
    ( cd "$ROOT/li-tests/hosting-matrix/backends" && npm install --no-audit --no-fund ) || true
    [[ -x "$bun_local" ]] && export PATH="$(dirname "$bun_local"):$PATH"
  fi
  command -v bun >/dev/null 2>&1
}

stop_served() {
  kill_pid "$HOSTING_PID"
  rm -f "${HOSTING_CONF:-}"
  HOSTING_PID=""
  HOSTING_CONF=""
  pkill -9 li-httpd >/dev/null 2>&1 || true
  if [[ -n "${HOSTING_LISTEN_PORT:-}" ]]; then
    free_port "$HOSTING_LISTEN_PORT" 6
    HOSTING_LISTEN_PORT=""
  fi
}

wait_http() {
  local url="$1"
  local tries="${2:-40}"
  local i=0
  local code
  while (( i < tries )); do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 0.5 "$url" 2>/dev/null || echo "000")"
    if [[ "$code" =~ ^[0-9]{3}$ ]] && [[ "$code" != "000" ]]; then
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
free_matrix_ports 8
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
free_matrix_ports 6
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
free_matrix_ports 8
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
JAR="$(mktemp)"
curl -sS --http1.1 --max-time 20 -c "$JAR" -b "$JAR" -X POST "http://127.0.0.1:39233/api/login" \
  -H "content-type: application/json" \
  -d '{"user":"agent","pass":"secret"}' | grep -q '"ok":true' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "proxy login Set-Cookie"
}
code_me="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -b "$JAR" "http://127.0.0.1:39233/api/me")"
[[ "$code_me" == "200" ]] || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "proxy /api/me with session cookie (code=$code_me)"
}
code_anon="$(curl -sS --http1.1 -o /dev/null -w "%{http_code}" "http://127.0.0.1:39233/api/me")"
[[ "$code_anon" == "401" ]] || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "proxy /api/me without cookie should 401 (code=$code_anon)"
}
echo '{"hello":"li-httpd"}' | curl -sS --http1.1 --max-time 10 -b "$JAR" -X POST "http://127.0.0.1:39233/api/echo" \
  -H "content-type: application/json" -d @- | grep -q 'hello' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "proxy POST /api/echo JSON body"
}

# REST CRUD through proxy
rest_create="$(curl -sS --http1.1 --max-time 10 -X POST "http://127.0.0.1:39233/api/rest/users" \
  -H "content-type: application/json" -d '{"name":"Charlie","email":"c@example.com"}')"
echo "$rest_create" | grep -q '"name":"Charlie"' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "REST POST create user (got: ${rest_create:0:120})"
}
new_id="$(echo "$rest_create" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")"
curl -sS --http1.1 --max-time 10 -X PUT "http://127.0.0.1:39233/api/rest/users/${new_id}" \
  -H "content-type: application/json" -d '{"name":"Charles","email":"c@example.com"}' | grep -q '"name":"Charles"' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "REST PUT update user"
}
curl -sS --http1.1 --max-time 10 -X PATCH "http://127.0.0.1:39233/api/rest/users/${new_id}" \
  -H "content-type: application/json" -d '{"email":"charles@example.com"}' | grep -q 'charles@example.com' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "REST PATCH partial update"
}
code_del="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X DELETE "http://127.0.0.1:39233/api/rest/users/${new_id}")"
[[ "$code_del" == "204" ]] || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "REST DELETE should 204 (code=$code_del)"
}
curl -sS --http1.1 --max-time 10 "http://127.0.0.1:39233/api/rest/users?filter=Alice" | grep -q '"name":"Alice"' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "REST GET with query string"
}

# SOAP XML through proxy
SOAP_BODY='<?xml version="1.0"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><test/></soap:Body></soap:Envelope>'
soap_resp="$(curl -sS --http1.1 --max-time 10 -X POST "http://127.0.0.1:39233/api/soap" \
  -H "content-type: text/xml" \
  -H 'SOAPAction: "urn:test#Echo"' \
  -d "$SOAP_BODY")"
echo "$soap_resp" | grep -q 'EchoResponse' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "SOAP POST through proxy (got: ${soap_resp:0:120})"
}
echo "$soap_resp" | grep -q 'urn:test#Echo' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "SOAPAction passthrough in response"
}

# Header passthrough (Authorization, X-Custom, SOAPAction, Accept)
hdr_body="$(curl -sS --http1.1 --max-time 10 "http://127.0.0.1:39233/api/headers" \
  -H "authorization: Bearer smoke-token" \
  -H "x-custom: matrix-test" \
  -H 'SOAPAction: "urn:headers"' \
  -H "accept: application/json")"
echo "$hdr_body" | grep -q 'Bearer smoke-token' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "Authorization header passthrough"
}
echo "$hdr_body" | grep -q 'matrix-test' || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "X-Custom header passthrough"
}

# CORS preflight for PUT
code_opts="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X OPTIONS "http://127.0.0.1:39233/api/rest/users" \
  -H "origin: http://example.com" \
  -H "access-control-request-method: PUT")"
[[ "$code_opts" == "204" ]] || {
  kill_served
  kill_pid "$PID_NODE"
  rm -f "$JAR"
  fail "CORS OPTIONS preflight for PUT (code=$code_opts)"
}

rm -f "$JAR"
kill_served
kill_pid "$PID_NODE"
ok "reverse proxy -> Node (REST, SOAP, JSON, headers, CORS)"

# --- 5) Bun backend + reverse proxy ---
if ensure_bun; then
  export BACKEND_PORT=39232
  free_matrix_ports 8
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
  bun_api_body=""
  for _ in 1 2 3 4 5; do
    bun_api_body="$(curl -sS --http1.1 "http://127.0.0.1:39235/api/page" 2>/dev/null || true)"
    echo "$bun_api_body" | grep -q "bun upstream html" && break
    sleep 0.15
  done
  echo "$bun_api_body" | grep -q "bun upstream html" || {
    kill_served
    kill_pid "$PID_BUN"
    fail "proxy-bun body (got: ${bun_api_body:0:120})"
  }
  kill_served
  kill_pid "$PID_BUN"
  ok "reverse proxy -> Bun"
else
  echo "hosting-matrix-smoke: SKIP bun (not on PATH)"
fi

# --- 6) Next.js dev + reverse proxy (TOML) ---
# Default: CL stand-in (next dev streams chunked; li-httpd relay is CL-oriented today).
# Set HOSTING_MATRIX_REAL_NEXT=1 to exercise full `next dev` (may SKIP on proxy body).
export BACKEND_PORT=39237
free_matrix_ports 8
if [[ "${HOSTING_MATRIX_REAL_NEXT:-0}" == "1" && -f "$ROOT/li-tests/hosting-matrix/next-dev/package.json" ]]; then
  NEXT_DIR="$ROOT/li-tests/hosting-matrix/next-dev"
  [[ -d "$NEXT_DIR/node_modules" ]] || ( cd "$NEXT_DIR" && npm install --no-audit --no-fund )
  ( cd "$NEXT_DIR" && npm run dev -- -p 39237 -H 127.0.0.1 ) &
  PID_NEXT_UP=$!
  NEXT_LABEL="Next.js dev (next dev)"
else
  node "$ROOT/li-tests/hosting-matrix/backends/next-dev-standin.mjs" &
  PID_NEXT_UP=$!
  NEXT_LABEL="Next.js dev stand-in"
fi
if wait_http "http://127.0.0.1:39237/" 120; then
  serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/proxy-next-dev.toml"
  if wait_http "http://127.0.0.1:39238/" 40; then
    body="$(curl -sS --http1.1 "http://127.0.0.1:39238/" 2>/dev/null || true)"
    if echo "$body" | grep -qi "next"; then
      kill_served
      kill_pid "$PID_NEXT_UP"
      ok "reverse proxy -> $NEXT_LABEL"
    else
      kill_served
      kill_pid "$PID_NEXT_UP"
      if [[ "${HOSTING_MATRIX_REAL_NEXT:-0}" == "1" ]]; then
        echo "hosting-matrix-smoke: SKIP real next dev proxy (chunked upstream; use stand-in or static export)"
      else
        fail "next dev proxy body (got: ${body:0:200})"
      fi
    fi
  else
    kill_served 2>/dev/null || true
    kill_pid "$PID_NEXT_UP"
    fail "next dev proxy front (39238) did not respond"
  fi
else
  kill_pid "$PID_NEXT_UP" 2>/dev/null || true
  fail "next dev upstream (39237) did not start"
fi

# --- 7) Full app front (static + API on one port) ---
export BACKEND_PORT=39242
free_matrix_ports 8
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_APP=$!
if ! wait_http "http://127.0.0.1:39242/health"; then
  kill_pid "$PID_APP"
  fail "app backend health"
fi
serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/proxy-app.toml"
if ! wait_http "http://127.0.0.1:39241/login.html"; then
  kill_served
  kill_pid "$PID_APP"
  fail "proxy-app static login.html"
fi
curl -fsS "http://127.0.0.1:39241/login.html" | grep -q "Session demo" || {
  kill_served
  kill_pid "$PID_APP"
  fail "proxy-app login.html body"
}
kill_served
kill_pid "$PID_APP"
ok "proxy-app (static + API routes)"

# --- 8) Sticky cookie LB (two peers) ---
free_matrix_ports 8
export BACKEND_RUNTIME=peer-a BACKEND_PORT=39244
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_PA=$!
export BACKEND_RUNTIME=peer-b BACKEND_PORT=39245
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_PB=$!
if ! wait_http "http://127.0.0.1:39244/health"; then
  kill_pid "$PID_PA" "$PID_PB"
  fail "sticky peer-a health"
fi
if ! wait_http "http://127.0.0.1:39245/health"; then
  kill_pid "$PID_PA" "$PID_PB"
  fail "sticky peer-b health"
fi
serve_from_toml "$ROOT/li-tests/hosting-matrix/configs/proxy-sticky.toml"
if ! wait_http "http://127.0.0.1:39243/"; then
  kill_served
  kill_pid "$PID_PA" "$PID_PB"
  fail "sticky LB front (39243)"
fi
STICKY_JAR="$(mktemp)"
peer_body=""
for _ in 1 2 3 4 5; do
  peer_body="$(curl -sS --http1.1 -c "$STICKY_JAR" -b "$STICKY_JAR" "http://127.0.0.1:39243/")"
  sleep 0.05
done
echo "$peer_body" | grep -q "peer=" || {
  kill_served
  kill_pid "$PID_PA" "$PID_PB"
  rm -f "$STICKY_JAR"
  fail "sticky cookie body (got: ${peer_body:0:80})"
}
for _ in 1 2 3; do
  b2="$(curl -sS --http1.1 -b "$STICKY_JAR" "http://127.0.0.1:39243/")"
  [[ "$b2" == "$peer_body" ]] || {
    kill_served
    kill_pid "$PID_PA" "$PID_PB"
    rm -f "$STICKY_JAR"
    fail "sticky cookie affinity changed peer"
  }
done
rm -f "$STICKY_JAR"
kill_served
kill_pid "$PID_PA" "$PID_PB"
ok "sticky sessions (li_route cookie LB)"

# --- 9) argv proxy (optional; static+backend split) ---
PORT_BE=39246
PORT_FRONT=39247
export BACKEND_PORT="$PORT_BE"
free_matrix_ports 8
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
