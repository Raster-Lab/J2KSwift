import XCTest
@testable import J2KCodec

/// Minimal focused test to find exact point of RLC encoder/decoder divergence.
final class J2KRLCDebugTests: XCTestCase {
    
    /// Test that a single cleanup pass (first bit plane) roundtrips correctly.
    /// This isolates whether the issue is in one pass or cumulative.
    func testSingleBitPlaneRoundTrip() throws {
        // 8x8 block with values that have exactly 1 active bit plane
        // All values are 0 or 1, so only 1 bit plane (MSB), which is cleanup pass only
        let width = 8
        let height = 8
        let coefficients: [Int32] = [
            1, 0, 0, 1, 0, 0, 0, 1,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 1, 0, 0, 0, 0, 1, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 1, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
        ]
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _, _, _, _, _, _) = try  encoder.encode(
            coefficients: coefficients, bitDepth: 1
        )
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data, passCount: passCount, bitDepth: 1, zeroBitPlanes: zeroBitPlanes
            
        )
        
        XCTAssertEqual(decoded, coefficients, "Single bit plane should round-trip exactly")
    }
    
    /// Test with values that occupy 2 bit planes.
    /// This gives: 1 cleanup pass + 1 significance propagation + 1 magnitude refinement + 1 cleanup
    func testTwoBitPlaneRoundTrip() throws {
        let width = 8
        let height = 8
        // Values 0-3, so 2 bit planes
        let coefficients: [Int32] = [
            3, 0, 0, 2, 0, 0, 0, 1,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 1, 0, 0, 0, 0, 3, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 2, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            1, 0, 0, 0, 0, 0, 0, 3,
        ]
        
        let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (data, passCount, zeroBitPlanes, _, _, _, _, _, _) = try  encoder.encode(
            coefficients: coefficients, bitDepth: 2
        )
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(
            data: data, passCount: passCount, bitDepth: 2, zeroBitPlanes: zeroBitPlanes
            
        )
        
        XCTAssertEqual(decoded, coefficients, "Two bit planes should round-trip exactly")
    }
    
    /// Test with a 32x32 block and values that use enough bit planes to trigger the failure.
    /// We incrementally increase the max value to find exactly where it breaks.
    func testIncrementalMaxValueRoundTrip() throws {
        let width = 32
        let height = 32
        let bitDepth = 12
        
        // Test at the threshold we identified
        for maxVal: Int32 in [100, 200, 300, 400, 500, 600, 650, 700, 750, 800, 999] {
            var coefficients = [Int32](repeating: 0, count: width * height)
            for i in 0..<coefficients.count {
                let val = Int32(i % Int(maxVal + 1))
                coefficients[i] = (i % 3 == 0) ? -val : val
            }
            
            let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (data, passCount, zeroBitPlanes, _, _, _, _, _, _) = try  encoder.encode(
                coefficients: coefficients, bitDepth: bitDepth
            )
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: data, passCount: passCount, bitDepth: bitDepth, zeroBitPlanes: zeroBitPlanes
                
            )
            
            let matches = decoded == coefficients
            print("maxVal=\(maxVal): \(matches ? "PASS" : "FAIL") (passCount=\(passCount), zeroBitPlanes=\(zeroBitPlanes), dataSize=\(data.count))")
            if !matches {
                // Find first mismatch
                for i in 0..<coefficients.count {
                    if decoded[i] != coefficients[i] {
                        let x = i % width
                        let y = i / width
                        print("  First mismatch at index \(i) (x=\(x), y=\(y)): expected \(coefficients[i]), got \(decoded[i])")
                        break
                    }
                }
            }
        }
    }
    
    /// Test that ONLY varies the number of coding passes by controlling bit depth.
    /// If the single-pass case works but multi-pass doesn't, the issue is in pass interaction.
    func testVaryingBitPlanes() throws {
        let width = 16
        let height = 16
        
        // Create consistent data with a known pattern
        // Actual max value is 255, which uses 8 bit planes
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32(i % 256)
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        for bitDepth in 1...12 {
            // Clamp coefficients to bitDepth range
            let maxMag = Int32((1 << bitDepth) - 1)
            let clamped = coefficients.map { val -> Int32 in
                let mag = min(abs(val), maxMag) 
                return val < 0 ? -mag : mag
            }
            
            let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (data, passCount, zeroBitPlanes, _, _, _, _, _, _) = try  encoder.encode(
                coefficients: clamped, bitDepth: bitDepth
            )
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: data, passCount: passCount, bitDepth: bitDepth, zeroBitPlanes: zeroBitPlanes
                
            )
            
            let matches = decoded == clamped
            print("bitDepth=\(bitDepth): \(matches ? "PASS" : "FAIL") (passCount=\(passCount), zeroBitPlanes=\(zeroBitPlanes))")
            if !matches {
                for i in 0..<clamped.count {
                    if decoded[i] != clamped[i] {
                        let x = i % width
                        let y = i / width
                        print("  First mismatch at index \(i) (x=\(x), y=\(y)): expected \(clamped[i]), got \(decoded[i])")
                        break
                    }
                }
            }
        }
    }
    
    /// Test with ALL coefficients being the same non-zero value.
    /// In this case, RLC will always find firstSigPos=0 for the first cleanup pass.
    func testUniformNonZeroValues() throws {
        let width = 32
        let height = 32
        let bitDepth = 12
        
        for val: Int32 in [1, 10, 100, 500, 700, 999] {
            let coefficients = [Int32](repeating: val, count: width * height)
            
            let encoder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (data, passCount, zeroBitPlanes, _, _, _, _, _, _) = try  encoder.encode(
                coefficients: coefficients, bitDepth: bitDepth
            )
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: data, passCount: passCount, bitDepth: bitDepth, zeroBitPlanes: zeroBitPlanes
                
            )
            
            let matches = decoded == coefficients
            print("uniform val=\(val): \(matches ? "PASS" : "FAIL") (passCount=\(passCount), zeroBitPlanes=\(zeroBitPlanes))")
        }
    }
}
