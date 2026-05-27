// V10_34_DecoderFormatFlexibilityTests.swift
//
// v10.22.0 — Verify J2KDecoder.decodeAnyFormat(_:) + decodeFile(at:)
// + J2KFileReader.extractCodestream(from:) handle raw J2K codestream
// AND JP2-box-wrapped bytes equivalently.
//
// No new binary fixtures committed — JP2/JPH test files are
// synthesised at test time via J2KEncoder + J2KFileWriter (writing
// to a temp file, then reading back the bytes). Same fixture-
// generation pattern as V10_33's J2K-tagged DICOM synthesis.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KFileFormat

final class V10_34_DecoderFormatFlexibilityTests: XCTestCase {

    // MARK: - Fixture builders

    /// 16×16 16-bit single-component LCG image (small enough to keep
    /// tests fast; deterministic for byte-exact comparisons).
    private func makeImage(seed: UInt64 = 0xDEAD_BEEF) -> J2KImage {
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

    /// Writes the image to a temp JP2/JPH file via J2KFileWriter (which
    /// builds the box wrapper + encodes the codestream internally).
    /// Returns (fileURL, fileBytes). Uses `J2KConfiguration.lossless`
    /// so the round-trip is bit-exact.
    private func makeSyntheticJP2(
        image: J2KImage,
        format: J2KFormat = .jp2
    ) async throws -> (fileURL: URL, fileBytes: Data) {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(
            "v10_34_synthetic_\(UUID().uuidString).\(format.fileExtension)")
        let writer = J2KFileWriter(format: format)
        // Lossless config so the writer's internal encode → decode
        // round-trip is bit-exact. (J2KConfiguration() defaults to
        // quality 0.9 + lossy 9/7, which would corrupt the equality
        // assertions below.)
        try await writer.write(image, to: url,
                               configuration: J2KConfiguration.lossless)
        let bytes = try Data(contentsOf: url)
        return (url, bytes)
    }

    // MARK: - extractCodestream

    /// J2KFileReader.extractCodestream returns the codestream inside
    /// the jp2c box of a J2KFileWriter-produced JP2 file.
    func testExtractCodestreamFromJP2() async throws {
        let image = makeImage()
        let (_, fileBytes) = try await makeSyntheticJP2(image: image)

        let reader = J2KFileReader()
        let extracted = try reader.extractCodestream(from: fileBytes)

        // Extracted bytes should start with SOC (0xFF 0x4F) — definitive
        // marker of a raw J2K codestream.
        XCTAssertGreaterThanOrEqual(extracted.count, 2)
        XCTAssertEqual(extracted[extracted.startIndex], 0xFF)
        XCTAssertEqual(extracted[extracted.startIndex + 1], 0x4F)
    }

    /// Same for a JPH (HTJ2K) file.
    func testExtractCodestreamFromJPH() async throws {
        let image = makeImage()
        let (_, fileBytes) = try await makeSyntheticJP2(image: image, format: .jph)

        let reader = J2KFileReader()
        let extracted = try reader.extractCodestream(from: fileBytes)

        XCTAssertEqual(extracted[extracted.startIndex], 0xFF)
        XCTAssertEqual(extracted[extracted.startIndex + 1], 0x4F)
    }

    /// Extracting from raw codestream bytes (no JP2 wrapper) throws —
    /// `extractCodestream` is specifically for box-format inputs.
    func testExtractCodestreamRejectsRawCodestream() async throws {
        let image = makeImage()
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, useHTJ2K: true,
            useReversibleFilter: true, htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantQuality
        let raw = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        XCTAssertThrowsError(try J2KFileReader().extractCodestream(from: raw))
    }

    // MARK: - decodeAnyFormat

    /// decodeAnyFormat accepts raw J2K codestream bytes (pass-through to decode).
    func testDecodeAnyFormatAcceptsRawCodestream() async throws {
        let image = makeImage()
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, useHTJ2K: true,
            useReversibleFilter: true, htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantQuality
        let raw = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let decoded = try await J2KDecoder().decodeAnyFormat(raw)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, image.components.count)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "Round-trip via decodeAnyFormat (raw path) must be bit-exact for lossless HTJ2K.")
    }

    /// decodeAnyFormat accepts JP2-boxed bytes (extracts codestream + decodes).
    func testDecodeAnyFormatAcceptsJP2BoxedBytes() async throws {
        let image = makeImage()
        let (_, jp2Bytes) = try await makeSyntheticJP2(image: image)

        let decoded = try await J2KDecoder().decodeAnyFormat(jp2Bytes)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "Round-trip via decodeAnyFormat (JP2 path) must be bit-exact.")
    }

    /// decodeAnyFormat accepts JPH-boxed bytes.
    func testDecodeAnyFormatAcceptsJPHBoxedBytes() async throws {
        let image = makeImage()
        let (_, jphBytes) = try await makeSyntheticJP2(image: image, format: .jph)

        let decoded = try await J2KDecoder().decodeAnyFormat(jphBytes)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "Round-trip via decodeAnyFormat (JPH path) must be bit-exact.")
    }

    // MARK: - decodeFile

    /// decodeFile reads a temp file from disk and decodes it.
    func testDecodeFileReadsJP2FromDisk() async throws {
        let image = makeImage()
        let (url, _) = try await makeSyntheticJP2(image: image)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await J2KDecoder().decodeFile(at: url)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "decodeFile via temp JP2 disk file must be bit-exact.")
    }

    /// decodeFile against a missing file throws I/O error.
    func testDecodeFileMissingThrowsIOError() async throws {
        let bogusURL = URL(fileURLWithPath: "/tmp/v10_34_does_not_exist_\(UUID().uuidString).jp2")
        do {
            _ = try await J2KDecoder().decodeFile(at: bogusURL)
            XCTFail("Expected I/O error for missing file")
        } catch {
            // OK — any thrown error is acceptable; Data(contentsOf:) throws
            // CocoaError on missing file. We just verify the call doesn't
            // succeed silently.
        }
    }
}
