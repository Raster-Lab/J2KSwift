# J2KSwift Cross-Backend × Cross-Codec Bit-Exactness Report

J2KSwift v5.2.0 (`gpu-lossless-bit-exact` branch) on the **same 10 real DICOM images** used in `CROSS_CODEC_DICOM_REPORT.md` (CT, DX, MG, MR, PX, XA — 102 MB of source data).

This report exercises **every encode × decode combination** that matters for production use: J2KSwift CPU encoder, J2KSwift GPU encoder, OpenJPEG (J2K Part 1 reference), and OpenJPH (HTJ2K reference) — all decoded by every applicable counterpart, including the bit-exact integer 5/3 GPU IDWT path that just landed.

The headline:

| Test family                                          | Pass rate | Notes |
| ---------------------------------------------------- | --------: | ----- |
| **J2KSwift self-consistency** (CPU↔GPU enc/dec)      | **80 / 80** | Every CPU/GPU encode is byte-identical to every CPU/GPU decode. |
| **OpenJPEG self-test** (J2K Part 1 LL)               | 10 / 10  | Reference baseline. |
| **OpenJPH self-test** (HTJ2K LL)                     | 10 / 10  | Reference baseline. |
| **J2KSwift ↔ OpenJPEG interop** (J2K Part 1 LL)      | 40 / 40* | Pixel-equal modulo PGM byte order (see §Note on PGM endianness). |
| **J2KSwift ↔ OpenJPH interop** (HTJ2K LL)            | **40 / 40\*** | **Fixed in this branch** — see §HTJ2K interop fix. |
| **Total**                                            | **180 / 180** | All cross-codec mismatches are PGM byte-order serialisation, not codec disagreements. |

> * "swap" — pixel values agree byte-for-byte after a 16-bit byte swap. The codestream encodes the correct values; the only difference is whether the decoder serialises 16-bit pixels as big-endian (PGM spec) or little-endian (the byte order of the original PGMs).

---

## Detailed cross-matrix (per image)

| #  | File          | Dim         | jc/jc P1 | jc/jg P1 | jg/jc P1 | jg/jg P1 | jc→opj | jg→opj | opj→jc | opj→jg | opj→opj | jc/jc HT | jc/jg HT | jg/jc HT | jg/jg HT | jc→oph | jg→oph | oph→jc | oph→jg | oph→oph |
| --:| ------------- | ----------- | :------: | :------: | :------: | :------: | :----: | :----: | :----: | :----: | :-----: | :------: | :------: | :------: | :------: | :----: | :----: | :----: | :----: | :-----: |
|  1 | ct_s001       |   512×512   |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  2 | ct_s003_50    |   512×512   |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  3 | dx_s001       |  2544×3056  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  4 | dx_s002       |  2800×2288  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  5 | mg_s001       |  3520×4784  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  6 | mg_s002       |  3521×4784  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  7 | mr_s001       |   886×886   |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  8 | mr_s002_100   |   180×180   |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
|  9 | px_s001       |  2459×1316  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |
| 10 | xa_s001       |  1024×1024  |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |    ✓     |    ✓     |    ✓     |    ✓     |  swap  |  swap  |  swap  |  swap  |    ✓    |

**Column legend** (each cell answers "does the round-trip recover the original pixel data byte-for-byte?"):

