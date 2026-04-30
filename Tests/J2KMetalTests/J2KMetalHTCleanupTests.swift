//
// J2KMetalHTCleanupTests.swift
// J2KSwift
//
// Bit-exact validation of the GPU full-cleanup HT decoder (phase 2)
// against the CPU `HTBlockDecoderConformant.decode`. Encodes a
// synthetic codeblock with `HTBlockEncoderConformant`, assembles the
// wire-format block, parses it for the GPU descriptor, runs the GPU
// kernel, and asserts byte-equality with the CPU decoder's output.
//

import XCTest
import J2KMetal
@testable import J2KCodec

final class J2KMetalHTCleanupTests: XCTestCase {

    private static let stderr = FileHandle.standardError
    private static func say(_ s: String) {
        stderr.write(Data((s + "\n").utf8))
    }

    /// Build a deterministic sign-magnitude coefficient buffer that
    /// exercises both significant and zero samples.
    ///
    /// A coefficient `t` is significant per the encoder's check
    /// `(t << 1) >> p >= 2`, i.e. the magnitude must have bit `p` set
    /// or above. Magnitudes below `2^p` decode as zero. We pick
    /// magnitudes in `[2^p, 2^(p+3))` so they cover a few different
    /// `eQ` values without overflowing into bit 31 (the sign bit).
    private func makeCoefficients(
        width: Int, height: Int, seed: UInt64, p: Int
    ) -> [UInt32] {
        var rng = seed | 1
        var out = [UInt32](repeating: 0, count: width * height)
        let minMag = UInt32(1) << p                     // 2^p — smallest significant magnitude
        let extraBits = min(3, 30 - p)                  // up to 3 bits of magnitude variation, but stay below bit 31
        let extraMask: UInt32 = extraBits >= 31 ? 0 : ((UInt32(1) << extraBits) - 1)
        for i in 0..<out.count {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            // Use a higher-entropy bit (top byte) for the ~40%
            // significance gate. The LCG's low bits cycle in a
            // predictable parity pattern, which after a second LCG
            // step would skew distribution heavily.
            let gate = UInt8((rng >> 56) & 0xFF)
            if gate < 100 { out[i] = 0; continue }   // ~39% zero
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let extra = UInt32((rng >> 32) & UInt64(extraMask))
            let sign = UInt32((rng >> 1) & 1) << 31
            out[i] = sign | (minMag &+ extra)
        }
        return out
    }

