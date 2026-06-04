# Podman / Docker multi-replica proxy smoke

Proves li-httpd can load-balance across multiple upstream replicas in containers.

**Note:** li-httpd upstream peers are `127.0.0.1:PORT` only (see `flatten-httpd-config.py`). The compose file uses **`network_mode: host`** so each replica binds a distinct loopback port on Linux/WSL.

## Run

From `li-httpd/` (WSL/Linux with **Podman** preferred, Docker as fallback):

```bash
cp ../lic/build/li-httpd build/li-httpd   # or scripts/build-li-httpd.sh
bash scripts/hosting-matrix-docker-smoke.sh
```

The smoke script picks **Podman** when `podman info` works, otherwise **Docker**. It prints which runtime was selected.

If neither runtime is available, the script runs a **host fallback**: two Node peers on 39344/39345 with cookie sticky LB on 39343.

## Podman (recommended)

**WSL / Linux (rootless):**

```bash
sudo apt install -y podman podman-compose   # Debian/Ubuntu
export PODMAN_COMPOSE_PROVIDER=podman-compose   # if podman compose picks broken docker-compose on PATH
bash scripts/hosting-matrix-docker-smoke.sh
```

**Host networking:** `network_mode: host` in `compose.multi-replica.yml` is the Podman equivalent of `docker run --network host`. On WSL2/Linux, rootless Podman can bind `127.0.0.1:39341–39346` on the WSL host loopback so the front proxy and peers see the same addresses as in the TOML config. Do not use bridge networking for this stack — peers would not be reachable at `127.0.0.1`.

**Windows (Podman Desktop):** run the smoke inside the Podman/WSL machine (Linux), not from Windows `podman.exe` alone — host mode and loopback ports match the Linux path above.

## Docker (fallback)

Same commands if Podman is absent and Docker Desktop/WSL integration is running (`docker info` succeeds).

## Stack (`compose.multi-replica.yml`)

| Service | Port | LB route |
|---------|------|----------|
| `front` | 39300 | — |
| `node-a`, `node-b`, `node-c` | 39341–39343 | cookie `/node/**` |
| `bun-a`, `bun-b` | 39344–39345 | round_robin `/bun/**` |
| `li-static` | 39346 | `/li/**` |

Front: `http://127.0.0.1:39300`
