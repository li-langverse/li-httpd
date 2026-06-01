# Architecture — Li-only httpd

## Principle

**lic is the compiler.** li-httpd, li-net, li-tls, and related libraries are **Li programs and packages** in their own repos. Server logic is not developed in lic and not written in ad-hoc C there.

## Current layers (target end state)

```
li-httpd (this repo)     — HTTP/1.1, proxy, config, epoll loop in Li
    ↓ imports
li-tls, li-net, li-crypto, li-http, …   — separate Li repos
    ↓ OS / syscalls
lic compiler             — codegen, minimal runtime seam (sockets only, shrinking)
```

## Legacy debt (do not extend)

Historically, much of the server lived in lic:

- `runtime/li_rt_net.c`, `li_rt_tls.c`, `li_rt_httpd.c`, `li_rt_h2.c`
- `std/runtime/seam.li` — dozens of `httpd_*` C bindings

That allowed fast iteration before the ecosystem split. **New work must not add C there.** Migrate call sites into Li (`packages/` in sibling repos) and delete seam surface over time.

## Dual HTTP + HTTPS

Configured via runtime conf (from TOML flatten):

- `listen_port` — TLS listener when `tls_enabled=1`
- `listen_port_http` — cleartext listener in parallel (nginx-style)

Implemented in `src/lib.li` (epoll accepts on both fds).

## Building

lic is required **only as toolchain**:

```bash
export LIC_ROOT=../lic   # or commit from li-toolchain.toml
./scripts/build-li-httpd.sh
```

The binary may still link legacy C objects from the pinned lic version until the seam is fully removed — that link is not permission to add more C.

## Config tooling

Long term: `flatten-httpd-config.py` / validators move from lic into **li-httpd**. Until then, call lic scripts only as a pinned tool, not as a development home.
