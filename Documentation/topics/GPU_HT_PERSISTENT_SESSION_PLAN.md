# GPU HT decoder — persistent Metal session plan (v5.6.0)

**Branch:** `gpu-ht-persistent-session`
**Predecessor:** v5.5.0 (M2-prime production integration)
**Theme:** turn the M2-prime integration shape into an actual end-to-end perf win for warm-process decode.

## Why this is the right next milestone

v5.5.0 wired GPU HT decode into production behind `--gpu-ht`, but the [perf report](GPU_HT_M2_PRIME_PERF_REPORT.md) showed `j2k decode --gpu-ht` is 0.03×–0.49× the CPU path on every fixture. Two reasons identified there:

1. Per-process Metal init cost (~50–60 ms shader compile + device setup)
2. Other pipeline stages still on CPU

This release tackles **#1**. It does not yet address #2 (that's a future release).

The win is real: the M2P-3 corpus test (a single Swift process that decodes all 7 fixtures via the SDK) finishes in **0.79 s** total — versus the CLI which pays the 50–60 ms init *per decode* and shows the slowdown in the perf table. Caching the Metal infrastructure across calls in a long-running process amortises the init cost away, which is exactly the warm-process pattern most production usage follows (servers, batch tools, app sessions).

## Scope

### In scope

1. **`J2KMetalSession` type** — a Sendable wrapper bundling a shared `J2KMetalDevice`, `J2KMetalShaderLibrary`, and `J2KMetalBufferPool`. Long-lived; constructed once by the caller.
2. **`J2KDecoder.decodeWithGPUHT(_:session:)`** overload that accepts a session and reuses its Metal objects across calls.
3. **`J2KDecoderPipeline` plumbing** — pass the session through `applyEntropyDecoding` (for HT cleanup) and `applyInverseWaveletTransformGPU` (for inverse DWT) so both stages reuse the same device and shader library.
4. **`J2KGPUHTDispatch.decodeBatch`** signature accepts an optional session in addition to the existing optional `J2KMetalHTCleanup`.
5. **Perf measurement** — extend the existing perf script to cover the warm-process case (single SDK process decoding the corpus N times) alongside the existing cold-CLI numbers.
6. **v5.6.0 release notes** that lead with the warm-process speedup honestly.

### Out of scope (deferred)

- **Pre-compiled `.metallib` bundling.** Would eliminate the first-call shader compile (~50 ms) for cold-process callers. Requires Xcode build setup + multi-platform build artifacts. Bigger scope, separate release.
- **GPU dequantisation kernel.** Per-sample shift+sign conversion currently runs CPU-side. Promoting to GPU would unlock command-buffer fusion in a later release.
- **HT-cleanup → DWT command-buffer fusion.** Theoretical M2 from the original phase-3 plan. Becomes feasible after GPU dequant + persistent session both land.
- **CLI single-shot perf.** The CLI use case requires the first-call init cost to drop, which means `.metallib` bundling — explicitly not in this release.

## Integration map

The two production sites that construct fresh Metal objects per decode:

- [J2KGPUHTDispatch.swift:170](Sources/J2KCodec/J2KGPUHTDispatch.swift#L170) — `let cleanupKernel = cleanup ?? J2KMetalHTCleanup()`. Fresh `J2KMetalHTCleanup` creates fresh `J2KMetalDevice` and `J2KMetalShaderLibrary` if not provided.
- [J2KDecoderPipeline.swift:2425](Sources/J2KCodec/J2KDecoderPipeline.swift#L2425) — `let metalDWT = J2KMetalDWT(...)`. Same pattern.

Both can already accept pre-constructed Metal infrastructure via init parameters; they default to fresh ones when not supplied. The work is plumbing — wiring a shared session through `J2KDecoder.decodeWithGPUHT` → `DecoderPipeline.decodeGPU` → both call sites.

The shared `J2KMetalShaderLibrary` is the load-bearing optimisation: it caches the compiled MSL library and the compute pipelines (per [J2KMetalShaderLibrary.swift:191](Sources/J2KMetal/J2KMetalShaderLibrary.swift#L191)). Calling `loadShaders(device:)` on a fresh library compiles MSL source (~50 ms); calling it on a library that's already loaded is a no-op.

## Sequencing and milestones

| Milestone | Scope | Wall-clock |
|---|---|---|
| **M3P-1** | New `J2KMetalSession` type bundling device + shader library + buffer pool. Sendable, `init()` lazy-defaults, plus optional injectable accessors. | 1 day |
| **M3P-2** | `J2KDecoder.decodeWithGPUHT(_:session:)` overload; plumb session into `DecoderPipeline`; `J2KGPUHTDispatch.decodeBatch(blocks:cleanup:session:)` accepts session and threads through to `J2KMetalHTCleanup`. | 1–2 days |
| **M3P-3** | `applyInverseWaveletTransformGPU` accepts session; pass through to `J2KMetalDWT`. Same plumbing pattern. | 1 day |
| **M3P-4** | Extend `Scripts/measure_gpu_ht_perf.sh` to add a "warm SDK" benchmark mode that decodes the corpus N times in one process. Compare cold vs warm numbers. | 1 day |
| **M3P-5** | v5.6.0 release notes; commit perf report; merge + tag. | 1 day |

Total: ~5–6 days. Each milestone independently mergeable.

## Risks and unknowns

- **Sendable conformance** — `J2KMetalSession` needs to be safely shareable across `decodeWithGPUHT` calls that might run concurrently from different tasks. The underlying `J2KMetalDevice` and `J2KMetalShaderLibrary` are already actors, so the session is as Sendable as its contents.
- **Backward compatibility** — existing `decodeWithGPUHT(_:)` and `decodeWithGPUHT(_:progress:)` overloads must continue to work without a session, falling back to per-call construction (i.e. v5.5.0 behaviour).
- **First-call cost remains** — the `J2KMetalSession`'s first use still pays the ~50 ms shader compile. The win is on the SECOND through Nth decode. Release notes must be honest about this.
- **Buffer-pool state across calls** — `J2KMetalBufferPool` is already an actor with proper Sendable handling. Sharing should be safe; pool growth across many decodes might use more memory than the per-call pool, but the pool already has size/memory limits in its config.

## Verification gates

1. **Bit-exactness preserved** — all v5.5.0 tests continue to pass with default behaviour (no session injected). The new session-injected path produces byte-identical output to the no-session path.
2. **Warm-process speedup measurable** — the new perf script should show GPU HT going from 0.03×–0.49× (cold per-process) to ≥1.0× (warm SDK) on at least the larger fixtures.
3. **No regression in v5.5.0 CLI numbers** — the cold CLI path is unchanged in this release; numbers should match the v5.5.0 baseline within measurement noise.

## Out-of-scope-but-tracked follow-ups

- **`.metallib` bundling** for cold-CLI wins.
- **GPU dequantisation kernel.**
- **HT-cleanup → DWT cb fusion** (becomes feasible after GPU dequant lands).
- **Persistent session for `J2KEncoder`** — same problem on the encode side; same fix.
