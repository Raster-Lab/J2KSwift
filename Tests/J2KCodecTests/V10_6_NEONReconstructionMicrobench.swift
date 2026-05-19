// V10_6_NEONReconstructionMicrobench.swift
//
// v10.6-research — per-block microbench A/B: C+NEON HT decoder with
// scalar reconstruction (`read_quad_samples_scalar`) vs SIMD
// reconstruction (`read_quad_samples_simd`).
//
// Same synthetic block corpus drives both paths; only the
// `reconstruct_use_simd` parameter to `j2knhd_decode_block_ht32`
// flips between A and B.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_6_NEONReconstructionMicrobench: XCTestCase {

    struct BlockCorpus {
        let label: String
        let width: Int
        let height: Int
        let blocks: [[UInt8]]
    }

    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32) -> UInt32 {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

    private static func makeCorpus(
        width: Int, height: Int, density: Double, count: Int, baseSeed: UInt64
    ) -> BlockCorpus {
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(count)
        for i in 0..<count {
            let p: UInt32 = 30
            var coefs = [UInt32](repeating: 0, count: width * height)
            var state = (baseSeed &+ UInt64(i)) | 1
            for k in 0..<coefs.count {
                state &*= 6364136223846793005
                state &+= 1442695040888963407
                let pct = Double(state >> 32) / Double(UInt32.max)
                if pct < density {
                    let sign = (state & 1) == 1
                    coefs[k] = binCenter(mu: 1, sign: sign, p: p)
                }
            }
            let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
            let block = (try? HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)) ?? []
            blocks.append(block)
        }
        return BlockCorpus(
            label: "\(width)×\(height) density \(density)",
            width: width, height: height, blocks: blocks)
    }

    struct Stats { let median: Double; let mean: Double; let min: Double; let p99: Double }

    private static func summarise(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        let mean = samples.reduce(0, +) / Double(samples.count)
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        return Stats(median: sorted[sorted.count / 2],
                     mean: mean,
                     min: sorted.first!,
                     p99: p99)
    }

    private static func bench(_ corpus: BlockCorpus, iterations: Int, useSimd: Bool) -> Stats {
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
                                    /* useSwar */ true,
                                    useSimd,
                                    co.baseAddress)
                            }
                        }
                    }
                }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
            }
        }
        return summarise(samples)
    }

    func testReconstructionMicrobench() {
        let width = 64, height = 64
        let perClass = 1000
        let iterations = 5

        let corpora: [BlockCorpus] = [
            Self.makeCorpus(width: width, height: height, density: 0.05, count: perClass, baseSeed: 0xBB01),
            Self.makeCorpus(width: width, height: height, density: 0.25, count: perClass, baseSeed: 0xBB02),
            Self.makeCorpus(width: width, height: height, density: 0.50, count: perClass, baseSeed: 0xBB03),
            Self.makeCorpus(width: width, height: height, density: 0.80, count: perClass, baseSeed: 0xBB04),
        ]

        print("=== V10_6_NEON_RECONSTRUCTION_AB_BEGIN ===")
        print("HT block decode: scalar reconstruction vs SIMD reconstruction (NEON intrinsics)")
        print("Same C+NEON entry point; only the `reconstruct_use_simd` parameter toggles.")
        print("")
        print("| Corpus | scalar med ns | SIMD med ns | speedup | Δ ns/block |")
        print("|---|---:|---:|---:|---:|")
        // Warmup
        for corpus in corpora {
            for block in corpus.blocks.prefix(64) {
                var dummy = [UInt32](repeating: 0, count: corpus.width * corpus.height)
                _ = block.withUnsafeBufferPointer { bp -> Int32 in
                    return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0p in
                        return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1p in
                            return dummy.withUnsafeMutableBufferPointer { co in
                                return j2knhd_decode_block_ht32(
                                    bp.baseAddress, bp.count,
                                    UInt32(corpus.width), UInt32(corpus.height), 0,
                                    t0p.baseAddress, t1p.baseAddress,
                                    true, false, co.baseAddress)
                            }
                        }
                    }
                }
            }
        }
        for corpus in corpora {
            let scalar = Self.bench(corpus, iterations: iterations, useSimd: false)
            let simd   = Self.bench(corpus, iterations: iterations, useSimd: true)
            let speedup = scalar.median / simd.median
            let delta = simd.median - scalar.median
            print(String(format: "| %@ | %.0f | %.0f | %.2fx | %+.0f |",
                         corpus.label, scalar.median, simd.median, speedup, delta))
        }
        print("=== V10_6_NEON_RECONSTRUCTION_AB_END ===")
    }
}
#endif
