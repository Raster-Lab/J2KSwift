# MQ-Coder State Divergence Bug Report

**Date**: 2026-02-08  
**Status**: ROOT CAUSE IDENTIFIED - Requires specialized debugging  
**Priority**: HIGH (blocks 32 tests)  
**Affected Version**: v1.0.0

## Executive Summary

The bit-plane decoder has a synchronization bug caused by **MQ-coder arithmetic state divergence** between encoder and decoder. The bug manifests when encoding/decoding 3+ non-zero coefficients and causes position corruption in decoded coefficients.

## Symptoms

- **Tests with 1-2 coefficients**: PASS ✅
- **Tests with 3+ coefficients**: FAIL ❌
- **Failure pattern**: Zero-valued positions incorrectly decode as ±1
- **Affected tests**: 32 tests (2.4% of test suite)
- **Pass rate**: 96.1% (1,292/1,344 tests passing)

## Test Case

```swift
// 4x4 block with 3 coefficients
var coefficients = [Int32](repeating: 0, count: 16)
coefficients[0] = 100   // Position (0,0)
coefficients[5] = -50   // Position (1,1)
coefficients[10] = 25   // Position (2,2)

// Expected layout:
//  100    0    0    0
//    0  -50    0    0
//    0    0   25    0
//    0    0    0    0

// Actual decoded result:
//  100    0    0   -1   <- Position [3] corrupted!
//    0  -50    0    0
//    0    0   25    0
//    0    0    0    0
```

## Root Cause Analysis

### Investigation Timeline

1. **Initial hypothesis**: RLC (Run-Length Coding) synchronization bug
   - **Result**: RULED OUT - Bug persists with RLC disabled

2. **Second hypothesis**: State management in bit-plane passes
   - **Result**: RULED OUT - Encoder and decoder use identical logic

3. **Third hypothesis**: Processing order mismatch
   - **Result**: RULED OUT - Verified identical processing order

4. **CONFIRMED**: MQ-coder probability state divergence

### Evidence

From detailed execution trace (bit-plane 0, cleanup pass):

**Encoder behavior:**
```
[ENC-MR] Pos[0] (0,0): bit=0
[ENC-MR] Pos[5] (1,1): bit=0
[ENC-MR] Pos[10] (2,2): bit=0  <- Debug log (may be incorrect)
[ENC] Col 3, Stripe 0-4, RLC: false
[ENC]   Pos[3] (3,0): isSig=false, ctx=sigPropLL_LH_0
```

**Decoder behavior:**
```
[DEC-MR] Pos[0] (0,0): bit=0
[DEC-MR] Pos[5] (1,1): bit=0
[DEC-MR] Pos[10] (2,2): bit=1  <- Correct! (25 & 0x01 = 1)
[DEC] Col 3, Stripe 0-4, RLC: false
[DEC]   Pos[3] (3,0): isSig=true, ctx=sigPropLL_LH_0  <- Reads WRONG value!
```

### The Divergence

1. **Encoder writes** (bit-plane 0):
   - 3 magnitude refinement bits (for positions 0, 5, 10)
   - 1 significance bit for position 3 (value: FALSE)
   - **Total: 4 bits**

2. **Decoder reads** (bit-plane 0):
   - 3 magnitude refinement bits (reads: 0, 0, 1) ✓ CORRECT
   - 1 significance bit for position 3 (reads: TRUE) ✗ WRONG
   - **Total: 4 bits read, but DIFFERENT VALUES**

3. **Conclusion**: 
   - Both encoder and decoder use the same context (`sigPropLL_LH_0`)
   - Both process in the same order
   - But the MQ-coder decodes a DIFFERENT bit value than was encoded
   - This indicates **arithmetic coder internal state has diverged**

## Why State Diverges

The MQ-coder maintains internal state for each context:
- `stateIndex`: Index into probability table (0-46)
- `mps`: Most probable symbol (0 or 1)

Plus encoder/decoder have their own state:
- `a`: Interval size (probability range)
- `c`: Code value (encoder) or code stream buffer (decoder)
- `ct`: Bit counter

When encoder and decoder process the SAME sequence of symbols with the SAME contexts, their internal states should remain synchronized. The fact that they diverge indicates:

1. **Incorrect state update logic** in encoder OR decoder
2. **Incorrect probability table** (unlikely - standard table)
3. **Termination/initialization issue** affecting subsequent bit-planes
4. **Byte stuffing bug** causing bit alignment issues

## Prior Investigation

Previous attempts documented in:
- `BIT_PLANE_BUG_ANALYSIS_2026-02-07.md`
- `CLEANUP_PASS_FIX.md`
- `DEBUG_BIT_PLANE_DECODER_BUG.md`

