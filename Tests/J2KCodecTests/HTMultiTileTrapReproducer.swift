// HTMultiTileTrapReproducer.swift
// v6-alpha3 step 4 — non-crash regression tests for the planner-
// bypassed multi-tile encode path.
//
// Background: v6-alpha3 step 3 plumbed real per-tile image-coordinate
// origin into the encoder pipeline. That made the parity-aware DWT
// fire correctly for every tile, but exposed an architectural blocker
// in the wrap-and-stitch path: each per-tile codestream's `SIZ`
// marker still declares image origin (0, 0), while the per-tile
// content was now encoded at a non-zero image-coordinate origin.
// Internally inconsistent codestreams resulted, and the J2KSwift
// decoder trapped in `HTMagSgn.read(count:)` with "MagSgn read
// width > 32" when band-size computation based on the (0, 0)-origin
// SIZ disagreed with the encoder's parity-aware band sizes.
//
// Step 4's fix (lands in this commit): a guard inside
// `J2KMultiTileEncoder.encode(...)` that refuses any layout whose
// tile origins aren't multiples of `2^decompositionLevels`. The
// guard throws `J2KError.invalidTileConfiguration` with a clear
// message. Production (planner-constrained) never sees such layouts;
// only test code that bypasses the planner can hit this guard.
//
// These tests verify two invariants:
//
//   1. The fail-fast behaviour: planner-bypassed multi-tile encode
//      on a non-32-aligned layout cleanly throws (no SIGTRAP).
//   2. The 32-aligned happy path remains correct: layouts that
//      satisfy the constraint still encode + decode bit-exact.
//
// Once the v6-alpha3 step 5+ native multi-tile assembler lands and
// the J2KSwift decoder becomes parity-aware, the guard can be
// relaxed and these tests will be updated to verify successful
// encode + cross-decode on MR/PX/DX.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTMultiTileTrapReproducer: XCTestCase {

    /// Build a synthetic 16-bit BE image of the given dimensions.
    private func syntheticImage(width: Int, height: Int) -> J2KImage {
        var data = Data(count: width * height * 2)
        for i in 0..<(width * height) {
            let v = UInt16((i * 7) % 65536)
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

    /// Helper: assert that running the multi-tile encoder on the
    /// given (image, layout) cleanly throws
    /// `J2KError.invalidTileConfiguration`. The test fails if the
    /// call succeeds, traps, or throws a different error.
    private func assertEncodeThrowsInvalidTileConfig(
        image: J2KImage,
        layout: J2KTileLayout,
        config: J2KEncodingConfiguration,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await J2KMultiTileEncoder.encode(
                image: image, layout: layout, configuration: config)
            XCTFail("\(label): expected J2KError.invalidTileConfiguration but encode succeeded",
                    file: file, line: line)
        } catch let err as J2KError {
            switch err {
            case .invalidTileConfiguration:
                return  // expected
            default:
                XCTFail("\(label): got J2KError.\(err) — expected .invalidTileConfiguration",
                        file: file, line: line)
            }
        } catch {
            XCTFail("\(label): unexpected non-J2KError thrown: \(error)",
                    file: file, line: line)
        }
    }

    // MARK: - Non-crash regression tests for non-32-aligned layouts

    /// MR 886×886 2x2 → tile origins include (443, 0), (0, 443), (443, 443).
    /// 443 is not a multiple of 32. Step 4's guard must refuse this layout.
    func testPlannerBypassedMR2x2DoesNotTrap() async {
        guard let mr = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == "MR" && $0.labelHint == "886×886"
        }), let url = CrossCodecTooling.fixtureURL(mr.path),
              let img = try? CrossCodecTooling.loadPGM16BE(url)
        else { return }  // skip silently if fixture missing
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 443, tileHeight: 443,
            imageWidth: 886, imageHeight: 886)
        await assertEncodeThrowsInvalidTileConfig(
            image: img, layout: layout, config: cfg,
            label: "MR 886×886 2x2 (origins include 443)")
    }

    /// PX 2459×1316 2x2 → tile origins include (1230, 0), (0, 658).
    /// 1230 % 32 = 14, 658 % 32 = 18. Step 4's guard must refuse.
    func testPlannerBypassedPX2x2DoesNotTrap() async {
        guard let px = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == "PX" && $0.labelHint == "2459×1316"
        }), let url = CrossCodecTooling.fixtureURL(px.path),
              let img = try? CrossCodecTooling.loadPGM16BE(url)
        else { return }
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 1230, tileHeight: 658,
            imageWidth: 2459, imageHeight: 1316)
        await assertEncodeThrowsInvalidTileConfig(
            image: img, layout: layout, config: cfg,
            label: "PX 2459×1316 2x2 (origins include 1230, 658)")
    }

    /// DX 2800×2288 2x2 → tile origins include (1400, 0), (0, 1144).
    /// 1400 % 32 = 24, 1144 % 32 = 24. Step 4's guard must refuse.
    func testPlannerBypassedDX2x2DoesNotTrap() async {
        guard let dx = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == "DX" && $0.labelHint == "2800×2288"
        }), let url = CrossCodecTooling.fixtureURL(dx.path),
              let img = try? CrossCodecTooling.loadPGM16BE(url)
        else { return }
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 1400, tileHeight: 1144,
            imageWidth: 2800, imageHeight: 2288)
        await assertEncodeThrowsInvalidTileConfig(
            image: img, layout: layout, config: cfg,
            label: "DX 2800×2288 2x2 (origins include 1400, 1144)")
    }

    /// DX 2800×2288 4x4 → tile origins include (700, 0), (0, 572), etc.
    /// 700 % 32 = 28, 572 % 32 = 28. Step 4's guard must refuse.
    func testPlannerBypassedDX4x4DoesNotTrap() async {
        guard let dx = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == "DX" && $0.labelHint == "2800×2288"
        }), let url = CrossCodecTooling.fixtureURL(dx.path),
              let img = try? CrossCodecTooling.loadPGM16BE(url)
        else { return }
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 4, rows: 4, tileWidth: 700, tileHeight: 572,
            imageWidth: 2800, imageHeight: 2288)
        await assertEncodeThrowsInvalidTileConfig(
            image: img, layout: layout, config: cfg,
            label: "DX 2800×2288 4x4 (origins include 700, 572)")
    }

    /// Synthetic 90×90 2x2 → tile origins include (45, 0), etc.
    /// 45 % 32 = 13. Step 4's guard must refuse. This is the
    /// minimal reproducer — runs without depending on any
    /// medical fixture being present.
    func testPlannerBypassedSyntheticOddOriginDoesNotTrap() async {
        let img = syntheticImage(width: 90, height: 90)
        let cfg = htConfig(decompositionLevels: 3)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 45, tileHeight: 45,
            imageWidth: 90, imageHeight: 90)
        await assertEncodeThrowsInvalidTileConfig(
            image: img, layout: layout, config: cfg,
            label: "synthetic 90×90 2x2 (origins include 45)")
    }

    // MARK: - Happy-path: 32-aligned layouts still succeed

    /// XA 1024×1024 2x2 → tile origins (0, 0), (512, 0), (0, 512), (512, 512).
    /// 512 = 16·32 ✓. The guard must NOT block this; the encode + self-decode
    /// must succeed bit-exact (regression guard for v6-alpha2 / step 3 XA work).
    func testThirtyTwoAlignedXAStillSucceeds() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 512, tileHeight: 512,
            imageWidth: 1024, imageHeight: 1024)
        let result = try await J2KMultiTileEncoder.encode(
            image: img, layout: layout, configuration: cfg)
        XCTAssertEqual(result.observations.count, 4)
        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(result.codestream)
        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
        XCTAssertEqual(maxDiff, 0,
            "XA 2x2 (32-aligned origins) must self-roundtrip bit-exact post step 4")
    }

    /// Synthetic 64×64 2x2 → tile origins (0, 0), (32, 0), (0, 32), (32, 32).
    /// 32 = 1·32 ✓. Minimal happy-path test — exercises the guard's
    /// allow-pass branch on the smallest possible 32-aligned layout.
    func testThirtyTwoAlignedSyntheticStillSucceeds() async throws {
        let img = syntheticImage(width: 64, height: 64)
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 32, tileHeight: 32,
            imageWidth: 64, imageHeight: 64)
        let result = try await J2KMultiTileEncoder.encode(
            image: img, layout: layout, configuration: cfg)
        XCTAssertEqual(result.observations.count, 4)
    }
}
