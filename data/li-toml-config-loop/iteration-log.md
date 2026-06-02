| UTC timestamp | repo | branch | phase | gate | notes |
|---|---|---|---|---|---|

# li-toml config migration — iteration log

| Date | Phase | Agent | Gate | Notes |
|------|-------|-------|------|-------|
| 2026-06-02 | phase-0-prep | code_implementer | phase-0-prep-gate.sh OK | Copied 27 good + 20 reject TOMLs from lic; created li-toml scaffold |
| 2026-06-02 | phase-a0-parse | code_implementer | phase-a0-parse-gate.sh OK | li-toml parses 14 good TOMLs |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Added parity gate + script; currently validates legacy Python flatten succeeds for standalone server configs and fails for reject corpus (Li parity still pending). |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Synced loop/gates + added `scripts/config-parity-check.sh` and `li-tests/config` corpus to enable parity gating in fresh clones. |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Verified parity gate passes in workflow clone (`LIC_ROOT=/workspace/lic`). |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Fixed parity gate reproducibility across isolated clones by normalizing absolute repo paths in `runtime.conf` before golden diffs. |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Re-verified parity gate passes in isolated workflow clone (python baseline; Li parity still pending). |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Improved `LIC_ROOT` auto-discovery in `scripts/config-parity-check.sh` for sibling + isolated-workspace layouts. |
| 2026-06-02 | phase-b1-parity | code_implementer | phase-b1-parity-gate.sh OK | Added benchmarks env flag `LI_HTTPD_CONFIG_PIPELINE` (default `python`) and fixed a new TOML sample that broke the parity corpus. |
