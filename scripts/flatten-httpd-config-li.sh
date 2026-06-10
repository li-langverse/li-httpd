#!/usr/bin/env bash
# Li-native httpd config flatten (phase B1). Emits runtime.conf on stdout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RS='<<<LI_HTTPD_CONF_RS>>>'
if [[ $# -lt 1 ]]; then
  echo "flatten-httpd-config-li: usage: $0 config.toml [-o out.conf]" >&2
  exit 2
fi
IN="$1"
shift
OUT=""
if [[ "${1:-}" == "-o" ]]; then
  OUT="${2:?}"
  shift 2
fi
BIN="${FLATTEN_ONE_BIN:-$ROOT/build/flatten_one}"
need_rebuild=0
if [[ ! -x "$BIN" ]]; then
  need_rebuild=1
else
  for src in \
    "$ROOT/li-tests/corpus/config/flatten_corpus.li" \
    "$ROOT/li-tests/corpus/config/flatten.li" \
    "$ROOT/li-tests/corpus/flatten_one.li" \
    "$ROOT/scripts/build-flatten-one.sh"; do
    if [[ -f "$src" && "$src" -nt "$BIN" ]]; then
      need_rebuild=1
      break
    fi
  done
fi
if (( need_rebuild )); then
  bash "$ROOT/scripts/build-flatten-one.sh"
fi
RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT
if ! "$BIN" "$IN" >"$RAW"; then
  echo "flatten-httpd-config-li: flatten failed: $IN" >&2
  exit 1
fi
emit_conf() {
  python3 - "$RS" "$1" <<'PY'
import sys
rs = sys.argv[1]
path = sys.argv[2]
text = open(path, encoding="utf-8").read()
out = text.replace(rs, "\n")
if out and not out.endswith("\n"):
    out += "\n"
sys.stdout.write(out)
PY
}
if [[ -n "$OUT" ]]; then
  emit_conf "$RAW" >"$OUT"
else
  emit_conf "$RAW"
fi
