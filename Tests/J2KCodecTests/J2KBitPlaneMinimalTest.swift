//
// J2KBitPlaneMinimalTest.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Ultra-minimal test to identify the exact bug
final class J2KBitPlaneMinimalTest: XCTestCase {
    /// Test the simplest possible case that fails
    func testTinyBlock4x4PowerOfTwo() throws {
        print("\n=== Testing 4x4 with power-of-2 value ===")

        let size = 4
        let bitDepth = 12
        let options = CodingOptions.fastEncoding

        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        // Create a pattern with exactly 2048 (power of 2) that triggers the bug
        var original = [Int32](repeating: 0, count: size * size)
        original[0] = 2048  // This is 2^11, requires 12 bits
        original[1] = 1024  // This is 2^10, requires 11 bits
        original[2] = 2047  // This is 2047, requires 12 bits
        original[3] = 2048  // Another 2^11

        print("Test coefficients:")
        for (i, val) in original.enumerated() {
            if val != 0 {
                print("  [\(i)]: \(val) (0x\(String(val, radix: 16)))")
            }
        }

        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: size,
            height: size,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )

        print("Encoded: \(codeBlock.data.count) bytes")
        print("Zero bit planes: \(codeBlock.zeroBitPlanes)")
        print("Pass count: \(codeBlock.passeCount)")

        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )

        print("\nResults:")
        for i in 0..<size * size {
            if original[i] != decoded[i] {
                print("  [\(i)]: expected \(original[i]), got \(decoded[i]) ❌")
            } else if original[i] != 0 {
                print("  [\(i)]: \(original[i]) ✓")
            }
        }

        // Check
        for i in 0..<size * size {
            XCTAssertEqual(decoded[i], original[i], "Mismatch at index \(i)")
        }
    }

    /// Test exact boundary: 2047 vs 2048
    func testPowerOfTwoBoundary() throws {
        print("\n=== Testing power-of-2 boundary (2047 vs 2048) ===")

        let size = 2
        let bitDepth = 12
        let options = CodingOptions.fastEncoding

        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        // Test values right at the power-of-2 boundary
        let testValues: [Int32] = [2047, 2048, 2049, 1024]

        var original = [Int32](repeating: 0, count: size * size)
        for (i, val) in testValues.enumerated() {
            if i < original.count {
                original[i] = val
            }
        }

        print("Test values: \(original)")
        print("Binary representations:")
        for (i, val) in original.enumerated() {
            let binary = String(val, radix: 2).padLeft(toLength: 12, withPad: "0")
            let bits = 32 - val.leadingZeroBitCount
            print("  [\(i)]: \(val) = 0b\(binary) (needs \(bits) bits)")
        }

        // Encode
        let codeBlock = try encoder.encode(
            coefficients: original,
            width: size,
            height: size,
            subband: .ll,
            bitDepth: bitDepth,
            options: options
        )

        print("\nEncoded: \(codeBlock.data.count) bytes, zero bit planes: \(codeBlock.zeroBitPlanes)")

        // Decode
        let decoded = try decoder.decode(
            codeBlock: codeBlock,
            bitDepth: bitDepth,
            options: options
        )

        print("\nResults:")
        for i in 0..<size * size {
            let match = original[i] == decoded[i] ? "✓" : "❌"
            print("  [\(i)]: \(original[i]) -> \(decoded[i]) \(match)")
        }

        // Assert
        XCTAssertEqual(decoded, original, "All values should match")
    }

    /// Test with pattern showing the log2 edge case
    func testLog2EdgeCase() throws {
        print("\n=== Testing log2 edge case ===")

        let bitDepth = 12
        let options = CodingOptions.fastEncoding

        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        // Test single coefficient at various powers of 2
        let powerOfTwoValues: [Int32] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]

        for val in powerOfTwoValues {
            var original = [Int32](repeating: 0, count: 1)
            original[0] = val

            let codeBlock = try encoder.encode(
                coefficients: original,
                width: 1,
                height: 1,
                subband: .ll,
                bitDepth: bitDepth,
                options: options
            )

            let decoded = try decoder.decode(
                codeBlock: codeBlock,
                bitDepth: bitDepth,
                options: options
            )

            let match = original[0] == decoded[0]
            let status = match ? "✓" : "❌"
            let bits = 32 - val.leadingZeroBitCount
            let zeroBitPlanes = codeBlock.zeroBitPlanes
            let activeBitPlanes = bitDepth - zeroBitPlanes

            print("  \(val) (2^\(bits - 1), needs \(bits) bits): active=\(activeBitPlanes), zero=\(zeroBitPlanes) -> \(decoded[0]) \(status)")

            if !match {
                print("    ERROR: Expected \(original[0]), got \(decoded[0])")
            }
        }
    }
}

extension String {
    func padLeft(toLength length: Int, withPad character: Character) -> String {
        if self.count >= length {
            return String(self.suffix(length))
        } else {
            return String(repeating: String(character), count: length - self.count) + self
        }
    }
}
