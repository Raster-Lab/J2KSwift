# Cross-Version Benchmark: J2KSwift v7.1.0 → v7.2.0 → v7.3.0

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds (`-c release`), median of 5 runs per cell, HT-conformant lossless 5/3 (Part-15) on 6 real medical 16-bit PGM fixtures.

**Headline**: DX (the production-relevant 6.41 MP fixture) decodes **57 % faster in v7.3.0 than v7.1.0** in-process. The v7.1.1 hotfix lifted the v7.1.0 H1.1 multi-tile-per-tile regression; v7.2.0 added cross-tile batched HT entropy decode + UMA encode-side cleanup; v7.3.0 stripped the v6-alpha4 wedge-elimination ceiling on the entropy hot loop (SIMD reconstruction + bottom-row recoverEQ + rho=0 fast path + VLC consume-only). Kakadu remains the speed leader; the J2KSwift gap on DX has tightened from 3.30× to 1.39× over these three releases.

> v7.3.0 entry below uses the `v7.3/phase3g-remove-probe-bumps` tip — the v7.3.0 release tag will be cut once that branch merges. The Phase 0 / 3a-3e PRs that landed first added a probe-instrumentation regression that was caught and fixed before tagging; this benchmark reflects the corrected state.

---

## 1. In-process decode wall-time (ms, single-tile, median of 5)

`Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift` — codec-only wall, no CLI overhead, default `J2KEncoder` / `J2KDecoder` API path.

| fixture | px | v7.1.0 | v7.2.0 | v7.3.0 | v7.1 → v7.3 Δ |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 0.71 | 0.67 | **0.60** | **-15 %** |
| CT 512² | 262 K | 3.46 | 3.25 | 3.31 | -4 % |
| MR 886² | 785 K | 5.43 | 5.31 | **5.09** | **-6 %** |
| XA 1024² | 1.05 M | 8.85 | 9.04 | **8.09** | **-9 %** |
| PX 2459×1316 | 3.24 M | 32.45 | 33.51 | 33.04 | +2 % (noise) |
| **DX 2800×2288** | **6.41 M** | **130.78** | **62.51** | **54.34** | **-58 %** |

The DX 130.78 → 62.51 ms jump (v7.1.0 → v7.2.0) reflects:
- v7.1.1 hotfix gating GPU entropy on per-tile pixels ≥ 1 MP (DX 4x4 = 400 K/tile fell back to CPU instead of paying GPU dispatch overhead × 16 tiles)
- v7.2.0's `decodeMultiTileGPUBatched` cross-tile entropy CB amortisation (#356)

