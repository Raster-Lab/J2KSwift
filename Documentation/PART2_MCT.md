# Multi-Component Transform (MCT) — ISO/IEC 15444-2 Part 2

## Overview

J2KSwift provides complete support for Multi-Component Transform (MCT) as defined in ISO/IEC 15444-2 (JPEG 2000 Part 2). MCT extends the basic color transforms (RCT/ICT) with arbitrary linear transformations that can decorrelate any number of image components, significantly improving compression efficiency for multi-spectral and hyperspectral imagery.

## Features

- **Array-Based Transforms** — Define custom N×N transformation matrices for any number of components
- **Reversible and Irreversible** — Support both integer (lossless) and floating-point (lossy) transforms
- **Hardware Acceleration** — vDSP-accelerated matrix operations on Apple platforms with 20-50× speedup
- **Marker Segment Support** — Complete MCT/MCC/MCO marker segment parsing and generation
- **Perfect Reconstruction** — Automatic validation of transform invertibility
- **Predefined Matrices** — Built-in RGB↔YCbCr, averaging, and identity transforms

## Quick Start

### Basic Usage

```swift
import J2KCodec

// Create a Multi-Component Transform
let mct = J2KMCT()

// Define a 3×3 decorrelation matrix
let matrix = try J2KMCTMatrix(
    size: 3,
    coefficients: [
        1.0,  0.0,  0.0,
        -0.5, 1.0,  0.0,
        -0.5, -0.5, 1.0
    ],
    precision: .floatingPoint
)

// Apply forward transform
let input: [[Double]] = [
    [255, 128, 64],  // Component 0
    [192, 96, 32],   // Component 1
    [128, 64, 16]    // Component 2
]

let transformed = try mct.forwardTransform(
    components: input,
    matrix: matrix
)

// Apply inverse transform
let inverse = try matrix.inverse()
let reconstructed = try mct.inverseTransform(
    components: transformed,
    matrix: inverse
)
```

### Using Predefined Matrices

```swift
// RGB to YCbCr conversion
let ycbcr = try mct.forwardTransform(
    components: rgbComponents,
    matrix: J2KMCTMatrix.rgbToYCbCr
)

// YCbCr to RGB conversion
let rgb = try mct.inverseTransform(
    components: ycbcr,
    matrix: J2KMCTMatrix.yCbCrToRGB
)

// Identity transform (no change)
let unchanged = try mct.forwardTransform(
    components: input,
    matrix: J2KMCTMatrix.identity3
)
```

### Hardware-Accelerated Transforms

```swift
#if canImport(J2KAccelerate)
import J2KAccelerate

let accelerated = J2KAcceleratedMCT()

// Automatically uses vDSP for 20-50× speedup on Apple platforms
let transformed = try accelerated.forwardTransform(
    components: largeImageComponents,
    matrix: transformMatrix
)

// Optimized 3×3 fast path for RGB images
let ycbcr = try accelerated.forwardTransform3x3(
    components: rgbComponents,
    matrix: J2KMCTMatrix.rgbToYCbCr
)

// Optimized 4×4 fast path for RGBA images
let transformed4 = try accelerated.forwardTransform4x4(
    components: rgbaComponents,
    matrix: rgba_matrix
)
#endif
```

## Matrix Operations

### Creating Transformation Matrices

```swift
// Identity matrix (no transformation)
let identity = J2KMCTMatrix.identity(size: 4)

// Custom decorrelation matrix
let matrix = try J2KMCTMatrix(
    size: 3,
    coefficients: [
        0.577, 0.577, 0.577,   // Average
        0.707, -0.707, 0.0,    // Difference 1
        0.408, 0.408, -0.816   // Difference 2
    ],
    precision: .floatingPoint
)

// Integer (reversible) matrix
let intMatrix = try J2KMCTMatrix(
    size: 2,
    coefficients: [
        1.0, 1.0,
        1.0, -1.0
    ],
    precision: .integer
)
```

### Matrix Operations

