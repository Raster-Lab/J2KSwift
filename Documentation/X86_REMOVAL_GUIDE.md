# x86-64 Code Removal Guide

## Overview

This guide documents all x86-64 specific code in J2KSwift and provides instructions for safely removing it in future versions. The project has transitioned to focus primarily on Apple Silicon (ARM64) architecture, with x86-64 code maintained for compatibility but not actively optimized.

## Current x86-64 Code Locations

### 1. J2KAccelerate Module

#### `Sources/J2KAccelerate/x86/J2KAccelerate_x86.swift` (228 lines)
**Purpose**: x86-64 specific hardware acceleration support
**Status**: Isolated in dedicated x86/ directory with deprecation notices
**Dependencies**: Accelerate framework (when available on x86-64)

**Key Components**:
- `J2KAccelerateX86` struct providing x86-64 optimizations
- AVX/AVX2 SIMD detection and usage
- x86-64 specific performance characteristics

**Conditional Compilation**:
```swift
#if canImport(Accelerate) && arch(x86_64)
```

### 2. J2KCodec Module (Motion JPEG 2000)

#### `Sources/J2KCodec/x86/MJ2_x86.swift` (106 lines)
**Purpose**: x86-64 specific MJ2 operations and detection
**Status**: Isolated in dedicated x86/ directory with deprecation notices
**Dependencies**: None (Foundation only)

**Key Components**:
- `MJ2X86` struct providing x86-64 detection and warnings
- CPU feature detection (SSE4.2, AVX, AVX2)
- Deprecation warning messages for users

**Conditional Compilation**:
```swift
#if arch(x86_64)
```

**Note**: VideoToolbox is not available on non-Apple x86-64 platforms, so hardware acceleration is limited to Apple Intel Macs.

#### `Sources/J2KCodec/x86/J2KSSEEntropyCoding.swift`
**Purpose**: SSE4.2/AVX2-accelerated entropy coding for JPEG 2000
**Status**: Isolated in dedicated x86/ directory with deprecation notices
**Dependencies**: Foundation

**Key Components**:
- `X86EntropyCodingCapability` — CPUID-based SSE4.2/AVX2/FMA feature detection
- `SSEContextFormation` — AVX2 8-wide context label computation for MQ-coder
- `AVX2BitPlaneCoder` — AVX2 bit-plane extraction, magnitude refinement, run-length detection
- `X86MQCoderVectorised` — Batch MQ-coder probability state updates, vectorised leading-zeros

**Conditional Compilation**:
```swift
#if arch(x86_64)
// SIMD8<Float>  → AVX2 ymm registers (256-bit)
// SIMD8<Int32>  → AVX2 ymm registers (256-bit)
#endif
```

**Tests**: `Tests/J2KCodecTests/J2KSSEEntropyTests.swift`

#### `Sources/J2KAccelerate/x86/J2KSSETransforms.swift`
**Purpose**: SSE4.2/AVX2-accelerated wavelet, colour, quantisation, and cache transforms
**Status**: Isolated in dedicated x86/ directory with deprecation notices
**Dependencies**: Foundation, J2KCore

**Key Components**:
- `X86TransformCapability` — Runtime SIMD capability detection (SSE4.2/AVX2/FMA)
- `X86WaveletLifting` — AVX2 8-wide 5/3 and 9/7 wavelet lifting with FMA for 9/7 coefficients
- `X86ColourTransform` — AVX2 8-wide ICT and RCT colour transforms (ISO/IEC 15444-1 Annex G)
- `X86Quantizer` — AVX2 batch scalar and dead-zone quantisation/dequantisation
- `X86CacheOptimizer` — Cache-oblivious DWT blocking, 32-byte aligned alloc, streaming stores

**Conditional Compilation**:
```swift
#if arch(x86_64)
// SIMD8<Float>  → 256-bit AVX2 ymm registers
// SIMD8<Int32>  → 256-bit AVX2 ymm registers
#endif
```

**Tests**: `Tests/J2KAccelerateTests/J2KSSETransformTests.swift`

#### `Sources/J2KAccelerate/J2KHTSIMDAcceleration.swift`
**Purpose**: SIMD acceleration with cross-platform support
**Status**: Contains x86-64 fallback paths alongside ARM64 optimizations

**x86-64 References** (15 occurrences):
- Documentation comments mentioning SSE4.2/AVX2 capabilities
- `#elseif arch(x86_64)` conditional compilation blocks
- x86_64 SIMD level detection logic
- Performance notes for x86-64 platforms

**Key Sections**:
```swift
#if arch(x86_64)
/// Detects x86_64 SIMD level.
private static func detectX86SIMDLevel() -> SIMDLevel {
    // x86_64 detection logic
}
#endif
```

## Removal Strategy

### Phase 1: Deprecation (Current State)
✅ All x86-64 code is already isolated and marked with deprecation notices
✅ Documentation clearly indicates x86-64 as secondary architecture
✅ Tests validate both ARM64 and x86-64 paths separately

### Phase 2: Warning Period (Next Major Version)
- Add compiler warnings for x86-64 builds
- Update documentation to announce removal timeline
- Provide migration guides for Intel Mac users
- Recommend Rosetta 2 for running ARM64 builds on Intel Macs

### Phase 3: Removal (Future Major Version)

#### Step 1: Remove Dedicated x86-64 Files
```bash
# Remove the x86 directories
rm -rf Sources/J2KAccelerate/x86/
rm -rf Sources/J2KCodec/x86/
```

