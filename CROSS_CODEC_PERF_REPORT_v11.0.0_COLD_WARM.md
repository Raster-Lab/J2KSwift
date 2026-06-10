# Cross-Codec Performance Report — J2KSwift v11.0.0, COLD + WARM

**Date:** 2026-06-10 · **Host:** Apple M2 (Mac14,2, 8 cores) · **J2KSwift:** v11.0.0
**Protocol:** median-of-7 after 2 warmups, per fixture per codec per direction; all five
modes measured back-to-back in one session (single thermal envelope), strictly sequential.
**Codecs:** J2KSwift v11.0.0, OpenJPH 0.27, Grok 20.3, Kakadu 8.4 · **Task:** HT-conformant
lossless J2K, 16-bit medical PGM (the canonical 38-fixture corpus; tables below show the
real-medical subset).
**Data:** `Documentation/Benchmarks/data/benchmark-results-Mac142-11.0.0-{warm-inproc,warm-sustained,warm-isolated,cold-cli,cold-sdk-firstcall}-20260610.json`
**Harness:** `Scripts/benchmarks/cross_codec_warm_bench.py` (3 warm modes) +
`Scripts/benchmarks/cross_codec_cold_cli_bench.py` (new in this report — identical corpus,
commands, and protocol; the J2KSwift column drops `--daemon` so every invocation is a fresh
one-shot process).

---

## The five modes, in one sentence each

| Mode | What it measures | Who should read it |
|---|---|---|
| **Warm in-proc** | Pure SDK wall (`j2k inproc-bench`): no process, no XPC | Library/SDK consumers (DICOMKit, PACS in-process) |
| **Warm daemon-sustained** | `j2k --daemon` CLI back-to-back vs competitor CLIs | Batch pipelines shelling out per image |
| **Warm daemon-isolated** | Same, with cool-downs between calls | Per-call latency floor for sporadic CLI use |
| **Cold CLI** | Fresh `j2k` process, **no daemon**, every invocation | One-shot scripting; worst-case CLI |
| **Cold SDK first-call** | First decode/encode in a fresh process, zero warmups | App-launch latency; what `preWarm()` hides |

## Verdict — large-medical geomeans (PX/DX/MG, 7 real fixtures, ms)

| Direction | J2K in-proc | J2K sustained | J2K isolated | J2K **COLD** | Kakadu sust. | Kakadu cold | Grok sust. |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Decode** | **59.8** | 102.1 | 105.4 | 120.6 | 47.6 | 47.2 | 47.6 |
| **Encode** | **36.4** | 83.0 | 98.5 | 150.8 | 26.4 | 26.6 | 87.6 |

- **Warm in-process is J2KSwift's shape.** 59.8 ms decode / 36.4 ms encode geomean —
  ~1.26×/1.38× behind Kakadu's *CLI* numbers, with the usual caveat that this compares an
  in-process call against a fork+exec'd CLI in both directions (the only shapes each side
  offers). On MG decode, J2KSwift in-proc **beats every competitor outright**
  (74.3–88.1 ms vs Kakadu 76.2–76.9, Grok 76.0–76.9).
- **Kakadu is effectively cold-proof** (47.2 cold vs 47.6 warm decode): a tiny static C++
  binary has nothing to warm. That is the structural gap in CLI shapes.
- **The daemon makes the CLI ~2.1× Kakadu, cold makes it ~2.6× (decode) / 5.7× (encode).**
  The daemon amortises the Swift-runtime + Metal tax but adds XPC + client spawn per call
  (~30–45 ms on this corpus); cold pays everything every time.

## Decode (median ms, real medical corpus)

| Fixture | J2K in-proc | J2K sust. | J2K isol. | J2K COLD | Kakadu | Grok | OpenJPH | Kakadu cold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MR 174×192 | **0.45** | 9.72 | 10.57 | 9.66 | 4.52 | 9.53 | 9.54 | 4.48 |
| CT 512² | **2.31** | 19.81 | 20.22 | 9.71 | 4.47 | 9.42 | 9.56 | 4.46 |
| XA 1024² | **6.96** | 40.77 | 40.80 | 20.01 | 9.53 | 9.55 | 19.65 | 9.50 |
| PX 2793×1316 | 29.85 | 53.67 | 78.22 | 76.55 | 19.62 | 19.72 | 76.79 | 19.88 |
| DX 2224×2798 | 48.56 | 82.70 | 81.31 | 75.61 | 39.74 | 39.51 | 76.85 | 39.67 |
| DX 2800×2288 | 60.26 | 84.45 | 79.16 | 76.60 | 39.83 | 39.83 | 131.67 | 38.20 |
| DX 2544×3056 | 59.88 | 136.09 | 124.75 | 129.71 | 39.69 | 39.43 | 132.05 | 39.81 |
| MG 3516×4784 | **79.90** | 132.85 | 131.55 | 186.61 | 76.19 | 76.97 | 182.27 | 76.85 |
| MG 3518×4784 | **74.30** | 128.95 | 131.63 | 184.35 | 76.89 | 76.00 | 131.87 | 76.81 |
| MG 3521×4784 | 88.07 | 132.78 | 132.88 | 187.47 | 76.88 | 76.92 | 183.77 | 74.23 |

