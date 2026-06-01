# li-httpd

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
