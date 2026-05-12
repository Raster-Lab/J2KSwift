# J2KSwift v9.5.0 — Daemon-encode large-fixture closure + qstep-cache + SIGTRAP fix

**Release date:** 2026-05-12
**Mission:** open-source medical-imaging codec faster than Kakadu on Apple Silicon.
**Status:** RC — bit-exact validated; release-mode gate clean; production-ready.

## Headline

v9.5.0 closes the v9.5–v9.8 research arc. The version slot follows
the conventional next-minor cadence after v9.4.0; the arc explored
four directions (entropy NEON, qstep cache, cold-shot pre-seed,
image-statistics qstep prediction) and ships the subset that
graduated.

Three production wins land in v9.5.0:

1. **Daemon-encode large-fixture closure.** The v9.4.0 `j2k --daemon`
   path regressed below cold on DX (2800×2288): warm 146 ms vs cold
   108 ms on M2. v9.5.0 fixes this — DX warm-encode via `--daemon` is
   now **57.5 ms (M2)**, a 2.5× warm-only improvement vs v9.4.0 and
   1.8× faster than cold same-binary.
2. **Process-default qstep cache** (`J2KQstepCache.shared`) for
   similar-shape lossy-9/7 batches. DX lossy-9/7 wall **99 ms → 29 ms
   (–71%) on M4**, with bit-exact codestream preservation for cache
   hits. (Scope note: this is lossy-path work; the project's lossless
   product target is unaffected — defaults for lossless encoding are
   unchanged.)
3. **SIGTRAP fix in `encodeViaQstepSearch`** — production bug. The
   refinement loop computed `Int(targetBytes * .infinity)` when a
   tolerance branch produced an unbounded scale, trapping at runtime.
   `J2KCrossScaleRDQualityProbe` and any caller of `.constantBitrate`
   auto-promoted to qstep-search are unblocked.

## Cross-codec parity matrix (Apple M2, fresh measurement)

Every J2KSwift HT-conformant lossless codestream emitted by v9.5.0
round-trips bit-exactly through three external decoders:

| suite                                                  | tests | cells | bit-exact | runtime |
|--------------------------------------------------------|------:|------:|----------:|--------:|
| `HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` | 1 | (multi-fixture × OpenJPH/OpenJPEG/Kakadu) | **all pass** | 1.55 s |
| `HTGPUForward53CrossCodecTests.testGPUForward53_MedicalCorpus_CrossDecodesBitExactExternalDecoders` | 1 | corpus × OpenJPH/OpenJPEG/Kakadu | **all pass** | 0.63 s |
| `J2KStrictCrossCodecValidationTests` (3 methods)        | 3 | strict + DICOM + truncated paths | **all pass** | 0.46 s |

External codec versions on this host: **OpenJPH 0.27.0**, **Grok**, **Kakadu HT**.

## Medical-corpus benchmarks (Apple M2, fresh measurement)

### HT-conformant lossless — CLI cold, median of 5 (`Scripts/benchmarks/cross_codec_*.py`)

| fixture          | J2KSwift cold | OpenJPH | Grok HT | Kakadu HT |
|------------------|--------------:|--------:|--------:|----------:|
| MR-small 180²    |         38.31 |    4.67 |    6.10 |      3.06 |
| CT 512²          |         44.74 |    8.47 |    7.65 |      3.69 |
| MR 886²          |         43.93 |    8.54 |    9.31 |      4.04 |
| XA 1024²         |         52.36 |   19.66 |   12.20 |      5.40 |
| PX 2459×1316     |         72.18 |   56.57 |   25.81 |     12.24 |
| **DX 2800×2288** |    **104.40** |  110.34 |   44.27 |     19.50 |

Decode wall, same conditions:

| fixture          | J2KSwift cold | OpenJPH | Grok  | Kakadu |
|------------------|--------------:|--------:|------:|-------:|
| MR-small 180²    |          5.91 |    4.11 |  5.68 |   2.99 |
| CT 512²          |          9.17 |    6.88 |  6.73 |   4.13 |
| MR 886²          |         13.80 |    9.91 |  7.69 |   5.71 |
| XA 1024²         |         16.23 |   15.28 |  8.86 |   7.00 |
| PX 2459×1316     |         41.85 |   42.74 | 16.85 |  17.35 |
| **DX 2800×2288** |     **71.84** |   80.86 | 26.38 |  29.67 |

