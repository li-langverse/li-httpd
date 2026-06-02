#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "phase-a0-parse-gate: $*" >&2; exit 1; }

GOOD_DIR="$ROOT/li-tests/config/good"
test -d "$GOOD_DIR" || fail "missing good corpus dir: $GOOD_DIR"

shopt -s nullglob
GOOD_FILES=( "$GOOD_DIR"/*.toml )
if (( ${#GOOD_FILES[@]} == 0 )); then
  fail "no *.toml found under $GOOD_DIR"
fi

# Resolve li-toml workspace root (allow override for isolated clones).
LI_TOML_ROOT="${LI_TOML_ROOT:-}"
if [[ -z "$LI_TOML_ROOT" ]]; then
  if [[ -f "$ROOT/../li-toml/li.toml" ]]; then
    LI_TOML_ROOT="$ROOT/../li-toml"
  elif [[ -d "$ROOT/../../li-toml" ]]; then
    # Typical isolated-workspace layout:
    #   .../li-langverse/li-toml/<run>/repo
    cands=( "$ROOT/../../li-toml/"*/repo )
    if (( ${#cands[@]} > 0 )); then
      # Pick newest candidate by mtime.
      LI_TOML_ROOT="$(ls -td "${cands[@]}" 2>/dev/null | awk 'NR==1{print; exit}')"
    fi
  fi
fi
test -f "$LI_TOML_ROOT/li.toml" || fail "missing li-toml repo (set LI_TOML_ROOT): $LI_TOML_ROOT"

HARNESS="$LI_TOML_ROOT/li-tests/corpus/parse_one.li"
test -f "$HARNESS" || fail "missing parse harness: $HARNESS"

# Resolve lic binary (CI container should provide it; local loop may export LIC_ROOT).
LIC_BIN="${LIC:-}"
if [[ -z "$LIC_BIN" ]]; then
  if [[ -n "${LIC_ROOT:-}" ]]; then
    LIC_BIN="$LIC_ROOT/build/compiler/lic/lic"
  fi
fi
test -x "$LIC_BIN" || fail "missing lic binary (set LIC or LIC_ROOT): $LIC_BIN"

OUT_DIR="${PHASE_A0_PARSE_OUT_DIR:-/tmp/li-toml-phase-a0-parse}"
mkdir -p "$OUT_DIR"
BIN="$OUT_DIR/parse_one"

echo "phase-a0-parse-gate: building parse harness with $(basename "$LIC_BIN")"
LIC_ROOT="${LIC_ROOT:-}"
if [[ -z "$LIC_ROOT" ]]; then
  # If LIC_BIN matches .../build/compiler/lic/lic then strip that suffix.
  case "$LIC_BIN" in
    */build/compiler/lic/lic)
      LIC_ROOT="${LIC_BIN%/build/compiler/lic/lic}"
      ;;
  esac
fi
test -n "$LIC_ROOT" || fail "missing LIC_ROOT (set LIC_ROOT or ensure LIC_BIN points to .../build/compiler/lic/lic)"
test -x "$LIC_BIN" || fail "missing lic binary (set LIC or LIC_ROOT): $LIC_BIN"

LIC_BUILD_DIR="${LIC_BUILD_DIR:-$LIC_ROOT/build}"
test -d "$LIC_BUILD_DIR" || fail "missing LIC build dir: $LIC_BUILD_DIR"

export LI_REPO_ROOT="$LIC_ROOT"
export LI_LINK_RUNTIME_FULL="${LI_LINK_RUNTIME_FULL:-1}"

( cd "$LIC_BUILD_DIR" && "$LIC_BIN" build --allow-open-vc --no-lean-verify "$LI_TOML_ROOT/li-tests/corpus/parse_one.li" -o "$BIN" )

echo "phase-a0-parse-gate: parsing ${#GOOD_FILES[@]} good TOMLs"
for f in "${GOOD_FILES[@]}"; do
  "$BIN" "$f" || fail "parse failed: $f"
done

echo "phase-a0-parse-gate: OK"
