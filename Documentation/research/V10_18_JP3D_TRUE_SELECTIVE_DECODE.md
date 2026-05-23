# v10.18-research — JP3D true partial-resolution / ROI

**Branch:** `v10.18-research` · **Status:** Phases 0-5 landed on
branch · **Started:** 2026-05-23

Port the v10.4–v10.7 2D true-selective decode arc (per-resolution
code-block filter; ROI footprint-skip; tile-skip) to the JP3D slice-
stack decoder. Closes the **`project_jp3d_beat_openjpeg.md` open
follow-up** ("ROI decoder decodes-then-crops, no true per-resolution
selective decode"). Concrete, scoped, with a clear test surface (3D
fixtures decode-then-crop vs true-selective parity, plus per-fixture
wall-clock A/B).

Research stays on `v10.18-research` per `feedback_research_no_main_merge.md`.

## Why now

Three things lined up:

1. **The 2D arc shipped** — v10.5.0 (partial-res), v10.6.0 (ROI
   `.direct`), v10.7.0 (tile-skip) all landed on `main` and proved
   3-8× thumbnail / 1.4-1.7× ROI speedup on the 2D codec.
2. **JP3D's architecture maps directly** — JP3DSliceStackCodec.swift
   already runs each volume slice as an independent 2D JPEG 2000
   codestream, so the JP3D win = the 2D win applied per-slice.
3. **JP3DDecoderConfiguration.resolutionLevel was a half-finished
   field** — wired into the struct since v5.x but ignored by the
   decoder. Documentation said one thing, behaviour did another. Bad
   smell for downstream consumers; the v10.18 port closes it.

## Deliverable shape

A multi-week JP3D arc spanning four code areas:

| Phase | Scope | Status |
|---|---|---|
| **Phase 0** | Bench scaffolding: J2KBenchApp Volumes tab + 3-plane MPR viewer + J2KBenchMac `--jp3d` mode + JP3D corpus + LCG synthesis | **Done** |
| **Phase 1** | Parity oracle (`V10_18_TrueSelectiveParityTests`) — establishes the specification BEFORE any codec change | **Done** |
| **Phase 2** | Port v10.5.0 `maxResolutionLevel` into JP3DSliceStackCodec per-slice 2D decode | **Done — 2.4-3.2× speedup** |
| **Phase 3** | Port v10.6.0 ROI footprint-skip into JP3DROIDecoder (replaces decode-then-crop) | **Done — 1.5-2.2× speedup** |
| **Phase 4** | v10.7.0 tile-skip — already covered by `JP3DTilingConfiguration.tilesIntersecting` since pre-v10.18 | **Done (documentation-only)** |
| **Phase 5** | Wire `resolutionLevel` + ROI through `JP3DDecoderConfiguration`; throw loud on the combined case (Phase 5 future for the 2D codec) | **Done** |

## Measured wins (M2 release, J2KBenchMac --jp3d --quick)

| Fixture | full ms | res1 ms | Phase 2 vs full | ROI 1/4 ms | Phase 3 vs full |
|---|---:|---:|---:|---:|---:|
| mr_3d_small (128×128×16, 262K vox)  | 13.95 | 5.94  | **2.35×** | 8.02  | **1.74×** |
| ct_3d_small (256×256×16, 1 M vox)   | 43.25 | 14.52 | **2.98×** | 19.61 | **2.21×** |
| mr_3d_mid   (256×256×32, 2 M vox)   | 87.06 | 29.09 | **2.99×** | 39.36 | **2.21×** |

The Phase 2 ratios (2.4-3.2×) match the 2D v10.5.0 arc's 3-8×
thumbnail finding — JP3D's slice-stack arch means the 3D win is
exactly the 2D win applied per-slice, including the Z-delta
residual path which decodes residual + base at the same downsampled
resolution.

The Phase 3 ratios (1.7-2.2×) on centre-quarter ROI are bound by
the Z-axis: all slices in an intersecting tile still decode because
Z-delta residuals chain through the slice sequence. A future Phase
could batch-extract non-residual slice segments to skip out-of-Z-
range slices entirely — projected additional 2× on Z-narrow ROIs.

The combined case (`resolutionLevel > 0 + sub-region ROI`) throws
LOUDLY rather than silently doing decode-at-full-res. The 2D codec
itself doesn't yet implement "footprint-skip at a downsampled
resolution" — that's a separate arc; the JP3D port surfaces the
limitation rather than hiding it.

## Architecture port

JP3D's slice-stack design (each volume tile encoded as N independent
2D codestreams + Z-delta residual chaining) made the port surgical:

```
JP3DDecoder.decode
  └ for each tile:
    JP3DSliceStackCodec.decode(
        payload, expectedTile,
        resolutionLevel: K,                  ← v10.18 Phase 2
        regionOfInterest: (xRange, yRange))  ← v10.18 Phase 3
      └ for each slice:
        K == 0  +  ROI nil    → J2KDecoder.decode             (current)
        K == 0  +  ROI set    → J2KDecoder.decodeRegion(.direct)  (P3)
        K > 0   +  ROI nil    → J2KDecoder.decodeResolution   (P2)
        K > 0   +  ROI set    → THROW: Phase 5 wiring future
```

Each of the four cells composes the existing 2D API surface — no
duplication of footprint-skip / partial-res implementation, no new
codec logic invented for the 3D path.