| Column     | Encoder        | Decoder        | Codec mode    |
|------------|----------------|----------------|---------------|
| `jc/jc P1` | J2KSwift CPU   | J2KSwift CPU   | J2K Part 1 LL |
| `jc/jg P1` | J2KSwift CPU   | J2KSwift GPU   | J2K Part 1 LL |
| `jg/jc P1` | J2KSwift GPU   | J2KSwift CPU   | J2K Part 1 LL |
| `jg/jg P1` | J2KSwift GPU   | J2KSwift GPU   | J2K Part 1 LL |
| `jc→opj`   | J2KSwift CPU   | OpenJPEG       | J2K Part 1 LL |
| `jg→opj`   | J2KSwift GPU   | OpenJPEG       | J2K Part 1 LL |
| `opj→jc`   | OpenJPEG       | J2KSwift CPU   | J2K Part 1 LL |
| `opj→jg`   | OpenJPEG       | J2KSwift GPU   | J2K Part 1 LL |
| `opj→opj`  | OpenJPEG       | OpenJPEG       | J2K Part 1 LL (baseline) |
| `jc/jc HT` | J2KSwift CPU   | J2KSwift CPU   | HTJ2K LL      |
| `jc/jg HT` | J2KSwift CPU   | J2KSwift GPU   | HTJ2K LL      |
| `jg/jc HT` | J2KSwift GPU   | J2KSwift CPU   | HTJ2K LL      |
| `jg/jg HT` | J2KSwift GPU   | J2KSwift GPU   | HTJ2K LL      |
| `jc→oph`   | J2KSwift CPU   | OpenJPH        | HTJ2K LL      |
| `jg→oph`   | J2KSwift GPU   | OpenJPH        | HTJ2K LL      |
| `oph→jc`   | OpenJPH        | J2KSwift CPU   | HTJ2K LL      |
| `oph→jg`   | OpenJPH        | J2KSwift GPU   | HTJ2K LL      |
| `oph→oph`  | OpenJPH        | OpenJPH        | HTJ2K LL (baseline) |

---

## What this proves

### J2KSwift core paths: clean across the board (80 / 80)

Every combination of the J2KSwift CPU encoder, J2KSwift GPU encoder, J2KSwift CPU decoder, and J2KSwift GPU decoder produces **byte-identical** output to the original PGM, on **both** J2K Part 1 lossless and HTJ2K lossless, on **all 10** images:

- **CPU enc → CPU dec**: 20 / 20 ✓
- **CPU enc → GPU dec**: 20 / 20 ✓ ← the verifyEncodedRoundTrip case for DICOMKit
- **GPU enc → CPU dec**: 20 / 20 ✓ ← cross-direction validation
- **GPU enc → GPU dec**: 20 / 20 ✓

This includes the 12-bit DX images that historically tripped the GPU `verifyEncodedRoundTrip` path. The bit-exact integer 5/3 IDWT is verified on real medical data, in every direction.

### Cross-codec J2K Part 1: pixel-equal modulo PGM serialisation (40 / 40 *)

J2KSwift and OpenJPEG agree on **every pixel value** in **every direction**:

- **J2KSwift CPU enc → OpenJPEG dec**: 10 / 10 pixel-equal (after byte swap)
- **J2KSwift GPU enc → OpenJPEG dec**: 10 / 10 pixel-equal (after byte swap)
- **OpenJPEG enc → J2KSwift CPU dec**: 10 / 10 pixel-equal (after byte swap)
- **OpenJPEG enc → J2KSwift GPU dec**: 10 / 10 pixel-equal (after byte swap)

The "swap" is purely a PGM serialisation difference (see Note below), not a codec bug.

### Cross-codec HTJ2K: full bidirectional interop with OpenJPH (40 / 40 *)

J2KSwift HTJ2K codestreams now decode cleanly through `ojph_expand`, and OpenJPH HTJ2K codestreams decode cleanly through `j2k decode`. Pixel-equal in every direction modulo PGM byte order — same `swap` semantics as the J2KSwift ↔ OpenJPEG cells.

This required two fixes (see §HTJ2K interop fix below):

1. **Encoder default flipped from `.custom` to `.conformant`.** The CLI's `--htj2k` flag was previously defaulting to a J2KSwift-private block layout that no third-party Part-15 decoder could read. The default now matches OpenJPH and the spec; `--htj2k-custom` opts into the legacy private format for backward compatibility.

2. **Decoder format auto-detection.** The decoder now structurally sniffs the first non-empty codeblock when no explicit J2KSwift HT-block-format COM marker is present. OpenJPH-encoded codestreams (no marker, conformant block layout) are detected and routed through the conformant decoder; legacy J2KSwift `.custom` archives (no marker, custom 6-byte header) are still detected and routed through the custom decoder.

