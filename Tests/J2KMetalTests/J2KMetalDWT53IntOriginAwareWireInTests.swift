//
// J2KMetalDWT53IntOriginAwareWireInTests.swift
//
// v7.1.0 H2.2 — wire-in tests for the parity-aware inverse 5/3
// integration. The H2 PR (#346) shipped the `j2k_dwt_inverse_53_*_int_odd`
// kernels with bit-exact tests against the CPU reference. This PR
// wires them into `J2KMetalDWT.inverse2DInt32(...)` via the new
// `tileOriginX` / `tileOriginY` fields on `J2KMetalDWTSubbandsInt32`.
//
// What these tests gate:
//   - **Origin (0, 0)**: backward-compat — existing kernels still
//     fire, output unchanged from pre-H2.2 behavior.
//   - **Origin (1, 1)**: both axes odd → both odd-origin kernels
//     fire on the GPU path; CPU backend uses the parity-aware
//     1D inverse. GPU == CPU.
//   - **Origin (1, 0) and (0, 1)**: mixed parity — only one axis's
//     odd-origin kernel fires; the other axis uses even-origin.
//     GPU == CPU at bit level.

import XCTest
@testable import J2KMetal
@testable import J2KCore

final class J2KMetalDWT53IntOriginAwareWireInTests: XCTestCase {

    // MARK: - Synthetic bands

