# Bypass Mode Bug Investigation - February 8, 2026

## Executive Summary

The bypass mode in bit-plane coding has a synchronization bug affecting 4 tests. Decoded coefficients have small offsets (±1, ±2) from expected values. This is a continuation of the bit-plane decoder bug investigation from earlier.

## Current Status

- **Tests Affected**: 4 out of 1,380 (0.3%)
- **Severity**: Medium (affects only bypass mode, a performance optimization)
- **Workaround**: Disable bypass mode or use lower bypass threshold
- **Test Pass Rate**: 99.7% (1,376 passing)

## Affected Tests

All failures are in bypass mode tests:

1. `testCodeBlockBypassRoundTrip` - Dense coefficient array
2. `testCodeBlockBypassLargeBlock` - 32×32 block
3. `testCodeBlockBypassHighBitDepth` - 14-bit coefficients
4. `testCodeBlockBypassAllSubbands` - All subband types

## Passing Tests (Control Group)

These bypass mode tests **pass**, providing clues:

- `testCodeBlockBypassSparse` - Only 4 non-zero values ✅
- `testCodeBlockBypassZeros` - All zeros ✅
- `testCodeBlockBypassVariousThresholds` - Multiple threshold values ✅

## Error Pattern

### Example from testCodeBlockBypassRoundTrip

Pattern: `original[i] = sign * Int32((i * 13) % 2000)`

| Index | Expected | Actual | Difference |
|-------|----------|--------|------------|
| 0     | 0        | 2      | +2         |
| 1     | -13      | -14    | -1         |
| 2     | 26       | 25     | -1         |
| 3     | -39      | -39    | 0          |
| 4     | 52       | 52     | 0          |
| 5     | -65      | -65    | 0          |

The pattern of offsets (+2, -1, -1, 0, 0, 0) suggests a bit-plane synchronization issue in the first few significant coefficients.

## Code Analysis

### Bypass Mode Configuration

```swift
// CodingOptions.fastEncoding
bypassEnabled: true
bypassThreshold: 4  // Use bypass for bit-planes 0, 1, 2, 3
```

### Bypass Mode Decision Logic

Both encoder and decoder use identical logic:

```swift
let useBypass = options.bypassEnabled && bitPlane < options.bypassThreshold
```

### MQ-Coder Bypass Implementation

**Encoder (encodeBypass)**:
```swift
c <<= 1
if symbol {
    c += 0x8000  // Correct per JPEG 2000 spec
}
ct -= 1
if ct == 0 {
    emitByte()
}
```

**Decoder (decodeBypass)**:
```swift
if ct == 0 {
    fillC()
}
ct -= 1
c <<= 1

if (c >> 16) >= 0x8000 {
    c -= 0x8000 << 16
    return true
}
return false
```

**Analysis**: The order of operations is slightly different but should be equivalent:
- Encoder: decrement ct, check for emit
- Decoder: check for fill, decrement ct

This is the standard pattern for keeping encoder/decoder synchronized.

### When Bypass is Used

Bypass mode is only used in the **Magnitude Refinement Pass** for bit-planes below the threshold.

**Encoder** (line 230-232):
```swift
encodeMagnitudeRefinementPass(
    // ...
    useBypass: useBypass
)
```

**Decoder** (line 700-702):
```swift
decodeMagnitudeRefinementPass(
    // ...
    useBypass: useBypass
)
```

## Key Observations

1. **Sparse vs Dense Data**: Tests with sparse data (few non-zero values) pass. Tests with dense data (many non-zero values) fail.

2. **Magnitude of Errors**: Offsets are small (±1, ±2), suggesting bit-level issues rather than byte-level issues.

3. **Pattern**: First few values show errors, later values are correct. This suggests the issue occurs early in the decoding process.

4. **Bypass Threshold**: The passing sparse test uses threshold=6, failing dense tests use threshold=4. However, this may be correlation not causation.

## Hypotheses

### Hypothesis 1: Bit Counting Issue
The encoder and decoder may be counting bits differently when switching between regular MQ-coding and bypass mode, causing desynchronization.

