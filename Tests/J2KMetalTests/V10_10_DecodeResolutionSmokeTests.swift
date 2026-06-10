// V10_10_DecodeResolutionSmokeTests.swift
//
// v10.10-research Phase 1 — smoke test for the new `decodeResolution`
// implementation (replaces v10.3.0 era `notImplemented` stub).
//
// v10.25 — strengthened after the multi-tile partial-resolution
// corruption shipped undetected: the original tests asserted only
// `image.width/height`, which the broken path reported correctly
// while carrying full-image-sized component buffers full of
// mis-composited junk. Every resolution-pyramid assertion now checks
//   1. image AND component dimensions at each level,
//   2. component.data.count == expectedW × expectedH × bytesPerSample
//      (catches reduced-dims-header-over-full-size-buffer corruption),
//   3. content correlation against a block-mean downsample of the
//      full decode (catches mis-composited pixels), and
//   4. byte-identity with `decode()` at level N,
// on BOTH single-tile (CT 512×512) and multi-tile fixtures
// (DX 2800×2288 → 4x4 under default `.auto`, MG 3518×4784 → 2x2).
//
// Multi-tile fixtures additionally get the strongest oracle: at every
// partial level the multi-tile output must agree (corr > 0.99) with a
// single-tile encode of the SAME pixels decoded through the proven
// v10.5.0 single-tile partial path. Block-mean correlation alone
// can't be thresholded tightly — a 5-deep 5/3 LL pyramid is not a box
// filter, so even the correct path measures 0.86-0.95 on noisy CT
// thumbnails — but the single-vs-multi-tile parity check pins the
// composite itself.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_10_DecodeResolutionSmokeTests: XCTestCase {

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

    // MARK: - Helpers

    /// Component samples as Double. Decoder output and the PGM
    /// fixtures both carry 16-bit samples big-endian.
    private func samples(_ comp: J2KComponent) -> [Double] {
        let bytesPerSample = comp.bitDepth <= 8 ? 1 : 2
        let n = comp.data.count / bytesPerSample
        var out = [Double](repeating: 0, count: n)
        comp.data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            if bytesPerSample == 1 {
                for i in 0..<n { out[i] = Double(p[i]) }
            } else {
                for i in 0..<n {
                    out[i] = Double((UInt16(p[2 * i]) << 8) | UInt16(p[2 * i + 1]))
                }
            }
        }
        return out
    }

    private func pearsonCorrelation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -2 }
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n
        let mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count {
            let x = a[i] - ma, y = b[i] - mb
            num += x * y; da += x * x; db += y * y
        }
        let den = (da * db).squareRoot()
        return den > 0 ? num / den : -2
    }

    /// Full resolution-pyramid assertion: dims, component dims,
    /// component data size, content correlation vs block-mean of the
    /// full decode at every partial level, byte-identity at level N.
    private func assertResolutionPyramid(
        codestream: Data,
        levels N: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)
        let W = full.width, H = full.height

        for level in 0...N {
            let f = 1 << (N - level)
            let expectW = (W + f - 1) / f
            let expectH = (H + f - 1) / f
            let out = try await decoder.decodeResolution(
                codestream,
                options: J2KResolutionDecodingOptions(level: level))

            XCTAssertEqual(out.width, expectW,
                "[\(label) level \(level)] image width", file: file, line: line)
            XCTAssertEqual(out.height, expectH,
                "[\(label) level \(level)] image height", file: file, line: line)
            XCTAssertEqual(out.components.count, full.components.count,
                "[\(label) level \(level)] component count", file: file, line: line)

            for comp in out.components {
                let bytesPerSample = comp.bitDepth <= 8 ? 1 : 2
                XCTAssertEqual(comp.width, expectW,
                    "[\(label) level \(level)] component width", file: file, line: line)
                XCTAssertEqual(comp.height, expectH,
                    "[\(label) level \(level)] component height", file: file, line: line)
                XCTAssertEqual(comp.data.count, expectW * expectH * bytesPerSample,
                    "[\(label) level \(level)] component data size must equal "
                    + "reduced dims × bytes/sample (a full-image-sized buffer "
                    + "behind reduced width/height fields is the v10.25 "
                    + "multi-tile corruption signature)",
                    file: file, line: line)
            }

            if level == N {
                XCTAssertEqual(out.components[0].data, full.components[0].data,
                    "[\(label)] decodeResolution(level: N) must be byte-identical to decode()",
                    file: file, line: line)
            } else {
                let reference = try J2KDecoder.downscaleByPowerOf2(
                    image: full, targetWidth: expectW, targetHeight: expectH, factor: f)
                let corr = pearsonCorrelation(
                    samples(out.components[0]),
                    samples(reference.components[0]))
                // Threshold calibrated on the CORRECT path across the
                // corpus: a 5-deep 5/3 LL pyramid vs a block-mean box
                // filter measures 0.86 (noisy CT 16×16 thumbnail) to
                // 0.99 (DX). The broken multi-tile composite scored
                // ≈ -0.1 — anything near the old behaviour fails this
                // by a mile. The tight (> 0.99) content check for
                // multi-tile is the single-vs-multi-tile parity oracle
                // in `assertMultiTileMatchesSingleTilePyramid`.
                XCTAssertGreaterThan(corr, 0.85,
                    "[\(label) level \(level)] content correlation vs \(f)x "
                    + "block-mean of full decode (mis-composited tiles "
                    + "score ≈ 0)",
                    file: file, line: line)
                print("V10_10 [\(label)] level \(level): \(expectW)×\(expectH), corr = \(String(format: "%.4f", corr))")
            }
        }
        print("V10_10 [\(label)] resolution pyramid OK at all \(N + 1) levels")
    }

    /// Strong multi-tile oracle: decodeResolution of the multi-tile
    /// codestream must agree with decodeResolution of a SINGLE-tile
    /// encode of the same pixels (the proven v10.5.0 path) at every
    /// partial level. Not bit-exact — each tile runs its own DWT, so
    /// LL coefficients near tile boundaries legitimately differ — but
    /// interior samples are identical and correlation stays > 0.99.
    /// A mis-composited canvas (wrong offsets / strides / parity)
    /// collapses this to ≈ 0.
    private func assertMultiTileMatchesSingleTilePyramid(
        multiTileStream: Data,
        singleTileStream: Data,
        levels N: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let decoder = J2KDecoder()
        for level in 0..<N {
            let multi = try await decoder.decodeResolution(
                multiTileStream, options: J2KResolutionDecodingOptions(level: level))
            let single = try await decoder.decodeResolution(
                singleTileStream, options: J2KResolutionDecodingOptions(level: level))
            XCTAssertEqual(multi.width, single.width,
                "[\(label) level \(level)] multi-tile width vs single-tile", file: file, line: line)
            XCTAssertEqual(multi.height, single.height,
                "[\(label) level \(level)] multi-tile height vs single-tile", file: file, line: line)
            XCTAssertEqual(multi.components[0].data.count, single.components[0].data.count,
                "[\(label) level \(level)] multi-tile data size vs single-tile", file: file, line: line)
            let corr = pearsonCorrelation(
                samples(multi.components[0]),
                samples(single.components[0]))
            XCTAssertGreaterThan(corr, 0.99,
                "[\(label) level \(level)] multi-tile partial decode must "
                + "match the single-tile partial decode of the same pixels "
                + "(differences are confined to tile-boundary DWT halos)",
                file: file, line: line)
            print("V10_10 [\(label)] level \(level): single-vs-multi-tile corr = \(String(format: "%.5f", corr))")
        }
        print("V10_10 [\(label)] single-vs-multi-tile parity OK at all \(N) partial levels")
    }

    // MARK: - Single-tile

    func testDecodeResolution_singleTile_CT_pyramid() async throws {
        guard let image = try loadPGM16("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)

        let meta = try DecoderPipeline.peekMetadata(codestream)
        XCTAssertEqual(meta.totalTiles, 1,
            "CT 512×512 should encode single-tile under default .auto")

        try await assertResolutionPyramid(
            codestream: codestream, levels: 5, label: "CT single-tile")
    }

    // MARK: - Multi-tile

    /// The v10.25 corruption repro: DX 2800×2288 encodes 4x4
    /// multi-tile under default `.auto`, with non-32-aligned tile
    /// origins (x ∈ {0, 700, 1400, 2100}) that exercise both the
    /// reduced-dimension composite offsets AND the truncated-iDWT
    /// parity depth offset. The broken path scored level-0
    /// correlation ≈ -0.1 against the 32x block-mean.
    func testDecodeResolution_multiTile_DX4x4_pyramid() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)

        let meta = try DecoderPipeline.peekMetadata(codestream)
        XCTAssertGreaterThan(meta.totalTiles, 1,
            "DX 2800×2288 must encode multi-tile under default .auto "
            + "(expected 4x4) — if the planner heuristics changed, force "
            + "a multi-tile layout here so this test keeps covering the "
            + "multi-tile partial-resolution path")
        print("V10_10 DX tiling: \(meta.numTilesX)x\(meta.numTilesY) = \(meta.totalTiles) tiles")

        try await assertResolutionPyramid(
            codestream: codestream, levels: 5, label: "DX 4x4 multi-tile")

        // The exact repro criterion from the v10.25 bug report:
        // level-0 thumbnail vs 32x block-mean of the full decode must
        // exceed 0.95 on DX (measured 0.986 on the fixed path).
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)
        let thumb = try await decoder.decodeResolution(
            codestream, options: J2KResolutionDecodingOptions(level: 0))
        let reference = try J2KDecoder.downscaleByPowerOf2(
            image: full, targetWidth: thumb.width, targetHeight: thumb.height, factor: 32)
        let corr = pearsonCorrelation(
            samples(thumb.components[0]), samples(reference.components[0]))
        XCTAssertGreaterThan(corr, 0.95,
            "DX multi-tile level-0 thumbnail vs 32x block-mean (broken composite gave ≈ -0.1)")

        // Strong oracle: agree with the proven single-tile partial
        // path on the same pixels at every level.
        let singleTileStream = try await encoder._singleTileEncode(image)
        let metaS = try DecoderPipeline.peekMetadata(singleTileStream)
        XCTAssertEqual(metaS.totalTiles, 1, "single-tile reference encode must be 1 tile")
        try await assertMultiTileMatchesSingleTilePyramid(
            multiTileStream: codestream, singleTileStream: singleTileStream,
            levels: 5, label: "DX 4x4 vs single")
    }

    func testDecodeResolution_multiTile_MG2x2_pyramid() async throws {
        guard let image = try loadPGM16("medical-real/mg_real_mid_3518x4784.pgm") else {
            throw XCTSkip("MG fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)

        let meta = try DecoderPipeline.peekMetadata(codestream)
        XCTAssertGreaterThan(meta.totalTiles, 1,
            "MG 3518×4784 must encode multi-tile under default .auto (expected 2x2)")
        print("V10_10 MG tiling: \(meta.numTilesX)x\(meta.numTilesY) = \(meta.totalTiles) tiles")

        try await assertResolutionPyramid(
            codestream: codestream, levels: 5, label: "MG 2x2 multi-tile")

        // Strong oracle: agree with the proven single-tile partial
        // path on the same pixels at every level.
        let singleTileStream = try await encoder._singleTileEncode(image)
        let metaS = try DecoderPipeline.peekMetadata(singleTileStream)
        XCTAssertEqual(metaS.totalTiles, 1, "single-tile reference encode must be 1 tile")
        try await assertMultiTileMatchesSingleTilePyramid(
            multiTileStream: codestream, singleTileStream: singleTileStream,
            levels: 5, label: "MG 2x2 vs single")
    }

    // MARK: - Irreversible 9/7

    /// v10.25 — the 9/7 iDWT branch never honoured the Stage B.2
    /// truncation: partial-resolution decode of an irreversible
    /// codestream ran all synthesis levels and returned full-dimension
    /// data behind reduced width/height fields (the same corruption
    /// signature as the multi-tile composite bug, present on
    /// SINGLE-tile lossy since v10.5.0). This pins dims + data size at
    /// every level and content correlation at the mid levels.
    /// Correlation thresholds are looser than the lossless pyramid —
    /// lossy reconstruction noise stacks on top of the LL-vs-box-filter
    /// methodology divergence.
    func testDecodeResolution_singleTile_CT_lossy97_pyramid() async throws {
        guard let image = try loadPGM16("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let cfg = J2KEncodingConfiguration(
            quality: 0.9, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: false,
            useReversibleFilter: false)
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let meta = try DecoderPipeline.peekMetadata(codestream)
        XCTAssertEqual(meta.totalTiles, 1)
        guard case .irreversible97 = meta.configuration.waveletFilter else {
            return XCTFail("expected an irreversible 9/7 codestream")
        }

        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)
        let W = full.width, H = full.height
        for level in 0...5 {
            let f = 1 << (5 - level)
            let expectW = (W + f - 1) / f
            let expectH = (H + f - 1) / f
            let out = try await decoder.decodeResolution(
                codestream, options: J2KResolutionDecodingOptions(level: level))
            XCTAssertEqual(out.width, expectW, "[9/7 level \(level)] image width")
            XCTAssertEqual(out.height, expectH, "[9/7 level \(level)] image height")
            for comp in out.components {
                let bytesPerSample = comp.bitDepth <= 8 ? 1 : 2
                XCTAssertEqual(comp.data.count, expectW * expectH * bytesPerSample,
                    "[9/7 level \(level)] component data size must equal reduced "
                    + "dims × bytes/sample (the 9/7 branch returned full-size "
                    + "buffers behind reduced dims until v10.25)")
            }
            if level >= 2 && level < 5 {
                let reference = try J2KDecoder.downscaleByPowerOf2(
                    image: full, targetWidth: expectW, targetHeight: expectH, factor: f)
                let corr = pearsonCorrelation(
                    samples(out.components[0]),
                    samples(reference.components[0]))
                XCTAssertGreaterThan(corr, 0.8,
                    "[9/7 level \(level)] content correlation vs \(f)x block-mean")
                print("V10_10 [CT 9/7] level \(level): \(expectW)×\(expectH), corr = \(String(format: "%.4f", corr))")
            }
        }
        print("V10_10 [CT 9/7] lossy partial-resolution pyramid OK")
    }

    // MARK: - Upscale

    func testDecodeResolution_upscale_recoversFullDims() async throws {
        guard let image = try loadPGM16("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()

        // Decode at level 1 with upscale: should match original dims.
        let opts = J2KResolutionDecodingOptions(level: 1, upscale: true)
        let out = try await decoder.decodeResolution(codestream, options: opts)
        XCTAssertEqual(out.width, image.width)
        XCTAssertEqual(out.height, image.height)
        print("V10_10 decodeResolution upscale: dimensions reconstructed OK")
    }
}
#endif
