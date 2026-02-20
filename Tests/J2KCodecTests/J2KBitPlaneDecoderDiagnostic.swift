//
// J2KBitPlaneDecoderDiagnostic.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Diagnostic tests to help debug the bit-plane decoder issue.
final class J2KBitPlaneDecoderDiagnostic: XCTestCase {
    /// Test the specific failing case with detailed logging.
    func testDiagnosticSmallBlock() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)

        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100    // Binary: 01100100 (7 bits)
        original[5] = -50    // Binary: 00110010 (6 bits) + sign
        original[10] = 25    // Binary: 00011001 (5 bits)
        original[15] = -10   // Binary: 00001010 (4 bits) + sign

        print("\nOriginal coefficients:")
        printBlock(original, width: width, height: height)

        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        print("\nEncoded data:")
        print("  Size: \(data.count) bytes")
        print("  Pass count: \(passCount)")
        print("  Zero bit planes: \(zeroBitPlanes)")
        print("  Data (hex): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("  Data (binary): \(data.map { String(format: "%08b", $0) }.joined(separator: " "))")

        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        print("\nDecoded coefficients:")
        printBlock(decoded, width: width, height: height)

        print("\nDifferences:")
        var hasDifferences = false
        for i in 0..<original.count {
            if original[i] != decoded[i] {
                let row = i / width
                let col = i % width
                print("  Index \(i) [row \(row), col \(col)]: expected \(original[i]), got \(decoded[i])")
                hasDifferences = true
            }
        }
        if !hasDifferences {
            print("  None - round-trip is exact!")
        }

        XCTAssertEqual(decoded, original, "Round-trip should be exact")
    }

    /// Test with just one non-zero value to isolate the issue.
    func testDiagnosticSingleValue() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)

        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100

        print("\nTesting single value:")
        printBlock(original, width: width, height: height)

        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        XCTAssertEqual(decoded, original, "Single value round-trip should be exact")
    }

    /// Test with two values in different positions.
    func testDiagnosticTwoValues() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)

        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100
        original[5] = -50

        print("\nTesting two values:")
        printBlock(original, width: width, height: height)

        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        XCTAssertEqual(decoded, original, "Two values round-trip should be exact")
    }

    /// Test with three values in different positions.
    func testDiagnosticThreeValues() throws {
        let width = 4
        let height = 4
        let bitDepth = 8

        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)

        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 100
        original[5] = -50
        original[10] = 25

        print("\nTesting three values:")
        printBlock(original, width: width, height: height)

        let (data, passCount, zeroBitPlanes, _) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )

        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )

        print("\nDecoded:")
        printBlock(decoded, width: width, height: height)

        XCTAssertEqual(decoded, original, "Three values round-trip should be exact")
    }

    /// Helper to print a block in a grid format.
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
