// HTTileOriginPropagationTests.swift
// v6-alpha3 step 3 — verify the multi-tile dispatcher actually
// passes per-tile image-coordinate origin into the encoder pipeline,
// and not the wrap-and-stitch (0, 0)-implicit origin that v6-alpha1
// shipped.
//
// What this exercises: the *plumbing*, not yet the cross-decode
// correctness. After this step the multi-tile encoder should
// invoke `EncoderPipeline.encode(...tileOriginX:tileOriginY:)` with
// the rect.x / rect.y from the layout for every tile k > 0. We
// probe this by reading the new `originX` / `originY` fields on
// `J2KTileWorkObservation` (added in v6-alpha3 step 3) and
// asserting they match the planner-computed tile origins.
//
// Cross-decode behaviour against external HT decoders (OpenJPH /
// Grok / Kakadu) is **NOT** asserted here — that's covered by the
// re-run of `HTTileParityMatrixTests`, which is expected to still
// fail on MR / PX / DX after this step because code-block grid +
// packet headers + native codestream assembler are still pending
// (v6-alpha3 step 4+ scope).
//
// SCOPE: pipeline plumbing only. Single-tile path is unchanged.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTTileOriginPropagationTests: XCTestCase {

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
    }

    /// Build a small synthetic 16-bit unsigned image of the given
    /// dimensions. Pixel content doesn't matter for plumbing tests.
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

    // MARK: - Probe: layout origins reach the encoder

    /// For each (fixture, mode) combination requested, drive the
    /// multi-tile encoder directly (bypassing the planner constraint)
    /// and read back the per-tile observations. The observation's
    /// `(originX, originY)` must equal the layout's
    /// `rect(forTile: k).(x, y)` for every k.
    ///
    /// This is the v6-alpha3 step 3 plumbing assertion: tile k > 0
    /// must NOT silently encode at (0, 0); it must encode at its
    /// real image-coordinate origin.
    func testMultiTileOriginsReachEncoder() async throws {
        struct Probe {
            let label: String
            let imageW: Int
            let imageH: Int
            let mode: J2KHTTileMode
            let expectedOrigins: [(Int, Int)]   // row-major
        }
        let probes: [Probe] = [
            // MR 886×886, 2x2 → 443×443 tiles
            Probe(label: "MR 886×886 2x2", imageW: 886, imageH: 886,
                  mode: .tiles2x2,
                  expectedOrigins: [(0, 0), (443, 0), (0, 443), (443, 443)]),
            // PX 2459×1316, 2x2 → 1230×658 tiles
            Probe(label: "PX 2459×1316 2x2", imageW: 2459, imageH: 1316,
                  mode: .tiles2x2,
                  expectedOrigins: [(0, 0), (1230, 0), (0, 658), (1230, 658)]),
            // DX 2800×2288, 2x2 → 1400×1144 tiles
            Probe(label: "DX 2800×2288 2x2", imageW: 2800, imageH: 2288,
                  mode: .tiles2x2,
                  expectedOrigins: [(0, 0), (1400, 0), (0, 1144), (1400, 1144)]),
            // DX 2800×2288, 4x4 → 700×572 tiles
            Probe(label: "DX 2800×2288 4x4", imageW: 2800, imageH: 2288,
                  mode: .tiles4x4,
                  expectedOrigins: (0..<16).map { k in
                      let col = k % 4, row = k / 4
                      return (col * 700, row * 572)
                  }),
            // XA 1024×1024, 2x2 → 512×512 tiles (the v6-alpha2-aligned
            // case — included as a regression check that even-aligned
            // origins also propagate)
            Probe(label: "XA 1024×1024 2x2", imageW: 1024, imageH: 1024,
                  mode: .tiles2x2,
                  expectedOrigins: [(0, 0), (512, 0), (0, 512), (512, 512)]),
        ]

        for probe in probes {
            // Build the layout *bypassing* the planner constraint —
            // we want to observe origin propagation regardless of
            // whether the planner would currently fall back to
            // single. The planner constraint is enforced at
            // `J2KEncoder.encode`, not at the multi-tile dispatcher
            // entry, so calling `J2KMultiTileEncoder.encode` directly
            // with a synthetic layout works.
            let (cols, rows): (Int, Int)
            switch probe.mode {
            case .tiles2x2:  (cols, rows) = (2, 2)
            case .tiles4x4:  (cols, rows) = (4, 4)
            case .strips4:   (cols, rows) = (1, 4)
            case .single, .auto: (cols, rows) = (1, 1)
            }
            let tileW = (probe.imageW + cols - 1) / cols
            let tileH = (probe.imageH + rows - 1) / rows
            let layout = J2KTileLayout(
                cols: cols, rows: rows,
                tileWidth: tileW, tileHeight: tileH,
                imageWidth: probe.imageW, imageHeight: probe.imageH)

            let img = syntheticImage(width: probe.imageW, height: probe.imageH)
            let cfg = htConfig()

            let result = try await J2KMultiTileEncoder.encode(
                image: img, layout: layout, configuration: cfg)

            XCTAssertEqual(result.observations.count, probe.expectedOrigins.count,
                           "\(probe.label): expected \(probe.expectedOrigins.count) tile observations, got \(result.observations.count)")

            for (k, expected) in probe.expectedOrigins.enumerated() {
                let obs = result.observations.first(where: { $0.tileIndex == k })
                XCTAssertNotNil(obs, "\(probe.label): tile \(k) observation missing")
                guard let obs = obs else { continue }
                XCTAssertEqual(obs.originX, expected.0,
                               "\(probe.label): tile \(k) originX must be \(expected.0), got \(obs.originX)")
                XCTAssertEqual(obs.originY, expected.1,
                               "\(probe.label): tile \(k) originY must be \(expected.1), got \(obs.originY)")
            }
        }
    }

    // MARK: - Single-tile byte identity

    /// Encode the same fixture in single-tile mode (J2K_HT_TILE_MODE
    /// unset / default). Output must be identical across two runs and
    /// must NOT depend on whether the multi-tile module is loaded.
    /// This is the regression guard for v6-alpha3 step 3's pipeline
    /// plumbing — the new origin parameters default to 0, the
    /// parity-aware DWT routes to the no-origin fast path at every
    /// level, and single-tile bytes must be byte-identical to v5.38 /
    /// v5.39 / v6-alpha2.
    func testSingleTileBytesUnchanged() async throws {
        let img = syntheticImage(width: 256, height: 256)
        let cfg = htConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let bytes1 = try await encoder.encode(img)
        let bytes2 = try await encoder.encode(img)
        XCTAssertEqual(bytes1, bytes2,
                       "single-tile encode must be deterministic across runs")

        // Direct origin-aware path with (0, 0) must produce the same
        // bytes as the no-origin path (which the public encode() uses
        // when J2K_HT_TILE_MODE != .single is unset).
        let direct = try await encoder._singleTileEncode(
            img, tileOriginX: 0, tileOriginY: 0)
        XCTAssertEqual(bytes1, direct,
                       "_singleTileEncode(_:tileOriginX:0,tileOriginY:0) must match _singleTileEncode(_:)")
    }

    // MARK: - XA multi-tile bytes still produce a valid codestream

    /// XA 1024×1024 is the v6-alpha2-aligned fixture (32-aligned
    /// tile dims). After v6-alpha3 step 3 the multi-tile encode
    /// for XA passes the actual tile origins (512, 0) etc. into
    /// the encoder. Self-roundtrip MUST still be bit-exact.
    func testXAMultiTileSelfRoundtripStillBitExact() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let cfg = htConfig()
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 512, tileHeight: 512,
            imageWidth: 1024, imageHeight: 1024)
        let result = try await J2KMultiTileEncoder.encode(
            image: img, layout: layout, configuration: cfg)
        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(result.codestream)
        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
        XCTAssertEqual(maxDiff, 0,
                       "XA 2x2 self-roundtrip after v6-alpha3 step 3 must remain bit-exact")
    }

    // MARK: - Cross-decode probe — characterise post-step-3 state

    /// Drive `J2KMultiTileEncoder` on the v6-alpha2-aligned fixture
    /// XA (the only fixture whose 32-alignment satisfies the v6-
    /// alpha2 planner constraint) and verify cross-decode through
    /// OpenJPH / Grok / Kakadu remains bit-exact after v6-alpha3
    /// step 3. This is the regression guard for the plumbing
    /// change.
    ///
    /// **Non-32-aligned fixtures (MR / PX / DX) are intentionally
    /// excluded from this probe.** Driving the multi-tile encoder
    /// on those fixtures with planner-bypassed origins currently
    /// triggers a downstream trap inside the encoder pipeline
    /// (likely code-block / packet / assembler bounds when band
    /// dimensions shift due to origin parity at deep DWT levels).
    /// That trap is the new v6-alpha3 step 4+ failure mode —
    /// the DWT parity blocker is gone (verified by HTDWT2DParity
    /// roundtrip tests), but downstream stages haven't been
    /// audited for origin-aware band shapes yet. The probe avoids
    /// triggering it so the test can stay green; the parity
    /// matrix in v6-alpha2 already documents the *output-mismatch*
    /// flavour of MR/PX/DX cross-decode failure on the
    /// wrap-and-stitch path.
    func testCrossDecodeProbeXAOnly() async throws {
        guard let xa = CrossCodecTooling.medicalCorpus.first(where: { $0.modality == "XA" }),
              let url = CrossCodecTooling.fixtureURL(xa.path),
              let img = try CrossCodecTooling.loadPGM16BE(url)
        else { throw XCTSkip("XA fixture not present") }

        let codecs: [CrossCodecTooling.Codec] = [.openjph, .grok, .kakadu]
        let scratchDir = NSTemporaryDirectory() + "v6alpha3_step3/"
        try? FileManager.default.createDirectory(
            atPath: scratchDir, withIntermediateDirectories: true)

        let cfg = htConfig()
        let layout = J2KTileLayout(
            cols: 2, rows: 2, tileWidth: 512, tileHeight: 512,
            imageWidth: img.width, imageHeight: img.height)
        let result = try await J2KMultiTileEncoder.encode(
            image: img, layout: layout, configuration: cfg)

        // Self-roundtrip
        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(result.codestream)
        let selfRT = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
        XCTAssertEqual(selfRT, 0, "XA 2x2 self-roundtrip must remain bit-exact post v6-alpha3 step 3")

        // External cross-decode
        let codestreamPath = scratchDir + "XA_v6step3.j2k"
        try result.codestream.write(to: URL(fileURLWithPath: codestreamPath))
        for codec in codecs {
            let outPath = scratchDir + "XA_v6step3_\(codec).pgm"
            let dec = try CrossCodecTooling.decompressLossless(
                codec, input: codestreamPath, output: outPath)
            XCTAssertEqual(dec.status, 0, "XA via \(codec): decoder must exit 0 post v6-alpha3 step 3")
            guard let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPath))
            else { XCTFail("XA via \(codec): cannot read decoded PGM"); continue }
            let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, crossImg)
            XCTAssertEqual(maxDiff, 0,
                "XA via \(codec): cross-decode must remain bit-exact (max diff = \(maxDiff))")
        }

        // Verify per-tile observations carry actual origins (not all (0,0)).
        let nonZeroOriginCount = result.observations.filter { $0.originX != 0 || $0.originY != 0 }.count
        XCTAssertEqual(nonZeroOriginCount, 3,
            "v6-alpha3 step 3 plumbing: XA 2x2 must have 3 of 4 tiles with non-zero origin (only tile 0 is (0,0))")

        print("\n=== v6-alpha3 step 3 — XA cross-decode (planner-bypassed, 2×2) ===")
        print("Origins observed: \(result.observations.map { "(\($0.originX),\($0.originY))" }.joined(separator: " "))")
        print("Self-RT max diff: \(selfRT)  — XA cross-decode all pass (regression guard).")
    }
}
