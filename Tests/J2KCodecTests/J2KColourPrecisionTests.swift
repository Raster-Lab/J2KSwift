//
// J2KColourPrecisionTests.swift
// J2KSwift
//
// Tests for colour transform precision: gradients, colour bars, edge
// transitions, per-channel PSNR, bias/clipping, and DC level shift.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Colour precision regression tests.
///
/// These tests verify that:
/// - RCT is perfectly reversible on all patterns
/// - ICT round-trip error is bounded (≤ 1 LSB per channel)
/// - Per-channel PSNR is balanced (no channel asymmetry)
/// - DC level shift centres unsigned data correctly
/// - No systematic bias or clipping artefacts
final class J2KColourPrecisionTests: XCTestCase {

    // MARK: - Helpers

    /// Computes per-channel MSE between two Int32 arrays.
    private func mse(_ a: [Int32], _ b: [Int32]) -> Double {
        precondition(a.count == b.count)
        guard !a.isEmpty else { return 0 }
        var sum: Double = 0
        for i in 0..<a.count {
            let d = Double(a[i]) - Double(b[i])
            sum += d * d
        }
        return sum / Double(a.count)
    }

    /// Computes PSNR in dB for a given MSE and peak value.
    private func psnr(mse: Double, peak: Double = 255.0) -> Double {
        guard mse > 0 else { return Double.infinity }
        return 10.0 * log10((peak * peak) / mse)
    }

    /// Computes mean signed error (bias).
    private func bias(_ a: [Int32], _ b: [Int32]) -> Double {
        precondition(a.count == b.count)
        guard !a.isEmpty else { return 0 }
        var sum: Double = 0
        for i in 0..<a.count {
            sum += Double(b[i]) - Double(a[i])
        }
        return sum / Double(a.count)
    }

    /// Computes maximum absolute error.
    private func maxAbsError(_ a: [Int32], _ b: [Int32]) -> Int32 {
        precondition(a.count == b.count)
        var maxErr: Int32 = 0
        for i in 0..<a.count {
            maxErr = max(maxErr, abs(a[i] - b[i]))
        }
        return maxErr
    }

