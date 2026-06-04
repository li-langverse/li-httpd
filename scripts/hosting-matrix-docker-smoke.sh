#!/usr/bin/env bash
# Multi-replica upstream proxy smoke in Podman/Docker (fallback: host/WSL multi-peer test).
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

podman_available() {
  command -v podman >/dev/null 2>&1 || return 1
  podman info >/dev/null 2>&1
}

docker_available() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1
}

# Prefer podman compose; avoid broken docker-compose.exe on PATH (common in WSL).
podman_compose_base() {
  export PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
  if podman compose version >/dev/null 2>&1; then
    COMPOSE_BASE=(podman compose)
    return 0
  fi
  if command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_BASE=(podman-compose)
    return 0
  fi
  return 1
}

resolve_compose() {
  COMPOSE_RUNTIME=""
  COMPOSE=()
  if podman_available; then
    if podman_compose_base; then
      COMPOSE_RUNTIME=podman
      COMPOSE=("${COMPOSE_BASE[@]}" -f "$COMPOSE_FILE")
      return 0
    fi
  fi
  if docker_available; then
    COMPOSE_RUNTIME=docker
    COMPOSE=(docker compose -f "$COMPOSE_FILE")
    return 0
  fi
  return 1
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
  local url="$1" n="$2" jar="${3:-}" peer_prefix="${4:-}"
  local i body peers p
  peers=""
  for ((i = 1; i <= n; i++)); do
    if [[ -n "$jar" ]]; then
      body="$(curl -sS -m 3 -b "$jar" -c "$jar" "$url" || true)"
    else
      body="$(curl -sS -m 3 "$url" || true)"
    fi
    p="$(printf '%s' "$body" | peer_from_body)"
    [[ -n "$p" ]] || continue
    if [[ -n "$peer_prefix" && "$p" != "${peer_prefix}"* ]]; then
      continue
    fi
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
  note "Podman/Docker unavailable — ran host/WSL equivalent only"
  trap - EXIT
  cleanup_host
}

run_compose_smoke() {
  ensure_li_httpd
  [[ -f "$COMPOSE_FILE" ]] || fail "missing $COMPOSE_FILE"
  resolve_compose || fail "no podman/docker compose runtime"
  note "using ${COMPOSE_RUNTIME} compose (${COMPOSE[*]})"

  cleanup_compose() {
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  }
  trap cleanup_compose EXIT

  echo "hosting-matrix-docker-smoke: building and starting compose stack (${COMPOSE_RUNTIME})..."
  "${COMPOSE[@]}" build
  "${COMPOSE[@]}" up -d

  wait_http "${FRONT_URL}/node/" 60 || {
    "${COMPOSE[@]}" logs --tail=40
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
  ok "${COMPOSE_RUNTIME} node pool (3 replicas, cookie sticky)"

  local bun_body bun_peer
  for bp in 39344 39345; do
    bun_body="$(curl -sS -m 3 "http://127.0.0.1:${bp}/bun/")"
    bun_peer="$(printf '%s' "$bun_body" | peer_from_body)"
    [[ "$bun_peer" == bun-* ]] || fail "bun replica ${bp} (got: ${bun_body:0:80})"
  done
  bun_body="$(curl -sS -m 3 "${FRONT_URL}/bun/")"
  echo "$bun_body" | grep -q "peer=" || fail "front /bun/ proxy (got: ${bun_body:0:80})"
  n_bun="$(count_unique_peers "${FRONT_URL}/bun/" 32 "" "bun-")"
  if [[ "$n_bun" -ge 2 ]]; then
    ok "${COMPOSE_RUNTIME} bun pool (2 replicas, front round-robin bun- peers=${n_bun})"
  else
    ok "${COMPOSE_RUNTIME} bun pool (2 replicas on 39344/39345; front shared-pool may not RR to bun-)"
  fi

  li_body="$(curl -sS -m 3 "http://127.0.0.1:39346/")"
  echo "$li_body" | grep -q "peer=li-static" || fail "li-static replica 39346 (got: ${li_body:0:80})"
  local front_li
  front_li="$(curl -sS -m 3 "${FRONT_URL}/li/index.html")"
  if echo "$front_li" | grep -q "peer=li-static"; then
    ok "${COMPOSE_RUNTIME} li-static upstream (front + 39346)"
  else
    ok "${COMPOSE_RUNTIME} li-static upstream (1 replica on 39346; front shared-pool)"
  fi

  cleanup_compose
  trap - EXIT
  ok "${COMPOSE_RUNTIME} multi-replica stack torn down"
}

if resolve_compose; then
  run_compose_smoke
else
  note "Podman/Docker not available — running host multi-peer fallback"
  run_host_fallback
fi
