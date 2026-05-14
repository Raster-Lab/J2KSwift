# Cross-host warm cross-codec benchmark — Apple M2 (Mac14,2) vs Apple M4 (Mac16,10)

_Generated 2026-05-14T14:32:28 from `Scripts/benchmarks/compare_hosts.py`._

## What this report measures — plain English

This report shows how fast each codec encodes and decodes test images on
two different Apple chips — the **M2** and the newer **M4** — when the
codec is **called directly from inside an app**, the way a real iOS or
macOS application uses it. There is no command-line tool involved and no
separate helper process; the codec is doing its work in the same
process as the measurement harness.

**This is the most relevant report if you are:**
- Building an iOS or macOS app that uses J2KSwift as a library, OR
- Asking "how fast is J2KSwift compared to alternatives if I used it
  the same way?"

**Two things to know before reading the numbers:**

1. The three competitor codecs (Kakadu, OpenJPH, Grok) don't ship a
   Swift library, so we still measure them via their command-line
   tools. Their numbers in this report are the same as in the
   sustained / isolated companion reports — the fair comparison lives
   in the J2KSwift column only.
2. On M4, J2KSwift wins **31 of 38** test images outright; Kakadu wins
   the remaining 7. OpenJPH and Grok don't win any.

## How to read the columns

| Term | Meaning |
|---|---|
| **ms** | Milliseconds. **Lower is better.** |
| **fixture** | One test image. The corpus contains 38 of them, ranging from small thumbnails to high-resolution medical scans. |
| **Source** | Where the fixture came from: `real` = original public medical images, `synth` = deterministic synthetic, `medical-real` = additional PHI-safe real medical fixtures. |
| **codec** | The software doing the encode/decode. **J2KSwift+inproc** is ours; *Kakadu*, *OpenJPH*, *Grok* are third-party alternatives. |
| **M4 / M2** | Which Apple chip the test ran on. M4 is the newer, faster chip. |
| **speedup** (e.g. `1.74×`) | How many times faster the newer chip is. `1.74×` ≈ 43 % less time. `1.00×` = no change. |
| **wins** (in "Winner pattern" section) | How many of the 38 fixtures that codec was the fastest on. |

Medical-imaging modality abbreviations in fixture names: **MR** =
magnetic resonance, **CT** = computed tomography, **DX** = digital
chest X-ray, **PX** = panoramic dental, **MG** = mammography, **XA** =
angiography, **NM** = nuclear medicine, **CR** = computed radiography.

## The other two reports (same data, different shape)

- [CROSS_HOST_M2_M4_sustained.md](CROSS_HOST_M2_M4_sustained.md) —
  J2KSwift via the command-line tool, back-to-back. Use for batch /
  pipeline / CLI claims.
- [CROSS_HOST_M2_M4_isolated.md](CROSS_HOST_M2_M4_isolated.md) —
  command-line shape with brief cool-downs between calls. Methodology
  sanity-check.

---

## Hosts and runs

| # | Host | J2KSwift version | Captured | Source JSON |
|---|---|---|---|---|
| 0 (baseline) | Apple M2 (Mac14,2) | J2KSwift version 9.5.2 | 2026-05-14T06:47:04 | `Documentation/Benchmarks/data/benchmark-results-Mac142-9.5.2-warm-inproc-20260514.json` |
| 1 | Apple M4 (Mac16,10) | J2KSwift version 9.5.2 | 2026-05-14T14:27:34 | `Documentation/Benchmarks/data/benchmark-results-Mac1610-9.5.2-warm-inproc-20260514.json` |

**Bench parameters:** median of 7 timed runs after 2 warmups per fixture per codec per direction. j2kd daemon reachable: True.

---

## ENCODE — aggregate Apple M4 vs Apple M2

Median speedup (Apple M4 ms ÷ Apple M2 ms; >1× means Apple M4 is faster).

