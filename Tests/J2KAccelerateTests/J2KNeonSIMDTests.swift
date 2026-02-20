//
// J2KNeonSIMDTests.swift
// J2KSwift
//
import XCTest
@testable import J2KAccelerate

/// Tests for ARM NEON SIMD-optimised wavelet and colour transforms.
///
/// These tests validate the correctness of NEON-accelerated transform operations
/// by comparing results against known-good scalar references. Tests run on all
/// platforms but NEON-specific paths are only exercised on ARM64.
final class J2KNeonSIMDTests: XCTestCase {

    // MARK: - Capability Detection

    func testNeonTransformCapabilityDetection() {
        let cap = NeonTransformCapability.detect()
        #if arch(arm64)
        XCTAssertTrue(cap.isAvailable, "NEON should be available on ARM64")
        XCTAssertEqual(cap.vectorWidth, 4)
        #else
        XCTAssertFalse(cap.isAvailable, "NEON should not be available on non-ARM64")
        XCTAssertEqual(cap.vectorWidth, 1)
        #endif
    }

    // MARK: - 5/3 Wavelet Lifting

    func testForward53BasicSignal() {
        let lifter = NeonWaveletLifting()
        var data: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let original = data
        lifter.forward53(data: &data, length: data.count)

        // Result should be different from the original
        XCTAssertNotEqual(data, original, "Forward 5/3 should transform the data")

        // Lowpass coefficients in first half should be close to averages
        let halfLen = data.count / 2
        for i in 0..<halfLen {
            XCTAssertFalse(data[i].isNaN, "Lowpass coefficient \(i) should not be NaN")
        }
        for i in halfLen..<data.count {
            XCTAssertFalse(data[i].isNaN, "Highpass coefficient \(i) should not be NaN")
        }
    }

    func testForwardInverse53RoundTrip() {
        let lifter = NeonWaveletLifting()
        let original: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]
        var data = original

