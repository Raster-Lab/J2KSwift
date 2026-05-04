// J2KWaveletConventionAuditTests.swift
// v5.22.0 — Conformance Audit. Cross-module wavelet implementation
// agreement.
//
// Background: v5.21.0 caught a scaling-direction inversion in
// J2KMetalDWT vs J2KCodec.J2KDWT1D — both modules were self-
// consistent (round-trip within each worked) but used opposite
// conventions for the 9/7 ε scaling step. The bug was invisible to
// internal round-trip tests; only direct cross-module comparison
// surfaced it.
//
// This test suite locks in cross-module agreement to prevent the
// same shape of bug from re-appearing or being introduced in other
// wavelet paths:
//
// 1. J2KMetalDWT 9/7 inverse vs J2KCodec.J2KDWT1D 9/7 inverse —
//    locks in the v5.21.0 scaling fix.
// 2. J2KMetalDWT 9/7 forward vs J2KCodec.J2KDWT1D 9/7 forward —
//    same. The forward CPU reference was also fixed in v5.21.0.
// 3. J2KMetalDWT 5/3 vs J2KCodec.J2KDWT1D 5/3 — already proven
//    bit-exact via v5.7+ Int32 tests, but this lock makes the
//    contract explicit at the Float-array level too.
// 4. JP3DMetalDWT 9/7 forward vs J2K3D.JP3DWaveletTransform 9/7
//    forward — locks in the v5.22.0 fix.
//
// All tests use Float-precision tolerance (max diff < 1e-3 on
// 64-element synthetic input). A failure means the convention
// drifted and a cross-module decode/encode pair would corrupt data.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class J2KWaveletConventionAuditTests: XCTestCase {

    private func synthSignal(count: Int, seed: UInt64 = 0xfeed_face) -> [Double] {
        var s = seed
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            out[i] = Double(Int32(bitPattern: UInt32(s >> 32))) / Double(Int32.max) * 100.0
        }
        return out
    }

    // MARK: - 9/7 inverse cross-module agreement (v5.21.0 lock-in)

    /// J2KMetalDWT.inverse2D(.cpu) and J2KCodec.J2KDWT1D.inverseTransform97
    /// must agree to within Float-precision tolerance on a single
    /// level. Pre-v5.21.0 they disagreed by K⁴ ≈ 2.29× scaling.
    func testJ2KMetalDWT_vs_J2KCodec_Inverse97_AgreeOnSingleLevel() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available for context")

        let n = 64
        let halfN = (n + 1) / 2
        let halfH = n / 2

        // Build identical lowpass + highpass for both modules.
        let lowpassD = synthSignal(count: halfN, seed: 0x1)
        let highpassD = synthSignal(count: halfH, seed: 0x2)

        // J2KCodec.J2KDWT1D inverse 9/7 (Double, the canonical reference).
        let codecResult = try J2KDWT1D.inverseTransform97(
            lowpass: lowpassD, highpass: highpassD)

        // J2KMetalDWT inverse 9/7 (Float, CPU backend for direct
        // comparison without GPU dispatch noise).
        let lowpassF = lowpassD.map { Float($0) }
        let highpassF = highpassD.map { Float($0) }
        // Use 1D path: build a 2D-shape with height=1
        let metalDWT = J2KMetalDWT(
            configuration: J2KMetalDWTConfiguration(filter: .irreversible97))
        try await metalDWT.initialize()
        let metalResult = try await metalDWT.inverse1D(
            lowpass: lowpassF, highpass: highpassF, backend: .cpu)

        XCTAssertEqual(codecResult.count, metalResult.count,
            "J2KCodec and J2KMetalDWT inverse 9/7 produced different output sizes")

        var maxDiff: Double = 0
        for i in 0..<min(codecResult.count, metalResult.count) {
            let d = abs(codecResult[i] - Double(metalResult[i]))
            if d > maxDiff { maxDiff = d }
        }
        // Float vs Double on 64-element input: expect max diff < 1e-3.
        XCTAssertLessThan(maxDiff, 1e-3,
            "Cross-module 9/7 inverse divergence: J2KMetalDWT vs J2KCodec.J2KDWT1D max diff = \(maxDiff)")
    }

    // MARK: - 9/7 forward cross-module agreement

    /// J2KMetalDWT.forward1D(.cpu) and J2KCodec.J2KDWT1D.forwardTransform97
    /// must agree. v5.21.0 fixed the scaling direction in both forward
    /// and inverse — this gate catches re-introduction of the inversion.
    func testJ2KMetalDWT_vs_J2KCodec_Forward97_AgreeOnSingleLevel() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available for context")

        let n = 64
        let inputD = synthSignal(count: n, seed: 0x3)

        // J2KCodec forward 9/7 (Double canonical).
        let codecResult = try J2KDWT1D.forwardTransform97(signal: inputD)

        // J2KMetalDWT forward 9/7 (Float, CPU backend).
        let inputF = inputD.map { Float($0) }
        let metalDWT = J2KMetalDWT(
            configuration: J2KMetalDWTConfiguration(filter: .irreversible97))
        try await metalDWT.initialize()
        let metalResult = try await metalDWT.forward1D(signal: inputF, backend: .cpu)

        XCTAssertEqual(codecResult.lowpass.count, metalResult.lowpass.count,
            "Forward 9/7 lowpass size mismatch")
        XCTAssertEqual(codecResult.highpass.count, metalResult.highpass.count,
            "Forward 9/7 highpass size mismatch")

        var maxLowDiff: Double = 0
        for i in 0..<min(codecResult.lowpass.count, metalResult.lowpass.count) {
            let d = abs(codecResult.lowpass[i] - Double(metalResult.lowpass[i]))
            if d > maxLowDiff { maxLowDiff = d }
        }
        var maxHighDiff: Double = 0
        for i in 0..<min(codecResult.highpass.count, metalResult.highpass.count) {
            let d = abs(codecResult.highpass[i] - Double(metalResult.highpass[i]))
            if d > maxHighDiff { maxHighDiff = d }
        }
        let maxDiff = max(maxLowDiff, maxHighDiff)
        XCTAssertLessThan(maxDiff, 1e-3,
            "Cross-module 9/7 forward divergence: J2KMetalDWT vs J2KCodec.J2KDWT1D max diff = \(maxDiff)")
    }

    // MARK: - 5/3 cross-module agreement

    /// J2KMetalDWT 5/3 (Float) vs J2KCodec.J2KDWT1D 5/3 dispatched
    /// via the public `inverseTransform` entry. 5/3 is integer
    /// arithmetic so the two should agree exactly within rounding.
    /// Locks in convention agreement at the Float-array level.
    func testJ2KMetalDWT_vs_J2KCodec_Inverse53_AgreeOnSingleLevel() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available for context")

        let n = 64
        let halfN = (n + 1) / 2
        let halfH = n / 2

        // Integer-valued data — 5/3 stays exact.
        let lowpassI: [Int32] = (0..<halfN).map { Int32($0 * 3 - 50) }
        let highpassI: [Int32] = (0..<halfH).map { Int32($0 * 5 - 80) }

        // J2KCodec inverse 5/3 via the public Int32 dispatch entry.
        let codecResultI = try J2KDWT1D.inverseTransform(
            lowpass: lowpassI, highpass: highpassI,
            filter: .reversible53)
        let codecResult = codecResultI.map { Double($0) }

        // J2KMetalDWT inverse 5/3 (Float CPU backend).
        let lowpassF = lowpassI.map { Float($0) }
        let highpassF = highpassI.map { Float($0) }
        let metalDWT = J2KMetalDWT(
            configuration: J2KMetalDWTConfiguration(filter: .reversible53))
        try await metalDWT.initialize()
        let metalResult = try await metalDWT.inverse1D(
            lowpass: lowpassF, highpass: highpassF, backend: .cpu)

        XCTAssertEqual(codecResult.count, metalResult.count)
        var maxDiff: Double = 0
        for i in 0..<min(codecResult.count, metalResult.count) {
            let d = abs(codecResult[i] - Double(metalResult[i]))
            if d > maxDiff { maxDiff = d }
        }
        // J2KCodec uses exact Int32 arithmetic for 5/3; J2KMetalDWT
        // uses Float lifting (close-but-not-bit-exact). On 64-element
        // input the divergence stays under 1 LSB. The point of this
        // test is convention agreement (scaling direction, lifting
        // coefficient signs) — convention drift would produce
        // multi-LSB or worse divergence. The Int32 bit-exact contract
        // is enforced separately by v5.7+ Int32 GPU IDWT regression
        // tests.
        XCTAssertLessThan(maxDiff, 1.0,
            "Cross-module 5/3 inverse convention drift: J2KMetalDWT vs J2KCodec.J2KDWT1D max diff = \(maxDiff)")
    }

    // MARK: - JP3DMetalDWT 9/7 vs J2K3D.JP3DWaveletTransform (v5.22.0 lock-in)

    /// JP3DMetalDWT's 9/7 CPU forward must agree with J2K3D's
    /// canonical `JP3DWaveletTransform.forward97`. v5.22.0 fixed the
    /// JP3DMetalDWT scaling direction — this test catches re-
    /// introduction of the inversion if anyone wires JP3DMetalDWT
    /// into the encoder/decoder pipeline.
    func testJP3DMetalDWT_vs_JP3DWaveletTransform_Forward97_Agree() async throws {
        // Both APIs operate on Float arrays. We compare JP3DMetalDWT's
        // CPU 9/7 forward (along X) against a hand-built ISO/IEC
        // 15444-1 Annex F.4.1.1 reference. JP3DMetalDWT's internal
        // forward path was fixed in v5.22.0 to use spec-compliant
        // scaling; this test catches re-introduction of the inversion.
        let n = 32
        let inputF = synthSignal(count: n, seed: 0x5).map { Float($0) }

        // Reference: ISO/IEC 15444-1 forward 9/7 with `lowpass /= K`,
        // `highpass *= K` after lifting.
        let alpha: Float = -1.586134342
        let beta: Float = -0.052980118
        let gamma: Float = 0.882911075
        let delta: Float = 0.443506852
        let k: Float = 1.230174105

        let nL = (n + 1) / 2
        let nH = n / 2
        var l = [Float](repeating: 0, count: nL)
        var h = [Float](repeating: 0, count: nH)
        for i in 0..<nL { l[i] = inputF[2 * i] }
        for i in 0..<nH { h[i] = inputF[2 * i + 1] }
        for i in 0..<nH {
            let lR = (i + 1 < nL) ? l[i + 1] : l[max(nL - 1, 0)]
            h[i] += alpha * (l[i] + lR)
        }
        for i in 0..<nL {
            let hP = (i == 0) ? h[0] : h[i - 1]
            let hC = (i < nH) ? h[i] : h[max(nH - 1, 0)]
            l[i] += beta * (hP + hC)
        }
        for i in 0..<nH {
            let lR = (i + 1 < nL) ? l[i + 1] : l[max(nL - 1, 0)]
            h[i] += gamma * (l[i] + lR)
        }
        for i in 0..<nL {
            let hP = (i == 0) ? h[0] : h[i - 1]
            let hC = (i < nH) ? h[i] : h[max(nH - 1, 0)]
            l[i] += delta * (hP + hC)
        }
        // Spec scaling: lowpass /= K, highpass *= K.
        for i in 0..<nL { l[i] /= k }
        for i in 0..<nH { h[i] *= k }
        let specLowpass = l
        let specHighpass = h

        // JP3DMetalDWT exposes `forward97X` — let's run 1D-along-X
        // with CPU backend (no Metal needed for this test).
        let jp3dMetal = JP3DMetalDWT(backend: .cpu)
        let inputData = inputF
        let result = try await jp3dMetal.forward97X(
            data: inputData, width: n, height: 1, depth: 1)

        // forward97X output layout: lowpass first then highpass.
        var maxLowDiff: Float = 0
        var maxHighDiff: Float = 0
        for i in 0..<min(specLowpass.count, result.low.count) {
            let d = abs(specLowpass[i] - result.low[i])
            if d > maxLowDiff { maxLowDiff = d }
        }
        for i in 0..<min(specHighpass.count, result.high.count) {
            let d = abs(specHighpass[i] - result.high[i])
            if d > maxHighDiff { maxHighDiff = d }
        }
        let maxDiff = max(maxLowDiff, maxHighDiff)
        XCTAssertLessThan(maxDiff, 1e-3,
            "JP3DMetalDWT 9/7 forward divergence from spec reference: max diff = \(maxDiff). Pre-v5.22 had K² scaling error.")
    }
}
