import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Trace test: directly encode and decode the minimal failing case
/// and dump per-pass data to find divergence.
final class J2KRLCTraceTest: XCTestCase {
    
    func testTraceMinimalFailure() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        let subband: J2KSubband = .ll
        
        // Generate test data: values 0-255 clamped to bitDepth range
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        // Enable tracing
        let trace = EBCOTDebugTrace.shared
        trace.enabled = true
        trace.reset()
        
        // Encode with per-pass to isolate
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("Segment lengths: \(segmentLengths ?? []), total encoded: \(encoded.count) bytes, passes: \(passCount)")
        
        let encodeOps = trace.encodeOps
        trace.reset()
        
        // Decode
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        let decodeOps = trace.decodeOps
        trace.enabled = false
        
        print("=== TRACE COMPARISON ===")
        print("Encode ops: \(encodeOps.count)")
        print("Decode ops: \(decodeOps.count)")
        
        // Find first divergence
        let minCount = min(encodeOps.count, decodeOps.count)
        var firstDiv = -1
        for i in 0..<minCount {
            let (eOp, eX, eY) = encodeOps[i]
            let (dOp, dX, dY) = decodeOps[i]
            if eOp != dOp || eX != dX || eY != dY {
                firstDiv = i
                
                // Find last pass marker before divergence
                var lastPassMarker = "unknown"
                for j in stride(from: i-1, through: 0, by: -1) {
                    if encodeOps[j].0.contains("===") {
                        lastPassMarker = encodeOps[j].0
                        break
                    }
                }
                print("FIRST DIVERGENCE at operation \(i) (in: \(lastPassMarker)):")
                // Show context: 10 ops before divergence
                let start = max(0, i - 10)
                for j in start...min(i+5, minCount-1) {
                    let ePrefix = j == i ? ">>>ENC " : "   ENC "
                    let dPrefix = j == i ? ">>>DEC " : "   DEC "
                    if j < encodeOps.count {
                        let (op, x, y) = encodeOps[j]
                        print("\(ePrefix)[\(j)] x=\(x) y=\(y) \(op)")
                    }
                    if j < decodeOps.count {
                        let (op, x, y) = decodeOps[j]
                        print("\(dPrefix)[\(j)] x=\(x) y=\(y) \(op)")
                    }
                }
                break
            }
        }
        
        // Also dump the first 50 ops to see the pattern
        print("\n=== ALL PASS MARKERS (encoder) ===")
        for i in 0..<encodeOps.count {
            if encodeOps[i].0.contains("===") {
                print("  [\(i)] \(encodeOps[i].0)")
            }
        }
        print("\n=== FIRST 50 OPS ===")
        for i in 0..<min(50, minCount) {
            let (eOp, eX, eY) = encodeOps[i]
            let (dOp, dX, dY) = decodeOps[i]
            let match = (eOp == dOp && eX == dX && eY == dY) ? "OK" : "DIFF"
            print("[\(i)] E: x=\(eX) y=\(eY) \(eOp) | D: x=\(dX) y=\(dY) \(dOp) \(match)")
        }
        
        if encodeOps.count != decodeOps.count {
            print("OP COUNT MISMATCH: enc=\(encodeOps.count) dec=\(decodeOps.count)")
        } else {
            // Check if any diverge
            var diverged = false
            for i in 0..<encodeOps.count {
                if encodeOps[i].0 != decodeOps[i].0 || encodeOps[i].1 != decodeOps[i].1 || encodeOps[i].2 != decodeOps[i].2 {
                    diverged = true
                    break
                }
            }
            if !diverged {
                print("ALL OPS MATCH - issue is elsewhere!")
            }
        }
        