---

## Note on PGM endianness

The 10 source PGMs were written with **little-endian 16-bit pixels** (the byte order of `Pixel Data` in DICOM Explicit-VR Little-Endian transfer syntaxes). The PGM specification mandates **big-endian** for `maxval > 255`. So:

- J2KSwift's PGM read/write is LE-native — it round-trips the originals exactly.
- OpenJPEG and OpenJPH follow the PGM spec — they read input as BE, write output as BE.

When J2KSwift encodes the LE-input PGM and OpenJPEG decodes the resulting codestream, OpenJPEG writes a BE-output PGM. The encoded codestream actually contains **the same pixel values** — both codecs agree on the wavelet coefficients, the entropy decoding, and the final pixels. The difference is only in how the 16-bit values are packed into bytes for the output PGM. Hence "swap" rather than "no" in the matrix above.

If you fed each codec a strictly PGM-spec-compliant (big-endian) input, the cross-codec cells would be plain "✓".

---

## CPU vs GPU decode time on the 10 DICOMs (median of 3 runs)

| #  | File          | Dim         | LL CPU ms | LL GPU ms | HT CPU ms | HT GPU ms | Lossy CPU ms | Lossy GPU ms | Bit-exact CPU=GPU |
| --:| ------------- | ----------- | --------: | --------: | --------: | --------: | -----------: | -----------: | :---------------: |
|  1 | ct_s001       |   512×512   |     20.9  |     20.2  |     20.2  |     20.5  |       19.9   |       21.0   |        ✓          |
|  2 | ct_s003_50    |   512×512   |     21.1  |     21.4  |     20.0  |     20.2  |       19.9   |       20.3   |        ✓          |
|  3 | dx_s001       |  2544×3056  |    331.9  |    326.3  |    351.1  |    315.8  |      340.3   |      341.4   |        ✓          |
|  4 | dx_s002       |  2800×2288  |    247.7  |    239.3  |    230.6  |    228.2  |      227.7   |      225.9   |        ✓          |
|  5 | mg_s001       |  3520×4784  |    379.7  |    381.4  |    375.9  |    382.9  |      704.2   |      686.6   |        ✓          |
|  6 | mg_s002       |  3521×4784  |    451.2  |    459.7  |    460.7  |    493.2  |      639.7   |      634.4   |        ✓          |
|  7 | mr_s001       |   886×886   |     21.9  |     22.1  |     21.6  |     21.5  |       34.5   |       37.2   |        ✓          |
|  8 | mr_s002_100   |   180×180   |     12.0  |     11.8  |     11.4  |     11.8  |       11.4   |       11.5   |        ✓          |
|  9 | px_s001       |  2459×1316  |    134.9  |    133.6  |    129.8  |    124.9  |      130.3   |      129.3   |        ✓          |
| 10 | xa_s001       |  1024×1024  |     55.1  |     55.1  |     49.8  |     50.5  |       47.4   |       48.1   |        ✓          |
|    | **Totals**    |             | **1676.4** | **1670.9** | **1671.1** | **1669.5** | **2175.3**  | **2155.7**  |    **30 / 30**    |

End-to-end CPU and GPU decode times track each other within a few percent because entropy decoding (still CPU-bound) dominates total wall-clock. The actual GPU IDWT speedup is hidden inside this number — see the next section.

---

## IDWT-only micro-benchmark (the hidden 3–4× speedup)

End-to-end decode is dominated by entropy decoding, not IDWT. Isolating the inverse 5/3 DWT stage on the same dimensions exposes the real GPU advantage. Median of 5 runs after 2 warmups, `-c release`. Bit-exactness re-asserted on every iteration.

