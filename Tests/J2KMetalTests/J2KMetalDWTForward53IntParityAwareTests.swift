//
// J2KMetalDWTForward53IntParityAwareTests.swift
// J2KSwift
//
// v6-alpha5 / lossless-only pivot — Phase 4 slice 1.
//
// Verifies the new parity-aware GPU forward 5/3 INT path
// (`forward2DInt32(...tileOriginX:tileOriginY:)`) is bit-exact
// against the locally-replicated CPU reference at every
// combination of tile-component image-coord origin parity.
//
// Phase 0 / 1 / 2 / 3 covered the even-origin path. Phase 4
// extends the GPU forward to odd origins, mirroring the
// v6-alpha3-step-6B parity-aware decoder work on the encode side.
// Slice 1 lands the kernels + a single-level bit-exactness test;
// slice 2 adds multi-level fused with per-level Eq. B-15 origin
// tracking; slice 3 wires it into the encoder so multi-tile
// production encodes can route into the GPU forward path.
//

import XCTest
@testable import J2KMetal
@testable import J2KCore
@testable import J2KCodec

final class J2KMetalDWTForward53IntParityAwareTests: XCTestCase {

    // MARK: - Locally-duplicated CPU references

    /// Even-origin (or no-origin) forward 5/3 1D — bit-exact match
    /// for `AcceleratedDWT2D.forward53_1D(...workspace:)`.
    private static func reference1DForward53Even(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        let lpSize = (n + 1) / 2
        let hpSize = n / 2
        var lp = [Int32](repeating: 0, count: lpSize)
        var hp = [Int32](repeating: 0, count: hpSize)
        for i in 0..<hpSize {
            let left  = signal[2 * i]
            let right = (2 * i + 2 < n) ? signal[2 * i + 2] : signal[2 * i]
            hp[i] = signal[2 * i + 1] &- ((left &+ right) >> 1)
        }
        for i in 0..<lpSize {
            let left  = (i > 0) ? hp[i - 1] : (hpSize > 0 ? hp[0] : 0)
            let right = (i < hpSize) ? hp[i] : (hpSize > 0 ? hp[hpSize - 1] : 0)
            lp[i] = signal[2 * i] &+ ((left &+ right &+ 2) >> 2)
        }
        return (lp, hp)
    }

    /// Odd-origin forward 5/3 1D — bit-exact match for
    /// `AcceleratedDWT2D.forward53_1D(...uOrigin: <odd>)`.
    private static func reference1DForward53Odd(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        let lowCount  = n / 2
        let highCount = n - lowCount
        var lp = [Int32](repeating: 0, count: lowCount)
        var hp = [Int32](repeating: 0, count: highCount)
        for i in 0..<lowCount  { lp[i] = signal[2 * i + 1] }
        for i in 0..<highCount { hp[i] = signal[2 * i] }
        if highCount > 0 {
            hp[0] = hp[0] &- lp[0]
        }
        let predictInteriorEnd = min(highCount, lowCount)
        for i in 1..<predictInteriorEnd {
            hp[i] = hp[i] &- ((lp[i - 1] &+ lp[i]) >> 1)
        }
        if highCount > lowCount {
            hp[lowCount] = hp[lowCount] &- lp[lowCount - 1]
        }
        for i in 0..<lowCount {
            let leftH  = hp[i]
            let rightH = (i + 1 < highCount) ? hp[i + 1] : hp[highCount - 1]
            lp[i] = lp[i] &+ ((leftH &+ rightH &+ 2) >> 2)
        }
        return (lp, hp)
    }

