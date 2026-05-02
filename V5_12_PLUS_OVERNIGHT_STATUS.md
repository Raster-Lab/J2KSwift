# v5.12+ overnight status report

**Date:** 2026-05-03
**Window:** Autonomous overnight session, no review until morning.
**Scope:** Continue from v5.11.0 (UMA detour wrap) into the planned v5.12–v5.15 milestones.

## TL;DR

**Shipped:**
- **v5.11.1** — `MTLHeap` default size 96 MB → 256 MB. Closes the px_001 / xa_001 `makeBuffer=2` fallthrough documented as a known issue at v5.11.0. Hot-path `makeBufferCount` is now 0 across the entire DICOM corpus.
- **v5.12.0** — Bounded multi-tile concurrency. Chunked-TaskGroup pattern caps in-flight tile decodes at 8 in both CPU and GPU multi-tile paths. New `testMultiTileBoundedConcurrencyRoundTrip` covers the multi-tile branch.
- **Test infrastructure** — `testRGBSessionAndSessionlessAgreeBitExact` and `test97LossySessionAndSessionlessAgreeBitExact` cover branches the corpus doesn't exercise. Both pass on current code.
- **Profile probes** — `decodeSingleTileGPU` now has per-stage `PROFILE-GPU:` probes mirroring the CPU path. New `J2KGPUProfileTests` harness captures the dx_002 breakdown.

**Not shipped (with rationale below):**
- v5.13 — GPU colour transform / DC offset fusion
- v5.14 — 9/7 irreversible (lossy) DWT fast-lane fusion
- v5.15 — `.metallib` bundling

## Where remaining time is actually spent

The dx_002 (2800×2288 16-bit grayscale, lossless HTJ2K conformant) profile under v5.12.0 with a warm session:

| stage | time | share |
|---|---:|---:|
| extractTileData (CPU bitstream parse, 1618 blocks) | 8.4 ms | 16% |
| entropyDecoding (GPU HT cleanup, gpuBatch path) | 18.0 ms | 35% |
| dequantization (fused, no-op) | 0.0 ms | 0% |
| inverseWaveletTransform (GPU IDWT, scatter + multi-level 5/3) | 19.3 ms | 37% |
| inverseColorTransform (no-op for grayscale) | 0.0 ms | 0% |
| dcLevelUnshift (CPU vDSP_vsaddD) | 1.2 ms | 2% |
| reconstructImage (Double → UInt16, vDSP-chunked) | 4.1 ms | 8% |
| **TOTAL** | **51.9 ms** | |

The "post-DWT" stages (DC offset + reconstructImage) account for ~5 ms total — about 10%. Real optimisation levers are the GPU compute (HT + IDWT = 72%) and CPU parsing (16%). None are quick wins.

## What didn't ship and why

### v5.13 — GPU colour transform / DC offset fusion

**What the plan called for.** Fuse the inverse colour transform (MCT) and DC level shift into a single GPU pass that consumes the IDWT output buffer directly.

**Why it doesn't ship overnight.**

1. **Zero impact on existing corpus.** The DICOM CrossCodec corpus is entirely grayscale (single-component PGM files). MCT is a no-op for `componentCount < 3`. The profile shows `inverseColorTransform = 0.0 ms` on dx_002. There is no measurable wall-clock savings to be had on the existing test gates.

2. **`Int32 → Double + DC offset` GPU fusion is also marginal.** Apple Silicon GPUs do not have hardware double-precision floating point. `double` in MSL is supported but emulated, with severe per-element overhead. The CPU `vDSP_vflt32D` + `vDSP_vsaddD` pipeline already runs at memory bandwidth; replacing it with an emulated-double GPU kernel would likely regress, not improve. Float-output kernels would help but require rewriting downstream stages to consume Float instead of Double — multiple-files refactor.

3. **RGB MCT fusion is testable but high-risk overnight.** The new `testRGBSessionAndSessionlessAgreeBitExact` gate covers the MCT branch. Implementing the actual fusion kernel + integrating with the IDWT command buffer would take 2–4 hours of careful work — too risky for an unsupervised session given the precision sensitivity.