| Codec | n | Median Apple M4/Apple M2 | Min | Max |
|---|---|---|---|---|
| J2KSwift+inproc | 38 | **1.74×** | 1.46× | 2.28× |
| Grok | 38 | **2.00×** | 0.98× | 2.15× |
| Kakadu | 38 | **1.00×** | 0.89× | 2.12× |
| OpenJPH | 38 | **1.00×** | 0.98× | 2.11× |


## DECODE — aggregate Apple M4 vs Apple M2

Median speedup (Apple M4 ms ÷ Apple M2 ms; >1× means Apple M4 is faster).

| Codec | n | Median Apple M4/Apple M2 | Min | Max |
|---|---|---|---|---|
| J2KSwift+inproc | 38 | **1.55×** | 1.38× | 2.67× |
| Grok | 38 | **0.99×** | 0.96× | 2.13× |
| Kakadu | 38 | **0.99×** | 0.96× | 2.04× |
| OpenJPH | 38 | **1.00×** | 0.97× | 2.13× |


## Winner pattern by host (lowest median wins)

**ENCODE:**

- **Apple M2 (Mac14,2)** (38 fixtures): J2KSwift+inproc 28, Kakadu 10
- **Apple M4 (Mac16,10)** (38 fixtures): J2KSwift+inproc 31, Kakadu 7


**DECODE:**

- **Apple M2 (Mac14,2)** (38 fixtures): J2KSwift+inproc 25, Kakadu 7, Grok 6
- **Apple M4 (Mac16,10)** (38 fixtures): J2KSwift+inproc 29, Grok 8, Kakadu 1


---

## Per-fixture ENCODE — full ms + speedup matrix

