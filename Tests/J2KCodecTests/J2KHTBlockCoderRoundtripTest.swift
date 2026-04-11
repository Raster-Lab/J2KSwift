//
// J2KHTBlockCoderRoundtripTest.swift
// J2KSwift
//
// Direct encode/decode roundtrip test for HT block coder

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KHTBlockCoderRoundtripTest: XCTestCase {

    /// Test cleanup-only roundtrip with known coefficients
    func testCleanupRoundtripSmall() throws {
        let width = 8
        let height = 8
        // Known coefficient pattern with mix of significant and insignificant
        let coefficients: [Int] = [
            128, 0, 50, 200, -130, 0, 0, 64,
            0, 0, 0, 0, 255, -128, 0, 0,
            133, 0, 0, -200, 0, 0, 0, 0,
            0, 129, 0, 0, 0, 0, -140, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
        ]

        let maxMag = coefficients.map { abs($0) }.max()!
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1
        print("maxMag=\(maxMag), topBitPlane=\(topBitPlane)")

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let block = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: block)

        // Check each coefficient
        var mismatches = 0
        for i in 0..<coefficients.count {
            let expected = coefficients[i]
            let sigBit = (abs(expected) >> topBitPlane) & 1
            if sigBit != 0 {
                // Significant: should be fully reconstructed at cleanup level
                if decoded[i] != expected {
                    print("MISMATCH at \(i): expected \(expected), got \(decoded[i])")
                    mismatches += 1
                }
            } else {
                // Not significant at topBitPlane: should be 0 after cleanup
                if decoded[i] != 0 {
                    print("NON-SIG MISMATCH at \(i): expected 0, got \(decoded[i])")
                    mismatches += 1
                }
            }
        }
        print("Cleanup roundtrip: \(mismatches) mismatches out of \(coefficients.count)")
        XCTAssertEqual(mismatches, 0, "Cleanup roundtrip should be lossless for significant coefficients")
    }

    /// Test with random coefficients of various magnitudes
    func testCleanupRoundtripRandom() throws {
        let width = 16
        let height = 16
        // Use a fixed seed for reproducibility
        srand48(42)
        let coefficients = (0..<(width * height)).map { _ -> Int in
            let v = Int.random(in: -200...200)
            return v
        }

        let maxMag = coefficients.map { abs($0) }.max()!
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let block = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: block)

        var mismatches = 0
        for i in 0..<coefficients.count {
            let expected = coefficients[i]
            let sigBit = (abs(expected) >> topBitPlane) & 1
            if sigBit != 0 {
                if decoded[i] != expected {
                    if mismatches < 10 {
                        print("MISMATCH[\(i)]: expected \(expected), got \(decoded[i]) (sigBit=\(sigBit), bp=\(topBitPlane))")
                    }
                    mismatches += 1
                }
            }
        }
        print("Random roundtrip: \(mismatches)/\(coefficients.count) mismatches (bp=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "Cleanup roundtrip should be lossless for significant coefficients")
    }

    /// Test full encode/decode via decodeFromCodestream (cleanup + refinement)
    func testFullRoundtripInt32() throws {
        let width = 8
        let height = 8
        let coefficients: [Int32] = [
            128, 5, 50, 200, -130, 3, 0, 64,
            0, 10, 20, 30, 255, -128, 7, 0,
            133, 0, 15, -200, 0, 0, 0, 0,
            0, 129, 0, 0, 0, 0, -140, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 1, 0, 2, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 3,
        ]

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1
        let bitDepth = topBitPlane + 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients.map { Int32($0) }, bitPlane: topBitPlane)
        var significanceState = result.significanceState
        let absMags = result.absMags

        var allData = result.block.codedData
        var totalPasses = 1

        // Add refinement passes
        for bp in stride(from: topBitPlane - 1, through: 0, by: -1) {
            let sigPropData = try encoder.encodeSigProp(
                coefficients: coefficients.map { Int($0) },
                significanceState: significanceState,
                bitPlane: bp
            )
            allData.append(sigPropData)
            totalPasses += 1

            let magRefData = try encoder.encodeMagRef(
                coefficients: coefficients.map { Int($0) },
                significanceState: significanceState,
                bitPlane: bp
            )
            allData.append(magRefData)
            totalPasses += 1

            // Update significance
            for i in 0..<coefficients.count {
                if !significanceState[i] && (Int(absMags[i]) >> bp) & 1 != 0 {
                    significanceState[i] = true
                }
            }
        }

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeFromCodestream(
            data: allData,
            passCount: totalPasses,
            bitDepth: bitDepth,
            zeroBitPlanes: 0
        )

        var mismatches = 0
        for i in 0..<coefficients.count {
            if decoded[i] != coefficients[i] {
                print("FULL MISMATCH[\(i)]: expected \(coefficients[i]), got \(decoded[i])")
                mismatches += 1
            }
        }
        print("Full roundtrip: \(mismatches)/\(coefficients.count) mismatches")
        XCTAssertEqual(mismatches, 0, "Full encode/decode roundtrip should be lossless")
    }

    /// Test full roundtrip with 64×64 block (actual pipeline code block size)
    func testFullRoundtrip64x64() throws {
        let width = 64
        let height = 64
        let count = width * height

        // Generate realistic wavelet-like coefficients:
        // mostly small values with some large ones scattered through
        var coefficients = [Int32](repeating: 0, count: count)
        srand48(123) // Fixed seed for reproducibility
        for i in 0..<count {
            let r = drand48()
            if r < 0.3 {
                // 30% chance of significant coefficient
                coefficients[i] = Int32.random(in: -255...255)
            } else if r < 0.5 {
                // 20% small coefficient
                coefficients[i] = Int32.random(in: -15...15)
            }
            // else 50% zero
        }

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        guard maxMag > 0 else { return }
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1
        let bitDepth = topBitPlane + 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)
        var significanceState = result.significanceState
        let absMags = result.absMags

        var allData = result.block.codedData
        var totalPasses = 1

        for bp in stride(from: topBitPlane - 1, through: 0, by: -1) {
            let sigPropData = try encoder.encodeSigProp(
                coefficients: coefficients.map { Int($0) },
                significanceState: significanceState,
                bitPlane: bp
            )
            allData.append(sigPropData)
            totalPasses += 1

            let magRefData = try encoder.encodeMagRef(
                coefficients: coefficients.map { Int($0) },
                significanceState: significanceState,
                bitPlane: bp
            )
            allData.append(magRefData)
            totalPasses += 1

            for i in 0..<count {
                if !significanceState[i] && (Int(absMags[i]) >> bp) & 1 != 0 {
                    significanceState[i] = true
                }
            }
        }

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeFromCodestream(
            data: allData,
            passCount: totalPasses,
            bitDepth: bitDepth,
            zeroBitPlanes: 0
        )

        var mismatches = 0
        for i in 0..<count {
            if decoded[i] != coefficients[i] {
                if mismatches < 10 {
                    print("64x64 MISMATCH[\(i)]: expected \(coefficients[i]), got \(decoded[i])")
                }
                mismatches += 1
            }
        }
        print("64x64 full roundtrip: \(mismatches)/\(count) mismatches (topBP=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "64x64 full roundtrip should be lossless")
    }

    /// Test cleanup-only roundtrip with 64×64 block to isolate cleanup vs refinement issues
    func testCleanupOnly64x64() throws {
        let width = 64
        let height = 64
        let count = width * height

        var coefficients = [Int32](repeating: 0, count: count)
        srand48(123)
        for i in 0..<count {
            let r = drand48()
            if r < 0.3 {
                coefficients[i] = Int32.random(in: -255...255)
            } else if r < 0.5 {
                coefficients[i] = Int32.random(in: -15...15)
            }
        }

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        guard maxMag > 0 else { return }
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: result.block)

        var mismatches = 0
        for i in 0..<count {
            let expected = Int(coefficients[i])
            let sigBit = (abs(expected) >> topBitPlane) & 1
            if sigBit != 0 {
                if decoded[i] != expected {
                    if mismatches < 10 {
                        let row = i / width
                        let col = i % width
                        print("CLEANUP64 MISMATCH[\(i)] r=\(row) c=\(col): expected \(expected), got \(decoded[i])")
                    }
                    mismatches += 1
                }
            } else {
                if decoded[i] != 0 {
                    if mismatches < 10 {
                        let row = i / width
                        let col = i % width
                        print("CLEANUP64 GHOST[\(i)] r=\(row) c=\(col): expected 0, got \(decoded[i])")
                    }
                    mismatches += 1
                }
            }
        }
        print("64x64 cleanup-only: \(mismatches)/\(count) mismatches (topBP=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "64x64 cleanup roundtrip should be lossless for significant coefficients")
    }

    /// Test with all coefficients significant — isolates MagSgn/VLC from MEL run coding
    func testCleanupAllSignificant64x64() throws {
        let width = 64
        let height = 64
        let count = width * height

        // All coefficients are significant at the top bit-plane (>= 128)
        var coefficients = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            // Values 128-255, all significant at bp=7
            let sign: Int32 = (i % 3 == 0) ? -1 : 1
            coefficients[i] = sign * Int32(128 + (i % 128))
        }

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: result.block)

        var mismatches = 0
        for i in 0..<count {
            let expected = Int(coefficients[i])
            if decoded[i] != expected {
                if mismatches < 10 {
                    print("ALLSIG MISMATCH[\(i)]: expected \(expected), got \(decoded[i])")
                }
                mismatches += 1
            }
        }
        print("All-significant 64x64: \(mismatches)/\(count) mismatches (topBP=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "All-significant cleanup should be lossless")
    }

    /// Deterministic mixed-significance test to trace MEL desync
    func testCleanupDeterministic32x8() throws {
        let width = 32
        let height = 8
        let count = width * height

        // Deterministic pattern: alternate significant/insignificant
        // At bp=7, coefficient must be >= 128 to be significant
        var coefficients = [Int32](repeating: 0, count: count)
        // Put significant values at known positions
        // Pattern: every 3rd coefficient is significant
        for i in 0..<count {
            if i % 3 == 0 {
                coefficients[i] = 128 + Int32(i % 128)
            } else if i % 7 == 0 {
                coefficients[i] = -(128 + Int32(i % 128))
            }
            // else 0 (not significant)
        }

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        // Compute expected significance pattern for verification
        var expectedSig = [Bool](repeating: false, count: count)
        for i in 0..<count {
            expectedSig[i] = (abs(Int(coefficients[i])) >> topBitPlane) & 1 != 0
        }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        // Print stream sizes for debugging
        let codedData = result.block.codedData
        let mel16 = UInt16(codedData[0]) << 8 | UInt16(codedData[1])
        let vlc16 = UInt16(codedData[2]) << 8 | UInt16(codedData[3])
        let mag16 = UInt16(codedData[4]) << 8 | UInt16(codedData[5])
        print("Stream sizes: mel=\(mel16) vlc=\(vlc16) magsgn=\(mag16) total=\(codedData.count)")

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: result.block)

        var mismatches = 0
        for i in 0..<count {
            let expected = Int(coefficients[i])
            let sigBit = (abs(expected) >> topBitPlane) & 1
            let actual = decoded[i]

            if sigBit != 0 {
                if actual != expected {
                    print("DET MISMATCH[\(i)] r=\(i/width) c=\(i%width): expected \(expected), got \(actual)")
                    mismatches += 1
                }
            } else {
                if actual != 0 {
                    print("DET GHOST[\(i)] r=\(i/width) c=\(i%width): expected 0, got \(actual)")
                    mismatches += 1
                }
            }
        }
        print("Deterministic 32x8: \(mismatches)/\(count) mismatches (topBP=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "Deterministic cleanup roundtrip should be lossless")
    }

    /// Test with sparse coefficients to trigger long MEL runs
    func testCleanupSparse64x64() throws {
        let width = 64
        let height = 64
        let count = width * height

        // Very sparse: only ~5% of coefficients are significant
        var coefficients = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            if i % 20 == 0 {
                coefficients[i] = 128 + Int32(i % 128)
            } else if i % 37 == 0 {
                coefficients[i] = -(128 + Int32(i % 128))
            }
        }

        let maxMag = Int(coefficients.map { abs($0) }.max()!)
        guard maxMag > 0 else { return }
        let topBitPlane = Int.bitWidth - maxMag.leadingZeroBitCount - 1

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: topBitPlane)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanup(from: result.block)

        var mismatches = 0
        for i in 0..<count {
            let expected = Int(coefficients[i])
            let sigBit = (abs(expected) >> topBitPlane) & 1
            if sigBit != 0 {
                if decoded[i] != expected {
                    if mismatches < 15 {
                        let row = i / width, col = i % width
                        let pairRow = row % 4, stripe = row / 4, pairCol = col / 2
                        print("SPARSE MISMATCH[\(i)] r=\(row) c=\(col) stripe=\(stripe) pairCol=\(pairCol) pairRow=\(pairRow): expected \(expected), got \(decoded[i])")
                    }
                    mismatches += 1
                }
            } else {
                if decoded[i] != 0 {
                    if mismatches < 15 {
                        let row = i / width, col = i % width
                        let pairRow = row % 4, stripe = row / 4, pairCol = col / 2
                        print("SPARSE GHOST[\(i)] r=\(row) c=\(col) stripe=\(stripe) pairCol=\(pairCol) pairRow=\(pairRow): expected 0, got \(decoded[i])")
                    }
                    mismatches += 1
                }
            }
        }
        print("Sparse 64x64: \(mismatches)/\(count) mismatches (topBP=\(topBitPlane))")
        XCTAssertEqual(mismatches, 0, "Sparse cleanup should be lossless")
    }

    /// Direct MEL round-trip test with known decision sequence
    func testMELRoundtripLongRun() throws {
        // Create a decision sequence that produces long runs of zeros
        // This mimics what happens in sparse 64×64 blocks
        var decisions: [Int] = []
        // Pattern: mostly zeros with occasional ones, triggering longer runs
        for i in 0..<128 {
            if i % 10 == 0 {
                decisions.append(1)
            } else {
                decisions.append(0)
            }
        }

        // Encode
        var melEncoder = HTMELCoder()
        for d in decisions {
            melEncoder.encode(bit: d)
        }
        let melData = melEncoder.flush()
        print("MEL data: \(melData.count) bytes for \(decisions.count) decisions")

        // Decode
        var melReader = J2KBitReader(data: melData)
        var melDecoder = HTMELCoder()
        var decoded: [Int] = []
        for _ in 0..<decisions.count {
            let d = try melDecoder.decode(from: &melReader)
            decoded.append(d)
        }

        var mismatches = 0
        for i in 0..<decisions.count {
            if decisions[i] != decoded[i] {
                print("MEL DECISION MISMATCH[\(i)]: encoded \(decisions[i]), decoded \(decoded[i])")
                mismatches += 1
                if mismatches > 20 { break }
            }
        }
        print("MEL roundtrip: \(mismatches)/\(decisions.count) mismatches")
        XCTAssertEqual(mismatches, 0, "MEL decisions should round-trip perfectly")
    }
}