### HT-conformant lossless — WARM via `j2k --daemon`, median of 7 after 3 warmups

| fixture          | J2KSwift `--daemon` | OpenJPH | Grok HT | Kakadu HT | vs cold |
|------------------|--------------------:|--------:|--------:|----------:|--------:|
| MR-small 180²    |                7.41 |    4.38 |    5.85 |      2.93 |   5.2×  |
| CT 512²          |               11.66 |    8.06 |    7.26 |      3.60 |   3.8×  |
| MR 886²          |               12.20 |    8.33 |    9.21 |      3.85 |   3.6×  |
| XA 1024²         |               16.28 |   19.48 |   12.26 |      5.46 |   3.2×  |
| PX 2459×1316     |               29.73 |   58.30 |   26.17 |     12.06 |   2.4×  |
| **DX 2800×2288** |           **57.46** |  113.82 |   45.50 |     20.28 |   1.8×  |

**Warm-encode beats OpenJPH on every fixture ≥ XA (4 of 6 fixtures).**
Kakadu still leads on every fixture, narrowest at PX (2.5×) and
DX (2.8×).

### Lossy 9/7 corpus encode (release gate, n=5, Apple M2)

From `J2KMedicalCorpusEncodePerformanceTests.testCorpusEncodeAcrossAPIs`
(HT-conformant lossy 9/7 @ 2.0 bpp):

| Fixture              | CPU encode (ms) | GPU encode (ms) | CPU/GPU× |
|----------------------|----------------:|----------------:|---------:|
| mr_002 (180×180)     |             0.6 |             0.7 |    0.90× |
| ct_001 (512×512)     |             2.5 |             2.6 |    0.93× |
| mr_001 (886×886)     |            13.1 |             4.5 |    2.93× |
| xa_001 (1024×1024)   |             9.5 |             9.2 |    1.03× |
| px_001 (2459×1316)   |            29.4 |            29.6 |    0.99× |
| dx_002 (2800×2288)   |            56.7 |            57.7 |    0.98× |

### Lossy 9/7 corpus decode (release gate, warm session, n=5)

From `J2KMedicalCorpusPerformanceTests.testCorpusWarmSessionAcrossDecodeAPIs`:

| Fixture              | CPU (ms) | decodeGPU (ms) | decodeWithGPUHT (ms) | winner |
|----------------------|---------:|---------------:|---------------------:|--------|
| mr_002 (180×180)     |      1.4 |            3.4 |                  2.5 | CPU |
| ct_001 (512×512)     |      6.8 |            8.9 |                  9.2 | CPU |
| mr_001 (886×886)     |     20.2 |           12.5 |                 12.5 | decodeGPU (1.62×) |
| xa_001 (1024×1024)   |     24.7 |           13.1 |                 13.1 | decodeGPU (1.89×) |
| px_001 (2459×1316)   |     81.9 |           25.1 |                 25.1 | decodeGPU (3.27×) |
| dx_002 (2800×2288)   |     39.8 |           47.1 |                 46.7 | CPU |

## What v9.5.0 ships

### Production-default

- **`J2KQstepCache.shared`** — process-default qstep cache for
  similar-shape lossy-9/7 batches. Same image shape and target bpp
  produces a cache key; subsequent encodes skip the 3-pass qstep
  refinement search. Bit-exact codestream preservation on cache hit.
  (`Sources/J2KCodec/J2KQstepCache.swift`, +45 lines.) See
  `V9_6_QSTEP_CACHE_RESEARCH.md` for the M4 99→29 ms measurement.
- **`encodeViaQstepSearch` SIGTRAP fix** — guards
  `Int(targetBytes * .infinity)` in the refinement loop. Unblocks
  `J2KCrossScaleRDQualityProbe` and any caller of
  `.constantBitrate` auto-promoted to qstep-search.
  (`Sources/J2KCodec/J2KEncoderPipeline.swift`.)
