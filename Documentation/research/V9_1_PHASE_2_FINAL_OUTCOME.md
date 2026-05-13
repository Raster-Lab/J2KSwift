# V9.1 Path B Phase 2 — Final outcome: integration complete, wall measurement WASH

**Date**: 2026-05-11
**Branch**: `v9.1-pathB`
**Status**: ⚠️ **Production integration is bit-exact + cross-codec-parity-validated, but A/B wall measurement is wash on M2 across 3 runs.** Consistent with the 18+ prior lever-ceiling investigations on M2 + Swift release.

## TL;DR

The raw-pointer engine architecture works exactly as designed:
- ✅ 3 production engine types added (`HTMagSgnEncoderRawConformant`, `HTMELEncoderRawConformant`, `HTReverseBitEmitterRawConformant`)
- ✅ Generic `encodeLoopGeneric` helper shared between Array + Raw paths
- ✅ Bit-exact codestream across all 6 medical-corpus fixtures (Array MD5 == Raw MD5)
- ✅ Cross-codec parity: OpenJPH + Kakadu pixel-exact decode of Raw codestream
- ✅ `HTTileParityMatrixTests` + `J2KStrictCrossCodecValidationTests` PASS with raw mode enabled
- ✅ V91Phase2cArrayVsRawParityTests (9 unit tests) all PASS
- ✅ Per-worker buffer hoisting (Phase 2d) plumbed through encoder pipeline

But:
- ⚠️ A/B wall measurement is wash on M2 across 3 runs (signal within noise floor)

## A/B benchmark — 3 runs

Each run: median per fixture over `n` warm-cache encode invocations, J2KSwift in-proc, `--no-daemon`.

### Run #1 (n=8, post-Phase-2c initial integration)

| Fixture           | Array (ms) | Raw (ms) | Δ (ms) | Δ %     |
|-------------------|-----------:|---------:|-------:|--------:|
| MR-small 180²     |     71.19  |   37.02  | -34.17 | -48.00% |
| CT 512²           |     63.71  |   49.71  | -14.00 | -21.97% |
| MR 886²           |     61.06  |   45.89  | -15.17 | -24.84% |
| XA 1024²          |     72.43  |   67.59  |  -4.84 |  -6.68% |
| PX 2459×1316      |    112.82  |  114.35  |  +1.53 |  +1.35% |
| **DX 2800×2288**  |   **206.10** | **182.04** | **-24.06** | **-11.67%** |
| corpus total      |    587.30  |  496.59  | -90.71 | -15.44% |

### Run #2 (n=8, post-Phase-2d hoisting)

| Fixture           | Array (ms) | Raw (ms) | Δ (ms) | Δ %     |
|-------------------|-----------:|---------:|-------:|--------:|
| MR-small 180²     |     40.78  |   37.85  |  -2.92 |  -7.17% |
| CT 512²           |     43.18  |   42.68  |  -0.50 |  -1.16% |
| MR 886²           |     44.86  |   42.54  |  -2.32 |  -5.17% |
| XA 1024²          |     61.82  |   60.01  |  -1.81 |  -2.93% |
| PX 2459×1316      |    111.72  |  110.28  |  -1.44 |  -1.29% |
| **DX 2800×2288**  |   **173.62** | **170.30** |  **-3.33** |  **-1.92%** |
| corpus total      |    475.97  |  463.65  | -12.33 |  -2.59% |

### Run #3 (n=10 + 3 warmups, fully thermally settled)

| Fixture           | Array (ms) | Raw (ms) | Δ (ms) | Δ %     |
|-------------------|-----------:|---------:|-------:|--------:|
| MR-small 180²     |     37.06  |   37.36  |  +0.31 |  +0.82% |
| CT 512²           |     42.48  |   44.52  |  +2.04 |  +4.81% |
| MR 886²           |     41.91  |   44.85  |  +2.94 |  +7.01% |
| XA 1024²          |     59.84  |   63.52  |  +3.68 |  +6.14% |
| PX 2459×1316      |    110.16  |  106.71  |  -3.45 |  -3.13% |
| **DX 2800×2288**  |   **173.34** | **172.87** |  **-0.46** |  **-0.27%** |
| corpus total      |    464.79  |  469.84  |  +5.05 |  +1.09% |

### Analysis

