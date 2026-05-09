// MgRegressionTriageTest.swift
//
// Permanent regression test for the v7.2.0 cross-tile batched HT
// entropy decode silent-corruption bug (PR #356,
// `decodeMultiTileGPUBatched`). The bug corrupts decode output
// when the HTJ2K codestream's total sample count crosses 2^24
// (≈ 16.78 M px) — first surfaced on 3520×4784 mammography
// fixtures during a 4-codec eval matrix on 2026-05-09. External
// decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1) decode
// the same J2KSwift-encoded bytes bit-exactly; the corruption
// is purely on the J2KSwift batched-decode side.
//
// **Mitigation (v7.5.1 hotfix)**: flip
// `DecoderPipeline._multiTileBatchedEntropyEnabled` default
// from `true` to `false`, falling back to the per-tile shape.
// The flag stays public so future repro / root-cause work can
// re-enable it.
//
// This test is in the mandatory pre-release gate so the bug
// cannot silently regress: it round-trips a synthetic 3520×4784
// 16-bit image (16.84 M samples — over the 2^24 threshold) and
// asserts bit-exact lossless reconstruction.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class MgRegressionTriageTest: XCTestCase {

    /// Generate a deterministic synthetic 16-bit image at the
    /// dimensions that triggered the v7.2.0 batched-decode bug.
    /// Content chosen to vary across the entire image (so HT
    /// entropy coding has actual work to do — all-zeros would
    /// hit the rho=0 fast path and skip most of the decoder).
    private func makeTriggerImage() -> J2KImage {
        let width = 3520
        let height = 4784  // 3520 × 4784 = 16 838 680 ≈ 2^24 + 60K
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

    /// Permanent gate — multi-tile HT-conformant lossless
    /// round-trip at total sample count > 2^24 must be bit-exact.
    /// This was silently broken from v7.2.0 → v7.5.0.
    func testMultiTileHTLossless_AboveTwoToTheTwentyFour_BitExact() async throws {
        let image = makeTriggerImage()
        XCTAssertGreaterThan(
            image.width * image.height, 1 << 24,
            "regression test must run an image whose total sample count " +
            "is above 2^24, otherwise it doesn't exercise the bug condition")

        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, qualityLayers: 1,
            useHTJ2K: true, useReversibleFilter: true,
            htj2kBlockFormat: .conformant)

        let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let decoded = try await J2KDecoder().decode(bytes)

        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "HTJ2K lossless round-trip must be bit-exact at 16+ MP — " +
            "PR #356's _multiTileBatchedEntropyEnabled corrupts output above 2^24 samples")
    }

    /// **v8.2 fix verified**: the cross-tile batched-entropy path
    /// now decodes correctly at 16+ MP. The v7.5.1 hotfix disabled
    /// it; v8.2 root-caused the bug to multi-tile-per-tile GPU
    /// IDWT being incorrectly invoked when entropy was batched
    /// (see `decodeTilePayloadGPU`'s preBatched branch) and
    /// re-enabled the default. This test pins the fix.
    func testMultiTileHTLossless_BatchedPath_FixedAt16MP() async throws {
        let image = makeTriggerImage()

        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, qualityLayers: 1,
            useHTJ2K: true, useReversibleFilter: true,
            htj2kBlockFormat: .conformant)

        let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let prev = DecoderPipeline._multiTileBatchedEntropyEnabled
        defer { DecoderPipeline._multiTileBatchedEntropyEnabled = prev }
        DecoderPipeline._multiTileBatchedEntropyEnabled = true

        let decoded = try await J2KDecoder().decode(bytes)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "v8.2 must decode multi-tile HT lossless > 2^24 samples bit-exact " +
            "via the cross-tile batched-entropy path with " +
            "_multiTileBatchedEntropyEnabled=true")
    }
}
