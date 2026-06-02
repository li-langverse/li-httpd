#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "config-parity-check: $*" >&2; exit 1; }

GOOD_DIR="$ROOT/li-tests/config/good"
REJECT_DIR="$ROOT/li-tests/config/reject"
test -d "$GOOD_DIR" || fail "missing good corpus dir: $GOOD_DIR"
test -d "$REJECT_DIR" || fail "missing reject corpus dir: $REJECT_DIR"

# Legacy baseline (temporary during migration).
# We intentionally do not vendor/copy the Python scripts into li-httpd.
LIC_ROOT="${LIC_ROOT:-}"
if [[ -z "$LIC_ROOT" ]]; then
  if [[ -d /workspace/lic && -f /workspace/lic/scripts/flatten-httpd-config.py ]]; then
    LIC_ROOT="/workspace/lic"
  fi
fi
test -d "$LIC_ROOT" || fail "missing LIC_ROOT (set LIC_ROOT or mount /workspace/lic)"

PY_FLATTEN="$LIC_ROOT/scripts/flatten-httpd-config.py"
test -f "$PY_FLATTEN" || fail "missing python flatten script: $PY_FLATTEN"

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || fail "missing python3 (set PYTHON)"

OUT_DIR="${CONFIG_PARITY_OUT_DIR:-/tmp/li-httpd-config-parity}"
mkdir -p "$OUT_DIR/good" "$OUT_DIR/reject"

shopt -s nullglob
GOOD_FILES=( "$GOOD_DIR"/*.toml )
REJECT_FILES=( "$REJECT_DIR"/*.toml )
if (( ${#GOOD_FILES[@]} == 0 )); then
  fail "no good corpus files: $GOOD_DIR/*.toml"
fi
if (( ${#REJECT_FILES[@]} == 0 )); then
  fail "no reject corpus files: $REJECT_DIR/*.toml"
fi

echo "config-parity-check: baseline=python (LIC_ROOT=$LIC_ROOT)"
echo "config-parity-check: good=${#GOOD_FILES[@]} reject=${#REJECT_FILES[@]}"

run_py_flatten() {
  local in_toml="$1"
  local out_conf="$2"
  "$PYTHON" "$PY_FLATTEN" "$in_toml" -o "$out_conf"
}

echo "config-parity-check: python flatten on good corpus"
tested_good=0
for f in "${GOOD_FILES[@]}"; do
  # Some "good" TOMLs are fragments (e.g. generated leak-censor snippets) and are
  # intentionally not valid standalone server configs for the legacy flattener.
  # During phase B1 we only parity-check files that represent full server configs.
  if ! grep -qE '(^server\.listen\b|^\[server\])' "$f"; then
    continue
  fi
  base="$(basename "$f" .toml)"
  out="$OUT_DIR/good/$base.runtime.conf"
  if ! run_py_flatten "$f" "$out" >/dev/null 2>&1; then
    fail "python flatten failed (good): $f"
  fi
  if [[ ! -s "$out" ]]; then
    fail "python flatten produced empty conf (good): $f"
  fi
  tested_good=$((tested_good + 1))
done
if (( tested_good == 0 )); then
  fail "no full server configs found to parity-check under $GOOD_DIR"
fi

echo "config-parity-check: python flatten must fail on reject corpus"
for f in "${REJECT_FILES[@]}"; do
  base="$(basename "$f" .toml)"
  out="$OUT_DIR/reject/$base.runtime.conf"
  if run_py_flatten "$f" "$out" >/dev/null 2>&1; then
    fail "python flatten unexpectedly succeeded (reject): $f"
  fi
done

echo "config-parity-check: OK (python baseline only; li parity pending)"

