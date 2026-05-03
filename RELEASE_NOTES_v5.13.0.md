# J2KSwift v5.13.0 — `default.metallib` bundled

**Release date:** 2026-05-03
**Theme:** Closes the cold-CLI shader-source-compile cost flagged in v5.6.0.

## What's in this release

The v5.6.0 perf report flagged the ~50 ms shader-source-compile cost on every cold process startup. The runtime infrastructure to load a pre-compiled `default.metallib` instead of source-compiling has been wired since v5.6.0 (`device.makeDefaultLibrary(bundle: .module)` in `J2KMetalShaderLibrary.loadShaders`), but the metallib itself was never built — SwiftPM doesn't auto-compile `.metal` files under `swift build` (only Xcode does), so the bundle only ever contained the source.

v5.13.0 ships a pre-compiled `default.metallib` checked in to `Sources/J2KMetal/`, declared as a `.copy()` resource in `Package.swift`. `device.makeDefaultLibrary(bundle: .module)` now succeeds at runtime and the source-compile fallback is no longer hit on production builds.

(This was the v5.15 plan item from the UMA optimisation roadmap. Ships as v5.13.0 because project versioning is sequential. The plan's v5.13/v5.14 — GPU MCT fusion and 9/7 lossy fast-lane — remain unimplemented per `V5_12_PLUS_OVERNIGHT_STATUS.md`; the metallib infrastructure is independent.)

## Workflow change for contributors

When `Sources/J2KMetal/J2KShaders.metal` changes, regenerate the metallib:

```
Scripts/build_metallib.sh
```

The script requires the Metal Toolchain. Install once:

```
xcodebuild -downloadComponent MetalToolchain
```

Commit the regenerated `Sources/J2KMetal/default.metallib` alongside the .metal change. Without this, the metallib will be stale (still loads, but with the previous version's kernels) — the `J2KMetalLibraryLoadPathTests` gate doesn't catch source/metallib drift.

## Perf

Cold-CLI start (`j2k decode --gpu-ht` on a 512×512 HTJ2K input):

| run | with metallib (v5.13.0) | source-compile (pre-v5.13) |
| ---:| ---:| ---:|
| #1 (cold) | 0.29 s | 0.32 s |
| #2-5 (warm) | 0.08 s | 0.08 s |

~30 ms savings on the cold first run. Warm runs are unchanged because the Metal driver caches the compiled library either way.

The savings show up on the **first call into Metal in a new process** — relevant for batch-processing scripts that spawn a new `j2k` process per file. Long-running processes (e.g. apps that decode many images in one session) see no warm-run difference; v5.6.0's `J2KMetalSession` opt-in remains the right tool there.

## Verification

- **`J2KMetalLibraryLoadPathTests.testBundledMetallibIsLoaded`** — asserts `J2KMetalShaderLibrary.loadPath == .metallib` after `loadShaders`. Catches accidental regression if the metallib goes missing or stops shipping.
- **`J2KMetalLibraryLoadBenchTests.testLoadShadersBench`** — opt-in (`J2K_BENCH_LIBRARY_LOAD=1`) bench that reports median load time over 10 runs. Useful for spotting regressions that re-route through source-compile.

All v5.12.0 bit-exactness gates continue to pass byte-for-byte (the metallib produces the same compiled kernels as source-compile).

## What this release does not change

- **Sessionless / session decode behaviour** — identical to v5.12.0. The metallib is a startup optimisation; the loaded MTLLibrary object behaves identically whichever path produced it.
- **Cross-platform behaviour** — non-macOS / non-iOS targets that don't have the metallib bundled (or where `Bundle.module.url(forResource:withExtension:)` returns nil) fall through to source-compile. Same fallback as before.
- **Encoder paths** — v5.13 is decoder-side. Encoder shader loading uses the same `J2KMetalShaderLibrary` path, so it picks up the metallib transparently.

## Build env requirement (one-time)

Install the Metal Toolchain on any build machine that needs to regenerate the metallib:

```
xcodebuild -downloadComponent MetalToolchain
```

Without it, `Scripts/build_metallib.sh` errors out with a clear message. Build machines that don't regenerate (just consume the checked-in metallib) don't need the toolchain.
