# v6-alpha6 — GPU forward HT entropy plan (Phase 0)

**Status**: Design doc only. No code yet. Open question on the
preferred approach (see §4) is the gate to Phase 1.

**Branch**: `feature/gpu-forward-ht-entropy-phase-0`

**Anchor memory**: `feedback_lossless_only_v5_38.md` — v5.38+ scope is
lossless-only; this work targets the encode-side hot stage of the
HT-conformant lossless path.

---

## 1. Why this is the next target

After v6.0.0 shipped GPU forward 5/3 INT DWT (`.auto` multi-tile
production-default + opt-in `J2K_GPU_FORWARD_53=1`), the wall-time
breakdown of a DX 2800×2288 lossless encode looks like:

| stage | DX wall % (v6.0.0 single-tile, CPU) | accelerated by v6.0.0? |
|---|---:|:---:|
| Preprocess (`extractComponentData`) | 3 % | no (already cheap, M7 fixed) |
| Forward DWT (5/3 INT) | 8 % | **yes** (GPU forward, opt-in) |
| **Forward HT entropy** | **45 %** | **no — this proposal** |
| Rate control (PCRD) | 7 % | indirectly (v5.30 fix) |
| Codestream assembly | 7 % | yes (v5.38 M3 writeBytes) |
| Tier-2 packet header | 9 % | no |
| Other (allocator, scheduler) | 21 % | partially |

**Forward HT entropy is the single largest unaccelerated stage.** The
decoder-side analogue (HT MagSgn reader + cleanup-pass kernel) is
already on GPU at [`J2KMetalHTMagSgn.swift`](../Sources/J2KMetal/J2KMetalHTMagSgn.swift)
and [`J2KMetalHTCleanup.swift`](../Sources/J2KMetal/J2KMetalHTCleanup.swift)
(GPU HT decoder prototype, pre-v5.38). The encode-side has no GPU
equivalent.

If we move the entropy stage to GPU at the same setup cost as the
forward DWT (≈ 0 ms warm via `J2KMetalSession.processShared`), the
ceiling speedup is roughly:

  - Best case (entropy 100 % moved): DX 76 ms → 42 ms (1.81×)
  - Realistic (entropy 60 % moved, PCRD/preprocess unchanged): DX 76 ms → 56 ms (1.36×)

That'd close most of the structural Kakadu gap on DX (current 2.78×
on encode → 1.5× on encode), worth attempting.

---

## 2. Encode-side hot-path map

Three streams are produced per codeblock by [`HTBlockEncoderConformant.encode`](../Sources/J2KCodec/J2KHTConformantBlockEncoder.swift):

