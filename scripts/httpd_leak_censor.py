#!/usr/bin/env python3
"""M1.5 leak_censor config oracle + generated path merge."""

from __future__ import annotations

from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

from schema_catalog import merge_catalog, parse_migrations_dir

PATTERN_IDS = frozenset({"openai_sk", "jwt_bearer", "pem_private"})
ON_DETECT_VALUES = frozenset({"redact", "block_502", "abort_stream"})
GENERATED_FILENAME = "leak_censor.generated.toml"


class ConfigError(Exception):
    """Raised by leak_censor validators."""


def load_generated(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    return tomllib.loads(path.read_text(encoding="utf-8"))


def generated_paths_for_config(cfg_dir: Path, include_generated: bool) -> tuple[list[str], list[str]]:
    if not include_generated:
        return [], []
    gen_path = cfg_dir / GENERATED_FILENAME
    gen = load_generated(gen_path)
    paths: list[str] = []
    headers: list[str] = []
    nested = gen.get("generated") or {}
    if isinstance(nested, dict):
        jp = nested.get("json_paths") or {}
        if isinstance(jp, dict):
            raw = jp.get("paths") or []
            if isinstance(raw, list):
                paths.extend(str(p) for p in raw)
        hdr = nested.get("headers") or {}
        if isinstance(hdr, dict):
            raw_h = hdr.get("deny_names") or []
            if isinstance(raw_h, list):
                headers.extend(str(h) for h in raw_h)
    block = gen.get("generated.json_paths")
    if isinstance(block, dict):
        raw = block.get("paths") or []
        if isinstance(raw, list):
            paths.extend(str(p) for p in raw)
    hdr_flat = gen.get("generated.headers")
    if isinstance(hdr_flat, dict):
        raw_h = hdr_flat.get("deny_names") or []
        if isinstance(raw_h, list):
            headers.extend(str(h) for h in raw_h)
    return paths, headers


def validate_patterns(raw: object, field: str) -> None:
    if raw is None:
        return
    if not isinstance(raw, list):
        raise ConfigError(f"{field} must be an array of pattern enum ids")
    for item in raw:
        pid = str(item).strip()
        if pid not in PATTERN_IDS:
            raise ConfigError(
                f"{field}: unknown pattern id {pid!r} (allowed: {', '.join(sorted(PATTERN_IDS))})"
            )


def validate_deny_paths(raw: object, field: str) -> list[str]:
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise ConfigError(f"{field} must be an array of JSONPath strings")
    out: list[str] = []
    for item in raw:
        p = str(item).strip()
        if not p.startswith("$."):
            raise ConfigError(f"{field}: deny path must start with '$.' (got {p!r})")
        out.append(p)
    return out


def leak_censor_enabled(data: dict[str, Any]) -> bool:
    block = data.get("leak_censor") or {}
    if not isinstance(block, dict):
        return False
    en = block.get("enabled")
    if en is None:
        return False
    return str(en).lower() not in ("0", "false", "no")


def validate_leak_censor(data: dict[str, Any], cfg_path: Path | None = None) -> list[str]:
    """Validate [leak_censor] and nested tables. Returns warnings (non-fatal)."""
    warnings: list[str] = []
    block = data.get("leak_censor")
    if not isinstance(block, dict):
        return warnings

    on_detect = block.get("on_detect")
    if on_detect is not None and str(on_detect) not in ON_DETECT_VALUES:
        raise ConfigError(
            f"leak_censor.on_detect must be one of {sorted(ON_DETECT_VALUES)} (got {on_detect!r})"
        )

    json_block = block.get("json") if isinstance(block.get("json"), dict) else {}
    if not isinstance(json_block, dict):
        for key in data:
            if key == "leak_censor.json" or key.startswith("leak_censor.json."):
                json_block = data.get("leak_censor.json") or {}
                break
    if not json_block:
        json_block = data.get("leak_censor.json") or {}

    pat_block = block.get("patterns") if isinstance(block.get("patterns"), dict) else {}
    if not pat_block:
        pat_block = data.get("leak_censor.patterns") or {}

    user_paths = validate_deny_paths(
        json_block.get("deny_paths") if isinstance(json_block, dict) else None,
        "leak_censor.json.deny_paths",
    )
    include_gen = json_block.get("include_generated") if isinstance(json_block, dict) else False
    if include_gen is None:
        include_gen = False
    include_gen = str(include_gen).lower() not in ("0", "false", "no")

    if cfg_path is not None:
        gen_paths, _ = generated_paths_for_config(cfg_path.parent, include_gen)
        merged = list(dict.fromkeys(user_paths + gen_paths))
        if include_gen and not gen_paths and leak_censor_enabled(data):
            warnings.append(
                f"leak_censor.json.include_generated=true but {GENERATED_FILENAME} missing or empty "
                f"(run: python3 scripts/setup-censor-httpd.py --migrations <dir> -o {cfg_path.parent})"
            )
        if len(merged) > 256:
            raise ConfigError("merged deny_paths exceeds 256 entries")
    else:
        merged = user_paths

    validate_patterns(
        pat_block.get("allow") if isinstance(pat_block, dict) else None,
        "leak_censor.patterns.allow",
    )

    profile = str((data.get("profile") or "")).lower()
    if profile == "production" and not leak_censor_enabled(data):
        ack = block.get("ack_disable_censor")
        if str(ack).lower() not in ("1", "true", "yes"):
            warnings.append(
                "production profile with leak_censor.enabled=false — set ack_disable_censor=true to acknowledge"
            )

    hdr_block = block.get("headers") if isinstance(block.get("headers"), dict) else {}
    if isinstance(hdr_block, dict):
        deny_names = hdr_block.get("deny_names")
        if deny_names is not None and not isinstance(deny_names, list):
            raise ConfigError("leak_censor.headers.deny_names must be an array")

    return warnings


def write_generated_toml(
    out_path: Path,
    json_paths: list[str],
    header_deny: list[str],
    sources: list[str],
) -> None:
    lines = [
        "# generated by li-httpd setup-censor",
        f"# source: {', '.join(sources) if sources else 'migrations'}",
        "",
        "[generated.json_paths]",
        "paths = [",
    ]
    for p in json_paths:
        lines.append(f'  "{p}",')
    lines.append("]")
    lines.append("")
    lines.append("[generated.headers]")
    lines.append("deny_names = [")
    for h in header_deny:
        lines.append(f'  "{h}",')
    lines.append("]")
    lines.append("")
    out_path.write_text("\n".join(lines), encoding="utf-8")
