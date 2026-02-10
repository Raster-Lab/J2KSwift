# J2KSwift v1.1 Development Roadmap

**Target Release**: 8-12 weeks from v1.0.0 (April-May 2026)  
**Primary Goal**: Complete high-level codec integration and make J2KSwift fully functional

## Overview

Version 1.0.0 provides a solid architectural foundation with all individual components implemented and tested. Version 1.1 will connect these components into complete encoding and decoding pipelines, making J2KSwift a fully functional JPEG 2000 codec.

## Success Criteria

By the end of v1.1 development:
- ✅ `J2KEncoder.encode()` fully functional
- ✅ `J2KDecoder.decode()` fully functional
- ✅ Hardware acceleration active (vDSP integration)
- ✅ JPIP streaming operations working
- ✅ 100% test pass rate (fix bit-plane decoder bug)
- ✅ End-to-end integration tests passing
- ✅ Performance within 80% of OpenJPEG
- ✅ Complete encode→decode round-trip working

## Phase 1: Fix Critical Issues (Weeks 1-2)

### Priority 1: Bit-Plane Decoder Bug (Week 1)
**Status**: Cleanup pass bug fixed; 5 tests remaining (bypass mode and predictable termination)

**Completed**:
- [x] Identify exact point of divergence (deferred vs immediate state updates in cleanup pass)
- [x] Fix synchronization bug: use immediate state updates per ISO/IEC 15444-1
- [x] Add passSegmentLengths to J2KCodeBlock for predictable termination support
- [x] Update decoder to handle per-pass segment decoding

**Fixed Tests** (3 of 6):
- testBitPlaneDecoderRoundTripDifferentSubbands (HH subband context fix)
- testCodeBlockRoundTripAllSubbands (all subbands, various sizes)
- testCodeBlockRoundTripLargeBlock (64x64, default options)

**Remaining** (5 tests - deeper issues):
- testMinimalBlock32x32 (bypass mode, dense data)
- testMinimalBlock64x64 (bypass mode, dense data)
- testCodeBlockBypassLargeBlock (bypass mode, 64x64)
- test64x64WithoutBypass (predictable termination, 64x64)
- testProgressiveBlockSizes (bypass mode, progressive sizes)

**Root Causes of Remaining Failures**:
- Bypass mode: MQ coder's byte I/O state (c/ct/buffer) is shared between
  MQ and bypass coding. For large blocks with dense data, the bypass
  transition causes desynchronization between encoder and decoder.
- Predictable termination: `finishPredictable()` produces a termination
  sequence that the standard MQ decoder cannot properly re-initialize from
  at 64x64 scale.

**Estimated Effort**: 3-5 days  
**Dependencies**: None  
**Risk**: Medium (complex bug, well-documented)

### Priority 2: Code Review & Cleanup (Week 2)
**Tasks**:
- [ ] Review all public APIs for consistency
- [ ] Remove debug code and TODOs
- [ ] Ensure all placeholder methods have clear error messages
- [ ] Update documentation for component usage patterns
- [ ] Add missing unit tests
- [ ] Run comprehensive SwiftLint review

**Estimated Effort**: 2-3 days  
**Dependencies**: None  
**Risk**: Low

## Phase 2: High-Level Encoder Implementation (Weeks 3-5)

### Week 3: Encoder Pipeline Architecture

**Goal**: Design and implement the encoding pipeline structure

**Tasks**:
- [x] Design encoder pipeline architecture
  - Input: `J2KImage`
  - Output: `Data` (JPEG 2000 codestream)
  - Pipeline stages: preprocessing → color transform → wavelet transform → quantization → entropy coding → rate control → codestream generation
- [x] Implement encoder pipeline (`EncoderPipeline` struct)
- [x] Add progress reporting callbacks (`EncoderProgressUpdate`, `EncodingStage`)
- [x] Design error handling strategy (propagate `J2KError` from each stage)
- [x] Add `J2KEncoder(encodingConfiguration:)` initializer for detailed configuration
- [ ] Add cancellation support (async/await) — deferred to Week 4

**Testing**:
- [x] Unit tests for pipeline stages (14 tests)
- [x] Progress callback tests
- [x] Edge case tests (1×1, odd dimensions, all-zero data)
- [ ] Cancellation tests — deferred

### Week 4: Encoder Component Integration

**Goal**: Connect all encoding components

**Tasks**:
- [ ] Implement preprocessing stage
  - Tile splitting
  - Component separation
  - Input validation
- [ ] Integrate color transform
  - Select RCT or ICT based on configuration
  - Apply to all components
- [ ] Integrate wavelet transform
  - Apply DWT to each tile-component
  - Multi-level decomposition
  - Subband generation
- [ ] Integrate quantization
  - Apply to wavelet coefficients
  - ROI processing if configured
