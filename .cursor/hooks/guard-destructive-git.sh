#!/usr/bin/env bash
# Cursor beforeShellExecution — block destructive git unless LI_HOOK_ALLOW=1.
set -euo pipefail
input="$(cat)"
cmd="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
if [[ "${LI_HOOK_ALLOW:-}" == "1" ]]; then
  exit 0
fi
case "$cmd" in
  *"git push"*"--force"*|*"git push -f"*)
    echo "blocked: force push (set LI_HOOK_ALLOW=1 if intentional)" >&2
    exit 2
    ;;
  *"git reset --hard"*|*"git commit"*"--no-verify"*)
    echo "blocked: destructive git (set LI_HOOK_ALLOW=1 if intentional)" >&2
    exit 2
    ;;
esac
exit 0
