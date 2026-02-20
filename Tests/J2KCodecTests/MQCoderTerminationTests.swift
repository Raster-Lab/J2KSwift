//
// MQCoderTerminationTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Isolated test for MQ-coder termination bug
/// This test encodes a simple sequence of symbols and verifies correct decoding
final class MQCoderTerminationTests: XCTestCase {
    func testSimpleSequence() throws {
        // Create encoder
        var encoder = MQEncoder()
        var contexts = ContextStateArray()

        // Start with context at state 30, mps=false (matches the failing case)
        contexts[.sigPropLL_LH_0] = MQContext(stateIndex: 30, mps: false)

        // Encode 5 false symbols (which are MPS since mps=false)
        for i in 0..<5 {
            let contextBefore = contexts[.sigPropLL_LH_0]
            print("Encode #\(i + 1): symbol=false, state=\(contextBefore.stateIndex), mps=\(contextBefore.mps)")
            encoder.encode(symbol: false, context: &contexts[.sigPropLL_LH_0])
            let contextAfter = contexts[.sigPropLL_LH_0]
            print("         After: state=\(contextAfter.stateIndex), mps=\(contextAfter.mps)")
        }

        // Finish encoding
        let data = encoder.finish(mode: .default)
        print("\nEncoded data: \(data.count) bytes")
        print("Bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Create decoder
        var decoder = MQDecoder(data: data)
        var decodeContexts = ContextStateArray()
        decodeContexts[.sigPropLL_LH_0] = MQContext(stateIndex: 30, mps: false)

        // Decode 5 symbols
        var allCorrect = true
        for i in 0..<5 {
            let contextBefore = decodeContexts[.sigPropLL_LH_0]
            print("\nDecode #\(i + 1): state=\(contextBefore.stateIndex), mps=\(contextBefore.mps)")
            let symbol = decoder.decode(context: &decodeContexts[.sigPropLL_LH_0])
            let contextAfter = decodeContexts[.sigPropLL_LH_0]
            print("         Result: symbol=\(symbol), state=\(contextAfter.stateIndex)")

            if symbol != false {
                print("         ERROR: Expected false, got \(symbol)")
                allCorrect = false
            }
        }

        print("\n" + (allCorrect ? "✓ ALL SYMBOLS DECODED CORRECTLY" : "✗ DECODING FAILED"))
        XCTAssertTrue(allCorrect, "All symbols should decode as false")
    }

    func testVariousSymbolCounts() throws {
        // Test with different numbers of symbols to find the pattern
        for count in 1...10 {
            var encoder = MQEncoder()
            var contexts = ContextStateArray()
            contexts[.sigPropLL_LH_0] = MQContext(stateIndex: 30, mps: false)

            // Encode 'count' false symbols
            for _ in 0..<count {
                encoder.encode(symbol: false, context: &contexts[.sigPropLL_LH_0])
            }

            let data = encoder.finish(mode: .default)

            // Decode and verify
            var decoder = MQDecoder(data: data)
            var decodeContexts = ContextStateArray()
            decodeContexts[.sigPropLL_LH_0] = MQContext(stateIndex: 30, mps: false)

            var success = true
            for _ in 0..<count {
                let symbol = decoder.decode(context: &decodeContexts[.sigPropLL_LH_0])
                if symbol != false {
                    success = false
                    break
                }
            }

            if !success {
                print("FAIL at count=\(count)")
            } else {
                print("PASS at count=\(count)")
            }

            XCTAssertTrue(success, "Should decode correctly with \(count) symbols")
        }
    }
}
