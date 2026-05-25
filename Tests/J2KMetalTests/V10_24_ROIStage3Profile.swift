// V10_24_ROIStage3Profile.swift
//
// v10.24-research Phase 0 — confirm iDWT dominates the remaining
// single-tile ROI decode time after entropy-skip. If iDWT < 40%,
// the v10.15.0 plan (Stage 3 windowed iDWT) needs re-targeting;
// if ≥ 60%, Stage 3 is the right target with the expected magnitude
// of win.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_24_ROIStage3Profile: XCTestCase {

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Stage breakdown for `decodeRegion(.direct)` on DX 2800×2288
    /// single-tile, 256² centre region. Used by v10.24 Phase 0 to
    /// validate that iDWT dominates the remaining ~22 ms (after
    /// entropy-skip) — confirming Stage 3 windowed iDWT is the right
    /// next-arc target.
    func testStage3Profile_DX2800_256region() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()
        let region = J2KRegion(x: image.width / 2 - 128,
                               y: image.height / 2 - 128,
                               width: 256, height: 256)

        // Warm-up — first call pays Metal-init + JIT.
        _ = try await decoder.decodeRegion(
            codestream, options: J2KROIDecodingOptions(region: region, strategy: .direct))

        let trials = 7
        J2KDecodeTimings.reset()
        var wallMs = 0.0
        for _ in 0..<trials {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decoder.decodeRegion(
                codestream, options: J2KROIDecodingOptions(region: region, strategy: .direct))
            wallMs += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        }
        let snap = J2KDecodeTimings.snapshot()
        // Convert accumulators (totals across `trials` runs) to per-call ms.
        func ms(_ t: TimeInterval) -> Double { (t / Double(trials)) * 1000 }
        let avgWall = wallMs / Double(trials)
        print(String(format: """

        V10_24 Phase 0 — DX 2800×2288 single-tile, 256² centre ROI, n=%d trials, release mode

        Per-call wall: %.2f ms
        Stage breakdown (per-call, accumulator-derived):
          extractTileData :  %5.2f ms  (%.1f%%)
          entropyDecoding :  %5.2f ms  (%.1f%%)
            └─ gpuHTDispatch :  %5.2f ms
            └─ regroup       :  %5.2f ms
          dequantization  :  %5.2f ms  (%.1f%%)
          iDWT            :  %5.2f ms  (%.1f%%)
          inverseColour   :  %5.2f ms  (%.1f%%)
          dcLevelUnshift  :  %5.2f ms  (%.1f%%)
          reconstructImage:  %5.2f ms  (%.1f%%)
          ────────────────────────────────────
          stages-sum      :  %5.2f ms

        v10.24 Stage 3 target = iDWT row above. Expected reduction: ~67× theoretical
        (256² region + halo at each level vs full 2800×2288 iDWT). Realistic
        end-to-end: %.1f ms → %.1f ms ≈ %.2fx faster after Stage 3.
        """,
            trials, avgWall,
            ms(snap.extractTileData), ms(snap.extractTileData) / avgWall * 100,
            ms(snap.entropyDecoding), ms(snap.entropyDecoding) / avgWall * 100,
            ms(snap.gpuHTDispatch),
            ms(snap.entropyRegroup),
            ms(snap.dequantization), ms(snap.dequantization) / avgWall * 100,
            ms(snap.inverseWaveletTransform), ms(snap.inverseWaveletTransform) / avgWall * 100,
            ms(snap.inverseColorTransform), ms(snap.inverseColorTransform) / avgWall * 100,
            ms(snap.dcLevelUnshift), ms(snap.dcLevelUnshift) / avgWall * 100,
            ms(snap.reconstructImage), ms(snap.reconstructImage) / avgWall * 100,
            ms(snap.total),
            avgWall, avgWall - ms(snap.inverseWaveletTransform) * 0.95,
            avgWall / (avgWall - ms(snap.inverseWaveletTransform) * 0.95)))

        // Phase 0 sanity gate: don't enforce, just print. Phase 1
        // proceeds only if iDWT % is ≥ 40% (per the v10.15.0 plan).
    }
}
#endif
