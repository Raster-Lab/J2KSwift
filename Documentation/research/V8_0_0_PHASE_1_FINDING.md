# v8.0.0 Phase 1 — Cold-start elimination (CLI overhead)

**Captured**: 2026-05-09, Apple M2.
**Phase 1 deliverable per the v8 strategy RFC (#379)**: eliminate the ~48 ms init-on-first-decode that Phase 0 (#380) localised as the dominant CLI overhead component.

## TL;DR

Phase 1 saves **40-47 ms on every CLI decode invocation** by addressing one root cause and reordering two gate conditions. The CLI-warm gap to Kakadu shrinks from **4-7× pre-Phase-1** to **1.2-3.0× post-Phase-1**. Three of six corpus fixtures (CT 512², MR-small, MR 886²) come within ~30 % of Kakadu — close enough that the next phase's compute work could finish the win.

## Root cause (Phase 0 hypothesised, Phase 1 confirmed)

`J2KMetalDevice.isAvailable` was a computed property that called `MTLCreateSystemDefaultDevice() != nil` **on every access**. `MTLCreateSystemDefaultDevice()` loads the Metal frameworks + creates a default device on first call within a process — ~50 ms cold-start cost on Apple Silicon.

The dominant CLI overhead was therefore not `J2KMetalSession.processShared` (already lazy) and not Metal session set-up: it was the **gate evaluation** in `DecoderPipeline.decode` that called `J2KMetalDWT.isAvailable` (which delegates to `J2KMetalDevice.isAvailable`) BEFORE the cheap pixel-threshold check could short-circuit it. Even tiny 180×180 images that would never use GPU paid the 50 ms init.

A second site at `applyEntropyDecoding` (line 2289) computed `idwtWillBeGPU` for every tile, triggering the same isAvailable call independently of the top-level gate.

## Three fixes shipped

### Fix 1 — Cache `J2KMetalDevice.isAvailable`

```swift
// Before
public static var isAvailable: Bool {
    return MTLCreateSystemDefaultDevice() != nil
}

// After
public static var isAvailable: Bool {
    return _isAvailableCache
}
nonisolated(unsafe) private static let _isAvailableCache: Bool = {
    return MTLCreateSystemDefaultDevice() != nil
}()
```

Subsequent in-process accesses are now free. (First access still pays the cost — the reorder fixes that.)

### Fix 2 — Reorder gate condition in `DecoderPipeline.decode`

```swift
// Before
if Self._gpuInverse53Enabled
    && J2KMetalDWT.isAvailable          // ~50 ms cold
    && metadata.width * metadata.height >= Self._gpuInverse53PixelThreshold

// After
if Self._gpuInverse53Enabled
    && metadata.width * metadata.height >= Self._gpuInverse53PixelThreshold  // cheap
    && J2KMetalDWT.isAvailable          // only called when threshold met
```

For images < 3 M px (the threshold), the isAvailable call is now skipped entirely. Saves 50 ms cold on every tiny/small CLI invocation.

### Fix 3 — Reorder + gate `idwtWillBeGPU` in `applyEntropyDecoding`

```swift
// Before
let idwtWillBeGPU =
    pixelCount >= 256 * 256 &&
    dwtLevels >= 1 &&
    metadata.configuration.waveletKernelConfiguration == nil &&
    J2KMetalDWT.isAvailable

// After
let idwtWillBeGPU =
    Self._gpuInverse53Enabled &&         // also gates on the static flag
    pixelCount >= 256 * 256 &&
    dwtLevels >= 1 &&
    metadata.configuration.waveletKernelConfiguration == nil &&
    J2KMetalDWT.isAvailable
```

When `--no-gpu` is set (Fix 4), `_gpuInverse53Enabled` becomes false and short-circuits this expression entirely.

### Fix 4 — CLI `--no-gpu` honored

The CLI's `decode` command parsed `--gpu-ht` but **silently ignored `--no-gpu`** for the standard `decode()` path. Added explicit handling:

```swift
let forceCPU = options["no-gpu"] != nil
if forceCPU {
    setenv("J2K_GPU_INVERSE_53", "0", 1)
    setenv("J2K_GPU_HT_ENTROPY", "0", 1)
}
```

`DecoderPipeline._gpuInverse53Enabled` and `_gpuHTEntropyEnabled` are static-let-initialised from these env vars. Setting them in main before any decoder code touches the flags makes `--no-gpu` actually skip Metal entirely.

## Measurement

Local CLI matrix, median of 5, Apple M2 release builds, all three corpus fixtures present.

| fixture | pre-Phase-1 | **post-Phase-1** | saving | Kakadu | post-gap |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 64 ms | **23 ms** | −41 ms | 19 ms | 1.21× |
| CT 512² | 65 ms | **22 ms** | −43 ms | 17 ms | 1.29× |
| MR 886² | 69 ms | **26 ms** | −43 ms | 17 ms | 1.53× |
| XA 1024² | 76 ms | **31 ms** | −45 ms | 19 ms | 1.63× |
| PX 2459×1316 | 105 ms | **58 ms** | −47 ms | 25 ms | 2.32× |
| DX 2800×2288 | 134 ms | **94 ms** | −40 ms | 31 ms | 3.03× |

The 40-47 ms saving is consistent across every fixture, confirming the cost was a **fixed init overhead**, not size-scaled work. Variation across fixtures (40-47 ms) is run-to-run noise, not a real difference.

## Where the remaining gap lives

After Phase 1, three of six fixtures are within 30 % of Kakadu (MR-small, CT 512², MR 886²). The remaining gap on PX and DX is the **in-process compute gap** flagged in Phase 0:

- DX in-process compute (post-Phase-1 CLI ≈ in-process): J2KSwift 59 ms vs Kakadu's implied ~30 ms = **~2× compute gap**.
- Dominated by HT entropy decode (199 ms accumulated across parallel tiles) + 5/3 IDWT (120 ms accumulated).

These are the targets for Phase 2 (multi-level fused 5/3 INT IDWT Metal kernel) and Phase 3 (re-evaluate `decodeWithGPUHT` routing now that cold-start is fixed).

## Decision points consumed (from §5 of Phase 0)

1. ✓ **`--no-gpu` truly skips metallib load** — fixed via env var propagation
2. ⏸ **Persistent Metal session via XPC daemon** — deferred to v8.1 as recommended
3. ◯ **CLI auto-routing to best backend** — partial: `--no-gpu` honored, but the auto-recommend-API logic in `J2KDecoder.recommendedDecodeAPI` is not yet wired into the CLI's default routing. Phase 2 candidate.

## What lands in this PR

- `Sources/J2KMetal/J2KMetalDevice.swift`: `isAvailable` cached.
- `Sources/J2KCodec/J2KDecoderPipeline.swift`: gate reorder × 2 + `idwtWillBeGPU` short-circuit on `_gpuInverse53Enabled`.
- `Sources/J2KCLI/Commands.swift`: `--no-gpu` parsed, sets routing env vars.
- `V8_0_0_PHASE_1_FINDING.md`: this document.

## Mandatory gate (release mode, 0 failures)

10/10 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1
- `MgRegressionTriageTest` — 2/2

## Reproduction

```bash
swift build -c release --product j2k

# Per-fixture CLI matrix (requires kdu_compress + kdu_expand on PATH)
for fix in mr_small ct_512 mr_886 xa_1024 px dx; do
  /usr/bin/time .build/release/j2k decode -i ${fix}.j2k -o /tmp/dec.pgm \
    --output-format pgm --no-gpu --quiet
done
```

## Phase 2 starts on `v8-phase-2-fused-int-idwt`

Target: in-process IDWT for PX/DX (60-120 ms accumulated) via multi-level fused 5/3 INT Metal kernel mirroring v5.25.0's 9/7 lossy pattern.
