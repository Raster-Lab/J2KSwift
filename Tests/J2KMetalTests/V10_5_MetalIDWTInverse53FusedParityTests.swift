// V10_5_MetalIDWTInverse53FusedParityTests.swift
//
// v10.5-research Phase 4 — bit-exact parity oracle for the fused
// H+V inverse 5/3 Int Metal kernel
// (`j2k_dwt_inverse_53_fused_int_tiled`) introduced in Phase 2-3.
//
// Compares scalar production path
// (`inverse53IntTiledEnabled = false`, no fused) against the new
// fused path (`inverse53IntFusedEnabled = true`). Bit-exact Int32
// output is the gate.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KMetal
@testable import J2KCore

final class V10_5_MetalIDWTInverse53FusedParityTests: XCTestCase {

    private struct SizeSpec {
        let label: String
        let width: Int
        let height: Int
        let levels: Int
    }

    private static func makeSubbandChain(
        width: Int, height: Int, levels: Int, seed: UInt64
    ) -> [J2KMetalDWTSubbandsInt32] {
        var subbands: [J2KMetalDWTSubbandsInt32] = []
        subbands.reserveCapacity(levels)
        var state = seed | 1
        @inline(__always) func nextI32() -> Int32 {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            return Int32(truncatingIfNeeded: (state >> 32) & 0x7FFF)
        }
        var levelDims: [(Int, Int)] = []
        var curW = width
        var curH = height
        for _ in 0..<levels {
            levelDims.append((curW, curH))
            curW = (curW + 1) / 2
            curH = (curH + 1) / 2
        }
        let innermostLLW = (levelDims.last!.0 + 1) / 2
        let innermostLLH = (levelDims.last!.1 + 1) / 2
        for (idx, (W, H)) in levelDims.reversed().enumerated() {
            let llW = (W + 1) / 2
            let llH = (H + 1) / 2
            let hW = W / 2
            let hH = H / 2
            let llCount = idx == 0 ? innermostLLW * innermostLLH : llW * llH
            var ll = [Int32](repeating: 0, count: max(llCount, 1))
            for i in 0..<ll.count { ll[i] = nextI32() }
            var lh = [Int32](repeating: 0, count: max(llW * hH, 1))
            for i in 0..<lh.count { lh[i] = nextI32() }
            var hl = [Int32](repeating: 0, count: max(hW * llH, 1))
            for i in 0..<hl.count { hl[i] = nextI32() }
            var hh = [Int32](repeating: 0, count: max(hW * hH, 1))
            for i in 0..<hh.count { hh[i] = nextI32() }
            subbands.append(J2KMetalDWTSubbandsInt32(
                ll: ll, lh: lh, hl: hl, hh: hh,
                llWidth: llW, llHeight: llH,
                originalWidth: W, originalHeight: H))
        }
        return subbands
    }

    private func runDecode(
        _ dwt: J2KMetalDWT,
        chain: [J2KMetalDWTSubbandsInt32],
        path: String
    ) async throws -> [Int32] {
        let prevTiled = J2KMetalDWT.inverse53IntTiledEnabled
        let prevFused = J2KMetalDWT.inverse53IntFusedEnabled
        defer {
            J2KMetalDWT.inverse53IntTiledEnabled = prevTiled
            J2KMetalDWT.inverse53IntFusedEnabled = prevFused
        }
        switch path {
        case "scalar":
            J2KMetalDWT.inverse53IntTiledEnabled = false
            J2KMetalDWT.inverse53IntFusedEnabled = false
        case "tiled":
            J2KMetalDWT.inverse53IntTiledEnabled = true
            J2KMetalDWT.inverse53IntFusedEnabled = false
        case "fused":
            J2KMetalDWT.inverse53IntTiledEnabled = false
            J2KMetalDWT.inverse53IntFusedEnabled = true
        default:
            fatalError("unknown path \(path)")
        }
        return try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
    }