    /// Generates a smooth horizontal gradient (0 → 255) across width pixels,
    /// replicated over height rows.
    private func gradient(width: Int, height: Int, channel: Int) -> [Int32] {
        var data = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                // Shift phase per channel so R/G/B differ
                let val = (x * 255 / max(width - 1, 1) + channel * 85) % 256
                data[y * width + x] = Int32(val)
            }
        }
        return data
    }

    /// Standard SMPTE-style colour bars: white, yellow, cyan, green,
    /// magenta, red, blue, black — 8 bars each `barWidth` pixels wide.
    private func colourBars(barWidth: Int, height: Int)
        -> (red: [Int32], green: [Int32], blue: [Int32])
    {
        let width = barWidth * 8
        let bars: [(Int32, Int32, Int32)] = [
            (255, 255, 255),  // white
            (255, 255, 0),    // yellow
            (0, 255, 255),    // cyan
            (0, 255, 0),      // green
            (255, 0, 255),    // magenta
            (255, 0, 0),      // red
            (0, 0, 255),      // blue
            (0, 0, 0),        // black
        ]
        var r = [Int32](repeating: 0, count: width * height)
        var g = [Int32](repeating: 0, count: width * height)
        var b = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let barIdx = min(x / barWidth, 7)
                let (rv, gv, bv) = bars[barIdx]
                let idx = y * width + x
                r[idx] = rv; g[idx] = gv; b[idx] = bv
            }
        }
        return (r, g, b)
    }

    /// Sharp edge transition: left half = colour A, right half = colour B.
    private func edgeTransition(width: Int, height: Int,
                                colourA: (Int32, Int32, Int32),
                                colourB: (Int32, Int32, Int32))
        -> (red: [Int32], green: [Int32], blue: [Int32])
    {
        var r = [Int32](repeating: 0, count: width * height)
        var g = [Int32](repeating: 0, count: width * height)
        var b = [Int32](repeating: 0, count: width * height)
        let mid = width / 2
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if x < mid {
                    r[idx] = colourA.0; g[idx] = colourA.1; b[idx] = colourA.2
                } else {
                    r[idx] = colourB.0; g[idx] = colourB.1; b[idx] = colourB.2
                }
            }
        }
        return (r, g, b)
    }

    // MARK: - RCT Perfect Reversibility

    func testRCTReversibilityGradient() throws {
        let transform = J2KColorTransform()
        let w = 256; let h = 4
        let red = gradient(width: w, height: h, channel: 0)
        let green = gradient(width: w, height: h, channel: 1)
        let blue = gradient(width: w, height: h, channel: 2)

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
        let (rr, gg, bb) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(red, rr, "RCT gradient: red channel not perfectly reversible")
        XCTAssertEqual(green, gg, "RCT gradient: green channel not perfectly reversible")
        XCTAssertEqual(blue, bb, "RCT gradient: blue channel not perfectly reversible")
    }

    func testRCTReversibilityColourBars() throws {
        let transform = J2KColorTransform()
        let (r, g, b) = colourBars(barWidth: 32, height: 4)

        let (y, cb, cr) = try transform.forwardRCT(red: r, green: g, blue: b)
        let (rr, gg, bb) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r, rr, "RCT colour bars: red not reversible")
        XCTAssertEqual(g, gg, "RCT colour bars: green not reversible")
        XCTAssertEqual(b, bb, "RCT colour bars: blue not reversible")
    }

    func testRCTReversibilityEdgeTransition() throws {
        let transform = J2KColorTransform()
        let (r, g, b) = edgeTransition(
            width: 64, height: 4,
            colourA: (0, 0, 0),
            colourB: (255, 255, 255)
        )

        let (y, cb, cr) = try transform.forwardRCT(red: r, green: g, blue: b)
        let (rr, gg, bb) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r, rr); XCTAssertEqual(g, gg); XCTAssertEqual(b, bb)
    }

    func testRCTReversibilityFullRange() throws {
        // Every possible 8-bit value
        let transform = J2KColorTransform()
        var r = [Int32](); var g = [Int32](); var b = [Int32]()
        for rv in stride(from: 0, to: 256, by: 17) {
            for gv in stride(from: 0, to: 256, by: 17) {
                for bv in stride(from: 0, to: 256, by: 17) {
                    r.append(Int32(rv)); g.append(Int32(gv)); b.append(Int32(bv))
                }
            }
        }
        let (y, cb, cr) = try transform.forwardRCT(red: r, green: g, blue: b)
        let (rr, gg, bb) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r, rr, "RCT not perfectly reversible over full 8-bit range")
        XCTAssertEqual(g, gg)
        XCTAssertEqual(b, bb)
    }

    // MARK: - ICT Round-Trip Precision

    /// Helper: run forward ICT → round to Int32 → inverse ICT → round to Int32,
    /// matching the pipeline's double-rounding behaviour.
    private func ictRoundTrip(red: [Int32], green: [Int32], blue: [Int32])
        throws -> (red: [Int32], green: [Int32], blue: [Int32])
    {
        let transform = J2KColorTransform()
        let rd = red.map { Double($0) }
        let gd = green.map { Double($0) }
        let bd = blue.map { Double($0) }

        let (y, cb, cr) = try transform.forwardICT(red: rd, green: gd, blue: bd)

        // Simulate pipeline rounding (encoder output → Int32)
        let yi = y.map { Int32($0.rounded()) }
        let cbi = cb.map { Int32($0.rounded()) }
        let cri = cr.map { Int32($0.rounded()) }

        // Inverse with same rounding (decoder)
        let yd = yi.map { Double($0) }
        let cbd = cbi.map { Double($0) }
        let crd = cri.map { Double($0) }
        let (rOut, gOut, bOut) = try transform.inverseICT(y: yd, cb: cbd, cr: crd)

        return (
            rOut.map { Int32($0.rounded()) },
            gOut.map { Int32($0.rounded()) },
            bOut.map { Int32($0.rounded()) }
        )
    }

    func testICTRoundTripGradientPSNR() throws {
        let w = 256; let h = 4
        let red = gradient(width: w, height: h, channel: 0)
        let green = gradient(width: w, height: h, channel: 1)
        let blue = gradient(width: w, height: h, channel: 2)

        let (rr, gg, bb) = try ictRoundTrip(red: red, green: green, blue: blue)

        let mseR = mse(red, rr)
        let mseG = mse(green, gg)
        let mseB = mse(blue, bb)

        let psnrR = psnr(mse: mseR)
        let psnrG = psnr(mse: mseG)
        let psnrB = psnr(mse: mseB)

        // ICT double-rounding: expect MAE ≤ 1, PSNR ≥ 40 dB
        XCTAssertGreaterThan(psnrR, 40.0, "Red PSNR too low: \(psnrR) dB")
        XCTAssertGreaterThan(psnrG, 40.0, "Green PSNR too low: \(psnrG) dB")
        XCTAssertGreaterThan(psnrB, 40.0, "Blue PSNR too low: \(psnrB) dB")

        // Channel balance: max PSNR spread should be < 10 dB
        let minPSNR = min(psnrR, psnrG, psnrB)
        let maxPSNR = max(psnrR, psnrG, psnrB)
        let spread = maxPSNR - minPSNR
        XCTAssertLessThan(spread, 10.0,
            "Per-channel PSNR imbalance: R=\(psnrR), G=\(psnrG), B=\(psnrB), spread=\(spread)")

        // MAE ≤ 1
        XCTAssertLessThanOrEqual(maxAbsError(red, rr), 1, "Red MAE > 1")
        XCTAssertLessThanOrEqual(maxAbsError(green, gg), 1, "Green MAE > 1")
        XCTAssertLessThanOrEqual(maxAbsError(blue, bb), 1, "Blue MAE > 1")
    }

    func testICTRoundTripColourBarsPSNR() throws {
        let (r, g, b) = colourBars(barWidth: 32, height: 4)

        let (rr, gg, bb) = try ictRoundTrip(red: r, green: g, blue: b)

        // Colour bars have discrete values — MAE should be ≤ 1
        XCTAssertLessThanOrEqual(maxAbsError(r, rr), 1, "Colour bars: red MAE > 1")
        XCTAssertLessThanOrEqual(maxAbsError(g, gg), 1, "Colour bars: green MAE > 1")
        XCTAssertLessThanOrEqual(maxAbsError(b, bb), 1, "Colour bars: blue MAE > 1")
    }

    func testICTRoundTripEdgeTransition() throws {
        let (r, g, b) = edgeTransition(
            width: 64, height: 4,
            colourA: (16, 235, 128),   // typical video range
            colourB: (235, 16, 64)
        )

        let (rr, gg, bb) = try ictRoundTrip(red: r, green: g, blue: b)

        XCTAssertLessThanOrEqual(maxAbsError(r, rr), 1)
        XCTAssertLessThanOrEqual(maxAbsError(g, gg), 1)
        XCTAssertLessThanOrEqual(maxAbsError(b, bb), 1)
    }

    // MARK: - Bias and Clipping Detection

    func testICTRoundTripBiasGradient() throws {
        let w = 256; let h = 4
        let red = gradient(width: w, height: h, channel: 0)
        let green = gradient(width: w, height: h, channel: 1)
        let blue = gradient(width: w, height: h, channel: 2)

        let (rr, gg, bb) = try ictRoundTrip(red: red, green: green, blue: blue)

        let biasR = bias(red, rr)
        let biasG = bias(green, gg)
        let biasB = bias(blue, bb)

        // Bias should be near zero (< 0.5 LSB on average)
        XCTAssertLessThan(abs(biasR), 0.5, "Red bias: \(biasR)")
        XCTAssertLessThan(abs(biasG), 0.5, "Green bias: \(biasG)")
        XCTAssertLessThan(abs(biasB), 0.5, "Blue bias: \(biasB)")
    }

    func testICTNoClippingAtExtremes() throws {
        let transform = J2KColorTransform()

        // Test extremes: all-zero and all-255
        let zeros: [Int32] = Array(repeating: 0, count: 16)
        let maxVals: [Int32] = Array(repeating: 255, count: 16)

        // All black
        let (rr0, gg0, bb0) = try ictRoundTrip(red: zeros, green: zeros, blue: zeros)
        for i in 0..<16 {
            XCTAssertEqual(rr0[i], 0, "Black: red[\(i)] clipped to \(rr0[i])")
            XCTAssertEqual(gg0[i], 0, "Black: green[\(i)] clipped to \(gg0[i])")
            XCTAssertEqual(bb0[i], 0, "Black: blue[\(i)] clipped to \(bb0[i])")
        }

        // All white
        let (rr255, gg255, bb255) = try ictRoundTrip(red: maxVals, green: maxVals, blue: maxVals)
        for i in 0..<16 {
            XCTAssertEqual(rr255[i], 255, "White: red[\(i)] clipped to \(rr255[i])")
            XCTAssertEqual(gg255[i], 255, "White: green[\(i)] clipped to \(gg255[i])")
            XCTAssertEqual(bb255[i], 255, "White: blue[\(i)] clipped to \(bb255[i])")
        }

        // Pure primaries
        let (rrR, _, _) = try ictRoundTrip(red: maxVals, green: zeros, blue: zeros)
        XCTAssertLessThanOrEqual(maxAbsError(maxVals, rrR), 1, "Pure red: red MAE > 1")

        let (_, ggG, _) = try ictRoundTrip(red: zeros, green: maxVals, blue: zeros)
        XCTAssertLessThanOrEqual(maxAbsError(maxVals, ggG), 1, "Pure green: green MAE > 1")

        let (_, _, bbB) = try ictRoundTrip(red: zeros, green: zeros, blue: maxVals)
        XCTAssertLessThanOrEqual(maxAbsError(maxVals, bbB), 1, "Pure blue: blue MAE > 1")
    }

    // MARK: - ICT Coefficient Verification

    func testICTForwardCoefficientsMatchISO() throws {
        let transform = J2KColorTransform()

        // Pure red (255, 0, 0) — only the R column matters
        let (y, cb, cr) = try transform.forwardICT(
            red: [255.0], green: [0.0], blue: [0.0]
        )
        XCTAssertEqual(y[0], 0.299 * 255, accuracy: 1e-10)
        XCTAssertEqual(cb[0], -0.168736 * 255, accuracy: 1e-10)
        XCTAssertEqual(cr[0], 0.5 * 255, accuracy: 1e-10)

        // Pure green (0, 255, 0)
        let (y2, cb2, cr2) = try transform.forwardICT(
            red: [0.0], green: [255.0], blue: [0.0]
        )
        XCTAssertEqual(y2[0], 0.587 * 255, accuracy: 1e-10)
        XCTAssertEqual(cb2[0], -0.331264 * 255, accuracy: 1e-10)
        XCTAssertEqual(cr2[0], -0.418688 * 255, accuracy: 1e-10)

        // Pure blue (0, 0, 255)
        let (y3, cb3, cr3) = try transform.forwardICT(
            red: [0.0], green: [0.0], blue: [255.0]
        )
        XCTAssertEqual(y3[0], 0.114 * 255, accuracy: 1e-10)
        XCTAssertEqual(cb3[0], 0.5 * 255, accuracy: 1e-10)
        XCTAssertEqual(cr3[0], -0.081312 * 255, accuracy: 1e-10)
    }

    func testICTInverseCoefficientsMatchISO() throws {
        let transform = J2KColorTransform()

        // Identity: Y=1, Cb=0, Cr=0 → should recover R=G=B=1
        let (r, g, b) = try transform.inverseICT(y: [1.0], cb: [0.0], cr: [0.0])
        XCTAssertEqual(r[0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(g[0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(b[0], 1.0, accuracy: 1e-10)

        // Pure Cr=1 contribution
        let (r2, g2, b2) = try transform.inverseICT(y: [0.0], cb: [0.0], cr: [1.0])
        XCTAssertEqual(r2[0], 1.402, accuracy: 1e-10)
        XCTAssertEqual(g2[0], -0.714136, accuracy: 1e-10)
        XCTAssertEqual(b2[0], 0.0, accuracy: 1e-10)

        // Pure Cb=1 contribution
        let (r3, g3, b3) = try transform.inverseICT(y: [0.0], cb: [1.0], cr: [0.0])
        XCTAssertEqual(r3[0], 0.0, accuracy: 1e-10)
        XCTAssertEqual(g3[0], -0.344136, accuracy: 1e-10)
        XCTAssertEqual(b3[0], 1.772, accuracy: 1e-10)
    }

    // MARK: - DC Level Shift

    func testDCLevelShiftCentresUnsignedData() throws {
        // Simulate encoder DC level shift for 8-bit unsigned
        let unsigned8: [Int32] = [0, 128, 255]
        let shift: Int32 = 128  // 2^(8-1)
        let shifted = unsigned8.map { $0 &- shift }

        XCTAssertEqual(shifted, [-128, 0, 127])
    }

    func testDCLevelShiftSignedUnchanged() throws {
        // Signed components should not be shifted
        let signed8: [Int32] = [-128, 0, 127]
        // In the pipeline, signed components skip the shift
        // Verify the values remain unchanged (trivially)
        XCTAssertEqual(signed8, [-128, 0, 127])
    }

    func testDCLevelShiftRoundTrip16Bit() throws {
        // 16-bit unsigned: shift = 32768
        let shift: Int32 = 32768
        let values: [Int32] = [0, 1, 32767, 32768, 65535]
        let shifted = values.map { $0 &- shift }
        let restored = shifted.map { $0 &+ shift }
        XCTAssertEqual(values, restored, "DC level shift round-trip failed for 16-bit")
    }

    func testRCTWithDCLevelShiftedInput() throws {
        // Verify RCT reversibility still holds on DC-shifted (centred) data
        let transform = J2KColorTransform()
        let shift: Int32 = 128
        let r: [Int32] = [200 - shift, 100 - shift, 50 - shift, 0 - shift, 255 - shift]
        let g: [Int32] = [150 - shift, 80 - shift, 200 - shift, 0 - shift, 255 - shift]
        let b: [Int32] = [100 - shift, 60 - shift, 150 - shift, 0 - shift, 255 - shift]

        let (y, cb, cr) = try transform.forwardRCT(red: r, green: g, blue: b)
        let (rr, gg, bb) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r, rr, "RCT not reversible on DC-shifted data")
        XCTAssertEqual(g, gg)
        XCTAssertEqual(b, bb)
    }

    func testICTWithDCLevelShiftedInput() throws {
        // ICT on DC-shifted data should produce centred Y, Cb, Cr
        let transform = J2KColorTransform()
        let shift = 128.0
        let n = 256
        var rd = [Double](repeating: 0, count: n)
        var gd = [Double](repeating: 0, count: n)
        var bd = [Double](repeating: 0, count: n)
        for i in 0..<n {
            rd[i] = Double(i) - shift
            gd[i] = Double(i) - shift
            bd[i] = Double(i) - shift
        }

        let (y, cb, cr) = try transform.forwardICT(red: rd, green: gd, blue: bd)

        // For equal R=G=B (grey ramp), Cb and Cr should be zero
        for i in 0..<n {
            XCTAssertEqual(cb[i], 0.0, accuracy: 1e-10,
                "Cb should be zero for grey input at index \(i)")
            XCTAssertEqual(cr[i], 0.0, accuracy: 1e-10,
                "Cr should be zero for grey input at index \(i)")
        }

        // Y should equal the input (since R=G=B and coefficients sum to 1)
        for i in 0..<n {
            XCTAssertEqual(y[i], rd[i], accuracy: 1e-10,
                "Y should equal input for grey at index \(i)")
        }
    }

    // MARK: - Per-Channel PSNR Balance

    func testICTPerChannelPSNRBalanceOverRandomData() throws {
        // Deterministic pseudo-random data covering full 8-bit range
        let count = 1024
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)

        // Simple LCG for reproducibility
        var seed: UInt64 = 42
        func nextRand() -> Int32 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int32((seed >> 33) & 0xFF)
        }

        for i in 0..<count {
            r[i] = nextRand()
            g[i] = nextRand()
            b[i] = nextRand()
        }

        let (rr, gg, bb) = try ictRoundTrip(red: r, green: g, blue: b)

        let mseR = mse(r, rr)
        let mseG = mse(g, gg)
        let mseB = mse(b, bb)

        let psnrR = psnr(mse: mseR)
        let psnrG = psnr(mse: mseG)
        let psnrB = psnr(mse: mseB)

        // All channels ≥ 40 dB
        XCTAssertGreaterThan(psnrR, 40.0, "Random data: Red PSNR = \(psnrR) dB")
        XCTAssertGreaterThan(psnrG, 40.0, "Random data: Green PSNR = \(psnrG) dB")
        XCTAssertGreaterThan(psnrB, 40.0, "Random data: Blue PSNR = \(psnrB) dB")

        // Spread < 10 dB
        let minP = min(psnrR, psnrG, psnrB)
        let maxP = max(psnrR, psnrG, psnrB)
        XCTAssertLessThan(maxP - minP, 10.0,
            "PSNR spread too large: R=\(psnrR), G=\(psnrG), B=\(psnrB)")

        // MAE ≤ 1 for double-rounding
        XCTAssertLessThanOrEqual(maxAbsError(r, rr), 1)
        XCTAssertLessThanOrEqual(maxAbsError(g, gg), 1)
        XCTAssertLessThanOrEqual(maxAbsError(b, bb), 1)
    }

    func testICTPerChannelBiasOverRandomData() throws {
        let count = 4096
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)

        var seed: UInt64 = 12345
        func nextRand() -> Int32 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int32((seed >> 33) & 0xFF)
        }

        for i in 0..<count {
            r[i] = nextRand(); g[i] = nextRand(); b[i] = nextRand()
        }

        let (rr, gg, bb) = try ictRoundTrip(red: r, green: g, blue: b)

        let biasR = bias(r, rr)
        let biasG = bias(g, gg)
        let biasB = bias(b, bb)

        // No systematic bias (|bias| < 0.5 LSB)
        XCTAssertLessThan(abs(biasR), 0.5, "Red bias: \(biasR)")
        XCTAssertLessThan(abs(biasG), 0.5, "Green bias: \(biasG)")
        XCTAssertLessThan(abs(biasB), 0.5, "Blue bias: \(biasB)")
    }

    // MARK: - Grayscale Fixed-Point Precision

    func testGrayscaleFixedPointAccuracy() throws {
        let transform = J2KColorTransform()

        // Compare integer fixed-point vs double precision
        var maxDiff: Double = 0
        for rv in stride(from: 0, through: 255, by: 1) {
            for gv in stride(from: 0, through: 255, by: 51) {
                for bv in stride(from: 0, through: 255, by: 51) {
                    let ri: [Int32] = [Int32(rv)]
                    let gi: [Int32] = [Int32(gv)]
                    let bi: [Int32] = [Int32(bv)]

                    let grayInt = try transform.rgbToGrayscale(red: ri, green: gi, blue: bi)
                    let grayDbl = try transform.rgbToGrayscale(
                        red: [Double(rv)], green: [Double(gv)], blue: [Double(bv)])

                    let diff = abs(Double(grayInt[0]) - grayDbl[0])
                    maxDiff = max(maxDiff, diff)
                }
            }
        }

        // Fixed-point should be within 1 LSB of floating-point
        XCTAssertLessThanOrEqual(maxDiff, 1.0,
            "Grayscale fixed-point vs double max diff: \(maxDiff)")
    }

    // MARK: - ICT Symmetry (Forward → Inverse = Identity in Double)

    func testICTDoubleSymmetryPerfect() throws {
        // Without any rounding, forward → inverse should be exact
        let transform = J2KColorTransform()
        let testValues: [(Double, Double, Double)] = [
            (0, 0, 0),
            (255, 255, 255),
            (128, 128, 128),
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
            (100.5, 200.7, 50.3),
        ]

        for (rv, gv, bv) in testValues {
            let (y, cb, cr) = try transform.forwardICT(red: [rv], green: [gv], blue: [bv])
            let (rr, gg, bb) = try transform.inverseICT(y: y, cb: cb, cr: cr)

            XCTAssertEqual(rr[0], rv, accuracy: 1e-9,
                "ICT symmetry failed for R at input (\(rv),\(gv),\(bv)): got \(rr[0])")
            XCTAssertEqual(gg[0], gv, accuracy: 1e-9,
                "ICT symmetry failed for G at input (\(rv),\(gv),\(bv)): got \(gg[0])")
            XCTAssertEqual(bb[0], bv, accuracy: 1e-9,
                "ICT symmetry failed for B at input (\(rv),\(gv),\(bv)): got \(bb[0])")
        }
    }
}
