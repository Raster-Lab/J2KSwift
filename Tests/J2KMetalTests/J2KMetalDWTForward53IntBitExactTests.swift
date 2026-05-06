//
// J2KMetalDWTForward53IntBitExactTests.swift
// J2KSwift
//
// v6-alpha5 / lossless-only pivot — Phase 0.
//
// Verifies the new GPU integer forward 5/3 DWT path against the spec-
// equivalent CPU reference. Symmetric in scope to
// `J2KMetalDWT53IntBitExactTests` (which covered the inverse INT path).
//
// **Phase 0 goal**: prove the new
// `j2k_dwt_forward_53_horizontal_int` and
// `j2k_dwt_forward_53_vertical_int` kernels produce bit-identical
// output to the CPU forward 5/3 reference on representative
// medical-imaging signal sizes and bit depths. The kernels are NOT
// yet wired into the production encoder pipeline — that is phase 1
// work — so this test is the only consumer of the new public
// `J2KMetalDWT.forward2DInt32(image:width:height:backend:)` API.
//
// The mandatory commit-gate suite still runs against a forward-
// **CPU**-only encoder; nothing in this test changes encode bytes
// for any user.
//

import XCTest
@testable import J2KMetal
@testable import J2KCore

final class J2KMetalDWTForward53IntBitExactTests: XCTestCase {

    // MARK: - Locally-replicated CPU reference

