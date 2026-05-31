---
name: plan-feature-from-issue
description: >-
  Plan a new feature from a GitHub issue aligned with li-langverse vision,
  master plan PH-* phases, engineering standards, and correct doc placement.
  Use when triaging feature/enhancement issues or before large implementation PRs.
---

# Plan feature from issue

Use when an issue asks for new capability and **no** `plan-approved` / `has-plan` label exists.

## Read first (mandatory)

| Doc | URL |
|-----|-----|
| Vision layers | [vision-and-roadmap.md](https://github.com/li-langverse/roadmap/blob/main/docs/ecosystem/vision-and-roadmap.md) — north star: HPC, scientific computing, AI |
| Engineering gates | [engineering-standards.md](https://github.com/li-langverse/roadmap/blob/main/docs/ecosystem/engineering-standards.md) |
| Agent coordination | [agent-coordination.md](https://github.com/li-langverse/roadmap/blob/main/docs/ecosystem/agent-coordination.md) |
| Master plan + PH tracker | [master plan](https://github.com/li-langverse/lic/blob/main/docs/superpowers/plans/2026-05-14-li-master-plan.md) |
| Provability honesty | [provability-gaps.md](https://github.com/li-langverse/lic/blob/main/docs/verification/provability-gaps.md) |

Repo-specific: `AGENTS.md` in the issue's repo.

## Vision filter (five pillars)

Every feature must strengthen at least one pillar without weakening others:

1. **Easy** — low ceremony, clear APIs
2. **AI-first** — agent-safe defaults, diagnosable errors
3. **Secure** — proofs, CVE tests for new attack surface
4. **Provable** — static gates; update **G-*** gaps honestly
5. **Fast** — benchmarks if perf-sensitive; no claims without data

**Reject or defer** if the issue duplicates work outside the correct vision layer (e.g. package-only scope in master plan).

## Planning workflow

### 1. Classify the issue

| Signal | Action |
|--------|--------|
| Labels `feature`, `enhancement`, `plan-needed` | Full plan required |
| Title contains feat/implement/add | Treat as feature unless typo/docs-only |
| Already `plan-approved` | Skip planning; implement per linked plan |
| Cross-repo impact | Master plan + roadmap proposal, not package README only |

### 2. Choose canonical home for the plan

| Scope | Write plan to |
|-------|----------------|
| Language / compiler / PH-* | `lic/docs/superpowers/plans/YYYY-MM-DD-<topic>.md` |
| Ecosystem / org policy | `roadmap/docs/ecosystem/` or proposal PR on **roadmap** |
| Single package | `packages/<name>/docs/` + traceability `REQ-*` |
| Benchmarks only | `benchmarks/catalog.toml` + lic harness (never copy harness) |
| Dashboard / ingest | **benchmarks** repo |

### 3. Plan document template

```markdown
# <Title> (PH-XXX / REQ-YYY)

> **Issue:** #N · **Repo:** li-langverse/<repo>
> **Vision:** which pillar(s) · **Learned from:** 2–4 references

## Goal
One paragraph.

## Non-goals
Bullets.

## Dependencies
PH-*, upstream repos, human-only actions.

## Sub-phases
| Sub | Deliverable | Exit gate |
|-----|-------------|-----------|

## Tests / benches
li-tests paths, tier-N bench ids, CVE row if security.

## Provability
Which G-* rows move Partial → Done; what stays honest limit.

## Rollout
PR order, downstream pins, release notes path.
```

### 4. Issue comment (do not implement yet)

Post on the GitHub issue:

1. Link to the plan file (or PR that adds it)
2. PH-* / REQ-* ids
3. **Human-only** blockers if any (org settings, new repo, secrets)
4. Ask maintainer to add label `plan-approved` before implementation agents run

### 5. Labels

- Remove `plan-needed` when plan is posted
- Add `plan-approved` only after human ack (or org policy allows agent self-label)

## Do not

- Implement before plan + `plan-approved` unless user explicitly says "skip planning"
- Hide ecosystem vision only in issue comments
- Weaken benchmark thresholds to "complete" a feature
- Self-merge planning PRs on **roadmap** or governance docs

## Related automations

- `.cursor/automations/issue-feature-planner.md` — scheduled issue sweep
- `.cursor/automations/plan-completion-audit.md` — finds stale plans
