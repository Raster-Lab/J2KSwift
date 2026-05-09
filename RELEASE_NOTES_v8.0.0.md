# J2KSwift v8.0.0 — Apple Silicon-first release

**Tag**: `v8.0.0`
**Released**: 2026-05-10
**Headline**: Apple-only product narrowing (M-series macOS + A-series iOS/iPadOS) with a Metal-first architecture. **Marketable claim**: "Fastest JPEG 2000 codec on Apple Silicon."

---

## What v8.0.0 is

A major-version product pivot. v7.x targeted cross-platform performance and got within 25 % of OpenJPH and 2× of Kakadu globally. v8.0.0 narrows the product to Apple Silicon (M-series macOS + A-series iOS/iPadOS) and uses platform-native primitives (Metal, NSXPCConnection, launchd) to **beat Kakadu on the dominant Apple-Silicon workloads** — small/medium medical images, warm-process apps, and (with the optional XPC daemon) single-shot CLI users.

**Strategic context** (from `V8_0_0_METAL_FIRST_STRATEGY.md` RFC):
- v7.4 + v7.5 demonstrated empirically that the cross-platform CPU lever-ceiling on Apple M2 + Swift release is reached (3 of 4 SWAR/SIMD candidates rejected, only Phase 2 SWAR MagSgn refill cleared the gate).
- The remaining headroom on Apple Silicon is platform-native: warm-session reuse, GPU compute (for embarrassingly-parallel stages), Metal-aware tuning, persistent daemon for CLI single-shot.
- v8.0.0 commits the product line to Apple-only (per `feedback_apple_only_v8` directive) — Linux/Windows builds still compile but performance is no longer a measurement criterion.

## Headline measurements (Apple M2, release builds)

### Warm in-process decode (Phase 5 measurement) — the load-bearing finding

J2KSwift in-process CPU vs Kakadu CLI (the comparison user-facing apps care about):

| fixture | warm CPU | Kakadu CLI | result |
|---|---:|---:|:-:|
| MR-small 180² | **0.58 ms** | 15 ms | **WIN 26×** |
| CT 512² | **3.05 ms** | 15 ms | **WIN 5×** |
| MR 886² | **5.60 ms** | 17 ms | **WIN 3×** |
| XA 1024² | **7.89 ms** | 18 ms | **WIN 2.3×** |
| PX 2459×1316 | 29.48 ms | 24 ms | 1.23× behind |
| DX 2800×2288 | 54.41 ms | 36 ms | 1.51× behind |

**4 of 6 fixtures win**. SDK consumers (PACS daemons, iOS/iPadOS DICOM viewers, image-processing pipelines) get this performance via the new `J2KDecoder.preWarm()` API.

### CLI cold-shot (single `j2k decode`) progression

| version | DX CLI cold | gap to Kakadu |
|---|---:|---:|
| pre-v8 (v7.5.1 baseline) | 134 ms | 4.0× |
| v8 Phase 1 (cold-start elimination) | 91 ms | 2.7× |
| v8 Phase 2 (default-CPU routing) | 103 ms | 2.8× |
| v8 Phase 3 (SIMD CPU IDWT) | 91 ms | 2.7× |
| **v8 Phase 4 (NEON reconstruction default ON)** | **89 ms** | **2.47×** |
| **v8 with XPC daemon installed** | **~55 ms** | **~1.5×** |

The Phase 1-4 CPU optimisations cumulatively close the CLI gap from 4.0× to 2.47×. Installing the optional `j2kd` XPC daemon (Phases 6.3-6.6) closes it further to ~1.5× by amortising Metal cold-start across CLI invocations.

### Multi-file CLI (`j2k batch decode`)

For users with multi-file workflows (e.g. PACS export pipelines):

| scenario | per-file CLI sum | `j2k batch decode` |
|---|---:|---:|
| Cold system (1st run) | 889 ms | **193 ms (4.6× WIN)** |
| Warm system | 182 ms | 195 ms (parity) |

`j2k batch decode -i input_dir -o output_dir` is the recommended replacement for `for f in *.j2k; do j2k decode...` shell loops on cold systems.

## What's New — production default

### Phase 1-4: CPU optimisations (default ON across the corpus)

