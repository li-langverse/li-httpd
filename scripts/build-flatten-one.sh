#!/usr/bin/env bash
# Build li-tests/corpus/flatten_one (phase B1 Li flatten harness).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIC_ROOT="${LIC_ROOT:-/workspace/lic}"
LIC_BIN="${LIC:-$LIC_ROOT/build/compiler/lic/lic}"
LI_TOML_ROOT="${LI_TOML_ROOT:-}"
if [[ -z "$LI_TOML_ROOT" ]]; then
  if [[ -f "$ROOT/../li-toml/li.toml" ]]; then
    LI_TOML_ROOT="$ROOT/../li-toml"
  else
    cands=( "$ROOT/../../li-toml/"*/repo )
    if (( ${#cands[@]} > 0 )); then
      LI_TOML_ROOT="$(ls -td "${cands[@]}" 2>/dev/null | awk 'NR==1{print; exit}')"
    fi
  fi
fi
test -x "$LIC_BIN" || { echo "build-flatten-one: missing lic: $LIC_BIN" >&2; exit 1; }
test -f "$LI_TOML_ROOT/li.toml" || { echo "build-flatten-one: missing li-toml (set LI_TOML_ROOT)" >&2; exit 1; }
test -f "$ROOT/li-tests/corpus/config/flatten_corpus.li" || {
  LIC_ROOT="$LIC_ROOT" python3 "$ROOT/scripts/gen-li-flatten-corpus.py"
}
export LI_REPO_ROOT="$LIC_ROOT" LI_LINK_RUNTIME_FULL="${LI_LINK_RUNTIME_FULL:-1}"
OUT="${FLATTEN_ONE_OUT:-$ROOT/build/flatten_one}"
mkdir -p "$(dirname "$OUT")"

# The compiler resolves ecosystem packages under "$LI_REPO_ROOT/packages".
# Ensure this repo is available there so imports like `toml` resolve.
PKG_LINK="$LIC_ROOT/packages/li-httpd-workflow"
mkdir -p "$(dirname "$PKG_LINK")"
if [[ -L "$PKG_LINK" ]]; then
  if [[ "$(readlink "$PKG_LINK")" != "$ROOT" ]]; then
    ln -sfn "$ROOT" "$PKG_LINK"
  fi
elif [[ -e "$PKG_LINK" ]]; then
  echo "build-flatten-one: expected symlink at $PKG_LINK, found non-link" >&2
  exit 1
else
  ln -s "$ROOT" "$PKG_LINK"
fi

( cd "$LIC_ROOT/build" && "$LIC_BIN" build --allow-open-vc --no-lean-verify \
  "$PKG_LINK/li-tests/corpus/flatten_one.li" -o "$OUT" )
echo "build-flatten-one: $OUT"