- [ ] Integrate entropy coding
  - Code-block formation
  - Bit-plane coding
  - Packet generation
- [ ] Integrate rate control
  - Layer formation
  - PCRD-opt algorithm
  - Target bitrate enforcement

**Code Integration**:
```swift
private func encodeInternal(_ image: J2KImage) async throws -> Data {
    // 1. Preprocessing
    let tiles = splitIntoTiles(image)
    
    // 2. Color transform
    let transformed = try applyColorTransform(tiles)
    
    // 3. Wavelet transform
    let waveletData = try await applyWaveletTransform(transformed)
    
    // 4. Quantization
    let quantized = try applyQuantization(waveletData)
    
    // 5. Entropy coding
    let coded = try applyEntropyCoding(quantized)
    
    // 6. Rate control & layer formation
    let layers = try formLayers(coded)
    
    // 7. File format
    return try encodeToFileFormat(layers)
}
```

**Testing**:
- [ ] Component integration tests
- [ ] Round-trip tests (encode → decode)
- [ ] Various image sizes and configurations
- [ ] Edge cases (1x1, very large, odd dimensions)

### Week 5: Encoder Configuration & Presets

**Goal**: Expose full configuration options

**Tasks**:
- [ ] Implement unified configuration type
  - Merge `J2KConfiguration`, `J2KEncodingConfiguration`, `J2KEncodingPreset`
  - Add validation
  - Add smart defaults
- [ ] Implement encoding presets
  - `.lossless`: RCT + 5/3 filter
  - `.fast`: Low complexity settings
  - `.balanced`: Good quality/speed tradeoff
  - `.quality`: Best quality settings
  - `.custom`: Full control
- [ ] Add configuration builder pattern
- [ ] Implement configuration validation
- [ ] Add configuration serialization

**Code Example**:
```swift
public struct EncoderConfiguration: Sendable {
    public var quality: Quality
    public var compressionMode: CompressionMode
    public var tileSize: TileSize
    public var progressionOrder: ProgressionOrder
    public var layers: Int
    public var decompositionLevels: Int
    
    public enum Quality {
        case lossless
        case high // PSNR > 45 dB
        case medium // PSNR > 40 dB
        case low // PSNR > 35 dB
        case custom(targetPSNR: Double)
        case targetBitrate(Double) // bpp
    }
    
    public static let lossless = EncoderConfiguration(...)
    public static let fast = EncoderConfiguration(...)
    public static let balanced = EncoderConfiguration(...)
    public static let quality = EncoderConfiguration(...)
}
```

**Testing**:
- [ ] Configuration validation tests
- [ ] Preset tests
- [ ] Quality target tests
- [ ] Bitrate target tests

## Phase 3: High-Level Decoder Implementation (Weeks 6-8)

### Week 6: Decoder Pipeline Architecture

**Goal**: Design and implement the decoding pipeline

**Tasks**:
- [ ] Design decoder pipeline architecture
  - Input: `Data` (JP2 file)
  - Output: `J2KImage`
  - Pipeline stages: file parsing → entropy decoding → dequantization → inverse transform
- [ ] Implement decoder state machine
- [ ] Add progress reporting
- [ ] Design caching strategy
- [ ] Add partial decoding support
- [ ] Add resolution/quality progressive decoding

**Code Structure**:
```swift
public actor J2KDecoder {
    public struct DecodingOptions: Sendable {
        var region: CGRect?
        var maxResolutionLevel: Int?
        var maxQualityLayers: Int?
        var components: [Int]?
    }
    
    public func decode(
        _ data: Data,
        options: DecodingOptions = .default,
        progress: ((Double) -> Void)? = nil
    ) async throws -> J2KImage {
        // Implementation
    }
}
```

**Testing**:
- [ ] Pipeline stage tests
- [ ] Partial decoding tests
- [ ] Progressive decoding tests

### Week 7: Decoder Component Integration

**Goal**: Connect all decoding components

**Tasks**:
- [ ] Implement file format parsing
  - Box structure parsing
  - Marker segment parsing
  - Codestream extraction
  - Metadata extraction
- [ ] Integrate entropy decoding
  - Packet parsing
  - Bit-plane decoding
  - Code-block reconstruction
- [ ] Integrate dequantization
  - Step size application
  - ROI decoding
- [ ] Integrate inverse wavelet transform
  - Multi-level IDWT
  - Tile reconstruction
  - Boundary handling
- [ ] Integrate inverse color transform
  - YCbCr → RGB
  - Component composition
- [ ] Image reconstruction
  - Tile assembly
  - Final image formation