DX wall deltas across 3 runs: **-24.06, -3.33, -0.46 ms.** The median is -3.33 ms (Run #2). Runs #1 and #3 are likely thermal artifacts — the Run #1 Array baseline (206 ms) is 33 ms slower than the thermally-settled Runs #2/#3 baseline (173 ms), suggesting M2 P-cores were throttling under sustained load in the first measurement. The Raw path's apparent -24 ms win in Run #1 is therefore not a real algorithmic improvement — it's noise from the thermal state delta.

Run #3 with n=10 + 3 warmups (most thermally stable) shows the cleanest signal: corpus total +1.09% (Raw is *slightly slower* than Array) and DX -0.27% (within measurement noise).

**Verdict**: Raw-pointer engines produce a wall delta within the noise floor on M2 + Swift release. The 5× concurrent contention measured in `V91Phase2ConcurrentContentionProbe` was real in that probe's tight-loop pattern but does NOT translate to measurable end-to-end wins in the actual encoder pipeline.

### Why the contention probe didn't predict the wash

The Phase 2 concurrent contention probe ran a tight loop of `HTBlockEncoderConformant.encode` calls on the SAME block per task. It measured 5× per-block inflation at 6 workers. In the actual encoder pipeline:

- Per-block work is more than just the entropy encode: sign-magnitude conversion (~4 µs), HTBlockLayoutConformant.assemble (~10 µs), per-block setup. Encode is ~30-40% of per-block wall.
- Each block has different content, different sizes, different significance density. Cache behaviour differs from the probe's "same block 1000 times" pattern.
- The Array engines' `bytes.append` with reset-preserving-capacity has good cache behaviour — the appends mostly hit L1-resident allocated storage, only occasionally crossing the "ARC retain on Array storage" path.
- TaskGroup workers in the real pipeline have other work (DWT, MCT, coefficient transposes) that masks the entropy-only contention.

The probe identified a TRUE contention source but it's not the dominant cost in the real pipeline. Phase 2 closes as **wash + lesson learned**: tight-loop microbenches can mislead about which optimisations translate to end-to-end wins.

## Lever-ceiling pattern (now 19 investigations on M2)

| Direction                         | Wash count   |
|-----------------------------------|--------------|
| Decode codec                      | 6 (v6-alpha4, v7.4, v7.5, v8.1, v8.4×3, v8.5) |
| Encode codec                      | 3 (v8.6 forward DWT, v8.6 HT classifier, v8.7 algorithmic) |
| Dispatch                          | 1 (GCD vs TaskGroup) |
| Accelerate                        | 1 (vDSP/vImage/BLAS) |
| AMX                               | 1 (corsix/dougallj review) |
| IPC primitives                    | 1 (file mmap, IOSurface, mach_vm_remap, xpc_shmem) |
| Metal pipeline cache              | 1 (MTLBinaryArchive) |
| Daemon batch RPC                  | 1 (in-process batch already amortises) |
| Daemon concurrent dispatch        | 1 (in-process parallel already faster) |
| CLI cold-shot floor               | 1 (3.28 ms structural Swift-runtime tax) |
| Multi-tile parallelism            | 1 (already 86% efficient; encoder hardware-bound) |
| Kakadu gap analysis               | 1 (algorithm-efficiency gap, not parallelism) |
| **Raw-pointer engine refactor**   | **1 (this — contention probe → wash at end-to-end)** |

## What's on `v9.1-pathB` after this session

**Production code** (would be permanent if this branch merged):
- `Sources/J2KCodec/J2KHTConformantRawPointerEngines.swift` — 3 raw-pointer engine types + protocols
- `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` — refactored to generic `encodeLoopGeneric` + Array overload + Raw overload
- `Sources/J2KCodec/J2KEncoderPipeline.swift` — env-var-gated routing through raw engines, per-worker buffer hoisting in 4 worker scopes
- `Sources/J2KCodec/J2KHTEntropyEncoderProfile.swift` — encoder profile counter infrastructure

**Test code** (research artifacts):
- 8 V91Phase* test files (corpus probe, microbench, parity prototypes, parity gate)

**Documentation** (research findings):
- 6 V9_1_PATH_B/V9_1_PHASE_* markdown files documenting the full pivot history

## Recommendation

**Do NOT merge to main as v9.1.0.** Per the user's standing directive ("I don't want to ship the half work"), shipping a wash result violates the release-readiness gate — even though the integration is correct and bit-exact, there's no measurable user benefit on M2.

**Three options**:

1. **Tag as `v9.1-research`** — preserves the bit-exact infrastructure on a research branch (same pattern as v8.8-research, v8.9-research, v9.0-research). The raw-pointer engines + protocols stay available for future investigations (M3+/A-series silicon, or when allocator behavior changes). No production impact.

2. **Cherry-pick the Phase 0 profiler infrastructure only** to main as v8.2.0 — gives the project ongoing encoder observability without the wash-level production integration. The raw-pointer types and refactor stay on `v9.1-research`.

3. **Full revert** — accept that the Phase 2 work was a research exercise with no production deliverable. Close the branch.

I recommend **Option 1**: tag the branch, preserve the infrastructure, document the wash as the 19th lever-ceiling investigation. The Phase 0 measurement infrastructure (encoder profiler) has standalone value for future work and could be cherry-picked separately later.

## What WAS worth tonight's autonomous work

- Identified that the 5× concurrent contention is real in microbench but NOT the dominant cost in the real encoder pipeline
- Built bit-exact raw-pointer engine architecture (reusable)
- Refactored encode() into generic + Array/Raw wrappers (cleaner code)
- Established the encoder profile infrastructure (Phase 0 — useful regardless of Phase 2 outcome)
- Documented 5 phases of pivots driven by empirical data
- Honest engineering: didn't ship a wash as a v9.1.0 release

The mission to close the Kakadu gap on M2 remains unfinished. The lever-ceiling pattern (now 19 investigations) suggests the gap is structural to M2 + Swift release. Path C (M3+/M4 silicon probe) on different hardware is the remaining viable direction.
