# V9.1 Phase 1A — SIMD16 batched classifier: NEGATIVE RESULT

**Date**: 2026-05-11
**Branch**: `v9.1-pathB`
**Status**: ❌ Phase 1A microbench REJECTS the SIMD16 architecture as a path to closing the Kakadu gap. Phase 1 must pivot OR be reconsidered.

## TL;DR

The Phase 0 plan picked **Candidate A — batched per-quad SIMD pipeline (SIMD16)** as the highest-confidence Phase 1 target. The Phase 1A microbench was supposed to validate the speedup hypothesis (≥1.5× per-quad classification speedup).

**Result**: SIMD16 is **6× SLOWER** than scalar for the per-quad classifier. SIMD4 is only 1.22× faster.

| Variant            | ns/quad | speedup vs scalar |
|--------------------|--------:|------------------:|
| Scalar (1 quad)    |    4.45 |             1.00× |
| SIMD4  (1 quad)    |    3.66 |             1.22× |
| **SIMD16 (4 quads)** | **28.53** | **0.16× (slower)** |

**Phase 1A architecture rejected.** The naive "go wider" approach fails because Swift's `SIMD<UInt32>` does not expose SIMD-wide primitives for the operations the HT classifier needs:

1. **`leadingZeroBitCount`** is per-lane scalar (Swift doesn't surface NEON's `vclz` over `SIMD16<UInt32>` as a single op).
2. **Lane comparison** returns `SIMDMask` with limited operations; we have to extract scalarly to build the rho/sig flags.
3. **Per-lane gather/scatter** for the `safeVal = sig ? val : 1` substitution requires 16 scalar conditional moves.

Net effect: a "SIMD16" loop body does ~16 scalar operations per iteration plus the SIMD vector setup. That's strictly more work than 4× scalar `processQuad` calls.

## What the Phase 1A bench measured

`Tests/J2KCodecTests/V91Phase1ABatchedClassifyMicrobench.swift`:
- Generates 256K samples of synthetic UInt32 data (defeats L1 cache).
- Runs three variants of the per-quad classifier: scalar / SIMD4 / SIMD16.
- 50K iterations × 5 runs, median-of-5 wall ns/call.
- Correctness gate: `testSIMD16BitExactVsScalarOnRandomCorpus` sweeps 10K random sample-quartets at p=24 (16-bit medical lossless), confirming SIMD16 produces bit-exact identical output to scalar. **The SIMD16 LOGIC is correct; the architecture is just slow.**

## Why the corpus probe's "96% loop body" finding still stands

Phase 0's corpus probe showed:
- 770 ms accumulated entropy CPU on DX
- ~31 ms in bit-emission engine calls (4%)
- ~736 ms in "loop body residual" (96%)

But the Phase 1A bench shows the per-quad classifier alone is only **4.45 ns**, NOT 1112 ns. The per-quad cost in the actual encoder (1112 ns) is **278× higher** than the isolated classifier cost (4 ns).

Where does the 1100+ ns/quad disparity go? Decomposing what we know:

| Component | Microbench ns | × calls per quad | Cost per quad |
|-----------|--------------:|-----------------:|--------------:|
| processQuad classifier | 4.45 | 1 | 4 ns |
| vlcEnc.encode (engine) | 6-15 | ~3.2 (tuple+UVLC) | 30 ns |
| melEnc.encode (engine) | 3-5 | ~0.05 | 0 ns |
| magsgnEnc.encode (engine) | 9-11 | ~3 | 30 ns |
| **Sum of measured pieces** |   |   | **~64 ns/quad** |
| **Corpus measured** |   |   | **~1112 ns/quad** |
| **Unaccounted** |   |   | **~1048 ns (94%)** |

**The unaccounted 1048 ns/quad is the real Path B target.** It must be Swift function-call boundary overhead in the encoder context: inout struct write-back through the engine `mutating func encode`, ARC retain/release on the engine's internal `bytes: [UInt8]` arrays (HTMagSgnEncoderConformant has dynamic byte storage), array bounds checks on `bytes.append(...)`, possibly TLS / closure-capture overhead from the nested function structure.

## What Path B actually has to attack

Not classification. Not engine bit-emission internals. The function-call boundary cost in the per-quad inner loop.

**Realistic Phase 1 candidates (revised):**

### Candidate B′ — fuse the inner loop (eliminate engine struct boundary)

Inline the engine bit-emit logic directly into `HTBlockEncoderConformant.encode`'s row-quad loop, eliminating the `vlcEnc.encode(...)`, `melEnc.encode(...)`, `magsgnEnc.encode(...)` call overhead. The engines maintain bit-stream state (`tmp`, `usedBits`, `bytes` array) that needs to be hoisted out as locals in the encoder's stack frame.

Structure:
```swift
public static func encode(...) {
    var magsgn_tmp: UInt32 = 0
    var magsgn_usedBits: Int = 0
    var magsgn_maxBits: Int = 8
    var magsgn_bytes: [UInt8] = []
    // ... mel + vlc state similarly hoisted

    @inline(__always) func magsgnEmit(codeword: UInt32, count: Int) {
        // Inline the entire encode loop with direct local writes,
        // no inout struct, no method dispatch.
    }
    // ... similar for mel + vlc

    // Row-quad loop now calls inline functions instead of engine methods.
}
```

