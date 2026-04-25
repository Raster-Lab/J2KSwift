# JP3D Clinical Validation Report

**Codec under test**: J2KSwift JP3D (M2 slice-stack)
**Reference**: OpenJPEG 2.0.1 JP3D (`opj_jp3d_compress -C 3EB -r 1`)
**Hardware**: Apple Silicon (arm64e), macOS 14.6
**Dataset**: `LocalDatasets/medical-dicom-organized/` (32 slices/study)
**Timing**: minimum wall-time over 2 iterations

## Headline

**7 / 7 studies meet every medical-grade pass criterion.**

Pass criteria per study:
- Bit-exact lossless round-trip (non-negotiable)
- Compression ratio within 1 % of OpenJPEG (`ratio_delta ≥ 0.99`)
- Encode wall-time at least 1.5× faster than OpenJPEG
- Decode wall-time at least 1.5× faster than OpenJPEG

## Per-study results

| Study | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ | Encode speedup | Decode J2K / OPJ | Decode speedup | Pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| CT/study_001 | 512×512×32 | 3.556:1 | 3.566:1 | 0.9973× | 560 ms / 1527 ms | **2.73×** | 655 ms / 1579 ms | **2.41×** | ✓ |
| CT/study_003 | 512×512×32 | 3.395:1 | 3.419:1 | 0.9928× | 579 ms / 1578 ms | **2.72×** | 671 ms / 1619 ms | **2.41×** | ✓ |
| CT/study_005 | 512×512×32 | 3.643:1 | 3.622:1 | 1.0059× | 560 ms / 1520 ms | **2.71×** | 639 ms / 1557 ms | **2.44×** | ✓ |
| MR/study_002 | 180×180×32 | 3.866:1 | 3.845:1 | 1.0053× | 84 ms / 204 ms | **2.43×** | 93 ms / 212 ms | **2.27×** | ✓ |
| MR/study_003 | 128×128×32 | 1.758:1 | 1.768:1 | 0.9945× | 68 ms / 150 ms | **2.19×** | 87 ms / 150 ms | **1.73×** | ✓ |
| MR/study_004 | 512×656×32 | 5.406:1 | 5.241:1 | 1.0315× | 628 ms / 1668 ms | **2.65×** | 726 ms / 1737 ms | **2.39×** | ✓ |
| MR/study_005 | 180×180×32 | 3.743:1 | 3.720:1 | 1.0062× | 84 ms / 204 ms | **2.44×** | 94 ms / 213 ms | **2.25×** | ✓ |

## Failures (if any)

_None — every study passed every gate._

## Methodology

Prep: each DICOM series is exported by [Scripts/prep_jp3d_volume.py](../Scripts/prep_jp3d_volume.py)
to a single raw little-endian uint16 `.bin` plus a matching `.img`
header. Both codecs read the same bytes — J2KSwift via `j2k encode3d`'s
raw-volume mode and OpenJPEG via `bintovolume` (which reads native LE
when its hard-coded `bigendian` flag is 0).

Encode: J2KSwift uses `--codec j2k-lossless`, which routes every Z-slice
through the same `J2KEncoder` EBCOT path that beats OpenJPEG 2D 1.4×–13.6×
in `BENCHMARK_COMPARISON.md`. OpenJPEG uses `-C 3EB -r 1` (3D-EBCOT,
the only OpenJPEG JP3D mode that is genuinely lossless on volumetric
input — `-C 2EB`, the default, silently drops precision).

Decode: J2KSwift via `j2k decode3d --output-format raw`; OpenJPEG via
`opj_jp3d_decompress`. Bit-exact verified against the original `.bin`
truncated to the source byte count (OpenJPEG sometimes pads trailing
samples to a byte alignment).

The J2KSwift M2 architecture (slice-stack codec — see
`docs/JP3D_BEAT_OPENJPEG_PLAN.md`) trades the ≤ 1 % inter-slice DWT
gain that OpenJPEG's `-C 3EB` exploits for a ≥ 2× speed gain on both
encode and decode plus random-access slice decode — operationally the
dominant property in clinical PACS workflows.
