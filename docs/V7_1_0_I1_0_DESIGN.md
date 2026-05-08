# v7.1.0 I1.0 — GPU forward HT entropy approach C: design + risk analysis

**Status**: Design doc only. No code in this PR. Sign-off on the architecture before I1.1 (classify + prefix-sum kernels) lands.

**Branch**: `feature/v7.1.0-gpu-fwd-ht-entropy-c-design`

**Anchors**:
- [`docs/V7_1_0_PLAN.md`](V7_1_0_PLAN.md) §I1 — GPU forward HT entropy approach C scope
- [`docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) §4 — original approach taxonomy A/B/C/D/E
- v6-alpha6 #305 — approach B closed as -200 % regression at every corpus scale
- v6-alpha6 #306 — approach E (CPU-SIMD only) closed as wash on M2

---

## Why this exists

The Kakadu encode-wall gap on PX/DX is the v7.1.0 release's primary lever. Per the [`docs/V7_1_0_PLAN.md`](V7_1_0_PLAN.md) trajectory:

| Modality | Shape | px | J2KSwift v7.0.0 | Kakadu | gap |
|---|---|---:|---:|---:|---:|
| **PX** | **2459×1316** | **3.24M** | **24.26** | **11.2** | **+2.2× behind** |
| **DX** | **2800×2288** | **6.41M** | **52.79** | **18.9** | **+2.8× behind** |

Per F1 (#324) and #309's empirical breakdown, **entropy is ~45 % of DX encode wall** — by far the dominant remaining lever. The v6-alpha4 lever-ceiling memory locked out further CPU single-thread optimisation. v6-alpha6 explored two GPU approaches (B and E); both regressed or washed on M2. **Approaches C and D from the v6-alpha6 taxonomy remain unexplored.**

v7.1.0 I1 attacks approach C — the highest-upside untried GPU strategy. If it lands a measurable win, v7.1.0 closes the Kakadu encode gap on PX/DX materially. If it regresses (mirror of approach B's failure mode), it ships opt-in and the v7.1.0 release headline carries on H1.1 (decode-side wins, already shipped) + K1.

---

## Approach taxonomy — what's been tried, what's left

| Approach | Description | Status | DX wall reduction (measured or estimated) |
|---|---|---|---:|
| **A** | Per-codeblock thread, fully serial within thread | Untried | ~10–15 % (estimate) |
| **B** | 2-pass: classify GPU, emit CPU | **Closed** ([#305](https://github.com/Raster-Lab/J2KSwift/pull/305)) | **−200 % to −250 % regression** at every corpus scale on M2 |
| **C** | 3-pass: classify GPU → prefix-sum GPU → byte-write GPU + 0xFF correction | **Untried (v7.1.0 I-series target)** | **~35–40 % if correction is fast** |
| **D** | Per-warp/threadgroup serial (SIMD-group serial within block) | Untried | ~25–35 % (estimate) |
| **E** | CPU-SIMD only — promote v5.39 M1 SIMD classification + NEON on per-quad emit | **Closed** ([#306](https://github.com/Raster-Lab/J2KSwift/pull/306)) | **wash on M2** (within ±5 % noise band) |

### Why approach B failed (the empirical lesson)

[#305](https://github.com/Raster-Lab/J2KSwift/pull/305) measured DX 2x2 with approach B: GPU 238.68 ms vs CPU 71.62 ms = **3.3× slower**. The decision message identified the structural cause:

> Per-block CPU emit dominates total wall time, and the savings from offloading classification to GPU are tiny (sampleInfo is < 5 % of per-block emit cost; rho/eQMax accumulation, MEL/VLC/MagSgn emission are all on CPU and unaffected by the GPU work). GPU readback + per-block tuple unpacking costs more than the classification savings.

The lesson for approach C: **the byte emission MUST move to the GPU too, or the GPU classification cost is wasted on synchronization + readback**. Approach C is designed around this constraint — pass 3 is the byte-write itself, on GPU.

---

## Approach C — three-pass GPU pipeline architecture

### Stage overview

```
                  ┌──────────────────────────┐
input: per-block  │  Pass 1 — Classify       │  output: per-block byte budgets
coefficients   ─▶ │  (one threadgroup/block, │  (MagSgn / MEL / VLC bytes per block)
+ block dims      │   per-sample threads)     │  + per-sample tuple stream
                  └──────────────────────────┘
                              │
                              ▼
                  ┌──────────────────────────┐
                  │  Pass 2 — Prefix-sum     │  output: per-block byte offsets
                  │  (block-wide scan over   │  in the final concatenated buffer
                  │   per-block byte counts)  │
                  └──────────────────────────┘
                              │
                              ▼
                  ┌──────────────────────────┐
                  │  Pass 3 — Byte-write     │  output: GPU buffer with all
                  │  (one threadgroup/block, │  blocks' MagSgn+MEL+VLC bytes
                  │   per-block emission)     │  written in parallel
                  └──────────────────────────┘
                              │
                              ▼
                  ┌──────────────────────────┐
                  │  Pass 4 — 0xFF stuff     │  output: codestream-compliant
                  │  insertion (CPU or GPU)   │  byte stream per block
                  └──────────────────────────┘
                              │
                              ▼
                output: per-block bytes the existing
                CPU emitter (HTBlockLayoutConformant.assemble)
                can wrap in the standard MagSgn/MEL/VLC layout
```

### Pass 1 — Classify (GPU)

**Inputs**: per-sample Int32 coefficients (already passed to GPU after forward DWT — uses the existing v6-alpha5 GPU forward DWT output buffer); per-block dimensions; per-block missingMSBs.

**Outputs** (per-block):
- `magsgnByteCount`, `melByteCount`, `vlcByteCount` (3 × Int32 per block)
- Per-sample tuple stream: `(rho, eqMax, magnitude, sign)` packed into a per-sample 32-bit slot, written into a per-block scratch buffer

**Threadgroup organisation**: one threadgroup per block; threads within the group iterate samples (typically 32×32 = 1024 samples per block, fits in a 1024-thread group).

**Apple Metal primitives**:
- `simd_*` intrinsics for in-warp reduction (counting significant samples → byte budget)
- `threadgroup_barrier` between phases (sample-level reduction → block-level totals)
- `device` writes for the per-sample tuple stream (block-local scratch buffer, passed to pass 3)

**Risk**: Low. Approach B already proved per-sample classification on GPU is correct; the issue was that emit stayed on CPU. Pass 1 is a refined version of approach B's classifier.

### Pass 2 — Prefix-sum (GPU)

**Inputs**: per-block byte counts from pass 1 (3 × Int32 × N blocks).

**Outputs**: per-block byte offsets — start of each block's MagSgn/MEL/VLC region in the final output buffer. 3 separate prefix-sums (or one over a flattened triple).

**Apple Metal primitive**: `MPSScan` (Metal Performance Shaders inclusive/exclusive scan). For N = 2,300 blocks (DX 2x2 per-tile) this is well below MPS's efficient range. **Hand-rolled per-warp scan** is also viable for our block counts (N ≤ ~10K) — Apple's `simd_prefix_inclusive_sum` can do up to 32 elements per call; a two-level reduction handles up to 1024 then 32×1024 = 32K elements with two threadgroups.

**Decision for I1.1 spike**: try MPSScan first (least code), fall back to hand-rolled if MPSScan dispatch overhead is too high.

**Risk**: Low–medium. Prefix-sum is a textbook GPU primitive; the only risk is dispatch overhead being too high for our small N. Mitigated by hand-rolled fallback if MPSScan disappoints.

### Pass 3 — Byte-write (GPU)

**Inputs**: per-sample tuple stream (from pass 1); per-block byte offsets (from pass 2).

**Outputs**: GPU output buffer with all blocks' raw MagSgn/MEL/VLC bytes written at their per-block offsets (concatenated, no 0xFF stuffing yet).

**Threadgroup organisation**: one threadgroup per block; threads iterate samples in the per-block tuple stream and emit bits into the block's output region.

**Critical implementation detail**: bit-level writes within a block are **inherently serial** (next bit depends on previous bit's write position in the byte stream). However, blocks are **independent of each other**, so block-level parallelism via threadgroup-per-block is the right level of parallelism.

**Per-block bit-write strategy (within one threadgroup)**:
- One thread per block does the serial bit-write into a threadgroup-shared bit accumulator
- Other threads in the group help with parallel reduction-style work (e.g. computing run lengths for MEL coding)
- Use threadgroup memory for the bit accumulator state (24-bit register + spill to device on overflow)

This is the **highest-risk pass**. Approach D's "per-warp serial" idea applies here: SIMD-group serial within block (32-wide groups) where one thread does the serial bit-write and 31 stand idle. That wastes 96.9 % of GPU compute per group but the GPU has many such groups in flight simultaneously. **Whether the wasted threads pay off depends on whether N blocks is large enough to keep the GPU occupied** — DX 2x2 has ~2,300 blocks per tile; each tile gets one threadgroup per block; that's 2,300 threadgroups in flight per GPU dispatch. Apple M2's GPU has 10 cores × ~32 simultaneous threadgroups = ~320 in-flight threadgroups. So we'd queue 7+ deep per core — should keep occupancy high.

**Risk**: HIGH. This is the unproven part. The spike in I1.1 / I1.2 will measure whether a per-block-serial bit-write kernel produces the right bit-exact bytes AND completes faster than CPU emit.

### Pass 4 — 0xFF stuffing correction

**Background**: the JPEG 2000 conformant block format requires byte-stuffing — when emitted bytes contain `0xFF`, a stuff bit is inserted into the next byte's MSB to prevent confusion with marker bytes. The stuff byte breaks the block-level offset arithmetic computed in pass 2 (which assumed no stuffing).

**Two design options**:

**4a. CPU fix-up after readback (simpler)**: GPU writes raw bytes; CPU readback scans the output buffer once per block, inserts stuff bytes inline, returns final per-block bytes. Cost: O(total bytes) memcpy + scan = ~1.2 ms on DX (12 MB at ~10 GB/s). Adds CPU sync point but simple.

**4b. GPU correction pass (faster, riskier)**: a second GPU dispatch scans for `0xFF` runs in the per-block buffer and shifts subsequent bytes to insert stuff bytes. Needs careful per-block atomic offset arithmetic. Higher risk; saves ~1 ms on DX.

**Decision for I1.3**: implement 4a first (simpler, faster to ship). If the spike's wall-time A/B comes within 2-3 ms of beating Kakadu, switch to 4b for the extra savings.

**Risk**: Medium. The 0xFF stuffing rule is well-defined (ISO 15444-1 D.5); the implementation is straightforward but easy to off-by-one. Bit-exact regression tests catch errors.

---

## Empirical gates

Each phase ships with the standard mandatory commit gate plus phase-specific validation:

| Phase | Deliverable | Gate |
|---|---|---|
| **I1.0** (this PR) | Design doc + risk analysis | sign-off |
| **I1.1** | Pass 1 + Pass 2 (classify + prefix-sum) standalone Metal kernels + microbenchmarks | (a) per-block byte-count output bit-exact vs CPU; (b) prefix-sum output exact; (c) dispatch + execution time on DX 2x2 reasonable |
| **I1.2** | Pass 3 byte-write kernel + integration | per-block raw bytes (pre-stuffing) bit-exact vs CPU emitter's pre-stuffing intermediate state |
| **I1.3** | Pass 4 (CPU fix-up) + orchestrator wire-in | full corpus 6/6 byte-identical to CPU encoder; cross-codec parity 21/21; **decision gate: ≥ 15 % DX wall reduction → default-on, else opt-in** |

If I1.3's decision gate fails:
- **Pivot to approach D** (per-warp/threadgroup serial fallback) for v7.1.0 — same 3-pass structure but with different threadgroup organisation
- OR ship I1.3 opt-in (mirror of #305 pattern); v7.1.0 carries H + K1 headline only

---

## Apple M2 dispatch budget — what we have to beat

Per the v6-alpha6 #305 measurement on DX 2x2:
- CPU encode total: 71.6 ms
- CPU entropy stage: ~32 ms (~45 % of wall per #309)
- GPU dispatch overhead (no-op kernel from #301 dispatch probe): ~3.6 ms

For approach C to land a +35 % entropy reduction:
- Target: 32 ms × 0.65 = 20.8 ms total entropy on GPU path
- Budget for GPU passes (4 of them) + readback + 0xFF fix-up: 20.8 ms
- Subtract dispatch overhead (3.6 ms × 4 passes ≈ 14 ms if naive; can fuse): need to beat the rest in actual kernel work

**Tight but plausible.** The fundamental question pass-by-pass is whether GPU per-block-thread compute beats CPU single-thread compute when amortised over ~2,300 blocks. The GPU has 10 M2 cores × ~128 ALUs = 1280 ALUs vs CPU's 8 cores. ~160:1 raw parallelism advantage. Even at 5-10× per-thread compute disadvantage, the parallelism net should win — IF dispatch + memory + bit-stream serialisation don't dominate.

---

## Risk-mitigation strategy

The plan ([`docs/V7_1_0_PLAN.md`](V7_1_0_PLAN.md)) recommends shipping I1 as opt-in if the empirical gate fails. v6-alpha6 #305's pattern is the model:
- Approach B regressed; shipped opt-in with a high block-count threshold
- Cross-device retesting on M3/M4/M4 Pro/M4 Max may flip the dispatch latency curve
- Larger fixtures than corpus (whole-slide pathology) may amortise better

I1's PRs each ship behind the existing `_gpuForwardHTEntropyEnabled` static flag (from v6-alpha6 phase 1.2) which defaults `false`. Production behaviour unchanged unless the gate is flipped. The v7.1.0 release-candidate decides default-on vs default-off based on the I1.3 corpus A/B.

---

## What I1.0 ships

**This PR is design-doc only**. No production code change. The deliverable is:
- This document — architecture, risk analysis, phase-by-phase plan
- Confirmation that approaches A/B/C/D/E from v6-alpha6 are correctly enumerated
- The decision tree for "approach C lands win" vs "approach C regresses → pivot to D"

I1.1 onwards opens production code PRs. Each ships behind the existing opt-in flag with mandatory commit gate + bit-exact regression tests.

---

## Decision gate before I1.1 lands

Confirm one of:

- **"Go by your recommendation"** — start with **I1.1** (Pass 1 + Pass 2 standalone Metal kernels + microbenchmarks). Lowest-risk part of approach C; proves the classifier + prefix-sum primitives work before committing to the harder Pass 3 (byte-write).
- **Pivot to H2 first** — close decode-side polish (GPU 5/3 IDWT parity-aware) before tackling the high-risk encode-side gamble. v7.1.0 ships fully closed H + K + I trajectory with longer cycle.
- **Pivot to approach D** instead — skip C, go directly to per-warp/threadgroup serial. Lower upside (~25–35 % vs C's ~35–40 %) but same architectural risk profile.
- **Cap I-series, ship v7.1.0 with H1.1 + K1 only** — defer encode-side GPU work to v7.2.0; release v7.1.0 with the decode-side wins already in hand. Smaller release but ships sooner.

---

## v-series arc summary so far

| version | shipped | DX encode | DX decode |
|---|---|---:|---:|
| v6.0.0 | `.auto` multi-tile + opt-in GPU forward DWT | 1.3× | — |
| v6.1.0 | GPU forward DWT default-on for ≥4 MP | +21 % | — |
| v6.2.0 | GPU iDWT + GPU HT entropy default-on for ≥4 MP single-tile | — | +46 % |
| v6.3.0 | Multi-tile decode correctness + threshold 4 MP → 3 MP | +17 % | — |
| v7.0.0 | Multi-tile encode default-flip | +6 % (+50 % MR / +35 % XA / +30 % PX) | — |
| v7.1.0 H1.1 | Defect A fix (multi-tile decode entropy on GPU) | — | **+44–60 % (multi-tile DX)** |
| **v7.1.0 I-series (this design)** | **GPU forward HT entropy approach C (3-pass GPU pipeline)** | **target: ≥15 % DX wall reduction = +5–7 ms saved** | — |

If I-series lands the target, v7.1.0 closes the Kakadu DX encode gap from 2.8× → ~2.4× (still behind, but materially closer). The remaining DX gap is the architectural per-block-buffer elimination work (J / v7.2.0+ scope).
