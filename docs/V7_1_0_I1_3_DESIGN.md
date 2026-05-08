# v7.1.0 I1.3 — unified Pass 3 cleanup-pass kernel: design + scope correction

**Status**: Design doc only. No code in this PR. Sign-off on the architecture before the unified kernel lands.

**Anchors**:
- [`docs/V7_1_0_I1_0_DESIGN.md`](V7_1_0_I1_0_DESIGN.md) — original I-series design (Pass 1/2/3/4 split)
- [`Sources/J2KMetal/J2KMetalHTMagSgnEmit.swift`](../Sources/J2KMetal/J2KMetalHTMagSgnEmit.swift) — I1.2/I1.2b MagSgn primitive
- [`Sources/J2KMetal/J2KMetalHTMELEmit.swift`](../Sources/J2KMetal/J2KMetalHTMELEmit.swift) — I1.2c MEL primitive
- [`Sources/J2KMetal/J2KMetalHTVLCEmit.swift`](../Sources/J2KMetal/J2KMetalHTVLCEmit.swift) — I1.2d VLC primitive
- [`Sources/J2KCodec/J2KHTConformantBlockEncoder.swift`](../Sources/J2KCodec/J2KHTConformantBlockEncoder.swift) — CPU reference, 628 lines

---

## TL;DR — scope correction

The I1.0 design split GPU cleanup-pass into:

- Pass 1 (classify) — per-sample tuples + per-block byte budgets
- Pass 2 (prefix-sum) — byte budgets → offsets
- Pass 3 (byte-write) — emit bytes from tuples + offsets

**That split doesn't work**: per-block byte budgets cannot be derived from per-sample classification alone. They depend on the per-quad cleanup-pass state machine — MEL run-length, VLC Huffman, U-value derivation, MagSgn-bit-width-per-quad logic. **Producing budgets requires running emit-equivalent logic.**

Therefore I1.3 is a **single unified per-block kernel** that:

1. Reads the per-sample tuple stream (already produced by the v6-alpha6 `J2KMetalHTForwardClassifier`)
2. Walks quads, runs the cleanup-pass state machine
3. Inline-emits MagSgn / MEL / VLC bytes via the bit-packing logic proven in I1.2 / I1.2b / I1.2c / I1.2d
4. Outputs 3 per-block byte streams + their actual byte counts

The I1.1 prefix-sum kernel still applies — to the *post-emit* byte counts, for layout-time concatenation across blocks. The I1.2 / I1.2b / I1.2c / I1.2d standalone bit-packing kernels remain valuable as bit-exact reference implementations and as standalone microbenchmark sentinels, but **they are not called from the unified kernel** (MSL forbids kernel-from-kernel calls; we inline the equivalent logic).

---

## Why the original Pass 1/Pass 3 split looked plausible

The CPU encoder structure suggests a clean separation:

```swift
// Per-sample classification (tuple stream)
let tuples = classify(samples)        // Pass 1 candidate

// Per-block emit (consumes tuples)
let bytes = emit(tuples)              // Pass 3 candidate
```

But `emit` does much more than bit packing. Reading `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` lines 162-628:

- `processQuadFromTuples(baseX:baseY:)` — quad-level (rho, eQMax, eQ0..3, s0..3) reduction (~30 lines)
- Outer loop walking quads in row-then-column order (~40 lines)
- Per-row scratch state: `eVal[guardedWidth]`, `cxVal[guardedWidth]` for context propagation
- MEL run-length state machine (~50 lines, lines ~452-522)
- VLC encoding via Huffman table (~50 lines, lines ~564-616)
- MagSgn per-quad bit emission with U-value derivation (~30 lines, lines ~401-415)
- Byte-stuffing applied INLINE during all three emit calls (already validated in I1.2/c/d)