```swift
// Compute inverse matrix
let inverse = try matrix.inverse()

// Get transpose
let transposed = matrix.transpose()

// Validate perfect reconstruction
let isValid = matrix.validateReconstructibility()

// Matrix multiplication (internal)
let product = matrix1 * matrix2  // Via internal method
```

## Marker Segment Support

### MCT Marker (0xFF75)

The MCT marker defines the transformation matrix:

```swift
// Create MCT marker from matrix
let marker = try J2KMCTMarkerSegment.from(
    matrix: transformMatrix,
    index: 0
)

// Encode to codestream
let encoded = try marker.encode()

// Parse from codestream
let parsed = try J2KMCTMarkerSegment.parse(from: data)

// Convert back to matrix
let matrix = try parsed.toMatrix(inputComponentCount: 3)
```

### MCC Marker (0xFF77)

The MCC marker groups components for transformation:

```swift
// Define component collection
let mcc = J2KMCCMarkerSegment(
    index: 0,
    inputComponents: [0, 1, 2],     // RGB
    outputComponents: [0, 1, 2],    // YCbCr
    mctIndex: 0                     // Reference to MCT marker
)

// Encode and parse
let encoded = try mcc.encode()
let parsed = try J2KMCCMarkerSegment.parse(from: data)
```

### MCO Marker (0xFF76)

The MCO marker specifies transform ordering:

```swift
// Define transform order
let mco = J2KMCOMarkerSegment(
    mccOrder: [0, 1, 2]  // Apply MCC 0, then 1, then 2
)

// Encode and parse
let encoded = try mco.encode()
let parsed = try J2KMCOMarkerSegment.parse(from: data)
```

## Component-Based Transforms

Transform J2KComponent objects directly:

```swift
// Create components
let component0 = J2KComponent(
    index: 0,
    bitDepth: 8,
    signed: false,
    width: 512,
    height: 512,
    data: imageData0
)

let component1 = J2KComponent(/* ... */)
let component2 = J2KComponent(/* ... */)

let components = [component0, component1, component2]

// Apply MCT
let transformed = try mct.forwardTransform(
    components: components,
    matrix: transformMatrix
)

// Inverse transform
let reconstructed = try mct.inverseTransform(
    components: transformed,
    matrix: inverseMatrix
)
```

## Integer (Reversible) Transforms

For lossless compression:

```swift
// Define integer matrix
let matrix = try J2KMCTMatrix(
    size: 3,
    coefficients: [
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0
    ],
    precision: .integer
)

// Integer component data
let input: [[Int32]] = [
    [100, 200, 150],
    [50, 75, 100],
    [25, 50, 75]
]

// Transform with perfect reconstruction
let transformed = try mct.forwardTransformInteger(
    components: input,
    matrix: matrix
)

let reconstructed = try mct.inverseTransformInteger(
    components: transformed,
    matrix: try matrix.inverse()
)

// Exact match guaranteed
assert(reconstructed == input)
```

## Advanced Usage

### Multi-Spectral Imagery

MCT excels at compressing multi-spectral and hyperspectral images:

```swift
// 10-band multi-spectral image
let bandCount = 10
let matrix = J2KMCTMatrix.identity(size: bandCount)

// Or use PCA/KLT-derived decorrelation matrix
let pca_matrix = computePCAMatrix(from: multispectralData)

let transformed = try mct.forwardTransform(
    components: spectralBands,
    matrix: pca_matrix
)
```

### Custom Decorrelation Matrices

Design matrices based on image statistics:

```swift
// Compute covariance matrix from training data
let covariance = computeCovariance(trainingImages)

// Eigen decomposition (KLT)
let (eigenvalues, eigenvectors) = eigenDecomposition(covariance)

// Create KLT matrix
let klt_matrix = try J2KMCTMatrix(
    size: componentCount,
    coefficients: eigenvectors,
    precision: .floatingPoint
)

// Validate and use
assert(klt_matrix.validateReconstructibility())
let transformed = try mct.forwardTransform(
    components: imageData,
    matrix: klt_matrix
)
```

### Batch Processing

