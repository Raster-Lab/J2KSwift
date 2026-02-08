import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Comprehensive test cases for bit-plane decoder bug fix.
///
/// These tests are designed to systematically test the bit-plane decoder
/// with various patterns to ensure the synchronization bug is fixed.
final class J2KBitPlaneDecoderFixTests: XCTestCase {
    
    // MARK: - Single Non-Zero Value Tests
    
    /// Test with a single non-zero value at different positions.
    func testSingleValueAtPosition0() throws {
        try testRoundTrip(values: [(0, 100)], width: 4, height: 4)
    }
    
    func testSingleValueAtPosition3() throws {
        try testRoundTrip(values: [(3, 100)], width: 4, height: 4)
    }
    
    func testSingleValueAtPosition15() throws {
        try testRoundTrip(values: [(15, 100)], width: 4, height: 4)
    }
    
    // MARK: - Two Non-Zero Value Tests
    
    /// Test with two non-zero values at different position combinations.
    func testTwoValuesAdjacentHorizontal() throws {
        try testRoundTrip(values: [(0, 100), (1, 50)], width: 4, height: 4)
    }
    
    func testTwoValuesAdjacentVertical() throws {
        try testRoundTrip(values: [(0, 100), (4, 50)], width: 4, height: 4)
    }
    
    func testTwoValuesAdjacentDiagonal() throws {
        try testRoundTrip(values: [(0, 100), (5, 50)], width: 4, height: 4)
    }
    
    func testTwoValuesSeparated() throws {
        try testRoundTrip(values: [(0, 100), (15, 50)], width: 4, height: 4)
    }
    
    func testTwoValuesInSameColumn() throws {
        try testRoundTrip(values: [(0, 100), (8, 50)], width: 4, height: 4)
    }
    
    func testTwoValuesInDifferentColumns() throws {
        try testRoundTrip(values: [(0, 100), (5, 50)], width: 4, height: 4)
    }
    
    // MARK: - Three Non-Zero Value Tests
    
    /// Test with three non-zero values (the original failing case).
    func testThreeValuesOriginalFailingCase() throws {
        try testRoundTrip(values: [(0, 100), (5, -50), (10, 25)], width: 4, height: 4)
    }
    
    func testThreeValuesInSameRow() throws {
        try testRoundTrip(values: [(0, 100), (1, 50), (2, 25)], width: 4, height: 4)
    }
    
    func testThreeValuesInSameColumn() throws {
        try testRoundTrip(values: [(0, 100), (4, 50), (8, 25)], width: 4, height: 4)
    }
    
    func testThreeValuesScattered() throws {
        try testRoundTrip(values: [(0, 100), (6, -50), (15, 25)], width: 4, height: 4)
    }
    
    // MARK: - Four Non-Zero Value Tests
    
    /// Test with four non-zero values in one column (RLC stripe case).
    func testFourValuesFullColumn() throws {
        try testRoundTrip(values: [(0, 100), (4, 50), (8, 25), (12, 10)], width: 4, height: 4)
    }
    
    func testFourValuesCorners() throws {
        try testRoundTrip(values: [(0, 100), (3, 50), (12, 25), (15, 10)], width: 4, height: 4)
    }
    
    func testFourValuesDiagonal() throws {
        try testRoundTrip(values: [(0, 100), (5, 50), (10, 25), (15, 10)], width: 4, height: 4)
    }
    
    // MARK: - Edge Case Tests
    
    /// Test with negative values.
    func testAllNegativeValues() throws {
        try testRoundTrip(values: [(0, -100), (5, -50), (10, -25)], width: 4, height: 4)
    }
    
    /// Test with mixed positive and negative values.
    func testMixedSigns() throws {
        try testRoundTrip(values: [(0, 100), (5, -50), (10, 25), (15, -10)], width: 4, height: 4)
    }
    
    /// Test with small values (low bit-planes only).
    func testSmallValues() throws {
        try testRoundTrip(values: [(0, 7), (5, -3), (10, 1)], width: 4, height: 4)
    }
    
    /// Test with large values (high bit-planes).
    func testLargeValues() throws {
        try testRoundTrip(values: [(0, 255), (5, -200), (10, 150)], width: 4, height: 4)
    }
    
