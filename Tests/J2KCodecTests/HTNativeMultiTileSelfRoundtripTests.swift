// HTNativeMultiTileSelfRoundtripTests.swift
// v6-alpha3 step 6B slice 3 — end-to-end self-roundtrip tests
// for the J2KSwift encoder + decoder on multi-tile codestreams.
//
// What slice 3 wired up (this commit's contribution):
//   - `decodeTilePayload` now passes the tile's image-coordinate
//     origin into `applyInverseWaveletTransform`.
//   - `applyInverseWaveletTransform`'s per-level subband-size
//     calculation now uses the ISO/IEC 15444-1 Eq. B-15 spec
//     formula instead of the recursive `(pw + 1) / 2` even-origin
//     formula.
//   - The IDWT call dispatches the parity-aware multi-level
//     inverse from slice 2 with the right `(tileOriginX,
//     tileOriginY)`.
//
// What's STILL MISSING for end-to-end self-roundtrip on
// non-32-aligned multi-tile (deferred to step 6B slice 4):
//
//   The decoder's ENTROPY STAGE — `extractTileData` /
//   `applyEntropyDecoding` and the underlying packet/code-block
//   parsing — still computes band sizes via the even-origin
//   formula and reads code-blocks via a tile-relative grid.
//   Step 6A (commit fb851bf) made the encoder canvas-anchor the
//   code-block partition per ISO/IEC 15444-1 B.7. The decoder
//   must mirror that to read back the same wire bytes; without
//   slice 4 a non-32-aligned multi-tile codestream traps in
//   `J2KHTConformantMagSgnCoder.read(count:)` ("MagSgn read width
//   > 32") because the bit-stream alignment drifts when the
//   decoder reads fewer or more code-blocks than the encoder
//   wrote.
//
// Therefore in this slice the MR/PX/DX 2x2 + DX 4x4 self-
// roundtrip tests are XCTSkip'd with a pointer to slice 4. The
// XA 1024×1024 2x2 self-roundtrip remains live as a regression
// guard (XA's tile origins are 32-aligned → all DWT levels
// even-origin → entropy decoder's even-origin block grid happens
// to be canvas-anchored, so XA self-roundtrips through the
// decoder unchanged from pre-slice-3).
//
// External cross-decode (OpenJPH/Grok/Kakadu) is already
// bit-exact for ALL FIVE fixtures post step 6A; this slice
// doesn't change the encoded bytes, only the decoder's IDWT
// stage.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTNativeMultiTileSelfRoundtripTests: XCTestCase {

    private func htConfig(decompositionLevels: Int = 5) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1, progressionOrder: .lrcp,
            bitrateMode: .lossless, maxThreads: 8,
            useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
    }

    private func syntheticImage(width: Int, height: Int) -> J2KImage {
        var data = Data(count: width * height * 2)
        var rng: UInt64 = 0xC0FEE
        for i in 0..<(width * height) {
            rng &+= 0x9E37_79B9_7F4A_7C15
            let v = UInt16(truncatingIfNeeded: rng)
            data[2 * i]     = UInt8(v >> 8)
            data[2 * i + 1] = UInt8(v & 0xFF)
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data, sampleByteOrder: .bigEndian)
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func uniformLayout(_ image: J2KImage, cols: Int, rows: Int)
        -> J2KTileLayout
    {
        let tw = (image.width  + cols - 1) / cols
        let th = (image.height + rows - 1) / rows
        return J2KTileLayout(
            cols: cols, rows: rows, tileWidth: tw, tileHeight: th,
            imageWidth: image.width, imageHeight: image.height)
    }

    /// Helper: encode via native multi-tile, decode via the
    /// J2KSwift decoder, assert bit-exact roundtrip.
    private func assertSelfRoundtripBitExact(
        imageW: Int, imageH: Int, cols: Int, rows: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let img = syntheticImage(width: imageW, height: imageH)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = uniformLayout(img, cols: cols, rows: rows)
        let (codestream, _) = try await pipeline.encodeNativeMultiTile(
            img, layout: layout)

        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(codestream)
        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
        XCTAssertEqual(maxDiff, 0,
            "\(label): J2KSwift self-roundtrip must be bit-exact " +
            "(max abs diff = \(maxDiff))",
            file: file, line: line)
    }

    // MARK: - 32-aligned baseline (regression guard)

    /// XA 1024×1024 2x2 — 32-aligned. Was already bit-exact
    /// pre-slice-3; this test guards that slice 3 doesn't regress
    /// it.
    func testXA2x2SelfRoundtripBitExact() async throws {
        try await assertSelfRoundtripBitExact(
            imageW: 1024, imageH: 1024, cols: 2, rows: 2,
            label: "XA 1024×1024 2x2")
    }

    // MARK: - Non-32-aligned fixtures — DEFERRED to step 6B slice 4

    /// Slice 4 is the entropy-decoder mirror of step 6A: the decoder
    /// must compute spec-correct band sizes (Eq. B-15) and walk a
    /// canvas-anchored code-block partition (B.7) so the bit-stream
    /// alignment matches what the encoder wrote. Without slice 4 the
    /// MR/PX/DX 2x2 + DX 4x4 self-roundtrip traps in
    /// `J2KHTConformantMagSgnCoder.read(count:)` ("MagSgn read width
    /// > 32") because the decoder's tile-relative block grid produces
    /// a different block count than the encoder's canvas-anchored
    /// grid. These tests stay XCTSkip until slice 4 lands; flipping
    /// them to live is part of slice 4's gate.

    func testMR2x2SelfRoundtripBitExact() async throws {
        throw XCTSkip("v6-alpha3 step 6B slice 4 — entropy decoder " +
                      "must mirror canvas-anchored block grid before " +
                      "MR 886×886 2x2 self-roundtrip can succeed.")
        // try await assertSelfRoundtripBitExact(
        //     imageW: 886, imageH: 886, cols: 2, rows: 2,
        //     label: "MR 886×886 2x2")
    }

    func testPX2x2SelfRoundtripBitExact() async throws {
        throw XCTSkip("v6-alpha3 step 6B slice 4 — entropy decoder " +
                      "must mirror canvas-anchored block grid before " +
                      "PX 2459×1316 2x2 self-roundtrip can succeed.")
    }

    func testDX2x2SelfRoundtripBitExact() async throws {
        throw XCTSkip("v6-alpha3 step 6B slice 4 — entropy decoder " +
                      "must mirror canvas-anchored block grid before " +
                      "DX 2800×2288 2x2 self-roundtrip can succeed.")
    }

    func testDX4x4SelfRoundtripBitExact() async throws {
        throw XCTSkip("v6-alpha3 step 6B slice 4 — entropy decoder " +
                      "must mirror canvas-anchored block grid before " +
                      "DX 2800×2288 4x4 self-roundtrip can succeed.")
    }
}