**Code Integration**:
```swift
private func decodeInternal(_ data: Data, options: DecodingOptions) async throws -> J2KImage {
    // 1. Parse file format
    let codestream = try parseFileFormat(data)
    
    // 2. Parse codestream
    let packets = try parseCodestream(codestream)
    
    // 3. Entropy decoding
    let coefficients = try await decodeEntropy(packets)
    
    // 4. Dequantization
    let dequantized = try applyDequantization(coefficients)
    
    // 5. Inverse wavelet transform
    let spatial = try applyInverseWaveletTransform(dequantized)
    
    // 6. Inverse color transform
    let rgb = try applyInverseColorTransform(spatial)
    
    // 7. Reconstruct image
    return try reconstructImage(rgb)
}
```

**Testing**:
- [ ] Component integration tests
- [ ] Round-trip tests (encode → decode → compare)
- [ ] Various file formats (JP2, J2K)
- [ ] Corrupted data handling

### Week 8: Advanced Decoding Features

**Goal**: Implement progressive and partial decoding

**Tasks**:
- [ ] Implement region-of-interest decoding
  - Spatial window extraction
  - Minimal tile decoding
  - Coefficient pruning
- [ ] Implement resolution-progressive decoding
  - Multi-resolution pyramid
  - Early stopping after N levels
  - Memory optimization
- [ ] Implement quality-progressive decoding
  - Layer-by-layer refinement
  - Quality target stopping
- [ ] Implement incremental decoding
  - Stream-based decoding
  - Partial data handling
  - Resume support

**Testing**:
- [ ] ROI decoding accuracy tests
- [ ] Progressive decoding tests
- [ ] Memory usage tests
- [ ] Incremental decoding tests

## Phase 4: Hardware Acceleration (Weeks 9-10)

### Week 9: vDSP Integration

**Goal**: Implement Accelerate framework optimizations

**Tasks**:
- [ ] Implement vDSP-based 1D DWT
  - Forward transform
  - Inverse transform
  - Benchmark vs software implementation
- [ ] Implement vDSP-based 2D DWT
  - Separable transforms
  - Multi-level decomposition
  - Tile processing
- [ ] Implement vDSP color transforms
  - RGB → YCbCr (RCT/ICT)
  - YCbCr → RGB
  - SIMD optimizations
- [ ] Add platform detection
  - Automatic vDSP usage on Apple platforms
  - Graceful fallback for non-Apple platforms

**Code Structure**:
```swift
// Sources/J2KAccelerate/J2KDWTAccelerated.swift

#if canImport(Accelerate)
import Accelerate

public struct J2KDWTAccelerated {
    public static func forwardTransform1D(
        _ input: [Float],
        filter: J2KWaveletFilter
    ) throws -> [Float] {
        // vDSP implementation
        var output = [Float](repeating: 0, count: input.count)
        // Use vDSP_conv, vDSP_vdiv, etc.
        return output
    }
}
#else
// Software fallback
#endif
```

**Testing**:
- [ ] Correctness tests (compare with software)
- [ ] Performance benchmarks
- [ ] Cross-platform tests

### Week 10: Performance Optimization

**Goal**: Optimize codec performance

**Tasks**:
- [ ] Profile encoder pipeline
  - Identify hot spots
  - Optimize critical paths
  - Reduce memory allocations
- [ ] Profile decoder pipeline
  - Optimize packet parsing
  - Reduce copying
  - Cache optimization
- [ ] Implement multi-threading
  - Tile-level parallelism
  - Code-block parallel encoding
  - Thread pool optimization
- [ ] Memory optimization
  - Reduce peak memory usage
  - Implement streaming where possible
  - Buffer reuse

**Performance Targets**:
- Encoding: > 10 MP/s (megapixels per second)
- Decoding: > 15 MP/s
- Memory: < 2x compressed file size
- Thread scaling: > 80% efficiency up to 8 cores

**Testing**:
- [ ] Performance regression tests
- [ ] Memory usage tests
- [ ] Thread scaling tests
- [ ] Large image tests (4K, 8K)

## Phase 5: JPIP Integration (Weeks 11-12)

### Week 11: JPIP Client Implementation

**Goal**: Implement functional JPIP client

**Tasks**:
- [ ] Implement `requestImage()` method
  - Full image streaming
  - Progressive quality
  - Integration with decoder
- [ ] Implement `requestRegion()` method
  - Spatial window requests
  - ROI streaming
  - Efficient precinct selection
- [ ] Implement `requestProgressive()` method
  - Layer-by-layer streaming
  - Quality progression
- [ ] Implement `requestResolution()` method
  - Resolution-level streaming
  - Pyramid decoding
- [ ] Implement `requestComponents()` method
  - Component selection
  - Multi-component streaming