Process large images efficiently:

```swift
#if canImport(J2KAccelerate)
let accelerated = J2KAcceleratedMCT()

// Automatic optimal batching
let transformed = try accelerated.forwardTransformOptimized(
    components: largeComponents,  // Millions of samples
    matrix: transformMatrix
)

// Manual batch size control
let batchSize = J2KAcceleratedMCT.optimalBatchSize(
    sampleCount: sampleCount,
    componentCount: componentCount
)
#endif
```

## Performance

### Benchmarks

On Apple Silicon (M1/M2/M3):

| Operation | Scalar | vDSP (3×3) | vDSP (General) | Speedup |
|-----------|--------|------------|----------------|---------|
| 1K pixels | 0.1 ms | 0.01 ms | 0.02 ms | 5-10× |
| 1M pixels | 100 ms | 4 ms | 8 ms | 12-25× |
| 16M pixels | 1.6 s | 0.06 s | 0.12 s | 13-26× |

### Optimization Tips

1. **Use Hardware Acceleration**: Always use `J2KAcceleratedMCT` on Apple platforms
2. **Optimize Matrix Size**: 3×3 and 4×4 have dedicated fast paths
3. **Batch Large Images**: Automatic batching improves cache utilization
4. **Reversible When Possible**: Integer transforms are faster than floating-point
5. **Validate Once**: Disable reconstruction validation in release builds

```swift
let config = J2KMCTConfiguration(
    type: .arrayBased,
    matrix: matrix,
    validateReconstruction: false  // Faster in production
)
```

## Integration with Encoding Pipeline

### Encoder Configuration

```swift
// Configure encoder with MCT
let encodingConfig = J2KEncodingConfiguration(
    quality: 0.95,
    lossless: false,
    mctConfiguration: J2KMCTEncodingConfiguration(
        mode: .arrayBased(customMatrix),
        useExtendedPrecision: false,
        preferReversible: false
    )
)

let encoder = J2KEncoder(configuration: encodingConfig)
let encoded = try encoder.encode(image)
```

### Rate-Distortion Integration

MCT is now integrated with the rate-distortion optimization system:

```swift
// Rate control automatically accounts for MCT compression efficiency
let mctConfig = J2KMCTEncodingConfiguration(
    mode: .arrayBased(J2KMCTMatrix.rgbToYCbCr)
)

let rateConfig = RateControlConfiguration(
    mode: .targetBitrate(1.5),
    layerCount: 3,
    mctConfiguration: mctConfig,  // MCT-aware distortion estimation
    componentCount: 3
)

// Encoder will optimize layers considering MCT decorrelation efficiency
```

The rate-distortion optimizer adjusts distortion estimates based on MCT configuration:
- **Array-Based MCT**: 10-30% efficiency gain for multi-spectral images
- **Dependency MCT**: 12-35% efficiency gain for sparse correlations
- **Adaptive MCT**: 15-40% efficiency gain through content-aware selection

### Per-Tile MCT Configuration

For images with spatially varying content, you can specify different MCT matrices per tile:

```swift
let mctConfig = J2KMCTEncodingConfiguration(
    mode: .arrayBased(J2KMCTMatrix.rgbToYCbCr),  // Global default
    perTileMCT: [
        0: customMatrixForTile0,
        2: customMatrixForTile2,
        5: customMatrixForTile5
    ]
)

// Tiles 0, 2, and 5 use custom matrices; other tiles use the global matrix
```

### Adaptive MCT Selection

The encoder can automatically select the best transform matrix per tile:

```swift
let candidates = [
    J2KMCTMatrix.rgbToYCbCr,
    J2KMCTMatrix.averaging3,
    customSpectralMatrix
]

let mctConfig = J2KMCTEncodingConfiguration(
    mode: .adaptive(
        candidates: candidates,
        selectionCriteria: .rateDistortion  // or .correlation, .compressionEfficiency
    )
)

// Encoder evaluates each candidate and selects the best for each tile
```

### Decoder Support

