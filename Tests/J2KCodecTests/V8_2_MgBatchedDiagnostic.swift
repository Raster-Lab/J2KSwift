// V8_2_MgBatchedDiagnostic.swift
//
// v8.2 — diagnostic for the v7.5.1 mg silent-corruption bug.
// Compares the per-tile decode output (correct) against the
// batched decode output (broken) on the same multi-tile codestream
// and prints the first tile/sample where they diverge. The goal
// is to localise WHERE the corruption starts so the fix can be
// targeted to a specific code path.

#if os(macOS)

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V8_2_MgBatchedDiagnostic: XCTestCase {

    /// Generate a deterministic synthetic 12-bit image at the
    /// dimensions that triggered the v7.2.0 batched-decode bug.
    private func makeTriggerImage(width: Int = 3520, height: Int = 4784) -> J2KImage {
        var data = Data(count: width * height * 2)
        var rng: UInt64 = 0xC0FFEE_DEADBEEF
        data.withUnsafeMutableBytes { rawBuf in
            let p = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(width * height) {
                rng &+= 0x9E37_79B9_7F4A_7C15
                var z = rng
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                let v = UInt16((z ^ (z >> 31)) & 0x0FFF) // 12-bit content
                p[i * 2 + 0] = UInt8(v >> 8)
                p[i * 2 + 1] = UInt8(v & 0xFF)
            }
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: data, sampleByteOrder: .bigEndian)])
    }

    /// Force multi-tile encoding via direct API rather than env var
    /// (env var is read once at process start). Mirrors what the
    /// auto planner does on a 16+ MP image at default config.
    private func encodeMultiTile(_ image: J2KImage) async throws -> Data {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, qualityLayers: 1,
            useHTJ2K: true, useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width,
            imageHeight: image.height,
            decompositionLevels: cfg.decompositionLevels,
            mode: .tiles2x2)
        XCTAssertTrue(layout.isMultiTile,
            "diagnostic must run a multi-tile codestream")
        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        return result.codestream
    }

    /// Find the first sample index where two byte arrays differ,
    /// and how many of the first 64 K samples differ.
    private func firstDivergence(
        _ a: Data, _ b: Data
    ) -> (firstIdx: Int?, divCountFirst64K: Int) {
        XCTAssertEqual(a.count, b.count, "diagnostic decoded byte counts must match")
        var firstIdx: Int? = nil
        var divCount = 0
        let probeWindow = min(a.count, 65536 * 2)   // 64 K 16-bit samples
        for i in 0..<min(a.count, b.count) {
            if a[i] != b[i] {
                if firstIdx == nil { firstIdx = i }
                if i < probeWindow { divCount += 1 }
            }
        }
        return (firstIdx, divCount)
    }

    /// **DIAGNOSTIC** — sweeps several image sizes; for each, encode
    /// multi-tile and decode via per-tile vs batched, compare bytes.
    /// Reports which sizes trigger divergence and where.
    func testDiagnostic_PerTileVsBatched_FirstDivergence() async throws {
        let cases: [(Int, Int, String)] = [
            (3520, 4784, "mg fixture exact"),
            (3520, 4783, "mg minus one row"),
            (3521, 4784, "mg plus one col"),
            (3519, 4784, "mg minus one col"),
            (1760, 4784, "mg single tile-col width"),
            (3520, 2392, "mg single tile-row height"),
            (1760, 2392, "1760×2392 smallest known trigger"),
            (3520, 9568, "mg width × 2× height"),
            // controls — must continue to pass
            (4097, 4097, "just over 2^24 square"),
            (4608, 4608, "21.2 MP square"),
        ]
        for (w, h, label) in cases {
            try await runOneCase(width: w, height: h, label: label)
        }
    }

    private func runOneCase(width: Int, height: Int, label: String) async throws {
        let image = makeTriggerImage(width: width, height: height)
        print("\n[diag] CASE \(label): \(image.width) × \(image.height) = \(image.width * image.height) px")

        let bytes = try await encodeMultiTile(image)
        print("[diag] codestream: \(bytes.count) bytes (multi-tile 2x2)")

        let prev = DecoderPipeline._multiTileBatchedEntropyEnabled
        defer { DecoderPipeline._multiTileBatchedEntropyEnabled = prev }

        // Per-tile path.
        DecoderPipeline._multiTileBatchedEntropyEnabled = false
        let decPerTile = try await J2KDecoder().decode(bytes)
        let perTileMatches = decPerTile.components[0].data == image.components[0].data
        print("[diag] per-tile path: matches source = \(perTileMatches)")

        // Batched path.
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        let decBatched = try await J2KDecoder().decode(bytes)
        let batchedMatches = decBatched.components[0].data == image.components[0].data
        print("[diag] batched path: matches source = \(batchedMatches)")

        // Compare the two decode outputs.
        let bytesA = decPerTile.components[0].data
        let bytesB = decBatched.components[0].data
        let (firstIdx, divCount) = firstDivergence(bytesA, bytesB)
        if let idx = firstIdx {
            let pixelIdx = idx / 2
            let row = pixelIdx / image.width
            let col = pixelIdx % image.width
            // Tile mapping
            let halfW = (image.width + 1) / 2
            let halfH = (image.height + 1) / 2
            let tileCol = col >= halfW ? 1 : 0
            let tileRow = row >= halfH ? 1 : 0
            let tileIdx = tileRow * 2 + tileCol
            print("[diag] FIRST DIVERGE at byte \(idx) (sample \(pixelIdx), row=\(row), col=\(col))")
            print("[diag] tile = (\(tileRow), \(tileCol)) (linear tileIdx=\(tileIdx))")
            print("[diag] divergence count in first 64K samples: \(divCount)")
            let i = idx & ~1
            let aSample = (Int(bytesA[i]) << 8) | Int(bytesA[i + 1])
            let bSample = (Int(bytesB[i]) << 8) | Int(bytesB[i + 1])
            let srcBytes = image.components[0].data
            let sSample = (Int(srcBytes[i]) << 8) | Int(srcBytes[i + 1])
            print("[diag] at sample \(pixelIdx): per-tile=0x\(String(aSample, radix: 16)) (\(aSample)) " +
                "batched=0x\(String(bSample, radix: 16)) (\(bSample)) " +
                "source=0x\(String(sSample, radix: 16)) (\(sSample))")
        } else {
            print("[diag] no divergence — paths agree on this fixture")
        }
    }
}

#endif
