//
// J2KMetalDWT53IntBitExactTests.swift
// J2KSwift
//
// Verifies the bit-exact integer 5/3 inverse DWT path on GPU. The DICOMKit
// lossless verifyEncodedRoundTrip workflow enforces byte equality between
// the encoder input and the decoder output, so this path *must* match the
// JPEG 2000 spec exactly — no Float rounding allowed.
//

import XCTest
@testable import J2KMetal
@testable import J2KCore

final class J2KMetalDWT53IntBitExactTests: XCTestCase {
    // The bit-exact reference, replicated locally so the test does not depend
    // on the J2KCodec module (J2KMetalTests only links against J2KMetal +
    // J2KCore). Matches J2KDWT1D.inverseTransform53 with symmetric extension.
    private static func reference1DInverse53(lowpass: [Int32], highpass: [Int32]) -> [Int32] {
        let lpSize = lowpass.count
        let hpSize = highpass.count
        if hpSize == 0 { return lowpass }
        let n = lpSize + hpSize
        var even = lowpass
        for i in 0..<lpSize {
            let left  = (i > 0) ? highpass[i - 1] : highpass[0]
            let right = (i < hpSize) ? highpass[i] : highpass[hpSize - 1]
            even[i] = lowpass[i] - ((left + right + 2) >> 2)
        }
        var odd = [Int32](repeating: 0, count: hpSize)
        for i in 0..<hpSize {
            let left  = even[i]
            let right = (i + 1 < lpSize) ? even[i + 1] : even[lpSize - 1]
            odd[i] = highpass[i] + ((left + right) >> 1)
        }
        var result = [Int32](repeating: 0, count: n)
        for i in 0..<lpSize { result[2 * i] = even[i] }
        for i in 0..<hpSize { result[2 * i + 1] = odd[i] }
        return result
    }