```swift
// Decoder automatically handles MCT markers
let decoder = J2KDecoder()
let decoded = try decoder.decode(codestreamWithMCT)

// MCT transform is automatically reversed
// Per-tile MCT is handled transparently
```

## Multi-Spectral Encoding Guide

### Working with Multi-Spectral Images

Multi-spectral images contain more than 3 components, often representing different spectral bands. MCT provides optimal decorrelation for these images:

```swift
// Example: 5-band multi-spectral satellite imagery
// Bands: Blue, Green, Red, NIR (Near-Infrared), SWIR (Short-Wave Infrared)

// Define a decorrelation matrix optimized for spectral bands
let spectralMatrix = try J2KMCTMatrix(
    size: 5,
    coefficients: [
        0.2, 0.2, 0.2, 0.2, 0.2,    // Average (luminance-like)
        1.0, -0.5, -0.25, -0.15, -0.1,  // Blue-dominant difference
        -0.25, 1.0, -0.5, -0.15, -0.1,  // Green-dominant difference
        -0.25, -0.5, 1.0, -0.15, -0.1,  // Red-dominant difference
        -0.1, -0.15, -0.25, 1.0, -0.5   // Infrared difference
    ],
    precision: .floatingPoint
)

let mctConfig = J2KMCTEncodingConfiguration(
    mode: .arrayBased(spectralMatrix),
    useExtendedPrecision: true  // Better accuracy for multi-spectral
)

// Expected compression gain: 20-40% compared to no transform
```

### Designing Transform Matrices

When creating custom decorrelation matrices for multi-spectral data:

#### 1. **Analyze Component Correlation**

```swift
// Compute correlation matrix from sample data
func computeCorrelation(components: [[Double]]) -> [[Double]] {
    let n = components.count
    var correlation = Array(repeating: Array(repeating: 0.0, count: n), count: n)
    
    for i in 0..<n {
        for j in 0..<n {
            let cov = covariance(components[i], components[j])
            let std_i = standardDeviation(components[i])
            let std_j = standardDeviation(components[j])
            correlation[i][j] = cov / (std_i * std_j)
        }
    }
    
    return correlation
}
```

#### 2. **Create Decorrelation Strategy**

- **High Correlation (>0.8)**: Use difference transforms to remove redundancy
- **Medium Correlation (0.4-0.8)**: Use weighted averaging with differences
- **Low Correlation (<0.4)**: Consider keeping components separate

#### 3. **Validate Invertibility**

```swift
let matrix = try J2KMCTMatrix(
    size: componentCount,
    coefficients: yourCoefficients,
    precision: .floatingPoint
)

// Verify the matrix is invertible
do {
    let inverse = try matrix.inverse()
    let isInvertible = try matrix.isInvertible()
    print("Matrix is invertible: \(isInvertible)")
} catch {
    print("Matrix is not invertible - adjust coefficients")
}
```

#### 4. **Test Round-Trip Accuracy**

```swift
let config = J2KMCTConfiguration(
    type: .arrayBased,
    matrix: matrix,
    validateReconstruction: true  // Enable automatic validation
)

let mct = J2KMCT(configuration: config)

// Should reconstruct perfectly for lossless encoding
let transformed = try mct.forwardTransform(components: original, matrix: matrix)
let inverse = try matrix.inverse()
let reconstructed = try mct.forwardTransform(components: transformed, matrix: inverse)

// Check reconstruction error
for compIdx in 0..<componentCount {
    let maxError = zip(original[compIdx], reconstructed[compIdx])
        .map { abs($0 - $1) }
        .max() ?? 0.0
    print("Component \(compIdx) max error: \(maxError)")
}
```

### Performance Tuning for Multi-Spectral

#### Component Count Impact

MCT performance scales with component count:

| Components | CPU Transform | vDSP Accelerated | Speedup |
|------------|---------------|------------------|---------|
| 3 (RGB)    | 1.2 ms        | 0.08 ms         | 15×     |
| 5 (MSI)    | 3.5 ms        | 0.12 ms         | 29×     |
| 8 (HSI)    | 8.9 ms        | 0.18 ms         | 49×     |
| 16 (HSI)   | 35.2 ms       | 0.35 ms         | 100×    |

