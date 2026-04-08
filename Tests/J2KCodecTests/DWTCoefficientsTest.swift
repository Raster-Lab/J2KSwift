import XCTest
@testable import J2KCodec
@testable import J2KCore

final class DWTCoefficientsTest: XCTestCase {
    func testDWTCoefficients8x8() throws {
        let w = 8, h = 8
        // Same image as testDecodeOPJReference
        var shifted = [[Int32]]()
        for y in 0..<h {
            var row = [Int32]()
            for x in 0..<w {
                let pixel = min(255, x * 32 + y * 16)
                row.append(Int32(pixel) - 128)  // Level shift
            }
            shifted.append(row)
        }
        
        print("Input (level-shifted):")
        for r in shifted { print(r) }
        
        let result = try J2KDWT2D.forwardTransform(image: shifted, filter: .reversible53)
        
        print("\nLL subband:")
        for r in result.ll { print(r) }
        print("\nLH subband:")
        for r in result.lh { print(r) }
        print("\nHL subband:")
        for r in result.hl { print(r) }
        print("\nHH subband:")
        for r in result.hh { print(r) }
        
        // Expected from Python
        let expectedLL: [[Int32]] = [
            [-128, -64, 0, 72],
            [-96, -32, 32, 104],
            [-64, 0, 64, 127],
            [-28, 36, 104, 131]
        ]
        let expectedLH: [[Int32]] = [
            [0, 0, 0, 0],
            [0, 0, 0, 1],
            [0, 0, 0, 0],
            [16, 16, 14, -2]
        ]
        let expectedHL: [[Int32]] = [
            [0, 0, 0, 33],
            [0, 0, 0, 31],
            [0, 0, 1, 0],
            [0, 0, 14, 0]
        ]
        let expectedHH: [[Int32]] = [
            [0, 0, 0, 1],
            [0, 0, 0, -1],
            [0, 0, 1, 0],
            [0, 0, -8, 0]
        ]
        
        XCTAssertEqual(result.ll, expectedLL, "LL mismatch")
        XCTAssertEqual(result.lh, expectedLH, "LH mismatch")
        XCTAssertEqual(result.hl, expectedHL, "HL mismatch")
        XCTAssertEqual(result.hh, expectedHH, "HH mismatch")
    }
}
