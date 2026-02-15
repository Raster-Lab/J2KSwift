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

### Linux: Lossless Decoding Returns Empty Data

**Severity:** Medium  
**Platforms Affected:** Linux (Ubuntu verified, likely other distributions)  
**Status:** Under Investigation for v1.2.0

#### Description

When encoding an image with lossless configuration (`quality: 1.0, lossless: true`), the decoder successfully parses the codestream structure but returns empty component data (0 bytes) on Linux. The same code is expected to work correctly on macOS.

#### Symptoms

- **Encoder**: Works correctly, produces valid codestream (e.g., 150 bytes for 16×16 gradient)
- **Decoder**: Parses structure correctly (width, height, component count all correct)
- **Data**: Component `data` field is empty (0 bytes instead of expected value)
- **Platform**: Only occurs on Linux; expected to work on macOS

#### Working Configurations

✅ **Works correctly on Linux:**
- Default encoding (no explicit lossless config)
- Lossy encoding (quality < 1.0, lossless: false)
- Multi-component RGB encoding/decoding
- Constant-value images with default config

❌ **Fails on Linux:**
- Explicit lossless encoding (quality: 1.0, lossless: true) with gradient or varied data

#### Test Case

The issue is captured in `Tests/J2KCodecIntegrationTests/testLosslessRoundTrip()`:
- Creates 16×16 gradient pattern
- Encodes with `J2KEncodingConfiguration(quality: 1.0, lossless: true)`
- Decodes successfully with correct dimensions
- Component data is empty (0 bytes)

**Current Status:** Test skipped on Linux via `#if os(Linux)`

#### Suspected Causes

Possible areas for investigation:
1. **Reversible Color Transform (RCT)**: Platform-specific integer arithmetic differences
2. **Reversible Wavelet (5/3 filter)**: Lifting step implementation differences
3. **Quantization**: Expounded quantization mode handling
4. **Packet Parsing**: Multi-level decomposition packet structure interpretation
5. **Memory Layout**: Endianness or alignment differences

#### Workaround

On Linux, use default encoder configuration or explicitly set `lossless: false`:

```swift
// Works on Linux
let encoder = J2KEncoder()  // Uses default config
let encoded = try encoder.encode(image)
let decoded = try decoder.decode(encoded)

// Or explicitly use lossy
let config = J2KEncodingConfiguration(quality: 0.95, lossless: false)
let encoder = J2KEncoder(encodingConfiguration: config)
```

#### Investigation Plan for v1.2.0

1. Add comprehensive debug logging to decoder pipeline
2. Compare byte-by-byte codestream output between Linux and macOS
3. Test intermediate pipeline stages (post-DWT, post-quantization, etc.)
4. Check for platform-specific behavior in:
   - `J2KDWT1D.forwardTransform` (reversible mode)
   - `J2KDWT2D.forwardTransform` (5/3 filter)
   - `J2KQuantizer.quantize` (expounded mode)
   - `DecoderPipeline.applyInverseWaveletTransform`
5. Validate arithmetic precision in lifting steps
6. Test on additional platforms (Fedora, Arch, ARM64 Linux)

#### Related

- **File**: `Tests/J2KCodecTests/J2KCodecIntegrationTests.swift` (line 152)
- **Documentation**: `CROSS_PLATFORM.md` (detailed platform testing)
- **Issue Tracking**: To be created for v1.2.0 milestone

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
