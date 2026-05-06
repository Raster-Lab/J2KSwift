// HTTilePlannerRelaxationTests.swift
// v6-alpha3 step 7 — planner-relaxation regression tests.
//
// v6-alpha2 imposed a 32-alignment constraint on the multi-tile
// planner: tile width and tile height each had to be a multiple of
// `2^decompositionLevels` or the planner fell back to single-tile.
// That constraint existed because the v6-alpha1 wrap-and-stitch
// encoder produced bytes that external decoders read with wrong
// pixels for any non-32-aligned tile origin. The v6-alpha3 work
// (step 1+2+3 origin-aware DWT, step 5 native multi-tile assembler,
// step 6A canvas-anchored block grid, step 6B parity-aware decoder
// inverse + canvas-anchored block grid mirror) made native multi-
// tile correctness-clean on every corpus fixture × every mode
// (cross-decode bit-exact through OpenJPH/Grok/Kakadu AND
// J2KSwift self-roundtrip bit-exact).
//
// Step 7 removes the 32-alignment constraint. This file pins the
// new behaviour:
//
//   - MR/PX/DX 2x2 + 4x4 layouts no longer fall back to single
//   - XA continues to fire multi-tile (regression guard for the
//     v6-alpha2-aligned fixture)
//   - The per-tile DWT depth floor (constraint 1) is intact —
//     tile dimensions below `2^decompositionLevels` still
//     fall back to single-tile (else the per-tile DWT cannot run)
//
// The HTTileParityMatrixTests suite (which probes external cross-
// decode for every (fixture, mode) cell the planner accepts) is
// the end-to-end correctness gate; this file is the planner-only
// unit gate.

import XCTest
@testable import J2KCodec

final class HTTilePlannerRelaxationTests: XCTestCase {

    // MARK: - Non-32-aligned fixtures must NOT fall back

