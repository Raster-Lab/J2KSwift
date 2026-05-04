// J2KGPULossy97DivergenceTests.swift
// v5.21.0 medical-grade gate — verify GPU and CPU 9/7 lossy decode
// agree within Float-precision tolerance.
//
// Original observation (v5.20.0 investigation): GPU 9/7 lossy decode
// diverged from CPU by max ~45000 / avg ~19000 in 16-bit space — far
// beyond Float-vs-Double precision tolerance. Bisection confirmed the
// bug was in GPU IDWT (decodeGPU == decodeWithGPUHT divergence).
//
// Root cause (v5.21.0): J2KMetalDWT module's 9/7 forward and inverse
// CPU+GPU paths used the OPPOSITE scaling direction from J2KCodec's
// J2KDWT1D reference. ISO/IEC 15444-1 Annex F.4.1.1 specifies
// `lowpass /= K, highpass *= K` in forward; J2KMetalDWT had it
// inverted. The module was self-consistent — round-tripping within
// J2KMetalDWT worked — but produced K⁴-scaled garbage when paired
// with J2KCodec-encoded codestreams. The encoder is the canonical
// reference; J2KMetalDWT was the outlier.
//
// v5.21.0 fix: swap the scaling lines in J2KMetalDWT's
// inverse1DCPU97, forward1DCPU97, and the corresponding GPU kernels
// in J2KShaders.metal + J2KMetalShaderLibrary's embedded source.
//
// Post-fix CPU vs GPU 9/7 lossy decode max abs diff ≈ 1 LSB at
// 16-bit (Float-precision residual), avg = 0. This test asserts
// the divergence stays within medical-grade tolerance. Pre-fix it
// was max=45000+; post-fix it's max=1.

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

        // After v5.21.0's scaling fix, GPU 9/7 IDWT matches the CPU
        // reference within Float-precision tolerance. Tolerance is
        // 4 LSB at 16-bit — observed residual is typically 1 LSB,
        // 4 leaves headroom for Float-vs-Double precision drift on
        // higher-decomp-level inputs. Average diff should be ≪ 1.
        XCTAssertLessThanOrEqual(gpuVsCpu.maxDiff, 4,
            "decodeGPU must match decode for 9/7 lossy within 4 LSB (Float-precision); got max=\(gpuVsCpu.maxDiff).")
        XCTAssertLessThanOrEqual(gpuHTVsCpu.maxDiff, 4,
            "decodeWithGPUHT must match decode for 9/7 lossy within 4 LSB (Float-precision); got max=\(gpuHTVsCpu.maxDiff).")
        // Average should be essentially zero (sub-LSB).
        let avgGpuVsCpu = Double(gpuVsCpu.sumDiff) / Double(gpuVsCpu.count)
        XCTAssertLessThan(avgGpuVsCpu, 0.5,
            "average GPU vs CPU diff exceeds Float-precision tolerance: \(avgGpuVsCpu)")
    }
}
