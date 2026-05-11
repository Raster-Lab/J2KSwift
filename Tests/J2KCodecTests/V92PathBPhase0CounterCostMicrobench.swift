// V92PathBPhase0CounterCostMicrobench.swift
//
// v9.2 Path B Phase 0a — measure the cost of the (now opt-in)
// J2KHTEntropyEncoderProfile counter instrumentation.
//
// **Hypothesis being tested**: the always-on Phase 0 instrumentation
// counters in J2KHTEntropyEncoderProfile contribute meaningfully to
// per-block wall (~10 K `&+=` operations per 64x64 block against a
// shared static), AND under concurrent encoders they cause cache-line
// invalidation across CPU cores, contributing to the 5× per-block
// inflation observed in V91Phase2ConcurrentContentionProbe.
//
// **Methodology**:
//   1. Single-thread A/B: encode the same block N times with counters
//      enabled vs disabled, compare ns/block.
//   2. Concurrent A/B: TaskGroup of W workers encoding N/W blocks each,
//      measure wall and parallel efficiency with/without counters.
//
// **Bit-exact**: the codestream is identical regardless of counters
// (counters only update statics; do not affect emit logic).

import XCTest
@testable import J2KCodec

final class V92PathBPhase0CounterCostMicrobench: XCTestCase {

    /// Same moderate-density block as V91Phase1BBlockEncodeMicrobench
    /// for direct comparability.
    private func moderateDensityBlock() -> [UInt32] {
        var block = [UInt32](repeating: 0, count: 64 * 64)
        var idx = 0
        while idx < 64 * 64 {
            block[idx] = (idx & 1 == 0) ? 0x0000_0080 : 0x8000_0080
            idx += 10
        }
        return block
    }

    /// Measure ns/block for a single thread across a tight loop.
    /// Returns the median of `runs` invocations.
    private func measureSingleThread(
        block: [UInt32],
        blocksPerRun: Int,
        runs: Int,
        countersEnabled: Bool
    ) -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            var magsgn = HTMagSgnEncoderConformant()
            var mel = HTMELEncoderConformant()
            var vlc = HTReverseBitEmitterConformant()
            J2KHTEntropyEncoderProfile.setEnabled(countersEnabled)
            J2KHTEntropyEncoderProfile.reset()

