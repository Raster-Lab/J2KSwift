import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Performance benchmarks for entropy coding (MQ-coder and bit-plane coding).
///
/// This test suite benchmarks the performance-critical paths in JPEG 2000 entropy coding,
/// including MQ encoding/decoding, context modeling, and bit-plane operations.
final class J2KEntropyBenchmarkTests: XCTestCase {
    // MARK: - Test Configuration

    /// Number of iterations for each benchmark.
    private let benchmarkIterations = 100

    /// Number of warmup iterations.
    private let warmupIterations = 5

    // MARK: - MQ Encoder Benchmarks

    /// Benchmarks MQ encoding with a uniform bit pattern.
    func testMQEncoderUniformPattern() throws {
        let benchmark = J2KBenchmark(name: "MQ Encoder - Uniform Pattern (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()
            var context = MQContext()

            // Encode 1000 alternating bits
            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)

        // Sanity check: should complete reasonably fast
        XCTAssertLessThan(result.averageTime, 0.01, "MQ encoding should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with random data.
    func testMQEncoderRandomPattern() throws {
        // Pre-generate random bit pattern
        let symbols = (0..<1000).map { _ in Bool.random() }

        let benchmark = J2KBenchmark(name: "MQ Encoder - Random Pattern (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()
            var context = MQContext()

            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ encoding should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with skewed data (mostly zeros).
    func testMQEncoderSkewedPattern() throws {
        let benchmark = J2KBenchmark(name: "MQ Encoder - Skewed Pattern (1000 symbols, 90% zeros)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()
            var context = MQContext()

            // Encode mostly zeros (90%)
            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 10), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ encoding should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with bypass (uniform) mode.
    func testMQEncoderBypassMode() throws {
        let benchmark = J2KBenchmark(name: "MQ Encoder - Bypass Mode (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()

            for i in 0..<1000 {
                encoder.encodeBypass(symbol: i.isMultiple(of: 2))
            }

            _ = encoder.finish()
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ bypass encoding should complete in under 10ms")
    }

    /// Benchmarks MQ encoding with multiple contexts.
    func testMQEncoderMultipleContexts() throws {
        let benchmark = J2KBenchmark(name: "MQ Encoder - Multiple Contexts (10 contexts, 100 symbols each)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()
            var contexts = (0..<10).map { _ in MQContext() }

            // Encode with different contexts
            for i in 0..<1000 {
                let contextIndex = i % 10
                encoder.encode(symbol: i.isMultiple(of: 2), context: &contexts[contextIndex])
            }

            _ = encoder.finish()
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ encoding with multiple contexts should complete in under 10ms")
    }

    // MARK: - MQ Decoder Benchmarks

    /// Benchmarks MQ decoding with uniform pattern.
    func testMQDecoderUniformPattern() throws {
        // Pre-encode data
        var encoder = MQEncoder()
        var encodeContext = MQContext()
        for i in 0..<1000 {
            encoder.encode(symbol: i.isMultiple(of: 2), context: &encodeContext)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KBenchmark(name: "MQ Decoder - Uniform Pattern (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var decoder = MQDecoder(data: encodedData)
            var context = MQContext()

            for _ in 0..<1000 {
                _ = decoder.decode(context: &context)
            }
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ decoding should complete in under 10ms")
    }

    /// Benchmarks MQ decoding with random pattern.
    func testMQDecoderRandomPattern() throws {
        // Pre-encode random data
        let symbols = (0..<1000).map { _ in Bool.random() }
        var encoder = MQEncoder()
        var encodeContext = MQContext()
        for symbol in symbols {
            encoder.encode(symbol: symbol, context: &encodeContext)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KBenchmark(name: "MQ Decoder - Random Pattern (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var decoder = MQDecoder(data: encodedData)
            var context = MQContext()

            for _ in 0..<1000 {
                _ = decoder.decode(context: &context)
            }
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ decoding should complete in under 10ms")
    }

    /// Benchmarks MQ decoding with bypass mode.
    func testMQDecoderBypassMode() throws {
        // Pre-encode data in bypass mode
        var encoder = MQEncoder()
        for i in 0..<1000 {
            encoder.encodeBypass(symbol: i.isMultiple(of: 2))
        }
        let encodedData = encoder.finish()

        let benchmark = J2KBenchmark(name: "MQ Decoder - Bypass Mode (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var decoder = MQDecoder(data: encodedData)

            for _ in 0..<1000 {
                _ = decoder.decodeBypass()
            }
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.01, "MQ bypass decoding should complete in under 10ms")
    }

    // MARK: - Round-trip Benchmarks

    /// Benchmarks complete encode/decode round-trip.
    func testMQRoundTripBenchmark() throws {
        let symbols = (0..<1000).map { _ in Bool.random() }

        let benchmark = J2KBenchmark(name: "MQ Round-trip (1000 symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            // Encode
            var encoder = MQEncoder()
            var encodeContext = MQContext()
            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &encodeContext)
            }
            let encodedData = encoder.finish()

            // Decode
            var decoder = MQDecoder(data: encodedData)
            var decodeContext = MQContext()
            for _ in 0..<symbols.count {
                _ = decoder.decode(context: &decodeContext)
            }
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.02, "MQ round-trip should complete in under 20ms")
    }

    // MARK: - Large Data Benchmarks

    /// Benchmarks MQ encoding with large data set (10K symbols).
    func testMQEncoderLargeDataSet() throws {
        let symbols = (0..<10000).map { _ in Bool.random() }

        let benchmark = J2KBenchmark(name: "MQ Encoder - Large Data (10K symbols)")

        let result = benchmark.measure(iterations: 50, warmupIterations: 3) {
            var encoder = MQEncoder()
            var context = MQContext()

            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.1, "MQ encoding large data should complete in under 100ms")
    }

    /// Benchmarks MQ decoding with large data set (10K symbols).
    func testMQDecoderLargeDataSet() throws {
        // Pre-encode large data
        let symbols = (0..<10000).map { _ in Bool.random() }
        var encoder = MQEncoder()
        var encodeContext = MQContext()
        for symbol in symbols {
            encoder.encode(symbol: symbol, context: &encodeContext)
        }
        let encodedData = encoder.finish()

        let benchmark = J2KBenchmark(name: "MQ Decoder - Large Data (10K symbols)")

        let result = benchmark.measure(iterations: 50, warmupIterations: 3) {
            var decoder = MQDecoder(data: encodedData)
            var context = MQContext()

            for _ in 0..<10000 {
                _ = decoder.decode(context: &context)
            }
        }

        print(result.summary)
        XCTAssertLessThan(result.averageTime, 0.1, "MQ decoding large data should complete in under 100ms")
    }

    // MARK: - Termination Mode Benchmarks

    /// Benchmarks different termination modes.
    func testMQEncoderTerminationModes() throws {
        let symbols = (0..<1000).map { _ in Bool.random() }

        // Benchmark default termination
        let defaultBenchmark = J2KBenchmark(name: "MQ Encoder - Default Termination")
        let defaultResult = defaultBenchmark.measure(iterations: benchmarkIterations) {
            var encoder = MQEncoder()
            var context = MQContext()
            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }
            _ = encoder.finish(mode: .default)
        }
        print(defaultResult.summary)

        // Benchmark predictable termination
        let predictableBenchmark = J2KBenchmark(name: "MQ Encoder - Predictable Termination")
        let predictableResult = predictableBenchmark.measure(iterations: benchmarkIterations) {
            var encoder = MQEncoder()
            var context = MQContext()
            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }
            _ = encoder.finish(mode: .predictable)
        }
        print(predictableResult.summary)

        // Benchmark near-optimal termination
        let nearOptimalBenchmark = J2KBenchmark(name: "MQ Encoder - Near-Optimal Termination")
        let nearOptimalResult = nearOptimalBenchmark.measure(iterations: benchmarkIterations) {
            var encoder = MQEncoder()
            var context = MQContext()
            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }
            _ = encoder.finish(mode: .nearOptimal)
        }
        print(nearOptimalResult.summary)

        // Compare results
        let comparison = nearOptimalResult.compare(to: defaultResult)
        print(comparison.summary)
    }

    // MARK: - Context State Transition Benchmarks

    /// Benchmarks context state transitions in different probability regions.
    func testMQContextStateTransitions() throws {
        let benchmark = J2KBenchmark(name: "MQ Context State Transitions")

        let result = benchmark.measure(iterations: benchmarkIterations, warmupIterations: warmupIterations) {
            var encoder = MQEncoder()
            var context = MQContext()

            // Force state transitions by encoding alternating patterns
            for _ in 0..<100 {
                // Encode 5 MPS to move to lower probability states
                for _ in 0..<5 {
                    encoder.encode(symbol: false, context: &context)
                }
                // Encode 1 LPS to trigger state change
                encoder.encode(symbol: true, context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)
    }

    // MARK: - Memory Allocation Benchmarks

    /// Benchmarks memory allocation patterns in MQ encoder.
    func testMQEncoderMemoryAllocation() throws {
        let benchmark = J2KBenchmark(name: "MQ Encoder - Memory Allocation (1K symbols)")

        let result = benchmark.measure(iterations: benchmarkIterations) {
            // Create fresh encoder to measure allocation overhead
            var encoder = MQEncoder()
            var context = MQContext()

            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
            }

            _ = encoder.finish()
        }

        print(result.summary)
    }

    // MARK: - Compression Ratio Analysis

    /// Tests compression effectiveness for different data patterns.
    func testCompressionRatiosForPatterns() throws {
        print("\n" + "═" * 60)
        print("Compression Ratio Analysis")
        print("═" * 60)

        // Test 1: All zeros (highly compressible)
        do {
            var encoder = MQEncoder()
            var context = MQContext()
            for _ in 0..<1000 {
                encoder.encode(symbol: false, context: &context)
            }
            let data = encoder.finish()
            let ratio = 1000.0 / Double(data.count * 8)
            print("All zeros (1000 bits): \(data.count) bytes, ratio: \(String(format: "%.2f", ratio)):1")
        }

        // Test 2: Alternating pattern
        do {
            var encoder = MQEncoder()
            var context = MQContext()
            for i in 0..<1000 {
                encoder.encode(symbol: i.isMultiple(of: 2), context: &context)
            }
            let data = encoder.finish()
            let ratio = 1000.0 / Double(data.count * 8)
            print("Alternating (1000 bits): \(data.count) bytes, ratio: \(String(format: "%.2f", ratio)):1")
        }

        // Test 3: Random data
        do {
            var encoder = MQEncoder()
            var context = MQContext()
            let symbols = (0..<1000).map { _ in Bool.random() }
            for symbol in symbols {
                encoder.encode(symbol: symbol, context: &context)
            }
            let data = encoder.finish()
            let ratio = 1000.0 / Double(data.count * 8)
            print("Random (1000 bits): \(data.count) bytes, ratio: \(String(format: "%.2f", ratio)):1")
        }

        print("═" * 60 + "\n")
    }
}

// MARK: - Helper for String Repetition

private func *(lhs: String, rhs: Int) -> String {
    String(repeating: lhs, count: rhs)
}
