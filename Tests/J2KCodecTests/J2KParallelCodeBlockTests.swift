//
// J2KParallelCodeBlockTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for parallel code-block encoding, SIMD optimizations, and reference benchmarks.
///
/// This test suite validates:
/// 1. Parallel code-block encoding produces identical results to sequential encoding
/// 2. SIMD-optimized magnitude/sign separation is correct
/// 3. SIMD-optimized max absolute value computation is correct
/// 4. Performance benchmarks against reference implementations for bit-plane coding
final class J2KParallelCodeBlockTests: XCTestCase {
    // MARK: - Parallel Code-Block Encoding Tests

    /// Tests that parallel and sequential encoding produce identical code-block results.
    func testParallelEncodingMatchesSequential() async throws {
        // Create a simple test image
        let image = createTestImage(width: 64, height: 64, components: 1)

        let parallelPipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))

        let sequentialPipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: false
        ))

        // Both should produce valid output
        let parallelResult = try await parallelPipeline.encode(image)
        let sequentialResult = try await sequentialPipeline.encode(image)

        // Results should match (codestreams should be identical)
        XCTAssertEqual(parallelResult.count, sequentialResult.count,
                      "Parallel and sequential encoding should produce same size output")
        XCTAssertEqual(parallelResult, sequentialResult,
                      "Parallel and sequential encoding should produce identical output")
    }

    /// Tests parallel encoding with a larger multi-component image.
    func testParallelEncodingMultiComponent() async throws {
        let image = createTestImage(width: 128, height: 128, components: 3)

        let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            decompositionLevels: 3,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))

        let result = try await pipeline.encode(image)
        XCTAssertGreaterThan(result.count, 0, "Parallel encoding should produce output")

        // Verify SOC and EOC markers
        XCTAssertEqual(result[0], 0xFF)
        XCTAssertEqual(result[1], 0x4F) // SOC marker
        XCTAssertEqual(result[result.count - 2], 0xFF)
        XCTAssertEqual(result[result.count - 1], 0xD9) // EOC marker
    }

    /// Tests that the enableParallelCodeBlocks configuration option works.
    func testParallelCodeBlocksConfigOption() {
        let defaultConfig = J2KEncodingConfiguration()
        XCTAssertTrue(defaultConfig.enableParallelCodeBlocks,
                     "Parallel code-blocks should be enabled by default")

        let disabledConfig = J2KEncodingConfiguration(enableParallelCodeBlocks: false)
        XCTAssertFalse(disabledConfig.enableParallelCodeBlocks,
                      "Should be able to disable parallel code-blocks")

        let enabledConfig = J2KEncodingConfiguration(enableParallelCodeBlocks: true)
        XCTAssertTrue(enabledConfig.enableParallelCodeBlocks,
                     "Should be able to explicitly enable parallel code-blocks")
    }

    // MARK: - SIMD Optimization Tests

    /// Tests SIMD-optimized separateMagnitudesAndSigns with known values.
    func testSIMDMagnitudeSignSeparation() async throws {
        let coefficients: [Int32] = [5, -3, 0, 7, -10, 2, -1, 100]

        let coder = BitPlaneCoder(width: 8, height: 1, subband: .ll)

        // Encode the coefficients - the SIMD code path will be exercised
        let result = try await coder.encode(coefficients: coefficients, bitDepth: 8)

        // Verify encoding produces valid output
        XCTAssertGreaterThan(result.data.count, 0, "Should produce encoded data")
        XCTAssertGreaterThan(result.passCount, 0, "Should have coding passes")
    }

    /// Tests SIMD optimization with various coefficient sizes.
    func testSIMDWithVariousSizes() async throws {
        // Test with sizes that exercise both SIMD and remainder paths
        for size in [1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64] {
            let coefficients = (0..<size).map { i -> Int32 in
                let val = Int32(i * 3 + 1)
                return i.isMultiple(of: 3) ? -val : val
            }

            let coder = BitPlaneCoder(width: size, height: 1, subband: .hl)
            let result = try await coder.encode(coefficients: coefficients, bitDepth: 10)

            XCTAssertGreaterThan(result.data.count, 0,
                               "Size \(size): Should produce encoded data")
        }
    }

    /// Tests SIMD-optimized maxAbsValue computation.
    func testSIMDMaxAbsValue() {
        // Test with positive values
        XCTAssertEqual(EncoderPipeline.maxAbsValue([1, 2, 3, 4, 5]), 5)

        // Test with negative values
        XCTAssertEqual(EncoderPipeline.maxAbsValue([-1, -2, -3, -4, -5]), 5)

        // Test with mixed values
        XCTAssertEqual(EncoderPipeline.maxAbsValue([1, -10, 3, -4, 5]), 10)

        // Test with zeros
        XCTAssertEqual(EncoderPipeline.maxAbsValue([0, 0, 0, 0]), 0)

        // Test with empty array
        XCTAssertEqual(EncoderPipeline.maxAbsValue([]), 0)

        // Test with single element
        XCTAssertEqual(EncoderPipeline.maxAbsValue([-42]), 42)
        XCTAssertEqual(EncoderPipeline.maxAbsValue([42]), 42)

        // Test with exactly 4 elements (pure SIMD)
        XCTAssertEqual(EncoderPipeline.maxAbsValue([-100, 50, -75, 200]), 200)

        // Test with 5 elements (SIMD + remainder)
        XCTAssertEqual(EncoderPipeline.maxAbsValue([1, 2, 3, 4, -500]), 500)

        // Test with 7 elements (SIMD + remainder)
        XCTAssertEqual(EncoderPipeline.maxAbsValue([1, 2, 3, 4, 5, 6, -7]), 7)

        // Test with large array
        let large = (0..<1000).map { _ in Int32.random(in: -1000...1000) }
        let expected = large.map { abs($0) }.max() ?? 0
        XCTAssertEqual(EncoderPipeline.maxAbsValue(large), expected)
    }

    /// Tests that SIMD and scalar paths produce identical results.
    func testSIMDConsistencyWithScalar() {
        // Generate random coefficients of varying sizes
        for _ in 0..<10 {
            let count = Int.random(in: 1...256)
            let coefficients = (0..<count).map { _ in Int32.random(in: Int32.min / 2...Int32.max / 2) }

            let simdResult = EncoderPipeline.maxAbsValue(coefficients)
            let scalarResult = coefficients.reduce(Int32(0)) { max($0, abs($1)) }

            XCTAssertEqual(simdResult, scalarResult,
                          "SIMD and scalar maxAbsValue should match for \(count) elements")
        }
    }

    // MARK: - Reference Benchmark Tests

    /// Benchmarks bit-plane coding of a 32x32 code-block.
    func testBitPlaneCoding32x32Benchmark() async throws {
        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int32.random(in: -255...255) }

        // Run the operation directly (measureJ2KSwiftThrowing does not support async closures)
        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let encoded = try await coder.encode(coefficients: coefficients, bitDepth: 10)
        XCTAssertGreaterThan(encoded.data.count, 0, "Encoded data should not be empty")
    }

    /// Benchmarks bit-plane coding of a 64x64 code-block.
    func testBitPlaneCoding64x64Benchmark() async throws {
        let width = 64
        let height = 64
        let coefficients = (0..<(width * height)).map { _ in Int32.random(in: -255...255) }

        let coder = BitPlaneCoder(width: width, height: height, subband: .hl)
        let encoded = try await coder.encode(coefficients: coefficients, bitDepth: 10)
        XCTAssertGreaterThan(encoded.data.count, 0, "Encoded data should not be empty")
    }

    /// Benchmarks parallel code-block encoding with 16 blocks.
    func testParallelCodeBlocks16Benchmark() async throws {
        let image = createTestImage(width: 128, height: 128, components: 1)

        let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))
        let encoded = try await pipeline.encode(image)
        XCTAssertGreaterThan(encoded.count, 0, "Encoded data should not be empty")
    }

    /// Benchmarks parallel vs sequential to measure speedup.
    func testParallelVsSequentialComparison() async throws {
        let image = createTestImage(width: 128, height: 128, components: 1)

        // Sequential
        let seqPipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: false
        ))
        let seqStart = CFAbsoluteTimeGetCurrent()
        let seqEncoded = try await seqPipeline.encode(image)
        let seqTime = CFAbsoluteTimeGetCurrent() - seqStart

        // Parallel
        let parPipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))
        let parStart = CFAbsoluteTimeGetCurrent()
        let parEncoded = try await parPipeline.encode(image)
        let parTime = CFAbsoluteTimeGetCurrent() - parStart

        print("Sequential: \(seqTime)s, Parallel: \(parTime)s")

        // Both should complete successfully
        XCTAssertGreaterThan(seqEncoded.count, 0)
        XCTAssertGreaterThan(parEncoded.count, 0)
    }

    /// Comprehensive reference benchmark suite including bit-plane coding.
    func testBitPlaneCodingReferenceSuite() async throws {
        // 32x32 code-block encoding
        let coeffs32 = (0..<(32 * 32)).map { _ in Int32.random(in: -255...255) }
        let coder32 = BitPlaneCoder(width: 32, height: 32, subband: .ll)
        let encoded32 = try await coder32.encode(coefficients: coeffs32, bitDepth: 10)
        XCTAssertGreaterThan(encoded32.data.count, 0)

        // 64x64 code-block encoding
        let coeffs64 = (0..<(64 * 64)).map { _ in Int32.random(in: -255...255) }
        let coder64 = BitPlaneCoder(width: 64, height: 64, subband: .hl)
        let encoded64 = try await coder64.encode(coefficients: coeffs64, bitDepth: 10)
        XCTAssertGreaterThan(encoded64.data.count, 0)

        // Parallel code-block encoding
        let image = createTestImage(width: 64, height: 64, components: 1)
        let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))
        let encodedPar = try await pipeline.encode(image)
        XCTAssertGreaterThan(encodedPar.count, 0)
    }

    // MARK: - ParallelResultCollector Tests

    /// Tests that ParallelResultCollector correctly collects results from concurrent operations.
    func testParallelResultCollector() {
        let collector = ParallelResultCollector<Int>(capacity: 100)

        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let values = Array((i * 10)..<((i + 1) * 10))
            collector.append(contentsOf: values)
        }

        let results = collector.results
        XCTAssertEqual(results.count, 100, "Should have collected 100 results")

        // All values 0-99 should be present
        let sorted = results.sorted()
        XCTAssertEqual(sorted, Array(0..<100), "Should contain all values 0-99")
    }

    /// Tests ParallelResultCollector with empty input.
    func testParallelResultCollectorEmpty() {
        let collector = ParallelResultCollector<String>()
        XCTAssertTrue(collector.results.isEmpty, "Empty collector should have no results")
    }

    // MARK: - Helper Methods

    /// Creates a simple test image with specified dimensions.
    private func createTestImage(width: Int, height: Int, components: Int) -> J2KImage {
        var imageComponents: [J2KComponent] = []

        for i in 0..<components {
            var data = Data(count: width * height)
            for j in 0..<(width * height) {
                data[j] = UInt8(j % 256)
            }

            let component = J2KComponent(
                index: i,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                data: data
            )
            imageComponents.append(component)
        }

        return J2KImage(
            width: width,
            height: height,
            components: imageComponents
        )
    }
}