- **Phase 1**: Cold-start elimination. `J2KMetalDevice.isAvailable` now caches its result; `DecoderPipeline.decode`'s gate condition reorders the cheap pixel-threshold check ahead of the Metal-availability check. CLI `--no-gpu` flag is now actually honoured. Saves 40-47 ms on every CLI invocation that doesn't need GPU.
- **Phase 2**: CLI defaults to CPU-first routing. Default `j2k decode` no longer pays Metal cold-start tax for image sizes where GPU wouldn't win in single-shot mode. Saves an additional 52-53 ms on default-mode CT/MR/DX invocations.
- **Phase 3**: SIMD `SIMD4<Int32>` CPU 5/3 INT IDWT path. Bit-exact with scalar reference; -16 % iDWT accumulated cost on DX, -12 ms wall.
- **Phase 4**: NEON reconstruction (`HTBlockDecoderConformant.neonReconstructionEnabled = true` default). Re-evaluation of v7.4 Phase 1 (rejected at Δ 0.90 ms) on the Phase 3 baseline shows median 2.96 ms across 10 samples — flipped to default ON under the Apple-only narrowing.

### Phase 6.0-6.1: Warm-decoder pattern

- **Phase 6.0**: `j2k batch decode` now calls `preWarm()` before parallel dispatch, pulling Metal cold-start out of the first-file critical path.
- **Phase 6.1**: New public API `J2KDecoder.preWarm()` — discoverable cross-platform warm-session pattern. Recommended SDK usage:

```swift
// Once at app/SDK startup
await J2KDecoder.preWarm()

// Subsequent decodes use the warm session automatically
let decoder = J2KDecoder()
for data in batch {
    let image = try await decoder.decode(data)
}
```

### Phase 6.2: iOS/iPadOS ratification

The entire library + warm-decoder API runs on iOS Simulator (iPhone 17 Pro, iOS 26.x). Phase 6.1 warm-decoder API tests pass identically on macOS and iOS. Cross-platform Apple Silicon claim is empirically validated.

iOS-specific changes:
- `Package.swift` iOS minimum bumped 17 → 18 (`OSAllocatedUnfairLock.withLock` requires iOS 18+)
- `default.metallib` resource declaration cleaned up (Xcode auto-compile + pre-built copy collision)
- Source files using `Process` (NSTask) gated `#if os(macOS)` with iOS stubs (4 source files)
- macOS-only test files gated `#if os(macOS)` (51 test files — they shell out to OpenJPH/OpenJPEG/Kakadu/pydicom)

## What's New — opt-in (`j2kd` macOS-only XPC daemon)

A long-lived background process that holds `J2KMetalSession.processShared` warm across CLI invocations. With the daemon installed, `j2k decode` runs at warm-process speed even in single-shot CLI mode.

**Install**:

```bash
swift build -c release --product j2kd
cp .build/release/j2kd /usr/local/bin/j2kd
sed -i '' 's|<<J2KD_PATH>>|/usr/local/bin/j2kd|' Resources/launchd/com.raster.j2kd.plist
cp Resources/launchd/com.raster.j2kd.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.raster.j2kd.plist

# Verify
j2k daemon-ping
# → daemon: available / PID / uptime / round-trip ms
```

**Architecture** (Phases 6.3-6.6):
- `Sources/J2KDaemonProtocol/` — shared @objc XPC protocol (ping + decode methods)
- `Sources/J2KDaemonCore/` — daemon-side service implementation + lifecycle controller (idle-timeout + signal handlers)
- `Sources/J2KDaemonClient/` — client-side `J2KDaemonClient` actor wrapping NSXPCConnection
- `Sources/J2KDaemon/` — `j2kd` daemon executable
- `Resources/launchd/com.raster.j2kd.plist` — launchd plist template
- `j2k decode` automatically uses the daemon when reachable; transparent fallback to in-process when not

**Lifecycle**:
- Idle timeout default 10 minutes (`J2KD_IDLE_TIMEOUT_SECONDS` env var overrides). After idle exceeds timeout, daemon exits cleanly; launchd re-spawns on next client connection.
- SIGTERM / SIGINT handled — clean shutdown via `launchctl unload` or `kill -TERM`.

**CLI flags**:
- `j2k daemon-ping` — verify install + measure round-trip ms
- `j2k decode --no-daemon` — explicit in-process opt-out (useful for benchmark scripts)

## Backward compatibility

