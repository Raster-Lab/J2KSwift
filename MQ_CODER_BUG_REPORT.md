# MQ-Coder Synchronization Bug Report

## Summary
Critical bug in MQ-coder causing encoder/decoder desynchronization in specific scenarios with scattered significant coefficients in cleanup pass.

## Symptoms
- Test `testThreeValuesOriginalFailingCase` with values `[(0, 100), (5, -50), (10, 25)]` fails
- Decoder reads position 3 as significant (-1) when it should be 0
- Occurs at final bit-plane (0), final position (3)
- Encoder writes MPS (false), decoder reads LPS (true)

## Root Cause Analysis

### Synchronization Point
- Encoder and decoder process identical positions in identical order
- All RLC decisions match perfectly
- Context states match until the final decode operation
- At state 31/32, encoder writes MPS, decoder reads LPS

### MQ-Coder State
Final problematic operation at bit-plane 0, position 3:
- **Encoder**: state=31, mps=false, encodes false (MPS) → stays at 31 (no renormalization)
- **Decoder**: state=31, mps=false, decodes true (LPS) → goes to 29

From state 31: `MQState(qe: 0x09C1, nextMPS: 32, nextLPS: 29, switchMPS: false)`

The decoder's C-register value `(c >> 16) >= a`, indicating LPS region, when encoder encoded MPS.

### Pattern Analysis
Tests that PASS:
- 1-2 scattered coefficients
- 3+ coefficients in same column (processed via significance propagation)
- Random/fuzz tests
- All coefficients in vertical line

Tests that FAIL:
- 3+ coefficients scattered across columns
- Coefficients processed in cleanup pass (not sig prop)

## Suspected Issues

1. **Bitstream Synchronization**: Encoder writes fewer/more bits than decoder expects
2. **Renormalization Bug**: Subtle issue in MQ encoder/decoder renormalization logic
3. **Byte Stuffing**: Problem with 0xFF stuffing affecting C-register
4. **Conditional Exchange**: Error in conditional exchange logic for specific state transitions

## Investigation Notes

### MQ Encoder Logic (Line 194-203)
```swift
if symbol == context.mps {
    // MPS path
    if a < 0x8000 {
        if a < qe {
            c += a
            a = qe
        }
        context.stateIndex = state.nextMPS  // State update only if renormalizing
        renormalize()
    }
    // If a >= 0x8000: state NOT updated (no renormalization needed)
}
```

This is correct per JPEG 2000 standard - state only updates when renormalization occurs.

### MQ Decoder Logic (Line 483-500)
```swift
if (c >> 16) < a {
    // MPS region
    if a < 0x8000 {
        if a < qe {
            symbol = !mps  // Conditional exchange
            context.stateIndex = state.nextLPS
        } else {
            symbol = mps
            context.stateIndex = state.nextMPS
        }
        renormalizeDecoder()
    } else {
        symbol = mps  // No state update
    }
}
```

The decoder enters LPS region (line 501+) when `(c >> 16) >= a`, meaning C-register is misaligned with encoder's output.

## Debugging Steps Taken

1. ✅ Verified position processing order matches
2. ✅ Verified RLC decisions match
3. ✅ Verified context state transitions match (until failure point)
4. ✅ Verified no positions are skipped
5. ✅ Verified MQ state table correctness
6. ✅ Ruled out state update timing issues in cleanup pass
7. ✅ Ruled out RLC as cause
8. ✅ Ruled out test setup issues

## Next Steps

1. **Add MQ-Coder Tracing**: Instrument encoder/decoder to log C, A registers at each operation
2. **Bisect Bitstream**: Identify exact bit where synchronization diverges
3. **Reference Implementation**: Compare against OpenJPEG or Kakadu MQ-coder
4. **State Machine Audit**: Verify all 47 state transitions against ISO/IEC 15444-1 Annex C
5. **Renormalization Review**: Check renormalization loops for off-by-one errors
6. **Byte Stuffing**: Verify 0xFF stuffing logic matches standard

## Workaround
None currently. Bug affects real-world scenarios with scattered coefficients.

## Test Coverage
- 23 of 73 BitPlane tests fail
- All failures involve 3+ scattered coefficients
- Fuzz/random tests pass (different code paths?)

## Files Involved
- `Sources/J2KCodec/J2KMQCoder.swift` (MQ encoder/decoder)
- `Sources/J2KCodec/J2KBitPlaneCoder.swift` (cleanup pass)
- `Tests/J2KCodecTests/J2KBitPlaneDecoderFixTests.swift` (test cases)

## Priority
**CRITICAL** - Affects correctness of JPEG 2000 encoding/decoding for common coefficient patterns.
