#!/usr/bin/env bash
# Cursor beforeShellExecution — discourage printing likely secret files.
set -euo pipefail
input="$(cat)"
cmd="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
if [[ "${LI_HOOK_ALLOW:-}" == "1" ]]; then
  exit 0
fi
if echo "$cmd" | grep -qE '\.(env\.github|pem|key)$|/\.env\.github|credentials\.json'; then
  if echo "$cmd" | grep -qE '(cat|head|tail|less|more|echo|type)\s'; then
    echo "blocked: command may expose secrets; use env vars, not cat" >&2
    exit 2
  fi
fi
exit 0
