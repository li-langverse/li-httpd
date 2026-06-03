# C runtime.conf loader freeze (phase C)

During the Li-native TOML migration, `runtime.conf` is still consumed by
`httpd_load_runtime_config_i` in **lic** (`runtime/li_rt_net.c`). That strcmp
loop is **frozen**: no new keys may be added in C after phase B1.

## Policy

| Change | Where |
|--------|--------|
| New httpd config field | Li desugar + Li apply (`HttpdConfig` / setters) |
| Bugfix in existing key parsing | lic C loader only with freeze file updated in lockstep |
| TOML syntax / tables | **li-toml** |
| Desugar / validation | **li-httpd** `li-tests/corpus/config/` |

## Gate

```bash
bash scripts/lint-frozen-c-config-keys.sh
```

Compares live strcmp keys against `data/c-runtime-config-keys.freeze` (41 keys).

## Apply path (transitional)

- **B1–B2:** Li flatten → `runtime.conf` → C loader (wrapper `li-httpd serve`).
- **C+:** Li orchestrates apply; C loader shrinks field-by-field in follow-up PRs.

See `docs/plans/2026-06-li-toml-config-migration.md`.
