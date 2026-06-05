#!/usr/bin/env python3
"""M3 optional: L4 stream proxy config + token-budget hooks (RFC + validate/flatten)."""

from __future__ import annotations

import ipaddress
import re
from typing import Any

from httpd_m15 import ConfigError as M15Error
from httpd_m15 import has_proxy_routes
from httpd_m2 import ConfigError as M2Error
from httpd_tls import ConfigError as TlsError
from httpd_tls import is_loopback_listen

class ConfigError(Exception):
    """Raised by M3 config validators."""


TOKEN_BUDGET_HEADER_RE = re.compile(r"^x-[a-z0-9-]+$")
TOKEN_BUDGET_MAX_CAP = 10_000_000
L4_MAX_CONNECTIONS_CAP = 10_000
L4_UPSTREAM_PORT_MAX = 65535


def _server_block(data: dict[str, Any]) -> dict[str, Any]:
    server = data.get("server")
    return server if isinstance(server, dict) else {}


def _limits_block(data: dict[str, Any]) -> dict[str, Any]:
    limits = data.get("limits")
    return limits if isinstance(limits, dict) else {}


def _l4_block(data: dict[str, Any]) -> dict[str, Any] | None:
    server = _server_block(data)
    l4 = server.get("l4_stream")
    if isinstance(l4, dict):
        return l4
    return None


def _token_budget_block(data: dict[str, Any]) -> dict[str, Any] | None:
    limits = _limits_block(data)
    tb = limits.get("token_budget")
    if isinstance(tb, dict):
        return tb
    return None


def m3_profile_active(data: dict[str, Any]) -> bool:
    l4 = _l4_block(data)
    if isinstance(l4, dict) and str(l4.get("enabled", "")).lower() in ("1", "true", "yes"):
        return True
    tb = _token_budget_block(data)
    if isinstance(tb, dict) and str(tb.get("enabled", "")).lower() in ("1", "true", "yes"):
        return True
    return False


def _parse_host_port(listen: str) -> tuple[str, int]:
    if ":" not in listen:
        raise ConfigError("listen must be host:port")
    host, _, port_s = listen.rpartition(":")
    try:
        port = int(port_s)
    except ValueError as e:
        raise ConfigError("listen port must be an integer") from e
    if port < 1 or port > L4_UPSTREAM_PORT_MAX:
        raise ConfigError("listen port out of range")
    return host.strip(), port


def _upstream_host_blocked(hostname: str, allow_private: bool) -> bool:
    if allow_private:
        return False
    try:
        addr = ipaddress.ip_address(hostname)
    except ValueError:
        return False
    return addr.is_private or addr.is_loopback or addr.is_link_local


def validate_m3_l4_stream(data: dict[str, Any], path: Any) -> None:
    l4 = _l4_block(data)
    if l4 is None:
        return
    enabled = str(l4.get("enabled", "")).lower() in ("1", "true", "yes")
    if not enabled:
        return
    listen = l4.get("listen")
    if not isinstance(listen, str) or not listen.strip():
        raise ConfigError("server.l4_stream.listen is required when l4_stream.enabled")
    host, _port = _parse_host_port(listen.strip())
    if not is_loopback_listen(listen.strip()):
        server = _server_block(data)
        tls = server.get("tls")
        if not isinstance(tls, dict) or str(tls.get("mode", "")).lower() in ("", "off", "none"):
            raise ConfigError(
                "server.l4_stream on public listen requires [server.tls] (TLS terminate or loopback only)"
            )
    upstream_host = l4.get("upstream_host")
    if not isinstance(upstream_host, str) or not upstream_host.strip():
        raise ConfigError("server.l4_stream.upstream_host is required when enabled")
    upstream_host = upstream_host.strip()
    if "/" in upstream_host or ":" in upstream_host:
        raise ConfigError("server.l4_stream.upstream_host must be a hostname (no path or port)")
    allow_private = str(l4.get("allow_private_upstream", "")).lower() in ("1", "true", "yes")
    if _upstream_host_blocked(upstream_host, allow_private):
        raise ConfigError("server.l4_stream.upstream_host is not allowed (SSRF guard)")
    try:
        upstream_port = int(l4.get("upstream_port"))
    except (TypeError, ValueError) as e:
        raise ConfigError("server.l4_stream.upstream_port is required and must be an integer") from e
    if upstream_port < 1 or upstream_port > L4_UPSTREAM_PORT_MAX:
        raise ConfigError("server.l4_stream.upstream_port out of range")
    max_conn = l4.get("max_connections", 256)
    try:
        mc = int(max_conn)
    except (TypeError, ValueError) as e:
        raise ConfigError("server.l4_stream.max_connections must be an integer") from e
    if mc < 1 or mc > L4_MAX_CONNECTIONS_CAP:
        raise ConfigError(f"server.l4_stream.max_connections must be in [1, {L4_MAX_CONNECTIONS_CAP}]")
    _ = path  # reserved for future path-relative errors


