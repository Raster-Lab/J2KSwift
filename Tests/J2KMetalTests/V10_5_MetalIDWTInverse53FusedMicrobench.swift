// V10_5_MetalIDWTInverse53FusedMicrobench.swift
//
// v10.5-research Phase 5 — microbench A/B for the fused H+V inverse
// 5/3 Int Metal kernel (v10.5 Phase 2-3) vs the v10.3 Phase 2-2-tiled
// pair. Same synthetic Int32 input, same 5-level multi-level fused
// driver path, only `inverse53IntTiledEnabled` and
// `inverse53IntFusedEnabled` flip between A and B.
//
// Run with:
//   swift test -c release --filter V10_5_MetalIDWTInverse53FusedMicrobench

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KMetal
@testable import J2KCore

final class V10_5_MetalIDWTInverse53FusedMicrobench: XCTestCase {

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
        path: String,
        warmups: Int,
        iterations: Int
    ) async throws -> Stats {
        let prevTiled = J2KMetalDWT.inverse53IntTiledEnabled
        let prevFused = J2KMetalDWT.inverse53IntFusedEnabled
        let prevThreshold = J2KMetalDWT.inverse53IntFusedPixelThreshold
        defer {
            J2KMetalDWT.inverse53IntTiledEnabled = prevTiled
            J2KMetalDWT.inverse53IntFusedEnabled = prevFused
            J2KMetalDWT.inverse53IntFusedPixelThreshold = prevThreshold
        }
        // Microbench lowers threshold to 0 so we measure the fused
        // path's raw cost across the full size sweep, including
        // sub-12 MP fixtures where production routes back to tiled.
        J2KMetalDWT.inverse53IntFusedPixelThreshold = 0
        switch path {
        case "tiled":
            J2KMetalDWT.inverse53IntTiledEnabled = true
            J2KMetalDWT.inverse53IntFusedEnabled = false
        case "fused":
            J2KMetalDWT.inverse53IntTiledEnabled = false
            J2KMetalDWT.inverse53IntFusedEnabled = true
        default:
            fatalError("unknown path \(path)")
        }
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
        let p99Idx = min(samples.count - 1, Int(Double(samples.count) * 0.99))
        return Stats(median: samples[samples.count / 2],
                     min: samples.first!,
                     p99: samples[p99Idx])
    }

    func testPhase2_3_FusedMicrobench() async throws {
        let fixtures: [FixtureSpec] = [
            .init(label: "MR-small 180²",  width: 180,  height: 180,  levels: 5),
            .init(label: "CT 512²",        width: 512,  height: 512,  levels: 5),
            .init(label: "MR 886²",        width: 886,  height: 886,  levels: 5),
            .init(label: "XA 1024²",       width: 1024, height: 1024, levels: 5),
            .init(label: "PX 2459×1316",   width: 2459, height: 1316, levels: 5),
            .init(label: "PX 2793×1316",   width: 2793, height: 1316, levels: 5),
            .init(label: "DX 2800×2288",   width: 2800, height: 2288, levels: 5),
            .init(label: "DX 2544×3056",   width: 2544, height: 3056, levels: 5),
            .init(label: "MG 3520×4784",   width: 3520, height: 4784, levels: 5),
            .init(label: "MG 3521×4784",   width: 3521, height: 4784, levels: 5),
        ]
        let dwt = J2KMetalDWT()
        let warmups = 2
        let iterations = 7

        print("=== V10_5_METAL_IDWT_FUSED_AB_BEGIN ===")
        print("J2KMetalDWT.inverse2DInt32MultiLevelFused: tiled (v10.3 Phase 2-2) vs fused (v10.5 Phase 2-3)")
        print("Processor: \(processorBrandString())")
        print("Warmups: \(warmups)  Iterations: \(iterations)")
        print("")
        print("| Fixture | Pixels | Tiled ms | Fused ms | Speedup | Δ ms |")
        print("|---|---:|---:|---:|---:|---:|")
        for fix in fixtures {
            let chain = Self.makeSubbandChain(
                width: fix.width, height: fix.height,
                levels: fix.levels, seed: 0xCAFEBABE)
            let tiled = try await Self.bench(dwt, chain: chain, path: "tiled",
                                              warmups: warmups, iterations: iterations)
            let fused = try await Self.bench(dwt, chain: chain, path: "fused",
                                              warmups: warmups, iterations: iterations)
            let speedup = tiled.median / fused.median
            let delta = fused.median - tiled.median
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2fx | %+.2f |",
                         fix.label, fix.width * fix.height,
                         tiled.median, fused.median, speedup, delta))
        }
        print("Phase 2-3-fused gate (≥3 ms wall lift on MG or DX vs tiled): see ms column above.")
        print("=== V10_5_METAL_IDWT_FUSED_AB_END ===")
    }
}
#endif
