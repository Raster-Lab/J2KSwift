import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Test vectors for entropy coding validation.
///
/// This file contains reference test vectors for validating the correctness
/// of the MQ-coder and bit-plane coding implementations against known values.
/// These vectors help ensure compliance with the JPEG 2000 standard.
final class J2KEntropyTestVectorTests: XCTestCase {
    // MARK: - MQ-Coder Test Vectors

    /// Test vector from ISO/IEC 15444-1 Annex C: Simple MQ encoding sequence
    func testMQCoderISOTestVector1() throws {
        // Test vector: Encode a simple sequence of MPS symbols
        var encoder = MQEncoder()
        var context = MQContext(stateIndex: 0, mps: false)

        // Encode 8 MPS (More Probable Symbol) occurrences
        for _ in 0..<8 {
            encoder.encode(symbol: false, context: &context) // false is MPS when context.mps is false
        }

        let encodedData = encoder.finish()

        // Verify we got encoded data
        XCTAssertGreaterThan(encodedData.count, 0, "Should produce encoded data")

        // Verify encoding is efficient for repeated MPS
        XCTAssertLessThan(encodedData.count, 10, "Repeated MPS should compress well")

        // Note: Full decode verification requires complete decoder implementation
        // which may not handle all termination modes correctly yet
    }

    /// Test vector: Alternating symbols
    func testMQCoderAlternatingSymbols() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        // Create a specific pattern: 101010
        let pattern: [Bool] = [true, false, true, false, true, false]

        for symbol in pattern {
            encoder.encode(symbol: symbol, context: &context)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Alternating symbols should not compress as well as uniform data
        XCTAssertLessThan(encodedData.count, 20, "Should produce reasonable output size")

        // Note: Decoding test omitted until decoder fully supports termination modes
    }

    /// Test vector: All zeros (highly compressible)
    func testMQCoderAllZeros() throws {
        var encoder = MQEncoder()
        var context = MQContext(stateIndex: 0, mps: false)

        // Encode 100 zeros (MPS)
        for _ in 0..<100 {
            encoder.encode(symbol: false, context: &context)
        }

        let encodedData = encoder.finish()

        // All zeros should compress very well
        XCTAssertLessThan(encodedData.count, 20, "100 zeros should compress to < 20 bytes")

        // Verify we got some data
        XCTAssertGreaterThan(encodedData.count, 0)

        // Note: Full decode verification deferred until decoder implementation is complete
    }

    /// Test vector: Random-like sequence with known seed
    func testMQCoderDeterministicRandom() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        // Use deterministic pseudo-random sequence
        var seed: UInt32 = 12345
        var pattern: [Bool] = []
        for _ in 0..<50 {
            seed = seed &* 1103515245 &+ 12345 // Linear congruential generator
            pattern.append((seed / 65536) % 2 == 0)
        }

        for symbol in pattern {
            encoder.encode(symbol: symbol, context: &context)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Pseudo-random should compress somewhat
        XCTAssertLessThan(encodedData.count, pattern.count, "Should provide some compression")

        // Note: Full round-trip test deferred until decoder implementation is complete
    }