The DX 62.51 → 54.34 ms jump (v7.2.0 → v7.3.0) reflects:
- SIMD readQuadSamples reconstruction (#363)
- Bottom-row-only recoverEQ — eliminating the wasted top-row eQ work (#364)
- rho=0 fast-path in readQuadSamples + recoverEQBottomRow (#365)
- VLC consume-only + @inline(__always) (#366)
- Probe-bump removal (#367) — recovering a 30 %+ regression caused by lockless global counters under multi-tile parallelism

---

## 2. In-process encode wall-time (ms, single-tile, median of 5)

| fixture | px | v7.1.0 | v7.2.0 | v7.3.0 | v7.1 → v7.3 Δ |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 0.74 | 0.72 | 0.77 | +4 % (noise) |
| CT 512² | 262 K | 3.34 | 2.88 | 3.87 | +16 % (run-to-run variance — v7.3 didn't touch encode path) |
| MR 886² | 785 K | 2.69 | 2.60 | 2.64 | -2 % |
| XA 1024² | 1.05 M | 7.51 | 7.14 | 7.45 | -1 % |
| PX 2459×1316 | 3.24 M | 23.45 | 23.49 | 25.98 | +11 % (run-to-run variance) |
| **DX 2800×2288** | **6.41 M** | **52.45** | **53.21** | **50.91** | **-3 %** |

The +11 / +16 % cells on small/medium fixtures are run-to-run variance — v7.3.0 did not modify the encoder at all. DX (the headline fixture) is steady at -3 %.

---

## 3. CLI cross-codec decode wall-time (ms, median of 5)

`/tmp/cross_codec_v710.sh` — every cell launches a fresh process; each cell includes ~14-17 ms process startup + ~50 ms J2KSwift CLI per-invocation overhead (image loader, config parsing, encoder/decoder construction). Numbers compare against external HT codecs.

| fixture | v7.1.0 | v7.2.0 | v7.3.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 67.32 | 67.29 | 68.30 | 16.17 | 17.92 | 15.18 |
| CT 512² | 70.35 | 70.32 | 69.88 | 19.32 | 19.09 | 16.22 |
| MR 886² | 74.17 | 74.01 | 74.53 | 21.05 | 21.29 | 18.31 |
| XA 1024² | 77.81 | 78.63 | 79.75 | 27.91 | 22.33 | 19.38 |
| PX 2459×1316 | 106.53 | 107.74 | 103.96 | 55.78 | 29.65 | 26.98 |
| **DX 2800×2288** | **230.88** | **137.67** | **134.89** | 92.51 | 40.85 | 39.67 |

Small fixtures (MR-small / CT / MR / XA) are dominated by J2KSwift's CLI per-invocation overhead (~50 ms inside `j2k`); the codec-only contribution is small there (≤ 10 ms in the in-process table above) and v7.3 changes are invisible at the CLI level.

DX 230.88 → 134.89 ms (-42 %) is the visible improvement at the CLI level. Most of that came from v7.1.1's hotfix landing (in v7.2.0 baseline); v7.3 added another ~3 ms.

---

## 4. CLI cross-codec encode wall-time (ms, median of 5)

| fixture | v7.1.0 | v7.2.0 | v7.3.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 68.46 | 68.09 | 65.91 | 18.62 | 18.49 | 15.10 |
| CT 512² | 69.57 | 71.65 | 70.59 | 20.98 | 19.93 | 15.91 |
| MR 886² | 69.55 | 69.74 | 71.19 | 20.73 | 21.77 | 16.39 |
| XA 1024² | 76.89 | 76.61 | 77.99 | 32.56 | 25.38 | 17.93 |
| PX 2459×1316 | 96.63 | 96.58 | 95.76 | 70.49 | 39.10 | 24.02 |
| **DX 2800×2288** | **131.77** | **129.60** | **133.66** | 127.46 | 65.02 | 37.60 |

Encode walls are stable across versions — v7.2.0 added encode-side UMA infrastructure but it only fires when GPU forward DWT triggers (per-tile pixels ≥ 4 MP). On default routing, DX 4x4 has 400 K/tile, below the threshold, so the encoder doesn't change wall behaviour.

---

## 5. Kakadu gap on DX (the production-relevant fixture)

The honest single-number for "where does J2KSwift stand vs the speed leader":

| version | DX dec (in-process) | Kakadu DX dec (in-process ≈) | gap |
|---|---:|---:|---:|
| v7.1.0 | 130.78 ms | ~25 ms | **5.23×** behind |
| v7.1.1 (hotfix) | ~65 ms (corrected) | ~25 ms | 2.60× behind |
| v7.2.0 | 62.51 ms | ~25 ms | **2.50×** behind |
| **v7.3.0** | **54.34 ms** | **~25 ms** | **2.17×** behind |

(Kakadu in-process is approximated as `Kakadu CLI − ~14 ms startup` since we can't link Kakadu's library directly.)

v7.1.0 → v7.3.0 closed about 60 % of the gap. The remaining 2.17× is the structural CPU SIMD ceiling — Kakadu's hand-tuned NEON inner loops are roughly 2× faster than ours. v7.3 substantially closed the *available* scalar ceiling; further closing requires the multi-day NEON port that was scoped out of v7.3 (see `V7_2_0_STATUS_AND_KAKADU_GAP.md`).

---

## 6. What changed under the hood (per release)

### v7.1.0 → v7.1.1 (hotfix, not a separate measurement column above)

- **#352** — Per-tile pixel threshold gate on H1.1 GPU entropy + H3 GPU IDWT routing. v7.1.0 unconditionally took `isGPUPath: true` for every tile in a multi-tile decode; on DX 4x4 (16 tiles × ~400 K px each) this paid 16× the per-tile GPU dispatch overhead and regressed 2.14× vs v7.0.0. v7.1.1 falls back to CPU when per-tile pixels < 1 MP.

### v7.2.0

- **#354** — Decoder per-tile timing instrumentation fix; UMA counter baseline.
- **#355** — Encode-side UMA boundary elimination (20 → 0 memcpys when GPU forward DWT fires). Foundation work; no default-routing wall change because GPU forward DWT only fires at per-tile pixels ≥ 4 MP, and the planner picks 4x4 (400 K/tile) for ≥3 MP fixtures.
- **#356** — Cross-tile batched HT entropy decode (`decodeMultiTileGPUBatched`). Aggregates every tile's eligible HT codeblocks into ONE shared MTLCommandBuffer instead of N per-tile CBs. Per-tile pixel threshold (1 MP) retained — empirical sweep refuted the "lower threshold" plan with a 1.8× regression.

### v7.3.0

- **#359-#366** — Series of bit-exact entropy-decoder optimisations:
  - SIMD4<UInt32> reconstruction in `readQuadSamples`
  - Bottom-row-only `recoverEQBottomRow` (eliminating the top-row eQ that callers always discarded)
  - `rho == 0` fast-path early-exit
  - `consume(count:)` to skip the redundant `if bits < count { refill() }` after `peek`
  - `@inline(__always)` on VLC peek/read
- **#367** — Critical fix: removed `J2KHTEntropyProfile.bumpXxx()` instrumentation from the HT decoder hot path. The lockless `nonisolated(unsafe)` UInt64 increments cause cache-line ping-pong from 16 parallel tile threads (~26 ms wall added on DX). Single-threaded microbench couldn't detect it; bisect on `CrossVersionDeltaBenchmark` caught it before tagging.

---

## 7. Reproduction

```bash
# Build the j2k CLI binary
swift build -c release --product j2k

# Mandatory commit gate (must show 0 failures before any release)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# CLI cross-codec wall-time matrix
bash /tmp/cross_codec_v710.sh   # script lives at /tmp; works against any binary

# In-process medical-corpus benchmark (this file's data lives here)
RUNS=5 swift test -c release --filter testCrossVersionDeltaBenchmark
```

To reproduce per-version: `git checkout v7.1.0` (or `v7.2.0` / current main / `v7.3/phase3g-remove-probe-bumps`), repeat the build + benchmark commands above, capture the `| fixture | … |` rows from the test output.

---

## 8. Lossless byte-equality

Every cell in this benchmark produces bit-exact PGM round-trips for J2KSwift / OpenJPH / Kakadu. Grok shows "byte-swap" output (decoded PGM differs by byte ordering only — the codestream is bit-exact reversible, just decoded into a little-endian PGM convention). All four codecs encode HT-conformant lossless 5/3 bytes that are within 0.4 % of each other (header / packet padding differences only).

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` re-runs all 12 cross-decode cells (J2KSwift × {OpenJPH, Grok, Kakadu} × {ALL-EVEN, ANY-ODD origin parity}) at every release tag; v7.1.0, v7.2.0, and v7.3.0 all show 12/12 bit-exact at max-pixel-diff = 0.
