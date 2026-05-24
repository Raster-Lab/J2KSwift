# v10.20-research — JP3D batched GPU iDWT

**Branch:** `v10.19-research` · **Status:** Phase 0–3b shipped;
Phase 3c/3d/4 open · started 2026-05-24

The multi-week JP3D batched GPU iDWT arc — the only path to a GPU
iDWT win on JP3D after v10.19 closed naive per-slice GPU iDWT
routing as a structural regression. **Headline result: 2.4× faster
kernel-level dispatch** (16 slices × 256×256 × 3 levels, M2 release).
**Open issue: bit-exact integration with the production CPU per-
level iDWT path** needs root-cause + parity-safe wiring before the
kernel win reaches the end-to-end JP3D decode wall.

## Phase status

| Phase | Scope | Commit | Tests | Result |
|---|---|---|---|---|
| 0 | Feasibility verdict — can the pipeline split? | (doc) | — | 🟢 GREEN |
| 1 | JP3D bridge SPI: `_jp3dDecodeToCoefficients` + `_jp3dIDWTAndFinalize` | `1fa3a95` | 5/5 PASS | Bit-exact composition: `decode(data) ≡ bridge(decodeToCoefs(data))` |
| 2 | Batched single-level Metal kernel + Swift API | `f3a6693` | 7/7 PASS | Bit-exact vs serial GPU single-image |
| 3a | Multi-level batched orchestrator | `01eebb3` | 12/12 PASS | **2.4× faster** on M2 release (4.94 → 2.06 ms) — measured kernel-level |
| 3b | Bridge SPI batched variant `_jp3dIDWTAndFinalizeBatched` | `ed73a96` | 5/5 PASS | SPI surface ships; implementation = serial loop (parity-safe) |
| 3c | `JP3DSliceStackCodec` wiring | — | — | **Open** — refactor with no perf change until 3d, deferred |
| 3d | Parity-safe orchestrator integration | — | — | **Open** — root-cause CPU-vs-GPU iDWT divergence on real data |
| 4 | JP3D bench A/B + ship | — | — | **Open** — conditional on 3d |

## The 2.4× measured win

**`J2KMetalDWT.inverse2DInt32MultiLevelFusedBatched`** on M2 release:

| Fixture | Serial (16× per-slice dispatch) | Batched (1× multi-level dispatch) | Ratio |
|---|---:|---:|---:|
| 16 slices × 256×256 × 3 levels | 4.94 ms | **2.06 ms** | **0.42× (= 2.4× faster)** |

This is the per-slice GPU dispatch overhead amortisation that
`V10_19_JP3D_GPU_IDWT_CLOSED.md` identified as the only structural
path to a real GPU iDWT win on JP3D. The kernel + orchestrator
proves the architecture works at the Metal layer.

## Open issue — Phase 3d

When integrating the batched orchestrator through the JP3D bridge
SPI, the output diverges byte-for-byte from the serial bridge SPI
(`_jp3dIDWTAndFinalize`) on **real codestream coefficient data**.
Symptoms:

- Phase 3a parity tests (`V10_20_BatchedInverseInt32ParityTests`) use
  synthetic LCG-noise subbands with limited magnitude range — **12/12
  PASS** comparing batched GPU vs serial GPU multi-level fused (both
  Metal paths).
- Phase 3b parity tests (`V10_20_BatchedBridgeParityTests`) compare
  batched bridge SPI vs serial bridge SPI on real codestream data —
  **bytes diverge byte-for-byte**, slice 0 onwards, every fixture.
- The serial bridge SPI calls `applyInverseWaveletTransform`, which
  routes to the **CPU per-level iDWT path** by default since v10.3.0
  flipped `_gpuHTEntropyEnabled` to OFF.

So the divergence is **GPU multi-level fused** vs **CPU per-level**
iDWT, on real coefficient data. Both are spec-required to be bit-
exact equivalent for 5/3 reversible; there's an existing 9-fixture
cross-test suite (`V10_3_V82BypassCrossCodecCheck`) proving this is
true in normal production flow. So either:

1. The Phase 3a orchestrator's GPU-resident chain (output → next LL)
   produces subtly different intermediate values vs the per-level
   CPU readback chain on certain coefficient ranges.
2. The bridge SPI's `iDWTAndFinalizeCoefficients` finalize path
   differs in a way that mid-pipeline rounding accumulates
   differently than the production `decodeSingleTile` flow.

**Root-causing strategies for Phase 3d**:

- A. Bisect: compare GPU multi-level fused output vs CPU per-level
  output on a single fixture, print divergent samples + their
  pre-iDWT subband values. Should pinpoint whether the divergence
  is in iDWT math or downstream finalize.
- B. Write a parity test specifically for the JP3D-real flow:
  `inverse2DInt32MultiLevelFused(real_subbands)` vs serial per-level
  `inverse2DInt32(real_subbands, backend: .cpu)`. If these diverge,
  the bug is pre-existing (GPU vs CPU iDWT on real data); fix at the
  J2KMetal layer, not the v10.20 arc.
- C. If (B) shows they match, then my Phase 3a batched orchestrator
  has a subtle bug not caught by synthetic LCG tests — likely in
  the per-slice buffer striding or the level-chain GPU-resident
  reuse.

## What Phase 3b ships

The bridge SPI **surface** is ready and tested:

```swift
public func _jp3dIDWTAndFinalizeBatched(
    _ coefsBatch: [JP3DSliceCoefficients]
) async throws -> [J2KImage]
```

Current implementation = serial loop (delegates per-slice to
`_jp3dIDWTAndFinalize`). Bit-exact correctness guaranteed. No
performance change vs Phase 1.

Once Phase 3d resolves the orchestrator parity, the implementation
swaps in the 2.4× faster batched path — callers see only a perf
improvement, no API change.

## Cumulative test surface

| Suite | Tests | What it proves |
|---|---:|---|
| `V10_20_JP3DBridgeParityTests` | 5/5 PASS | Phase 1 bridge SPI bit-exact composition |
| `V10_20_BatchedInverseInt32ParityTests` | 12/12 PASS | Phase 2 + 3a batched kernel + orchestrator bit-exact vs serial GPU |
| `V10_20_BatchedBridgeParityTests` | 5/5 PASS | Phase 3b batched bridge SPI bit-exact (via serial-loop impl) |
| **Total** | **22/22 PASS** | Architecture proven; integration parity is the open work |

## Next session

Pick from:
- **3d-A**: Root-cause CPU-vs-GPU iDWT divergence (bisect on real
  coefficient data). If a fix is found, swap orchestrator into
  Phase 3b SPI, then proceed with Phase 3c JP3D wiring + Phase 4 bench.
- **3d-B**: Investigate whether the issue is genuinely a J2KSwift
  pre-existing GPU vs CPU iDWT bug — if yes, file it as a separate
  fix and the v10.20 arc unblocks naturally once it lands.
- **Park**: Leave the 2.4× kernel-level win as research artifact,
  ship the v10.20 codec without batched JP3D iDWT, pivot to another
  arc (chip-aware router, real DICOM bundling, etc.).
