# JPEG 2000 Conformance Testing Guide

## Overview

This document describes the conformance testing framework for J2KSwift and how to validate the implementation against ISO/IEC 15444-4 requirements.

## Conformance Testing Framework

J2KSwift includes a comprehensive conformance testing framework located in `Sources/J2KCore/J2KConformanceTesting.swift`.

### Key Components

#### 1. Error Metrics

The `J2KErrorMetrics` struct provides standard image quality metrics:

- **MSE (Mean Squared Error)**: Average of squared pixel differences
- **PSNR (Peak Signal-to-Noise Ratio)**: Quality metric in decibels
- **MAE (Maximum Absolute Error)**: Maximum single-pixel difference

```swift
let mse = J2KErrorMetrics.meanSquaredError(reference: referenceImage, test: decodedImage)
let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(reference: referenceImage, test: decodedImage, bitDepth: 8)
let mae = J2KErrorMetrics.maximumAbsoluteError(reference: referenceImage, test: decodedImage)
```

#### 2. Test Vectors

`J2KTestVector` encapsulates conformance test cases:

```swift
let vector = J2KTestVector(
    name: "lossless_grayscale_512x512",
    description: "Lossless encoding of 8-bit grayscale image",
    codestream: encodedData,
    referenceImage: referencePixels,
    width: 512,
    height: 512,
    components: 1,
    bitDepth: 8,
    maxAllowableError: 0  // Lossless
)
```

#### 3. Conformance Validator

The `J2KConformanceValidator` validates implementations:

```swift
let result = J2KConformanceValidator.validate(
    decoded: decodedImage,
    against: vector
)

if result.passed {
    print("✓ Test passed: MAE = \(result.mae!), PSNR = \(result.psnr!)dB")
} else {
    print("✗ Test failed: \(result.errorMessage!)")
}
```

## ISO/IEC 15444-4 Compliance

### Conformance Classes

JPEG 2000 defines several conformance classes:

1. **Profile 0 (Baseline)**: Basic JPEG 2000 features
2. **Profile 1 (Extended)**: Additional color transforms, ROI
3. **Profile 2 (Cinema)**: Digital cinema applications  
4. **Profile 3 (Broadcast)**: Broadcast video applications

### Error Tolerances

Different conformance classes have different error tolerances:

| Class | Type | Max Allowable Error |
|-------|------|---------------------|
| Lossless | Reversible 5/3 | 0 |
| Near-lossless | Irreversible 9/7 | 1-2 |
| Lossy | Variable bitrate | Specified per test |

## Test Suite Organization

### Core Tests

Located in `Tests/J2KCoreTests/J2KConformanceTestingTests.swift`:

- Error metric calculations (MSE, PSNR, MAE)
- Test vector creation and validation
- Validator functionality
- Report generation

### Security Tests

Located in `Tests/J2KCoreTests/J2KSecurityTests.swift`:

- Input validation (empty data, truncated data, invalid markers)
- Dimension validation (negative, zero, extreme values)
- Malformed data handling
- Fuzzing with random data
- Thread safety tests

### Stress Tests

Located in `Tests/J2KCoreTests/J2KStressTests.swift`:

- Large image handling (4K, 8K resolutions)
- Multi-component images (up to 16 components)
- High bit depth images (up to 38 bits)
- Memory stress tests
- Concurrent operations
- Edge cases (minimum/maximum dimensions, prime numbers)

## Running Conformance Tests

### Run All Tests

```bash
swift test
```

### Run Specific Test Suites

```bash
swift test --filter J2KConformanceTestingTests
swift test --filter J2KSecurityTests
swift test --filter J2KStressTests
```

### Run Individual Tests

```bash
swift test --filter J2KConformanceTestingTests.testPSNRIdenticalImages
```

## Creating Custom Test Vectors

### Step 1: Prepare Test Data

```swift
// Create or load reference image
let referenceImage: [Int32] = ... // Your reference pixels

// Create or load JPEG 2000 codestream
let codestream = Data(contentsOf: URL(fileURLWithPath: "test.jp2"))
```

### Step 2: Create Test Vector

```swift
let vector = J2KTestVector(
    name: "custom_test",
    description: "Description of test case",
    codestream: codestream,
    referenceImage: referenceImage,
    width: 512,
    height: 512,
    components: 3,
    bitDepth: 8,
    maxAllowableError: 0,
    shouldSucceed: true
)
```

### Step 3: Run Validation

```swift
// Decode the codestream
let decoder = J2KDecoder()
let decoded = try decoder.decode(data: vector.codestream)

// Validate
let result = J2KConformanceValidator.validate(
    decoded: decoded.data,
    against: vector
)

XCTAssertTrue(result.passed, result.errorMessage ?? "")
```

## Obtaining ISO Test Suite

The official ISO/IEC 15444-4 conformance test suite can be obtained from:

- ISO: https://www.iso.org/standard/85636.html
- ITU-T: https://www.itu.int/rec/T-REC-T.803

The test suite includes:

- Reference codestreams
- Decoded reference images
- Expected error bounds
- Test procedures

## Interpreting Results

### Success Criteria

A test passes when:
- Decoding completes without errors (if `shouldSucceed` is true)
- MAE is within `maxAllowableError`
- Image dimensions match expected values
- Component count matches expected value

### Common Failure Modes

1. **Size mismatch**: Decoded image has wrong dimensions
2. **Component mismatch**: Wrong number of color components
3. **Error exceeds tolerance**: MAE > maxAllowableError
4. **Decoding failure**: Exception thrown during decode

### Quality Metrics

- **PSNR > 40 dB**: Excellent quality
- **PSNR 30-40 dB**: Good quality
- **PSNR 20-30 dB**: Acceptable quality
- **PSNR < 20 dB**: Poor quality

## Continuous Integration

Integrate conformance tests into CI/CD:

```yaml
- name: Run conformance tests
  run: swift test --filter Conformance

- name: Run security tests
  run: swift test --filter Security

- name: Run stress tests
  run: swift test --filter Stress
```

## Benchmarking

The framework supports performance benchmarking:

```swift
measure {
    let decoded = try decoder.decode(data: codestream)
}
```

## Future Enhancements

Planned improvements to the conformance framework:

1. **ISO Test Suite Integration**: Automatic import of official test vectors
2. **Visual Comparison**: Side-by-side image comparison tools
3. **Detailed Reports**: HTML/PDF report generation
4. **Regression Testing**: Track quality metrics over time
5. **Platform-Specific Tests**: Accelerate framework validation

## References

- ISO/IEC 15444-1: JPEG 2000 Core Coding System
- ISO/IEC 15444-4: JPEG 2000 Conformance Testing
- ISO/IEC 15444-15: HTJ2K (High Throughput JPEG 2000)
- ITU-T T.800: JPEG 2000 Image Coding System
- ITU-T T.803: Conformance Testing

## Contact

For questions about conformance testing:
- Review the test code in `Tests/J2KCoreTests/`
- Check the API documentation
- File an issue on GitHub

---

**Last Updated**: 2026-02-07  
**Version**: 1.0  
**Status**: Active Development
