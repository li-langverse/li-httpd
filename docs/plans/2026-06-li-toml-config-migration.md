# Li-native TOML + li-httpd config migration (sprint loop)

## North star

Replace the Python `flatten-httpd-config.py` path and the legacy C `runtime.conf` loader with **Li-only** config:

- **li-toml** parses TOML (Li-only)
- **li-httpd** desugars/validates/applies config (Li-only)
- **lic** remains **compiler/toolchain only** (no new httpd/TOML logic in lic)

## Iteration rules

1. Read `data/li-toml-config-loop/state.json` for the current `phase` key.
2. Implement **only** that phase; commit + push.
3. Run the phase gate before ending the iteration.
4. Append one row to `data/li-toml-config-loop/iteration-log.md`.
5. Do not mark the sprint done until the **Completion gate** passes.

## Repos and branches (intent)

| Repo | Branch | Role |
|------|--------|------|
| **li-toml** (create if missing) | `cursor/li-toml-config-migration` | TOML parser (Li only) |
| **li-httpd** | `cursor/li-toml-config-migration` | Config desugar, gates, apply |
| **benchmarks** | `feat/li-toml-config-pipeline` | `LI_HTTPD_CONFIG_PIPELINE` harness |
| **lic** | *no feature work* | Pin only in `li-toolchain.toml` |

## Phase checklist

| Phase | Key | Deliverable | Gate |
|------:|-----|-------------|------|
| 0 | `phase-0-prep` | Repo scaffolds + corpus present | `bash scripts/gates/phase-0-prep-gate.sh` |
| A0 | `phase-a0-parse` | li-toml parses all `li-tests/config/good/*.toml` | `bash scripts/gates/phase-a0-parse-gate.sh` |
| B1 | `phase-b1-parity` | Li flatten byte-parity vs Python on good corpus; reject corpus fails | `bash scripts/gates/phase-b1-parity-gate.sh` |
| B2 | `phase-b2-serve` | `li-httpd serve server.toml`; tier5 smoke with `LI_HTTPD_CONFIG_PIPELINE=li` | `bash scripts/gates/phase-b2-serve-gate.sh` |
| C | `phase-c-retire-c` | Config applied in Li; no new C config keys | `bash scripts/gates/phase-c-retire-c-gate.sh` |
| D | `phase-d-done` | Harness default `pipeline=li`; Python flatten deprecated | `bash scripts/gates/li-toml-config-completion-gate.sh` |

## Completion gate

```bash
bash scripts/gates/li-toml-config-completion-gate.sh
```

