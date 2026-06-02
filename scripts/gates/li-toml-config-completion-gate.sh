#!/usr/bin/env bash
# Full sprint completion — all phase gates green.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATES=(
  phase-0-prep-gate.sh
  phase-a0-parse-gate.sh
  phase-b1-parity-gate.sh
  phase-b2-serve-gate.sh
  phase-c-retire-c-gate.sh
  phase-d-done-gate.sh
)
for g in "${GATES[@]}"; do
  bash "$ROOT/scripts/gates/$g"
done
echo "li-toml-config-completion-gate: OK"