The byte budgets are a *consequence* of running this machinery — not pre-computable from per-sample tuples. Approach B (#305) hit the same wall in a different shape: it ran classify on GPU but kept emit on CPU; the byte counts only became known after CPU emit, by which time the GPU classify cost had already been paid for nothing.

---

## What the unified Pass 3 kernel looks like

```metal
kernel void j2k_ht_cleanup_pass_emit_block(
    device const ulong*   tuples              [[buffer(0)]],   // sig:1|eQ:7|payload:32 per sample
    device const uint*    blockOffsets        [[buffer(1)]],   // start of each block in tuples[]
    device const uint4*   blockDims           [[buffer(2)]],   // (width, height, missingMSBs, _) per block
    device       uchar*   magsgnOut           [[buffer(3)]],
    device       uchar*   melOut              [[buffer(4)]],
    device       uchar*   vlcOut              [[buffer(5)]],
    device const uint*    magsgnOffsets       [[buffer(6)]],   // 4-byte-aligned, per-block
    device const uint*    melOffsets          [[buffer(7)]],
    device const uint*    vlcOffsets          [[buffer(8)]],
    device       uint*    magsgnByteCounts    [[buffer(9)]],
    device       uint*    melByteCounts       [[buffer(10)]],
    device       uint*    vlcByteCounts       [[buffer(11)]],
    constant     uint&    blockCount          [[buffer(12)]],
    uint tid                                  [[thread_position_in_threadgroup]],
    uint tgIdx                                [[threadgroup_position_in_grid]]
) {
    if (tgIdx >= blockCount) return;
    if (tid != 0u) return;        // per-block-serial — same pattern as I1.2b/c/d

    // 1. Read block dims
    // 2. Run row/column quad walk over the per-block tuple slice
    // 3. Per-quad: derive (rho, eQMax, eQ0..3, s0..3) from tuples
    // 4. Per-quad: emit MEL bits, VLC codeword, MagSgn bits — inline
    //              bit-packing (logic proven in I1.2/c/d)
    // 5. Write 3 byte counts to the count buffers
}
```

Two-pass alternative (split classify-byte-counts from byte-write):

```
Pass A: tuples → per-block byte counts (no byte writes — emit logic
        runs to completion but only updates a counter, no device stores)
Pass B: prefix-sum byte counts → aligned offsets
Pass C: tuples → bytes (re-runs the emit logic, this time writing bytes
        at the offsets from Pass B)
```

This lets us know exact byte budgets before allocating output buffers, but **runs the cleanup-pass state machine twice** — paying ~2× the per-block-serial cost. Initial estimate says single-kernel-with-upper-bound-allocation is faster.

---

## Output buffer sizing — the open design question

The unified kernel needs to write bytes to the output buffer *while* it's running the state machine. We don't know the final byte count until the state machine finishes. Two options:

**Option A** — *Upper-bound allocation per block*. Allocate `outputCapacity = blockCount × maxBytesPerBlock` for each stream, where `maxBytesPerBlock` is a worst-case upper bound (every sample produces N bytes, FF-stuff doubles, etc.). Each block writes at offset `blockIdx × maxBytesPerBlock`. After emit, a CPU compaction pass reads the actual byte counts and concatenates blocks tightly.

  - Pros: single GPU pass.
  - Cons: large output buffer (potentially ~3× actual size); CPU compaction adds memcpy bandwidth.

**Option B** — *Two GPU passes (count-then-write)*. Pass A counts bytes only. Pass B runs the prefix-sum kernel from I1.1 (×3 streams). Pass C writes bytes at the prefix-summed offsets.

  - Pros: minimal output buffer (matches actual byte sum).
  - Cons: cleanup-pass state machine runs twice. ~2× per-block-serial cost on GPU.

**Recommendation**: Option A. The CPU compaction is a sequential memcpy at ~10 GB/s; a 12 MB DX block consumes <2 ms. Running the state machine twice in Option B would cost more (~25-50 ms on GPU per redundant pass, based on I1.2b/c/d microbenchmarks). For initial spike + bit-exactness gate, Option A is simpler and faster.

The maxBytesPerBlock formula: a 32×32 block has 1024 samples; each sample contributes ≤ ~6 bits to each stream worst-case; so ≤ 1024 bytes per stream. With FF-stuff overhead (8/7), round up to ~1200 bytes. Per-block upper bound × 3 streams × 2,300 blocks per tile = ~8 MB per tile — tractable.

---

## Empirical gates

| PR | scope | gate |
|---|---|---|
| **I1.3a** (this PR) | Design doc + scope correction | sign-off |
| **I1.3b** | Single-block unified kernel + bit-exact tests | per-block 3-stream output byte-identical to `HTBlockEncoderConformant.encode(preClassifiedTuples:)` for ≥ 5 hand-picked codeblock fixtures + 3 randomised seeds |
| **I1.3c** | Batched (multi-block) dispatch + microbenchmark + corpus parity | per-block byte-identical across full DX/PX/MR/XA fixtures via the existing `_gpuForwardHTEntropyEnabled` flag |
| **I1.3d** | Production wire-in + corpus A/B vs CPU | **decision gate: ≥ 15 % DX wall reduction → default-on**, else opt-in (mirror of #305 pattern) |

The decision gate at I1.3d is the moment of truth: either approach C wins the wall reduction the I1.0 design predicted, or it joins approach B / E in the "tried, didn't pay" pile.

---

## Risk

**HIGH**. The cleanup-pass state machine is non-trivial to port — ~300-400 lines of MSL with careful attention to:

- Per-row context state (`eVal[]`, `cxVal[]`) — threadgroup-private array sized by block width
- MEL run-length state — counter + threshold table (small const buffer)
- VLC Huffman table — 256-entry lookup table (constant memory)
- Sample iteration order — column-major within quad, row-major across quads
- Edge cases: blocks smaller than 4×4, missingMSBs forces p > 30, all-zero blocks, all-significant blocks

The I1.2/I1.2b/c/d primitives proved out the bit-packing layer is bit-exact; that's the floor. The remaining risk is in the state-machine port. Mitigations:

1. Test against `HTBlockEncoderConformant.encode(preClassifiedTuples:)` for hand-picked + randomised codeblocks (the same path approach B used)
2. Single-block first, expand to batched after correctness is proven
3. Spike with a tiny block (8×8) to validate the row/column walk + state propagation before scaling up

---

## What I1.3 ships incrementally

- **I1.3a (this PR)** — design doc + scope correction. Acknowledges the Pass 1/Pass 3 split was wrong. Sets I1.3b's bit-exact gate.
- **I1.3b** — single-block unified kernel; bit-exact vs CPU per-block emit
- **I1.3c** — batched dispatch (one threadgroup per block); corpus parity
- **I1.3d** — production wire-in + corpus wall-time A/B; ≥ 15 % DX gate

Each ships behind the existing `_gpuForwardHTEntropyEnabled` opt-in flag from v6-alpha6 phase 1.2; production behaviour stays identical until I1.3d's gate decision flips it default-on or keeps it opt-in.

---

## Alternative: pivot to H2 / H3 / K1

If the scope of the unified kernel feels too risky given the encode-side wall budget remaining for v7.1.0, the alternative is to defer I1.3 to v7.2 and ship v7.1.0 with H + K headlines only:

- **H2** — GPU 5/3 IDWT parity-aware boundary lifting (Defect B fix). Modest decode-side gain, well-scoped.
- **H3** — re-enable `isMultiTilePerTile: false` in `decodeTilePayloadGPU` once H2 lands. Compiler-trivial flip.
- **K1** — multi-tile per-tile warm-session hardening. Few hours of work.

The encode-side I-series work then becomes v7.2's headline, with the I1.2/I1.2b/c/d primitives already in place as foundation. Trade-off: v7.1.0 ships a smaller win; v7.2 ships approach C.

**Recommendation**: proceed with I1.3b. The bit-packing primitives are bit-exact and ready; the cleanup-pass port is the natural next step, and the user's "beat Kakadu" framing pushes for the encode-side win that approach C is the only path to.
