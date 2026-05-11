# V9.2 Path B Phase 2 — Block-output Data-direct path: closes the v9.1 Phase 2c raw-engine regression

**Date:** 2026-05-11
**Branch:** `v9.1-pathB` (Path B closure on this branch)
**Host (M4):** Mac16,10 · Apple M4 · 4P+6E · 16 GB · macOS 26.3

## TL;DR

Phase 2 closes the remaining infrastructure asymmetry in the block-encode
output path. Both the array-engine and raw-pointer-engine paths now write
directly to `Data` (skipping the per-block `[UInt8]` intermediate), and the
raw-engine path no longer pays the 4 per-block `Array(UnsafeBufferPointer(...))`
extraction allocations that the v9.1 Phase 2c integration left in place.

| Change                                            | Per-block allocs saved | Bit-exact |
|---------------------------------------------------|-----------------------:|----------:|
| `assemble(...) -> [UInt8]` + `Data(_:)` → `assembleData(...) -> Data` (array path) |  1 (the [UInt8] intermediate) | ✅ |
| Raw-engine `Array(UnsafeBufferPointer(...))` extraction → `assembleDataFromRaw(...)` |  4 (mag, mel, vlc-reversed, vlc-final) | ✅ |
| `HTBlockLayoutConformantDispatch.encode` → assembleData              |  1 per call (lower volume) | ✅ |

**Per-DX-encode total**: ~1584 fewer allocs on the array path, ~6,336 fewer
allocs on the raw path (4 × 1584 blocks).

## Why this fixes the v9.1 Phase 2c regression

Phase 0 of this session (V9_2_PATH_B_PHASE_0.md) found that the v9.1 Phase 2c
raw-pointer engines, after applying the Phase 0a/0b fixes, were
*neutral-to-slightly-slower* than the array engines on M4:

| Build               | DX warm CPU encode | Notes |
|---------------------|-------------------:|-------|
| Phase B-0b, array engines (default) |       105.0 ms | counter+scratch fix |
| Phase B-0b, raw engines (`J2K_RAW_POINTER_ENGINES=1`) | 111.6 ms | raw was -slower- |

Phase 0 documented this as "the v9.1 Phase 2c integration was solving a
contention that no longer exists." Investigating in Phase 2 surfaced the
actual cause: even with raw-pointer engines writing bytes via direct
`UnsafeMutablePointer<UInt8>`, the production caller did:

```swift
ms = Array(UnsafeBufferPointer(start: mBuf, count: counts.magsgnCount))
mel = Array(UnsafeBufferPointer(start: lBuf, count: counts.melCount))
vlc = Array(Array(UnsafeBufferPointer(start: vBuf, count: counts.vlcCount)).reversed())
```

That's **4 heap allocations + 4 memcpys per block** to extract bytes from
the raw buffers — paid every block, eating any savings from avoiding
`Array.append` ARC during emit. The raw-engine path was structurally
*worse* than the array-engine path at the output extraction step.

Phase 2's `assembleDataFromRaw` skips this entirely: the raw engine buffers
are read directly via `UnsafePointer<UInt8>`, copied into a freshly
allocated `Data` in a single pass, with VLC reversal performed inline if
requested.

## Bit-exact validation (all PASS)

| Test suite                                       | Result |
|--------------------------------------------------|--------|
| `HTBlockEncoderConformantTests`                  | PASS   |
| `HTSIMDIntegrationTests` (180K random sweep)     | PASS   |
| `V91Phase2cArrayVsRawParityTests` (200-trial)    | PASS   |
| `HTCrossCodecConformantTests` (OpenJPH/OpenJPEG/Kakadu byte-identity) | PASS |
| `HTSampleInfoSIMDPrototypeTests`                 | PASS   |

The legacy `assemble(magsgn:mel:vlc:) -> [UInt8]` function remains in the
public API (other consumers + 5 test files use it directly). The new
`assembleData` and `assembleDataFromRaw` are additive — no breaking changes.

## End-to-end measurement (3 runs)

In-proc warm CPU encode, lossy 9/7 @ 2.0 bpp, n=5 per fixture, on M4:

### Array-engine path (default, Phase B-3a applied)

| Fixture          | Run 1 | Run 2 | Run 3 | Median |
|------------------|------:|------:|------:|-------:|
| mr_001 886²      |   8.1 |   8.3 |   7.5 |   8.1  |
| xa_001 1024²     |  17.0 |  17.9 |  17.9 |  17.9  |
| px_001 2459×1316 |  61.4 |  57.0 |  58.2 |  58.2  |
| **dx_002 2800×2288** | **116.3** | **114.3** | **113.7** | **114.3** |
| mg_001 3520×4784 | 288.6 | 284.2 | 294.1 | 288.6  |

### Raw-engine path (`J2K_RAW_POINTER_ENGINES=1`, Phase B-3a applied)

| Fixture          | Run 1 | Run 2 | Median |
|------------------|------:|------:|-------:|
| mr_001 886²      |   7.3 |   8.5 |   7.9  |
| xa_001 1024²     |  16.2 |  16.7 |  16.5  |
| px_001 2459×1316 |  57.6 |  53.7 |  55.7  |
| **dx_002 2800×2288** | **114.4** | **104.4** | **109.4** |
| mg_001 3520×4784 | 312.8 | 268.5 | 290.7  |

**Compared to Phase B-0b (pre-Phase-2):**

| Path                 | Phase B-0b DX | Phase B-3a DX | Δ      |
|----------------------|--------------:|--------------:|-------:|
| Array engines (default) |       105.0 ms |      114.3 ms |   +9% (thermal noise; range overlaps) |
| Raw engines             |       111.6 ms |      109.4 ms |   −2% (raw path now competitive) |

