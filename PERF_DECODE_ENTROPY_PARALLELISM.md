# Decode entropy parallelism — load-balanced + P-core-biased scheduling

**Date:** 2026-05-30 · **Host:** Apple M2 (8 cores) · **Goal:** close the decode gap to Kakadu/Grok.

## What changed

`J2KDecoderPipeline.swift` — the parallel code-block (tier-1) entropy decode previously split blocks into exactly `coreCount` **contiguous** chunks (`chunkSize = blockCount / coreCount`) with **no load-balancing, no oversubscription, and no QoS**. Because code-block decode cost is highly skewed (dense LL / low-frequency vs near-empty HH) and blocks arrive in resolution/packet order, the expensive blocks clustered into a few chunks → the slowest chunk gated the stage while other cores idled (**~2.9 of 8 cores effective, measured**), and the default-priority tasks spilled onto the M-series E-cores (3–4× slower than P-cores).

**Fix:** distribute blocks across `2 × coreCount` buckets via **LPT** (longest-processing-time-first — sort by descending encoded byte length, greedily assign to the least-loaded bucket), and run the tasks at **`.high` priority** (P-core bias). The decode-side analogue of the encoder's `Tier1ChunkPlan`. Output is keyed by block index, so the redistribution is **bit-exact**.

## Why this lever (vs the ~15 prior "lever-ceiling" washes)

Every prior optimization probe was a *pointwise / single-block* micro-op (SWAR/NEON refill, prefix-scan, MagSgn quad reads, per-quad SIMD classifier, GPU-HT batched dispatch, column-block IDWT). **None touched the work-distribution / scheduling layer.** Coarse parallelism was the one genuinely-untried axis — confirmed by a 5-way code-analysis + adversarial-verification scoping pass.

## Results (honest)

| Path | Before | After | Δ |
|---|---|---|---|
| **SDK / library decode** (in-proc bench config, CPU-IDWT) — DX | 63.9 ms | **48.1 ms** | **−25%** |
| same — CT | 6.2 ms | **2.3 ms** | −63% |
| effective cores (DX) | 2.9 | **4.4** | +52% |
| **Canonical decode** (large medical geomean, GPU-IDWT path) | 49.4 ms | 48.0 ms | −2.9% |
| MG decode (canonical) | 83–91 ms | 77–88 ms | −5 to −8% |
| Bit-exact / OpenJPH+Grok+Kakadu cross-decode | — | ✓ | — |

**It's a real, bit-exact improvement** — largest for the **library/SDK decode path** (the recommended consumption shape) and for multi-tile MG; on MG-mid J2KSwift now sometimes beats Kakadu and Grok. The mandatory gate (medical-corpus perf ×2 + strict cross-codec, 7 tests) passes 0-failure.

## What it did NOT do — honest standing vs #1

It did **not** make J2KSwift #1. On the canonical benchmark the large-medical decode gap to Kakadu remains ~1.1–1.3× (and is partly within run-to-run competitor noise, ~13%). The DX/PX single-tile decode path routes through **GPU IDWT**, where entropy is no longer the bottleneck, so the entropy rebalance barely moves those fixtures. The **encode** side of the same lever was tried and **washed (−0.3%)** — encode wall is forward-DWT-dominated, not entropy — so it was reverted (not shipped).

Net: this is the **13th independent confirmation** that the M2 + Swift hot-path gap to Kakadu is structural, but unlike the prior 12 it **banks a real decode improvement** rather than a pure wash.

## Credible paths to an actual #1 claim (next, higher-effort)

1. **Row-band CPU inverse-DWT** for single-tile 4–15 MP images (DX/PX) to use the idle cores and bypass GPU dispatch/readback — weeks, medium risk. The biggest remaining decode lever per the scoping.
2. **Cross-silicon** — prior measurements indicate J2KSwift already wins on M4. The fastest route to a truthful "#1" claim is to scope it to M4/A-series rather than M2.
3. **Narrower honest claim** — "fastest open/pure-Swift JPEG 2000+HTJ2K codec on Apple Silicon; within ~1.3× of Kakadu" remains accurate today.
