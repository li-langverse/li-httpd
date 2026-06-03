#!/usr/bin/env python3
"""Apply vhost + named upstream pool support to lic runtime before building li-httpd.

Run from li-httpd with LIC_ROOT set (compiler tree only — not where edge config lives).
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIC = Path(
    sys.argv[1]
    if len(sys.argv) > 1
    else (__import__("os").environ.get("LIC_ROOT") or str(ROOT.parent / "lic-pure-https"))
)
PATCHER = ROOT / "scripts" / "_lic_patch_vhost_net.py"

if __name__ == "__main__":
    if not (LIC / "runtime" / "li_rt_net.c").is_file():
        print(f"patch-vhost-runtime: missing {LIC}/runtime/li_rt_net.c", file=sys.stderr)
        raise SystemExit(1)
    if not PATCHER.is_file():
        print(f"patch-vhost-runtime: missing {PATCHER}", file=sys.stderr)
        raise SystemExit(1)
    raise SystemExit(subprocess.call([sys.executable, str(PATCHER), str(LIC)], cwd=LIC))