    private func assertParity(
        spec: SizeSpec, seed: UInt64
    ) async throws {
        let dwt = J2KMetalDWT()
        let chain = Self.makeSubbandChain(
            width: spec.width, height: spec.height,
            levels: spec.levels, seed: seed)
        let scalar = try await runDecode(dwt, chain: chain, path: "scalar")
        let fused  = try await runDecode(dwt, chain: chain, path: "fused")
        XCTAssertEqual(scalar.count, fused.count,
                       "[\(spec.label)] output count mismatch (scalar=\(scalar.count) fused=\(fused.count))")
        if scalar != fused {
            var first = -1
            for i in 0..<min(scalar.count, fused.count) where scalar[i] != fused[i] {
                first = i; break
            }
            // Show context around first mismatch.
            let lo = max(0, first - 4)
            let hi = min(scalar.count, first + 4)
            var ctx = ""
            for i in lo..<hi {
                let mark = (i == first) ? "*" : " "
                ctx += "[\(i)\(mark)] s=\(scalar[i]) f=\(fused[i])  "
            }
            XCTFail("[\(spec.label)] fused diverges at idx \(first); \(ctx)")
        }
    }

    // MARK: - Tests

    func testFusedParity_smallSizes() async throws {
        let cases: [SizeSpec] = [
            .init(label: "8×8 lv1",    width: 8,   height: 8,   levels: 1),
            .init(label: "16×16 lv2",  width: 16,  height: 16,  levels: 2),
            .init(label: "32×32 lv3",  width: 32,  height: 32,  levels: 3),
            .init(label: "64×64 lv5",  width: 64,  height: 64,  levels: 5),
            .init(label: "128×128 lv5",width: 128, height: 128, levels: 5)
        ]
        for (i, c) in cases.enumerated() {
            try await assertParity(spec: c, seed: UInt64(i + 1) &* 0xABCDEF12)
        }
    }

    func testFusedParity_oddDimensions() async throws {
        let cases: [SizeSpec] = [
            .init(label: "9×9 lv2",      width: 9,   height: 9,   levels: 2),
            .init(label: "17×17 lv2",    width: 17,  height: 17,  levels: 2),
            .init(label: "33×33 lv3",    width: 33,  height: 33,  levels: 3),
            .init(label: "63×63 lv5",    width: 63,  height: 63,  levels: 5),
            .init(label: "127×127 lv5",  width: 127, height: 127, levels: 5),
            .init(label: "255×255 lv5",  width: 255, height: 255, levels: 5),
            .init(label: "180×180 lv5",  width: 180, height: 180, levels: 5),
            .init(label: "247×189 lv4",  width: 247, height: 189, levels: 4)
        ]
        for (i, c) in cases.enumerated() {
            try await assertParity(spec: c, seed: UInt64(i + 100) &* 0xDEADBEEF)
        }
    }

    func testFusedParity_medicalCorpusDimensions() async throws {
        let cases: [SizeSpec] = [
            .init(label: "CT 512²",       width: 512,  height: 512,  levels: 5),
            .init(label: "MR 886²",       width: 886,  height: 886,  levels: 5),
            .init(label: "XA 1024²",      width: 1024, height: 1024, levels: 5),
            .init(label: "PX 2459×1316",  width: 2459, height: 1316, levels: 5),
            .init(label: "PX 2793×1316",  width: 2793, height: 1316, levels: 5),
            .init(label: "DX 2800×2288",  width: 2800, height: 2288, levels: 5),
            .init(label: "DX 2544×3056",  width: 2544, height: 3056, levels: 5),
            .init(label: "MG 3520×4784",  width: 3520, height: 4784, levels: 5)
        ]
        for (i, c) in cases.enumerated() {
            try await assertParity(spec: c, seed: UInt64(i + 1000) &* 0xC0FFEE5DEAD)
        }
    }
}
#endif
