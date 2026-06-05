# li-httpd hosting matrix

End-to-end smoke for static sites, Next.js export, reverse proxy, cookies, sessions, and sticky LB.

## Run (WSL/Linux)

```bash
cd li-httpd
cp ../lic/build/li-httpd build/li-httpd   # rebuild lic after runtime changes
bash scripts/hosting-matrix-smoke.sh
```

## What is covered

| Scenario | Ports | Notes |
|----------|-------|--------|
| Static HTML/CSS/JS | 39229, 39230 | argv + TOML |
| Next static export | 39236 | `_next/static/**` |
| Proxy → Node | 39233 → 39231 | Login cookie, `/api/me`, POST JSON |
| Proxy → Bun | 39235 → 39232 | Same app API |
| Next dev proxy | 39238 → 39237 | Stand-in by default; `HOSTING_MATRIX_REAL_NEXT=1` for real `next dev` |
| App front | 39241 → 39242 | Static `login.html` + `/api/*` |
| Sticky LB | 39243 → 39244/39245 | `upstream_balance=cookie`, `li_route` |

## Docker multi-replica

See [docker/README.md](docker/README.md). Host-only sticky LB is covered above; container multi-replica (Node×3, Bun×2, li-static×1) is `scripts/hosting-matrix-docker-smoke.sh`.

## Env

- `LI_HTTPD_PROXY_SNAP=0` (default in smoke) — disable GET snap cache for dynamic APIs
- `HOSTING_MATRIX_REAL_NEXT=1` — use real Next.js dev server instead of stand-in

## Demo login

Open `http://127.0.0.1:39241/login.html` (or via proxy-node on 39233) after starting `proxy-app.toml` manually.

Credentials: `agent` / `secret`