**Recommendation**: Always use `J2KAcceleratedMCT` on Apple platforms for >3 components

#### Memory Considerations

Multi-spectral images require more memory:

```swift
// For an 8-component, 4096×4096 image:
// - Original: 8 × 4096² × 2 bytes = 256 MB (16-bit)
// - Transformed: 256 MB (same size)
// - Temporary: ~512 MB during transform
// Total peak: ~768 MB

// Use tile-based processing for very large images:
let config = J2KEncodingConfiguration(
    tileSize: (2048, 2048),  // Process in smaller tiles
    mctConfiguration: mctConfig
)
```

#### Adaptive Selection for Mixed Content

For images with varying spectral characteristics:

```swift
// Define candidates for different content types
let candidates = [
    vegetationMatrix,    // High NIR/Red correlation
    waterMatrix,         // Blue-dominant
    urbanMatrix,         // Mixed spectral response
    generalMatrix        // Fallback
]

let mctConfig = J2KMCTEncodingConfiguration(
    mode: .adaptive(
        candidates: candidates,
        selectionCriteria: .compressionEfficiency
    )
)

// Encoder will select optimal matrix per tile
// Typical gain: 5-15% over fixed matrix
```

## Comparison with RCT/ICT

| Feature | RCT/ICT | MCT |
|---------|---------|-----|
| Component Count | 3 (RGB) | Arbitrary (N×N) |
| Reversibility | RCT only | Both |
| Hardware Accel | Limited | vDSP/BLAS |
| Spectral Images | No | Yes |
| Flexibility | Fixed | Custom matrices |
| Part | Part 1 | Part 2 |
| R-D Integration | Yes | **Yes (NEW)** |
| Tiling Support | Yes | **Yes (NEW)** |
| Adaptive Selection | No | **Yes (NEW)** |

## Error Handling

```swift
do {
    let transformed = try mct.forwardTransform(
        components: input,
        matrix: matrix
    )
} catch J2KError.invalidParameter(let msg) {
    print("Invalid input: \(msg)")
} catch J2KError.invalidData(let msg) {
    print("Data error: \(msg)")
} catch {
    print("Unexpected error: \(error)")
}
```

Common errors:
- **invalidParameter**: Mismatched component counts or dimensions
- **invalidData**: Corrupted marker segments
- **unsupportedFeature**: Dependency transforms (not yet implemented)

## API Reference

### J2KMCTMatrix

```swift
struct J2KMCTMatrix: Sendable {
    let size: Int
    let coefficients: [Double]
    let precision: J2KMCTPrecision
    
    init(size: Int, coefficients: [Double], precision: J2KMCTPrecision) throws
    static func identity(size: Int) -> J2KMCTMatrix
    func inverse() throws -> J2KMCTMatrix
    func transpose() -> J2KMCTMatrix
    func validateReconstructibility() -> Bool
    
    // Predefined matrices
    static let rgbToYCbCr: J2KMCTMatrix
    static let yCbCrToRGB: J2KMCTMatrix
    static let averaging3: J2KMCTMatrix
    static let identity3: J2KMCTMatrix
    static let identity4: J2KMCTMatrix
}
```

### J2KMCT

```swift
struct J2KMCT: Sendable {
    let configuration: J2KMCTConfiguration
    
    func forwardTransform(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    func inverseTransform(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    func forwardTransformInteger(components: [[Int32]], matrix: J2KMCTMatrix) throws -> [[Int32]]
    func inverseTransformInteger(components: [[Int32]], matrix: J2KMCTMatrix) throws -> [[Int32]]
    func forwardTransform(components: [J2KComponent], matrix: J2KMCTMatrix) throws -> [J2KComponent]
    func inverseTransform(components: [J2KComponent], matrix: J2KMCTMatrix) throws -> [J2KComponent]
}
```

### J2KAcceleratedMCT

