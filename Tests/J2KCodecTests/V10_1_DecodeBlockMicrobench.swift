// v10.1 Phase D1 Phase 0 — Swift per-block decode baseline.
//
// Establishes the per-block ns timing the future scalar C port must
// beat by ≥10% (single-thread) to clear the Phase 0 gate. See
// `Documentation/research/V10_1_DECODE_C_PORT_PROBE.md`.
//
// Methodology mirrors v9.4 encoder analog
// (`Documentation/research/V9_4_NEON_HOT_PATH_RESEARCH.md`):
//   - Synthetic 64×64 corpus, 1000 blocks total
//   - Sparsity classes {5%, 25%, 50%}
//   - Deterministic LCG fill, p=30 bit-depth, missingMSBs=0
//   - Single-thread and 12-worker concurrency measurements
//   - Median + min/max per-block ns reported
//
// Output is the `=== V10_1_DECODE_BASELINE BEGIN ===` markdown block
// for direct comparison with the future C path's `V10_1_DecodeBlockCMicrobench`.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec

final class V10_1_DecodeBlockMicrobench: XCTestCase {

    private struct BlockCorpus {
        let width: Int
        let height: Int
        let label: String
        let blocks: [[UInt8]]
    }

    // MARK: - Synthetic coefficient generator

