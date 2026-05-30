# Cross-Codec Performance Report — J2KSwift v10.24.1

**Date:** 2026-05-30 · **Host:** Apple M2 (Mac14,2, 8 cores) · **Mode:** warm, median-of-7 after 2 warmups
**Harness:** `Scripts/benchmarks/cross_codec_warm_bench.py` (canonical) · 3 modes (in-proc / daemon-sustained / daemon-isolated)
**Codecs:** J2KSwift v10.24.1, OpenJPH 0.27, Grok 20.3, Kakadu 8.4 · **Task:** HT-conformant lossless J2K, 16-bit medical PGM
**Data:** `Documentation/Benchmarks/data/benchmark-results-Mac142-10.24.1-warm-{inproc,sustained,isolated}-20260530.json`

---

## Verdict — are we "world toppers"?

**Honest answer: No — not the outright fastest. But J2KSwift is genuinely top-tier / world-class.**

On the **large real medical fixtures** (PX/DX/MG, 3–17 MP — where codec work dominates and the comparison is meaningful), warm geomean:

| Direction | J2KSwift | Kakadu | Grok | OpenJPH | J2KSwift's standing |
|---|---:|---:|---:|---:|---|
| **Encode** | 29.5 ms | **22.7 ms** | 73.4 ms | 117.7 ms | **#2** — ~1.3× behind Kakadu; **2.5× faster than Grok, 4.0× faster than OpenJPH** |
| **Decode** | 49.4 ms | **39.1 ms** | **39.2 ms** | 111.1 ms | **#3** — ~1.27× behind Kakadu & Grok (tied leaders); **2.25× faster than OpenJPH** |

**Ranking on large medical (M2, warm):**
- **Encode:** Kakadu > **J2KSwift** > Grok > OpenJPH
- **Decode:** Kakadu ≈ Grok > **J2KSwift** > OpenJPH

So J2KSwift is **the fastest open/HTJ2K-reference-class codec by a wide margin** (it beats OpenJPH 2.2–4× and beats Grok on encode 2.5×), and it is **within ~1.3× of Kakadu**, the commercial gold standard — but **Kakadu still leads both directions**, and Grok ties Kakadu on decode. Claiming "world topper" would be inaccurate; "world-class, neck-and-second to Kakadu" is the truthful claim.

> Note: even these numbers *flatter* J2KSwift — they compare J2KSwift measured **in-process** (no process startup) against the competitors' **CLIs** (which pay ~4–9 ms fork+exec). On a startup-adjusted codec-only basis Kakadu's lead widens (Kakadu wins 32/38 encode, Grok 36/38 decode). The conclusion is robust.

---

## Why the naive "29/38 wins" headline is misleading

The raw whole-corpus tally is **J2KSwift fastest on 29/38 encode, 26/38 decode** — but that is an **artifact of fixture size**. The corpus is mostly small synthetic images where the competitors' CLI startup (~4–9 ms) exceeds the actual codec time, so J2KSwift's in-process measurement "wins" on startup, not codec speed. On the large fixtures (startup amortized), the picture inverts to the honest ranking above. We do **not** cite the 29/38 number as a performance claim.

---

## CLI deployment (j2kd daemon) — slower than all

Measured as a warm **CLI** (`j2k --daemon`, the deployment shape directly comparable to the other codecs' CLIs):

| Direction | J2KSwift+daemon | Kakadu CLI | ratio |
|---|---:|---:|---|
| Encode (large medical) | 74.4 ms | 27.9 ms | **0.38× (2.6× slower)** |
| Decode (large medical) | 75.2 ms | 27.8 ms | **0.37× (2.7× slower)** |

J2KSwift wins **0/38** in both daemon modes. The daemon amortizes Swift-runtime cold-start but each call still pays an XPC round-trip plus the `j2k` client process fork+exec — overhead the lean C/C++ CLIs don't have. **Takeaway: J2KSwift's strength is the in-process SDK, not the CLI.** Consumers should call the library directly (the `J2KEncoder`/`J2KDecoder` API), not shell out per image.

---

## What this means

- **As a Swift library on Apple Silicon, J2KSwift is competitive with the best codec in the world (Kakadu) on encode (~1.3×) and decode (~1.3×), and dominates the open reference (OpenJPH) and Grok-on-encode.** For a pure-Swift, memory-safe, strict-concurrency implementation with native DICOM ingestion, that is an excellent, defensible position.
- **It is not the single fastest.** Kakadu (decades-optimized commercial C++) remains the speed leader on M2; Grok matches it on decode.
- The honest marketable claim remains the prior one: **the fastest *pure-Swift / open* JPEG 2000 + HTJ2K codec on Apple Silicon, within ~1.3× of Kakadu** — not "world's fastest."

## Reproduce

```bash
bash Scripts/benchmarks/run_canonical_bench.sh      # rebuilds, refreshes daemon, runs 3 modes
# then inspect Documentation/Benchmarks/data/benchmark-results-*-10.24.1-*.json
```
