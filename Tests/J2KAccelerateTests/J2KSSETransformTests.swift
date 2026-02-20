//
// J2KSSETransformTests.swift
// J2KSwift
//
// Tests for Intel x86-64 SSE4.2/AVX2 wavelet, colour, quantisation,
// and cache optimisation operations.
//
// Tests run on all platforms; x86-64 SIMD paths are exercised on x86_64.
//
import XCTest
@testable import J2KAccelerate

/// Tests for Intel x86-64 SSE4.2/AVX2-accelerated transform operations.
final class J2KSSETransformTests: XCTestCase {

    private let tolerance: Float = 1e-4

    // MARK: - Capability Detection

    func testX86TransformCapabilityDetection() {
        let cap = X86TransformCapability.detect()
        #if arch(x86_64)
        XCTAssertTrue(cap.isAvailable, "x86-64 SIMD should be available on x86_64")
        XCTAssertTrue(cap.hasSSE42, "SSE4.2 should be available on modern x86-64")
        XCTAssertTrue(cap.hasAVX2, "AVX2 should be available on modern x86-64")
        XCTAssertTrue(cap.hasFMA, "FMA should be available on modern x86-64")
        XCTAssertEqual(cap.vectorWidth, 8, "AVX2 vector width should be 8 floats")
        #else
        XCTAssertFalse(cap.isAvailable)
        XCTAssertFalse(cap.hasSSE42)
        XCTAssertFalse(cap.hasAVX2)
        XCTAssertFalse(cap.hasFMA)
        XCTAssertEqual(cap.vectorWidth, 1)
        #endif
    }

    func testX86TransformCapabilityLogicalConsistency() {
        let cap = X86TransformCapability.detect()
        if cap.hasAVX2 {
            XCTAssertTrue(cap.hasSSE42, "AVX2 implies SSE4.2")
            XCTAssertTrue(cap.isAvailable, "AVX2 availability implies SIMD available")
        }
        if cap.hasFMA {
            XCTAssertTrue(cap.hasAVX2, "FMA implies AVX2 on modern x86-64")
        }
        if !cap.isAvailable {
            XCTAssertFalse(cap.hasSSE42, "Not available implies no SSE4.2")
            XCTAssertFalse(cap.hasAVX2, "Not available implies no AVX2")
            XCTAssertFalse(cap.hasFMA, "Not available implies no FMA")
        }
        // Verify equality with a second detect() call
        let cap2 = X86TransformCapability.detect()
        XCTAssertEqual(cap, cap2, "Two detect() calls should return equal capabilities")
    }

    // MARK: - Wavelet Lifting: 5/3 Basic Correctness

    func testForward53BasicSignal() {
        let lifter = X86WaveletLifting()
        var data: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let original = data
        lifter.forward53(data: &data, length: data.count)

        XCTAssertNotEqual(data, original, "Forward 5/3 should transform data")
        for val in data { XCTAssertFalse(val.isNaN, "No NaN after forward 5/3") }
    }

