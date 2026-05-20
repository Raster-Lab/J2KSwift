// V10_10_DecodeResolutionSmokeTests.swift
//
// v10.10-research Phase 1 — smoke test for the new `decodeResolution`
// implementation (replaces v10.3.0 era `notImplemented` stub).
//
// Phase 1 is "decode-then-downsample": runs the full decode and
// downsamples the output to the requested resolution level via
// power-of-2 block-average. Provides a working API surface; perf
// gain is NOT realised until Phase 2 (true partial-resolution
// decode with code-block filtering + iDWT truncation).
//
// Tests:
//   1. decodeResolution at each level produces correctly-dimensioned output
//   2. decodeResolution(upscale: true) reconstructs original dims
//   3. Output content is plausible (non-zero, finite)

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

    func testDecodeResolution_dimensions_atEachLevel() async throws {
        guard let image = try loadPGM16("medical-real/mg_real_mid_3518x4784.pgm") else {
            throw XCTSkip("MG fixture missing")
        }
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()

        // Expected dimensions for an N=5 decomposition at each resolution
        // level. Phase 1 uses ⌈dim / 2^(5-r)⌉ rounding.
        let W = image.width, H = image.height
        let expected: [(Int, Int, Int)] = [
            (0, (W + 31) / 32, (H + 31) / 32),  // thumbnail
            (1, (W + 15) / 16, (H + 15) / 16),
            (2, (W + 7)  / 8,  (H + 7)  / 8),
            (3, (W + 3)  / 4,  (H + 3)  / 4),
            (4, (W + 1)  / 2,  (H + 1)  / 2),
            (5, W,              H),             // full
        ]

        for (level, expectW, expectH) in expected {
            let opts = J2KResolutionDecodingOptions(level: level)
            let out = try await decoder.decodeResolution(codestream, options: opts)
            XCTAssertEqual(out.width, expectW,
                "[level \(level)] width mismatch (got \(out.width), expected \(expectW))")
            XCTAssertEqual(out.height, expectH,
                "[level \(level)] height mismatch (got \(out.height), expected \(expectH))")
            XCTAssertGreaterThan(out.components[0].data.count, 0,
                "[level \(level)] empty data")
        }
        print("V10_10 decodeResolution: dimensions OK at all 6 levels (0..5)")
    }

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

    func testDecodeResolution_fullLevel_equivalentToFullDecode() async throws {
        guard let image = try loadPGM16("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()

        let full = try await decoder.decode(codestream)
        let viaRes = try await decoder.decodeResolution(
            codestream,
            options: J2KResolutionDecodingOptions(level: 5))

        XCTAssertEqual(full.width, viaRes.width)
        XCTAssertEqual(full.height, viaRes.height)
        XCTAssertEqual(full.components.count, viaRes.components.count)
        XCTAssertEqual(full.components[0].data, viaRes.components[0].data,
                       "decodeResolution at full level should be byte-identical to decode()")
        print("V10_10 decodeResolution(level=5) byte-identical to decode() ✓")
    }
}
#endif
