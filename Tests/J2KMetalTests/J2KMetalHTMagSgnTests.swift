//
// J2KMetalHTMagSgnTests.swift
// J2KSwift
//
// Bit-exact validation of the GPU MagSgn decoder (phase 1) against
// the CPU `HTMagSgnDecoderConformant`. Same input bytes + widths
// must produce the same UInt32 outputs.
//

import XCTest
import J2KMetal
import J2KCore
import J2KCodec

final class J2KMetalHTMagSgnTests: XCTestCase {

    private static let stderr = FileHandle.standardError
    private static func say(_ s: String) {
        stderr.write(Data((s + "\n").utf8))
    }

    /// Build a deterministic stream of `(value, bits)` pairs and the
    /// corresponding encoded byte array via `HTMagSgnCoderConformant.encodeBits`.
    /// Returns the encoded bytes, the per-sample widths, and the
    /// expected decoded values (for the CPU baseline cross-check).
    private func makeStream(sampleCount: Int, seed: UInt64)
        -> (bytes: [UInt8], widths: [UInt8], expected: [UInt32])
    {
        var rng = seed | 1
        var items: [(value: UInt32, bits: Int)] = []
        items.reserveCapacity(sampleCount)
        var widths: [UInt8] = []
        widths.reserveCapacity(sampleCount)
        var expected: [UInt32] = []
        expected.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            // Bit width 1..16 — covers single-bit reads up through
            // moderate-precision magnitudes the cleanup pass produces.
            let bits = Int(((rng >> 32) % 16) + 1)
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let mask: UInt32 = bits >= 32 ? ~UInt32(0) : ((UInt32(1) << bits) - 1)
            let value = UInt32((rng >> 32) & UInt64(mask))
            items.append((value, bits))
            widths.append(UInt8(bits))
            expected.append(value)
        }
        let bytes = HTMagSgnCoderConformant.encodeBits(items)
        return (bytes, widths, expected)
    }

    /// Single block, small sample count — proves end-to-end correctness.
    func testSingleBlockBitExact() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgn.isAvailable, "Metal not available")
        let sampleCount = 64
        let (bytes, widths, expected) = makeStream(
            sampleCount: sampleCount, seed: 0xCAFE_BEEF)

        // CPU baseline — the spec we want GPU to match.
        let cpu = HTMagSgnCoderConformant.decodeBits(
            bytes, widths: widths.map { Int($0) })
        XCTAssertEqual(cpu, expected, "CPU baseline mismatch — test bug")

        // GPU
        let desc = J2KMetalHTMagSgnBlockDescriptor(
            dataOffset: 0, dataLength: UInt32(bytes.count),
            widthsOffset: 0, outputOffset: 0,
            sampleCount: UInt32(sampleCount)
        )
        let gpu = J2KMetalHTMagSgn()
        let (out, stats) = try await gpu.run(
            descriptors: [desc],
            codestreamPool: bytes,
            widthsPool: widths,
            outputSampleCount: sampleCount
        )
        Self.say("[ht-magsgn] 1 block × \(sampleCount) samples: " +
                 "wall=\(String(format: "%.3f", stats.wallClockSeconds * 1000))ms " +
                 "kernel=\(String(format: "%.3f", stats.gpuKernelSeconds * 1000))ms")
        XCTAssertEqual(out, expected, "GPU MagSgn output must equal CPU")
    }

    /// Many blocks, varied sample counts and widths — exercises the
    /// batched-dispatch path the eventual real decoder will use.
    func testManyBlocksBitExact() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgn.isAvailable, "Metal not available")

        let blockCount = 256
        let perBlockSamples = 256  // 64 KB output total
        var descriptors: [J2KMetalHTMagSgnBlockDescriptor] = []
        descriptors.reserveCapacity(blockCount)
        var codestream: [UInt8] = []
        var widths: [UInt8] = []
        var expected: [UInt32] = []
        var dataOffset: UInt32 = 0
        var widthOutOffset: UInt32 = 0

        for b in 0..<blockCount {
            let (bytes, w, e) = makeStream(
                sampleCount: perBlockSamples,
                seed: UInt64(b) &* 0x9E37_79B9_7F4A_7C15)
            descriptors.append(J2KMetalHTMagSgnBlockDescriptor(
                dataOffset: dataOffset,
                dataLength: UInt32(bytes.count),
                widthsOffset: widthOutOffset,
                outputOffset: widthOutOffset,
                sampleCount: UInt32(perBlockSamples)
            ))
            codestream.append(contentsOf: bytes)
            widths.append(contentsOf: w)
            expected.append(contentsOf: e)
            dataOffset += UInt32(bytes.count)
            widthOutOffset += UInt32(perBlockSamples)
        }

        let totalSamples = blockCount * perBlockSamples
        let gpu = J2KMetalHTMagSgn()
        let (out, stats) = try await gpu.run(
            descriptors: descriptors,
            codestreamPool: codestream,
            widthsPool: widths,
            outputSampleCount: totalSamples
        )
        Self.say("[ht-magsgn] \(blockCount) blocks × \(perBlockSamples) samples: " +
                 "wall=\(String(format: "%.3f", stats.wallClockSeconds * 1000))ms " +
                 "kernel=\(String(format: "%.3f", stats.gpuKernelSeconds * 1000))ms")
        XCTAssertEqual(out.count, expected.count)
        XCTAssertEqual(out, expected)
    }

    /// Phase-1 speedup measurement: same workload on CPU and GPU,
    /// reports the ratio.
    func testGPUvsCPUSpeedup() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgn.isAvailable, "Metal not available")

        let blockCount = 777          // matches the 1024-RGB cross-matrix
        let perBlockSamples = 4096    // 64×64 codeblock samples
        var descriptors: [J2KMetalHTMagSgnBlockDescriptor] = []
        descriptors.reserveCapacity(blockCount)
        var codestream: [UInt8] = []
        var widths: [UInt8] = []
        var dataOffset: UInt32 = 0
        var sampleOffset: UInt32 = 0

        for b in 0..<blockCount {
            let (bytes, w, _) = makeStream(
                sampleCount: perBlockSamples,
                seed: UInt64(b) &* 0xA5A5_A5A5_A5A5_A5A5)
            descriptors.append(J2KMetalHTMagSgnBlockDescriptor(
                dataOffset: dataOffset,
                dataLength: UInt32(bytes.count),
                widthsOffset: sampleOffset,
                outputOffset: sampleOffset,
                sampleCount: UInt32(perBlockSamples)
            ))
            codestream.append(contentsOf: bytes)
            widths.append(contentsOf: w)
            dataOffset += UInt32(bytes.count)
            sampleOffset += UInt32(perBlockSamples)
        }
        let totalSamples = blockCount * perBlockSamples

        // CPU baseline: per-block decoder loop, parallel via concurrentPerform.
        // Pre-allocate per-block intermediate buffers to avoid races.
        let cpuStart = DispatchTime.now()
        var cpuOutput = [UInt32](repeating: 0, count: totalSamples)
        cpuOutput.withUnsafeMutableBufferPointer { outBuf in
            DispatchQueue.concurrentPerform(iterations: blockCount) { i in
                let desc = descriptors[i]
                let blockBytes = Array(codestream[
                    Int(desc.dataOffset)..<Int(desc.dataOffset + desc.dataLength)])
                let blockWidths = Array(widths[
                    Int(desc.widthsOffset)..<Int(desc.widthsOffset + desc.sampleCount)]
                ).map { Int($0) }
                let dec = HTMagSgnCoderConformant.decodeBits(blockBytes, widths: blockWidths)
                let outBase = Int(desc.outputOffset)
                for j in 0..<dec.count {
                    outBuf[outBase + j] = dec[j]
                }
            }
        }
        let cpuEnd = DispatchTime.now()
        let cpuMs = Double(cpuEnd.uptimeNanoseconds - cpuStart.uptimeNanoseconds) / 1_000_000.0

        // GPU
        let (gpuOut, stats) = try await J2KMetalHTMagSgn().run(
            descriptors: descriptors,
            codestreamPool: codestream,
            widthsPool: widths,
            outputSampleCount: totalSamples
        )
        XCTAssertEqual(gpuOut, cpuOutput, "GPU output must match CPU baseline")

        let gpuMs = stats.wallClockSeconds * 1000
        let kernelMs = stats.gpuKernelSeconds * 1000
        let speedup = cpuMs / max(gpuMs, 0.001)
        Self.say(String(format:
            "[ht-magsgn] %d blocks × %d samples: cpu=%.2fms gpu_wall=%.2fms gpu_kernel=%.2fms speedup=%.2fx",
            blockCount, perBlockSamples, cpuMs, gpuMs, kernelMs, speedup))
    }

    /// Edge cases — 1-bit reads, 16-bit reads, the 0xFF stuffing path.
    func testEdgeCases() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgn.isAvailable, "Metal not available")

        // Two cases that hit the FF-stuff refill path: stream that
        // contains 0xFF by construction (encode `0xFF`-equivalent data),
        // and a stream where decoding runs past EOF (post-EOF padding
        // = 0xFF per the spec).
        // Each entry's `value` must fit in `bits` bits — the encoder
        // doesn't mask, so feeding wider values gives back the masked
        // version on decode and the test would falsely fail.
        let mask16: UInt32 = 0xFFFF
        let cases: [(name: String, items: [(value: UInt32, bits: Int)])] = [
            ("1-bit-only",  Array(repeating: (UInt32(1), 1), count: 32)),
            ("16-bit-mix",  (0..<16).map { (UInt32($0) &* 0x1234 & mask16, 16) }),
            ("ff-stuff",    Array(repeating: (UInt32(0x7F), 7), count: 16)),
        ]

        for (name, items) in cases {
            let bytes = HTMagSgnCoderConformant.encodeBits(items)
            let widths = items.map { UInt8($0.bits) }
            let expected = items.map { $0.value }

            let cpu = HTMagSgnCoderConformant.decodeBits(
                bytes, widths: items.map { $0.bits })
            XCTAssertEqual(cpu, expected, "[\(name)] CPU baseline mismatch")

            let desc = J2KMetalHTMagSgnBlockDescriptor(
                dataOffset: 0, dataLength: UInt32(bytes.count),
                widthsOffset: 0, outputOffset: 0,
                sampleCount: UInt32(items.count)
            )
            let (out, _) = try await J2KMetalHTMagSgn().run(
                descriptors: [desc],
                codestreamPool: bytes,
                widthsPool: widths,
                outputSampleCount: items.count
            )
            XCTAssertEqual(out, expected, "[\(name)] GPU output mismatch")
        }
    }
}