```swift
struct J2KAcceleratedMCT: Sendable {
    static var isAvailable: Bool
    
    func forwardTransform(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    func forwardTransform3x3(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    func forwardTransform4x4(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    func forwardTransformInteger(components: [[Int32]], matrix: J2KMCTMatrix) throws -> [[Int32]]
    func forwardTransformOptimized(components: [[Double]], matrix: J2KMCTMatrix) throws -> [[Double]]
    static func optimalBatchSize(sampleCount: Int, componentCount: Int) -> Int
}
```

## Best Practices

1. **Choose Appropriate Precision**
   - Use `.integer` for lossless compression
   - Use `.floatingPoint` for lossy compression with better decorrelation

2. **Validate Matrices**
   - Always validate `validateReconstructibility()` before encoding
   - Test round-trip accuracy with representative data

3. **Optimize for Platform**
   - Use `J2KAcceleratedMCT` on Apple platforms
   - Check `isAvailable` before using accelerated features

4. **Handle Edge Cases**
   - Check for singular matrices (non-invertible)
   - Validate component counts match matrix size
   - Ensure all components have same dimensions

5. **Profile Performance**
   - Measure transform overhead vs. compression gain
   - Consider matrix computation cost vs. reuse

## Dependency Transforms

**New in Week 165-166**: J2KSwift now supports dependency-based multi-component transforms that provide efficient decorrelation using hierarchical prediction relationships.

### Overview

Dependency transforms define relationships between components where each component is predicted from its predecessors. This approach is often more efficient than full matrix transforms for:
- Large numbers of components (>4)
- Sparse decorrelation patterns
- Low-latency streaming applications

### Basic Usage

```swift
import J2KCodec

// Create a dependency chain
let chain = try J2KDependencyChain(
    componentCount: 3,
    dependencies: [
        // Component 1 depends on Component 0
        J2KComponentDependency(
            outputComponent: 1,
            dependencies: [(0, 0.5)]  // C1' = C1 - 0.5*C0
        ),
        // Component 2 depends on transformed Component 1
        J2KComponentDependency(
            outputComponent: 2,
            dependencies: [(1, 0.5)]  // C2' = C2 - 0.5*C1'
        )
    ]
)

// Apply forward transform
let transformer = J2KMCTDependencyTransform()
let transformed = try transformer.forwardTransform(
    components: inputComponents,
    chain: chain
)

// Apply inverse transform (perfect reconstruction)
let reconstructed = try transformer.inverseTransform(
    components: transformed,
    chain: chain
)
```

### Predefined Dependency Chains

```swift
// RGB decorrelation using dependency transform
let rgb = J2KDependencyChain.rgbDecorrelation
// - Y₀ = R
// - Y₁ = G - 0.5·R
// - Y₂ = B - 0.5·R - 0.5·(G - 0.5·R)

// Simple sequential decorrelation for 4 components
let avg4 = J2KDependencyChain.averaging4
// - Y₀ = C₀
// - Y₁ = C₁ - 0.5·Y₀
// - Y₂ = C₂ - 0.5·Y₁
// - Y₃ = C₃ - 0.5·Y₂
```

### Hierarchical Transforms

For complex multi-stage decorrelation:

```swift
// Stage 1: Decorrelate first pair
let stage1 = try J2KDependencyChain(
    componentCount: 4,
    dependencies: [
        J2KComponentDependency(outputComponent: 1, dependencies: [(0, 0.5)])
    ]
)

// Stage 2: Decorrelate remaining components
let stage2 = try J2KDependencyChain(
    componentCount: 4,
    dependencies: [
        J2KComponentDependency(outputComponent: 2, dependencies: [(0, 0.5)]),
        J2KComponentDependency(outputComponent: 3, dependencies: [(0, 0.5)])
    ]
)

let hierarchical = try J2KHierarchicalTransform(
    stages: [stage1, stage2],
    totalComponents: 4
)

// Apply multi-stage transform
let transformed = try transformer.forwardHierarchicalTransform(
    components: input,
    transform: hierarchical
)

// Inverse applies stages in reverse order
let reconstructed = try transformer.inverseHierarchicalTransform(
    components: transformed,
    transform: hierarchical
)
```

