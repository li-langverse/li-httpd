#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Rebuild Li flatten harness so corpus updates cannot pass with a stale binary.
bash "$ROOT/scripts/build-flatten-one.sh"
bash "$ROOT/scripts/config-parity-check.sh"
echo "phase-b1-parity-gate: OK"
