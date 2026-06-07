# Bump lic pin to studio-demo-2026-05-24

**Agent:** code_implementer · **PH:** ecosystem / toolchain

## Summary

Pins `li-toolchain.toml` and CI lic checkout to lic tag `studio-demo-2026-05-24` (`55defd82`).

## Agent continuation

1. Read `li-toolchain.toml` — confirm `lic_commit = 55defd82…`.
2. Run CI on the PR (`check`, `hosting-matrix-podman-e2e`, `hosting-matrix-features`).
3. Next: close li-httpd#8 when CI is green.
4. Blocked: none.

## Changed

- `li-toolchain.toml` — `lic_commit` → `55defd82878884ff46de304778741691d2ef1671`
- `.github/workflows/ci.yml` — lic checkout `ref` aligned to toolchain pin (3 jobs)
- `CHANGELOG.md` — unreleased toolchain bump note

## Not changed

- `src/lib.li` server implementation (compiler pin only; no source sync in this PR)
- `lic` upstream sources

## Breaking / Security / Performance / Downstream

| Area | Status |
|------|--------|
| Breaking | N/A — pin bump only |
| Security | N/A |
| Performance | N/A |
| Downstream | CI consumers inherit new lic @ `studio-demo-2026-05-24` |
