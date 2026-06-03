# Config corpus

This folder holds TOML corpora for the Li-native config pipeline.

- `good/`: valid configs that must parse and flatten deterministically
- `reject/`: configs that must be rejected (parser or validator), used for negative tests

Phase-0 seeds `good/` from `examples/*.toml` so downstream phases have stable fixtures.