        var mismatchCount = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] { mismatchCount += 1 }
        }
        
        XCTAssertEqual(coefficients, decoded, "\(mismatchCount) mismatches")
    }
    
    /// Same test but with HL subband (which passes)
    func testTraceHLSubband() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        let subband: J2KSubband = .hl
        
        // Same data
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        let coder = BitPlaneCoder(width: width, height: height, subband: subband)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        var mismatchCount = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] { mismatchCount += 1 }
        }
        
        print("\n=== HL SUBBAND ===")
        print("passCount=\(passCount) zeroBitPlanes=\(zeroBitPlanes) encoded=\(encoded.count) bytes")
        print("mismatches: \(mismatchCount)/\(coefficients.count)")
        
        XCTAssertEqual(coefficients, decoded)
    }
    
    /// Test with per-pass segments to isolate the problem to a specific pass
    func testTracePerPassSegments() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        let subband: J2KSubband = .ll
        
        // Same data
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        // Encode with per-pass segments (predictable termination)
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("\n=== PER-PASS SEGMENTS (LL) ===")
        print("passCount=\(passCount) zeroBitPlanes=\(zeroBitPlanes)")
        print("segmentLengths=\(segmentLengths)")
        print("total encoded=\(encoded.count) bytes")
        
        // Decode with per-pass segments
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let decoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        var mismatchCount = 0
        for i in 0..<coefficients.count {
            if coefficients[i] != decoded[i] { mismatchCount += 1 }
        }
        
        print("mismatches: \(mismatchCount)/\(coefficients.count)")
        
        if mismatchCount == 0 {
            print("PER-PASS PASSES - problem is in continuous mode MQ state carry-over!")
        } else {
            print("PER-PASS ALSO FAILS - problem is within a single pass")
        }
        
        XCTAssertEqual(coefficients, decoded, "\(mismatchCount) mismatches")
    }
    
    /// Test: encode incrementally and verify each stage matches at its precision
    func testTraceSingleBitPlane() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        let subband: J2KSubband = .ll
        
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        // Full encode (all passes) then decode
        let options = CodingOptions(terminationMode: .predictable)
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (encoded, passCount, zeroBitPlanes, segmentLengths, _) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("\n=== INCREMENTAL DECODE TEST ===")
        print("passCount=\(passCount) zeroBitPlanes=\(zeroBitPlanes) segments=\(segmentLengths)")
        
        // Decode incrementally: 1 pass at a time
        for numPasses in 1...passCount {
            let truncatedSegments = Array(segmentLengths.prefix(numPasses))
            let truncatedData = Data(encoded.prefix(truncatedSegments.reduce(0, +)))
            
            let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
            let decoded = try decoder.decode(
                data: truncatedData,
                passCount: numPasses,
                bitDepth: bitDepth,
                zeroBitPlanes: zeroBitPlanes,
                passSegmentLengths: truncatedSegments
            )
            
            // Full decode with all passes for reference
            let fullDecoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
            let fullDecoded = try fullDecoder.decode(
                data: encoded,
                passCount: passCount,
                bitDepth: bitDepth,
                zeroBitPlanes: zeroBitPlanes,
                passSegmentLengths: segmentLengths
            )
            
            // Check if truncated decode is consistent with input at appropriate precision
            // For numPasses passes over bitDepth-zeroBitPlanes active bit planes,
            // each bit plane has 3 passes
            let activeBitPlanes = bitDepth - zeroBitPlanes
            let bitPlanesDecoded = (numPasses + 2) / 3 // ceiling of numPasses/3 (approximately)
            let precisionMask: UInt32 = numPasses >= passCount ? 0xFFFFFFFF : (0xFFFFFFFF << UInt32(activeBitPlanes - bitPlanesDecoded))
            
            var mismatchCount = 0
            for i in 0..<coefficients.count {
                if decoded[i] != fullDecoded[i] {
                    // Only count as mismatch if this position ALSO differs in full decode
                    // Actually, just compare truncated to expected truncation of input
                }
                if coefficients[i] != decoded[i] { mismatchCount += 1 }
            }
            
            let passType = numPasses % 3 == 1 ? "SigProp" : (numPasses % 3 == 2 ? "MagRef" : "Cleanup")
            let bitPlane = activeBitPlanes - 1 - (numPasses - 1) / 3
            print("pass \(numPasses)/\(passCount) (\(passType) bp=\(bitPlane)): vs_full_mismatches=\(mismatchCount)")
        }
        
        // The real test: full decode should match exactly
        let decoder = BitPlaneDecoder(width: width, height: height, subband: subband, options: options)
        let fullDecoded = try decoder.decode(
            data: encoded,
            passCount: passCount,
            bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: segmentLengths
        )
        
        var fullMismatch = 0
        var firstMismatchIdx = -1
        for i in 0..<coefficients.count {
            if coefficients[i] != fullDecoded[i] {
                fullMismatch += 1
                if firstMismatchIdx == -1 {
                    firstMismatchIdx = i
                    let y = i / width
                    let x = i % width
                    print("FIRST MISMATCH: idx=\(i) (x=\(x),y=\(y)) expected=\(coefficients[i]) got=\(fullDecoded[i])")
                }
            }
        }
        print("Full decode mismatches: \(fullMismatch)/\(coefficients.count)")
        
        XCTAssertEqual(coefficients, fullDecoded, "\(fullMismatch) mismatches")
    }
    
    /// Test old code behavior: revert to fallthrough for LL
    func testOldCodeBehaviorLL() throws {
        let width = 16
        let height = 16
        let bitDepth = 4
        
        // Same data
        let maxVal = (1 << bitDepth) - 1
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            let val = Int32(i % 256)
            coefficients[i] = min(val, Int32(maxVal))
            if i % 3 == 0 { coefficients[i] = -coefficients[i] }
        }
        
        // Test with HL (should pass with both old and new code)
        let coderHL = BitPlaneCoder(width: width, height: height, subband: .hl)
        let (encodedHL, passCountHL, zeroBitPlanesHL, segHL, _) = try coderHL.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        let coderLL = BitPlaneCoder(width: width, height: height, subband: .ll)
        let (encodedLL, passCountLL, zeroBitPlanesLL, segLL, _) = try coderLL.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        print("\n=== HL vs LL comparison ===")
        print("HL: passCount=\(passCountHL) zeroBitPlanes=\(zeroBitPlanesHL) size=\(encodedHL.count)")
        print("LL: passCount=\(passCountLL) zeroBitPlanes=\(zeroBitPlanesLL) size=\(encodedLL.count)")
        print("Same pass structure: \(passCountHL == passCountLL && zeroBitPlanesHL == zeroBitPlanesLL)")
        
        // Compare encoded bytes
        if encodedHL.count == encodedLL.count {
            var diffBytes = 0
            for i in 0..<encodedHL.count {
                if encodedHL[i] != encodedLL[i] { diffBytes += 1 }
            }
            print("Encoded byte differences: \(diffBytes)/\(encodedHL.count)")
        } else {
            print("Different encoded sizes!")
        }
    }
}