    /// Generate deterministic pseudo-random LL/LH/HL/HH bands sized
    /// for an `originalWidth × originalHeight` reconstruction.
    private static func makeBands(
        originalWidth w: Int, originalHeight h: Int, seed: UInt32
    ) -> J2KMetalDWTSubbandsInt32 {
        let llW = (w + 1) / 2
        let llH = (h + 1) / 2
        let hlW = w / 2     // halfWH
        let hhH = h / 2     // halfHH
        var rng: UInt32 = seed

        @inline(__always) func next() -> Int32 {
            rng = rng &* 1_103_515_245 &+ 12_345
            return Int32(bitPattern: rng) >> 12
        }
        let ll = (0..<(llW * llH)).map { _ in next() }
        let hl = (0..<(hlW * llH)).map { _ in next() }
        let lh = (0..<(llW * hhH)).map { _ in next() }
        let hh = (0..<(hlW * hhH)).map { _ in next() }
        return J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: w, originalHeight: h)
    }

    private static func bandsWithOrigin(
        _ base: J2KMetalDWTSubbandsInt32, originX: Int, originY: Int
    ) -> J2KMetalDWTSubbandsInt32 {
        return J2KMetalDWTSubbandsInt32(
            ll: base.ll, lh: base.lh, hl: base.hl, hh: base.hh,
            llWidth: base.llWidth, llHeight: base.llHeight,
            originalWidth: base.originalWidth, originalHeight: base.originalHeight,
            tileOriginX: originX, tileOriginY: originY)
    }

    // MARK: - GPU vs CPU at each parity combination

    private func runGPUvsCPU(width: Int, height: Int,
                             originX: Int, originY: Int,
                             seed: UInt32 = 0xCAFE_F00D,
                             file: StaticString = #filePath,
                             line: UInt = #line) async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let base = Self.makeBands(originalWidth: width, originalHeight: height, seed: seed)
        let bands = Self.bandsWithOrigin(base, originX: originX, originY: originY)
        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.inverse2DInt32(subbands: bands, backend: .gpu)
        let cpu = try await dwt.inverse2DInt32(subbands: bands, backend: .cpu)
        XCTAssertEqual(gpu, cpu,
            "GPU vs CPU 2D inverse mismatch at origin (\(originX), \(originY)) " +
            "with \(width)×\(height) (seed=\(String(seed, radix: 16)))",
            file: file, line: line)
    }

    /// Origin (0, 0) — backward compat. Existing kernels fire on
    /// both axes; this test exists to pin "no behavior change for
    /// the historical default".
    func testOrigin_0_0_GPUvsCPU_BackwardCompat() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 0, originY: 0)
    }

    /// Origin (1, 1) — both axes odd. Both odd-origin kernels fire
    /// on GPU; both odd-origin 1D fire on CPU.
    func testOrigin_1_1_BothAxesOdd_GPUvsCPU() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 1, originY: 1)
    }

    /// Origin (1, 0) — only horizontal axis odd. Tests that vertical
    /// kernel selection is independent of horizontal.
    func testOrigin_1_0_HorizontalOddOnly_GPUvsCPU() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 1, originY: 0)
    }

    /// Origin (0, 1) — only vertical axis odd. Tests that horizontal
    /// kernel selection is independent of vertical.
    func testOrigin_0_1_VerticalOddOnly_GPUvsCPU() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 0, originY: 1)
    }

    /// Larger / non-square origins (3, 5) — odd parity on both axes
    /// with different magnitudes (>1) to confirm the kernel only
    /// looks at the parity bit, not the magnitude.
    func testOrigin_3_5_ParityOnly_GPUvsCPU() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 3, originY: 5)
    }

    /// Even-but-non-zero origin (4, 4) — should match even-origin
    /// fast path exactly, since parity is what matters.
    func testOrigin_4_4_EvenButNonZero_GPUvsCPU() async throws {
        try await runGPUvsCPU(width: 64, height: 64, originX: 4, originY: 4)
    }

    // MARK: - Dimension sweep at odd-origin

    func testDimensionSweep_OriginOdd_GPUvsCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        // Restricted to **even** widths/heights only. For even n,
        // floor(n/2) == ceil(n/2), so the LL vs HL band sizes are
        // parity-invariant. Odd n flips the band sizes between
        // even-origin and odd-origin per ISO 15444-1 Eq. B-15;
        // band-size handling for that case is covered by the
        // kernel-level `J2KMetalDWT53IntOddOriginBitExactTests`
        // (PR #346) which sizes bands per parity directly.
        for (w, h, seed) in [
            (8, 8,   UInt32(0xA1B2_C3D4)),
            (16, 16, UInt32(0xCAFE_F00D)),
            (16, 32, UInt32(0x0123_4567)),
            (32, 16, UInt32(0xDEAD_BEEF)),
            (32, 32, UInt32(0x1234_5678)),
            (64, 64, UInt32(0xFEED_F00D)),
        ] {
            try await runGPUvsCPU(width: w, height: h,
                                  originX: 1, originY: 1, seed: seed)
        }
    }

    // MARK: - Backward-compat: origin defaults to (0, 0)

    /// Two `J2KMetalDWTSubbandsInt32` values that don't pass origins
    /// (defaults applied) must produce the same result as ones that
    /// explicitly pass (0, 0). Also verifies the H2.2 init keeps
    /// the field defaults wired.
    func testDefaultInit_NoOriginParam_MatchesExplicit_0_0() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let w = 32, h = 32
        let llW = (w + 1) / 2
        let llH = (h + 1) / 2
        let hlW = w / 2
        let hhH = h / 2
        var rng: UInt32 = 0xBADC_0DE0
        @inline(__always) func n() -> Int32 {
            rng = rng &* 1_103_515_245 &+ 12_345
            return Int32(bitPattern: rng) >> 12
        }
        let ll = (0..<(llW * llH)).map { _ in n() }
        let hl = (0..<(hlW * llH)).map { _ in n() }
        let lh = (0..<(llW * hhH)).map { _ in n() }
        let hh = (0..<(hlW * hhH)).map { _ in n() }

        let bandsImplicit = J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: w, originalHeight: h)
        let bandsExplicit = J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: w, originalHeight: h,
            tileOriginX: 0, tileOriginY: 0)
        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()
        let r1 = try await dwt.inverse2DInt32(subbands: bandsImplicit, backend: .gpu)
        let r2 = try await dwt.inverse2DInt32(subbands: bandsExplicit, backend: .gpu)
        XCTAssertEqual(r1, r2, "Default-init origin must match explicit (0, 0)")
    }
}