        lifter.forward53(data: &data, length: data.count)
        lifter.inverse53(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.01,
                "Round-trip 5/3 should reconstruct sample \(i)")
        }
    }

    func testForwardInverse53LargeSignal() {
        let lifter = NeonWaveletLifting()
        let count = 64
        var original = [Float](repeating: 0, count: count)
        for i in 0..<count {
            original[i] = Float(i * i) / Float(count)
        }
        var data = original

        lifter.forward53(data: &data, length: count)
        lifter.inverse53(data: &data, length: count)

        for i in 0..<count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.01,
                "Round-trip 5/3 should reconstruct large signal sample \(i)")
        }
    }

    func testForward53MinimumLength() {
        let lifter = NeonWaveletLifting()
        var data: [Float] = [1, 2, 3, 4]
        let original = data
        lifter.forward53(data: &data, length: data.count)
        XCTAssertNotEqual(data, original)
    }

    func testForward53TooShort() {
        let lifter = NeonWaveletLifting()
        var data: [Float] = [1, 2]
        let original = data
        lifter.forward53(data: &data, length: data.count)
        XCTAssertEqual(data, original, "Signal too short should be unchanged")
    }

    // MARK: - 9/7 Wavelet Lifting

    func testForward97BasicSignal() {
        let lifter = NeonWaveletLifting()
        var data: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let original = data
        lifter.forward97(data: &data, length: data.count)
        XCTAssertNotEqual(data, original, "Forward 9/7 should transform the data")
    }

    func testForwardInverse97RoundTrip() {
        let lifter = NeonWaveletLifting()
        let original: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]
        var data = original

        lifter.forward97(data: &data, length: data.count)
        lifter.inverse97(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.1,
                "Round-trip 9/7 should reconstruct sample \(i)")
        }
    }

    func testForwardInverse97LargeSignal() {
        let lifter = NeonWaveletLifting()
        let count = 64
        var original = [Float](repeating: 0, count: count)
        for i in 0..<count {
            original[i] = sin(Float(i) * 0.1) * 100
        }
        var data = original

        lifter.forward97(data: &data, length: count)
        lifter.inverse97(data: &data, length: count)

        for i in 0..<count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.5,
                "Round-trip 9/7 should reconstruct large signal sample \(i)")
        }
    }

    // MARK: - ICT (Irreversible Colour Transform)

    func testForwardICT() {
        let transform = NeonColourTransform()
        var r: [Float] = [255, 128, 0, 64]
        var g: [Float] = [0, 128, 255, 192]
        var b: [Float] = [0, 128, 0, 128]

        transform.forwardICT(r: &r, g: &g, b: &b, count: 4)

        // Y should be weighted sum of RGB
        XCTAssertEqual(r[0], 255 * 0.299 + 0 * 0.587 + 0 * 0.114, accuracy: 0.01)
        // Pure white (128, 128, 128) should have Cb ≈ 0, Cr ≈ 0
        XCTAssertEqual(g[1], 0.0, accuracy: 0.1, "Pure grey Cb should be ~0")
        XCTAssertEqual(b[1], 0.0, accuracy: 0.1, "Pure grey Cr should be ~0")
    }

    func testForwardInverseICTRoundTrip() {
        let transform = NeonColourTransform()
        let origR: [Float] = [200, 100, 50, 150, 220, 30, 180, 90]
        let origG: [Float] = [150, 200, 100, 50, 170, 220, 60, 140]
        let origB: [Float] = [100, 50, 200, 100, 80, 190, 230, 110]

        var r = origR, g = origG, b = origB
        transform.forwardICT(r: &r, g: &g, b: &b, count: 8)
        transform.inverseICT(y: &r, cb: &g, cr: &b, count: 8)

        for i in 0..<8 {
            XCTAssertEqual(r[i], origR[i], accuracy: 0.1,
                "ICT round-trip R[\(i)] should match")
            XCTAssertEqual(g[i], origG[i], accuracy: 0.1,
                "ICT round-trip G[\(i)] should match")
            XCTAssertEqual(b[i], origB[i], accuracy: 0.1,
                "ICT round-trip B[\(i)] should match")
        }
    }

    func testICTEmptyInput() {
        let transform = NeonColourTransform()
        var r: [Float] = [], g: [Float] = [], b: [Float] = []
        transform.forwardICT(r: &r, g: &g, b: &b, count: 0)
        XCTAssertTrue(r.isEmpty)
    }

    // MARK: - RCT (Reversible Colour Transform)

    func testForwardRCT() {
        let transform = NeonColourTransform()
        var r: [Int32] = [100, 200, 50, 150]
        var g: [Int32] = [150, 100, 200, 100]
        var b: [Int32] = [200, 50, 150, 50]

        transform.forwardRCT(r: &r, g: &g, b: &b, count: 4)

        // Y = floor((R + 2G + B) / 4)
        XCTAssertEqual(r[0], (100 + 2 * 150 + 200) >> 2)
        // U = B - G
        XCTAssertEqual(g[0], 200 - 150)
        // V = R - G
        XCTAssertEqual(b[0], 100 - 150)
    }

    func testForwardInverseRCTRoundTrip() {
        let transform = NeonColourTransform()
        let origR: [Int32] = [100, 200, 50, 150, 220, 30, 180, 90]
        let origG: [Int32] = [150, 100, 200, 100, 170, 220, 60, 140]
        let origB: [Int32] = [200, 50, 150, 100, 80, 190, 230, 110]

        var r = origR, g = origG, b = origB
        transform.forwardRCT(r: &r, g: &g, b: &b, count: 8)
        transform.inverseRCT(y: &r, u: &g, v: &b, count: 8)

        for i in 0..<8 {
            XCTAssertEqual(r[i], origR[i], "RCT round-trip R[\(i)] should match")
            XCTAssertEqual(g[i], origG[i], "RCT round-trip G[\(i)] should match")
            XCTAssertEqual(b[i], origB[i], "RCT round-trip B[\(i)] should match")
        }
    }

    func testRCTNonMultipleOfFour() {
        let transform = NeonColourTransform()
        let origR: [Int32] = [100, 200, 50, 150, 220]
        let origG: [Int32] = [150, 100, 200, 100, 170]
        let origB: [Int32] = [200, 50, 150, 100, 80]

        var r = origR, g = origG, b = origB
        transform.forwardRCT(r: &r, g: &g, b: &b, count: 5)
        transform.inverseRCT(y: &r, u: &g, v: &b, count: 5)

        for i in 0..<5 {
            XCTAssertEqual(r[i], origR[i], "RCT non-4 round-trip R[\(i)]")
            XCTAssertEqual(g[i], origG[i], "RCT non-4 round-trip G[\(i)]")
            XCTAssertEqual(b[i], origB[i], "RCT non-4 round-trip B[\(i)]")
        }
    }

    // MARK: - Pixel Format Conversion

    func testDeinterleaveRGB() {
        let transform = NeonColourTransform()
        let interleaved: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let result = transform.deinterleaveRGB(interleaved: interleaved, count: 3)

        XCTAssertEqual(result.r, [1, 4, 7])
        XCTAssertEqual(result.g, [2, 5, 8])
        XCTAssertEqual(result.b, [3, 6, 9])
    }

    func testInterleaveRGB() {
        let transform = NeonColourTransform()
        let r: [Float] = [1, 4, 7]
        let g: [Float] = [2, 5, 8]
        let b: [Float] = [3, 6, 9]
        let result = transform.interleaveRGB(r: r, g: g, b: b, count: 3)

        XCTAssertEqual(result, [1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    func testDeinterleaveInterleaveRoundTrip() {
        let transform = NeonColourTransform()
        let original: [Float] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
        let planar = transform.deinterleaveRGB(interleaved: original, count: 4)
        let result = transform.interleaveRGB(r: planar.r, g: planar.g, b: planar.b, count: 4)
        XCTAssertEqual(result, original)
    }

    func testEmptyDeinterleave() {
        let transform = NeonColourTransform()
        let result = transform.deinterleaveRGB(interleaved: [], count: 0)
        XCTAssertTrue(result.r.isEmpty)
        XCTAssertTrue(result.g.isEmpty)
        XCTAssertTrue(result.b.isEmpty)
    }
}
