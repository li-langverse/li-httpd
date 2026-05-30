# Repo scope: **roadmap** (issue feature planner)

Parent: [issue-feature-planner.md](../issue-feature-planner.md)

## This repo

Ecosystem governance, **agent-kit** (`agent-kit/manifest.toml`), vision docs.

## Rules

- Bump `agent-kit` version when changing shared `.cursor/` templates
- Run `./scripts/install-agent-kit.sh <target-repo>` from roadmap after merge
- **benchmarks** runs `./scripts/sync-agent-kit.sh`

Feature issues here often require human merge on governance PRs.

```bash
gh issue list --repo li-langverse/roadmap --state open
```
