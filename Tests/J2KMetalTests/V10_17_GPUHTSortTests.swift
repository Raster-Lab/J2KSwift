//
// V10_17_GPUHTSortTests.swift
// J2KSwift — v10.17-research
//
// Issue #440 GPU HT entropy redesign — Lever A: divergence-reducing
// descriptor sort. The HT cleanup kernel runs one GPU thread per
// codeblock; a 32-lane SIMD warp finishes only when its slowest lane
// does, so warps holding a mix of low- and high-entropy blocks waste
// lanes. Lever A reorders the descriptors by descending codestream
// length before dispatch so each warp holds similar-cost blocks.
//
//   • testLeverAParity   — sort OFF vs ON bit-identical; lossless
//                          decode bit-exact to the original.
//   • testLeverAPerfAB   — warm A/B: decodeWithGPUHT end-to-end wall
//                          + the gpuHTDispatch stage, OFF vs ON.
//
// Run: swift test -c release --filter V10_17_GPUHTSortTests

import XCTest
import Foundation
import J2KCore
import J2KMetal
@testable import J2KCodec

final class V10_17_GPUHTSortTests: XCTestCase {

    /// Real medical PGM fixtures checked into the repo. The ≥3 MP
    /// fixtures (px_001, dx_002) carry hundreds of HT code-blocks —
    /// where the divergence sort can matter.
    private static let fixtures = [
        "mr_study_002_instance_000100.pgm",
        "ct_study_001_instance_000001.pgm",
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

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    /// 2 warmups + 7 timed `decodeWithGPUHT` runs — returns the median
    /// end-to-end wall and the median `gpuHTDispatch` stage time (ms).
    private func measureHT(_ cs: Data, session: J2KMetalSession)
        async throws -> (wall: Double, htStage: Double) {
        for _ in 0..<2 {
            _ = try await J2KDecoder().decodeWithGPUHT(cs, session: session)
        }
        var walls: [Double] = []
        var stages: [Double] = []
        for _ in 0..<7 {
            J2KDecodeTimings.reset()
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await J2KDecoder().decodeWithGPUHT(cs, session: session)
            let t1 = DispatchTime.now().uptimeNanoseconds
            walls.append(Double(t1 - t0) / 1_000_000.0)
            stages.append(J2KDecodeTimings.snapshot().gpuHTDispatch * 1000.0)
        }
        return (median(walls), median(stages))
    }

    // MARK: - Test 1 — parity

    func testLeverAParity() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal unavailable")
        defer { J2KMetalHTCleanup.divergenceSortEnabled = false }

        for f in Self.fixtures {
            guard let img = loadPGM16(f) else {
                print("V10_17 parity: skipped \(f) (not found)")
                continue
            }
            let cs = try await losslessEncode(img)

            J2KMetalHTCleanup.divergenceSortEnabled = false
            let off = try await J2KDecoder().decodeWithGPUHT(cs)
            J2KMetalHTCleanup.divergenceSortEnabled = true
            let on = try await J2KDecoder().decodeWithGPUHT(cs)
            J2KMetalHTCleanup.divergenceSortEnabled = false

            XCTAssertTrue(imagesEqual(off, on),
                          "\(f): divergence sort changed decodeWithGPUHT output")
            XCTAssertTrue(imagesEqual(img, on),
                          "\(f): sorted decodeWithGPUHT not bit-exact to original")
        }
    }

    // MARK: - Test 2 — warm A/B

    func testLeverAPerfAB() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal unavailable")
        defer { J2KMetalHTCleanup.divergenceSortEnabled = false }

        let session = J2KMetalSession()
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        print("")
        print("=== V10_17 Lever A A/B — GPU HT divergence sort, decodeWithGPUHT, lossless ===")
        print("| Fixture | px | wall OFF | wall ON | Δ wall | htStage OFF | htStage ON | Δ ht |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|")

        for f in Self.fixtures {
            guard let img = loadPGM16(f) else { continue }
            let px = img.width * img.height
            let cs = try await losslessEncode(img)

            J2KMetalHTCleanup.divergenceSortEnabled = false
            let off = try await measureHT(cs, session: session)
            J2KMetalHTCleanup.divergenceSortEnabled = true
            let on = try await measureHT(cs, session: session)
            J2KMetalHTCleanup.divergenceSortEnabled = false

            print(String(format: "| %@ | %d | %.1f | %.1f | %+.1f | %.1f | %.1f | %+.1f |",
                         f, px, off.wall, on.wall, on.wall - off.wall,
                         off.htStage, on.htStage, on.htStage - off.htStage))
        }
        print("=== end V10_17 Lever A A/B ===")
        print("")
    }
}