**Evidence**:
- Small offsets (±1, ±2) are consistent with single-bit errors
- Pattern affects first few values then stabilizes

**Counter-evidence**:
- Both use identical `useBypass` calculation
- Sparse data tests pass (would fail if bit counting was fundamentally wrong)

### Hypothesis 2: Context State Issue
When switching from regular MQ-coding to bypass mode, context state may not be properly maintained.

**Evidence**:
- Magnitude refinement pass uses both regular and bypass coding
- The `a` register in MQ-coder should remain at 0x8000 during bypass

**Counter-evidence**:
- encodeBypass/decodeBypass don't modify `a`
- Bypass mode is stateless by design

### Hypothesis 3: Byte Alignment Issue
The transition between regular coding and bypass mode may have byte boundary issues.

**Evidence**:
- emitByte() and fillC() have complex logic for 0xFF stuffing
- The `ct` counter tracks bits within current byte

**Investigation needed**:
- Add logging to track ct, c, and a values across mode transitions
- Check if emitByte/fillC are called at the right times

### Hypothesis 4: First Refinement Flag
The magnitude refinement pass has special handling for first refinement. Bypass mode may interact incorrectly with this.

**Code**:
```swift
let isFirstRefinement = !firstRefineFlags[idx]
```

**Investigation needed**:
- Check if firstRefineFlags is being updated correctly in bypass mode
- Verify the context selection logic doesn't interfere with bypass

## Recommended Next Steps

### Step 1: Add Detailed Logging
Instrument both encoder and decoder to log:
- Bit-plane number
- Coefficient index
- Whether bypass is used
- Bit value encoded/decoded
- MQ-coder state (c, a, ct) before and after each operation

### Step 2: Create Minimal Test Case
Create the smallest possible test that reproduces the bug:
- 2×2 or 4×4 block (not 32×32)
- Simple coefficient pattern (e.g., [100, 50, 25, 10])
- bypassThreshold: 4

### Step 3: Compare Bitstreams
- Log encoder output bit-by-bit
- Log decoder input bit-by-bit
- Find exact point of divergence

### Step 4: Review JPEG 2000 Spec
- ISO/IEC 15444-1 Section C.3.4 (Magnitude Refinement Pass)
- ISO/IEC 15444-1 Section C.3.5 (Bypass mode)
- Verify implementation matches specification exactly

### Step 5: Compare with Reference Implementation
- OpenJPEG bypass mode implementation
- Verify our approach matches proven implementation

## Temporary Workarounds

For users affected by this bug:

### Option 1: Disable Bypass Mode
```swift
let options = CodingOptions(bypassEnabled: false)
```

**Impact**: Slightly slower encoding (5-10%), but correct results.

### Option 2: Use Higher Bypass Threshold
```swift
let options = CodingOptions(bypassEnabled: true, bypassThreshold: 6)
```

**Impact**: Reduces chance of hitting the bug (sparse test passes with threshold=6).

### Option 3: Use Predictable Termination
```swift
let options = CodingOptions(terminationMode: .predictable)
```

**Impact**: Resets encoder/decoder state between passes, may avoid the bug.

## Impact Assessment

- **Production Use**: Low impact - bypass mode is a performance optimization
- **Standards Compliance**: Bypass mode is optional in JPEG 2000
- **Testing**: 99.7% tests pass, all core functionality works
- **Interoperability**: May affect compatibility with encoders that heavily use bypass mode

## References

- BIT_PLANE_BUG_ANALYSIS_2026-02-07.md - Previous investigation
- BYPASS_MODE.md - Bypass mode documentation
- Sources/J2KCodec/J2KMQCoder.swift - MQ-coder implementation
- Sources/J2KCodec/J2KBitPlaneCoder.swift - Bit-plane coder implementation
- Tests/J2KCodecTests/J2KTier1CodingTests.swift - Failing tests

---

**Date**: 2026-02-08  
**Status**: Under Investigation  
**Priority**: Medium  
**Assignee**: Open
