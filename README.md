# li-httpd

Proved AI/agent HTTP gateway (Phase H). **M1 not implemented** — blocked on full **2e–2f** Lean gate; see [httpd plan](../../docs/superpowers/plans/2026-05-16-li-httpd-plan.md) and [httpd prerequisites](../../docs/ecosystem/httpd-prerequisites.md).

**Composable by default:** import `li_httpd` from any program; lifecycle lives in `src/lib.li`. `src/main.li` is a thin demo only. See [composable-by-default](../../docs/ecosystem/composable-by-default.md).

Path deps: `li-net`, `li-bytes` (planned), workspace in `lic` `packages/li.toml`.

## Composable API (aspirational — stubs today)

```nim
import li_httpd

let cfg = HttpdConfig(port=8080)
let h = httpd_serve(cfg)      # start (stub until P0-net)
discard httpd_ready(h)        # await accepting
httpd_stop(h)                 # tear down
```

Other packages embed the same calls in their own `proc main` — no copy-paste of server loop.

## Build

```bash
lic build src/lib.li -o /dev/null
lic build src/main.li -o li-httpd-demo   # optional thin demo
```

From the monorepo root, ensure `lic` is built: `./scripts/build.sh`.

## Traceability

| ID | Link |
|----|------|
| Package | `PKG-li-httpd` |
| Org repo | https://github.com/li-langverse/li-httpd |
| Governance | [Ecosystem governance](https://li-langverse.github.io/li-language/ecosystem/governance/) |

See `PUBLISH.md` and `docs/traceability.md`.

## License

Apache-2.0 OR MIT
