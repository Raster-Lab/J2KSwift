// HTNativeMultiTileAssemblerTests.swift
// v6-alpha3 step 5 — structural + correctness gates for the native
// multi-tile codestream assembler.
//
// What changed in step 5: `J2KMultiTileEncoder.encode(...)` no longer
// produces N standalone per-tile codestreams and stitches them at byte
// level. Instead it calls a new `EncoderPipeline.encodeNativeMultiTile`
// that emits a single legal codestream with one main header (SOC +
// SIZ + CAP/CPF + COD + QCD + COM) and N tile-parts (SOT + SOD +
// tile-data) followed by EOC.
//
// These tests verify the structural invariants of that output and
// the cross-decode behaviour:
//
//   - testNativeAssemblerEmitsSingleSOC
//   - testNativeAssemblerEmitsSingleSIZ
//   - testNativeAssemblerEmitsExpectedSOTCountFor2x2
//   - testNativeAssemblerSOTTileIndicesAreCorrect
//   - testNativeAssemblerPsotLengthsAreValid
//   - testNativeAssemblerDoesNotCopyPerTileMainHeaders
//   - testNativeAssemblerXA2x2SelfRoundtrip
//   - testNativeAssemblerXA2x2CrossDecodeOpenJPHGrokKakadu
//   - testNativeAssemblerMR2x2DoesNotUseWrapAndStitch
//   - testNativeAssemblerPX2x2DoesNotUseWrapAndStitch
//   - testNativeAssemblerDX2x2DoesNotUseWrapAndStitch
//
// SCOPE: structural correctness + XA cross-decode regression. The
// MR/PX/DX cells (planner-bypassed) verify the assembler completes
// and produces a well-formed codestream — not that the J2KSwift
// decoder can roundtrip them yet (the inverse 5/3 DWT becoming
// parity-aware is v6-alpha3 step 6).

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTNativeMultiTileAssemblerTests: XCTestCase {

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

    private func syntheticImage(width: Int, height: Int, seed: UInt64 = 0xC0FEE) -> J2KImage {
        // Deterministic 16-bit BE pixel data so tests are reproducible.
        var data = Data(count: width * height * 2)
        var rng: UInt64 = seed
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

    /// Force a 2×2 layout regardless of planner preferences. Used by
    /// the structural tests — we want to see the multi-tile output
    /// even on fixtures the production planner would reject.
    private func layout2x2(_ image: J2KImage) -> J2KTileLayout {
        let tw = (image.width  + 1) / 2
        let th = (image.height + 1) / 2
        return J2KTileLayout(
            cols: 2, rows: 2, tileWidth: tw, tileHeight: th,
            imageWidth: image.width, imageHeight: image.height)
    }

    // MARK: - Marker scanning

    /// Scan a JPEG 2000 codestream and return offsets of every
    /// non-trivial marker. Skips bytes inside SOT-bounded tile-part
    /// payloads (uses Psot to leap past them so packet bytes that
    /// happen to contain `0xFFxx` aren't misread as markers).
    private static func scanMarkers(_ data: Data) -> [(offset: Int, code: UInt16)] {
        var out: [(Int, UInt16)] = []
        var i = 0
        var psotRemaining = 0
        while i < data.count - 1 {
            if psotRemaining > 0 {
                // Skip past the tile-part body (Psot bytes from start
                // of SOT, minus the 12 SOT bytes we already advanced).
                let skip = min(psotRemaining, data.count - i)
                i += skip
                psotRemaining = 0
                continue
            }
            if data[i] == 0xFF, data[i + 1] >= 0x4F {
                let code = (UInt16(data[i]) << 8) | UInt16(data[i + 1])
                let m = data[i + 1]
                out.append((i, code))
                switch m {
                case 0x4F:                    // SOC — no segment
                    i += 2
                case 0xD9:                    // EOC — no segment
                    i += 2
                case 0x93:                    // SOD — no segment
                    i += 2
                case 0x90 where i + 11 < data.count:    // SOT — Lsot=10
                    let psot = (Int(data[i + 6]) << 24)
                             | (Int(data[i + 7]) << 16)
                             | (Int(data[i + 8]) << 8)
                             |  Int(data[i + 9])
                    // Per spec the SOD marker (0xFF93) sits
                    // immediately after the 12-byte SOT marker
                    // segment. Surface it here before we leap past
                    // the tile-part body so callers can count SOD
                    // markers without iterating tile-data bytes
                    // (which contain arbitrary 0xFFxx noise).
                    if i + 13 < data.count, data[i + 12] == 0xFF, data[i + 13] == 0x93 {
                        out.append((i + 12, 0xFF93))
                    }
                    psotRemaining = psot - 12  // already consumed 12 SOT bytes below
                    i += 12
                default:
                    if i + 4 <= data.count {
                        let len = (Int(data[i + 2]) << 8) | Int(data[i + 3])
                        i += 2 + len
                    } else {
                        i += 2
                    }
                }
            } else {
                i += 1
            }
        }
        return out
    }

    private static func sotInfo(_ data: Data, offset: Int) -> (isot: Int, psot: Int)? {
        guard offset + 11 < data.count else { return nil }
        let isot = (Int(data[offset + 4]) << 8) | Int(data[offset + 5])
        let psot = (Int(data[offset + 6]) << 24)
                 | (Int(data[offset + 7]) << 16)
                 | (Int(data[offset + 8]) << 8)
                 |  Int(data[offset + 9])
        return (isot, psot)
    }

    private static func sizFields(_ data: Data, offset: Int) -> (xsiz: Int, ysiz: Int, xtsiz: Int, ytsiz: Int)? {
        // SIZ marker is 2 bytes (0xFF51) + 2-byte Lsiz + payload.
        // Field offsets within the *payload* (after Lsiz) are spec-defined.
        guard offset + 30 < data.count else { return nil }
        // Payload starts at offset+4 (skip marker+Lsiz). Layout:
        //   payload[0..1]  Rsiz
        //   payload[2..5]  Xsiz
        //   payload[6..9]  Ysiz
        //   payload[10..13] XOsiz
        //   payload[14..17] YOsiz
        //   payload[18..21] XTsiz
        //   payload[22..25] YTsiz
        let p = offset + 4
        func u32(_ a: Int) -> Int {
            (Int(data[a]) << 24) | (Int(data[a+1]) << 16) | (Int(data[a+2]) << 8) | Int(data[a+3])
        }
        return (u32(p + 2), u32(p + 6), u32(p + 18), u32(p + 22))
    }

    // MARK: - 1. Single SOC

    func testNativeAssemblerEmitsSingleSOC() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let socCount = Self.scanMarkers(cs).filter { $0.code == 0xFF4F }.count
        XCTAssertEqual(socCount, 1, "native multi-tile must emit exactly one SOC")
    }

    // MARK: - 2. Single SIZ

    func testNativeAssemblerEmitsSingleSIZ() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let sizMarkers = Self.scanMarkers(cs).filter { $0.code == 0xFF51 }
        XCTAssertEqual(sizMarkers.count, 1, "native multi-tile must emit exactly one SIZ in main header")

        // Verify SIZ encodes full image dims + tile grid.
        guard let siz = sizMarkers.first else { return }
        guard let f = Self.sizFields(cs, offset: siz.offset) else {
            XCTFail("could not parse SIZ fields"); return
        }
        XCTAssertEqual(f.xsiz, 1024, "SIZ Xsiz must be full image width")
        XCTAssertEqual(f.ysiz, 1024, "SIZ Ysiz must be full image height")
        XCTAssertEqual(f.xtsiz, 512, "SIZ XTsiz must be tile width (not image width)")
        XCTAssertEqual(f.ytsiz, 512, "SIZ YTsiz must be tile height")
    }

    // MARK: - 3. Expected SOT count

    func testNativeAssemblerEmitsExpectedSOTCountFor2x2() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let sotCount = Self.scanMarkers(cs).filter { $0.code == 0xFF90 }.count
        XCTAssertEqual(sotCount, 4, "2x2 layout must emit exactly 4 SOT markers")

        // And exactly 4 SODs for parity.
        let sodCount = Self.scanMarkers(cs).filter { $0.code == 0xFF93 }.count
        XCTAssertEqual(sodCount, 4, "2x2 layout must emit exactly 4 SOD markers")
    }

    // MARK: - 4. SOT tile indices monotonic 0..N-1

    func testNativeAssemblerSOTTileIndicesAreCorrect() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let sotOffsets = Self.scanMarkers(cs)
            .filter { $0.code == 0xFF90 }
            .map { $0.offset }
        XCTAssertEqual(sotOffsets.count, 4)
        let isots = sotOffsets.compactMap { Self.sotInfo(cs, offset: $0)?.isot }
        XCTAssertEqual(isots, [0, 1, 2, 3],
                       "SOT Isot fields must be 0, 1, 2, 3 in row-major order for 2x2")
    }

    // MARK: - 5. Psot lengths valid (each tile-part body matches Psot)

    func testNativeAssemblerPsotLengthsAreValid() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let sotOffsets = Self.scanMarkers(cs)
            .filter { $0.code == 0xFF90 }
            .map { $0.offset }
        XCTAssertEqual(sotOffsets.count, 4)

        // For each SOT, walk forward Psot bytes and verify we land on
        // either the next SOT or the EOC.
        let sortedSot = sotOffsets.sorted()
        for (idx, sot) in sortedSot.enumerated() {
            guard let info = Self.sotInfo(cs, offset: sot) else {
                XCTFail("Psot/Isot unreadable at \(sot)"); continue
            }
            let nextOffset = sot + info.psot
            if idx + 1 < sortedSot.count {
                XCTAssertEqual(nextOffset, sortedSot[idx + 1],
                    "SOT \(idx) Psot=\(info.psot) must land on SOT \(idx + 1)")
            } else {
                // Last tile — Psot lands on EOC.
                XCTAssertEqual(cs[nextOffset], 0xFF,
                    "last SOT's Psot=\(info.psot) must land on EOC marker (got byte 0x\(String(format: "%02x", cs[nextOffset])))")
                XCTAssertEqual(cs[nextOffset + 1], 0xD9,
                    "last SOT's Psot must land on EOC marker (second byte)")
            }
        }
    }

    // MARK: - 6. No per-tile main headers stitched in

    func testNativeAssemblerDoesNotCopyPerTileMainHeaders() async throws {
        // The wrap-and-stitch path produced one SIZ per tile (4 in
        // a 2x2 layout) because each per-tile codestream had its own
        // main header that was only partially patched. The native
        // assembler emits ONE SIZ. Same for COD/QCD/CAP/CPF.
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let scanned = Self.scanMarkers(cs)
        for (code, name) in [(UInt16(0xFF51), "SIZ"), (UInt16(0xFF52), "COD"),
                             (UInt16(0xFF5C), "QCD"), (UInt16(0xFF50), "CAP"),
                             (UInt16(0xFF59), "CPF")] {
            let count = scanned.filter { $0.code == code }.count
            XCTAssertLessThanOrEqual(count, 1,
                "native multi-tile must emit at most 1 \(name) (got \(count))")
        }
    }

    // MARK: - 7. XA 2x2 self-roundtrip bit-exact

    func testNativeAssemblerXA2x2SelfRoundtrip() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(cs)
        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
        XCTAssertEqual(maxDiff, 0,
                       "native XA 2x2 self-roundtrip must remain bit-exact post step 5")
    }

    // MARK: - 8. XA 2x2 cross-decode through external HT decoders

    func testNativeAssemblerXA2x2CrossDecodeOpenJPHGrokKakadu() async throws {
        let img = syntheticImage(width: 1024, height: 1024)
        let pipeline = EncoderPipeline(config: htConfig())
        let layout = layout2x2(img)
        let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)

        let scratch = NSTemporaryDirectory() + "v6alpha3_step5/"
        try? FileManager.default.createDirectory(
            atPath: scratch, withIntermediateDirectories: true)
        let codestreamPath = scratch + "XA_native_2x2.j2k"
        try cs.write(to: URL(fileURLWithPath: codestreamPath))

        for codec in [CrossCodecTooling.Codec.openjph, .grok, .kakadu] {
            let outPath = scratch + "XA_native_2x2_\(codec).pgm"
            let dec = try CrossCodecTooling.decompressLossless(
                codec, input: codestreamPath, output: outPath)
            XCTAssertEqual(dec.status, 0,
                "XA 2x2 native via \(codec): decoder must exit 0 (got \(dec.status))")
            guard let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPath))
            else { XCTFail("XA 2x2 native via \(codec): cannot read decoded PGM"); continue }
            let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, crossImg)
            XCTAssertEqual(maxDiff, 0,
                "XA 2x2 native via \(codec): cross-decode must remain bit-exact (max diff \(maxDiff))")
        }
    }

    // MARK: - 9, 10, 11. MR / PX / DX use native, not wrap-and-stitch

    /// For each non-32-aligned fixture, the native assembler must:
    ///   - complete without trapping
    ///   - produce a structurally valid codestream (single SOC + SIZ
    ///     + COD + QCD; expected number of SOTs)
    ///   - declare the full image dimensions in SIZ, not tile dims
    /// Cross-decode bit-exactness is a separate concern (the J2KSwift
    /// decoder is not yet parity-aware — step 6).
    private func runStructuralProbe(
        modality: String, shape: String,
        cols: Int, rows: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        guard let fixture = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == modality && $0.labelHint == shape
        }), let url = CrossCodecTooling.fixtureURL(fixture.path),
              let img = try CrossCodecTooling.loadPGM16BE(url)
        else { throw XCTSkip("\(modality) \(shape) fixture missing") }

        let pipeline = EncoderPipeline(config: htConfig())
        let tileW = (img.width  + cols - 1) / cols
        let tileH = (img.height + rows - 1) / rows
        let layout = J2KTileLayout(
            cols: cols, rows: rows, tileWidth: tileW, tileHeight: tileH,
            imageWidth: img.width, imageHeight: img.height)
        let (cs, partials) = try await pipeline.encodeNativeMultiTile(
            img, layout: layout)
        XCTAssertEqual(partials.count, cols * rows,
            "\(modality) \(shape): expected \(cols * rows) tile partials",
            file: file, line: line)

        // Structural invariants
        let scanned = Self.scanMarkers(cs)
        XCTAssertEqual(scanned.filter { $0.code == 0xFF4F }.count, 1,
            "\(modality) \(shape): single SOC", file: file, line: line)
        XCTAssertEqual(scanned.filter { $0.code == 0xFF51 }.count, 1,
            "\(modality) \(shape): single SIZ", file: file, line: line)
        XCTAssertEqual(scanned.filter { $0.code == 0xFF52 }.count, 1,
            "\(modality) \(shape): single COD", file: file, line: line)
        XCTAssertEqual(scanned.filter { $0.code == 0xFF5C }.count, 1,
            "\(modality) \(shape): single QCD", file: file, line: line)
        XCTAssertEqual(scanned.filter { $0.code == 0xFF90 }.count, cols * rows,
            "\(modality) \(shape): N SOT markers", file: file, line: line)
        XCTAssertEqual(scanned.filter { $0.code == 0xFFD9 }.count, 1,
            "\(modality) \(shape): single EOC", file: file, line: line)

        // SIZ declares full image dims + tile grid (NOT tile dims as
        // image dims, which would be the wrap-and-stitch signature).
        if let sizOffset = scanned.first(where: { $0.code == 0xFF51 })?.offset,
           let f = Self.sizFields(cs, offset: sizOffset) {
            XCTAssertEqual(f.xsiz, img.width,
                "\(modality) \(shape): SIZ Xsiz = image width", file: file, line: line)
            XCTAssertEqual(f.ysiz, img.height,
                "\(modality) \(shape): SIZ Ysiz = image height", file: file, line: line)
            XCTAssertEqual(f.xtsiz, tileW,
                "\(modality) \(shape): SIZ XTsiz = tile width", file: file, line: line)
            XCTAssertEqual(f.ytsiz, tileH,
                "\(modality) \(shape): SIZ YTsiz = tile height", file: file, line: line)
        } else {
            XCTFail("\(modality) \(shape): SIZ unreadable", file: file, line: line)
        }
    }

    func testNativeAssemblerMR2x2DoesNotUseWrapAndStitch() async throws {
        try await runStructuralProbe(modality: "MR", shape: "886×886",
                                     cols: 2, rows: 2)
    }

    func testNativeAssemblerPX2x2DoesNotUseWrapAndStitch() async throws {
        try await runStructuralProbe(modality: "PX", shape: "2459×1316",
                                     cols: 2, rows: 2)
    }

    func testNativeAssemblerDX2x2DoesNotUseWrapAndStitch() async throws {
        try await runStructuralProbe(modality: "DX", shape: "2800×2288",
                                     cols: 2, rows: 2)
    }

    func testNativeAssemblerDX4x4DoesNotUseWrapAndStitch() async throws {
        try await runStructuralProbe(modality: "DX", shape: "2800×2288",
                                     cols: 4, rows: 4)
    }

    // MARK: - Diagnostic probe: external decoder behaviour on native non-aligned output

    /// **Diagnostic only — does NOT assert bit-exactness.** Exercises
    /// the native multi-tile assembler on every non-32-aligned medical
    /// fixture, runs the result through OpenJPH / Grok / Kakadu, and
    /// prints the per-decoder outcome (exit status, max-abs-pixel-diff
    /// vs original). Used to characterise the post-step-5 cross-decode
    /// landscape:
    ///
    ///   - exit status == 0 + maxDiff == 0  →  cross-decode bit-exact
    ///   - exit status == 0 + maxDiff  > 0  →  decoder accepts but
    ///     reconstructs wrong pixels (an encoder-side or per-tile
    ///     wire-format bug remains)
    ///   - exit status != 0                 →  decoder rejects the
    ///     codestream (a structural validity bug remains)
    ///
    /// XA 2x2 is included as a regression check: the post-step-5
    /// native path for the 32-aligned fixture must remain bit-exact
    /// through every external decoder.
    func testNativeAssemblerExternalCrossDecodeProbe() async throws {
        struct Probe {
            let modality: String
            let shape: String
            let cols: Int
            let rows: Int
        }
        let probes: [Probe] = [
            Probe(modality: "XA", shape: "1024×1024", cols: 2, rows: 2),
            Probe(modality: "MR", shape: "886×886",   cols: 2, rows: 2),
            Probe(modality: "PX", shape: "2459×1316", cols: 2, rows: 2),
            Probe(modality: "DX", shape: "2800×2288", cols: 2, rows: 2),
            Probe(modality: "DX", shape: "2800×2288", cols: 4, rows: 4),
        ]
        let codecs: [CrossCodecTooling.Codec] = [.openjph, .grok, .kakadu]
        let scratch = NSTemporaryDirectory() + "v6alpha3_step5_probe/"
        try? FileManager.default.createDirectory(
            atPath: scratch, withIntermediateDirectories: true)

        print("\n=== v6-alpha3 step 5 — native multi-tile cross-decode probe ===")
        print("(maxDiff = 0 → bit-exact; maxDiff > 0 → wrong pixels; FAIL → decoder exit non-zero)")
        print()
        print("| Modality | Shape | Mode | OpenJPH | Grok | Kakadu |")
        print("|---|---|---|---:|---:|---:|")

        for probe in probes {
            guard let fixture = CrossCodecTooling.medicalCorpus.first(where: {
                $0.modality == probe.modality && $0.labelHint == probe.shape
            }), let url = CrossCodecTooling.fixtureURL(fixture.path),
                  let img = try CrossCodecTooling.loadPGM16BE(url)
            else {
                print("| \(probe.modality) | \(probe.shape) | \(probe.cols)x\(probe.rows) | (fixture missing) | | |")
                continue
            }

            let pipeline = EncoderPipeline(config: htConfig())
            let tw = (img.width  + probe.cols - 1) / probe.cols
            let th = (img.height + probe.rows - 1) / probe.rows
            let layout = J2KTileLayout(
                cols: probe.cols, rows: probe.rows,
                tileWidth: tw, tileHeight: th,
                imageWidth: img.width, imageHeight: img.height)
            let (cs, _) = try await pipeline.encodeNativeMultiTile(img, layout: layout)
            let stem = "\(probe.modality)_\(probe.shape.replacingOccurrences(of: "×", with: "x"))_\(probe.cols)x\(probe.rows)"
            let codePath = scratch + "\(stem).j2k"
            try cs.write(to: URL(fileURLWithPath: codePath))

            var diffs: [String: String] = [:]
            for codec in codecs {
                let outPath = scratch + "\(stem)_\(codec).pgm"
                let dec = try CrossCodecTooling.decompressLossless(
                    codec, input: codePath, output: outPath)
                if dec.status != 0 {
                    diffs[codec.rawValue] = "FAIL"
                } else if let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPath)) {
                    diffs[codec.rawValue] = "\(CrossCodecTooling.maxAbsPixelDiff(img, crossImg))"
                } else {
                    diffs[codec.rawValue] = "FAIL"
                }
            }

            print("| \(probe.modality) | \(probe.shape) | \(probe.cols)x\(probe.rows) | \(diffs["openjph"] ?? "?") | \(diffs["grok"] ?? "?") | \(diffs["kakadu"] ?? "?") |")

            // Hard regression check: XA 2x2 must remain bit-exact.
            if probe.modality == "XA" && probe.cols == 2 && probe.rows == 2 {
                XCTAssertEqual(diffs["openjph"], "0", "XA 2x2 native via OpenJPH must remain bit-exact")
                XCTAssertEqual(diffs["grok"],    "0", "XA 2x2 native via Grok must remain bit-exact")
                XCTAssertEqual(diffs["kakadu"],  "0", "XA 2x2 native via Kakadu must remain bit-exact")
            }
        }
    }
}