    // 2D reference: per JPEG 2000 spec (Annex F), inverse applies
    // horizontal pass first (per row: LL+HL → colLow, LH+HH → colHigh),
    // then vertical pass (per column: colLow+colHigh → final output).
    private static func reference2DInverse53(
        ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32],
        llWidth: Int, llHeight: Int,
        originalWidth: Int, originalHeight: Int
    ) -> [Int32] {
        let llW = llWidth, llH = llHeight
        let halfWH = originalWidth / 2
        let halfHH = originalHeight / 2
        let width = originalWidth
        let height = originalHeight

        // Step 1: horizontal pass
        var colLow  = [Int32](repeating: 0, count: width * llH)
        var colHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)

        for y in 0..<llH {
            let lpRow = Array(ll[(y * llW)..<(y * llW + llW)])
            let hpRow: [Int32]
            if hl.isEmpty || halfWH == 0 {
                hpRow = []
            } else {
                hpRow = Array(hl[(y * halfWH)..<(y * halfWH + halfWH)])
            }
            let merged = reference1DInverse53(lowpass: lpRow, highpass: hpRow)
            for x in 0..<min(width, merged.count) {
                colLow[y * width + x] = merged[x]
            }
        }

        if halfHH > 0 {
            for y in 0..<halfHH {
                let lpRow: [Int32]
                if lh.isEmpty {
                    lpRow = [Int32](repeating: 0, count: llW)
                } else {
                    lpRow = Array(lh[(y * llW)..<(y * llW + llW)])
                }
                let hpRow: [Int32]
                if hh.isEmpty || halfWH == 0 {
                    hpRow = []
                } else {
                    hpRow = Array(hh[(y * halfWH)..<(y * halfWH + halfWH)])
                }
                let merged = reference1DInverse53(lowpass: lpRow, highpass: hpRow)
                for x in 0..<min(width, merged.count) {
                    colHigh[y * width + x] = merged[x]
                }
            }
        }

        // Step 2: vertical pass
        var result = [Int32](repeating: 0, count: width * height)
        for x in 0..<width {
            var lpCol = [Int32](repeating: 0, count: llH)
            for y in 0..<llH { lpCol[y] = colLow[y * width + x] }
            var hpCol: [Int32] = []
            if halfHH > 0 {
                hpCol = [Int32](repeating: 0, count: halfHH)
                for y in 0..<halfHH { hpCol[y] = colHigh[y * width + x] }
            }
            let merged = reference1DInverse53(lowpass: lpCol, highpass: hpCol)
            for y in 0..<min(height, merged.count) {
                result[y * width + x] = merged[y]
            }
        }
        return result
    }

    // Build a synthetic decomposition by running the analysis (forward) 5/3
    // on a bit-perfect deterministic image. The forward 1D below is the
    // direct inverse of `reference1DInverse53` from the spec.
    private static func reference1DForward53(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        let lpSize = (n + 1) / 2
        let hpSize = n / 2
        var lp = [Int32](repeating: 0, count: lpSize)
        var hp = [Int32](repeating: 0, count: hpSize)
        // Predict: hp[i] = signal[2i+1] - floor((signal[2i] + signal[2i+2]) / 2)
        for i in 0..<hpSize {
            let left = signal[2 * i]
            let right = (2 * i + 2 < n) ? signal[2 * i + 2] : signal[2 * i]
            hp[i] = signal[2 * i + 1] - ((left + right) >> 1)
        }
        // Update: lp[i] = signal[2i] + floor((hp[i-1] + hp[i] + 2) / 4)
        for i in 0..<lpSize {
            let left  = (i > 0) ? hp[i - 1] : (hpSize > 0 ? hp[0] : 0)
            let right = (i < hpSize) ? hp[i] : (hpSize > 0 ? hp[hpSize - 1] : 0)
            lp[i] = signal[2 * i] + ((left + right + 2) >> 2)
        }
        return (lp, hp)
    }

    private static func deterministic12BitImage(width: Int, height: Int, seed: UInt64) -> [Int32] {
        // 12-bit grayscale has range [0, 4095]. Use a linear-congruential
        // generator so the pattern is reproducible across runs.
        var state = seed | 1
        var data = [Int32](repeating: 0, count: width * height)
        for i in 0..<data.count {
            state = state &* 2862933555777941757 &+ 3037000493
            data[i] = Int32((state >> 32) & 0xFFF)  // 0..4095
        }
        return data
    }

    private static func deterministic16BitImage(width: Int, height: Int, seed: UInt64) -> [Int32] {
        var state = seed | 1
        var data = [Int32](repeating: 0, count: width * height)
        for i in 0..<data.count {
            state = state &* 2862933555777941757 &+ 3037000493
            data[i] = Int32((state >> 16) & 0xFFFF) - 32768  // signed 16-bit-ish
        }
        return data
    }

    // Build a single-level (LL, LH, HL, HH) decomposition matching the
    // JPEG 2000 spec encoder order (vertical forward first, then horizontal
    // forward). The matching inverse is horizontal-then-vertical, which is
    // what `J2KMetalDWT.inverse2DInt32` does after the spec-correctness fix.
    private static func buildSingleLevelDecomposition(
        image: [Int32], width: Int, height: Int
    ) -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32], llW: Int, llH: Int) {
        let llW = (width + 1) / 2
        let llH = (height + 1) / 2
        let halfWH = width / 2
        let halfHH = height / 2

        // Step 1 (vertical forward on columns): each column → low and high rows.
        var vLow  = [Int32](repeating: 0, count: width * llH)
        var vHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)
        for x in 0..<width {
            var col = [Int32](repeating: 0, count: height)
            for y in 0..<height { col[y] = image[y * width + x] }
            let (lp, hp) = reference1DForward53(signal: col)
            for y in 0..<llH { vLow[y * width + x] = lp[y] }
            for y in 0..<halfHH { vHigh[y * width + x] = hp[y] }
        }

        // Step 2 (horizontal forward on rows of vLow / vHigh):
        //   rows of vLow  → LL (lowpass cols) and HL (highpass cols)
        //   rows of vHigh → LH (lowpass cols) and HH (highpass cols)
        var ll = [Int32](repeating: 0, count: llW * llH)
        var hl = [Int32](repeating: 0, count: max(halfWH, 1) * llH)
        var lh = [Int32](repeating: 0, count: llW * halfHH)
        var hh = [Int32](repeating: 0, count: max(halfWH, 1) * halfHH)
        for y in 0..<llH {
            let row = Array(vLow[(y * width)..<(y * width + width)])
            let (lp, hp) = reference1DForward53(signal: row)
            for x in 0..<llW { ll[y * llW + x] = lp[x] }
            for x in 0..<halfWH { hl[y * halfWH + x] = hp[x] }
        }
        for y in 0..<halfHH {
            let row = Array(vHigh[(y * width)..<(y * width + width)])
            let (lp, hp) = reference1DForward53(signal: row)
            for x in 0..<llW { lh[y * llW + x] = lp[x] }
            for x in 0..<halfWH { hh[y * halfWH + x] = hp[x] }
        }
        return (ll, lh, hl, hh, llW, llH)
    }

    // MARK: - Tests

    /// 12-bit 384×384 grayscale: GPU integer inverse must equal the spec reference exactly.
    func testInverse2DInt32_12BitGrayscale_BitExactGPUMatchesSpec() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 384, height = 384
        let image = Self.deterministic12BitImage(width: width, height: height, seed: 0xCAFE_BEEF)
        let dec = Self.buildSingleLevelDecomposition(image: image, width: width, height: height)
        let expected = Self.reference2DInverse53(
            ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
            llWidth: dec.llW, llHeight: dec.llH,
            originalWidth: width, originalHeight: height
        )
        XCTAssertEqual(expected, image, "Forward + reference-inverse 5/3 must perfectly round-trip")

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let subbands = J2KMetalDWTSubbandsInt32(
            ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
            llWidth: dec.llW, llHeight: dec.llH,
            originalWidth: width, originalHeight: height
        )

        let gpuResult = try await dwt.inverse2DInt32(subbands: subbands, backend: .gpu)
        XCTAssertEqual(gpuResult, expected, "GPU integer 5/3 inverse must be bit-exact with spec")

        let cpuResult = try await dwt.inverse2DInt32(subbands: subbands, backend: .cpu)
        XCTAssertEqual(cpuResult, expected, "CPU integer 5/3 inverse must be bit-exact with spec")
    }

    /// 16-bit 256×256 high-bit-depth: this is the case where the old Float
    /// path produced non-bit-exact output because float arithmetic does not
    /// truncate `(a+b+2)/4` to `floor((a+b+2)/4)`.
    func testInverse2DInt32_16BitGrayscale_BitExactGPUMatchesSpec() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 256, height = 256
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xDEAD_BEEF)
        let dec = Self.buildSingleLevelDecomposition(image: image, width: width, height: height)
        let expected = Self.reference2DInverse53(
            ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
            llWidth: dec.llW, llHeight: dec.llH,
            originalWidth: width, originalHeight: height
        )
        XCTAssertEqual(expected, image)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let subbands = J2KMetalDWTSubbandsInt32(
            ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
            llWidth: dec.llW, llHeight: dec.llH,
            originalWidth: width, originalHeight: height
        )

        let gpu = try await dwt.inverse2DInt32(subbands: subbands, backend: .gpu)
        XCTAssertEqual(gpu, image, "GPU 5/3 inverse must round-trip 16-bit data bit-exactly")
    }

    /// Odd dimensions exercise the asymmetric (lpSize != hpSize) boundary path,
    /// where the CPU implementation uses min((i+1)*2, (lpSize-1)*2) for the
    /// last odd sample. The GPU shader's `(2*i+2 < width)` branch must produce
    /// identical results for both even and odd dimensions.
    func testInverse2DInt32_OddDimensions_BitExactBoundaries() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        for (w, h) in [(257, 257), (513, 257), (257, 513), (511, 511)] {
            let image = Self.deterministic12BitImage(width: w, height: h, seed: UInt64(w * 31 + h))
            let dec = Self.buildSingleLevelDecomposition(image: image, width: w, height: h)
            let expected = Self.reference2DInverse53(
                ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
                llWidth: dec.llW, llHeight: dec.llH,
                originalWidth: w, originalHeight: h
            )

            let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
                filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
            ))
            try await dwt.initialize()

            let subbands = J2KMetalDWTSubbandsInt32(
                ll: dec.ll, lh: dec.lh, hl: dec.hl, hh: dec.hh,
                llWidth: dec.llW, llHeight: dec.llH,
                originalWidth: w, originalHeight: h
            )
            let gpu = try await dwt.inverse2DInt32(subbands: subbands, backend: .gpu)
            XCTAssertEqual(gpu, expected, "GPU output must be bit-exact for \(w)×\(h)")
        }
    }
}
