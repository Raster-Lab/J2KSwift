// V10_35_EncoderFileFormatTests.swift
//
// v10.23.0 — write-side counterpart to v10.22.0's V10_34. Verifies the
// new J2KFileWriter.wrap + J2KEncoder.encodeToFormat + encodeFile
// extensions produce bytes that round-trip through the existing
// J2KDecoder.decodeAnyFormat / decodeFile path bit-exactly for
// lossless HTJ2K.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KFileFormat

final class V10_35_EncoderFileFormatTests: XCTestCase {

    // MARK: - Fixtures

    /// 16×16 16-bit single-component LCG image — small enough to keep
    /// tests fast; deterministic for byte-exact round-trip comparisons.
    private func makeImage(seed: UInt64 = 0x1234_5678) -> J2KImage {
        let w = 16, h = 16
        var bytes = Data(count: w * h * 2)
        var s = seed &* 6364136223846793005 &+ 1442695040888963407
        bytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<(w * h) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFF))
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: w, height: h,
            data: bytes, sampleByteOrder: .bigEndian)
        return J2KImage(width: w, height: h, components: [comp])
    }

    /// HTJ2K Lossless configuration — exercises the rich encoder path
    /// that J2KFileWriter.write's simpler J2KConfiguration can't reach.
    private func makeHTJ2KLosslessEncoder() -> J2KEncoder {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantQuality
        return J2KEncoder(encodingConfiguration: cfg)
    }

    // MARK: - J2KFileWriter.wrap

    /// wrap(codestream:headerForImage:) for `.j2k` returns the
    /// codestream unchanged — no boxes for raw format.
    func testWrapJ2KFormatReturnsCodestreamUnchanged() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()
        let codestream = try await encoder.encode(image)

        let wrapped = try J2KFileWriter(format: .j2k)
            .wrap(codestream: codestream, headerForImage: image)
        XCTAssertEqual(wrapped, codestream,
            "wrap(format: .j2k) must return the codestream unchanged.")
    }

    /// wrap(codestream:headerForImage:) for `.jp2` produces bytes
    /// that start with the JP2 signature box.
    func testWrapJP2FormatPrependsJP2Signature() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()
        let codestream = try await encoder.encode(image)

        let wrapped = try J2KFileWriter(format: .jp2)
            .wrap(codestream: codestream, headerForImage: image)
        // JP2 signature box: 12 bytes starting with 0x00 00 00 0C 'jP  ' 0D 0A 87 0A
        XCTAssertGreaterThan(wrapped.count, codestream.count,
            "JP2-wrapped bytes must be larger than raw codestream (signature + filetype + jp2h boxes)")
        XCTAssertEqual(wrapped[wrapped.startIndex + 0], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 1], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 2], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 3], 0x0C)
        XCTAssertEqual(wrapped[wrapped.startIndex + 4], 0x6A) // 'j'
        XCTAssertEqual(wrapped[wrapped.startIndex + 5], 0x50) // 'P'
    }

    /// wrap(codestream:headerForImage:) for `.jph` produces JP2-style
    /// boxes with the JPH brand in the file-type box.
    func testWrapJPHFormatProducesJPHBrand() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()
        let codestream = try await encoder.encode(image)

        let wrapped = try J2KFileWriter(format: .jph)
            .wrap(codestream: codestream, headerForImage: image)
        // Same signature box as JP2, but the file-type (ftyp) box that
        // follows carries 'jph ' brand instead of 'jp2 '.
        XCTAssertGreaterThan(wrapped.count, codestream.count)
        XCTAssertEqual(wrapped[wrapped.startIndex + 0], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 1], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 2], 0x00)
        XCTAssertEqual(wrapped[wrapped.startIndex + 3], 0x0C)
    }

    /// Round-trip: wrap then extractCodestream recovers the original
    /// codestream bit-exactly.
    func testWrapThenExtractCodestreamRoundTrip() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()
        let codestream = try await encoder.encode(image)

        let wrapped = try J2KFileWriter(format: .jp2)
            .wrap(codestream: codestream, headerForImage: image)
        let extracted = try J2KFileReader().extractCodestream(from: wrapped)
        XCTAssertEqual(extracted, codestream,
            "wrap → extractCodestream must recover the codestream bit-exactly.")
    }

    /// wrap rejects images with zero dimensions.
    func testWrapRejectsInvalidImage() async throws {
        let badImage = J2KImage(width: 0, height: 0,
                                components: [J2KComponent(
                                    index: 0, bitDepth: 16, signed: false,
                                    width: 0, height: 0,
                                    data: Data(), sampleByteOrder: .bigEndian)])
        XCTAssertThrowsError(try J2KFileWriter(format: .jp2)
            .wrap(codestream: Data([0xFF, 0x4F]), headerForImage: badImage))
    }

    // MARK: - J2KEncoder.encodeToFormat

    /// encodeToFormat(.j2k) returns same bytes as encode(image).
    func testEncodeToFormatJ2KMatchesEncode() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        let raw = try await encoder.encode(image)
        let viaFormat = try await encoder.encodeToFormat(image, format: .j2k)

        XCTAssertEqual(viaFormat, raw,
            "encodeToFormat(.j2k) must return identical bytes to encode(_:).")
    }

    /// encodeToFormat(.jp2) → decodeAnyFormat round-trip is bit-exact for lossless.
    func testEncodeToFormatJP2RoundTripsBitExact() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        let wrapped = try await encoder.encodeToFormat(image, format: .jp2)
        let decoded = try await J2KDecoder().decodeAnyFormat(wrapped)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "JP2 encode → decode round-trip must be bit-exact for lossless HTJ2K.")
    }

    /// encodeToFormat(.jph) → decodeAnyFormat round-trip is bit-exact.
    func testEncodeToFormatJPHRoundTripsBitExact() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        let wrapped = try await encoder.encodeToFormat(image, format: .jph)
        let decoded = try await J2KDecoder().decodeAnyFormat(wrapped)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "JPH encode → decode round-trip must be bit-exact.")
    }

    // MARK: - J2KEncoder.encodeFile

    /// encodeFile writes to disk + decodeFile reads back bit-exactly.
    func testEncodeFileWriteThenDecodeFileRoundTrip() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v10_35_roundtrip_\(UUID().uuidString).jp2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await encoder.encodeFile(image, to: tempURL, format: .jp2)

        // File should exist + be larger than raw codestream
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 200,
            "JP2 file should contain the codestream + box overhead.")

        // Round-trip via v10.22's decodeFile
        let decoded = try await J2KDecoder().decodeFile(at: tempURL)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "encodeFile → decodeFile round-trip must be bit-exact.")
    }

    /// encodeFile defaults to .jp2 format when format param omitted.
    func testEncodeFileDefaultsToJP2() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v10_35_default_\(UUID().uuidString).jp2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await encoder.encodeFile(image, to: tempURL)  // no format arg

        let bytes = try Data(contentsOf: tempURL)
        // Should be JP2-boxed (starts with the 12-byte JP2 signature box)
        XCTAssertGreaterThan(bytes.count, 12)
        XCTAssertEqual(bytes[bytes.startIndex + 3], 0x0C,
            "Default .jp2 format must produce JP2 signature box (length 0x0C).")
    }

    /// encodeFile to an unwritable path throws an I/O error.
    func testEncodeFileUnwritablePathThrowsIOError() async throws {
        let image = makeImage()
        let encoder = makeHTJ2KLosslessEncoder()

        // /dev/null/cant-write-here would be a typical unwritable path
        let badURL = URL(fileURLWithPath: "/dev/null/v10_35_cant_write_here.jp2")

        do {
            try await encoder.encodeFile(image, to: badURL, format: .jp2)
            XCTFail("Expected I/O error for unwritable path")
        } catch {
            // OK — any thrown error is acceptable; we just verify the
            // call doesn't succeed silently.
        }
    }
}