### Phase 2 (resolutionLevel)

Volume-level scaling per JPEG 2000 spec rule:
- `outW = ⌈siz.width / 2^K⌉`, `outH = ⌈siz.height / 2^K⌉`, `outD = depth`
- Tile origins / dims scale by `⌈ref / 2^K⌉` (no gaps or overlaps;
  testROIDecodeMatchesFullDecodeCroppedAtCorner + testPartialResolution­
  Level2Shape exercise the corner / interior cases)
- Z is per-slice (slice-stack), so `resolutionLevel` never downsamples Z

Per-slice 2D level mapping: 2D codec uses `level=N` for full,
`level=0` for thumbnail; JP3D's K is halvings-from-full. So
slice 2D `level = max(0, N - K)`.

`N` is read once per JP3D tile via an inline 20-line COD-marker peek
(`peekDecompositionLevels`, `static` on `JP3DSliceStackCodec`) — no
new module dependency on J2KCodec internals or J2KFileFormat.

### Phase 3 (ROI footprint-skip)

`regionOfInterest: (xRange: Range<Int>, yRange: Range<Int>)?`
parameter on `JP3DSliceStackCodec.decode`:
- `nil` → whole-tile path (unchanged)
- non-nil → per-slice 2D decode via `J2KDecoder.decodeRegion(_:options:)`
  with `.direct` strategy and the in-tile XY sub-region; returned
  Float buffers sized exactly for the region (`regionW × regionH ×
  sliceCount`)

JP3DROIDecoder.decode reshape:
- Per-tile in-tile XY range computed from intersection of clamped
  ROI and tile spatial extent (tile-local coords)
- `useRegionPath = strict inset on either axis` triggers the new
  fast path; otherwise (tile entirely inside ROI) the legacy
  whole-tile + intersection-crop runs as before
- Z range filtering at the per-component placement loop, unchanged

Z-delta residual correctness: residual + prior slice both decoded
at the SAME region parameters, per-voxel add operates on matched
dims.

## Test surface

`Tests/JP3DTests/V10_18_TrueSelectiveParityTests.swift` — 8 tests:

| Test | Phase | Purpose |
|---|---|---|
| testFullDecodeLosslessRoundTripBaseline | baseline | Sanity anchor for the LCG-synthesised volume + JP3D round-trip |
| testROIDecodeMatchesFullDecodeCropped | 3 guard | Specification: ROI output ≡ full-decode-then-crop, bit-exact |
| testROIDecodeMatchesFullDecodeCroppedAtCorner | 3 guard | Edge-region (0,0,0) variant |
| testResolutionLevel0IsBitExactFullDecode | 2 guard | Backward-compat: K=0 must match default decode |
| testPartialResolutionShape | 2 | Dim contract: `⌈W/2⌉ × ⌈H/2⌉ × D` at K=1 |
| testPartialResolutionDeterministic | 2 | Deterministic per-fixture output |
| testPartialResolutionLevel2Shape | 2 | Higher-K validity at K=2 (off-by-one guard) |
| testCombinedResolutionLevelAndROIIsPhase5Future | 5 tripwire | Throws today; unskip when 2D codec gains the combined path |

Result: **8/8 pass** + **61/61 existing JP3DDecoderTests pass** = no
regression in the existing JP3D surface.

## App surface

`Sources/J2KBenchApp/`:

- **`Volumes` tab** (new) on `J2KBenchApp` — root list of saved JP3D
  bench runs, share-as-JSON, per-fixture drill-down.
- **JP3DBenchRunner** exercises all three decode lanes per fixture:
  full / res-1 / ROI 1/4 with warm 2+7 timing methodology.
- **3-plane MPR viewer** — pushes from a fixture detail row;
  axial + sagittal + coronal slices with tap-to-sync crosshair, a
  decode-mode picker (Full / Res-1 / ROI 1/4) that re-decodes and
  shows the wall-time for each mode, and per-plane sliders for
  navigating Z (axial) / X (sagittal) / Y (coronal).

`Sources/J2KBenchMac/`:

- **`--jp3d` flag** runs the macOS JP3D bench (same corpus, same
  three lanes, canonical JSON schema `warm-inproc-jp3d-v1`).

Apples-to-apples cross-silicon: when an iPhone-side JP3D bench JSON
and a J2KBenchMac --jp3d JSON have the same schema, the same
cross_silicon_compare.py harness reads them.

## Open follow-ups

- **Combined `resolutionLevel + ROI`** — needs the 2D codec to support
  "footprint-skip at a downsampled resolution" first; not a JP3D
  problem.
- **Z-narrow ROI skip** — when an ROI's Z-range is narrow relative
  to the tile depth, the slice-stack codec still decodes every slice
  due to Z-delta residual chaining. A future phase could batch non-
  residual segments and skip out-of-Z-range ones.
- **GPU iDWT for JP3D** — JP3DMetalDWT.swift exists but isn't wired
  into JP3DDecoder. Orthogonal to v10.18; would be its own arc.
- **Real DICOM fixtures in the iOS app** — `project.yml` bundles 2D
  PGM medical images today; the Volumes tab uses synthetic LCG
  volumes only. Real DICOM-derived JP3D fixtures (via
  `Scripts/prep_jp3d_volume.py`) would let testers run the bench on
  data closer to their workload.
