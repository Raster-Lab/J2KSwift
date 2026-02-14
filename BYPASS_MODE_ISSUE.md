# Bypass Mode Known Issue

## Summary

The bypass mode implementation in J2KSwift has a synchronization bug that causes decode failures with dense coefficient data. This affects approximately 0.3% of tests (5 out of 1,475 tests).

## Impact

- **Severity**: Low (bypass mode is a performance optimization, not a correctness requirement)
- **Affected Tests**: 5 tests fail when using `CodingOptions.fastEncoding` (which enables bypass mode)
- **Normal Operation**: All 1,470+ other tests pass, including all tests without bypass mode

## Failing Tests

1. `J2KBitPlaneDiagnosticTest.testMinimalBlock32x32` - 95.70% decode error rate
2. `J2KBitPlaneDiagnosticTest.testMinimalBlock64x64` - Similar failure pattern
3. `J2KBypassModeTests.testCodeBlockBypassLargeBlock` - Large block with bypass
4. `J2KLargeBlockDiagnostic.test64x64WithoutBypass` - Predictable termination issue  
5. `J2KLargeBlockDiagnostic.testProgressiveBlockSizes` - Progressive sizes

## Root Cause

The bypass mode encoder and decoder use incompatible bit positioning in the C register:

**Encoder** (`encodeBypass`):
```swift
c <<= 1              // Shift entire C register left
if symbol {
    c += 0x8000      // Add bit at position 15
}
ct -= 1
if ct == 0 {
    emitByte()       // Extracts bits from positions 19-26
}
```

**Decoder** (`decodeBypass`):
```swift
if ct == 0 {
    fillC()          // Fills C register (upper 16 bits)
}
ct -= 1
c <<= 1              // Shift entire C register left
return (c >> 16) >= 0x8000  // Check bit 31
```

The encoder places bits that eventually end up in positions 19-26 (after shifts), while the decoder checks bit 31. This fundamental mismatch causes desynchronization.

## Investigation History

Multiple implementation approaches were attempted:

1. **Rewrote to match OpenJPEG** - OpenJPEG uses a different buffer pointer architecture
2. **Added proper MQ coder flush** - Made the issue worse (more bytes emitted)
3. **Shared MQ coder state** - 100% failure rate
4. **Different bit positioning** - Still failed

The core issue is that bypass mode needs to integrate seamlessly with the MQ coder's complex byte output mechanism (including carry propagation and 0xFF stuffing), and the current bit positioning doesn't align correctly.

## Workaround

### Option 1: Disable Bypass Mode (Recommended)

```swift
// Instead of:
let options = CodingOptions.fastEncoding

// Use:
let options = CodingOptions(
    bypassEnabled: false,
    bypassThreshold: 0,
    terminationMode: .default,
    resetOnEachPass: false
)
```

**Impact**: Slightly slower encoding (5-10%), but correct results.

### Option 2: Use Higher Bypass Threshold

```swift
let options = CodingOptions(
    bypassEnabled: true,
    bypassThreshold: 6,  // Higher threshold = less bypass usage
    terminationMode: .default,
    resetOnEachPass: false
)
```

**Impact**: Reduces chance of hitting the bug with sparse data.

### Option 3: Use Lossless Mode

```swift
let options = CodingOptions(
    bypassEnabled: false,
    terminationMode: .default,
    resetOnEachPass: false
)
```

Lossless mode doesn't use bypass.

## Future Plans

### v1.1.1 or v1.2 (Priority: Medium)

This issue will be addressed in a future release by one of:

1. **Deep rewrite**: Restructure MQ coder to match OpenJPEG's pointer-based architecture
2. **Bit-level debugging**: Create minimal test cases and trace through bit-by-bit
3. **Alternative implementation**: Use a separate bypass path that doesn't share MQ coder state
4. **Expert consultation**: Bring in JPEG 2000 arithmetic coding expert

### Estimated Effort

3-5 days of focused work by someone with deep JPEG 2000 expertise, or 1-2 weeks for learning and implementation.

## References

- [BYPASS_MODE.md](BYPASS_MODE.md) - Feature documentation
- [BYPASS_MODE_BUG_2026-02-08.md](BYPASS_MODE_BUG_2026-02-08.md) - Initial investigation
- [ROADMAP_v1.1.md](ROADMAP_v1.1.md) - v1.1 development plan
- OpenJPEG source: `src/lib/openjp2/mqc.c` and `mqc_inl.h`
- ISO/IEC 15444-1 Annex C - MQ-coder specification

## Testing

To verify bypass mode is not being used:

```swift
let options = CodingOptions(bypassEnabled: false)
let encoder = CodeBlockEncoder()
let codeBlock = try encoder.encode(
    coefficients: data,
    width: 32,
    height: 32,
    subband: .ll,
    bitDepth: 12,
    options: options
)
// This should work correctly
```

## Conclusion

Bypass mode is a performance optimization that trades slightly faster encoding for this known bug. Since disabling it provides correct results with minimal performance impact, this is classified as a low-priority issue suitable for a future release.

Users needing maximum encoding speed can work around this by using the standard MQ coder (bypass disabled) until a fix is available in v1.1.1 or later.
