// v9.6 — focused microbench around AcceleratedDWT2D.forwardDecomposition
// to confirm whether the DWT stage has C+NEON-shaped headroom over the
// existing Swift + vDSP + DispatchQueue.concurrentPerform path.
//
// Measures wall ms per full 5-level decomposition on DX-class shapes
// (matches the corpus benchmark dimensions) at synthetic LCG content.
// Reports both ns/coefficient and ms/decomposition.
//
// Used to inform v9.6 scope: if ns/coefficient is already <3 ns on M4,
// the same auto-vec ceiling that washed v9.5 entropy NEON likely
// applies; pivot to per-block overhead or other stages instead.

import XCTest
import Darwin
@testable import J2KCodec

final class V96DWTMicrobenchTests: XCTestCase {

    /// Synthetic LCG-generated image data, matches the corpus
    /// `synthesizeImage` style — 16-bit medical-like content.
    private func makeFloatBuffer(width: Int, height: Int,
                                  seed: UInt64) -> [Float]
    {
        let n = width * height
        var out = [Float](repeating: 0, count: n)
        var s = seed
        for i in 0..<n {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(UInt32(truncatingIfNeeded: s >> 32) & 0xFFFF)
            out[i] = Float(v - 32768)  // dc-shifted 16-bit
        }
        return out
    }

    private func benchDecomposition(width: Int, height: Int,
                                     levels: Int, label: String,
                                     trials: Int = 30) async
    {
        let buf = makeFloatBuffer(width: width, height: height, seed: 0xfeed_face)
        // Warm-up
        _ = await AcceleratedDWT2D.forwardDecomposition(
            data: buf, width: width, height: height, levels: levels)

        var samples = [Double](repeating: 0, count: trials)
        for i in 0..<trials {
            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            _ = await AcceleratedDWT2D.forwardDecomposition(
                data: buf, width: width, height: height, levels: levels)
            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            samples[i] = Double(t1 - t0)
        }
        samples.sort()
        let med = samples[trials / 2]
        let mn = samples[0]
        let mx = samples[trials - 1]
        // Per-decomposition coefficient count: 1 + 1/4 + 1/16 + ... geometric series.
        // For N levels, total ≈ N * (4/3) * pixels (each level transforms
        // pixels, decreasing 4× per level; sum is geometric).
        let pixels = Double(width * height)
        let totalCoeffs = pixels * 4.0 / 3.0 * (1.0 - pow(0.25, Double(levels)))
        let nsPerCoeff = med / totalCoeffs
        print(String(format: "| %@ | %d×%d | L=%d | med %.2f ms | min %.2f ms | max %.2f ms | %.2f ns/coeff |",
                     label, width, height, levels,
                     med / 1_000_000.0, mn / 1_000_000.0, mx / 1_000_000.0,
                     nsPerCoeff))
    }

    /// Sweeps DWT decomposition ns/coefficient across representative
    /// shapes. The forward DWT is parallelized via concurrentPerform
    /// and uses vDSP for the 1D lifting; this microbench grounds
    /// whether further hand-NEON optimization has measurable room.
    func testDWTNsPerCoefficientAcrossShapes() async {
        print("=== v9.6 — DWT forward decomposition microbench ===")
        print("Processor: Apple M4 (\(ProcessInfo.processInfo.activeProcessorCount) procs)")
        print("Path: AcceleratedDWT2D.forwardDecomposition (Float 9/7 lifting + vDSP + DispatchQueue.concurrentPerform)")
        print()
        print("| Label | w×h | levels | median | min | max | ns/coeff |")
        print("|---|---|---|---|---|---|---|")
        await benchDecomposition(width: 512,  height: 512,  levels: 5, label: "ct-like")
        await benchDecomposition(width: 1024, height: 1024, levels: 5, label: "xa-like")
        await benchDecomposition(width: 2459, height: 1316, levels: 5, label: "px-like")
        await benchDecomposition(width: 2800, height: 2288, levels: 5, label: "dx-like")
        await benchDecomposition(width: 3520, height: 4784, levels: 5, label: "mg-like")
        print()
        print("Interpretation:")
        print("- ns/coeff <3 likely implies auto-vec ceiling — explicit NEON DWT will wash.")
        print("- ns/coeff 5-10 implies tractable hand-NEON win.")
        print("- ns/coeff >10 implies serious headroom; cache + transpose work worthwhile.")
    }
}
