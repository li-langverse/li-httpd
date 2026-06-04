#!/usr/bin/env bash
# REST/SOAP/JSON protocol smoke (proxy-node section only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export LI_HTTPD_PROXY_SNAP=0
export LI_HTTPD_PROXY_C=1
export BACKEND_PORT=49231

BIN="$ROOT/build/li-httpd"
fail() { echo "api-protocol: FAIL $*" >&2; exit 1; }
ok() { echo "api-protocol: OK $*"; }

kill_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

[[ -x "$BIN" ]] || fail "missing $BIN"

fuser -k 49231/tcp 49233/tcp 2>/dev/null || true
sleep 0.5

node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
PID_NODE=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sS --http1.1 -o /dev/null --max-time 0.5 "http://127.0.0.1:49231/health" 2>/dev/null && break
  sleep 0.2
done

CONF="$(mktemp --suffix=.conf)"
python3 "$ROOT/scripts/flatten-httpd-config.py" "$ROOT/li-tests/hosting-matrix/configs/proxy-node.toml" -o "$CONF"
sed -i 's/39233/49233/g; s/39231/49231/g' "$CONF"
"$BIN" "$CONF" &
PID_FE=$!
BASE="http://127.0.0.1:49233"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sS --http1.1 -o /dev/null --max-time 0.5 "$BASE/api/health" 2>/dev/null && break
  sleep 0.2
done

rest_create="$(curl -sS --http1.1 --max-time 10 -X POST "$BASE/api/rest/users" \
  -H "content-type: application/json" -d '{"name":"Charlie","email":"c@example.com"}')"
echo "$rest_create" | grep -q '"name":"Charlie"' || fail "REST POST (got: ${rest_create:0:120})"

new_id="$(echo "$rest_create" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")"

curl -sS --http1.1 --max-time 10 -X PUT "$BASE/api/rest/users/${new_id}" \
  -H "content-type: application/json" -d '{"name":"Charles","email":"c@example.com"}' | grep -q '"name":"Charles"' \
  || fail "REST PUT"

curl -sS --http1.1 --max-time 10 -X PATCH "$BASE/api/rest/users/${new_id}" \
  -H "content-type: application/json" -d '{"email":"charles@example.com"}' | grep -q 'charles@example.com' \
  || fail "REST PATCH"

code_del="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X DELETE "$BASE/api/rest/users/${new_id}")"
[[ "$code_del" == "204" ]] || fail "REST DELETE (code=$code_del)"

curl -sS --http1.1 --max-time 10 "$BASE/api/rest/users?filter=Alice" | grep -q '"name":"Alice"' || fail "REST GET query"

SOAP_BODY='<?xml version="1.0"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><test/></soap:Body></soap:Envelope>'
soap_resp="$(curl -sS --http1.1 --max-time 10 -X POST "$BASE/api/soap" \
  -H "content-type: text/xml" \
  -H 'SOAPAction: "urn:test#Echo"' \
  -d "$SOAP_BODY")"
echo "$soap_resp" | grep -q 'EchoResponse' || fail "SOAP POST"
echo "$soap_resp" | grep -q 'urn:test#Echo' || fail "SOAPAction echo"

hdr_body="$(curl -sS --http1.1 --max-time 10 "$BASE/api/headers" \
  -H "authorization: Bearer smoke-token" \
  -H "x-custom: matrix-test" \
  -H 'SOAPAction: "urn:headers"' \
  -H "accept: application/json")"
echo "$hdr_body" | grep -q 'Bearer smoke-token' || fail "Authorization passthrough"
echo "$hdr_body" | grep -q 'matrix-test' || fail "X-Custom passthrough"

code_opts="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE/api/rest/users" \
  -H "origin: http://example.com" \
  -H "access-control-request-method: PUT")"
[[ "$code_opts" == "204" ]] || fail "CORS OPTIONS (code=$code_opts)"

code_put="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X PUT "$BASE/api/echo" \
  -H "content-type: application/json" -d '{"method":"PUT","probe":true}')"
[[ "$code_put" == "200" ]] || fail "PUT /api/echo (code=$code_put)"
put_echo="$(curl -sS --http1.1 --max-time 10 -X PUT "$BASE/api/echo" \
  -H "content-type: application/json" -d '{"method":"PUT","probe":true}')"
echo "$put_echo" | grep -q '"echo":' || fail "PUT /api/echo missing echo (got: ${put_echo:0:120})"
echo "$put_echo" | grep -q 'PUT' || fail "PUT /api/echo body"

code_patch="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -X PATCH "$BASE/api/echo" \
  -H "content-type: application/json" -d '{"method":"PATCH","probe":true}')"
[[ "$code_patch" == "200" ]] || fail "PATCH /api/echo (code=$code_patch)"
patch_echo="$(curl -sS --http1.1 --max-time 10 -X PATCH "$BASE/api/echo" \
  -H "content-type: application/json" -d '{"method":"PATCH","probe":true}')"
echo "$patch_echo" | grep -q '"echo":' || fail "PATCH /api/echo missing echo (got: ${patch_echo:0:120})"

JAR="$(mktemp)"
curl -sS --http1.1 --max-time 20 -c "$JAR" -b "$JAR" -X POST "$BASE/api/login" \
  -H "content-type: application/json" \
  -d '{"user":"agent","pass":"secret"}' | grep -q '"ok":true' || fail "login before logout"
code_me_pre="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -b "$JAR" "$BASE/api/me")"
[[ "$code_me_pre" == "200" ]] || fail "/api/me before logout (code=$code_me_pre)"
code_logout="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -b "$JAR" -c "$JAR" -X POST "$BASE/api/logout")"
[[ "$code_logout" == "200" ]] || fail "POST /api/logout (code=$code_logout)"
code_me_post="$(curl -sS --http1.1 --max-time 10 -o /dev/null -w "%{http_code}" -b "$JAR" "$BASE/api/me")"
[[ "$code_me_post" == "401" ]] || fail "/api/me after logout (code=$code_me_post)"
rm -f "$JAR"

kill_pid "$PID_FE" "$PID_NODE"
rm -f "$CONF"
ok "REST, SOAP, JSON, echo PUT/PATCH, logout, headers, CORS through proxy"
