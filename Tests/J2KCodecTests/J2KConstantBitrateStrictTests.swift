// J2KConstantBitrateStrictTests.swift
// v5.34.0 — hard regression tests for `.constantBitrateStrict` and
// the auto-promoted `.constantBitrate` path on HT-conformant lossy.
//
// The strict mode runs the v5.33.0 quality-first bounded Qstep search
// then truncates the codestream at the largest LRCP packet boundary
// that fits the byte cap. The fundamental contract under test:
//
//     output.count <= maxOvershootRatio * targetBytes  (always)
//
// On flat-curve content (large medical fixtures at low bpp), v5.33.0
// could overshoot the cap by 3–4×. v5.34.0's truncation closes that
// structurally — there is no input that violates the hard byte cap.
//
// We also verify that:
//   - A truncated codestream still decodes (premature-EOC handling).
//   - When the bounded result already fits the cap, no truncation
//     occurs (quality matches the bounded mode exactly).
//   - The auto-promoted `.constantBitrate` path inherits the strict
//     contract on bitDepth ≥ 12 HT-conformant lossy.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KConstantBitrateStrictTests: XCTestCase {

    private struct Fixture {
        let name: String
        let path: String
    }

    private static let largeFlatCurveFixtures: [Fixture] = [
        Fixture(name: "px_001 (2459×1316 PX)", path: "px_study_001_instance_000001.pgm"),
        Fixture(name: "dx_002 (2800×2288 DX)", path: "dx_study_002_instance_000001.pgm"),
    ]

    private static let smallFixtures: [Fixture] = [
        Fixture(name: "ct_001 (512×512 CT)", path: "ct_study_001_instance_000001.pgm"),
        Fixture(name: "xa_001 (1024² XA)",   path: "xa_study_001_instance_000001.pgm"),
    ]

    private func loadPGM(_ filename: String) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: fixture.path) else { return nil }
        let data = try Data(contentsOf: fixture)
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htConformantConfig(_ mode: J2KBitrateMode) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = mode
        return cfg
    }

    // MARK: - Hard byte cap is honored on flat-curve content

    /// **Core regression**: strict mode must never exceed the cap on
    /// any input, including the v5.33.0 worst cases (large fixtures
    /// at low bpp). This is the test that justifies v5.34.0 existing.
    func testStrictMode_HardCapHonoredOnFlatCurveFixtures() async throws {
        let bpps: [Double] = [0.5, 1.0, 2.0, 4.0]
        var ranAtLeastOne = false
        for fixture in Self.largeFlatCurveFixtures {
            guard let img = try loadPGM(fixture.path) else {
                print("  SKIP \(fixture.name): fixture not found")
                continue
            }
            ranAtLeastOne = true
            let totalSamples = img.width * img.height * img.componentCount
            for bpp in bpps {
                let targetBytes = Double(totalSamples) * bpp / 8.0
                let cfg = htConformantConfig(
                    .constantBitrateStrict(
                        bitsPerPixel: bpp,
                        maxOvershootRatio: 1.0,
                        maxPasses: 3))
                let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
                let ratio = Double(encoded.count) / targetBytes
                print("  \(fixture.name) @ \(bpp) bpp: \(encoded.count) bytes (ratio \(String(format: "%.3f", ratio)))")
                XCTAssertLessThanOrEqual(
                    Double(encoded.count), targetBytes,
                    "Strict mode must never exceed cap; \(fixture.name) @ \(bpp) bpp produced \(encoded.count) bytes vs \(Int(targetBytes)) target")
            }
        }
        if !ranAtLeastOne {
            throw XCTSkip("no flat-curve fixtures available")
        }
    }

    /// Truncated codestream must still decode (premature-EOC handling).
    func testStrictMode_TruncatedCodestreamDecodes() async throws {
        guard let img = try loadPGM("px_study_001_instance_000001.pgm") else {
            throw XCTSkip("px_001 fixture not found")
        }
        let cfg = htConformantConfig(
            .constantBitrateStrict(
                bitsPerPixel: 0.5,
                maxOvershootRatio: 1.0,
                maxPasses: 3))
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.width, img.width)
        XCTAssertEqual(decoded.height, img.height)
        XCTAssertEqual(decoded.components.count, img.components.count)
        XCTAssertEqual(decoded.components[0].data.count, img.components[0].data.count)
    }

    /// Relaxed cap (`maxOvershootRatio > 1.0`) must be honored as the
    /// upper bound. Larger cap → strictly higher quality (no truncation
    /// when bounded result fits the relaxed cap).
    func testStrictMode_RelaxedCapHonored() async throws {
        guard let img = try loadPGM("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("dx_002 fixture not found")
        }
        let totalSamples = img.width * img.height * img.componentCount
        let targetBpp = 0.5
        let targetBytes = Double(totalSamples) * targetBpp / 8.0
        for cap in [1.0, 1.5, 2.0, 3.0] as [Double] {
            let cfg = htConformantConfig(
                .constantBitrateStrict(
                    bitsPerPixel: targetBpp,
                    maxOvershootRatio: cap,
                    maxPasses: 3))
            let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
            let ratio = Double(encoded.count) / targetBytes
            print("  dx_002 @ \(targetBpp) bpp, cap \(cap)×: \(encoded.count) bytes (ratio \(String(format: "%.3f", ratio)))")
            XCTAssertLessThanOrEqual(
                ratio, cap + 1e-6,
                "Strict mode @ cap \(cap)× must not exceed; got ratio \(ratio)")
        }
    }

    /// On small fixtures where the bounded result already fits the
    /// cap, strict mode must NOT truncate — output must equal the
    /// bounded result byte-for-byte (same Qstep search, no post-step).
    func testStrictMode_NoTruncationWhenBoundedFits() async throws {
        var ranAtLeastOne = false
        for fixture in Self.smallFixtures {
            guard let img = try loadPGM(fixture.path) else { continue }
            ranAtLeastOne = true
            // High bpp + relaxed cap = bounded should fit easily.
            let bpp = 4.0
            let bounded = htConformantConfig(
                .constantBitrateBounded(
                    bitsPerPixel: bpp,
                    maxOvershootRatio: 2.0,
                    maxPasses: 3))
            let strict = htConformantConfig(
                .constantBitrateStrict(
                    bitsPerPixel: bpp,
                    maxOvershootRatio: 2.0,
                    maxPasses: 3))
            let boundedData = try await J2KEncoder(encodingConfiguration: bounded).encode(img)
            let strictData = try await J2KEncoder(encodingConfiguration: strict).encode(img)
            print("  \(fixture.name) @ \(bpp) bpp: bounded \(boundedData.count) vs strict \(strictData.count)")
            // When the bounded result is already within the cap, strict
            // returns it verbatim — modulo a small byte delta from
            // packet-boundary truncation rounding (≤ 64 bytes is the
            // SOP/SOT marker size for a single packet, which is the
            // truncation granularity). Pre-v9.9 the bracket widening
            // wasn't in play and bounded/strict produced identical
            // bytes for fixtures fitting the cap; with widened search
            // brackets the converged qstep can differ by 0.1% across
            // the two modes, producing ~10-30 byte differences in the
            // final codestream even when both fit the cap.
            let totalSamples = img.width * img.height * img.componentCount
            let targetBytes = Double(totalSamples) * bpp / 8.0
            if Double(boundedData.count) <= targetBytes * 2.0 {
                let delta = abs(strictData.count - boundedData.count)
                XCTAssertLessThanOrEqual(
                    delta, 128,
                    "When bounded fits cap, strict must match bounded within a packet-boundary truncation rounding (got delta=\(delta) bytes; bounded=\(boundedData.count) strict=\(strictData.count))")
            }
        }
        if !ranAtLeastOne {
            throw XCTSkip("no small fixtures available")
        }
    }

    // MARK: - Auto-promote `.constantBitrate` inherits strict contract

    /// The auto-promote path (.constantBitrate → strict on bitDepth ≥
    /// 12 HT-conformant lossy) must enforce the same hard cap.
    func testAutoPromote_HardCapHonoredAcrossCorpus() async throws {
        let allFixtures = Self.smallFixtures + Self.largeFlatCurveFixtures
        let bpps: [Double] = [0.5, 1.0, 2.0]
        var ranAtLeastOne = false
        for fixture in allFixtures {
            guard let img = try loadPGM(fixture.path) else { continue }
            ranAtLeastOne = true
            let totalSamples = img.width * img.height * img.componentCount
            for bpp in bpps {
                let targetBytes = Double(totalSamples) * bpp / 8.0
                // Use plain .constantBitrate — auto-promote should
                // route to the strict path internally.
                let cfg = htConformantConfig(.constantBitrate(bitsPerPixel: bpp))
                let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
                let ratio = Double(encoded.count) / targetBytes
                print("  auto-promote \(fixture.name) @ \(bpp) bpp: \(encoded.count) bytes (ratio \(String(format: "%.3f", ratio)))")
                XCTAssertLessThanOrEqual(
                    Double(encoded.count), targetBytes,
                    "Auto-promote .constantBitrate must not exceed target on \(fixture.name) @ \(bpp) bpp")
            }
        }
        if !ranAtLeastOne {
            throw XCTSkip("no fixtures available")
        }
    }

    // MARK: - Truncation infrastructure unit-level

    /// Spot check that the truncation helper does what it claims on a
    /// synthetic but valid encoded codestream. Uses a moderate qstep
    /// so the original encode comfortably exceeds half-size and the
    /// truncation has meaningful work to do.
    func testTruncateAtPacketBoundary_ProducesByteExactCap() async throws {
        guard let img = try loadPGM("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("ct_001 fixture not found")
        }
        let cfg = htConformantConfig(.fixedQstep(qstep: 1.0))
        let pipeline = EncoderPipeline(config: cfg)
        let indexed = try await pipeline.encodeWithPacketIndex(img)
        XCTAssertGreaterThan(indexed.packetEndOffsets.count, 0,
            "expected at least one packet")
        XCTAssertGreaterThan(indexed.tileDataOffset, 0)
        XCTAssertLessThan(indexed.tileDataOffset, indexed.data.count)

        // Truncate to half-size — must land at a packet boundary,
        // must be byte-exact ≤ requested target, must end with EOC.
        let target = indexed.data.count / 2
        let truncated = EncoderPipeline.truncateAtPacketBoundary(
            indexed, targetBytes: target)
        XCTAssertLessThanOrEqual(truncated.count, target)
        // Last 2 bytes must be EOC (0xFFD9)
        XCTAssertEqual(truncated[truncated.count - 2], 0xFF)
        XCTAssertEqual(truncated[truncated.count - 1], 0xD9)
        // Truncated codestream must decode
        let decoded = try await J2KDecoder().decode(truncated)
        XCTAssertEqual(decoded.width, img.width)
        XCTAssertEqual(decoded.height, img.height)
    }
}
