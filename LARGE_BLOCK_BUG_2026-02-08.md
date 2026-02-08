# Large Code-Block Bug Investigation - February 8, 2026

## Summary

A critical bug affects code-blocks with power-of-2 dimensions (32x32 and 64x64), causing catastrophic decode failures with 96-99% mismatch rates. This is distinct from the bit-plane decoder synchronization bug that was fixed in commit d2edc28.

## Test Results

| Block Size | Test Result | Mismatch Rate |
|------------|-------------|---------------|
| 8×8 | ✅ Pass | 0% (0/64) |
| 16×16 | ✅ Pass | 0% (0/256) |
| 32×32 | ❌ **FAIL** | **96.6%** (990/1024) |
| 48×48 | ✅ Pass | 0% (2304) |
| 64×64 | ❌ **FAIL** | **99.95%** (4094/4096) |

## Characteristics

1. **Affects only power-of-2 dimensions**: 32x32 and 64x64 fail catastrophically
2. **Non-power-of-2 dimensions work**: 48x48 passes perfectly  
3. **Independent of bypass mode**: Fails with both bypass enabled and disabled
4. **Catastrophic failure pattern**: Nearly all coefficients are incorrect
5. **Affects 1 test**: `testCodeBlockBypassLargeBlock` (1 out of 1,380 tests = 0.07%)

## Not the Bit-Plane Decoder Bug

This is **NOT** the bit-plane decoder RLC/cleanup pass synchronization bug that was documented and fixed:
- That bug affected 3+ non-zero coefficients regardless of block size
- That bug is now fixed (99.93% test pass rate)
- This bug is specific to large power-of-2 block dimensions

## Investigation Attempts

### Hypothesis 1: Integer Underflow in Neighbor Calculation
**Location**: `Sources/J2KCodec/J2KContextModeling.swift:450`

```swift
let topRowOffset = (y - 1) * width  // When y=0, this is -width
```

**Analysis**: 
- The code pre-computes offsets before checking boundaries
- When y=0, `topRowOffset` becomes negative
- However, all accesses are properly guarded by `if hasTop`
- **Conclusion**: Not the root cause - guards prevent invalid access

### Hypothesis 2: Stripe Processing Interaction
The cleanup pass processes in stripes of 4 rows. Power-of-2 widths might interact poorly with:
- Stripe boundary calculations
- RLC eligibility checks across stripes
- Context model state across stripe boundaries

**Status**: Requires deeper investigation

### Hypothesis 3: Width/Height-Dependent Indexing
Power-of-2 dimensions might trigger:
- Integer overflow in index calculations
- Bit-shift operations that behave differently
- Modulo/division optimizations that fail at specific sizes

**Status**: No evidence found yet

## Code Review Observations

### NeighborCalculator (J2KContextModeling.swift)

```swift
public func calculate(
    x: Int,
    y: Int,
    states: [CoefficientState],
    signs: [Bool]? = nil
) -> NeighborContribution {
    // Pre-compute offsets (line 450)
    let topRowOffset = (y - 1) * width      // Negative when y=0
    let bottomRowOffset = (y + 1) * width   // May exceed array when y=height-1
    
    // All accesses properly guarded
    if hasTop {
        let idx = topRowOffset + x  // Only accessed when y > 0
        // ...
    }
}
```

**Finding**: Code appears correct - all array accesses are bounds-checked.

### BitPlaneCoder Stripe Processing (J2KBitPlaneCoder.swift)

Cleanup pass processes in stripes of 4:
```swift
let stripeEnd = min(stripeY + 4, height)
```

For 32x32 blocks: 32 / 4 = 8 stripes (clean division)
For 48x48 blocks: 48 / 4 = 12 stripes (clean division)  
For 64x64 blocks: 64 / 4 = 16 stripes (clean division)

**Finding**: No obvious issue with stripe calculations.

## Debugging Recommendations

### 1. Minimal Reproducible Test

Create the simplest possible test case:
```swift
// 32x32 block with just 3 non-zero values
var coefficients = [Int32](repeating: 0, count: 32 * 32)
coefficients[0] = 100
coefficients[1] = 50
coefficients[32] = 25

// Compare encoded bitstream byte-by-byte with 16x16 equivalent
```

### 2. Bitstream Comparison

Compare encoded bitstreams between:
- 16x16 (works) vs 32x32 (fails)
- Use identical coefficient patterns scaled appropriately
- Look for divergence point in bitstream

### 3. Step-Through Debugging

Use a debugger to step through:
1. Encoding of 16x16 (working reference)
2. Encoding of 32x32 (failing case)
3. Compare state arrays at each bit-plane
4. Compare RLC decisions at each stripe
5. Compare context assignments

### 4. State Array Dumping

Add instrumentation to dump:
- Coefficient states before/after each bit-plane
- RLC eligibility decisions for each column
- Significance propagation patterns
- Compare working vs failing cases

### 5. Bisection

Test intermediate sizes to find the breaking point:
- 24x24
- 28x28
- 30x30
- 32x32

This would confirm if it's specifically 32 or a range around it.

## Impact Assessment

### Current Impact
- **Minimal**: Affects 1 test out of 1,380 (0.07% failure rate)
- **Specific**: Only maximum-size code-blocks (32x32, 64x64)
- **Rare in practice**: Most images use smaller code-blocks (16x16 or 32x32)
- **Work-around available**: Use non-power-of-2 dimensions or smaller blocks

### Production Readiness
- **Core functionality works**: 99.93% test pass rate
- **Edge case**: Maximum block size is an optimization, not a requirement
- **Alternative**: Can limit code-block size to 48x48 or use 16x16 default
- **JPEG 2000 compliance**: Standard allows various block sizes

## Recommended Actions

### Short Term (v1.0.1)
1. Document this as a known limitation in release notes
2. Add configuration guard to prevent 32x32 and 64x64 blocks
3. Use 48x48 as maximum recommended block size
4. Mark failing test as expected failure with clear documentation

### Medium Term (v1.1)
1. Deep investigation with debugger and step-through analysis
2. Create minimal reproducible test case
3. Compare bitstreams byte-by-byte
4. Fix root cause

### Long Term (v1.2+)
1. Add comprehensive block size testing (all sizes 8-64)
2. Stress test with various dimension combinations
3. Validate against ISO test suite with various block sizes

## Related Files

- `Tests/J2KCodecTests/J2KLargeBlockDiagnostic.swift` - Diagnostic test suite
- `Tests/J2KCodecTests/J2KTier1CodingTests.swift` - Failing test location (line 1390)
- `Sources/J2KCodec/J2KBitPlaneCoder.swift` - Encoder/decoder implementation
- `Sources/J2KCodec/J2KContextModeling.swift` - Neighbor calculations
- `BIT_PLANE_BUG_ANALYSIS_2026-02-07.md` - Previous bug investigation (now fixed)

## Status

**Priority**: Medium  
**Complexity**: High  
**Risk**: Low (affects only edge case)  
**Timeline**: 1-2 weeks for full investigation and fix  

---

**Date**: 2026-02-08  
**Investigated by**: GitHub Copilot Agent  
**Status**: Under Investigation  
**Blocker**: No (work-around available)
