# Known Limitations in J2KSwift

This document outlines known limitations and edge cases in the current implementation of J2KSwift.

## MQ Coder - 64x64 Dense Data Issue

### Description

The MQ (arithmetic) coder has a known issue when encoding/decoding code blocks that meet ALL of the following criteria:
- Block size is exactly 64×64 (4,096 coefficients)
- Data contains dense, high-magnitude values with significant variation
- Pattern has many non-zero coefficients with varied bit-planes

### Symptoms

- Approximately 63% of decoded coefficients are incorrect
- Sign errors are common (e.g., Expected: -839, Got: 839)
- Various magnitude errors throughout the block
- Issue appears as cumulative state divergence between encoder and decoder

### Working Configurations

✅ **Works correctly:**
- 8×8, 16×16, 32×32 blocks with same dense pattern (1,024 coefficients or fewer)
- 64×64 blocks with simple patterns (sequential, constant values, sparse data)
- Any block size with sparse or low-variation data

❌ **Fails:**
- 64×64 blocks with dense, high-magnitude, varied coefficient data

### Investigation Summary

**Tested hypotheses:**
1. ❌ MPS state update missing when `a >= 0x8000` - Made issue worse
2. ❌ Carry propagation overflow in BYTEOUT - No change
3. ❌ Buffer size limits - No hardcoded limits found at 4096
4. ❌ Context state overflow - State table properly bounded (0-46)

**Root cause:**
The issue appears to be cumulative precision loss or state machine divergence in the MQ coder when processing 4,096+ symbols with complex probability distributions. The exact mechanism requires deeper investigation of the ISO/IEC 15444-1 Annex C arithmetic coding procedures.

### Workaround

Configure encoding to use code blocks ≤ 32×32 for images with dense, high-variation data:

```swift
var config = J2KEncodingConfiguration.balanced
config.codeBlockSize = (width: 32, height: 32)

let encoder = J2KEncoder(configuration: config)
let encoded = try encoder.encode(image)
```

### Impact

**Low impact in practice:**
- JPEG 2000 Part 1 allows code blocks up to 4,096 total coefficients (width × height)
- Most implementations default to 32×32 (1,024 coefficients) or 64×32 (2,048 coefficients)
- 64×64 is the maximum allowed size and rarely used in production
- Dense, high-variation patterns at maximum block size is worst-case scenario
- Real-world images typically have more structured/predictable data

**Affected use cases:**
- Synthetic test data with intentionally difficult patterns
- Medical imaging with high-frequency noise at maximum code block sizes
- Custom encoders explicitly configured for 64×64 blocks

### Status

- **Priority:** Low (affects only edge case scenarios)
- **Tracked in:** Tests marked with `XCTSkip` in J2KBitPlaneDiagnosticTest.swift
- **Planned fix:** v1.2.0 or later (requires detailed standard analysis)
- **Alternative:** HTJ2K codec (Part 15) planned for v2.0 has different entropy coding

### References

- Test case: `J2KBitPlaneDiagnosticTest.testMinimalBlock64x64()`
- Test case: `J2KLargeBlockDiagnostic.test64x64WithoutBypass()`
- JPEG 2000 Standard: ISO/IEC 15444-1:2019, Annex C (MQ-coder)
- Related code: `Sources/J2KCodec/J2KMQCoder.swift`

## Platform-Specific Issues

### MQDecoder Position Underflow ✅ FIXED

**Severity:** Critical  
**Platforms Affected:** All platforms (Linux, macOS, etc.)  
**Status:** ✅ **FIXED** in v1.2.0

#### Description

The MQDecoder would crash with an "Illegal instruction" error when decoding certain JPEG 2000 codestreams, particularly those with multiple decomposition levels.

#### Root Cause

In the `fillC()` method of `MQDecoder` (J2KMQCoder.swift line 494), `position -= 1` was being called unconditionally after calling `readByte()`. When `readByte()` hit end-of-file (position >= data.count), it would return 0xFF without incrementing position. However, `fillC()` would still decrement position, making it -1 (underflow).

