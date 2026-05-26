# Repo scope: **lic** (issue feature planner)

Parent prompt: [issue-feature-planner.md](../issue-feature-planner.md)

## This repo

- **Issues:** language, compiler, `packages/`, `li-tests/`, `docs/superpowers/plans/`
- **Plan home:** `docs/superpowers/plans/YYYY-MM-DD-*.md` + master plan PH tracker
- **Provability:** always list **G-*** ids in plan; update [provability-gaps.md](https://github.com/li-langverse/lic/blob/main/docs/verification/provability-gaps.md) in implementation PR

## Feature examples

| Issue type | Plan must include |
|------------|-------------------|
| New syntax | Phase 2* / 3*, `li-tests/`, handbook stub |
| New std package | `li-new-package`, traceability, 80% coverage path |
| Physics / numerics | `research-li-numerics` skill, tier2 bench in lic |
| Perf | `benchmarks/harness/` change + benchmarks catalog row |

## gh filter

```bash
gh issue list --repo li-langverse/lic --label "feature,enhancement,plan-needed" --state open
```
