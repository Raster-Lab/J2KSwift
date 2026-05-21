//
// V10_16_GPUDecodeFusedIDWTTests.swift
// J2KSwift — v10.16-research
//
// Issue #440: the GPU decode paths underperform CPU/Kakadu on mid/large
// medical images. Lever 1 routes `decodeGPU`'s inverse DWT through the
// single-command-buffer `inverse2DInt32MultiLevelFused` dispatch instead
// of the per-level `inverse2DInt32` path (which reads back to a CPU
// array between every decomposition level).
//
// Two tests:
//   • testLever1Parity   — flag OFF vs ON must be bit-identical, and a
//                          lossless decode must reproduce the original.
//   • testLever1PerfAB    — warm A/B: cpu / decodeGPU OFF / decodeGPU ON
//                          / decodeWithGPUHT, lossless corpus.
//
// Run: swift test -c release --filter V10_16_GPUDecodeFusedIDWTTests

import XCTest
import Foundation
import J2KCore
@testable import J2KCodec

final class V10_16_GPUDecodeFusedIDWTTests: XCTestCase {

    /// Real medical PGM fixtures checked into the repo, spanning the
    /// 32 K–6.4 MP range — the band `recommendedDecodeAPI` routes to
    /// `decodeGPU`.
    private static let fixtures = [
        "mr_study_002_instance_000100.pgm",
        "ct_study_001_instance_000001.pgm",
        "ct_study_003_instance_000050.pgm",
        "mr_study_001_instance_000001.pgm",
        "xa_study_001_instance_000001.pgm",
        "px_study_001_instance_000001.pgm",
        "dx_study_002_instance_000001.pgm",
    ]

    // MARK: - Fixture loading

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Tests/Fixtures/CrossCodec/\(filename)")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count > 2, bytes[0] == 0x50, bytes[1] == 0x35 else { return nil }
        var i = 2
        func skip() {
            while i < bytes.count {
                let c = bytes[i]
                if c == 0x23 { while i < bytes.count, bytes[i] != 0x0A { i += 1 } }
                else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 }
                else { break }
            }
        }
        func readInt() -> Int? {
            skip()
            var v = 0, any = false
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                v = v * 10 + Int(bytes[i] - 0x30); i += 1; any = true
            }
            return any ? v : nil
        }
        guard let w = readInt(), let h = readInt(), let maxv = readInt(),
              w > 0, h > 0, maxv > 255 else { return nil }
        i += 1
        let need = w * h * 2
        guard i + need <= bytes.count else { return nil }
        let raster = Data(bytes[i..<(i + need)])
        let bitDepth = Int(ceil(log2(Double(maxv + 1))))
        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: w, height: h, subsamplingX: 1, subsamplingY: 1,
            data: raster, sampleByteOrder: .bigEndian)
        return J2KImage(width: w, height: h, components: [comp])
    }

    private func losslessEncode(_ img: J2KImage) async throws -> Data {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
        return try await J2KEncoder(encodingConfiguration: cfg).encode(img)
    }

    private func imagesEqual(_ a: J2KImage, _ b: J2KImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              a.components.count == b.components.count else { return false }
        for (ca, cb) in zip(a.components, b.components) where ca.data != cb.data {
            return false
        }
        return true
    }

    private func median(_ xs: [Double]) -> Double {
        xs.sorted()[xs.count / 2]
    }

    /// 2 untimed warmups + 7 timed runs, median ms (DispatchTime clock).
    private func measure(_ body: () async throws -> Void) async rethrows -> Double {
        for _ in 0..<2 { try await body() }
        var samples: [Double] = []
        for _ in 0..<7 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            try await body()
            let t1 = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(t1 - t0) / 1_000_000.0)
        }
        return median(samples)
    }

    // MARK: - Test 1 — parity

    func testLever1Parity() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal unavailable")
        defer { DecoderPipeline._gpuDecodeFusedIDWTEnabled = false }

        for f in Self.fixtures {
            guard let img = loadPGM16(f) else {
                print("V10_16 parity: skipped \(f) (not found)")
                continue
            }
            let cs = try await losslessEncode(img)

            DecoderPipeline._gpuDecodeFusedIDWTEnabled = false
            let off = try await J2KDecoder().decodeGPU(cs)
            DecoderPipeline._gpuDecodeFusedIDWTEnabled = true
            let on = try await J2KDecoder().decodeGPU(cs)
            DecoderPipeline._gpuDecodeFusedIDWTEnabled = false

            XCTAssertTrue(imagesEqual(off, on),
                          "\(f): Lever 1 changed decodeGPU output (not bit-exact)")
            XCTAssertTrue(imagesEqual(img, on),
                          "\(f): lossless decodeGPU with Lever 1 not bit-exact to original")
        }
    }

    // MARK: - Test 2 — warm A/B

    func testLever1PerfAB() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal unavailable")
        defer { DecoderPipeline._gpuDecodeFusedIDWTEnabled = false }

        let session = J2KMetalSession()
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        print("")
        print("=== V10_16 Lever 1 A/B — lossless HT, warm in-process, median of 7 ===")
        print("| Fixture | px | CPU ms | decodeGPU OFF | decodeGPU ON | Δ ms | decodeWithGPUHT |")
        print("|---|---:|---:|---:|---:|---:|---:|")

        for f in Self.fixtures {
            guard let img = loadPGM16(f) else { continue }
            let px = img.width * img.height
            let cs = try await losslessEncode(img)

            let cpu = try await measure { _ = try await J2KDecoder().decode(cs) }

            DecoderPipeline._gpuDecodeFusedIDWTEnabled = false
            let gpuOff = try await measure {
                _ = try await J2KDecoder().decodeGPU(cs, session: session)
            }
            DecoderPipeline._gpuDecodeFusedIDWTEnabled = true
            let gpuOn = try await measure {
                _ = try await J2KDecoder().decodeGPU(cs, session: session)
            }
            DecoderPipeline._gpuDecodeFusedIDWTEnabled = false

            let ht = try await measure {
                _ = try await J2KDecoder().decodeWithGPUHT(cs, session: session)
            }

            let delta = gpuOn - gpuOff
            print(String(format: "| %@ | %d | %.1f | %.1f | %.1f | %+.1f | %.1f |",
                         f, px, cpu, gpuOff, gpuOn, delta, ht))
        }
        print("=== end V10_16 Lever 1 A/B ===")
        print("")
    }
}
