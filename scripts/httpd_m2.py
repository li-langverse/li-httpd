#!/usr/bin/env python3
"""M2 scale: TLS1.3 terminate, HTTP/2, WebSocket, circuit breaker, queue 429, webhook allowlist."""

from __future__ import annotations

import ipaddress
import re
from typing import Any
from urllib.parse import urlparse

from httpd_m15 import ConfigError as M15Error
from httpd_m15 import has_proxy_routes, parse_duration
from httpd_tls import ConfigError as TlsError
from httpd_tls import is_loopback_listen, is_public_listen, validate_tls_config

class ConfigError(Exception):
    """Raised by M2 config validators (mirrors httpd_config.ConfigError)."""


DURATION_RE = re.compile(r"^(\d+)(s|m|h)?$", re.IGNORECASE)
QUEUE_MAX_DEPTH_CAP = 10_000
QUEUE_MAX_WAIT_CAP = 3600
CB_ERROR_THRESHOLD_MAX = 1000
CB_WINDOW_SEC_MAX = 600
CB_OPEN_SEC_MAX = 600
HTTP2_MAX_STREAMS_CAP = 4096
WEBHOOK_ALLOW_MAX = 32
HTTPS_HOST_RE = re.compile(
    r"^https://[a-zA-Z0-9][a-zA-Z0-9._-]*(?::\d+)?(/[a-zA-Z0-9._~:/?#\[\]@!$&'()*+,;=-]*)?$"
)


def _route_queue_block(data: dict[str, Any]) -> dict[str, Any] | None:
    q = data.get("route.queue")
    if isinstance(q, dict):
        return q
    route = data.get("route")
    if isinstance(route, dict):
        nested = route.get("queue")
        if isinstance(nested, dict):
            return nested
    return None


def m2_profile_active(data: dict[str, Any]) -> bool:
    server = data.get("server") or {}
    if isinstance(server, dict):
        h2 = server.get("http2")
        if isinstance(h2, dict) and h2.get("enabled"):
            return True
        tls = server.get("tls")
        if isinstance(tls, dict) and tls.get("terminate"):
            return True
    if _route_queue_block(data) is not None or data.get("circuit_breaker") is not None:
        return True
    if data.get("webhooks") is not None:
        return True
    routes = data.get("routes")
    if isinstance(routes, dict):
        for key in routes:
            if isinstance(key, str) and "require=websocket" in key:
                return True
    return False


def _server_tls_block(data: dict[str, Any]) -> dict[str, Any]:
    server = data.get("server") or {}
    if not isinstance(server, dict):
        return {}
    tls = server.get("tls")
    return tls if isinstance(tls, dict) else {}


def validate_m2_tls_terminate(data: dict[str, Any], path: Any) -> None:
    if not m2_profile_active(data):
        return
    tls_nested = _server_tls_block(data)
    server = data.get("server") or {}
    listen = server.get("listen") if isinstance(server, dict) else None
    h2 = server.get("http2") if isinstance(server, dict) else None
    h2_on = isinstance(h2, dict) and str(h2.get("enabled", "")).lower() in ("1", "true", "yes")
    terminate = str(tls_nested.get("terminate", "")).lower() in ("1", "true", "yes")
    if h2_on and not terminate:
        raise ConfigError("server.http2.enabled requires server.tls.terminate = true (M2 ALPN)")
    if h2_on or terminate:
        profile = validate_tls_config(data, path)
        if profile is None:
            raise ConfigError("server.tls is required when M2 terminate or HTTP/2 is enabled")
        if profile.min_protocol != "1.3":
            raise ConfigError("M2 TLS terminate requires server.tls.min_protocol = \"1.3\"")
        if terminate and is_public_listen(listen) and profile.mode == "self_signed":
            ss = tls_nested.get("self_signed") or {}
            dev = isinstance(ss, dict) and str(ss.get("dev", "")).lower() in ("1", "true", "yes")
            if not dev and not is_loopback_listen(listen):
                raise ConfigError(
                    "M2 TLS terminate on public listen requires non-self_signed TLS or tls.self_signed.dev"
                )


