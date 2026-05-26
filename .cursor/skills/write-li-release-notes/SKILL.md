---
name: write-li-release-notes
description: >-
  Write mandatory agent-oriented release notes before PR merge — specific, scoped,
  with Agent continuation section. Use on every merge-worthy change in li-langverse repos.
---

# Write Li release notes

Use **before** `gh pr create` on any merge-worthy change.

## Read first

1. [release-notes.md](../../../docs/ecosystem/release-notes.md)
2. [TEMPLATE.md](../../../docs/release-notes/TEMPLATE.md)

## Steps

1. **Inventory the diff** — `git diff main...HEAD --stat`; list every area touched.
2. **Copy template** → `docs/release-notes/YYYY-MM-DD-<slug>.md` (create `docs/release-notes/` if missing).
3. Fill **every** section; use **N/A — &lt;reason&gt;** never leave blank.
4. **Agent continuation** — minimum 4 lines: Read / Run / Then / Blocked on.
5. **Not changed** — list at least 3 things a naive agent might wrongly assume (other pillars, other repos, phase gates).
6. **CHANGELOG.md** — add under `## [Unreleased]` with same facts (shorter bullets OK).
7. PR body — paste Summary + Agent continuation + link to the dated file.

## Good vs bad

| Bad | Good |
|-----|------|
| Improved parser | `lic` parser: `def` methods parse `self` param; `li-tests/encapsulation/def_method.li` added; PH-2g |
| Security hardening | CVE-2024-XXXX class: added `li-tests/security/smuggling_*.li`; row in `security/cve-catalog.json` |
| Benchmarks updated | `simd_dot` li 0.0286s vs cpp 0.0317s (0.90×); see benchmarks dashboard tier-1 |

## Repo-specific

| Repo | Extra |
|------|-------|
| **lic** | PH-, REQ-, `li-tests` T- ids; provability / trusted.lean if touched |
| **lis** | tier5_http scenario paths; nginx oracle N/A if stub |
| **benchmarks** | catalog.toml row; ingest script; dashboard category |
| **roadmap** | agent-kit manifest version bump if `.cursor/` changed |

## Checklist

- [ ] Dated file under `docs/release-notes/`
- [ ] CHANGELOG Unreleased updated
- [ ] Agent continuation block complete
- [ ] Not changed section present
- [ ] No forbidden vague phrases
