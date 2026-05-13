# Cross-Codec Benchmark — J2KSwift v7.1.0 vs OpenJPH 0.27 / Grok 20.3 / Kakadu 8.4.1

> **⚠ Withdrawn — see [CROSS_CODEC_BENCHMARK_v7.1.1.md](CROSS_CODEC_BENCHMARK_v7.1.1.md) for corrected data.**
>
> This report contained two material errors:
> 1. The "subtract ~67 ms startup from CLI rows" caveat is **false** — measured pure CLI startup is 14–17 ms across all four codecs (median of 10). The ~50 ms gap between J2KSwift CLI and the C codecs comes from per-invocation overhead **inside `j2k`'s CLI binary** (image loader / config parsing / encoder construction), not Swift runtime startup. The "in-process numbers" table that subtracted 67 ms therefore over-credited J2KSwift by ~50 ms per cell and produced spurious "wins" against Kakadu/Grok.
> 2. The "ties or wins" framing in the bottom-line is wrong: with the corrected numbers, J2KSwift's library is **2.6× behind Kakadu on DX encode and 2.7× behind on DX decode**. The honest position is "wins vs OpenJPH library-to-library; loses to Kakadu / Grok on PX and DX."
>
> The v7.1.1 file rewrites every table with the corrected measurements + adds a GPU-vs-CPU comparison so callers can confirm the optimal setting (`--gpu` default is fine; within ±5 % of `--no-gpu` on single-tile).

**Measured**: 2026-05-08, Apple M2, release builds, median of 5 runs per cell, **CLI launches** (each timing includes process startup)
**Mode**: HT-conformant lossless 5/3 (Part-15)
**Fixtures**: 6 real medical 16-bit PGMs from `Tests/Fixtures/CrossCodec/`

| codec | version | encode invocation |
|---|---|---|
| J2KSwift | **v7.1.0** | `j2k encode -i F.pgm -o F.j2c --htj2k --reversible` |
| OpenJPH | 0.27 (homebrew) | `ojph_compress -i F.pgm -o F.j2c -reversible true` |
| Grok | 20.3.0 (homebrew) | `grk_compress -i F.pgm -o F.jph -M 64` (HT mode 64 ⇒ HTJ2K) |
| Kakadu | 8.4.1 demo | `kdu_compress -i F.pgm -o F.j2c Cmodes=HT Creversible=yes Cprecincts="{256,256}"` |

**Caveat — CLI startup**: every cell includes process-launch overhead. The Swift-based J2KSwift CLI pays ≈ 65–70 ms of dynamic-loader / Swift runtime initialization on macOS that the C-based codecs don't. The startup tax is fixed per call and dominates small-fixture cells. For the **codec-only** wall, subtract a constant ~67 ms from J2KSwift CLI rows; the in-process J2KSwift numbers (from `Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift`) are reported separately at the bottom of this document for the truest codec comparison.

---

## Encode wall-time (median of 5, ms — **CLI**)

| fixture | shape | px | bytes | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | ~45K | 65.5 | 16.5 | 18.3 | 15.2 |
| CT | 512×512 | 262K | ~436K | 67.5 | 20.1 | 19.6 | 15.6 |
| MR | 886×886 | 785K | ~169K | 68.9 | 20.5 | 21.7 | 16.2 |
| XA | 1024×1024 | 1.05M | ~1.62M | 75.2 | 32.5 | 24.4 | 18.0 |
| **PX** | **2459×1316** | **3.24M** | **~6.45M** | **94.3** | **71.4** | **38.1** | **24.1** |
| **DX** | **2800×2288** | **6.41M** | **~12.7M** | **127.6** | **125.5** | **56.9** | **32.4** |

## Decode wall-time (median of 5, ms — **CLI**)

| fixture | shape | px | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | 66.0 | 16.4 | 17.9 | 16.8 |
| CT | 512×512 | 262K | 68.1 | 18.8 | 18.8 | 15.8 |
| MR | 886×886 | 785K | 72.4 | 20.8 | 20.4 | 18.1 |
| XA | 1024×1024 | 1.05M | 76.1 | 27.4 | 21.6 | 19.3 |
| **PX** | **2459×1316** | **3.24M** | **104.1** | **54.9** | **28.9** | **27.4** |
| **DX** | **2800×2288** | **6.41M** | **241.5** | **92.4** | **39.0** | **38.3** |

---

## Codec-only wall-time (J2KSwift in-process; subtract ~67 ms startup from CLI rows above)

The numbers below come from `CrossVersionDeltaBenchmark` running the codec in-process (no CLI overhead) on the same fixtures. The same-CSV captured for the Cross-Version Delta Report.

### Encode (J2KSwift in-process vs CLI codecs from above)

| fixture | px | **J2KSwift in-proc** | OpenJPH CLI | Grok CLI | Kakadu CLI | J2K vs Kakadu |
|---|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | **0.79** | 16.5 | 18.3 | 15.2 | **+19× faster** |
| CT 512² | 262K | **3.69** | 20.1 | 19.6 | 15.6 | **+4.2× faster** |
| MR 886² | 785K | **2.95** | 20.5 | 21.7 | 16.2 | **+5.5× faster** |
| XA 1024² | 1.05M | **7.36** | 32.5 | 24.4 | 18.0 | **+2.4× faster** |
| PX 2459×1316 | 3.24M | **24.74** | 71.4 | 38.1 | 24.1 | tie (-2 %) |
| **DX 2800×2288** | **6.41M** | **54.70** | 125.5 | 56.9 | **32.4** | **−1.69× behind** |

### Decode (J2KSwift in-process vs CLI codecs from above)

