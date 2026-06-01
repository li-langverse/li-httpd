#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
(root / "AGENTS.md").write_text(
    """# Agent instructions (`li-httpd`)

## Source of truth

**All HTTP server work happens in this repo and sibling Li package repos — never in [lic](https://github.com/li-langverse/lic).**

| Repo | Role |
|------|------|
| **li-httpd** (here) | Server loop, proxy, config surface, examples, gates |
| **li-net**, **li-tls**, **li-crypto**, **li-http**, ... | Network/TLS/crypto (separate repos; Li only) |
| **lic** | **Compiler + toolchain only.** Pin via `li-toolchain.toml`. No new httpd/net/tls in lic. |

## Language rule

- **Write Li.** Do not add or extend C in lic for httpd, epoll, TLS, or proxy.
- Legacy `runtime/li_rt_*.c` + `seam.li` httpd bindings are **debt to replace**, not extend.
- Prefer pure Li (`import tls`, `import net`) over OpenSSL/C seam paths.
- New OS glue: compiler/runtime seam for syscalls only — not hand-written httpd C in lic.

## Workflow

1. Branch + PR in **li-httpd** (or the Li library repo).
2. Build: `./scripts/build-li-httpd.sh` with `LIC_ROOT` pointing at pinned lic.
3. **Do not** develop in `lic/packages/li-net-httpd` (optional mirror only).

## Tests

- `li-tests/` smokes; tier5 via `LI_HTTPD_BIN=./build/li-httpd` in benchmarks repo.
""",
    encoding="utf-8",
    newline="\n",
)
(root / "README.md").write_text(
    """# li-httpd

Li-native HTTP/HTTPS server — epoll, TLS, reverse proxy, dual HTTP+HTTPS listeners.

**Develop here.** [lic](https://github.com/li-langverse/lic) is the **compiler only** (`li-toolchain.toml`). No httpd/net/TLS features in lic or C under `lic/runtime/`.

## Build

```bash
export LIC_ROOT=../lic
./scripts/build-li-httpd.sh
./build/li-httpd path/to/runtime.conf
```

## Config

```toml
[server]
listen = "127.0.0.1:8443"
listen_http = "127.0.0.1:8080"
```

See `docs/architecture.md`, `AGENTS.md`, `examples/`.

## Import

```li
import net.httpd
```
""",
    encoding="utf-8",
    newline="\n",
)
print("policy docs ok")
