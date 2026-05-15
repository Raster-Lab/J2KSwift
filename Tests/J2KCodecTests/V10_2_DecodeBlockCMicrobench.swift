// v10.2-research Phase D1.5-B — per-block decoder microbench.
//
// Times Swift HTBlockDecoderConformant.decode (production) vs C
// j2knhd_decode_block_ht32 (scalar + SWAR variants) over the same
// synthetic block corpus as v10.1's V10_1_DecodeBlockMicrobench.
//
// Comparison is per-block decode wall-clock (ns/block). Phase D1.5-B
// gate: integrated C ≥ Swift × 0.90 single-thread AND ≥ Swift × 0.95
// at 12-worker concurrency.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_2_DecodeBlockCMicrobench: XCTestCase {

    private struct BlockCorpus {
        let width: Int
        let height: Int
        let label: String
        let blocks: [[UInt8]]
    }

    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32) -> UInt32 {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

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

    private static func makeCorpus(width: Int, height: Int, density: Double, count: Int, baseSeed: UInt64) -> BlockCorpus {
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(count)
        for i in 0..<count {
            let coefs = makeCoefficients(width: width, height: height, density: density, seed: baseSeed &+ UInt64(i))
            let (ms, mel, vlc) = HTBlockEncoderConformant.encode(coefficients: coefs, width: width, height: height, missingMSBs: 0)
            do {
                let block = try HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)
                blocks.append(block)
            } catch {
                continue
            }
        }
        return BlockCorpus(width: width, height: height, label: "\(width)x\(height) @ \(Int(density*100))%", blocks: blocks)
    }

    private struct Stats { let median: Double; let min: Double; let p99: Double }

    private static func summarise(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        let med = sorted[sorted.count / 2]
        let p99idx = Int(Double(sorted.count - 1) * 0.99)
        return Stats(median: med, min: sorted.first!, p99: sorted[p99idx])
    }

    // MARK: - Benches

    private static func benchSwift(_ corpus: BlockCorpus, iterations: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(corpus.blocks.count * iterations)
        for _ in 0..<iterations {
            for block in corpus.blocks {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try? HTBlockDecoderConformant.decode(
                    block: block, width: corpus.width, height: corpus.height, missingMSBs: 0)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
        }
        return summarise(samples)
    }

    private static func benchC(_ corpus: BlockCorpus, iterations: Int, useSwar: Bool) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(corpus.blocks.count * iterations)
        var coefs = [UInt32](repeating: 0, count: corpus.width * corpus.height)
        for _ in 0..<iterations {
            for block in corpus.blocks {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = block.withUnsafeBufferPointer { bp -> Int32 in
                    return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0p in
                        return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1p in
                            return coefs.withUnsafeMutableBufferPointer { co in
                                return j2knhd_decode_block_ht32(
                                    bp.baseAddress, bp.count,
                                    UInt32(corpus.width), UInt32(corpus.height), 0,
                                    t0p.baseAddress, t1p.baseAddress,
                                    useSwar, co.baseAddress)
                            }
                        }
                    }
                }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
        }
        return summarise(samples)
    }

    private static func benchSwiftConcurrent(_ corpus: BlockCorpus, iterations: Int, workers: Int) -> Stats {
        let total = corpus.blocks.count * iterations
        let chunk = (total + workers - 1) / workers
        var perWorker = Array(repeating: [Double](), count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { w in
            var local: [Double] = []
            local.reserveCapacity(chunk)
            let lo = w * chunk
            let hi = min(total, lo + chunk)
            for idx in lo..<hi {
                let block = corpus.blocks[idx % corpus.blocks.count]
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try? HTBlockDecoderConformant.decode(
                    block: block, width: corpus.width, height: corpus.height, missingMSBs: 0)
                local.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
            perWorker[w] = local
        }
        return summarise(perWorker.flatMap { $0 })
    }

    private static func benchCConcurrent(_ corpus: BlockCorpus, iterations: Int, workers: Int, useSwar: Bool) -> Stats {
        let total = corpus.blocks.count * iterations
        let chunk = (total + workers - 1) / workers
        var perWorker = Array(repeating: [Double](), count: workers)
        DispatchQueue.concurrentPerform(iterations: workers) { w in
            var local: [Double] = []
            local.reserveCapacity(chunk)
            var coefs = [UInt32](repeating: 0, count: corpus.width * corpus.height)
            let lo = w * chunk
            let hi = min(total, lo + chunk)
            for idx in lo..<hi {
                let block = corpus.blocks[idx % corpus.blocks.count]
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = block.withUnsafeBufferPointer { bp -> Int32 in
                    return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0p in
                        return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1p in
                            return coefs.withUnsafeMutableBufferPointer { co in
                                return j2knhd_decode_block_ht32(
                                    bp.baseAddress, bp.count,
                                    UInt32(corpus.width), UInt32(corpus.height), 0,
                                    t0p.baseAddress, t1p.baseAddress,
                                    useSwar, co.baseAddress)
                            }
                        }
                    }
                }
                local.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
            perWorker[w] = local
        }
        return summarise(perWorker.flatMap { $0 })
    }

    func testPhaseD1_5B_blockMicrobench() {
        let width = 64, height = 64
        let perClass = 1000
        let iterations = 5

        let corpora: [BlockCorpus] = [
            Self.makeCorpus(width: width, height: height, density: 0.05, count: perClass, baseSeed: 0xAA01),
            Self.makeCorpus(width: width, height: height, density: 0.25, count: perClass, baseSeed: 0xAA02),
            Self.makeCorpus(width: width, height: height, density: 0.50, count: perClass, baseSeed: 0xAA03)
        ]

        struct Row {
            let label: String
            let swiftST: Stats
            let cScalarST: Stats
            let cSwarST: Stats
            let swiftMT: Stats
            let cSwarMT: Stats
        }
        var rows: [Row] = []
        for corpus in corpora {
            // Warmups (2 untimed passes).
            for _ in 0..<2 {
                for block in corpus.blocks.prefix(64) {
                    _ = try? HTBlockDecoderConformant.decode(
                        block: block, width: corpus.width, height: corpus.height, missingMSBs: 0)
                    var dummy = [UInt32](repeating: 0, count: corpus.width * corpus.height)
                    _ = block.withUnsafeBufferPointer { bp -> Int32 in
                        return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0p in
                            return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1p in
                                return dummy.withUnsafeMutableBufferPointer { co in
                                    return j2knhd_decode_block_ht32(
                                        bp.baseAddress, bp.count,
                                        UInt32(corpus.width), UInt32(corpus.height), 0,
                                        t0p.baseAddress, t1p.baseAddress, true, co.baseAddress)
                                }
                            }
                        }
                    }
                }
            }

            let swiftST   = Self.benchSwift(corpus, iterations: iterations)
            let cScalarST = Self.benchC(corpus, iterations: iterations, useSwar: false)
            let cSwarST   = Self.benchC(corpus, iterations: iterations, useSwar: true)
            let swiftMT   = Self.benchSwiftConcurrent(corpus, iterations: iterations, workers: 12)
            let cSwarMT   = Self.benchCConcurrent(corpus, iterations: iterations, workers: 12, useSwar: true)
            rows.append(Row(label: corpus.label,
                            swiftST: swiftST, cScalarST: cScalarST, cSwarST: cSwarST,
                            swiftMT: swiftMT, cSwarMT: cSwarMT))
        }

        print("")
        print("=== V10_2_DECODE_BLOCK_C_MICROBENCH_BEGIN ===")
        print("Per-block HT decode wall (ns/block) — Swift production vs C scalar vs C SWAR-4")
        print("M2 release, 64x64 blocks, 1000 blocks/class, 5 iterations")
        print("")
        print("| Sparsity | Swift ST ns | C scalar ST ns | C SWAR ST ns | C SWAR / Swift ST | Swift MT ns | C SWAR MT ns | C SWAR / Swift MT |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %.0f | %.0f | %.0f | %.2fx | %.0f | %.0f | %.2fx |",
                         r.label,
                         r.swiftST.median, r.cScalarST.median, r.cSwarST.median,
                         r.swiftST.median / r.cSwarST.median,
                         r.swiftMT.median, r.cSwarMT.median,
                         r.swiftMT.median / r.cSwarMT.median))
        }
        print("")
        let geoMeanST = rows.map { $0.swiftST.median / $0.cSwarST.median }.reduce(1.0, *)
        let geoMeanSTroot = pow(geoMeanST, 1.0 / Double(rows.count))
        let geoMeanMT = rows.map { $0.swiftMT.median / $0.cSwarMT.median }.reduce(1.0, *)
        let geoMeanMTroot = pow(geoMeanMT, 1.0 / Double(rows.count))
        print(String(format: "Geometric mean single-thread speedup (C SWAR vs Swift): %.2fx", geoMeanSTroot))
        print(String(format: "Geometric mean 12-worker  speedup (C SWAR vs Swift): %.2fx", geoMeanMTroot))
        print("Phase D1.5-B gates:")
        print("  - Single-thread: C ≥ Swift × 0.90 (i.e. ratio ≥ 1.111x)")
        print("  - 12-worker:     C ≥ Swift × 0.95 (i.e. ratio ≥ 1.053x)")
        let stPass = geoMeanSTroot >= 1.111
        let mtPass = geoMeanMTroot >= 1.053
        if stPass && mtPass {
            print("Status: PASS — both gates cleared. Proceed to D1.5-C pipeline integration.")
        } else {
            print("Status: REVIEW — at least one gate marginal/fail.")
            print("  Single-thread: \(stPass ? "PASS" : "MISS")")
            print("  12-worker:     \(mtPass ? "PASS" : "MISS")")
        }
        print("=== V10_2_DECODE_BLOCK_C_MICROBENCH_END ===")
        print("")

        for r in rows {
            XCTAssertGreaterThan(r.swiftST.median, 0)
            XCTAssertGreaterThan(r.cSwarST.median, 0)
        }
    }
}
#endif