def validate_m3_token_budget(data: dict[str, Any]) -> None:
    tb = _token_budget_block(data)
    if tb is None:
        return
    enabled = str(tb.get("enabled", "")).lower() in ("1", "true", "yes")
    if not enabled:
        return
    header = str(tb.get("header", "x-token-budget")).strip().lower()
    if not TOKEN_BUDGET_HEADER_RE.match(header):
        raise ConfigError(
            "limits.token_budget.header must match x-[a-z0-9-]+ (custom dimension, not Authorization)"
        )
    try:
        cap = int(tb.get("max_per_request", 0))
    except (TypeError, ValueError) as e:
        raise ConfigError("limits.token_budget.max_per_request must be a positive integer") from e
    if cap < 1 or cap > TOKEN_BUDGET_MAX_CAP:
        raise ConfigError(f"limits.token_budget.max_per_request must be in [1, {TOKEN_BUDGET_MAX_CAP}]")
    if has_proxy_routes(data) and cap < 1:
        raise ConfigError("limits.token_budget.max_per_request required when token_budget enabled on proxy routes")


def validate_m3_config(data: dict[str, Any], path: Any) -> None:
    """Run all M3 validators; raises ConfigError on violation."""
    try:
        validate_m3_l4_stream(data, path)
        validate_m3_token_budget(data)
    except (M15Error, M2Error, TlsError) as e:
        raise ConfigError(str(e)) from e


def m3_flatten_lines(data: dict[str, Any], cfg_path: Any) -> list[str]:
    if not m3_profile_active(data):
        return ["m3_enabled=0"]
    lines = ["m3_enabled=1"]
    l4 = _l4_block(data)
    if isinstance(l4, dict) and str(l4.get("enabled", "")).lower() in ("1", "true", "yes"):
        lines.append("m3_l4_enabled=1")
        listen = str(l4.get("listen", "")).strip()
        host, port = _parse_host_port(listen)
        lines.append(f"m3_l4_listen_host={host}")
        lines.append(f"m3_l4_listen_port={port}")
        lines.append(f"m3_l4_upstream_host={str(l4.get('upstream_host', '')).strip()}")
        lines.append(f"m3_l4_upstream_port={int(l4.get('upstream_port'))}")
        lines.append(f"m3_l4_max_connections={int(l4.get('max_connections', 256))}")
    tb = _token_budget_block(data)
    if isinstance(tb, dict) and str(tb.get("enabled", "")).lower() in ("1", "true", "yes"):
        lines.append("m3_token_budget_enabled=1")
        header = str(tb.get("header", "x-token-budget")).strip().lower()
        lines.append(f"m3_token_budget_header={header}")
        lines.append(f"m3_token_budget_max={int(tb.get('max_per_request'))}")
        reject = tb.get("reject_over_cap", True)
        lines.append(
            "m3_token_budget_reject_over_cap=1"
            if str(reject).lower() not in ("0", "false", "no")
            else "m3_token_budget_reject_over_cap=0"
        )
    _ = cfg_path
    return lines
