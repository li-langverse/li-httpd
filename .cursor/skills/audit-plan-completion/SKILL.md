---
name: audit-plan-completion
description: >-
  Audit incomplete master-plan phases, plan checkboxes, provability gaps, and
  catalog/harness drift. Use in scheduled automations or before release tagging.
---

# Audit plan completion

## Run scripts (benchmarks repo)

```bash
cd benchmarks
export LIC_ROOT=../lic   # or absolute path
python3 scripts/plan-completion-audit.py
python3 scripts/issue-feature-triage.py   # optional: open feature issues
python3 scripts/ecosystem-audit.py
cat data/latest/plan-completion-audit.json
```

## Interpret findings

| Source | Meaning |
|--------|---------|
| `master_plan_open` | PH phase tracker still unchecked — update plan or finish work |
| `plan_files_open` | Sub-plan `- [ ]` items stale |
| `provability_gaps` Partial/Missing | **G-*** not closed — handbook must not overclaim |
| `catalog_gaps` | `catalog.toml` row without lic path — ingest will lie |
| `implementation_signals` | Scaffold packages, unpublished branches |

## Priority actions

1. **P0** — Failing org CI (from `ecosystem-audit.json`) before new plan work
2. **P1** — Master plan / provability drift on active phases
3. **P2** — Catalog-only "done" without lic implementation
4. **P3** — Close completed plan checkboxes in same PR as implementation

## Output format (for automations)

Post a digest:

- `generated_at` from JSON
- Top 5 open master-plan items
- Count of partial **G-*** gaps
- Catalog gaps list
- Recommended next PR (one repo, one scope)

## Do not

- Mark plan items `[x]` without evidence in the same PR
- Delete catalog rows to make audit green
- File 10 issues at once — batch one repo per run
