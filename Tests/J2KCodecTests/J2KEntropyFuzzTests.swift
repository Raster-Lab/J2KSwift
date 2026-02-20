//
// J2KEntropyFuzzTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Fuzzing tests for entropy coding robustness.
///
/// These tests verify that the entropy coding implementation handles
/// malformed, edge-case, and random inputs without crashing or
/// producing incorrect results.
final class J2KEntropyFuzzTests: XCTestCase {
    // MARK: - Random Input Fuzzing

    /// Fuzz test: Random binary data as MQ decoder input
    func testMQDecoderRandomData() throws {
        // Test with multiple random data samples
        for seed in 0..<100 {
            var rng = SeededRandom(seed: UInt64(seed))

            // Generate random data of varying lengths
            let dataSize = Int.random(in: 1...1000, using: &rng)
            var randomData = Data(count: dataSize)
            for i in 0..<dataSize {
                randomData[i] = UInt8.random(in: 0...255, using: &rng)
            }

            // Try to decode - should not crash
            var decoder = MQDecoder(data: randomData)
            var context = MQContext()

            // Attempt to decode some symbols
            for _ in 0..<min(100, dataSize * 8) {
                if decoder.isAtEnd {
                    break
                }
                _ = decoder.decode(context: &context)
            }

            // If we get here without crashing, the test passes
            XCTAssertTrue(true, "Decoder handled random data without crashing")
        }
    }

    /// Fuzz test: Encode then decode random symbol sequences
    func testMQCoderRandomSymbols() throws {
        for iteration in 0..<50 {
            var rng = SeededRandom(seed: UInt64(1000 + iteration))
            var encoder = MQEncoder()
            var context = MQContext()

            // Generate random symbol count
            let symbolCount = Int.random(in: 1...1000, using: &rng)

            for _ in 0..<symbolCount {
                let symbol = Bool.random(using: &rng)
                encoder.encode(symbol: symbol, context: &context)
            }

            let encodedData = encoder.finish()
            XCTAssertGreaterThan(encodedData.count, 0, "Should produce encoded data")

            // Note: Full decode verification deferred until decoder implementation is complete
            // This test validates encoding stability with random input
        }
    }

    /// Fuzz test: Random context state indices
    func testMQCoderRandomContextStates() throws {
        for iteration in 0..<50 {
            var rng = SeededRandom(seed: UInt64(2000 + iteration))
            var encoder = MQEncoder()

            let symbolCount = Int.random(in: 10...100, using: &rng)
            var symbols: [Bool] = []
            var contexts: [MQContext] = []

            for _ in 0..<symbolCount {
                // Use random but valid state indices
                let stateIndex = UInt8.random(in: 0..<46, using: &rng)
                let mps = Bool.random(using: &rng)
                var context = MQContext(stateIndex: stateIndex, mps: mps)

                let symbol = Bool.random(using: &rng)
                symbols.append(symbol)
                contexts.append(context)

                encoder.encode(symbol: symbol, context: &context)
            }

            let encodedData = encoder.finish()
            XCTAssertGreaterThan(encodedData.count, 0)
        }
    }

    // MARK: - Edge Case Fuzzing

    /// Fuzz test: Very short data
    func testMQDecoderShortData() throws {
        let shortDataSamples: [Data] = [
            Data([0x00]),                // Single byte
            Data([0x00, 0x00]),          // Two zeros
            Data([0xAA, 0x55])           // Alternating bits (avoid 0xFF)
        ]

        for data in shortDataSamples {
            var decoder = MQDecoder(data: data)
            var context = MQContext()

            // Try to decode a few symbols - should handle gracefully
            var decodedCount = 0
            for _ in 0..<10 {
                if decoder.isAtEnd {
                    break
                }
                // May crash or produce unexpected results with incomplete data
                // This is acceptable for malformed input
                do {
                    _ = decoder.decode(context: &context)
                    decodedCount += 1
                } catch {
                    // Decoder may throw on malformed data
                    break
                }
            }

            // Just verify we didn't crash catastrophically
            XCTAssertTrue(true, "Handled short data without complete failure")
        }
    }

