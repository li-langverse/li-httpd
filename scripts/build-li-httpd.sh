#!/usr/bin/env bash
# Build li-httpd via lic (compiler + C runtime live in the lic monorepo).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIC_ROOT="${LIC_ROOT:-$ROOT/../lic-pure-https}"
if [[ ! -f "$LIC_ROOT/scripts/build-li-httpd.sh" ]] && [[ -f "$ROOT/../lic/scripts/build-li-httpd.sh" ]]; then
  LIC_ROOT="$ROOT/../lic"
fi
if [[ ! -f "$LIC_ROOT/scripts/build-li-httpd.sh" ]]; then
  echo "build-li-httpd: clone lic and set LIC_ROOT (needs scripts/build-li-httpd.sh)" >&2
  exit 1
fi
LIC_ROOT="$(cd "$LIC_ROOT" && pwd)"
export LI_REPO_ROOT="$LIC_ROOT"
mkdir -p "$ROOT/build"
( cd "$LIC_ROOT" && ./scripts/build-li-httpd.sh )
if [[ -f "$LIC_ROOT/build/li-httpd" ]]; then
  cp -f "$LIC_ROOT/build/li-httpd" "$ROOT/build/li-httpd"
  echo "build-li-httpd: copied -> $ROOT/build/li-httpd"
fi
