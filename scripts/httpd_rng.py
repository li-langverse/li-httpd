#!/usr/bin/env python3
"""RNG config: OsRng default, Prng-on-TLS profile gates (httpd plan rng-concepts)."""

from __future__ import annotations

import os
from typing import Any

RNG_MODES = frozenset({"os", "prng", "sim", "bad"})
DEV_PROFILES = frozenset({"dev", "lab", "prob-test"})


class ConfigError(Exception):
    """Raised by RNG config validators."""


def tls_configured(data: dict[str, Any]) -> bool:
    server = data.get("server")
    if not isinstance(server, dict):
        return False
    tls = server.get("tls")
    return isinstance(tls, dict) and bool(tls.get("mode"))


def config_profile(data: dict[str, Any]) -> str:
    return str(data.get("profile") or "production").strip().lower()


def validate_rng_config(data: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Validate [server.rng]. Returns (errors, warnings)."""
    errs: list[str] = []
    warnings: list[str] = []
    server = data.get("server")
    if not isinstance(server, dict):
        return errs, warnings
    rng = server.get("rng")
    if not isinstance(rng, dict):
        return errs, warnings

    mode = str(rng.get("mode") or "os").strip().lower()
    if mode not in RNG_MODES:
        errs.append(f"server.rng.mode must be one of {sorted(RNG_MODES)} (got {mode!r})")
        return errs, warnings

    if mode == "bad":
        if os.environ.get("LI_HTTPD_EXPLOIT_HARNESS", "").strip() not in ("1", "true", "yes"):
            errs.append(
                'server.rng.mode="bad" is only allowed in exploit harness '
                "(set LI_HTTPD_EXPLOIT_HARNESS=1)"
            )

    if mode == "sim":
        sched = rng.get("sim_schedule_file")
        if not sched or not str(sched).strip():
            errs.append("server.rng.sim_schedule_file is required when mode=sim")

    if mode == "prng":
        if rng.get("seed") is None:
            errs.append("server.rng.seed is required when mode=prng")
        if tls_configured(data):
            profile = config_profile(data)
            allow = rng.get("allow_insecure_rng")
            allowed = str(allow).lower() in ("1", "true", "yes")
            if profile == "production" and not allowed:
                errs.append(
                    "server.rng.mode=prng with TLS is rejected on production profile "
                    "(use profile dev/lab/prob-test or server.rng.allow_insecure_rng=true)"
                )
            elif profile in DEV_PROFILES:
                warnings.append(
                    "insecure_rng_prng_tls: deterministic PRNG feeds TLS secrets (dev/lab only)"
                )

    return errs, warnings


def validate_rng_config_raise(data: dict[str, Any]) -> list[str]:
    errs, warnings = validate_rng_config(data)
    if errs:
        raise ConfigError(errs[0])
    return warnings
