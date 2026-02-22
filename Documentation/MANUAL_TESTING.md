# J2KSwift Manual Testing Guide

Comprehensive manual testing documentation for J2KSwift v2.3.0, organised phase by phase covering all 5,419 automated test cases across 14 test targets and 21 development phases.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Running Tests](#running-tests)
- [Phase 0: Foundation](#phase-0-foundation-weeks-1-10)
- [Phase 1: Entropy Coding](#phase-1-entropy-coding-weeks-11-25)
- [Phase 2: Wavelet Transform](#phase-2-wavelet-transform-weeks-26-40)
- [Phase 3: Quantization](#phase-3-quantization-weeks-41-48)
- [Phase 4: Color Transforms](#phase-4-color-transforms-weeks-49-56)
- [Phase 5: File Format](#phase-5-file-format-weeks-57-68)
- [Phase 6: JPIP Protocol](#phase-6-jpip-protocol-weeks-69-80)
- [Phase 7: Optimisation and Features](#phase-7-optimisation-and-features-weeks-81-92)
- [Phase 8: Production Ready](#phase-8-production-ready-weeks-93-100)
- [Phase 9: HTJ2K Codec](#phase-9-htj2k-codec-weeks-101-120)
- [Phase 10: Lossless Transcoding](#phase-10-lossless-transcoding-weeks-121-130)
- [Phase 11: Enhanced JPIP with HTJ2K](#phase-11-enhanced-jpip-with-htj2k-v140)
- [Phase 12: Performance and Cross-Platform](#phase-12-performance-and-cross-platform-v150)
- [Phase 13: Part 2 Extensions](#phase-13-part-2-extensions-v160)
- [Phase 14: Metal GPU Acceleration](#phase-14-metal-gpu-acceleration-v170)
- [Phase 15: Motion JPEG 2000](#phase-15-motion-jpeg-2000-v180)
- [Phase 16: JP3D Volumetric](#phase-16-jp3d-volumetric-v190)
- [Phase 17: v2.0 Refactoring](#phase-17-v20-refactoring-weeks-236-295)
- [Phase 18: GUI Testing Application](#phase-18-gui-testing-application-v21)
- [Phase 19: Multi-Spectral JP3D and Vulkan](#phase-19-multi-spectral-jp3d-and-vulkan-v220)
- [Phase 20: JPEG XS Core Codec](#phase-20-jpeg-xs-core-codec-v230)
- [Performance Targets](#performance-targets)
- [Conformance Matrix](#conformance-matrix)
- [Known Limitations](#known-limitations)
- [Glossary](#glossary)

---

## Overview

| Metric | Value |
|--------|-------|
| Total automated tests | 5,419 |
| Test targets | 14 |
| Development phases | 21 (Phase 0-20) |
| Current version | 2.3.0 |
| Swift version | 6.2+ |
| Minimum macOS | 15.0 |

### Test Target Summary

| Target | Tests | Primary Coverage |
|--------|------:|------------------|
| J2KCoreTests | 734 | Core types, memory, bitstream, markers, platform |
| J2KCodecTests | 1,679 | Entropy coding, DWT, quantization, colour, HTJ2K, pipeline |
| J2KAccelerateTests | 367 | Hardware acceleration, SIMD, Neon, SSE, vImage |
| J2KFileFormatTests | 384 | JP2 boxes, file I/O, MJ2 format |
| JPIPTests | 478 | JPIP client/server, streaming, cache, WebSocket |
| J2KMetalTests | 314 | Metal GPU compute, DWT, colour, quantization |
| J2KTestAppTests | 309 | GUI test app models and view models |
| J2KComplianceTests | 304 | ISO conformance Parts 1, 2, 3, 10, 15 |
| JP3DTests | 405 | 3D volumetric, multi-spectral, HTJ2K 3D |
| PerformanceTests | 154 | Benchmarks, validation, OpenJPEG comparison |
| J2KInteroperabilityTests | 142 | OpenJPEG cross-validation |
| J2KVulkanTests | 85 | Vulkan GPU compute, DWT, colour |
| J2KXSTests | 52 | JPEG XS codec |
| J2KCLITests | 12 | Command-line interface |

---

## Prerequisites

- **macOS 15.0+** (Sequoia) or **Linux** (Ubuntu 22.04+)
- **Xcode 16.3+** with Swift 6.2+
- **Swift toolchain**: `swift --version` should report 6.2 or later
- Optional: **OpenJPEG** (`opj_compress`/`opj_decompress`) for interoperability tests

## Running Tests

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test target
swift test --filter J2KCoreTests

# Run a specific test class
swift test --filter J2KCoreTests.J2KCoreTests

# Run a single test function
swift test --filter J2KCoreTests.J2KCoreTests/testGetVersion

# Run tests with verbose output
swift test -v

# Run with release optimisations
swift test -c release
```

---

## Phase 0: Foundation (Weeks 1-10)

**Goal**: Establish project infrastructure, core types, and basic building blocks.

### Test Target: J2KCoreTests

#### TC-0.1: Project Setup and Module Linkage

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 0.1.1 | Module compilation | `testModuleCompilationAndLinkage` | All modules compile and link |
| 0.1.2 | Version string | `testGetVersion` | Returns current version string |

**Manual verification**:
```bash
swift build
swift test --filter J2KCoreTests.J2KCoreTests/testModuleCompilationAndLinkage
```

#### TC-0.2: Core Type System (Week 3-4)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 0.2.1 | Configuration defaults | `testConfigurationDefaults` | Default config has sensible values |
| 0.2.2 | Configuration custom | `testConfigurationCustomValues` | Custom values stored correctly |
| 0.2.3 | Error types | `testErrorTypes` | All J2KError cases instantiable |
| 0.2.4 | Component init | `testComponentInitialization` | Components with correct bit-depth |
| 0.2.5 | Component subsampling | `testComponentSubsampling` | Subsampling ratios correct |
| 0.2.6 | Component signed | `testComponentSigned` | Signed flag set correctly |
| 0.2.7 | Image simple init | `testImageSimpleInitialization` | Width, height, components stored |
| 0.2.8 | Image custom bit-depth | `testImageCustomBitDepth` | Non-default bit-depth works |
| 0.2.9 | Image with tiling | `testImageWithTiling` | Tile dimensions set correctly |
| 0.2.10 | Image without tiling | `testImageWithoutTiling` | No tiling by default |
| 0.2.11 | Image colour space | `testImageColorSpace` | Colour space enum correct |
| 0.2.12 | Tile init | `testTileInitialization` | Tile index and bounds correct |
| 0.2.13 | Tile with components | `testTileWithComponents` | Multi-component tile |
| 0.2.14 | Tile component init | `testTileComponentInitialization` | Per-component tile data |
| 0.2.15 | Precinct init | `testPrecinctInitialization` | Precinct bounds set |
| 0.2.16 | Code block init | `testCodeBlockInitialization` | Code block dimensions |
| 0.2.17 | Code block subbands | `testCodeBlockSubbands` | Subband assignment correct |
| 0.2.18 | Subband enum | `testSubbandEnum` | LL, LH, HL, HH cases exist |
| 0.2.19 | Colour space enum | `testColorSpaceEnum` | sRGB, grayscale, etc. |
| 0.2.20 | Colour space ICC | `testColorSpaceICCProfile` | ICC profile attachment |

```bash
swift test --filter J2KCoreTests.J2KCoreTests
```

#### TC-0.3: Memory Management (Week 5-6)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 0.3.1 | Buffer init | `testBufferInitialization` | Buffer created with correct size |
| 0.3.2 | Buffer from Data | `testBufferFromData` | Data round-trip |
| 0.3.3 | Buffer read access | `testBufferReadAccess` | Read without crash |
| 0.3.4 | Buffer write access | `testBufferWriteAccess` | Write modifies data |
| 0.3.5 | Buffer copy-on-write | `testBufferCopyOnWrite` | COW semantics |
| 0.3.6 | Buffer to Data | `testBufferToData` | Export to Foundation.Data |
| 0.3.7 | Buffer update count | `testBufferUpdateCount` | Count tracks modifications |
| 0.3.8 | Image buffer init | `testImageBufferInitialization` | Width x height allocation |
| 0.3.9 | Image buffer 16-bit | `testImageBuffer16Bit` | 16-bit sample support |
| 0.3.10 | Image buffer COW | `testImageBufferCopyOnWrite` | Image-level COW |
| 0.3.11 | Image buffer pixel access | `testImageBufferGetSetPixel` | Get/set individual pixels |
| 0.3.12 | Image buffer coordinates | `testImageBufferGetSetPixelCoordinates` | Coordinate validation |
| 0.3.13 | Image buffer from Data | `testImageBufferFromData` | Construct from raw data |
| 0.3.14 | Image buffer to Data | `testImageBufferToData` | Serialise to Data |
| 0.3.15 | Image buffer unsafe | `testImageBufferUnsafeAccess` | Pointer-based access |
| 0.3.16 | Image buffer size | `testImageBufferSizeInBytes` | Memory footprint correct |
| 0.3.17 | Memory pool acquire | `testMemoryPoolAcquireAndRelease` | Pool acquire/release cycle |
| 0.3.18 | Memory pool reuse | `testMemoryPoolReuse` | Previously released buffers reused |
| 0.3.19 | Memory pool config | `testMemoryPoolConfiguration` | Pool configuration respected |
| 0.3.20 | Memory pool clear | `testMemoryPoolClear` | Pool fully drained |
| 0.3.21 | Memory pool stats | `testMemoryPoolStatistics` | Hit/miss statistics tracked |
| 0.3.22 | Memory tracker alloc | `testMemoryTrackerAllocation` | Allocation recorded |
| 0.3.23 | Memory tracker dealloc | `testMemoryTrackerDeallocation` | Deallocation recorded |
| 0.3.24 | Memory tracker limit | `testMemoryTrackerLimit` | Allocation refused above limit |
| 0.3.25 | Memory tracker peak | `testMemoryTrackerPeakUsage` | Peak watermark tracked |
| 0.3.26 | Memory tracker pressure | `testMemoryTrackerPressure` | Pressure level classification |

```bash
swift test --filter J2KCoreTests.J2KMemoryManagementTests
```

#### TC-0.4: Basic I/O Infrastructure (Week 7-8)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 0.4.1 | BitReader init | `testBitReaderInitialization` | Reader created from Data |
| 0.4.2 | Read UInt8 | `testReadUInt8` | Correct byte read |
| 0.4.3 | Read UInt16 | `testReadUInt16` | Big-endian 16-bit |
| 0.4.4 | Read UInt32 | `testReadUInt32` | Big-endian 32-bit |
| 0.4.5 | Read bytes | `testReadBytes` | Multi-byte read |
| 0.4.6 | Read single bit | `testReadBit` | MSB-first bit read |
| 0.4.7 | Read N bits | `testReadBits` | Arbitrary bit count |
| 0.4.8 | Seek and skip | `testSeekAndSkip` | Position manipulation |
| 0.4.9 | Peek UInt8 | `testPeekUInt8` | Non-advancing peek |
| 0.4.10 | Read marker | `testReadMarker` | JPEG 2000 marker read |
| 0.4.11 | Read beyond data | `testReadBeyondData` | Error on overflow |
| 0.4.12 | BitWriter init | `testBitWriterInitialization` | Writer created empty |
| 0.4.13 | Write UInt8 | `testWriteUInt8` | Byte written |
| 0.4.14 | Write UInt16 | `testWriteUInt16` | 16-bit big-endian |
| 0.4.15 | Write single bit | `testWriteBit` | MSB-first bit write |
| 0.4.16 | Write N bits | `testWriteBits` | Arbitrary bit count |
| 0.4.17 | Align to byte | `testAlignToByte` | Padding with zeros |
| 0.4.18 | Write marker | `testWriteMarker` | Marker written |
| 0.4.19 | Byte round-trip | `testByteRoundTrip` | Write then read |
| 0.4.20 | Bit round-trip | `testBitRoundTrip` | Bit-level round-trip |
| 0.4.21 | Marker round-trip | `testMarkerRoundTrip` | Marker write/read |

```bash
swift test --filter J2KCoreTests.J2KBitstreamTests
```

#### TC-0.5: Marker System (Week 7-8)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 0.5.1 | Marker values | `testMarkerValues` | SOC=0xFF4F, SOT=0xFF90, etc. |
| 0.5.2 | Marker has segment | `testMarkerHasSegment` | SIZ/COD have segments, SOC does not |
| 0.5.3 | Marker is delimiting | `testMarkerIsDelimiting` | SOC/SOT/SOD/EOC are delimiters |
| 0.5.4 | Marker in main header | `testMarkerCanAppearInMainHeader` | SIZ/COD valid in main header |
| 0.5.5 | Marker name | `testMarkerName` | Human-readable names |
| 0.5.6 | Marker segment init | `testMarkerSegmentInitialization` | Segment with payload |
| 0.5.7 | Parse SOC | `testParseMarkerSegmentSOC` | SOC delimiter parsed |
| 0.5.8 | Parse invalid marker | `testParseInvalidMarker` | Error on non-marker byte |
| 0.5.9 | Parse main header | `testParseMainHeader` | Full header parsed |
| 0.5.10 | Validate structure | `testValidateBasicStructure` | SOC-SOT-SOD-EOC order |

```bash
swift test --filter J2KCoreTests.J2KMarkerTests
```

---

## Phase 1: Entropy Coding (Weeks 11-25)

**Goal**: Implement EBCOT (Embedded Block Coding with Optimised Truncation) engine.

### Test Target: J2KCodecTests

#### TC-1.1: MQ-Coder Arithmetic Entropy Coding (Week 11-13)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 1.1.1 | MQ state table size | `testMQStateTableSize` | 47 entries |
| 1.1.2 | MQ state first entry | `testMQStateTableFirstEntry` | Qe=0x5601, MPS=0 |
| 1.1.3 | MQ context init | `testMQContextInitialization` | 19 contexts initialised |
| 1.1.4 | EBCOT context count | `testEBCOTContextCount` | 19 contexts |
| 1.1.5 | MQ encoder init | `testMQEncoderInitialization` | A=0x8000, C=0 |
| 1.1.6 | MQ encode single | `testMQEncoderSingleSymbol` | Non-empty output |
| 1.1.7 | MQ encode multiple | `testMQEncoderMultipleSymbols` | Growing output |
| 1.1.8 | MQ encoder reset | `testMQEncoderReset` | State restored |
| 1.1.9 | MQ bypass mode | `testMQEncoderBypassMode` | Raw bits emitted |
| 1.1.10 | MQ finish default | `testMQEncoderFinishDefault` | Standard flush |
| 1.1.11 | MQ finish predictable | `testMQEncoderFinishPredictable` | Predictable termination |
| 1.1.12 | MQ finish near-optimal | `testMQEncoderFinishNearOptimal` | Shortest valid suffix |
| 1.1.13 | MQ decoder init | `testMQDecoderInitialization` | Decoder from bytes |
| 1.1.14 | MQ round-trip small | `testMQRoundTripSmall` | Encode then decode match |

#### TC-1.2: Test Vectors and Fuzz Tests (Week 23-25)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 1.2.1 | ISO test vector 1 | `testMQCoderISOTestVector1` | Matches reference |
| 1.2.2 | All zeros | `testMQCoderAllZeros` | Compresses efficiently |
| 1.2.3 | Alternating symbols | `testMQCoderAlternatingSymbols` | Correct decode |
| 1.2.4 | Long sequence | `testMQCoderLongSequence` | Large data handled |
| 1.2.5 | State transitions | `testMQCoderStateTransitions` | State evolves correctly |
| 1.2.6 | Random symbols fuzz | `testMQCoderRandomSymbols` | No crash, round-trip |
| 1.2.7 | Large data fuzz | `testMQCoderLargeData` | Memory stability |
| 1.2.8 | Many small encodes | `testMQCoderManySmallEncodes` | Repeated encode/decode |
| 1.2.9 | Random decoder data | `testMQDecoderRandomData` | No crash on random |

#### TC-1.3: Bit-Plane Coding (Week 11-13)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 1.3.1 | Coder init | `testBitPlaneCoderInitialization` | Valid state |
| 1.3.2 | Encode simple | `testBitPlaneCoderEncodeSimple` | Basic coefficients |
| 1.3.3 | Encode zeros | `testBitPlaneCoderEncodeZeros` | All-zero block |
| 1.3.4 | Default termination | `testBitPlaneCoderDefaultTermination` | Standard mode |
| 1.3.5 | Predictable termination | `testBitPlaneCoderPredictableTermination` | Predictable mode |
| 1.3.6 | Near-optimal termination | `testBitPlaneCoderNearOptimalTermination` | Near-optimal mode |
| 1.3.7 | Bypass mode | `testBitPlaneCoderWithBypass` | Bypass pass |
| 1.3.8 | Decoder round-trip | `testBitPlaneDecoderRoundTrip4x4` | Perfect reconstruction |

#### TC-1.4: Code-Block Coding (Week 14-16)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 1.4.1 | Encoder simple | `testCodeBlockEncoderSimple` | Basic encode |
| 1.4.2 | Decoder simple | `testCodeBlockDecoderSimple` | Basic decode |
| 1.4.3 | Round-trip zeros | `testCodeBlockRoundTripZeros` | All zero block |
| 1.4.4 | Round-trip mixed | `testCodeBlockRoundTripMixed` | Mixed signs |
| 1.4.5 | Round-trip sparse | `testCodeBlockRoundTripSparse` | Mostly zeros |
| 1.4.6 | Round-trip large | `testCodeBlockRoundTripLargeBlock` | 64x64 block |
| 1.4.7 | Round-trip all subbands | `testCodeBlockRoundTripAllSubbands` | LL/LH/HL/HH |

#### TC-1.5: Tier-2 Coding (Week 17-19)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 1.5.1 | Empty packet header | `testEmptyPacketHeader` | Zero-length packet |
| 1.5.2 | Complete packet | `testCompletePacketEncoding` | Full packet encode |
| 1.5.3 | Header round-trip | `testPacketHeaderRoundTrip` | Write then read match |
| 1.5.4 | Layer formation | `testLayerFormationMultipleLayers` | Multiple layers |
| 1.5.5 | Layer R-D optimisation | `testLayerFormationRDOptimization` | R-D optimal layers |
| 1.5.6 | Progression orders | `testProgressionOrderCount` | 5 orders |

```bash
swift test --filter J2KCodecTests.J2KTier1CodingTests
swift test --filter J2KCodecTests.J2KTier2CodingTests
swift test --filter J2KCodecTests.J2KEntropyTestVectors
swift test --filter J2KCodecTests.J2KEntropyFuzzTests
```

---

## Phase 2: Wavelet Transform (Weeks 26-40)

**Goal**: Implement discrete wavelet transforms with multiple filter types.

#### TC-2.1: 1D DWT (Week 26-28)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 2.1.1 | Forward 5/3 simple | `testForwardTransform53Simple` | Known output |
| 2.1.2 | Inverse 5/3 simple | `testInverseTransform53Simple` | Known output |
| 2.1.3 | 5/3 perfect reconstruction | `testPerfectReconstruction53WithVariousLengths` | Bit-exact |
| 2.1.4 | 5/3 random data | `testPerfectReconstruction53WithRandomData` | Perfect reconstruction |
| 2.1.5 | Forward 9/7 simple | `testForwardTransform97Simple` | Known output |
| 2.1.6 | Inverse 9/7 simple | `testInverseTransform97Simple` | Known output |
| 2.1.7 | 9/7 near-perfect | `testNearPerfectReconstruction97WithVariousLengths` | Near-perfect (lossy) |
| 2.1.8 | Symmetric boundary | `testSymmetricBoundaryExtension53` | Symmetric extension |
| 2.1.9 | Periodic boundary | `testPeriodicBoundaryExtension53` | Periodic extension |

```bash
swift test --filter J2KCodecTests.J2KDWT1DTests
```

#### TC-2.2: 2D DWT (Week 29-31)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 2.2.1 | Forward 2x2 | `testForwardTransform2x2` | Minimum size |
| 2.2.2 | Forward 4x4 | `testForwardTransform4x4` | Known coefficients |
| 2.2.3 | Reconstruction 4x4 | `testPerfectReconstruction4x4` | Bit-exact (5/3) |
| 2.2.4 | Reconstruction 8x8 | `testPerfectReconstruction8x8` | Larger block |
| 2.2.5 | Multi-level 2 | `testMultiLevelDecomposition2Levels` | 2-level DWT |
| 2.2.6 | Multi-level 3 | `testMultiLevelDecomposition3Levels` | 3-level DWT |
| 2.2.7 | Multi-level perfect | `testMultiLevelPerfectReconstruction` | Multi-level round-trip |
| 2.2.8 | Odd dimensions | `testOddDimensions` | Non-power-of-2 |
| 2.2.9 | Rectangular | `testRectangularImage` | Non-square input |
| 2.2.10 | Constant image | `testConstantImage` | DC-only content |

```bash
swift test --filter J2KCodecTests.J2KDWT2DTests
```

#### TC-2.3: Tiled DWT (Week 32-34)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 2.3.1 | Extract single tile | `testExtractSingleTile` | Tile extraction |
| 2.3.2 | Extract multiple tiles | `testExtractMultipleTiles` | Multi-tile |
| 2.3.3 | Non-aligned tiles | `testExtractTileWithNonAlignedDimensions` | Edge tiles |
| 2.3.4 | Assemble single | `testAssembleSingleTile` | Tile to image |
| 2.3.5 | Assemble multiple | `testAssembleMultipleTiles` | Multi-tile assembly |
| 2.3.6 | Forward single tile | `testForwardTransformSingleTile` | Per-tile DWT |
| 2.3.7 | Round-trip single tile | `testRoundTripSingleTile` | Tile round-trip |
| 2.3.8 | Multi-level tile | `testMultiLevelTileTransform` | Multi-level tiled |

```bash
swift test --filter J2KCodecTests.J2KDWT2DTiledTests
```

---

## Phase 3: Quantization (Weeks 41-48)

**Goal**: Implement scalar quantization, ROI coding, and rate control.

#### TC-3.1: Basic Quantization (Week 41-43)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 3.1.1 | Mode all cases | `testQuantizationModeAllCases` | Lossless + lossy |
| 3.1.2 | Guard bits valid | `testGuardBitsValidRange` | 0-7 accepted |
| 3.1.3 | Guard bits invalid | `testGuardBitsInvalidRange` | Out of range rejected |
| 3.1.4 | Default lossy params | `testDefaultLossyParameters` | Sensible defaults |
| 3.1.5 | Default lossless params | `testDefaultLosslessParameters` | Step size = 1.0 |
| 3.1.6 | Quality high | `testParametersFromQualityHigh` | Small step sizes |
| 3.1.7 | Quality low | `testParametersFromQualityLow` | Large step sizes |
| 3.1.8 | Quality clamping | `testParametersFromQualityClamping` | 0.0-1.0 clamped |

```bash
swift test --filter J2KCodecTests.J2KQuantizationTests
```

#### TC-3.2: Region of Interest (Week 44-45)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 3.2.1 | ROI shapes | `testROIShapeTypeAllCases` | Rectangle/ellipse/polygon |
| 3.2.2 | Rectangle region | `testRectangleRegionCreation` | Bounds correct |
| 3.2.3 | Ellipse region | `testEllipseRegionCreation` | Centre/radii correct |
| 3.2.4 | Polygon region | `testPolygonRegionCreation` | Vertices stored |
| 3.2.5 | Region priority | `testRegionPriority` | Priority ordering |
| 3.2.6 | Rectangle mask | `testGenerateRectangleMask` | Binary mask correct |
| 3.2.7 | Ellipse mask | `testGenerateEllipseMask` | Smooth ellipse |
| 3.2.8 | Polygon mask | `testGeneratePolygonMaskTriangle` | Triangle rasterised |

```bash
swift test --filter J2KCodecTests.J2KROITests
```

#### TC-3.3: Rate Control (Week 46-48)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 3.3.1 | Mode equality | `testRateControlModeEquality` | Equatable modes |
| 3.3.2 | Lossless config | `testLosslessConfiguration` | No rate limit |
| 3.3.3 | Target bitrate | `testTargetBitrateConfiguration` | BPP target set |
| 3.3.4 | Constant quality | `testConstantQualityConfiguration` | Quality target set |
| 3.3.5 | Distortion methods | `testDistortionEstimationMethods` | MSE/PSNR/SSIM |
| 3.3.6 | Empty code-blocks | `testRateControlWithEmptyCodeBlocks` | No crash |

```bash
swift test --filter J2KCodecTests.J2KRateControlTests
```

---

## Phase 4: Color Transforms (Weeks 49-56)

**Goal**: Implement reversible and irreversible colour transforms.

#### TC-4.1: Colour Transforms

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 4.1.1 | Mode all cases | `testColorTransformModeAllCases` | RCT/ICT/none |
| 4.1.2 | Default config | `testDefaultConfiguration` | Sensible defaults |
| 4.1.3 | Lossless config | `testLosslessConfiguration` | RCT mode |
| 4.1.4 | Lossy config | `testLossyConfiguration` | ICT mode |
| 4.1.5 | Forward RCT | `testForwardRCTBasic` | RGB to YCbCr integer |
| 4.1.6 | Inverse RCT | `testInverseRCTBasic` | YCbCr to RGB integer |
| 4.1.7 | RCT reversibility | `testRCTReversibility` | Bit-exact round-trip |
| 4.1.8 | RCT signed values | `testRCTWithSignedValues` | Signed input handled |

70 total tests cover both RCT and ICT paths including batch operations and precision analysis.

```bash
swift test --filter J2KCodecTests.J2KColorTransformTests
```

---

## Phase 5: File Format (Weeks 57-68)

**Goal**: Implement JP2/J2K/JPX file format support.

### Test Target: J2KFileFormatTests (384 tests)

#### TC-5.1: Box Structure (Week 57-59)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 5.1.1 | Box type creation | `testBoxTypeCreation` | FourCC type |
| 5.1.2 | Standard box types | `testStandardBoxTypes` | jp2h, ihdr, colr, etc. |
| 5.1.3 | Reader standard | `testBoxReaderStandardLength` | 4-byte length |
| 5.1.4 | Reader extended | `testBoxReaderExtendedLength` | 8-byte length |
| 5.1.5 | Reader multiple | `testBoxReaderMultipleBoxes` | Sequential boxes |
| 5.1.6 | Reader invalid | `testBoxReaderInvalidLength` | Malformed rejected |
| 5.1.7 | Reader truncated | `testBoxReaderTruncatedData` | Truncation detected |

#### TC-5.2: File Writer (Week 63-65)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 5.2.1 | Grayscale JP2 | `testWriteSimpleGrayscaleImageJP2` | Valid JP2 output |
| 5.2.2 | RGB JP2 | `testWriteRGBImageJP2` | 3-component JP2 |
| 5.2.3 | J2K codestream | `testWriteJ2KCodestream` | Raw codestream |
| 5.2.4 | Round-trip write/read | `testRoundTripWriteAndRead` | Write then read match |
| 5.2.5 | Invalid dimensions | `testWriteInvalidImageDimensions` | Zero dimension rejected |

```bash
swift test --filter J2KFileFormatTests
```

---

## Phase 6: JPIP Protocol (Weeks 69-80)

**Goal**: Implement JPIP (JPEG 2000 Interactive Protocol) client and server.

### Test Target: JPIPTests (478 tests)

#### TC-6.1: Session and Request (Week 69-71)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 6.1.1 | Module linkage | `testModuleCompilationAndLinkage` | JPIP module compiles |
| 6.1.2 | Session creation | `testSessionCreation` | Session with ID |
| 6.1.3 | Server instantiation | `testServerInstantiation` | Server created |
| 6.1.4 | Basic request | `testBasicRequestCreation` | Request URL built |
| 6.1.5 | Region request | `testRegionRequest` | fsiz/rsiz/roff params |
| 6.1.6 | Resolution request | `testResolutionRequest` | Resolution level param |

#### TC-6.2: Cache Management (Week 75-77)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 6.2.1 | Cache init | `testCacheModelInitialization` | Empty cache |
| 6.2.2 | Add data bin | `testAddDataBinToCache` | Bin stored |
| 6.2.3 | Get data bin | `testGetDataBinFromCache` | Bin retrieved |
| 6.2.4 | Cache miss | `testCacheMiss` | nil returned |
| 6.2.5 | Cache hit rate | `testCacheHitRate` | Ratio calculated |
| 6.2.6 | Size limit | `testCacheSizeLimit` | Eviction on overflow |

#### TC-6.3: Server (Week 78-80)

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 6.3.1 | Server init | `testServerInitialization` | Default config |
| 6.3.2 | Custom config | `testServerWithCustomConfiguration` | Custom port/pool |
| 6.3.3 | Register image | `testRegisterImage` | Image available |
| 6.3.4 | Unregister image | `testUnregisterImage` | Image removed |
| 6.3.5 | List images | `testListRegisteredImages` | All images listed |
| 6.3.6 | Start server | `testStartServer` | Listening |

```bash
swift test --filter JPIPTests
```

---

## Phase 7: Optimisation and Features (Weeks 81-92)

**Goal**: Performance tuning, advanced encoding/decoding, extended formats.

#### TC-7.1: Encoding Pipeline

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 7.1.1 | Encode grayscale | `testEncodeMinimalGrayscaleImage` | Valid codestream |
| 7.1.2 | Encode RGB | `testEncodeRGBImage` | 3-component encode |
| 7.1.3 | Encode lossless | `testEncodeLossless` | Reversible path |
| 7.1.4 | Decomposition levels | `testEncodeWithVariousDecompositionLevels` | 1-5 levels |
| 7.1.5 | SIZ marker present | `testCodestreamContainsSIZMarker` | SIZ in output |
| 7.1.6 | Marker order | `testCodestreamMarkerOrder` | SOC-SIZ-COD-QCD order |

#### TC-7.2: Integration Pipeline

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 7.2.1 | Grayscale round-trip | `testSimpleGrayscaleRoundTrip` | Encode then decode |
| 7.2.2 | RGB round-trip | `testRGBRoundTrip` | Multi-component |
| 7.2.3 | Lossless round-trip | `testLosslessRoundTrip` | Bit-exact |
| 7.2.4 | Minimal image | `testMinimalImage` | 1x1 pixel |
| 7.2.5 | All zero | `testAllZeroImage` | Flat image |
| 7.2.6 | Odd dimensions | `testOddDimensions` | Non-even sizes |

```bash
swift test --filter J2KCodecTests.J2KEncoderPipelineTests
swift test --filter J2KCodecTests.J2KCodecIntegrationTests
```

---

## Phase 8: Production Ready (Weeks 93-100)

**Goal**: Documentation, final validation, and v1.0 release readiness.

Covered by J2KDocumentationTests and integration/stress tests in J2KCoreTests.

---

## Phase 9: HTJ2K Codec (Weeks 101-120)

**Goal**: Implement High Throughput JPEG 2000 (ISO/IEC 15444-15) codec.

### Test Target: J2KCodecTests (J2KHTCodecTests - 83 tests)

#### TC-9.1: HT Entropy Coding

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 9.1.1 | HT coding mode | `testHTCodingModeEquality` | Mode enum |
| 9.1.2 | HT pass types | `testHTCodingPassTypes` | Cleanup/SigProp/MagRef |
| 9.1.3 | MEL coder init | `testMELCoderInitialization` | MEL state |
| 9.1.4 | MEL encode flush | `testMELCoderEncodeFlush` | Clean finish |
| 9.1.5 | MEL all zeros | `testMELCoderAllZeros` | Efficient encoding |
| 9.1.6 | MEL all ones | `testMELCoderAllOnes` | Worst case |
| 9.1.7 | VLC coder init | `testVLCCoderInitialization` | VLC state |
| 9.1.8 | VLC significance | `testVLCCoderEncodeSignificancePatterns` | Pattern coding |

```bash
swift test --filter J2KCodecTests.J2KHTCodecTests
```

---

## Phase 10: Lossless Transcoding (Weeks 121-130)

**Goal**: Lossless transcoding between JPEG 2000 Part 1 and Part 15.

### Test Target: J2KCodecTests (J2KTranscoderTests - 35 tests)

#### TC-10.1: Transcoding Engine

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 10.1.1 | Direction values | `testTranscodingDirectionRawValues` | Forward/reverse |
| 10.1.2 | Stage all cases | `testTranscodingStageAllCases` | All stages |
| 10.1.3 | Coefficients create | `testCodeBlockCoefficientsCreation` | Coefficient storage |
| 10.1.4 | Tile coefficients | `testTileCoefficientsCreation` | Tile-level storage |
| 10.1.5 | Validation | `testTranscodingCoefficientsValidation` | Valid input accepted |
| 10.1.6 | Invalid dimensions | `testTranscodingCoefficientsValidationInvalidDimensions` | Rejected |

```bash
swift test --filter J2KCodecTests.J2KTranscoderTests
```

---

## Phase 11: Enhanced JPIP with HTJ2K (v1.4.0)

**Goal**: Enhanced JPIP support for HTJ2K content.

Tests in `JPIPHTJ2KSupportTests` cover HTJ2K format detection, capability signalling, enhanced server API, codec integration for data bin streaming, and on-the-fly transcoding.

```bash
swift test --filter JPIPTests.JPIPHTJ2KSupportTests
```

---

## Phase 12: Performance and Cross-Platform (v1.5.0)

**Goal**: HTJ2K SIMD optimisation, WebSocket JPIP, server push, cross-platform.

| Area | Test Class | Target |
|------|-----------|--------|
| Adaptive block size | `J2KAdaptiveBlockSizeTests` | J2KCodecTests |
| Neon entropy | `J2KNeonEntropyTests` | J2KCodecTests |
| SSE entropy | `J2KSSEEntropyTests` | J2KCodecTests |
| WebSocket transport | `JPIPWebSocketTests` | JPIPTests |
| Server push | `JPIPServerPushTests` | JPIPTests |
| Session persistence | `JPIPSessionPersistenceTests` | JPIPTests |
| Bandwidth delivery | `JPIPBandwidthAwareDeliveryTests` | JPIPTests |
| Client cache | `JPIPClientCacheManagerTests` | JPIPTests |
| Windows platform | `J2KWindowsPlatformTests` | J2KCoreTests |
| Swift 6.2 compat | `J2KSwift62CompatibilityTests` | J2KCoreTests |
| Cross-platform | `J2KCrossPlatformValidationTests` | J2KCoreTests |

```bash
swift test --filter JPIPTests
swift test --filter J2KCoreTests.J2KCrossPlatformValidationTests
```

---

## Phase 13: Part 2 Extensions (v1.6.0)

**Goal**: ISO/IEC 15444-2 extensions.

| Area | Test Class | Target |
|------|-----------|--------|
| DC offset | `J2KDCOffsetTests` | J2KCodecTests |
| Arbitrary wavelets | `J2KArbitraryWaveletTests` | J2KCodecTests |
| MCT | `J2KMCTTests` | J2KCodecTests |
| NLT | `J2KNonLinearTransformTests` | J2KCodecTests |
| TCQ | `J2KTrellisQuantizerTests` | J2KCodecTests |
| Extended ROI | `J2KExtendedROITests` | J2KCodecTests |
| Perceptual | `J2KPerceptualEncoderTests` | J2KCodecTests |
| Visual masking | `J2KVisualMaskingTests` | J2KCodecTests |
| Part 2 conformance | `J2KPart2ConformanceHardeningTests` | J2KComplianceTests |

```bash
swift test --filter J2KCodecTests.J2KDCOffsetTests
swift test --filter J2KCodecTests.J2KArbitraryWaveletTests
swift test --filter J2KCodecTests.J2KMCTTests
swift test --filter J2KCodecTests.J2KTrellisQuantizerTests
```

---

## Phase 14: Metal GPU Acceleration (v1.7.0)

**Goal**: Metal compute shader acceleration.

### Test Target: J2KMetalTests (314 tests)

| Area | Test Class | Tests |
|------|-----------|------:|
| Device | `J2KMetalDeviceTests` | Various |
| DWT | `J2KMetalDWTTests` | 100+ |
| Colour | `J2KMetalColorTransformTests` | Various |
| MCT | `J2KMetalMCTTests` | Various |
| Quantization | `J2KMetalQuantizerTests` | Various |
| ROI | `J2KMetalROITests` | Various |
| Performance | `J2KMetalPerformanceTests` | Various |
| GPU refactoring | `J2KMetalGPUComputeRefactoringTests` | 63 |

```bash
swift test --filter J2KMetalTests
```

---

## Phase 15: Motion JPEG 2000 (v1.8.0)

**Goal**: MJ2 file format, creation, extraction, playback.

| Area | Test Class | Target |
|------|-----------|--------|
| File format | `MJ2FileFormatTests` | J2KFileFormatTests |
| Creator | `MJ2CreatorTests` | J2KFileFormatTests |
| Extractor | `MJ2ExtractorTests` | J2KFileFormatTests |
| Player | `MJ2PlayerTests` | J2KFileFormatTests |
| Integration | `MJ2IntegrationTests` | J2KFileFormatTests |
| Conformance | `MJ2ConformanceTests` | J2KFileFormatTests |
| VideoToolbox | `MJ2VideoToolboxTests` | J2KCodecTests |
| Cross-platform | `MJ2CrossPlatformTests` | J2KCodecTests |
| Performance | `MJ2PerformanceTests` | J2KCodecTests |

```bash
swift test --filter J2KFileFormatTests
```

---

## Phase 16: JP3D Volumetric (v1.9.0)

**Goal**: ISO/IEC 15444-10 volumetric JPEG 2000.

### Test Target: JP3DTests (405 tests)

| Area | Test Class | Tests |
|------|-----------|------:|
| Core types | `JP3DCoreTypeTests` | Various |
| 3D wavelets | `JP3DWaveletTests` | 100+ |
| Encoder | `JP3DEncoderTests` | Various |
| Decoder | `JP3DDecoderTests` | Various |
| Integration | `JP3DIntegrationTests` | 49 |
| HTJ2K 3D | `JP3DHTJ2KTests` | Various |
| Streaming | `JP3DStreamingTests` | Various |
| Compliance | `JP3DComplianceTests` | 100+ |

```bash
swift test --filter JP3DTests
```

---

## Phase 17: v2.0 Refactoring (Weeks 236-295)

**Goal**: Swift 6.2 concurrency, hardware acceleration, ISO Part 4 conformance, OpenJPEG interoperability, CLI tools, documentation, integration testing.

### Sub-phase 17a: Swift 6.2 Concurrency

| Area | Test Class | Target |
|------|-----------|--------|
| Swift 6.2 compat | `J2KSwift62CompatibilityTests` | J2KCoreTests |
| Concurrency perf | `J2KConcurrencyPerformanceTests` | J2KCoreTests |
| Module concurrency | `J2KModuleConcurrencyTests` | J2KCodecTests |

### Sub-phase 17b: Apple Silicon Optimisation

| Area | Test Class | Target |
|------|-----------|--------|
| Neon SIMD | `J2KNeonSIMDTests` | J2KAccelerateTests |
| ARM64 platform | `J2KARM64PlatformTests` | J2KAccelerateTests |
| vImage integration | `J2KVImageIntegrationTests` | J2KAccelerateTests |
| Perceptual | `J2KAcceleratedPerceptualTests` | J2KAccelerateTests |
| HT SIMD | `J2KHTSIMDTests` | J2KAccelerateTests |

### Sub-phase 17c: Intel x86-64 Optimisation

| Area | Test Class | Target |
|------|-----------|--------|
| SSE transforms | `J2KSSETransformTests` | J2KAccelerateTests |
| x86 platform | `J2KAccelerateX86Tests` | J2KAccelerateTests |

### Sub-phase 17d: ISO Part 4 Conformance

| Area | Test Class | Tests |
|------|-----------|------:|
| Part 1 | `J2KPart1ConformanceTests` | ~50 |
| Part 2 hardening | `J2KPart2ConformanceHardeningTests` | ~30 |
| Part 3/10 | `J2KPart3Part10ConformanceTests` | ~50 |
| Part 15 | `J2KPart15IntegratedConformanceTests` | ~50 |
| Part 4 final | `J2KPart4ConformanceFinalTests` | ~41 |

```bash
swift test --filter J2KComplianceTests
```

### Sub-phase 17e: OpenJPEG Interoperability

142 tests in `OpenJPEGInteropTests` covering cross-validation with OpenJPEG tools.

```bash
swift test --filter J2KInteroperabilityTests
```

### Sub-phase 17f: CLI Tools

12 tests in `J2KCLITests` covering the `j2k` command-line tool.

```bash
swift test --filter J2KCLITests
```

### Sub-phase 17g: Integration Testing

| Area | Test Class | Tests |
|------|-----------|------:|
| End-to-end | `J2KEndToEndPipelineTests` | 69 |
| Regression | `J2KRegressionTests` | 67 |
| Stress | `J2KExtendedStressTests` | 58 |

```bash
swift test --filter J2KCodecTests.J2KEndToEndPipelineTests
swift test --filter J2KCoreTests.J2KRegressionTests
swift test --filter J2KCoreTests.J2KExtendedStressTests
```

### Sub-phase 17h: Performance Validation

154 tests in PerformanceTests covering platform benchmarks, SIMD utilisation, memory bandwidth, power efficiency, and OpenJPEG comparison.

```bash
swift test --filter PerformanceTests
```

---

## Phase 18: GUI Testing Application (v2.1)

**Goal**: macOS SwiftUI test application for interactive testing.

### Test Target: J2KTestAppTests (309 tests)

#### TC-18.1: Application Architecture (Week 296-298)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.1.1 | TestCategory enum | Model | 7 categories exist |
| 18.1.2 | TestStatus enum | Model | All statuses |
| 18.1.3 | TestResult | Model | Result storage |
| 18.1.4 | AppSettings Codable | Model | Settings persist |
| 18.1.5 | TestSession actor | Model | Thread-safe session |
| 18.1.6 | PipelineStage | Model | 6 stages |
| 18.1.7 | MainViewModel | ViewModel | Observable state |

#### TC-18.2: Encoding/Decoding Screens (Week 299-301)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.2.1 | EncodeConfiguration | Model | Preset enum |
| 18.2.2 | ProgressionOrderChoice | Model | 5 orders |
| 18.2.3 | WaveletTypeChoice | Model | 4 wavelet types |
| 18.2.4 | EncodeViewModel | ViewModel | Observable encoding |
| 18.2.5 | DecodeViewModel | ViewModel | Observable decoding |
| 18.2.6 | RoundTripMetrics | Model | PSNR/SSIM/MSE |

#### TC-18.3: Conformance Screens (Week 302-304)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.3.1 | ConformancePart | Model | 4 parts |
| 18.3.2 | ConformanceReport | Model | Pass rate/banner |
| 18.3.3 | ConformanceViewModel | ViewModel | Matrix grid state |
| 18.3.4 | InteropViewModel | ViewModel | Side-by-side compare |
| 18.3.5 | ValidationViewModel | ViewModel | 3 validation modes |

#### TC-18.4: Performance Screens (Week 305-307)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.4.1 | BenchmarkImageSizeChoice | Model | 6 sizes |
| 18.4.2 | PerformanceViewModel | ViewModel | Regression detection |
| 18.4.3 | GPUTestViewModel | ViewModel | Metal availability |
| 18.4.4 | SIMDTestViewModel | ViewModel | Platform detection |

#### TC-18.5: Streaming Screens (Week 308-310)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.5.1 | JPIPSessionStatus | Model | 5 states |
| 18.5.2 | JPIPViewModel | ViewModel | Connect/load |
| 18.5.3 | VolumetricTestViewModel | ViewModel | Volume slice view |
| 18.5.4 | MJ2TestViewModel | ViewModel | Playback control |

#### TC-18.6: Reporting (Week 311-313)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.6.1 | ReportViewModel | ViewModel | Trend/heatmap |
| 18.6.2 | PlaylistViewModel | ViewModel | Preset/custom |
| 18.6.3 | HeadlessRunner | Model | CLI test runner |

#### TC-18.7: GUI Polish (Week 314-315)

| ID | Test Case | Area | Expected Result |
|----|-----------|------|-----------------|
| 18.7.1 | J2KDesignSystem | Model | Spacing tokens |
| 18.7.2 | WindowPreferences | Model | UserDefaults |
| 18.7.3 | AboutViewModel | Model | Version info |
| 18.7.4 | AccessibilityIdentifiers | Model | ID constants |
| 18.7.5 | ErrorStateModel | Model | Factory methods |

```bash
swift test --filter J2KTestAppTests
```

---

## Phase 19: Multi-Spectral JP3D and Vulkan (v2.2.0)

**Goal**: Multi-spectral volumetric imaging and Vulkan GPU acceleration.

#### TC-19.1: Multi-Spectral JP3D (Week 316-321)

33 tests in `JP3DMultiSpectralTests` covering spectral band definitions, mappings (visible/NIR/hyperspectral), multi-spectral volume creation, encoding, decoding, and spectral analysis (NDVI/NDWI/NDBI).

```bash
swift test --filter JP3DTests.JP3DMultiSpectralTests
```

#### TC-19.2: Vulkan JP3D Acceleration (Week 322-324)

15 tests in `J2KVulkanJP3DDWTTests` covering GPU 3D wavelet transforms, auto backend selection (GPU/CPU), and statistics tracking.

```bash
swift test --filter J2KVulkanTests.J2KVulkanJP3DDWTTests
```

#### TC-19.3: JPEG XS Types (Week 325)

21 tests in `J2KXSTypesTests` covering profile/level enums, configuration structs, and capability queries.

```bash
swift test --filter J2KCoreTests.J2KXSTypesTests
```

---

## Phase 20: JPEG XS Core Codec (v2.3.0)

**Goal**: JPEG XS (ISO/IEC 21122) low-latency codec implementation.

### Test Target: J2KXSTests (52 tests)

#### TC-20.1: Image Types and API

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 20.1.1 | Capabilities available | `testCapabilitiesIsAvailableTrue` | v2.3.0 available |
| 20.1.2 | Supported profiles | `testCapabilitiesSupportedProfiles` | All 3 profiles |
| 20.1.3 | Version string | `testCapabilitiesVersion` | "2.3.0" |
| 20.1.4 | Error equality | `testErrorEquality` | Equatable errors |
| 20.1.5 | Encode result | `testEncodeResultProperties` | Size/slice count |
| 20.1.6 | Decode result | `testDecodeResultProperties` | Decoded image |

#### TC-20.2: DWT Engine

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 20.2.1 | Forward DWT | `testDWTEngineForwardSmallSlice` | Haar lifting |
| 20.2.2 | Inverse round-trip | `testDWTEngineInverseRoundTrip` | Perfect reconstruction |
| 20.2.3 | Orientation cases | `testDWTOrientationAllCases` | All orientations |
| 20.2.4 | Orientation labels | `testDWTOrientationLabels` | Human-readable |
| 20.2.5 | Decomposition result | `testDWTEngineDecompositionResultApproximation` | Approximation band |
| 20.2.6 | Reset statistics | `testDWTEngineResetStatistics` | Counters zeroed |
| 20.2.7 | Sample mismatch | `testDWTEngineSampleCountMismatch` | Error thrown |
| 20.2.8 | Too small | `testDWTEngineTooSmallForLevels` | Error thrown |

#### TC-20.3: Encoder/Decoder

| ID | Test Case | Function | Expected Result |
|----|-----------|----------|-----------------|
| 20.3.1 | Encode small RGB | `testEncoderEncodeSmallRGBImage` | Valid codestream |
| 20.3.2 | Plane mismatch | `testEncoderPlaneMismatchThrows` | Error thrown |
| 20.3.3 | Unsupported profile | `testEncoderUnsupportedProfileThrows` | Error thrown |
| 20.3.4 | Decode small | `testDecoderDecodeSmallImage` | Decoded image |
| 20.3.5 | Empty codestream | `testDecoderEmptyCodestreamThrows` | Error thrown |

```bash
swift test --filter J2KXSTests
```

---

## Performance Targets

| Metric | Platform | Target |
|--------|----------|--------|
| Encoding throughput | Apple Silicon (M1+) | >= 2x OpenJPEG |
| Decoding throughput | Apple Silicon (M1+) | >= 2x OpenJPEG |
| Encoding throughput | Intel x86-64 | >= 1.5x OpenJPEG |
| Decoding throughput | Intel x86-64 | >= 1.5x OpenJPEG |
| Metal GPU speedup | DWT/colour/quant | >= 3x vs CPU |
| SIMD utilisation | Neon/SSE/AVX | >= 85% |
| Memory overhead | vs OpenJPEG | <= 1.2x |
| HTJ2K encoding | vs Part 1 | >= 5x faster |
| HTJ2K decoding | vs Part 1 | >= 5x faster |

```bash
swift test --filter PerformanceTests.PerformanceValidationTests
swift test --filter J2KAccelerateTests.J2KAccelerateBenchmarks
```

---

## Conformance Matrix

| Standard Part | Coverage | Test Class |
|---------------|----------|------------|
| Part 1 (Core) | Full | `J2KPart1ConformanceTests` |
| Part 2 (Extensions) | Full | `J2KPart2ConformanceHardeningTests` |
| Part 3 (Motion) | Full | `J2KPart3Part10ConformanceTests`, `MJ2ConformanceTests` |
| Part 4 (Conformance) | Full | `J2KPart4ConformanceFinalTests` |
| Part 10 (JP3D) | Full | `JP3DComplianceTests` |
| Part 15 (HTJ2K) | Full | `J2KPart15IntegratedConformanceTests` |

```bash
swift test --filter J2KComplianceTests
```

---

## Known Limitations

1. **Multi-component decoding**: J2KDecoder returns only the first component for multi-component images.
2. **Decomposition levels**: Non-tiled images with >= 5 decomposition levels on >= 256x256 images may fail with "Missing LL subband". Use <= 2 decomposition levels for >= 128x128 or enable tiling.
3. **Metal GPU**: Metal tests require macOS with compatible GPU; tests are skipped on CI without Metal.
4. **Vulkan GPU**: Vulkan backend falls back to CPU on platforms without Vulkan support.
5. **JPEG XS**: Current implementation uses Haar wavelet only.
6. **OpenJPEG interop**: Requires `opj_compress`/`opj_decompress` in PATH for interoperability tests.

---

## Glossary

| Term | Definition |
|------|------------|
| **EBCOT** | Embedded Block Coding with Optimised Truncation |
| **MQ-coder** | Binary arithmetic entropy coder used in JPEG 2000 Part 1 |
| **DWT** | Discrete Wavelet Transform |
| **5/3 filter** | Le Gall 5/3 reversible wavelet filter for lossless coding |
| **9/7 filter** | CDF 9/7 irreversible wavelet filter for lossy coding |
| **RCT** | Reversible Colour Transform (integer YCbCr) |
| **ICT** | Irreversible Colour Transform (float YCbCr) |
| **ROI** | Region of Interest |
| **HTJ2K** | High Throughput JPEG 2000 (Part 15) |
| **FBCOT** | Fast Block Coder with Optimised Truncation |
| **MEL** | Modular Embedded Lossless coding in HTJ2K |
| **VLC** | Variable Length Coding in HTJ2K |
| **JPIP** | JPEG 2000 Interactive Protocol |
| **JP2** | JPEG 2000 Part 1 file format |
| **MJ2** | Motion JPEG 2000 (Part 3) |
| **JP3D** | JPEG 2000 Part 10 (volumetric 3D) |
| **MCT** | Multi-Component Transform |
| **NLT** | Non-Linear Point Transform |
| **TCQ** | Trellis Coded Quantization |
| **ADS** | Arbitrary Decomposition Structure |
| **PSNR** | Peak Signal-to-Noise Ratio (dB) |
| **SSIM** | Structural Similarity Index Measure |
| **MSE** | Mean Squared Error |
| **SIMD** | Single Instruction Multiple Data |
| **Neon** | ARM Advanced SIMD instruction set |
| **JPEG XS** | ISO/IEC 21122 low-latency codec |

---

*Generated for J2KSwift v2.3.0 - Last updated: February 2026*
