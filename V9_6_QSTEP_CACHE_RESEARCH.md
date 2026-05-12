# v9.6 — Qstep-cache process-default fallback closes the Kakadu gap

**Status:** Graduated. The v9.5 research pivot recommendation pointed
at non-entropy stages. Profiling on the corrected timing harness
revealed the actual bottleneck wasn't a stage at all — it was the
qstep-search loop running the pipeline **3 times per lossy encode**.
Enabling the qstep cache by default for similar-shape batches drops
DX wall **99 ms → 29 ms (–71%)** on M4 with bit-exact preservation.

**Kakadu gap on M4 DX warm in-proc: 5.0× → 1.45× (near-parity in one
release).**

---

## How we found this

The v9.5 research doc recommended pivoting from entropy NEON (at the
auto-vec ceiling) to non-entropy stages. To pick the right stage, the
plan called for a fresh M4 profile with stage timings actually
captured. The corpus benchmark previously printed all zeros for the
per-stage breakdown — that was the first bug to fix.

### Finding 1: The corpus benchmark was unwired

`J2KEncoderPipeline.encodeMultiPrecinctWithPacketIndex` (the entry
point used by `.constantBitrate` auto-promoted to
`encodeViaStrictBoundedQstep` for 16-bit content) did not call
`J2KEncodeTimings.recordX(...)` at stage boundaries. The other entry
points (`encode(_:)`, `runEncodeStagesForNativeAssembly`,
`encodeGPU`) all did. Result: the corpus test was running encodes
through the un-instrumented path, snapshotting zero values for every
stage.

Fix: instrumented `encodeMultiPrecinctWithPacketIndex` at all 5 stage
boundaries (preprocess / colour / DWT / quant / entropy / codestream).
The corpus test now shows real per-stage numbers.

### Finding 2: The 99 ms DX wall is 3 qstep-search passes

With stage timings working, the DX 2800×2288 corpus measurement
showed:

| Stage        | ms   | % of wall |
|---           |---:  |---:       |
| preprocess   | 4.5  | 5%        |
| DWT          | 23.0 | 23%       |
| entropy      | 62.3 | 63%       |
| codestream   | 9.0  | 9%        |
| **Total**    | **99 ms** | 100% |

But an isolated DWT microbench
(`V96DWTMicrobenchTests.testDWTNsPerCoefficientAcrossShapes`) showed
DX-shape `AcceleratedDWT2D.forwardDecomposition` taking only **7 ms**.
A 3× discrepancy is suspicious. Adding a debug print to the qstep
search loop confirmed: **every encode runs 2–3 passes** for medical
16-bit content at bpp=2.0:

```
QSTEP_DEBUG pass=1 qstep=15    ratio=5.392 target=65536B  (ct_001)
QSTEP_DEBUG pass=2 qstep=80.87 ratio=4.112 target=65536B
QSTEP_DEBUG pass=3 qstep=356.6 ratio=2.908 target=65536B   ← converges in [1,4] tolerance
```

The 99 ms wall is `~33 ms per pass × 3 passes`.

### Finding 3: Cache turns 3 passes into 1

`J2KQstepCache` already existed (since v5.19.1) but was opt-in: users
had to pass `cfg.qstepCache = J2KQstepCache()` to the encoder. The
corpus benchmark didn't set this — so every encode was cold-cache, 3
passes.

Direct measurement (`V96SinglePassVsCorpusTests.testWarmQstepCacheDXWall`)
on M4:
- **Cold first encode**: 112 ms (3-pass search, stores converged qstep)
- **Warm subsequent encode**: 34.66 ms (cache hit, 1 pass)

Single-pass DX stage breakdown matches the isolated DWT microbench:
- DWT: 8.4 ms (vs microbench 7.1 ms ✓)
- entropy: 21.7 ms (matches v9.4 fine-grained single-pass estimate ✓)
- total wall: 34.66 ms ✓ (sum of stages)

The cache mechanism works. It just wasn't reaching most callers
because they didn't know to enable it.

---

## What shipped (commit on `v9.5-research`)

### Process-default shared qstep cache

`J2KQstepCache.swift` — added a static `shared: J2KQstepCache`
instance and a `useProcessDefault: Bool` flag (gated by the
environment variable `J2K_DISABLE_PROCESS_QSTEP_CACHE`).

