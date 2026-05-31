#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROADMAP="${LI_ROADMAP_ROOT:-$ROOT/../roadmap}"
exec "$ROADMAP/scripts/install-agent-kit.sh" "li-httpd" "$@"
