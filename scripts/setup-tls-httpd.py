#!/usr/bin/env python3
"""li-httpd setup-tls — self-signed dev certs; ACME staging obtain + renew."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from httpd_tls import ConfigError, normalize_tls_block, provision_tls

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore


def main() -> int:
    p = argparse.ArgumentParser(description="Provision TLS material for li-httpd.toml")
    p.add_argument("config", type=Path, help="li-httpd.toml path")
    p.add_argument(
        "-o",
        "--cert-dir",
        type=Path,
        default=None,
        help="Override server.tls.cert_dir",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="lets_encrypt: staging placeholder certs (no live ACME)",
    )
    p.add_argument(
        "--gen-dhparam",
        action="store_true",
        help="Also write dhparam.pem into cert dir (openssl dhparam 2048)",
    )
    p.add_argument(
        "--renew",
        action="store_true",
        help="Renew using acme-renewal.json (lets_encrypt only)",
    )
    args = p.parse_args()

    if not args.config.is_file():
        print(f"setup-tls: missing config {args.config}", file=sys.stderr)
        return 1

    out_dir = args.cert_dir
    if out_dir is None:
        try:
            data = tomllib.loads(args.config.read_text(encoding="utf-8"))
            prof = normalize_tls_block(data)
            out_dir = prof.cert_dir
        except Exception:
            out_dir = None

    if args.gen_dhparam:
        if out_dir is None:
            print("setup-tls: --gen-dhparam needs --cert-dir or config cert_dir", file=sys.stderr)
            return 1
        resolved = out_dir if out_dir.is_absolute() else (args.config.parent / out_dir).resolve()
        resolved.mkdir(parents=True, exist_ok=True)
        dh_out = resolved / "dhparam.pem"
        subprocess.run(
            ["openssl", "dhparam", "-out", str(dh_out), "2048"],
            check=True,
        )
        print(f"setup-tls: wrote {dh_out}")

    try:
        written = provision_tls(
            args.config,
            cert_dir=args.cert_dir,
            dry_run=args.dry_run,
            renew_only=args.renew,
        )
    except ConfigError as e:
        print(f"setup-tls: {e}", file=sys.stderr)
        return 1

    for path in written:
        print(f"setup-tls: wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