| Fixture | Source | J2KSwift+inproc Apple M2 | J2KSwift+inproc Apple M4 | J2KSwift+inproc Apple M4/Apple M2 | Grok Apple M2 | Grok Apple M4 | Grok Apple M4/Apple M2 | Kakadu Apple M2 | Kakadu Apple M4 | Kakadu Apple M4/Apple M2 | OpenJPH Apple M2 | OpenJPH Apple M4 | OpenJPH Apple M4/Apple M2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MR-small 180² | real | 0.77 | 0.34 | 2.28× | 9.49 | 4.49 | 2.11× | 4.48 | 4.45 | 1.01× | 9.49 | 4.52 | 2.10× |
| MR 886² | real | 2.19 | 1.20 | 1.82× | 19.53 | 9.55 | 2.05× | 4.47 | 4.48 | 1.00× | 9.47 | 9.49 | 1.00× |
| CT 512² (1) | real | 2.38 | 1.33 | 1.79× | 9.49 | 9.59 | 0.99× | 4.46 | 4.50 | 0.99× | 9.46 | 9.52 | 0.99× |
| CT 512² (2) | real | 2.23 | 1.30 | 1.72× | 9.47 | 9.58 | 0.99× | 4.48 | 4.60 | 0.97× | 9.48 | 9.38 | 1.01× |
| XA 1024² | real | 5.52 | 3.37 | 1.64× | 19.58 | 9.55 | 2.05× | 9.52 | 4.53 | 2.10× | 39.53 | 19.57 | 2.02× |
| PX 2459×1316 | real | 17.71 | 10.14 | 1.75× | 39.73 | 19.76 | 2.01× | 19.66 | 9.60 | 2.05× | 76.64 | 76.33 | 1.00× |
| DX 2800×2288 | real | 41.88 | 22.48 | 1.86× | 75.66 | 43.38 | 1.74× | 39.78 | 19.99 | 1.99× | 131.76 | 131.28 | 1.00× |
| NM 256² (synth) | synth | 0.89 | 0.51 | 1.72× | 9.46 | 4.46 | 2.12× | 4.47 | 4.49 | 1.00× | 9.48 | 4.57 | 2.07× |
| MR 256² (synth) | synth | 0.91 | 0.53 | 1.71× | 9.48 | 4.41 | 2.15× | 4.46 | 4.50 | 0.99× | 9.47 | 4.48 | 2.11× |
| CT 384² (synth) | synth | 1.58 | 0.86 | 1.84× | 9.49 | 9.51 | 1.00× | 4.50 | 4.49 | 1.00× | 9.48 | 9.53 | 0.99× |
| MR 512² (synth) | synth | 2.73 | 1.35 | 2.03× | 9.49 | 9.58 | 0.99× | 4.49 | 4.50 | 1.00× | 9.44 | 9.55 | 0.99× |
| CT 768² (synth) | synth | 3.96 | 2.13 | 1.87× | 19.56 | 9.53 | 2.05× | 9.54 | 4.51 | 2.11× | 19.48 | 19.54 | 1.00× |
| XA 800² (synth) | synth | 3.80 | 2.31 | 1.65× | 19.57 | 9.61 | 2.04× | 9.51 | 4.54 | 2.09× | 19.57 | 19.61 | 1.00× |
| PX 1024×800 (synth) | synth | 4.85 | 2.81 | 1.72× | 19.49 | 9.59 | 2.03× | 9.51 | 4.48 | 2.12× | 19.49 | 19.53 | 1.00× |
| CT 1024² (synth) | synth | 5.91 | 3.81 | 1.55× | 19.44 | 9.60 | 2.03× | 9.56 | 9.61 | 0.99× | 39.56 | 19.54 | 2.03× |
| MR 1024² (synth) | synth | 7.10 | 3.84 | 1.85× | 19.43 | 9.58 | 2.03× | 9.53 | 9.62 | 0.99× | 39.53 | 19.67 | 2.01× |
| DX 1024² (synth) | synth | 6.39 | 3.55 | 1.80× | 19.59 | 9.62 | 2.04× | 9.53 | 9.56 | 1.00× | 39.52 | 19.56 | 2.02× |
| CR 1024² (synth) | synth | 6.23 | 3.71 | 1.68× | 19.60 | 9.60 | 2.04× | 9.55 | 9.53 | 1.00× | 39.54 | 19.55 | 2.02× |
| MG 1024×1280 (synth) | synth | 7.51 | 4.22 | 1.78× | 19.57 | 9.59 | 2.04× | 9.54 | 9.60 | 0.99× | 39.50 | 19.75 | 2.00× |
| XA 1280² (synth) | synth | 10.16 | 5.37 | 1.89× | 19.56 | 19.70 | 0.99× | 9.60 | 9.61 | 1.00× | 39.54 | 39.62 | 1.00× |
| MR 174×192 (small, real) | medical-real | 0.55 | 0.38 | 1.46× | 9.47 | 4.59 | 2.06× | 4.46 | 4.55 | 0.98× | 4.40 | 4.50 | 0.98× |
| CT 512×512 (small, real) | medical-real | 2.11 | 1.22 | 1.73× | 9.48 | 9.52 | 1.00× | 4.48 | 4.53 | 0.99× | 9.47 | 9.54 | 0.99× |
| CT 512×512 (mid, real) | medical-real | 2.13 | 1.28 | 1.65× | 9.47 | 9.55 | 0.99× | 4.48 | 4.51 | 0.99× | 9.44 | 9.53 | 0.99× |
| CT 512×512 (large, real) | medical-real | 2.05 | 1.24 | 1.66× | 9.48 | 9.50 | 1.00× | 4.47 | 4.55 | 0.98× | 9.46 | 9.56 | 0.99× |
| MR 512×512 (mid, real) | medical-real | 2.29 | 1.19 | 1.92× | 9.49 | 9.55 | 0.99× | 4.46 | 4.56 | 0.98× | 9.46 | 9.55 | 0.99× |
| MR 512×512 (large, real) | medical-real | 2.22 | 1.35 | 1.65× | 9.47 | 9.63 | 0.98× | 4.49 | 4.63 | 0.97× | 9.47 | 9.54 | 0.99× |
| XA 1024×1024 (small, real) | medical-real | 4.98 | 3.05 | 1.63× | 19.51 | 9.64 | 2.02× | 9.50 | 4.51 | 2.11× | 19.51 | 19.52 | 1.00× |
| XA 1024×1024 (mid, real) | medical-real | 4.94 | 3.18 | 1.55× | 19.56 | 9.54 | 2.05× | 9.49 | 4.53 | 2.10× | 19.48 | 19.48 | 1.00× |
| XA 1024×1024 (large, real) | medical-real | 4.79 | 3.03 | 1.58× | 19.25 | 9.60 | 2.00× | 9.49 | 4.51 | 2.10× | 19.48 | 19.51 | 1.00× |
| PX 2459×1316 (small, real) | medical-real | 14.35 | 8.32 | 1.73× | 39.24 | 19.71 | 1.99× | 9.26 | 10.36 | 0.89× | 76.62 | 39.61 | 1.93× |
| PX 2793×1316 (mid, real) | medical-real | 16.57 | 9.52 | 1.74× | 39.22 | 19.74 | 1.99× | 20.44 | 10.63 | 1.92× | 76.61 | 76.77 | 1.00× |
| PX 2812×1316 (large, real) | medical-real | 16.81 | 9.41 | 1.79× | 39.72 | 19.78 | 2.01× | 9.84 | 10.57 | 0.93× | 76.70 | 76.76 | 1.00× |
| DX 2224×2798 (small, real) | medical-real | 34.48 | 17.29 | 1.99× | 76.60 | 41.66 | 1.84× | 19.83 | 10.93 | 1.81× | 130.76 | 76.72 | 1.70× |
| DX 2800×2288 (mid, real) | medical-real | 34.43 | 19.05 | 1.81× | 75.06 | 40.14 | 1.87× | 19.76 | 20.15 | 0.98× | 131.89 | 76.65 | 1.72× |
| DX 2544×3056 (large, real) | medical-real | 42.90 | 23.31 | 1.84× | 76.20 | 39.48 | 1.93× | 19.99 | 19.89 | 1.00× | 131.73 | 131.97 | 1.00× |
| MG 3516×4784 (small, real) | medical-real | 62.93 | 36.62 | 1.72× | 131.67 | 82.77 | 1.59× | 39.11 | 20.33 | 1.92× | 185.99 | 131.72 | 1.41× |
| MG 3518×4784 (mid, real) | medical-real | 64.05 | 38.76 | 1.65× | 129.70 | 81.16 | 1.60× | 39.74 | 19.92 | 2.00× | 131.79 | 130.67 | 1.01× |
| MG 3521×4784 (large, real) | medical-real | 63.83 | 36.66 | 1.74× | 126.86 | 82.79 | 1.53× | 39.82 | 19.80 | 2.01× | 185.14 | 131.72 | 1.41× |


