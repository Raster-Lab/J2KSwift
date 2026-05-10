// V8_6_ForwardDWTPhase0Bench.swift
//
// v8.6 Phase 0 — characterise the production forward 5/3 1D DWT
// hot-path cost. The v8.4 stage breakdown showed DX 2800×2288
// encode wall is **DWT 53% + entropy 44% + ...**; the encoder
// hasn't been through the same lever-ceiling search arc as
// decode. This bench answers: is there a SIMD4-shaped lever in
// `forward53_1D` analogous to the v8 Phase 3 SIMD4 inverse 5/3
// IDWT?
//
// Pure measurement: no production-code change. Builds the data
// to project DX wall savings before implementing a SIMD4
// prototype.
//
// Decision rule:
//   - If projected DX wall savings ≥ 3 ms (per v7.4/v8.1
//     acceptance discipline), proceed to Phase 1A.
//   - Else, document projected wash and move to a different
//     encoder lever (entropy or codestream).

#if os(macOS)

import XCTest
@testable import J2KCodec

final class V8_6_ForwardDWTPhase0Bench: XCTestCase {

    func testSmoke_OneCall() {
        let n = 128
        var input = [Int32](repeating: 0, count: n)
        for i in 0..<n { input[i] = Int32(i &* 13) }
        var output = [Int32](repeating: 0, count: n)
        let workspace = AcceleratedDWT2D.DWTWorkspace53(maxSignalLength: n)
        input.withUnsafeBufferPointer { ip in
            output.withUnsafeMutableBufferPointer { op in
                AcceleratedDWT2D.forward53_1D(
                    ip.baseAddress!, op.baseAddress!,
                    count: n, workspace: workspace)
            }
        }
        print("[smoke] forward53 produced output[0]=\(output[0]) output[\(n-1)]=\(output[n-1])")
    }

    /// Per-sample ns for the production `forward53_1D` (workspace
    /// overload) at three DX-relevant signal lengths. Establishes
    /// whether the v5.38 M5 auto-vectorisable lifting loops achieve
    /// SIMD throughput, or if there's residual lever for explicit
    /// SIMD4. Output via stderr to bypass XCTest's stdout capture
    /// quirks; results render in `swift test` log under [phase0].
    func testForward53_PerSampleCost_LengthSweep() {
        @inline(never)
        func errlog(_ s: String) {
            FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
        }

        // Bench a single (n, iterations, runs) configuration.
        // Returns ns/call.
        @inline(never)
        func benchOne(n: Int, iterations: Int, runs: Int) -> Double {
            let ipBase = UnsafeMutablePointer<Int32>.allocate(capacity: n)
            let opBase = UnsafeMutablePointer<Int32>.allocate(capacity: n)
            defer {
                ipBase.deallocate()
                opBase.deallocate()
            }
            for i in 0..<n {
                let x = Int32(truncatingIfNeeded: i &* 7919) & 0xFFFF
                ipBase[i] = x - 32768
            }
            let workspace = AcceleratedDWT2D.DWTWorkspace53(maxSignalLength: n)
            // Warm-up.
            AcceleratedDWT2D.forward53_1D(
                UnsafePointer(ipBase), opBase,
                count: n, workspace: workspace)
            var samples: [Double] = []
            samples.reserveCapacity(runs)
            for _ in 0..<runs {
                let t0 = DispatchTime.now()
                for _ in 0..<iterations {
                    AcceleratedDWT2D.forward53_1D(
                        UnsafePointer(ipBase), opBase,
                        count: n, workspace: workspace)
                }
                let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
                samples.append(Double(dt) / Double(iterations))
            }
            samples.sort()
            return samples[runs / 2]
        }

        errlog("")
        errlog("=== v8.6 Phase 0 — production forward53_1D per-sample cost ===")
        errlog("Apple M2, release-mode. Workspace pre-allocated; pure inner loop.")
        errlog("")
        errlog("  n        | ns/call    | ns/sample | samples/ns")
        errlog("  ---------+------------+-----------+-----------")

        // Hold ns/sample at the largest size for projection.
        var nsPerSampleAtLargest: Double = 0
        let cases: [(n: Int, iters: Int, runs: Int)] = [
            (128, 1000, 3),
            (512, 500, 3),
            (2048, 200, 3),
        ]
        for c in cases {
            let nsCall = benchOne(n: c.n, iterations: c.iters, runs: c.runs)
            let nsSample = nsCall / Double(c.n)
            nsPerSampleAtLargest = nsSample
            let nsCallStr = String(format: "%10.1f", nsCall)
            let nsSampleStr = String(format: "%9.3f", nsSample)
            let throughputStr = String(format: "%9.2f", 1.0 / nsSample)
            errlog("  \(String(format: "%-8d", c.n)) | \(nsCallStr) | \(nsSampleStr) | \(throughputStr)")
        }

        errlog("")
        errlog("Memory-bandwidth context (M2 single-core):")
        errlog("  - Stream Int32 r+w peak: ~0.27 ns/sample")
        errlog("  - 2-3 pass lifting ceiling: ~1 ns/sample")
        if nsPerSampleAtLargest < 1.5 {
            errlog("  - => Already near memory-bound. SIMD4 lever LIKELY < 10%.")
        } else if nsPerSampleAtLargest < 3.0 {
            errlog("  - => Compute-bound but auto-vec is decent. SIMD4 lever ~10-20%.")
        } else {
            errlog("  - => Compute-bound, auto-vec headroom. SIMD4 lever >= 20% plausible.")
        }
        errlog("")

        // Project DX 2800x2288 encode wall (5-level pyramid):
        // Total samples processed by forward53 1D = sum over levels of
        //   (rows * cols + cols * rows) per level.
        // Approx: ~17 M sample-calls (each "sample" measured per 1D
        // call — we approximate via DX total pixels * 2 dimensions *
        // 4/3 series). For projection use the v8.4 stage breakdown's
        // measured 333 ms accumulated DWT CPU as the reality anchor.
        let dxAccDwtCpuMs = 333.0
        let parallelism = 12.3  // 333 acc / 27 wall = 12.3
        let dxDwtWallMs = dxAccDwtCpuMs / parallelism

        errlog("Projection to DX 2800x2288 encode (5-level forward DWT):")
        errlog("  v8.4 measured acc DWT CPU: 333 ms (constant — reality anchor)")
        errlog("  v8.4 measured DWT wall:    \(String(format: "%.1f", dxDwtWallMs)) ms")
        errlog("")
        errlog("Hypothetical lifts speedup -> wall savings:")
        let fractions: [(label: String, frac: Double)] = [
            ("10%", 0.10),
            ("15%", 0.15),
            ("20%", 0.20),
            ("30%", 0.30),
        ]
        for f in fractions {
            let accDelta = dxAccDwtCpuMs * f.frac
            let wallDelta = accDelta / parallelism
            let mark = wallDelta >= 3.0 ? "[MET]" : "[NO]"
            errlog("  \(f.label) lifts speedup => -\(String(format: "%5.1f", accDelta)) ms acc / -\(String(format: "%4.2f", wallDelta)) ms wall  \(mark)")
        }
        errlog("")
        errlog("Decision rule per v7.4/v8.1: >= 3 ms DX wall => Phase 1A justified.")
    }
}

#endif
