#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys


def normalize_line(line: str) -> str:
    # Normalize absolute paths that point into this repo so goldens are stable
    # across isolated workflow directories.
    #
    # We only normalize when the value contains a known repo-relative anchor.
    anchors = [
        "li-tests/config/",
        "examples/",
    ]
    for anchor in anchors:
        # Replace any absolute path prefix ending right before the anchor.
        #
        # Example:
        #   document_root=/abs/.../repo/li-tests/config/good/public
        # becomes:
        #   document_root=<ROOT>/li-tests/config/good/public
        pattern = rf"=/.*/({re.escape(anchor)}.*)$"
        line = re.sub(pattern, r"=<ROOT>/\1", line)
    return line


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", help="Input file (default: stdin)")
    args = ap.parse_args()

    if args.path:
        with open(args.path, "r", encoding="utf-8") as f:
            src = f.read().splitlines(keepends=True)
    else:
        src = sys.stdin.read().splitlines(keepends=True)

    for line in src:
        sys.stdout.write(normalize_line(line))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

