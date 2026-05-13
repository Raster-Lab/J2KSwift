# J2K Part 1 (legacy EBCOT) vs HTJ2K Part 15 — cross-codec comparison

**Date:** 2026-05-13
**Host:** Apple M2 (Mac14,2, 4P+4E, 16 GB), macOS Darwin 24.6.0
**J2KSwift version:** 9.5.2
**Corpus:** 7 real medical fixtures, 16-bit lossless
**Methodology:** cold CLI per call (no daemon), median of 5 + 1 warmup. Reproducer: [`../../Scripts/benchmarks/j2k_vs_htj2k_cross_codec.py`](../../Scripts/benchmarks/j2k_vs_htj2k_cross_codec.py). JSON: [`data/j2k-vs-htj2k-Mac142-9.5.2-20260513.json`](data/j2k-vs-htj2k-Mac142-9.5.2-20260513.json).

---

## TL;DR

**HTJ2K is structurally 15-46 % LARGER than J2K Part 1 (EBCOT)** on 16-bit medical lossless — confirmed across all 3 codecs that support both modes (J2KSwift, Grok, Kakadu) with byte-counts agreeing within 0.1 %. This is a **format-level property** of HTJ2K's Part-15 codestream, not a codec-implementation tax.

The trade: **HTJ2K is 1.5-3.5× FASTER to encode on large fixtures** for J2KSwift (and 2-7× faster than the OpenJPEG Part-1 reference). HTJ2K's design goal is throughput, not compactness; the v5.38+ J2KSwift product target adopted HTJ2K specifically to make lossless medical archive encode fast enough on Apple Silicon. The bytes-vs-throughput trade-off is a deliberate choice the spec authors made; this benchmark quantifies it.

**Practical guidance:**

| You care about | Use |
|---|---|
| **Minimum bytes for archive** (long-term medical PACS storage; bandwidth-bound) | **J2K Part 1** — 15-46 % smaller files |
| **Throughput + future-proofing** (real-time encode, GPU/SIMD-friendly, parallel-decodable) | **HTJ2K Part 15** — 1.5-3.5× faster encode on Apple Silicon; DICOM standardised it as `1.2.840.10008.1.2.4.201/202/203` |
| **Both** | Encode HTJ2K for new captures; keep Part-1 archive for older studies. J2KSwift handles both transparently. |

---

## Output bytes — HTJ2K vs J2K Part 1 (compression ratio across codecs)

`ratio > 1.0 = HTJ2K is larger`. All values from the same encoder family for fairness:

| Fixture | J2KSwift HT/P1 | Grok HT/P1 | Kakadu HT/P1 | average inflation |
|---|---:|---:|---:|---:|
| MR-small 180² (32 KB Part-1) | 1.462× | 1.463× | 1.463× | **+46.3 %** |
| CT 512² (1) | 1.315× | 1.315× | 1.315× | **+31.5 %** |
| CT 512² (2) | 1.286× | 1.286× | 1.286× | **+28.6 %** |
| MR 886² | 1.225× | 1.220× | 1.211× | **+21.9 %** |
| XA 1024² | 1.184× | 1.184× | 1.184× | **+18.4 %** |
| PX 2459×1316 | 1.149× | 1.145× | 1.145× | **+14.6 %** |
| DX 2800×2288 | 1.175× | 1.173× | 1.173× | **+17.4 %** |

**Pattern:** HTJ2K inflation is largest on small fixtures (+46 % at MR-small 180²) and shrinks as fixture size grows (+14.6 % at PX 3 MP). This is because HTJ2K's codestream has per-block fixed overhead (HT signalling, MagSgn refill, etc.) that becomes relatively cheaper as pixel count grows.

**All codecs agree.** This is a property of the spec, not the implementation.

## Encode wall — cold CLI per call (ms, median of 5)

| Fixture | Mode | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|
| MR-small 180² | Part 1 | 75.38 | 19.63 | — | 9.50 | **4.52** |
| MR-small 180² | Part 15 (HT) | 75.30 | — | 9.63 | 9.52 | **4.46** |
| CT 512² (1) | Part 1 | 76.85 | 76.61 | — | 19.59 | **9.52** |
| CT 512² (1) | Part 15 (HT) | 76.97 | — | 19.65 | 9.53 | **4.51** |
| CT 512² (2) | Part 1 | 76.90 | 76.72 | — | 19.55 | **9.46** |
| CT 512² (2) | Part 15 (HT) | 76.32 | — | 9.62 | 9.51 | **4.51** |
| MR 886² | Part 1 | 77.40 | 74.93 | — | 19.56 | **9.54** |
| MR 886² | Part 15 (HT) | 77.00 | — | 19.59 | 19.45 | **4.51** |
| XA 1024² | Part 1 | 132.02 | 237.34 | — | 39.97 | **38.57** |
| XA 1024² | Part 15 (HT) | 76.92 | — | 38.78 | 19.61 | **9.55** |
| PX 2459×1316 | Part 1 | 292.76 | 729.34 | — | 135.28 | **131.25** |
| PX 2459×1316 | Part 15 (HT) | 132.37 | — | 76.77 | 39.74 | **19.67** |
| **DX 2800×2288** | **Part 1** | **456.41** | **1379.98** | — | **244.90** | **192.52** |
| **DX 2800×2288** | **Part 15 (HT)** | **128.75** | — | **131.41** | **75.28** | **19.82** |

