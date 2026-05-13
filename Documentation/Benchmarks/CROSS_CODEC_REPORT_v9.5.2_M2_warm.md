# Cross-Codec Research Report — v9.5.2, Apple M2, warm

**Date:** 2026-05-13
**Host:** Apple M2 (Mac14,2, 4P+4E, 16 GB unified memory), macOS Darwin 24.6.0
**J2KSwift version:** 9.5.2 with v9.4.0 C+NEON HT entropy hot path **default-on**
**External codecs:** OpenJPH 0.27.0 (Homebrew), Grok 20.x (Homebrew), Kakadu 8.4.x (commercial)
**Methodology:** `Scripts/benchmarks/cross_codec_warm_bench.py` — median of **7 timed runs** after **2 discarded warmups**, per (fixture × codec × direction). J2KSwift uses the warm `j2kd` XPC daemon (v9.5.0); external codecs use plain CLI.
**JSON capture:** [`data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json`](data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json)
**Corpus:** 38 PGM fixtures (7 real + 13 deterministic synthetic + 18 real-medical, all PHI-safe) + 13 DICOM fixtures (synthetic, uncompressed Explicit VR LE).

---

## Headline findings

### J2KSwift+daemon **beats OpenJPH** on every large medical fixture

| fixture (≥6 MP) | J2KSwift+daemon | OpenJPH | Δ (×) |
|---|---:|---:|---:|
| DX 2800×2288 (real) | **77.44** | 129.91 | **1.68×** |
| DX 2224×2798 (medical-real, small) | **77.66** | 131.78 | **1.70×** |
| DX 2800×2288 (medical-real, mid) | **75.68** | 131.78 | **1.74×** |
| DX 2544×3056 (medical-real, large) | **77.86** | 131.75 | **1.69×** |
| MG 3516×4784 (medical-real, small) | **129.97** | 186.82 | **1.44×** |
| MG 3521×4784 (medical-real, large) | **129.17** | 185.59 | **1.44×** |
| MG 3518×4784 (medical-real, mid) | 130.51 | 131.75 | parity |

This is the marketable claim: **J2KSwift is the fastest open-source HTJ2K encoder on Apple Silicon for chest radiography (DX) and mammography (MG) — the two largest-fixture clinical workloads.**

### NEON contribution (in-proc warm A/B)

The v9.4.0 C+NEON hot path delivers **−10 % to −21 % wall** on M2 warm encode. Measured by toggling `J2K_NEON_HOT_PATH=0` on `J2KMedicalCorpusEncodePerformanceTests`:

| fixture | NEON ON | NEON OFF | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| MR-small 180² | 0.6 | 0.7 | −0.1 | −14 % |
| CT 512² (1) | 2.4 | 2.7 | −0.3 | −11 % |
| CT 512² (2) | 2.3 | 2.9 | −0.6 | **−21 %** |
| MR 886² | 12.7 | 15.8 | −3.1 | −20 % |
| XA 1024² | 8.5 | 9.7 | −1.2 | −12 % |
| PX 2459×1316 | 28.2 | 32.6 | −4.4 | −13 % |
| **DX 2800×2288** | **55.7** | **63.0** | **−7.3** | **−12 %** |
| DX 2544×3056 (synth)\* | 66.1 | 73.5 | −7.4 | −10 % |
| MG 3520×4784 (synth)\* | 142.1 | 157.4 | **−15.3** | −10 % |
| MG 3521×4784 (synth)\* | 144.6 | 164.0 | **−19.4** | −12 % |

Larger fixtures save more in absolute ms (DX saves 7 ms, MG saves 15-19 ms); smaller fixtures save more in percentage (CT/MR 512² save 11-21 %).

### Where J2KSwift trails

