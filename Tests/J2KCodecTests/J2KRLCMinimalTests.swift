import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Precise test to find the exact minimum reproduction case.
final class J2KRLCMinimalTests: XCTestCase {
    
    /// Reproduce the bitDepth=4, 16x16 failure with exact same data.
    func testBitDepth4Failure() throws {
        let width = 16
        let height = 16
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32(i % 256)
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        let maxMag: Int32 = 15
        let clamped = coefficients.map { val -> Int32 in
            let mag = min(abs(val), maxMag)
            return val < 0 ? -mag : mag
        }
        
        // Print the data so we can see the pattern
        print("Input (16x16, bitDepth=4, clamped to ±15):")
        for y in 0..<height {
            let row = (0..<width).map { x in String(clamped[y * width + x]) }
            print("  row \(y): \(row.joined(separator: ", "))")
        }
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _, _, _, _) = try encoder.encode(
            coefficients: clamped, bitDepth: 4
        )
        
        print("Encoded: passCount=\(passCount), zeroBitPlanes=\(zeroBitPlanes), dataSize=\(data.count)")
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data, passCount: passCount, bitDepth: 4, zeroBitPlanes: zeroBitPlanes
        )
        
        print("Decoded (16x16):")
        for y in 0..<height {
            let row = (0..<width).map { x in String(decoded[y * width + x]) }
            print("  row \(y): \(row.joined(separator: ", "))")
        }
        
        // Count mismatches
        var mismatches = 0
        for i in 0..<clamped.count {
            if decoded[i] != clamped[i] {
                let x = i % width
                let y = i / width
                if mismatches < 10 {
                    print("MISMATCH at (\(x),\(y)): expected \(clamped[i]), got \(decoded[i])")
                }
                mismatches += 1
            }
        }
        print("Total mismatches: \(mismatches) / \(clamped.count)")
        
        XCTAssertEqual(decoded, clamped)
    }
    
    /// Try to reduce the 16x16 case to find the minimum failing size.
    func testMinimalSizeForBitDepth4() throws {
        for size in [4, 8, 12, 16] {
            let width = size
            let height = size
            var coefficients = [Int32](repeating: 0, count: width * height)
            for i in 0..<coefficients.count {
                coefficients[i] = Int32(i % 256)
                if i % 3 == 0 { coefficients[i] = -coefficients[i] }
            }
            let maxMag: Int32 = 15
            let clamped = coefficients.map { val -> Int32 in
                let mag = min(abs(val), maxMag)
                return val < 0 ? -mag : mag
            }
            
            let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (data, passCount, zeroBitPlanes, _, _, _, _) = try encoder.encode(
                coefficients: clamped, bitDepth: 4
            )
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: data, passCount: passCount, bitDepth: 4, zeroBitPlanes: zeroBitPlanes
            )
            
            let matches = decoded == clamped
            print("size=\(size)x\(size), bitDepth=4: \(matches ? "PASS" : "FAIL") (passCount=\(passCount))")
        }
    }
    
    /// Test different subbands with the same data.
    func testDifferentSubbands() throws {
        let width = 16
        let height = 16
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32(i % 256)
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        let maxMag: Int32 = 15
        let clamped = coefficients.map { val -> Int32 in
            let mag = min(abs(val), maxMag)
            return val < 0 ? -mag : mag
        }
        
        for subband: J2KSubband in [.ll, .lh, .hl, .hh] {
            let encoder = BitPlaneCoder(width: width, height: height, subband: subband)
            let (data, passCount, zeroBitPlanes, _, _, _, _) = try encoder.encode(
                coefficients: clamped, bitDepth: 4
            )
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: subband)
            let decoded = try decoder.decode(
                data: data, passCount: passCount, bitDepth: 4, zeroBitPlanes: zeroBitPlanes
            )
            
            let matches = decoded == clamped
            print("subband=\(subband), 16x16, bitDepth=4: \(matches ? "PASS" : "FAIL")")
        }
    }
    
    /// Test a 4x4 block where we can manually trace through every step.
    func testManualTrace4x4() throws {
        // 4x4 block with hand-crafted values:
        // First column (x=0): all non-significant for cleanup pass
        // has mixed values to create interesting RLC scenarios
        let width = 4
        let height = 4
        let coefficients: [Int32] = [
            // bitDepth=4 means values up to 15
            // Row 0: 8, 3, 0, 12     (bit 3: 1,0,0,1)
            // Row 1: 0, 5, 0, 0      (bit 3: 0,0,0,0)
            // Row 2: 9, 0, 0, 6      (bit 3: 1,0,0,0)
            // Row 3: 0, 0, 15, 0     (bit 3: 0,0,1,0)
            8, 3, 0, 12,
            0, 5, 0, 0,
            9, 0, 0, 6,
            0, 0, 15, 0,
        ]
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _, _, _, _) = try encoder.encode(
            coefficients: coefficients, bitDepth: 4
        )
        
        print("4x4 bitDepth=4: passCount=\(passCount), zeroBitPlanes=\(zeroBitPlanes), dataSize=\(data.count)")
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data, passCount: passCount, bitDepth: 4, zeroBitPlanes: zeroBitPlanes
        )
        
        print("Expected: \(coefficients)")
        print("Decoded:  \(decoded)")
        XCTAssertEqual(decoded, coefficients)
    }
}