**Buggy code:**
```swift
private mutating func fillC() {
    if buffer == 0xFF {
        nextBuffer = readByte()  // May not increment if EOF
        if nextBuffer > 0x8F {
            c += 0xFF00
            ct = 8
            position -= 1  // ❌ Wrong: decrements even if readByte() didn't advance
        }
        ...
    }
}
```

When `data[position]` was accessed with position = -1, it caused an illegal instruction crash at the Swift runtime level.

**Fixed code:**
```swift
private mutating func fillC() {
    if buffer == 0xFF {
        let prevPosition = position  // Track position before read
        nextBuffer = readByte()
        if nextBuffer > 0x8F {
            // Only decrement if we actually advanced (read from data, not EOF)
            if position > prevPosition {
                position -= 1
            }
            c += 0xFF00
            ct = 8
        }
        ...
    }
}
```

#### Fix

The `fillC()` method now tracks the position before calling `readByte()` and only decrements if the position actually advanced (i.e., we read from data, not EOF).

**Files Changed:**
- `Sources/J2KCodec/J2KMQCoder.swift` (lines 486-508)
- `Sources/J2KCodec/J2KBitPlaneCoder.swift` (added defensive guards at lines 764-842)

**Tests:**
- All codec integration tests now pass
- `Tests/J2KCodecTests/J2KCodecIntegrationTests.swift` - `testDifferentDecompositionLevels()` now passes

#### Status

✅ **RESOLVED** - MQDecoder position underflow fixed. All 1,528 tests pass (24 platform-specific tests skipped).

## Platform-Specific Issues

### Linux: Lossless Decoding Returns Empty Data ✅ FIXED

**Severity:** Medium  
**Platforms Affected:** Linux (Ubuntu verified, likely other distributions)  
**Status:** ✅ **FIXED** in v1.2.0

#### Description

When encoding an image with lossless configuration (`quality: 1.0, lossless: true`), the decoder was successfully parsing the codestream structure but returning empty component data (0 bytes) on Linux.

#### Root Cause

The issue was in the packet header parsing logic in `J2KDecoderPipeline.extractTileData()`. The `lengths` and `passes` arrays contain data **only for included code blocks**, not for all code blocks. The original code was using the code block index directly to access these arrays, causing an index out of bounds condition that resulted in no blocks being extracted.

**Buggy code:**
```swift
for (idx, included) in inclusions.enumerated() {
    guard included, idx < lengths.count else { continue }
    let dataLength = lengths[idx]  // ❌ Wrong: idx is code block index, not data index
    ...
}
```

**Fixed code:**
```swift
var dataIndex = 0  // Track position in lengths/passes arrays
for (idx, included) in inclusions.enumerated() {
    guard included else { continue }
    guard dataIndex < lengths.count else { break }
    let dataLength = lengths[dataIndex]  // ✅ Correct: use separate data index
    dataIndex += 1
    ...
}
```

#### Fix

The packet parsing code was updated to use a separate index (`dataIndex`) to track position in the `lengths` and `passes` arrays, which are compressed to contain only data for included blocks.

**Files Changed:**
- `Sources/J2KCodec/J2KDecoderPipeline.swift` (lines 550-591 and 633-670)

**Tests:**
- `Tests/J2KCodecTests/J2KCodecIntegrationTests.swift` - `testLosslessRoundTrip()` now passes on Linux

#### Status

✅ **RESOLVED** - Lossless decoding now works correctly on Linux.

## Future Improvements

### HTJ2K (High Throughput JPEG 2000)

J2KSwift v2.0 will include HTJ2K (ISO/IEC 15444-15) support, which uses a completely redesigned block coder (FBCOT) that addresses many limitations of the legacy MQ coder:
- Significantly faster encoding/decoding (4-10× throughput)
- Simpler state machine with fewer edge cases
- Better handling of large blocks
- Backward compatible with JPEG 2000 Part 1

---

**Last Updated:** 2026-02-15  
**Version:** 1.1.1  
**Status:** Released
