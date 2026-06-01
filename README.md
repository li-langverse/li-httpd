# li-httpd

Li-native HTTP/HTTPS server (epoll, TLS terminate, reverse proxy). **Official repo** — package source is developed in [lic](https://github.com/li-langverse/lic) (`packages/li-net-httpd`) and synced here.

## Build

Requires a sibling **lic** checkout (compiler + C runtime). Pinned in `li-toolchain.toml` (currently `33757321`).

```bash
export LIC_ROOT=../lic-pure-https   # or ../lic on main
./scripts/build-li-httpd.sh
./build/li-httpd path/to/runtime.conf
```

Env: `LI_HTTPD_TLS_LEGACY_OPENSSL=1`, `LI_HTTPD_WORKERS=0`, `LI_HTTPD_M2_HTTP2=0` for tier5 parity.

## Config

TOML → runtime conf via lic's `scripts/flatten-httpd-config.py`, or hand-write `listen_port`, `listen_port_http` (dual HTTP+HTTPS), `tls_enabled=1`, etc.

Examples in `examples/`. See `docs/proxy-nginx-li-migration.md`.

## Import

```li
import net.httpd
```

Composable API in `src/lib.li`; `src/main.li` is the CLI entry.

## CI

Checks out pinned **lic** and runs `lic check` / smoke build (see `.github/workflows/ci.yml`).