    /// Test with power-of-2 values.
    func testPowerOfTwoValues() throws {
        try testRoundTrip(values: [(0, 128), (5, -64), (10, 32), (15, 16)], width: 4, height: 4)
    }
    
    // MARK: - Different Block Sizes
    
    /// Test with 8x8 block.
    func test8x8Block() throws {
        try testRoundTrip(values: [(0, 100), (10, -50), (20, 25), (63, 10)], width: 8, height: 8)
    }
    
    /// Test with 16x16 block.
    func test16x16Block() throws {
        try testRoundTrip(values: [(0, 100), (50, -50), (100, 25), (255, 10)], width: 16, height: 16)
    }
    
    /// Test with non-square block.
    func testNonSquareBlock4x8() throws {
        try testRoundTrip(values: [(0, 100), (10, -50), (20, 25)], width: 4, height: 8)
    }
    
    /// Test with non-square block 8x4.
    func testNonSquareBlock8x4() throws {
        try testRoundTrip(values: [(0, 100), (10, -50), (20, 25)], width: 8, height: 4)
    }
    
    // MARK: - Column-Specific Tests (RLC-related)
    
    /// Test where last column uses RLC with HasSig=false.
    func testLastColumnRLCFalse() throws {
        // All values in first columns, last column empty
        try testRoundTrip(values: [(0, 100), (1, -50), (4, 25), (5, 10)], width: 4, height: 4)
    }
    
    /// Test where last column uses RLC with HasSig=true.
    func testLastColumnRLCTrue() throws {
        // Value in last column
        try testRoundTrip(values: [(3, 100), (7, -50)], width: 4, height: 4)
    }
    
    /// Test where all columns use RLC.
    func testAllColumnsRLC() throws {
        // Only two values, far apart
        try testRoundTrip(values: [(0, 100), (5, 50)], width: 4, height: 4)
    }
    
    // MARK: - Different Subbands
    
    /// Test with HL subband.
    func testHLSubband() throws {
        try testRoundTrip(values: [(0, 100), (5, -50), (10, 25)], width: 4, height: 4, subband: .hl)
    }
    
    /// Test with LH subband.
    func testLHSubband() throws {
        try testRoundTrip(values: [(0, 100), (5, -50), (10, 25)], width: 4, height: 4, subband: .lh)
    }
    
    /// Test with HH subband.
    func testHHSubband() throws {
        try testRoundTrip(values: [(0, 100), (5, -50), (10, 25)], width: 4, height: 4, subband: .hh)
    }
    
    // MARK: - Helper Methods
    
    /// Test round-trip encoding and decoding with specified values.
    ///
    /// - Parameters:
    ///   - values: Array of (index, value) pairs representing non-zero coefficients.
    ///   - width: Width of the code block.
    ///   - height: Height of the code block.
    ///   - subband: Subband type (default: .ll).
    ///   - bitDepth: Bit depth (default: 8).
    private func testRoundTrip(
        values: [(Int, Int32)],
        width: Int,
        height: Int,
        subband: J2KSubband = .ll,
        bitDepth: Int = 8
    ) throws {
        // Create coefficient array
        var coefficients = [Int32](repeating: 0, count: width * height)
        for (index, value) in values {
            coefficients[index] = value
        }
        
        // Encode
        let encoder = BitPlaneCoder(width: width, height: height, subband: subband)
        let (data, passCount, zeroBitPlanes) = try encoder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        // Decode
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband)
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )
        
        // Verify
        XCTAssertEqual(decoded.count, coefficients.count, "Array size mismatch")
        
        var mismatches: [(Int, Int32, Int32)] = []
        for i in 0..<coefficients.count {
            if decoded[i] != coefficients[i] {
                mismatches.append((i, coefficients[i], decoded[i]))
            }
        }
        
        if !mismatches.isEmpty {
            let row = { $0 / width }
            let col = { $0 % width }
            let details = mismatches.map { idx, expected, got in
                "Index \(idx) [\(row(idx)),\(col(idx))]: expected \(expected), got \(got)"
            }.joined(separator: "\n")
            XCTFail("Round-trip mismatch:\n\(details)")
        }
    }
}