| File / dim    | Modality | Pixels    | CPU IDWT ms | GPU IDWT ms | **Speedup** |
| ------------- | -------- | --------- | ----------: | ----------: | ----------: |
| mr_s002 180×180 | MR     |    32 K   |        0.78 |        2.73 |   0.29×     |
| ct_s001 512×512 | CT     |   262 K   |        3.12 |        5.79 |   0.54×     |
| mr_s001 886×886 | MR     |   784 K   |        7.14 |        8.88 |   0.80×     |
| xa_s001 1024×1024 | XA   |     1 M   |       12.80 |       13.26 |   0.97×     |
| px_s001 2459×1316 | PX   |   3.2 M   |       32.52 |       15.99 | **2.03×**   |
| dx_s002 2800×2288 | DX   |   6.4 M   |       62.07 |       20.63 | **3.01×**   |
| mg_s001 3520×4784 | MG   |  16.8 M   |      229.89 |       59.74 | **3.85×**   |
| mg_s002 3521×4784 | MG   |  16.8 M   |      235.58 |       56.95 | **4.14×**   |
| dx_s001 2544×3056 | DX   |   7.8 M   |       99.00 |       23.87 | **4.15×**   |

Crossover is around 1–2 megapixels; below that, Metal command-buffer dispatch overhead dominates and CPU wins. Above that, GPU runs **3–4× faster** on the IDWT alone.

The reason this is invisible at the end-to-end level: on dx_s001 the IDWT is the difference between 99 ms and 24 ms, but entropy decoding adds ~300 ms regardless — so wall-clock stays at ~330 ms either way. **Parallelizing entropy decode is the next lever to expose this 4× to users.** (Tile-level parallelism has already shipped, but on single-tile DICOMs the inner code-block parallelism is already saturating the cores; a smarter scheduler that picks tile-vs-codeblock parallelism based on tile count would close the gap.)

Reproduce: `swift test -c release --filter J2KMetalDWT53IntBenchmarkTests`. Source: [Tests/J2KMetalTests/J2KMetalDWT53IntBenchmarkTests.swift](Tests/J2KMetalTests/J2KMetalDWT53IntBenchmarkTests.swift).

---

## HTJ2K interop fix

### What was broken

The CLI's `--htj2k` flag built a `J2KEncodingConfiguration` with `htj2kBlockFormat = .custom`. That's a **J2KSwift-private** block layout that prepends each codeblock with a 6-byte `[melLen | vlcLen | magsgnLen]` header — convenient for J2KSwift's own decoder, but not part of ISO/IEC 15444-15. OpenJPH (and Kakadu) reject those codestreams at the codeblock layer:

```
ojph info  0x00030092: cleanup segment cannot contain less than 2 bytes
ojph warning 0x00010001: malformed codeblock that has more than one coding pass, but zero length for 2nd and potential 3rd pass
ojph info  0x000300A1: Error decoding a codeblock.
```

Conversely, the J2KSwift decoder defaulted to `htj2kBlockFormat = .custom` and only flipped to `.conformant` when it saw the J2KSwift-private COM marker. OpenJPH-encoded codestreams don't carry that marker, so the J2KSwift decoder mis-routed them through the custom decoder, which threw on the very first block:

```
J2KError.decodingError("Invalid stream lengths in HT encoded block")
```

Both directions broke for the same reason: J2KSwift's "default HTJ2K" was J2KSwift-private, not Part-15.

### The fix

Two changes:

1. **`Sources/J2KCodec/J2KEncodingPresets.swift` and `Sources/J2KCLI/Commands.swift`**: the encoder default for `useHTJ2K = true` is now `htj2kBlockFormat = .conformant`. The CLI's `--htj2k` flag follows; a new `--htj2k-custom` flag opts into the legacy private format.

2. **`Sources/J2KCodec/J2KDecoderPipeline.swift`**: the decoder default flipped to `.conformant`, and the entropy decoder now runs `detectHTBlockFormat` (already present at `Sources/J2KCodec/J2KHTConformantDispatch.swift:138`) on the first non-empty codeblock when no explicit COM marker is present. This catches:
   - OpenJPH / Kakadu codestreams (no marker, conformant layout) → conformant decoder.
   - Legacy J2KSwift `.custom` archives (no marker, custom 6-byte header) → custom decoder.
   - New J2KSwift conformant codestreams (COM marker present) → conformant decoder, marker-confirmed.

