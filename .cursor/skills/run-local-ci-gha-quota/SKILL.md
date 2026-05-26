---
name: run-local-ci-gha-quota
description: >-
  Run Li ecosystem CI locally when GitHub Actions minutes are exhausted or
  checks are missing/red. Uses li-langverse/li-local-ci (act or host profiles)
  and benchmarks merge gate JSON. Use before merge, PR review, phase-0 cleanup,
  or when the user mentions GHA quota, local actions, act, or local-ci-sweep.
---

# Run local CI when GHA quota is exhausted

GitHub Actions may be **skipped, queued forever, or red** when org minutes are consumed. **Do not merge** on faith. Run the **same workflow intent** locally and record results for `pr-merge-gate.py`.

**Canonical repo:** [li-langverse/li-local-ci](https://github.com/li-langverse/li-local-ci) — clone as a sibling of `lic`, `benchmarks`, `li-cursor-agents`.

## When to use (mandatory)

- `statusCheckRollup` is empty, `pending`, or failed **and** you cannot re-run GHA
- User says **GHA quota**, **minutes exhausted**, **run CI locally**
- Supervisor / merge agent before `pr_merger` (default: `LI_USE_LOCAL_CI=1`)
- Phase-0 or pre-PR verification on a devbox

## Quick decision

| Situation | Command |
|-----------|---------|
| **This repo checkout** (no PR clone) | Repo-specific host CI (fastest) |
| **Open PR branch** (merge gate) | `li-local-ci run-pr` |
| **Many PRs** | `benchmarks/scripts/local-ci-sweep.py` |
| **act missing** | `--profile legacy` or repo `scripts/local-ci.sh` |

## Per-repo host CI (no act)

```bash
# lic — mirrors scripts/ci.sh (build, li-tests, tier-0, security, …)
cd lic && ./scripts/local-ci.sh
# Optional Ubuntu 24.04 container parity:
cd lic && ./scripts/local-ci.sh --docker

# benchmarks
cd benchmarks && ./scripts/ci.sh   # if present; else see repo README

# li-cursor-agents
cd li-cursor-agents && npm run ci:local
```

Set LLVM on Linux/macOS before `lic` host CI:

```bash
export LLVM_DIR=/usr/lib/llvm-18/lib/cmake/llvm   # Debian llvm-18
export CC=clang CXX=clang++
```

## li-local-ci (PR-accurate)

```bash
export LI_LOCAL_CI_ROOT=~/path/to/li-local-ci   # optional if sibling exists
export PATH="$LI_LOCAL_CI_ROOT/bin:$PATH"

./bin/li-local-ci doctor          # act optional; shows disk/docker
./bin/li-local-ci list            # profiles: lic-host, lic-docker, …

# Single PR — runs workflow YAML on the PR branch (preferred for merge)
./bin/li-local-ci run-pr --repo lic --pr 173

# Local branch (no gh)
./bin/li-local-ci workflows --repo ../lic

# act unavailable → shell profile
./bin/li-local-ci run-pr --repo lic --pr 173 --profile legacy
```

Install act when possible: `brew install act` (macOS) or see li-local-ci README.

## Merge gate artifact

`benchmarks/data/latest/local-ci-results.json` — written by `run-pr` / sweep.

```bash
cd benchmarks
python3 scripts/local-ci-sweep.py --repo lic --pr N
python3 scripts/local-ci-sweep.py --merge-candidates-only
python3 scripts/pr-merge-gate.py --repo lic --pr N   # accepts local-ci pass
```

Disable swarm sweep only if human asked: `LI_USE_LOCAL_CI=0`.

## Agent rules

1. **Run local CI before claiming PR is green** when GHA is not trustworthy.
2. **Post evidence** in PR or handoff: command, exit code, log tail, `local-ci-results.json` timestamp.
3. **Do not merge** without GHA green **or** fresh local-ci `ok: true` for that PR.
4. **Heavy lic workflow in act** may need `LI_LOCAL_CI_BINDS` or `lic-host` profile — prefer host `lic/scripts/local-ci.sh` on devbox when act/docker fails.
5. **li-cursor-agents e2e:** under act only unit tests run; full e2e needs host `npm run ci:local` or GHA.

## Related

- `lic` rule: `.cursor/rules/li-local-actions-quota.mdc`
- `li-cursor-agents` AGENTS.md § Local CI
- Skill `li-ecosystem-discipline` — gates before cross-repo merge
