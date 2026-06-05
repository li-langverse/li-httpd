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

## CI (GitHub Actions)

Workflow: [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml), job **`hosting-matrix-podman-e2e`**.

Runs on `ubuntu-24.04` for pushes and PRs to `main` and `feat/**` branches (in parallel with the lic-ci `check` job). The job:

1. Builds `lic` + `li-httpd` via the pinned `ghcr.io/li-langverse/lic-ci:ubuntu24-llvm22` image (Docker on the runner), copies `lic/build/li-httpd` → `build/li-httpd`.
2. Installs **Podman** and **podman-compose** from apt.
3. Runs `bash scripts/hosting-matrix-docker-smoke.sh` with `LI_HTTPD_PROXY_SNAP=0`, `LI_HTTPD_PROXY_C=1`, and `PODMAN_COMPOSE_PROVIDER=podman-compose`.

The compose stack uses **`network_mode: host`** (required for loopback upstream peers). The `front` service sets proxy env vars in `compose.multi-replica.yml`.

**Caveats on GitHub-hosted runners:**

- **Host networking** must work for rootless or rootful Podman; the job fails (no `continue-on-error`) if Podman/compose cannot start the stack — it does not accept the host-only Node fallback as a substitute for a green CI run.
- **Image builds** pull `node:22-bookworm-slim` and `oven/bun:1.2`; recent `ubuntu-24.04` runner images occasionally break HTTPS inside container build networks. If builds fail with certificate errors, retry with Podman build `--network=host` (see [actions/runner-images#13422](https://github.com/actions/runner-images/issues/13422)).
- Timeout is **20 minutes** (compose build + smoke probes).

Local verification matches CI: same script and env vars on WSL/Linux with Podman 4.9+.
