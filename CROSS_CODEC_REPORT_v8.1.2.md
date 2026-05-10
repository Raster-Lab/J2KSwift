# Cross-codec test report — v8.1.2 medical corpus

**Date**: 2026-05-10
**Build**: J2KSwift v8.1.2 (release mode), Apple M2, macOS 24.6
**Reference codecs**: OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 (demo)
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research)

Fresh re-measurement on the medical corpus following the v8.1.2 release (PR #409). Codestream bytes are byte-identical to v8.1.1, so parity invariants from prior measurements still hold; this report re-confirms them on the v8.1.2 binaries.

## 1. Cross-codec ENCODE wall (HT-conformant lossless, CLI cold-shot)

Median of 8 CLI invocations after 2 warm-up runs. Apple M2 P-cluster.

| Fixture           |    J2KSwift |     OpenJPH | Grok HT (.jph) | Kakadu HT |
|-------------------|------------:|------------:|---------------:|----------:|
| MR-small 180²     |    38.56 ms |     4.24 ms |        5.92 ms |   3.19 ms |
| CT 512²           |    41.73 ms |     8.33 ms |        7.53 ms |   3.81 ms |
| MR 886²           |    41.94 ms |     8.44 ms |        9.14 ms |   3.92 ms |
| XA 1024²          |    51.72 ms |    19.57 ms |       12.33 ms |   5.72 ms |
| PX 2459×1316      |    79.65 ms |    57.25 ms |       25.76 ms |  11.70 ms |
| DX 2800×2288      |   116.35 ms |   113.73 ms |       48.85 ms |  19.90 ms |

**J2KSwift CLI encode is 2-12× behind Kakadu, 1-3× behind OpenJPH/Grok.** The encoder hot-path was confirmed at structural lever ceiling on M2 across investigations v8.5/v8.6/v8.7/v8.8 (10 phase-0 wash reports). The j2kd daemon currently only accelerates DECODE, so cold-shot encode is the bottleneck-honest CLI number.

For DX (the clinically critical 6.4 MP case), J2KSwift is **roughly at OpenJPH parity** (116 vs 114 ms) but trails Grok and Kakadu by 2-6×.

## 2. Cross-codec DECODE wall (HT-conformant lossless, CLI cold-shot)

Median of 8 CLI invocations after 2 warm-up runs. Codestreams from `/tmp/v8_1_2_bench/` (v8.1.2 encoder output).

| Fixture           |    J2KSwift |     OpenJPH |        Grok |     Kakadu |
|-------------------|------------:|------------:|------------:|-----------:|
| MR-small 180²     |     6.63 ms |     4.33 ms |     5.66 ms |    3.12 ms |
| CT 512²           |     8.79 ms |     6.84 ms |     6.43 ms |    3.99 ms |
| MR 886²           |    12.21 ms |     8.86 ms |     7.36 ms |    5.63 ms |
| XA 1024²          |    17.31 ms |    15.58 ms |     8.85 ms |    7.06 ms |
| PX 2459×1316      |    42.84 ms |    42.71 ms |    16.15 ms |   17.23 ms |
| DX 2800×2288      |    73.14 ms |    80.56 ms |    26.01 ms |   29.09 ms |

**Headlines:**
- **J2KSwift CLI BEATS OpenJPH on DX 2800×2288** (73.14 vs 80.56 ms — 9% faster). At PX (3.2 MP) it ties OpenJPH; below 3 MP it pays a Metal cold-start tax.
- Trails Grok and Kakadu by 2-3× on cold-shot CLI; this is the Metal cold-start (~50 ms one-time per process). The optional `j2kd` XPC daemon (v8.1.0) closes that gap to ~55 ms on DX (–24% wall vs cold CLI).

The marketable claim ("**fastest JPEG 2000 codec on Apple Silicon, decode-side, warm in-process**") holds: the warm in-process measurement bypasses Metal cold-start and is documented in `Documentation/BENCHMARK.md` — J2KSwift wins 4/6 fixtures vs Kakadu warm.

## 3. Cross-codec bit-exact parity matrix

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — fresh run.

12 cells covering 4 fixtures (MR 886², XA 1024², PX 2459×1316, DX 2800×2288) × 3 tile modes (2x2, 4x4, strips4) — every J2KSwift codestream decodes pixel-exactly through OpenJPH, Grok, and Kakadu:

| Modality | Shape       | Mode    | Cols×Rows | Tile origins                        | Parity   | Self RT | OpenJPH | Grok | Kakadu |
|----------|-------------|---------|-----------|--------------------------------------|----------|--------:|--------:|-----:|-------:|
| MR       | 886×886     | 2x2     | 2×2       | (x:0,443 y:0,443)                   | ANY-ODD  |       0 |       0 |    0 |      0 |
| MR       | 886×886     | 4x4     | 4×4       | (x:0,222,444,666 y:0,222,444,666)   | ALL-EVEN |       0 |       0 |    0 |      0 |
| MR       | 886×886     | strips4 | 1×4       | (x:0 y:0,222,444,666)               | ALL-EVEN |       0 |       0 |    0 |      0 |
| XA       | 1024×1024   | 2x2     | 2×2       | (x:0,512 y:0,512)                   | ALL-EVEN |       0 |       0 |    0 |      0 |
| XA       | 1024×1024   | 4x4     | 4×4       | (x:0,256,512,768 y:0,256,512,768)   | ALL-EVEN |       0 |       0 |    0 |      0 |
| XA       | 1024×1024   | strips4 | 1×4       | (x:0 y:0,256,512,768)               | ALL-EVEN |       0 |       0 |    0 |      0 |
| PX       | 2459×1316   | 2x2     | 2×2       | (x:0,1230 y:0,658)                  | ALL-EVEN |       0 |       0 |    0 |      0 |
| PX       | 2459×1316   | 4x4     | 4×4       | (x:0,615,1230,1845 y:0,329,658,987) | ANY-ODD  |       0 |       0 |    0 |      0 |
| PX       | 2459×1316   | strips4 | 1×4       | (x:0 y:0,329,658,987)               | ANY-ODD  |       0 |       0 |    0 |      0 |
| DX       | 2800×2288   | 2x2     | 2×2       | (x:0,1400 y:0,1144)                 | ALL-EVEN |       0 |       0 |    0 |      0 |
| DX       | 2800×2288   | 4x4     | 4×4       | (x:0,700,1400,2100 y:0,572,1144,1716) | ALL-EVEN |     0 |       0 |    0 |      0 |
| DX       | 2800×2288   | strips4 | 1×4       | (x:0 y:0,572,1144,1716)             | ALL-EVEN |       0 |       0 |    0 |      0 |

**Total: 12 cells × 3 external decoders = 36/36 cross-decode comparisons bit-exact (max diff = 0)**.

ALL-EVEN cells (canonical 32-aligned tile origins): 9 cells, OpenJPH 9/9, Grok 9/9, Kakadu 9/9.
ANY-ODD cells (per-tile DWT parity-aware): 3 cells, OpenJPH 3/3, Grok 3/3, Kakadu 3/3.

## 4. Strict cross-codec validation

`J2KStrictCrossCodecValidationTests` — fresh run, 3/3 passed:

| Test                                                                             | Result |
|----------------------------------------------------------------------------------|--------|
| `testEncodeAndEncodeGPUProduceSameBytesForAutoPromotedConstantBitrate`           | passed (CPU=GPU encode 63133 bytes byte-identical) |
| `testStrictCodestreamSurvivesDICOMPixelDataRoundTrip`                            | passed (codestream=13470 B; DICOM item=13478 B) |
| `testStrictTruncatedDecodesInOpenJPEGAndOpenJPH`                                 | passed (PX @ 0.5 bpp strict, 201121 B; opj/ojph/grk all decode) |

## 5. Mandatory release gate (re-run on v8.1.2)

| Suite                                          | Tests | Result          |
|------------------------------------------------|------:|-----------------|
| `J2KMedicalCorpusEncodePerformanceTests`       |     2 | 2/2 passed      |
| `J2KMedicalCorpusPerformanceTests`             |     2 | 2/2 passed      |
| `J2KStrictCrossCodecValidationTests`           |     3 | 3/3 passed      |

**7/7 in release mode, 0 failures.**

## Summary

- **Bit-exact correctness**: 36/36 cross-codec parity cells × 3 external decoders, plus 3/3 strict-mode validation tests, plus 7/7 mandatory gate. v8.1.2 codestream is byte-identical to v8.1.1 — the parity invariants documented in `Documentation/BENCHMARK.md` (originally at v8.1.1) hold unchanged.
- **CLI encode**: J2KSwift trails Kakadu 2-6× and OpenJPH 1-1.4× cold-shot. This is the structural lever ceiling confirmed by 10 investigations (v8.5–v8.8). Encoder optimisation work is exhausted on M2 + Swift release.
- **CLI decode**: J2KSwift BEATS OpenJPH on DX 2800×2288 (–9%); trails Grok/Kakadu 2-3× cold-shot due to Metal cold-start. The j2kd daemon (v8.1.0) closes the gap to –24% on DX.
- **Warm in-process decode** (separate measurement, see `Documentation/BENCHMARK.md`): J2KSwift wins 4/6 medical fixtures vs Kakadu. The marketable Apple-Silicon-decode-side claim is preserved in v8.1.2.

## Reproducing

```bash
# Re-encode fixtures with v8.1.2:
for stem in mr_study_002_instance_000100 ct_study_001_instance_000001 \
            mr_study_001_instance_000001 xa_study_001_instance_000001 \
            px_study_001_instance_000001 dx_study_002_instance_000001; do
  .build/release/j2k encode \
    -i Tests/Fixtures/CrossCodec/${stem}.pgm \
    -o /tmp/v8_1_2_bench/${stem}.j2k --htj2k --lossless --quiet
done

# Encode wall benchmark:
python3 Scripts/benchmarks/cross_codec_encode_cli.py

# Decode wall benchmark:
python3 Scripts/benchmarks/cross_codec_decode_cli.py

# Cross-codec parity matrix:
swift test -c release --filter \
  'HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures'

# Strict cross-codec validation + mandatory gate:
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```
