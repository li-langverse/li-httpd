#!/usr/bin/env bash
# Cursor guard — keep Li surface syntax `def`-only and prevent helper-code drift.
set -euo pipefail

if [[ "${LI_HOOK_ALLOW:-}" == "1" ]]; then
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo_root"

diff_file="$(mktemp)"
status_file="$(mktemp)"
trap 'rm -f "$diff_file" "$status_file"' EXIT

{
  git diff --unified=0 --no-ext-diff HEAD 2>/dev/null || true
  git diff --cached --unified=0 --no-ext-diff HEAD 2>/dev/null || true
} >"$diff_file"

{
  git diff --name-status --no-ext-diff HEAD 2>/dev/null || true
  git diff --cached --name-status --no-ext-diff HEAD 2>/dev/null || true
} >"$status_file"

python3 - "$diff_file" "$status_file" <<'PY'
import re
import sys
from pathlib import PurePosixPath

diff_path, status_path = sys.argv[1], sys.argv[2]

policy_paths = {
    ".cursor/hooks/guard-li-surface.sh",
    "agent-kit/.cursor/hooks/guard-li-surface.sh",
    ".cursor/rules/li-def-not-proc.mdc",
    "agent-kit/.cursor/rules/li-def-not-proc.mdc",
}

policy_prefixes = (
    "docs/release-notes/",
    "agent-kit/CHANGELOG.md",
)

helper_exts = {
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx",
    ".py", ".js", ".jsx", ".ts", ".tsx", ".rs", ".go", ".java",
}

helper_allowed_prefixes = (
    "compiler/",
    "runtime/",
    "scripts/",
    ".cursor/hooks/",
    "agent-kit/.cursor/hooks/",
    "agent-kit/scripts/",
    "benchmarks/harness/",
)

def is_policy_path(path: str) -> bool:
    return path in policy_paths or any(path.startswith(prefix) for prefix in policy_prefixes)

def is_helper_allowed(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in helper_allowed_prefixes)

violations = []
violation_set = set()

def add_violation(message: str) -> None:
    if message not in violation_set:
        violation_set.add(message)
        violations.append(message)
current = None
with open(diff_path, encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if line.startswith("+++ b/"):
            current = line[6:]
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        if current is None or is_policy_path(current):
            continue
        body = line[1:]
        if re.search(r"\bproc\b", body):
            add_violation(f"{current}: added forbidden Li surface token 'proc'")

seen = set()
with open(status_path, encoding="utf-8", errors="replace") as f:
    for raw in f:
        parts = raw.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        status = parts[0]
        path = parts[-1]
        if path in seen or not status.startswith("A"):
            continue
        seen.add(path)
        suffix = PurePosixPath(path).suffix
        if suffix in helper_exts and not is_helper_allowed(path):
            add_violation(
                f"{path}: new non-Li helper code outside compiler/runtime/scripts/hooks boundary"
            )

if violations:
    print("li surface guard blocked this diff:", file=sys.stderr)
    for item in violations[:20]:
        print(f"  - {item}", file=sys.stderr)
    if len(violations) > 20:
        print(f"  ... {len(violations) - 20} more", file=sys.stderr)
    print(
        "Use Li `def` and `.li` package code. Set LI_HOOK_ALLOW=1 only for an explicitly reviewed legacy compiler/runtime exception.",
        file=sys.stderr,
    )
    sys.exit(2)
PY
