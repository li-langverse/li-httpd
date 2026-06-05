#!/usr/bin/env python3
"""M1.5 agent gateway config: stream limits, model routing, OTel require (Python oracle)."""

from __future__ import annotations

import re
from typing import Any

class ConfigError(Exception):
    """Raised by M1.5 config validators (mirrors httpd_config.ConfigError)."""

DURATION_RE = re.compile(r"^(\d+)(s|m|h)?$", re.IGNORECASE)
STREAM_IDLE_MAX = 3600
STREAM_MAX_DURATION_CAP = 86400
CONCURRENT_STREAMS_MAX = 10_000
MODEL_VALUE_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$")


def parse_duration(raw: object, field: str) -> int:
    if raw is None:
        raise ConfigError(f"{field} is required for M1.5 agent proxy configs")
    s = str(raw).strip().lower()
    m = DURATION_RE.match(s)
    if not m:
        raise ConfigError(f"{field} must be a duration like 120s (got {raw!r})")
    n = int(m.group(1))
    unit = (m.group(2) or "s").lower()
    if unit == "m":
        n *= 60
    elif unit == "h":
        n *= 3600
    if n < 1:
        raise ConfigError(f"{field} must be positive")
    return n


def has_proxy_routes(data: dict[str, Any]) -> bool:
    routes = data.get("routes")
    if isinstance(routes, dict):
        return any(
            isinstance(a, str) and a.strip().startswith("proxy:")
            for a in routes.values()
        )
    if isinstance(routes, list):
        return any(
            isinstance(r, dict) and str(r.get("action", "")).startswith("proxy:")
            for r in routes
        )
    return False


def m15_profile_active(data: dict[str, Any]) -> bool:
    """M1.5 agent profile when stream limits, model routing, or OTel require appear."""
    limits = data.get("limits") or {}
    if limits.get("stream_idle_timeout") is not None:
        return True
    if limits.get("concurrent_streams") is not None:
        return True
    if _route_match_rows(data):
        return True
    routes = data.get("routes")
    if isinstance(routes, dict):
        for key in routes:
            if isinstance(key, str) and "require=traceparent" in key:
                return True
    return False


def validate_m15_limits(data: dict[str, Any]) -> None:
    if not m15_profile_active(data) or not has_proxy_routes(data):
        return
    limits = data.get("limits") or {}
    idle = parse_duration(limits.get("stream_idle_timeout"), "limits.stream_idle_timeout")
    if idle > STREAM_IDLE_MAX:
        raise ConfigError(
            f"limits.stream_idle_timeout must be <= {STREAM_IDLE_MAX}s (got {idle}s)"
        )
    max_dur = parse_duration(limits.get("stream_max_duration"), "limits.stream_max_duration")
    if max_dur > STREAM_MAX_DURATION_CAP:
        raise ConfigError(
            f"limits.stream_max_duration must be <= {STREAM_MAX_DURATION_CAP}s"
        )
    if max_dur < idle:
        raise ConfigError("limits.stream_max_duration must be >= limits.stream_idle_timeout")
    conc = limits.get("concurrent_streams")
    if conc is None:
        raise ConfigError(
            "limits.concurrent_streams is required when routes include proxy: (M1.5 agent gate)"
        )
    try:
        c = int(conc)
    except (TypeError, ValueError) as e:
        raise ConfigError("limits.concurrent_streams must be a positive integer") from e
    if c < 1 or c > CONCURRENT_STREAMS_MAX:
        raise ConfigError(
            f"limits.concurrent_streams must be in [1, {CONCURRENT_STREAMS_MAX}]"
        )


def collect_upstream_pools(data: dict[str, Any]) -> set[str]:
    pools: set[str] = set()
    nested = data.get("upstreams")
    if isinstance(nested, dict):
        pools.update(str(k) for k in nested.keys())
    for key in data:
        if key.startswith("upstreams.") and isinstance(data[key], dict):
            pools.add(key.split(".", 1)[1])
    return pools


def _route_match_rows(data: dict[str, Any]) -> list[Any] | None:
    rows = data.get("route.match")
    if isinstance(rows, list):
        return rows
    route_tbl = data.get("route")
    if isinstance(route_tbl, dict):
        nested = route_tbl.get("match")
        if isinstance(nested, list):
            return nested
    return None


def validate_route_match(data: dict[str, Any]) -> list[tuple[str, str, str]]:
    """Return list of (header, value, proxy_pool) from [[route.match]]."""
    rows = _route_match_rows(data)
    if rows is None:
        return []
    if not isinstance(rows, list):
        raise ConfigError("[[route.match]] must be an array of tables")
    pools = collect_upstream_pools(data)
    out: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for i, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ConfigError(f"route.match[{i}] must be a table")
        header = str(row.get("header", "")).strip().lower()
        value = str(row.get("value", "")).strip()
        proxy = str(row.get("proxy", "")).strip()
        if header != "x-model":
            raise ConfigError(
                f"route.match[{i}].header must be 'x-model' (literal enum, not {header!r})"
            )
        if not MODEL_VALUE_RE.match(value):
            raise ConfigError(
                f"route.match[{i}].value must be a literal model id (got {value!r})"
            )
        if not proxy or proxy not in pools:
            raise ConfigError(
                f"route.match[{i}].proxy {proxy!r} must name an [upstreams.*] pool"
            )
        key = (header, value)
        if key in seen:
            raise ConfigError(f"duplicate route.match for x-model={value!r}")
        seen.add(key)
        out.append((header, value, proxy))
    return out


def validate_inference_require(data: dict[str, Any]) -> None:
    """Proxy routes on /v1/* must declare require=traceparent in route key extras."""
    if not m15_profile_active(data):
        return
    routes = data.get("routes")
    if not isinstance(routes, dict):
        return
    for key, action in routes.items():
        if not isinstance(key, str) or not isinstance(action, str):
            continue
        if not action.strip().startswith("proxy:"):
            continue
        if "/v1/" not in key and not key.strip().endswith("/v1/*"):
            path_part = key.split(None, 1)
            path = path_part[1] if len(path_part) > 1 else ""
            if not path.startswith("/v1"):
                continue
        if "require=traceparent" not in key:
            raise ConfigError(
                f"inference proxy route {key!r} must include require=traceparent in route key (M1.5 OTel)"
            )
