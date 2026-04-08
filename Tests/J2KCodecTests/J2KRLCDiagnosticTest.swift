import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Diagnostic tests to isolate the EBCOT cleanup pass RLC round-trip bug
/// that causes failures at sizes >= 31×31
final class J2KRLCDiagnosticTest: XCTestCase {

    /// Helper: generates the standard test data pattern
    private func makeCoefficients(width: Int, height: Int) -> [Int32] {
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let sign: Int32 = (i.isMultiple(of: 3)) ? -1 : 1
            coefficients[i] = sign * Int32((i * 7) % 1000)
        }
        return coefficients
    }

    /// Helper: run a round-trip and return mismatch count
    private func roundTrip(
        width: Int, height: Int, bitDepth: Int,
        subband: J2KSubband = .ll,
        options: CodingOptions = .default
    ) throws -> (mismatches: Int, total: Int) {
        let coefficients = makeCoefficients(width: width, height: height)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _, _, _) = try coder.encode(
            coefficients: coefficients, bitDepth: bitDepth
        )
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded, passCount: passCount, bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes, passSegmentLengths: segmentLengths
        )
        var mismatches = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] { mismatches += 1 }
        }
        return (mismatches, coefficients.count)
    }

    // MARK: - Test 1: Predictable termination at various sizes
    // If predictable termination ALSO fails at 31, the bug is in
    // the cleanup pass logic itself, not in MQ stream continuity.
    func testPredictableTermination31x31() throws {
        for size in [29, 30, 31, 32] {
            let options = CodingOptions(terminationMode: .predictable)
            let (mismatches, total) = try roundTrip(
                width: size, height: size, bitDepth: 12, options: options
            )
            print("Predictable \(size)x\(size): \(mismatches)/\(total) mismatches")
            // Don't break - run all sizes
        }
    }

    // MARK: - Test 2: Default termination at various sizes (baseline)
    func testDefaultTerminationSizes() throws {
        for size in [29, 30, 31, 32] {
            let (mismatches, total) = try roundTrip(
                width: size, height: size, bitDepth: 12
            )
            print("Default \(size)x\(size): \(mismatches)/\(total) mismatches")
        }
    }

    // MARK: - Test 3: Isolate width vs height
    // Test non-square sizes to see if the issue is width or height specific
    func testWidthVsHeight() throws {
        // 31 wide, 30 tall — 8 stripes, last has 2 rows, 31 columns
        let r1 = try roundTrip(width: 31, height: 30, bitDepth: 12)
        print("Default 31x30: \(r1.mismatches)/\(r1.total) mismatches")
        
        // 30 wide, 31 tall — 8 stripes, last has 3 rows, 30 columns
        let r2 = try roundTrip(width: 30, height: 31, bitDepth: 12)
        print("Default 30x31: \(r2.mismatches)/\(r2.total) mismatches")
        
        // 30 wide, 32 tall — 8 stripes, all 4 rows, 30 columns
        let r3 = try roundTrip(width: 30, height: 32, bitDepth: 12)
        print("Default 30x32: \(r3.mismatches)/\(r3.total) mismatches")
        
        // 32 wide, 30 tall
        let r4 = try roundTrip(width: 32, height: 30, bitDepth: 12)
        print("Default 32x30: \(r4.mismatches)/\(r4.total) mismatches")
    }

    // MARK: - Test 4: Uniform data (all same magnitude)
    // If all coefficients are identical, the pattern is maximally regular.
    // This isolates whether the data pattern at 31×31 is special.
    func testUniformData31x31() throws {
        for size in [30, 31, 32] {
            var coefficients = [Int32](repeating: 500, count: size * size)
            // Make every 3rd negative
            for i in stride(from: 0, to: coefficients.count, by: 3) {
                coefficients[i] = -coefficients[i]
            }
            
            let options = CodingOptions.default
            let coder = BitPlaneCoder(width: size, height: size, subband: .ll, options: options)
            let (encoded, passCount, zeroBP, segLens, _, _, _) = try coder.encode(
                coefficients: coefficients, bitDepth: 12
            )
            let decoder = BitPlaneDecoder(width: size, height: size, subband: .ll, options: options)
            let decoded = try decoder.decode(
                data: encoded, passCount: passCount, bitDepth: 12,
                zeroBitPlanes: zeroBP, passSegmentLengths: segLens
            )
            var mismatches = 0
            for i in 0..<coefficients.count {
                if coefficients[i] != decoded[i] { mismatches += 1 }
            }
            print("Uniform-500 \(size)x\(size): \(mismatches)/\(coefficients.count) mismatches, passes=\(passCount), zeroBP=\(zeroBP)")
        }
    }

    // MARK: - Test 5: Single bit-plane active (only 1 bit plane)
    // All coefficients = 1. Only bit-plane 0 is active. Only 3 coding passes.
    // This minimizes the number of passes, testing if the issue is pass-count related.
    func testSingleBitPlane() throws {
        for size in [30, 31, 32] {
            var coefficients = [Int32](repeating: 1, count: size * size)
            for i in stride(from: 0, to: coefficients.count, by: 3) {
                coefficients[i] = -1
            }
            
            let options = CodingOptions.default
            let coder = BitPlaneCoder(width: size, height: size, subband: .ll, options: options)
            let (encoded, passCount, zeroBP, segLens, _, _, _) = try coder.encode(
                coefficients: coefficients, bitDepth: 12
            )
            let decoder = BitPlaneDecoder(width: size, height: size, subband: .ll, options: options)
            let decoded = try decoder.decode(
                data: encoded, passCount: passCount, bitDepth: 12,
                zeroBitPlanes: zeroBP, passSegmentLengths: segLens
            )
            var mismatches = 0
            for i in 0..<coefficients.count {
                if coefficients[i] != decoded[i] { mismatches += 1 }
            }
            print("SingleBP \(size)x\(size): \(mismatches)/\(coefficients.count) mismatches, passes=\(passCount), zeroBP=\(zeroBP)")
        }
    }

    // MARK: - Test 5b: Test different partial stripe heights individually
    func testPartialStripeHeights() throws {
        let width = 31
        for height in [4, 8, 12, 16, 20, 24, 28, 32, 36] {  // multiples of 4 only (safe)
            var coefficients = [Int32](repeating: 1, count: width * height)
            for i in stride(from: 0, to: coefficients.count, by: 3) {
                coefficients[i] = -1
            }
            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (encoded, passCount, zeroBP, segLens, _, _, _) = try coder.encode(
                coefficients: coefficients, bitDepth: 12
            )
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(
                data: encoded, passCount: passCount, bitDepth: 12,
                zeroBitPlanes: zeroBP, passSegmentLengths: segLens
            )
            var mismatches = 0
            for i in 0..<coefficients.count {
                if coefficients[i] != decoded[i] { mismatches += 1 }
            }
            print("W=\(width) H=\(height) (mod4=\(height%4)): \(mismatches)/\(coefficients.count) mismatches")
        }
    }

    // MARK: - Test 5c: Narrow the exact threshold
    func testMod4Values() throws {
        // Test W=31 with heights 16..20 and also try different widths
        print("=== W=31, various heights ===")
        for height in [16, 17, 18, 19, 20] {
            let width = 31
            var coefficients = [Int32](repeating: 1, count: width * height)
            for i in stride(from: 0, to: coefficients.count, by: 3) { coefficients[i] = -1 }
            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (encoded, pc, zbp, sl, _, _, _) = try coder.encode(coefficients: coefficients, bitDepth: 12)
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(data: encoded, passCount: pc, bitDepth: 12, zeroBitPlanes: zbp, passSegmentLengths: sl)
            var m = 0
            for i in 0..<coefficients.count { if coefficients[i] != decoded[i] { m += 1 } }
            print("W=\(width) H=\(height) stripes=\(height/4 + (height%4>0 ? 1:0)): \(m)/\(coefficients.count)")
        }

        print("=== Various widths at H=20 ===")
        for width in [16, 20, 24, 28, 30, 31, 32, 33, 40, 48, 64] {
            let height = 20
            var coefficients = [Int32](repeating: 1, count: width * height)
            for i in stride(from: 0, to: coefficients.count, by: 3) { coefficients[i] = -1 }
            let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
            let (encoded, pc, zbp, sl, _, _, _) = try coder.encode(coefficients: coefficients, bitDepth: 12)
            let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
            let decoded = try decoder.decode(data: encoded, passCount: pc, bitDepth: 12, zeroBitPlanes: zbp, passSegmentLengths: sl)
            var m = 0
            for i in 0..<coefficients.count { if coefficients[i] != decoded[i] { m += 1 } }
            print("W=\(width) H=\(height): \(m)/\(coefficients.count)")
        }
        
        print("=== W=31, H=20: Where does first mismatch appear? ===")
        let width = 31
        let height = 20
        var coefficients = [Int32](repeating: 1, count: width * height)
        for i in stride(from: 0, to: coefficients.count, by: 3) { coefficients[i] = -1 }
        let coder = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (encoded, pc, zbp, sl, _, _, _) = try coder.encode(coefficients: coefficients, bitDepth: 12)
        let decoder = BitPlaneDecoder(width: width, height: height, subband: .ll)
        let decoded = try decoder.decode(data: encoded, passCount: pc, bitDepth: 12, zeroBitPlanes: zbp, passSegmentLengths: sl)
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] {
                let x = i % width
                let y = i / width
                print("FIRST mismatch at idx=\(i) (x=\(x),y=\(y)): expected=\(coefficients[i]) got=\(decoded[i])")
                break
            }
        }
    }

    // MARK: - Test 6: Count active bit-planes and passes for different sizes
    // Check if 31×31 triggers a different number of passes or bit-planes
    func testPassCountComparison() throws {
        for size in [29, 30, 31, 32, 33] {
            let coefficients = makeCoefficients(width: size, height: size)
            let maxMag = coefficients.map { UInt32(abs($0)) }.max() ?? 0
            let activeBP = maxMag > 0 ? Int(log2(Double(maxMag))) + 1 : 0
            let zeroBP = max(0, 12 - activeBP)
            
            let options = CodingOptions.default
            let coder = BitPlaneCoder(width: size, height: size, subband: .ll, options: options)
            let (encoded, passCount, encoderZeroBP, _, _, _, _) = try coder.encode(
                coefficients: coefficients, bitDepth: 12
            )
            
            print("Size \(size)x\(size): maxMag=\(maxMag), activeBP=\(activeBP), zeroBP=\(zeroBP), encoderZeroBP=\(encoderZeroBP), passes=\(passCount), encodedBytes=\(encoded.count)")
        }
    }

    // MARK: - Test 7a: Find the threshold for predictable termination failure
    func testPredictableThreshold() throws {
        for size in [4, 8, 12, 16, 20, 24, 28, 29, 30, 31] {
            let options = CodingOptions(terminationMode: .predictable)
            let (mismatches, total) = try roundTrip(
                width: size, height: size, bitDepth: 12, options: options
            )
            print("Pred \(size)x\(size): \(mismatches)/\(total) mismatches")
        }
    }

    // MARK: - Test 7b: Non-square with both dims >= 31
    func testNonSquareLarge() throws {
        for (w, h) in [(31, 32), (32, 31), (33, 31), (31, 33), (35, 35)] {
            let (mismatches, total) = try roundTrip(width: w, height: h, bitDepth: 12)
            print("Default \(w)x\(h): \(mismatches)/\(total) mismatches")
        }
    }

    // MARK: - Test 7: Trace first divergence point
    // Compare decoded coefficients to find WHERE divergence starts
    func testFirstDivergencePoint() throws {
        let size = 31
        let coefficients = makeCoefficients(width: size, height: size)
        
        let options = CodingOptions.default
        let coder = BitPlaneCoder(width: size, height: size, subband: .ll, options: options)
        let (encoded, passCount, zeroBP, segLens, _, _, _) = try coder.encode(
            coefficients: coefficients, bitDepth: 12
        )
        let decoder = BitPlaneDecoder(width: size, height: size, subband: .ll, options: options)
        let decoded = try decoder.decode(
            data: encoded, passCount: passCount, bitDepth: 12,
            zeroBitPlanes: zeroBP, passSegmentLengths: segLens
        )
        
        // Find the first mismatch
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] {
                let x = i % size
                let y = i / size
                let stripeY = (y / 4) * 4
                print("FIRST MISMATCH at idx=\(i) (x=\(x), y=\(y), stripe=\(stripeY)): expected=\(coefficients[i]), got=\(decoded[i])")
                
                // Print surrounding context
                let startIdx = max(0, i - 5)
                let endIdx = min(coefficients.count, i + 10)
                for j in startIdx..<endIdx {
                    let jx = j % size
                    let jy = j / size
                    let marker = j == i ? " <-- FIRST" : ""
                    if coefficients[j] != decoded[j] {
                        print("  [\(j)] (x=\(jx),y=\(jy)): expected=\(coefficients[j]), got=\(decoded[j])\(marker)")
                    } else {
                        print("  [\(j)] (x=\(jx),y=\(jy)): OK (\(coefficients[j]))\(marker)")
                    }
                }
                break
            }
        }
        
        // Also print total stats
        var mismatches = 0
        var firstMismatchBit = -1
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] {
                mismatches += 1
                if firstMismatchBit == -1 {
                    let expected = UInt32(abs(coefficients[i]))
                    let got = UInt32(abs(decoded[i]))
                    let diff = expected ^ got
                    if diff > 0 {
                        firstMismatchBit = Int(log2(Double(diff)))
                    }
                }
            }
        }
        print("Total: \(mismatches)/\(coefficients.count) mismatches")
        print("First mismatch bit position: \(firstMismatchBit)")
    }
}
