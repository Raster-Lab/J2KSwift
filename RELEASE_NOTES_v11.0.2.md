# J2KSwift v11.0.2

Decoder-only correctness and performance patch for the v11.0.x line.

## Summary

v11.0.2 fixes unnecessary work in the EBCOT bit-plane decoder exposed by
lossless digital breast tomosynthesis (DBT) images. A truncated quality-layer
prefix now stops at the exact coding-pass boundary instead of continuing
through every lower bit-plane, and reusable decoder scratch clears only the
logical code-block region rather than its retained worker capacity.

EBCOT diagnostic tracing is now removed by conditional compilation unless
`EBCOT_DEBUG_TRACE` is explicitly enabled. Public API and codestream structure
are unchanged.

## What's New — production-default

- Stop bit-plane decoding as soon as the requested pass contribution is
  consumed.
- Limit `codedThisPass` clearing to the active coefficient count.
- Compile disabled EBCOT tracing out of encoder, decoder, context-model, and MQ
  coder hot paths.
- Add focused pass-boundary and runtime regressions.
- Add a bounded DBT verifier with process-group watchdogs and byte-exact PGM
  comparison.

## What's New — opt-in

None.

## Backward compatibility

- Public API is unchanged.
- Encoder behaviour and codestream format are unchanged.
- Verified DBT outputs are byte-identical to their reference PGM images.

## Cross-codec parity matrix

Fresh Apple M5 release-mode validation is bit-exact in every measured cell:

| Scope | OpenJPH 0.30.1 | Grok 20.3.5 | Kakadu 8.4.1 demo |
|---|---:|---:|---:|
| GPU forward 5/3, 7 medical fixtures | 7/7 | 7/7 | 7/7 |
| Multi-tile geometry matrix, 12 configurations | 12/12 | 12/12 | 12/12 |
| **Total** | **19/19** | **19/19** | **19/19** |

All **57/57 external-decode cells** reconstructed with maximum absolute pixel
difference zero.

## Medical-corpus benchmarks

Apple M5, release mode, warm in-process median of five. This table is a fresh
release gate, not a claim of a version-to-version broad-corpus speedup; the
v11.0.2 change targets truncated DBT quality-layer prefixes.

| Fixture | CPU encode ms | GPU encode ms | CPU decode ms | GPU decode ms | GPU-HT decode ms |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 0.4 | 0.4 | 1.6 | 1.5 | 3.0 |
| CT 512² | 1.6 | 1.6 | 11.3 | 3.9 | 5.2 |
| MR 886² | 6.4 | 2.3 | 37.1 | 8.7 | 11.3 |
| XA 1024² | 5.1 | 5.7 | 41.1 | 6.7 | 9.3 |
| PX 2459×1316 | 22.7 | 23.9 | 154.3 | 19.6 | 17.6 |
| DX 2800×2288 | 54.1 | 65.4 | 45.9 | 41.5 | 37.5 |

CPU encode stage means for the same six fixtures:

| Fixture | Preprocess | DWT | Entropy | Codestream |
|---|---:|---:|---:|---:|
| MR-small 180² | 0.0 | 0.1 | 0.2 | 0.1 |
| CT 512² | 0.0 | 0.4 | 1.0 | 0.1 |
| MR 886² | 0.3 | 2.0 | 2.0 | 0.4 |
| XA 1024² | 0.2 | 1.6 | 3.8 | 0.5 |
| PX 2459×1316 | 1.1 | 6.1 | 15.4 | 1.9 |
| DX 2800×2288 | 2.2 | 12.2 | 34.3 | 5.1 |

The canonical warm sustained CLI benchmark used seven timed runs after two
warmups. The six real-fixture subset is shown below; the archived JSON contains
all 38 PGM and 13 DICOM fixtures.

| Fixture | Direction | J2KSwift+daemon | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|
| MR-small 180² | Encode | 10.17 | 10.14 | 9.74 | 4.71 |
| MR-small 180² | Decode | 20.56 | 10.51 | 10.33 | 4.94 |
| CT 512² | Encode | 19.85 | 9.77 | 9.62 | 4.56 |
| CT 512² | Decode | 20.12 | 9.86 | 9.84 | 4.71 |
| MR 886² | Encode | 19.60 | 9.61 | 9.69 | 4.59 |
| MR 886² | Decode | 40.40 | 10.05 | 10.11 | 9.97 |
| XA 1024² | Encode | 19.97 | 19.71 | 9.78 | 9.74 |
| XA 1024² | Decode | 19.98 | 19.77 | 9.77 | 9.83 |
| PX 2459×1316 | Encode | 40.86 | 76.22 | 39.83 | 20.17 |
| PX 2459×1316 | Decode | 40.13 | 39.98 | 19.98 | 20.17 |
| DX 2800×2288 | Encode | 79.31 | 132.64 | 40.31 | 21.83 |
| DX 2800×2288 | Decode | 79.44 | 127.82 | 41.18 | 40.37 |

## Test Suite Results

- Focused `J2KBitPlaneDecoderFixTests`: 36/36 passing in release mode.
- Bounded DBT verification: 4/4 available frames bit-exact; every frame below
  the 5,000 ms per-frame bound and 10-second hard timeout.
- Mandatory release gate: 7/7 passing.
- Fresh cross-codec and tile parity filters: 2/2 passing; 57/57 external cells
  bit-exact.
- Lossless encode stage-profile filter: 1/1 passing.
- Release `j2k` and `j2kd` products built successfully; canonical warm
  benchmark completed with all configured external codecs available.

## API surface

No additions, removals, signature changes, or default-policy changes.

## Known limitations

- The local bounded DBT fixture set contains four frames. The prior v11.0.1
  release validation covered the complete 100-frame TCIA DBT corpus.

## Reproducing

```sh
swift test -c release --filter J2KBitPlaneDecoderFixTests
Scripts/verify-dbt-decoder.sh --input-dir /tmp
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
swift test -c release --filter 'HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures|HTGPUForward53CrossCodecTests'
swift test -c release --filter EncodeStageProfileLosslessCorpusTests
python3 Scripts/benchmarks/cross_codec_warm_bench.py \
  --output Documentation/Benchmarks/data/benchmark-results-arm64-v11.0.2-20260711.json
```

## Companion documents

- `Documentation/Benchmarks/data/benchmark-results-arm64-v11.0.2-20260711.json`