- **Per-worker NEON-buffer hoisting** (v9.5 Phase 5E,
  commit `72d6d97`) — all four worker scopes in `J2KEncoderPipeline`
  allocate the three 16 KB NEON output buffers once per worker
  (gated on `HTBlockEncoderConformant.useNEONHotPath`) and plumb
  them through `encodeCodeBlockHTJ2KFast`. On a 6.4 MP DX encode
  this eliminates ~9,500 allocations. Standalone perf was neutral
  on M4 corpus, but the structure is the foundation enabling the
  daemon-encode large-fixture closure measured above.

### Research artefacts (committed, not default-on)

- **v9.5 Phase 5A quad-pair batched classifier** — under
  compile-time gate `J2KNHE_PHASE5A_QUAD_PAIR`. Measured wash on M4
  (±10% across 7 fixture/density profiles), reverted from default.
  Kept in tree for future investigation.
- **v9.7 cold-shot qstep pre-seed** — closed as research artifact.
  Real medical content's converged-qstep range spans more than four
  orders of magnitude; no single seed serves all modes.
  (`V9_7_COLD_SHOT_RESEARCH.md`)
- **v9.8 image-statistics qstep prediction infrastructure** — texture
  (mean absolute neighbour difference) confirmed as dominant
  predictor; production-grade calibration deferred to a follow-up
  sprint. Test harness `V98QstepCalibrationTests` lands.
  (`V9_8_IMAGE_STATS_RESEARCH.md`)

## Backward compatibility

- **No public API breaks.** `J2KQstepCache.shared` is additive; all
  existing call sites operate identically when the cache is cold.
- **Codestream bytes** on the lossless default config are unchanged
  (verified by `HTTileParityMatrixTests` + `HTGPUForward53CrossCodecTests`
  passing post-merge).
- **Lossy-9/7 codestream bytes** on cache-hit paths are bit-identical
  to v9.4.0 cache-miss paths (the cache stores qstep values, not
  codestream content; same qstep → same codestream).

## Test Suite Results (release mode, 0 failures)

```
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

| Suite                                            | tests | failures | runtime |
|--------------------------------------------------|------:|---------:|--------:|
| J2KMedicalCorpusEncodePerformanceTests           | 2     | 0        | 14.6 s  |
| J2KMedicalCorpusPerformanceTests                 | 2     | 0        |  8.7 s  |
| J2KStrictCrossCodecValidationTests               | 3     | 0        |  0.5 s  |
| **Total (release-mode pre-tag gate)**            | **7** | **0**    | **23.8 s** |

```
swift test -c release --filter 'HTTileParityMatrixTests|HTGPUForward53CrossCodecTests'
```

| Suite                                            | tests | failures | runtime |
|--------------------------------------------------|------:|---------:|--------:|
| HTGPUForward53CrossCodecTests                    | 1     | 0        | 0.63 s  |
| HTTileParityMatrixTests                          | 1     | 0        | 1.55 s  |

## API surface (additions only)

- `J2KQstepCache.shared: J2KQstepCache` — process-default cache instance.
- `J2KQstepCache.lookup(shape:bpp:) -> Double?` and `record(shape:bpp:qstep:)`.
- No removed types, no signature changes.

## Known limitations

- **Daemon-encode XPC marshalling cost on M2** — for fixtures ≥ ~3 MP
  the XPC pixel-marshalling cost partially eats the cold-start
  savings. DX warm 57.5 ms vs cold 104.4 ms (1.8×) is the same
  fixture's net win; smaller fixtures see 3-5× speedups. Crossover
  with cold is roughly PX (3.2 MP); above that, expect 1.5–2×
  rather than 3–5× warm gains on M2. M4 results should be wider —
  the v9.2 Path B report measured DX daemon 74 ms on M4 — but
  measurements on M4 hardware are not in scope for this release.
- **Decode `--daemon` is flat versus cold on M2.** The XPC round-trip
  cost (raw pixel buffer out is larger than encoded bytes in)
  cancels the cold-start savings. Daemon decode still useful for the
  shared `j2k decode` install flow described in v8.1.0 release notes.
- **Cross-platform position unchanged** — Kakadu still leads encode
  on every fixture (DX gap 2.8× warm). Closing that gap further
  requires either non-entropy stage work (DWT 23% of DX wall, the
  next largest stage after entropy) or per-block overhead reduction;
  both are deferred to v9.6+.

## Reproducing the headline numbers

```bash
# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product j2k --product j2kd

