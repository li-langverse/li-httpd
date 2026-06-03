#!/usr/bin/env bash
# Multi-replica upstream proxy smoke in Docker (fallback: host/WSL multi-peer test).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="$ROOT/li-tests/hosting-matrix/docker"
COMPOSE_FILE="$DOCKER_DIR/compose.multi-replica.yml"
FRONT_URL="${HOSTING_MATRIX_DOCKER_URL:-http://127.0.0.1:39300}"

fail() { echo "hosting-matrix-docker-smoke: FAIL $*" >&2; exit 1; }
ok() { echo "hosting-matrix-docker-smoke: OK $*"; }
note() { echo "hosting-matrix-docker-smoke: NOTE $*"; }

command -v curl >/dev/null 2>&1 || fail "curl required"

ensure_li_httpd() {
  local bin="$ROOT/build/li-httpd"
  if [[ -x "$bin" ]]; then
    return 0
  fi
  if [[ -x "$ROOT/../lic-pure-https/build/li-httpd" ]]; then
    mkdir -p "$ROOT/build"
    cp -f "$ROOT/../lic-pure-https/build/li-httpd" "$bin"
    return 0
  fi
  if [[ -x "$ROOT/../lic/build/li-httpd" ]]; then
    mkdir -p "$ROOT/build"
    cp -f "$ROOT/../lic/build/li-httpd" "$bin"
    return 0
  fi
  bash "$ROOT/scripts/build-li-httpd.sh"
  [[ -x "$bin" ]] || fail "missing $bin"
}

docker_available() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1
}

wait_http() {
  local url="$1" tries="${2:-40}"
  local i
  for ((i = 1; i <= tries; i++)); do
    if curl -fsS -m 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

peer_from_body() {
  sed -n 's/.*peer=\([^<]*\).*/\1/p' | head -1
}

count_unique_peers() {
  local url="$1" n="$2" jar="${3:-}"
  local i body peers
  peers=""
  for ((i = 1; i <= n; i++)); do
    if [[ -n "$jar" ]]; then
      body="$(curl -sS -m 3 -b "$jar" -c "$jar" "$url" || true)"
    else
      body="$(curl -sS -m 3 "$url" || true)"
    fi
    p="$(printf '%s' "$body" | peer_from_body)"
    [[ -n "$p" ]] || continue
    if ! printf '%s\n' "$peers" | grep -qx "$p"; then
      peers="${peers}${p}"$'\n'
    fi
  done
  printf '%s' "$peers" | grep -c . || true
}

run_host_fallback() {
  command -v node >/dev/null 2>&1 || { note "no node for host fallback"; exit 0; }
  command -v python3 >/dev/null 2>&1 || { note "no python3 for host fallback"; exit 0; }

  ensure_li_httpd
  local bin="$ROOT/build/li-httpd"
  local pa=39344 pb=39345 front=39343
  local pid_pa pid_pb pid_front conf
  conf="$(mktemp --suffix=.conf)"

  fuser -k "${front}/tcp" "${pa}/tcp" "${pb}/tcp" 2>/dev/null || true
  sleep 0.2

  export BACKEND_HOST=127.0.0.1 BACKEND_RUNTIME=peer-a BACKEND_PORT="$pa"
  node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
  pid_pa=$!
  export BACKEND_RUNTIME=peer-b BACKEND_PORT="$pb"
  node "$ROOT/li-tests/hosting-matrix/backends/node-server.mjs" &
  pid_pb=$!

  cleanup_host() {
    kill "${pid_pa:-}" "${pid_pb:-}" "${pid_front:-}" 2>/dev/null || true
    rm -f "$conf"
    fuser -k "${front}/tcp" "${pa}/tcp" "${pb}/tcp" 2>/dev/null || true
  }
  trap cleanup_host EXIT

  wait_http "http://127.0.0.1:${pa}/health" 20 || fail "host fallback peer-a health"
  wait_http "http://127.0.0.1:${pb}/health" 20 || fail "host fallback peer-b health"

  local toml
  toml="$(mktemp --suffix=.toml)"
  cat >"$toml" <<EOF
[server]
listen = "127.0.0.1:${front}"
document_root = "${ROOT}/li-tests/hosting-matrix/static"

[limits]
rate_limit_rps = 10000
rate_limit_burst = 20000

[upstreams.pool]
balance = "cookie"
peers = ["http://127.0.0.1:${pa}", "http://127.0.0.1:${pb}"]

[routes]
"GET /*" = "proxy:pool"
EOF
  python3 "$ROOT/scripts/flatten-httpd-config.py" "$toml" -o "$conf" || fail "flatten host fallback config"
  rm -f "$toml"
  "$bin" "$conf" &
  pid_front=$!
  wait_http "http://127.0.0.1:${front}/" 30 || fail "host fallback front"

  local jar peer_body b2 n_rr
  jar="$(mktemp)"
  peer_body="$(curl -sS -c "$jar" -b "$jar" "http://127.0.0.1:${front}/")"
  echo "$peer_body" | grep -q "peer=" || fail "host fallback sticky body"
  b2="$(curl -sS -b "$jar" "http://127.0.0.1:${front}/")"
  [[ "$b2" == "$peer_body" ]] || fail "host fallback sticky affinity"
  rm -f "$jar"

  n_rr="$(count_unique_peers "http://127.0.0.1:${front}/" 12)"
  [[ "$n_rr" -ge 1 ]] || fail "host fallback round-robin probe"

  ok "host fallback (2 Node peers, cookie sticky on ${front})"
  note "Docker unavailable — ran host/WSL equivalent only"
  trap - EXIT
  cleanup_host
}

run_docker_smoke() {
  ensure_li_httpd
  [[ -f "$COMPOSE_FILE" ]] || fail "missing $COMPOSE_FILE"

  local compose=(docker compose -f "$COMPOSE_FILE")
  cleanup_compose() {
    "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  }
  trap cleanup_compose EXIT

  echo "hosting-matrix-docker-smoke: building and starting compose stack..."
  "${compose[@]}" build --quiet
  "${compose[@]}" up -d

  wait_http "${FRONT_URL}/node/" 60 || {
    "${compose[@]}" logs --tail=40
    fail "front /node/ not ready at ${FRONT_URL}"
  }

  local jar peer_body n_bun n_node li_body
  jar="$(mktemp)"

  peer_body="$(curl -sS -c "$jar" -b "$jar" "${FRONT_URL}/node/")"
  echo "$peer_body" | grep -q "peer=node-" || fail "node pool body (got: ${peer_body:0:80})"
  for _ in 1 2 3; do
    b2="$(curl -sS -b "$jar" "${FRONT_URL}/node/")"
    [[ "$b2" == "$peer_body" ]] || fail "node cookie sticky affinity changed peer"
  done
  rm -f "$jar"
  ok "docker node pool (3 replicas, cookie sticky)"

  n_bun="$(count_unique_peers "${FRONT_URL}/bun/" 16)"
  if [[ "$n_bun" -lt 2 ]]; then
    fail "bun round-robin expected >=2 peers, got ${n_bun}"
  fi
  ok "docker bun pool (2 replicas, round-robin distinct peers=${n_bun})"

  li_body="$(curl -sS "${FRONT_URL}/li/")"
  echo "$li_body" | grep -q "peer=li-static" || fail "li-static upstream (got: ${li_body:0:80})"
  ok "docker li-static upstream (1 li-httpd replica)"

  cleanup_compose
  trap - EXIT
  ok "docker multi-replica stack torn down"
}

if docker_available; then
  run_docker_smoke
else
  note "Docker not available — running host multi-peer fallback"
  run_host_fallback
fi