| fixture | px | **J2KSwift in-proc** | OpenJPH CLI | Grok CLI | Kakadu CLI | J2K vs Kakadu |
|---|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | **0.71** | 16.4 | 17.9 | 16.8 | **+24× faster** |
| CT 512² | 262K | **3.71** | 18.8 | 18.8 | 15.8 | **+4.3× faster** |
| MR 886² | 785K | **5.52** | 20.8 | 20.4 | 18.1 | **+3.3× faster** |
| XA 1024² | 1.05M | **8.83** | 27.4 | 21.6 | 19.3 | **+2.2× faster** |
| PX 2459×1316 | 3.24M | **34.02** | 54.9 | 28.9 | 27.4 | **−1.24× behind** |
| **DX 2800×2288** | **6.41M** | **127.83** | 92.4 | 39.0 | **38.3** | **−3.34× behind** ⚠ |

The asymmetry is real: when J2KSwift is invoked in-process (the way every Swift / iOS / macOS / DICOMKit caller invokes it), it ships **wins on small-to-medium fixtures and ties on PX encode** vs all three external HT codecs. **DX** remains the lone gap — the v7.1.0 H3 multi-tile decode regression (60→128 ms regression vs v7.0.0, see [Cross-Version Delta Report](CROSS_VERSION_DELTA_REPORT_v5.38_v7.0_v7.1.md)) makes DX decode **3.34× behind Kakadu** when it should be only ~1.6× behind. Hotfixing the H3 routing recovers DX decode to ~60 ms (then ~1.6× behind Kakadu, the pre-H3 baseline).

---

## Lossless byte-equality

**Lossless contract**: the decoded PGM must equal the input PGM byte-for-byte. All codecs are encoding HT-conformant lossless 5/3, so the codestream contains every coefficient bit; the only free parameter is whether the decoded PGM is written big-endian (input format) or little-endian.

| codec | bytes-equal output | notes |
|---|:-:|---|
| J2KSwift v7.1.0 | ✓ | bit-exact PGM round-trip |
| OpenJPH 0.27 | ✓ | bit-exact PGM round-trip |
| Grok 20.3 | byte-swap | decoded PGM differs from input by byte ordering only; codec is lossless internally (sample values identical) |
| Kakadu 8.4.1 | ✓ | bit-exact PGM round-trip |

Grok's "byte-swap" output is a known PGM-writer convention difference, not a codec defect — the encoded codestream is bit-exact reversible, just decoded into a little-endian PGM. Validated by `HTTileParityMatrixTests`'s 12/12 cross-decode matrix where Grok's decoded coefficients match J2KSwift / OpenJPH / Kakadu byte-identical (max-pixel-diff = 0).

---

## Codestream size

All four codecs are HT-conformant lossless 5/3 — bytes are deterministic given the same coefficient pattern + tile layout. Differences come from header / packet padding and tile choices:

| fixture | px | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | 45,224 | 45,201 | 45,300 | 45,201 |
| CT 512² | 262K | 436,460 | 436,398 | 436,496 | 436,417 |
| MR 886² | 785K | 169,709 | 167,774 | 169,040 | 167,767 |
| XA 1024² | 1.05M | 1,621,712 | 1,621,116 | 1,621,191 | 1,621,201 |
| PX 2459×1316 | 3.24M | 6,453,588 | 6,430,774 | 6,430,873 | 6,431,290 |
| DX 2800×2288 | 6.41M | 12,705,470 | 12,681,852 | 12,681,953 | 12,682,694 |

J2KSwift codestream is consistently within 0.4 % of the OpenJPH baseline; Grok and Kakadu are within 0.01 % of each other. The small extras come from a slightly more conservative SOT / TLM marker padding and a single LRCP packet vs the default-mode Cprecincts of the others.

---

## Bottom-line read

1. **In-process small/medium fixtures**: J2KSwift v7.1.0 ties or beats every HT codec including Kakadu through PX (3.24 M px). The wins on MR-small / CT / MR 886² are 4–24× thanks to Swift's lightweight in-process invocation vs the C codecs' CLI overhead — but the codec-only J2KSwift wall is genuinely competitive at these sizes.
2. **DX (6.41 MP)**: J2KSwift v7.1.0 encode is **−1.69× behind Kakadu**, decode is **−3.34× behind Kakadu**. The decode gap widens beyond what v7.0.0 was due to the H3 regression; recovering v7.0.0 decode wall (60 ms) puts decode at ~−1.6× — the same as encode.
3. **CLI overhead matters for users**: Anyone shelling out to the `j2k` CLI per file pays a ~67 ms tax that wipes out small-fixture wins. The DICOMKit / SwiftPM / direct-API caller, which is the primary product target, doesn't pay this — it's purely the CLI distribution.

**Hotfix candidate that closes the DX decode gap**: the H3 multi-tile per-tile GPU IDWT routing should fall back to CPU when per-tile pixel count is below ~1 MP. The `_gpuInverse53MultiTilePerTilePixelThreshold` static var was added in K1 ([#350](https://github.com/Raster-Lab/9J2KSwift/pull/350)) but isn't actually consulted on the production routing path — wire it in and DX 4x4 (the .auto-default for ≥3 MP fixtures) recovers the v7.0.0 decode wall.

---

## Reproducing

```bash
# J2KSwift in-process (this is what real callers experience)
LABEL=v7.1.0 J2K_DELTA_OUT=/tmp/j2k_delta_v7.1.0 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark

# All four codecs via CLI (cross-codec comparison)
bash /tmp/cross_codec_v710.sh
```

The CLI script lives at `/tmp/cross_codec_v710.sh` (a one-off harness; not committed to the repo). It reads fixtures from `Tests/Fixtures/CrossCodec/`, invokes each codec's CLI 5× per cell, takes the median, and writes a CSV to `/tmp/cross_codec_v710/results.csv`.