    /// Bit-exact 1D forward 5/3 reference (predict then update with
    /// whole-sample symmetric mirror), matching
    /// `AcceleratedDWT2D.forward53_1D` in the J2KCodec module.
    private static func reference1DForward53(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
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

    /// 2D reference: vertical first, then horizontal. Matches the spec
    /// encoder order and the locally-defined `forward2DCPUInt32` inside
    /// `J2KMetalDWT`.
    private static func reference2DForward53(
        image: [Int32], width: Int, height: Int
    ) -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32], llW: Int, llH: Int) {
        let llW = (width  + 1) / 2
        let llH = (height + 1) / 2
        let halfWH = width  / 2
        let halfHH = height / 2

        var vLow  = [Int32](repeating: 0, count: width * llH)
        var vHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)
        for x in 0..<width {
            var col = [Int32](repeating: 0, count: height)
            for y in 0..<height { col[y] = image[y * width + x] }
            let (lp, hp) = reference1DForward53(signal: col)
            for y in 0..<llH    { vLow[y * width + x]  = lp[y] }
            for y in 0..<halfHH { vHigh[y * width + x] = hp[y] }
        }

        var ll = [Int32](repeating: 0, count: llW * llH)
        var hl = [Int32](repeating: 0, count: max(halfWH, 1) * llH)
        var lh = [Int32](repeating: 0, count: llW * halfHH)
        var hh = [Int32](repeating: 0, count: max(halfWH, 1) * halfHH)
        for y in 0..<llH {
            let row = Array(vLow[(y * width)..<(y * width + width)])
            let (lp, hp) = reference1DForward53(signal: row)
            for x in 0..<llW    { ll[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hl[y * halfWH + x] = hp[x] }
        }
        for y in 0..<halfHH {
            let row = Array(vHigh[(y * width)..<(y * width + width)])
            let (lp, hp) = reference1DForward53(signal: row)
            for x in 0..<llW    { lh[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hh[y * halfWH + x] = hp[x] }
        }
        return (ll, lh, hl, hh, llW, llH)
    }

    private static func deterministic12BitImage(width: Int, height: Int, seed: UInt64) -> [Int32] {
        var state = seed | 1
        var data = [Int32](repeating: 0, count: width * height)
        for i in 0..<data.count {
            state = state &* 2862933555777941757 &+ 3037000493
            data[i] = Int32((state >> 32) & 0xFFF)
        }
        return data
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

    /// 12-bit 384×384 grayscale: GPU integer forward must equal the
    /// CPU spec reference exactly.
    func testForward2DInt32_12BitGrayscale_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 384, height = 384
        let image = Self.deterministic12BitImage(width: width, height: height, seed: 0xCAFE_BEEF)
        let expected = Self.reference2DForward53(image: image, width: width, height: height)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let gpuResult = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        XCTAssertEqual(gpuResult.ll, expected.ll, "GPU LL must equal CPU reference LL")
        XCTAssertEqual(gpuResult.lh, expected.lh, "GPU LH must equal CPU reference LH")
        XCTAssertEqual(gpuResult.hl, expected.hl, "GPU HL must equal CPU reference HL")
        XCTAssertEqual(gpuResult.hh, expected.hh, "GPU HH must equal CPU reference HH")
        XCTAssertEqual(gpuResult.llWidth, expected.llW)
        XCTAssertEqual(gpuResult.llHeight, expected.llH)

        let cpuResult = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .cpu)
        XCTAssertEqual(cpuResult.ll, expected.ll, "CPU LL must equal CPU reference LL")
        XCTAssertEqual(cpuResult.lh, expected.lh, "CPU LH must equal CPU reference LH")
        XCTAssertEqual(cpuResult.hl, expected.hl, "CPU HL must equal CPU reference HL")
        XCTAssertEqual(cpuResult.hh, expected.hh, "CPU HH must equal CPU reference HH")
    }

    /// 16-bit 256×256 high-bit-depth: this exercises the same edge
    /// cases (signed Int32 carry, near-overflow) that motivated the
    /// integer inverse path on the decode side.
    func testForward2DInt32_16BitGrayscale_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 256, height = 256
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xDEAD_BEEF)
        let expected = Self.reference2DForward53(image: image, width: width, height: height)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let gpuResult = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        XCTAssertEqual(gpuResult.ll, expected.ll, "GPU LL must equal CPU reference LL")
        XCTAssertEqual(gpuResult.lh, expected.lh, "GPU LH must equal CPU reference LH")
        XCTAssertEqual(gpuResult.hl, expected.hl, "GPU HL must equal CPU reference HL")
        XCTAssertEqual(gpuResult.hh, expected.hh, "GPU HH must equal CPU reference HH")
    }

    /// Odd-dimension 99×97 — exercises the n-odd boundary on both
    /// axes (predict bulk runs all of highCount; update tail is the
    /// right-mirror case where halfWidth > halfWidthH).
    func testForward2DInt32_OddDimensions_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 99, height = 97
        let image = Self.deterministic12BitImage(width: width, height: height, seed: 0xBAD_F00D)
        let expected = Self.reference2DForward53(image: image, width: width, height: height)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let gpuResult = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        XCTAssertEqual(gpuResult.ll, expected.ll)
        XCTAssertEqual(gpuResult.lh, expected.lh)
        XCTAssertEqual(gpuResult.hl, expected.hl)
        XCTAssertEqual(gpuResult.hh, expected.hh)
        XCTAssertEqual(gpuResult.llWidth,  (width  + 1) / 2)
        XCTAssertEqual(gpuResult.llHeight, (height + 1) / 2)
    }

    /// GPU forward → existing GPU inverse must roundtrip bit-exactly
    /// to the input image. Closes the round-trip loop on the new
    /// kernels via the already-verified inverse INT path.
    func testForward2DInt32_GPUForwardThenGPUInverse_RoundtripsExactly() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 320, height = 240
        let image = Self.deterministic16BitImage(width: width, height: height, seed: 0xF00D_BABE)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let subbands = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        let recovered = try await dwt.inverse2DInt32(subbands: subbands, backend: .gpu)
        XCTAssertEqual(recovered, image,
            "GPU forward → GPU inverse must roundtrip bit-exactly")
    }

    // MARK: - Phase 1 — Multi-Level Fused Forward

    /// Multi-level CPU reference — loops `reference2DForward53` per
    /// level using the previous level's LL as the next level's input.
    /// Mirrors `AcceleratedDWT2D.forwardDecomposition53(data:width:height:levels:)`
    /// in the J2KCodec module, locally duplicated here.
    private static func referenceMultiLevelForward53(
        image: [Int32], width: Int, height: Int, levels: Int
    ) -> (perLevel: [(ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32], llW: Int, llH: Int)],
          coarsestLL: [Int32], llW: Int, llH: Int) {
        var current = image
        var w = width
        var h = height
        var perLevel: [(ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32], llW: Int, llH: Int)] = []
        for _ in 0..<levels {
            guard w >= 2, h >= 2 else { break }
            let r = reference2DForward53(image: current, width: w, height: h)
            perLevel.append(r)
            current = r.ll
            w = r.llW
            h = r.llH
        }
        return (perLevel, current, w, h)
    }

    /// 5-level forward on a 700×572 tile (matches DX 4×4 multi-tile
    /// per-tile dimensions): every level's LH / HL / HH and the
    /// coarsest LL must match the CPU reference exactly.
    func testForward2DInt32MultiLevelFused_DX4x4Tile_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 700, height = 572   // DX 2800×2288 / 4×4 = 700×572 per tile
        let levels = 5
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0x5A1A_F0_0D)

        let cpu = Self.referenceMultiLevelForward53(
            image: image, width: width, height: height, levels: levels)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels)

        XCTAssertEqual(gpu.count, cpu.perLevel.count,
            "Number of levels must match")
        for (i, (gpuLevel, cpuLevel)) in zip(gpu, cpu.perLevel).enumerated() {
            XCTAssertEqual(gpuLevel.lh, cpuLevel.lh,
                "Level \(i) LH must equal CPU reference")
            XCTAssertEqual(gpuLevel.hl, cpuLevel.hl,
                "Level \(i) HL must equal CPU reference")
            XCTAssertEqual(gpuLevel.hh, cpuLevel.hh,
                "Level \(i) HH must equal CPU reference")
            XCTAssertEqual(gpuLevel.ll, cpuLevel.ll,
                "Level \(i) LL must equal CPU reference (which is the next level's input)")
            XCTAssertEqual(gpuLevel.llWidth, cpuLevel.llW)
            XCTAssertEqual(gpuLevel.llHeight, cpuLevel.llH)
        }
        // The last level's LL is the coarsest approximation.
        XCTAssertEqual(gpu.last?.ll, cpu.coarsestLL,
            "Coarsest LL must equal CPU reference final approximation")
    }

    /// 5-level forward on a 1400×1144 tile (matches DX 2×2 per-tile
    /// dimensions). Same bit-exactness contract.
    func testForward2DInt32MultiLevelFused_DX2x2Tile_BitExactGPUMatchesCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 1400, height = 1144
        let levels = 5
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0x9A1A_BEEF)

        let cpu = Self.referenceMultiLevelForward53(
            image: image, width: width, height: height, levels: levels)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let gpu = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: levels)

        XCTAssertEqual(gpu.count, cpu.perLevel.count)
        for (i, (gpuLevel, cpuLevel)) in zip(gpu, cpu.perLevel).enumerated() {
            XCTAssertEqual(gpuLevel.lh, cpuLevel.lh, "Level \(i) LH")
            XCTAssertEqual(gpuLevel.hl, cpuLevel.hl, "Level \(i) HL")
            XCTAssertEqual(gpuLevel.hh, cpuLevel.hh, "Level \(i) HH")
            XCTAssertEqual(gpuLevel.ll, cpuLevel.ll, "Level \(i) LL")
        }
        XCTAssertEqual(gpu.last?.ll, cpu.coarsestLL)
    }

    /// 1-level edge case — multi-level fused with `levels = 1` must
    /// produce the same single-level output as the non-fused entry
    /// point.
    func testForward2DInt32MultiLevelFused_OneLevel_MatchesNonFused() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let width = 256, height = 256
        let image = Self.deterministic16BitImage(
            width: width, height: height, seed: 0xDEAD_BEEF)

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 1, gpuThreshold: 1
        ))
        try await dwt.initialize()

        let single = try await dwt.forward2DInt32(
            image: image, width: width, height: height, backend: .gpu)
        let fused = try await dwt.forward2DInt32MultiLevelFused(
            image: image, width: width, height: height, levels: 1)

        XCTAssertEqual(fused.count, 1)
        XCTAssertEqual(fused[0].ll, single.ll)
        XCTAssertEqual(fused[0].lh, single.lh)
        XCTAssertEqual(fused[0].hl, single.hl)
        XCTAssertEqual(fused[0].hh, single.hh)
    }

    // MARK: - Phase 1 — GPU-vs-CPU Forward Wall-Time Benchmark
    //
    // Diagnostic only — not a regression gate. Prints median-of-5
    // wall times for the multi-level fused GPU forward and the
    // locally-duplicated CPU reference at the per-tile sizes used by
    // multi-tile encoding (700×572 and 1400×1144 = DX 4×4 / 2×2),
    // so we can decide whether wiring into the encoder pipeline (the
    // phase-2 work) actually closes any of the +25 ms residual DX
    // wall gap step-12 measured.

    /// Diagnostic benchmark — gated on release build.
    func testForward2DInt32MultiLevelFused_WallTimeBenchmark() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Forward 5/3 INT GPU benchmark running in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter J2KMetalDWTForward53IntBitExactTests/testForward2DInt32MultiLevelFused_WallTimeBenchmark")
        #endif

        struct Bench {
            let label: String
            let width: Int
            let height: Int
        }
        let cases: [Bench] = [
            Bench(label: "MR 2×2 tile (443×443)",  width: 443,  height: 443),
            Bench(label: "DX 4×4 tile (700×572)",  width: 700,  height: 572),
            Bench(label: "DX 2×2 tile (1400×1144)", width: 1400, height: 1144),
        ]

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: 5, gpuThreshold: 1
        ))
        try await dwt.initialize()

        print("=== Phase 1 — GPU forward 5/3 INT vs CPU reference (median of 5, ms) ===")
        print("| Fixture | px | GPU fused | CPU ref | GPU/CPU× |")
        print("|---|---:|---:|---:|---:|")

        for c in cases {
            let image = Self.deterministic16BitImage(
                width: c.width, height: c.height, seed: 0xC0FF_EE42)

            // Warm-up (kernel pipelines + buffer pool).
            _ = try await dwt.forward2DInt32MultiLevelFused(
                image: image, width: c.width, height: c.height, levels: 5)

            var gpuTimes: [Double] = []
            for _ in 0..<5 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await dwt.forward2DInt32MultiLevelFused(
                    image: image, width: c.width, height: c.height, levels: 5)
                gpuTimes.append(
                    (Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            gpuTimes.sort()
            let gpuMedian = gpuTimes[2]

            var cpuTimes: [Double] = []
            for _ in 0..<5 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = Self.referenceMultiLevelForward53(
                    image: image, width: c.width, height: c.height, levels: 5)
                cpuTimes.append(
                    (Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuTimes.sort()
            let cpuMedian = cpuTimes[2]

            let pixels = c.width * c.height
            let ratio = cpuMedian / gpuMedian
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2f× |",
                c.label, pixels, gpuMedian, cpuMedian, ratio))
        }

        print("")
        print("Note: CPU reference here is the locally-duplicated scalar")
        print("loop, NOT the production `AcceleratedDWT2D.forward53_1D`")
        print("which is vDSP / parallel-strip optimised. The CPU column")
        print("over-estimates production CPU cost by ~3×; treat the GPU")
        print("column as the absolute deliverable for phase-2 encoder")
        print("wire-in decision.")
    }
}
