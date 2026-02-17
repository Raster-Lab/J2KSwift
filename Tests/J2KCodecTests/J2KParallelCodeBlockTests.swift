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
    func testParallelEncodingMatchesSequential() throws {
        // Create a simple test image
        let image = createTestImage(width: 64, height: 64, components: 1)
        
        // Encode with parallel code-blocks enabled
        var parallelConfig = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        )
        _ = parallelConfig // suppress unused warning
        
        // Encode with parallel code-blocks disabled
        var sequentialConfig = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 2,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: false
        )
        _ = sequentialConfig // suppress unused warning
        
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
        let parallelResult = try parallelPipeline.encode(image)
        let sequentialResult = try sequentialPipeline.encode(image)
        
        // Results should match (codestreams should be identical)
        XCTAssertEqual(parallelResult.count, sequentialResult.count,
                      "Parallel and sequential encoding should produce same size output")
        XCTAssertEqual(parallelResult, sequentialResult,
                      "Parallel and sequential encoding should produce identical output")
    }
    
    /// Tests parallel encoding with a larger multi-component image.
    func testParallelEncodingMultiComponent() throws {
        let image = createTestImage(width: 128, height: 128, components: 3)
        
        let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            decompositionLevels: 3,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 1,
            enableParallelCodeBlocks: true
        ))
        
        let result = try pipeline.encode(image)
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
    func testSIMDMagnitudeSignSeparation() throws {
        let coefficients: [Int32] = [5, -3, 0, 7, -10, 2, -1, 100]
        
        let coder = BitPlaneCoder(width: 8, height: 1, subband: .ll)
        
        // Encode the coefficients - the SIMD code path will be exercised
        let result = try coder.encode(coefficients: coefficients, bitDepth: 8)
        
        // Verify encoding produces valid output
        XCTAssertGreaterThan(result.data.count, 0, "Should produce encoded data")
        XCTAssertGreaterThan(result.passCount, 0, "Should have coding passes")
    }
    
    /// Tests SIMD optimization with various coefficient sizes.
    func testSIMDWithVariousSizes() throws {
        // Test with sizes that exercise both SIMD and remainder paths
        for size in [1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 64] {
            let coefficients = (0..<size).map { i -> Int32 in
                let val = Int32(i * 3 + 1)
                return i % 3 == 0 ? -val : val
            }
            
            let coder = BitPlaneCoder(width: size, height: 1, subband: .hl)
            let result = try coder.encode(coefficients: coefficients, bitDepth: 10)
            
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
            let coefficients = (0..<count).map { _ in Int32.random(in: Int32.min/2...Int32.max/2) }
            
            let simdResult = EncoderPipeline.maxAbsValue(coefficients)
            let scalarResult = coefficients.reduce(Int32(0)) { max($0, abs($1)) }
            
            XCTAssertEqual(simdResult, scalarResult,
                          "SIMD and scalar maxAbsValue should match for \(count) elements")
        }
    }
    
    // MARK: - Reference Benchmark Tests
    
    /// Benchmarks bit-plane coding of a 32x32 code-block.
    func testBitPlaneCoding32x32Benchmark() throws {
        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int32.random(in: -255...255) }
        
        let benchmark = J2KReferenceBenchmark(
            component: .bitPlaneCoding,
            testCase: .codeBlock32x32,
            iterations: 50,
            warmupIterations: 5
        )
        
        let result = try benchmark.measureJ2KSwiftThrowing {
            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
            _ = try coder.encode(coefficients: coefficients, bitDepth: 10)
        }
        
        print(result.formattedSummary)
        
        XCTAssertLessThan(result.averageTime, 0.05,
                         "32x32 bit-plane coding should complete in under 50ms")
        XCTAssertGreaterThan(result.throughput, 20,
                            "Should achieve >20 ops/sec for 32x32 coding")
    }
    
    /// Benchmarks bit-plane coding of a 64x64 code-block.
    func testBitPlaneCoding64x64Benchmark() throws {
        let width = 64
        let height = 64
        let coefficients = (0..<(width * height)).map { _ in Int32.random(in: -255...255) }
        
        let benchmark = J2KReferenceBenchmark(
            component: .bitPlaneCoding,
            testCase: .codeBlock64x64,
            iterations: 20,
            warmupIterations: 3
        )
        
        let result = try benchmark.measureJ2KSwiftThrowing {
            let coder = BitPlaneCoder(width: width, height: height, subband: .hl)
            _ = try coder.encode(coefficients: coefficients, bitDepth: 10)
        }
        
        print(result.formattedSummary)
        
        XCTAssertLessThan(result.averageTime, 0.2,
                         "64x64 bit-plane coding should complete in under 200ms")
    }
    
    /// Benchmarks parallel code-block encoding with 16 blocks.
    func testParallelCodeBlocks16Benchmark() throws {
        let benchmark = J2KReferenceBenchmark(
            component: .parallelCodeBlocks,
            testCase: .codeBlocks16Parallel,
            iterations: 10,
            warmupIterations: 2
        )
        
        let image = createTestImage(width: 128, height: 128, components: 1)
        
        let result = try benchmark.measureJ2KSwiftThrowing {
            let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
                quality: 0.9,
                lossless: true,
                decompositionLevels: 2,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 1,
                enableParallelCodeBlocks: true
            ))
            _ = try pipeline.encode(image)
        }
        
        print(result.formattedSummary)
        
        XCTAssertLessThan(result.averageTime, 1.0,
                         "Parallel encoding of 128x128 image should complete in under 1s")
    }
    
    /// Benchmarks parallel vs sequential to measure speedup.
    func testParallelVsSequentialComparison() throws {
        let image = createTestImage(width: 128, height: 128, components: 1)
        let iterations = 5
        let warmup = 1
        
        // Sequential benchmark
        let seqBenchmark = J2KBenchmark(name: "Sequential Code-Block Encoding")
        let seqResult = try seqBenchmark.measureThrowing(iterations: iterations, warmupIterations: warmup) {
            let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
                quality: 0.9,
                lossless: true,
                decompositionLevels: 2,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 1,
                enableParallelCodeBlocks: false
            ))
            _ = try pipeline.encode(image)
        }
        
        // Parallel benchmark
        let parBenchmark = J2KBenchmark(name: "Parallel Code-Block Encoding")
        let parResult = try parBenchmark.measureThrowing(iterations: iterations, warmupIterations: warmup) {
            let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
                quality: 0.9,
                lossless: true,
                decompositionLevels: 2,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 1,
                enableParallelCodeBlocks: true
            ))
            _ = try pipeline.encode(image)
        }
        
        let comparison = parResult.compare(to: seqResult)
        print(comparison.summary)
        
        // Both should complete successfully
        XCTAssertGreaterThan(seqResult.averageTime, 0, "Sequential should have non-zero time")
        XCTAssertGreaterThan(parResult.averageTime, 0, "Parallel should have non-zero time")
    }
    
    /// Comprehensive reference benchmark suite including bit-plane coding.
    func testBitPlaneCodingReferenceSuite() throws {
        var results: [ReferenceBenchmarkResult] = []
        
        // 32x32 code-block encoding
        let coeffs32 = (0..<(32 * 32)).map { _ in Int32.random(in: -255...255) }
        let bench32 = J2KReferenceBenchmark(
            component: .bitPlaneCoding,
            testCase: .codeBlock32x32,
            iterations: 50,
            warmupIterations: 5
        )
        let result32 = try bench32.measureJ2KSwiftThrowing {
            let coder = BitPlaneCoder(width: 32, height: 32, subband: .ll)
            _ = try coder.encode(coefficients: coeffs32, bitDepth: 10)
        }
        results.append(result32)
        
        // 64x64 code-block encoding
        let coeffs64 = (0..<(64 * 64)).map { _ in Int32.random(in: -255...255) }
        let bench64 = J2KReferenceBenchmark(
            component: .bitPlaneCoding,
            testCase: .codeBlock64x64,
            iterations: 20,
            warmupIterations: 3
        )
        let result64 = try bench64.measureJ2KSwiftThrowing {
            let coder = BitPlaneCoder(width: 64, height: 64, subband: .hl)
            _ = try coder.encode(coefficients: coeffs64, bitDepth: 10)
        }
        results.append(result64)
        
        // Parallel code-block encoding
        let image = createTestImage(width: 64, height: 64, components: 1)
        let benchPar = J2KReferenceBenchmark(
            component: .parallelCodeBlocks,
            testCase: .codeBlocks16Parallel,
            iterations: 10,
            warmupIterations: 2
        )
        let resultPar = try benchPar.measureJ2KSwiftThrowing {
            let pipeline = EncoderPipeline(config: J2KEncodingConfiguration(
                quality: 0.9,
                lossless: true,
                decompositionLevels: 2,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 1,
                enableParallelCodeBlocks: true
            ))
            _ = try pipeline.encode(image)
        }
        results.append(resultPar)
        
        let suite = ReferenceBenchmarkSuite(results: results)
        
        print("\n")
        print(suite.formattedComparison)
        print("\n")
        print("CSV Export:")
        print(suite.csvExport)
        
        XCTAssertEqual(results.count, 3, "Should have 3 benchmark results")
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
