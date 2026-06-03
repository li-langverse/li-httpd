#!/usr/bin/env python3
"""Flatten validated li-httpd.toml to httpd.runtime.conf for C loader.

Usage:
  python3 scripts/flatten-httpd-config.py li-tests/config_desugar/good/agent_gateway.toml \\
    -o /tmp/httpd.runtime.conf
  ./build/li-httpd /tmp/httpd.runtime.conf
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from urllib.parse import urlparse

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

from httpd_config import (
    ConfigError,
    HttpdConfig,
    load_httpd_config,
    load_httpd_full,
    load_httpd_sites,
)
from httpd_leak_censor import (
    PATTERN_IDS,
    generated_paths_for_config,
    leak_censor_enabled,
)
from httpd_m15 import ConfigError as M15Error, parse_duration, validate_route_match
from httpd_m2 import ConfigError as M2Error, m2_flatten_lines
from httpd_m3 import ConfigError as M3Error, m3_flatten_lines
from httpd_tls import ConfigError as TlsError, tls_flatten_lines


def parse_listen(raw: str) -> int:
    raw = raw.strip()
    if raw.startswith(":"):
        return int(raw[1:])
    if ":" in raw:
        return int(raw.rsplit(":", 1)[1])
    return int(raw)


def peer_host_port(url: str) -> tuple[str, int]:
    u = urlparse(url.strip())
    if u.scheme not in ("http", "https"):
        raise ValueError(f"peer URL must be http(s): {url!r}")
    host = u.hostname or "127.0.0.1"
    if not u.port:
        raise ValueError(f"peer URL must include explicit port: {url!r}")
    return host, int(u.port)


def route_pool_id(action: str) -> str:
    if action.startswith("proxy:"):
        return action.split(":", 1)[1]
    return ""


def emit_route_line(r, vhost: str) -> str:
    kind = r.path_kind if r.path_kind in ("exact", "prefix", "prefix_strip") else "prefix"
    action = "proxy" if r.action.startswith("proxy:") else "static"
    pool = route_pool_id(r.action)
    v = vhost or ""
    rrps = getattr(r, "rate_limit_rps", 0)
    rburst = getattr(r, "rate_limit_burst", 0)
    if rrps > 0:
        burst = rburst if rburst > 0 else rrps
        return f"route={r.method}|{r.path}|{kind}|{action}|{pool}|{v}|{rrps}|{burst}"
    return f"route={r.method}|{r.path}|{kind}|{action}|{pool}|{v}"


def flatten_site_routes(site: HttpdConfig, lines: list[str]) -> bool:
    proxy_any = False
    for r in site.routes:
        if r.action.startswith("proxy:"):
            proxy_any = True
        lines.append(emit_route_line(r, site.host))
    return proxy_any


def flatten_upstreams(upstreams: dict[str, list[str]], lines: list[str]) -> None:
    for pool_id, peers in upstreams.items():
        lines.append(f"upstream_pool={pool_id}")
        for peer in peers:
            host, port = peer_host_port(peer)
            lines.append(f"upstream_peer={pool_id}|{host}|{port}")


def flatten(cfg_path: Path) -> list[str]:
    load_httpd_config(cfg_path)
    data = tomllib.loads(cfg_path.read_text(encoding="utf-8"))
    lines: list[str] = []
    server = data.get("server") or {}
    listen = server.get("listen")
    if listen:
        lines.append(f"listen_port={parse_listen(str(listen))}")
    root = server.get("document_root")
    if root:
        rp = Path(str(root))
        if not rp.is_absolute():
            rp = (cfg_path.parent / rp).resolve()
        lines.append(f"document_root={rp}")

    auth = data.get("auth") or {}
    if isinstance(auth, dict):
        req = auth.get("require_bearer")
        if req is not None:
            on = str(req).lower() not in ("0", "false", "no")
            lines.append(f"auth_required={1 if on else 0}")
        keys = auth.get("keys")
        if isinstance(keys, list):
            for key in keys:
                k = str(key).strip()
                if k:
                    lines.append(f"auth_key={k}")

    health = data.get("health") or {}
    if isinstance(health, dict):
        if health.get("max_fails") is not None:
            lines.append(f"health_max_fails={int(health['max_fails'])}")
        ft = health.get("fail_timeout") or health.get("fail_timeout_sec")
        if ft is not None:
            s = str(ft).strip().rstrip("s")
            if s.isdigit():
                lines.append(f"health_fail_timeout_sec={int(s)}")

    limits = data.get("limits") or {}
    if limits.get("rate_limit_rps") is not None:
        lines.append(f"rate_limit_rps={int(limits['rate_limit_rps'])}")
    if limits.get("rate_limit_burst") is not None:
        lines.append(f"rate_limit_burst={int(limits['rate_limit_burst'])}")

    upstreams: dict[str, list[str]] = {}
    proxy_any = False

    if data.get("site") is not None:
        sites = load_httpd_sites(cfg_path)
        for site in sites:
            if not listen and site.listen:
                lines.append(f"listen_port={parse_listen(site.listen)}")
            upstreams = {**upstreams, **site.upstreams}
            if flatten_site_routes(site, lines):
                proxy_any = True
    else:
        full = load_httpd_full(cfg_path)
        upstreams = full.upstreams
        vhost = full.host
        for r in full.routes:
            if r.action.startswith("proxy:"):
                proxy_any = True
            lines.append(emit_route_line(r, vhost))

    flatten_upstreams(upstreams, lines)

    if proxy_any and not any(l.startswith("upstream_peer=") for l in lines):
        lines.append("proxy_all=1")

    lc = data.get("leak_censor") or {}
    if isinstance(lc, dict) and leak_censor_enabled(data):
        lines.append("leak_censor_enabled=1")
    else:
        lines.append("leak_censor_enabled=0")
    try:
        lines.extend(tls_flatten_lines(data, cfg_path))
    except TlsError as e:
        raise ConfigError(str(e)) from e
    try:
        lines.extend(m2_flatten_lines(data, cfg_path))
    except M2Error as e:
        raise ConfigError(str(e)) from e
    try:
        lines.extend(m3_flatten_lines(data, cfg_path))
    except M3Error as e:
        raise ConfigError(str(e)) from e

    return lines
def main() -> int:
    p = argparse.ArgumentParser(description="flatten li-httpd.toml to runtime.conf")
    p.add_argument("config", type=Path)
    p.add_argument("-o", "--output", type=Path, required=True)
    args = p.parse_args()
    if not args.config.is_file():
        print(f"flatten-httpd-config: missing {args.config}", file=sys.stderr)
        return 1
    try:
        lines = flatten(args.config)
    except (ConfigError, M15Error, M2Error, M3Error, TlsError, ValueError) as e:
        print(f"flatten-httpd-config: {e}", file=sys.stderr)
        return 1
    if not any(l.startswith("listen_port=") for l in lines):
        print("flatten-httpd-config: server.listen required", file=sys.stderr)
        return 1
    if not any(l.startswith("document_root=") for l in lines):
        print("flatten-httpd-config: server.document_root required", file=sys.stderr)
        return 1
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"flatten-httpd-config: wrote {args.output} ({len(lines)} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
