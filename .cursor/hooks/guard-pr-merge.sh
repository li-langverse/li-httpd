#!/usr/bin/env bash
# Cursor beforeShellExecution — agents must not merge PRs (human/reviewer only).
set -euo pipefail
input="$(cat)"
cmd="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null || true)"
[[ -n "$cmd" ]] || exit 0
if [[ "${LI_HOOK_ALLOW:-}" == "1" ]]; then
  exit 0
fi
case "$cmd" in
  *"gh pr merge"*|*"gh api"*"pulls"*"merge"*|*"git merge"*"origin/main"*|*"git merge"*"origin/dev"*)
    echo "blocked: PR merge is human-only — open PR and request review (LI_HOOK_ALLOW=1 if intentional)" >&2
    exit 2
    ;;
esac
exit 0
