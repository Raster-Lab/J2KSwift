// V91Phase2ConcurrentContentionProbe.swift
//
// v9.1 Path B Phase 2 — concurrent contention hypothesis test.
//
// Phase 2 cache-pressure probe REFUTED the cache-bound interpretation
// of Phase 1B: pool sizes from 16 KB to 64 MB all measured 35 ns/quad
// in a single-threaded microbench.
//
// New hypothesis: the 8.5× per-block-wall inflation between corpus
// (308 µs/block) and microbench (36 µs/block) comes from **concurrent
// heap/allocator contention** when 6+ TaskGroup workers run simultaneously.
// Each encode() pays ARC + Array.append + heap allocator costs that
// don't scale linearly with concurrency due to allocator-level locks.
//
// This probe replicates the corpus's concurrent dispatch pattern in a
// controlled microbench: dispatch N copies of the same encode work in
// parallel TaskGroup workers. If per-block wall time inflates with
// worker count, allocator contention is the bottleneck.

import XCTest
@testable import J2KCodec

final class V91Phase2ConcurrentContentionProbe: XCTestCase {

    private static let blockSize = 64

    private func sparseBlock(sigCount: Int) -> [UInt32] {
        var block = [UInt32](repeating: 0, count: Self.blockSize * Self.blockSize)
        let stride = max(1, (Self.blockSize * Self.blockSize) / max(sigCount, 1))
        for i in 0..<sigCount {
            let idx = i * stride
            if idx < block.count {
                block[idx] = (i & 1 == 0) ? 0x0000_0080 : 0x8000_0080
            }
        }
        return block
    }

    func testConcurrentDispatchScaling() async throws {
        let blocksPerWorker = 1000
        let sigPerBlock = 200  // 5% significance
        let workerCounts = [1, 2, 4, 6, 8, 12]
        let bs = Self.blockSize

        struct Row {
            let workers: Int
            let medianPerBlockNs: UInt64
            let totalWallMs: Double
            let totalBlocks: Int
            let throughputBlocksPerSec: Double
        }
        var rows: [Row] = []

        for workerCount in workerCounts {
            // Drive `workerCount` concurrent tasks, each encoding
            // `blocksPerWorker` blocks; capture per-block wall samples.
            // Each task builds its OWN coefficient block to avoid
            // sharing-immutable-array Sendable issues.
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let allSamples = await withTaskGroup(of: [UInt64].self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        var magsgn = HTMagSgnEncoderConformant()
                        var mel = HTMELEncoderConformant()
                        var vlc = HTReverseBitEmitterConformant()
                        // Inline-build the coefficient block in this task.
                        var coeffs = [UInt32](repeating: 0, count: bs * bs)
                        let stride = max(1, (bs * bs) / max(sigPerBlock, 1))
                        for i in 0..<sigPerBlock {
                            let idx = i * stride
                            if idx < coeffs.count {
                                coeffs[idx] = (i & 1 == 0) ? 0x0000_0080 : 0x8000_0080
                            }
                        }
                        var samples: [UInt64] = []
                        samples.reserveCapacity(blocksPerWorker)
                        for _ in 0..<blocksPerWorker {
                            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            _ = coeffs.withUnsafeBufferPointer { ptr in
                                HTBlockEncoderConformant.encode(
                                    coefficients: ptr,
                                    width: bs, height: bs,
                                    missingMSBs: 24,
                                    magsgnEnc: &magsgn,
                                    melEnc: &mel,
                                    vlcEnc: &vlc,
                                    useSIMDClassification: false,
                                    preClassifiedTuples: nil)
                            }
                            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            samples.append(t1 &- t0)
                        }
                        return samples
                    }
                }
                var collected: [UInt64] = []
                for await sub in group {
                    collected.append(contentsOf: sub)
                }
                return collected
            }
            let wallEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

            var sorted = allSamples
            sorted.sort()
            let median = sorted[sorted.count / 2]
            let totalBlocks = workerCount * blocksPerWorker
            let totalWallMs = Double(wallEnd &- wallStart) / 1_000_000.0
            let throughput = Double(totalBlocks) / (totalWallMs / 1000.0)
            rows.append(Row(
                workers: workerCount,
                medianPerBlockNs: median,
                totalWallMs: totalWallMs,
                totalBlocks: totalBlocks,
                throughputBlocksPerSec: throughput))
        }

        print()
        print("=== v9.1 Phase 2 — concurrent dispatch scaling probe ===")
        print()
        print("\(Self.blockSize)×\(Self.blockSize) blocks, 5% significance.")
        print("\(blocksPerWorker) blocks per worker. Each worker = independent task.")
        print()
        print("| workers | median ns/block | total wall ms | total blocks | blocks/sec | speedup vs 1 |")
        print("|--------:|----------------:|--------------:|-------------:|-----------:|-------------:|")
        let baseline = rows[0].throughputBlocksPerSec
        for r in rows {
            print(String(format: "| %7d | %15llu | %13.2f | %12d | %10.0f | %12.2f× |",
                r.workers, r.medianPerBlockNs, r.totalWallMs, r.totalBlocks,
                r.throughputBlocksPerSec, r.throughputBlocksPerSec / baseline))
        }
        print()
        print("Interpretation:")
        print("  - If median ns/block grows with worker count (e.g. 1 worker = 30 µs,")
        print("    8 workers = 200 µs), allocator/heap contention is the bottleneck.")
        print("  - If throughput scales sub-linearly (e.g. 8 workers < 6× speedup),")
        print("    same conclusion: per-worker overhead grows with concurrency.")
        print("  - If throughput scales linearly AND ns/block stays flat, contention")
        print("    is NOT the issue and Phase 1B finding needs further root-causing.")
    }
}