    /// MR 886×886 2x2: tile dims 443×443. 443 is not a multiple
    /// of 32 → pre-step-7 the planner returned single (1x1).
    /// Post-step-7 the planner accepts the 2x2 layout.
    func testMR886x886_2x2_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 886, imageHeight: 886,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertEqual(layout.cols, 2, "MR 886×886 2x2 must produce 2 cols post-step-7")
        XCTAssertEqual(layout.rows, 2, "MR 886×886 2x2 must produce 2 rows post-step-7")
        XCTAssertTrue(layout.isMultiTile, "MR 886×886 2x2 must fire multi-tile post-step-7")
        XCTAssertEqual(layout.tileWidth, 443)
        XCTAssertEqual(layout.tileHeight, 443)
    }

    /// MR 886×886 4x4: tile dims 222×222.
    func testMR886x886_4x4_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 886, imageHeight: 886,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 4)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 222)
        XCTAssertEqual(layout.tileHeight, 222)
    }

    /// PX 2459×1316 2x2: tile dims 1230×658. Trailing column is
    /// 1229 wide; trailing row is 658 tall — but the LAYOUT's
    /// nominal tileWidth/tileHeight is 1230×658. The planner only
    /// cares about whether tileW/tileH meet the DWT depth floor;
    /// trailing-tile clipping happens at `rect(forTile:)`.
    func testPX2459x1316_2x2_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2459, imageHeight: 1316,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 1230)
        XCTAssertEqual(layout.tileHeight, 658)
    }

    /// PX 2459×1316 4x4: tile dims 615×329.
    func testPX2459x1316_4x4_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2459, imageHeight: 1316,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 4)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 615)
        XCTAssertEqual(layout.tileHeight, 329)
    }

    /// DX 2800×2288 2x2: tile dims 1400×1144.
    func testDX2800x2288_2x2_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2800, imageHeight: 2288,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 1400)
        XCTAssertEqual(layout.tileHeight, 1144)
    }

    /// DX 2800×2288 4x4: tile dims 700×572.
    func testDX2800x2288_4x4_doesNotFallBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2800, imageHeight: 2288,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 4)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 700)
        XCTAssertEqual(layout.tileHeight, 572)
    }

    // MARK: - XA regression guard (was the only fixture that fired pre-step-7)

    /// XA 1024×1024 2x2: tile dims 512×512 (32-aligned). This
    /// fixture passed the v6-alpha2 32-alignment constraint and
    /// fired multi-tile pre-step-7; it must continue to fire
    /// multi-tile post-step-7.
    func testXA1024x1024_2x2_remainsMultiTile() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 1024, imageHeight: 1024,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 512)
        XCTAssertEqual(layout.tileHeight, 512)
    }

    /// XA 4x4 — tile dims 256×256 (still 32-aligned).
    func testXA1024x1024_4x4_remainsMultiTile() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 1024, imageHeight: 1024,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 4)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 256)
        XCTAssertEqual(layout.tileHeight, 256)
    }

    // MARK: - Constraint 1 (DWT depth floor) is intact

    /// Tile dim < `2^decompositionLevels` must fall back. With 5
    /// levels, `2^5 == 32`. A 64×64 image at 4x4 would give
    /// tileWidth = 16, which is below 32 → fall back to single.
    func testTinyImageBelowDWTFloorFallsBackToSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 64, imageHeight: 64,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 1, "64×64 4x4 must fall back: tileW=16 < 2^5=32")
        XCTAssertEqual(layout.rows, 1)
        XCTAssertFalse(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 64)
        XCTAssertEqual(layout.tileHeight, 64)
    }

    /// Edge case at the floor boundary: 64×64 image at 2x2 gives
    /// tileWidth = 32 (= 2^5). That meets constraint 1 exactly →
    /// must fire multi-tile.
    func testImageAtDWTFloorBoundaryFiresMultiTile() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 64, imageHeight: 64,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 32)
        XCTAssertEqual(layout.tileHeight, 32)
    }

    /// Smaller decomposition depth admits smaller tiles.
    /// With 3 levels (2^3 = 8), a 64×64 image at 4x4 gives
    /// tileWidth = 16 → above floor → multi-tile fires.
    func testSmallerDecompositionDepthAdmitsSmallerTiles() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 64, imageHeight: 64,
            decompositionLevels: 3, mode: .tiles4x4)
        XCTAssertEqual(layout.cols, 4)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertTrue(layout.isMultiTile)
        XCTAssertEqual(layout.tileWidth, 16)
        XCTAssertEqual(layout.tileHeight, 16)
    }

    // MARK: - `single` and `auto` modes

    /// `.single` mode always returns 1x1 regardless of size.
    func testSingleModeAlwaysSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2800, imageHeight: 2288,
            decompositionLevels: 5, mode: .single)
        XCTAssertEqual(layout.cols, 1)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertFalse(layout.isMultiTile)
    }

    /// `.auto` chooses 2x2 for images ≥ 3 MP, single otherwise.
    /// MR 886×886 (= 0.78 MP) → auto picks single.
    func testAutoModeBelowThresholdPicksSingle() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 886, imageHeight: 886,
            decompositionLevels: 5, mode: .auto)
        XCTAssertFalse(layout.isMultiTile,
            "MR 886×886 (0.78 MP) is below the auto threshold (3 MP)")
    }

    /// PX 2459×1316 (= 3.24 MP) → auto picks 2x2. Pre-step-7 this
    /// would have fallen back to single because 1230 isn't 32-
    /// aligned. Post-step-7 it fires multi-tile.
    func testAutoModeAboveThresholdPicks2x2_PX() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2459, imageHeight: 1316,
            decompositionLevels: 5, mode: .auto)
        XCTAssertEqual(layout.cols, 2,
            "PX 2459×1316 (3.24 MP) is above auto threshold; auto picks 2x2")
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
    }

    /// DX 2800×2288 (= 6.41 MP) → auto picks 2x2.
    func testAutoModeAboveThresholdPicks2x2_DX() {
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: 2800, imageHeight: 2288,
            decompositionLevels: 5, mode: .auto)
        XCTAssertEqual(layout.cols, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertTrue(layout.isMultiTile)
    }
}
