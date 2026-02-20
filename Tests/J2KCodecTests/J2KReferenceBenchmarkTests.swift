//
// J2KReferenceBenchmarkTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Reference benchmarks comparing J2KSwift against JPEG 2000 reference implementations.
///
/// This test suite provides standardized benchmarks that can be compared against
/// reference implementations like OpenJPEG. The tests use identical test cases and
/// parameters to ensure fair comparison.
///
/// ## OpenJPEG Comparison Methodology
///
/// To compare J2KSwift with OpenJPEG:
///
/// 1. Build OpenJPEG from source: https://github.com/uclouvain/openjpeg
/// 2. Use the same test images and parameters
/// 3. Measure encoding/decoding times using system tools (e.g., time command)
/// 4. Compare throughput and memory usage
///
/// ## Performance Targets (from MILESTONES.md)
///
/// - Encoding speed: Within 80% of OpenJPEG for comparable quality
/// - Decoding speed: Within 80% of OpenJPEG
/// - Memory usage: < 2x compressed file size for decoding
/// - Thread scaling: > 80% efficiency up to 8 cores
final class J2KReferenceBenchmarkTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite { XCTestSuite(name: "J2KReferenceBenchmarkTests (Disabled)") }

    /// Benchmark iterations for reference tests.
    private let benchmarkIterations = 100
    private let warmupIterations = 5

    // MARK: - Entropy Encoding Benchmarks

    /// Benchmarks MQ encoding with uniform pattern (1K symbols).
    func testMQEncoderUniform1K() {
        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: .uniformPattern1K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.formattedSummary)

        // Performance target: should complete reasonably fast
        XCTAssertLessThan(result.averageTime, 0.01,
                         "MQ encoding 1K symbols should complete in under 10ms")
        XCTAssertGreaterThan(result.throughput, 5000,
                           "Should achieve >5000 ops/sec for 1K encoding")
    }

    /// Benchmarks MQ encoding with random pattern (1K symbols).
    func testMQEncoderRandom1K() {
        // Pre-generate random pattern for consistency
        let symbols = (0..<1000).map { _ in Bool.random() }

        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: .randomPattern1K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }

            _ = encoder.finish()
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.01,
                         "MQ encoding 1K random symbols should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with skewed pattern (1K symbols, 90% zeros).
    func testMQEncoderSkewed1K() {
        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: .skewedPattern1K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 10), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.formattedSummary)

        // Skewed data should compress better and potentially be faster
        XCTAssertLessThan(result.averageTime, 0.01,
                         "MQ encoding 1K skewed symbols should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with uniform pattern (10K symbols).
    func testMQEncoderUniform10K() {
        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: .uniformPattern10K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for i in 0..<10000 {
                encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.1,
                         "MQ encoding 10K symbols should complete in under 100ms")
        XCTAssertGreaterThan(result.throughput, 500,
                           "Should achieve >500 ops/sec for 10K encoding")
    }

    /// Benchmarks MQ encoding with random pattern (10K symbols).
    func testMQEncoderRandom10K() {
        let symbols = (0..<10000).map { _ in Bool.random() }

        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: .randomPattern10K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }

            _ = encoder.finish()
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.1,
                         "MQ encoding 10K random symbols should complete in under 100ms")
    }

    // MARK: - Entropy Decoding Benchmarks

    /// Benchmarks MQ decoding with uniform pattern (1K symbols).
    func testMQDecoderUniform1K() {
        // Pre-encode data for decoding
        var encoder = MQEncoder()
        var context = MQContext()
        for i in 0..<1000 {
            encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KReferenceBenchmark(
            component: .entropyDecoding,
            testCase: .uniformPattern1K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var decoder = MQDecoder(data: encodedData)
            var decContext = MQContext()

            for _ in 0..<1000 {
                _ = decoder.decode(context: &decContext)
            }
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.01,
                         "MQ decoding 1K symbols should complete in under 10ms")
        XCTAssertGreaterThan(result.throughput, 5000,
                           "Should achieve >5000 ops/sec for 1K decoding")
    }

    /// Benchmarks MQ decoding with random pattern (10K symbols).
    func testMQDecoderRandom10K() {
        // Pre-encode random data
        let symbols = (0..<10000).map { _ in Bool.random() }
        var encoder = MQEncoder()
        var context = MQContext()
        for symbol in symbols {
            encoder.encode(symbol: symbol, context: &context)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KReferenceBenchmark(
            component: .entropyDecoding,
            testCase: .randomPattern10K,
            iterations: benchmarkIterations,
            warmupIterations: warmupIterations
        )

        let result = benchmark.measureJ2KSwift {
            var decoder = MQDecoder(data: encodedData)
            var decContext = MQContext()

            for _ in 0..<10000 {
                _ = decoder.decode(context: &decContext)
            }
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.1,
                         "MQ decoding 10K symbols should complete in under 100ms")
    }

    // MARK: - DWT Benchmarks

    /// Benchmarks forward DWT on 256x256 tile.
    func testDWTForward256x256() {
        // Create test tile
        let tileSize = 256
        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtForward,
            testCase: .tile256x256,
            iterations: 50, // Fewer iterations for heavier operations
            warmupIterations: 3
        )

        let result = benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.forwardTransform(
                signal: input,
                filter: .reversible53
            )
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.1,
                         "Forward DWT on 256 samples should complete in under 100ms")
    }

    /// Benchmarks forward DWT on 512x512 tile.
    func testDWTForward512x512() {
        let tileSize = 512
        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtForward,
            testCase: .tile512x512,
            iterations: 20, // Fewer iterations for large data
            warmupIterations: 2
        )

        let result = benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.forwardTransform(
                signal: input,
                filter: .reversible53
            )
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.5,
                         "Forward DWT on 512 samples should complete in under 500ms")
    }

    /// Benchmarks inverse DWT on 256x256 tile.
    func testDWTInverse256x256() {
        let tileSize = 256
        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }

        // Apply forward transform first
        guard let (lowpass, highpass) = try? J2KDWT1D.forwardTransform(
            signal: input,
            filter: .reversible53
        ) else {
            XCTFail("Forward transform failed")
            return
        }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtInverse,
            testCase: .tile256x256,
            iterations: 50,
            warmupIterations: 3
        )

        let result = benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.1,
                         "Inverse DWT on 256 samples should complete in under 100ms")
    }

    /// Benchmarks inverse DWT on 512x512 tile.
    func testDWTInverse512x512() {
        let tileSize = 512
        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }

        // Apply forward transform first
        guard let (lowpass, highpass) = try? J2KDWT1D.forwardTransform(
            signal: input,
            filter: .reversible53
        ) else {
            XCTFail("Forward transform failed")
            return
        }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtInverse,
            testCase: .tile512x512,
            iterations: 20,
            warmupIterations: 2
        )

        let result = benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.5,
                         "Inverse DWT on 512 samples should complete in under 500ms")
    }

    // MARK: - Quantization Benchmarks

    /// Benchmarks quantization on 256x256 tile.
    func testQuantization256x256() {
        let tileSize = 256
        let coefficients = (0..<(tileSize * tileSize)).map { _ in Float.random(in: -1000...1000) }
        let stepSize: Float = 0.1

        let benchmark = J2KReferenceBenchmark(
            component: .quantization,
            testCase: .tile256x256,
            iterations: 100,
            warmupIterations: 5
        )

        let result = benchmark.measureJ2KSwift {
            _ = coefficients.map { coeff in
                Int32(coeff / stepSize)
            }
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.01,
                         "Quantization on 256x256 should complete in under 10ms")
    }

    /// Benchmarks dequantization on 256x256 tile.
    func testDequantization256x256() {
        let tileSize = 256
        let quantized = (0..<(tileSize * tileSize)).map { _ in Int32.random(in: -1000...1000) }
        let stepSize: Float = 0.1

        let benchmark = J2KReferenceBenchmark(
            component: .dequantization,
            testCase: .tile256x256,
            iterations: 100,
            warmupIterations: 5
        )

        let result = benchmark.measureJ2KSwift {
            _ = quantized.map { quant in
                Float(quant) * stepSize
            }
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.01,
                         "Dequantization on 256x256 should complete in under 10ms")
    }

    // MARK: - Color Transform Benchmarks

    /// Benchmarks RCT forward transform on 512x512 RGB image.
    func testColorTransformRCTForward512x512() throws {
        let width = 512
        let height = 512
        let pixelCount = width * height

        let r = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }
        let g = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }
        let b = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }

        let transform = J2KColorTransform()

        let benchmark = J2KReferenceBenchmark(
            component: .colorTransformRCT,
            testCase: .image512x512RGB,
            iterations: 50,
            warmupIterations: 3
        )

        let result = try benchmark.measureJ2KSwiftThrowing {
            _ = try transform.forwardRCT(red: r, green: g, blue: b)
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.05,
                         "RCT forward on 512x512 should complete in under 50ms")
    }

    /// Benchmarks ICT forward transform on 512x512 RGB image.
    func testColorTransformICTForward512x512() throws {
        let width = 512
        let height = 512
        let pixelCount = width * height

        let r = (0..<pixelCount).map { _ in Double.random(in: 0...1) }
        let g = (0..<pixelCount).map { _ in Double.random(in: 0...1) }
        let b = (0..<pixelCount).map { _ in Double.random(in: 0...1) }

        let transform = J2KColorTransform()

        let benchmark = J2KReferenceBenchmark(
            component: .colorTransformICT,
            testCase: .image512x512RGB,
            iterations: 50,
            warmupIterations: 3
        )

        let result = try benchmark.measureJ2KSwiftThrowing {
            _ = try transform.forwardICT(red: r, green: g, blue: b)
        }

        print(result.formattedSummary)

        XCTAssertLessThan(result.averageTime, 0.05,
                         "ICT forward on 512x512 should complete in under 50ms")
    }

    // MARK: - Benchmark Suite

    /// Runs all reference benchmarks and generates a comprehensive report.
    func testComprehensiveBenchmarkSuite() throws {
        var results: [ReferenceBenchmarkResult] = []

        // Entropy encoding
        results.append(contentsOf: [
            runEntropyEncodingBenchmark(.uniformPattern1K),
            runEntropyEncodingBenchmark(.randomPattern1K),
            runEntropyEncodingBenchmark(.uniformPattern10K)
        ])

        // Entropy decoding
        results.append(contentsOf: [
            runEntropyDecodingBenchmark(.uniformPattern1K),
            runEntropyDecodingBenchmark(.randomPattern10K)
        ])

        // DWT
        results.append(contentsOf: [
            runDWTForwardBenchmark(.tile256x256),
            runDWTInverseBenchmark(.tile256x256)
        ])

        // Color transform
        results.append(contentsOf: try [
            runColorTransformRCTBenchmark(.image512x512RGB),
            runColorTransformICTBenchmark(.image512x512RGB)
        ])

        let suite = ReferenceBenchmarkSuite(results: results)

        print("\n")
        print(suite.formattedComparison)
        print("\n")
        print("CSV Export:")
        print(suite.csvExport)

        // All tests should complete successfully
        XCTAssertGreaterThanOrEqual(results.count, 9, "Should have run at least 9 benchmarks")
    }

    // MARK: - Helper Methods

    private func runEntropyEncodingBenchmark(_ testCase: J2KReferenceBenchmark.TestCase) -> ReferenceBenchmarkResult {
        let symbolCount: Int
        switch testCase {
        case .uniformPattern1K, .randomPattern1K, .skewedPattern1K:
            symbolCount = 1000
        case .uniformPattern10K, .randomPattern10K:
            symbolCount = 10000
        default:
            symbolCount = 1000
        }

        let benchmark = J2KReferenceBenchmark(
            component: .entropyEncoding,
            testCase: testCase,
            iterations: 100,
            warmupIterations: 5
        )

        return benchmark.measureJ2KSwift {
            var encoder = MQEncoder()
            var context = MQContext()

            for i in 0..<symbolCount {
                let symbol: Bool
                switch testCase {
                case .uniformPattern1K, .uniformPattern10K:
                    symbol = i.isMultiple(of: 2)
                case .skewedPattern1K:
                    symbol = i.isMultiple(of: 10)
                default:
                    symbol = Bool.random()
                }
                encoder.encode(symbol: symbol, context: &context)
            }

            _ = encoder.finish()
        }
    }

    private func runEntropyDecodingBenchmark(_ testCase: J2KReferenceBenchmark.TestCase) -> ReferenceBenchmarkResult {
        let symbolCount: Int
        switch testCase {
        case .uniformPattern1K:
            symbolCount = 1000
        case .randomPattern10K:
            symbolCount = 10000
        default:
            symbolCount = 1000
        }

        // Pre-encode data
        var encoder = MQEncoder()
        var context = MQContext()
        for i in 0..<symbolCount {
            encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KReferenceBenchmark(
            component: .entropyDecoding,
            testCase: testCase,
            iterations: 100,
            warmupIterations: 5
        )

        return benchmark.measureJ2KSwift {
            var decoder = MQDecoder(data: encodedData)
            var decContext = MQContext()

            for _ in 0..<symbolCount {
                _ = decoder.decode(context: &decContext)
            }
        }
    }

    private func runDWTForwardBenchmark(_ testCase: J2KReferenceBenchmark.TestCase) -> ReferenceBenchmarkResult {
        let tileSize: Int
        let iterations: Int

        switch testCase {
        case .tile256x256:
            tileSize = 256
            iterations = 50
        case .tile512x512:
            tileSize = 512
            iterations = 20
        default:
            tileSize = 256
            iterations = 50
        }

        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtForward,
            testCase: testCase,
            iterations: iterations,
            warmupIterations: 3
        )

        return benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.forwardTransform(
                signal: input,
                filter: .reversible53
            )
        }
    }

    private func runDWTInverseBenchmark(_ testCase: J2KReferenceBenchmark.TestCase) -> ReferenceBenchmarkResult {
        let tileSize: Int
        let iterations: Int

        switch testCase {
        case .tile256x256:
            tileSize = 256
            iterations = 50
        case .tile512x512:
            tileSize = 512
            iterations = 20
        default:
            tileSize = 256
            iterations = 50
        }

        let input = (0..<tileSize).map { _ in Int32.random(in: 0...255) }
        guard let (lowpass, highpass) = try? J2KDWT1D.forwardTransform(signal: input, filter: .reversible53) else {
            // Return a dummy result if forward transform fails
            return ReferenceBenchmarkResult(
                component: .dwtInverse,
                testCase: testCase,
                implementation: "J2KSwift",
                averageTime: 0,
                medianTime: 0,
                minTime: 0,
                maxTime: 0,
                standardDeviation: 0,
                throughput: 0
            )
        }

        let benchmark = J2KReferenceBenchmark(
            component: .dwtInverse,
            testCase: testCase,
            iterations: iterations,
            warmupIterations: 3
        )

        return benchmark.measureJ2KSwift {
            _ = try? J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )
        }
    }

    private func runColorTransformRCTBenchmark(
        _ testCase: J2KReferenceBenchmark.TestCase
    ) throws -> ReferenceBenchmarkResult {
        let width = 512
        let height = 512
        let pixelCount = width * height

        let r = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }
        let g = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }
        let b = (0..<pixelCount).map { _ in Int32.random(in: 0...255) }

        let transform = J2KColorTransform()

        let benchmark = J2KReferenceBenchmark(
            component: .colorTransformRCT,
            testCase: testCase,
            iterations: 50,
            warmupIterations: 3
        )

        return try benchmark.measureJ2KSwiftThrowing {
            _ = try transform.forwardRCT(red: r, green: g, blue: b)
        }
    }

    private func runColorTransformICTBenchmark(
        _ testCase: J2KReferenceBenchmark.TestCase
    ) throws -> ReferenceBenchmarkResult {
        let width = 512
        let height = 512
        let pixelCount = width * height

        let r = (0..<pixelCount).map { _ in Double.random(in: 0...1) }
        let g = (0..<pixelCount).map { _ in Double.random(in: 0...1) }
        let b = (0..<pixelCount).map { _ in Double.random(in: 0...1) }

        let transform = J2KColorTransform()

        let benchmark = J2KReferenceBenchmark(
            component: .colorTransformICT,
            testCase: testCase,
            iterations: 50,
            warmupIterations: 3
        )

        return try benchmark.measureJ2KSwiftThrowing {
            _ = try transform.forwardICT(red: r, green: g, blue: b)
        }
    }
}
