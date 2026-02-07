# Bit-Plane Decoder Bug Analysis - February 7, 2026

## Problem Summary

The bit-plane decoder has a synchronization bug where the decoder reads more bits than the encoder wrote, causing coefficient corruption. The bug manifests when encoding/decoding 3 or more non-zero coefficients.

**Failing Test Pattern:**
- 1 value: ✅ Pass
- 2 values: ✅ Pass  
- 3 values: ❌ Fail (position 3 corrupted)
- 4 values: ❌ Fail (position 3 corrupted)

**Expected vs Actual:**
```
Expected: [100, 0, 0, 0, 0, -50, 0, 0, 0, 0, 25, 0, 0, 0, 0, -10]
Actual:   [100, 0, 0, 1, 0, -50, 0, 0, 0, 0, 25, 0, 0, 0, 0, -10]
                      ^--- Position 3 corrupted
```

## Code Analysis Performed

### 1. RLC Eligibility Functions
**Encoder:** `isEligibleForRunLengthCoding` (line 536)  
**Decoder:** `canUseRunLengthDecoding` (line 943)

**Finding:** These functions are functionally identical (line-by-line match except for function name and a comment).

### 2. Cleanup Pass Logic
**Encoder:** `encodeCleanupPass` (line 443)  
**Decoder:** `decodeCleanupPass` (line 857)

**Finding:** The flow control is identical:
- Check RLC eligibility
- If eligible, encode/decode RLC flag
- If RLC flag is false, mark all coefficients as coded and skip
- Otherwise, process individually

### 3. State Management
- `.codedThisPass` flags are cleared between bit-planes (lines 267, 712)
- `.significant` flags persist across bit-planes
- State updates happen in the same order in both encoder and decoder

### 4. Neighbor Calculations
- `NeighborCalculator.calculate()` has two overloads (with/without signs)
- RLC eligibility checks use the version WITHOUT signs
- Individual coefficient processing uses the version WITH signs
- This is consistent between encoder and decoder

### 5. Signs Parameter Hypothesis
**Test:** Added `signs` parameter to RLC eligibility checks
**Result:** No change in behavior (as theoretically expected, since `neighbors.hasAny` doesn't depend on signs)

## Theoretical Analysis

### When Encoder/Decoder Could Diverge

The encoder writes fewer bits than the decoder reads, suggesting one of these scenarios:

1. **RLC Decision Mismatch:** Encoder uses RLC when decoder doesn't (or vice versa)
   - **Assessment:** RLC eligibility functions are identical, so given identical states, they should make the same decision
   
2. **State Synchronization:** The `states` array differs between encoder and decoder
   - **Assessment:** State updates are identical, and processing order is deterministic
   
3. **Hidden Bug:** A subtle logic error not visible in static analysis
   - **Assessment:** Most likely, but not found despite extensive review

### Key Observations

1. Bug appears specifically at position 3 (row 0, column 3)
2. Position 3 has no direct relationship to the significant coefficients (positions 0, 5, 10)
3. Position 3's neighbors (2, 7, 6) are all non-significant
4. The corruption value varies (sometimes 1, sometimes -1)

### Bit-Plane Processing Trace (Theoretical)

For 3 values at positions 0, 5, 10:
- Position 0: value 100 (highest bit: 6)
- Position 5: value -50 (highest bit: 5)  
- Position 10: value 25 (highest bit: 4)

**Bit-plane 6:** Only position 0 becomes significant
**Bit-plane 5:** Position 5 becomes significant
**Bit-plane 4:** Position 10 becomes significant

By bit-plane 4, positions 0 and 5 are already significant. When processing column 3:
- Position 3's neighbors should all be non-significant
- Column 3 should be eligible for RLC
- RLC flag should be false (no coefficients become significant)
- All coefficients in column 3 should be marked as coded and skipped

**Question:** Why is the decoder reading a significance bit for position 3 when the encoder never wrote one?

## Attempted Fixes

### Fix 1: Add Signs Parameter to RLC Checks
**Rationale:** Ensure encoder and decoder use identical neighbor information  
**Result:** No change (as expected - signs don't affect `neighbors.hasAny`)

## Recommendations for Resolution

### Approach 1: Runtime Debugging (Recommended)
Add detailed logging to trace execution:

```swift
// In cleanup pass, before RLC check
print("Column \(x), Stripe \(stripeY)-\(stripeEnd)")
print("  States: \(states)")
print("  RLC eligible: \(isEligible)")
```

Compare encoder and decoder logs side-by-side to find the exact point of divergence.

### Approach 2: Reference Implementation
Compare against a known-correct JPEG 2000 implementation (e.g., OpenJPEG) to verify:
- RLC eligibility criteria
- State management
- Bit-plane processing order

### Approach 3: Simplified Test Case
Create a minimal test case with detailed assertions at each step:
```swift
// Encode with logging
let (data, ...) = encoder.encode(coefficients)
// Verify bitstream length
// Decode with logging
let decoded = decoder.decode(data, ...)
// Compare states at each bit-plane
```

### Approach 4: Code Review
Have another developer review the cleanup pass implementation with fresh eyes. Sometimes a subtle bug is only visible to someone who hasn't been staring at the code for hours.

## Files Involved

- `Sources/J2KCodec/J2KBitPlaneCoder.swift` - Main encoder/decoder implementation
- `Sources/J2KCodec/J2KContextModeling.swift` - Neighbor calculations
- `Tests/J2KCodecTests/J2KTier1CodingTests.swift` - Failing tests
- `Tests/J2KCodecTests/J2KBitPlaneDecoderDiagnostic.swift` - Diagnostic tests

## Impact

**Test Results:**
- Total tests: ~1307
- Passing: ~1278 (97.8%)
- Failing: 29 (all related to this bug)

**Affected Tests:**
- J2KBitPlaneCoderTests (8 tests)
- J2KBypassModeTests (6 tests)
- Various Tier-1 coding tests (15 tests)

## Next Steps

1. Add runtime debug logging to encoder and decoder
2. Run diagnostic tests and compare logs
3. Identify exact point of divergence
4. Implement targeted fix
5. Validate with all 29 failing tests
6. Ensure no regressions in passing tests

## Status

**Date:** 2026-02-07  
**Analyst:** GitHub Copilot Agent  
**Status:** Root cause not yet identified - requires runtime debugging  
**Priority:** High (blocks 100% test pass rate goal)