**Files to Remove**:
- `Sources/J2KAccelerate/x86/J2KAccelerate_x86.swift`
- `Sources/J2KAccelerate/x86/J2KSSETransforms.swift`
- `Sources/J2KCodec/x86/MJ2_x86.swift`
- `Sources/J2KCodec/x86/J2KSSEEntropyCoding.swift`

#### Step 2: Clean Up Conditional Compilation

**In `J2KHTSIMDAcceleration.swift`**:
1. Remove all `#if arch(x86_64)` and `#elseif arch(x86_64)` blocks
2. Remove `detectX86SIMDLevel()` function
3. Update `SIMDLevel` enum to remove x86-specific cases:
   - Remove `.sse42`
   - Remove `.avx2`
4. Keep only ARM64 SIMD levels (`.neon`, `.neonWithAMX`)
5. Update documentation to remove x86-64 performance notes

**Search and Replace Patterns**:
```bash
# Find all x86_64 references
grep -r "x86_64\|#if arch(x86_64)" --include="*.swift" Sources/

# Find SSE/AVX references (for documentation cleanup)
grep -r "SSE\|AVX\|x86" --include="*.swift" Sources/J2KAccelerate/
```

#### Step 3: Update Documentation
1. Remove x86-64 performance notes from all documents
2. Update architecture support tables
3. Revise installation instructions for Intel Mac users
4. Update README.md platform requirements

**Files to Update**:
- `README.md` - Platform requirements section
- `Documentation/HARDWARE_ACCELERATION.md` - Remove x86-64 sections
- `Documentation/ACCELERATE_ADVANCED.md` - Remove Intel-specific optimizations
- `Documentation/PERFORMANCE_APPLE_SILICON.md` - Rename if needed
- All tutorial and guide documents mentioning x86-64

#### Step 4: Update Tests
1. Remove x86-64 specific test cases in `J2KAccelerateTests`
2. Update CI/CD pipelines to remove Intel Mac runners
3. Remove x86-64 performance benchmarks

#### Step 5: Update Package Configuration
**In `Package.swift`**:
- Remove any x86-64 specific build settings
- Update platform deployment targets if needed
- Clean up conditional compilation settings

### Phase 4: Validation
After removal, validate:
1. ✅ ARM64 builds compile without errors
2. ✅ All tests pass on Apple Silicon
3. ✅ Performance benchmarks show expected results
4. ✅ No references to x86-64 remain in codebase
5. ✅ Documentation is consistent

## Migration Path for Users

### For Intel Mac Users (Post-Removal)

**Option 1: Use Rosetta 2 (Recommended)**
```bash
# Build universal binary (ARM64 native)
swift build -c release

# Run on Intel Mac via Rosetta 2
arch -arm64 .build/release/j2k-cli encode ...
```

**Option 2: Use Older Version**
- Continue using v1.7.0 or earlier with x86-64 support
- Receive security updates only
- No new features

**Option 3: Migrate to Apple Silicon Hardware**
- Best performance and power efficiency
- Full Metal GPU acceleration
- AMX matrix coprocessor support

## Verification Checklist

Before removing x86-64 code, ensure:

- [ ] All x86-64 code locations are documented
- [ ] Deprecation notices are in place for one major version
- [ ] Users are notified through release notes
- [ ] Migration guides are available
- [ ] Fallback options are documented (Rosetta 2)
- [ ] CI/CD updated to test ARM64 only
- [ ] Performance targets validated on ARM64
- [ ] Documentation scrubbed of x86-64 references

## Impact Analysis

### Performance Impact
- **ARM64**: No impact (already optimized)
- **x86-64**: Users must use Rosetta 2 (slight overhead)

### Maintenance Impact
- Reduced code complexity
- Simplified testing matrix
- Focus on single architecture optimization
- Cleaner conditional compilation

### User Impact
- **Apple Silicon Users**: No impact
- **Intel Mac Users**: Must use Rosetta 2 or older version
- **Linux Users**: ARM64 servers unaffected; x86-64 Linux would need Rosetta-equivalent

## Timeline Recommendation

Based on Apple Silicon adoption:

- **v1.7.0 (Current)**: x86-64 supported with deprecation notices
- **v1.8.0 (Q3 2026)**: Add removal warnings, announce timeline
- **v2.0.0 (Q1 2027)**: Remove x86-64 code completely

## References

### x86-64 Code Documentation
- `Sources/J2KAccelerate/x86/J2KAccelerate_x86.swift` - Main x86-64 implementation
- `Sources/J2KAccelerate/J2KHTSIMDAcceleration.swift` - Cross-platform SIMD with x86-64 support

### Apple Silicon Transition
- [Apple Silicon Documentation](https://developer.apple.com/documentation/apple-silicon)
- [Accelerate Framework on Apple Silicon](https://developer.apple.com/documentation/accelerate)
- [Metal on Apple Silicon](https://developer.apple.com/metal/)

### Related Documents
- `Documentation/APPLE_SILICON_OPTIMIZATION.md` - ARM64 optimization guide
- `Documentation/ACCELERATE_ADVANCED.md` - Accelerate framework integration
- `Documentation/HARDWARE_ACCELERATION.md` - General hardware acceleration

---

**Last Updated**: 2026-02-19  
**Version**: 1.7.0  
**Maintainer**: J2KSwift Team
