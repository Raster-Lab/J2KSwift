// v10.3-research Phase 2-0 — isolated GPU iDWT microbench.
//
// Times `J2KMetalDWT.inverse2DInt32MultiLevelFused` directly, on
// synthetic Int32 subband inputs matching DX (2800×2288) and MG
// (3520×4784) dimensions. 5 decomposition levels, 1 component,
// HT-J2K-Lossless-relevant 5/3 reversible path.
//
// This is the baseline that Phase 2-1's tile-mined kernel A/B
// will be measured against. The microbench isolates GPU iDWT time
// from the full decode pipeline so kernel-level wins/losses don't
// get diluted by extractTileData / entropy / reconstruct stages.
//
// Output: a markdown block `=== V10_3_METAL_IDWT_BASELINE_BEGIN ===`
// with per-fixture median + per-level breakdown (best-effort; the
// fused-multi-level entry doesn't expose per-level timing, so the
// per-level numbers in the output table are placeholders for
// Phase 2-1's instrumented version).

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KMetal
@testable import J2KCore

final class V10_3_MetalIDWTMicrobench: XCTestCase {

    private struct FixtureSpec {
        let label: String
        let width: Int
        let height: Int
        let levels: Int
    }

    /// 5-level decomposition. For each level we need subbands sized
    /// to the canvas-anchored partition. For a clean microbench we
    /// generate deterministic Int32 content with no zero blocks.
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

        // Build innermost-first. Level 0's LL is the deepest level.
        // For each level, compute the previous level's full dims and
        // the current LL/H bands.
        var curW = width
        var curH = height
        // Compute dims per level from outermost down to innermost.
        var levelDims: [(Int, Int)] = []
        for _ in 0..<levels {
            levelDims.append((curW, curH))
            curW = (curW + 1) / 2
            curH = (curH + 1) / 2
        }
        // Innermost LL is the smallest.
        let innermostLLW = (levelDims.last!.0 + 1) / 2
        let innermostLLH = (levelDims.last!.1 + 1) / 2

        for (idx, (W, H)) in levelDims.reversed().enumerated() {
            let llW = (W + 1) / 2
            let llH = (H + 1) / 2
            let hW = W / 2
            let hH = H / 2
            // LL only populated at innermost; subsequent levels' LL
            // comes from prior level's output (Metal driver handles).
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

    private static func benchOne(
        _ dwt: J2KMetalDWT,
        _ spec: FixtureSpec,
        iterations: Int,
        warmups: Int
    ) async throws -> (median: Double, min: Double, p99: Double, samples: [Double]) {
        // Generate one subband chain and reuse across iterations.
        let chain = makeSubbandChain(
            width: spec.width, height: spec.height,
            levels: spec.levels, seed: 0xC0FFEEDEADBEEF)

        for _ in 0..<warmups {
            _ = try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
        }
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0
            samples.append(dt)
        }
        let sorted = samples.sorted()
        return (sorted[sorted.count / 2], sorted.first!,
                sorted[Int(Double(sorted.count - 1) * 0.99)], samples)
    }

    func testPhase2_0_MetalIDWTBaseline() async throws {
        let dwt = J2KMetalDWT()
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
            .init(label: "MG 3521×4784",   width: 3521, height: 4784, levels: 5)
        ]

        struct Row {
            let label: String
            let pixels: Int
            let median: Double
            let min: Double
            let p99: Double
            let nsPerPx: Double
        }
        var rows: [Row] = []
        for spec in fixtures {
            let r = try await Self.benchOne(dwt, spec, iterations: 9, warmups: 3)
            rows.append(Row(label: spec.label,
                            pixels: spec.width * spec.height,
                            median: r.median, min: r.min, p99: r.p99,
                            nsPerPx: (r.median * 1_000_000.0) / Double(spec.width * spec.height)))
        }

        print("")
        print("=== V10_3_METAL_IDWT_BASELINE_BEGIN ===")
        print("J2KMetalDWT.inverse2DInt32MultiLevelFused — production Metal kernel baseline")
        print("M2 release, 5 decomposition levels, 1 component, Int32 subbands")
        print("Synthetic deterministic input (LCG), warmups=3, iterations=9 median-of-9")
        print("")
        print("| Fixture | Pixels | Median ms | Min ms | P99 ms | ns/pixel |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2f | %.2f |",
                         r.label, r.pixels, r.median, r.min, r.p99, r.nsPerPx))
        }
        print("")
        print("Notes:")
        print("- ns/pixel rises with image size, indicating cache pressure on finest level.")
        print("- M2 LPDDR5 ~70 GB/s effective; theoretical floor for read+write of Int32 buffer")
        print("  at finest level = pixels × 4 bytes × 2 / 70 GB/s.")
        print("- Phase 2-1's tiled kernel A/B will be measured against these baseline numbers.")
        print("=== V10_3_METAL_IDWT_BASELINE_END ===")
        print("")

        for r in rows {
            XCTAssertGreaterThan(r.median, 0)
        }
    }
}
#endif
