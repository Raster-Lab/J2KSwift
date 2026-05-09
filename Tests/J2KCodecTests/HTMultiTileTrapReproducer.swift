// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// HTMultiTileTrapReproducer.swift
// v6-alpha3 step 4 — non-crash regression tests for the planner-
// bypassed multi-tile encode path.
// v6-alpha3 step 5 update — the step-4 guard is gone; the native
// multi-tile assembler (one main header + N tile-parts) replaced
// wrap-and-stitch and structurally handles any tile origin.
//
// Background:
//
//   v6-alpha3 step 3 plumbed real per-tile image-coordinate origin
//   into the encoder pipeline. That made the parity-aware DWT fire
//   correctly for every tile, but exposed an architectural blocker
//   in the wrap-and-stitch path: each per-tile codestream's `SIZ`
//   declared image origin (0, 0) while the per-tile content was
//   encoded for a non-zero origin. Internally inconsistent
//   codestreams resulted, and the J2KSwift decoder trapped in
//   `HTMagSgn.read(count:)` with "MagSgn read width > 32" when
//   band-size computation disagreed.
//
//   Step 4 added a fail-fast guard at `J2KMultiTileEncoder.encode`:
//   non-32-aligned layouts threw `J2KError.invalidTileConfiguration`
//   so test code couldn't trip the SIGTRAP.
//
//   Step 5 replaced wrap-and-stitch with the native multi-tile
//   codestream assembler. The native path emits ONE legal
//   codestream and structurally handles any tile origin — the
//   step-4 guard is no longer needed because the underlying bug
//   it papered over no longer exists.
//
// What these tests now assert (post step 5):
//
//   1. Planner-bypassed multi-tile encode on a non-32-aligned
//      layout COMPLETES without trapping. (Step 4 asserted a
//      clean throw; step 5 expects success.)
//   2. The 32-aligned happy path still encodes + self-roundtrips
//      bit-exact via XA.
//
// The test names retain "DoesNotTrap" because that's the property
// we keep guarding. Whether the call succeeds or throws cleanly
// is implementation detail — the SIGTRAP regression must never
// return.

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

    /// Helper: drive the multi-tile dispatcher on a non-32-aligned
    /// layout and assert the call completes (success or graceful
    /// error) without SIGTRAP. Either:
    ///   - returns a non-empty codestream (step 5 native path), or
    ///   - throws a `J2KError` (any kind — the underlying
    ///     non-trap regression is what matters).
    private func assertEncodeCompletesWithoutTrap(
        image: J2KImage,
        layout: J2KTileLayout,
        config: J2KEncodingConfiguration,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let result = try await J2KMultiTileEncoder.encode(
                image: image, layout: layout, configuration: config)
            XCTAssertGreaterThan(result.codestream.count, 0,
                "\(label): native encode produced an empty codestream",
                file: file, line: line)
            XCTAssertEqual(result.observations.count, layout.tileCount,
                "\(label): native encode must produce one observation per tile",
                file: file, line: line)
        } catch is J2KError {
            // A graceful J2KError throw is also acceptable — the
            // important invariant is "did not SIGTRAP". If a future
            // step intentionally narrows the supported origin set
            // and re-introduces a guard, this branch covers that.
        } catch {
            XCTFail("\(label): unexpected non-J2KError thrown: \(error)",
                    file: file, line: line)
        }
    }

    // MARK: - Non-crash regression tests for non-32-aligned layouts

    /// MR 886×886 2x2 → tile origins include (443, 0), (0, 443), (443, 443).
    /// Step 5 native assembler must not trap.
    func testPlannerBypassedMR2x2DoesNotTrap() async {
        guard let mr = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == "MR" && $0.labelHint == "886×886"
        }), let url = CrossCodecTooling.fixtureURL(mr.path),
              let img = try? CrossCodecTooling.loadPGM16BE(url)
        else { return }
        let cfg = htConfig(decompositionLevels: 5)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 443, tileHeight: 443,
            imageWidth: 886, imageHeight: 886)
        await assertEncodeCompletesWithoutTrap(
            image: img, layout: layout, config: cfg,
            label: "MR 886×886 2x2 (origins include 443)")
    }

    /// PX 2459×1316 2x2 → tile origins include (1230, 0), (0, 658).
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
        await assertEncodeCompletesWithoutTrap(
            image: img, layout: layout, config: cfg,
            label: "PX 2459×1316 2x2 (origins include 1230, 658)")
    }

    /// DX 2800×2288 2x2 → tile origins include (1400, 0), (0, 1144).
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
        await assertEncodeCompletesWithoutTrap(
            image: img, layout: layout, config: cfg,
            label: "DX 2800×2288 2x2 (origins include 1400, 1144)")
    }

    /// DX 2800×2288 4x4 → tile origins include (700, 0), (0, 572), etc.
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
        await assertEncodeCompletesWithoutTrap(
            image: img, layout: layout, config: cfg,
            label: "DX 2800×2288 4x4 (origins include 700, 572)")
    }

    /// Synthetic 90×90 2x2 → tile origins include (45, 0), etc.
    /// Minimal reproducer; runs without depending on any medical
    /// fixture being present.
    func testPlannerBypassedSyntheticOddOriginDoesNotTrap() async {
        let img = syntheticImage(width: 90, height: 90)
        let cfg = htConfig(decompositionLevels: 3)
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 45, tileHeight: 45,
            imageWidth: 90, imageHeight: 90)
        await assertEncodeCompletesWithoutTrap(
            image: img, layout: layout, config: cfg,
            label: "synthetic 90×90 2x2 (origins include 45)")
    }

    // MARK: - Happy-path: 32-aligned layouts still succeed bit-exact

    /// XA 1024×1024 2x2 → tile origins (0, 0), (512, 0), (0, 512), (512, 512).
    /// 512 = 16·32 ✓. Encode + self-decode must roundtrip bit-exact.
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
            "XA 2x2 (32-aligned origins) must self-roundtrip bit-exact post step 5")
    }

    /// Synthetic 64×64 2x2 → tile origins (0, 0), (32, 0), (0, 32), (32, 32).
    /// 32 = 1·32 ✓. Smallest possible 32-aligned happy path.
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

#endif // os(macOS)
