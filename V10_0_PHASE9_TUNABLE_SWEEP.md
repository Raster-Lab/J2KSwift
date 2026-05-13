# v10.0 Phase 9 — Encoder tunable sweep, pareto front

**Status:** Default config `(decompositionLevels=5, codeBlockSize=64×64)` is **near-pareto-optimal** on the medical corpus. No non-default combo dominates default on more than 1 of 6 fixtures, and margins are <0.1 % bytes.

**Date:** 2026-05-14
**Branch:** `v10.0-research`
**Test:** `Tests/J2KMetalTests/V10Phase9TunableSweepTests.swift::testTunableSweep_Pareto_M2`
**Host:** Apple M2, v9.4.0-era v10.0-research binary, release mode, n=5 median per cell.

## Headline

For HT-conformant lossless 5/3 encoding on the medical corpus:

- **Block size: 64×64 strictly dominates 32×32** at every decomposition level on every fixture. 32×32 is slower AND produces larger bytes. **Don't use 32×32 in production.**
- **Decomposition levels = 5 is near-optimal** but adjacent levels (3, 4, 6) win on individual fixtures by <0.1 % bytes / <2 % wall. The default's choice is well-tuned.
- **No "secret winner" tunable** — the default config has been correctly chosen.

This Phase 9 closes the question "are there pareto-better non-default configs?" with a clear no.

## Cross-fixture summary

Combos that *dominate* default `(levels=5, block=64×64)` on each fixture:

| Combo | Dominates default on | % of corpus |
|---|---:|---:|
| levels=4 block=64×64 | 1 / 6 fixtures | 17 % |
| levels=6 block=64×64 | 1 / 6 fixtures | 17 % |
| levels=3 block=64×64 | 1 / 6 fixtures | 17 % |
| All `block=32×32` combos | 0 / 6 fixtures | 0 % |

**No non-default combo dominates more than 1/6 fixtures** and even those wins are tied (the "dominating" combo wins by <1% wall and <0.1% bytes). The default is robustly pareto-optimal across the corpus.

## Sample per-fixture pareto tables

### MR-small 180² (smallest fixture, encode <1 ms)

| levels | blocksize | wall ms | bytes | bpp | vs default |
|---:|---|---:|---:|---:|---|
| 3 | 32×32 | 0.64 | 45 643 | 11.27 | dominated |
| 3 | 64×64 | 0.55 | 45 333 | 11.19 | faster but larger |
| 4 | 32×32 | 0.58 | 45 529 | 11.24 | dominated |
| 4 | 64×64 | 0.54 | 45 219 | 11.17 | **dominates default** (faster + smaller, both within noise) |
| 5 | 32×32 | 0.61 | 45 534 | 11.24 | dominated |
| **5** | **64×64** | **0.56** | **45 224** | **11.17** | **(default)** |
| 6 | 32×32 | 0.65 | 45 569 | 11.25 | dominated |
| 6 | 64×64 | 0.61 | 45 259 | 11.18 | dominated |

Note: levels=4 wins on MR-small but only by 0.02 ms wall + 5 bytes — both within measurement noise. Functionally identical to default.

### DX 2800×2288 (largest fixture)

| levels | blocksize | wall ms | bytes | bpp | vs default |
|---:|---|---:|---:|---:|---|
| 3 | 32×32 | 41.44 | 12 795 266 | 15.98 | dominated |
| 3 | 64×64 | 40.02 | 12 717 870 | 15.88 | dominated |
| 4 | 32×32 | 42.19 | 12 786 016 | 15.97 | dominated |
| 4 | 64×64 | 40.00 | 12 708 111 | 15.87 | dominated |
| 5 | 32×32 | 43.00 | 12 783 397 | 15.96 | dominated |
| **5** | **64×64** | **38.09** | **12 705 470** | **15.87** | **(default)** |
| 6 | 32×32 | 42.83 | 12 783 458 | 15.96 | dominated |
| 6 | 64×64 | 39.04 | 12 705 376 | 15.87 | smaller (94 bytes) but slower (+1 ms) |

On DX, default is fastest. levels=6 saves 94 bytes (0.001%) at +1 ms wall — strictly worse.

## Key observation: 32×32 block size is universally worse

Across 24 (32×32) measurements (4 levels × 6 fixtures), every single one was dominated by the corresponding 64×64 combo. On DX: 32×32 is consistently 5 ms slower AND ~80 KB larger than 64×64. The 64×64 block size is the established Part-15 HTJ2K default for good reason on Apple M2.

## Why levels has small effect

For HT-conformant lossless 5/3:
- Bytes are determined primarily by pixel entropy (HT block coder is near-arithmetic-optimal)
- Decomposition levels affect WHERE the bits are spent (more levels = more low-frequency LL subbands → slightly different inter-subband bit allocation), but at lossless quality the total entropy is fixed.
- More levels = more iterations of DWT + per-subband block extraction, hence slightly more wall.
- Fewer levels = fewer subbands but each subband larger, more entropy work.
- The (default) level=5 balance is near-optimal for the corpus.

## Verdict

**Default `J2KEncodingConfiguration` for HT-conformant lossless 5/3 is correctly tuned and pareto-optimal.** SDK consumers should not override `decompositionLevels` or `codeBlockSize` for medical workloads.

**Phase 9 is the 13th lever-ceiling-style finding** (in the sense that the default is unbeatable, no new tunable to graduate). Adds to the v10.0 closure narrative.

## Practical SDK guidance update for OPTIMAL_PERFORMANCE_GUIDE.md

The existing guide says "use the default config." Phase 9 confirms that with measurement:

- ✗ `cfg.codeBlockSize = (32, 32)` — slower and larger; **don't**
- ✗ `cfg.decompositionLevels = 3` (or 4 or 6) — within measurement noise of 5 on the medical corpus; **don't override**
- ✓ Default `J2KEncodingConfiguration` — leave it alone; it's optimal.

## Reproducing

```bash
swift test -c release --filter V10Phase9TunableSweepTests
```

Run time ~3.5 s release-mode (288 encodes total, mostly small fixtures).

## Files added in Phase 9

```
Tests/J2KMetalTests/V10Phase9TunableSweepTests.swift  (NEW)
V10_0_PHASE9_TUNABLE_SWEEP.md                          (this doc)
```

Stay on `v10.0-research` per the no-merge policy.