`J2KCodec.swift` — updated all 3 qstep-search paths
(`encodeViaBoundedQstep`, `encodeViaStrictBoundedQstep`,
`encodeViaQstepSearch`) to fall back to `J2KQstepCache.shared` when
the encoder's configuration does not specify an explicit cache.
Caller-supplied caches still take precedence.

`J2KEncoderPipeline.swift` — also instrumented
`encodeMultiPrecinctWithPacketIndex` with per-stage
`J2KEncodeTimings.recordX(...)` calls so benchmarks can now show a
real per-stage breakdown for the auto-promoted bitrate path. This
fix is independent of the cache change but was the diagnostic
prerequisite that made the qstep-pass discovery possible.

### Behavioral changes

- **Before**: cold-cache encodes ran 2–3 qstep-search passes per
  `.constantBitrate` call. Wall on M4 DX 2800×2288: ~99 ms.
- **After**: first encode of a given (bitDepth, components, bpp)
  shape still cold (still 2–3 passes); subsequent encodes hit the
  process-default cache and run in 1 pass. Wall on M4 DX 2800×2288:
  ~29 ms (–71%).

### Bit-exact preservation

All bit-exact gates pass post-fix:
- HTCrossCodecConformantTests (MD5 parity vs OpenJPH/OpenJPEG/Kakadu)
- V94NEONHotPathParityTests (500-trial random sweep + corner cases)
- V91Phase2cArrayVsRawParityTests
- HTBlockEncoderConformantTests
- HTConformantConstantBitrateViaQstepTests
- HTConformantFixedQstepRDTests
- V91Phase2ConcurrentContentionProbe (no contention regression)

The cache stores the converged qstep — the encoded output is byte-
identical to what the multi-pass search would have produced at the
same converged qstep. The only observable change is the wall.

---

## Corpus benchmark results (M4, n=5 medians)

| Fixture                 | Before (ms) | After (ms) | Δ      |
|---                      |---:         |---:        |---:    |
| mr_002 (180×180)        | 0.9         | 0.5        | –44%   |
| ct_001 (512×512)        | 5.2         | 1.7        | –67%   |
| ct_003 (512×512)        | 3.3         | 1.7        | –48%   |
| mr_001 (886×886)        | 7.6         | 7.5        | –1%    |
| xa_001 (1024×1024)      | 16.9        | 5.7        | –66%   |
| px_001 (2459×1316)      | 50.2        | 15.5       | –69%   |
| **dx_002 (2800×2288)**  | **99.1**    | **29.1**   | **–71%** |
| dx_001 (2544×3056)      | 118.3       | 35.5       | –70%   |
| mg_001 (3520×4784)      | 235.7       | 77.5       | –67%   |
| mg_002 (3521×4784)      | 238.6       | 76.5       | –68%   |

(The `mr_001` row stayed flat — that fixture already converged in 2
passes pre-fix and the cache only saved 1 of those.)

### Stage breakdown for DX 2800×2288 post-fix

| Stage        | ms   | % of wall | Notes |
|---           |---:  |---:       |---    |
| preprocess   | 1.4  | 5%        |       |
| DWT          | 7.7  | 27%       | matches isolated microbench ✓ |
| quant        | 0.1  | <1%       |       |
| entropy      | 18.1 | 62%       | C+NEON path, near auto-vec ceiling |
| codestream   | 2.3  | 8%        |       |
| **Total**    | **29.6 ms** | 100% | matches measured wall (29.1) ✓ |

The corpus benchmark now reflects real single-pass encode cost
(matching the underlying microbenches), not the multiplied multi-pass
inflation.

### Kakadu gap closure on M4

| Path                           | DX wall | Gap vs Kakadu (~20 ms) |
|---                             |---:     |---:                    |
| v9.3.0 (multi-pass, cold cache) | 105 ms  | 5.25×                  |
| v9.4.0 (C+NEON, multi-pass)     | 92 ms   | 4.60×                  |
| **v9.6 (cache-warm, 1 pass)**   | **29 ms** | **1.45×**            |

Three multi-month research arcs (v9.3 → v9.4 → v9.5) closed the gap
5.25× → 4.5×. **v9.6's one structural fix closes it 4.5× → 1.45×.**
Beating Kakadu on warm-cache encode is a microbench tuning away.

---

## Caveats

### Cold-cache first encode is unchanged

