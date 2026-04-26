# JP3D vs OpenJPEG — Medical-Grade Beat Plan

**Branch**: `feature/jp3d-beat-openjpeg` (from `main` @ 7124682)
**Started**: 2026-04-25
**Reference codec**: OpenJPEG 2.0.1 JP3D (`opj_jp3d_compress` / `opj_jp3d_decompress`, 3D-EBCOT)
**Dataset**: `LocalDatasets/medical-dicom-organized/` (CT, MR, XA, DX, MG — real DICOM studies)
**Hardware**: Apple Silicon (arm64e), macOS 14.6

Mirror of the 2D head-to-head work in [BEAT_OPENJPEG.md](../BEAT_OPENJPEG.md) (J2KSwift HTJ2K won 24/24 by 45×–810×), adapted for JP3D (ISO/IEC 15444-10, volumetric).

## M1 — Infrastructure + baseline diagnosis (DONE 2026-04-25)

### Cross-codec acquired

OpenJPEG removed JP3D after v2.0.1 — it is not in any current Homebrew package.
[Scripts/setup-jp3d-openjpeg.sh](../Scripts/setup-jp3d-openjpeg.sh) clones
OpenJPEG v2.0.1, builds `opj_jp3d_compress` and `opj_jp3d_decompress` only
(`BUILD_JP3D=ON`, static libs, `-O3`), and installs them under
`$HOME/.j2kswift-tools/jp3d/bin/`. `--skip-if-present` makes reruns no-ops.

### Medical-grade volume pipeline

[Scripts/prep_jp3d_volume.py](../Scripts/prep_jp3d_volume.py) reads a DICOM
series, checks consistency (same rows/cols/bits per slice, `PixelRepresentation`),
and writes three artefacts from identical pixel data:

- `<base>.bin` — raw little-endian uint16 voxels, slice-major
- `<base>.img` — OpenJPEG `.img` header (Bpp / Color Map / Dimensions / Resolution)
- `<base>.meta` — JSON metadata (w/h/d/bit-depth/signed/spacing) for the driver

The same `.bin` is fed to both codecs: J2KSwift's raw-mode reads bytes verbatim,
and OpenJPEG's `bintovolume` reads native LE uint16 when `bigendian=0` (the
hard-coded default in `src/bin/jp3d/convert.c`).

### Head-to-head harness

[Scripts/jp3d_beat_openjpeg.sh](../Scripts/jp3d_beat_openjpeg.sh) orchestrates:

1. Prepare the CT volume (idempotent, cached in `/tmp/jp3d_bench/`)
2. Run J2KSwift encode3d → decode3d → bit-exact check
3. Run `opj_jp3d_compress -C 3EB -r 1` → `opj_jp3d_decompress` → bit-exact check
4. Report ratio / encode time / decode time / bit-exact PASS for both codecs
5. Gate on medical-grade targets: bit-exact required, ratio ≥ OpenJPEG,
   encode ≥ 1.5× faster, decode ≥ 1.5× faster

Critical finding about the reference codec: OpenJPEG JP3D's **default entropy
coder (`-C 2EB` = 2D-EBCOT) is lossy even at `-r 1`** — only `-C 3EB` (3D-EBCOT)
is truly lossless for volumetric input. The harness always passes `-C 3EB -r 1`
to keep the comparison apples-to-apples on lossless CT.

### Baseline results on CT study_001, 512×512×16 @ 16bpv

```
 metric                 J2KSwift       OpenJPEG       J2K vs OpenJPEG
 ---                    ---            ---            ---
 encoded bytes          16,777,358     2,389,562      (raw = 8,388,608)
 compression ratio      0.5000:1       3.5105:1       0.1424× (7× WORSE)
 encode time (min)      0.61 s         0.76 s         1.25× speedup (below 1.5× target)
 decode time (min)      0.29 s         0.78 s         2.69× speedup ✓
 lossless bit-exact     PASS           PASS
```

### Root cause

[Sources/J2K3D/JP3DEncoder.swift:387-392](../Sources/J2K3D/JP3DEncoder.swift#L387-L392)
— the non-HTJ2K encode path writes quantized 3D coefficients as raw
big-endian `Int32`:

```swift
for coeff in quantized.coefficients {
    var value = coeff.bigEndian
    tileBytes.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
}
```

That produces 4 bytes per voxel regardless of magnitude, hence the 0.5:1
"compression" (actually 2× bloat vs the 2-byte-per-voxel 16-bit raw input).
The HTJ2K-mode path has the same shape at
[Sources/J2K3D/JP3DHTJ2K.swift:409-422](../Sources/J2K3D/JP3DHTJ2K.swift#L409-L422)
(`encodeHTCoefficients` writes a `zbp` prefix then raw BE Int32 per
coefficient — no real HT block coding).

Both JP3D paths are **entropy-coder stubs**. The surrounding structure
(tiling, 3D DWT, quantization, codestream markers, packet formation) is in
place and correct, but the code-block coder is a placeholder.

## M2 — Wire real entropy coding into JP3D (next)

Fix options, roughly ordered by scope:

1. **Per-subband 2D EBCOT**: code-block the 3D DWT output by 2D slabs
   (`b=Bx×By×1` per-Z-slice), call the existing J2KCodec tier-1 EBCOT
   per slab. Matches OpenJPEG JP3D's `-C 2EB` mode. Requires lifting
   `J2KCodec.BlockEncoder` / `BlockDecoder` to public (or moving
   `JP3DEncoder` into `J2KCodec`).

2. **Reuse J2KSwift HTJ2K block coder**: JP3D's J2K-mode writes HT blocks
   too if the codestream signals Part-15 capability. Given J2KSwift's
   HT encoder already wins 45×–810× in 2D (see [BEAT_OPENJPEG.md](../BEAT_OPENJPEG.md)),
   this is the highest-leverage entropy path. Same plumbing as (1) but
   call the HT block coder.

3. **3D-EBCOT from scratch**: faithful to OpenJPEG's `-C 3EB` — adds a
   Z-axis context to the block coder. Highest fidelity to the standard
   but weeks of work; worth deferring until (1)/(2) is proven.

Either (1) or (2) unblocks the medical-grade targets:

- Ratio: entropy coding recovers the ~7× factor; real medical CT has
  more structure than the synthetic gradient where OpenJPEG hit 16.87:1.
- Encode speed: J2KSwift's EBCOT already beats OpenJPEG's 1.5–13× in 2D;
  the same tier-1 hot path should carry 3D.
- Decode speed: already winning (2.69×) even on the coefficient-dump path,
  because decode is just reading 4 bytes per voxel — option (1)/(2) will
  slow decode down but still beat OpenJPEG's decode by a wide margin.

## M3 — Medical-grade validation report

Once M2 lands, re-run the harness across the full medical-dicom-organized
matrix (CT × 5 studies, MR × 5, XA, plus lossy-8:1 / lossy-20:1 points
where PSNR ≥ 50 dB is the medical-grade floor) and generate
`JP3D_CLINICAL_VALIDATION.md` modelled on [CLINICAL_VALIDATION_REPORT.md](../CLINICAL_VALIDATION_REPORT.md).

Release gate: 24/24 comparisons beat OpenJPEG on every medical-grade metric.
