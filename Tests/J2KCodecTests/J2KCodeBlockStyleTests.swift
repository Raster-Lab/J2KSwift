//
// J2KCodeBlockStyleTests.swift
// J2KSwift
//
// Regression tests for the SPcod/SPcoc code-block style byte
// (ISO/IEC 15444-1 Table A.19).
//
// The decoder used to read only bit 0 (selective bypass) and bit 6 (HT),
// discarding RESET, RESTART, vertically-causal context, PREDICTABLE and
// SEGMARK. Each of those changes how the entropy data is segmented or how
// context is formed, so a codestream using any of them desynchronised by
// construction: 78 of 194 conformant reversible codestreams from Kakadu,
// OpenJPEG, OpenJPH and Grok decoded to garbage, silently.
//
// These tests pin the pieces that fix is built on — the segment model, the
// style-byte decode, and the tile clip — at the unit level, because the
// end-to-end evidence needs third-party encoders that are not available in
// CI. `Scripts/generate-integrity-corpus.sh` reproduces that corpus, and
// Documentation/CODING_MODES.md records the measurement.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KCodeBlockStyleTests: XCTestCase {

    // MARK: - Style byte

    /// Every bit of Table A.19 must be decoded, not just the two that were.
    func testEveryStyleBitIsDecoded() {
        let none = DecoderPipeline.codeBlockStyleFlags(0x00)
        XCTAssertFalse(none.bypass)
        XCTAssertFalse(none.resetContext)
        XCTAssertFalse(none.terminateAll)
        XCTAssertFalse(none.verticallyCausal)
        XCTAssertFalse(none.predictableTermination)
        XCTAssertFalse(none.segmentationSymbols)
        XCTAssertFalse(none.ht)

        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x01).bypass)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x02).resetContext)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x04).terminateAll)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x08).verticallyCausal)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x10).predictableTermination)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x20).segmentationSymbols)
        XCTAssertTrue(DecoderPipeline.codeBlockStyleFlags(0x40).ht)

        // Kakadu's Cmodes=BYPASS|RESTART|PREDICTABLE|SEGMARK.
        let all = DecoderPipeline.codeBlockStyleFlags(0x35)
        XCTAssertTrue(all.bypass)
        XCTAssertTrue(all.terminateAll)
        XCTAssertTrue(all.predictableTermination)
        XCTAssertTrue(all.segmentationSymbols)
        XCTAssertFalse(all.resetContext)
    }

    /// Each bit must reach the entropy decoder's options, not stop at the
    /// configuration. Previously everything but bypass was dropped here.
    func testStyleFlagsReachTheEntropyDecoder() {
        var config = DecoderConfiguration()
        config.applyCodeBlockStyle(0x2E)   // reset | terminate | causal | segmark
        let options = DecoderPipeline.decodeCodingOptions(for: config)

        XCTAssertFalse(options.bypassEnabled)
        XCTAssertTrue(options.resetContextOnEachPass)
        XCTAssertTrue(options.terminateOnEachPass)
        XCTAssertTrue(options.verticallyCausalContext)
        XCTAssertTrue(options.segmentationSymbols)
    }

    /// RESTART must not imply RESET.
    ///
    /// Terminating the codeword segment and resetting the context
    /// probabilities are independent bits. `TerminationMode.predictable`
    /// historically stood for a mixture of them, so mapping a bit onto that
    /// case would silently enable the other — which is exactly what
    /// corrupted every RESTART-only stream.
    func testRestartDoesNotImplyContextReset() {
        var config = DecoderConfiguration()
        config.applyCodeBlockStyle(0x04)   // RESTART alone
        let options = DecoderPipeline.decodeCodingOptions(for: config)

        XCTAssertTrue(options.terminateOnEachPass)
        XCTAssertFalse(options.resetContextOnEachPass)
        XCTAssertFalse(options.resetOnEachPass,
                       "RESTART alone must not reset context probabilities")
    }

    // MARK: - Codeword segment model

    /// Without a style that splits the block, it is one segment.
    func testDefaultStyleIsASingleSegment() {
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 31, terminateOnEachPass: false, bypass: false),
            [31])
    }

    /// Termination on each pass gives one segment per pass.
    func testTerminateOnEachPassGivesOneSegmentPerPass() {
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 5, terminateOnEachPass: true, bypass: false),
            [1, 1, 1, 1, 1])
    }

    /// Selective bypass: ten arithmetically coded passes, then alternating
    /// two-pass raw and one-pass cleanup segments.
    ///
    /// This is the shape the decode loop got wrong. It advanced one segment
    /// per pass, which is right only under termination-on-each-pass, so under
    /// bypass it ran off the end of the block's slices partway through.
    func testBypassSegmentShape() {
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 19, terminateOnEachPass: false, bypass: true),
            [10, 2, 1, 2, 1, 2, 1])
        // Truncated mid-segment.
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 11, terminateOnEachPass: false, bypass: true),
            [10, 1])
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 7, terminateOnEachPass: false, bypass: true),
            [7])
    }

    /// Termination on each pass wins over bypass when both are set.
    func testTerminateAllDominatesBypass() {
        XCTAssertEqual(
            DecoderPipeline.segmentPassCounts(
                numPasses: 4, terminateOnEachPass: true, bypass: true),
            [1, 1, 1, 1])
    }

    /// Every segmentation must account for exactly the passes it was given.
    func testSegmentCountsAlwaysSumToThePassCount() {
        for passes in 0...40 {
            for terminateAll in [false, true] {
                for bypass in [false, true] {
                    let counts = DecoderPipeline.segmentPassCounts(
                        numPasses: passes,
                        terminateOnEachPass: terminateAll, bypass: bypass)
                    XCTAssertEqual(counts.reduce(0, +), passes,
                                   "passes=\(passes) terminateAll=\(terminateAll) bypass=\(bypass)")
                    XCTAssertFalse(counts.contains(where: { $0 <= 0 }),
                                   "empty segment for passes=\(passes)")
                }
            }
        }
    }

    // MARK: - Tile clipping

    /// A nominal tile larger than the image codes only the image's extent
    /// (ISO/IEC 15444-1 Eq. B-7).
    ///
    /// A 64×48 image declaring `XTsiz = YTsiz = 128` has a codestream whose
    /// entropy payload is byte-identical to the same image tiled at exactly
    /// 64×48 — only the SIZ fields differ. It decoded to garbage because the
    /// subband grid was computed for a 128-wide tile.
    func testNominalTileLargerThanImageIsClipped() async throws {
        let image = makeImage(width: 64, height: 48)
        let encoded = try await J2KEncoder(configuration: .lossless).encode(image)

        // Rewrite XTsiz/YTsiz to 128×128 in place. SIZ layout: marker(2)
        // Lsiz(2) Rsiz(2) Xsiz(4) Ysiz(4) XOsiz(4) YOsiz(4) XTsiz(4) YTsiz(4),
        // so XTsiz starts at offset 2+2+2+2+16 = 24 from the SOC marker.
        var bytes = [UInt8](encoded)
        try XCTSkipUnless(bytes.count > 40 && bytes[2] == 0xFF && bytes[3] == 0x51,
                          "fixture does not begin SOC, SIZ")
        func writeUInt32(_ value: UInt32, at offset: Int) {
            bytes[offset] = UInt8(value >> 24)
            bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
            bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
            bytes[offset + 3] = UInt8(value & 0xFF)
        }
        writeUInt32(128, at: 24)   // XTsiz
        writeUInt32(128, at: 28)   // YTsiz

        let decoded = try await J2KDecoder().decode(Data(bytes))
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        XCTAssertEqual(samples(decoded), samples(image),
                       "an oversized nominal tile must decode identically to an exact one")
    }

    /// A resolution level's precinct grid must be sized from every sub-band
    /// it carries, not from HL alone.
    ///
    /// HL carries a half-sample x offset and HH carries both (Eq. B-15), so
    /// for a tile the image edge cuts to a narrow strip either can come out
    /// exactly zero wide while LH does not. Sizing the grid from HL then
    /// skipped the whole resolution level — and the packet that really was
    /// there — desynchronising every packet after it.
    ///
    /// A 4-wide tile at x = 256 with three decomposition levels is such a
    /// case: HL and HH are empty, LH is one sample wide.
    func testResolutionGridCoversEveryBandOfTheLevel() {
        let hl = DecoderPipeline.subbandDimensionsForTesting(
            tileWidth: 4, tileHeight: 128, tileOriginX: 256, tileOriginY: 0,
            levels: 3, resLevel: 1, subband: .hl)
        let lh = DecoderPipeline.subbandDimensionsForTesting(
            tileWidth: 4, tileHeight: 128, tileOriginX: 256, tileOriginY: 0,
            levels: 3, resLevel: 1, subband: .lh)
        XCTAssertEqual(hl.width, 0, "fixture no longer exercises a degenerate HL")
        XCTAssertGreaterThan(lh.width, 0, "fixture no longer has a live LH")

        let grid = DecoderPipeline.resolutionGridSize(
            tileWidth: 4, tileHeight: 128, tileOriginX: 256, tileOriginY: 0,
            levels: 3, resLevel: 1)
        XCTAssertEqual(grid.width, lh.width,
                       "an empty HL must not shrink the level's precinct grid")
        XCTAssertGreaterThan(grid.height, 0)
    }

    // MARK: - Fixtures

    private func makeImage(width: Int, height: Int) -> J2KImage {
        var bytes = Data(capacity: width * height * 2)
        var seed: UInt64 = 0x2026_0921
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let value = UInt16(clamping: (x * 400 + y * 250) % 40000 + Int((seed >> 33) % 600))
                bytes.append(UInt8(value >> 8))
                bytes.append(UInt8(value & 0xFF))
            }
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                subsamplingX: 1, subsamplingY: 1, data: bytes)])
    }

    private func samples(_ image: J2KImage) -> [Int] {
        let bytes = [UInt8](image.components[0].data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map {
            Int(bytes[$0]) << 8 | Int(bytes[$0 + 1])
        }
    }
}
