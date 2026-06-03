# Docker multi-replica proxy smoke

Proves li-httpd can load-balance across multiple upstream replicas in containers.

**Note:** li-httpd upstream peers are `127.0.0.1:PORT` only (see `flatten-httpd-config.py`). The compose file uses **`network_mode: host`** so each replica binds a distinct loopback port on Linux/WSL Docker.

## Run

From `li-httpd/` (WSL/Linux with Docker):

```bash
cp ../lic/build/li-httpd build/li-httpd   # or scripts/build-li-httpd.sh
bash scripts/hosting-matrix-docker-smoke.sh
```

If Docker is unavailable, the script runs a **host fallback**: two Node peers on 39344/39345 with cookie sticky LB on 39343.

## Stack (`compose.multi-replica.yml`)

| Service | Port | LB route |
|---------|------|----------|
| `front` | 39300 | — |
| `node-a`, `node-b`, `node-c` | 39341–39343 | cookie `/node/**` |
| `bun-a`, `bun-b` | 39344–39345 | round_robin `/bun/**` |
| `li-static` | 39346 | `/li/**` |

Front: `http://127.0.0.1:39300`