**Code Integration**:
```swift
public actor JPIPClient {
    public func requestImage(
        target: String,
        maxBytes: Int? = nil,
        progress: ((Double) -> Void)? = nil
    ) async throws -> J2KImage {
        // Request codestream data
        let data = try await requestCodestream(target, maxBytes: maxBytes)
        
        // Update cache
        await cache.add(data)
        
        // Decode incrementally
        let decoder = J2KDecoder()
        return try await decoder.decode(data, progress: progress)
    }
}
```

**Testing**:
- [ ] Client request tests
- [ ] Progressive streaming tests
- [ ] Cache correctness tests
- [ ] Network error handling tests

### Week 12: JPIP Server & Integration

**Goal**: Complete JPIP implementation

**Tasks**:
- [ ] Implement JPIP server request handling
  - Parse JPIP requests
  - Generate appropriate responses
  - Precinct selection
  - Bandwidth management
- [ ] Implement server cache model
  - Track client cache state
  - Optimize data transmission
  - Avoid redundant sends
- [ ] Add client-server integration tests
  - End-to-end streaming tests
  - Multi-client tests
  - Error recovery tests
- [ ] Optimize JPIP performance
  - Request prioritization
  - Response streaming
  - Connection pooling

**Testing**:
- [ ] Server functionality tests
- [ ] Client-server integration tests
- [ ] Load tests (multiple clients)
- [ ] Bandwidth throttling tests

## Testing & Quality Assurance

### Integration Testing
Create comprehensive integration tests covering:
- [ ] Basic encode → decode round-trip
- [ ] Lossless compression (RCT + 5/3)
- [ ] Lossy compression (ICT + 9/7)
- [ ] Various image sizes (1x1 to 8K)
- [ ] Various bit depths (8, 10, 12, 16 bits)
- [ ] Multiple components (grayscale, RGB, RGBA, CMYK)
- [ ] Tiled images
- [ ] ROI encoding/decoding
- [ ] Progressive decoding
- [ ] Partial decoding
- [ ] JPIP streaming

### Conformance Testing
- [ ] Test against ISO JPEG 2000 test suite (if available)
- [ ] Compare against reference implementations (OpenJPEG)
- [ ] Interoperability tests
- [ ] Standards compliance validation

### Performance Testing
- [ ] Encoding speed benchmarks
- [ ] Decoding speed benchmarks
- [ ] Memory usage profiling
- [ ] Thread scaling tests
- [ ] Large dataset tests

### Regression Testing
- [ ] Ensure v1.0 component tests still pass
- [ ] No performance regressions
- [ ] API compatibility maintained

## Documentation Updates

- [ ] Update README.md with functional examples
- [ ] Update GETTING_STARTED.md with complete workflows
- [ ] Update TUTORIAL_ENCODING.md with high-level APIs
- [ ] Update TUTORIAL_DECODING.md with high-level APIs
- [ ] Create JPIP_TUTORIAL.md for streaming usage
- [ ] Update API_REFERENCE.md with new methods
- [ ] Create MIGRATION_v1.0_to_v1.1.md guide
- [ ] Add more code examples throughout

## API Stability

Maintain backward compatibility with v1.0:
- All v1.0 public APIs remain available
- No breaking changes to component APIs
- Deprecate redundant APIs with clear migration path
- Add new high-level APIs without changing existing ones

## Release Process

### v1.1.0-beta.1 (Week 8)
- High-level codec integration complete
- Basic functionality working
- Beta testing with early adopters

### v1.1.0-beta.2 (Week 10)
- Hardware acceleration complete
- Performance optimizations applied
- Bug fixes from beta.1 feedback

### v1.1.0-rc.1 (Week 11)
- JPIP integration complete
- All features implemented
- Final testing and bug fixes

### v1.1.0 (Week 12)
- Release candidate promoted to stable
- Documentation complete
- Release announcement

## Risk Mitigation

### Technical Risks
- **Integration complexity**: Mitigate with incremental integration and testing
- **Performance issues**: Profile early and optimize continuously
- **Bit-plane decoder bug**: Allocate dedicated time for investigation
- **Platform differences**: Test on all supported platforms regularly

### Schedule Risks
- **Underestimation**: Phases have buffer time built in
- **Dependencies**: Work can proceed in parallel where possible
- **Scope creep**: Stick to defined v1.1 scope, defer new features to v1.2

## Success Metrics

v1.1 will be considered successful when:
- ✅ All planned features implemented
- ✅ 100% test pass rate (including bit-plane decoder fix)
- ✅ Performance within 80% of OpenJPEG
- ✅ Zero critical bugs
- ✅ Complete documentation
- ✅ Positive community feedback
- ✅ Production-ready for real-world use

---

**Document Version**: 1.0  
**Created**: 2026-02-07  
**Target Start**: Week of 2026-02-14  
**Target Completion**: Week of 2026-05-01  
**Total Duration**: 12 weeks