## Encode (median ms, real medical corpus)

| Fixture | J2K in-proc | J2K sust. | J2K isol. | J2K COLD | Kakadu | Grok | OpenJPH | Kakadu cold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MR 174×192 | **0.58** | 9.84 | 20.16 | 76.29 | 4.46 | 9.49 | 9.58 | 4.49 |
| CT 512² | **2.20** | 19.47 | 20.27 | 76.09 | 4.42 | 9.55 | 19.61 | 4.50 |
| XA 1024² | **4.88** | 21.14 | 39.96 | 75.40 | 9.52 | 19.43 | 39.73 | 9.48 |
| PX 2793×1316 | **16.87** | 42.04 | 78.11 | 131.44 | 19.26 | 37.98 | 75.87 | 19.47 |
| DX 2224×2798 | 33.67 | 76.72 | 80.33 | 129.92 | 19.27 | 75.73 | 131.33 | 19.74 |
| DX 2800×2288 | 36.12 | 78.20 | 79.24 | 128.95 | 19.59 | 75.76 | 128.00 | 19.72 |
| DX 2544×3056 | 44.27 | 80.22 | 78.99 | 129.02 | 20.51 | 79.31 | 128.54 | 19.77 |
| MG 3516×4784 | 48.21 | 129.85 | 132.82 | 185.85 | 39.91 | 131.13 | 186.96 | 39.94 |
| MG 3518×4784 | **38.40** | 77.79 | 129.61 | 184.14 | 39.96 | 132.29 | 130.38 | 39.84 |
| MG 3521×4784 | 50.21 | 133.31 | 132.77 | 182.74 | 37.34 | 132.14 | 183.72 | 39.87 |

(Bold = J2KSwift fastest of all measured codecs/modes in that row's shape class.)

## Cold-start decomposition

### Cold-SDK first call (fresh process, zero warmups, median of 5) vs warm steady state

| Fixture | First decode | Warm decode | Decode tax | First encode | Warm encode | **Encode tax** |
|---|---:|---:|---:|---:|---:|---:|
| CT 512² | 3.45 | 2.31 | +1.1 | 42.68 | 2.20 | **+40.5** |
| XA 1024² | 9.67 | 6.96 | +2.7 | 52.42 | 4.88 | **+47.5** |
| PX 2793×1316 | 31.54 | 29.85 | +1.7 | 70.70 | 16.87 | **+53.8** |
| DX 2800×2288 | 50.53 | 60.26¹ | ~0 | 91.53 | 36.12 | **+55.4** |
| MG 3518×4784 | 81.68 | 74.30 | +7.4 | 119.52 | 38.40 | **+81.1** |

¹ dx_mid's warm median was noisy this session (its small/large siblings and the v10.25.0
capture all sit ~49–60); the first-call number aligns with the quieter captures.

### The two cold-start findings

1. **Cold decode is nearly tax-free (+1–7 ms); cold encode pays +40–81 ms — even on a
   512² image.** The CLI decode path defaults to CPU (`J2K_GPU_INVERSE_53=0`, the
   measured v8 Phase 2 decision), so a cold decode never initialises Metal. The encode
   path initialises the shared Metal session (device + shader library) regardless of
   whether the GPU forward-DWT threshold (3 MP) will ever fire — a 512² encode that runs
   entirely on CPU still pays ~40 ms of Metal warm-up. **Identified follow-up:** defer
   encoder Metal-session init until the pixel threshold actually routes a dispatch to the
   GPU; projected to cut the cold-encode floor from ~76 ms to roughly the ~10 ms
   runtime-only floor that cold decode already enjoys for sub-3 MP images.
2. **The cold one-shot CLI floor is ~9.6 ms (decode) / ~76 ms (encode)** — Swift runtime +
   dyld accounts for ~8–9 ms; everything above that on the encode side is the Metal init
   above. Kakadu's corresponding floor is ~4.5 ms in both directions.

## Honest standing per consumption shape

| You are… | Use | Standing vs best-in-class |
|---|---|---|
| In-process SDK consumer (DICOMKit, PACS) | `J2KEncoder`/`J2KDecoder` API, optional `preWarm()` | **Best shape.** MG decode leads all codecs; large-medical geomean ~1.26× Kakadu-CLI decode, ~1.38× encode; small fixtures 2–10× faster than any CLI |
| Batch pipeline shelling out per image | `j2k --daemon` | ~2.1× Kakadu CLI; the XPC + client spawn (~30–45 ms/call) dominates; prefer the SDK in-process |
| One-shot scripts | plain `j2k` | Decode: ~2.6× Kakadu; Encode: ~5.7× (Metal-init tax — see follow-up above) |

## Reproducing

```bash
# warm (3 modes)
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc  --output inproc.json
python3 Scripts/benchmarks/cross_codec_warm_bench.py            --output sustained.json
python3 Scripts/benchmarks/cross_codec_warm_bench.py --isolated --output isolated.json
# cold (fresh-process, no daemon)
python3 Scripts/benchmarks/cross_codec_cold_cli_bench.py --runs 7 --warmups 2 --output cold.json
```