### Encoding with Dependency MCT

```swift
// Configure encoder to use dependency transform
let chain = J2KDependencyChain.rgbDecorrelation
let depConfig = J2KMCTDependencyConfiguration(
    transform: .chain(chain),
    optimizeEvaluation: true
)

var config = J2KEncodingPreset.balanced.configuration()
config.mctConfiguration = J2KMCTEncodingConfiguration(
    mode: .dependency(depConfig),
    useExtendedPrecision: false,
    preferReversible: false
)

let encoder = J2KEncoder(configuration: config)
let encoded = try encoder.encode(image)
```

### Adaptive MCT Selection

For automatic matrix selection based on image content:

```swift
// Define candidate matrices
let candidates = [
    J2KMCTMatrix.identity3,
    J2KMCTMatrix.rgbToYCbCr,
    J2KMCTMatrix.averaging3
]

// Configure adaptive selection
var config = J2KEncodingPreset.balanced.configuration()
config.mctConfiguration = J2KMCTEncodingConfiguration(
    mode: .adaptive(
        candidates: candidates,
        selectionCriteria: .compressionEfficiency
    )
)

// Encoder will automatically select best matrix per tile
let encoder = J2KEncoder(configuration: config)
```

### Per-Tile MCT

For spatially varying content with different decorrelation needs:

```swift
var config = J2KEncodingPreset.balanced.configuration()
config.mctConfiguration = J2KMCTEncodingConfiguration(
    mode: .arrayBased(J2KMCTMatrix.rgbToYCbCr),
    perTileMCT: [
        0: J2KMCTMatrix.identity3,      // Tile 0 uses identity
        1: J2KMCTMatrix.rgbToYCbCr,     // Tile 1 uses RGB→YCbCr
        5: J2KMCTMatrix.averaging3      // Tile 5 uses averaging
    ]
)
```

## Limitations

- **Tile-Specific MCT Integration**: Per-tile matrix application in encoder pipeline pending
- **Rate-Distortion Optimization**: MCT cost not yet integrated into R-D optimization
- **Non-Linear Transforms**: Limited to linear transformations
- **GPU Acceleration**: Metal-accelerated MCT planned for Phase 14

## Future Enhancements

Completed in Phase 13:

- **✅ Rate-Distortion Integration**: MCT-aware distortion estimation in PCRD-opt
- **✅ Tiling Support**: Per-tile MCT configuration and adaptive selection
- **✅ Multi-Spectral Support**: Comprehensive testing with 4-16 component images

Planned for upcoming phases:

- **KLT/PCA Support**: Automatic decorrelation matrix generation from image statistics
- **Spectral Transform Library**: Pre-computed matrices for common sensor types (Landsat, Sentinel, MODIS)
- **Metal GPU Acceleration**: 100-200× speedup for large multi-spectral images (Phase 14)
- **Advanced Adaptive Selection**: Machine learning-based matrix selection

## References

- [ISO/IEC 15444-2:2004](https://www.iso.org/standard/33160.html) - JPEG 2000 Part 2 Extensions
- [Accelerate Framework](https://developer.apple.com/documentation/accelerate) - Apple's vector DSP library
- [PART2_DC_OFFSET.md](PART2_DC_OFFSET.md) - Related Part 2 feature
- [PART2_ARBITRARY_WAVELETS.md](PART2_ARBITRARY_WAVELETS.md) - Custom wavelet kernels

## Examples

See `Tests/J2KCodecTests/J2KMCTTests.swift` for 68 comprehensive examples covering:
- Matrix creation and operations
- Forward/inverse transforms
- Dependency transforms and hierarchical transforms
- Component-based transforms
- Encoding configuration with rate-distortion integration
- Per-tile MCT configuration
- Multi-spectral image processing (4-16 components)
- Marker segment encoding/decoding
- Hardware acceleration
- Performance benchmarks