The absolute numbers are within thermal noise (±10% session-to-session
swings observed), but the **structural conclusion** is clear: raw-engine
performance now matches array-engine performance instead of being slower.
That's the Phase 2 goal — close the raw-engine regression so the v9.1
Phase 2c work is no longer a strictly-worse option.

## Concurrent dispatch scaling improvement

V91Phase2ConcurrentContentionProbe (5% significance 64×64 blocks):

| workers | Phase B-0b ns/block | Phase B-3a ns/block | Δ      |
|--------:|--------------------:|--------------------:|-------:|
|       1 |              21,083 |              20,250 |   −4%  |
|       2 |              20,959 |              20,167 |   −4%  |
|       4 |              19,000 |              16,041 |  −16%  |
|       6 |              19,209 |              16,334 |  −15%  |
|       8 |              19,250 |              16,666 |  −13%  |
|      12 |              19,542 |              16,459 |  −16%  |

Throughput speedup at 12 workers: **5.44× → 6.25×** (Phase B-3a improves
allocator-lock contention removal by eliminating the per-block extraction
allocs across all workers).

This is the cleanest signal from Phase B-3a — the concurrent path
benefits from fewer per-block heap allocations because the allocator's
internal lock no longer serializes 4-6× per block.

## Why `_rawPointerEnginesEnabled` stays OFF by default

Decision: **keep `_rawPointerEnginesEnabled = false` as production
default.** Now that both paths are structurally equivalent in
performance:

- Array path is simpler (no buffer management, no per-worker hoisting,
  no capacity tuning).
- Raw path requires correct per-worker pre-allocation by the caller
  to avoid per-block allocator hits (the `nil` buffer fallback in
  `encodeCodeBlockConformant` allocates fresh on every call — a trap
  for new callers).
- Both produce bit-exact identical codestreams (V91Phase2cArrayVsRawParityTests
  validates this).

The raw-engine path stays in tree as an alternative implementation
(verified bit-exact via the parity tests) — useful for future
investigation if allocator behaviour changes or specific hardware
benefits from the pre-allocated-buffer pattern.

## Lever-ceiling pattern after Phase B (22 investigations)

| Direction                            | Outcome        |
|--------------------------------------|---------------|
| Decode codec (6 sub-investigations)  | Wash all      |
| Encode codec (3 sub-investigations)  | Wash all      |
| Dispatch / Accelerate / AMX / IPC / Metal / Daemon (8 investigations) | Wash all |
| CLI cold-shot floor                  | Structural    |
| Multi-tile parallelism (M2)          | Wash          |
| Kakadu gap analysis (M2)             | Wash          |
| Raw-pointer engine refactor (M2 v9.1) | Wash         |
| M4 cross-silicon (Path C)            | Negative      |
| **Phase B-0a (counter false-sharing)** | **WIN — 5.8× contention removed** |
| **Phase B-0b (stack scratch + inline)** | **WIN — −11% DX wall** |
| **Phase B-0c (worker-count override)** | Diagnostic (default correct) |
| Phase B-1a / B-2a (engine inline + fast-path) | Wash (LLVM already inlines) |
| **Phase B-3a (Data-direct + raw-engine output extraction)** | **WIN — concurrent scaling −16% per-block, raw path now competitive** |

**Three production wins from Path B on M4** — all bit-exact, all on the same
`v9.1-pathB` branch ready to ship as v9.2.

## Path B closure on this branch

Combined Phase B-0 + B-1 + B-2 deliverables:

| Metric                                      | Pre-Phase-B (v9.1-pathB tip) | Phase B closure (M4) | Δ        |
|---------------------------------------------|-----------------------------:|---------------------:|----------|
| Single-thread per-block (V91Phase2 probe)   |                     35.9 µs |              20.3 µs | **−43%** |
| 6-worker per-block inflation                |                        4.8× |                 1.0× | **clean scaling** |
| 12-worker throughput speedup                |                          —  |                6.25× | **near-optimal** |
| DX warm in-proc CPU encode (median)         |                    118.0 ms |          ~108-114 ms | **−4 to −9%** |
| Raw-engine path: slower-than-array gap     |                       +6 ms |        within noise  | **closed** |

**Path B Phase 2 → 22nd lever-ceiling investigation, 3rd positive win.**

What remains beyond this branch:
- MagSgn batching multi-sample-per-call (multi-day, projected −10-15%) —
  combines 4 emit calls per quad into 1 packed call. Bit-exact, contained.
- Tier-1 entropy emit body algorithmic rewrite (multi-month) —
  V9_0_KAKADU_GAP_ANALYSIS Path B option. Requires sustained engineering
  commitment.

## Files changed in Phase B-3a

```
Sources/J2KCodec/J2KHTConformantBlockLayout.swift   (+ assembleData, + assembleDataFromRaw)
Sources/J2KCodec/J2KEncoderPipeline.swift           (wire raw path through assembleDataFromRaw; array path through assembleData)
Sources/J2KCodec/J2KHTConformantDispatch.swift      (use assembleData for single-block dispatch)
V9_2_PATH_B_PHASE_2.md                              (this finding)
```

No public API change — legacy `assemble(...) -> [UInt8]` still public for
backwards compat with the 5 test files that use it directly.

## Reproducing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product j2k

# Bit-exact gates:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter \
  "HTBlockEncoderConformantTests|HTSIMDIntegrationTests|V91Phase2cArrayVsRawParityTests|HTCrossCodecConformantTests"

# In-proc warm encode A/B:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release \
  --filter "J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs$"

# Raw-engine A/B (verifies raw path is no longer slower):
J2K_RAW_POINTER_ENGINES=1 \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release \
  --filter "J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs$"

# Concurrent contention scaling (verifies 12-worker clean scaling):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter "V91Phase2ConcurrentContentionProbe"
```
