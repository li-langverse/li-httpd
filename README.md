# li-httpd

Proved AI/agent HTTP gateway (Phase H). **M1 not implemented** — blocked on full **2e–2f** Lean gate; see [httpd plan](../../docs/superpowers/plans/2026-05-16-li-httpd-plan.md) and [httpd prerequisites](../../docs/ecosystem/httpd-prerequisites.md).

Path deps: `li-net`, `li-bytes` (planned), workspace in `lic` `packages/li.toml`.

## Build

```bash
lic build src/lib.li -o li-httpd
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
