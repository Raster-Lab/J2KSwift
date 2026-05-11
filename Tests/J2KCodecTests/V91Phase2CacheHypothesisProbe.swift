// V91Phase2CacheHypothesisProbe.swift
//
// v9.1 Path B Phase 2 — verify the Phase 1B cache-bound hypothesis.
//
// Phase 1B finding: HTBlockEncoderConformant.encode runs at 40 ns/quad
// when the coefficient block is L1-resident, but the corpus measurement
// on DX shows 1112 ns/quad. The 27× ratio was attributed to "cache +
// memory bandwidth contention when many TaskGroup workers compete".
//
// This probe DIRECTLY tests that hypothesis by varying ONLY the cache
// pressure while keeping everything else identical:
//
//   - Variant A — WARM: encode the same 64×64 block N times. Coefficient
//     buffer stays L1-resident.
//   - Variant B — COLD-SCATTER: encode N different blocks scattered
//     across a large coefficient buffer. Each block read forces L2/L3
//     traffic, mimicking the real-pipeline access pattern.
//   - Variant C — SCATTER-BLOCK-MAJOR: encode N different blocks from
//     a buffer where each block's data is CONTIGUOUS. Tests whether
//     reorganizing coefficient layout to be block-major improves cache
//     behaviour.
//
// Hypothesis: COLD-SCATTER will be much slower than WARM (5-20× slower).
// SCATTER-BLOCK-MAJOR will be faster than COLD-SCATTER but slower than
// WARM (1.5-5× cold-scatter speedup).
//
// If the hypothesis holds, Phase 2 Candidate D (block-major coefficient
// layout) is empirically validated as the right Path B target.

import XCTest
@testable import J2KCodec

final class V91Phase2CacheHypothesisProbe: XCTestCase {

    private static let blockSize = 64
    private static let samplesPerBlock = 64 * 64

    private func sparseBlockData(seed: UInt64, sigCount: Int) -> [UInt32] {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: seed)
        var data = [UInt32](repeating: 0, count: Self.samplesPerBlock)
        // Place sigCount significant samples at stride-deterministic positions
        // with safe magnitude (0x80, well within UInt8 eQ budget at p=6).
        let stride = max(1, Self.samplesPerBlock / max(sigCount, 1))
        for i in 0..<sigCount {
            let idx = i * stride
            if idx < Self.samplesPerBlock {
                let signBit = (rng.next() & 1) != 0 ? UInt32(0x8000_0000) : 0
                data[idx] = signBit | 0x0000_0080
            }
        }
        return data
    }

    private func runVariant(
        label: String,
        blocks: [[UInt32]],
        blockOrder: [Int],
        iterations: Int
    ) -> (nsPerBlock: Double, encodedSize: Int) {
        var magsgn = HTMagSgnEncoderConformant()
        var mel = HTMELEncoderConformant()
        var vlc = HTReverseBitEmitterConformant()
        let missingMSBs = 24
        var encodedSize = 0
        let runs = 5
        var samples: [Double] = []

        // Warmup: run once through the order without timing.
        for blockIdx in blockOrder.prefix(min(iterations, blockOrder.count)) {
            let block = blocks[blockIdx % blocks.count]
            _ = block.withUnsafeBufferPointer { ptr in
                HTBlockEncoderConformant.encode(
                    coefficients: ptr,
                    width: Self.blockSize, height: Self.blockSize,
                    missingMSBs: missingMSBs,
                    magsgnEnc: &magsgn,
                    melEnc: &mel,
                    vlcEnc: &vlc,
                    useSIMDClassification: false,
                    preClassifiedTuples: nil)
            }
        }

        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            for i in 0..<iterations {
                let blockIdx = blockOrder[i % blockOrder.count]
                let block = blocks[blockIdx % blocks.count]
                let r = block.withUnsafeBufferPointer { ptr in
                    HTBlockEncoderConformant.encode(
                        coefficients: ptr,
                        width: Self.blockSize, height: Self.blockSize,
                        missingMSBs: missingMSBs,
                        magsgnEnc: &magsgn,
                        melEnc: &mel,
                        vlcEnc: &vlc,
                        useSIMDClassification: false,
                        preClassifiedTuples: nil)
                }
                encodedSize = r.magsgn.count + r.mel.count + r.vlc.count
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / Double(iterations))
        }
        samples.sort()
        return (samples[runs / 2], encodedSize)
    }

    func testWarmVsColdScatterEncode() throws {
        // Strategy: ramp the "distinct block pool" size from 1 (warm)
        // to N (cold-scatter), with each block having identical work
        // characteristics (same sig count, same encoded size). Throughput
        // delta isolates the cache effect.

        let iterations = 5000
        let sigPerBlock = 200  // ~5% significance, ~realistic medical subband density
        let poolSizes = [1, 16, 64, 256, 1024, 4096]  // 4 KB to 16 MB working set

        struct Row {
            let label: String
            let poolSize: Int
            let workingSetMB: Double
            let nsPerBlock: Double
            let encodedSize: Int
        }
        var rows: [Row] = []

        for poolSize in poolSizes {
            // Build a pool of distinct blocks.
            var pool: [[UInt32]] = []
            pool.reserveCapacity(poolSize)
            for i in 0..<poolSize {
                pool.append(sparseBlockData(seed: UInt64(0xCAFE0000 + i), sigCount: sigPerBlock))
            }
            // Block-order: walk pool in sequence each iteration (so
            // each iteration's block is fresh from the pool, not from
            // L1 cache unless pool fits in L1).
            let order = Array(0..<poolSize)
            let result = runVariant(
                label: "pool=\(poolSize)",
                blocks: pool,
                blockOrder: order,
                iterations: iterations)
            let workingSetBytes = poolSize * Self.samplesPerBlock * 4
            let workingSetMB = Double(workingSetBytes) / (1024 * 1024)
            rows.append(Row(
                label: "pool=\(poolSize) (\(workingSetMB) MB)",
                poolSize: poolSize,
                workingSetMB: workingSetMB,
                nsPerBlock: result.nsPerBlock,
                encodedSize: result.encodedSize))
        }

        print()
        print("=== v9.1 Phase 2 — cache hypothesis verification ===")
        print()
        print("Sparse 64×64 blocks (\(sigPerBlock)/4096 sig samples ≈ 5%).")
        print("iterations per variant: \(iterations).")
        print("Each variant uses a different pool size; same encoded work per block.")
        print()
        print("| pool size | working set (MB) | ns/block | ns/quad | ratio vs warm |")
        print("|----------:|-----------------:|---------:|--------:|--------------:|")
        let warmNs = rows[0].nsPerBlock
        for r in rows {
            print(String(format: "| %9d | %16.2f | %8.0f | %7.2f | %13.2f× |",
                r.poolSize, r.workingSetMB, r.nsPerBlock, r.nsPerBlock / 1024.0, r.nsPerBlock / warmNs))
        }
        print()
        print("Reference points:")
        print("  - M2 per-core L1 data cache: 128 KB → ~8 blocks of 16 KB each")
        print("  - M2 per-cluster L2: 12 MB → ~768 blocks")
        print("  - Phase 0 corpus DX measurement: 1112 ns/quad")
        print()
        print("Interpretation:")
        print("  - If ns/block GROWS as pool size grows past 8-16 blocks (L1 overflow)")
        print("    or 768 blocks (L2 overflow), cache pressure IS the bottleneck.")
        print("  - If ns/block stays flat, cache is NOT the bottleneck and the")
        print("    Phase 1B interpretation needs revision.")
    }
}