def validate_m2_http2(data: dict[str, Any]) -> None:
    server = data.get("server") or {}
    if not isinstance(server, dict):
        return
    h2 = server.get("http2")
    if not isinstance(h2, dict):
        return
    enabled = str(h2.get("enabled", "")).lower() in ("1", "true", "yes")
    if not enabled:
        return
    max_streams = h2.get("max_concurrent_streams", 256)
    try:
        n = int(max_streams)
    except (TypeError, ValueError) as e:
        raise ConfigError("server.http2.max_concurrent_streams must be a positive integer") from e
    if n < 1 or n > HTTP2_MAX_STREAMS_CAP:
        raise ConfigError(
            f"server.http2.max_concurrent_streams must be in [1, {HTTP2_MAX_STREAMS_CAP}]"
        )


def validate_m2_route_queue(data: dict[str, Any]) -> None:
    q = _route_queue_block(data)
    if q is None:
        return
    if not isinstance(q, dict):
        raise ConfigError("[route.queue] must be a table")
    if not has_proxy_routes(data):
        raise ConfigError("[route.queue] requires at least one proxy: route (M2 backpressure)")
    depth = q.get("max_depth")
    if depth is None:
        raise ConfigError("route.queue.max_depth is required when [route.queue] is set")
    try:
        d = int(depth)
    except (TypeError, ValueError) as e:
        raise ConfigError("route.queue.max_depth must be a positive integer") from e
    if d < 1 or d > QUEUE_MAX_DEPTH_CAP:
        raise ConfigError(f"route.queue.max_depth must be in [1, {QUEUE_MAX_DEPTH_CAP}]")
    wait = parse_duration(q.get("max_wait"), "route.queue.max_wait")
    if wait > QUEUE_MAX_WAIT_CAP:
        raise ConfigError(f"route.queue.max_wait must be <= {QUEUE_MAX_WAIT_CAP}s")
    ra = q.get("retry_after")
    if ra is not None:
        parse_duration(ra, "route.queue.retry_after")


def validate_m2_circuit_breaker(data: dict[str, Any]) -> None:
    cb = data.get("circuit_breaker")
    if cb is None:
        return
    if not isinstance(cb, dict):
        raise ConfigError("[circuit_breaker] must be a table")
    if not has_proxy_routes(data):
        raise ConfigError("[circuit_breaker] requires proxy routes (M2 upstream protection)")
    try:
        thresh = int(cb.get("error_threshold", 0))
    except (TypeError, ValueError) as e:
        raise ConfigError("circuit_breaker.error_threshold must be a positive integer") from e
    if thresh < 1 or thresh > CB_ERROR_THRESHOLD_MAX:
        raise ConfigError(
            f"circuit_breaker.error_threshold must be in [1, {CB_ERROR_THRESHOLD_MAX}]"
        )
    try:
        window = int(cb.get("window_sec", 0))
    except (TypeError, ValueError) as e:
        raise ConfigError("circuit_breaker.window_sec must be a positive integer") from e
    if window < 1 or window > CB_WINDOW_SEC_MAX:
        raise ConfigError(f"circuit_breaker.window_sec must be in [1, {CB_WINDOW_SEC_MAX}]")
    try:
        open_sec = int(cb.get("open_duration_sec", 0))
    except (TypeError, ValueError) as e:
        raise ConfigError("circuit_breaker.open_duration_sec must be a positive integer") from e
    if open_sec < 1 or open_sec > CB_OPEN_SEC_MAX:
        raise ConfigError(
            f"circuit_breaker.open_duration_sec must be in [1, {CB_OPEN_SEC_MAX}]"
        )
    probes = cb.get("half_open_probes", 1)
    try:
        p = int(probes)
    except (TypeError, ValueError) as e:
        raise ConfigError("circuit_breaker.half_open_probes must be a positive integer") from e
    if p < 1 or p > 8:
        raise ConfigError("circuit_breaker.half_open_probes must be in [1, 8]")


def _webhook_host_blocked(host: str) -> bool:
    if not host:
        return True
    h = host.lower().strip("[]")
    if h in ("localhost", "metadata.google.internal"):
        return True
    if h.endswith(".local") or h.endswith(".internal"):
        return True
    try:
        addr = ipaddress.ip_address(h)
        if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_reserved:
            return True
    except ValueError:
        pass
    return False