            let t0 = DispatchTime.now()
            block.withUnsafeBufferPointer { ptr in
                for _ in 0..<blocksPerRun {
                    _ = HTBlockEncoderConformant.encode(
                        coefficients: ptr,
                        width: 64, height: 64,
                        missingMSBs: 24,
                        magsgnEnc: &magsgn,
                        melEnc: &mel,
                        vlcEnc: &vlc,
                        useSIMDClassification: false,
                        preClassifiedTuples: nil)
                }
            }
            let dt = DispatchTime.now().uptimeNanoseconds
                  &- t0.uptimeNanoseconds
            samples.append(Double(dt) / Double(blocksPerRun))
        }
        // Always restore default (disabled) for subsequent tests.
        J2KHTEntropyEncoderProfile.setEnabled(false)
        samples.sort()
        return samples[runs / 2]
    }

    /// Measure ns/block across W concurrent workers (each encodes
    /// blocksPerWorker blocks back-to-back in its own task), reporting
    /// the wall divided by total blocks. Lower = better parallel scaling.
    private func measureConcurrent(
        block: [UInt32],
        blocksPerWorker: Int,
        workers: Int,
        runs: Int,
        countersEnabled: Bool
    ) async -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            J2KHTEntropyEncoderProfile.setEnabled(countersEnabled)
            J2KHTEntropyEncoderProfile.reset()
            let t0 = DispatchTime.now()
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<workers {
                    group.addTask {
                        var magsgn = HTMagSgnEncoderConformant()
                        var mel = HTMELEncoderConformant()
                        var vlc = HTReverseBitEmitterConformant()
                        block.withUnsafeBufferPointer { ptr in
                            for _ in 0..<blocksPerWorker {
                                _ = HTBlockEncoderConformant.encode(
                                    coefficients: ptr,
                                    width: 64, height: 64,
                                    missingMSBs: 24,
                                    magsgnEnc: &magsgn,
                                    melEnc: &mel,
                                    vlcEnc: &vlc,
                                    useSIMDClassification: false,
                                    preClassifiedTuples: nil)
                            }
                        }
                    }
                }
            }
            let dt = DispatchTime.now().uptimeNanoseconds
                  &- t0.uptimeNanoseconds
            let totalBlocks = workers * blocksPerWorker
            samples.append(Double(dt) / Double(totalBlocks))
        }
        J2KHTEntropyEncoderProfile.setEnabled(false)
        samples.sort()
        return samples[runs / 2]
    }

    /// Single-thread A/B: disabled-counters should be faster.
    func testSingleThreadCounterCost() throws {
        let block = moderateDensityBlock()
        let runs = 5
        let blocksPerRun = 5_000

        let disabledNs = measureSingleThread(
            block: block, blocksPerRun: blocksPerRun, runs: runs,
            countersEnabled: false)
        let enabledNs = measureSingleThread(
            block: block, blocksPerRun: blocksPerRun, runs: runs,
            countersEnabled: true)

        let speedup = enabledNs / disabledNs
        let savedPct = 100 * (enabledNs - disabledNs) / enabledNs

        print()
        print("=== v9.2 Path B Phase 0a — single-thread counter A/B ===")
        print()
        print("Moderate-density 64×64 block, missingMSBs=24,")
        print("\(blocksPerRun) blocks/run × median of \(runs).")
        print()
        print("| mode                |   ns/block   | ns/quad |")
        print("|---------------------|-------------:|--------:|")
        print(String(format: "| counters disabled   | %12.0f | %7.2f |",
                     disabledNs, disabledNs / 1024.0))
        print(String(format: "| counters enabled    | %12.0f | %7.2f |",
                     enabledNs, enabledNs / 1024.0))
        print()
        print(String(format: "Speedup (disabled vs enabled): %.3f×", speedup))
        print(String(format: "Counter overhead: %+.1f%% of per-block wall",
                     savedPct))
    }

    /// Concurrent A/B at 8 workers — the configuration that V91 Phase 2
    /// measured 5× per-block inflation at on M2. If the inflation is
    /// driven by counter false-sharing, this delta should be larger
    /// than the single-thread delta.
    func testConcurrent8WorkersCounterCost() async throws {
        let block = moderateDensityBlock()
        let runs = 5
        let blocksPerWorker = 2_000   // 8 × 2000 = 16K blocks/run

        let disabledNs = await measureConcurrent(
            block: block, blocksPerWorker: blocksPerWorker,
            workers: 8, runs: runs, countersEnabled: false)
        let enabledNs = await measureConcurrent(
            block: block, blocksPerWorker: blocksPerWorker,
            workers: 8, runs: runs, countersEnabled: true)

        let speedup = enabledNs / disabledNs
        let savedPct = 100 * (enabledNs - disabledNs) / enabledNs

        print()
        print("=== v9.2 Path B Phase 0a — concurrent counter A/B (8 workers) ===")
        print()
        print("Moderate-density 64×64 block, missingMSBs=24,")
        print("\(blocksPerWorker) blocks × 8 workers × median of \(runs).")
        print()
        print("| mode                |   ns/block   | ns/quad |")
        print("|---------------------|-------------:|--------:|")
        print(String(format: "| counters disabled   | %12.0f | %7.2f |",
                     disabledNs, disabledNs / 1024.0))
        print(String(format: "| counters enabled    | %12.0f | %7.2f |",
                     enabledNs, enabledNs / 1024.0))
        print()
        print(String(format: "Speedup (disabled vs enabled): %.3f×", speedup))
        print(String(format: "Counter overhead under 8-worker contention: %+.1f%%",
                     savedPct))
        print()
        print("Interpretation:")
        print("  If concurrent overhead >> single-thread overhead, the")
        print("  counter statics are causing false-sharing across cores")
        print("  (cache-line ping-pong). If they are similar, the dominant")
        print("  cost is the counter store itself, not contention.")
    }
}