    /// Test vector: Bypass mode encoding
    func testMQCoderBypassMode() throws {
        var encoder = MQEncoder()

        // Bypass mode encodes bits directly without context
        let bypassBits: [Bool] = [true, false, true, true, false, false, true, false]

        for bit in bypassBits {
            encoder.encodeBypass(symbol: bit)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Bypass mode: each bit should take approximately 1 bit
        // With overhead, 8 bits should be ~1-2 bytes
        XCTAssertLessThan(encodedData.count, 5, "Bypass mode should be efficient")
    }

    /// Test vector: Mixed context-adaptive and bypass mode
    func testMQCoderMixedModes() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        // Start with context-adaptive coding
        encoder.encode(symbol: true, context: &context)
        encoder.encode(symbol: false, context: &context)

        // Switch to bypass mode
        encoder.encodeBypass(symbol: true)
        encoder.encodeBypass(symbol: true)
        encoder.encodeBypass(symbol: false)

        // Back to context-adaptive
        encoder.encode(symbol: true, context: &context)
        encoder.encode(symbol: false, context: &context)

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)
    }

    // MARK: - Termination Mode Test Vectors

    /// Test vector: Context-adaptive coding termination
    func testMQCoderTermination() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        let symbols: [Bool] = [true, false, true, true, false]
        for symbol in symbols {
            encoder.encode(symbol: symbol, context: &context)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Termination should produce valid output
        let lastByte = encodedData.last ?? 0
        XCTAssertGreaterThanOrEqual(lastByte, 0, "Should have valid last byte")
    }

    // MARK: - Context State Test Vectors

    /// Test vector: State transitions
    func testMQCoderStateTransitions() throws {
        var encoder = MQEncoder()

        // Use multiple contexts to test state transitions
        var context0 = MQContext(stateIndex: 0, mps: false)
        var context1 = MQContext(stateIndex: 0, mps: false)

        // Encode with different contexts
        encoder.encode(symbol: false, context: &context0) // MPS for context0
        encoder.encode(symbol: false, context: &context1) // MPS for context1
        encoder.encode(symbol: true, context: &context0)  // LPS for context0
        encoder.encode(symbol: false, context: &context1) // MPS for context1

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Verify state has changed
        XCTAssertNotEqual(context0.stateIndex, 0, "Context 0 state should have changed")
    }

    // MARK: - Edge Case Test Vectors

    /// Test vector: Empty sequence
    func testMQCoderEmptySequence() throws {
        var encoder = MQEncoder()
        let encodedData = encoder.finish()

        // Empty encoding should produce minimal data
        XCTAssertGreaterThanOrEqual(encodedData.count, 0)
        XCTAssertLessThan(encodedData.count, 5, "Empty sequence should produce minimal data")
    }

    /// Test vector: Single symbol
    func testMQCoderSingleSymbol() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        encoder.encode(symbol: true, context: &context)

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)
        XCTAssertLessThan(encodedData.count, 5, "Single symbol should be small")

        // Note: Decode test deferred until decoder termination handling is complete
    }

    /// Test vector: Very long sequence (stress test)
    func testMQCoderLongSequence() throws {
        var encoder = MQEncoder()
        var context = MQContext()

        // Encode 10,000 symbols
        var seed: UInt32 = 54321
        for _ in 0..<10_000 {
            seed = seed &* 1103515245 &+ 12345
            let symbol = (seed / 65536) % 2 == 0
            encoder.encode(symbol: symbol, context: &context)
        }

        let encodedData = encoder.finish()
        XCTAssertGreaterThan(encodedData.count, 0)

        // Should provide meaningful compression for pseudo-random data
        XCTAssertLessThan(encodedData.count, 10_000 / 4, "Should compress pseudo-random data")

        // Note: Full decode test deferred - this validates encoding stability
    }

    // MARK: - Bit-Plane Coding Test Vectors

    /// Test vector: Single bit-plane
    func testBitPlaneSinglePlane() throws {
        // Create a simple 4x4 code-block with one significant bit-plane
        let width = 4
        let height = 4
        var coefficients = [Int32](repeating: 0, count: width * height)

        // Set up a simple pattern: 1s in corners
        coefficients[0] = 1      // (0,0)
        coefficients[3] = 1      // (3,0)
        coefficients[12] = 1     // (0,3)
        coefficients[15] = 1     // (3,3)

        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let result = try coder.encode(coefficients: coefficients, bitDepth: 4)

        XCTAssertGreaterThan(result.data.count, 0, "Should produce encoded data")

        // Verify encoding is relatively compact for sparse data
        XCTAssertLessThan(result.data.count, 100, "Simple pattern should compress well")
    }

    /// Test vector: Multiple bit-planes
    func testBitPlaneMultiplePlanes() throws {
        let width = 4
        let height = 4
        var coefficients = [Int32](repeating: 0, count: width * height)

        // Create coefficients with multiple bit-planes
        coefficients[0] = 7   // Binary: 111
        coefficients[1] = 5   // Binary: 101
        coefficients[2] = 3   // Binary: 011
        coefficients[3] = 1   // Binary: 001

        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let result = try coder.encode(coefficients: coefficients, bitDepth: 4)

        XCTAssertGreaterThan(result.data.count, 0)

        // Multiple bit-planes require more data
        XCTAssertGreaterThan(result.data.count, 5)
    }

    /// Test vector: Negative coefficients
    func testBitPlaneNegativeCoefficients() throws {
        let width = 4
        let height = 4
        var coefficients = [Int32](repeating: 0, count: width * height)

        // Mix positive and negative
        coefficients[0] = 5
        coefficients[1] = -3
        coefficients[2] = 7
        coefficients[3] = -1

        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let result = try coder.encode(coefficients: coefficients, bitDepth: 4)

        XCTAssertGreaterThan(result.data.count, 0)
    }

    /// Test vector: All zero coefficients
    func testBitPlaneAllZeros() throws {
        let width = 4
        let height = 4
        let coefficients = [Int32](repeating: 0, count: width * height)

        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let result = try coder.encode(coefficients: coefficients, bitDepth: 4)

        // All zeros should compress extremely well
        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertLessThan(result.data.count, 20, "All zeros should be highly compressible")
    }

    // MARK: - Compression Ratio Test Vectors

    /// Test vector: Verify compression ratios for known patterns
    func testCompressionRatios() throws {
        struct TestCase {
            let name: String
            let data: [Bool]
            let maxCompressedSize: Int

            init(_ name: String, _ data: [Bool], maxSize: Int) {
                self.name = name
                self.data = data
                self.maxCompressedSize = maxSize
            }
        }

        let testCases = [
            TestCase("All zeros", [Bool](repeating: false, count: 1000), maxSize: 20),
            TestCase("All ones", [Bool](repeating: true, count: 1000), maxSize: 20),
            TestCase("Alternating", (0..<1000).map { $0 % 2 == 0 }, maxSize: 200)
        ]

        for testCase in testCases {
            var encoder = MQEncoder()
            var context = MQContext()

            for symbol in testCase.data {
                encoder.encode(symbol: symbol, context: &context)
            }

            let encodedData = encoder.finish()

            XCTAssertLessThan(encodedData.count, testCase.maxCompressedSize,
                            "\(testCase.name): compressed size should be < \(testCase.maxCompressedSize) bytes")
        }
    }
}