    func testForwardInverse53RoundTrip8() {
        let lifter = X86WaveletLifting()
        let original: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]
        var data = original
        lifter.forward53(data: &data, length: data.count)
        lifter.inverse53(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.01,
                "Round-trip 5/3 sample \(i)")
        }
    }

    func testForwardInverse53RoundTrip16() {
        let lifter = X86WaveletLifting()
        let original = (0..<16).map { Float($0 * 3 + 1) }
        var data = original
        lifter.forward53(data: &data, length: data.count)
        lifter.inverse53(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.01,
                "Round-trip 5/3 sample \(i) (16 elements)")
        }
    }

    func testForwardInverse53RoundTrip32() {
        let lifter = X86WaveletLifting()
        let original = (0..<32).map { Float($0) }
        var data = original
        lifter.forward53(data: &data, length: data.count)
        lifter.inverse53(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.1,
                "Round-trip 5/3 sample \(i) (32 elements)")
        }
    }

    func testForward53TooShort() {
        let lifter = X86WaveletLifting()
        var data: [Float] = [1, 2, 3]
        let before = data
        lifter.forward53(data: &data, length: data.count)
        XCTAssertEqual(data, before, "Signals shorter than 4 should be unchanged")
    }

    func testForward53ConstantSignal() {
        let lifter = X86WaveletLifting()
        var data = [Float](repeating: 5.0, count: 8)
        lifter.forward53(data: &data, length: data.count)
        // Highpass coefficients of a constant signal should be zero
        for i in 4..<8 {
            XCTAssertEqual(data[i], 0.0, accuracy: 1e-5,
                "Highpass of constant signal should be zero at \(i)")
        }
    }

    // MARK: - Wavelet Lifting: 9/7 Basic Correctness

    func testForward97BasicSignal() {
        let lifter = X86WaveletLifting()
        var data: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let original = data
        lifter.forward97(data: &data, length: data.count)

        XCTAssertNotEqual(data, original, "Forward 9/7 should transform data")
        for val in data { XCTAssertFalse(val.isNaN, "No NaN after forward 9/7") }
    }

    func testForwardInverse97RoundTrip8() {
        let lifter = X86WaveletLifting()
        let original: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]
        var data = original
        lifter.forward97(data: &data, length: data.count)
        lifter.inverse97(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.01,
                "Round-trip 9/7 sample \(i)")
        }
    }

    func testForwardInverse97RoundTrip16() {
        let lifter = X86WaveletLifting()
        let original = (0..<16).map { Float($0 * 2 + 1) }
        var data = original
        lifter.forward97(data: &data, length: data.count)
        lifter.inverse97(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.05,
                "Round-trip 9/7 sample \(i) (16 elements)")
        }
    }

    func testForwardInverse97RoundTrip32() {
        let lifter = X86WaveletLifting()
        let original = (0..<32).map { Float($0) }
        var data = original
        lifter.forward97(data: &data, length: data.count)
        lifter.inverse97(data: &data, length: data.count)

        for i in 0..<original.count {
            XCTAssertEqual(data[i], original[i], accuracy: 0.1,
                "Round-trip 9/7 sample \(i) (32 elements)")
        }
    }

    func testForward97TooShort() {
        let lifter = X86WaveletLifting()
        var data: [Float] = [1, 2]
        let before = data
        lifter.forward97(data: &data, length: data.count)
        XCTAssertEqual(data, before, "Signals shorter than 4 should be unchanged")
    }

    // MARK: - Wavelet Lifting: Consistency with NEON Reference

    // x86-64 and NEON paths should produce identical results on the same input.
    func testForward53MatchesScalarReference() {
        let lifter = X86WaveletLifting()
        var dataX86: [Float] = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
        lifter.forward53(data: &dataX86, length: dataX86.count)

        // Compute scalar reference
        var dataRef: [Float] = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
        scalarForward53(data: &dataRef, length: dataRef.count)

        for i in 0..<dataX86.count {
            XCTAssertEqual(dataX86[i], dataRef[i], accuracy: 1e-5,
                "x86 5/3 should match scalar reference at \(i)")
        }
    }

    func testForward97MatchesScalarReference() {
        let lifter = X86WaveletLifting()
        var dataX86: [Float] = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
        lifter.forward97(data: &dataX86, length: dataX86.count)

        var dataRef: [Float] = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
        scalarForward97(data: &dataRef, length: dataRef.count)

        for i in 0..<dataX86.count {
            XCTAssertEqual(dataX86[i], dataRef[i], accuracy: 1e-4,
                "x86 9/7 should match scalar reference at \(i)")
        }
    }

    // MARK: - ICT Colour Transform

    func testForwardICTBasicRGB() {
        let ct = X86ColourTransform()
        var r: [Float] = [255, 0, 0, 128]
        var g: [Float] = [0, 255, 0, 128]
        var b: [Float] = [0, 0, 255, 128]
        ct.forwardICT(r: &r, g: &g, b: &b, count: 4)

        // Y for pure red (255,0,0) = 0.299 * 255 ≈ 76.245
        XCTAssertEqual(r[0], 0.299 * 255, accuracy: 0.01, "Y for pure red")
        // Cb for pure green (0,255,0) = -0.33126 * 255 ≈ -84.471
        XCTAssertEqual(g[1], -0.33126 * 255, accuracy: 0.01, "Cb for pure green")
        // Cr for pure blue (0,0,255) = -0.08131 * 255 ≈ -20.734
        XCTAssertEqual(b[2], -0.08131 * 255, accuracy: 0.01, "Cr for pure blue")
    }

    func testForwardInverseICTRoundTrip() {
        let ct = X86ColourTransform()
        let originalR: [Float] = [100, 200, 50, 175, 25, 220, 80, 160]
        let originalG: [Float] = [50, 100, 150, 75, 200, 120, 30, 90]
        let originalB: [Float] = [200, 50, 100, 225, 75, 60, 190, 140]
        var r = originalR, g = originalG, b = originalB

        ct.forwardICT(r: &r, g: &g, b: &b, count: 8)
        ct.inverseICT(y: &r, cb: &g, cr: &b, count: 8)

        for i in 0..<8 {
            XCTAssertEqual(r[i], originalR[i], accuracy: 0.01, "R round-trip at \(i)")
            XCTAssertEqual(g[i], originalG[i], accuracy: 0.01, "G round-trip at \(i)")
            XCTAssertEqual(b[i], originalB[i], accuracy: 0.01, "B round-trip at \(i)")
        }
    }

    func testForwardICTGrayInputYEqualsLuma() {
        let ct = X86ColourTransform()
        // For equal R=G=B, Y = 0.299R + 0.587G + 0.114B = R
        let val: Float = 128.0
        var r: [Float] = [val]
        var g: [Float] = [val]
        var b: [Float] = [val]
        ct.forwardICT(r: &r, g: &g, b: &b, count: 1)
        XCTAssertEqual(r[0], val, accuracy: 0.01, "Y should equal original luminance for grey input")
        XCTAssertEqual(g[0], 0.0, accuracy: 0.01, "Cb should be ~0 for grey input")
        XCTAssertEqual(b[0], 0.0, accuracy: 0.01, "Cr should be ~0 for grey input")
    }

    func testForwardICTEmpty() {
        let ct = X86ColourTransform()
        var r: [Float] = [], g: [Float] = [], b: [Float] = []
        ct.forwardICT(r: &r, g: &g, b: &b, count: 0)
        XCTAssertTrue(r.isEmpty && g.isEmpty && b.isEmpty)
    }

    // MARK: - RCT Colour Transform

    func testForwardRCTBasic() {
        let ct = X86ColourTransform()
        var r: [Int32] = [4, 8]
        var g: [Int32] = [2, 4]
        var b: [Int32] = [4, 8]
        ct.forwardRCT(r: &r, g: &g, b: &b, count: 2)

        // Y = (R + 2G + B) >> 2 = (4 + 4 + 4) >> 2 = 3
        XCTAssertEqual(r[0], 3, "Y = (4+2*2+4)>>2 = 3")
        // U = B - G = 4 - 2 = 2
        XCTAssertEqual(g[0], 2, "U = B - G = 2")
        // V = R - G = 4 - 2 = 2
        XCTAssertEqual(b[0], 2, "V = R - G = 2")
    }

    func testForwardInverseRCTRoundTrip() {
        let ct = X86ColourTransform()
        let originalR: [Int32] = [10, 20, 30, 40, 50, 60, 70, 80]
        let originalG: [Int32] = [5, 15, 25, 35, 45, 55, 65, 75]
        let originalB: [Int32] = [8, 18, 28, 38, 48, 58, 68, 78]
        var r = originalR, g = originalG, b = originalB

        ct.forwardRCT(r: &r, g: &g, b: &b, count: 8)
        ct.inverseRCT(y: &r, u: &g, v: &b, count: 8)

        for i in 0..<8 {
            XCTAssertEqual(r[i], originalR[i], "R round-trip at \(i)")
            XCTAssertEqual(g[i], originalG[i], "G round-trip at \(i)")
            XCTAssertEqual(b[i], originalB[i], "B round-trip at \(i)")
        }
    }

    func testForwardRCTGrayInput() {
        let ct = X86ColourTransform()
        var r: [Int32] = [100]
        var g: [Int32] = [100]
        var b: [Int32] = [100]
        ct.forwardRCT(r: &r, g: &g, b: &b, count: 1)
        // Y = (100 + 200 + 100) >> 2 = 400 >> 2 = 100
        XCTAssertEqual(r[0], 100, "Y for grey input")
        // U = B - G = 0
        XCTAssertEqual(g[0], 0, "U = 0 for grey")
        // V = R - G = 0
        XCTAssertEqual(b[0], 0, "V = 0 for grey")
    }

    func testForwardRCTVectorAlignment() {
        let ct = X86ColourTransform()
        // 9 elements: exercises SIMD8 + 1 scalar tail
        var r = (0..<9).map { Int32($0 * 4) }
        var g = (0..<9).map { Int32($0 * 2) }
        var b = (0..<9).map { Int32($0 * 3) }
        let origR = r, origG = g, origB = b

        ct.forwardRCT(r: &r, g: &g, b: &b, count: 9)
        ct.inverseRCT(y: &r, u: &g, v: &b, count: 9)

        for i in 0..<9 {
            XCTAssertEqual(r[i], origR[i], "R round-trip at \(i) (9 elements)")
            XCTAssertEqual(g[i], origG[i], "G round-trip at \(i) (9 elements)")
            XCTAssertEqual(b[i], origB[i], "B round-trip at \(i) (9 elements)")
        }
    }

    // MARK: - Batch Quantisation

    func testBatchQuantiseBasic() {
        let q = X86Quantizer()
        let coefficients: [Float] = [0, 8, 16, 24, 32, 40, 48, 56]
        let result = q.batchQuantise(coefficients: coefficients, stepSize: 8.0)
        let expected: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        XCTAssertEqual(result, expected)
    }

    func testBatchQuantiseZeroCoefficients() {
        let q = X86Quantizer()
        let coefficients = [Float](repeating: 0, count: 8)
        let result = q.batchQuantise(coefficients: coefficients, stepSize: 4.0)
        XCTAssertEqual(result, [Int32](repeating: 0, count: 8))
    }

    func testBatchQuantiseInvalidStepSize() {
        let q = X86Quantizer()
        let result = q.batchQuantise(coefficients: [1, 2, 3], stepSize: 0)
        XCTAssertTrue(result.isEmpty, "Zero step size should return empty")
    }

    func testBatchDequantiseBasic() {
        let q = X86Quantizer()
        let indices: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let stepSize: Float = 8.0
        let result = q.batchDequantise(indices: indices, stepSize: stepSize)
        XCTAssertEqual(result.count, 8)
        // Index 0 → 0.0 (zero, no offset)
        XCTAssertEqual(result[0], 0.0, accuracy: 0.01)
        // Index 4 → (4 + 0.5) * 8 = 36
        XCTAssertEqual(result[4], 36.0, accuracy: 0.01)
    }

    func testQuantiseRoundTripApproximate() {
        let q = X86Quantizer()
        let step: Float = 4.0
        let original: [Float] = [0, 4, 8, 12, 16, 20, 24, 28]
        let quantised = q.batchQuantise(coefficients: original, stepSize: step)
        let reconstructed = q.batchDequantise(indices: quantised, stepSize: step)

        for i in 0..<original.count {
            // Reconstruction error bounded by stepSize / 2
            XCTAssertEqual(reconstructed[i], original[i], accuracy: step,
                "Quantise round-trip error at \(i) should be < stepSize")
        }
    }

    func testBatchDeadZoneQuantise() {
        let q = X86Quantizer()
        let step: Float = 8.0
        let deadZone: Float = 4.0
        // Values below deadZone → 0; above → normal quantisation
        let coefficients: [Float] = [3, 0, -3, 12, -12, 8, -8, 16]
        let result = q.batchDeadZoneQuantise(
            coefficients: coefficients,
            stepSize: step,
            deadZone: deadZone
        )
        // 3 < 4 (deadZone) → 0
        XCTAssertEqual(result[0], 0, "Value below dead zone → 0")
        // 0 → 0
        XCTAssertEqual(result[1], 0, "Zero → 0")
        // -3 < 4 (deadZone) → 0
        XCTAssertEqual(result[2], 0, "Negative below dead zone → 0")
        // 12: (12 - 4) / 8 = 1
        XCTAssertEqual(result[3], 1, "12 above dead zone → quantised 1")
        // -12: -(12 - 4) / 8 = -1
        XCTAssertEqual(result[4], -1, "−12 above dead zone → quantised −1")
    }

    func testBatchDeadZoneQuantiseLargeInput() {
        let q = X86Quantizer()
        let count = 17  // Exercises SIMD8 twice + 1 scalar
        let coefficients = (0..<count).map { Float($0 * 2) }
        let result = q.batchDeadZoneQuantise(
            coefficients: coefficients,
            stepSize: 4.0,
            deadZone: 2.0
        )
        XCTAssertEqual(result.count, count)
    }

    // MARK: - Cache Optimiser

    func testCacheBlockedDWTCorrectDimensions() throws {
        let cacheOpt = X86CacheOptimizer()
        let width = 64, height = 64
        let data = (0..<(width * height)).map { Float($0) }
        let result = try cacheOpt.cacheBlockedDWT(data: data, width: width, height: height)
        XCTAssertEqual(result.count, data.count)
    }

    func testCacheBlockedDWTInvalidDimensions() {
        let cacheOpt = X86CacheOptimizer()
        let data = [Float](repeating: 1.0, count: 10)
        XCTAssertThrowsError(try cacheOpt.cacheBlockedDWT(data: data, width: 4, height: 4),
            "Should throw for mismatched dimensions")
    }

    func testCacheBlockedDWTSmallImage() throws {
        let cacheOpt = X86CacheOptimizer()
        let width = 4, height = 4
        let data = (0..<16).map { Float($0) }
        let result = try cacheOpt.cacheBlockedDWT(data: data, width: width, height: height)
        XCTAssertEqual(result.count, 16)
    }

    func testL1BlockSizeIsPlatformDependent() {
        #if arch(x86_64)
        XCTAssertEqual(X86CacheOptimizer.l1BlockSize, 32, "x86-64 L1 block size should be 32")
        XCTAssertEqual(X86CacheOptimizer.l2BlockSize, 256, "x86-64 L2 block size should be 256")
        #else
        XCTAssertEqual(X86CacheOptimizer.l1BlockSize, 64, "Non-x86-64 L1 block size should be 64")
        XCTAssertEqual(X86CacheOptimizer.l2BlockSize, 512, "Non-x86-64 L2 block size should be 512")
        #endif
    }

    func testAllocateAligned() {
        let cacheOpt = X86CacheOptimizer()
        let buf = cacheOpt.allocateAligned(count: 64)
        XCTAssertEqual(buf.count, 64)
        XCTAssertEqual(buf, [Float](repeating: 0, count: 64), "Aligned buffer should be zero-filled")
    }

    func testStreamingStore() {
        let cacheOpt = X86CacheOptimizer()
        let source = (0..<16).map { Float($0) }
        var dest = [Float](repeating: 0, count: 16)
        cacheOpt.streamingStore(source: source, destination: &dest, count: 16)
        XCTAssertEqual(Array(dest), source)
    }
}

