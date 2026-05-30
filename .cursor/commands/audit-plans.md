# Audit plan completion

In **benchmarks** repo run:

```bash
export LIC_ROOT="${LIC_ROOT:-../lic}"
python3 scripts/plan-completion-audit.py
python3 scripts/issue-feature-triage.py || true
```

Summarize `data/latest/plan-completion-audit.json` per skill **audit-plan-completion**.
