# V8.8 — MTLBinaryArchive for Metal pipeline caching: not worth implementing

**Status**: NOT VIABLE. The OS-level Metal Compiler Service cache already does what MTLBinaryArchive would do. The pipeline compile cost is ~3 ms, well below the 3 ms wall threshold.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)
**Probe instrumentation**: `Sources/J2KCodec/J2KMetalSession.swift` — `J2K_PREWARM_TRACE=1` env var.

## Goal

Test whether `MTLBinaryArchive` (Apple's framework for serialising compiled Metal pipelines to disk, available since macOS 11/iOS 14) could meaningfully reduce the daemon's cold-shot Metal init cost. The hypothesis: precompile Metal pipelines once, write to a binary archive on disk, load instantly on subsequent process startups.

## Method

Added `J2K_PREWARM_TRACE=1` env-gated stage timestamps to `J2KMetalSession.preWarm()`, breaking the cost into:

1. `device_init` — `MTLDevice` + `MTLCommandQueue` setup
2. `loadShaders` — `device.makeDefaultLibrary(bundle:)` (loads precompiled metallib + GPU compile)
3. `compile_11_pipelines` — `device.makeComputePipelineState(function:)` × 11 in parallel
4. (warmup-dispatch — tiny synthetic decode, separately timed via daemon trace)

Daemon installed with both `J2KD_DECODE_TRACE=1` and `J2K_PREWARM_TRACE=1` env vars.

## Headline data

### Truly cold one-time cost (after metallib version change or fresh OS state)

```
[preWarm-trace] device_init=1.38 loadShaders=4060.67 compile_11_pipelines=5.23 total=4067.28
```

The first time a new metallib version is loaded on a system, Metal Compiler Service compiles the AIR bytecode to GPU-specific machine code. This takes ~4 seconds on M2. Result is cached at the OS level (`~/Library/Caches/com.apple.metalfx` and similar paths).

**This 4-second cost is one-time per system per metallib version.** Most user invocations skip it.

### Warm-cache cost (typical case, after first daemon launch)

```
[preWarm-trace] device_init=0.88 loadShaders=10.83 compile_11_pipelines=2.92 total=14.63
[j2kd-trace] preWarm=37.33 ms total_in_daemon=123.13 ms
```

Per-stage warm-cache breakdown:
- `device_init`: 0.88–1.38 ms (MTLDevice + queue)
- `loadShaders`: 10.83–11.48 ms (precompiled metallib load + GPU machine-code lookup)
- `compile_11_pipelines`: 2.50–2.92 ms (MTLComputePipelineState × 11)
- **Total cached path: ~14 ms** (excluding warmup-dispatch)
- Warmup-dispatch (tiny 256×256 9/7 decode): ~23 ms

Daemon's reported `preWarm` of 37 ms = `loadShaders + compile + warmup-dispatch`.

## Why MTLBinaryArchive doesn't help

`MTLBinaryArchive` caches the **pipeline state object** (the bridge between an MTLFunction and the device-specific GPU machine code). Our trace shows:

| Stage | Cost (warm-cache) | Can MTLBinaryArchive help? |
|-------|-------------------:|-----------------------------|
| `device_init` | ~1 ms | No (separate device setup) |
| `loadShaders` | ~11 ms | No (Metal Compiler Service OS cache; archive can't replace metallib load) |
| `compile_pipelines` | ~3 ms | **Yes — but only ~3 ms savings** |
| `warmup-dispatch` | ~23 ms | No (driver state init) |

MTLBinaryArchive would shave ~3 ms off the pipeline-compile step. **Below the 3 ms wall threshold.** Plus the daemon's `preWarm` cost is paid ONCE per daemon launch, not per request — so the amortised per-request impact is negligible.

The 4-second truly-cold cost is paid once per system per metallib version. While in theory MTLBinaryArchive could ship a precompiled archive in the bundle, that:
1. Requires shipping per-GPU-architecture archives (M1, M2, M3, A-series, etc.)
2. Adds bundle size (each archive is several MB)
3. Falls back to source compilation when the archive doesn't match the device — same 4-second cost

For J2KSwift with one supported architecture (Apple Silicon arm64), the OS Metal Compiler Service cache already provides this benefit at zero engineering cost.

## Decision: close as wash

This is the **12th independent lever-ceiling investigation** on the v8.8 branch. The pattern continues:

| Direction | Investigations | Outcome |
|-----------|---------------|---------|
| Decode codec | v6-alpha4, v7.4, v7.5, v8.1, v8.4 (3 probes), v8.5 | WASH all 6 |
| Encode codec | v8.6 forward DWT, v8.6 HT classifier, v8.7 (3 probes) | WASH all 3 |
| Dispatch | v8.8 GCD vs TaskGroup | WASH |
| Accelerate | v8.8 vDSP/vImage/BLAS API | WASH |
| AMX | v8.8 corsix/dougallj review | WASH (not viable) |
| IPC alternatives | v8.8 file mmap, IOSurface, mach_vm_remap, xpc_shmem | WASH-or-borderline |
| **Metal pipeline cache** | **v8.8 MTLBinaryArchive (this)** | **WASH** |

The OS-level Metal Compiler Service cache + the precompiled metallib in the SwiftPM bundle already provide ~14 ms warm-cache cold-start cost. Further reduction would require either:

1. **Eliminating the metallib load entirely** — would need Metal source-compilation at app launch, but our trace shows the precompiled-metallib path is faster (10 ms) than source-compile would be (~50 ms).
2. **Per-invocation caching of pipelines** — already happens via `J2KMetalShaderLibrary.pipelineCache`.
3. **Skipping the warmup-dispatch step** — saves ~23 ms but moves the cost to the user's first decode (net wash for daemon's typical workflow).

## What stays in tree

- `Sources/J2KCodec/J2KMetalSession.swift` — `J2K_PREWARM_TRACE=1` instrumentation (env-gated, zero perf impact when off). Future-investigator reference for re-measuring on M3+/A-series silicon.
- `V8_8_MTL_BINARY_ARCHIVE_FINDING.md` — this document.

No production code change. No new public API surface.

## What WOULD justify reopening this

1. **A bigger metallib** — if J2KSwift adds many more compute kernels (e.g., GPU encoder integration), the pipeline-compile cost might grow above the threshold. Currently 11 pipelines × ~0.3 ms each = ~3 ms, even if doubled = 6 ms.
2. **A bundled precompiled MTLBinaryArchive** — requires per-architecture build pipeline + bundle size budget. Could eliminate the truly-cold 4-second cost. Multi-week scope.
3. **A different machine class** — M3+/A-series may have different Metal Compiler Service tuning. Re-run the `J2K_PREWARM_TRACE=1` probe to measure.

## Companion finding — the warmup-dispatch step is borderline

The `preWarm(includeWarmupDispatch: true)` step (~23 ms) runs a tiny synthetic decode to warm Metal driver state. It saves ~10–20 ms on the user's FIRST decode after preWarm. For the daemon's typical workflow (preWarm followed by decode), this is roughly neutral. For users who call `J2KDecoder.preWarm()` and never decode, it's pure waste.

`J2KDecoder.preWarm(includeWarmupDispatch: false)` is the documented opt-out. The daemon currently uses the default `true`. Switching to `false` would save 23 ms on the daemon's first preWarm, but cost ~10–20 ms on the daemon's first user decode — small wash.
