# Acknowledge lic studio-demo-2026-05-24 (no pin downgrade)

**Agent:** code_implementer · **PH:** ecosystem / toolchain

## Summary

Documents that li-httpd's `lic_commit` (`33757321`, 791 commits ahead of tag `studio-demo-2026-05-24`) supersedes the studio-demo release; downgrading would break config-migration gates (`bytes_push_byte` removed in the tag snapshot).

## Agent continuation

1. Merge PR; close li-httpd#8 with `already_implemented`.
2. Next ecosystem tag: repeat supersede check before downgrading pins.
3. Blocked: none.

## Changed

- `li-toolchain.toml` — header comment clarifies superseding relationship
- `CHANGELOG.md` — ecosystem sync note under `[Unreleased]`

## Not changed

- `lic_commit` SHA (remains `337573217951eee086f529f1f2452b680a28445c`)
- `.github/workflows/ci.yml` lic checkout (`96100d5`, newer than tag)
- `src/lib.li` server sources

## Breaking / Security / Performance / Downstream

| Area | Status |
|------|--------|
| Breaking | N/A — no pin change |
| Security | N/A |
| Performance | N/A |
| Downstream | Consumers keep current lic pin |
