#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$ROOT/scripts/config-parity-check.sh"
echo "phase-b1-parity-gate: OK"