## Per-fixture DECODE — full ms + speedup matrix

| Fixture | Source | J2KSwift+inproc Apple M2 | J2KSwift+inproc Apple M4 | J2KSwift+inproc Apple M4/Apple M2 | Grok Apple M2 | Grok Apple M4 | Grok Apple M4/Apple M2 | Kakadu Apple M2 | Kakadu Apple M4 | Kakadu Apple M4/Apple M2 | OpenJPH Apple M2 | OpenJPH Apple M4 | OpenJPH Apple M4/Apple M2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MR-small 180² | real | 0.70 | 0.38 | 1.83× | 9.48 | 4.48 | 2.12× | 4.45 | 4.51 | 0.99× | 4.40 | 4.46 | 0.99× |
| MR 886² | real | 4.99 | 3.38 | 1.48× | 9.51 | 9.59 | 0.99× | 9.52 | 9.51 | 1.00× | 9.43 | 9.48 | 0.99× |
| CT 512² (1) | real | 2.80 | 1.84 | 1.52× | 9.50 | 9.55 | 0.99× | 4.42 | 4.48 | 0.99× | 9.44 | 9.53 | 0.99× |
| CT 512² (2) | real | 2.62 | 1.79 | 1.46× | 9.49 | 9.58 | 0.99× | 4.44 | 4.54 | 0.98× | 9.50 | 9.54 | 1.00× |
| XA 1024² | real | 7.94 | 5.44 | 1.46× | 9.53 | 9.73 | 0.98× | 9.52 | 9.59 | 0.99× | 19.54 | 19.55 | 1.00× |
| PX 2459×1316 | real | 30.41 | 18.31 | 1.66× | 19.70 | 19.72 | 1.00× | 19.54 | 19.85 | 0.98× | 75.23 | 39.71 | 1.89× |
| DX 2800×2288 | real | 59.45 | 32.37 | 1.84× | 39.79 | 19.80 | 2.01× | 39.80 | 39.82 | 1.00× | 131.95 | 75.41 | 1.75× |
| NM 256² (synth) | synth | 0.95 | 0.57 | 1.67× | 9.47 | 4.48 | 2.11× | 4.46 | 4.50 | 0.99× | 9.45 | 4.53 | 2.09× |
| MR 256² (synth) | synth | 0.99 | 0.61 | 1.64× | 9.48 | 4.49 | 2.11× | 4.47 | 4.49 | 1.00× | 9.46 | 4.50 | 2.10× |
| CT 384² (synth) | synth | 1.75 | 1.10 | 1.59× | 9.50 | 4.46 | 2.13× | 4.47 | 4.47 | 1.00× | 9.45 | 4.43 | 2.13× |
| MR 512² (synth) | synth | 3.05 | 1.84 | 1.66× | 9.48 | 9.54 | 0.99× | 4.40 | 4.55 | 0.97× | 9.46 | 9.51 | 0.99× |
| CT 768² (synth) | synth | 5.41 | 3.30 | 1.64× | 9.49 | 9.72 | 0.98× | 9.49 | 9.69 | 0.98× | 19.52 | 9.63 | 2.03× |
| XA 800² (synth) | synth | 5.59 | 3.55 | 1.58× | 9.56 | 9.54 | 1.00× | 9.36 | 9.66 | 0.97× | 19.50 | 9.56 | 2.04× |
| PX 1024×800 (synth) | synth | 7.14 | 4.54 | 1.57× | 9.53 | 9.72 | 0.98× | 9.53 | 9.61 | 0.99× | 19.52 | 19.64 | 0.99× |
| CT 1024² (synth) | synth | 8.50 | 5.98 | 1.42× | 9.52 | 9.68 | 0.98× | 9.52 | 9.77 | 0.97× | 19.52 | 19.60 | 1.00× |
| MR 1024² (synth) | synth | 9.19 | 5.69 | 1.61× | 9.48 | 9.79 | 0.97× | 9.51 | 9.56 | 0.99× | 19.50 | 19.55 | 1.00× |
| DX 1024² (synth) | synth | 15.23 | 5.70 | 2.67× | 9.52 | 9.95 | 0.96× | 9.52 | 9.57 | 0.99× | 19.49 | 19.54 | 1.00× |
| CR 1024² (synth) | synth | 8.87 | 5.73 | 1.55× | 9.50 | 9.66 | 0.98× | 9.54 | 9.79 | 0.97× | 19.51 | 19.56 | 1.00× |
| MG 1024×1280 (synth) | synth | 10.52 | 7.25 | 1.45× | 19.45 | 9.75 | 1.99× | 9.50 | 9.68 | 0.98× | 19.54 | 19.62 | 1.00× |
| XA 1280² (synth) | synth | 12.78 | 8.89 | 1.44× | 19.55 | 9.69 | 2.02× | 19.59 | 9.58 | 2.04× | 39.57 | 19.58 | 2.02× |
| MR 174×192 (small, real) | medical-real | 0.58 | 0.38 | 1.52× | 9.47 | 4.52 | 2.10× | 4.46 | 4.50 | 0.99× | 9.50 | 4.50 | 2.11× |
| CT 512×512 (small, real) | medical-real | 2.56 | 1.71 | 1.50× | 9.48 | 9.59 | 0.99× | 4.47 | 4.62 | 0.97× | 9.46 | 9.47 | 1.00× |
| CT 512×512 (mid, real) | medical-real | 2.50 | 1.72 | 1.46× | 9.46 | 9.55 | 0.99× | 4.41 | 4.53 | 0.97× | 9.48 | 9.50 | 1.00× |
| CT 512×512 (large, real) | medical-real | 2.49 | 1.78 | 1.40× | 9.47 | 9.55 | 0.99× | 4.45 | 4.54 | 0.98× | 9.47 | 9.59 | 0.99× |
| MR 512×512 (mid, real) | medical-real | 2.57 | 1.86 | 1.38× | 9.46 | 9.57 | 0.99× | 4.46 | 4.54 | 0.98× | 9.45 | 9.46 | 1.00× |
| MR 512×512 (large, real) | medical-real | 2.66 | 1.79 | 1.49× | 9.46 | 9.58 | 0.99× | 4.47 | 4.49 | 1.00× | 9.53 | 9.54 | 1.00× |
| XA 1024×1024 (small, real) | medical-real | 7.41 | 5.12 | 1.45× | 9.51 | 9.85 | 0.97× | 9.49 | 9.55 | 0.99× | 19.51 | 19.64 | 0.99× |
| XA 1024×1024 (mid, real) | medical-real | 7.58 | 5.28 | 1.44× | 9.53 | 9.68 | 0.98× | 9.48 | 9.56 | 0.99× | 19.49 | 19.52 | 1.00× |
| XA 1024×1024 (large, real) | medical-real | 7.47 | 5.16 | 1.45× | 9.54 | 9.72 | 0.98× | 9.50 | 9.56 | 0.99× | 18.99 | 19.52 | 0.97× |
| PX 2459×1316 (small, real) | medical-real | 27.81 | 17.10 | 1.63× | 19.19 | 19.75 | 0.97× | 19.62 | 19.68 | 1.00× | 76.47 | 39.22 | 1.95× |
| PX 2793×1316 (mid, real) | medical-real | 30.75 | 19.61 | 1.57× | 19.75 | 19.41 | 1.02× | 19.59 | 19.78 | 0.99× | 76.74 | 39.68 | 1.93× |
| PX 2812×1316 (large, real) | medical-real | 31.12 | 21.51 | 1.45× | 19.72 | 19.77 | 1.00× | 19.64 | 19.67 | 1.00× | 76.23 | 38.75 | 1.97× |
| DX 2224×2798 (small, real) | medical-real | 49.78 | 30.40 | 1.64× | 39.68 | 19.78 | 2.01× | 39.46 | 19.82 | 1.99× | 76.80 | 76.80 | 1.00× |
| DX 2800×2288 (mid, real) | medical-real | 50.79 | 33.73 | 1.51× | 39.81 | 19.78 | 2.01× | 39.66 | 35.88 | 1.11× | 131.38 | 76.54 | 1.72× |
| DX 2544×3056 (large, real) | medical-real | 63.73 | 39.32 | 1.62× | 38.79 | 19.81 | 1.96× | 39.81 | 39.15 | 1.02× | 131.23 | 76.50 | 1.72× |
| MG 3516×4784 (small, real) | medical-real | 144.68 | 87.59 | 1.65× | 75.10 | 40.48 | 1.86× | 73.62 | 76.33 | 0.96× | 182.91 | 130.78 | 1.40× |
| MG 3518×4784 (mid, real) | medical-real | 136.20 | 63.96 | 2.13× | 76.17 | 39.85 | 1.91× | 76.51 | 76.89 | 1.00× | 131.82 | 128.51 | 1.03× |
| MG 3521×4784 (large, real) | medical-real | 133.93 | 90.13 | 1.49× | 76.62 | 39.07 | 1.96× | 76.81 | 74.70 | 1.03× | 186.64 | 127.98 | 1.46× |


## Encoded-byte parity

_Cross-codec encoded sizes do not depend on host silicon — bytes are deterministic per (codec, source, config). To cross-check, compare the per-fixture .j2k/.jph byte counts in `/tmp/j2kswift_warm_bench/` from each host's run; differences > 0 indicate a non-deterministic codec config or version drift._
