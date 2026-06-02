# Li-native TOML + li-httpd config migration (sprint)

## Goal

Replace the Python `flatten-httpd-config.py` pipeline and legacy C config loading with **Li-only** config:

- **`li-toml`** parses TOML (Li-only repo)
- **`li-httpd`** desugars, validates, and applies config (this repo)

Constraint: **`lic` is compiler only** — no new HTTPD/TOML feature work lands in `lic`.

## Phase loop (authoritative)

Phase state lives in `data/li-toml-config-loop/state.json`.

After each iteration:

- Run the current phase gate.
- Append one row to `data/li-toml-config-loop/iteration-log.md`.
- Advance the phase only after the gate passes.

## Phase checklist (high level)

- **phase-0-prep**: bootstrap repos + corpus + gates
- **phase-a0-parse**: `li-toml` parses `li-tests/config/good/*.toml`
- **phase-b1-parity**: Li flatten is byte-parity vs Python on good corpus; reject corpus fails
- **phase-b2-serve**: `li-httpd serve server.toml`; tier5 smoke on `LI_HTTPD_CONFIG_PIPELINE=li`
- **phase-c-retire-c**: config applied in Li; no new C config keys
- **phase-d-done**: harness defaults `pipeline=li`; Python flatten deprecated

## Corpus

`li-httpd` keeps a config-desugar corpus under `li-tests/config/`:

- `li-tests/config/good/`: configs expected to parse and flatten
- `li-tests/config/bad/`: configs expected to fail parsing/validation (added in later phases)

