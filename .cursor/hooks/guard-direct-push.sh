#!/usr/bin/env bash
# Cursor beforeShellExecution — block push to protected branches unless LI_HOOK_ALLOW=1.
set -euo pipefail
input="$(cat)"
cmd="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
if [[ "${LI_HOOK_ALLOW:-}" == "1" ]]; then
  exit 0
fi
case "$cmd" in
  *"git push"*"origin main"*|*"git push"*"origin dev"*|*"git push"*"origin master"*|\
  *"git push main"*|*"git push dev"*|*"git push master"*|\
  *"git push"*"langverse"*"main"*|*"git push -f"*|*"git push --force"*)
    echo "blocked: push to protected branch — use feature branch + PR (LI_HOOK_ALLOW=1 if intentional)" >&2
    exit 2
    ;;
esac
exit 0