// MARK: - Scalar Reference Implementations

/// Scalar reference implementation of forward 5/3 lifting for test validation.
private func scalarForward53(data: inout [Float], length: Int) {
    guard length >= 4 else { return }
    let halfLen = length / 2
    var low = (0..<halfLen).map { data[2 * $0] }
    var high = (0..<halfLen).map { data[2 * $0 + 1] }

    for i in 0..<(halfLen - 1) { high[i] += -0.5 * (low[i] + low[i + 1]) }
    high[halfLen - 1] += -0.5 * (low[halfLen - 1] + low[halfLen - 1])

    low[0] += 0.25 * (high[0] + high[0])
    for i in 1..<halfLen { low[i] += 0.25 * (high[i - 1] + high[i]) }

    for i in 0..<halfLen {
        data[i] = low[i]
        data[halfLen + i] = high[i]
    }
}

/// Scalar reference implementation of forward 9/7 lifting for test validation.
private func scalarForward97(data: inout [Float], length: Int) {
    guard length >= 4 else { return }
    let halfLen = length / 2
    let alpha97: Float = -1.586134342
    let beta97: Float  = -0.052980118
    let gamma97: Float =  0.882911076
    let delta97: Float =  0.443506852
    let k97: Float     =  1.230174105

    var low  = (0..<halfLen).map { data[2 * $0] }
    var high = (0..<halfLen).map { data[2 * $0 + 1] }

    func predict(_ l: [Float], _ h: inout [Float], _ f: Float) {
        for i in 0..<(halfLen - 1) { h[i] += f * (l[i] + l[i + 1]) }
        h[halfLen - 1] += f * (l[halfLen - 1] + l[halfLen - 1])
    }
    func update(_ l: inout [Float], _ h: [Float], _ f: Float) {
        l[0] += f * (h[0] + h[0])
        for i in 1..<halfLen { l[i] += f * (h[i - 1] + h[i]) }
    }

    predict(low, &high, alpha97)
    update(&low, high, beta97)
    predict(low, &high, gamma97)
    update(&low, high, delta97)

    for i in 0..<halfLen { low[i] *= k97; high[i] /= k97 }
    for i in 0..<halfLen { data[i] = low[i]; data[halfLen + i] = high[i] }
}
