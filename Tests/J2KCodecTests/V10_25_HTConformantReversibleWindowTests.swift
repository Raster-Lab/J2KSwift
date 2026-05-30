//
// V10_25_HTConformantReversibleWindowTests.swift
// J2KSwift
//
// Regression guard for the HTJ2K conformant **lossless** encoder
// magnitude-window (K_max) sizing bug.
//
// Root cause (fixed): the conformant HT encoder converts coefficients to
// OpenJPH sign-magnitude as `sign | (|v| << (31 - K_max))`, where K_max was
// derived from the *single-level* subband gain {LL:0, HL/LH:1, HH:2}. A
// multi-level reversible 5/3 transform expands the coefficient range (the
// deep LL band especially), so high-contrast content — e.g. 8-bit images
// with hard 0↔255 transitions — produces coefficients whose magnitude
// exceeds `2^K_max`. `|v| << shift` then overflowed bit 31 (the sign bit),
// silently dropping the top bitplane: lossless mode was NOT lossless.
//
// The bug was discovered on the Cloudinary Image Dataset '22 (4 of 49 RGB
// reference images lost data) and confirmed encoder-side against OpenJPH
// (the reference decoder reproduced the loss from our codestream). The 12/16
// -bit medical DICOM corpus never triggered it because that content does not
// approach full scale.
//
// These tests assert bit-exact reversible HT-conformant round-trips for the
// exact minimal reproducer plus synthetic high-contrast grayscale and RGB
// content across several decomposition depths.
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

final class V10_25_HTConformantReversibleWindowTests: XCTestCase {

    /// Encode `image` with the reversible HT **conformant** path, decode, and
    /// return per-component mismatch counts.
    private func roundTripMismatches(
        _ image: J2KImage, decompositionLevels: Int
    ) async throws -> [Int] {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true)
        cfg.useReversibleFilter = true
        cfg.htj2kBlockFormat = .conformant
        cfg.bitrateMode = .lossless

        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.components.count, image.components.count,
                       "component count changed across round-trip")
        var mism: [Int] = []
        for c in 0..<min(decoded.components.count, image.components.count) {
            let orig = [UInt8](image.components[c].data)
            let rec = [UInt8](decoded.components[c].data)
            let n = min(orig.count, rec.count)
            var diff = abs(orig.count - rec.count)
            for i in 0..<n where orig[i] != rec[i] { diff += 1 }
            mism.append(diff)
        }
        return mism
    }

    private func grayImage(width: Int, height: Int, bytes: [UInt8]) -> J2KImage {
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: Data(bytes))
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func rgbImage(width: Int, height: Int, planes: [[UInt8]]) -> J2KImage {
        let comps = planes.enumerated().map { idx, p in
            J2KComponent(index: idx, bitDepth: 8, signed: false,
                         width: width, height: height, data: Data(p))
        }
        return J2KImage(width: width, height: height,
                        components: comps, colorSpace: .sRGB)
    }

    // MARK: - Exact minimal reproducer (8x8 RGB, interleaved -> planes)

    /// The exact 8x8 RGB tile (extracted from CID22 `2190188.png`) that
    /// reproduced the bug: HT-conformant lossless previously decoded with
    /// max|err| = 192 over 84 samples. Must now be bit-exact at every
    /// decomposition depth.
    func testMinimalReproducerBitExact() async throws {
        // Interleaved R,G,B,R,G,B... (8*8*3 = 192 bytes).
        let interleaved: [UInt8] = [
            255, 213, 0, 255, 214, 0, 255, 228, 157, 253, 247, 244, 246, 246, 255, 182,
            179, 218, 58, 49, 124, 49, 37, 106, 255, 210, 0, 255, 210, 0, 255, 219,
            121, 252, 240, 230, 242, 242, 252, 182, 180, 218, 70, 54, 134, 58, 47, 119,
            255, 206, 0, 255, 206, 0, 255, 208, 31, 253, 221, 173, 242, 231, 233, 201,
            197, 225, 109, 100, 158, 48, 36, 114, 255, 211, 0, 255, 211, 0, 255, 210,
            0, 255, 214, 79, 251, 231, 208, 240, 236, 244, 200, 201, 228, 100, 97, 151,
            255, 215, 0, 255, 216, 0, 255, 216, 0, 255, 219, 52, 254, 236, 207, 251,
            249, 253, 231, 234, 251, 140, 137, 185, 255, 211, 0, 255, 212, 0, 255, 213,
            0, 255, 215, 25, 254, 230, 190, 249, 245, 249, 230, 232, 250, 141, 137, 187,
            255, 207, 0, 255, 207, 0, 255, 208, 0, 255, 209, 0, 254, 217, 133, 249,
            235, 230, 231, 230, 248, 153, 155, 204, 255, 208, 0, 255, 208, 0, 255, 208,
            0, 255, 207, 0, 255, 209, 59, 252, 229, 202, 242, 239, 248, 200, 201, 234,
        ]
        var planes: [[UInt8]] = [[], [], []]
        for i in stride(from: 0, to: interleaved.count, by: 3) {
            planes[0].append(interleaved[i])
            planes[1].append(interleaved[i + 1])
            planes[2].append(interleaved[i + 2])
        }
        let image = rgbImage(width: 8, height: 8, planes: planes)
        for levels in [1, 2, 3] {
            let mism = try await roundTripMismatches(image, decompositionLevels: levels)
            XCTAssertEqual(mism, [0, 0, 0],
                           "minimal reproducer not bit-exact at \(levels) level(s): \(mism)")
        }
    }

    // MARK: - Synthetic high-contrast content

    /// Hard full-range 0/255 edges drive the largest reversible-5/3
    /// coefficients. Distinct per-channel phase exercises the RCT-widened
    /// U/V components. Must be bit-exact (was the failure class).
    func testHighContrastRGBBitExact() async throws {
        let w = 64, h = 64
        var planes: [[UInt8]] = [[], [], []]
        for y in 0..<h {
            for x in 0..<w {
                // Sharp 0/255 transitions, different period/phase per channel.
                planes[0].append(((x / 3) % 2 == 0) ? 255 : 0)
                planes[1].append(((y / 2) % 2 == 0) ? 255 : 0)
                planes[2].append((((x + y) / 5) % 2 == 0) ? 255 : 0)
            }
        }
        let image = rgbImage(width: w, height: h, planes: planes)
        for levels in [2, 3, 5] {
            let mism = try await roundTripMismatches(image, decompositionLevels: levels)
            XCTAssertEqual(mism, [0, 0, 0],
                           "high-contrast RGB not bit-exact at \(levels) levels: \(mism)")
        }
    }

    /// Single-component high-contrast content also overflows the window
    /// (the bug is not multi-component specific).
    func testHighContrastGrayscaleBitExact() async throws {
        let w = 64, h = 64
        var bytes: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                bytes.append((((x / 2) ^ (y / 3)) % 2 == 0) ? 255 : 0)
            }
        }
        let image = grayImage(width: w, height: h, bytes: bytes)
        for levels in [2, 3, 5] {
            let mism = try await roundTripMismatches(image, decompositionLevels: levels)
            XCTAssertEqual(mism, [0],
                           "high-contrast grayscale not bit-exact at \(levels) levels: \(mism)")
        }
    }
}