    /// Bin-centered sign-magnitude sample. Matches the encoder's
    /// expected per-coefficient convention.
    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32) -> UInt32 {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

    /// Deterministic LCG coefficient generator. Matches the format
    /// used by `HTBlockBenchmarkConformantTests.makeCoefficients`.
    private static func makeCoefficients(
        width: Int, height: Int, density: Double, seed: UInt64
    ) -> [UInt32] {
        let p: UInt32 = 30
        var coefs = [UInt32](repeating: 0, count: width * height)
        var state = seed | 1
        for i in 0..<coefs.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let pct = Double(state >> 32) / Double(UInt32.max)
            if pct < density {
                let sign = (state & 1) == 1
                coefs[i] = binCenter(mu: 1, sign: sign, p: p)
            }
        }
        return coefs
    }

    private static func makeCorpus(
        width: Int, height: Int, density: Double, count: Int, baseSeed: UInt64
    ) -> BlockCorpus {
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(count)
        for i in 0..<count {
            let coefs = makeCoefficients(
                width: width, height: height,
                density: density, seed: baseSeed &+ UInt64(i))
            let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
            do {
                let block = try HTBlockLayoutConformant.assemble(
                    magsgn: ms, mel: mel, vlc: vlc)
                blocks.append(block)
            } catch {
                // Skip — degenerate corpora occasionally produce SCUP
                // out-of-range; this is uncommon at the chosen
                // sparsities but worth tolerating in the corpus.
                continue
            }
        }
        return BlockCorpus(
            width: width, height: height,
            label: "\(width)x\(height) @ \(Int(density * 100))%",
            blocks: blocks)
    }

    // MARK: - Per-block timing primitives

    /// Sorted [Double] → (median, min, max, p99).
    private struct Stats {
        let median: Double
        let min: Double
        let max: Double
        let p99: Double
    }

    private static func summarise(_ samples: [Double]) -> Stats {
        guard !samples.isEmpty else { return Stats(median: 0, min: 0, max: 0, p99: 0) }
        let sorted = samples.sorted()
        let med = sorted[sorted.count / 2]
        let p99idx = Int(Double(sorted.count - 1) * 0.99)
        return Stats(
            median: med,
            min: sorted.first!,
            max: sorted.last!,
            p99: sorted[p99idx])
    }

    /// Decode every block in `corpus` `iterations` times on the main
    /// thread, return per-block-per-iteration ns samples.
    private static func benchSingleThread(_ corpus: BlockCorpus, iterations: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(corpus.blocks.count * iterations)
        for _ in 0..<iterations {
            for block in corpus.blocks {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try? HTBlockDecoderConformant.decode(
                    block: block,
                    width: corpus.width,
                    height: corpus.height,
                    missingMSBs: 0)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
        }
        return summarise(samples)
    }

    /// Decode every block in `corpus` across `workers` concurrent
    /// dispatches, return per-block ns. Captures the multi-thread
    /// number v9.4 reported (`16,416 ns → 7,916 ns` for the
    /// encoder analog at 12 workers).
    private static func benchConcurrent(
        _ corpus: BlockCorpus, iterations: Int, workers: Int
    ) -> Stats {
        // Each worker decodes its slice of `(blocks * iterations)`,
        // sampling per-block ns. Aggregate after the join.
        let total = corpus.blocks.count * iterations
        let chunk = (total + workers - 1) / workers
        var samples = Array(repeating: [Double](), count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            var local: [Double] = []
            local.reserveCapacity(chunk)
            let lo = worker * chunk
            let hi = min(total, lo + chunk)
            for idx in lo..<hi {
                let block = corpus.blocks[idx % corpus.blocks.count]
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try? HTBlockDecoderConformant.decode(
                    block: block,
                    width: corpus.width,
                    height: corpus.height,
                    missingMSBs: 0)
                local.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
            samples[worker] = local
        }
        return summarise(samples.flatMap { $0 })
    }

    // MARK: - Main probe

    /// Drives the entire Phase 0 baseline measurement.
    /// Prints a markdown table inside `=== V10_1_DECODE_BASELINE_BEGIN ===`.
    func testPhaseD1Phase0_swiftBaseline() {
        // 1000 blocks per sparsity class, 64×64, 5 iterations.
        // 1000 × 5 = 5000 samples per class — enough to make the
        // median stable.
        let width = 64, height = 64
        let perClass = 1000
        let iterations = 5

        let corpora: [BlockCorpus] = [
            Self.makeCorpus(width: width, height: height, density: 0.05,
                            count: perClass, baseSeed: 0xAA01),
            Self.makeCorpus(width: width, height: height, density: 0.25,
                            count: perClass, baseSeed: 0xAA02),
            Self.makeCorpus(width: width, height: height, density: 0.50,
                            count: perClass, baseSeed: 0xAA03)
        ]

        struct Row {
            let label: String
            let single: Stats
            let concurrent: Stats
        }
        var rows: [Row] = []
        for corpus in corpora {
            // Warmups: 2 untimed passes (JIT/cache).
            for _ in 0..<2 {
                for block in corpus.blocks.prefix(64) {
                    _ = try? HTBlockDecoderConformant.decode(
                        block: block, width: corpus.width,
                        height: corpus.height, missingMSBs: 0)
                }
            }
            let single = Self.benchSingleThread(corpus, iterations: iterations)
            let concurrent = Self.benchConcurrent(corpus, iterations: iterations, workers: 12)
            rows.append(Row(label: corpus.label, single: single, concurrent: concurrent))
        }

        print("")
        print("=== V10_1_DECODE_BASELINE_BEGIN ===")
        print("J2KSwift HEAD per-block decode (Swift reference path)")
        print("64x64 blocks, 1000 blocks/class, 5 iterations, M2 release")
        print("")
        print("| Sparsity | Single-thread median ns | min ns | p99 ns | 12-worker median ns | min ns | p99 ns |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f |",
                         r.label,
                         r.single.median, r.single.min, r.single.p99,
                         r.concurrent.median, r.concurrent.min, r.concurrent.p99))
        }
        print("")
        print("Gate (when C path lands):")
        print("  - scalar C median ≤ Swift median × 0.90 (single-thread, ≥10% win)")
        print("  - 12-worker C median ≤ Swift median × 0.95")
        print("=== V10_1_DECODE_BASELINE_END ===")
        print("")

        // Sanity-check the corpus is non-trivial.
        for r in rows {
            XCTAssertGreaterThan(r.single.median, 0)
            XCTAssertGreaterThan(r.concurrent.median, 0)
        }
    }
}
#endif
