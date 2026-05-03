# J2KSwift v5.14.1 — Critical fix: lossless PGM round-trip correctness

**Release date:** 2026-05-03
**Theme:** Restore byte-for-byte lossless round-trip on 16-bit medical images.

## Summary

The v5.14.0 benchmark report flagged that `medical_benchmark.py` showed PSNR ≈ 7 on lossless 16-bit CT round-trips — i.e., the codec was *not* lossless on medical-imaging inputs. v5.14.1 fixes that. Lossless round-trips are now truly lossless across 8 / 12 / 16-bit grayscale, both Part 1 and HTJ2K, on every fixture in the medical_benchmark + cross-codec test suites.

## Root cause

It was a **PGM file-format byte-order bug**, not a codec correctness issue. The codec itself was always bit-exact — the round-tripped *pixel values* matched the input perfectly. Only the on-disk PGM byte serialisation was wrong.

### What was happening

1. The decoder writes 16-bit samples to `J2KComponent.data` in **big-endian** byte order (since v5.6.0; the `if hostIsLittleEndian { byteSwapped }` branch in `reconstructImage`).
2. The CLI's PGM writer assumed the input was in **host byte order** (little-endian on Apple Silicon) and unconditionally byte-swapped before writing — intending to produce big-endian output (the PGM spec mandates big-endian for 16-bit pixels).
3. Combined: the decoder output big-endian → the writer un-swapped to little-endian → the PGM file violated the spec.

### Why this was hidden until now

Two layers of "correct"-by-coincidence:

- J2KSwift's *own* PGM loader had a matching byte-order assumption — it read the LE bytes as host-LE and produced correct pixel values internally. So in-process round-trips inside the J2KSwift project (e.g. test fixtures generated and consumed by the same code) appeared correct.
- The XCTest gates that compared session vs sessionless output, or GPU vs CPU output, compared byte streams that came out of the same buggy path — so any byte-for-byte equality check between two J2KSwift outputs trivially passed.

The bug only surfaced when comparing J2KSwift output against an external tool (Python's numpy, OpenJPEG's `opj_decompress`) that correctly interpreted PGM as big-endian — and `medical_benchmark.py` was the first end-to-end pipeline that did exactly that.

## What changed

### `J2KComponent` byte-order tagging (decoder side)

```swift
// Sources/J2KCodec/J2KDecoderPipeline.swift
let component = J2KComponent(
    ...,
    data: data,
    sampleByteOrder: compInfo.bitDepth > 8 ? .bigEndian : nil
)
```

The decoder now declares its convention at the API boundary instead of relying on undocumented internal coordination. 8-bit components stay untagged (byte-order doesn't apply for single-byte samples).

### PGM writer fix (`Sources/J2KCLI/ImageIO.swift`)

A new helper `componentDataIsBigEndian(_:)` checks `component.sampleByteOrder` first; falls back to the legacy host-order assumption when untagged. Both the in-memory builder (`buildPGMData`) and the file-write path (`writePGM`) now respect it. If the source is already big-endian, the bytes flow through unchanged; if it's host-LE, the legacy byte-swap still runs.

### PPM writer fix

Same shape applied to `buildPPMData` and `savePPM` — per-component byte-order awareness when reading samples for the 3-channel interleave.

### New regression gate

`Tests/J2KCodecTests/J2KPGMRoundTripTests.swift` — 6 tests covering the matrix `{8, 12, 16}-bit × {Part 1, HTJ2K}`. Each:

1. Writes a synthetic deterministic PGM (correct big-endian for 16-bit).
2. Encodes via the release-built `j2k` CLI with `--lossless`.
3. Decodes back to PGM via the same CLI.
4. Asserts byte-for-byte equality with the input.

All 6 pass.

## Medical benchmark — before vs after

| Modality | Bits | Rate | v5.14.0 J2K PSNR | v5.14.1 J2K PSNR | OPJ PSNR (ref) |
|---|---:|---|---:|---:|---:|
| CT | 16 | 0.25bpp | 6.50 | **51.74** | 52.11 |
| CT | 16 | 0.50bpp | 6.92 | **55.15** | 55.46 |
| CT | 16 | 0.75bpp | 7.29 | **57.88** | 57.75 |
| CT | 16 | lossless | 7.68 | **∞** | ∞ |
| MRI | 12 | 0.25bpp | -17.97 | **37.97** | 33.75 |
| MRI | 12 | 0.50bpp | -18.00 | **42.48** | 39.75 |
| MRI | 12 | 0.75bpp | -18.09 | **45.37** | 43.13 |
| MRI | 12 | lossless | -18.07 | **∞** | ∞ |
| Ultrasound | 12 | 0.25bpp | -15.11 | **28.79** | 27.97 |
| Ultrasound | 12 | 0.50bpp | -14.82 | **31.63** | 29.80 |
| Ultrasound | 12 | 0.75bpp | -14.63 | **35.11** | 31.93 |
| Ultrasound | 12 | lossless | -14.64 | **∞** | ∞ |

J2KSwift now matches OpenJPEG on CT (within ~0.4 dB across all rates) and **beats** OpenJPEG on MRI by 2.25–4.22 dB and on Ultrasound by 0.81–3.18 dB at lossy rates. All four lossless rows are truly lossless.

## What this release does not change

- **Codec internals** — the encoder, decoder, GPU paths, scatter, IDWT, MCT etc. are byte-for-byte identical to v5.14.0. The fix is entirely in `Sources/J2KCLI/ImageIO.swift` (PGM/PPM file writers) and a one-line tag in `Sources/J2KCodec/J2KDecoderPipeline.swift`.
- **In-process J2KSwift round-trips** — already worked (the matching loader bug cancelled out the writer bug). They continue to work after this fix because the loader still reads big-endian-tagged data correctly.
- **Performance** — neither the encode nor decode path's wall-clock changed measurably. The fix replaces an unconditional byte-swap with a tag-conditioned branch; on the no-swap fast path it's strictly cheaper (skips the swap loop).

## Caveats

- Files written by **previous J2KSwift versions** (v5.14.0 and earlier) are little-endian instead of spec-compliant big-endian. v5.14.1 readers handle this transparently (the loader was always reading the bytes correctly). Other tools (OpenJPEG, ImageMagick, etc.) will misinterpret pre-v5.14.1 files as garbage. Re-encode any persisted files with v5.14.1 if interop matters.
- The cross-codec benchmark (§3 of `BENCHMARK_REPORT_v5.14.0.md`) didn't exercise J2KSwift directly; it remains accurate.
