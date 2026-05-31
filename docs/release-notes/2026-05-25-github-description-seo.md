# Release notes: 2026-05-25 — github-description-seo

**Status:** Ready for review  
**Repo:** li-langverse/li-httpd  
**PR:** `chore/github-description-seo`  
**PH / REQ:** PH-H (metadata)  
**Author:** agent (WP-A4)

---

## Summary (one sentence)

Replace template GitHub description with HPC/AI-oriented blurb; README tagline and `.github/repo-description` canonical string.

## Agent continuation (required)

1. Read: `.github/repo-description`, WP-A4 plan.
2. Run: `gh repo view li-langverse/li-httpd --json description`; post-merge `gh repo edit` from file if still template.
3. Then: resume httpd M1 when Lean gates allow.
4. Blocked on: WP-H2 SPDX/LICENSE mass-edit — **none**.

## Changed (specific)

| Area | What | Evidence |
|------|------|----------|
| Metadata | `.github/repo-description` | PR diff |
| Docs | README tagline | `README.md` |

## Not changed (scope fence)

- `src/`, `net.httpd` import path, Lean proofs — **not** touched.
- `lic` compiler, `lis` tier5 — **not** in this PR.
- LICENSE file policy — WP-H2.

## Breaking changes

None.

## Security

N/A.

## Performance

N/A.

## Downstream

N/A.
