## Summary

<!-- What changed and why (link PKG- / T- / REQ- ids when applicable). -->

## Engineering gates (mandatory)

- [ ] **Functionality** — tests green; REQ/PH/T ids cited
- [ ] **Security** — relevant CVE/exploit rows; security CI if attack surface changed
- [ ] **Performance** — benchmark row or documented N/A
- [ ] **Learned from** — 2–4 reference ecosystems (if new feature)
- [ ] **Coverage tier** — std 100% / publish ≥80% as applicable

## Traceability

| Type | ID |
|------|-----|
| Package | |
| Test | |
| Phase | |

## Checklist

- [ ] `lic build` / `lic check` passes on touched `.li` files
- [ ] `CHANGELOG.md` updated (Keep a Changelog)
- [ ] SemVer bump in `li.toml` if releasing
