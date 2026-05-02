# J2KSwift v5.6.0 — Persistent Metal session + GPU dequantisation

**Release date:** 2026-05-02
**Branch:** `gpu-ht-persistent-session` → `main`
**Companion:** continuation of v5.5.0; cross-codec verification + codestream output unchanged.

## What's in this release

Two performance levers for warm-process callers (long-running SDK processes that decode many images), both opt-in via the existing `decodeWithGPUHT` surface from v5.5.0:

1. **`J2KMetalSession`** — a Sendable bundle of a shared Metal device, shader library, and buffer pool. Construct once at the SDK boundary; pass to every decode call:

   ```swift
   let decoder = J2KDecoder()
   let session = J2KMetalSession()
   for data in batch {
       let img = try await decoder.decodeWithGPUHT(data, session: session)
   }
   ```

   First call still pays the ~50 ms shader compile; every subsequent call reuses the cached library + compute pipelines + buffer pool.

2. **GPU dequantisation kernel** — new MSL kernel `j2k_ht_dequant` that converts the HT cleanup kernel's UInt32 OpenJPH sign-magnitude output to the pipeline's Int32 integer-magnitude convention on the GPU side. When a session is supplied, the dispatcher chains the cleanup and dequant kernels in a single command buffer and skips the CPU-side per-sample shift+sign loop that used to run after readback.

The two are independent but they compose. Session alone gets a modest ~1.07× median warm-process speedup. Session + GPU dequant together gets **~1.26× median**. Most of the v5.6.0 win comes from the two combined; the dequant kernel is roughly half of the speedup.

## Measured impact

Apple M2, release builds, single Swift process decoding the 7 DICOM fixtures via the SDK with the same session reused across calls. First decode per backend dropped (warmup); median of 4 timed runs reported.

| fixture | size | sessionless (ms) | session (ms) | speedup |
| --- | ---:| ---:| ---:| ---:|
| ct_001 | 512×512 | 16.68 | 12.37 | **1.35×** |
| ct_003 | 512×512 | 14.45 | 11.91 | 1.21× |
| dx_002 | 2800×2288 | 111.49 | 82.40 | **1.35×** |
| mr_001 | 886×886 | 18.65 | 16.02 | 1.16× |
| mr_002 | 180×180 | 6.35 | 5.49 | 1.16× |
| px_001 | 2459×1316 | 60.63 | 48.19 | 1.26× |
| xa_001 | 1024×1024 | 24.64 | 19.33 | 1.27× |

Median: **1.26×**. Range: 1.16×–1.35×. Largest absolute saving is on the 2800×2288 fixture (29 ms). On a single-fixture isolated benchmark, the speedup is **1.88×** (24.17 → 12.85 ms).

## What this release does not change

**Cold CLI numbers from v5.5.0 are unchanged.** `j2k decode --gpu-ht` still pays the per-process Metal init cost on every invocation, and is still slower than the default CPU path on the small/medium DICOM fixtures (0.03×–0.49× per the v5.5.0 perf report). Fixing that requires a pre-compiled `default.metallib` bundled in `Bundle.module` so the SDK can skip MSL source compilation. v5.6.0 wires that path in (`Sources/J2KMetal/J2KShaders.metal` is registered as a SwiftPM resource; `loadShaders` prefers `device.makeDefaultLibrary(bundle:.module)`), but the binary artefact is not included — Apple's Metal toolchain wasn't installed in the build environment used to ship this release. Whoever runs `xcodebuild -downloadComponent MetalToolchain` and produces a `default.metallib` will pick up the cold-CLI win automatically; no code change required.

The default decode path (no `--gpu-ht`, no session) is byte-identical to v5.5.0. End users who don't opt in see no behavioural change.

## Bit-exactness

Every existing gate continues to pass:

- **`J2KMetalSessionTests`** (4 tests, all release-mode pass): bit-exact gate (session output ≡ sessionless output), warm-process speedup gate (asserts session ≥ 1× sessionless), corpus-wide perf measurement, session construction smoke.
- **`J2KGPUHTDispatchTests`** (3 tests): bit-exact mixed batch, empty fallback, all-empty fallback.
- **`J2KGPUHTPipelineTests`** (4 tests): bit-exact at 384×384 + 512×512, Part 1 flag-inert check, full DICOM corpus byte-equality.
- **`Scripts/run_cross_matrix.sh --check`** (147/147 cells): unaffected, as the cross-codec matrix exercises the default CPU decode path.

## Added

- **`Sources/J2KCodec/J2KMetalSession.swift`** — public `J2KMetalSession` struct, Sendable, default-init lazy.
- **`J2KDecoder.decodeWithGPUHT(_:session:)`** + progress-callback overload.
- **`Sources/J2KMetal/J2KMetalHTCleanup.swift`** — `runIntegerMagnitude(...)` returning `[Int32]`, chains cleanup + dequant in one command buffer.
- **`j2k_ht_dequant` MSL kernel** added to both inlined `J2KMetalShaderSource.kernelSource` and the standalone `J2KShaders.metal` resource.
- **`Sources/J2KMetal/J2KShaders.metal`** — extracted from inlined string, registered as a SwiftPM `.process()` resource. Dormant in pure-SwiftPM builds (no metal toolchain integration); ready to be picked up if a `default.metallib` lands in `Bundle.module`.
- **`Tests/J2KCodecTests/J2KMetalSessionTests.swift`** — four new tests.
- **`GPU_HT_PERSISTENT_SESSION_PLAN.md`** — five-milestone plan (M3P-1..5, all complete in this release).

## Changed

- **`Sources/J2KMetal/J2KMetalShaderLibrary.swift`** — `loadShaders` prefers bundled metallib when available, falls back to source compilation. New `htDequant` shader function enum case.
- **`Sources/J2KCodec/J2KGPUHTDispatch.swift`** — `decodeBatch(blocks:cleanup:session:)` accepts an optional session. Dispatches via `runIntegerMagnitude` (chained GPU dequant) when session or cleanup is supplied; sessionless path unchanged.
- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** — `metalSession: J2KMetalSession?` field on `DecoderPipeline`. Threads through to both the GPU HT batch and the GPU inverse DWT path.
- **`Package.swift`** — `J2KMetal` target adds `resources: [.process("J2KShaders.metal")]`.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns "5.6.0".
- `VERSION` bumped 5.5.0 → 5.6.0.

## Out-of-scope-but-tracked follow-ups

- **`default.metallib` bundling** — the artefact, not the wiring. Would convert the v5.5.0 cold-CLI numbers from 0.03×–0.49× toward parity. Requires the Metal toolchain in the build environment.
- **HT-cleanup → DWT command-buffer fusion** — both stages already use Metal; the missing piece is keeping the intermediate Int32 buffer GPU-resident across the boundary. v5.6.0's `runIntegerMagnitude` returning Int32 is the foundation; v5.7 candidate.
- **Persistent session for `J2KEncoder`** — same per-process Metal init cost on the encode side; same fix.
- **GPU subband regrouping** — would let the entire HT-decoded tile flow GPU-side into the inverse DWT without per-block CPU readback.

## Source

- Branch: `gpu-ht-persistent-session` (one commit ahead of v5.5.0)
- Plan: [GPU_HT_PERSISTENT_SESSION_PLAN.md](GPU_HT_PERSISTENT_SESSION_PLAN.md)
- v5.5.0 release notes: [RELEASE_NOTES_v5.5.0.md](RELEASE_NOTES_v5.5.0.md)
- v5.5.0 perf report: [GPU_HT_M2_PRIME_PERF_REPORT.md](GPU_HT_M2_PRIME_PERF_REPORT.md)
