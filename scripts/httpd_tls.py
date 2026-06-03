#!/usr/bin/env python3
"""M1.5 TLS auto: manual | self_signed | lets_encrypt config oracle + provisioning."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

TLS_MODES = frozenset({"manual", "self_signed", "lets_encrypt"})
TLS_SHORTHAND = frozenset({"manual", "self_signed", "lets_encrypt"})
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
DURATION_RE = re.compile(r"^(\d+)(d|days?)?$", re.IGNORECASE)
RENEW_STATE = "acme-renewal.json"
ACME_RESERVED_PATH = "/.well-known/acme-challenge/"


class ConfigError(Exception):
    """Raised by TLS validators (mirrors httpd_config.ConfigError)."""


@dataclass
class TlsProfile:
    mode: str
    min_protocol: str
    cert_dir: Path
    manual_cert: Path | None = None
    manual_key: Path | None = None
    self_signed_dev: bool = False
    self_signed_days: int = 90
    self_signed_key_type: str = "ed25519"
    le_email: str = ""
    le_domains: list[str] = None  # type: ignore[assignment]
    le_environment: str = "production"
    renew_before_days: int = 30
    http01_bind: str = "0.0.0.0:80"

    def __post_init__(self) -> None:
        if self.le_domains is None:
            self.le_domains = []


def parse_listen_host_port(raw: object) -> tuple[str, int]:
    s = str(raw or "").strip()
    if not s:
        return "", 0
    if s.startswith(":"):
        return "", int(s[1:])
    if s.startswith("[") and "]" in s:
        end = s.index("]")
        host = s[1:end]
        rest = s[end + 1 :]
        if rest.startswith(":"):
            return host, int(rest[1:])
        return host, 443
    if ":" in s:
        host, port_s = s.rsplit(":", 1)
        return host.strip(), int(port_s)
    return s, 443


def is_loopback_listen(listen: object) -> bool:
    host, _ = parse_listen_host_port(listen)
    if not host:
        return False
    h = host.lower()
    return h in ("127.0.0.1", "::1", "localhost")


def is_public_listen(listen: object) -> bool:
    host, _ = parse_listen_host_port(listen)
    if not host:
        return True
    h = host.lower()
    if h in ("0.0.0.0", "::", "::0", "*"):
        return True
    if h.startswith("127.") or h == "localhost" or h == "::1":
        return False
    return True


def collect_route_hosts(data: dict[str, Any]) -> set[str]:
    hosts: set[str] = set()
    server = data.get("server") or {}
    if isinstance(server, dict) and server.get("host"):
        hosts.add(str(server["host"]).strip().lower())
    routes = data.get("routes")
    if isinstance(routes, dict):
        for key in routes:
            if not isinstance(key, str):
                continue
            m = re.match(r"^[A-Z]+\s+/[^\s]+(?:\s+host=([^\s]+))?", key.strip())
            if m and m.group(1):
                hosts.add(m.group(1).lower())
    return {h for h in hosts if h}


def parse_renew_before(raw: object) -> int:
    if raw is None:
        return 30
    s = str(raw).strip().lower()
    m = DURATION_RE.match(s)
    if not m:
        raise ConfigError(f"renew_before must be like 30d (got {raw!r})")
    n = int(m.group(1))
    unit = (m.group(2) or "d").lower()
    if unit.startswith("d"):
        return n
    return n


def normalize_tls_block(data: dict[str, Any]) -> TlsProfile:
    server = data.get("server") or {}
    if not isinstance(server, dict):
        server = {}
    tls_val = server.get("tls")
    nested: dict[str, Any] = {}
    shorthand: str | None = None
    if isinstance(tls_val, dict):
        nested = tls_val
    elif isinstance(tls_val, str):
        shorthand = tls_val.strip().lower()

    mode = str(nested.get("mode") or shorthand or "").strip().lower()
    if not mode:
        raise ConfigError("server.tls.mode or server.tls shorthand is required for TLS listeners")

    if mode not in TLS_MODES:
        raise ConfigError(f"server.tls.mode must be one of {sorted(TLS_MODES)} (got {mode!r})")
    if mode == "off":
        raise ConfigError('server.tls.mode = "off" is forbidden on public listeners')

    min_proto = str(nested.get("min_protocol") or "1.3").strip()
    if min_proto not in ("1.2", "1.3"):
        raise ConfigError("server.tls.min_protocol must be 1.2 or 1.3")

    cert_dir_raw = nested.get("cert_dir") or server.get("cert_dir") or "./certs"
    cert_dir = Path(str(cert_dir_raw)).expanduser()

    profile = TlsProfile(
        mode=mode,
        min_protocol=min_proto,
        cert_dir=cert_dir,
        renew_before_days=parse_renew_before(nested.get("renew_before")),
    )

    manual = nested.get("manual") if isinstance(nested.get("manual"), dict) else {}
    if not manual:
        manual = data.get("server.tls.manual") if isinstance(data.get("server.tls.manual"), dict) else {}
    if isinstance(manual, dict):
        if manual.get("cert"):
            profile.manual_cert = Path(str(manual["cert"]))
        if manual.get("key"):
            profile.manual_key = Path(str(manual["key"]))

    ss = nested.get("self_signed") if isinstance(nested.get("self_signed"), dict) else {}
    if not ss:
        ss = data.get("server.tls.self_signed") if isinstance(data.get("server.tls.self_signed"), dict) else {}
    if isinstance(ss, dict):
        dev = ss.get("dev")
        profile.self_signed_dev = str(dev).lower() in ("1", "true", "yes")
        if ss.get("valid_days") is not None:
            days = int(ss["valid_days"])
            if days < 1 or days > 365:
                raise ConfigError("server.tls.self_signed.valid_days must be in [1, 365]")
            profile.self_signed_days = days

    le = nested.get("lets_encrypt") if isinstance(nested.get("lets_encrypt"), dict) else {}
    if not le:
        le = data.get("server.tls.lets_encrypt") if isinstance(data.get("server.tls.lets_encrypt"), dict) else {}
    email = ""
    if isinstance(le, dict):
        email = str(le.get("email") or "").strip()
        doms = le.get("domains") or []
        if isinstance(doms, list):
            profile.le_domains = [str(d).strip().lower() for d in doms if str(d).strip()]
        env = str(le.get("environment") or "production").strip().lower()
        if env not in ("staging", "production"):
            raise ConfigError("server.tls.lets_encrypt.environment must be staging or production")
        profile.le_environment = env
        if le.get("http01_bind"):
            profile.http01_bind = str(le["http01_bind"]).strip()
    if not email:
        email = str(server.get("email") or "").strip()
    profile.le_email = email

    return profile


def validate_tls_config(data: dict[str, Any], cfg_path: Path | None = None) -> TlsProfile | None:
    """Validate TLS tables. Returns profile when TLS is configured."""
    server = data.get("server") or {}
    if not isinstance(server, dict):
        return None
    listen = server.get("listen")
    if not listen:
        return None
    has_tls_shorthand = (
        isinstance(server.get("tls"), str)
        and str(server.get("tls")).strip().lower() in TLS_SHORTHAND
    )
    has_tls_table = isinstance(server.get("tls"), dict)
    if not has_tls_shorthand and not has_tls_table:
        if is_public_listen(listen):
            raise ConfigError(
                "public server.listen requires server.tls mode (manual | self_signed | lets_encrypt)"
            )
        return None

    profile = normalize_tls_block(data)
    route_hosts = collect_route_hosts(data)

    if profile.mode == "manual":
        if not profile.manual_cert or not profile.manual_key:
            raise ConfigError("server.tls.manual requires cert and key paths")
        if cfg_path and not profile.manual_cert.is_file():
            raise ConfigError(f"manual cert not found: {profile.manual_cert}")
        if cfg_path and not profile.manual_key.is_file():
            raise ConfigError(f"manual key not found: {profile.manual_key}")

    if profile.mode == "self_signed":
        if is_public_listen(listen) and not profile.self_signed_dev:
            raise ConfigError(
                "self_signed on public bind requires server.tls.self_signed.dev = true"
            )

    if profile.mode == "lets_encrypt":
        if not profile.le_email or not EMAIL_RE.match(profile.le_email):
            raise ConfigError("lets_encrypt requires valid server.tls.lets_encrypt.email")
        if not profile.le_domains:
            if server.get("host"):
                profile.le_domains = [str(server["host"]).strip().lower()]
            else:
                raise ConfigError("lets_encrypt requires domains[] or server.host")
        for dom in profile.le_domains:
            if dom not in route_hosts:
                raise ConfigError(
                    f"lets_encrypt domain {dom!r} must match server.host or a route host"
                )
        if is_public_listen(listen) and not profile.le_email:
            raise ConfigError("lets_encrypt on public listener requires email")

    routes = data.get("routes")
    if isinstance(routes, dict):
        for key in routes:
            if isinstance(key, str) and ACME_RESERVED_PATH in key:
                raise ConfigError(
                    f"route {key!r} conflicts with reserved ACME path {ACME_RESERVED_PATH}"
                )

    return profile


def _normalize_key_type(raw: str | None) -> str:
    key = (raw or "ed25519").strip().lower().replace("_", "-")
    allowed = {
        "ed25519",
        "ecdsa-p256",
        "ecdsa-p384",
        "rsa2048",
        "rsa4096",
    }
    if key not in allowed:
        raise ConfigError(f"unsupported server.tls.self_signed key_type: {raw!r}")
    return key




def _openssl_newkey_arg(key_type: str) -> str:
    if key_type == "ed25519":
        return "ed25519"
    if key_type == "ecdsa-p256":
        return "ec:p-256"
    if key_type == "ecdsa-p384":
        return "ec:p-384"
    if key_type == "rsa2048":
        return "rsa:2048"
    if key_type == "rsa4096":
        return "rsa:4096"
    raise ConfigError(f"unsupported key_type for openssl: {key_type}")


def _openssl_self_signed(
    cert_dir: Path, days: int, cn: str, *, key_type: str = "ed25519"
) -> tuple[Path, Path]:
    cert_dir.mkdir(parents=True, exist_ok=True)
    try:
        cert_dir.chmod(0o700)
    except OSError:
        pass
    key_path = cert_dir / "privkey.pem"
    cert_path = cert_dir / "fullchain.pem"
    subj = f"/CN={cn}/O=li-httpd-dev"
    cmd = [
        "openssl",
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-keyout",
        str(key_path),
        "-out",
        str(cert_path),
        "-days",
        str(days),
        "-nodes",
        "-subj",
        subj,
    ]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    try:
        key_path.chmod(0o600)
    except OSError:
        pass
    meta = {
        "mode": "self_signed",
        "cn": cn,
        "fingerprint_hint": "dev only — trust locally",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    (cert_dir / "tls-meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return cert_path, key_path


def _write_renewal_state(cert_dir: Path, profile: TlsProfile, dry_run: bool) -> None:
    now = datetime.now(timezone.utc)
    next_renew = now + timedelta(days=max(1, profile.renew_before_days))
    state = {
        "mode": profile.mode,
        "environment": profile.le_environment,
        "email": profile.le_email,
        "domains": profile.le_domains,
        "renew_before_days": profile.renew_before_days,
        "next_renew_after": next_renew.isoformat(),
        "last_obtain": now.isoformat(),
        "dry_run": dry_run,
        "http01_bind": profile.http01_bind,
    }
    (cert_dir / RENEW_STATE).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def acme_obtain_staging(
    profile: TlsProfile, cert_dir: Path, *, dry_run: bool = False
) -> tuple[Path, Path]:
    """Obtain certs: staging/dry-run uses self-signed placeholder; production needs live ACME."""
    cert_dir.mkdir(parents=True, exist_ok=True)
    try:
        cert_dir.chmod(0o700)
    except OSError:
        pass
    cn = profile.le_domains[0] if profile.le_domains else "localhost"
    if dry_run or profile.le_environment == "staging":
        cert_path, key_path = _openssl_self_signed(cert_dir, 90, cn, key_type=getattr(profile, "self_signed_key_type", "ed25519"))
        acct = cert_dir / "acme-account.key"
        if not acct.is_file():
            subprocess.run(
                ["openssl", "genrsa", "-out", str(acct), "2048"],
                check=True,
                capture_output=True,
            )
            try:
                acct.chmod(0o600)
            except OSError:
                pass
        _write_renewal_state(cert_dir, profile, dry_run=dry_run or profile.le_environment == "staging")
        return cert_path, key_path
    raise ConfigError(
        "lets_encrypt production obtain requires reachable HTTP-01 (use --dry-run or environment=staging in CI)"
    )


def provision_tls(
    cfg_path: Path,
    *,
    cert_dir: Path | None = None,
    dry_run: bool = False,
    renew_only: bool = False,
) -> list[Path]:
    data = tomllib.loads(cfg_path.read_text(encoding="utf-8"))
    profile = validate_tls_config(data, cfg_path)
    if profile is None:
        raise ConfigError("no TLS profile in config")
    out_dir = cert_dir or profile.cert_dir
    if not out_dir.is_absolute():
        out_dir = (cfg_path.parent / out_dir).resolve()

    written: list[Path] = []

    if renew_only:
        state_path = out_dir / RENEW_STATE
        if not state_path.is_file():
            raise ConfigError(f"renew: missing {RENEW_STATE} (run setup-tls first)")
        state = json.loads(state_path.read_text(encoding="utf-8"))
        profile.le_domains = state.get("domains") or profile.le_domains
        profile.le_email = state.get("email") or profile.le_email
        profile.le_environment = state.get("environment") or profile.le_environment
        if profile.mode != "lets_encrypt":
            raise ConfigError("renew only applies to lets_encrypt mode")
        cert_path, key_path = acme_obtain_staging(profile, out_dir, dry_run=dry_run)
        written.extend([cert_path, key_path, state_path])
        return written

    if profile.mode == "self_signed":
        cn = profile.le_domains[0] if profile.le_domains else "localhost"
        cert_path, key_path = _openssl_self_signed(out_dir, profile.self_signed_days, cn, key_type=profile.self_signed_key_type)
        written.extend([cert_path, key_path, out_dir / "tls-meta.json"])
    elif profile.mode == "lets_encrypt":
        cert_path, key_path = acme_obtain_staging(profile, out_dir, dry_run=dry_run)
        written.extend([cert_path, key_path, out_dir / RENEW_STATE, out_dir / "acme-account.key"])
    elif profile.mode == "manual":
        if not profile.manual_cert or not profile.manual_key:
            raise ConfigError("manual mode: cert and key required")
        written.extend([profile.manual_cert, profile.manual_key])
    else:
        raise ConfigError(f"unsupported tls mode: {profile.mode}")

    return written


def tls_flatten_lines(data: dict[str, Any], cfg_path: Path) -> list[str]:
    profile = validate_tls_config(data, cfg_path)
    if profile is None:
        return ["tls_enabled=0"]
    lines = [
        "tls_enabled=1",
        f"tls_mode={profile.mode}",
        f"tls_min_protocol={profile.min_protocol}",
        f"tls_cert_dir={profile.cert_dir.resolve() if profile.cert_dir.is_absolute() else (cfg_path.parent / profile.cert_dir).resolve()}",
    ]
    if profile.mode == "self_signed":
        lines.append(f"tls_self_signed_dev={1 if profile.self_signed_dev else 0}")
    if profile.mode == "lets_encrypt":
        lines.append(f"tls_le_email={profile.le_email}")
        for dom in profile.le_domains:
            lines.append(f"tls_le_domain={dom}")
        lines.append(f"tls_le_environment={profile.le_environment}")
        lines.append(f"tls_renew_before_days={profile.renew_before_days}")
        lines.append(f"tls_http01_bind={profile.http01_bind}")
        lines.append("tls_acme_reserved_path=/.well-known/acme-challenge/")
    if profile.manual_cert:
        lines.append(f"tls_manual_cert={profile.manual_cert}")
    if profile.manual_key:
        lines.append(f"tls_manual_key={profile.manual_key}")
    return lines


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: httpd_tls.py <config.toml>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    try:
        profile = validate_tls_config(data, path)
    except ConfigError as e:
        print(f"tls error: {e}", file=sys.stderr)
        return 1
    if profile is None:
        print("OK: no TLS")
        return 0
    print(f"OK: tls mode={profile.mode} cert_dir={profile.cert_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
