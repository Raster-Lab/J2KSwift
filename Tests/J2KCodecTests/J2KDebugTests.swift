import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Temporary debug tests to understand encoder/decoder issues
final class J2KDebugTests: XCTestCase {
    
    func testSimpleRoundTrip() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        
        // Create a very simple pattern: one non-zero value
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 1
        
        print("Original coefficients: \(original)")
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )
        
        print("Encoded: \(data.count) bytes, \(passCount) passes, \(zeroBitPlanes) zero bit-planes")
        print("Data bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )
        
        print("Decoded coefficients: \(decoded)")
        
        XCTAssertEqual(decoded, original, "Simple round-trip should work")
    }
    
    func testTwoNonZeroValues() throws {
        let width = 4
        let height = 4
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        
        var original = [Int32](repeating: 0, count: width * height)
        original[0] = 3
        original[5] = 2
        
        print("Original coefficients: \(original)")
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )
        
        print("Encoded: \(data.count) bytes, \(passCount) passes, \(zeroBitPlanes) zero bit-planes")
        
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )
        
        print("Decoded coefficients: \(decoded)")
        
        for i in 0..<original.count {
            if original[i] != decoded[i] {
                print("Mismatch at index \(i): expected \(original[i]), got \(decoded[i])")
            }
        }
        
        XCTAssertEqual(decoded, original, "Two non-zero values round-trip should work")
    }
    
    func testValue60() throws {
        let width = 8
        let height = 8
        let bitDepth = 8
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        
        // Test specifically with value 60 which is failing
        var original = [Int32](repeating: 0, count: width * height)
        original[60] = 60
        
        print("Original: value 60 at index 60")
        print("Binary of 60: \(String(60, radix: 2).leftPadding(toLength: 8, withPad: "0"))")
        
        let (data, passCount, zeroBitPlanes) = try encoder.encode(
            coefficients: original,
            bitDepth: bitDepth
        )
        
        print("Encoded: \(data.count) bytes, \(passCount) passes, \(zeroBitPlanes) zero bit-planes")
        
        let decoded = try decoder.decode(
            data: data,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes
        )
        
        print("Decoded: value \(decoded[60]) at index 60")
        if decoded[60] != 60 {
            print("Binary of \(decoded[60]): \(String(decoded[60], radix: 2).leftPadding(toLength: 8, withPad: "0"))")
        }
        
        XCTAssertEqual(decoded[60], 60, "Value 60 should decode correctly")
    }
}

extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let stringLength = self.count
        if stringLength < toLength {
            return String(repeatElement(character, count: toLength - stringLength)) + self
        } else {
            return self
        }
    }
}