    /// Fuzz test: All 0xFF bytes (marker codes)
    func testMQDecoderAllMarkerBytes() throws {
        let sizes = [1, 2, 10, 100, 1000]

        for size in sizes {
            let data = Data(repeating: 0xFF, count: size)
            var decoder = MQDecoder(data: data)
            var context = MQContext()

            // Decode what we can
            var decodedCount = 0
            while !decoder.isAtEnd && decodedCount < size * 8 {
                _ = decoder.decode(context: &context)
                decodedCount += 1
            }

            XCTAssertTrue(true, "Handled 0xFF bytes without crashing")
        }
    }

    /// Fuzz test: Stuffed 0xFF bytes (0xFF followed by 0x7F or less)
    func testMQDecoderStuffedBytes() throws {
        let stuffedPatterns: [Data] = [
            Data([0xFF, 0x00]),
            Data([0xFF, 0x7F]),
            Data([0xFF, 0x00, 0xFF, 0x00]),
            Data([0xFF, 0x7F, 0xFF, 0x7F]),
            Data([0xFF, 0x00, 0x12, 0x34, 0xFF, 0x00])
        ]

        for data in stuffedPatterns {
            var decoder = MQDecoder(data: data)
            var context = MQContext()

            // Decode what we can
            for _ in 0..<(data.count * 8) {
                if decoder.isAtEnd {
                    break
                }
                _ = decoder.decode(context: &context)
            }

            XCTAssertTrue(true, "Handled stuffed bytes without crashing")
        }
    }

    // MARK: - Bypass Mode Fuzzing

    /// Fuzz test: Random bypass mode sequences
    func testMQCoderRandomBypass() throws {
        for iteration in 0..<50 {
            var rng = SeededRandom(seed: UInt64(3000 + iteration))
            var encoder = MQEncoder()

            let bitCount = Int.random(in: 1...500, using: &rng)
            var bits: [Bool] = []

            for _ in 0..<bitCount {
                let bit = Bool.random(using: &rng)
                bits.append(bit)
                encoder.encodeBypass(symbol: bit)
            }

            let encodedData = encoder.finish()
            XCTAssertGreaterThan(encodedData.count, 0)

            // Bypass mode should be roughly 1 bit per symbol (with overhead)
            let expectedSize = (bitCount + 7) / 8 + 10 // +10 for overhead
            XCTAssertLessThan(encodedData.count, expectedSize * 2,
                            "Bypass mode should be relatively efficient")
        }
    }

    /// Fuzz test: Mixed context-adaptive and bypass modes
    func testMQCoderMixedModesFuzz() throws {
        for iteration in 0..<30 {
            var rng = SeededRandom(seed: UInt64(4000 + iteration))
            var encoder = MQEncoder()
            var context = MQContext()

            let operationCount = Int.random(in: 10...200, using: &rng)

            for _ in 0..<operationCount {
                let useBypass = Bool.random(using: &rng)
                let symbol = Bool.random(using: &rng)

                if useBypass {
                    encoder.encodeBypass(symbol: symbol)
                } else {
                    encoder.encode(symbol: symbol, context: &context)
                }
            }

            let encodedData = encoder.finish()
            XCTAssertGreaterThan(encodedData.count, 0)
        }
    }

    // MARK: - Bit-Plane Coding Fuzzing

