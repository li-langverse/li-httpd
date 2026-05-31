#!/usr/bin/env bash
# Cursor afterFileEdit — roadmap governance paths need human merge.
set -euo pipefail
input="$(cat)"
path="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null || true)"
case "$path" in
  docs/*|proposals/*)
    echo "roadmap governance edit: open PR; human reviewer must merge (agents do not merge docs/proposals)" >&2
    ;;
esac
exit 0