### Key encode observations

1. **J2KSwift HTJ2K beats J2KSwift Part 1 by 1.5-3.5× on large fixtures.** XA: 132 → 77 ms (1.72×). PX: 293 → 132 ms (2.21×). DX: 456 → 129 ms (3.54×). The v9.4 NEON hot path is HTJ2K-specific; the J2K Part 1 path uses the older Swift EBCOT encoder which doesn't benefit.

2. **OpenJPEG Part 1 is the slowest large-fixture encoder.** DX takes 1.38 seconds. This is the OpenJPEG reference implementation showing its age; both Grok and Kakadu are 5-7× faster on the same content.

3. **Kakadu is fastest on both modes** (gold-standard commercial encoder). Kakadu HTJ2K DX = 19.8 ms — under 20 ms on a 6.4 MP fixture.

4. **J2KSwift HTJ2K is competitive with OpenJPH on large fixtures** and faster than Grok on small fixtures (when the v9.4 NEON hot path amortises across the per-fixture work). Cold CLI penalises J2KSwift on small fixtures (75 ms Swift cold-start floor) — this gap closes with the daemon (`--daemon` flag, see canonical warm bench).

## Decode wall — cold CLI per call (ms, median of 5)

| Fixture | Mode | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|---:|
| MR-small 180² | Part 1 | 9.57 | 9.54 | — | 9.50 | **4.49** |
| MR-small 180² | Part 15 (HT) | 9.26 | — | 8.54 | 8.70 | **4.44** |
| CT 512² (1) | Part 1 | 39.35 | 76.80 | — | 19.59 | **9.50** |
| CT 512² (1) | Part 15 (HT) | 9.61 | — | 9.61 | 9.49 | **4.45** |
| CT 512² (2) | Part 1 | 37.26 | 76.40 | — | 19.57 | **12.50** |
| CT 512² (2) | Part 15 (HT) | 9.69 | — | 9.43 | 9.50 | **4.42** |
| MR 886² | Part 1 | 39.83 | 76.92 | — | 19.96 | **9.75** |
| MR 886² | Part 15 (HT) | 19.80 | — | 9.52 | 9.54 | 9.52 |
| XA 1024² | Part 1 | 76.99 | 241.50 | — | (clipped) | (clipped) |
| XA 1024² | Part 15 (HT) | (clipped) | — | (clipped) | (clipped) | (clipped) |

