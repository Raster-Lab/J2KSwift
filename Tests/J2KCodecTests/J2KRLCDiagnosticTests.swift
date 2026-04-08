import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Diagnostic test to find where RLC position encoding diverges
final class J2KRLCDiagnosticTests: XCTestCase {

    /// Test with bitDepth 8 and small block — passes with both approaches
    func testRoundTrip8x8BitDepth8() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 8
        let height = 8
        let bitDepth = 8

        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 100)
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "8x8 bitDepth 8 round-trip")
    }

    /// Test with bitDepth 10 and 16x16 block
    func testRoundTrip16x16BitDepth10() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 16
        let height = 16
        let bitDepth = 10

        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 500)
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "16x16 bitDepth 10 round-trip")
    }

    /// Test with bitDepth 12 and 8x8 block — isolate if it's block size or bitDepth
    func testRoundTrip8x8BitDepth12() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 8
        let height = 8
        let bitDepth = 12

        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 1000)
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "8x8 bitDepth 12 round-trip")
    }

    /// Identical to failing test but with smaller data values
    func testRoundTrip32x32BitDepth12SmallValues() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 32
        let height = 32
        let bitDepth = 12

        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 100)  // Small values - max 99
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "32x32 bitDepth 12 small values round-trip")
    }

    /// Gradually increase values to find threshold
    func testRoundTrip32x32BitDepth12MediumValues() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 32
        let height = 32
        let bitDepth = 12

        // Test increasing value ranges
        for maxVal in [100, 200, 300, 400, 500, 600, 700, 800, 900, 999] {
            var original = [Int32](repeating: 0, count: width * height)
            for i in 0..<original.count {
                let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
                original[i] = sign * Int32((i * 7) % maxVal)
            }

            let codeBlock = try encoder.encode(
                coefficients: original, width: width, height: height,
                subband: .ll, bitDepth: bitDepth
            )
            let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
            XCTAssertEqual(decoded, original, "32x32 bitDepth 12 maxVal \(maxVal) round-trip")
        }
    }

    /// Identical to failing test
    func testRoundTrip32x32BitDepth12LargeValues() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 32
        let height = 32
        let bitDepth = 12

        var original = [Int32](repeating: 0, count: width * height)
        for i in 0..<original.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 1000)  // Large values
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "32x32 bitDepth 12 large values round-trip")
    }

    /// Test with lots of zeros (sparse) — should trigger RLC heavily
    func testRoundTrip32x32BitDepth12MostlyZeros() throws {
        let encoder = CodeBlockEncoder()
        let decoder = CodeBlockDecoder()

        let width = 32
        let height = 32
        let bitDepth = 12

        var original = [Int32](repeating: 0, count: width * height)
        // Only set every 10th value
        for i in stride(from: 0, to: original.count, by: 10) {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            original[i] = sign * Int32((i * 7) % 1000)
        }

        let codeBlock = try encoder.encode(
            coefficients: original, width: width, height: height,
            subband: .ll, bitDepth: bitDepth
        )
        let decoded = try decoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)
        XCTAssertEqual(decoded, original, "32x32 bitDepth 12 mostly zeros round-trip")
    }
}
