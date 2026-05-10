// V8_8_GCDvsTaskGroupPhase0Bench.swift
//
// v8.8 Phase 0 — measure the dispatch-overhead lever in the
// forward 2D 5/3 DWT column pass. v8.7 identified that the
// 18.78 ms DX single-level wall is dominated NOT by inner lifting
// (0.37 ns/sample, ~6 ms acc CPU) NOR by transpose (0.07 ns/cell,
// 0.4% of stage), but by per-strip TaskGroup dispatch + the
// 25 MB srcBuf / dstBuf intermediate copies + multi-tile
// coordination.
//
// `forward2D_53Pooled` uses `await withTaskGroup` with one task
// per column-strip — for DX 2800x2288 with stripWidth=8 that's
// ~350 tasks per L0 column pass. Each Swift `Task` allocation
// pays ~1-2 µs of structured-concurrency overhead for the @Sendable
// closure, parent-task linkage, and async/await suspension
// boundaries. 350 × 2 µs = ~700 µs minimum dispatch overhead, before
// any actual lifting work.
//
// Apple's `DispatchQueue.concurrentPerform` runs over the same
// pthread_workqueue under libdispatch but skips the structured-
// concurrency tracking and async boundary crossings. Phase 0 asks:
// is the per-task overhead delta meaningful at DX scale?
//
// Decision rule:
//   - If TaskGroup → concurrentPerform delta ≥ 3 ms wall on a
//     DX-shaped synthetic workload, proceed to Phase 1A prototype
//     in production code.
//   - If < 3 ms, document projected wash and close.

#if os(macOS)

import XCTest
import Foundation
@testable import J2KCodec

final class V8_8_GCDvsTaskGroupPhase0Bench: XCTestCase {

    /// Synthetic per-strip workload that mimics the forward-DWT
    /// column-pass's actual shape: small CPU-bounded work (transpose-
    /// in + lift + transpose-out at one strip's worth of cells), with
    /// no shared mutable state across strips.
    @inline(never)
    static func stripWork(_ stripIdx: Int, height: Int) -> Int32 {
        // Mimic ~10 µs of work: scalar lifting on a strip-sized buffer.
        var acc: Int32 = Int32(stripIdx)
        // ~stripWidth * height = 8 * 2288 = 18304 ops per strip
        let n = 8 * height
        for i in 0..<n {
            acc = acc &+ Int32(truncatingIfNeeded: i &* 7919)
            acc = acc ^ (acc &<< 3)
        }
        return acc
    }

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    /// Bench `withTaskGroup` dispatching N strips. This is the shape
    /// of the production `forward2D_53Pooled` column pass.
    private func benchTaskGroup(numStrips: Int, height: Int, runs: Int) async -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            await withTaskGroup(of: Int32.self) { group in
                for stripIdx in 0..<numStrips {
                    group.addTask { @Sendable in
                        Self.stripWork(stripIdx, height: height)
                    }
                }
                var sink: Int32 = 0
                for await v in group {
                    sink = sink &+ v
                }
                XCTAssertNotEqual(sink, Int32.max - 1)
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / 1_000_000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    /// Bench `DispatchQueue.concurrentPerform` over the same N strips.
    private func benchConcurrentPerform(numStrips: Int, height: Int, runs: Int) -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            // Per-strip output array to avoid contention; reduce after.
            let outputs = UnsafeMutablePointer<Int32>.allocate(capacity: numStrips)
            outputs.initialize(repeating: 0, count: numStrips)
            defer {
                outputs.deinitialize(count: numStrips)
                outputs.deallocate()
            }
            let t0 = DispatchTime.now()
            DispatchQueue.concurrentPerform(iterations: numStrips) { stripIdx in
                outputs[stripIdx] = Self.stripWork(stripIdx, height: height)
            }
            var sink: Int32 = 0
            for i in 0..<numStrips {
                sink = sink &+ outputs[i]
            }
            XCTAssertNotEqual(sink, Int32.max - 1)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / 1_000_000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    /// Headline A/B: 350-strip workload (DX L0 column pass shape).
    func testTaskGroup_vs_ConcurrentPerform_DX_Shape() async {
        let height = 2288
        let runs = 7

        // Warm-up.
        _ = await benchTaskGroup(numStrips: 350, height: height, runs: 1)
        _ = benchConcurrentPerform(numStrips: 350, height: height, runs: 1)

        errlog("")
        errlog("=== v8.8 Phase 0 — dispatch overhead A/B at DX strip count ===")
        errlog("Workload: 350 strips × \(8 * height) scalar ops/strip (~10 µs/strip).")
        errlog("Apple M2, release-mode. \(runs) runs, median.")
        errlog("")
        errlog("  N strips | TaskGroup ms | concurrentPerform ms | Δ ms     | %")
        errlog("  ---------+--------------+----------------------+----------+------")

        var aggregateDeltaMs: Double = 0.0
        for nStrips in [10, 50, 100, 350, 700] {
            let tg = await benchTaskGroup(numStrips: nStrips, height: height, runs: runs)
            let cp = benchConcurrentPerform(numStrips: nStrips, height: height, runs: runs)
            let delta = tg - cp
            let pct = (delta / tg) * 100.0
            errlog(String(format: "  %-8d | %12.3f | %20.3f | %+8.3f | %+5.1f%%", nStrips, tg, cp, delta, pct))
            if nStrips == 350 {
                aggregateDeltaMs = delta
            }
        }
        errlog("")

        // Project to DX 5-level pyramid. Each level does 1 column pass
        // (parallel) + 1 row pass (sequential default). The column pass
        // has ~350 strips at L0, halving each level → ~466 strips total
        // across the pyramid. Multi-tile auto = 4 tiles → ~1864 strips
        // total per encode.
        // Conservatively: 1 forward2D call per tile per level = 5 levels
        // × 4 tiles = 20 calls; each call has ~strips proportional to
        // tile width / 8.
        // Simpler proxy: total dispatch savings = aggregate Δ × pyramid factor.
        let pyramidFactor = 1.332  // L0 + L1/4 + L2/16 + L3/64 + L4/256
        let multiTileFactor = 4.0  // DX runs as 2x2 multi-tile
        let dxCallSavingsMs = aggregateDeltaMs * pyramidFactor * multiTileFactor

        errlog("Projection to DX 2800x2288 forward 2D 5/3 (5-level, 4 tiles):")
        errlog("  per-call savings @ 350 strips:   \(String(format: "%6.3f", aggregateDeltaMs)) ms wall")
        errlog("  pyramid factor:                  \(String(format: "%5.3f", pyramidFactor))")
        errlog("  multi-tile factor (2x2 auto):    \(String(format: "%5.3f", multiTileFactor))")
        errlog("  estimated total wall savings:    \(String(format: "%6.3f", dxCallSavingsMs)) ms")
        errlog("")
        if dxCallSavingsMs >= 3.0 {
            errlog("  ⇒ ≥ 3 ms threshold MET. Phase 1A justified.")
        } else {
            errlog("  ⇒ < 3 ms threshold. Wash; close.")
        }
    }
}

#endif
