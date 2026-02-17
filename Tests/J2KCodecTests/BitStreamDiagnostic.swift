// BitStreamDiagnostic.swift
// Comprehensive bit-level logging for debugging encoder/decoder synchronization

import XCTest
@testable import J2KCodec

/// Test class for bit-level diagnostic logging
final class BitStreamDiagnosticTests: XCTestCase {
    /// Test the three-coefficient scenario with detailed bit-level logging
    func testThreeCoefficientsWithBitTracking() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        // Create test data: coefficients at positions 0, 5, and 10
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100   // 0b01100100 - highest bit: 6
        original[5] = -50   // 0b00110010 - highest bit: 5
        original[10] = 25   // 0b00011001 - highest bit: 4

        print("\n" + String(repeating: "=", count: 80))
        print("THREE COEFFICIENT BIT-TRACKING DIAGNOSTIC")
        print(String(repeating: "=", count: 80))

        print("\nOriginal coefficients:")
        printBlock(original, width: width, height: height)
        print("\nBit representation:")
        print("  Pos[0]  = 100  = 0b\(String(100, radix: 2).padLeft(toLength: 8, withPad: "0"))")
        print("  Pos[5]  = -50  = 0b\(String(50, radix: 2).padLeft(toLength: 8, withPad: "0")) (magnitude)")
        print("  Pos[10] = 25   = 0b\(String(25, radix: 2).padLeft(toLength: 8, withPad: "0"))")

        // Encode with detailed logging
        print("\n" + String(repeating: "-", count: 80))
        print("ENCODING PHASE")
        print(String(repeating: "-", count: 80))

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        print("\nEncoding complete:")
        print("  Data length: \(data.count) bytes")
        print("  Pass count: \(passCount)")
        print("  Zero bit-planes: \(zeroBitPlanes)")
        print("  Total bits available: \(data.count * 8)")

        // Decode with detailed logging
        print("\n" + String(repeating: "-", count: 80))
        print("DECODING PHASE")
        print(String(repeating: "-", count: 80))

        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        print("\nDecoding complete:")
        printBlock(decoded, width: width, height: height)

        // Check for differences
        print("\n" + String(repeating: "-", count: 80))
        print("COMPARISON")
        print(String(repeating: "-", count: 80))

        var hasDifferences = false
        for i in 0..<original.count {
            if decoded[i] != original[i] {
                let x = i % width
                let y = i / width
                print("❌ Pos[\(i)] (\(x),\(y)): expected \(original[i]), got \(decoded[i])")
                hasDifferences = true
            }
        }

        if !hasDifferences {
            print("✅ All coefficients match!")
        }

        print(String(repeating: "=", count: 80))

        XCTAssertEqual(decoded, original, "Three values round-trip should be exact")
    }

    /// Test with incremental coefficient count to identify the threshold
    func testIncrementalCoefficientCounts() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        print("\n" + String(repeating: "=", count: 80))
        print("INCREMENTAL COEFFICIENT COUNT TEST")
        print(String(repeating: "=", count: 80))

        // Test with 1, 2, 3, 4, 5 coefficients
        let testCases: [(count: Int, positions: [Int], values: [Int32])] = [
            (1, [0], [100]),
            (2, [0, 5], [100, -50]),
            (3, [0, 5, 10], [100, -50, 25]),
            (4, [0, 5, 10, 15], [100, -50, 25, -10]),
            (5, [0, 1, 5, 10, 15], [100, 75, -50, 25, -10])
        ]

        for testCase in testCases {
            var original = [Int32](repeating: 0, count: width * height)
            for (index, pos) in testCase.positions.enumerated() {
                original[pos] = testCase.values[index]
            }

            print("\n" + String(repeating: "-", count: 60))
            print("Testing with \(testCase.count) coefficient(s):")
            printBlock(original, width: width, height: height)

            let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
                coefficients: original,
                bitDepth: bitDepth
            )

            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: data,
                passCount: passCount,
                bitDepth: bitDepth,
                zeroBitPlanes: zeroBitPlanes
            )

            let matches = decoded == original
            print("Result: \(matches ? "✅ PASS" : "❌ FAIL")")

            if !matches {
                for i in 0..<original.count {
                    if decoded[i] != original[i] {
                        let x = i % width
                        let y = i / width
                        print("  Pos[\(i)] (\(x),\(y)): expected \(original[i]), got \(decoded[i])")
                    }
                }
            }
        }

        print(String(repeating: "=", count: 80))
    }

    /// Test to isolate which bit-plane causes the issue
    func testBitPlaneIsolation() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        print("\n" + String(repeating: "=", count: 80))
        print("BIT-PLANE ISOLATION TEST")
        print(String(repeating: "=", count: 80))

        // Use coefficients that have bits set at different planes
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 64    // 0b01000000 - only bit 6
        original[5] = 32    // 0b00100000 - only bit 5
        original[10] = 16   // 0b00010000 - only bit 4

        print("\nOriginal (single-bit coefficients):")
        printBlock(original, width: width, height: height)
        print("\nBit representation:")
        print("  Pos[0]  = 64 = 0b01000000 (bit 6)")
        print("  Pos[5]  = 32 = 0b00100000 (bit 5)")
        print("  Pos[10] = 16 = 0b00010000 (bit 4)")

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        print("\nDecoded:")
        printBlock(decoded, width: width, height: height)

        let matches = decoded == original
        print("\nResult: \(matches ? "✅ PASS" : "❌ FAIL")")

        if !matches {
            for i in 0..<original.count {
                if decoded[i] != original[i] {
                    let x = i % width
                    let y = i / width
                    print("  Pos[\(i)] (\(x),\(y)): expected \(original[i]), got \(decoded[i])")
                }
            }
        }

        print(String(repeating: "=", count: 80))
    }

    /// Helper to print a block in a grid format
    private func printBlock(_ coefficients: [Int32], width: Int, height: Int) {
        for y in 0..<height {
            var row = "  "
            for x in 0..<width {
                let idx = y * width + x
                row += String(format: "%4d ", coefficients[idx])
            }
            print(row)
        }
    }
}

// Helper extension for string padding
extension String {
    func padLeft(toLength: Int, withPad: String) -> String {
        let padLength = toLength - self.count
        guard padLength > 0 else { return self }
        return String(repeating: withPad, count: padLength) + self
    }
}
