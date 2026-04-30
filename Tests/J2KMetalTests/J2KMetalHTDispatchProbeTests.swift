//
// J2KMetalHTDispatchProbeTests.swift
// J2KSwift
//
// Microbenchmarks the GPU HT decoder prototype's dispatch envelope.
// Answers: at what codeblock count does the GPU layout become viable?
//
// Run:
//   swift test -c release --filter J2KMetalHTDispatchProbeTests 2>&1 \
//     | grep '\[ht-probe\]'
//

import XCTest
import J2KMetal
import J2KCore

final class J2KMetalHTDispatchProbeTests: XCTestCase {

    /// Build a synthetic batch of `blockCount` codeblocks each `width × height`
    /// in size, with `bytesPerBlock` bytes of dummy codestream per block.
    private func makeBatch(
        blockCount: Int,
        width: Int = 64,
        height: Int = 64,
        bytesPerBlock: Int = 256
    ) -> (descriptors: [J2KMetalHTBlockDescriptor],
          codestream: [UInt8],
          outputSampleCount: Int)
    {
        var descriptors: [J2KMetalHTBlockDescriptor] = []
        descriptors.reserveCapacity(blockCount)
        var codestream: [UInt8] = []
        codestream.reserveCapacity(blockCount * bytesPerBlock)
        var dataOffset: UInt32 = 0
        var outputOffset: UInt32 = 0
        let samplesPerBlock = width * height
        var rng: UInt64 = 0xDEAD_BEEF_CAFE_F00D
        for _ in 0..<blockCount {
            descriptors.append(J2KMetalHTBlockDescriptor(
                dataOffset: dataOffset,
                dataLength: UInt32(bytesPerBlock),
                outputOffset: outputOffset,
                width: UInt16(width),
                height: UInt16(height)
            ))
            for _ in 0..<bytesPerBlock {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                codestream.append(UInt8((rng >> 32) & 0xFF))
            }
            dataOffset += UInt32(bytesPerBlock)
            outputOffset += UInt32(samplesPerBlock)
        }
        return (descriptors, codestream, blockCount * samplesPerBlock)
    }

    /// Reference CPU implementation of the same per-block work the
    /// Metal kernel does, so we can measure the cross-over point.
    private func runCPU(
        descriptors: [J2KMetalHTBlockDescriptor],
        codestream: [UInt8],
        outputSampleCount: Int
    ) -> [Int32] {
        var output = [Int32](repeating: 0, count: outputSampleCount)
        DispatchQueue.concurrentPerform(iterations: descriptors.count) { idx in
            let desc = descriptors[idx]
            var checksum: UInt32 = 0
            let base = Int(desc.dataOffset)
            for i in 0..<Int(desc.dataLength) {
                checksum = checksum &* 1103515245 &+ UInt32(codestream[base + i])
            }
            let v = Int32(checksum & 0x0FFF)
            let sampleCount = Int(desc.width) * Int(desc.height)
            let outBase = Int(desc.outputOffset)
            output.withUnsafeMutableBufferPointer { buf in
                for i in 0..<sampleCount {
                    buf[outBase + i] = (i & 1) == 0 ? v : -v
                }
            }
        }
        return output
    }

    private func runOnce(blockCount: Int) async throws
        -> (cpuMs: Double, gpuWallMs: Double, gpuKernelMs: Double, equal: Bool)
    {
        let (desc, cs, samples) = makeBatch(blockCount: blockCount)
        let probe = J2KMetalHTDispatchProbe()

        // Warm-up
        _ = try await probe.run(descriptors: desc, codestreamPool: cs, outputSampleCount: samples)
        _ = runCPU(descriptors: desc, codestream: cs, outputSampleCount: samples)

        // Time
        let cpuStart = DispatchTime.now()
        let cpuOut = runCPU(descriptors: desc, codestream: cs, outputSampleCount: samples)
        let cpuEnd = DispatchTime.now()

        let (gpuOut, stats) = try await probe.run(
            descriptors: desc, codestreamPool: cs, outputSampleCount: samples)

        let cpuMs = Double(cpuEnd.uptimeNanoseconds - cpuStart.uptimeNanoseconds) / 1_000_000.0
        let gpuWallMs = stats.wallClockSeconds * 1000.0
        let gpuKernelMs = stats.gpuKernelSeconds * 1000.0
        return (cpuMs, gpuWallMs, gpuKernelMs, cpuOut == gpuOut)
    }

