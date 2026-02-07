# Bit-Plane Decoder Bug Analysis

## Problem Description
Test `testBitPlaneDecoderRoundTrip4x4` fails with:
- Expected: `[100, 0, 0, 0, 0, -50, 0, 0, 0, 0, 25, 0, 0, 0, 0, -10]`
- Actual:   `[100, 0, 0, 1, 0, -50, 0, 0, 0, 0, 25, 0, 0, 0, 0, -10]`

Index 3 incorrectly decodes to 1 instead of 0.

## Root Cause Analysis

### Key Findings
1. **Bitstream Misalignment**: The decoder reads an extra "true" significance bit for index 3 at bitMask=1, while the encoder wrote "false"

2. **Coefficient Counts**:
   - Encoder: Processes 23 coefficients in cleanup pass, 1 found significant
   - Decoder: Processes 23 coefficients in cleanup pass, 2 found significant
   - The extra significant coefficient is index [3] at bitMask=1

3. **RLC Functions Verified**: Both `isEligibleForRunLengthCoding` (encoder) and `canUseRunLengthDecoding` (decoder) have identical logic

4. **anyBecomeSignificant Verified**: Returns correct values for all RLC skip points

### Where Divergence Occurs
The divergence happens between:
- Encoder: Successfully encodes significance bit for index 3 at bitMask=1 as "false"
- Decoder: Decodes significance bit for index 3 at bitMask=1 as "true"

This indicates the decoder is reading from the wrong position in the bitstream.

## Hypothesis
The encoder and decoder are processing a DIFFERENT NUMBER OF BITS before reaching index 3 at bitMask=1. This could happen if:

1. The encoder skips processing a coefficient that the decoder attempts to process
2. The RLC eligibility check returns different values in some edge case
3. The states arrays diverge due to different update ordering

The most likely culprit is the RLC skip logic:
- When `hasSignificant` is false, the encoder marks all coefficients in the column as `.codedThisPass` and continues to the next column
- The decoder does the same
- But the timing or ordering might cause the decoder to skip different coefficients during individual processing

## Investigation Process

### Verified Identical:
- RLC eligibility check logic
- anyBecomeSignificant calculation
- Individual coefficient processing structure
- Skip condition: `states[idx].contains(.codedThisPass) || states[idx].contains(.significant)`
- State updates for significance and sign bits

### Evidence of Bitstream Misalignment:
- Encoder encodes fewer "significant" bits than decoder reads
- This causes subsequent bit reads to shift by 1 position
- Result: Decoder reads garbage bits starting from index 3 at bitMask=1

## Recommendations for Fix

1. **Add binary-level logging**: Track exact bit positions encoded/decoded at each step
2. **Verify state sync**: Confirm encoder and decoder states are identical before RLC eligibility check
3. **Review RLC skip timing**: Ensure `.codedThisPass` is set/cleared at exactly the same times
4. **Test with intermediate bitplanes**: Run tests stopping at bitMask=2 to see if issue exists earlier
5. **Compare with reference implementation**: Check against JPEG2000 standard or known working implementation

## Code Locations
All functions are located in `Sources/J2KCodec/J2KBitPlaneCoder.swift`:
- `BitPlaneCoder.encodeCleanupPass()` - Main encoding cleanup pass for each bit-plane
- `BitPlaneDecoder.decodeCleanupPass()` - Main decoding cleanup pass for each bit-plane  
- `BitPlaneCoder.isEligibleForRunLengthCoding()` - Encoder's RLC eligibility check
- `BitPlaneDecoder.canUseRunLengthDecoding()` - Decoder's RLC eligibility check (must match encoder)
- `BitPlaneCoder.anyBecomeSignificant()` - Checks if any coefficient becomes significant in current bit-plane

The two RLC eligibility functions are critical to fix since they must return identical results for proper encoder/decoder synchronization.