    /// Parity-aware 2D reference. Vertical first then horizontal,
    /// each picking the even/odd 1D variant per axis.
    private static func reference2DForward53(
        image: [Int32], width: Int, height: Int, uX: Int, uY: Int
    ) -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32], llW: Int, llH: Int) {
        let llW = ((uX & 1) == 0) ? (width  + 1) / 2 : width  / 2
        let llH = ((uY & 1) == 0) ? (height + 1) / 2 : height / 2
        let halfWH = width  - llW
        let halfHH = height - llH

        let yOdd = (uY & 1) == 1
        let xOdd = (uX & 1) == 1

        var vLow  = [Int32](repeating: 0, count: width * llH)
        var vHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)
        for x in 0..<width {
            var col = [Int32](repeating: 0, count: height)
            for y in 0..<height { col[y] = image[y * width + x] }
            let r = yOdd ? reference1DForward53Odd(signal: col) : reference1DForward53Even(signal: col)
            for y in 0..<llH    { vLow[y * width + x]  = r.lowpass[y] }
            for y in 0..<halfHH { vHigh[y * width + x] = r.highpass[y] }
        }

        var ll = [Int32](repeating: 0, count: llW * llH)
        var hl = [Int32](repeating: 0, count: max(halfWH, 1) * llH)
        var lh = [Int32](repeating: 0, count: llW * halfHH)
        var hh = [Int32](repeating: 0, count: max(halfWH, 1) * halfHH)
        for y in 0..<llH {
            let row = Array(vLow[(y * width)..<(y * width + width)])
            let r = xOdd ? reference1DForward53Odd(signal: row) : reference1DForward53Even(signal: row)
            for x in 0..<llW    { ll[y * llW    + x] = r.lowpass[x] }
            for x in 0..<halfWH { hl[y * halfWH + x] = r.highpass[x] }
        }
        for y in 0..<halfHH {
            let row = Array(vHigh[(y * width)..<(y * width + width)])
            let r = xOdd ? reference1DForward53Odd(signal: row) : reference1DForward53Even(signal: row)
            for x in 0..<llW    { lh[y * llW    + x] = r.lowpass[x] }
            for x in 0..<halfWH { hh[y * halfWH + x] = r.highpass[x] }
        }
        return (ll, lh, hl, hh, llW, llH)
    }

    private static func deterministic16BitImage(width: Int, height: Int, seed: UInt64) -> [Int32] {
        var state = seed | 1
        var data = [Int32](repeating: 0, count: width * height)
        for i in 0..<data.count {
            state = state &* 2862933555777941757 &+ 3037000493
            data[i] = Int32((state >> 16) & 0xFFFF) - 32768
        }
        return data
    }

    // MARK: - Tests

    /// Even origins — must route to the existing fast path and
    /// produce byte-identical output to the no-origin overload.
    /// Regression guard for Phase 0 / 1 / 2 / 3.
    func testForward2DInt32_EvenEvenOrigin_RoutesToNoOriginFastPath() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 384, height = 384
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xCAFE_BEEF)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let noOrigin = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        let evenEven = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 0, tileOriginY: 0, backend: .gpu)
        XCTAssertEqual(evenEven.ll, noOrigin.ll)
        XCTAssertEqual(evenEven.lh, noOrigin.lh)
        XCTAssertEqual(evenEven.hl, noOrigin.hl)
        XCTAssertEqual(evenEven.hh, noOrigin.hh)
    }

    /// Odd uX, even uY — exercises the horizontal odd-origin kernel
    /// while vertical uses the existing even kernel. Tile-boundary
    /// case for MR 886×886 / 2×2 tile 1 origin (443, 0).
    func testForward2DInt32_OddX_EvenY_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 443, height = 444   // MR 2x2 right-edge tile, even-trimmed height
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xAA11)
        let expected = Self.reference2DForward53(
            image: image, width: width, height: height, uX: 1, uY: 0)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 1, tileOriginY: 0, backend: .gpu)
        XCTAssertEqual(gpu.ll, expected.ll, "LL bit-exact")
        XCTAssertEqual(gpu.lh, expected.lh, "LH bit-exact")
        XCTAssertEqual(gpu.hl, expected.hl, "HL bit-exact")
        XCTAssertEqual(gpu.hh, expected.hh, "HH bit-exact")
        XCTAssertEqual(gpu.llWidth,  expected.llW)
        XCTAssertEqual(gpu.llHeight, expected.llH)
    }

    /// Even uX, odd uY — exercises the vertical odd-origin kernel.
    /// Tile-boundary case: MR 886×886 / 2×2 tile 2 origin (0, 443).
    func testForward2DInt32_EvenX_OddY_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 444, height = 443
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xBB22)
        let expected = Self.reference2DForward53(
            image: image, width: width, height: height, uX: 0, uY: 1)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 0, tileOriginY: 1, backend: .gpu)
        XCTAssertEqual(gpu.ll, expected.ll)
        XCTAssertEqual(gpu.lh, expected.lh)
        XCTAssertEqual(gpu.hl, expected.hl)
        XCTAssertEqual(gpu.hh, expected.hh)
    }

    /// Both uX and uY odd — the maximum-flip case. Both kernels run
    /// in their odd variants. MR 886×886 / 2×2 tile 3 origin (443, 443).
    func testForward2DInt32_OddX_OddY_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 443, height = 443
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xCC33)
        let expected = Self.reference2DForward53(
            image: image, width: width, height: height, uX: 1, uY: 1)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 1, tileOriginY: 1, backend: .gpu)
        XCTAssertEqual(gpu.ll, expected.ll)
        XCTAssertEqual(gpu.lh, expected.lh)
        XCTAssertEqual(gpu.hl, expected.hl)
        XCTAssertEqual(gpu.hh, expected.hh)
    }

    /// CPU parity-aware path must match the GPU output too — both
    /// backends share the same locally-duplicated reference.
    func testForward2DInt32_OddX_OddY_CPUEqualsGPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 257, height = 259
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xDD44)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 7, tileOriginY: 9, backend: .gpu)
        let cpu = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 7, tileOriginY: 9, backend: .cpu)

        XCTAssertEqual(gpu.ll, cpu.ll)
        XCTAssertEqual(gpu.lh, cpu.lh)
        XCTAssertEqual(gpu.hl, cpu.hl)
        XCTAssertEqual(gpu.hh, cpu.hh)
    }

    // MARK: - Phase 4 slice 2 — multi-level fused parity-aware

    /// Multi-level forward at MR 2x2 tile-3 origin (443, 443) — every
    /// level alternates parity per Eq. B-15 (`(x + 1) >> 1`):
    ///   L0: 443 odd → odd kernels
    ///   L1: 222 even → even kernels
    ///   L2: 111 odd → odd
    ///   L3:  56 even → even
    ///   L4:  28 even → even
    /// Output bit-exact match against the production CPU reference
    /// `AcceleratedDWT2D.forwardDecomposition53(...tileOriginX:
    /// tileOriginY:)` — which the encoder pipeline already calls
    /// for multi-tile encodes per v6-alpha3 step 3.
    func testForward2DInt32MultiLevelFused_MR2x2Tile3Origin_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        // Use 444×444 (even-trimmed for clean MR 2×2 tile shape) with
        // origins 443, 443 → every recursion level has shifted parity.
        let width = 444, height = 444
        let levels = 5
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0xC0FE_BABE)

        // CPU reference via the production parity-aware multi-level
        // path used by the encoder.
        let cpu = await AcceleratedDWT2D.forwardDecomposition53(
            data: image, width: width, height: height, levels: levels,
            tileOriginX: 443, tileOriginY: 443)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels,
            tileOriginX: 443, tileOriginY: 443)

        XCTAssertEqual(gpu.count, cpu.levels.count,
            "Number of levels must match")
        for (i, (gpuL, cpuL)) in zip(gpu, cpu.levels).enumerated() {
            XCTAssertEqual(gpuL.lh, cpuL.lh, "Level \(i) LH must equal CPU reference")
            XCTAssertEqual(gpuL.hl, cpuL.hl, "Level \(i) HL must equal CPU reference")
            XCTAssertEqual(gpuL.hh, cpuL.hh, "Level \(i) HH must equal CPU reference")
        }
        XCTAssertEqual(gpu.last?.ll, cpu.coarsestLL,
            "Coarsest LL must equal CPU reference")
        XCTAssertEqual(gpu.last?.llWidth,  cpu.llW)
        XCTAssertEqual(gpu.last?.llHeight, cpu.llH)
    }

    /// Multi-level forward at PX 4x4 tile-5 origin (615, 329).
    /// Mixes axis parities differently than MR — exercises the
    /// asymmetric kernel selection per axis per level.
    func testForward2DInt32MultiLevelFused_PX4x4Tile5Origin_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 614, height = 329   // PX-style sub-tile
        let levels = 5
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0xCAFE_F00D)
        let uX = 615, uY = 329  // both odd at L0

        let cpu = await AcceleratedDWT2D.forwardDecomposition53(
            data: image, width: width, height: height, levels: levels,
            tileOriginX: uX, tileOriginY: uY)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 1))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels,
            tileOriginX: uX, tileOriginY: uY)

        XCTAssertEqual(gpu.count, cpu.levels.count)
        for (i, (gpuL, cpuL)) in zip(gpu, cpu.levels).enumerated() {
            XCTAssertEqual(gpuL.lh, cpuL.lh, "L\(i) LH")
            XCTAssertEqual(gpuL.hl, cpuL.hl, "L\(i) HL")
            XCTAssertEqual(gpuL.hh, cpuL.hh, "L\(i) HH")
        }
        XCTAssertEqual(gpu.last?.ll, cpu.coarsestLL)
    }

    /// Origin (0, 0) → must equal the no-origin multi-level fused
    /// output (regression guard). Every level stays at (0, 0) per
    /// Eq. B-15, every kernel stays the even variant.
    func testForward2DInt32MultiLevelFused_ZeroOrigin_MatchesNoOriginVariant() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 700, height = 572
        let levels = 5
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0xAA00_BB00)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 1))
        try await dwt.initialize()

        let noOrigin = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels)
        let zeroOrigin = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels,
            tileOriginX: 0, tileOriginY: 0)

        XCTAssertEqual(zeroOrigin.count, noOrigin.count)
        for (a, b) in zip(zeroOrigin, noOrigin) {
            XCTAssertEqual(a.ll, b.ll)
            XCTAssertEqual(a.lh, b.lh)
            XCTAssertEqual(a.hl, b.hl)
            XCTAssertEqual(a.hh, b.hh)
        }
    }

    /// Origin parity matters per-bit only — origin 1 and origin
    /// 33 must produce the same output (parity-aware path looks at
    /// `origin & 1`). MR-style boundary verification.
    func testForward2DInt32_OddOrigin_OnlyParityMatters() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 200, height = 200
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xEE55)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1))
        try await dwt.initialize()

        let one = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 1, tileOriginY: 1, backend: .gpu)
        let thirtyThree = try await dwt.forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 33, tileOriginY: 33, backend: .gpu)
        XCTAssertEqual(one.ll, thirtyThree.ll)
        XCTAssertEqual(one.lh, thirtyThree.lh)
        XCTAssertEqual(one.hl, thirtyThree.hl)
        XCTAssertEqual(one.hh, thirtyThree.hh)
    }
}
