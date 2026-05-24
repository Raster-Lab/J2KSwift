# v10.19-research — JP3D GPU iDWT (closed — wash + regression)

**Branch:** `v10.19-research` · **Status:** closed wash · 2026-05-24

Originated from the v10.18-research finding doc's "GPU iDWT for JP3D"
open follow-up. Investigated whether wiring or enabling GPU iDWT on
the JP3D decode path delivers the same 1.5–2× wins the 2D codec got
in v10.1.0 / v10.3.0. **It does not** — the slice-stack architecture
makes per-slice GPU dispatch overhead the dominant cost on every
typical JP3D fixture.

## Two interpretations, both negative

### (a) "Wire `JP3DMetalDWT` into JP3D" — dead code

The `JP3DMetalDWT.swift` Metal kernels (`inverse53X`, `inverse97X`,
forward variants) are scoped to the **true 3D wavelet transform**
path orchestrated by `JP3DWaveletTransform.inverse(decomposition:)`.

That path is never reached in production:
- `JP3DEncoder` emits slice-stack codestreams (`'J3DS'` magic) exclusively
- `JP3DDecoder.decode` line 208 hard-routes every tile through
  `JP3DSliceStackCodec` based on the `'J3DS'` magic check
- `JP3DWaveletTransform` is referenced only by `inverseWaveletTransform`
  helpers in `JP3DDecoder.swift:417` + `JP3DROIDecoder.swift:364` —
  both helpers are unreached in the slice-stack tile-dispatch branch

Wiring `JP3DMetalDWT` into a path no codestream ever takes is
zero-impact work. **Closed without code change.**

### (b) Force per-slice 2D GPU iDWT — measurable REGRESSION

The slice-stack codec calls `J2KDecoder.decode(codestream)` per slice.
The 2D codec gates GPU iDWT on `_gpuInverse53PixelThreshold = 4 MP`;
typical JP3D slices (256×256, 512×512, 1024×1024) all sit below 4 MP
and go CPU iDWT today.

A/B test (commit on this branch, reverted before merge):

```swift
// JP3DSliceStackCodec.decode — env-gated route:
if Self.forceGPUIDWTEnabled {
    image = try await decoder.decodeGPU(codestream)   // force GPU iDWT
} else {
    image = try await decoder.decode(codestream)      // default — threshold-gated
}
```

`J2K_JP3D_FORCE_GPU_IDWT=1` enabled the route. M2 release,
`J2KBenchMac --jp3d --quick`:

| Fixture | Slices | full ms (CPU iDWT) | full ms (GPU iDWT) | Δ |
|---|---:|---:|---:|---:|
| mr_3d_small (262K vox) | 16 | 14.21 | 14.01 | wash |
| ct_3d_small (1M vox)   | 16 | 45.16 | 45.53 | wash |
| mr_3d_mid (2M vox)     | **32** | 90.42 | **122.85** | **+32 ms regression** |

The regression scales precisely with slice count: 32 slices × ~1 ms
GPU dispatch overhead ≈ +32 ms total — matching observation. The
2D codec's 4 MP threshold exists for exactly this reason; in JP3D
that overhead multiplies by slice count, making the regression
worse, not better.

## Root cause — per-slice independent GPU dispatch × N slices

Each slice in `JP3DSliceStackCodec` is decoded as a fully-independent
2D J2K codestream. There is no current API or kernel path to batch
N slices into a single GPU dispatch — the slice-stack codec calls
the 2D `J2KDecoder` actor's `decode` (or `decodeGPU` /
`decodeResolution` / `decodeRegion`) one slice at a time, and each
call pays its own GPU launch overhead.

Per-slice GPU dispatch overhead × 16–64 slices > whatever CPU iDWT
saves per slice. This is structural.

## The only path to a real win

**Batched single-dispatch GPU iDWT for N slices** — extend
`J2KMetalDWT` (or write a new `JP3DBatchedMetalDWT`) with a kernel
that accepts N slices' coefficient buffers and submits one Metal
dispatch executing N parallel iDWTs. Requires:

- Significant J2KMetal-layer extension (new kernel + threadgroup
  layout that maps slice index onto Z)
- Slice-stack codec refactor — collect N decoded entropy outputs
  (not yet iDWT'd) into a batched buffer, submit one dispatch,
  scatter results
- Or — entropy + iDWT both batched (closer to what the GPU HT
  redesign attempted in v10.17 for HT entropy)

Multi-week, high risk, structurally similar to the v10.17 GPU HT
redesign that closed as structurally blocked. Not a near-term arc.

## Strategic recommendation

Per `project_v10_8_dxpx_wash.md`: "Strategic recommendation: pivot
to cross-silicon positioning (M4 already wins) or product-layer
wins (DICOM fast-path) — don't expect more from codec hot-path
tuning."

The chip-aware `recommendedDecodeAPI` router (3 silicons of data
already, including A19 which wants `.decodeWithGPUHT` at ≥15 MP) is
the most concrete next codec arc. The real-medical-fixture iOS
bundling is the most concrete product-layer arc.

## Why this entry exists at all

This is the 12th independent investigation that arrived at the same
"M2 + Swift release lever ceiling" — but for the JP3D-specific case.
Documented here so future sessions don't re-derive the same result;
the v10.18 finding doc's "GPU iDWT for JP3D" follow-up has been
moved from open to closed-wash. The `J2K_JP3D_FORCE_GPU_IDWT` env
flag is **not committed** — the A/B was a research-only check on
this branch, reverted before merge.
