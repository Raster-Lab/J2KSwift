# Bit-Plane Decoder Synchronization Bug - Investigation Report

## Summary

Critical synchronization bug in EBCOT bit-plane encoder/decoder causing test failures for 3+ coefficient cases.

## Bug Manifestation

- **Tests with 1-2 coefficients**: PASS ✅
- **Tests with 3+ coefficients**: FAIL ❌  
- **Affected tests**: 18+ bit-plane related tests failing
- **Total impact**: 33 failing tests out of 1347

## Specific Failure Case

Test: Three coefficients at positions 0, 5, 10 with values 100, -50, 25 in a 4x4 grid.

**Expected:**
```
100    0    0    0
  0  -50    0    0
  0    0   25    0
  0    0    0    0
```

**Actual:**
```
100    0    0   -1    ← Position [3] corrupted!
  0  -50    0    0
  0    0   25    0
  0    0    0    0
```

## Root Cause Analysis

### Observation 1: Processing Order is Identical

Both encoder and decoder process coefficients in the exact same order:
- Bit-planes: 6 → 0 (MSB to LSB)
- Within each bit-plane: Sig Prop → Mag Ref → Cleanup
- Within each pass: Row-by-row, column-by-column

### Observation 2: Contexts are Identical

At the point of failure (Pos[3], bit-plane 0, cleanup pass):
- **Encoder**: Uses context `sigPropLL_LH_0` (0 neighbors)
- **Decoder**: Uses context `sigPropLL_LH_0` (0 neighbors)

Contexts match perfectly.

### Observation 3: State Updates are Synchronized

Both encoder and decoder:
- Mark coefficients as `significant` when they become significant
- Mark coefficients as `codedThisPass` during each pass
- Clear `codedThisPass` flag after each bit-plane
- Update states in the same order

### Observation 4: Same Number of Bits

At bit-plane 0, both encoder and decoder process:
- Sig Prop: Pos[2], Pos[6], Pos[14] (3 significance bits, all false)
- Mag Ref: Pos[0], Pos[5], Pos[10] (3 magnitude bits)
- Cleanup: Pos[3] and others

Total bits match.

### Observation 5: RLC is Not the Culprit

Disabling Run-Length Coding entirely did NOT fix the issue. The bug persists even when all columns are processed individually.

## Critical Divergence Point

At bit-plane 0, cleanup pass, Pos[3]:
- **Encoder encodes**: Significance bit = FALSE (coefficient is 0)
- **Decoder decodes**: Significance bit = TRUE (reads "1" from bitstream)

This is followed by:
- **Decoder also decodes**: Sign bit = TRUE (negative)
- **Result**: Pos[3] = -1 instead of 0

## Hypothesis

The arithmetic coder (MQ-coder) state has diverged between encoder and decoder at this point. This causes:
1. Different probability distributions for the same context
2. Different encoded/decoded bit values despite using the same context label

## Possible Causes

### 1. State Update Timing Bug
When a coefficient becomes significant during sig prop, it updates its state immediately. Subsequent coefficients in the same pass see it as a significant neighbor. This is correct behavior per JPEG 2000 standard, but there might be a subtle bug in the implementation.

### 2. Neighbor Calculation Bug  
The neighbor calculator might produce different results between encoder and decoder in edge cases, leading to different context selections and state divergence.

### 3. MQ-Coder State Management Bug
The arithmetic coder itself might have a state management bug that only manifests in specific encoding patterns (e.g., certain sequences of contexts or bit values).

### 4. Context Initialization Bug
Context states might not be initialized identically between encoder and decoder, causing divergence over time.

### 5. Sign Encoding/Decoding Bug
The sign bit encoding uses XOR prediction based on neighbor signs. A bug in this logic could cause extra bits to be encoded/decoded.

## Investigation Attempts

1. ✅ Added comprehensive debug logging for sig prop, mag ref, and cleanup passes
2. ✅ Verified processing order is identical
3. ✅ Verified contexts are identical  
4. ✅ Verified state updates happen in same order
5. ✅ Disabled RLC to test if it's the culprit (it's not)
6. ❌ Could not pinpoint exact arithmetic coder state divergence point

## Next Steps

### Immediate Actions Required

1. **Add MQ-Coder Instrumentation**: Add detailed logging to MQEncoder and MQDecoder to track:
   - Context state (qe value, mps bit) before/after each encode/decode
   - A register and C register values
   - Byte output/input

2. **Bisect the Divergence**: Use the instrumentation to identify the exact encode/decode operation where states diverge.

3. **Compare with Reference Implementation**: Test against a known-good JPEG 2000 implementation (e.g., OpenJPEG) to verify our encoding is standard-compliant.

4. **Unit Test MQ-Coder**: Create isolated unit tests for the MQ-coder with known input/output pairs.

### Long-term Improvements

1. **Add State Validation**: Implement checksum or hash validation of encoder/decoder states at each pass boundary.

2. **Refactor State Management**: Consider making state updates more explicit and atomic to prevent subtle bugs.

3. **Add Conformance Tests**: Implement test vectors from JPEG 2000 Part 4 (Conformance Testing) to validate implementation.

## Files Modified

- `Sources/J2KCodec/J2KBitPlaneCoder.swift`: Enhanced debug logging for columns 2 and 3
- `Tests/J2KCodecTests/BitStreamDiagnostic.swift`: New comprehensive diagnostic tests

## Related Documents

- `BIT_PLANE_BUG_ANALYSIS_2026-02-07.md`: Previous analysis
- `DEBUG_BIT_PLANE_DECODER_BUG.md`: Initial bug report
- `CLEANUP_PASS_FIX.md`: Attempted fixes

## References

- ISO/IEC 15444-1: JPEG 2000 Image Coding System - Part 1: Core coding system
- Section 12: Entropy coding (EBCOT algorithm)
- Annex D: Arithmetic decoding procedure

---

**Status**: Bug identified but root cause not yet pinpointed. Requires MQ-coder level debugging.
**Priority**: CRITICAL - Blocking 18+ tests
**Assigned**: Requires expert review of arithmetic coder implementation
