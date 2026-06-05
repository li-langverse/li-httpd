#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fuser -k 39231/tcp 39233/tcp 2>/dev/null || true
sleep 0.5
export BACKEND_PORT=39231 LI_HTTPD_PROXY_SNAP=0 LI_HTTPD_PROXY_C=1
node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
BE=$!
sleep 1
"$ROOT/build/li-httpd" 39233 "$ROOT/li-tests/hosting-matrix/static" 39231 &
FE=$!
sleep 1
echo "=== argv GET ==="
curl -sS --max-time 5 "http://127.0.0.1:39233/api/page" | head -c 80; echo
echo "=== argv POST echo ==="
curl -sS --max-time 5 -X POST "http://127.0.0.1:39233/api/echo" \
  -H "content-type: application/json" -d '{"hello":"world"}' || echo FAIL
echo
echo "=== argv POST login ==="
curl -sS --max-time 5 -X POST "http://127.0.0.1:39233/api/login" \
  -H "content-type: application/json" -d '{"user":"agent","pass":"secret"}' || echo FAIL
echo
kill "$BE" "$FE" 2>/dev/null || true
