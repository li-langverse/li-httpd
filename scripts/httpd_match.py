#!/usr/bin/env python3
"""match_route simulator for routing TOML cases (M1 prep)."""

from __future__ import annotations

import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

from httpd_config import CanonicalRoute, ConfigError, load_httpd_config


@dataclass
class RequestView:
    method: str
    host: str
    path: str


def normalize_path(path: str) -> str:
    parts = [p for p in path.split("/") if p]
    return "/" + "/".join(parts) if parts else "/"


def route_matches(route: CanonicalRoute, req: RequestView) -> bool:
    if route.method != req.method:
        return False
    p = normalize_path(req.path)
    base = normalize_path(route.path)
    if route.path_kind == "exact":
        return p == base
    if route.path_kind == "prefix":
        return p == base or p.startswith(base.rstrip("/") + "/")
    if route.path_kind == "prefix_strip":
        return p == base or p.startswith(base.rstrip("/") + "/")
    return False


def match_route(routes: list[CanonicalRoute], req: RequestView) -> CanonicalRoute | None:
    for r in sorted(routes, key=lambda x: x.priority):
        if route_matches(r, req):
            return r
    return None


def action_kind(action: str) -> str:
    if action.startswith("static:"):
        return "static"
    if action.startswith("proxy:"):
        return "proxy"
    return "unknown"


def run_cases(config: Path, cases: Path) -> int:
    routes = load_httpd_config(config)
    data = tomllib.loads(cases.read_text(encoding="utf-8"))
    failed = 0
    for case in data.get("case") or []:
        cid = case.get("id", "?")
        req_d = case.get("request") or {}
        req = RequestView(
            method=str(req_d.get("method", "GET")),
            host=str(req_d.get("host", "")),
            path=str(req_d.get("path", "/")),
        )
        expect = case.get("expect") or {}
        got = match_route(routes, req)
        if "status" in expect and int(expect["status"]) == 404:
            if got is not None:
                print(f"FAIL {cid}: expected no match, got {got.name}", file=sys.stderr)
                failed += 1
            else:
                print(f"OK {cid}: no match")
            continue
        exp_route = expect.get("route")
        if got is None:
            print(f"FAIL {cid}: no match for {req.method} {req.path}", file=sys.stderr)
            failed += 1
            continue
        if exp_route and got.name != exp_route:
            print(
                f"FAIL {cid}: route {got.name!r} != {exp_route!r}",
                file=sys.stderr,
            )
            failed += 1
            continue
        exp_action = expect.get("action")
        if exp_action and action_kind(got.action) != exp_action:
            print(
                f"FAIL {cid}: action {action_kind(got.action)!r} != {exp_action!r}",
                file=sys.stderr,
            )
            failed += 1
            continue
        print(f"OK {cid}: {got.name} -> {got.action}")
    return failed


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: httpd_match.py <config.toml> <cases.toml>", file=sys.stderr)
        return 2
    config = Path(sys.argv[1])
    cases = Path(sys.argv[2])
    try:
        n = run_cases(config, cases)
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 1
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main())
