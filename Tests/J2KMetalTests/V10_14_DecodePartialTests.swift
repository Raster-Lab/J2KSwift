// V10_14_DecodePartialTests.swift
//
// v10.14-research — validation for `decodePartial`, the umbrella
// partial-decode API (v10.8.0). `decodePartial` composes the
// capabilities shipped across v10.5.0–v10.7.0:
//   - maxResolutionLevel → true partial-resolution decode (v10.5.0)
//   - region             → ROI decode (v10.6.0 + v10.7.0)
//   - components         → component subset selection
//
// These tests assert `decodePartial` is consistent with the
// already-shipped single-axis APIs it delegates to: a resolution-only
// `decodePartial` must equal `decodeResolution`; a region-only one
// must equal `decodeRegion(.direct)`; empty options must equal
// `decode()`; and component selection must pick exactly the requested
// components of a full decode.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_14_DecodePartialTests: XCTestCase {

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// 16-bit-aware test-side region crop.
    private func cropReference(_ image: J2KImage, _ region: J2KRegion) -> Data {
        let comp = image.components[0]
        let bps = (comp.bitDepth + 7) / 8
        var out = Data(count: region.width * region.height * bps)
        comp.data.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.baseAddress, let dst = dstRaw.baseAddress else { return }
                for y in 0..<region.height {
                    let srcOff = ((region.y + y) * comp.width + region.x) * bps
                    let dstOff = y * region.width * bps
                    memcpy(dst + dstOff, src + srcOff, region.width * bps)
                }
            }
        }
        return out
    }

    // MARK: - decodePartial ≡ the single-axis API it delegates to

    func testDecodePartial_resolutionOnly_matchesDecodeResolution() async throws {
        guard let image = try loadPGM16("medical-real/ct_real_mid_512x512.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()
        for level in [0, 2, 4] {
            let viaPartial = try await decoder.decodePartial(
                codestream, options: J2KPartialDecodingOptions(maxResolutionLevel: level))
            let viaResolution = try await decoder.decodeResolution(
                codestream, options: J2KResolutionDecodingOptions(level: level))
            XCTAssertEqual(viaPartial.width, viaResolution.width, "[level \(level)] width")
            XCTAssertEqual(viaPartial.height, viaResolution.height, "[level \(level)] height")
            XCTAssertEqual(viaPartial.components[0].data, viaResolution.components[0].data,
                "[level \(level)] decodePartial(maxResolutionLevel:) != decodeResolution(level:)")
        }
        print("V10_14 decodePartial resolution-only ≡ decodeResolution ✓ (levels 0/2/4)")
    }

    func testDecodePartial_regionOnly_matchesDecodeRegion() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()
        let region = J2KRegion(x: image.width / 3, y: image.height / 3, width: 256, height: 192)

        let viaPartial = try await decoder.decodePartial(
            codestream, options: J2KPartialDecodingOptions(region: region))
        let viaRegion = try await decoder.decodeRegion(
            codestream, options: J2KROIDecodingOptions(region: region, strategy: .direct))
        XCTAssertEqual(viaPartial.width, region.width)
        XCTAssertEqual(viaPartial.height, region.height)
        XCTAssertEqual(viaPartial.components[0].data, viaRegion.components[0].data,
            "decodePartial(region:) != decodeRegion(.direct)")
        print("V10_14 decodePartial region-only ≡ decodeRegion(.direct) ✓")
    }

    func testDecodePartial_emptyOptions_matchesFullDecode() async throws {
        guard let image = try loadPGM16("medical-real/ct_real_mid_512x512.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()
        let viaPartial = try await decoder.decodePartial(
            codestream, options: J2KPartialDecodingOptions())
        let full = try await decoder.decode(codestream)
        XCTAssertEqual(viaPartial.width, full.width)
        XCTAssertEqual(viaPartial.height, full.height)
        XCTAssertEqual(viaPartial.components[0].data, full.components[0].data,
            "decodePartial() with empty options must equal decode()")
        print("V10_14 decodePartial empty options ≡ decode() ✓")
    }

    func testDecodePartial_resolutionPlusRegion() async throws {
        guard let image = try loadPGM16("medical-real/ct_real_mid_512x512.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()

        // levels = 5; decode at level 2 → factor 2^(5-2)=8 → 64×64 grid.
        let level = 2, factor = 1 << (5 - level)
        let region = J2KRegion(x: 128, y: 96, width: 128, height: 128)
        let combined = try await decoder.decodePartial(
            codestream,
            options: J2KPartialDecodingOptions(maxResolutionLevel: level, region: region))

        // Reference: decode at the resolution level, then crop the
        // region mapped onto the reduced grid (the same mapping
        // decodePartial documents).
        let reduced = try await decoder.decodeResolution(
            codestream, options: J2KResolutionDecodingOptions(level: level))
        let rx = region.x / factor, ry = region.y / factor
        let rw = max(1, min((region.width + factor - 1) / factor, reduced.width - rx))
        let rh = max(1, min((region.height + factor - 1) / factor, reduced.height - ry))
        let scaled = J2KRegion(x: rx, y: ry, width: rw, height: rh)

        XCTAssertEqual(combined.width, scaled.width, "combined width")
        XCTAssertEqual(combined.height, scaled.height, "combined height")
        XCTAssertEqual(combined.components[0].data, cropReference(reduced, scaled),
            "decodePartial(resolution+region) != decodeResolution then crop")
        print("V10_14 decodePartial resolution+region ✓ (level \(level), \(rw)×\(rh))")
    }

    func testDecodePartial_componentSelection_grayscale() async throws {
        guard let image = try loadPGM16("medical-real/ct_real_mid_512x512.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()
        let selected = try await decoder.decodePartial(
            codestream, options: J2KPartialDecodingOptions(components: [0]))
        let full = try await decoder.decode(codestream)
        XCTAssertEqual(selected.components.count, 1)
        XCTAssertEqual(selected.components[0].index, 0)
        XCTAssertEqual(selected.components[0].data, full.components[0].data,
            "decodePartial(components:[0]) must equal decode()'s component 0")
        print("V10_14 decodePartial component selection (grayscale [0]) ✓")
    }

    func testDecodePartial_componentSelection_multiComponent() async throws {
        // Synthesise a distinct 3-component 96×96 8-bit image.
        let w = 96, h = 96
        let comps: [J2KComponent] = (0..<3).map { c in
            var data = Data(count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    data[y * w + x] = UInt8((x + y * 2 + c * 50) & 0xFF)
                }
            }
            return J2KComponent(index: c, bitDepth: 8, signed: false,
                                width: w, height: h, data: data)
        }
        let rgb = J2KImage(width: w, height: h, components: comps, colorSpace: .sRGB)
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(rgb)
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)
        guard full.components.count == 3 else {
            throw XCTSkip("3-component round-trip unavailable (got \(full.components.count) components)")
        }

        // Select components [2, 0] — non-contiguous, reordered.
        let selected = try await decoder.decodePartial(
            codestream, options: J2KPartialDecodingOptions(components: [2, 0]))
        XCTAssertEqual(selected.components.count, 2)
        XCTAssertEqual(selected.components[0].index, 2)
        XCTAssertEqual(selected.components[1].index, 0)
        XCTAssertEqual(selected.components[0].data, full.components[2].data,
            "selected[0] must equal full decode component 2")
        XCTAssertEqual(selected.components[1].data, full.components[0].data,
            "selected[1] must equal full decode component 0")
        print("V10_14 decodePartial component selection (3-component [2,0]) ✓")
    }

    func testDecodePartial_maxLayerNoOp() async throws {
        guard let image = try loadPGM16("medical-real/ct_real_mid_512x512.pgm") else {
            throw XCTSkip("CT fixture missing")
        }
        // htLosslessConfig is single-layer (qualityLayers: 1), so
        // maxLayer: 0 keeps every layer — a harmless no-op.
        let codestream = try await J2KEncoder(encodingConfiguration: htLosslessConfig()).encode(image)
        let decoder = J2KDecoder()
        let viaPartial = try await decoder.decodePartial(
            codestream, options: J2KPartialDecodingOptions(maxLayer: 0))
        let full = try await decoder.decode(codestream)
        XCTAssertEqual(viaPartial.components[0].data, full.components[0].data,
            "decodePartial(maxLayer:0) on a single-layer codestream must equal decode()")
        print("V10_14 decodePartial maxLayer no-op (single-layer) ✓")
    }
}
#endif