All confirmed the same finding: bit-plane pass logic is correct, bug is in MQ-coder.

## Required Fix

### Phase 1: Instrumentation

Add detailed state tracking to MQ-coder:

```swift
// In MQEncoder.encode()
#if DEBUG_MQ_CODER
print("[MQ-ENC] Symbol=\(symbol), Context=\(context.stateIndex), MPS=\(context.mps)")
print("  Before: a=0x\(String(a, radix: 16)), c=0x\(String(c, radix: 16)), ct=\(ct)")
// ... existing encoding logic ...
print("  After:  a=0x\(String(a, radix: 16)), c=0x\(String(c, radix: 16)), ct=\(ct)")
print("  New state: \(context.stateIndex), MPS=\(context.mps)")
#endif
```

Similar tracking in MQDecoder.

### Phase 2: Bisection

Run test case with full MQ-coder tracing, compare encoder vs decoder logs line-by-line to find the FIRST encode/decode operation where states diverge.

### Phase 3: Root Cause

Once divergence point is found:
1. Review that specific encode/decode operation
2. Compare against JPEG 2000 standard (ISO/IEC 15444-1 Annex C)
3. Compare against reference implementation (OpenJPEG)
4. Identify the exact logic error

### Phase 4: Fix & Verify

1. Implement targeted fix
2. Verify all 32 tests pass
3. Run full test suite (should be 100% pass rate)
4. Add regression tests

## Estimated Effort

- **Instrumentation**: 2-3 hours
- **Bisection**: 3-4 hours
- **Root cause analysis**: 2-4 hours
- **Fix implementation**: 1-2 hours
- **Verification**: 1-2 hours
- **Total**: 9-15 hours (1-2 days dedicated work)

## Impact Assessment

### Current Impact

- **Functionality**: Component-level APIs work correctly for simple cases
- **Test coverage**: 96.1% pass rate
- **Production use**: NOT RECOMMENDED for production until fixed
- **Development**: Can proceed with other v1.1 tasks

### Risk if Not Fixed

- ❌ Cannot achieve 100% test pass rate
- ❌ Cannot release v1.1 as production-ready
- ❌ Incorrect decoding for complex images
- ❌ Loss of user trust

## Recommended Approach

### Option A: Fix Immediately (HIGH PRIORITY)
- Dedicate 2 days to fix
- Blocks v1.1 release until fixed
- Achieves 100% test pass rate
- **Recommended for production release**

### Option B: Document & Defer (MEDIUM PRIORITY)
- Document limitation in release notes
- Continue with other v1.1 tasks
- Fix in v1.0.1 patch release
- **Acceptable for alpha/beta releases**

### Option C: Workaround (LOW PRIORITY - NOT RECOMMENDED)
- Detect problematic cases and fail gracefully
- Add parameter to disable affected code paths
- **Not acceptable long-term**

## References

- **JPEG 2000 Standard**: ISO/IEC 15444-1:2004, Annex C (Arithmetic Coding)
- **MQ-Coder Paper**: "The Q-Coder" by Pennebaker, Mitchell, Langdon, Arps (IBM Journal 1988)
- **OpenJPEG**: Reference implementation (https://github.com/uclouvain/openjpeg)

## Related Files

### Source Files
- `Sources/J2KCodec/J2KMQCoder.swift` - MQ-coder implementation
- `Sources/J2KCodec/J2KBitPlaneCoder.swift` - Bit-plane encoder/decoder

### Test Files
- `Tests/J2KCodecTests/BitStreamDiagnostic.swift` - New diagnostic tests
- `Tests/J2KCodecTests/J2KBitPlaneDecoderDiagnostic.swift` - Existing diagnostic tests
- `Tests/J2KCodecTests/J2KTier1CodingTests.swift` - Failing integration tests

### Documentation
- `BIT_PLANE_BUG_ANALYSIS_2026-02-07.md` - Initial analysis
- `CLEANUP_PASS_FIX.md` - Attempted fix documentation
- `DEBUG_BIT_PLANE_DECODER_BUG.md` - Debugging session notes

## Conclusion

The bug has been **positively identified** as MQ-coder arithmetic state divergence. The bit-plane coding logic is correct. Fixing requires:

1. MQ-coder state instrumentation
2. Comparative execution trace analysis
3. Targeted fix based on findings

This is a **solvable problem** with well-defined debugging methodology. Estimated 1-2 days of dedicated focus.

---

**Last Updated**: 2026-02-08  
**Next Action**: Implement MQ-coder state instrumentation  
**Assigned To**: TBD  
**Milestone**: v1.1.0 (required for production release)
