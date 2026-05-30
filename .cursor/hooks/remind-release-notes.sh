#!/usr/bin/env bash
# Cursor stop — remind if code changed but release notes likely missing.
set -euo pipefail
ROOT="${CURSOR_PROJECT_DIR:-$(pwd)}"
if ! git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

changed="$(git -C "$ROOT" diff --name-only HEAD 2>/dev/null; git -C "$ROOT" diff --name-only --cached 2>/dev/null)" || exit 0
[[ -n "$changed" ]] || exit 0

code=0
notes=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    CHANGELOG.md|docs/release-notes/*|*.md)
      notes=1
      ;;
    agent-kit/*|.cursor/*|docs/ecosystem/*)
      notes=1
      ;;
    *)
      case "$f" in
        *.md|LICENSE|SECURITY.md|.gitignore) ;;
        *) code=1 ;;
      esac
      ;;
  esac
done <<< "$changed"

if [[ "$code" -eq 1 && "$notes" -eq 0 ]]; then
  echo "release notes: update CHANGELOG.md + docs/release-notes/YYYY-MM-DD-slug.md (skill write-li-release-notes)" >&2
  echo "  policy: roadmap docs/ecosystem/release-notes.md" >&2
fi
exit 0
