// J2KGPULossy97DivergenceTests.swift
// v5.20.0 medical-grade gate — verify GPU and CPU 9/7 lossy decode
// produce identical output.
//
// Original observation (v5.20.0 investigation): GPU 9/7 lossy decode
// diverged from CPU by max ~45000 / avg ~19000 in 16-bit space — far
// beyond Float-vs-Double precision tolerance. Bisection confirmed the
// bug is in GPU IDWT (decodeGPU == decodeWithGPUHT divergence;
// decodeWithGPUHT internally calls decodeGPU's IDWT path).
//
// v5.20.0 fix: gate `applyInverseWaveletTransformGPU` to fall back to
// the CPU IDWT path for `.irreversible97`. After the gate, all three
// decode paths (decode, decodeGPU, decodeWithGPUHT) produce identical
// output for 9/7 lossy.
//
// This test asserts that the gate is in place. If a future change
// removes the gate without fixing the underlying GPU IDWT kernel, the
// test will fail loudly. Once the GPU IDWT bug is properly fixed,
// the assertion threshold can be tightened to a Float-precision-
// reasonable bound (e.g. max diff < 32 LSB at 16-bit).

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KGPULossy97DivergenceTests: XCTestCase {

    private func loadCT() throws -> J2KImage {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm")
        let data = try Data(contentsOf: fixture)
        // Parse P5 16-bit PGM
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])
    }

    private func maxAbsDiff16(_ a: Data, _ b: Data) -> (maxDiff: Int, sumDiff: Int64, count: Int) {
        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)
        let n = min(aBytes.count, bBytes.count) / 2
        var maxDiff = 0
        var sumDiff: Int64 = 0
        for i in 0..<n {
            let av = Int(aBytes[i*2]) * 256 + Int(aBytes[i*2 + 1])
            let bv = Int(bBytes[i*2]) * 256 + Int(bBytes[i*2 + 1])
            let d = abs(av - bv)
            if d > maxDiff { maxDiff = d }
            sumDiff += Int64(d)
        }
        return (maxDiff, sumDiff, n)
    }

    /// Bisect the divergence: encode once, decode three ways, compare.
    func testBisectDecodePaths() async throws {
        let img = try loadCT()
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: 4.0)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
        print("Encoded \(encoded.count) bytes from \(img.width)×\(img.height) 16-bit lossy 9/7 @ 4 bpp")

        let decoder = J2KDecoder()
        let cpuDec   = try await decoder.decode(encoded)
        let gpuDec   = try await decoder.decodeGPU(encoded)
        let gpuHTDec = try await decoder.decodeWithGPUHT(encoded)

        let cpuVsOrig    = maxAbsDiff16(img.components[0].data, cpuDec.components[0].data)
        let gpuVsCpu     = maxAbsDiff16(cpuDec.components[0].data, gpuDec.components[0].data)
        let gpuHTVsCpu   = maxAbsDiff16(cpuDec.components[0].data, gpuHTDec.components[0].data)
        let gpuVsOrig    = maxAbsDiff16(img.components[0].data, gpuDec.components[0].data)
        let gpuHTVsOrig  = maxAbsDiff16(img.components[0].data, gpuHTDec.components[0].data)

        print("=== v5.20.0 GPU 9/7 lossy decode bisection ===")
        print("CPU       vs original:  max=\(cpuVsOrig.maxDiff) avg=\(cpuVsOrig.sumDiff / Int64(cpuVsOrig.count))")
        print("GPU       vs CPU:       max=\(gpuVsCpu.maxDiff) avg=\(gpuVsCpu.sumDiff / Int64(max(1, gpuVsCpu.count)))")
        print("GPU       vs original:  max=\(gpuVsOrig.maxDiff) avg=\(gpuVsOrig.sumDiff / Int64(max(1, gpuVsOrig.count)))")
        print("GPU-HT    vs CPU:       max=\(gpuHTVsCpu.maxDiff) avg=\(gpuHTVsCpu.sumDiff / Int64(max(1, gpuHTVsCpu.count)))")
        print("GPU-HT    vs original:  max=\(gpuHTVsOrig.maxDiff) avg=\(gpuHTVsOrig.sumDiff / Int64(max(1, gpuHTVsOrig.count)))")

        // After v5.20.0's gate, GPU/GPU-HT for 9/7 lossy should fall
        // back to CPU IDWT, producing IDENTICAL output. Strict gate:
        // max abs diff must be 0. If a future change removes the gate
        // without fixing the underlying GPU IDWT kernel, this test
        // fires.
        XCTAssertEqual(gpuVsCpu.maxDiff, 0,
            "decodeGPU must match decode for 9/7 lossy; v5.20.0 gate forces CPU IDWT for irreversible97. Got max=\(gpuVsCpu.maxDiff).")
        XCTAssertEqual(gpuHTVsCpu.maxDiff, 0,
            "decodeWithGPUHT must match decode for 9/7 lossy; v5.20.0 gate forces CPU IDWT for irreversible97. Got max=\(gpuHTVsCpu.maxDiff).")
    }
}