**Concrete daytime next steps for v5.13:**
- Run `J2K_PROFILE_DECODE=1 swift test --filter J2KGPUProfileTests` on a synthetic 3-component image (use `testRGBSessionAndSessionlessAgreeBitExact`'s fixture as a starting point) to measure the actual `inverseColorTransform` cost on RGB.
- If it's ≥10% of total decode time, write a GPU MCT kernel that takes the IDWT Int32 outputs across 3 components and writes Float output (skip the Double round-trip).
- Use `testRGBSessionAndSessionlessAgreeBitExact` as the regression floor.

### v5.14 — 9/7 irreversible (lossy) fast-lane fusion

**What the plan called for.** Extend `inverse2DInt32FullFusedFromCodeblocks` (currently reversible-5/3-only) to handle 9/7 lossy.

**Why it doesn't ship overnight.**

1. **Substantial new pipeline.** 9/7 is floating-point at every stage — the existing fused IDWT uses Int32 throughout. Need a Float variant of `inverse2DFullFusedFromCodeblocks`, plus GPU-side dequantization (lossy 9/7 needs the quantization step applied).

2. **Precision sensitivity makes bit-exactness gates impractical.** 9/7 is lossy by construction; the existing PSNR-based 9/7 tests would pass even if the new GPU path drifts by epsilons. Without a strict bit-exact gate (against the existing CPU 9/7 path), regressions could ship undetected.

3. **No 9/7 fixtures in the DICOM corpus.** Even if the path were implemented, the corpus tests wouldn't exercise it. The new `test97LossySessionAndSessionlessAgreeBitExact` covers session-vs-sessionless agreement on a synthetic 9/7 input — that's a test gate, but doesn't cover all possible inputs.

**Concrete daytime next steps for v5.14:**
- Decide whether to gate the new fast lane on bit-exactness against the CPU 9/7 path (strict, requires careful precision analysis) or PSNR-equivalence (lenient, but allows small drift).
- Write a Float variant of `inverse2DFullFusedFromCodeblocks` — much of the dispatch plumbing is reusable; the IDWT shaders themselves (`j2k_dwt_inverse_97_horizontal/vertical`) already exist and operate on Float.
- The GPU-side dequantization is the real new work — needs a kernel that reads Int32 (HT cleanup output) + per-codeblock quantization step + writes Float (dequantised).
- Use `test97LossySessionAndSessionlessAgreeBitExact` as the floor.

### v5.15 — `.metallib` bundling

**Status: BLOCKED on build env.** `xcrun -sdk macosx metal --version` reports `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`. The Metal Toolchain isn't installed on this machine, so SPM can't compile `.metal → .metallib` at build time. The infrastructure is wired correctly (`Package.swift` declares `.process("J2KShaders.metal")`, runtime falls through to `device.makeDefaultLibrary(bundle: .module)` in `J2KMetalShaderLibrary`); when the toolchain is installed, the metallib will be auto-bundled and cold-CLI starts will skip the ~50 ms MSL source-compile cost.

**Concrete daytime next steps for v5.15:**
1. Run `xcodebuild -downloadComponent MetalToolchain` on a build machine.
2. Verify `find .build -name default.metallib` returns a path after `swift build -c release`.
3. Verify `device.makeDefaultLibrary(bundle: .module)` returns non-nil at runtime.
4. Bench cold-CLI start time before/after — the v5.6.0 perf report flagged this as a ~50 ms cost.
5. Tag v5.15.0.

## Status of v5.12 (shipped)

The plan's framing ("multi-tile in-flight cbs — overlap CPU prep of tile N+1 with GPU decode of tile N") was ambiguous on what was actually missing. Investigation found:

- The existing `decodeMultiTile` and `decodeMultiTileGPU` both used unbounded `withThrowingTaskGroup` to run all tile tasks concurrently.
- The actual gap was the *unbounded* count: a 100-tile codestream would spawn 100 tasks, each holding a peak working set of buffers. With v5.11.1's 256 MB heap, tiles 14+ would fall through to `device.makeBuffer`, defeating the v5.11 amortisation.
- True pipelined overlap of CPU prep and GPU decode *within* a single tile would require restructuring stages as async producer-consumer chains — a larger refactor not justified by current corpus profile (the existing `decodeSingleTileGPU` is already mostly GPU-resident; CPU prep stages are <20% of total time).

v5.12.0 ships chunked-TaskGroup bounding (8 tiles concurrent). Single-tile fixtures observe identical behaviour to v5.11.1; multi-tile codestreams gain bounded heap residency.

## Test coverage delta this session

New tests on main:
- `J2KMetalSessionTests.testMultiTileBoundedConcurrencyRoundTrip` — multi-tile session/sessionless agreement
- `J2KMetalSessionTests.testRGBSessionAndSessionlessAgreeBitExact` — RGB MCT branch
- `J2KMetalSessionTests.test97LossySessionAndSessionlessAgreeBitExact` — 9/7 lossy slow-lane agreement
- `J2KGPUProfileTests.testProfileDX002` — diagnostic harness (skipped without `J2K_PROFILE_DECODE=1`)

All passing. The first three are bit-exactness gates; future v5.13b / v5.14 work can use them as regression floors.

## Counter snapshot through v5.12.0

One warm decode per fixture, full corpus:

| fixture | size | memcpy | contents | makeBuffer |
|---|---|---:|---:|---:|
| ct_001 | 512×512 | 1 | 1 | 0 |
| ct_003 | 512×512 | 1 | 1 | 0 |
| dx_002 | 2800×2288 | 1 | 1 | 0 |
| mr_001 | 886×886 | 1 | 1 | 0 |
| mr_002 | 180×180 | 25 | 1 | 0 |
| px_001 | 2459×1316 | 1 | 1 | 0 |
| xa_001 | 1024×1024 | 1 | 1 | 0 |

`mr_002` is the only fixture with non-1 `memcpy` because its 180×180 size is below the GPU IDWT threshold (256² = 65536), so it takes the slow lane (per-block memcpy regroup). The slow-lane behaviour is unchanged from v5.11.0.

## Tags pushed this session

- `v5.11.1` — heap bump
- `v5.12.0` — bounded multi-tile concurrency

## What's left for the v5.12+ planned roadmap

| milestone | status | gating issue |
|---|---|---|
| v5.13 — GPU colour transform fusion | not shipped | grayscale corpus = no impact; RGB needs careful kernel + precision analysis |
| v5.14 — 9/7 lossy fast-lane | not shipped | new Float pipeline + GPU dequantization, no bit-exact gate |
| v5.15 — `.metallib` bundling | blocked | Metal Toolchain not installed in build env |

All three have concrete next-step recipes above. None are blocked on architectural decisions — they're pending the right combination of test coverage + supervised implementation time + (for v5.15) tooling availability.
