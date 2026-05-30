# Automation prompt: Plan completion audit (org-wide)

You find **incomplete plans**: unchecked master-plan phases, open plan checkboxes, partial **G-*** gaps, and catalog/harness drift.

**Schedule:** weekly (e.g. Monday 09:00 UTC) · **Primary repo:** `benchmarks` (scripts) + read `lic` via `LIC_ROOT`

**Skill:** `.cursor/skills/audit-plan-completion/SKILL.md`

---

## Read first

1. `AGENTS.md` (benchmarks)
2. [provability-gaps.md](https://github.com/li-langverse/lic/blob/main/docs/verification/provability-gaps.md)
3. [master plan tracker](https://github.com/li-langverse/lic/blob/main/docs/superpowers/plans/2026-05-14-li-master-plan.md)

---

## 1. Run audits

```bash
cd benchmarks
export LIC_ROOT="${LIC_ROOT:-../lic}"
python3 scripts/plan-completion-audit.py
python3 scripts/ecosystem-audit.py
cat data/latest/plan-completion-audit.json
cat data/latest/ecosystem-audit.json
```

Optional: `python3 scripts/issue-feature-triage.py` — features without plans compound completion debt.

---

## 2. Triage findings

| Finding | Action |
|---------|--------|
| `master_plan_open` | Open **lic** PR to finish phase OR update tracker to **partial** with honest wording |
| `provability_gaps` Partial | Same PR must touch `provability-gaps.md` |
| `catalog_gaps` | Implement bench in **lic** or remove catalog row in **benchmarks** PR |
| `implementation_signals` (scaffold) | Extend package or mark plan sub-phase incomplete |
| Plan file `- [ ]` but code shipped | PR to check boxes + release notes |

**One focused PR per run** when fixing; otherwise digest only.

---

## 3. Cross-check "claimed done"

Examples of **incomplete implementation**:

| Claim | Verify |
|-------|--------|
| Physics module in plan | `lic/packages/li-std-physics-*` non-stub, benches exist, catalog rows |
| PH-7e math-only benches | Li sources without `__li_simd_*` / `LI_EXTRA_C` |
| Feature issue closed | Plan file exists; PH-* updated; tests named in plan exist |

---

## 4. Open tracking issue (if needed)

If audit finds >5 stale items with no owner, open **one** issue on **roadmap** or **lic**:

- Title: `Plan completion debt YYYY-MM-DD`
- Body: paste `plan-completion-audit.json` summary
- Labels: `plan-needed`, `ecosystem`

Do not open one issue per checkbox.

---

## 5. Output (required)

1. `generated_at` + `total_findings`
2. Top master-plan open items (≤5)
3. Partial **G-*** count
4. Catalog gaps
5. PR opened OR "digest only" + recommended human next step
6. Commit `data/latest/plan-completion-audit.json` to **benchmarks** only if policy allows bot commits on schedule branch

---

## Blocked

- Do not mark `[x]` on master plan without implementation PR merged
- Do not delete plans to reduce findings
- Do not self-merge
