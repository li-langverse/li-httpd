# Httpd config pipeline (`LI_HTTPD_CONFIG_PIPELINE`)

## Default (phase D+)

| Surface | Default | Notes |
|---------|---------|--------|
| `li-httpd` wrapper (`./li-httpd serve`) | `li` | Li flatten + serve |
| benchmarks / tier5 harness | `li` | via `harness/httpd_flatten.py` |
| `scripts/config-parity-check.sh` | python baseline | Parity oracle only; not used for serve |

## Values

| Value | Behavior |
|-------|----------|
| `li` | `scripts/flatten-httpd-config-li.sh` / `li-httpd config flatten` |
| `python` | **Deprecated** — `lic/scripts/flatten-httpd-config.py` (rollback / parity only) |

Set `LI_HTTPD_CONFIG_PIPELINE=python` to roll back benchmarks or local smoke without code changes.

## Environment

| Variable | Purpose |
|----------|---------|
| `LI_HTTPD_CONFIG_PIPELINE` | `li` or `python` |
| `LI_HTTPD_ROOT` | Path to li-httpd repo (harness auto-discovers sibling) |
| `LIC_ROOT` | lic checkout for Python flatten fallback |
| `LI_HTTPD_BIN` | Built `li-httpd` binary for tier5 serve |

## Migration

See `docs/plans/2026-06-li-toml-config-migration.md`. Python flatten in **lic** is frozen; new config keys are Li-only (`li-tests/corpus/config/apply.li`).