**Expected speedup**: if function-call boundary is ~80% of per-quad cost (1048/1112 ≈ 94%), eliminating it is a 4-5× speedup on the per-quad loop. Closing 50%+ of the Kakadu gap.

**Risk**: huge code duplication (the engine logic now lives in two places — engine struct + inlined version). Maintenance burden grows. Bit-exactness gates must be very thorough.

**Effort**: 2-3 weeks for prototype, 4-6 weeks for parity gates + integration.

### Candidate C′ — port the encoder to C/C++ for the hot path

Write the HT block encoder in C/C++ (compiled with -O3 + NEON intrinsics) and bridge from Swift. Bypasses Swift's struct/inout/ARC overhead entirely.

**Expected speedup**: 3-5× per-quad wall reduction, comparable to Kakadu's hand-tuned C++ inner loops.

**Risk**: cross-language bridging adds complexity; loss of Swift safety; introduces a new tier of maintenance. Cross-codec parity validation must remain bit-exact.

**Effort**: 6-12 weeks for full C port + parity gates.

### Candidate D — accept that pure-Swift HT entropy can't match Kakadu on M2

Swift's struct-with-inout pattern incurs ~50-100 ns overhead per call vs C++'s direct function call (~5-10 ns). At ~3 calls per quad × 660K quads on DX, that's 100-200 ms of accumulated CPU just from language-level call overhead.

If this is the structural floor, no amount of Swift-internal optimisation can match Kakadu — you'd have to drop down to C/C++ at the hot path. This points back to Candidate C′ or to Path A (accept the gap).

## Recommendation

**Pause the Phase 1 implementation.** The Phase 1A microbench overturned the Phase 0 plan. The user said "Path B — 6-12 month algorithmic rewrite of DWT or HT entropy" trusting the Phase 0 finding that pointed to algorithmic redesign. The data now says:

- Algorithmic redesign of classification: tried, doesn't help (SIMD16 slower, SIMD4 only 1.22× and already shipped)
- Algorithmic redesign of engines: would only save 4% of entropy CPU
- The remaining 94% is **language-level overhead**, not algorithm choice

**The honest call is**: matching Kakadu on M2 likely requires dropping the hot path to C/C++ (Candidate C′). That's not the "algorithmic rewrite" the user was anticipating — it's a different category of work (cross-language bridge, loss of pure-Swift purity).

This warrants a user check-in:

1. **Greenlight Candidate C′ (C/C++ HT encoder hot path)** — 6-12 weeks, ports the bottom 100 ns/sample of the encoder to C++ with NEON intrinsics. Plausible 3-5× speedup. Accepts the cross-language hybrid architecture.
2. **Greenlight Candidate B′ (in-Swift inline fusion)** — 4-6 weeks, eliminates engine struct boundary by inlining bit-stream state. Lower-risk than C++ but might only get 1.5-2× speedup (still well short of Kakadu).
3. **Pivot to Path A** (accept the encode gap, lead on decode) — the v8.1.4 marketable claim already wins 4/6 fixtures vs Kakadu CLI on warm decode. No engineering effort needed.
4. **Pivot to Path C** (M3+/M4 silicon probe) — defer Path B until we measure if M3+ silicon shifts the language-overhead curve. Cross-silicon probe infrastructure already shipped on `v9.0-research`.

## What stays in tree on `v9.1-pathB`

- `Sources/J2KCodec/J2KHTEntropyEncoderProfile.swift` — encoder profile counters
- `Tests/J2KCodecTests/V91Phase0EncoderProfileTests.swift` — corpus breakdown probe
- `Tests/J2KCodecTests/V91Phase0EncoderMicrobench.swift` — per-engine ns/call
- `Tests/J2KCodecTests/V91Phase1ABatchedClassifyMicrobench.swift` — SIMD16 negative result
- `V9_1_PATH_B_PHASE_0.md` — initial Phase 0 finding
- `V9_1_PHASE_1A_NEGATIVE_RESULT.md` — this document (revised plan)

The instrumentation is non-breaking; codestream remains byte-identical to pre-instrumentation. We can keep these in tree for future Path B revisits even if we pivot to Path A.

## What I would NOT do without the user's check-in

- Begin a 6-12 week C/C++ port (Candidate C′) without explicit greenlight. Cross-language hybrid is a major architecture decision affecting the project's character ("fastest open-source pure-Swift JPEG 2000 codec on Apple Silicon" → "fastest open-source pure-Swift+C++ JPEG 2000 codec on Apple Silicon").
- Begin a 4-6 week inline-fusion (Candidate B′) without checking if user wants to invest given the lower expected speedup (1.5-2× vs the 3-5× Kakadu gap).
- Attempt the DWT alternative without first analysing whether DWT cost is similarly dominated by Swift overhead.

The right move is to surface this finding and let the user redirect the workstream.