    /// Encode coefficients to a wire-format Part-15 block, then decode
    /// once on CPU and once on GPU; returns both outputs for the test
    /// to compare.
    private func encodeAndDecode(
        coefficients: [UInt32],
        width: Int, height: Int, missingMSBs: Int
    ) async throws -> (cpu: [UInt32], gpu: [UInt32], stats: J2KMetalHTCleanup.Statistics) {
        let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefficients,
            width: width, height: height,
            missingMSBs: missingMSBs)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: magsgn, mel: mel, vlc: vlc)

        // CPU reference
        let cpu = try HTBlockDecoderConformant.decode(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs)

        // Parse the block to recover scup + sub-stream split for GPU
        guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
            XCTFail("layout parse failed"); throw NSError(domain: "x", code: 1)
        }

        // Build descriptor + flat pool: [magsgn bytes][melVlc bytes]
        var pool: [UInt8] = []
        pool.reserveCapacity(parsed.magsgn.count + parsed.melVlc.count)
        pool.append(contentsOf: parsed.magsgn)
        let melVlcOffset = UInt32(pool.count)
        pool.append(contentsOf: parsed.melVlc)

        let desc = J2KMetalHTCleanupBlockDescriptor(
            magsgnOffset: 0,
            magsgnLength: UInt32(parsed.magsgn.count),
            melVlcOffset: melVlcOffset,
            melVlcLength: UInt32(parsed.scup),
            outputOffset: 0,
            width: UInt32(width), height: UInt32(height),
            missingMSBs: UInt32(missingMSBs)
        )

        let gpu = J2KMetalHTCleanup()
        let (out, stats) = try await gpu.run(
            descriptors: [desc],
            codestreamPool: pool,
            vlcTable0: vlcDecoderTable0Conformant,
            vlcTable1: vlcDecoderTable1Conformant,
            outputSampleCount: width * height
        )
        return (cpu, out, stats)
    }

    /// Probe — load the cleanup shader pipeline. If this hangs, the
    /// shader compile is the culprit; if it returns, the kernel
    /// dispatch is.
    func testShaderLoadOnly() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        Self.say("[ht-cleanup] requesting pipeline")
        let dev = J2KMetalDevice()
        try await dev.initialize()
        let lib = J2KMetalShaderLibrary()
        let q = try await dev.commandQueue()
        try await lib.loadShaders(device: q.device)
        let pipeline = try await lib.computePipeline(for: .htCleanupDecode)
        Self.say("[ht-cleanup] pipeline ok: \(pipeline.maxTotalThreadsPerThreadgroup) threads/group")
    }

    /// Tiny 4×4 block — easiest to debug if anything goes wrong.
    /// Uses a hand-picked coefficient set to guarantee at least one
    /// significant sample (otherwise the block is trivially all-zero
    /// and the test wouldn't exercise the entropy coder paths).
    func testTinyBlock() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let w = 4, h = 4, missingMSBs = 5
        // p = 30 - missingMSBs = 25. Significance requires magnitude
        // >= 2^p = 2^25 = 0x02000000. Use multiples of that magnitude.
        var coefs = [UInt32](repeating: 0, count: w * h)
        coefs[0] = 0x0200_0000                      // small positive (just at threshold)
        coefs[5] = 0x8000_0000 | 0x0300_0000        // negative
        coefs[10] = 0x0500_0000                     // larger positive
        coefs[15] = 0x8000_0000 | 0x0200_00AA       // small negative w/ low bits
        let r = try await encodeAndDecode(
            coefficients: coefs, width: w, height: h, missingMSBs: missingMSBs)
        let nonZero = r.cpu.filter { $0 != 0 }.count
        Self.say("[ht-cleanup] 4x4 nonZero=\(nonZero) cpu=\(r.cpu) gpu=\(r.gpu)")
        XCTAssertGreaterThan(nonZero, 0, "test data must produce some significant samples")
        XCTAssertEqual(r.gpu, r.cpu, "GPU output must match CPU on 4x4 block")
    }

    /// 16×16 — covers multiple subsequent rows.
    func testSmallBlock() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let w = 16, h = 16, missingMSBs = 4
        let p = 30 - missingMSBs
        let coefs = makeCoefficients(
            width: w, height: h, seed: 0xCAFE_F00D_FACE_B00C, p: p)
        let r = try await encodeAndDecode(
            coefficients: coefs, width: w, height: h, missingMSBs: missingMSBs)
        let nonZero = r.cpu.filter { $0 != 0 }.count
        Self.say("[ht-cleanup] 16x16 nonZero=\(nonZero)/\(r.cpu.count)")
        XCTAssertGreaterThan(nonZero, 10, "test data must produce significant samples")
        if r.gpu != r.cpu {
            // Print first divergence for debugging.
            for i in 0..<r.cpu.count {
                if r.gpu[i] != r.cpu[i] {
                    Self.say(String(format:
                        "[ht-cleanup] divergence at %d: cpu=0x%08x gpu=0x%08x",
                        i, r.cpu[i], r.gpu[i]))
                    break
                }
            }
        }
        XCTAssertEqual(r.gpu, r.cpu, "GPU output must match CPU on 16x16 block")
    }

    /// 64×64 — full codeblock.
    func testFullCodeblock() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let w = 64, h = 64, missingMSBs = 4
        let p = 30 - missingMSBs
        let coefs = makeCoefficients(
            width: w, height: h, seed: 0xA5A5_A5A5_A5A5_A5A5, p: p)
        let r = try await encodeAndDecode(
            coefficients: coefs, width: w, height: h, missingMSBs: missingMSBs)
        let nonZero = r.cpu.filter { $0 != 0 }.count
        Self.say("[ht-cleanup] 64x64 nonZero=\(nonZero)/\(r.cpu.count)")
        XCTAssertGreaterThan(nonZero, 100, "test data must produce significant samples")
        if r.gpu != r.cpu {
            for i in 0..<r.cpu.count {
                if r.gpu[i] != r.cpu[i] {
                    Self.say(String(format:
                        "[ht-cleanup] divergence at %d (xy=%d,%d): cpu=0x%08x gpu=0x%08x",
                        i, i % w, i / w, r.cpu[i], r.gpu[i]))
                    break
                }
            }
        }
        XCTAssertEqual(r.gpu, r.cpu, "GPU output must match CPU on 64x64 block")
    }

    /// All-zero block — exercises the long-MEL-run path.
    func testAllZeroBlock() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let w = 32, h = 32, missingMSBs = 4
        let coefs = [UInt32](repeating: 0, count: w * h)
        let r = try await encodeAndDecode(
            coefficients: coefs, width: w, height: h, missingMSBs: missingMSBs)
        XCTAssertEqual(r.gpu, r.cpu, "GPU output must match CPU on all-zero block")
        XCTAssertTrue(r.cpu.allSatisfy { $0 == 0 }, "all-zero block must decode to zeros")
    }

    /// Many blocks dispatched in one kernel — exercises the per-thread
    /// state isolation.
    func testManyBlocksDispatch() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let blockCount = 32
        let w = 32, h = 32, missingMSBs = 4
        let p = 30 - missingMSBs
        let samplesPerBlock = w * h

        var descriptors: [J2KMetalHTCleanupBlockDescriptor] = []
        var pool: [UInt8] = []
        var cpuExpected = [UInt32](repeating: 0, count: blockCount * samplesPerBlock)

        for b in 0..<blockCount {
            let coefs = makeCoefficients(
                width: w, height: h,
                seed: UInt64(b) &* 0x9E37_79B9_7F4A_7C15 | 1, p: p)
            let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: w, height: h,
                missingMSBs: missingMSBs)
            let block = try HTBlockLayoutConformant.assemble(
                magsgn: magsgn, mel: mel, vlc: vlc)
            let cpu = try HTBlockDecoderConformant.decode(
                block: block, width: w, height: h, missingMSBs: missingMSBs)
            for i in 0..<samplesPerBlock {
                cpuExpected[b * samplesPerBlock + i] = cpu[i]
            }

            guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
                XCTFail("parse fail b=\(b)"); return
            }
            let magsgnOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.magsgn)
            let melVlcOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.melVlc)

            descriptors.append(J2KMetalHTCleanupBlockDescriptor(
                magsgnOffset: magsgnOffset,
                magsgnLength: UInt32(parsed.magsgn.count),
                melVlcOffset: melVlcOffset,
                melVlcLength: UInt32(parsed.scup),
                outputOffset: UInt32(b * samplesPerBlock),
                width: UInt32(w), height: UInt32(h),
                missingMSBs: UInt32(missingMSBs)
            ))
        }

        let (gpuOut, stats) = try await J2KMetalHTCleanup().run(
            descriptors: descriptors,
            codestreamPool: pool,
            vlcTable0: vlcDecoderTable0Conformant,
            vlcTable1: vlcDecoderTable1Conformant,
            outputSampleCount: blockCount * samplesPerBlock
        )
        Self.say("[ht-cleanup] \(blockCount) blocks: " +
                 "wall=\(String(format: "%.3f", stats.wallClockSeconds * 1000))ms " +
                 "kernel=\(String(format: "%.3f", stats.gpuKernelSeconds * 1000))ms")
        if gpuOut != cpuExpected {
            for i in 0..<cpuExpected.count {
                if gpuOut[i] != cpuExpected[i] {
                    let b = i / samplesPerBlock
                    let s = i % samplesPerBlock
                    Self.say(String(format:
                        "[ht-cleanup] divergence at block=%d sample=%d (xy=%d,%d): cpu=0x%08x gpu=0x%08x",
                        b, s, s % w, s / w, cpuExpected[i], gpuOut[i]))
                    break
                }
            }
        }
        XCTAssertEqual(gpuOut, cpuExpected, "batched GPU dispatch must match CPU")
    }

    /// Phase-2 speedup measurement: full cleanup decode on the same
    /// workload as the phase-1 MagSgn benchmark (777 × 64×64 blocks).
    /// Reports the CPU/GPU wall-time ratio.
    func testGPUvsCPUSpeedup() async throws {
        try XCTSkipUnless(J2KMetalHTCleanup.isAvailable, "Metal not available")
        let blockCount = 777
        let w = 64, h = 64, missingMSBs = 4
        let p = 30 - missingMSBs
        let samplesPerBlock = w * h

        var descriptors: [J2KMetalHTCleanupBlockDescriptor] = []
        var pool: [UInt8] = []
        var coefSets: [[UInt32]] = []
        coefSets.reserveCapacity(blockCount)
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(blockCount)

        for b in 0..<blockCount {
            let coefs = makeCoefficients(
                width: w, height: h,
                seed: UInt64(b) &* 0x9E37_79B9_7F4A_7C15 | 1, p: p)
            coefSets.append(coefs)
            let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: w, height: h,
                missingMSBs: missingMSBs)
            let block = try HTBlockLayoutConformant.assemble(
                magsgn: magsgn, mel: mel, vlc: vlc)
            blocks.append(block)
            guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
                XCTFail("parse fail b=\(b)"); return
            }
            let magsgnOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.magsgn)
            let melVlcOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.melVlc)
            descriptors.append(J2KMetalHTCleanupBlockDescriptor(
                magsgnOffset: magsgnOffset,
                magsgnLength: UInt32(parsed.magsgn.count),
                melVlcOffset: melVlcOffset,
                melVlcLength: UInt32(parsed.scup),
                outputOffset: UInt32(b * samplesPerBlock),
                width: UInt32(w), height: UInt32(h),
                missingMSBs: UInt32(missingMSBs)
            ))
        }

        // Warm-up
        _ = try await J2KMetalHTCleanup().run(
            descriptors: descriptors, codestreamPool: pool,
            vlcTable0: vlcDecoderTable0Conformant,
            vlcTable1: vlcDecoderTable1Conformant,
            outputSampleCount: blockCount * samplesPerBlock)

        // CPU baseline (parallel)
        let cpuStart = DispatchTime.now()
        var cpuOut = [UInt32](repeating: 0, count: blockCount * samplesPerBlock)
        cpuOut.withUnsafeMutableBufferPointer { outBuf in
            DispatchQueue.concurrentPerform(iterations: blockCount) { i in
                let dec = try! HTBlockDecoderConformant.decode(
                    block: blocks[i], width: w, height: h,
                    missingMSBs: missingMSBs)
                let outBase = i * samplesPerBlock
                for j in 0..<dec.count {
                    outBuf[outBase + j] = dec[j]
                }
            }
        }
        let cpuEnd = DispatchTime.now()
        let cpuMs = Double(cpuEnd.uptimeNanoseconds - cpuStart.uptimeNanoseconds) / 1_000_000.0

        // GPU
        let (gpuOut, stats) = try await J2KMetalHTCleanup().run(
            descriptors: descriptors, codestreamPool: pool,
            vlcTable0: vlcDecoderTable0Conformant,
            vlcTable1: vlcDecoderTable1Conformant,
            outputSampleCount: blockCount * samplesPerBlock)
        XCTAssertEqual(gpuOut, cpuOut, "GPU output must match CPU baseline")

        let gpuMs = stats.wallClockSeconds * 1000
        let kernelMs = stats.gpuKernelSeconds * 1000
        let speedup = cpuMs / max(gpuMs, 0.001)
        Self.say(String(format:
            "[ht-cleanup] %d blocks × %d samples: cpu=%.2fms gpu_wall=%.2fms gpu_kernel=%.2fms speedup=%.2fx",
            blockCount, samplesPerBlock, cpuMs, gpuMs, kernelMs, speedup))
    }
}