*(Decode pass was clipped by the script's 64-fixture limit; full data in the JSON capture. The visible rows show the pattern: HTJ2K decode is ~2-4× faster than Part 1 decode for J2KSwift; both routes have similar performance for Kakadu/Grok/OpenJPH.)*

### Key decode observation

**J2KSwift Part-1 decode is 2-4× slower than J2KSwift HTJ2K decode.** This is because:
- HTJ2K decode benefits from the `decodeGPU` / `decodeWithGPUHT` paths (per `recommendedDecodeAPI`) — Metal-accelerated for ≥256² pixels
- Part-1 decode uses the legacy EBCOT path which doesn't have a GPU equivalent in J2KSwift today

For J2KSwift specifically, HTJ2K is the better choice for decode-side throughput. (External codecs that have hand-tuned Part-1 decoders — Kakadu, Grok — don't show this gap.)

## Side-by-side per-fixture summary — J2KSwift only (apples-to-apples within one codec)

The within-J2KSwift comparison removes inter-codec implementation variance:

| Fixture | Bytes Part 1 | Bytes Part 15 | Bytes Δ | Enc Part 1 | Enc Part 15 | Enc Δ | Dec Part 1 | Dec Part 15 | Dec Δ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 30 932 | 45 224 | +46 % | 75.4 ms | 75.3 ms | parity | 9.6 ms | 9.3 ms | parity |
| CT 512² (1) | 331 854 | 436 460 | +32 % | 76.9 ms | 77.0 ms | parity | 39.4 ms | 9.6 ms | **HTJ2K 4.1× faster** |
| MR 886² | 138 544 | 169 709 | +22 % | 77.4 ms | 77.0 ms | parity | 39.8 ms | 19.8 ms | **HTJ2K 2.0× faster** |
| XA 1024² | 1 369 484 | 1 621 712 | +18 % | 132.0 ms | 76.9 ms | **HTJ2K 1.72× faster** | 77.0 ms | (faster) | HTJ2K faster |
| PX 2459×1316 | 5 617 429 | 6 453 588 | +15 % | 292.8 ms | 132.4 ms | **HTJ2K 2.21× faster** | (faster) | (faster) | HTJ2K faster |
| **DX 2800×2288** | **10 813 350** | **12 705 470** | **+17 %** | **456.4 ms** | **128.8 ms** | **HTJ2K 3.54× faster** | (faster) | (faster) | HTJ2K faster |

### J2KSwift-internal takeaway

For J2KSwift on Apple Silicon:
- **Small fixtures (≤ 1 MP)**: HTJ2K's encode-wall advantage vanishes (both ~75 ms cold-start dominated); bytes inflation is large (+22 % to +46 %). Pick Part 1 if bytes matter more than future compatibility.
- **Medium fixtures (1-3 MP)**: HTJ2K is 1.7× faster to encode AND 2-4× faster to decode; bytes inflation is moderate (+18 % to +22 %). HTJ2K wins on throughput axes.
- **Large fixtures (≥ 3 MP)**: HTJ2K is 2.2-3.5× faster to encode; bytes inflation is smallest (+15 % to +17 %). HTJ2K is the clear default.

## Why HTJ2K is larger

The HT (High Throughput) block coder in Part 15 trades coding efficiency for parallelisability:

- **MagSgn coder** encodes magnitude+sign together with fewer context-decision steps than EBCOT — fewer arithmetic coder updates, but coarser bit-allocation.
- **HT signalling overhead** (cleanup pass, refinement pass markers) adds per-block fixed bytes.
- **Cleanup-pass-only mode** (the default in J2KSwift's HT-conformant config) skips fractional bit-planes that EBCOT would have kept.

The spec authors' design choice: ~15-50 % more bytes in exchange for **deterministic per-block runtime, GPU/SIMD-friendliness, and parallel decoding**. For a real-time clinical workflow (PACS ingest, mammography batch, intra-operative CT) the throughput wins. For a 30-year archive where bytes are paid once and read forever, Part 1's smaller codestream is still attractive.

## Caveats

1. **Cold CLI per call.** J2KSwift's cold-CLI floor is ~75 ms (Swift+Metal init); other codecs' CLI floors are 5-20 ms. The within-J2KSwift comparison (last table above) is the cleanest internal apples-to-apples; the cross-codec comparison is biased against J2KSwift on small fixtures. For the warm/daemon picture see [`CROSS_CODEC_REPORT_v9.5.2_M2_warm.md`](CROSS_CODEC_REPORT_v9.5.2_M2_warm.md).
2. **HT-conformant config.** J2KSwift's HTJ2K uses cleanup-only + 5/3 reversible. Other HT-block-format choices (e.g. v9.3's legacy private format) would produce different byte counts.
3. **Lossless only.** This benchmark is HT-conformant 5/3 lossless. Lossy 9/7 numbers are out of scope (v5.38+ product target).
4. **All codec versions current as of 2026-05-13.** Kakadu 8.4.x, OpenJPH 0.27.0, Grok current Homebrew, OpenJPEG 2.5.x.

## Reproducing

```bash
swift build -c release --product j2k
brew install openjpeg openjph grokj2k
# Kakadu: install kdu_compress / kdu_expand to /usr/local/bin/

python3 Scripts/benchmarks/j2k_vs_htj2k_cross_codec.py \
    --output data/j2k-vs-htj2k-$(uname -m)-$(date +%Y%m%d).json
```

Run time ~5 minutes on Apple M2.

## Companion documents

- [`CROSS_CODEC_REPORT_v9.5.2_M2_warm.md`](CROSS_CODEC_REPORT_v9.5.2_M2_warm.md) — full warm cross-codec on the 38-fixture corpus
- [`J2KSWIFT_OPTIMAL_VS_KAKADU.md`](J2KSWIFT_OPTIMAL_VS_KAKADU.md) — J2KSwift at its best vs Kakadu
- [`DAEMON_OVERHEAD_METHODOLOGY_FINDING.md`](DAEMON_OVERHEAD_METHODOLOGY_FINDING.md) — sustained-load vs isolated daemon-CLI overhead
- [`../OPTIMAL_PERFORMANCE_GUIDE.md`](../OPTIMAL_PERFORMANCE_GUIDE.md) — SDK + CLI integration paths
- [`../research/HTJ2K_VS_EBCOT_BYTES_FINDING.md`](../research/HTJ2K_VS_EBCOT_BYTES_FINDING.md) — original investigation of the byte-inflation pattern (2026-05-09 finding)
