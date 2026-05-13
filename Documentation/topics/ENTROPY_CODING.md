# JPEG 2000 Entropy Coding Implementation

## Overview

This document describes the entropy coding implementation in J2KSwift, which forms the core of the JPEG 2000 compression system. The implementation follows the EBCOT (Embedded Block Coding with Optimized Truncation) algorithm specified in ISO/IEC 15444-1.

## Table of Contents

1. [Architecture](#architecture)
2. [Components](#components)
3. [MQ-Coder](#mq-coder)
4. [Bit-Plane Coding](#bit-plane-coding)
5. [Context Modeling](#context-modeling)
6. [Tier-2 Coding](#tier-2-coding)
7. [Usage Examples](#usage-examples)
8. [Performance Characteristics](#performance-characteristics)
9. [Implementation Notes](#implementation-notes)

## Architecture

The entropy coding system is organized into multiple layers following the JPEG 2000 standard:

```
┌─────────────────────────────────────────┐
│         Tier-2 Coding                   │
│    (Packet Headers, Layers)             │
├─────────────────────────────────────────┤
│         Tier-1 Coding                   │
│    (Bit-Plane, Context Modeling)        │
├─────────────────────────────────────────┤
│         MQ-Coder                        │
│    (Arithmetic Entropy Coder)           │
└─────────────────────────────────────────┘
```

### Key Design Principles

- **Strict Concurrency**: All types are `Sendable` and designed for Swift 6 concurrency
- **Value Types**: Core types use structs for value semantics and safety
- **Memory Efficiency**: Copy-on-write buffers and memory pooling
- **Performance**: Optimized hot paths with inline hints and capacity management
- **Correctness**: Comprehensive test coverage (330+ tests)

## Components

### Module Structure

The entropy coding implementation spans the `J2KCodec` module:

- `J2KMQCoder.swift` - MQ arithmetic coder implementation
- `J2KBitPlaneCoder.swift` - EBCOT bit-plane coding
- `J2KContextModeling.swift` - Context formation and state management
- `J2KTier2Coding.swift` - Packet headers and progression orders

## MQ-Coder

The MQ-coder is the arithmetic entropy coder at the heart of JPEG 2000. It provides context-adaptive binary arithmetic coding with high compression efficiency.

### Features

- **Adaptive Probability Estimation**: 47-state FSM for probability adaptation
- **Context-Adaptive Coding**: Multiple contexts for different symbol patterns
- **Bypass Mode**: Direct bit encoding for uniform distributions
- **Termination Modes**: Support for predictable and near-optimal termination
- **Bit Stuffing**: Automatic handling of marker code avoidance

### State Machine

The MQ-coder uses a 47-state finite state machine defined in `mqStateTable`:

```swift
public struct MQState: Sendable {
    public let qe: UInt32        // Probability estimate
    public let nextMPS: Int      // Next state for MPS
    public let nextLPS: Int      // Next state for LPS
    public let switchMPS: Bool   // Switch MPS flag
}
```

### Context Management

Contexts track probability state for different symbol types:

```swift
public struct MQContext: Sendable {
    public var stateIndex: Int   // Index into state table [0-46]
    public var mps: Bool         // More Probable Symbol
}
```

### Basic Usage

```swift
// Encoding
var encoder = MQEncoder()
var context = MQContext()

for symbol in symbols {
    encoder.encode(symbol: symbol, context: &context)
}

let encodedData = encoder.finish()

// Decoding
var decoder = MQDecoder(data: encodedData)
var decodeContext = MQContext()

for _ in symbols {
    let decoded = decoder.decode(context: &decodeContext)
}
```

### Bypass Mode

For uniform probability distributions, bypass mode provides faster encoding:

```swift
var encoder = MQEncoder()

for bit in rawBits {
    encoder.encodeBypass(symbol: bit)
}
```

### Performance

Current performance characteristics (measured on test hardware):

| Operation | Throughput | Notes |
|-----------|------------|-------|
| Encode (1K symbols) | 18,833 ops/sec | Context-adaptive |
| Decode (1K symbols) | 14,100 ops/sec | Context-adaptive |
| Encode (bypass) | ~50,000 ops/sec | Raw bit mode |

## Bit-Plane Coding

EBCOT bit-plane coding processes wavelet coefficients plane by plane, from most significant to least significant bit.

### Three-Pass Algorithm

Each bit-plane is coded in three passes:

1. **Significance Propagation Pass (SPP)**
   - Codes bits of coefficients with significant neighbors
   - Uses context based on neighbor significance

2. **Magnitude Refinement Pass (MRP)**
   - Refines already significant coefficients
   - Can use bypass mode for lower bit-planes

3. **Cleanup Pass (CP)**
   - Codes remaining coefficients
   - Most efficient pass for sparse data

### Coding Options

```swift
public struct CodingOptions: Sendable {
    let bypassEnabled: Bool      // Enable bypass mode
    let bypassThreshold: Int     // Bit-plane for bypass start
    let terminationMode: TerminationMode
}

// Predefined configurations
CodingOptions.default            // Standard encoding
CodingOptions.fastEncoding       // Bypass for speed
CodingOptions.errorResilient     // Predictable termination
CodingOptions.optimalCompression // Near-optimal termination
```

### Usage

```swift
let coder = BitPlaneCoder(
    width: 64,
    height: 64,
    subband: .ll,
    options: .default
)

let result = try coder.encode(
    coefficients: coefficients,
    bitDepth: 12,
    maxPasses: nil  // All passes
)

print("Encoded \(result.passCount) passes")
print("Zero bit-planes: \(result.zeroBitPlanes)")
```

### Coefficient State

Each coefficient tracks its coding state:

```swift
public struct CoefficientState: OptionSet, Sendable {
    static let significant       // Coefficient is significant
    static let codedThisPass    // Coded in current pass
    static let signBit          // Sign bit set
    static let visited          // Processed in this pass
}
```

## Context Modeling

Context modeling determines which probability context to use for each coded bit.

### EBCOT Contexts

19 distinct contexts for different coding scenarios:

```swift
public enum EBCOTContext: UInt8, CaseIterable, Sendable {
    // Significance propagation contexts (9)
    case sigPropLL_LH_0, sigPropLL_LH_1h, sigPropLL_LH_1v, ...
    
    // Sign contexts (5)
    case signH0V0, signH1V0, signH0V1, signH1V1, signH2V2
    
    // Magnitude refinement contexts (3)
    case magRef1, magRef2noSig, magRef2sig
    
    // Other contexts
    case uniform, runMode
}
```

### Context Formation

Context is formed based on neighbor significance and signs:

```swift
let modeler = ContextModeler(subband: .hl)

// Significance context
let sigCtx = modeler.significanceContext(neighbors: contribution)

// Sign context (returns context and XOR flag)
let (signCtx, xor) = modeler.signContext(neighbors: contribution)

// Magnitude refinement context
let magCtx = modeler.magnitudeRefinementContext(
    firstRefinement: true,
    neighborsWereSignificant: hasSignificantNeighbors
)
```

### Neighbor Calculation

The neighbor calculator efficiently computes neighbor contributions:

```swift
let calculator = NeighborCalculator(width: 64, height: 64)

let contribution = calculator.calculate(
    x: x,
    y: y,
    states: coefficientStates
)

// Result provides:
// - horizontal: Count of horizontal neighbors
// - vertical: Count of vertical neighbors  
// - diagonal: Count of diagonal neighbors
// - horizontalSign: Sum of horizontal signs
// - verticalSign: Sum of vertical signs
```

## Tier-2 Coding

Tier-2 handles packet formation and progression orders.

### Progression Orders

Five progression orders supported:

```swift
public enum ProgressionOrder: UInt8, CaseIterable, Sendable {
    case lrcp  // Layer-Resolution-Component-Position
    case rlcp  // Resolution-Layer-Component-Position
    case rpcl  // Resolution-Position-Component-Layer
    case pcrl  // Position-Component-Resolution-Layer
    case cprl  // Component-Position-Resolution-Layer
}
```

### Quality Layers

Quality layers enable progressive quality refinement:

```swift
public struct QualityLayer: Sendable {
    let index: Int
    let targetRate: Double?       // nil for lossless
    var codeBlockContributions: [Int: Int]
}
```

### Packet Headers

Packet headers describe code-block contributions:

```swift
public struct PacketHeader: Sendable {
    let layerIndex: Int
    let resolutionLevel: Int
    let componentIndex: Int
    let precinctIndex: Int
    let isEmpty: Bool
    let codeBlockInclusions: [Bool]
    let codingPasses: [Int]
    let dataLengths: [Int]
}
```

### Packet Header Encoding

```swift
let writer = PacketHeaderWriter()
let data = try writer.encode(header)

let reader = PacketHeaderReader()
let decodedHeader = try reader.decode(data)
```

## Usage Examples

### Complete Encoding Pipeline

```swift
import J2KCore
import J2KCodec

// 1. Initialize coder
let coder = BitPlaneCoder(
    width: 64,
    height: 64,
    subband: .hl,
    options: .default
)

// 2. Prepare coefficients (from wavelet transform)
let coefficients: [Int32] = ... // 64x64 = 4096 coefficients

// 3. Encode
let result = try coder.encode(
    coefficients: coefficients,
    bitDepth: 12,
    maxPasses: nil
)

// 4. Create packet header
let header = PacketHeader(
    layerIndex: 0,
    resolutionLevel: 3,
    componentIndex: 0,
    precinctIndex: 0,
    isEmpty: false,
    codeBlockInclusions: [true],
    codingPasses: [result.passCount],
    dataLengths: [result.data.count]
)

// 5. Write packet
let writer = PacketHeaderWriter()
let headerData = try writer.encode(header)
let packetData = headerData + result.data
```

### Custom Configuration

```swift
// Fast encoding with bypass mode
let fastOptions = CodingOptions(
    bypassEnabled: true,
    bypassThreshold: 4,  // Use bypass for lower 4 bit-planes
    terminationMode: .nearOptimal
)

let coder = BitPlaneCoder(
    width: 64,
    height: 64,
    subband: .hh,
    options: fastOptions
)
```

### Progressive Quality Layers

```swift
// Define quality layers
let layers = [
    QualityLayer(index: 0, targetRate: 0.1),  // 10% quality
    QualityLayer(index: 1, targetRate: 0.5),  // 50% quality
    QualityLayer(index: 2, targetRate: nil)   // Lossless
]

// Form layers using rate-distortion optimization
let optimizer = LayerOptimizer()
let optimizedLayers = optimizer.formLayers(
    codeBlocks: codeBlocks,
    targetLayers: layers
)
```

## Performance Characteristics

### Compression Ratios

Typical compression behavior for different data patterns:

| Pattern | Compression Ratio | Notes |
|---------|------------------|-------|
| All zeros | >50:1 | Highly compressible |
| Uniform MPS | >20:1 | Context adapts quickly |
| Alternating | ~2:1 | Poor compression |
| Pseudo-random | ~3:1 | Adaptive coding helps |
| Natural images | 5-15:1 | Typical JPEG 2000 range |

### Memory Usage

Memory requirements for code-block coding:

- Base overhead: ~1KB per encoder/decoder
- Coefficient states: 1 byte per coefficient
- Context states: 19 contexts × 8 bytes = 152 bytes
- Output buffer: ~coefficient count / 8 bytes (compressed)

For a 64×64 code-block:
- Coefficient states: 4KB
- Total working memory: ~6KB
- Output size (typical): 500-2000 bytes

### Scalability

Performance scales linearly with:
- Number of coefficients
- Number of bit-planes
- Code-block size

Parallelization opportunities identified (see [PARALLELIZATION.md](PARALLELIZATION.md)):
- Code-block level: 5-7x speedup potential
- Tile level: Near-linear scaling

## Implementation Notes

### Current Status

**Complete:**
- ✅ MQ-coder encoder/decoder
- ✅ Context modeling (19 contexts)
- ✅ Bit-plane coding (3-pass algorithm)
- ✅ Bypass mode support
- ✅ Packet header encoding/decoding
- ✅ Progression order support
- ✅ Quality layer formation (basic)

**In Progress:**
- 🔄 Rate-distortion optimization (placeholder)
- 🔄 Full decoder termination handling

**Planned:**
- 📋 ROI (Region of Interest) coding
- 📋 Arithmetic coding bypass optimization
- 📋 Parallel code-block coding

### Known Limitations

1. **Decoder Termination**: The MQ decoder currently has limited support for all termination modes. Full round-trip encode/decode is reliable for data encoded with default settings but may have issues with other configurations.

2. **Rate-Distortion Optimization**: Basic PCRD-opt is implemented but not yet optimized for production use.

3. **Integer Overflow**: The bit-plane coder handles magnitudes up to about ±1,000,000 safely. Extreme values (near Int32.max/min) may cause overflow in magnitude calculation.

### Testing

Comprehensive test suite with 330+ tests:

- **Unit Tests**: Component-level testing (MQ-coder, contexts, bit-planes)
- **Integration Tests**: Full encoding/decoding pipelines
- **Test Vectors**: Known patterns and ISO-style validation
- **Fuzzing Tests**: Random inputs and edge cases
- **Performance Tests**: Benchmarking and profiling

Run tests:
```bash
swift test --filter J2KCodecTests
```

### Optimization History

Performance improvements implemented in Phase 1, Week 20-22:

1. **Inline Hints**: Added `@inline(__always)` to 6 critical methods
2. **Capacity Management**: Pre-allocate buffers with estimated sizes
3. **Variable Optimization**: Reduced allocations in hot paths

Result: 3% improvement in encoding throughput (18,305 → 18,833 ops/sec)

### Future Work

See [MILESTONES.md](MILESTONES.md) for the full roadmap. Next steps:

1. **Phase 2: Wavelet Transform** (Weeks 26-40)
   - Implement DWT for coefficient generation
   - Enable end-to-end encoding/decoding

2. **Phase 3: Quantization** (Weeks 41-48)
   - Scalar and deadzone quantization
   - ROI coding support

3. **Parallelization** (Ongoing)
   - Actor-based architecture for parallel coding
   - Code-block level parallelism

## References

### JPEG 2000 Standard

- **ISO/IEC 15444-1:2019** - Core coding system
  - Annex C: Arithmetic coding (MQ-coder)
  - Annex D: EBCOT (bit-plane coding)
  - Annex B: Codestream syntax

### Implementation References

- **OpenJPEG**: Open-source reference implementation
- **Kakadu**: High-performance commercial implementation
- **JPEG 2000 Test Files**: ISO conformance test suite

### Related Documentation

- [PERFORMANCE.md](PERFORMANCE.md) - Performance analysis and optimization
- [PARALLELIZATION.md](PARALLELIZATION.md) - Parallelization strategy
- [MILESTONES.md](MILESTONES.md) - Development roadmap
- [API Documentation](https://raster-lab.github.io/J2KSwift/documentation/j2kcodec/) - Generated API docs

## Contributing

When working on entropy coding:

1. **Follow Swift 6 Concurrency**: All types must be `Sendable`
2. **Maintain Test Coverage**: Add tests for new features (target >90%)
3. **Document Public APIs**: Use DocC-style documentation
4. **Profile Before Optimizing**: Use the benchmark infrastructure
5. **Check Against Standard**: Validate against JPEG 2000 spec

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

**Last Updated**: 2026-02-05  
**Phase**: Phase 1, Week 23-25 (Testing & Validation)  
**Status**: Entropy coding implementation complete and validated