    /// Reports per-block-count timings. Always passes (probe is for
    /// telemetry, not gate); the CPU vs GPU equality assertion proves
    /// the data plumbing is correct.
    func testDispatchEnvelopeAcrossBlockCounts() async throws {
        try XCTSkipUnless(J2KMetalHTDispatchProbe.isAvailable, "Metal not available")

        let counts = [1, 4, 16, 64, 256, 777, 1024]
        print("[ht-probe] blockCount   cpuMs   gpuWallMs   gpuKernelMs   speedup(wall)   equal")
        for n in counts {
            let r = try await runOnce(blockCount: n)
            let speedup = r.cpuMs / max(r.gpuWallMs, 0.001)
            print(String(
                format: "[ht-probe] %10d  %7.3f    %8.3f      %8.3f         %5.2fx        %@",
                n, r.cpuMs, r.gpuWallMs, r.gpuKernelMs, speedup, r.equal ? "yes" : "NO"
            ))
            XCTAssertTrue(r.equal, "GPU output must match CPU at blockCount=\(n)")
        }
    }

    /// Tiny smoke-test: one block, prints whether the GPU pipeline
    /// produces any output at all.
    func testSmokeOneBlock() async throws {
        try XCTSkipUnless(J2KMetalHTDispatchProbe.isAvailable, "Metal not available")
        print("[ht-smoke] starting blockCount=1")
        let r = try await runOnce(blockCount: 1)
        print(String(format: "[ht-smoke] cpu=%.3fms gpuWall=%.3fms gpuKernel=%.3fms equal=%@",
                     r.cpuMs, r.gpuWallMs, r.gpuKernelMs, r.equal ? "yes" : "NO"))
        XCTAssertTrue(r.equal)
    }

    /// Even tinier than smoke — runs the probe with one trivially
    /// small block (4×4, 4 bytes). If this hangs, the bug is inside
    /// `J2KMetalHTDispatchProbe.run`; otherwise the previous hangs
    /// were in the larger payload.
    func testTinyOneBlock() async throws {
        try XCTSkipUnless(J2KMetalHTDispatchProbe.isAvailable, "Metal not available")
        // Use FileHandle for unbuffered output — xctest's stdout under
        // swift-test pipe gets fully buffered with `print()`.
        let stderr = FileHandle.standardError
        func say(_ s: String) { stderr.write(Data((s + "\n").utf8)) }
        say("[ht-tiny] start")
        let desc = [J2KMetalHTBlockDescriptor(
            dataOffset: 0, dataLength: 4, outputOffset: 0,
            width: 4, height: 4
        )]
        let cs: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        say("[ht-tiny] creating probe")
        let probe = J2KMetalHTDispatchProbe()
        say("[ht-tiny] calling run")
        let (out, stats) = try await probe.run(
            descriptors: desc, codestreamPool: cs, outputSampleCount: 16
        )
        say("[ht-tiny] done: \(out.count) samples, gpuKernel=\(stats.gpuKernelSeconds * 1000) ms")
        XCTAssertEqual(out.count, 16)
    }

    /// Even tinier — exercises only the shader load path. If this hangs
    /// the issue is in pipeline creation; if it returns the issue is
    /// in the GPU run.
    func testShaderLoadOnly() async throws {
        try XCTSkipUnless(J2KMetalHTDispatchProbe.isAvailable, "Metal not available")
        print("[ht-load] requesting probe shader pipeline")
        let dev = J2KMetalDevice()
        try await dev.initialize()
        let lib = J2KMetalShaderLibrary()
        let q = try await dev.commandQueue()
        try await lib.loadShaders(device: q.device)
        let pipeline = try await lib.computePipeline(for: .htDispatchProbe)
        print("[ht-load] pipeline ok: \(pipeline.maxTotalThreadsPerThreadgroup) max threads/group")
    }
}
