// HTNativeMultiTileBandGeometryTests.swift
// v6-alpha3 step 6A — internal-consistency tests for the
// native multi-tile encoder's per-band code-block grid +
// per-packet tag-tree dimensions + per-packet body block order.
//
// SCOPE: encoder-internal consistency only. These tests do NOT
// depend on external HT decoders. They prove that the parity-aware
// DWT band dimensions emitted by `applyWaveletTransform` propagate
// coherently through:
//
//   - PendingCodeBlock creation in `applyEntropyCodingHTJ2KFused`
//     (and its sibling EBCOT path)
//   - tag-tree dimensions in `writePacket`
//   - packet body block ordering in `writePacket`
//
// Tests 1-5 are per-fixture variants of the same assertion (so a
// MR-only failure is reported separately from a PX-only failure).
// Tests 6-8, 11 cross every fixture cell. Tests 9-10 use the
// parity-aware spec calculator below as the ground truth.
//
// **What these tests do NOT yet cover** (deferred to phase D fix):
//   - Whether the encoder's tile-relative block grid agrees with
//     the *canvas-anchored* code-block partition that an external
//     decoder reads from the wire bytes. ISO/IEC 15444-1 B.7 says
//     code-blocks are partitioned from the band canvas at (0, 0);
//     for non-zero tile-band-origins the first/last blocks should
//     be partial-width. The encoder currently produces a
//     tile-relative grid with full-width first blocks. The
//     audit (phase C) characterises this divergence; the fix
//     (phase D) anchors the grid to the band canvas so the wire
//     bytes match what an HTJ2K-compliant decoder expects.
//
// The internal-consistency tests in this file pass even with the
// known wire-format bug, because the bug is a CONSISTENT
// tile-relative-anchored encoder. Phase D's fix will preserve all
// these internal-consistency invariants and additionally make the
// encoder-emitted wire bytes spec-canvas-anchored. After the fix,
// tests 9-10 (which compare DWT band dims to spec-expected
// canvas-anchored values) will detect any regression in the
// parity-aware DWT itself.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTNativeMultiTileBandGeometryTests: XCTestCase {

    // MARK: - Fixtures + helpers

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

    /// Deterministic 16-bit BE synthetic image — pixel content
    /// doesn't matter for geometry tests, only shape does.
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

    /// Build a uniform `colsxrows` layout for the given image,
    /// using the planner-ignoring `(image + cols-1)/cols` rounding
    /// the existing assembler tests use.
    private func uniformLayout(_ image: J2KImage, cols: Int, rows: Int)
        -> J2KTileLayout
    {
        let tw = (image.width  + cols - 1) / cols
        let th = (image.height + rows - 1) / rows
        return J2KTileLayout(
            cols: cols, rows: rows, tileWidth: tw, tileHeight: th,
            imageWidth: image.width, imageHeight: image.height)
    }

    /// Run the native multi-tile encoder and return the populated
    /// geometry collector. The codestream itself is discarded — the
    /// tests only inspect the captured trace.
    private func collectGeometry(
        imageWidth: Int, imageHeight: Int,
        cols: Int, rows: Int,
        decompositionLevels: Int = 5
    ) async throws -> (collector: GeometryCollector, layout: J2KTileLayout) {
        let img = syntheticImage(width: imageWidth, height: imageHeight)
        let pipeline = EncoderPipeline(config: htConfig(
            decompositionLevels: decompositionLevels))
        let layout = uniformLayout(img, cols: cols, rows: rows)
        let collector = GeometryCollector()
        _ = try await pipeline.encodeNativeMultiTile(
            img, layout: layout, geometryCollector: collector)
        return (collector, layout)
    }

    // MARK: - Spec calculator (ISO/IEC 15444-1 B.5)

    /// Spec-expected band dimensions for a tile-component at the
    /// given image-coord origin + size, at decomposition level `d`,
    /// for the given subband. Per ISO/IEC 15444-1 Eq. B-15:
    ///
    ///   tbx0 = ceil((tcx0 - x_offset_b) / 2^d)
    ///   tby0 = ceil((tcy0 - y_offset_b) / 2^d)
    ///   tbx1 = ceil((tcx1 - x_offset_b) / 2^d)
    ///   tby1 = ceil((tcy1 - y_offset_b) / 2^d)
    ///
    /// where (x_offset_b, y_offset_b) is:
    ///   LL: (0, 0)        HL: (2^(d-1), 0)
    ///   LH: (0, 2^(d-1))  HH: (2^(d-1), 2^(d-1))
    ///
    /// And the band size is (tbx1 - tbx0, tby1 - tby0).
    ///
    /// For the coarsest LL band (LL_NL), pass `d = totalLevels`
    /// and `subband = .ll`.
    static func specExpectedBandDimensions(
        tileOriginX: Int, tileOriginY: Int,
        tileWidth: Int, tileHeight: Int,
        decompositionLevel d: Int,
        subband: J2KSubband
    ) -> (width: Int, height: Int) {
        precondition(d >= 1, "spec band formula requires d >= 1")
        let tcx0 = tileOriginX
        let tcy0 = tileOriginY
        let tcx1 = tileOriginX + tileWidth
        let tcy1 = tileOriginY + tileHeight

        let div  = 1 << d                 // 2^d
        let half = 1 << (d - 1)           // 2^(d-1)

        let (xOff, yOff): (Int, Int)
        switch subband {
        case .ll: (xOff, yOff) = (0, 0)
        case .hl: (xOff, yOff) = (half, 0)
        case .lh: (xOff, yOff) = (0, half)
        case .hh: (xOff, yOff) = (half, half)
        }

        // Mathematical ceiling division for possibly-negative
        // numerator. Swift's integer `/` truncates toward zero, so
        // -5/3 == -1 (not -2). Spec ceiling for negative numerator:
        //   ceil(num/den) = -floor(-num/den) = -((-num) / den)
        // For non-negative numerator: (num + den - 1) / den.
        func ceilDiv(_ num: Int, _ den: Int) -> Int {
            precondition(den > 0)
            if num >= 0 { return (num + den - 1) / den }
            return -((-num) / den)
        }

        let tbx0 = ceilDiv(tcx0 - xOff, div)
        let tby0 = ceilDiv(tcy0 - yOff, div)
        let tbx1 = ceilDiv(tcx1 - xOff, div)
        let tby1 = ceilDiv(tcy1 - yOff, div)
        return (tbx1 - tbx0, tby1 - tby0)
    }

    /// Map a `GeometryBand`'s (resolutionLevel, subband) back to
    /// the decomposition depth `d` used by the spec formula.
    /// Encoder code: LL → resolutionLevel=0; HL/LH/HH at info.level=d
    /// → resolutionLevel = totalLevels - d + 1.
    /// Inverse: HL/LH/HH at r → d = totalLevels - r + 1.
    /// LL is the coarsest LL_totalLevels.
    static func specDecompositionDepth(
        for band: GeometryBand, totalLevels: Int
    ) -> Int {
        if band.subband == .ll { return totalLevels }
        return totalLevels - band.resolutionLevel + 1
    }

    // MARK: - Tests 1-5: per-fixture band-vs-packet consistency

    func testXABandGeometryMatchesPacketHeaders() async throws {
        let (collector, _) = try await collectGeometry(
            imageWidth: 1024, imageHeight: 1024, cols: 2, rows: 2)
        assertBandsConsistentWithPackets(collector,
            label: "XA 1024×1024 2x2")
    }

    func testMR2x2BandGeometryMatchesPacketHeaders() async throws {
        let (collector, _) = try await collectGeometry(
            imageWidth: 886, imageHeight: 886, cols: 2, rows: 2)
        assertBandsConsistentWithPackets(collector,
            label: "MR 886×886 2x2")
    }

    func testPX2x2BandGeometryMatchesPacketHeaders() async throws {
        let (collector, _) = try await collectGeometry(
            imageWidth: 2459, imageHeight: 1316, cols: 2, rows: 2)
        assertBandsConsistentWithPackets(collector,
            label: "PX 2459×1316 2x2")
    }

    func testDX2x2BandGeometryMatchesPacketHeaders() async throws {
        let (collector, _) = try await collectGeometry(
            imageWidth: 2800, imageHeight: 2288, cols: 2, rows: 2)
        assertBandsConsistentWithPackets(collector,
            label: "DX 2800×2288 2x2")
    }

    func testDX4x4BandGeometryMatchesPacketHeaders() async throws {
        let (collector, _) = try await collectGeometry(
            imageWidth: 2800, imageHeight: 2288, cols: 4, rows: 4)
        assertBandsConsistentWithPackets(collector,
            label: "DX 2800×2288 4x4")
    }

    /// Helper: every packet record's per-band tag-tree dims must
    /// match the entropy stage's blocksX/blocksY for the SAME
    /// (tile, comp, res, subband) cell.
    private func assertBandsConsistentWithPackets(
        _ collector: GeometryCollector,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(collector.bands.isEmpty,
            "\(label): collector captured no bands",
            file: file, line: line)
        XCTAssertFalse(collector.packets.isEmpty,
            "\(label): collector captured no packets",
            file: file, line: line)

        for packet in collector.packets {
            for pBand in packet.bands {
                guard let band = collector.band(
                    tileIndex: packet.tileIndex,
                    componentIndex: packet.componentIndex,
                    resolutionLevel: packet.resolutionLevel,
                    subband: pBand.subband)
                else {
                    XCTFail("""
                        \(label): packet band has no matching entropy \
                        record at tile=\(packet.tileIndex) \
                        res=\(packet.resolutionLevel) \
                        comp=\(packet.componentIndex) \
                        subband=\(pBand.subband)
                        """, file: file, line: line)
                    continue
                }
                XCTAssertEqual(pBand.tagTreeWidth, band.blocksX,
                    "\(label): tag-tree width mismatch at " +
                    "tile=\(packet.tileIndex) res=\(packet.resolutionLevel) " +
                    "comp=\(packet.componentIndex) subband=\(pBand.subband) " +
                    "(band.blocksX=\(band.blocksX), packet.tagTreeWidth=\(pBand.tagTreeWidth))",
                    file: file, line: line)
                XCTAssertEqual(pBand.tagTreeHeight, band.blocksY,
                    "\(label): tag-tree height mismatch at " +
                    "tile=\(packet.tileIndex) res=\(packet.resolutionLevel) " +
                    "comp=\(packet.componentIndex) subband=\(pBand.subband) " +
                    "(band.blocksY=\(band.blocksY), packet.tagTreeHeight=\(pBand.tagTreeHeight))",
                    file: file, line: line)
            }
        }
    }

    // MARK: - Test 6: no PendingCodeBlock outside band bounds

    /// Across every (fixture, mode) cell + every (tile, band) +
    /// every PendingCodeBlock, the block's coefficient extraction
    /// region (`originX..originX+width × originY..originY+height`)
    /// must not extend past the band's reported width/height. Note
    /// that `x` and `y` are tag-tree cell positions (which can land
    /// past the band's right/bottom edge for the canvas-anchored
    /// partition's last cell when it straddles the trailing tile
    /// boundary). The relevant "no outside the band" check is on
    /// the EXTRACTION coordinates.
    func testNoPendingCodeBlockOutsideBandBounds() async throws {
        struct Cell {
            let label: String
            let imageW: Int
            let imageH: Int
            let cols: Int
            let rows: Int
        }
        let cells: [Cell] = [
            Cell(label: "XA 2x2", imageW: 1024, imageH: 1024, cols: 2, rows: 2),
            Cell(label: "MR 2x2", imageW:  886, imageH:  886, cols: 2, rows: 2),
            Cell(label: "PX 2x2", imageW: 2459, imageH: 1316, cols: 2, rows: 2),
            Cell(label: "DX 2x2", imageW: 2800, imageH: 2288, cols: 2, rows: 2),
            Cell(label: "DX 4x4", imageW: 2800, imageH: 2288, cols: 4, rows: 4),
        ]
        for cell in cells {
            let (collector, _) = try await collectGeometry(
                imageWidth: cell.imageW, imageHeight: cell.imageH,
                cols: cell.cols, rows: cell.rows)
            for band in collector.bands {
                for (i, b) in band.pendingBlocks.enumerated() {
                    XCTAssertGreaterThanOrEqual(b.originX, 0,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) res=\(band.resolutionLevel) " +
                        "block[\(i)] originX=\(b.originX) is negative")
                    XCTAssertGreaterThanOrEqual(b.originY, 0,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) block[\(i)] originY=\(b.originY) is negative")
                    XCTAssertGreaterThan(b.width, 0,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) block[\(i)] zero width")
                    XCTAssertGreaterThan(b.height, 0,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) block[\(i)] zero height")
                    XCTAssertLessThanOrEqual(b.originX + b.width, band.bandWidth,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) res=\(band.resolutionLevel) " +
                        "block[\(i)] extraction right edge originX+w=\(b.originX + b.width) " +
                        "exceeds bandWidth=\(band.bandWidth)")
                    XCTAssertLessThanOrEqual(b.originY + b.height, band.bandHeight,
                        "\(cell.label) tile=\(band.tileIndex) " +
                        "subband=\(band.subband) res=\(band.resolutionLevel) " +
                        "block[\(i)] extraction bottom edge originY+h=\(b.originY + b.height) " +
                        "exceeds bandHeight=\(band.bandHeight)")
                }
            }
        }
    }

    // MARK: - Test 7: packet tag-tree dims equal block grid

    /// Same shape as tests 1-5 but cross every fixture in one test.
    /// (Tests 1-5 exist as per-fixture entry points so the failure
    /// signal localises by modality; this one is the bulk gate.)
    func testPacketTagTreeDimensionsMatchBlockGrid() async throws {
        struct Cell {
            let label: String
            let imageW: Int
            let imageH: Int
            let cols: Int
            let rows: Int
        }
        let cells: [Cell] = [
            Cell(label: "XA 2x2", imageW: 1024, imageH: 1024, cols: 2, rows: 2),
            Cell(label: "MR 2x2", imageW:  886, imageH:  886, cols: 2, rows: 2),
            Cell(label: "PX 2x2", imageW: 2459, imageH: 1316, cols: 2, rows: 2),
            Cell(label: "DX 2x2", imageW: 2800, imageH: 2288, cols: 2, rows: 2),
            Cell(label: "DX 4x4", imageW: 2800, imageH: 2288, cols: 4, rows: 4),
        ]
        for cell in cells {
            let (collector, _) = try await collectGeometry(
                imageWidth: cell.imageW, imageHeight: cell.imageH,
                cols: cell.cols, rows: cell.rows)
            assertBandsConsistentWithPackets(collector, label: cell.label)
        }
    }

    // MARK: - Test 8: packet block count matches generated blocks

    /// For every (tile, res, comp, subband) cell, the packet's
    /// tag-tree iterates exactly `band.blocksX * band.blocksY`
    /// blocks (== `band.pendingBlocks.count`). The body subset
    /// (where `entry.included == true`) is naturally smaller for
    /// all-zero blocks, but the tag-tree must cover every
    /// generated block.
    func testPacketBlockCountMatchesGeneratedBlocks() async throws {
        struct Cell {
            let label: String
            let imageW: Int; let imageH: Int
            let cols: Int; let rows: Int
        }
        let cells: [Cell] = [
            Cell(label: "XA 2x2", imageW: 1024, imageH: 1024, cols: 2, rows: 2),
            Cell(label: "MR 2x2", imageW:  886, imageH:  886, cols: 2, rows: 2),
            Cell(label: "PX 2x2", imageW: 2459, imageH: 1316, cols: 2, rows: 2),
            Cell(label: "DX 2x2", imageW: 2800, imageH: 2288, cols: 2, rows: 2),
            Cell(label: "DX 4x4", imageW: 2800, imageH: 2288, cols: 4, rows: 4),
        ]
        for cell in cells {
            let (collector, _) = try await collectGeometry(
                imageWidth: cell.imageW, imageHeight: cell.imageH,
                cols: cell.cols, rows: cell.rows)
            for packet in collector.packets {
                for pBand in packet.bands {
                    guard let band = collector.band(
                        tileIndex: packet.tileIndex,
                        componentIndex: packet.componentIndex,
                        resolutionLevel: packet.resolutionLevel,
                        subband: pBand.subband)
                    else { continue }
                    XCTAssertEqual(pBand.entries.count, band.pendingBlocks.count,
                        "\(cell.label): packet entry count != band pending-block count " +
                        "at tile=\(packet.tileIndex) res=\(packet.resolutionLevel) " +
                        "comp=\(packet.componentIndex) subband=\(pBand.subband) " +
                        "(packet.entries=\(pBand.entries.count), " +
                        "band.pendingBlocks=\(band.pendingBlocks.count), " +
                        "band.blocksX*Y=\(band.blocksX * band.blocksY))")
                    XCTAssertEqual(pBand.entries.count, band.blocksX * band.blocksY,
                        "\(cell.label): packet entry count != blocksX*blocksY " +
                        "at tile=\(packet.tileIndex) subband=\(pBand.subband) " +
                        "(\(pBand.entries.count) vs \(band.blocksX)x\(band.blocksY))")
                }
            }
        }
    }

    // MARK: - Test 9: odd-origin parity-aware low/high counts

    /// For tiles whose image-coord origin is odd in either axis,
    /// the per-band low/high counts (HL/LH/HH band dims at the
    /// finest decomposition level d=1, where parity flips matter
    /// most) MUST match the spec-expected canvas-aware F.4.3
    /// formula. This validates that the parity-aware DWT
    /// (v6-alpha3 step 1+2) produces band dims an external
    /// canvas-anchored decoder will agree with.
    ///
    /// The specific cells exercised:
    ///   - MR 886×886 2x2 → tile 1 origin (443, 0), tile 2 (0, 443),
    ///     tile 3 (443, 443) — odd in X, Y, both
    ///   - PX 2459×1316 2x2 → tile 1 origin (1230, 0) — even in X,
    ///     but PX 4x4 would have odd origins; here we use 2x2
    ///   - DX 2800×2288 4x4 → tile origins include (700, 572) where
    ///     parity flips at deeper DWT levels (700 mod 32 = 28,
    ///     700/2/2 = 175 → odd at level 2)
    func testOddOriginLowHighBandCountsPropagateToPackets() async throws {
        let totalLevels = 5
        struct Cell {
            let label: String
            let imageW: Int; let imageH: Int
            let cols: Int; let rows: Int
        }
        let cells: [Cell] = [
            Cell(label: "MR 2x2", imageW:  886, imageH:  886, cols: 2, rows: 2),
            Cell(label: "PX 2x2", imageW: 2459, imageH: 1316, cols: 2, rows: 2),
            Cell(label: "DX 2x2", imageW: 2800, imageH: 2288, cols: 2, rows: 2),
            Cell(label: "DX 4x4", imageW: 2800, imageH: 2288, cols: 4, rows: 4),
        ]

        for cell in cells {
            let (collector, layout) = try await collectGeometry(
                imageWidth: cell.imageW, imageHeight: cell.imageH,
                cols: cell.cols, rows: cell.rows,
                decompositionLevels: totalLevels)
            for band in collector.bands {
                let r = layout.rect(forTile: band.tileIndex)
                let d = Self.specDecompositionDepth(for: band, totalLevels: totalLevels)
                let expected = Self.specExpectedBandDimensions(
                    tileOriginX: r.x, tileOriginY: r.y,
                    tileWidth: r.w, tileHeight: r.h,
                    decompositionLevel: d, subband: band.subband)
                XCTAssertEqual(band.bandWidth, expected.width,
                    "\(cell.label) tile=\(band.tileIndex) " +
                    "(origin (\(r.x), \(r.y)) size \(r.w)×\(r.h)) " +
                    "subband=\(band.subband) decomp_d=\(d): " +
                    "DWT-actual bandWidth=\(band.bandWidth) != " +
                    "spec-expected=\(expected.width) — parity-aware " +
                    "DWT band-dim mismatch (low/high count divergence)")
                XCTAssertEqual(band.bandHeight, expected.height,
                    "\(cell.label) tile=\(band.tileIndex) " +
                    "(origin (\(r.x), \(r.y)) size \(r.w)×\(r.h)) " +
                    "subband=\(band.subband) decomp_d=\(d): " +
                    "DWT-actual bandHeight=\(band.bandHeight) != " +
                    "spec-expected=\(expected.height)")
            }
        }
    }

    // MARK: - Test 10: trailing tile band geometry uses actual size

    /// PX 2459×1316 has odd Width → trailing-column tiles are 1229
    /// wide, not 1230. The encoder must use the trailing tile's
    /// actual size when computing band dims, not the nominal layout
    /// XTsiz value. Verified by comparing DWT-actual band dims
    /// against the spec calculator using the layout rect's clipped
    /// `r.w`, `r.h` (which reflect the actual per-tile size).
    func testTrailingTileBandGeometryIsCorrect() async throws {
        let totalLevels = 5
        // PX 2459×1316 2x2: trailing column tile width 1229; trailing
        // row tile height 658 (1316 - 658 = 658, even). Tile 1
        // (col 1, row 0) → (1230, 0) with size (1229, 658).
        let (collector, layout) = try await collectGeometry(
            imageWidth: 2459, imageHeight: 1316, cols: 2, rows: 2,
            decompositionLevels: totalLevels)

        // Find the trailing-column tile (tile 1 in row-major 2x2).
        let trailingCol = layout.rect(forTile: 1)
        XCTAssertEqual(trailingCol.x, 1230,
            "trailing-col tile origin x must be 1230 (not nominal XTsiz)")
        XCTAssertEqual(trailingCol.w, 1229,
            "trailing-col tile width must be 1229 (= 2459 - 1230), " +
            "not nominal XTsiz=1230")

        // Verify every band of every trailing tile uses the
        // clipped (actual) tile size in its dims.
        for tileIndex in [1, 3] {  // col 1 of each row in 2x2
            let r = layout.rect(forTile: tileIndex)
            let bands = collector.bands.filter { $0.tileIndex == tileIndex }
            XCTAssertFalse(bands.isEmpty,
                "no band records for tile \(tileIndex)")
            for band in bands {
                let d = Self.specDecompositionDepth(
                    for: band, totalLevels: totalLevels)
                let expected = Self.specExpectedBandDimensions(
                    tileOriginX: r.x, tileOriginY: r.y,
                    tileWidth: r.w, tileHeight: r.h,
                    decompositionLevel: d, subband: band.subband)
                XCTAssertEqual(band.bandWidth, expected.width,
                    "trailing tile \(tileIndex) (size \(r.w)×\(r.h)) " +
                    "subband=\(band.subband) d=\(d): " +
                    "bandWidth=\(band.bandWidth) != expected=\(expected.width)")
                XCTAssertEqual(band.bandHeight, expected.height,
                    "trailing tile \(tileIndex) subband=\(band.subband) d=\(d): " +
                    "bandHeight=\(band.bandHeight) != expected=\(expected.height)")
            }
        }
    }

    // MARK: - Test 11: packet body block order matches header order

    /// `writePacket` iterates each band's blocks in raster order,
    /// emitting the inclusion bit and (if included) appending the
    /// block to the body in the same loop iteration. So the body
    /// order is the header iteration order filtered to included
    /// blocks. This test verifies that invariant via the trace:
    /// the `bodyOrderIndex` of included blocks must form 0, 1, 2…
    /// in header iteration order.
    func testPacketBodyBlockOrderMatchesHeaderOrder() async throws {
        struct Cell {
            let label: String
            let imageW: Int; let imageH: Int
            let cols: Int; let rows: Int
        }
        let cells: [Cell] = [
            Cell(label: "XA 2x2", imageW: 1024, imageH: 1024, cols: 2, rows: 2),
            Cell(label: "MR 2x2", imageW:  886, imageH:  886, cols: 2, rows: 2),
        ]
        for cell in cells {
            let (collector, _) = try await collectGeometry(
                imageWidth: cell.imageW, imageHeight: cell.imageH,
                cols: cell.cols, rows: cell.rows)
            for packet in collector.packets {
                // The body order indexes are emitted across ALL
                // bands of a packet, in band-iteration order. So
                // we collect them across the packet, not per band,
                // and assert they form a contiguous 0..k sequence.
                var expected = 0
                for pBand in packet.bands {
                    for entry in pBand.entries {
                        if entry.included {
                            XCTAssertEqual(entry.bodyOrderIndex, expected,
                                "\(cell.label) tile=\(packet.tileIndex) " +
                                "res=\(packet.resolutionLevel) " +
                                "comp=\(packet.componentIndex): " +
                                "body order broken at subband=\(pBand.subband) " +
                                "block @ (\(entry.x), \(entry.y)) — " +
                                "expected bodyOrderIndex=\(expected), " +
                                "got \(entry.bodyOrderIndex ?? -1)")
                            expected += 1
                        } else {
                            XCTAssertNil(entry.bodyOrderIndex,
                                "\(cell.label) tile=\(packet.tileIndex): " +
                                "non-included block must have nil bodyOrderIndex")
                        }
                    }
                }
            }
        }
    }
}