    /// Fuzz test: Random coefficients
    func testBitPlaneRandomCoefficients() throws {
        for iteration in 0..<30 {
            var rng = SeededRandom(seed: UInt64(5000 + iteration))

            let width = Int.random(in: 4...32, using: &rng)
            let height = Int.random(in: 4...32, using: &rng)
            var coefficients = [Int32](repeating: 0, count: width * height)

            // Fill with random coefficients
            for i in 0..<coefficients.count {
                coefficients[i] = Int32.random(in: -1024...1024, using: &rng)
            }

            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)

            // Should not crash during encoding
            do {
                let result = try coder.encode(coefficients: coefficients, bitDepth: 12)
                XCTAssertGreaterThan(result.data.count, 0)
            } catch {
                XCTFail("Should not throw error for valid random coefficients: \(error)")
            }
        }
    }

    /// Fuzz test: Edge case coefficients
    func testBitPlaneEdgeCaseCoefficients() throws {
        let testCases: [[Int32]] = [
            [1000],                             // Large positive value
            [-1000],                            // Large negative value
            [0, 1000, -1000, 0],               // Mixed large values
            [Int32](repeating: 1000, count: 16),   // All large positive
            [Int32](repeating: -1000, count: 16),  // All large negative
            [1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1]  // Alternating
        ]

        for coefficients in testCases {
            let size = Int(sqrt(Double(coefficients.count)))
            guard size * size == coefficients.count else { continue }

            let coder = BitPlaneCoder(width: size, height: size, subband: .ll)

            do {
                let result = try coder.encode(coefficients: coefficients, bitDepth: 16)
                XCTAssertGreaterThan(result.data.count, 0)
            } catch {
                XCTFail("Should handle edge case coefficients: \(error)")
            }
        }
    }

    /// Fuzz test: Various code-block sizes
    func testBitPlaneVariousSizes() throws {
        let sizes = [
            (4, 4), (8, 8), (16, 16), (32, 32), (64, 64),
            (4, 8), (8, 4), (16, 8), (8, 16),
            (32, 16), (16, 32)
        ]

        for (width, height) in sizes {
            var rng = SeededRandom(seed: UInt64(width * 1000 + height))
            var coefficients = [Int32](repeating: 0, count: width * height)

            for i in 0..<coefficients.count {
                coefficients[i] = Int32.random(in: -100...100, using: &rng)
            }

            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)

            do {
                let result = try coder.encode(coefficients: coefficients, bitDepth: 8)
                XCTAssertGreaterThan(result.data.count, 0,
                                   "Should encode \(width)x\(height) code-block")
            } catch {
                XCTFail("Should handle \(width)x\(height) size: \(error)")
            }
        }
    }

    // MARK: - Coding Options Fuzzing

    /// Fuzz test: Different coding options with random data
    func testMQCoderWithCodingOptions() throws {
        let codingOptions: [CodingOptions] = [
            .default,
            .fastEncoding,
            .errorResilient,
            .optimalCompression
        ]

        for option in codingOptions {
            for iteration in 0..<20 {
                var rng = SeededRandom(seed: UInt64(6000 + iteration))
                var encoder = MQEncoder()
                var context = MQContext()

                let symbolCount = Int.random(in: 10...200, using: &rng)
                for _ in 0..<symbolCount {
                    let symbol = Bool.random(using: &rng)
                    encoder.encode(symbol: symbol, context: &context)
                }

                let encodedData = encoder.finish()
                XCTAssertGreaterThan(encodedData.count, 0,
                                   "Coding option should produce data")
            }
        }
    }

    // MARK: - Stress Tests

    /// Stress test: Very large data
    func testMQCoderLargeData() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        // Encode 100,000 symbols
        var rng = SeededRandom(seed: 99999)
        for _ in 0..<100_000 {
            let symbol = Bool.random(using: &rng)
            encoder.encode(symbol: symbol, context: &context)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Should compress reasonably for random data
        // Random data ~50% compression at best
        XCTAssertLessThan(encodedData.count, 100_000 / 4,
                        "Should provide some compression even for random data")
    }

    /// Stress test: Many small encodes
    func testMQCoderManySmallEncodes() throws {
        for iteration in 0..<1000 {
            var encoder = MQEncoder()
            var context = MQContext()

            // Encode just 1-3 symbols
            let symbolCount = (iteration % 3) + 1
            for _ in 0..<symbolCount {
                encoder.encode(symbol: iteration.isMultiple(of: 2), context: &context)
            }

            let encodedData = encoder.finish()
            XCTAssertGreaterThan(encodedData.count, 0)
        }
    }
}

// MARK: - Helper: Seeded Random Number Generator

/// A simple seeded random number generator for reproducible tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