| stream | source | parallelism profile |
|---|---|---|
| **MagSgn** (forward bit emitter) | [`HTMagSgnEncoderConformant.encode(codeword:count:)`](../Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift#L53) | **fundamentally serial per-codeblock** — see §3 |
| **MEL** (run-length, M5 cleanup orchestrator) | per-quad `rho`/`eQMax` decision | per-quad serial; MEL state carries forward |
| **VLC** (reverse bit emitter, M3 stream) | per-quad VLC codewords | reverse-direction emission; serial per-codeblock |

All three are produced from the same per-quad walk:

```
for each 2×2 quad in the codeblock:
    classify 4 samples → (sig_mask, eQ, payloads)         [SIMD-clean]
    update rho/eQMax accumulators                          [SIMD-clean]
    emit MEL bits for run-length                           [serial]
    emit VLC bits for context-coded quad info              [serial]
    emit MagSgn bits for each significant sample's payload [serial]
```

The classification step (`sampleInfo`) is already SIMD-vectorised on
CPU as of v5.39 M1 (`useSIMDClassification: true` toggle, lane-
identical to scalar reference, gated off-by-default until v5.39 ships
proven).

---

## 3. The serial constraint (Why this is hard)

The MagSgn forward emitter has two sequential dependencies that
block per-sample GPU parallelism:

### 3.1 Variable-length per-sample emission

Each significant sample contributes a variable number of bits to
the MagSgn stream (from 0 if not significant, up to ~30 for
high-magnitude samples at full precision). The byte position of
sample N depends on how many bits samples 0..N-1 have emitted —
which can't be known without doing the work.

A prefix-sum over per-sample bit counts gets you the byte starts
**but not the bit positions inside those bytes** unless you also
prefix-sum the cumulative bits. Doable, but it's two parallel
passes plus a third masking pass.

### 3.2 The 0xFF stuff-bit rule

When the MagSgn encoder emits a `0xFF` byte, the **next byte
reserves its high bit as a 0 stuff bit** — meaning that byte holds
only 7 user bits instead of 8. The encoder tracks this via
`maxBits` toggling between 8 and 7.

This makes the emitter's output non-prefix-summable: you can't
compute the byte position of sample N without knowing whether any
of samples 0..N-1 produced a `0xFF`, because that shifts the bit
budget for every sample after.

Three workarounds, all imperfect:

  - **Speculative + correction**: assume no `0xFF` happens, emit
    speculatively in parallel; do a serial correction pass that
    detects `0xFF` and shifts the suffix. Suffix shift is
    serial-per-block; might still beat fully-serial CPU on large
    blocks.
  - **Per-sample upper-bound padding**: pad each sample to its
    worst-case byte boundary; never emit `0xFF`-ambiguous bytes.
    Output isn't bit-exact — fails our cross-codec invariant
    immediately.
  - **Per-codeblock thread, full serial within thread**: each GPU
    thread encodes one full codeblock serially; parallelism is
    across blocks. Limited by per-thread compute (GPU threads are
    slower than CPU per single-stream serial work). For DX with
    ~2300 codeblocks, this might be break-even.

### 3.3 Symmetry with decoder kernel

Decoder side is parallelizable per sample because the byte stream
is already known — you're indexing INTO a fixed buffer. Encoder
side has to BUILD the buffer, which is where the dependency lives.

This is why the v6-alpha5 GPU forward DWT path was easier than this
will be: the DWT is a pure math transform with no encoding of
variable-length data.

---

## 4. Candidate approaches (Phase 1 picks one)

| approach | per-sample parallel? | bit-exact? | risk | est. wall % saved on DX |
|---|:---:|:---:|---|---:|
| **A. Per-codeblock thread, fully serial within thread** | ❌ (parallel ACROSS blocks) | ✓ | Low; mirrors decoder dispatch probe pattern | ~10–15 % (GPU per-thread compute slower than CPU) |
| **B. Two-pass: classify on GPU, emit on CPU** | ✓ classify; ❌ emit | ✓ | Moderate; introduces a synchronization point | ~25–30 % (only the classification is moved) |
| **C. Three-pass: classify GPU → bit-budget prefix-sum GPU → byte-write GPU with per-block correction** | ✓ classify + prefix; ❌ correction | ✓ if correction is faithful | High; the correction-pass logic for `0xFF` byte stuffing is non-trivial and easy to get wrong | ~35–40 % if correction is fast |
| **D. Per-warp/threadgroup serial (SIMD-group serial within block)** | ✓ within block (32-wide groups) | ✓ | Moderate; needs careful threadgroup bit-state | ~25–35 % |
| **E. CPU-SIMD only (skip GPU)** — make the v5.39 M1 SIMD classification production default + add NEON on per-quad emission | ✓ classify; partial emit | ✓ | Low; well-trodden CPU pattern | ~10–20 % |

**My current lean: B first** as a Phase 1 spike. It minimises GPU complexity (only the per-sample classification + payload computation moves, the byte emission stays CPU), proves out the upload/dispatch/readback latency budget against a known-good CPU emitter, and gives a clean number for "is GPU even worth it for this stage." If B's number is good (≥ 15 % wall reduction on DX), promote to C; if not, fall back to E.

A is a useful **Phase 0.5 dispatch probe** — a no-op kernel that takes per-codeblock descriptors and dispatches one thread per block. Mirrors [`J2KMetalHTDispatchProbe`](../Sources/J2KMetal/J2KMetalHTDispatchProbe.swift) on the encode side. Establishes the upload + scheduling cost floor.

---

## 5. Phase trajectory (planned)

| phase | deliverable | gate |
|---|---|---|
| **0 (this doc)** | Plan + design constraint analysis | docs only |
| **0.5** | Encode-side dispatch probe — kernel `j2k_ht_forward_dispatch_probe` + Swift wrapper + timing harness | dispatch latency baseline measured on DX (2300 blocks) |
| **1** | **Approach B spike**: GPU sample classifier + payload extractor over coefficients; CPU consumes the per-quad tuple stream and emits MagSgn/MEL/VLC bytes | A/B test on DX; CPU↔hybrid wall-time comparison; bytes byte-identical |
| **2** | If approach B wins: production wire-in mirroring v6-alpha5 phase 2 (telemetry + threshold gate). If approach B loses: pivot to C or E. | env var `J2K_GPU_FORWARD_HT_ENTROPY=1` opt-in |
| **3** | Multi-tile correctness: per-tile dispatch must remain bit-exact across multi-tile parity matrix (mirror v6-alpha3 step 6A/6B work) | parity matrix 36/36 |
| **4** | Cross-codec validation through OpenJPH/Grok/Kakadu (mirror Phase 8) | 21/21 cells |
| **5** | Threshold-boundary sweep (mirror Phase 9) | empirical threshold for production opt-in |
| **6** | Decision point: ship as opt-in (like v6.0.0 GPU forward DWT) or default-on if win is consistent across fixtures + devices | `RELEASE_NOTES_v6.X.Y.md` |

---

## 6. Pre-commit gate (every phase)

Mandatory per `feedback_commit_gate.md`:

```bash
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

Plus phase-specific:

  - Phase 0.5: dispatch latency probe must run without crash
  - Phase 1+: bit-exact output vs CPU encoder on every codeblock in the medical corpus
  - Phase 3+: 36/36 multi-tile parity cells bit-exact
  - Phase 4+: 21/21 cross-codec cells bit-exact

---

## 7. Open questions

1. **Per-codeblock thread vs per-warp threadgroup** — does Apple GPU's threadgroup-shared bit state outperform 2300 independent-thread serial encodes? Phase 0.5 dispatch probe is too coarse to answer; needs Phase 1 spike.
2. **Float vs Int classification on GPU** — the CPU classifier uses `UInt32`; GPU can use `int4` SIMD or floats. Performance vs precision trade-off TBD.
3. **Two-stage upload — coefficients to GPU, payload tuples back to CPU**: is the round-trip latency acceptable on UMA? Phase 0.5 dispatch probe will measure.
4. **Multi-tile interaction** — does per-tile entropy parallelism on CPU (`withThrowingTaskGroup`) compose with per-block GPU parallelism, or do they fight for the SoC scheduler? Test in Phase 3.
5. **Threshold model** — v6.0.0 forward DWT uses a pixel-count threshold. Forward entropy might want a codeblock-count threshold instead (the work is per-block, not per-pixel). TBD by Phase 5 sweep.

---

## 8. Non-goals for this work

- Lossy entropy (`useReversibleFilter: false`) is parked per `feedback_lossless_only_v5_38.md`. Do not extend this work to lossy until that scope is re-opened.
- HT non-conformant block format (`htj2kBlockFormat: .nonConformant`) is not in scope. Conformant only.
- Decoder-side acceleration is already in flight (the GPU HT decoder prototype). This work is encode-side only.
- Forward EBCOT (Part-1, non-HT) is not in scope. EBCOT lossless was deprioritized at v5.38 M4 in favour of HT.

---

## 9. Why a doc-only Phase 0

The GPU forward DWT trajectory had a code Phase 0 (bit-exact kernels) because the math was straightforward. The forward HT entropy doesn't have a "drop in a kernel" Phase 0 — the design constraint analysis in §3 has to land first, and the candidate-approach trade-offs in §4 have to be acknowledged before code starts. Otherwise we'd write a kernel that fails the byte-stuffing rule and waste the implementation pass.

A doc-only Phase 0 is the right shape for this work. Phase 0.5 is the smallest code milestone — a dispatch probe — and only after this doc is reviewed and the open questions in §7 have at least an empirical-validation plan attached.
