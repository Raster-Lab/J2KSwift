// v10.3-research Phase 2-1 — Metal inverse 5/3 Int tiled microbench.
//
// A/B times `J2KMetalDWT.inverse2DInt32MultiLevelFused` with the
// `inverse53IntTiledEnabled` flag OFF (scalar production kernels)
// vs ON (new tiled kernels). Same synthetic Int32 input, 5
// decomposition levels, 1 component.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KMetal
@testable import J2KCore

final class V10_3_MetalIDWTInverse53TiledMicrobench: XCTestCase {

    private struct FixtureSpec {
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

    private struct Stats { let median: Double; let min: Double; let p99: Double }

    private static func bench(
        _ dwt: J2KMetalDWT,
        chain: [J2KMetalDWTSubbandsInt32],
        useTiled: Bool,
        warmups: Int,
        iterations: Int
    ) async throws -> Stats {
        let prev = J2KMetalDWT.inverse53IntTiledEnabled
        J2KMetalDWT.inverse53IntTiledEnabled = useTiled
        defer { J2KMetalDWT.inverse53IntTiledEnabled = prev }
        for _ in 0..<warmups {
            _ = try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
        }
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0)
        }
        samples.sort()
        return Stats(median: samples[samples.count / 2],
                     min: samples.first!,
                     p99: samples[Int(Double(samples.count - 1) * 0.99)])
    }

    func testPhase2_2_TiledMicrobench() async throws {
        let dwt = J2KMetalDWT()
        let fixtures: [FixtureSpec] = [
            .init(label: "MR-small 180²", width: 180,  height: 180,  levels: 5),
            .init(label: "CT 512²",       width: 512,  height: 512,  levels: 5),
            .init(label: "MR 886²",       width: 886,  height: 886,  levels: 5),
            .init(label: "XA 1024²",      width: 1024, height: 1024, levels: 5),
            .init(label: "PX 2459×1316",  width: 2459, height: 1316, levels: 5),
            .init(label: "PX 2793×1316",  width: 2793, height: 1316, levels: 5),
            .init(label: "DX 2800×2288",  width: 2800, height: 2288, levels: 5),
            .init(label: "DX 2544×3056",  width: 2544, height: 3056, levels: 5),
            .init(label: "MG 3520×4784",  width: 3520, height: 4784, levels: 5),
            .init(label: "MG 3521×4784",  width: 3521, height: 4784, levels: 5)
        ]

        struct Row {
            let label: String
            let pixels: Int
            let scalar: Stats
            let twod: Stats
            var speedup: Double { scalar.median / twod.median }
        }
        var rows: [Row] = []
        for spec in fixtures {
            let chain = Self.makeSubbandChain(
                width: spec.width, height: spec.height,
                levels: spec.levels, seed: 0xBADC0FFEE0DDF00D)
            let scalar = try await Self.bench(dwt, chain: chain, useTiled: false,
                                              warmups: 3, iterations: 9)
            let twod = try await Self.bench(dwt, chain: chain, useTiled: true,
                                            warmups: 3, iterations: 9)
            rows.append(Row(label: spec.label,
                            pixels: spec.width * spec.height,
                            scalar: scalar, twod: twod))
        }

        print("")
        print("=== V10_3_METAL_IDWT_2D_AB_BEGIN ===")
        print("J2KMetalDWT.inverse2DInt32MultiLevelFused: scalar (1 thread/row) vs 2D (1 thread/sample)")
        print("M2 release, 5 decomposition levels, warmups=3, iterations=9 median-of-9")
        print("")
        print("| Fixture | Pixels | Scalar ms | Tiled ms | Speedup | Δ ms |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2fx | %+.2f |",
                         r.label, r.pixels,
                         r.scalar.median, r.twod.median, r.speedup,
                         r.twod.median - r.scalar.median))
        }
        print("")
        // Phase 2-3-tiled gate: 2D ≥ 1.5× faster on at least one of DX/MG.
        let dxRow = rows.first { $0.label.contains("2544") }!
        let mgRow = rows.first { $0.label.contains("3520") }!
        print(String(format: "Phase 2-3-tiled gate (≥1.5x on DX or MG):"))
        print(String(format: "  DX 2544×3056 speedup: %.2fx", dxRow.speedup))
        print(String(format: "  MG 3520×4784 speedup: %.2fx", mgRow.speedup))
        if dxRow.speedup >= 1.5 || mgRow.speedup >= 1.5 {
            print("  Status: PASS — 2D layout clears Phase 2-3-tiled gate. Proceed to Phase 2-3.")
        } else if dxRow.speedup >= 1.2 || mgRow.speedup >= 1.2 {
            print("  Status: MARGINAL — modest win, may need threadgroup-memory tiling to clear gate.")
        } else {
            print("  Status: WASH — 2D layout alone insufficient. Investigate threadgroup memory.")
        }
        print("=== V10_3_METAL_IDWT_2D_AB_END ===")
        print("")

        for r in rows {
            XCTAssertGreaterThan(r.scalar.median, 0)
            XCTAssertGreaterThan(r.twod.median, 0)
        }
    }
}
#endif
