# J2KSwift v1.2.0 Release Notes

**Release Date:** February 16, 2026  
**Status:** Released

## Overview

Version 1.2.0 is a minor release that includes critical bug fixes discovered after v1.1.1, along with performance improvements and enhanced cross-platform support.

## Critical Bug Fixes

### MQDecoder Position Underflow ✅ FIXED

**Severity:** Critical  
**Impact:** Could cause crashes with "Illegal instruction" error when decoding certain JPEG 2000 codestreams

**Description:**
The MQDecoder would crash when decoding codestreams with multiple decomposition levels due to a position underflow bug in the `fillC()` method.

**Root Cause:**
The `fillC()` method was unconditionally decrementing the position after calling `readByte()`, even when `readByte()` hit EOF and didn't advance the position. This caused position to underflow to -1, leading to crashes when accessing `data[position]`.

**Fix:**
The `fillC()` method now tracks the position before calling `readByte()` and only decrements if the position actually advanced.

**Files Changed:**
- `Sources/J2KCodec/J2KMQCoder.swift` (lines 486-508)
- `Sources/J2KCodec/J2KBitPlaneCoder.swift` (lines 764-842)

**Tests:**
- All codec integration tests now pass
- `testDifferentDecompositionLevels()` specifically validates this fix

**Credit:** Issue #121

---

### Linux: Lossless Decoding Returns Empty Data ✅ FIXED

**Severity:** Medium  
**Platform:** Linux (all distributions)  
**Impact:** Lossless encoded images decoded to empty data on Linux

**Description:**
When encoding an image with lossless configuration (`quality: 1.0, lossless: true`), the decoder would successfully parse the codestream structure but return empty component data (0 bytes) on Linux.

**Root Cause:**
The packet header parsing logic in `J2KDecoderPipeline.extractTileData()` was incorrectly indexing into the `lengths` and `passes` arrays. These arrays contain data only for included code blocks, not for all code blocks. The original code was using the code block index directly to access these arrays, causing an index out of bounds condition.

**Fix:**
The packet parsing code was updated to use a separate index (`dataIndex`) to track position in the `lengths` and `passes` arrays, which are compressed to contain only data for included blocks.

**Files Changed:**
- `Sources/J2KCodec/J2KDecoderPipeline.swift` (lines 550-591 and 633-670)

**Tests:**
- `testLosslessRoundTrip()` now passes on Linux
- Cross-platform validation tests confirm fix

---

## Test Results

**Total Tests:** 1,528  
**Passing:** 1,504 (98.4%)  
**Skipped:** 24 (platform-specific and known 64×64 MQ coder issue)  
**Failing:** 0

### Test Coverage by Module
- **J2KCore:** 100% pass rate
- **J2KCodec:** 98.4% pass rate (6 tests skipped for known 64×64 MQ coder issue)
- **J2KFileFormat:** 100% pass rate
- **J2KAccelerate:** 100% pass rate
- **JPIP:** 100% pass rate

## Known Limitations

### MQ Coder - 64×64 Dense Data Issue

The MQ coder has a known issue when encoding/decoding code blocks that meet ALL of the following criteria:
- Block size is exactly 64×64 (4,096 coefficients)
- Data contains dense, high-magnitude values with significant variation
- Pattern has many non-zero coefficients with varied bit-planes

**Status:** Documented, low priority (affects only edge cases)  
**Workaround:** Use code blocks ≤ 32×32 for images with dense, high-variation data  
**Planned Fix:** v1.2.x or later

See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for complete details.

## Performance

Performance benchmarking is ongoing. Current status:
- Encoding speed: ~32.6% of OpenJPEG (target: ≥80%)
- Decoding speed: TBD
- Memory usage: Optimized with buffer pooling

See [REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md) for detailed performance analysis.

## Cross-Platform Support

### Validated Platforms
- ✅ **Linux (Ubuntu x86_64, Swift 6.2.3):** 98.4% test pass rate
- ✅ **macOS:** Full support (via CI)
- ⏭️ **Windows:** Planned for future release

See [CROSS_PLATFORM.md](CROSS_PLATFORM.md) for platform-specific details.

## API Changes

No breaking API changes in v1.2.0. All v1.1.x APIs remain compatible.

## Documentation Updates

- Updated [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) to reflect fixed issues
- Updated [CROSS_PLATFORM.md](CROSS_PLATFORM.md) with Linux validation results
- Created this release notes document

## Migration Guide

No migration required from v1.1.1 to v1.2.0. Simply update your package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.2.0")
]
```

## Acknowledgments

- GitHub issue reporters for bug reports
- Contributors who helped validate fixes across platforms
- The Swift community for Swift 6.2 support

## What's Next

### Planned for v1.2.x Patches
- Performance optimizations (target: ≥80% of OpenJPEG speed)
- Additional cross-platform validation (Windows support)
- Enhanced conformance testing

### Planned for v1.3.0
- API refinements based on user feedback
- Additional encoding/decoding optimizations
- Enhanced JPIP streaming features

### Planned for v2.0.0
- HTJ2K codec (ISO/IEC 15444-15 - High Throughput JPEG 2000)
- Lossless transcoding between JPEG 2000 and HTJ2K
- JPEG 2000 Part 2 extensions

---

**Project:** J2KSwift - A pure Swift 6 implementation of JPEG 2000  
**License:** MIT  
**Repository:** https://github.com/Raster-Lab/J2KSwift  
**Documentation:** [README.md](README.md) | [MILESTONES.md](MILESTONES.md)
