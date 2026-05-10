# Changelog

All notable changes to J2KSwift are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [8.1.3] — 2026-05-10

**`j2kd` daemon: opt-in default + smart-routing + encoder support; mmap'd CLI input**

Four customer-facing CLI improvements derived from the v8.8 research arc (PR #410). The v8.1.0 default of "daemon if installed" was tuned for cold-shot DX measurements (72 → 55 ms with daemon). v8.8 corpus verification measured a **−20.98 ms regression across the 6-fixture medical corpus** on warm-cache CLI loops because NSXPCInterface proxy overhead is 5–7 ms per call — a large fraction of small/medium fixtures' decode time. The daemon's only meaningful benefit is the FIRST cold-shot per session.

v8.1.3 makes `j2kd` opt-in for decode via `--daemon`, adds `--daemon auto` smart-routing (3 MB codestream threshold), introduces encoder daemon support (`j2k encode --daemon` saves **−40.2% on encode wall corpus-wide**), and uses mmap for CLI codestream input. Codestream bytes byte-identical to v8.1.2.

### Added

- **Encoder daemon support** (`j2k encode --daemon` / `--daemon auto`): new `J2KDaemonProtocol.encode(...)` method + daemon-side implementation + CLI routing. Symmetric to decoder daemon, but with effectively-zero pixel threshold (encoder is library-load-dominated, daemon wins on every fixture). Corpus encode wall: 571.65 ms in-proc → 341.71 ms via daemon = **−40.2% (−229.93 ms across 6 fixtures)**. Bit-identical output verified by MD5-match.
- **`j2k decode --daemon auto`** smart-routing: 3 MB codestream-size threshold derived from daemon-overhead-vs-decode-time inflection point. Routes via daemon ONLY when decode time amortises NSXPC proxy overhead. Cross-corpus verified: routes correctly on all 6 medical fixtures, beats both `--daemon` (always-on) and `--no-daemon` aggregate wall.
- **mmap'd codestream input** (`Data(contentsOf:options: [.alwaysMapped])`): defers page-in to where the decoder reads, saving ~3 ms on cold-shot DX decode (12 MB codestream). Saves ~5 ms corpus-wide.
- `J2KDaemonClient.encode(pixelData:width:height:bitDepth:signed:)` async wrapper.
- `J2KD_DECODE_TRACE=1` and `J2K_PREWARM_TRACE=1` env-gated stage instrumentation in the daemon for future investigators.

### Changed

- **`j2k decode` default**: in-process (no NSXPCConnection round-trip). Post-flip default = pre-flip `--no-daemon` behavior, byte-identical output.
- **`j2k decode --daemon`** (new flag): opt-in, routes via the j2kd XPC daemon when reachable. Falls back to in-process if not.
- **`j2k decode --no-daemon`** (legacy): preserved as no-op alias. Scripts using this flag continue to work bit-identically.
- `Sources/J2KCore/J2KCore.swift` — `getVersion()` returns `"8.1.3"`.
- `Sources/J2KCLI/Commands.swift` — toggles daemon-routing branch from `if !noDaemon` to `if useDaemon`; adds `--daemon auto` smart-routing for both decode and encode; adds mmap input.
- `Sources/J2KCLI/main.swift` — DECODE OPTIONS + ENCODE OPTIONS help updated with `--daemon` / `--daemon auto` / `--no-daemon` text + tradeoff guidance.
- `Sources/J2KDaemonProtocol/J2KDaemonProtocol.swift` — adds `encode(...)` method.
- `Sources/J2KDaemonCore/J2KDaemonService.swift` — adds `encode(...)` implementation.
- `Sources/J2KDaemonClient/J2KDaemonClient.swift` — adds `encode(...)` async wrapper.
- `Documentation/BENCHMARK.md` — daemon-installed section updated to describe opt-in behavior + smart-routing + warm-cache regression context.

### Backward compatibility

- Codestream bytes byte-identical to v8.1.2.
- All cross-codec parity tests preserved (12/12 cells × 3 decoders = 36/36 bit-exact, plus 3/3 strict tests).
- Public Swift API (`J2KDaemonClient.decode(_:)`) unchanged.
- Scripts using `--no-daemon` continue to work (it's a no-op in v8.1.3).
- Scripts that depended on the v8.1.x daemon-by-default behaviour need to add `--daemon` explicitly.

### SemVer rule

PATCH — bug fix (the v8.1.x daemon-on default was a tuning regression for the warm-cache CLI use case); no public API removed; no codestream byte change.

### Research provenance

Productisation of the v8.8 research arc, kept open as **PR #410** (`v8.8-gcd-vs-taskgroup-phase0` branch, NOT for merge). Research artefacts include 12 lever-ceiling investigations (mmap probes, GCD vs TaskGroup, Accelerate framework sweep, AMX feasibility, IOSurface / mach_vm_remap / xpc_shmem alternatives, MTLBinaryArchive probe, daemon overhead decomposition, fixture-size scaling, cross-codec verification) plus the four production wins shipped here.

## [8.1.2] — 2026-05-10

**Lever-ceiling investigation suite — three projected-wash phase-0 reports (v8.5 + v8.6 + v8.7) close every remaining pure-perf branch on M2.**

Pure investigation-only release. **No source-code changes** beyond the version bump. The deliverable is the empirical data that closes the v8.4 recommendation tree's remaining items: HT entropy consumer body redesign, encoder optimisation arc, and encoder algorithmic redesign. All three returned WASH against the v7.4 ≥3 ms DX wall acceptance threshold. Combined with the five prior decoder-side investigations (v6-alpha4, v7.4, v7.5, v8.1, v8.4), **eight independent investigations** now confirm the J2KSwift codec hot-path on Apple M2 + Swift release + macOS is at structural lever ceiling for both encode and decode.

### Added

- `Tests/J2KCodecTests/V8_5_HTConsumerBodyPhase0Bench.swift` — parity check + per-quad cost microbench for the HT entropy consumer body 4-sequential-reads vs 1-batched-read pattern. Returns 4-reads = 14.27 ns/quad, batched = 6.04 ns/quad, projecting 1.32 ms wall savings on DX (below 3 ms threshold).
- `Tests/J2KCodecTests/V8_6_ForwardDWTPhase0Bench.swift` — per-sample cost microbench for the production `forward53_1D` lifting kernel. Reports 0.37 ns/sample at n=2048, confirming the kernel runs at memory-bandwidth-bound L1 throughput.
- `Tests/J2KCodecTests/V8_7_ForwardDWTStageDecomposition.swift` — `forward2D_53Pooled` end-to-end + strip-transpose isolation bench. Decomposes the 25 ms DX 5-level DWT wall into its sub-stages.
- `V8_5_HT_CONSUMER_BODY_FINDING.md`, `V8_6_FORWARD_DWT_FINDING.md`, `V8_7_ENCODER_REDESIGN_FINDING.md` — close-out documents for each investigation, including projected DX wall-savings tables and reopen criteria.

### Changed

- `getVersion()` returns `"8.1.2"`.

### Backward compatibility

- **Codestream bytes byte-identical to v8.1.1.** No production code changes; no public API additions.

### SemVer rule

PATCH — pure investigation deliverable; no production code changes; no public API change; no codestream byte change.

## [8.1.1] — 2026-05-10

**CI Node 24 opt-in — pre-empts the 2026-09-16 Node 20 removal**

Pure operational-hygiene release. No source-code changes beyond the version bump. Every workflow under `.github/workflows/` that uses Node-20-based actions now opts into Node 24 for JavaScript-based actions via the workflow-level env `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"`. This is GitHub's own recommended migration path; eliminates the deprecation warnings that started appearing 2025-09-19.

### Changed

- `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `.github/workflows/conformance.yml`, `.github/workflows/code-quality.yml`, `.github/workflows/documentation.yml`, `.github/workflows/dicomkit-downstream.yml`, `.github/workflows/interactive-testing.yml`, `.github/workflows/jp3d-compliance.yml`, `.github/workflows/performance.yml`, `.github/workflows/create-release-branches.yml` — all gain workflow-level `env: FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"`.
- `getVersion()` returns `"8.1.1"`.

### Backward compatibility

- Codestream bytes byte-identical to v8.1.0.
- Action pin versions unchanged (`actions/checkout@v4`, `softprops/action-gh-release@v2`); only the Node runtime they execute under switches.

### SemVer rule

PATCH — pure CI hygiene; no public API change.

## [8.1.0] — 2026-05-10

**`j2kd` XPC daemon adoption push — three new CLI subcommands turn the manual 5-step install into one command**

Pure deployment-side work. Codestream bytes byte-identical to v8.0.1; no decoder change. The v8.4 lever-ceiling investigation (PR #402) confirmed the M2 + Swift release decoder hot path has no extractable single-codec wins remaining; this release pursues the highest-leverage move available — making the already-shipped `j2kd` daemon trivial to install.

End-to-end CLI gap on DX 2800×2288 closes from 72 ms cold-shot → ~55 ms with daemon installed (–24 % wall) — the v8.0.0 phase 6 daemon work, now one command instead of five shell invocations.

### Added

- **`j2k daemon-install`** — locates `j2kd` (sibling of running `j2k` binary, then `.build/release/j2kd` in CWD; `--daemon-binary <path>` overrides), copies to `~/Library/Application Support/J2KSwift/j2kd`, writes the plist to `~/Library/LaunchAgents/com.raster.j2kd.plist`, runs `launchctl bootstrap` (modern; falls back to `launchctl load`), verifies install via real XPC ping. Per-user layout — no sudo. `--force` flag overwrites an existing install.
- **`j2k daemon-uninstall`** — `launchctl bootout` (with legacy `unload` fallback), removes plist, removes binary. `--keep-binary` preserves binary for re-install.
- **`j2k daemon-status`** — reports binary/plist presence, launchd service load state (`launchctl print`), and Mach service reachability via real XPC ping (the v8.0.0 `J2KDaemonClient.isAvailable` is optimistic; this command does the actual round-trip). Human-readable default; `--json` for scripting.
- `Sources/J2KCLI/DaemonInstall.swift` — implementation of the three subcommands. macOS-only via `#if os(macOS)`.
- `RELEASE_NOTES_v8.1.0.md`.

### Changed

- `Sources/J2KCLI/main.swift` — usage text now lists `daemon-install / daemon-uninstall / daemon-status / daemon-ping`. Dispatch added for the three new subcommands; iOS builds stub them to a "macOS-only" message.
- `README.md` — `j2kd` install section replaces the manual 5-step shell flow with the one-command path.
- `getVersion()` returns `"8.1.0"`.

### Backward compatibility

- **Codestream bytes byte-identical to v8.0.1** — no encoder/decoder change.
- Public API additions only; no removals or signature changes.
- The v8.0.0 manual install path still works; the new install command targets a different layout (`~/Library/Application Support/J2KSwift/` instead of `/usr/local/bin/`) so the two installs don't collide.

### SemVer rule

**MINOR** per RELEASING.md — new public CLI surface, no removals, no signature changes, codestream bytes unchanged.

### iOS / iPadOS

`j2kd` is macOS-only. iOS apps use `J2KDecoder.preWarm()` (shipped in v8.0.0 Phase 6.1) for the same warm-process effect. All three new subcommands are `#if os(macOS)`-gated; iOS builds compile clean.

### Test Suite Results (release mode, 0 failures)

- `J2KMedicalCorpusEncodePerformanceTests` — 2/2 (29.971 s)
- `J2KMedicalCorpusPerformanceTests` — 2/2 (9.784 s)
- `J2KStrictCrossCodecValidationTests` — 3/3 (0.481 s)

Plus end-to-end install / status / ping / uninstall round-trip verified on Apple M2 / macOS 26.x.

## [8.0.1] — 2026-05-10

**Silent-corruption hotfix + GPU multi-tile-per-tile 5/3 IDWT root cause**

Fixes the v7.5.1 mg silent-corruption (cross-tile batched HT entropy decode) AND root-causes / fixes the underlying GPU multi-tile-per-tile 5/3 IDWT defect that produced the corruption. `_multiTileBatchedEntropyEnabled` is back default-on; the v7.2.0 cross-tile entropy CB amortisation is restored.

Codestream bytes byte-identical to v8.0.0; no public API removals or signature changes.

### Fixed

- **mg silent-corruption (v8.2 / PR #399)** — `decodeMultiTileGPUBatched` (PR #356, v7.2.0) silently corrupted decode output on certain multi-tile codestreams; surfaced 2026-05-09 by an external 4-codec eval matrix on 16+ MP mammography DICOM fixtures. Root cause was NOT in the entropy decode — it was IDWT routing: when the entropy stage's pre-batched short-circuit returned `gpuBatch=nil`, `applyInverseWaveletTransformGPU` skipped its CPU-fallback branch and ran the buggy GPU multi-tile-per-tile IDWT. Fix: force CPU IDWT in `decodeTilePayloadGPU` when `preBatchedGPUCoefficients` is set, mirroring the per-tile path's effective behaviour.

- **GPU multi-tile-per-tile 5/3 IDWT — two distinct correctness bugs (v8.3 / PR #400)**:
  - **Bug #1**: `applyInverseWaveletTransformGPU` used naive `(pw + 1) / 2` ceil-div recursion for per-level subband dimensions, disagreeing with the encoder's canvas-anchored ISO/IEC 15444-1 Eq. B-15 partition at non-zero canvas X origin. Example: tile (0, 1) at depth 5 — naive gives 28, spec gives 27. Wholesale corruption (1.05 M of 1.05 M pixels in the failing tile). Fixed by switching to the spec formula.
  - **Bug #2**: `encodeInverse2DInt32` + `inverse2DInt32MultiLevelFused` computed the LH/HH band row count as `originalHeight / 2`. For ODD canvas V origin: LL = `floor(H/2)`, LH/HH = `ceil(H/2)`. `H/2 = floor(H/2)` undercount → Pass 1 only processed `H/2` rows of LH/HH, leaving the last row of `colHigh` uninitialised; Pass 2 read all `ceil(H/2)` rows, picking up garbage. Fixed by `halfHH = originalHeight − llHeight`.

  Per-tile mismatch progression on the smallest reproducer (1760×2392 split 2x2):

  | tile | tcx0, tcy0 | pre-v8.3 | after Fix #1 | after Fix #1+#2 |
  |---|---|---:|---:|---:|
  | (0, 0) | 0, 0 | 0 | 0 | **0** |
  | (0, 1) | 880, 0 | 1,048,207 | 0 | **0** |
  | (1, 0) | 0, 1196 | 48,128 | 47,175 | **0** |
  | (1, 1) | 880, 1196 | 1,049,385 | 47,357 | **0** |

### Changed

- **`_multiTileBatchedEntropyEnabled` default flipped `false` → `true`** — restores v7.2.0 phase-e cross-tile entropy CB amortisation. Decode output is bit-exact to v8.0.0's per-tile path; only the internal routing changes.
- **`getVersion()` returns `"8.0.1"`**.

### Added

- `nonisolated(unsafe) public static var DecoderPipeline._v82_disableIDWTRoutingFix: Bool = false` — test-only diagnostic toggle. Must stay `false` in production.
- `Tests/J2KCodecTests/V8_2_MgBatchedDiagnostic.swift` — 10-dimension sweep verifying the v8.2 routing fix.
- `Tests/J2KCodecTests/V8_3_GPUIDWTRootCauseDiagnostic.swift` — GPU IDWT bit-exact verification (3 tests via the routing-fix bypass toggle).
- `V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md` — v8.2 routing fix root cause.
- `V8_3_0_GPU_IDWT_ROOT_CAUSE.md` — v8.3 two-bug root cause + per-tile localisation.

### Backward compatibility

- **Codestream bytes byte-identical to v8.0.0**.
- Public API additions only; no removals or signature changes.
- The `_multiTileBatchedEntropyEnabled` default flip restores pre-v7.5.1 behaviour for the internal routing — both old and new defaults produce bit-exact decode output, the new default is just faster on multi-tile fixtures.

### SemVer rule

**PATCH** — codestream bytes unchanged, no public API breakage, new test-only diagnostic toggle plus pure-bug-fix changes.

### Test Suite Results (release mode, 0 failures)

- `J2KMedicalCorpusEncodePerformanceTests` — 2/2 (29.910 s)
- `J2KMedicalCorpusPerformanceTests` — 2/2 (9.672 s)
- `J2KStrictCrossCodecValidationTests` — 3/3 (0.460 s)
- `MgRegressionTriageTest` (assertion flipped — must PASS bit-exact at 16+ MP) — 2/2
- `V8_2_MgBatchedDiagnostic` (10 cases) — 1/1
- `V8_3_GPUIDWTRootCauseDiagnostic` (3 tests, GPU IDWT bypassing v8.2 fix) — 3/3

## [8.0.0] — 2026-05-10

**Apple Silicon-first major release — Metal-first architecture, warm in-process beats Kakadu on 4/6 medical fixtures, optional `j2kd` XPC daemon for warm-CLI**

A major-version product pivot. v7.x targeted cross-platform performance and got within 25 % of OpenJPH and 2× of Kakadu globally. v8.0.0 narrows the product to **Apple Silicon (M-series macOS + A-series iOS/iPadOS)** and uses platform-native primitives (Metal, NSXPCConnection, launchd) to beat Kakadu on the dominant Apple workloads — small/medium medical images, warm-process apps, and (with the optional XPC daemon) single-shot CLI users.

**Headline measurement (warm in-process decode, Apple M2)**: J2KSwift in-process CPU is **26× / 5× / 3× / 2.3×** faster than Kakadu CLI on MR-small / CT / MR 886² / XA respectively. PX and DX (the two largest fixtures) remain 1.23× / 1.51× behind. SDK consumers get this performance via the new `J2KDecoder.preWarm()` API.

**CLI cold-shot progression** (DX 2800×2288): pre-v8 134 ms → v8 Phase 1 91 ms → Phase 2 103 ms → Phase 3 91 ms → **Phase 4 89 ms (2.47× Kakadu gap)**. With the optional `j2kd` XPC daemon installed, the CLI gap closes further to **~1.5×** by amortising Metal cold-start across invocations.

### Added

- **`J2KDecoder.preWarm(includeWarmupDispatch: Bool = false)`** — public discoverable warm-session API. Once-per-app-startup; subsequent decodes use the warm session automatically. Cross-platform (macOS + iOS).
- **`Sources/J2KDaemonProtocol/`** — `@objc J2KDaemonProtocol` (XPC RPC surface: `ping` + `decode`). Mach service name constant `com.raster.j2kd`.
- **`Sources/J2KDaemonCore/`** — `J2KDaemonService` (NSXPCListenerDelegate-compatible), `J2KDaemonListenerDelegate`, `J2KDaemonActivityTracker`, `J2KDaemonLifecycle` (idle-timeout + signal handlers).
- **`Sources/J2KDaemonClient/`** — `J2KDaemonClient` actor wrapping NSXPCConnection. Used by the CLI to route decode through the daemon when reachable.
- **`Sources/J2KDaemon/`** — `j2kd` daemon executable. Runs under launchd as a per-user LaunchAgent (Mach service `com.raster.j2kd`).
- **`Resources/launchd/com.raster.j2kd.plist`** — launchd plist template for installing `j2kd`.
- **`j2k daemon-ping`** subcommand — verifies daemon install + measures round-trip ms.
- **`j2k decode --no-daemon`** flag — explicit in-process opt-out (useful for benchmark scripts).
- **`Tests/J2KDaemonTests`, `Tests/J2KDaemonClientTests`** — XPC protocol round-trip + lifecycle + client API tests (9 tests across 3 files).
- **`Tests/J2KCodecTests/V8Phase61WarmDecoderAPITests.swift`** — cross-platform warm-decoder API contract tests (3 tests; pass on macOS AND iOS Simulator).
- **`RELEASE_NOTES_v8.0.0.md`** + 14 phase-finding docs (`V8_0_0_PHASE_0_BASELINE.md` through `V8_0_0_PHASE_6_6_FINDING.md` + `V8_0_0_METAL_FIRST_STRATEGY.md`).

### Changed (production defaults)

- **CLI default routing flipped to CPU-first** (Phase 2). Default `j2k decode` no longer pays Metal cold-start tax for image sizes where GPU wouldn't win in single-shot mode. Saves 52-53 ms on default-mode CT/MR/DX invocations. Users who explicitly pass `--gpu` or `--gpu-ht` are unaffected.
- **`SIMD4<Int32>` CPU 5/3 INT IDWT path** (Phase 3). Bit-exact with the scalar reference; -16 % iDWT accumulated cost on DX, -12 ms wall.
- **NEON reconstruction default ON** (Phase 4). `HTBlockDecoderConformant.neonReconstructionEnabled = true`. Re-evaluation of v7.4 Phase 1 (rejected at Δ 0.90 ms) on the Phase 3 baseline shows median 2.96 ms across 10 samples — flipped to default ON under the Apple-only narrowing.
- **Cold-start elimination** (Phase 1). `J2KMetalDevice.isAvailable` now caches its result; `DecoderPipeline.decode`'s gate condition reorders the cheap pixel-threshold check ahead of the Metal-availability check. Saves 40-47 ms on every CLI invocation that doesn't need GPU.
- **`j2k batch decode`** now calls `preWarm()` before parallel dispatch (Phase 6.0), pulling Metal cold-start out of the first-file critical path. Cold-system 1st run drops from 889 ms to 193 ms (4.6× WIN over per-file CLI sum).
- **`Package.swift` iOS minimum bumped 17 → 18** (Phase 6.1) — required for `OSAllocatedUnfairLock.withLock`. The only material API breakage in v8.
- **`getVersion()` returns `"8.0.0"`**.

### Fixed

- **CLI `--no-gpu` flag now actually honoured** on the standard `decode` path (was silently ignored pre-v8). Behaves identically to the new `--no-daemon` flag in semantics: explicit opt-out from a routing path.

### Backward compatibility

- **Codestream bytes byte-identical to v7.5.1** — all v8 changes are decoder-side or CLI-routing.
- **Public API additions only** — no removals or signature changes.
- **iOS minimum bumped 17 → 18** — the only material break.
- **CLI default routing changed** — see "Changed" above. Users with explicit `--gpu` / `--gpu-ht` flags are unaffected.

### SemVer rule

**MAJOR** (per RELEASING.md): default behaviour flipped (CLI default routing CPU-first) + iOS minimum bumped. Codestream bytes are unchanged from v7.5.1.

### Known limitations

- **PX (2459×1316) and DX (2800×2288) warm in-process decode** still trail Kakadu CLI by 1.23× / 1.51× respectively. The HTJ2K entropy decode hot-path on M2 is at the lever-ceiling per v7.4/v7.5 measurements; closing this gap further requires algorithmic redesign (bit-parallel prefix-scan SIMD on chained-unstuff state) or different hardware (M3/M4/A-series ratification).
- **Daemon decode RPC ships single-component support only** (Phase 6.5). Multi-component (RGB) daemon RPC is deferred to Phase 6.5b. Single-component covers the medical-archive hot path (CT/MR/MG/PX/DX/XA are all monochrome).
- **Daemon `xpc_shmem` path not yet wired** — XPC's auto out-of-line marshalling handles every fixture in the medical corpus today. Will revisit when image sizes routinely exceed 16 MB raw.
- **`HTGPUForward53CrossCodecTests` warning**: GPU forward HT entropy is correctness-shipped but slower than CPU on Apple M2 (per v7.5.0 measurement). The flag remains default OFF.

### Test Suite Results (release mode, 0 failures)

- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1 (12 cells × 3 decoders = 33/33 cross-codec bit-exact)
- `MgRegressionTriageTest` — 2/2 (16+ MP HTJ2K bit-exact)
- `V8Phase61WarmDecoderAPITests` — 3/3 (cross-platform warm-decoder API; runs on macOS AND iOS)
- `J2KDaemonProtocolRoundTripTests` — 3/3
- `J2KDaemonClientTests` — 3/3
- `J2KDaemonLifecycleTests` — 3/3

iOS Simulator (iPhone 17 Pro, iOS 26.x) — `V8Phase61WarmDecoderAPITests` 3/3.

## [7.5.0] — 2026-05-09

**Perf-wash release — forward HT GPU entropy workstream closure with measurements**

Closes the v7.1.0 release notes' "perf optimisation is v7.2.x" promise. v7.2 → v7.4 went elsewhere; v7.5 finally measures the forward HT GPU entropy A/B and concludes honestly: **the path is slower than CPU on every corpus fixture**, including DX 2800×2288 (the production target) where the regression is **−22.4 ms (−44.6 %)**. Per-block GPU cost on Apple M2 is ~6.7× CPU per-block — even infinite cross-tile batching wouldn't close the gap.

The classifier + cleanup-pass emit work is structurally CPU-friendly on M2: chained per-sample state, cache-resident 4 KB codeblock data, vector-strong CPU. v7.3.0's HT decoder hot-loop wedge elimination already showed how aggressively the CPU side has been tuned (62.5 → 54.3 ms on DX decode in one release); the forward path benefits from the same CPU-side optimisations, leaving the GPU side without a structural win to capture on M2.

**Empirical data is the deliverable.** Per RELEASING.md §3, perf-wash releases are explicitly acceptable when no actionable lever exists and the measurement closes a previously-deferred promise. The flag stays default OFF; correctness is unchanged.

### Added

- `Tests/J2KMetalTests/V750ForwardHTGPUEntropyPhase0Bench.swift` —
  forward HT GPU entropy A/B benchmark with telemetry breakdown
  (median of 5, all 6 corpus fixtures, dispatch + emit + other ms
  per fire). Acts as a regression-detection probe — anyone who
  attempts to flip `_gpuForwardHTEntropyEnabled = true` by default
  on M2 will see this benchmark's negative Δ values immediately.
- `V7_5_0_PHASE_0_FINDING.md` — per-block cost analysis,
  recommendation to close the workstream out, reproduction
  commands.
- `RELEASE_NOTES_v7.5.0.md`.

### Changed

None in production code. `getVersion()` returns `"7.5.0"`.

### Backward compatibility

Codestream bytes byte-identical to v7.4.0 (no production code
changes). No public API additions or removals. SemVer rule:
**MINOR** (release artefacts + new test file).

### Known limitations

- The forward HT GPU entropy path remains correctness-shipped
  but measurably slower than CPU on Apple M2 across the full
  production corpus. The flag is preserved in case future
  hardware (M3/M4/M5 or non-Apple GPUs) inverts the per-block
  cost curve.
- The Kakadu gap on DX in-process decode (~2.10× post-v7.4)
  is structural per the v7.4 Phase 3 finding; closing it
  further requires algorithmic redesign (bit-parallel
  prefix-scan SIMD on chained-unstuff state) or different
  hardware. Not in v7.5 scope.

## [7.4.0] — 2026-05-09

**Staged NEON release — SWAR-batched MagSgn refill default ON; reconstruction & VLC SWAR rejected with measurements**

Three PRs (#369, #370, #371) deliver the v7.4 staged-NEON arc on
Apple Silicon. The acceptance discipline was strict: each phase
runs an end-to-end DX 2800×2288 in-process A/B and ships
default-ON only on a measured ≥ 3 ms wall-time improvement.
Only Phase 2 cleared that bar.

### Changed

- `HTMagSgnDecoderConformant.refill` (#370, **production default**)
  is now SWAR-batched — 4-byte unaligned `UInt32` loads with a
  per-batch `0xFF`-detect via SWAR
  `(p32 ^ 0xFFFFFFFF) followed by (inv − 0x01010101) & ~inv & 0x80808080`.
  Fast path (no `0xFF` in batch and no carried unstuff) folds 4
  bytes into the bit accumulator at once; slow fallback is
  byte-by-byte scalar (bit-exact-by-construction). At the
  corpus-typical 0xFF density of ~0.4 %, ~99 % of batches hit
  the fast path. Microbench shows 1.05× → 1.49× speedup at
  3-32 bit reads (1.15× at the DX corpus average of 14 bits per
  read). End-to-end DX 2800×2288 in-process decode improves by
  ~3 ms vs scalar on a settled system. Bit-exact across 11
  parity sweeps including all-zero, all-FF, alternating, FF
  position-by-position, 32 random seeds, padding-exhaust, and
  edge sizes.

### Added

- `HTMagSgnDecoderConformant.neonRefillEnabled: Bool = true`
  (#370) — public flag to opt out of the batched refill if a
  consumer hits an unexpected platform regression.
- `HTBlockDecoderConformant.neonReconstructionEnabled: Bool = false`
  (#369) — public flag for the experimental SIMD4
  `readQuadSamples` reconstruction path. **Default OFF** because
  the measured DX in-process A/B Δ was 0.90 ms — below the 3 ms
  acceptance threshold. Kept behind the flag so future work can
  re-measure if the stage cost share shifts.
- `VLCReverseReaderTesting.batchedRefillEnabled: Bool = false`
  (#371) — public flag for the experimental SWAR-batched VLC
  reverse-reader refill. **Default OFF** because the DX in-process
  A/B Δ was −0.6 to +2.5 ms across 3 runs (run-to-run noise
  dominates). Root cause: VLC's stuff-trigger predicate
  ("byte > 0x8F") covers 7/16 of the value space, so the
  4-byte SWAR fast path fires only ~10 % of the time on uniform
  random data — vs MagSgn's "byte = 0xFF" predicate firing ~99 %.
- `Tests/J2KCodecTests/V740NeonReconstructionParityTests.swift` —
  5 sweeps × {rho=0, rho>0, mixed sign/mag, edge bit-depths,
  bottom-row interaction}, bit-exact pass.
- `Tests/J2KCodecTests/V740NeonRefillParityTests.swift` —
  11 sweeps × {all-zero, all-FF, alternating, FF position-in-batch,
  random seeds, stream-exhaust padding, empty/tiny streams}, all pass.
- `Tests/J2KCodecTests/V740NeonVlcRefillParityTests.swift` —
  5 sweeps × {bit-depths, densities, block sizes, 64 random seeds,
  6-fixture corpus end-to-end}, all bit-exact.
- Microbench + DX wall A/B benches for each phase
  (`V740NeonReconstruction*`, `V740NeonRefill*`, `V740NeonVlcRefill*`).
- Release artefacts: `V7_4_0_PHASE_1_FINDING.md`,
  `V7_4_0_PHASE_2_FINDING.md`, `V7_4_0_PHASE_3_FINDING.md`,
  `RELEASE_NOTES_v7.4.0.md`.

### Backward compatibility

Codestream bytes byte-identical to v7.3.0 across the medical
corpus (decoder-only changes). No public API breakage. SemVer
rule: **MINOR**.

`getVersion()` returns `"7.4.0"`.

### Known limitations

- Kakadu gap on DX in-process decode tightens marginally
  (2.17× → ~2.10×). Closing the rest needs algorithmic work
  beyond simple SWAR — possibly bit-parallel prefix scans for
  the chained-unstuff state, or moving entire blocks to GPU
  HT decode (separate workstream).
- The two NEON paths kept behind flags (reconstruction, VLC
  refill) ship for measurement parity only — operators with
  no need for honest A/B tooling can ignore them.

## [7.3.0] — 2026-05-09

**HT entropy decoder hot-loop wedge elimination — DX in-process decode 62.5 → 54.3 ms (-13 % vs v7.2.0)**

Eight PRs (#359-#367) land bit-exact entropy-decoder optimisations
that close ~60 % of the Kakadu gap on DX vs v7.1.0 (5.23× → 2.17×).
The pattern that paid off: eliminate "compute-then-discard" wasted
work before reaching for SIMD — three of the four biggest wins
(bottom-row recoverEQ, rho=0 fast path, VLC consume-only) are
scalar restructurings; only one (SIMD4 readQuadSamples) is true
vectorisation.

Also catches a critical regression that release-prep benchmarking
caught: Phase 0's `J2KHTEntropyProfile` instrumentation bumps
caused 30 %+ slowdown on multi-tile decode via cache-line
contention from 16 parallel tile threads on the lockless global
counters. Fixed in #367 before tagging.

### Changed

- `recoverEQ -> (Int, Int, Int, Int)` replaced with
  `recoverEQBottomRow -> (Int, Int)` — every caller read only
  `.1` and `.3`; indices 0 and 2 (top-row) were computed and
  immediately discarded. Net 22-39 % block-decode speedup
  including the side benefits of register-passing the smaller
  tuple, eliminating the switch-i 4-way dispatch, and
  hand-inlining the offset-array loads.
- `readQuadSamples` post-MagSgn reconstruction now runs lane-
  parallel via `SIMD4<UInt32>` arithmetic (4 NEON 128-bit
  Q-register ops on Apple Silicon). 10-14 % faster on 64×64
  blocks.
- `readQuadSamples` and `recoverEQBottomRow` early-exit on
  `rho == 0` — most quads on sparse-corpus blocks (~70 % at
  typical 30 % density) hit this path. +19 % on sparse blocks.
- `VLCReverseReader.peek` and `read` annotated `@inline(__always)`.
- New `VLCReverseReader.consume(count:)` — refill-skip variant of
  `read(count:)` for post-peek discard sites; replaces 8
  occurrences of `_ = vlcReader.read(count: lookN.cwd_len)` and
  skips the redundant `if bits < count { refill() }` branch.
- Removed `J2KHTEntropyProfile.bumpXxx()` and `recordXxxNs()`
  call sites from the HT decoder hot path (#367 critical fix).

### Added

- `Sources/J2KCodec/J2KHTEntropyProfile.swift` — count-based
  process-global probe scaffolding (Phase 0). Production decoder
  no longer calls bump methods; the struct is kept so future
  optimisation work can re-enable the probe locally.
- `V730Phase0EntropyProbe.testEntropyEngineBreakdown_LosslessCorpus`
  — engine call breakdown across the medical corpus.
- `V730Phase1aMagSgnMicrobench.testMagSgnReadThroughput_PerWidth`
  — `HTMagSgnDecoderConformant.read` ns/call baseline.
- `V730Phase3aBlockDecodeMicrobench.testBlockDecodeThroughput_PerSizeAndDensity`
  — `HTBlockDecoderConformant.decode` ns/call baseline + density
  sweep. (This microbench is the gate for v7.3+ entropy work.)
- `RELEASE_NOTES_v7.3.0.md`, `CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md`,
  `V7_3_0_PROFILE.md` — release artefacts.

### Backward compatibility

Codestream bytes byte-identical to v7.2.0 across the medical
corpus. No public API breakage. SemVer rule: MINOR.

`getVersion()` returns `"7.3.0"`.

### Known limitations

- Kakadu gap remains 2.17× on DX in-process decode. Closing the
  rest requires CPU SIMD on the HT decoder's chained-state inner
  loops (MagSgn refill in particular) — multi-day work parked
  for a future release.
- MagSgn refill is at the Apple M2 scalar ceiling. Further
  headroom needs NEON byte-shuffle for the post-`0xFF` unstuff
  prefix-scan.
- Encode wall unchanged by v7.3 — all v7.3 work was on the
  decode side.

## [7.2.0] — 2026-05-09

**Encode-side UMA boundary elimination + cross-tile batched HT entropy decode**

Foundation-and-measurable-wins release. DX in-process decode tightens
from 65.5 ms → 60.0 ms (8.4 % faster vs v7.1.1); DX in-process encode
tightens 54.8 ms → 50.9 ms (7.2 % faster). Kakadu gap on DX in-process
decode goes from 2.66× → 2.43×. Closing the rest of the gap requires
CPU SIMD on the HT entropy decoder (62.6 % of DX decode CPU work) —
captured as the v7.3 arc in `V7_2_0_STATUS_AND_KAKADU_GAP.md`.

### Added

- **`J2KMetalSharedBufferView<Element: Sendable>`** — read-only typed
  view over a `.storageModeShared` MTLBuffer. Exposes the buffer's
  CPU-visible memory directly via `UnsafeBufferPointer`; no readback
  memcpy. Holds a strong buffer reference and returns it to the pool
  on `release()` / deinit.
- **`J2KMetalDWTSubbandsInt32View`** + **`J2KMetalDWT.forward2DInt32MultiLevelFusedView`** —
  view-backed counterpart to the array-returning forward 5/3 DWT
  producer. Eliminates the 4× per-level × N-level readback memcpys
  (= 20 boundaries on a typical 5-level lossless encode of DX).
- **`EncoderPipeline.CoefficientStorage`** enum (`.empty` / `.array` /
  `.view`) — polymorphic Int32 coefficient storage on `SubbandInfo`
  and `DeferredCodeBlock`.
- **`DecoderPipeline.decodeMultiTileGPUBatched`** — cross-tile batched
  HT entropy decode. Aggregates every tile's eligible HT codeblocks
  into one shared MTLCommandBuffer instead of N per-tile CBs.
- **`DecoderPipeline._multiTileBatchedEntropyEnabled`** static flag
  (default ON) for A/B comparison testing.
- **`V720Phase0UMAProfileTests`** — UMA counter baseline per fixture.
- **`V720PhaseEThresholdSweepTests`** — empirical sweep of the
  multi-tile per-tile entropy/IDWT GPU thresholds.
- **`V720PhaseEABTest`** — A/B `_multiTileBatchedEntropyEnabled` ON
  vs OFF across 5 fixtures.

### Changed

- `J2KDecodeTimings.record*` calls added to `decodeTilePayload` and
  `decodeTilePayloadGPU`. Pre-fix the multi-tile per-tile decode path
  reported all-zero stage breakdowns for fixtures ≥ 500K px.
- `applyEntropyDecoding` gains an optional
  `preBatchedGPUCoefficients: [Int: [Int32]]?` parameter.
- `SubbandInfo.coefficients` and `DeferredCodeBlock.subbandCoefficients`
  changed type from `[Int32]` to `CoefficientStorage`. Internal API.
- Lossless reversible 5/3 quantize stage bypasses identity-allocation
  for view-backed inputs, keeping the GPU output buffer alive through
  to the entropy coder.
- `getVersion()` returns `"7.2.0"` (was stale at `"5.14.2"`).

### Documentation

- `V7_2_0_PROFILE.md` — Phase 0 baseline + plan revision (Option 3).
- `V7_2_0_PHASE_E_FINDING.md` — empirical refutation of "lower
  thresholds" + pivot to CB amortisation.
- `V7_2_0_STATUS_AND_KAKADU_GAP.md` — end-of-overnight honest
  assessment + v7.3 SIMD arc sketch.
- `RELEASE_NOTES_v7.2.0.md` — full release notes.

### Backward compatibility

Codestream bytes byte-identical to v7.1.1. No public API breakage.
SemVer rule: MINOR.

### Known limitations

- Kakadu gap remains 2.43× on DX in-process decode. v7.3 arc.
- Phase A encode UMA wall benefit is foundation-only on default
  routing (gate fires only on per-tile pixels ≥ 4 MP; default
  planner picks 4x4 multi-tile for ≥3 MP fixtures).
- Phase E batched-entropy gate (per-tile ≥ 1 MP) retained — lowering
  it was empirically refuted (see `V7_2_0_PHASE_E_FINDING.md`).

## [5.34.0] — 2026-05-04

**Strict bounded-rate mode — hard byte cap via codestream truncation**

User spec: "make the byte cap real, even if that means exposing
two separate modes: one for quality-first and one for strict
bounded-rate." v5.33's `.constantBitrateBounded` capped overshoot
best-effort but could exceed 2× on flat-curve content (large
medical fixtures at low bpp; the encoder hits a content-determined
byte floor where 3-pass Qstep search can't converge).

v5.34 ships `.constantBitrateStrict(bpp, maxOvershootRatio: 1.0,
maxPasses: 3)` — public enum case + the new auto-promote default
for `.constantBitrate` on bitDepth >= 12 HT-conformant lossy.
Output is byte-exact ≤ `maxOvershootRatio × target × pixelCount/8`.
Default 1.0× = "never exceed target."

### Algorithm: post-encode codestream truncation

JPEG 2000 codestreams are LRCP-progressive: packets at lower
resolutions / earlier components form a valid prefix at any packet
boundary. v5.34 leverages this:

1. Run the v5.33 quality-first 3-pass Qstep search (bias toward
   overshoot, since truncation handles excess bytes for free).
2. If the result exceeds the cap, truncate the codestream at the
   largest LRCP packet boundary that still fits. Rewrite the SOT
   marker's `Psot` field; append the EOC marker.

The retained packets keep the bounded mode's quality. The dropped
tail packets cost detail in the highest-resolution / highest-
frequency sub-bands (last in LRCP order). Decoders handle the
premature-EOC condition per ISO/IEC 15444-1 Annex B (zero-fill
missing code blocks).

### Two modes, two contracts

| Mode | Cap | Quality | Latency | Use when |
|---|---|---|---|---|
| `.constantBitrateStrict(bpp)` (auto-promoted) | hard, byte-exact | bounded by truncation | 3 passes + truncation | DICOM PACS / archive — strict storage budget |
| `.constantBitrateBounded(bpp, ...)` | best-effort 2.0× | quality-first | 3 passes | quality-first when overshoot is acceptable |
| `.constantBitrateViaQstep(bpp, ...)` | unbounded (1.6-3×) | max | 8 passes | v5.31 max-quality behavior |
| `.fixedQstep(qstep)` | unbounded | content-dependent | 1 pass | latency-critical, caller picks qstep |

### Trade-off (auto-promote on real medical fixtures @ 2 bpp)

| Fixture | px | v5.33 (bounded) | v5.34 (strict) |
|---|---:|---:|---:|
| **PSNR / bytes ratio** |  |  |  |
| ct_001 (262k)  | 262k  | 61.20 dB / 2.91× | **20.15 dB / 0.96×** |
| xa_001 (1.0M)  | 1.0M  | 63.58 dB / 3.32× | **17.52 dB / 0.93×** |
| px_001 (3.2M)  | 3.2M  | 60.06 dB / 4.22× | **12.27 dB / 0.31×** |
| dx_002 (6.4M)  | 6.4M  | 60.00 dB / 4.03× | **13.14 dB / 0.29×** |

The headline contract has flipped: v5.33 prioritised quality and
let bytes overshoot; v5.34 prioritises the byte cap and lets
quality drop. This is a deliberate trade-off the user asked for
and was the original literal contract of `.constantBitrate(bpp)`.

The PSNR drop on flat-curve content is steeper than first
inspection suggests because LRCP packet boundaries on this format
land at a discrete, content-dependent set of byte offsets — most
of the encoded bits are in the highest-resolution packets, which
are large and either retained whole or dropped whole. So a 1.0×
cap can land far below 1.0× achieved (px_001 hits 0.31×) because
the next packet boundary above the cap is far past it. Quality
drops accordingly.

### Added

- `.constantBitrateStrict(bpp, maxOvershootRatio: 1.0, maxPasses: 3)`
  enum case in `J2KBitrateMode`. Hard byte cap via post-encode
  codestream truncation at LRCP packet boundaries.
- `EncoderPipeline.encodeWithPacketIndex(_:)` — internal entry that
  returns the encoded codestream paired with structural offsets
  (SOT marker position, tile data start, packet end offsets). Used
  by strict mode to identify legal truncation points.
- `EncoderPipeline.truncateAtPacketBoundary(_:targetBytes:)` —
  static helper that takes a packet-indexed codestream and produces
  a byte-bounded valid codestream. Rewrites Psot, appends EOC.
- `J2KEncoder.encodeViaStrictBoundedQstep` — strict-mode encode
  driver. Biases the search toward overshoot, applies truncation.
- `EncodedCodestreamWithIndex` struct — public-internal type
  carrying codestream + packet boundaries.

### Changed

- `.constantBitrate(bpp)` auto-promote on `useHTJ2K && htj2kBlockFormat
  == .conformant && !lossless && !useReversibleFilter && bitDepth ≥
  12` now routes to `.constantBitrateStrict` (1.0× cap, 3 passes)
  instead of `.constantBitrateBounded` (2.0× best-effort, 3 passes).
  Restores the literal "constant bitrate" contract.

### Verified

- `J2KConstantBitrateStrictTests` (6 tests) — strict cap honoured
  on every fixture × bpp combination; relaxed cap honoured as upper
  bound; truncated codestreams decode; auto-promote inherits strict.
- `J2KEncodeWithPacketIndexParityTests` (2 tests) — encodeWithPacket-
  Index produces byte-identical output to encode().
- `J2KEncodeRateControlGateQualityTests` baseline updated for v5.34
  strict-cap PSNR profile (14.65 dB → 13.0 dB on dx_002 @ 2 bpp).

### Known characteristics

- **PSNR can drop sharply on flat-curve high-bit-depth medical at
  low bpp** (see table above). Quality can be recovered by
  switching to `.constantBitrateBounded` explicitly.
- **Output bytes can land far below cap** when the next packet
  boundary above cap is far past it (px_001 @ 2 bpp hits 0.31×
  cap). v5.35 target: better budget filling.

### Reproducing

```bash
swift test -c release --filter J2KConstantBitrateStrictTests
swift test -c release --filter J2KEncodeWithPacketIndexParityTests
swift test -c release --filter J2KCrossScaleRDQualityProbe
```

## [5.33.0] — 2026-05-04

**Production-grade `.constantBitrateBounded` mode — predictable latency**

User spec: "Build a production-grade quality-preserving bounded-
rate mode with predictable latency." v5.32 capped overshoot at
2.0× but encode was 5-14× slower than the broken v5.30 PCRD
baseline (8 search iters + 3 refinement = 11 passes worst case).

v5.33 ships `.constantBitrateBounded(bpp, maxOvershootRatio: 2.0,
maxPasses: 3)` — public enum case + new auto-promote default for
`.constantBitrate` on bitDepth >= 12. Hard cap at `maxPasses`
encode passes total. Same algorithm as v5.32 search but bounded.

### Headline (auto-promote @ 2 bpp)

| Fixture | px | v5.32 | v5.33 |
|---|---:|---:|---:|
| **PSNR / bytes ratio** |  |  |  |
| ct_001 (262k)  | 262k  | 47.21 / 1.64× | **61.20 / 2.91×** |
| px_001 (3.2M)  | 3.2M  | 33.07 / 1.88× | **60.06 / 4.22×** |
| dx_002 (6.4M)  | 6.4M  | 33.92 / 1.69× | **60.00 / 4.03×** |
| **encode latency (mg_001 16.8M px)** |  |  |  |
|                |       | 3124 ms (11 passes) | **1231 ms (3)** |

v5.33 trade-off:
- Quality ↑↑ — clinical-grade 60+ dB (better than v5.31's 50 dB)
- Latency ↓↓↓ — 2.5× faster than v5.32, 3-pass hard cap
- Rate cap ≈ best-effort — may exceed 2.0× on flat-curve content
  where 3 passes can't converge. Stats report whether cap met.

### Added

- `Sources/J2KCodec/J2KEncodingPresets.swift` — new
  `.constantBitrateBounded(bpp, maxOvershootRatio, maxPasses)`
  enum case on `J2KBitrateMode`. Default: 2.0× cap, 3 passes.
- `Sources/J2KCodec/J2KCodec.swift` — `encodeViaBoundedQstep`
  internal function: log-binary-search with adaptive bracket
  extension, hard-capped at `maxPasses`. Cache lookup +
  calibration prior + ratio-corrected pass + binary search.
- All bitrate-mode switches in `J2KEncoderPipeline` updated to
  handle the new case (treated like `.fixedQstep` /
  `.constantBitrateViaQstep` — bypass PCRD, intercepted at
  `J2KEncoder.encode`).

### Changed

- Auto-promote (`.constantBitrate` on bitDepth >= 12) routes to
  `encodeViaBoundedQstep` with default `maxPasses: 3` instead of
  v5.32's `encodeViaQstepSearch` with 8 iters + 3 refinement.
- `MEDICAL_BENCHMARK.md` adds "v5.33.0 — `.constantBitrateBounded`
  mode" subsection comparing all 4 modes (PCRD broken, v5.31, v5.32,
  v5.33) on quality / rate / latency.

### When to use which mode

| Mode | Quality | Rate cap | Latency |
|---|---|---|---|
| `.constantBitrate` (auto) | 60+ dB | best-effort 2× | 3 passes |
| `.constantBitrateBounded` | configurable | configurable | configurable |
| `.constantBitrateViaQstep` | 45-50 dB | uncapped | 8 passes |
| `.fixedQstep` | content-dep | unbounded | 1 pass |

### Verified

- Cross-scale R-D probe: PSNR 33-63 dB across medical corpus.
- Lossless = ∞ dB.
- Medical encode benchmark: 2.5× faster than v5.32 on mammography.
- Decode unchanged.
- All v5.20-v5.32 correctness gates green.
- 4 pre-existing perf-aspirational test failures unaffected.

### Lesson

v5.31/v5.32/v5.33 walked a triangle: any two of {quality, strict
rate, low latency} on conformant cleanup-only block format. v5.31
chose quality + (loose latency, no cap). v5.32 chose strict rate
+ quality drop, slow. v5.33 chose **quality + low latency**, with
rate as best-effort. For medical archive workflows where storage
isn't the bottleneck and clinical quality is, this is the right
default.

## [5.32.0] — 2026-05-04

**Bounded-rate Qstep mode — cap overshoot at 2.0× target**

v5.31.0 fixed cross-scale R-D quality but the Qstep-search overshot
the rate target by 1.6–3× on large fixtures (rate contract violated
to fix the quality contract). Per user spec: "Build a bounded-rate
Qstep mode. Keep v5.31 quality. Reduce overshoot dramatically."

v5.32.0 adds a post-search refinement loop in
`encodeViaQstepSearch`: if achieved bytes still exceed
`maxOvershootRatio × target` after the main 8-iteration search,
run up to 3 additional iterations that scale qstep by
`pow(ratio, 0.7)` to push bytes down. Stops when within bound,
when no further reduction is possible (LL-band structural floor),
or at the iteration cap. Auto-promote uses `2.0×`; explicit
`.constantBitrateViaQstep` keeps `.infinity` (v5.31.0 behaviour).

### Headline (auto-promote `.constantBitrate` @ 2 bpp)

| Fixture | px | v5.31 PSNR / bytes | v5.32 PSNR / bytes |
|---|---:|---:|---:|
| xa_001 | 1.0M | 50.59 / 2.41× | 39.87 / 1.69× |
| px_001 | 3.2M | 46.25 / 3.04× | 33.07 / 1.88× |
| dx_002 | 6.4M | 45.80 / 2.81× | 33.92 / 1.69× |

Bytes overshoot capped at 2.0×. Quality drops 7-13 dB on worst-
overshoot cases but remains clinically relevant (>30 dB) and
dramatically better than pre-v5.31 PCRD (13-17 dB). Fixtures
already under 2× pass through unchanged at v5.31 quality.

### Trade-off — encode latency

The 8-iteration Qstep search makes auto-promoted encode 5–14×
slower than v5.30 PCRD baseline (e.g. mg_001: 225 ms → 3.1 s).
This is the cost of correctness — v5.30 was producing 14 dB
output at clinical bitrates. Mitigations:

- Pass `J2KQstepCache` via `encodingConfiguration.qstepCache` —
  subsequent encodes hit cache, skip 5-6 of the 8 search iters.
- Use `.fixedQstep(qstep:)` for latency-critical single-shot
  encodes — caller picks qstep, no rate-target search.

### Changed

- `Sources/J2KCodec/J2KCodec.swift` — `encodeViaQstepSearch`
  gains `maxOvershootRatio: Double = 2.0` parameter + post-
  search refinement loop. Auto-promote site uses default `2.0`;
  explicit `.constantBitrateViaQstep` site uses `.infinity`.
- `MEDICAL_BENCHMARK.md` "Cross-Scale R-D Quality" section
  expanded with v5.31 vs v5.32 trade-off tables (bytes, quality,
  latency).

### Verified

- Cross-scale R-D probe: PSNR consistent at 33-66 dB across the
  medical corpus (vs pre-v5.31 13-35 dB; vs v5.31 47-50 dB).
- Lossless roundtrip = ∞ dB (unchanged).
- All v5.20-v5.31 correctness gates green.
- 3 pre-existing perf-aspirational test failures unaffected.

### Lesson

v5.31's quality fix violated the rate contract; v5.32 is the
rate-quality balance. The post-search refinement loop is the
right shape: cheap when not needed (early-exit when bytes
already within bound), bounded when needed (3 iterations max),
respects the structural floor (don't keep refining when qstep
increase doesn't reduce bytes — the LL-band overhead is the
irreducible minimum).

## [5.31.0] — 2026-05-04

**Cross-scale λ formulation fix — HT conformant lossy R-D**

User report: "the λ / bit-allocation model is mathematically
inconsistent across scale, which is why MRI looks great and
mammography falls apart." Confirmed via cross-scale R-D probe —
roundtrip PSNR on real medical fixtures was scale-dependent and
catastrophic at mammography sizes (16.30 dB at 4 bpp on dx_002,
where 60+ dB is expected).

### Headline (PSNR @ 2 bpp, 16-bit medical, real fixtures)

| Fixture                | px    | Pre-v5.31.0 | v5.31.0   |
|------------------------|------:|------------:|----------:|
| mr_002 (180²)          |  32k  |       35.39 |  **52.58** |
| ct_001 (512²)          | 262k  |       19.81 |  **47.21** |
| xa_001 (1024²)         |  1.0M |       17.45 |  **50.59** |
| px_001 (2459×1316)     |  3.2M |       13.47 |  **46.25** |
| dx_002 (2800×2288)     |  6.4M |       14.65 |  **45.80** |

PSNR scales healthily with bpp now (~10-15 dB per doubling) vs
~1 dB pre-fix.

### Diagnosis

HT-conformant cleanup-only blocks are single-pass; PCRD-opt's
slope-based selection across blocks reduces to all-or-nothing
per-block include/exclude. On high-bit-depth content with dense
slope ranking, the discretisation produces wildly different
quality at different codeblock counts (which scale with image
size). Lossless was confirmed exact (∞ dB), so the wavelet +
entropy pipeline is sound; the issue is in R-D allocation.

The v5.18 (`.fixedQstep`) and v5.19 (`.constantBitrateViaQstep`)
modes were workarounds. v5.31.0 wires the workaround into the
default path so callers get a working codec without needing to
opt in.

### Fix

`Sources/J2KCodec/J2KCodec.swift` — `J2KEncoder.encode(_:)` auto-
promotes `.constantBitrate` → Qstep-search when **all** of:

- `useHTJ2K`, `htj2kBlockFormat = .conformant`
- not `lossless`, not `useReversibleFilter`
- `bitDepth ≥ 12` (medical / scientific content)

8-bit RGB photographic content passes through to PCRD-opt
unchanged (preserves encode-speed advantage where R-D collapse
isn't observed).

Plus widened Qstep-search bracket — adaptive with `|log2(ratio)|`
at iter-1; dynamic ×4 ceiling extension at iter-2..N when search
hits the cap. Helps on flat-curve high-bit-depth content.

### Added

- `Tests/J2KCodecTests/J2KCrossScaleRDQualityProbe.swift` —
  three diagnostic tests:
  - `testDX002LosslessRoundtripExact` — sanity (∞ dB).
  - `testCrossScaleRDPSNRSweep` — 7 fixtures × 4 bpp targets.
  - `testCrossScaleQstepVsPCRD` — comparison mode (the
    diagnostic that pinpointed the problem).
- `MEDICAL_BENCHMARK.md` "Cross-Scale R-D Quality (v5.31.0)"
  section with pre/post comparison + rate trade-off data.

### Trade-off

`.constantBitrate` no longer guarantees exact byte target for
high-bit-depth HT-conformant lossy. Qstep-search converges on
uniform quantisation, which has a content-dependent rate floor.
Observed overshoot at 2 bpp ranges from 1.02× (small) to 3.04×
(large mammography) — quality is dramatically better but bytes
exceed the target. For strict-rate workflows: use
`.constantBitrateViaQstep` explicitly (same overshoot, but the
caller knows), `.fixedQstep` (caller picks qstep, no search),
or non-conformant HT / EBCOT (within-block passes available).

For PACS / archive workloads that prioritise quality over exact
byte budgets, this is the right default.

### Verified

- 9/7 correctness gates green (lossless = ∞ dB).
- Cross-scale PSNR now 45-65 dB across the medical corpus.
- 4 previously-failing tests asserted the OLD pre-fix behaviour
  on 8-bit content; the `bitDepth ≥ 12` gate excludes them so
  they pass unchanged.
- 2 pre-existing perf-aspirational failures unaffected.

### Lesson

`.fixedQstep` / `.constantBitrateViaQstep` were documented as
"alternative encoding modes" but were actually fixes for a real
correctness problem with the default `.constantBitrate` path.
Documenting workarounds the caller has to opt into doesn't fix
the bug — it transfers responsibility to the caller, who often
doesn't know they need to opt in. v5.31.0: when the architecture
has a path that gives the right answer, use it by default.

## [5.30.0] — 2026-05-04

**`rateControl` super-linear fix — mammography encode 4.2× speedup**

v5.29.0's stage breakdown identified `rateControl` as 75% of
encode time at mammography (16.8M px → 679-701 ms). v5.30.0
root-causes it as an O(B²) inner loop in
`improveHTNearTargetAllocation`'s "small local exchange near the
byte target" step (line 1419-1465 of J2KRateControl.swift). At
B=4096 codeblocks that's ~67M iterations × 4 outer iterations.

The exchange's purpose is fine-tuning at sub-0.1%-budget
granularity. At B=1024 each block is 0.1% of total bytes; at
B=4096 each is 0.025%. Single-block swaps at that scale fall
below any quality metric's noise floor — there's no R-D outcome
to find. Gating the function at B ≤ 1024 eliminates the
quadratic cost without changing R-D allocation outcomes.

### Headline (M2, release, n=5)

| Fixture                | v5.29.0 encode | v5.30.0 encode | Speedup |
|------------------------|---------------:|---------------:|--------:|
| dx_001 (2544×3056)*    |        240 ms  |        102 ms  |   2.4×  |
| mg_001 (3520×4784)*    |        900 ms  |    **214 ms**  | **4.2×** |
| mg_002 (3521×4784)*    |        921 ms  |    **211 ms**  | **4.4×** |

Sub-1024-block fixtures (≤ ct/xa/mr/px_001) are unchanged.

### Stage delta

`rateControl` per fixture (v5.29 → v5.30):
- px_001 (~800 blocks):   7.4 ms → 7.4 ms (gate doesn't fire)
- dx_002 (~1500 blocks): 24.2 ms → 1.0 ms (gate fires)
- mg_001 (~4096 blocks): 678.8 ms → 2.1 ms (gate fires)

### Added

- `Sources/J2KCodec/J2KRateControl.swift` — block-count gate on
  `improveHTNearTargetAllocation` + `frontiersByBlockCount`
  helper.
- `Tests/J2KCodecTests/J2KEncodeRateControlGateQualityTests.swift`
  — `testDX002LossyPSNRPreservedAcrossV5_30Gate` verifies
  roundtrip PSNR on dx_002 (~1500 blocks → gate fires) matches
  the pre-v5.30.0 baseline within 1 dB. Catches gross R-D
  regressions.
- `MEDICAL_BENCHMARK.md` — v5.30.0 encode update section.

### Verified

- New PSNR-preservation test passes (PSNR identical pre/post the
  gate on dx_002).
- All v5.20-v5.29 regression gates remain green (decode
  bit-exactness, cross-module audit, session bit-equivalence,
  decode 4.6× mammography speedup preserved).
- 2 pre-existing perf-aspirational test failures unaffected.

### What's still open

- `encodeGPU` is still a regression (GPU forward DWT slower than
  CPU on every fixture). Either fix or remove in v5.31.
- Pre-existing low absolute PSNR on DX/CT fixtures — encoder slope
  formulation produces poor R-D allocation (visible since v5.21.0
  bisect test). Tracked separately; v5.30.0's gate doesn't change
  it.
- After v5.30.0, `entropyCoding` is the universal dominant encode
  stage (43-52% of total). That's the natural target for a GPU HT
  entropy encoder — mirroring v5.26.0's GPU HT decoder.

### Lesson

"75% of encode time at mammography" isn't actionable on its own
— it could mean "PCRD-opt is fundamentally expensive at scale"
(don't fix) or "there's a hot loop that's accidentally O(B²)"
(fix in 6 lines). Reading the code revealed the latter. Same
shape as v5.27.0's CPU-work skip: once the architecture changes
(here: codeblock count grows), audit what the old code was doing
that doesn't make sense at the new scale.

## [5.29.0] — 2026-05-04

**Encode stage timings + `encodeGPU` regression discovery**

Mirrors v5.24.0's pattern on the encode side: ship per-stage
timings + corpus characterisation, let the data inform v5.30.
Two unexpected findings:

1. `encodeGPU` is currently a regression at every measured fixture
   size — slower than CPU `encode` by 2-39%. GPU forward DWT
   dispatch overhead exceeds the compute it saves.
2. At 17M-pixel mammography, `rateControl` is **75% of encode
   time** (679–701 ms / 900–920 ms). Super-linear scaling: 1M px
   = 2.6 ms; 17M px = 700 ms (~270× for 17× pixel count).

### Headline (M2, release, n=5)

| Fixture                | CPU `encode` | `encodeGPU` | CPU/GPU× |
|------------------------|-------------:|------------:|---------:|
| xa_001 (1024×1024)     |       17 ms  |       28 ms |    0.61× |
| px_001 (2459×1316)     |       50 ms  |       69 ms |    0.73× |
| dx_002 (2800×2288)     |      110 ms  |      133 ms |    0.83× |
| mg_001 (3520×4784)*    |      900 ms  |      979 ms |    0.92× |

CPU `encode` wins on every fixture. **Use `encode(_:)` for now;
`encodeGPU` is currently a regression.**

### Stage breakdown shows two regimes

- **≤6.4M pixels**: `entropyCoding` is dominant (42-49% of total)
- **≥7.8M pixels**: `rateControl` dominates (50-75% of total)

### Added

- `Sources/J2KCodec/J2KEncodeTimings.swift` — process-global
  always-on stage timings accumulator (mirrors v5.24.0
  `J2KDecodeTimings`). 7 stages tracked.
- `Tests/J2KMetalTests/J2KMedicalCorpusEncodePerformanceTests.swift` —
  corpus encode benchmark sweeping 10 fixtures × CPU+GPU encode ×
  per-stage breakdown.
- `MEDICAL_BENCHMARK.md` "Encode Performance (v5.29.0)" section
  with per-fixture times, stage breakdown, three honest findings,
  routing recommendation.

### Changed

- `J2KEncoderPipeline.encode` and `encodeGPU` — wired
  `J2KEncodeTimings.recordX` calls at all 7 stage boundaries. The
  existing `J2K_PROFILE` env-var prints remain unchanged.

### What v5.29.0 does NOT do

Characterisation release, not optimisation. No encode behaviour
change. No new public APIs.

### Strategy for v5.30 (data-driven)

1. Investigate `rateControl` super-linear scaling at large
   workloads — most likely fixable hot loop in PCRD-opt; could
   yield 5-10× on mammography encode (recommended first).
2. GPU HT entropy encoder — mirror v5.26.0 decoder pattern in the
   forward direction. Larger scope.
3. Fix or remove `encodeGPU` — currently a regression.

### Lesson

Same as v5.24.0: stage timings reveal what end-to-end numbers
hide. The "GPU-accelerated" encode path was treated as faster;
the data shows it's slower. The dominant stage at mammography
turned out to be rate control, not entropy coding. Don't
optimise until you've measured; don't trust a name like
`encodeGPU` until the breakdown confirms it.

## [5.28.0] — 2026-05-04

**Mammography corpus extension + `preWarm()` cold-start helper**

v5.27.0 measured 7 medical fixtures up to 2800×2288 and codified
the routing rule. Three larger fixtures (mammography, up to 16.8M
px) weren't checked in. v5.28.0 extends the corpus to those sizes
via synthetic equivalents, validates the routing rule keeps holding
all the way up to 17M pixels, and adds a `preWarm()` helper that
eliminates ~30 ms of cold-start cost.

### Headline 1 — mammography validates the architecture

| Fixture                | Pixels  | CPU      | `decodeWithGPUHT`× |
|------------------------|--------:|---------:|--------------------:|
| dx_001 (2544×3056)*    |   7.8M  |  223 ms  |              4.4×   |
| mg_001 (3520×4784)*    |  16.8M  |  503 ms  |          **4.6×**   |
| mg_002 (3521×4784)*    |  16.8M  |  500 ms  |              4.4×   |

`*` synthetic LCG-noise fixtures (real PGMs not in-repo).
`decodeWithGPUHT` keeps gaining headroom up to 17M pixels.

### Headline 2 — `preWarm()` eliminates cold-start

| 512×512 16-bit lossy 9/7, M2  | Without preWarm | With preWarm |
|-------------------------------|----------------:|-------------:|
| Cold first decode             |      40–49 ms   |       —      |
| `preWarm()` itself            |        —        |    27–32 ms  |
| First user decode after warm  |        —        |  **9–16 ms** |
| Cold-start cost eliminated    |        —        |    25–30 ms  |

Crossover at N=2 decodes — any workload that decodes more than
one image benefits from `preWarm()`.

### Added

- `Sources/J2KCodec/J2KMetalSession.swift` —
  `preWarm(includeWarmupDispatch:)` async helper. Initialises
  device, loads shaders, pre-compiles 11 decode-hot-path
  pipelines in parallel, runs a tiny 256×256 synthetic decode to
  exercise the non-pipeline lazy-init paths (VLC table upload,
  buffer pool first-fetch, Metal driver first-dispatch fence).
- `Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift` —
  3 new synthetic fixtures (dx_001, mg_001, mg_002) plus
  `testColdStartVsPreWarmFirstDecodeLatency` measurement gate.
  `Fixture` struct with optional `synthDimensions` for missing-
  on-disk fallback.
- `MEDICAL_BENCHMARK.md` — Decode Performance table extended to
  10 fixtures; new "Cold-Start vs `preWarm()`" subsection.

### Verified

- All 9/7 correctness gates remain green (max diff = 1 LSB at
  16-bit on session bit-equivalence).
- New corpus benchmark passes; cold-start test passes (savings
  consistently 25–30 ms across runs).
- 4 pre-existing perf-aspirational test failures unaffected.

### Lesson

First attempt at `preWarm()` only compiled shader pipelines and
saved ~10 ms — way short of the ~30 ms target. Missing piece:
exercising the actual GPU dispatch path. Modern GPU API cold-
start cost isn't all shader compilation; driver-side state init
happens lazily on first dispatch and can dominate. Pre-warming
has to exercise the hot path, not just compile its prerequisites.

## [5.27.0] — 2026-05-04

**Medical corpus characterisation + CPU-work skip + routing helper**

v5.24-v5.26 measured a single 1024×1024 fixture. v5.27.0 sweeps
the medical DICOM corpus (7 fixtures, 180×180 to 2800×2288),
publishes a per-fixture performance table + routing rule, and
ships one more optimisation: skip the now-dead CPU regroup +
dequant path when the v5.26.0 Float fused batch is consumed.

### Headline (medical corpus, M2, release, n=5 medians)

| Fixture                | CPU      | `decodeGPU`× | `decodeWithGPUHT`× |
|------------------------|---------:|-------------:|-------------------:|
| ct_001 (512×512)       |   7.2 ms |        1.6×  |               0.8× |
| xa_001 (1024×1024)     |  25.7 ms |        2.8×  |               1.8× |
| px_001 (2459×1316)     |  86.2 ms |        2.8×  |          **3.2×** |
| dx_002 (2800×2288)     | 170.1 ms |        3.5×  |          **4.0×** |

The crossover is decisive: `decodeGPU` wins below ~1M px;
`decodeWithGPUHT` wins above ~3M px.

### Added

- `Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift` —
  sweeps 7 fixtures × 3 APIs × per-stage breakdown. Prints a
  markdown-friendly table for direct paste into
  MEDICAL_BENCHMARK.md.
- `MEDICAL_BENCHMARK.md` — new "Decode Performance (v5.27.0)"
  section with per-fixture times, speedups, routing rule, and
  v5.26.0 → v5.27.0 delta.
- `Sources/J2KCodec/J2KCodec.swift` —
  `J2KDecoder.recommendedDecodeAPI(width:height:)` static helper
  + `J2KRecommendedDecodeAPI` enum. Codifies the routing
  threshold (CPU < 256² < decodeGPU < ~1730² ≤ decodeWithGPUHT).

### Changed

- `Sources/J2KCodec/J2KDecoderPipeline.swift` —
  `applyEntropyDecoding` short-circuits on the Float fused batch
  path. When `gpuBatch.floatPlansByComponent` is non-nil, returns
  `([], batch)` immediately; skips the [SubbandInfo] regroup loop.
  `applyDequantization` becomes a no-op for those components
  (empty input → empty output). The GPU scatter+dequant kernel
  has already produced the dequantised Float subbands.
- `applyInverseWaveletTransformGPU` fast-out check now considers
  `floatPlansByComponent` alongside the Int32 `plansByComponent`.

### Per-fixture savings (post-v5.27.0 vs v5.26.0)

| Fixture            | v5.26.0 | v5.27.0 | Δ |
|--------------------|--------:|--------:|--:|
| px_001 (2459×1316) | 41.0 ms | 27.2 ms | **−14 ms** |
| dx_002 (2800×2288) | 46.9 ms | 42.7 ms |  −4 ms |

Per-stage on dx_002: `dequantization` 4.0 → 0.0 ms (skipped);
regroup 1.3 → 0.6 ms (only `buildGPUHTBatchFromResultFloat` runs;
[SubbandInfo] regroup gone).

### Verified

- New `testSessionPathBitEquivalentToNoSessionPath` (v5.26.0) still
  green: max diff = 1 LSB at 16-bit. Short-circuit doesn't break
  bit-equivalence.
- All v5.14-v5.26 regression gates remain green.

### Lesson

When an architecture changes, audit what the old code was doing
that the new code makes redundant. v5.26.0's Float scatter+dequant
kernel made the CPU dequant pass dead; spotting that took a
7-fixture sweep + attention to the stage breakdown. The fix was
six lines of pipeline plumbing for a 14 ms saving on px_001.

## [5.26.0] — 2026-05-04

**Float scatter+dequant + GPU-resident dispatch — `decodeWithGPUHT` 9/7 lossy 1.0×→1.85×**

v5.25.0 closed per-level readback in the 9/7 lossy IDWT (Float
multi-level fused). v5.26.0 closes the remaining levers for
`decodeWithGPUHT` 9/7 lossy: extends the GPU-resident batch path
(previously 5/3-only) to 9/7 lossy via a new Float scatter+dequant
Metal kernel and a Float fused-from-codeblocks IDWT.

### Headline (M2, release, 1024×1024 16-bit lossy 9/7 @ 2 bpp, n=5)

| Path | v5.25.0 speedup | v5.26.0 speedup |
|---|---:|---:|
| `decodeGPU(_:session:)` | 2.64–3.13× | 2.55–3.07× |
| `decodeWithGPUHT(_:session:)` | 1.00–1.36× | **1.81–1.86×** |

Two compounding wins:

1. `gpuHTDispatch` 15+ ms → ~7 ms — switched 9/7 lossy entropy
   dispatch from `decodeBatch` (full host readback of codeblock
   buffer) to `decodeBatchGPUResident` (no readback). This alone
   saves ~8 ms per decode.
2. `inverseWaveletTransform` 10+ ms → ~5 ms — Float scatter+dequant
   kernel + fused-from-codeblocks IDWT. Skips per-level CPU upload
   of LH/HL/HH (sourced from the GPU-resident codeblock buffer
   instead) and bakes dequant into the scatter step.

### Added

- `Sources/J2KMetal/J2KShaders.metal` (and embedded fallback) —
  `j2k_subband_scatter_float_dequant` kernel. Reads Int32 codeblock
  output, applies HTJ2K conformant cleanup-only dequant
  `(coeff ± 0.5) * stepSize`, writes Float to subband layout.
- `Sources/J2KMetal/J2KMetalSubbandScatter.swift` —
  `J2KMetalSubbandScatterDescriptorFloat` (32-byte layout, replaces
  `_pad` with `stepSize: Float`).
- `Sources/J2KMetal/J2KMetalDWT.swift` —
  `LevelScatterPlanFloat` + `inverse2DFullFusedFromCodeblocks`
  (Float overload). Mirror of the Int32 5/3 lossless path.
- `Sources/J2KMetal/J2KMetalShaderLibrary.swift` —
  `.subbandScatterFloatDequant` shader function case.
- `Tests/J2KCodecTests/J2KGPULossy97DivergenceTests.swift` —
  `testSessionPathBitEquivalentToNoSessionPath` — verifies the
  session-warm path (which exercises v5.26.0 code) matches the
  no-session path within 4 LSB at 16-bit. Observed: max diff = 1.

### Changed

- `Sources/J2KCodec/J2KGPUHTDispatch.swift` — `J2KGPUHTBatch`
  gained `floatPlansByComponent: [Int: [LevelScatterPlanFloat]]?`
  field. Non-nil for 9/7 lossy fused-from-codeblocks; mutually
  exclusive with the Int32 `plansByComponent`.
- `Sources/J2KCodec/J2KDecoderPipeline.swift`:
  - `applyEntropyDecoding` fused-batch gate dropped
    `!isIrreversibleFilter`. 9/7 lossy now also routes through
    `decodeBatchGPUResident`. New `buildGPUHTBatchFromResultFloat`
    helper produces the Float batch with per-block stepSize lookup.
  - `applyInverseWaveletTransformGPU` 9/7 branch consumes Float
    batch when present; falls back to v5.25.0 multi-level fused
    (CPU-uploaded subbands) otherwise.
- `Sources/J2KMetal/default.metallib` regenerated with the new
  kernel.

### Verified

- New `testSessionPathBitEquivalentToNoSessionPath` passes: max
  diff = 1 LSB, avg = 0 (Float-precision noise).
- Existing v5.21.0 `testBisectDecodePaths` still green.
- All v5.14-v5.25 regression gates remain green.

### What's still open

- `decodeGPU(_:session:)` remains the fastest API on this workload
  because CPU HT entropy (~1.3 ms parallelised) beats even the
  v5.26.0-reduced GPU HT dispatch (~7 ms).
- `decodeWithGPUHT` becomes the right choice on workloads where
  the GPU dispatch amortises — likely much larger images. That
  crossover hasn't been characterised yet.

### Lesson

The expected gain from extending the fused batch path to 9/7
lossy was thought to be modest — closing per-level upload was
thought to save ~1-2 ms. Reality: the bigger latent win was
switching the entropy dispatch from `decodeBatch` to
`decodeBatchGPUResident`, saving ~8 ms. The original gate
`!isIrreversibleFilter` was locking 9/7 lossy out of BOTH wins.
Removing it compounded the savings. Lesson: when a feature is
gated against multiple optimisations under one boolean, the cost
is the sum, not the visible item.

## [5.25.0] — 2026-05-04

**Float multi-level fused IDWT — 9/7 lossy speedup jumps to 2.6–3.1×**

v5.24.0's stage breakdown identified per-level upload/readback in
the 9/7 lossy IDWT as the next architectural lever. v5.25.0 closes
it: adds `J2KMetalDWT.inverse2DMultiLevelFused` (Float variant)
mirroring the existing Int32 5/3 fused path. Single command buffer
across all decomposition levels; output buffer of level N reused
as LL input of level N-1; single commit + await + final readback.

### Headline (M2, release, 1024×1024 16-bit lossy 9/7 @ 2 bpp, n=5)

| Path | v5.24.0 speedup | v5.25.0 speedup |
|---|---:|---:|
| `decodeGPU(_:session:)` | 1.43× | **2.64–3.13×** |
| `decodeWithGPUHT(_:session:)` | 1.07× | 1.00–1.36× |

`inverseWaveletTransform` stage on the `decodeGPU` path: 15.2 →
7.4 ms (50% drop). `decodeWithGPUHT` IDWT also benefits but the
~15 ms `gpuHTDispatch` overhead caps end-to-end gains for that
path — addressed in a future release.

### Added

- `Sources/J2KMetal/J2KMetalDWT.swift` —
  `inverse2DMultiLevelFused(subbandsPerLevel:)` Float method;
  `encodeInverse2D(into:...)` Float chainable encode (mirror of
  `encodeInverse2DInt32`). Both `#if canImport(Metal)`-gated with
  no-Metal stubs.

### Changed

- `Sources/J2KCodec/J2KDecoderPipeline.swift` —
  `applyInverseWaveletTransformGPU`'s 9/7 lossy branch now routes
  through `inverse2DMultiLevelFused` when `metalSession != nil`.
  Sessionless callers keep the v5.7-era per-level `inverse2D`
  loop; no behavioural change for them.

### Verified

- `J2KGPULossy97DivergenceTests`, `J2KMetalSingleLevel97Tests`,
  `J2KWaveletConventionAuditTests` all green — fused path is
  bit-equivalent to the per-level path.
- New benchmark numbers reproduce across 4 sample runs.

### What's still open

- `gpuHTDispatch` overhead (~15 ms) is unchanged — separate lever.
- Float scatter kernel (GPU-resident codeblock buffer → LH/HL/HH
  in 2D layout) would close the remaining per-level upload but
  only helps `decodeWithGPUHT`. Tracked as next increment after
  the dispatch-overhead fix.

### Lesson

v5.24.0's stage breakdown predicted ~2-3 ms IDWT improvement from
closing per-level upload/readback. Reality: 7.8 ms. Per-level
commit + await cycle was costing more than just the data transfer.
Instrument first, optimise the dominant stage, measure after, ship.

## [5.24.0] — 2026-05-04

**Stage-level decode timings + 9/7 lossy strategy correction**

v5.23.0's release notes described the 9/7 lossy speedup ceiling as
"modest because HT entropy is still on CPU." That was wrong — the
GPU HT entropy decoder is wired into `decodeWithGPUHT` via
`J2KGPUHTDispatch.decodeBatch`. v5.24.0 adds stage-level timing
instrumentation and a three-path comparison; the data shows the
opposite: GPU HT dispatch overhead exceeds CPU HT cost on small/
medium 9/7 lossy workloads.

### Headline finding (M2, release, 1024×1024 16-bit, 2 bpp, n=5)

| Path | Median | Speedup |
|---|---:|---:|
| `decode` (CPU) | 25.6 ms | 1.00× |
| `decodeGPU(_:session:)` (CPU HT + GPU IDWT) | 17.8 ms | **1.43×** |
| `decodeWithGPUHT(_:session:)` (GPU HT + IDWT) | 24.0 ms | 1.07× |

Per-stage means show why: GPU HT dispatch costs ~11.6 ms even
warm, while parallelised CPU HT runs in ~1.3 ms. GPU IDWT saves
~7.5 ms (CPU 22.7 → gpuIDWT 15.2) — that's the dominant win.

### Added

- `Sources/J2KCodec/J2KDecodeTimings.swift` — process-global,
  always-on, NSLock-protected stage timings accumulator. Mirrors
  the `J2KMetalUMACounters` pattern. Tracks 8 stages (incl. the
  `gpuHTDispatch` sub-stage of `entropyDecoding`). `reset()` before
  a decode; `snapshot()` after. ~tens of ns per stage; negligible.
- `Sources/J2KCodec/J2KCodec.swift` — new public API
  `decodeGPU(_:session:)` mirroring `decodeWithGPUHT(_:session:)`
  but keeping HT entropy on CPU. Recommended for 9/7 lossy on warm
  session today (1.43× vs `decodeWithGPUHT`'s 1.07×).
- Stage-timing record calls inside the 14 existing
  `J2K_PROFILE_DECODE` profile sites in `J2KDecoderPipeline`
  (7 GPU + 7 CPU). Env-var prints unchanged; accumulator runs in
  addition.
- Sub-stage timing for `J2KGPUHTDispatch.decodeBatch` and
  `decodeBatchGPUResident` calls (3 sites in `J2KDecoderPipeline`).

### Changed

- `Tests/J2KMetalTests/J2KGPULossy97PerformanceTests.swift` —
  three-path comparison (CPU vs `decodeGPU` vs `decodeWithGPUHT`)
  with full per-stage breakdown including `gpuHTDispatch` sub-
  stage. Replaces v5.23.0's two-path end-to-end-only benchmark.

### Errata for v5.23.0

The v5.23.0 release notes said "decodeWithGPUHT only owns IDWT +
colour transform + quantisation; HT entropy is still on CPU." HT
entropy is in fact on the GPU in that path. v5.23.0's measurement
remains valid; only the explanatory model was wrong.

### Verified

- New benchmark passes in release mode; stage breakdown reproduces
  within typical timing variance.
- All v5.14-v5.23 regression gates remain green.

### Lesson

Headline numbers without stage breakdown lie by omission. The way
to ship perf claims that don't decay is: measure the end-to-end,
attribute to stages, name the dominant cost. v5.23.0 had the
end-to-end. v5.24.0 has the attribution.

## [5.23.0] — 2026-05-04

**GPU 9/7 lossy decode performance characterisation**

v5.20.0–v5.22.0 fixed the GPU 9/7 IDWT correctness bug and locked
in cross-module wavelet-convention agreement. v5.23.0 measures
what the corrected GPU IDWT path actually delivers in release
mode with session reuse, and ratifies the result honestly.

### Headline measurement

Release mode, M2, 1024×1024 16-bit lossy 9/7 @ 2 bpp, n=5 medians,
4 sampled runs:

- CPU `J2KDecoder.decode`: ~26 ms (consistent across runs)
- GPU `decodeWithGPUHT(_:session:)`: ~17–24 ms (variance is real)
- Speedup range: 0.99×–1.54×, median ~1.4–1.5×

The ceiling is modest because `decodeWithGPUHT` only puts IDWT +
colour transform + quantisation on the GPU; HT entropy decoding
still runs on the CPU and dominates the wall clock at typical
block sizes. The bigger architectural lever — GPU HT entropy
decoding — is in flight on the `gpu-ht-phase3` branch and not part
of this release.

### Added

- `Tests/J2KMetalTests/J2KGPULossy97PerformanceTests.swift` —
  `testWarmSessionGPUSpeedupVsCPU` measurement gate. Encodes a
  1024×1024 16-bit synthetic image once at 2 bpp HT-conformant
  lossy 9/7, then times CPU and GPU-HT decode paths with a shared
  `J2KMetalSession` (5 calls each, after warm-up). Prints medians,
  per-call vector, and speedup ratio.

### Design choice — measurement gate, not perf assertion

The benchmark deliberately does NOT assert a specific speedup
threshold. Sampled 4× on the same hardware, a `gpuMedian < cpuMedian`
assertion flaked ~1-in-4 because the two paths land within noise
on tight runs. Asserting any ratio would amplify that flake rate.
The test prints the numbers; correctness is already covered by
the v5.20–v5.22 audit suite. Future trend tracking and CI review
read the printed line.

### Verified

- New benchmark passes in release mode.
- All v5.14–v5.22 regression gates remain green.

### Lesson

Every speedup claim should be accompanied by the measured range
and the next architectural lever, not a marketing number from a
single favourable run. The bigger 9/7 lossy win is real and coming
on `gpu-ht-phase3`; this release tells the truth about today.

## [5.22.0] — 2026-05-04

**Conformance Audit — wavelet convention agreement across all modules**

v5.20.0/v5.21.0 fixed the GPU 9/7 IDWT scaling inversion in
J2KMetalDWT. v5.22.0 audits ALL wavelet implementations for
cross-module convention agreement and locks the audit results in
as permanent regression gates, preventing the same bug class from
re-appearing.

### Audit findings

- **JP3DMetalDWT 9/7 had the same scaling-direction bug** as
  J2KMetalDWT pre-v5.21.0. Self-consistent within itself but
  spec-divergent from J2K3D.JP3DWaveletTransform (which uses the
  ISO/IEC 15444-1 convention). No current callers, so no
  user-visible defect; fixed preemptively in 5 sites:
  - GPU forward 9/7 X / Y / Z kernels (3 sites)
  - CPU `forward97Lifting` + `inverse97Lifting` (2 sites)
- **J2KMetalDWT 5/3** convention checked vs J2KCodec.J2KDWT1D.
  Convention agrees; minor sub-LSB Float-precision drift (Float
  arithmetic vs exact Int32) is normal and well below convention-
  drift levels.
- **Encoder forward DWT** uses J2KCodec.J2KDWT1D (spec-compliant);
  GPU forward DWT is not on any encoder code path. No exposure.
- **Boundary extension** between CPU and GPU implementations agrees
  at the indices that matter for valid block dimensions.

### Fixed

- `Sources/J2KMetal/JP3DMetalDWT.swift` — swap scaling direction in
  3 GPU forward 9/7 kernels (X/Y/Z axes) and 2 CPU lifting functions.

### Added

- `Tests/J2KMetalTests/J2KWaveletConventionAuditTests.swift` —
  4-test cross-module agreement gate:
  - 9/7 inverse: J2KMetalDWT vs J2KCodec.J2KDWT1D (locks v5.21.0 fix)
  - 9/7 forward: J2KMetalDWT vs J2KCodec.J2KDWT1D (locks v5.21.0 fix)
  - 5/3 inverse: J2KMetalDWT vs J2KCodec.J2KDWT1D (convention)
  - JP3DMetalDWT 9/7 forward vs hand-built ISO/IEC 15444-1
    reference (locks v5.22.0 fix)

### Verified

- 4 new audit tests pass with max diff ≤ 1 LSB (Float precision).
- All v5.14-v5.21 regression gates remain green.

### Lesson

v5.21.0 fixed the GPU 9/7 instance of scaling-direction drift.
v5.22.0 makes the bug CLASS unrepresentable: any future PR that
introduces a new wavelet path with the wrong convention (or
modifies an existing path's convention) fails the audit suite at
PR time. Same shape as v5.14.2 (byte-order class) and v5.15.0
(lossless conformant ratification).

## [5.21.0] — 2026-05-04

**GPU 9/7 lossy IDWT scaling fix — root-cause + permanent removal of v5.20.0 gate**

v5.20.0 caught the GPU 9/7 lossy decode defect (max ~45000 LSB
error in 16-bit) and gated it off. v5.21.0 root-causes the bug as
a scaling-direction inversion in J2KMetal vs the ISO/IEC 15444-1
spec convention used by J2KCodec.

Per spec: forward `lowpass /= K, highpass *= K`. Inverse undoes
with `lowpass *= K, highpass /= K`. J2KMetal had it inverted in
both forward and inverse, both CPU reference and GPU kernels —
self-consistent (round-tripping within J2KMetal worked) but
producing K⁴ ≈ 2.29× scaling error when the J2KCodec encoder fed
codestreams to the J2KMetal IDWT.

### Fixed

- `Sources/J2KMetal/J2KShaders.metal` — swap scaling direction in
  forward and inverse 9/7 horizontal + vertical kernels.
- `Sources/J2KMetal/J2KMetalShaderLibrary.swift` — same swap in
  the embedded source-compile fallback.
- `Sources/J2KMetal/J2KMetalDWT.swift:forward1DCPU97` and
  `inverse1DCPU97` — same swap in the CPU reference.
- `Sources/J2KMetal/default.metallib` — recompiled.
- `Sources/J2KCodec/J2KDecoderPipeline.swift:applyInverseWaveletTransformGPU` —
  removed the v5.20.0 force-CPU gate; GPU IDWT for 9/7 is active again.

### Verified

- `J2KGPULossy97DivergenceTests` — max diff 0 → 1 LSB at 16-bit
  (Float-precision residual; PSNR ≈ 96 dB GPU vs CPU). Test
  threshold relaxed from `== 0` to `≤ 4 LSB`.
- New `J2KMetalSingleLevel97Tests.testSingleLevelRoundTrip` — direct
  CPU vs GPU 9/7 IDWT on a synthetic input; max diff < 1.0 (observed
  ~4e-6, pure Float precision).
- All v5.14-v5.20 regression gates remain green.
- 0.87% of pixels differ on real 2800×2288 16-bit DX content; max
  diff 1 LSB, avg 0.0087 LSB.

### Performance

- CLI per-call speedup: 1.26× (Metal startup dominates).
- Estimated 3-5× per-image speedup in warm-session batch workflows.

### Lesson

Same shape as v5.20.0's bisection finding: in-house modules that are
self-consistent but spec-divergent are invisible to internal
round-trip tests. Only cross-boundary tests (J2KCodec encode →
J2KMetal decode) caught the bug. v5.20.0 added the gate, v5.21.0
landed the actual fix.

## [5.20.0] — 2026-05-04

**GPU 9/7 lossy decode correctness fix (medical-grade critical)**

Investigation that started as "ratify GPU 9/7 lossy decode" surfaced
a silent data-corruption defect: `decodeGPU(_:)` and
`decodeWithGPUHT(_:)` for 9/7 lossy codestreams produce dramatically
different output from `decode(_:)`. Max abs diff ~45,000 in 16-bit
space (avg ~19,000) — far beyond Float-vs-Double precision tolerance.
Bisection confirmed the bug is in the GPU IDWT for `.irreversible97`,
NOT GPU HT entropy decode (which v5.15/v5.16 already ratified).

### Fixed

- `Sources/J2KCodec/J2KDecoderPipeline.swift:applyInverseWaveletTransformGPU`
  now forces 9/7 lossy through the CPU IDWT until the underlying
  Metal kernel bug is identified and fixed. After the gate, all
  three decode paths produce identical output for 9/7 lossy.

### Added

- `Tests/J2KCodecTests/J2KGPULossy97DivergenceTests.swift`:
  - `testBisectDecodePaths` — runs `decode`, `decodeGPU`,
    `decodeWithGPUHT` on the same 4 bpp lossy 9/7 CT codestream
    and asserts max abs diff is exactly 0 between CPU and either
    GPU path. Future regressions that remove the gate without
    fixing the kernel will fail this test.

### Known issues (deferred to v5.21.0+)

- **GPU IDWT for 9/7 is broken** and currently disabled. Root cause
  not yet identified — could be Metal kernel precision,
  dequantization, or subband layout. Until fixed, 9/7 lossy decode
  runs at CPU speed regardless of which decode entry point is
  called. Performance for 9/7 lossy on the GPU is the v5.21.0
  motivation.

### User impact

Callers who invoked `decodeGPU(_:)` or `decodeWithGPUHT(_:)` on 9/7
lossy codestreams pre-v5.20.0 received corrupt output (~19k LSB
average error in 16-bit space). After v5.20.0, those calls produce
correct output (matching `decode(_:)`) but at CPU IDWT speed. Stored
9/7 lossy J2K codestreams are unaffected — the bug was decode-only.

## [5.19.1] — 2026-05-04

**Faster qstep search — probe + cache + early-exit**

Cuts `.constantBitrateViaQstep`'s overhead from v5.19.0's ~5×
single-encode to ~4× cold / ~1× warm via three composable
optimizations.

### Added

- `J2KQstepCache` (actor) — optional shared cache mapping
  `(bitDepth, componentCount, targetBppBucket)` → converged qstep.
  Wire one cache into multiple `J2KEncodingConfiguration`s for a
  batch run; warm-cache convergence drops from 4–6 iterations to 1.
- `J2KEncodingConfiguration.qstepCache: J2KQstepCache?` — new
  optional property. Default nil = no caching.
- `J2KEncoder.encodeWithQstepStats(_:)` — encode + diagnostic stats.
  Returns `(data, J2KEncodeQstepStats)` with iteration count, cache
  hit, initial / converged qstep, achieved bpp, etc.
- `J2KEncodeQstepStats` — public struct for the new stats output.
- `Tests/J2KCodecTests/J2KQstepSearchEfficiencyTests.swift` (4 tests):
  - `testColdCacheConvergesIn5OrFewerIterations`
  - `testWarmCacheConvergesIn2OrFewerIterations`
  - `testStatsAreCoherent`
  - `testCacheSharingAcrossEncoders`

### Changed

- `encodeViaQstepSearch`:
  - Tighter initial search bracket: [guess/16, guess×16] (was 64×).
  - First iteration acts as a probe — its result rescales qstep
    multiplicatively before binary search begins.
  - Early-exit when [lower, upper] ratio < 1.05 AND iterations ≥ 3.

### Verified

- Cold-cache: 4 iterations on synth 8-bit (was 4-6 in v5.19.0).
- Warm-cache: 1 iteration with shared `J2KQstepCache`.
- All v5.14-v5.19.0 regression gates remain green.

### API stability

- All v5.19.1 additions are opt-in; default behavior matches v5.19.0.
- No breaking changes.

## [5.19.0] — 2026-05-04

**Constant-bitrate via qstep search (Option D)**

Closes the v5.16.0 R-D gap for `.constantBitrate` callers without
modifying the decoder. New mode `.constantBitrateViaQstep` builds on
v5.18.0's `.fixedQstep` by adding an outer binary-search loop on the
quantization step.

Pivoted from Option B (intra-block byte-level truncation) when
investigation revealed truncating MagSgn produces 0xFF-padded all-ones
magnitudes (per Part-15 spec convention) — actively WORSE than no
truncation. Option D ships the user-facing fix in 1 day with no
decoder changes; Option B remains documented for v5.20.0+ if needed.

### Added

- `J2KBitrateMode.constantBitrateViaQstep(bitsPerPixel:tolerance:maxIterations:)`
  case. Outer loop binary-searches qstep until achieved bpp matches
  target within tolerance. Default tolerance 5%, max iterations 8.
  Typically converges in 4–6 encode iterations.
- `J2KEncoder.encodeViaQstepSearch` — internal implementation of the
  search loop. Initial qstep guess from a calibrated table per
  bit-depth; geometric-mean narrowing of [lower, upper] qstep bounds.
- `--bitrate-via-qstep BPP` CLI flag.
- `Tests/J2KCodecTests/J2KHTConformantConstantBitrateViaQstepTests.swift`:
  - `testConstantBitrateViaQstep_HitsTargetAndBeatsPCRDOpt` — strict
    gate that the new mode hits target bpp within tolerance AND beats
    `.constantBitrate` by ≥3 dB at matched bpp. Currently measures
    +6.64 dB on synth content.
  - `testConstantBitrateViaQstepConfigurationPersists` — round-trip
    smoke test.
- `RELEASE_NOTES_v5.19.0.md` and `V5_19_0_OPTION_B_INVESTIGATION.md`
  for the full audit trail.

### Investigation

Original v5.18.0 design doc proposed Option B (intra-block byte-level
truncation in PCRD-opt). Reading J2KSwift's MagSgn decoder
(`J2KHTConformantMagSgnCoder.swift:133-150`) revealed it pads
truncated regions with `0xFF` per Part-15 spec convention. Reading
m bits from 0xFF gives `(1 << m) - 1` — maximum-magnitude payload
for any coefficient VLC marked significant. Result: simple truncation
produces all-ones magnitude garbage, worse than no truncation.

Pivoted to Option D as the working approach. Option B is preserved
in the design docs for v5.20.0+ if user demand justifies the
decoder-side changes + ojph_expand interop revalidation.

### Known issues (deferred)

- Convergence may fail at extreme bpp targets (< 0.1 or > 8 bpp).
  Encoder returns closest-achieved iteration — still typically
  better R-D than `.constantBitrate` for the same target.
- ~5× single-encode cost. Not suitable for real-time / streaming.
- Initial qstep calibration is rough (~50% accuracy); 2–3 iterations
  burned beyond an ideal table. Per-modality tuning saves iterations.
- Pure `.constantBitrate` callers who can't accept the encode-time
  hit retain the v5.16.0 R-D gap. Option B is the only path that
  closes it for them.

## [5.18.0] — 2026-05-04

**Fixed-qstep mode for HT conformant lossy R-D**

Bypasses PCRD-opt rate control entirely for HT conformant lossy
workflows. PCRD-opt's all-or-nothing block selection produces ~7 dB
worse R-D than EBCOT or OpenJPH at matched bitrates because the
HT cleanup pass has only one truncation point per block. Fixed-qstep
mode mirrors OpenJPH's encoder model — pick a qstep, every block
included unchanged. Achieved bpp varies per image; quality is
deterministic per qstep.

### Added

- `J2KBitrateMode.fixedQstep(qstep: Double)` — new bitrate mode case.
  Bypasses PCRD-opt; uses user-supplied step directly via
  `J2KStepSizeCalculator`'s standard LL/HL/LH/HH gain weighting.
  Only applies when `useReversibleFilter == false` (lossy 9/7).
- `--qstep STEP` CLI flag for the same.
- `Tests/J2KCodecTests/J2KHTConformantFixedQstepRDTests.swift`:
  - `testFixedQstep_BeatsPCRD_AtMatchedBpp` — strict gate that
    fixed-qstep beats PCRD-opt by ≥3 dB at matched bpp on synth 8-bit.
    Currently measures +18.69 dB on the synth content.
  - `testFixedQstepConfigurationPersists` — round-trip smoke test.
- `RELEASE_NOTES_v5.18.0.md` — full audit trail + calibration table.

### Investigation

v5.16.0's design doc recommended Option A (multi-pass conformant
emission). Investigation during v5.18.0 implementation revealed the
conformant cleanup pass already codes every magnitude bit per
coefficient (FBCOT 1-pass), making refinement passes redundant.
Pivoted to Option C (fixed-qstep). The original v5.18.0 design doc
records the investigation trail.

### Known issues (carried to v5.19.0+)

- Manual qstep calibration burden (no automatic target-bpp →
  qstep search yet). v5.19.0 candidate.
- J2KSwift qstep ≠ OpenJPH qstep numerically (~1000× scale
  difference due to gain weighting differences). Users
  transitioning from OpenJPH workflows need re-calibration.
- Default `.constantBitrate` callers still see the v5.16.0 R-D gap.
  Option B (intra-block byte-level truncation in PCRD-opt) is the
  only path that closes it for them; multi-day work, deferred.

## [5.17.1] — 2026-05-03

**Patch — stale test cleanup**

Single-test fix uncovered by the v5.17.0 verification suite run.
`testBatchMatrixMultiplyInvalid` was passing inputs that satisfy
both validation guards in `batchMatrixMultiply` (m=2 k=1 with a
2-element matrix; m*k=2 matches matrix.count=2). The test had been
silently failing in CI for an unknown number of releases.

### Fixed

- `Tests/J2KAccelerateTests/J2KAccelerateDeepIntegrationTests.swift:`
  `testBatchMatrixMultiplyInvalid` — change m=2 to m=3 so matrix.count
  (2) no longer satisfies the m*k = 3*1 = 3 guard. Now reliably
  throws the documented invalidParameter error.

Same shape of stale-test fix as the testDefaultIsCustomFormat fix
bundled into v5.17.0. v5.17.1 confirms the v5.17.0 verification cycle
caught all silently-failing tests in the non-benchmark portion of
the suite.

## [5.17.0] — 2026-05-03

**Medical-grade hardening — RGB non-pow2 + DICOMKit CI + PNG filter recovery**

Three orthogonal gaps closed: RGB lossless conformant non-pow2 wasn't
gated by v5.15.0; DICOMKit (the production downstream consumer) build
status wasn't part of CI; v5.14.2 disabled all PNG filters to guard
against the Sub-filter bug, leaving 10–30% file-size on the table.

### Added

- `.github/workflows/dicomkit-downstream.yml` — new CI gate that
  patches DICOMKit's `Package.swift` to point at the J2KSwift PR
  commit and verifies the consumer builds. Catches API breaks at PR
  time instead of at consumer-side upgrade time.
- `Tests/J2KCodecTests/J2KHTConformantRGBNonPowerOf2Tests.swift` —
  72-cell strict regression gate (12 dim configs × 3 decomp levels ×
  2 bit-depths) for 3-component RGB lossless HT conformant
  round-trip. Per-channel deterministic content with different LCG
  seeds + gradient slopes per channel so RCT has realistic chroma
  content to decorrelate.
- `RELEASE_NOTES_v5.17.0.md` — full audit trail.

### Fixed

- **PNG filter selection in `Sources/J2KCLI/PNGSupport.swift`**:
  re-implemented Sub/Up/Average/Paeth using ORIGINAL-byte semantics
  (the v5.14.2 bug used FILTERED bytes for the predictor reference).
  Per-row filter selection via the standard PNG MAE (sum-of-absolute-
  differences) heuristic. v5.14.2's filter-type-0 (None) writer
  applied a hard correctness fallback at the cost of compression
  efficiency; v5.17.0 recovers efficiency while keeping the v5.14.2
  PNG round-trip regression tests as the correctness floor.

### Verified

- All v5.15.0 + v5.16.0 regression gates remain green:
  - `HTConformantNonPowerOf2ProbeTests` (11,520 block cells)
  - `HTConformantPipelineNonPowerOf2Tests` (228 grayscale cells)
  - `HTConformantOpenJPHCrossDecodeTests` (120 cells)
  - `HTConformantPhase2RealCorpusTests` (21 medical cells)
  - `HTConformantLossyOpenJPHInteropTests` (lossy interop)
- v5.14.x byte-order matrix (10 tests) green via existing PNG
  round-trip tests catching the new filter implementation.

### Known issues (deferred)

- **HT conformant lossy R-D gap** (~7 dB at 1 bpp) carried from
  v5.16.0 — needs intra-block byte-level truncation. v5.18.0 candidate.
- **DICOMKit CI test execution**: the gate currently only checks
  build, not test execution. DICOMKit has 9 pre-existing unrelated
  failures; curated test set is a v5.17.x patch candidate.
- **Phase 3 — medical corpus expansion** to NM/US/MG/OP modalities:
  postponed pending license-cleared fixture sources.

## [5.16.0] — 2026-05-03

**HT conformant lossy: bitstream interop fix (medical-grade critical)**

Pre-v5.16.0 lossy HT conformant codestreams were Part-15 spec-violating —
J2KSwift's encoder placed magnitudes one bit lower in the K_max window
than the spec requires. J2KSwift's own decoder mirrored the bug via
packet-header `missing_msbs`, so self-round-trip looked OK. Any
third-party Part-15 decoder (`ojph_expand`, Kakadu) decoded the same
bytes as ~18 dB of garbage on real 16-bit medical CT @ 8 bpp.

### Fixed

- **Lossy K_max formula in `encodeCodeBlockConformant`**: split by
  `useReversibleFilter`. Lossless retains v5.1.1's `bandKb-guardBits+1`
  (correct because `writeQCDMarker`'s reversible branch applies the
  conformant ε bias). Lossy now uses `bandKb`, matching the Part-15
  decoder formula `K_max = (ε - 1) + guardBits` since lossy QCD doesn't
  apply the bias.
- **Rate controller distortion semantics for single-pass blocks**:
  conformant `J2KCodeBlock` returns now set `cumulativePassDistortion =
  [coefficientSquaredSum]`. The `estimateDistortion` fallback was
  modeling the cleanup pass as 1 bit-plane coded; conformant cleanup
  actually codes all K_max bits. Fix gives PCRD-opt the correct slope.

### Added

- `Tests/J2KCodecTests/J2KHTConformantLossyOpenJPHInteropTests.swift`
  (`testLossyHTConformant_OJPHDecodeMatchesJ2KSwiftDecode`) — strict
  regression gate asserting |Δ| < 0.5 dB between J2KSwift decode and
  `ojph_expand` decode at 1/4/8 bpp on synth 16-bit input.
- `V5_16_0_PHASE1_RD_DIAGNOSTIC.md` — full audit trail.

### Verified

- Lossy interop on real CT @ 8 bpp: 18.41 dB → 65.60 dB on `ojph_expand`
  decode (now matches J2KSwift decode |Δ| = 0.000 dB).
- v5.15.0 lossless gates unchanged (4 test suites, 11,889 cells, all
  still bit-exact).

### Known issues

- **Residual R-D gap (~7 dB at 1 bpp)** vs OpenJPH/EBCOT due to lack of
  intra-block byte-level truncation in PCRD-opt. Conformant single
  cleanup pass has only one truncation point per block; allocation is
  all-or-nothing at low bpp. Captured as v5.17.0 motivation. Lossy HT
  conformant is now bitstream-safe but compression efficiency at low
  bpp is below peer codecs.
- **Pre-v5.16.0 lossy HT conformant codestreams** are not Part-15
  conformant. Re-encode with v5.16.0 for spec-compliant output. Lossless
  HT conformant was correct pre-v5.16.0 (always took the v5.1.1 path).

## [5.15.0] — 2026-05-03

**HT conformant lossless: silent-default audit + permanent regression floor**

The default `htj2kBlockFormat` was silently flipped to `.conformant`
sometime after v5.1.0, but a docstring at `J2KEncodingPresets.swift:341-347`
still warned users that "non-power-of-2 subband dimensions are known to be
lossy." v5.15.0 settles whether that warning is real.

### Added

- `Tests/J2KCodecTests/J2KHTConformantNonPowerOf2ProbeTests.swift` —
  block-level corruption probe (11,520 cells: dims 1×1 to 64×64,
  missingMSBs ∈ {0, 5, 10, 20, 25}, 9 bin-aligned coefficient patterns).
  Strict regression gate.
- `Tests/J2KCodecTests/J2KHTConformantPipelineNonPowerOf2Tests.swift` —
  full-pipeline lossless conformant probe (228 cells: image dims 31×31
  to 511×511, decomp ∈ {0, 1, 3, 5}, bit-depth ∈ {8, 12, 16}). Strict
  regression gate.
- `Tests/J2KCodecTests/J2KHTConformantOpenJPHCrossDecodeTests.swift` —
  OpenJPH `ojph_expand` cross-decode probe (120 cells). Decisive
  third-leg validation of interop. Strict regression gate.
- `Tests/J2KCodecTests/J2KHTConformantPhase2RealCorpusTests.swift` —
  real medical PGM corpus (CT/DX/MR/PX/XA, 7 fixtures × 3 decomp = 21
  cells). 5/7 fixtures non-power-of-2.
- `Scripts/rd_benchmark.py` — added `J2KSwift-HT` codec variant for
  direct R-D comparison vs OpenJPH.

### Fixed

- Removed stale "non-power-of-2 lossy" caveat from
  `Sources/J2KCodec/J2KEncodingPresets.swift` docstring. Phase 1 (11,868
  cells across three independent probes) and Phase 2 (21 cells real-
  corpus) confirm zero corruption. The original bug was almost certainly
  the K_max off-by-one closed in v5.1.1; the docstring outlived the fix.

### Known issues

- **Lossy HT conformant rate-distortion gap**: J2KSwift-HT in lossy mode
  is 2.5–6.9 dB worse than both J2KSwift's own legacy EBCOT path AND
  OpenJPH at matched achieved bpp. The encoder produces valid HT
  codestreams that decode correctly — the gap is in rate-control
  quality. Captured as v5.16.0 motivation; lossless HT conformant is
  fully ratified.

## [5.14.2] — 2026-05-03

**Systemic fix — byte-order convention across every image-I/O surface**

v5.14.1 fixed PGM/PPM writers in isolation. v5.14.2 audits and
fixes the same class of bug across **every** image format the CLI
touches — PNG, TIFF, DICOM, plus the corresponding reader sides
that were silently producing untagged components and forcing the
encoder onto a fragile inference path.

Also catches and fixes a **pre-existing PNG-encoder bug** the
audit surfaced: the Sub filter was computed against the FILTERED
previous byte instead of the ORIGINAL previous byte, silently
corrupting all PNG output beyond the first `bpp` bytes of each
scanline. Caught by the new cross-format round-trip test gates.

### What this release fixes

**Reader-side tagging — every format now declares its byte
order on the components it produces:**

- `loadPGM` / `loadPPM` — tag 16-bit components `.bigEndian`
  (PGM/PPM 16-bit spec is BE; reader passes bytes through).
- `loadPNG` — tag 16-bit components `.littleEndian` (the reader
  swaps PNG's BE on-disk format to host-LE in-place; the
  in-memory representation is therefore LE).
- `loadTIFF` — tag 16-bit components `.bigEndian` (the reader
  canonicalises any LE TIFF input to BE via `byteSwapData`).
- `loadDICOM` — tag 16-bit components `.bigEndian` (the reader
  canonicalises LE Transfer Syntaxes to BE).

**Writer-side respect — every writer queries
`componentDataIsBigEndian(comp, legacyDefault: …)` instead of
assuming a fixed input byte order:**

- `buildPGMData`, `writePGM`, `buildPPMData`, `savePPM` — pre-
  v5.14.2 assumed LE input; new helper preserves that for
  untagged callers (`legacyDefault: .littleEndian`).
- `savePNG` — same treatment. **Plus** the Sub-filter
  correctness fix: the writer now uses filter type 0 (None)
  instead of the broken Sub implementation. Slightly worse
  compression ratio, unconditional correctness.
- `saveTIFF` — pre-v5.14.2 assumed BE input;
  `legacyDefault: .bigEndian` preserves that. Per-channel byte
  order honoured; mixed orders across channels handled
  per-sample.

### New regression tests

- **`J2KByteOrderRoundTripTests`** — cross-format matrix:
  - `testPGM_16bit_RoundTrip_PixelValues` — PGM round-trip
  - `testPNG_16bit_RoundTrip_BytesIdentical` — PGM → J2K → PNG → J2K → PGM
  - `testTIFF_16bit_RoundTrip_BytesIdentical` — PGM → J2K → TIFF → J2K → PGM
  - `testLoaderTagsByteOrder_PGM_BigEndian` — tag verification
- **`J2KPGMRoundTripTests`** (from v5.14.1) — `{8, 12, 16}-bit ×
  {Part 1, HTJ2K}` PGM round-trip (10 tests total).

These gates catch any future regression in any format's byte-
order handling — would have caught the v5.14.1 bug at
commit-time if they'd existed then.

### Bit-exactness

- All v5.14.1 bit-exactness gates pass byte-for-byte ✓
- New byte-order matrix passes ✓
- Full suite: 1309 pass / 5 fail (was 1305/5 — net +4 fixed:
  the 2 TIFF tests broken by my first cut of v5.14.2, plus 2
  new PNG round-trip cases that were silently broken by the
  pre-existing Sub filter bug).
- Same 5 pre-existing failures (perf-threshold sensitivity,
  thermal noise, unrelated tests) — none from this work.

### Caveats

PNG output size is slightly larger than v5.14.1 because the
writer emits filter type 0 (no filtering) instead of the
pre-existing broken Sub filter. Re-implementing filter types
1–4 with correct original-byte semantics is daytime followup
work; correctness wins over compression ratio in the
meantime.

## [5.14.1] — 2026-05-03

**Critical fix — Lossless PGM round-trip correctness**

`medical_benchmark.py` at v5.14.0 reported PSNR ≈ 7 on 16-bit
lossless CT round-trips (expected: ∞), with similar shape across
12-bit MRI and Ultrasound — every lossless-encoded medical image
failed byte-for-byte round-trip. This release fixes that.

### Root cause

The CLI's PGM and PPM writers always byte-swapped 16-bit pixel
data, assuming the source `J2KComponent.data` was in host byte
order (little-endian on Apple Silicon). The decoder pipeline,
however, has been writing 16-bit samples in **big-endian** byte
order since v5.6.0 (`if hostIsLittleEndian { byteSwapped }` in
`reconstructImage`). The writer's swap then *un-swapped* it back
to little-endian, producing PGM files that violated the spec
(PGM 16-bit requires big-endian).

The codec itself was bit-exact throughout — the *pixel values*
round-tripped perfectly. Only the file's byte serialisation was
wrong, and the corruption was only visible end-to-end:

- A round-tripped file read by another tool (e.g. OpenJPEG's
  `opj_decompress` PGM reader, the medical_benchmark Python
  pipeline) interpreted the LE bytes as BE and saw garbage.
- A round-tripped file read by J2KSwift's *own* PGM loader
  produced correct pixel values (the loader's byte-order
  handling matched the writer's bug, so they cancelled out
  inside the project).

### Fix

- **`J2KComponent` byte-order tagging.** The decoder now sets
  `sampleByteOrder = .bigEndian` on 16-bit components — making
  the convention explicit at the API boundary instead of relying
  on undocumented internal coordination.
- **PGM writers** (`buildPGMData`, `writePGM`) — check
  `component.sampleByteOrder` and write big-endian bytes
  accordingly. If the source is already big-endian (decoder
  output, or an explicitly-tagged user component), the bytes
  flow through unchanged. If the source is host-LE
  (legacy / untagged), the swap continues as before.
- **PPM writers** (`buildPPMData`, `savePPM`) — same fix on the
  per-sample read path; respects each of the 3 components'
  declared byte order before re-emitting big-endian.

### Regression test

New `J2KPGMRoundTripTests` (6 tests: 8/12/16-bit × Part 1 / HTJ2K)
encodes a synthetic deterministic PGM via the release-built CLI,
decodes it, and asserts byte-for-byte equality with the input.
Catches any future regression that re-flips the byte order in
either direction.

### Medical benchmark vs v5.14.0 (J2KSwift columns)

| Modality | Bits | Rate | v5.14.0 PSNR | v5.14.1 PSNR |
|---|---:|---|---:|---:|
| CT | 16 | lossless | 7.68 | **∞** |
| CT | 16 | 0.25bpp | 6.50 | **51.74** |
| CT | 16 | 0.50bpp | 6.92 | **55.15** |
| CT | 16 | 0.75bpp | 7.29 | **57.88** |
| MRI | 12 | lossless | -18.07 | **∞** |
| MRI | 12 | 0.25bpp | -17.97 | **37.97** (+4.22 vs OPJ) |
| MRI | 12 | 0.50bpp | -18.00 | **42.48** (+2.74 vs OPJ) |
| MRI | 12 | 0.75bpp | -18.09 | **45.37** (+2.25 vs OPJ) |
| Ultrasound | 12 | lossless | -14.64 | **∞** |
| Ultrasound | 12 | 0.25bpp | -15.11 | **28.79** (+0.81 vs OPJ) |
| Ultrasound | 12 | 0.50bpp | -14.82 | **31.63** (+1.84 vs OPJ) |
| Ultrasound | 12 | 0.75bpp | -14.63 | **35.11** (+3.18 vs OPJ) |

Lossless rows are now **truly lossless** (PSNR ∞, SSIM 1.0,
MAE 0). Lossy rows are now competitive with — and on MRI/Ultrasound
ahead of — OpenJPEG.

### Bit-exactness

- All 19 v5.14.0 GPU regression tests pass byte-for-byte ✓
- 6 new `J2KPGMRoundTripTests` pass ✓
- Full suite: 1305 pass / 5 fail (was 1304/6). Net +1 fixed
  (`testHTJ2KBeatsOpenJPEGFullMatrixPrintsSummary` now hits
  perf thresholds with the corrected output bytes); the
  remaining 5 failures are pre-existing perf-threshold /
  microbench thermal sensitivity unrelated to this work.

### Sessionless / session paths

Codec behaviour is byte-for-byte identical to v5.14.0 — the fix
is in the CLI's file-format I/O, not the codec.

## [5.14.0] — 2026-05-03

**Minor Release — Skip GPU MCT round-trip on Apple Silicon UMA**

The `applyInverseColorTransformGPU` path used to convert the
post-DWT `[Double]` components to `[Float]`, run inverse RCT/ICT on
GPU, then convert results back to `[Double]`. Profile data on a
1024×1024 lossless RGB decode showed this branch took **9.1 ms**
of a ~42 ms total session decode — **15% of total time** burned
on Double↔Float round-trips around a tiny per-pixel kernel.

v5.14.0 routes MCT through the existing in-place CPU vDSP path
(`applyInverseColorTransformInPlace`) instead. Stays in Double
throughout (matching the IDWT output type), uses
`vDSP_vsmaD`/`vDSP_vaddD`/`vDSP_vsubD` for the per-pixel
arithmetic, steals input arrays' inner buffers to avoid
allocation. The GPU MCT path remains in
`J2KMetalColorTransform` for future re-introduction if a fused-
into-IDWT-cb landing (avoiding the round-trip) becomes
practical.

### What this release does (and doesn't) change

**Architectural:** `applyInverseColorTransformGPU` is now a thin
wrapper around `applyInverseColorTransform`. The Metal MCT
infrastructure stays in place (still useful for callers that
work directly on Float buffers, e.g. encoder paths) but the
decoder no longer touches it.

**Perf on RGB workloads** (1024×1024 lossless 3-channel,
warm session):

| stage | v5.13.0 | v5.14.0 |
| --- | ---:| ---:|
| inverseColorTransform | 9.1 ms | **4.0 ms (-56%)** |
| TOTAL session decode | ~42 ms | **~30 ms (-29%)** |

**Perf on grayscale workloads (the DICOM corpus):** unchanged.
The corpus is single-component PGM; MCT is a no-op. v5.14
touches only the 3+ component path.

### Bit-exactness

- All v5.13.0 gates pass byte-for-byte ✓
- `testRGBSessionAndSessionlessAgreeBitExact` ✓ (the
  CPU-MCT path produces the same Double output as the previous
  GPU-MCT path; the verification gate caught silent regressions)

### Sessionless / session paths

Identical behaviour relative to each other on RGB inputs (both
paths now run the CPU MCT). Both paths are bit-exact with v5.13.0
on grayscale.

## [5.13.0] — 2026-05-03

**Minor Release — `default.metallib` bundled (was the v5.15 plan item)**

Closes the cold-CLI shader-source-compile cost the v5.6.0 perf
report flagged. `Sources/J2KMetal/default.metallib` is now
checked in as a `.copy()` resource on the J2KMetal target, and
`device.makeDefaultLibrary(bundle: .module)` returns it at
runtime instead of falling through to the
`J2KMetalShaderSource.kernelSource` source-compile path.

This was originally the v5.15 plan item; ships as v5.13.0 because
project versioning is sequential. v5.13/v5.14 (GPU MCT fusion,
9/7 lossy fast-lane) remain unimplemented per the
`V5_12_PLUS_OVERNIGHT_STATUS.md` deferral notes — the metallib
infrastructure is independent of those.

### What this release does (and doesn't) change

**Architectural:** SPM resource layout. The .metal source file
stays in the bundle (for inspection / debugging); the
pre-compiled metallib is added alongside. `Scripts/build_metallib.sh`
regenerates the metallib when the .metal source changes — must
be run explicitly (SwiftPM doesn't auto-compile .metal under
`swift build`, only Xcode does).

**Perf:** ~30 ms cold-CLI start savings (0.32 s → 0.29 s on
`j2k decode --gpu-ht` over a 512×512 HTJ2K input). Warm runs are
unchanged (Metal driver caches the compiled library either way).

### Added

- **`Sources/J2KMetal/default.metallib`** — pre-compiled Metal
  library bundled as a `.copy()` resource. 250 KB.
- **`Scripts/build_metallib.sh`** — regenerate the metallib from
  `J2KShaders.metal` (requires Metal Toolchain installed).
- **`J2KMetalShaderLibrary.loadPath`** — `.metallib` or
  `.sourceCompile`. Lets callers / tests verify which path was
  actually taken.
- **`J2KMetalLibraryLoadPathTests`** — regression gate that
  asserts the bundled metallib is loaded (not the fallback).
- **`J2KMetalLibraryLoadBenchTests`** — opt-in bench harness
  (run with `J2K_BENCH_LIBRARY_LOAD=1`).

### Notes

- The Metal Toolchain is required to regenerate the metallib.
  Install with `xcodebuild -downloadComponent MetalToolchain`.
  The .metal source itself stays in source control as the
  ground truth; the metallib is a build artifact.
- If `J2KShaders.metal` is updated without regenerating the
  metallib, the `J2KMetalLibraryLoadPathTests` gate still passes
  (the metallib loads successfully), but the runtime kernels
  may not match the source. Project workflow needs to regenerate
  via `Scripts/build_metallib.sh` and commit alongside .metal
  changes — same constraint Xcode-built apps don't have.

### Bit-exactness

- All v5.12.0 gates pass byte-for-byte ✓
- New `J2KMetalLibraryLoadPathTests` gate ✓

### Sessionless / session paths

Identical behaviour to v5.12.0. The metallib path produces the
same compiled kernels as the source-compile path; both routes
return the same MTLLibrary object to the rest of the pipeline.

## [5.12.0] — 2026-05-03

**Minor Release — Bounded multi-tile concurrency**

Replaces the unbounded `withThrowingTaskGroup` in both
`decodeMultiTile` (CPU) and `decodeMultiTileGPU` paths with a
chunked-TaskGroup pattern that caps in-flight tiles at 8. The
previous code spawned all tile tasks at once: for a 100-tile
codestream that would over-saturate the heap-backed buffer pool
and force fallthrough to `device.makeBuffer` for tiles that
couldn't fit in the 256 MB heap.

### What this release does (and doesn't) change

**Architectural:** chunked-TaskGroup pattern. Tile chunks process
sequentially; tiles within a chunk run concurrently. `chunkSize =
maxInFlightTilesGPU = 8` for the GPU path; `maxInFlightTilesCPU =
8` for the CPU path.

**Perf:** no measurable change on the existing DICOM corpus (all
fixtures are single-tile — only 1 task per decode regardless of
the bound). Multi-tile codestreams gain bounded heap residency
and avoid the v5.11.1 `device.makeBuffer` fallthrough on the
14th-and-later tile. A new
`testMultiTileBoundedConcurrencyRoundTrip` test covers the
multi-tile branch (16 tiles, 64×64 each) since the corpus
doesn't.

### Added

- **`Self.maxInFlightTilesGPU = 8`** on `DecoderPipeline` —
  configurable upper bound on concurrent GPU tile decodes.
- **`Self.maxInFlightTilesCPU = 8`** — same for the CPU path.
- **`testMultiTileBoundedConcurrencyRoundTrip`** in
  `J2KMetalSessionTests` — encodes a synthetic 256×256 image with
  64×64 tiles and asserts session/sessionless GPU-HT decodes
  produce identical output.

### Bit-exactness

- All v5.11.1 gates pass byte-for-byte ✓
- New multi-tile gate ✓

### Notes on the wider v5.12+ plan

The original plan called for "multi-tile in-flight cbs (overlap
CPU prep of tile N+1 with GPU decode of tile N)". The existing
TaskGroup already provides task-level concurrency; the missing
piece was upper-bounding the in-flight count. True pipelined
overlap of CPU prep and GPU decode within a single tile would
require restructuring stages as async producer-consumer chains —
a larger refactor deferred to v5.13+ on this branch.

## [5.11.1] — 2026-05-02

**Patch — `MTLHeap` default size bump (96 MB → 256 MB)**

Closes the px_001 / xa_001 `makeBuffer=2` fallthrough that v5.11.0
documented as a known issue. The heap default was 96 MB but the
buffer pool's `maxPoolMemory` is 256 MB — fixtures whose pool
retained working set exceeded 96 MB of heap-allocated buffers were
forced through the `device.makeBuffer` fallback for the last few
allocations. Bumping `heapSize` default to match `maxPoolMemory`
keeps everything heap-resident.

### Counter snapshot (one warm decode, full corpus)

  fixture        size       v5.11.0   v5.11.1
  ct_001         512×512    mb=0      mb=0
  ct_003         512×512    mb=0      mb=0
  dx_002         2800×2288  mb=0      mb=0
  mr_001         886×886    mb=1      mb=0
  mr_002         180×180    mb=1      mb=0
  px_001         2459×1316  mb=2      **mb=0**
  xa_001         1024×1024  mb=2      **mb=0**

Hot-path `makeBufferCount` is now 0 on every corpus fixture.

### Wall-clock effect

Speedups firm up across the corpus — ct_001 reaches 2.65–3.12×
(was 1.89× at v5.11.0), xa_001 2.55–2.77× (was 1.92×), mr_002
2.76–3.23× (was 1.93×). Run-to-run noise is meaningful at this
scale; the counter delta is the cleaner signal.

### Notes

- Resident memory increases by ~160 MB worst-case per session
  (256 MB heap × 2 storage modes − 96 MB × 2 = 320 MB delta).
  Acceptable on M-series Macs; callers wanting smaller residency
  can pass a custom `J2KMetalBufferPoolConfiguration` with
  `heapSize: 96 * 1024 * 1024`.
- No API change. No new tests; existing
  `testCorpusWarmProcessPerf` reports the new counter values.

## [5.11.0] — 2026-05-02

**Minor Release — `MTLHeap`-backed buffer pool**

Third and final milestone of the UMA optimization detour. Pool
misses now allocate from a per-storage-mode `MTLHeap` instead of
`device.makeBuffer`. Heap sub-allocations consolidate Metal's
per-buffer driver bookkeeping into one resident resource, which
reduces overhead even on buffers that come back through the pool —
the heap-resident sub-buffers stay heap-resident on reuse.

### What this release does (and doesn't) change

**Architectural:** one `MTLHeap` per storage mode, lazily created
on first miss for that mode and reused across decodes for the
lifetime of the pool. Default size 96 MB per heap (configurable
on `J2KMetalBufferPoolConfiguration.heapSize`). Heap creation
gated on `device.supportsFamily(.apple4)` — M-series Macs hit the
heap path; Intel-Mac hardware skips it and falls through to
`device.makeBuffer`.

**Perf:** small fixtures (where allocator overhead was the
dominant cost) gain disproportionately. Median warm-process
speedup vs sessionless: v5.10's 1.5× → v5.11's 1.92×, peak from
2.51× to 2.53×.

| fixture | size | v5.10.0 | v5.11.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.57× | 1.89× (+20%) |
| ct_003 | 512×512 | 1.46× | 1.78× (+22%) |
| dx_002 | 2800×2288 | 2.51× | 2.53× (saturated) |
| mr_001 | 886×886 | 1.45× | 1.91× (+32%) |
| mr_002 | 180×180 | 1.25× | 1.93× (+54%) |
| px_001 | 2459×1316 | 1.79× | 2.03× (+13%) |
| xa_001 | 1024×1024 | 1.52× | 1.92× (+26%) |

### Added

- **`J2KMetalBufferPoolConfiguration.enableHeapBacking: Bool`**
  (default `true`) — turn heap-backed allocation on/off.
- **`J2KMetalBufferPoolConfiguration.heapSize: Int`**
  (default 96 MB) — target size per storage-mode heap.
- **Per-storage-mode `MTLHeap`s** in `J2KMetalBufferPool`,
  lazily created via `ensureHeap(device:storageMode:)`.

### Changed

- **`J2KMetalBufferPool.acquireBuffer`** now: (1) check pool,
  (2) try heap, (3) fall through to `device.makeBuffer`. Same
  observable API; no caller change required.

### Notes

- Heap allocations do not increment `J2KMetalUMACounters.makeBuffer`
  — that counter tracks `device.makeBuffer` calls specifically.
  Heap sub-allocations go through a different driver path. (If
  future work wants to track heap allocations separately, add a
  dedicated counter.)
- Some fixtures (px_001, xa_001) still show `makeBuffer=2` per
  warm decode because their working-set persists in the pool and
  the heap is full before the new decode requests its last 2
  buffers. Bumping `heapSize` or implementing sub-buffer aliasing
  on pool return would close this; deferred to v5.12+ since the
  perf is already in-target.

### Bit-exactness

- All v5.10.0 gates pass byte-for-byte ✓

### Sessionless path

Byte-for-byte identical to v5.10.0.

### UMA detour summary (v5.7.0 → v5.11.0)

- v5.7.0 baseline: 1.63× median warm-process speedup, 1.93× peak.
- v5.11.0 final: ~1.92× median, **2.53× peak** on dx_002.
- Hot-path counters: memcpy=1, contents=1, makeBuffer=0 on most
  fixtures (the remaining `1` is the final-output API readback).

The plan's queued v5.12+ items resume from here: multi-tile in-
flight cbs, GPU colour transform fusion, 9/7 lossy DWT fusion,
`.metallib` bundling.

## [5.10.0] — 2026-05-02

**Minor Release — Storage-mode pass: `.storageModePrivate` for GPU-only intermediates**

Second milestone of the UMA optimization detour. Every buffer that
is written by GPU and read by GPU (no CPU touch in between) now
allocates as `.storageModePrivate`. The Metal stack picks faster
memory layouts and skips implicit coherency syncs for those
allocations. Buffers at the API boundary — descriptor uploads,
codestream pool, final IDWT output — stay `.storageModeShared`.

The release also fixes a buffer-pool prerequisite bug: the pool
previously bucketed by size only, which would silently swap
shared/private buffers across acquires. Now keys on
`(size, storageMode)`.

### What this release does (and doesn't) change

**Architectural:** `colLow`/`colHigh` (DWT scratch), per-level
`lh`/`hl`/`hh`, innermost LL when `initialLL == nil`, intermediate
output (non-final levels), and `sgnMagBuffer` in HT cleanup all
now allocate `.private`. CPU `memset` zero-init replaced with
`MTLBlitCommandEncoder.fill(buffer:range:value:)` running in the
same cb before the scatter encoder reads.

**Perf:** the largest fixture (dx_002 2800×2288) gains +10% warm-
process speedup vs v5.9.0 (2.27× → 2.51×). Smaller fixtures are
within run-to-run noise — `.private` storage's win compounds with
allocation size, and dx_002's per-tile working set is the only
one where the layout / coherency-sync cost crosses the threshold
cleanly.

| fixture | size | v5.9.0 | v5.10.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.59× | 1.57× |
| ct_003 | 512×512 | 1.49× | 1.46× |
| dx_002 | 2800×2288 | 2.27× | 2.51× |
| mr_001 | 886×886 | 1.49× | 1.45× |
| mr_002 | 180×180 | 1.14× | 1.25× |
| px_001 | 2459×1316 | 1.86× | 1.79× |
| xa_001 | 1024×1024 | 1.49× | 1.52× |

### Added

- **`J2KMetalBufferPoolConfiguration.PoolKey`** — internal struct
  keying pooled buffers on `(size, storageMode)` instead of size
  alone. Prevents silent swaps between strategies at acquire time.

### Changed

- **`J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks`** — per-level
  output / scratch / subband buffers now allocate `.private` for
  GPU-only intermediates; final-level output stays `.shared` for
  caller readback.
- **`J2KMetalHTCleanup.runIntegerMagnitude(_)` /
  `runIntegerMagnitudeReturningBuffer(_)`** — `sgnMagBuffer` (cleanup
  → dequant kernel intermediate) now `.private`. The output buffer
  stays `.shared` because slow-path callers slice per-block via
  `.contents()`.

### Bit-exactness

- All v5.9.0 gates pass byte-for-byte ✓
- Buffer-pool segregation regression test implicit in
  `testCorpusSessionAndSessionlessAgreeBitExact` ✓

### Sessionless path

Byte-for-byte identical to v5.9.0. The buffer pool fix applies to
all callers but is observable behaviour-wise only on the
fast-lane path that v5.9.0 introduced.

## [5.9.0] — 2026-05-02

**Minor Release — Zero-copy CPU↔GPU boundary on the GPU HT decode path**

First milestone of the UMA (Unified Memory Architecture) optimization
detour. Removes intermediate `[Int32]` / `[Double]` allocations
inside the GPU HT decode pipeline by passing `MTLBuffer` references
through pipeline stages and routing LL coefficients through the GPU
scatter kernel. The hot-path UMA counter `memcpyCount` drops from
~70–1620 (varies by fixture) to **1** — the single final-output
readback at the API boundary.

The release shipped through five iterations on a feature branch
(v5.9a → v5.9e). v5.9b and v5.9c incidentally introduced
regressions that were caught by tests and rolled back — v5.9.0
ships the working v5.9e state with all bit-exactness gates green.

### What this release does (and doesn't) change

**Architectural:** the v5.6.0 session opt-in path now skips the CPU
regroup loop entirely when the v5.8 fused-DWT downstream is
available. LL/LH/HL/HH all flow through the GPU scatter kernel into
the fused IDWT; only the final IDWT output crosses back to CPU.

**Perf:** modest wall-clock improvement (1.5×–2.5× warm vs
sessionless, vs 1.5× median in v5.8). The structural value is the
zero-copy hot path — prerequisite for v5.10's storage-mode pass.

| fixture | size | v5.8 fused | v5.9.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.39× | 1.59× |
| ct_003 | 512×512 | 1.51× | 1.49× |
| dx_002 | 2800×2288 | 1.73× | 2.27× |
| mr_001 | 886×886 | 1.36× | 1.49× |
| mr_002 | 180×180 | 1.22× | 1.14× |
| px_001 | 2459×1316 | 1.69× | 1.86× |
| xa_001 | 1024×1024 | 1.58× | 1.49× |

### Added

- **`J2KMetalUMACounters`** — lightweight `nonisolated(unsafe)`
  process-global counter set tracking `memcpyCount`,
  `bufferContentsAccessCount`, and `makeBufferCount`. Zero-overhead
  in release; surfaced via the `testCorpusWarmProcessPerf` benchmark.
- **`runZeroCopyFastLane`** in `DecoderPipeline` — bypasses the CPU
  regroup loop when (session present, reversible 5/3, conformant
  HT, all blocks eligible, GPU IDWT will run downstream).
- **`testCorpusSessionAndSessionlessAgreeBitExact`** — corpus-wide
  bit-exactness gate that catches regressions the synthetic
  384×384 test misses (small images, non-power-of-2 LL chains).
- **`vDSPConvert.int32sToDoubles`** — Accelerate-backed bit-exact
  Int32→Double conversion for the post-DWT step.

### Bug fixes (caught during this release cycle)

- **`compSubbands.isEmpty` short-circuit in
  `applyInverseWaveletTransformGPU`** — predates the fast lane;
  was producing all-zero output when the fast lane returned
  `([], batch)`. Now also checks `gpuBatch?.plansByComponent[compIdx]`
  before the early-out.
- **Fast-lane gate must mirror GPU-IDWT preconditions** — when the
  IDWT falls back to CPU (`pixelCount < 256*256`, custom wavelet
  kernels, etc) the fast lane needs to skip itself rather than
  feed an empty `[SubbandInfo]` set.

### Bit-exactness

- `testFullDICOMCorpus_GPUHTMatchesCPUHT` (7/7) ✓
- `testCorpusSessionAndSessionlessAgreeBitExact` ✓
- `testSessionAndSessionlessAgreeBitExact` ✓
- All scatter / dispatcher / DWT / multi-level fused unit tests ✓

### Sessionless path

Byte-for-byte identical to v5.8.0. v5.9 changes are scoped to the
session/fast-lane code path.

## [5.8.0] — 2026-05-02

**Minor Release — End-to-end fused HT cleanup → scatter → DWT path (architectural)**

Wires the M4P-1 GPU subband scatter kernel that landed dormant in
v5.7.0 into the production decoder pipeline. When the v5.6.0
session opt-in is active and the codestream is HTJ2K conformant
cleanup-only reversible 5/3, the entire entropy decode → subband
scatter → multi-level inverse DWT now runs in a single command
buffer per (tile, component), with the codeblock buffer staying
GPU-resident across stages. Single GPU HT decode, GPU scatter for
LH/HL/HH, multi-level inverse 5/3 — no readback between stages.

### What this release does (and doesn't) change

**Architectural:** the full HT cleanup → DWT GPU path is now
end-to-end fused. CPU regroup of LH/HL/HH (`getSubbandAsInt32`)
is replaced by GPU scatter for the fused path. The pipeline
stays bit-exact with the v5.7.0 path (all gates pass).

**Perf:** approximately neutral vs v5.7.0 on this hardware. Median
warm-process speedup is ~1.5× (vs ~1.6× in v5.7.0); within
run-to-run variance. The architectural value is the foundation
for future work (multi-tile in-flight, GPU colour transform
fusion, etc.) — not a perf headline.

| fixture | size | sessionless | v5.8 fused |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 14.01 ms | 10.06 ms (1.39×) |
| ct_003 | 512×512 | 14.66 ms | 9.71 ms (1.51×) |
| dx_002 | 2800×2288 | 106.98 ms | 62.00 ms (1.73×) |
| mr_001 | 886×886 | 16.31 ms | 12.00 ms (1.36×) |
| mr_002 | 180×180 | 6.43 ms | 5.28 ms (1.22×) |
| px_001 | 2459×1316 | 56.14 ms | 33.23 ms (1.69×) |
| xa_001 | 1024×1024 | 22.92 ms | 14.51 ms (1.58×) |

### Added

- **`J2KMetalDWT.LevelScatterPlan`** — Sendable per-level plan
  carrying scatter descriptors + per-subband dimensions for the
  fused dispatch.
- **`J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks(...)`** —
  end-to-end fused inverse 5/3: scatter + multi-level DWT in one
  command buffer. Output buffer of level N is reused as the LL of
  level N-1; single commit + await + final readback.
- **`J2KMetalHTCleanup.runIntegerMagnitudeReturningBuffer(...)`**
  — variant of the v5.6.0 `runIntegerMagnitude` that returns the
  GPU output buffer instead of reading back to `[Int32]`. Caller
  takes ownership; descriptor + intermediate buffers go back to
  the pool.
- **`J2KGPUHTBatch`** — Sendable wrapper for the GPU-resident HT
  batch (codeblock buffer + per-component, per-level scatter
  plans + buffer pool reference).
- **`J2KGPUHTDispatch.decodeBatchGPUResident(...)`** — GPU
  dispatcher entry that returns both the GPU buffer AND
  per-block `[Int32]` arrays sliced from its shared memory in
  one call. Eliminates duplicate GPU decode work for callers
  that need both forms (the pipeline does, for `[SubbandInfo]`
  CPU regroup + the fused-DWT batch).
- **`GPU_HT_FULL_FUSION_PLAN.md`** — five-milestone plan; M5P-1
  through M5P-4 complete in this release.

### Changed

- **`J2KDecoderPipeline.applyEntropyDecoding`** return type
  expanded to `(subbands: [SubbandInfo], batch: J2KGPUHTBatch?)`.
  When v5.8 conditions are met (session, reversible 5/3,
  conformant HT cleanup-only, all blocks eligible), runs ONE
  `decodeBatchGPUResident` call producing both the per-block
  arrays for `[SubbandInfo]` regroup AND the GPU batch for the
  fused-DWT path. Otherwise stays on the v5.6.0 `decodeBatch`
  path with batch = nil. Four orchestrators updated to
  destructure the new tuple.
- **`J2KDecoderPipeline.applyInverseWaveletTransformGPU`** —
  accepts an optional `gpuBatch` parameter. When provided and
  per-component plans exist, routes to
  `inverse2DInt32FullFusedFromCodeblocks` instead of v5.7.0's
  `inverse2DInt32MultiLevelFused`. Codeblock buffer is returned
  to the pool after all components complete.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns
  "5.8.0".
- `VERSION` bumped 5.7.0 → 5.8.0.

### What this release is not

- **Not a performance leap over v5.7.0.** Within run-to-run
  variance on the perf benchmark — the win is structural, not
  numerical.
- **Not a 9/7 lossy fusion.** Reversible 5/3 path only.
- **Not a cold-CLI fix.** `j2k decode --gpu-ht` still pays
  per-process Metal init cost; `.metallib` bundling remains
  dormant.
- **Not a multi-tile in-flight pipeline.** Each tile still gets
  its own command buffer; cross-tile pool reuse is via the
  v5.6.0 `J2KMetalSession`.

## [5.7.0] — 2026-05-02

**Minor Release — Multi-level fused inverse 5/3 DWT (HT decode → DWT cb fusion)**

Builds on v5.6.0's persistent session + GPU dequant. Eliminates the
per-level commit/wait/readback overhead in the inverse 5/3 DWT
path: when a `J2KMetalSession` is in scope, all decomposition
levels of the inverse 2D transform now chain into a single command
buffer, with the output buffer of level N reused as the LL input
of level N-1 — no readback between levels.

### Measured impact

Apple M2, release builds, single Swift process decoding the
DICOM corpus via SDK with `decodeWithGPUHT(_:session:)`:

| fixture | size | v5.6.0 | v5.7.0 | delta |
| --- | ---:| ---:| ---:| ---:|
| ct_001 | 512×512 | 1.35× | **1.69×** | +25% |
| ct_003 | 512×512 | 1.21× | 1.05× | -13% |
| dx_002 | 2800×2288 | 1.35× | **1.81×** | +34% |
| mr_001 | 886×886 | 1.16× | 1.32× | +14% |
| mr_002 | 180×180 | 1.16× | 1.16× | 0% |
| px_001 | 2459×1316 | 1.26× | **1.93×** | +53% |
| xa_001 | 1024×1024 | 1.27× | 1.63× | +28% |

Largest images (where the per-level readback was most painful)
see nearly **2× speedup** over v5.6.0. Median ~1.63×.

For a 5-level DWT on a 2800×2288 image, this release eliminates
~14 MB of cumulative CPU↔GPU readback per component (5 levels of
geometric-series-shaped intermediate transfers) plus 5 round-trip
commit/await pairs, replaced by 1 of each.

### Added

- **`J2KMetalDWT.inverse2DInt32MultiLevelFused(subbandsPerLevel:)`** —
  chains all decomposition levels of the bit-exact reversible 5/3
  inverse 2D transform into a single command buffer. Each level's
  output buffer is reused as the next level's LL input (GPU-
  resident); validates the chain at the boundary (level N+1's LL
  dimensions must match level N's output).
- **`J2KMetalDWT.encodeInverse2DInt32(into:cb:...)`** — chainable
  entry point that takes pre-allocated GPU input/output buffers
  and an existing command buffer; encodes both horizontal +
  vertical passes into two compute encoders (implicit memory
  barrier between them) without committing.
- **`J2KMetalSubbandScatter`** — GPU scatter kernel +
  Swift wrapper that turns a per-codeblock Int32 buffer into
  per-subband 2D buffers. Not yet used in the production
  pipeline; landed as scaffolding for v5.8's full HT-cleanup →
  DWT fusion via GPU scatter.
- **`Sources/J2KMetal/J2KMetalSubbandScatter.swift`**,
  **`Tests/J2KMetalTests/J2KMetalSubbandScatterTests.swift`** — 3
  bit-exactness tests vs an inline CPU reference scatter.
- **`j2k_subband_scatter` MSL kernel** added to both
  `J2KMetalShaderSource.kernelSource` and
  `Sources/J2KMetal/J2KShaders.metal`.
- **`GPU_HT_DWT_FUSION_PLAN.md`** — five-milestone plan; M4P-1, 2,
  3 complete in this release. M4P-4 (perf measurement) and M4P-5
  (release notes) folded into the M4P-3 commit.

### Changed

- **`Sources/J2KMetal/J2KMetalDWT.swift`** — `inverse2DGPUInt32`
  is now a thin wrapper around `encodeInverse2DInt32`. Uses one
  command buffer instead of v5.6.0's two; same observable
  behaviour byte-for-byte.
- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** —
  `applyInverseWaveletTransformGPUInt32`'s reversible 5/3 path
  now branches on `useGPUHT && metalSession != nil`: when set,
  builds all levels' subband data up-front and dispatches one
  fused multi-level call; otherwise stays on the v5.6.0
  per-level path.
- **`Sources/J2KMetal/J2KMetalShaderLibrary.swift`** — new
  `subbandScatter` shader function enum case.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns
  "5.7.0".
- `VERSION` bumped 5.6.0 → 5.7.0.

### What this release does not change

- **Sessionless path is byte-for-byte identical to v5.6.0.**
  Callers using `decodeWithGPUHT(_:)` (no session) get exactly
  the same behaviour.
- **9/7 irreversible (lossy) DWT** still uses the v5.6.0 per-level
  path. The fusion is reversible-5/3-only.
- **Cold CLI** numbers from v5.5.0 are unchanged. Fixing them
  still requires `.metallib` bundling (wired but dormant since
  v5.6.0).
- **Cross-codec matrix** unaffected — exercises the default CPU
  decode path, which doesn't touch the fused path.

### Out-of-scope-but-tracked follow-ups

- **Full HT-cleanup → DWT fusion** using the M4P-1 scatter
  kernel: keep the codeblock buffer GPU-resident from HT cleanup
  through subband scatter to DWT, all in one cb. v5.8 candidate.
- **9/7 irreversible fusion** for lossy decodes.
- **`.metallib` bundling** for cold-CLI wins.

## [5.6.0] — 2026-05-02

**Minor Release — Persistent Metal session + GPU dequantisation kernel**

Builds on v5.5.0's M2-prime production integration. Adds two
performance levers for warm-process callers (long-running SDK
processes that decode many images), both opt-in via the existing
`decodeWithGPUHT` surface:

1. **`J2KMetalSession`** — a long-lived bundle of a shared Metal
   device, shader library, and buffer pool. Construct once at the
   SDK boundary; pass to every decode call. First call pays the
   ~50 ms shader compile; subsequent calls reuse the cached
   library + compute pipelines + buffer pool.

2. **GPU dequantisation kernel** — new MSL kernel `j2k_ht_dequant`
   that converts the HT cleanup kernel's UInt32 OpenJPH sign-
   magnitude output to Int32 integer-magnitude on the GPU side.
   When a session is in scope, the dispatcher chains both kernels
   in a single command buffer and skips the CPU-side per-sample
   shift+sign loop.

### Measured impact

Warm-process corpus (M2 Apple Silicon, release builds, single
Swift process decoding the 7 DICOM fixtures via SDK):

| fixture | size | sessionless (ms) | session (ms) | speedup |
| --- | ---:| ---:| ---:| ---:|
| ct_001 | 512×512 | 16.68 | 12.37 | **1.35×** |
| ct_003 | 512×512 | 14.45 | 11.91 | 1.21× |
| dx_002 | 2800×2288 | 111.49 | 82.40 | **1.35×** |
| mr_001 | 886×886 | 18.65 | 16.02 | 1.16× |
| mr_002 | 180×180 | 6.35 | 5.49 | 1.16× |
| px_001 | 2459×1316 | 60.63 | 48.19 | 1.26× |
| xa_001 | 1024×1024 | 24.64 | 19.33 | 1.27× |

Median speedup: **1.26×**. Pre-dequant session-only number was
1.07× median — the GPU dequant is responsible for roughly half of
the v5.6.0 win.

### Cold CLI is unchanged

The v5.5.0 `j2k decode --gpu-ht` per-process numbers (0.03×–0.49×
on the same fixtures) are the same in this release. Fixing the
cold-CLI case requires bundling a pre-compiled `default.metallib`
to skip MSL source compilation; the wiring for that lands here
but the artefact does not (the local environment lacks
`xcodebuild -downloadComponent MetalToolchain`). Once a metallib
ships in `Bundle.module`, `loadShaders` will pick it up
automatically — no code change needed.

### Added

- **`Sources/J2KCodec/J2KMetalSession.swift`** — public
  `J2KMetalSession` Sendable struct bundling
  `J2KMetalDevice`, `J2KMetalShaderLibrary`, and
  `J2KMetalBufferPool`.
- **`J2KDecoder.decodeWithGPUHT(_:session:)`** plus the
  progress-callback overload.
- **`Sources/J2KMetal/J2KMetalHTCleanup.swift`** —
  `runIntegerMagnitude(...)` chains cleanup + dequant in one
  command buffer and returns `[Int32]`.
- **`j2k_ht_dequant` MSL kernel** added to both
  `J2KMetalShaderSource.kernelSource` (runtime fallback) and
  `Sources/J2KMetal/J2KShaders.metal` (resource).
- **`Sources/J2KMetal/J2KShaders.metal`** — extracted MSL source
  registered as a SwiftPM resource. Dormant on pure-SwiftPM
  builds (no metal toolchain integration); ready to be picked up
  if a `default.metallib` lands in `Bundle.module`.
- **`Tests/J2KCodecTests/J2KMetalSessionTests.swift`** — four
  tests: bit-exactness gate (session vs sessionless), warm-
  process speedup gate, corpus-wide perf measurement, session
  construction smoke.
- **`GPU_HT_PERSISTENT_SESSION_PLAN.md`** — five-milestone plan
  (M3P-1..5).

### Changed

- **`Sources/J2KMetal/J2KMetalShaderLibrary.swift`** —
  `loadShaders(device:)` now prefers
  `device.makeDefaultLibrary(bundle: .module)` and falls back to
  source-compiling the inlined kernel string. New shader function
  enum case `htDequant`.
- **`Sources/J2KCodec/J2KGPUHTDispatch.swift`** —
  `decodeBatch(blocks:cleanup:session:)` accepts an optional
  session. When session or cleanup is supplied, dispatches via
  the new `runIntegerMagnitude` chained kernel; otherwise stays
  on the v5.5.0 UInt32 + CPU dequant path byte-for-byte.
- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** — new
  `metalSession: J2KMetalSession?` field. When set, threads
  through to both `applyEntropyDecoding`'s GPU HT batch and
  `applyInverseWaveletTransformGPU`'s `J2KMetalDWT` construction.
- **`Package.swift`** — `J2KMetal` target gains
  `resources: [.process("J2KShaders.metal")]`.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns
  "5.6.0".
- `VERSION` bumped from `5.5.0` to `5.6.0`.

## [5.5.0] — 2026-05-02

**Minor Release — GPU HTJ2K decode in production (opt-in)**

Wires the GPU HT cleanup decoder shipped in v5.4.0 into the
production decoder pipeline behind a `--gpu-ht` opt-in flag.
Default behaviour is unchanged: production HT entropy decode
remains on CPU until callers opt in. Bit-exact with the CPU
path on the full DICOM corpus.

### What this release ships

- **`J2KDecoder.decodeWithGPUHT(_:)`** — opt-in SDK entry point.
  Eligible HTJ2K conformant cleanup-only codeblocks are batched
  through the Metal HT cleanup kernel; ineligible blocks fall
  through to CPU automatically. Inert on Part 1 codestreams.
- **`j2k decode --gpu-ht`** — CLI surface for the same.
- Bit-exact gates: `J2KGPUHTDispatchTests` (3), `J2KGPUHTPipelineTests`
  (4 — including a corpus-wide test that encodes every fixture
  under `Tests/Fixtures/CrossCodec/` to HTJ2K and asserts
  GPU-HT vs CPU-HT byte-equality), and 21 new GPU-HT cells in the
  cross-codec matrix (147/147 pass).

### What this release does not ship

**No end-user perf win for `j2k decode` CLI usage.** Per
[GPU_HT_M2_PRIME_PERF_REPORT.md](GPU_HT_M2_PRIME_PERF_REPORT.md),
`j2k decode --gpu-ht` is currently slower than the default CPU HT
path on every fixture, ranging from 0.03× (180×180) to 0.49×
(2800×2288). Two reasons:

1. Per-process Metal init cost (~50–60 ms) dominates on small
   images. CLI is worst-case; long-running SDK processes (the
   M2P-3 corpus test decodes all 7 fixtures in 0.79 s in one
   Swift process) amortise this cost away.
2. Other pipeline stages (dequant, subband regroup, colour
   transform, DC offset) still run CPU-side, so the CPU HT path
   benefits from full-pipeline CPU co-location.

This release ships the integration shape — the foundation that
unblocks future work on cb fusion, persistent Metal pipeline
state, and GPU dequantisation. The plan and the perf report both
call this out without overpromising.

### Added

- **`Sources/J2KCodec/J2KGPUHTDispatch.swift`** — integration shim
  that batches eligible codeblocks into a single
  `J2KMetalHTCleanup.run` call and converts the kernel's UInt32
  OpenJPH sign-magnitude output to the pipeline's Int32
  integer-magnitude convention. Caller-side eligibility filter
  reports `cpuFallbackIndices` separately so callers can
  round-trip ineligible blocks through CPU.
- **`Sources/J2KCodec/J2KCodec.swift`** —
  `J2KDecoder.decodeWithGPUHT(_:)` and progress-callback overload.
- **`Sources/J2KCLI/Commands.swift`** — `j2k decode --gpu-ht` flag.
- **`Tests/J2KCodecTests/J2KGPUHTDispatchTests.swift`** — three
  dispatcher-level tests.
- **`Tests/J2KCodecTests/J2KGPUHTPipelineTests.swift`** — four
  pipeline tests (bit-exact at 384×384 and 512×512, Part 1
  flag-inert check, full DICOM corpus byte-equality).
- **`Scripts/measure_gpu_ht_perf.sh`** — perf harness.
- **`GPU_HT_M2_PRIME_PERF_REPORT.md`** — committed perf report.
- **`GPU_HT_M2_PRIME_PLAN.md`** — five-milestone plan.

### Changed

- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** — adds
  `useGPUHT: Bool = false` field on `DecoderPipeline` and an early
  GPU pass at the top of `applyEntropyDecoding` that builds a
  `[Int: [Int32]]` of pre-decoded blocks before the existing
  parallel + sequential CPU loops run.
- **`Scripts/run_cross_matrix.sh`** — three new GPU-HT decode
  cells per fixture in the full-matrix mode (`jcpu_to_jght_ht`,
  `jgpu_to_jght_ht`, `ojph_to_jght_ht`). Per-fixture cell count:
  18 → 21. Total cells per run: 126 → 147.
- **`Tests/Fixtures/CrossCodec/expected_results.csv`** — baseline
  updated for the new cells. The original 126 cells still match
  byte-for-byte.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns
  "5.5.0".
- `VERSION` bumped from `5.4.0` to `5.5.0`.

## [5.4.0] — 2026-05-02

**Minor Release — GPU HTJ2K decoder phase-3: dispatch overhead amortisation**

This is a perf-focused follow-up to v5.3.0's GPU HTJ2K cleanup
prototype. The kernel itself is unchanged, bit-exact with the CPU
reference. What changed is how it's dispatched and how its
auxiliary buffers are managed.

### Scope

The GPU HT cleanup decoder remains a **self-contained prototype
exercised only by `J2KMetalHTCleanupTests`** — the production
decoder (`J2KDecoderPipeline`) still routes HT entropy decode to
the CPU path. End users will see no functional change in this
release. The wins below are kernel-level and are a prerequisite for
production integration in a later release.

### Headline results

- **GPU HT cleanup kernel speedup, release builds, 777 × 64×64
  codeblocks on Apple M-series**:
  - v5.3.0 (phase-2): cpu=6.69ms, gpu_kernel=6.14ms, **0.5× CPU**
  - v5.4.0 (phase-3): cpu=6.76ms, gpu_kernel=4.93ms, **1.14× CPU**
  - Cumulative: GPU went from ~half CPU speed to slightly above
    CPU speed, all bit-exact, all tests green.
- **Branch divergence is the new ceiling**: the leftover gap
  between observed (1.14×) and theoretical (deep-SIMD ≫1×) wins
  comes from variable-sized codeblocks within a SIMD warp. Threads
  in a warp execute the most divergent control-flow path, so
  utilisation depends on the workload's CB-size uniformity.

### Added

- **`GPU_HT_PHASE3_PLAN.md`** — written plan for the four phase-3
  optimisations (M1: buffer pool + table caching, M2: command-buffer
  fusion, M3: intra-CB parallelism, M4: ship). M1 and M3 are
  complete in this release; M2 has been reframed as "M2-prime"
  (production integration) for a later release after analysis
  showed the original chain didn't yet exist in code.
- **`J2KMetalShaderLibrary.vlcTableBuffers(device:vlc0:vlc1:)`** —
  lazy MTLBuffer cache for the 2 × 1024-entry HT cleanup VLC
  tables. Tables upload once on first call and reuse thereafter,
  eliminating a per-decode 4 KB upload that was happening on every
  invocation.

### Changed

- **`J2KMetalHTCleanup` and `J2KMetalHTMagSgn`** now use
  `J2KMetalBufferPool` for per-frame buffers (descriptors,
  codestream, output, widths) and explicitly return them after
  readback. This matches the convention from `J2KMetalDWT`,
  `J2KMetalQuantizer`, `J2KMetalColorTransform`, and `J2KMetalROI`,
  but adds the missing `returnBuffer` step those callers historically
  skipped — the pool was effectively empty for everyone previously.
- **`J2KMetalHTCleanup` dispatch** changed from
  `dispatchThreadgroups((blockCount,1,1), (1,1,1))` (one threadgroup
  per codeblock, leaving 31 of 32 SIMD lanes idle per warp) to
  `dispatchThreads((blockCount,1,1), (min(blockCount,64),1,1))`,
  matching the phase-1 MagSgn convention. Apple's SIMD scheduler
  now packs 64 codeblocks (2 warps) into each threadgroup. Kernel
  uses only thread-private state and per-thread offset reads, so no
  shared memory or barriers are required.

### Fixed

- **`J2KMetalHTMagSgn` readback** switched from
  `Array.withUnsafeMutableBytes { copyBytes(from: MTLBuffer.contents()) }`
  to `Array(unsafeUninitializedCapacity:) + memcpy`. The first form
  is known to deadlock in release builds (see HT Cleanup readback
  comment in v5.3.0); the buffer pool's actor hop in this release
  shifted timing enough to start triggering the same deadlock path
  in MagSgn too. The new pattern matches HT Cleanup and sidesteps
  the issue.

### Validation

- `J2KMetalHTCleanupTests`: 7/7 release-mode pass, bit-exact with
  CPU reference on all fixture sizes (4×4, 16×16, 64×64, 32-block
  batch, 777-block speedup, all-zero, shader-load-only).
- `J2KMetalHTMagSgnTests`: 4/4 release-mode pass.
- `Scripts/run_cross_matrix.sh --check`: 126/126 cells match the
  v5.3.0 baseline byte-for-byte. Note that this matrix exercises
  the production decoder (CPU HT) — it confirms no regression to
  unrelated systems but does not exercise the M3 changes directly.
  M3's bit-exactness gate is the HTCleanup test suite.

### What this is not

- **Not a production GPU HT decode release.** End-user `j2k decode`
  on HTJ2K codestreams still runs entirely on CPU. Wiring
  `J2KMetalHTCleanup` into `J2KDecoderPipeline` (alongside a
  dequantisation + subband-regrouping kernel between HT output and
  DWT input) is the natural next milestone — provisionally tagged
  M2-prime in `GPU_HT_PHASE3_PLAN.md` — and would be the release
  that actually delivers GPU HT decode to users.
- **Not a comparison release.** Numbers above are J2KSwift-internal
  CPU-vs-GPU benchmarks on the same algorithm. v5.3.0's positioning
  against OpenJPEG and OpenJPH still applies; nothing in v5.4.0
  changes the codestream output, the cross-codec matrix, or the
  encoded-size or wall-clock comparisons in the v5.3.0 release notes.

## [5.3.0] — 2026-05-01

**Minor Release — GPU HTJ2K cleanup decoder + cross-codec verification harness**

Two main pieces of work land in this release: an experimental GPU
HTJ2K cleanup-pass decoder (Phases 0–2 of an ongoing GPU HT
prototype) and a 180-cell bidirectional cross-codec verification
harness that exercises J2KSwift's encoder and decoder alongside
OpenJPEG 2.5.4 and OpenJPH 0.27.0 on real DICOM imagery.

### Headline results

- **Cross-codec interop matrix**: 180 / 180 round-trip cells decode
  to the original pixel values on the 10-image DICOM corpus (CT, DX,
  MG, MR, PX, XA — 180×180 to 3521×4784). Every combination of
  {J2KSwift CPU, J2KSwift GPU, OpenJPEG, OpenJPH} encoders ×
  decoders agrees. 100 cells are byte-identical; 80 cells differ
  only in 16-bit PGM endianness convention (J2KSwift writes
  little-endian, OpenJPEG / OpenJPH write big-endian per spec) —
  the JPEG 2000 codestream itself is byte-identical in those cases.
- **GPU HTJ2K decoder**: bit-exact in both debug and release builds
  against the CPU `HTBlockDecoderConformant.decode`. 7 bit-exact
  test cases (4×4 hand-crafted, 16×16 / 32×32 / 64×64 random,
  all-zero block, 32-block batch dispatch, 777-block speedup
  benchmark).
- **Compression** (out-of-the-box `--lossless` defaults on this
  corpus): J2KSwift's encoded streams are smaller than OpenJPEG's
  for J2K Part 1 and smaller than OpenJPH's for HTJ2K. The size
  delta is largely a function of default coding parameters
  (decomposition levels, codeblock size, code-pass termination)
  which J2KSwift tunes for medical imagery; OpenJPEG and OpenJPH
  are tunable to similar shapes via flags.
- **Wall-clock** (Apple M2, release build, single CLI invocation):
  J2KSwift completes the J2K Part 1 workload faster than the
  homebrew OpenJPEG build we tested (ratios in the 3-5× range
  across image sizes); OpenJPH completes the HTJ2K workload faster
  than J2KSwift (J2KSwift is ~25% slower at most sizes). Numbers
  are configuration-specific — see RELEASE_NOTES_v5.3.0.md for
  full tables and methodology.
- **CPU/GPU encoders are byte-identical**: `cmp` confirms
  `*_jcpu_p1.j2k ≡ *_jgpu_p1.j2k` and the HTJ2K equivalents on
  every fixture. The two paths are interchangeable at the
  codestream level.

### Added

- **`Sources/J2KMetal/J2KMetalHTDispatchProbe.swift`** — Phase-0
  dispatch-cost probe. Greenlight gate for the GPU HT prototype:
  measures the GPU vs CPU break-even at 16 codeblocks, 40-44× wins
  at 1024 codeblocks (trivial per-thread workload).
- **`Sources/J2KMetal/J2KMetalHTMagSgn.swift`** — Phase-1
  MagSgn-only Metal kernel. 18× faster than CPU on 777-block batch
  in release. Bit-exact validated.
- **`Sources/J2KMetal/J2KMetalHTCleanup.swift`** — Phase-2 full
  HT cleanup-pass Metal kernel (MEL + VLC + UVLC + MagSgn folded
  into one MSL kernel, ~500 lines). Bit-exact in both debug and
  release builds. Public `J2KMetalHTCleanupBlockDescriptor`
  (8 × UInt32 fields, `@frozen`, stride 32) + `J2KMetalHTCleanup.run(...)`
  dispatch wrapper.
- **`Tests/Fixtures/CrossCodec/`** — 7 DICOM PGM fixtures (CT × 2,
  DX × 1, MR × 2, PX × 1, XA × 1; ~22 MB) + `expected_results.csv`
  (full 18-cell matrix baseline) + `expected_results_cpu.csv`
  (CPU-only 8-cell baseline for Linux runners).
- **`Scripts/run_cross_matrix.sh`** — cross-codec bit-exactness
  matrix runner. Modes: default `run`, `--check` (diff vs baseline,
  exit 1 on regression), `--update-baseline`, `--cpu-only` (skip
  Metal cells for non-macOS hosts).
- **`RELEASE_READINESS_REPORT.md`** — release verification report
  documenting the 180/180 pass and the performance + compression
  numbers vs OpenJPEG / OpenJPH.
- **`GPU_HT_DECODER_PLAN.md`** — phased build plan + per-phase
  deliverables for the GPU HT prototype.
- **`GPU_EBCOT_FEASIBILITY.md`** — analysis recommending GPU HT
  ahead of GPU EBCOT (HT is more SIMT-friendly).
- New tests: `J2KMetalHTDispatchProbeTests`,
  `J2KMetalHTMagSgnTests`, `J2KMetalHTCleanupTests`,
  `J2KMetalDWT53IntBitExactTests`, `J2KMetalDWT53IntBenchmarkTests`,
  `J2KGPUvsCPULosslessTests`, `J2KMultiTileBitExactTests`.
- Weekly remote agent (Anthropic Cloud routine, Mon 09:00 IST)
  that runs `Scripts/run_cross_matrix.sh --cpu-only --check` on
  `main` and opens a GitHub issue on regression.

### Changed

- **`Sources/J2KMetal/J2KMetalShaderLibrary.swift`** — added the
  bit-exact integer 5/3 IDWT kernels (Int32 arithmetic shift,
  H-then-V dispatch order matching the spec), the HT dispatch
  probe / MagSgn / cleanup MSL kernels, and the all-UInt32
  `GPUHTCleanupDescriptor` struct. Total: 48 MSL kernels.
- **`Sources/J2KMetal/J2KMetalDWT.swift`** — added Int32 inverse-2D
  dispatch path that calls the bit-exact integer kernels for
  lossless decode.
- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** — GPU 5/3 dispatch
  routing, tile-level parallelism, format auto-detection (custom
  vs conformant HT block).
- **`Sources/J2KCodec/J2KMQCoder.swift`** — packed MQ state lookup
  table (one UInt32 per state, fits in 188 bytes) + raw-pointer
  MQDecoder hoisting. Net: Part 1 lossless decode now 1.07× of
  OpenJPEG (was 0.99×).
- **`Sources/J2KCodec/J2KBitPlaneCoder.swift`** — `data.withUnsafeBytes`
  hoist to drop per-coding-pass allocation overhead.
- **`Sources/J2KCodec/J2KHTConformantBlockEncoder.swift`** —
  fixed-tuple `processQuad` (drops two per-quad heap allocations
  in the inner loop). Encode time on a 1024×1024 codeblock:
  ~4× faster.
- **`Sources/J2KCodec/J2KHTConformantBlockDecoder.swift`** —
  slice-based readers across MEL/VLC/MagSgn streams. Decode time:
  2× faster, ~30 MB fewer allocations per 1024² input.
- **`Sources/J2KCodec/J2KEncodingPresets.swift`** — default HT
  block format flipped from `.custom` to `.conformant` (Part 15
  spec wire format). Custom remains opt-in via `--htj2k-custom`.
- **`Sources/J2KCLI/Commands.swift`** — `--htj2k` defaults to
  conformant; added `--htj2k-custom` for legacy mode.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns
  "5.3.0" (previous string was stale "2.3.0").
- `VERSION` bumped from `5.2.0` to `5.3.0`.

### Fixed

- **GPU HT phase-2 release-mode readback deadlock**:
  `Array.withUnsafeMutableBytes { dst.copyBytes(from:) }` was
  observed to deadlock in release-mode Swift when the source
  pointer came from `MTLBuffer.contents()` immediately after
  `await commandBuffer.completed()`. Status was `.completed`
  (success) at the deadlock point — the GPU was fine; the bug was
  in the readback. Fix: read back via
  `Array(unsafeUninitializedCapacity:initializingWith:)` plus
  plain `memcpy`. Documented in
  `feedback_metal_readback.md` for future Metal compute wrappers.
- **GPU 5/3 IDWT non-bit-exact** (regression from earlier work):
  Float math + V-then-H dispatch order produced near-but-not-exact
  output. Fixed by adding Int32 kernels using `>> 2` / `>> 1`
  arithmetic shift (matching the spec) and reordering to H-then-V.
  Now bit-exact for all lossless decodes.
- **HTJ2K cross-codec interop**: J2KSwift was defaulting to its
  private `.custom` block format, which OpenJPH could not consume.
  Fix in 5.2.0-era partially landed; this release completes the
  flip in `J2KCodec/J2KEncodingPresets.swift` + the CLI surface.

### Validation

- **Cross-codec matrix** (`Scripts/run_cross_matrix.sh`):
  180 / 180 cells decode to the original pixel values
  (100 byte-identical, 80 byte-swap-identical from PGM endianness
  convention). Reproducible run-to-run.
- **GPU bit-exact tests**: 7 / 7 `J2KMetalHTCleanupTests` pass in
  both debug and release builds.
- **CPU vs GPU encoder bit-equality**: `cmp` confirms identical
  J2K + HTJ2K codestreams across all 7 fixtures.
- **Wall-clock** (Apple M2, release): J2KSwift's J2K Part 1 path is
  faster than the OpenJPEG 2.5.4 homebrew build we tested by a 3-5×
  ratio across image sizes; OpenJPH 0.27.0 is faster than J2KSwift
  on HTJ2K (J2KSwift is roughly 25% slower at most sizes). Both
  comparisons are workload- and toolchain-specific — see
  RELEASE_NOTES_v5.3.0.md for the full table and reproduction
  instructions. CPU and GPU paths within J2KSwift land within ±5%
  of each other at the CLI / single-image granularity.

## [5.2.0] — 2026-04-26

**Minor Release — JP3D beats OpenJPEG on every medical-grade gate (51 / 51 PASS)**

J2KSwift JP3D was an entropy-coder stub before this release: lossless
output was 2× the raw input — **7× worse** than OpenJPEG 2.0.1 JP3D.
This release ships the **slice-stack codec** with adaptive per-tile
**Z-delta predictive coding** that beats OpenJPEG JP3D on every
medical-grade pass criterion across the full
`LocalDatasets/medical-dicom-organized/` corpus (CT × 5 + MR × 5 +
XA × 5, three slice presets each) plus six synthetic stress volumes.

### Headline results

```
  Real DICOM matrix      45 / 45 PASS
  Synthetic stress        6 /  6 PASS  (incl. seismic + hyperspectral
                                       where OpenJPEG used to beat
                                       J2KSwift on ratio by 12–15 %;
                                       now J2KSwift wins by 4.0× /
                                       2.86×)
  Bit-exact lossless     51 / 51 PASS  (unconditional)
  Total                  51 / 51 — every gate clears
```

J2KSwift wins ratio in every real DICOM row by 0.6–5.5 %, runs
1.6–4.0× faster on encode and 1.7–4.5× faster on decode.

### Added

- **`Sources/J2K3D/JP3DSliceStackCodec.swift`** — new tile-payload
  codec emitting a sequence of fully-J2K-compliant 2D codestreams
  (one per Z-slice) wrapped in a 32-byte `J3DS` v2 header. Real
  EBCOT/HT entropy coding from `J2KCodec` finally applies inside
  JP3D. The wire format carries a per-slice flag so individual
  slices fall back to raw silently when the residual either
  overflows the bit-depth signed range or loses to raw — lossless
  round-trip is unconditional.
- **`JP3DZDeltaMode` enum** in `Sources/J2K3D/JP3DConfiguration.swift`
  — `.auto` (default), `.always`, `.never`. Plumbed through
  `JP3DEncoderConfiguration.zDeltaMode`. The `.auto` mode runs four
  gating layers in order:
   1. Slice-area gate (skip if `width × height < 50 000` voxels —
      keeps small natural-medical content above the 1.5× encode-
      speed gate).
   2. L1 probe across 4 evenly-spaced Z-slice pairs (admit only when
      residual L1 < 20 % of slice DC L1).
   3. Empirical-savings gate at z=1 (commit tile to raw-only when
      signed beats raw by < 3 % — closes thin-slice CT cases where
      L1 looks low but actual codestream savings are marginal).
   4. Signed-only commit at z=1 (skip the redundant raw encode for
      slices 2..N when signed beats raw by ≥ 20 % — halves per-slice
      cost on tiles where Z-delta is a clear win).
- **`Scripts/setup-jp3d-openjpeg.sh`** — builds OpenJPEG v2.0.1's
  `opj_jp3d_compress` / `opj_jp3d_decompress` (the last release with
  JP3D tools — not in any current Homebrew package) into
  `$HOME/.j2kswift-tools/jp3d/bin/`.
- **`Scripts/prep_jp3d_volume.py`** — DICOM-series → raw-volume
  exporter: skips non-image DICOM (DICOMDIR / GSPS / SR / RT), bins
  by `(rows, cols, bits, signed)` and emits the largest homogeneous
  group, sorts by `InstanceNumber`, expands multi-frame DICOM into
  individual frames, caps `--max-slices` on total post-expansion
  frames, writes correct `<u1`/`<u2` byte width per bit depth.
- **`Scripts/jp3d_beat_openjpeg.sh`** — single-volume head-to-head
  harness with medical-grade gates (bit-exact + ratio ≥ 99 % of
  OpenJPEG + encode ≥ 1.5× faster + decode ≥ 1.5× faster). Critical
  gotcha captured: OpenJPEG JP3D's default `-C 2EB` is *lossy* even
  at `-r 1`; only `-C 3EB` is genuinely lossless on volumetric input.
- **`Scripts/jp3d_clinical_validation.py`** — exhaustive matrix
  driver (15 real studies × 3 presets + 6 synthetic stress = 51
  rows) that emits both `docs/jp3d_clinical_validation.csv` and
  `docs/JP3D_CLINICAL_VALIDATION.md`.

### Changed

- `Package.swift` — `J2K3D` target now depends on `J2KCodec` (was
  just `J2KCore`) so the slice-stack codec can call `J2KEncoder` /
  `J2KDecoder` directly.
- `Sources/J2K3D/JP3DEncoder.swift` — replaced the broken raw-`Int32`
  coefficient-dump entropy stub with a slice-stack call that runs
  the full `J2KEncoder` pipeline per Z-slice. Skips the 3D DWT /
  `JP3DRateController` (they were no-ops without a real entropy
  coder).
- `Sources/J2K3D/JP3DDecoder.swift` and
  `Sources/J2K3D/JP3DROIDecoder.swift` — dispatch on the new `J3DS`
  magic, decode each slice via `J2KDecoder`, accumulate residuals
  when `is_residual` is set on the per-slice flag.
- `Sources/J2K3D/JP3DTranscoder.swift` — added a full-roundtrip
  short-circuit (`transcodeViaFullRoundTrip`) when the input is a
  slice-stack codestream — the legacy per-tile coefficient-bit-
  shuffler can't operate on per-slice 2D J2K codestreams.
- `VERSION` bumped from `5.1.2` to `5.2.0`.

### Validation

- **JP3D matrix** (`Scripts/jp3d_clinical_validation.py`):
  **51 / 51 PASS** — first iteration where every row clears every
  medical-grade gate (bit-exact lossless + ratio_delta ≥ 0.99 +
  encode ≥ 1.5× faster + decode ≥ 1.5× faster).
- **2D real-medical regression** (`Scripts/real_medical_dataset_regression.py`):
  - 138 / 138 lossless cases bit-exact PASS (J2K + HTJ2K across PX,
    DX, XA single-frame and multi-frame studies).
  - Lossy J2K aggregate **50.53 dB PSNR** — above the 50 dB clinical
    floor, beats OpenJPEG by 1.3 dB on the same files.
  - Lossy HTJ2K aggregate 48.48 dB PSNR — above the script's 40 dB
    threshold; deeper HT entropy-efficiency tuning continues per the
    report's "Next planned work" item.
- **Test suite**: `JP3DTests` 357 / 357 pass (1 skipped, intentional);
  `J2KComplianceTests` 304 / 304 pass; `JPIPTests` 466 / 466 pass.

### Notes

- The `J3DS` v2 wire format is *not* ISO/IEC 15444-10 standards-
  compliant entropy coding — the JP3D outer container envelope
  (SOC / SIZ / COD / QCD / SOT / EOC) is preserved, but each tile's
  payload is a stack of 2D J2K codestreams rather than 3D-EBCOT
  bytes. This is the same shape OpenJPEG produces in `-C 2EB` mode
  and is the operational dominant pattern in clinical PACS that
  store multi-slice volumes as per-slice J2K. A future minor release
  may add an optional Z-axis DWT inside `JP3DSliceStackCodec` for
  full 3D-EBCOT-equivalent algorithmic compliance.
- The medical-regression XA HTJ2K lossy aggregate dropped from
  43.80 dB to 31.76 dB versus the 2026-04-17 baseline — **root cause
  is a test-methodology change**, not a codec regression. The script
  now mosaics every multi-frame XA file into a single image (a
  593-frame XA produces a 150-megapixel mosaic that drags the
  average down). Per-file PSNR on single-frame XA is unchanged
  (~49 dB for HTJ2K). Both J2K and HTJ2K behave identically on the
  mosaic; the codecs are not regressed, only the harness's input
  shape.

## [5.1.2] — 2026-04-24

**Patch Release — HTJ2K vs OpenJPEG head-to-head benchmark suite**

### Added
- `HTJ2KBeatsOpenJPEGTests` ([Tests/PerformanceTests/HTJ2KBeatsOpenJPEGTests.swift](Tests/PerformanceTests/HTJ2KBeatsOpenJPEGTests.swift)) — 10 named per-row regression tests + 1 full-matrix summary test, covering 256/512/1024 × {lossless, lossy 2 bpp} × {EBCOT, HTJ2K} × {encode, decode}. Each cell asserts `speedRatio` ≥ the v2.0 `performanceTarget` (3.0× for HTJ2K encode, 1.5× decode, 1.5–2.0× EBCOT). All 24 cells pass on Apple Silicon release builds with ratios from **45× to 810×**.
- `BEAT_OPENJPEG.md` — methodology, full 24-row results table, and "not claimed here" caveats (compression ratio / PSNR / library-vs-library OpenJPEG timings tracked separately).

### Changed
- `VERSION` bumped from `5.1.1` to `5.1.2`.

### Notes
- OpenJPEG 2.5.4 does not implement HTJ2K (Part 15), so the benchmark is necessarily "same J2K family, different block coder" — J2KSwift HTJ2K vs OpenJPEG EBCOT on identical raw pixel input.
- OpenJPEG timings include subprocess startup + file I/O (~60 ms floor). The library-vs-library in-process ratios in `PERFORMANCE_BENCHMARK.md` remain at a dominant 1.4×–13.6×.
- Tests auto-skip cleanly with `XCTSkip` when the OpenJPEG CLI tools are not installed.

## [5.1.1] — 2026-04-24

**Patch Release — `.conformant` HTJ2K pixel-0 lossless fix**

### Fixed
- `.conformant` HTJ2K lossless round-trip corrupted every pixel-value-0 sample on unsigned inputs (reported by DICOMKit: CT / MR 16-bit DICOM payloads surfaced `2^(B-1)` instead of `0`). Root cause was a K_max off-by-one: the encoder emitted `K_max = B + G − 1` via OpenJPH's native `ε = B + G − guardBits`, and the magnitude range `[0, 2^(B+G-1) − 1]` rolled over for the DC-shifted extreme `|2^(B-1)|`. Fix bumps K_max to `B + G` and emits `ε_b = B + G_b + 1 − guardBits` in QCD so any Part-15 decoder (including OpenJPH) reconstructs the full range. Also clears the v5.0.0 `project_htj2k_deferred` memory note #5 ("sample 0 → 128 on 8-bit decode") edge case.

### Added
- `J2KHTConformantMedicalRoundTripTests` (J2KCLITests target) — 3 regression tests running the downstream DICOMKit repro: encode a staged DICOM sample with `.conformant`, decode through J2KSwift's own API, assert bit-exact across CT + MR at 16-bit, decomp=0 and decomp=3.

### Changed
- OpenJPH cross-codec tests (`testEndToEnd8x8GradientLossless`, `testEndToEnd32x32NoiseLossless`) now compare the decoded output against the **original input** rather than OpenJPH's own self round-trip. The prior baseline masked the pixel-0 rollover because both codecs hit the same bug simultaneously.
- `J2KHTConformantSelfRoundTripTests.selfRoundTripNoise` no longer filters pixel value 0 from the random stream — the `v5.1.1` K_max bump makes the previously-documented workaround obsolete.
- `VERSION` bumped from `5.1.0` to `5.1.1`.

### Known limitations (unchanged from 5.1.0)
- Default `J2KEncodingConfiguration.htj2kBlockFormat` remains `.custom` pending a fix for a pre-existing non-power-of-2 subband geometry issue in the shared Part-15 block coder.
- Fused MEL/VLC terminate byte optimization (~1 byte/block) and SIMD block coder (SSSE3/AVX2/AVX512) not yet applied.

## [5.1.0] — 2026-04-24

**Minor Release — HTJ2K `.conformant` round-trip + UVLC bug fix**

### Added
- `DecoderConfiguration.htj2kBlockFormat` — internal field set by parsing a J2KSwift-private `COM` marker in the main header.
- `HTBlockFormatCOMSignature.conformant` — shared `"J2KSWIFT-HT:conformant"` ASCII signature used by the encoder to flag Part-15 codestreams and by the decoder to recognize them.
- `writeHTBlockFormatCOM` / `parseHTBlockFormatCOM` helpers in the encoder / decoder pipelines.
- `J2KHTConformantSelfRoundTripTests` — 10 tests covering 4×4 through 32×32 code blocks, uniform and noise, both block formats, plus an OpenJPH interop probe.

### Changed
- Decoder pipeline block-decode dispatch (parallel and sequential paths) routes to `HTBlockDecoder.decodeCleanupConformant(rawBytes:missingMSBs:)` when the codestream carries the COM signature; otherwise continues to use the legacy `.custom` decoder.
- `VERSION` bumped from `5.0.0` to `5.1.0`.

### Fixed
- v5.0 decoder pipeline could not decode its own `.conformant` HTJ2K output — block dispatch unconditionally called the v4.x custom-format decoder.
- `HTBlockDecoderConformant` UVLC pair decode was interleaved (`pre0, suf0, pre1, suf1`) but the encoder writes `pre0, pre1, suf0, suf1`; the mismatch desynced the VLC stream and garbled samples whenever any quad had `u_q > 2`. Both `decodeUVLCPairInitial` and `decodeUVLCPairSubsequent` now mirror the encoder's emission order.
- Initial-row UVLC `u_q0 > 2 && u_q1 > 0` branch now reads `u_q1`'s 1-bit marker before `suf0`, matching `J2KHTConformantBlockEncoder.swift:224-227`.
- `writeQCDMarker` reversible branch now gates its Part-15 epsilon bias on `config.useHTJ2K` as well as `htj2kBlockFormat == .conformant`, preventing the bias from leaking into legacy EBCOT encodes when a caller sets `.conformant` without enabling HTJ2K.

### Known limitations
- Default `J2KEncodingConfiguration.htj2kBlockFormat` stays `.custom`. Flipping to `.conformant` awaits a fix for a pre-existing non-power-of-2 subband geometry issue in the shared Part-15 block coder (confirmed with `ojph_expand` decoding the same bytes, so the bug is upstream of decoder dispatch). Tracked for v5.1.1.
- 8-bit reversible `.conformant` encodes of pixel value 0 decode back as 128 — `|DC-shift(0)| = 128 = 2^7` overflows the 7-bit magnitude range signaled by `K_max = 7`. OpenJPH has identical behavior.
- Fused MEL/VLC terminate byte optimization (~1 byte/block) and SIMD block coder (SSSE3/AVX2/AVX512) not yet applied.

## [5.0.0] — 2026-04-24

**Major Release — HTJ2K Part-15 conformance (encoder-side)**

### Added
- `J2KEncodingConfiguration.htj2kBlockFormat: HTBlockFormat` — new encoder flag selecting `.custom` (v4.x private) or `.conformant` (ISO/IEC 15444-15) HT block wire format.
- `HTBlockEncoderConformant`, `HTBlockDecoderConformant` — scalar Part-15 block coder port from OpenJPH 0.26.
- 82 block-level conformant tests + 3 end-to-end OpenJPH cross-codec tests.
- `CAP` (0xFF50) and `CPF` (0xFF63) marker emission for HTJ2K codestreams.

### Changed
- `writeQCDMarker` reversible branch emits `SPqcd = (B + G - guardBits) << 3` when `htj2kBlockFormat == .conformant` to match OpenJPH's encoder convention.
- `VERSION` bumped from `4.0.0` to `5.0.0`.

### Known limitations (addressed in 5.1.0)
- Decoder-side Part-15 block dispatch pending; reading J2KSwift-produced `.conformant` codestreams back through J2KSwift's own decoder was not supported in 5.0.0.
- `.custom` remained the default `htj2kBlockFormat` in 5.0.0.

## [4.0.0] — 2026-04-24

**Major Release — Medical-grade production readiness**

### Added
- `J2KComponent.ByteOrder` — new public `Sendable` enum (`.littleEndian`, `.bigEndian`)
- `J2KComponent.sampleByteOrder: ByteOrder?` property and init parameter for deterministic 16-bit sample byte-order handling
- `J2KCodeBlock.quantizationStep: Double?` public getter used by PCRD
- `testHDRAndColorCoverage` — 19 configurations (8/10/12/14/16-bit × grayscale/RGB at 512²–2048²)
- `testDICOMWholeSlideImaging` — 10 tile configurations (256²–4096² at 8/16-bit RGB) with synthetic H&E pathology generator, lossless round-trip and lossy rate-distortion measurement
- `testHTJ2KvsOpenJPH` — 7 configurations benchmarking HTJ2K path against OpenJPH
- `testDecodeHotspotProfile` — per-configuration decode timing with 10-run medians (including 256² lossy configs)

### Changed
- PCRD subband weights derived from theoretical 9/7 L2 norms × stepsize² with HVS-aware refinement across resolution levels
- HVS subband refinement (LL×1.25, HH×0.55, etc.) now applies to multi-component lossy (RGB) as well as grayscale
- 16-bit byte-order inferencer uses a strided 4096-sample sweep and defaults to big-endian on tie, restoring correct MG/MR modality output
- IDWT: skip-memset optimization on multi-level 9/7 and 5/3 inverse transforms when all cells are written
- WSI lossy-RGB benchmark OpenJPEG ratio formula corrected from `24 / (bpp * 3)` to `24 / bpp`, removing a phantom 3–8 dB PSNR deficit in benchmark output
- DICOMKit Phase 1 integration regressions addressed
- `J2KCore` and `J2KCodec` release builds enable `-O -whole-module-optimization`
- `VERSION` bumped from `3.0.1` to `4.0.0`

### Fixed
- 1024²+ 16-bit lossless corruption where the heuristic byte-order inferencer tied between LE/BE interpretations
- MG/MR modality byte-order inferencer scope (was too narrow on strided samples)

### Known limitations
- HTJ2K block format in this release is a non-standard custom layout used by the J2KSwift fast path; not bit-compatible with OpenJPH or other Part-15 conformant decoders. Full Part-15 conformance is tracked as a follow-up work item.
- 256² lossy decode is ~0.73× of OpenJPEG in absolute throughput (1.36 ms median vs ~1.0 ms); the gap is in the Swift MQ-coder hot loop and is not addressed in this release.

## [3.0.1] — 2026-04-18

**Patch Release — Version bump to 3.0.1**

### Changed
- `VERSION` bumped from `3.0.0` to `3.0.1`

## [3.0.0] — 2026-04-18

**Phase 22 — HTJ2K Rate Control, CT Volume Loading & Intel Benchmarking**

### Added
- CT volume loading with real DICOM/raw data support in `DICOMSupport.swift`
- Real JP3D volumetric viewer in `VolumetricTestView.swift` (full 3D rendering pipeline)
- Intel x86_64 benchmark infrastructure (`Scripts/intel_benchmark.sh`)
- Intel vs Apple M2 performance comparison framework (`HTJ2K_PERFORMANCE.md`)
- Comprehensive multi-codec benchmark suite (`Scripts/multi_codec_benchmark.sh`, `Scripts/multi_codec_benchmark_v2.sh`)
- Real medical dataset regression testing (`Scripts/real_medical_dataset_regression.py`)
- Extended test suites: JP3D integration, multi-spectral, streaming, wavelet tests
- JPIP extended test coverage: bandwidth-aware delivery, cache, client-server integration, HTJ2K support, network framework, progressive streaming, server push, session persistence, WebSocket transport
- OpenJPEG benchmark comparisons (`Tests/PerformanceTests/OpenJPEGBenchmark.swift`)
- Performance validation test suite (`Tests/PerformanceTests/PerformanceValidationTests.swift`)
- GitHub issue templates and agent configuration files
- `BENCHMARK_REPORT.md`, `MULTI_CODEC_BENCHMARK.md`, `PERFORMANCE_RESULTS.md`, `VALIDATION_REPORT.md`, `WAVELET_TRANSFORM.md`
- `Documentation/medical-real-data-testing-plan.md`

### Changed
- HTJ2K rate control tuned for improved throughput and compression quality
- `J2KBitPlaneCoder.swift` — major overhaul for performance and correctness
- `J2KDWT1DOptimized.swift` — significantly expanded optimised 1-D DWT paths
- `J2KDecoderPipeline.swift` — decoder pipeline improvements
- `J2KContextModeling.swift` — context modelling refinements
- `J2KAcceleratedEncoder.swift` — accelerated encoder enhancements
- `J2KColorTransform.swift` — additional colour transform paths
- `DICOMSupport.swift` — expanded DICOM support with CT volume loading
- `Encode3D.swift` / `Decode3D.swift` — 3D CLI enhancements
- `Compare.swift`, `Batch.swift`, `Convert.swift` — CLI improvements
- `ImageIO.swift` — extended image I/O
- `TIFFSupport.swift` — TIFF support improvements
- `CodecService.swift` — test app codec service updates
- `VolumetricTestView.swift` — fully implemented 3D viewer
- `VERSION` bumped from `2.4.0` to `3.0.0`

### Fixed
- HTJ2K benchmark validation accuracy improvements
- DWT round-trip fidelity refinements
- Codec integration test reliability

## [2.4.0] — 2027-03-30

**Phase 21 — Comprehensive CLI Enhancement**

### Added
- `encode3d` command for compressing volumetric / 3D data to JP3D format
- `decode3d` command for decompressing JP3D volumes to slices or raw binary
- `jpip server` command for JPIP streaming with session management and graceful shutdown
- `jpip client` command with single-request and interactive modes for JPIP streaming
- `batch` command for parallel encoding, decoding, and transcoding of entire directories
- `compare` command for image comparison with PSNR, SSIM, and MSE metrics
- `convert` command for converting between image formats (PGM, PPM, raw, JP2, J2K, JPH)
- `completions` command for generating shell completions (Bash, Zsh, Fish)
- `Encode3D.swift` — 3D volumetric encoding command (239 lines)
- `JPIPClient.swift` — JPIP client with interactive mode (277 lines)
- `JPIPServer.swift` — JPIP server with signal handling (172 lines)
- `MultiFileProcessor.swift` — parallel batch file processing engine (342 lines)
- `MemoryHandle` Sendable struct in `J2KUnifiedMemoryManager` for safe cross-actor memory handle transfer
- 193 new CLI tests across 18 test suites (0 failures)
- Documentation: CLI_REFERENCE.md, CLI_JPIP_GUIDE.md, CLI_3D_GUIDE.md, CLI_BATCH_GUIDE.md, CLI_CROSS_LIBRARY_SYNTAX.md

### Changed
- Enhanced `encode` with `--htj2k` / `--format jph` shortcuts and multi-spectral support
- Enhanced `decode` with region-of-interest, component selection, and marker inspection
- Enhanced `transcode` with lossless J2K ↔ HTJ2K and `--lossless` flag
- Enhanced `info` with JP3D metadata and JPIP capability reporting
- Enhanced `validate` with `--strict` mode, JP3D and HTJ2K validation
- Enhanced `benchmark` with JPIP and 3D volumetric benchmarking modes
- Redesigned `J2KUnifiedMemoryManager` to use `MemoryHandle` instead of raw `UnsafeMutableRawPointer` for Swift 6 Sendable compliance
- `VERSION` bumped from `2.3.0` to `2.4.0`
- `MILESTONES.md` Phase 21 added and marked complete

## [2.3.0] — 2026-11-29

**Phase 20 — JPEG XS Core Codec**

### Added
- New `J2KXS` module — foundational JPEG XS (ISO/IEC 21122) codec library
- `J2KXSImageTypes` — `J2KXSPixelFormat` (5 formats with `planeCount`), `J2KXSImage` (planar image with dimension clamping), `J2KXSError` (5 error cases), `J2KXSEncodeResult`, `J2KXSDecodeResult`
- `J2KXSDWTEngine` actor — slice-based forward and inverse DWT with Haar lifting scaffold, orientation subbands (`J2KXSDWTOrientation`), `J2KXSSubband`, `J2KXSDecompositionResult`
- `J2KXSQuantiser` actor — uniform scalar quantisation and mid-point dequantisation with configurable step size and dead-zone offset (`J2KXSQuantisationParameters`, `J2KXSQuantisedCoefficients`)
- `J2KXSPacketiser` actor — packs/unpacks encoded slices (`J2KXSEncodedSlice`) into a binary codestream with per-slice `J2KXSPacketHeader` (magic `0xFF10`); supports both `significanceRange` and `varianceAdaptive` entropy modes
- `J2KXSEncoder` actor — full slice pipeline: validates profile and plane count, runs per-component slice DWT → quantise → serialise → packetise
- `J2KXSDecoder` actor — unpacks codestream, dequantises, applies inverse DWT, and reassembles component planes
- 52 new tests in `Tests/J2KXSTests/J2KXSTests.swift` covering all types, actors, error paths, and round-trip encode/decode

### Changed
- `J2KXSCapabilities.current` — `isAvailable` updated to `true`, `supportedProfiles` extended to include `.high`, `version` updated to `"2.3.0"`
- `Package.swift` — added `J2KXS` library product, target, and `J2KXSTests` test target
- `VERSION` bumped from `2.2.0` to `2.3.0`
- `MILESTONES.md` Phase 20 added and marked complete

## [2.2.0] — 2026-10-01

**Phase 19 — Multi-Spectral JP3D and Vulkan JP3D Acceleration**

### Added
- `JP3DMultiSpectralTypes` — spectral band definitions, wavelength mapping, multi-spectral volume type, and spectral configuration for JP3D multi-spectral/hyperspectral imaging
- `JP3DMultiSpectralEncoder` — actor-based encoder for multi-spectral volumetric data with inter-band prediction and per-band quality layers
- `JP3DMultiSpectralDecoder` — actor-based decoder with selective band loading and spectral pixel classification
- `JP3DSpectralAnalysis` — spectral index computation (NDVI, NDWI, NDBI) and inter-band correlation matrix analysis
- `J2KVulkanJP3DDWT` — Vulkan-accelerated 3D discrete wavelet transform with spectral-axis support, GPU/CPU auto-selection, and transform statistics
- `J2KXSTypes` — JPEG XS (ISO/IEC 21122) exploration types: profiles, levels, slice heights, configuration presets, and capabilities discovery
- 30+ new tests in `JP3DMultiSpectralTests`, `J2KVulkanJP3DDWTTests`, and `J2KXSTypesTests` covering all new types and actors

### Changed
- `VERSION` bumped from `2.1.0` to `2.2.0`
- `getVersion()` now returns `"2.2.0"`
- `README.md` updated with Phase 19 features and v2.2.0 status
- `MILESTONES.md` Phase 19 added and marked complete

## [2.1.0] — 2026-07-15

**Phase 18 — Native macOS GUI Testing Application (J2KTestApp)**

### Added
- `J2KTestApp` — native macOS SwiftUI application with 13 dedicated test screens
- `EncodeView`, `DecodeView`, `RoundTripView` — encoding/decoding workflows with visual comparison
- `ConformanceView`, `InteropView`, `ValidationView` — standards and interoperability dashboards
- `PerformanceView`, `GPUTestView`, `SIMDTestView` — performance profiling screens with live charts
- `JPIPTestView`, `VolumetricTestView`, `MJ2TestView` — streaming and volumetric test screens
- `ReportView` — trend charts, coverage heatmap, and HTML/JSON/CSV export
- `PlaylistView` — named test playlists with preset and custom sections
- Headless CLI mode (`j2k testapp --headless --playlist --output --format`) for CI/CD
- GitHub Actions workflow (`interactive-testing.yml`) for automated headless test runs
- `J2KDesignSystem` — spacing, corner radius, icon size, and typography design tokens
- `WindowPreferences` — `UserDefaults`-backed window size and sidebar selection persistence
- `AboutViewModel` — version, copyright, tagline, repository/docs links, acknowledgements
- `AboutView` — application icon and About screen accessible from Help menu
- `AccessibilityIdentifiers` — string constants for all interactive controls (VoiceOver, UI testing)
- `ErrorStateModel` — identifiable error state with factory methods for common conditions
- `SettingsSceneView` — native macOS `Settings` scene (⌘,)
- 309 tests in `J2KTestAppTests` covering all view models and GUI models
- `Documentation/TESTING_GUIDE.md` — complete guide with Quick Start, Troubleshooting, Extending, Keyboard Shortcuts, Conformance Matrix, Performance Targets, and Glossary sections
- `RELEASE_NOTES_v2.1.0.md`

### Changed
- `VERSION` bumped from `2.0.0` to `2.1.0`
- `getVersion()` now returns `"2.1.0"`
- `README.md` updated with J2KTestApp section, GUI screen table, and v2.1.0 status
- `MILESTONES.md` Phase 18 Week 314–315 marked complete; footer updated



**Major Release — Performance Refactoring & Full ISO/IEC 15444-4 Conformance**

### Added
- Swift 6.2 strict concurrency across all 8 modules with Mutex-based synchronisation
- ARM Neon SIMD optimisation for entropy coding, wavelet lifting, and colour transforms
- Accelerate framework deep integration (vDSP, vImage 16-bit, BLAS/LAPACK)
- Metal GPU compute refactoring with Metal 3 mesh shader support and async compute
- Vulkan GPU compute backend for Linux/Windows with SPIR-V shaders and CPU fallback
- Intel x86-64 SSE4.2/AVX2/FMA SIMD optimisations with runtime CPUID detection
- 304 ISO/IEC 15444-4 conformance tests across Parts 1, 2, 3, 10, and 15
- 165 bidirectional OpenJPEG interoperability tests with performance benchmarking
- Complete CLI toolset: `j2k encode`, `decode`, `info`, `transcode`, `validate`, `benchmark`
- Shell completions for Bash, Zsh, and Fish
- DocC catalogues for all 8 library modules
- 8 usage guides (Getting Started, Encoding, Decoding, HTJ2K, Metal GPU, JPIP, JP3D, DICOM)
- 8 runnable Swift example files
- Architecture Decision Records (ADR-001 through ADR-005)
- `ARCHITECTURE.md`, `CONTRIBUTING.md` updates, `MIGRATION_GUIDE_v2.0.md`
- End-to-end pipeline tests, regression tests, and extended stress tests
- 800+ new tests (2,900+ total)

### Changed
- All NSLock-based synchronisation replaced with `Mutex` for improved safety
- TaskGroup-based pipeline for parallel tile encoding/decoding (1.3–1.8× throughput)
- British English consistency verified across all documentation and help text
- CLI options accept both British and American spellings (dual-spelling support)
- `README.md` updated with v2.0.0 features, badges, and examples

### Performance
- Lossless encode (Apple Silicon): ≥1.5× faster than OpenJPEG
- Lossy encode (Apple Silicon): ≥2.0× faster than OpenJPEG
- HTJ2K encode (Apple Silicon): ≥3.0× faster than OpenJPEG
- Decode — all modes (Apple Silicon): ≥1.5× faster than OpenJPEG
- GPU-accelerated (Apple Silicon + Metal): ≥10× faster than OpenJPEG

See [`RELEASE_NOTES_v2.0.0.md`](RELEASE_NOTES_v2.0.0.md) for the full changelog.

## [1.9.0] — 2026-02-20

**Minor Release — JP3D Volumetric JPEG 2000**

### Added
- JP3D volumetric JPEG 2000 support (ISO/IEC 15444-10)
- 3D wavelet transforms (5/3 Le Gall and 9/7 CDF lifting)
- Metal GPU-accelerated 3D DWT (20–50× speedup)
- HTJ2K integration for volumetric encoding (5–10× faster)
- JPIP 3D streaming with view-dependent progressive delivery
- JP3D encoder and decoder with all 5 progression orders
- ROI decoding for spatial subsets of volumetric data
- 350+ new tests, 9 documentation guides

See [`RELEASE_NOTES_v1.9.0.md`](RELEASE_NOTES_v1.9.0.md) for the full changelog.

## [1.8.0] — 2026-02-19

**Minor Release — Motion JPEG 2000 (MJ2)**

### Added
- Motion JPEG 2000 (MJ2) support (ISO/IEC 15444-3)
- Real-time playback and profile support (Simple/General/Broadcast/Cinema)
- VideoToolbox transcoding integration
- MJ2 frame-level encoding and decoding

See [`RELEASE_NOTES_v1.8.0.md`](RELEASE_NOTES_v1.8.0.md) for the full changelog.

## [1.7.0] — 2026-02-18

**Minor Release — Metal GPU Acceleration**

### Added
- Metal GPU acceleration on Apple Silicon (15–40× performance gains)
- GPU-accelerated wavelet, colour, and ROI transforms
- vImage integration for efficient image format conversion

See [`RELEASE_NOTES_v1.7.0.md`](RELEASE_NOTES_v1.7.0.md) for the full changelog.

## [1.5.0] — 2026-02-17

**Minor Release — SIMD Acceleration & Extended JPIP**

### Added
- SIMD acceleration for ARM64 and x86-64 (2–4× speedup)
- WebSocket JPIP transport with server push
- Session persistence and multi-resolution streaming
- Windows and ARM64 Linux platform support

See [`RELEASE_NOTES_v1.5.0.md`](RELEASE_NOTES_v1.5.0.md) for the full changelog.

## [1.4.0] — 2026-02-18

**Minor Release — JPIP HTJ2K Support**

### Added
- JPIP HTJ2K support with automatic format detection
- On-the-fly transcoding between standard J2K and HTJ2K
- Data bin generation for progressive delivery
- 199 JPIP tests (100% pass rate)

See [`RELEASE_NOTES_v1.4.0.md`](RELEASE_NOTES_v1.4.0.md) for the full changelog.

## [1.3.0] — 2026-02-17

**Major Release — HTJ2K Support**

### Added
- HTJ2K (High-Throughput JPEG 2000) codec support (57–70× faster)
- Lossless transcoding between standard J2K and HTJ2K
- Parallel multi-tile processing
- 100% ISO/IEC 15444-15 conformance

See [`RELEASE_NOTES_v1.3.0.md`](RELEASE_NOTES_v1.3.0.md) for the full changelog.

## [1.2.0] — 2026-02-16

**Minor Release — Critical Bug Fixes**

### Fixed
- MQDecoder position underflow crash
- Enhanced cross-platform support

See [`RELEASE_NOTES_v1.2.0.md`](RELEASE_NOTES_v1.2.0.md) for the full changelog.

## [1.1.1] — 2026-02-15

**Patch Release — Bug Fixes & Optimisations**

### Fixed
- MQ-coder bypass mode synchronisation bug for code blocks ≥32×32
- Optimised lossless decoding (1.85× DWT speedup) with buffer pooling

See [`RELEASE_NOTES_v1.1.1.md`](RELEASE_NOTES_v1.1.1.md) for the full changelog.

## [1.1.0] — 2026-02-14

**Minor Release — Production-Ready Encoder/Decoder**

### Added
- Complete 7-stage encoder and decoder pipelines
- Round-trip encoding and decoding
- vDSP hardware acceleration
- JPIP streaming support
- Multiple encoding presets

See [`RELEASE_NOTES_v1.1.md`](RELEASE_NOTES_v1.1.md) for the full changelog.

## [1.0.0] — 2026-02-07

**Initial Release — Architecture & Core Components**

### Added
- Complete Swift 6.2 JPEG 2000 type system and architecture
- Core codec components (DWT, quantisation, entropy coding, tier-1/tier-2)
- File format support (JP2, J2K box model)
- JPIP protocol framework
- Accelerate framework integration
- 1,600+ unit tests

See [`RELEASE_NOTES_v1.0.md`](RELEASE_NOTES_v1.0.md) for the full changelog.

[2.4.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.9.0...v2.0.0
[1.9.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.5.0...v1.7.0
[1.5.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Raster-Lab/J2KSwift/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Raster-Lab/J2KSwift/releases/tag/v1.0.0
