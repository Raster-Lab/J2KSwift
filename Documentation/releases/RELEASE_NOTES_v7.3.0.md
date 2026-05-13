# J2KSwift v7.3.0 — Release Notes

**Tag**: `v7.3.0`
**Released**: 2026-05-09
**Headline**: HT entropy decoder hot-loop wedge elimination — DX 2800×2288 in-process decode tightens **62.51 → 54.34 ms** (-13 %) vs v7.2.0; total v7.1.0 → v7.3.0 closure of the Kakadu gap on DX is **5.23× → 2.17×** (about 60 % of the gap closed).

---

## Summary

v7.3.0 is a **focused entropy-decoder optimisation release**. Eight PRs (#359-#367) land a sequence of small, surgical, bit-exact changes that compound into a 51 % block-level decode microbench speedup and a 13 % production wall improvement on the headline DX fixture. The pattern that paid off: **eliminate "compute-then-discard" wasted work before reaching for SIMD**. Three of the four biggest wins (bottom-row recoverEQ, rho=0 fast path, VLC consume-only) are scalar restructurings; only one (SIMD4 readQuadSamples reconstruction) is true vectorisation.

The release also catches a **critical regression** caught during release-prep benchmarking: Phase 0's `J2KHTEntropyProfile` instrumentation bumps caused 30 %+ slowdown on multi-tile decode via cache-line contention from 16 parallel tile threads on the lockless global counters. The single-threaded block-level microbench couldn't detect it; only the in-process pipeline benchmark did. That was fixed in #367 before tagging.

---

## What's New — production default

### 1. Phase 3b — SIMD4 readQuadSamples reconstruction (#363)

The four samples of a quad are independent in their reconstruction (each computes `coef = ((payload & mask) | (e1Bit << m) | 1 + 2) << (p - 1)` plus an OR-with-sign-bit). Only the MagSgn read itself is serial (the bit-stream cursor must advance in order). The post-MagSgn reconstruction now runs lane-parallel via `SIMD4<UInt32>` arithmetic — four NEON 128-bit Q-register ops on Apple Silicon. **10-14 % faster on 64×64 blocks** (the production code-block size on the medical corpus).

### 2. Phase 3c — Bottom-row-only `recoverEQBottomRow` (#364)

The previous `recoverEQ` returned a 4-tuple of in-quad-position eQ values, but every caller read only `.1` and `.3` (the bottom-row positions feeding `eVal` bookkeeping for the next decoding row). Indices 0 and 2 (top-row) were computed and immediately discarded. The new helper returns `(Int, Int)` — the savings exceed the naive "halving the iteration count" estimate because the old helper also paid: tuple-via-memory return calling convention, switch-i 4-way dispatch, and per-iteration offset-array load. **22-39 % faster across every block size and density**.

### 3. Phase 3d — `rho == 0` fast-path (#365)

Most quads on a sparse-corpus block (~70 % at typical 30 % density, ~90 % at 10 % density) have no significant samples and don't need any work. A 12-line `if rho == 0 { return }` early-exit at the top of `readQuadSamples` and `recoverEQBottomRow` skips the SIMD setup + 4 conditional stores + bit-test+bounds-check pairs. **+19 % on sparse blocks**, +5-8 % on typical density.

### 4. Phase 3e — VLC `consume(count:)` + `@inline(__always)` (#366)

Two surgical changes to the VLC stream reader: explicit inlining annotations on `peek`/`read`, plus a new `consume(count:)` that replaces 8 occurrences of `_ = vlcReader.read(count: lookN.cwd_len)` (post-peek, value discarded) — skips the redundant `if bits < count { refill() }` branch since `peek` already brought `bits ≥ maxBits`. **Additional 16-20 % on top of Phase 3d**.

### 5. Phase 3g — Critical fix: probe-bump removal (#367)

Phase 0's `J2KHTEntropyProfile.bumpXxx()` instrumentation in the HT decoder hot path turned out to add severe cache-line contention from 16 parallel tile threads. Non-atomic `&+=` on process-global `UInt64` counters → cache-line ping-pong (~50-100 ns penalty per contended increment). For DX 4x4 with ~4.2 M total bumps × 16 threads, that's ~26 ms of wall added — exactly matching the observed regression. The probe data has been captured (Phase 0 deliverable shipped); the bumps in production code were pure overhead.

The regression was **invisible to the single-threaded `V730Phase3aBlockDecodeMicrobench`** but caught immediately by `CrossVersionDeltaBenchmark` (which runs the full multi-tile pipeline). Bisect confirmed Phase 0 was the regression source. Removing the bumps recovered the full v7.3 win.

---

## What's New — opt-in / infrastructure

- New file `Sources/J2KCodec/J2KHTEntropyProfile.swift` — count-based profile struct (Phase 0). The struct is left in place so future optimisation arcs can re-enable the probe locally; the production hot-path bumps are removed in #367.
- New tests:
  - `V730Phase0EntropyProbe.testEntropyEngineBreakdown_LosslessCorpus` — engine call breakdown (gates off GPU paths to exercise the CPU entropy hot loops)
  - `V730Phase1aMagSgnMicrobench.testMagSgnReadThroughput_PerWidth` — standalone `HTMagSgnDecoderConformant.read` ns/call baseline
  - `V730Phase3aBlockDecodeMicrobench.testBlockDecodeThroughput_PerSizeAndDensity` — block-level `HTBlockDecoderConformant.decode` ns/call baseline; the regression-detection probe of choice for entropy-decoder work

---

## Backward compatibility

**Codestream bytes**: byte-identical to v7.2.0 across the medical corpus. `CrossVersionDeltaBenchmark` md5-equality verified for all 6 fixtures × {single, tile2x2}.

**Public API**: no removals, no signature changes, no defaults flipped. `J2KMetalSharedBufferView<Element>` (added in v7.2.0) and the v7.3 entropy work are all internal to the decoder. SemVer rule: MINOR.

`getVersion()` returns `"7.3.0"`.

---

## Cross-codec parity matrix

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` re-run on this tag — **all 12 cells bit-exact** (max-diff = 0):

- ALL-EVEN cells: 9/9 cross-decode pass (J2KSwift / OpenJPH / Grok / Kakadu produce byte-identical decoded coefficients on even-origin tiles)
- ANY-ODD cells: 3/3 cross-decode pass (parity-aware odd-origin handling)

CLI cross-codec wall-time matrix (median of 5):

### Decode (CLI, ms)

| fixture | px | J2KSwift v7.3.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 68.30 | 16.17 | 17.92 | 15.18 |
| CT 512² | 262 K | 69.88 | 19.32 | 19.09 | 16.22 |
| MR 886² | 785 K | 74.53 | 21.05 | 21.29 | 18.31 |
| XA 1024² | 1.05 M | 79.75 | 27.91 | 22.33 | 19.38 |
| PX 2459×1316 | 3.24 M | 103.96 | 55.78 | 29.65 | 26.98 |
| **DX 2800×2288** | **6.41 M** | **134.89** | 92.51 | 40.85 | 39.67 |

### Encode (CLI, ms)

| fixture | px | J2KSwift v7.3.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 65.91 | 18.62 | 18.49 | 15.10 |
| CT 512² | 262 K | 70.59 | 20.98 | 19.93 | 15.91 |
| MR 886² | 785 K | 71.19 | 20.73 | 21.77 | 16.39 |
| XA 1024² | 1.05 M | 77.99 | 32.56 | 25.38 | 17.93 |
| PX 2459×1316 | 3.24 M | 95.76 | 70.49 | 39.10 | 24.02 |
| DX 2800×2288 | 6.41 M | 133.66 | 127.46 | 65.02 | 37.60 |

J2KSwift CLI rows include ~14-17 ms process startup + ~50 ms per-invocation overhead inside the `j2k` binary (image loader, config parsing, encoder/decoder construction). Codec-only walls are in the in-process table below.

### Lossless byte-equality

| codec | bit-exact PGM round-trip | notes |
|---|:-:|---|
| J2KSwift v7.3.0 | ✓ | bit-exact |
| OpenJPH 0.27 | ✓ | bit-exact |
| Grok 20.3 | byte-swap | decoded PGM byte-swapped (writer convention only — codestream is bit-exact reversible) |
| Kakadu 8.4.1 | ✓ | bit-exact |

---

## Medical-corpus benchmarks (in-process, codec-only)

`CrossVersionDeltaBenchmark` v7.3.0, median of 5 release-mode runs per fixture, single-tile mode (default `J2KEncoder` / `J2KDecoder` API path):

| fixture | px | enc ms | dec ms | bytes |
|---|---:|---:|---:|---:|
| MR-small 180² | 32 K | 0.77 | 0.60 | 45 224 |
| CT 512² | 262 K | 3.87 | 3.31 | 436 460 |
| MR 886² | 785 K | 2.64 | 5.09 | 169 709 |
| XA 1024² | 1.05 M | 7.45 | 8.09 | 1 621 712 |
| PX 2459×1316 | 3.24 M | 25.98 | 33.04 | 6 453 588 |
| **DX 2800×2288** | **6.41 M** | **50.91** | **54.34** | 12 705 470 |

### Cross-version delta — DX 2800×2288 in-process decode

| version | dec ms | Δ vs prior | Kakadu gap |
|---|---:|---:|---:|
| v7.1.0 | 130.78 | (baseline) | **5.23×** |
| v7.2.0 | 62.51 | -52 % | 2.50× |
| **v7.3.0** | **54.34** | **-13 %** | **2.17×** |

v7.1.0 → v7.3.0 closes ~60 % of the Kakadu gap that v7.1.0 shipped with. The remaining 2.17× is the structural CPU SIMD ceiling — Kakadu's hand-tuned NEON inner loops are roughly 2× faster than ours; closing the rest requires the multi-day NEON port that was scoped out of v7.3 (sketched in `V7_2_0_STATUS_AND_KAKADU_GAP.md`).

Full per-fixture × per-version × {encode, decode} × {CLI, in-process} table is in [CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md](CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md).

---

## Test Suite Results

### Mandatory commit gate (release mode)

| suite | cells | result |
|---|---:|:---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2 | ✓ |
| `J2KStrictCrossCodecValidationTests` | 3 | ✓ |
| `HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` | 12 (9 ALL-EVEN + 3 ANY-ODD) | ✓ all bit-exact |
| **Total** | **8 + 12 cross-decode cells** | **0 failures** |

### v7.3.0-new validation suites

| suite | cells | what it pins |
|---|---:|---|
| `V730Phase0EntropyProbe` | 1 | HT entropy engine call breakdown across the medical corpus |
| `V730Phase1aMagSgnMicrobench` | 1 | `HTMagSgnDecoderConformant.read` ns/call baseline |
| `V730Phase3aBlockDecodeMicrobench` | 1 | `HTBlockDecoderConformant.decode` ns/call baseline + density sweep |

---

## API surface

### Additions (internal)

- `recoverEQBottomRow(rho:baseX:baseY:) -> (Int, Int)` on `DecodeState` — replaces the 4-tuple `recoverEQ` with the bottom-row-only variant; eliminates the wasted top-row eQ that callers always discarded.
- `consume(count:)` on `VLCReverseReader` — refill-skip variant of `read(count:)` for post-peek discard sites.
- Several `@inline(__always)` annotations on per-quad helpers (`nextMELEvent`, `lookupVLC`, `decodeUVLCPair*`, `readQuadSamples`, `recoverEQBottomRow`, `peek`, `read`).
- `J2KHTEntropyProfile` enum (Phase 0 probe scaffolding) — counters, snapshot, reset. Production decoder no longer calls bump methods (per #367); the struct is kept so future optimisation work can re-enable the probe locally.

### No removals; no signature changes; no default behaviour flips

---

## Known limitations

- **Kakadu gap remains 2.17× on DX in-process decode.** Closing the rest requires CPU SIMD on the HT decoder's chained-state inner loops (MagSgn refill in particular) — multi-day work parked for a future release. See `V7_2_0_STATUS_AND_KAKADU_GAP.md` for the full plan sketch.
- **MagSgn refill is at the Apple M2 scalar ceiling.** Phase 1b's raw-pointer rewrite gave only 1-6 % microbench improvement; further headroom needs NEON.
- **Encode wall unchanged** by v7.3 — all v7.3 work was on the decode side.
- **`J2KHTEntropyProfile` data is stale.** With production bumps removed, calling `J2KHTEntropyProfile.snapshot()` returns all-zero counters by default. Tests that need the data must re-enable bumps locally; the file's header comment documents the deletion-as-a-unit pattern when the probe is no longer needed.

---

## Reproducing the headline numbers

```bash
# Build the release binary
swift build -c release --product j2k

# Mandatory gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix
swift test -c release --filter HTTileParityMatrixTests

# CLI cross-codec wall-time matrix
bash /tmp/cross_codec_v710.sh

# In-process medical-corpus benchmark (the data behind §6 above)
RUNS=5 swift test -c release --filter testCrossVersionDeltaBenchmark

# Block-decode microbench (the regression detector that should have caught Phase 0
# but didn't, because it's single-threaded; kept as the entropy-stage gate for v7.3+)
swift test -c release --filter testBlockDecodeThroughput_PerSizeAndDensity
```

To reproduce per-version: `git checkout v7.1.0` (or `v7.2.0`, or `v7.3.0`), build, run.

---

## Companion documents

| document | what's in it |
|---|---|
| `CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md` | Full per-fixture × per-version × {encode, decode} × {CLI, in-process} measurements — the data behind this release notes' headline tables |
| `V7_2_0_STATUS_AND_KAKADU_GAP.md` | End-of-v7.2.0 honest assessment of the remaining Kakadu gap + the CPU-SIMD arc sketch that v7.3 partially executed |
| `V7_3_0_PROFILE.md` | Phase 0 deliverable — HT entropy engine call-count breakdown that drove the v7.3 plan |
| `RELEASE_NOTES_v7.2.0.md` | The previous release |