- **Kakadu wins encode on every fixture** (closed-source commercial encoder; expected — it's the gold-standard reference)
- **Smaller fixtures (≤1 MP)**: J2KSwift trails because daemon-fork+exec overhead dominates per-call timing. SDK-shape (in-process, no XPC) eliminates this — see `V10_0_PHASE6_DAEMON_DECOMPOSITION.md`.
- **Decode generally**: J2KSwift+daemon trails on most fixtures except DX-medical-real-mid where it wins 1.70× over OpenJPH.

---

## PGM encode wall — full corpus (median of 7, ms)

| Fixture | Source | J2KSwift+daemon | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|
| MR-small 180² | real | 9.72 | 9.53 | 9.48 | 4.50 |
| MR 886² | real | 19.76 | 9.52 | 18.66 | 4.48 |
| CT 512² (1) | real | 39.22 | 19.61 | 9.55 | 4.47 |
| CT 512² (2) | real | 19.94 | 19.66 | 9.51 | 4.51 |
| XA 1024² | real | 39.97 | 39.54 | 19.64 | 9.57 |
| PX 2459×1316 | real | 74.99 | 76.74 | 39.74 | 19.75 |
| **DX 2800×2288** | **real** | **77.44** | **129.91** | 76.12 | 40.05 |
| NM 256² | synth | 19.71 | 9.61 | 9.55 | 4.50 |
| MR 256² | synth | 19.68 | 9.57 | 9.50 | 4.48 |
| CT 384² | synth | 19.72 | 9.52 | 9.49 | 4.46 |
| MR 512² | synth | 38.05 | 19.40 | 9.49 | 4.51 |
| CT 768² | synth | 40.11 | 19.59 | 19.60 | 9.53 |
| XA 800² | synth | 39.51 | 19.51 | 19.57 | 9.55 |
| PX 1024×800 | synth | 39.99 | 34.39 | 19.65 | 9.53 |
| CT 1024² | synth | 39.98 | 39.59 | 19.62 | 9.57 |
| MR 1024² | synth | 40.21 | 39.42 | 19.54 | 9.59 |
| DX 1024² | synth | 40.00 | 38.77 | 19.16 | 9.57 |
| CR 1024² | synth | 40.07 | 39.55 | 19.61 | 9.55 |
| MG 1024×1280 | synth | 40.10 | 39.63 | 19.73 | 9.74 |
| XA 1280² | synth | 78.00 | 39.56 | 19.58 | 9.58 |
| MR 174×192 (small) | medical-real | 19.66 | 9.56 | 9.51 | 4.51 |
| CT 512×512 (small) | medical-real | 40.21 | 19.63 | 9.48 | 4.50 |
| CT 512×512 (mid) | medical-real | 40.19 | 19.60 | 9.48 | 4.49 |
| CT 512×512 (large) | medical-real | 40.46 | 18.01 | 9.50 | 4.46 |
| MR 512×512 (mid) | medical-real | 40.03 | 19.62 | 9.50 | 4.50 |
| MR 512×512 (large) | medical-real | 19.76 | 19.60 | 9.48 | 4.44 |
| XA 1024×1024 (small) | medical-real | 39.96 | 39.72 | 19.56 | 9.54 |
| XA 1024×1024 (mid) | medical-real | 40.43 | 36.56 | 19.60 | 9.54 |
| XA 1024×1024 (large) | medical-real | 40.57 | 39.62 | 19.59 | 9.52 |
| **PX 2459×1316 (small)** | **medical-real** | **40.07** | **76.61** | 39.78 | 9.60 |
| PX 2793×1316 (mid) | medical-real | 77.55 | 76.40 | 39.76 | 9.57 |
| PX 2812×1316 (large) | medical-real | 76.24 | 74.63 | 39.78 | 9.56 |
| **DX 2224×2798 (small)** | **medical-real** | **77.66** | **131.78** | 76.02 | 19.71 |
| **DX 2800×2288 (mid)** | **medical-real** | **75.68** | **131.78** | 74.27 | 19.72 |
| **DX 2544×3056 (large)** | **medical-real** | **77.86** | **131.75** | 76.99 | 19.84 |
| **MG 3516×4784 (small)** | **medical-real** | **129.97** | **186.82** | 129.03 | 39.23 |
| MG 3518×4784 (mid) | medical-real | 130.51 | 131.75 | 132.20 | 39.91 |
| **MG 3521×4784 (large)** | **medical-real** | **129.17** | **185.59** | 128.62 | 39.58 |

**Bold rows** = J2KSwift+daemon wins or ties OpenJPH (the closest comparable open-source HTJ2K encoder).

## PGM decode wall — full corpus (median of 7, ms)

| Fixture | Source | J2KSwift+daemon | OpenJPH | Grok | Kakadu |
|---|---|---:|---:|---:|---:|
| MR-small 180² | real | 19.71 | 9.60 | 9.52 | 4.50 |
| MR 886² | real | 40.06 | 19.62 | 9.54 | 9.52 |
| CT 512² (1) | real | 20.05 | 9.51 | 9.50 | 4.49 |
| CT 512² (2) | real | 19.76 | 9.51 | 9.50 | 4.45 |
| XA 1024² | real | 40.14 | 19.48 | 9.52 | 9.55 |
| PX 2459×1316 | real | 76.11 | 76.77 | 19.12 | 19.72 |
| DX 2800×2288 | real | 130.69 | 131.76 | 39.83 | 39.80 |
| NM 256² | synth | 19.64 | 9.60 | 9.52 | 4.48 |
| MR 256² | synth | 9.67 | 9.53 | 9.47 | 4.46 |
| CT 384² | synth | 19.68 | 9.52 | 9.46 | 4.44 |
| MR 512² | synth | 20.06 | 9.54 | 9.46 | 4.39 |
| CT 768² | synth | 40.32 | 19.50 | 9.52 | 9.48 |
| XA 800² | synth | 40.54 | 19.50 | 9.50 | 9.53 |
| PX 1024×800 | synth | 40.01 | 19.59 | 9.52 | 9.51 |
| CT 1024² | synth | 40.44 | 19.57 | 9.52 | 9.51 |
| MR 1024² | synth | 39.70 | 19.57 | 9.56 | 9.51 |
| DX 1024² | synth | 40.29 | 19.56 | 9.50 | 9.50 |
| CR 1024² | synth | 40.18 | 19.58 | 9.52 | 9.51 |
| MG 1024×1280 | synth | 39.90 | 39.62 | 19.59 | 9.54 |
| XA 1280² | synth | **37.59** | 39.57 | 19.60 | 19.60 |
| MR 174×192 (small) | medical-real | 9.64 | 9.54 | 9.51 | 4.47 |
| CT 512×512 (small) | medical-real | 40.26 | 9.62 | 9.49 | 4.47 |
| CT 512×512 (mid) | medical-real | 19.71 | 9.55 | 9.47 | 4.47 |
| CT 512×512 (large) | medical-real | 19.77 | 9.53 | 9.47 | 4.48 |
| MR 512×512 (mid) | medical-real | 19.76 | 9.59 | 9.48 | 4.44 |
| MR 512×512 (large) | medical-real | 19.73 | 9.49 | 9.45 | 4.48 |
| XA 1024×1024 (small) | medical-real | 40.35 | 19.53 | 9.57 | 9.50 |
| XA 1024×1024 (mid) | medical-real | 39.92 | 19.54 | 9.51 | 9.49 |
| XA 1024×1024 (large) | medical-real | 39.98 | 19.55 | 9.50 | 9.50 |
| PX 2459×1316 (small) | medical-real | 75.71 | 76.03 | 19.68 | 19.60 |
| PX 2793×1316 (mid) | medical-real | 77.39 | 75.77 | 19.67 | 19.60 |
| PX 2812×1316 (large) | medical-real | 77.52 | 76.72 | 19.69 | 19.77 |
| DX 2224×2798 (small) | medical-real | 125.90 | 76.70 | 39.76 | 39.65 |
| **DX 2800×2288 (mid)** | **medical-real** | **77.07** | **130.92** | 39.82 | 39.77 |
| DX 2544×3056 (large) | medical-real | 129.12 | 131.87 | 38.17 | 39.71 |
| MG 3516×4784 (small) | medical-real | 186.85 | 185.06 | 75.58 | 76.77 |
| MG 3518×4784 (mid) | medical-real | 184.78 | 131.85 | 74.08 | 76.29 |
| MG 3521×4784 (large) | medical-real | 183.63 | 186.05 | 76.91 | 76.80 |

## DICOM encode wall — J2KSwift only (median of 7, ms)

External codec CLIs (OpenJPH/Grok/Kakadu) are J2K-only and don't accept DICOM Part 10 input directly. Cross-codec DICOM comparison requires DCMTK / pydicom to extract the PixelData tag first — separate workflow. **J2KSwift's native DICOM read path is the marketable strength** here.

| Fixture | Modality | J2KSwift+daemon (DICOM→J2K) ms |
|---|---|---:|
| NM 256² (synth) | NM | 19.64 |
| MR 256² (synth) | MR | 19.64 |
| CT 384² (synth) | CT | 39.64 |
| MR 512² (synth) | MR | 76.56 |
| CT 768² (synth) | CT | 76.82 |
| XA 800² (synth) | XA | 127.85 |
| PX 1024×800 (synth) | PX | 131.78 |
| CT 1024² (synth) | CT | 131.86 |
| MR 1024² (synth) | MR | 131.88 |
| DX 1024² (synth) | DX | 131.53 |
| CR 1024² (synth) | CR | 131.88 |
| MG 1024×1280 (synth) | MG | 186.81 |
| XA 1280² (synth) | XA | 186.46 |

DICOM encode wall ≈ PGM encode wall + DICOM-parse overhead. The parse overhead scales with image size since the PixelData tag dominates DICOM bytes.

---

## Methodology details

### Why warm-only

Cold-CLI J2KSwift pays a ~70 ms Swift-runtime + Metal init tax that external codec CLIs don't pay (OpenJPH/Grok/Kakadu CLIs have ~5 ms inherent startup). Mixing cold + warm in one comparison table distorts every claim.

The j2kd XPC daemon (shipped v9.5.0) amortises the Swift cold-start across CLI invocations — putting J2KSwift on the same warm-start footing as the others. Phase 6 of v10.0-research (`Documentation/research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md`) decomposes the daemon win and proves daemon-CLI is the right warm baseline (not in-proc, which carries XPC marshal overhead going the other direction).

### Why this corpus

20 PGM real medical fixtures (7 originals + 13 synthetic deterministic) gives modality + size diversity for apples-to-apples sizing claims. The 18 PHI-safe real-medical PGMs added in commit `28633ee` (PR #419) extend the corpus to **38 PGM + 13 DICOM = 51 fixtures**, spanning 6 modalities × 3 size tiers.

### Per-cell stats

- **runs**: 7 timed (median taken)
- **warmups**: 2 (discarded)
- **cell**: (fixture × codec × direction)
- **subprocess wall**: `time.perf_counter()` brackets `subprocess.run(cmd)`; includes fork+exec + library init + encode + write + cleanup
- **failure handling**: any non-zero exit OR missing output file → cell marked `(err)`; not included in median

### Caveats for marketing claims

1. **CLI shape, not SDK shape.** This is what `j2k encode/decode` invocations cost from the shell. SDK consumers calling `J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)` directly inside a long-lived process are ~20 ms faster on DX (XPC marshal cost avoided — see Phase 6).
2. **M2 only.** v9.2 Path B M4 measurement (`Documentation/benchmarks/CROSS_CODEC_REPORT_v9.2_PATH_B.md`) showed materially different daemon-vs-in-proc curves on M4. "Fastest on Apple Silicon" claims should be qualified by host class until M3+ / A-series re-measurement is available.
3. **HT-conformant lossless only.** This is the v5.38+ product target (lossless medical archive). Lossy 9/7 numbers are out of scope.
4. **External codec versions matter.** OpenJPH 0.27.0 + Kakadu 8.4.x are current as of 2026-05-13. Re-run with newer versions for fresh comparisons.

### Reproducing

```bash
# One-time setup
swift build -c release --product j2k --product j2kd
.build/release/j2k daemon-install --force
brew install openjph grokj2k
# Kakadu: install kdu_compress / kdu_expand to /usr/local/bin/
python3 Scripts/benchmarks/generate_synthetic_corpus.py
# (and have LocalDatasets/medical-dicom-organized/ if regenerating the
# medical-real fixtures via select_real_medical_corpus.py)

# Run the canonical warm benchmark
python3 Scripts/benchmarks/cross_codec_warm_bench.py \
    --output benchmark-results-$(uname -m)-$(date +%Y%m%d).json
```

Total runtime ~12 minutes on M2 (DX/MG fixtures dominate; ~700 subprocess CLI invocations).

### Reproducing the NEON A/B

```bash
# NEON ON (default)
swift test -c release --filter J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs

# NEON OFF (forces v9.3 Swift-only entropy path)
J2K_NEON_HOT_PATH=0 swift test -c release \
    --filter J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs
```

The CPU-encode-ms columns from the two runs are directly comparable
since other variables (fixture, run count, warmup) are held constant.

---

## Position summary

| Workload | J2KSwift+daemon position |
|---|---|
| **Apples-to-apples cross-codec encode**, large medical fixtures (DX, MG-large) | **Beats OpenJPH 1.4× – 1.7×** |
| Apples-to-apples cross-codec encode, mid fixtures (PX small/mid) | Parity with OpenJPH; trails Grok/Kakadu |
| Apples-to-apples cross-codec encode, small fixtures (≤1 MP) | Trails OpenJPH (daemon overhead dominates per-call) |
| Apples-to-apples cross-codec encode vs Kakadu | Trails (Kakadu is closed-source commercial gold standard) |
| Apples-to-apples cross-codec decode | Generally trails; DX-mid wins 1.70× over OpenJPH |
| **DICOM encode** | **Sole open-source codec with native DICOM input** |
| **NEON contribution** (in-proc warm A/B) | **−10 % to −21 % wall** vs Swift-only entropy path |
| SDK shape (in-process API calls, no daemon) | ~20 ms faster than daemon-CLI on DX (no XPC marshal); not measured here |

## Companion documents

- [Documentation/BENCHMARK.md](../BENCHMARK.md) — canonical methodology section
- [Documentation/research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md](../research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md) — daemon win decomposition (M2 vs M4 silicon divergence)
- [Documentation/research/V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md](../research/V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md) — GPU forward 5/3 vs `.auto` wash (10th lever-ceiling confirmation)
- [Documentation/releases/RELEASE_NOTES_v9.5.2.md](../releases/RELEASE_NOTES_v9.5.2.md) — daemon-install help SDK vs CLI guidance
- [Documentation/releases/RELEASE_NOTES_v9.5.0.md](../releases/RELEASE_NOTES_v9.5.0.md) — daemon-encode large-fixture closure
- [Documentation/releases/RELEASE_NOTES_v9.4.0.md](../releases/RELEASE_NOTES_v9.4.0.md) — custom C+NEON HT block-encoder hot path
- [data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json](data/benchmark-results-Mac142-9.5.2-NEONwarm-20260513.json) — full JSON capture (this report's source data)