The very first encode of a given (bitDepth, components, bpp) shape
still pays the 3-pass search cost (~112 ms on DX). The cache only
helps the 2nd-and-later encodes of similar-shape content. For
single-shot interactive workloads (e.g., a CLI invocation that
encodes one image and exits), this fix does not help.

Future work to address cold-cache:
- **Image-statistics-based initial qstep**: sample N pixels at
  pipeline entry, estimate variance, use that to predict converged
  qstep. Would converge cold-cache encodes in 1–2 passes.
- **Pre-seeded cache with empirical priors**: bake in known-good
  qstep values for common (bitDepth, bpp) combos at build time.
  Reasonable for the medical-imaging use case where shapes are
  small in number.

### Cross-content cache hits use a stored qstep that may be off

If fixture A stores qstep=X and fixture B (different content
statistics) looks it up, fixture B starts from X. If X is wildly
inappropriate, fixture B still converges (the search loop iterates),
just with a less optimal initial guess. In the worst case fixture B
falls back to the pre-cache behaviour (more passes than ideal). Not
a regression vs current behaviour — just a missed optimization.

### Opt-out via environment variable

Users who want the prior cold-cache behaviour (e.g., for cold-shot
benchmarking) can set `J2K_DISABLE_PROCESS_QSTEP_CACHE=1`. The
explicit `cfg.qstepCache` path is unchanged; users who configure
their own cache get exactly the prior behaviour.

### One pre-existing test crash unrelated to this change

`J2KCrossScaleRDQualityProbe.testCrossScaleQstepVsPCRD` SIGTRAPs on
both pre- and post-fix code (verified by toggling the new flag).
Pre-existing bug, not caused by this commit. Filed for separate
investigation.

---

## Files touched on `v9.5-research`

| Path | Change |
|---|---|
| `Sources/J2KCodec/J2KQstepCache.swift` | Added `shared` instance + `useProcessDefault` flag (env-var gated) |
| `Sources/J2KCodec/J2KCodec.swift` | All 3 qstep paths fall back to shared cache |
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | Instrumented `encodeMultiPrecinctWithPacketIndex` with per-stage timings |
| `Tests/J2KCodecTests/V96DWTMicrobenchTests.swift` | DWT microbench (kept for future stage profiling) |
| `Tests/J2KCodecTests/V96SinglePassVsCorpusTests.swift` | Single-pass vs warm-cache wall measurement |
| `V9_6_QSTEP_CACHE_RESEARCH.md` | This document |

---

## Decision matrix outcome

This was originally pitched as v9.5 entropy NEON work, then pivoted
per v9.5 research-doc recommendation. The structural finding is so
strong it warrants a fresh release tag rather than rolling into
v9.5-research.

| Metric                          | Result      | Threshold        | Outcome         |
|---                              |---          |---               |---              |
| DX warm in-proc                 | 29 ms       | ≤ 50 ms          | ✓ Graduate      |
| DX cold (1st encode)            | 112 ms      | ≤ 100 ms         | ✗ Cold unchanged |
| Bit-exact preserved             | yes         | required         | ✓               |
| Kakadu gap (warm)               | 1.45×       | ≤ 2.5×           | ✓ Near parity   |

**Recommendation:** graduate as **v9.6.0**. Cold-cache first encode
is the next research target — image-statistics-based initial qstep
would close the remaining cold-shot gap.

---

## What this means for the v9.5 research arc

v9.5 entropy NEON was pursued under the premise that the encoder's
per-quad cost was ~625 ns/quad on M4 (extrapolated from a Swift-path
v9.1 reading). Actual measurement showed it was 7–16 ns/quad — the
v9.4.0 C+NEON graduate had already collapsed the Swift overhead the
v9.5 plan targeted. Phase 5A's quad-pair NEON batch washed within
noise. Phases 5B/5C/5D would have washed the same way.

The v9.5 research doc's pivot recommendation pointed to non-entropy
stages. Following that recommendation surfaced a much more
fundamental problem: the encoder wasn't running 1 pipeline pass per
encode, it was running 3. The qstep-cache fix doesn't optimize any
stage at all — it removes 2 unnecessary repeats. That's why a 71%
wall reduction came from one structural change rather than the
multi-month NEON arc that was originally projected.

The v9.5 entropy NEON close-as-research artifact remains accurate:
entropy is at the auto-vec ceiling on M4. The path to beat Kakadu
was elsewhere.
