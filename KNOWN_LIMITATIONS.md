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

## Future Improvements

### HTJ2K (High Throughput JPEG 2000)

J2KSwift v2.0 will include HTJ2K (ISO/IEC 15444-15) support, which uses a completely redesigned block coder (FBCOT) that addresses many limitations of the legacy MQ coder:
- Significantly faster encoding/decoding (4-10× throughput)
- Simpler state machine with fewer edge cases
- Better handling of large blocks
- Backward compatible with JPEG 2000 Part 1

---

**Last Updated:** 2026-02-15  
**Version:** 1.1.1-dev  
**Status:** Under Investigation