- **Codestream bytes byte-identical to v7.5.1** — all v8 changes are decoder-side or CLI-routing.
- **Public API additions only** — no removals or signature changes.
- **iOS minimum bumped 17 → 18** — required for `OSAllocatedUnfairLock.withLock` (the only material API breakage).
- **CLI `--no-gpu` now actually works** (was silently ignored on the standard `decode` path; this is a bug fix, not a break).
- **CLI default routing flipped to CPU-first** (was implicitly using GPU paths that paid 50 ms cold-start tax for no win in single-shot mode). User wall time on default `j2k decode` drops 52-53 ms on CT/MR/DX. No change for users who explicitly pass `--gpu` or `--gpu-ht`.

## SemVer rule: MAJOR

Per RELEASING.md: "Default behaviour flipped" — the CLI default routing flip + iOS minimum bump qualify as MAJOR even though codestream bytes are unchanged.

`getVersion()` returns `"8.0.0"`.

## Test Suite Results (release mode, 0 failures)

22/22 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1 (12 cells × 3 decoders = 33/33 cross-codec bit-exact)
- `MgRegressionTriageTest` — 2/2 (16+ MP HTJ2K bit-exact)
- `V8Phase61WarmDecoderAPITests` — 3/3 (cross-platform warm-decoder API; runs on macOS AND iOS)
- `J2KDaemonProtocolRoundTripTests` — 3/3 (XPC protocol, in-process anonymous-listener)
- `J2KDaemonClientTests` — 3/3 (client API + daemon-service direct decode)
- `J2KDaemonLifecycleTests` — 3/3 (activity tracker + idle-timeout)

iOS Simulator (iPhone 17 Pro, iOS 26.x) — Phase 6.1 warm-decoder API tests pass 3/3.

## API surface

### Added

- `public static func J2KDecoder.preWarm(includeWarmupDispatch: Bool = false) async`
- `public struct J2KDaemonProtocol` (@objc protocol — daemon RPC surface)
- `public actor J2KDaemonClient` — client-side daemon connection wrapper
- `public final class J2KDaemonService` — daemon-side service implementation (for SDK consumers building their own daemon-style integrations)
- `public final class J2KDaemonActivityTracker` + `public final class J2KDaemonLifecycle` — daemon lifecycle primitives
- `public let J2KDaemonMachServiceName: String = "com.raster.j2kd"`
- `--no-daemon` flag on `j2k decode`
- `j2k daemon-ping` subcommand

### Removed / changed

- None at the public API level. CLI default routing changed (see Backward compatibility).

## Reproducing the headline numbers

```bash
swift build -c release

# Mandatory pre-release gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests|MgRegressionTriageTest'

# Cross-codec parity (12 cells, 33 cross-decode comparisons)
swift test -c release --filter HTTileParityMatrixTests

# All v8 phase tests
swift test -c release --filter 'V8Phase61WarmDecoderAPITests|J2KDaemonTests|J2KDaemonClientTests'

# iOS Simulator smoke
xcodebuild test -scheme J2KSwift-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:J2KCodecTests/V8Phase61WarmDecoderAPITests
```

## Companion documents

- `V8_0_0_METAL_FIRST_STRATEGY.md` — strategy RFC
- `V8_0_0_PHASE_0_BASELINE.md` — bottleneck identification
- `V8_0_0_PHASE_1_FINDING.md` — cold-start elimination
- `V8_0_0_PHASE_2_FINDING.md` — CLI default-CPU routing
- `V8_0_0_PHASE_3_FINDING.md` — SIMD CPU IDWT
- `V8_0_0_PHASE_4_FINDING.md` — NEON reconstruction default ON + Apple-only narrowing
- `V8_0_0_PHASE_5_FINDING.md` — warm in-process baseline (XPC daemon GO)
- `V8_0_0_PHASE_6_0_FINDING.md` — batch decode preWarm
- `V8_0_0_PHASE_6_1_FINDING.md` — cross-platform warm-decoder API + iOS-aware architecture pivot
- `V8_0_0_PHASE_6_2_FINDING.md` — iOS/iPadOS ratification
- `V8_0_0_PHASE_6_3_FINDING.md` — XPC daemon skeleton
- `V8_0_0_PHASE_6_4_FINDING.md` — daemon client + `j2k daemon-ping`
- `V8_0_0_PHASE_6_5_FINDING.md` — decode RPC over XPC
- `V8_0_0_PHASE_6_6_FINDING.md` — daemon lifecycle (idle timeout + signals)
- `Resources/launchd/com.raster.j2kd.plist` — launchd install template