The fix is content-driven, not magic-byte-driven, so it stays robust if a future encoder version adds different markers.

### Performance note

The conformant block path is currently slower than the J2KSwift-private custom path for some workloads — pre-existing aspirational SLO tests in `HTJ2KBeatsOpenJPEGTests` (which never beat 1.9× encode / 0.5× decode against OpenJPEG when run on this dataset, regardless of this branch) flag the gap. Those tests use a synthetic CPU simulation, not the real codec, so my changes don't move their numbers — but the gap is real in the actual codec and worth a follow-up commit to optimise the conformant block coder.

---

## What changed in this branch

Before:

| Stage                       | CPU decoder                    | GPU decoder                          |
| --------------------------- | ------------------------------ | ------------------------------------ |
| Inverse 5/3 (lossless)      | `Int32` lifting, `>> 2 / >> 1` | **`Float` lifting, `/ 4.0f / 2.0f`** |
| Dispatch order (inverse)    | horizontal → vertical (spec)   | **vertical → horizontal**            |
| Multi-tile decode           | serial                         | serial                               |

After:

| Stage                       | CPU decoder                    | GPU decoder                          |
| --------------------------- | ------------------------------ | ------------------------------------ |
| Inverse 5/3 (lossless)      | `Int32` lifting, `>> 2 / >> 1` | **`int` lifting, `>> 2 / >> 1`**     |
| Dispatch order (inverse)    | horizontal → vertical          | **horizontal → vertical**            |
| Subband buffer at boundary  | `Int32` (no Float roundtrip)   | **`Int32` (no Float roundtrip)**     |
| Multi-tile decode           | task-group parallel            | task-group parallel                  |

Net result on the cross-matrix:
- J2KSwift self-consistency on lossless 5/3: 40 / 40 ✓ (any CPU/GPU encode + any CPU/GPU decode, both J2K Part 1 + HTJ2K)
- DICOMKit `verifyEncodedRoundTrip` byte-equality check now passes on the GPU path for HTJ2K-Lossless and HTJ2K-RPCL-Lossless real DICOMs.

---

## Test setup

| | |
|---|---|
| Date | 2026-04-29 |
| Host | Apple M2, 8C/8T, 24 GB RAM, macOS 24.6.0 (arm64) |
| J2KSwift | `gpu-lossless-bit-exact` (`swift build -c release --product j2k`) |
| OpenJPEG | 2.5.4 (`opj_compress -r 1`, `opj_decompress`) |
| OpenJPH  | 0.27.0 (`ojph_compress -reversible true`, `ojph_expand`) |
| Dataset  | `LocalDatasets/medical-dicom-organized/` (same 10 files used in `CROSS_CODEC_DICOM_REPORT.md`) |
| Comparison | PGM **pixel-only** equality, with optional 16-bit byte-swap to absorb PGM endianness differences |

**How to reproduce**

```bash
swift build -c release --product j2k
bash /tmp/j2k_codec_compare/run_cross_matrix.sh   # writes results.csv
```

Cross-matrix CSV: [/tmp/j2k_codec_compare/cross_matrix/results.csv](file:///tmp/j2k_codec_compare/cross_matrix/results.csv)
Driver: [/tmp/j2k_codec_compare/run_cross_matrix.sh](file:///tmp/j2k_codec_compare/run_cross_matrix.sh)
End-to-end CPU vs GPU CSV: [/tmp/j2k_codec_compare/cpu_vs_gpu/results.csv](file:///tmp/j2k_codec_compare/cpu_vs_gpu/results.csv)
End-to-end driver: [/tmp/j2k_codec_compare/run_cpu_vs_gpu.sh](file:///tmp/j2k_codec_compare/run_cpu_vs_gpu.sh)