def validate_m2_webhooks(data: dict[str, Any]) -> list[str]:
    wh = data.get("webhooks")
    if wh is None:
        return []
    if not isinstance(wh, dict):
        raise ConfigError("[webhooks] must be a table")
    allow = wh.get("allow")
    if allow is None:
        raise ConfigError("webhooks.allow is required when [webhooks] is set (SSRF-safe egress)")
    if not isinstance(allow, list) or not allow:
        raise ConfigError("webhooks.allow must be a non-empty array of https URLs")
    if len(allow) > WEBHOOK_ALLOW_MAX:
        raise ConfigError(f"webhooks.allow must have at most {WEBHOOK_ALLOW_MAX} entries")
    out: list[str] = []
    seen: set[str] = set()
    for i, raw in enumerate(allow):
        url = str(raw).strip()
        if not HTTPS_HOST_RE.match(url):
            raise ConfigError(
                f"webhooks.allow[{i}] must be https://host/path (no userinfo, no private hosts)"
            )
        parsed = urlparse(url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise ConfigError(f"webhooks.allow[{i}] must use https with a public hostname")
        if _webhook_host_blocked(parsed.hostname):
            raise ConfigError(f"webhooks.allow[{i}] hostname is not allowed (SSRF guard)")
        if url in seen:
            raise ConfigError(f"duplicate webhooks.allow entry: {url!r}")
        seen.add(url)
        out.append(url)
    return out


def validate_m2_websocket_routes(data: dict[str, Any]) -> None:
    routes = data.get("routes")
    if not isinstance(routes, dict):
        return
    for key, action in routes.items():
        if not isinstance(key, str) or "require=websocket" not in key:
            continue
        if not isinstance(action, str) or not action.strip().startswith("proxy:"):
            raise ConfigError(
                f"WebSocket route {key!r} must use proxy: action (M2 bidirectional tools)"
            )


def validate_m2_config(data: dict[str, Any], path: Any) -> None:
    """Run all M2 validators; raises ConfigError on violation."""
    try:
        validate_m2_tls_terminate(data, path)
        validate_m2_http2(data)
        validate_m2_route_queue(data)
        validate_m2_circuit_breaker(data)
        validate_m2_webhooks(data)
        validate_m2_websocket_routes(data)
    except (M15Error, TlsError) as e:
        raise ConfigError(str(e)) from e


def m2_flatten_lines(data: dict[str, Any], cfg_path: Any) -> list[str]:
    if not m2_profile_active(data):
        return ["m2_enabled=0"]
    lines = ["m2_enabled=1"]
    tls_nested = _server_tls_block(data)
    if str(tls_nested.get("terminate", "")).lower() in ("1", "true", "yes"):
        lines.append("m2_tls_terminate=1")
        lines.append("m2_tls_min_protocol=1.3")
    server = data.get("server") or {}
    h2 = server.get("http2") if isinstance(server, dict) else None
    if isinstance(h2, dict) and str(h2.get("enabled", "")).lower() in ("1", "true", "yes"):
        lines.append("m2_http2_enabled=1")
        ms = int(h2.get("max_concurrent_streams", 256))
        lines.append(f"m2_http2_max_streams={ms}")
    q = _route_queue_block(data)
    if isinstance(q, dict):
        lines.append(f"m2_queue_max_depth={int(q['max_depth'])}")
        lines.append(f"m2_queue_max_wait_sec={parse_duration(q.get('max_wait'), 'route.queue.max_wait')}")
        ra = q.get("retry_after")
        if ra is not None:
            lines.append(f"m2_queue_retry_after_sec={parse_duration(ra, 'route.queue.retry_after')}")
        else:
            lines.append("m2_queue_retry_after_sec=1")
    cb = data.get("circuit_breaker")
    if isinstance(cb, dict):
        lines.append(f"m2_cb_error_threshold={int(cb['error_threshold'])}")
        lines.append(f"m2_cb_window_sec={int(cb['window_sec'])}")
        lines.append(f"m2_cb_open_duration_sec={int(cb['open_duration_sec'])}")
        lines.append(f"m2_cb_half_open_probes={int(cb.get('half_open_probes', 1))}")
    wh = data.get("webhooks")
    if isinstance(wh, dict):
        for raw in wh.get("allow") or []:
            lines.append(f"m2_webhook_allow={str(raw).strip()}")
    routes = data.get("routes")
    if isinstance(routes, dict):
        for key, action in routes.items():
            if isinstance(key, str) and "require=websocket" in key and isinstance(action, str):
                m = re.match(r"^([A-Z]+)\s+(/[^\s#]+)", key.strip())
                if m:
                    lines.append(f"route_require={m.group(1)}|{m.group(2)}|websocket")
    return lines