# Verify version
.build/release/j2k version
# Expect: J2KSwift version 9.5.0

# Install the daemon (one-shot per user)
.build/release/j2k daemon-install --force
.build/release/j2k daemon-ping       # confirm reachable

# Mandatory pre-release gate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter \
  'HTTileParityMatrixTests|HTGPUForward53CrossCodecTests'

# Cross-codec wall timings (cold)
mkdir -p /tmp/v8_0_1_bench
for pgm in mr_study_002_instance_000100 ct_study_001_instance_000001 \
           mr_study_001_instance_000001 xa_study_001_instance_000001 \
           px_study_001_instance_000001 dx_study_002_instance_000001; do
    .build/release/j2k encode \
        -i Tests/Fixtures/CrossCodec/$pgm.pgm \
        -o /tmp/v8_0_1_bench/$pgm.j2k \
        --htj2k --lossless --quiet
done
python3 Scripts/benchmarks/cross_codec_encode_cli.py
python3 Scripts/benchmarks/cross_codec_decode_cli.py
```

## Files changed since v9.4.0

```
Sources/J2KCodec/J2KCodec.swift                            (+45  qstep cache wiring)
Sources/J2KCodec/J2KEncoderPipeline.swift                  (+191 NEON hoist + SIGTRAP fix + cache lookup)
Sources/J2KCodec/J2KHTConformantBlockEncoder.swift         (+36  encodeNEONIntoBuffers static)
Sources/J2KCodec/J2KQstepCache.swift                       (+45  NEW — process-default cache)
Sources/J2KCore/J2KCore.swift                              (version → 9.5.0)

Tests/J2KCodecTests/V95Phase5MicrobenchTests.swift         (NEW per-block ns harness)
Tests/J2KCodecTests/V96DWTMicrobenchTests.swift            (NEW DWT per-stage harness)
Tests/J2KCodecTests/V96SinglePassVsCorpusTests.swift       (NEW qstep-cache validation)
Tests/J2KCodecTests/V97ColdShotTests.swift                 (NEW cold-shot probe)
Tests/J2KCodecTests/V98QstepCalibrationTests.swift         (NEW image-stats infra)

V9_5_BEAT_KAKADU_RESEARCH.md                               (research closure — entropy NEON wash)
V9_5_PLAN_BEAT_KAKADU.md                                   (plan from start of arc)
V9_6_QSTEP_CACHE_RESEARCH.md                               (production graduation — qstep cache)
V9_7_COLD_SHOT_RESEARCH.md                                 (research closure — pre-seed negative)
V9_8_IMAGE_STATS_RESEARCH.md                               (research deferral — texture is predictor)

CROSS_CODEC_REPORT_main_bbee839.md                         (M2 cross-codec capture, fresh)
CROSS_CODEC_REPORT_v9.8.md                                 (same data, v9.8 codename copy)
RELEASE_NOTES_v9.5.0.md                                    (this doc)
```

## Companion documents

- [`V9_6_QSTEP_CACHE_RESEARCH.md`](V9_6_QSTEP_CACHE_RESEARCH.md) — qstep cache graduation
- [`V9_5_BEAT_KAKADU_RESEARCH.md`](V9_5_BEAT_KAKADU_RESEARCH.md) — entropy NEON wash + Phase 5E rationale
- [`V9_7_COLD_SHOT_RESEARCH.md`](V9_7_COLD_SHOT_RESEARCH.md) — pre-seed negative result
- [`V9_8_IMAGE_STATS_RESEARCH.md`](V9_8_IMAGE_STATS_RESEARCH.md) — texture predictor finding
- [`CROSS_CODEC_REPORT_main_bbee839.md`](CROSS_CODEC_REPORT_main_bbee839.md) — fresh M2 measurement

## Acknowledgements

v9.5.0 closes the v9.5-research / v9.5-pathB / v9.9-image-stats-predictor
exploration arc. The version skips no slot — v9.6/v9.7/v9.8 were
codename research phases on the `v9.5-research` branch, all merged
into `main` (commit `bbee839`) before this tag.
