// V10_33_FileParserUncompressedFixtureTests.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Verifies J2KDICOMFileParser.parse(_:) correctly handles the 13
// synthetic uncompressed DICOM fixtures shipped at
// Tests/Fixtures/CrossCodec/synthetic/. All carry Transfer Syntax UID
// "1.2.840.10008.1.2.1" (Explicit VR Little Endian) and should
// classify as .uncompressed with valid Image Pixel Module metadata.

import XCTest
import Foundation
@testable import J2KDICOMHelpers

final class V10_33_FileParserUncompressedFixtureTests: XCTestCase {

    /// Inventory of synthetic fixtures known to exist in Tests/Fixtures/CrossCodec/synthetic/.
    /// Format: (filename, expected modality keyword in the file name).
    private static let fixtures: [(filename: String, modality: String)] = [
        ("ct_synth_small.dcm",  "ct"),
        ("ct_synth_mid.dcm",    "ct"),
        ("ct_synth_large.dcm",  "ct"),
        ("mr_synth_small.dcm",  "mr"),
        ("mr_synth_mid.dcm",    "mr"),
        ("mr_synth_large.dcm",  "mr"),
        ("dx_synth_mid.dcm",    "dx"),
        ("xa_synth_small.dcm",  "xa"),
        ("xa_synth_mid.dcm",    "xa"),
        ("px_synth_mid.dcm",    "px"),
        ("mg_synth_mid.dcm",    "mg"),
        ("cr_synth_mid.dcm",    "cr"),
        ("nm_synth_small.dcm",  "nm"),
    ]

    /// Resolve a fixture relative to the test source directory.
    /// `Tests/J2KDICOMHelpersTests/V10_33_..._FixtureTests.swift` ⇒
    /// fixture at `../Fixtures/CrossCodec/synthetic/<filename>`.
    /// Uses `#filePath` (not `#file`) per the established pattern in
    /// Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift:59 — `#file`
    /// is unreliable in Swift 6.2 (returns abbreviated form by default).
    private func fixtureURL(filename: String) throws -> URL? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // → Tests/J2KDICOMHelpersTests/
        let candidate = here
            .deletingLastPathComponent()  // → Tests/
            .appendingPathComponent("Fixtures/CrossCodec/synthetic")
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        // Fallback: process working dir relative.
        let fallback = URL(fileURLWithPath: "Tests/Fixtures/CrossCodec/synthetic")
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    func testAllFixturesParseAsUncompressed() throws {
        var foundCount = 0
        for entry in Self.fixtures {
            guard let url = try fixtureURL(filename: entry.filename) else {
                continue  // skip if not present
            }
            foundCount += 1

            let data = try Data(contentsOf: url)
            let parsed: J2KDICOMFile
            do {
                parsed = try J2KDICOMFileParser.parse(data)
            } catch {
                XCTFail("\(entry.filename): parser threw \(error)")
                continue
            }

            guard case .uncompressed(let metadata) = parsed else {
                XCTFail("\(entry.filename): expected .uncompressed, got \(parsed)")
                continue
            }

            // All synthetic fixtures use Explicit VR LE (the most common UID).
            XCTAssertEqual(metadata.transferSyntaxUID, "1.2.840.10008.1.2.1",
                "\(entry.filename): unexpected Transfer Syntax UID")

            // Image-pixel-module sanity.
            XCTAssertGreaterThan(metadata.rows, 0,
                "\(entry.filename): rows must be > 0")
            XCTAssertGreaterThan(metadata.columns, 0,
                "\(entry.filename): columns must be > 0")
            XCTAssertTrue([8, 16].contains(metadata.bitsAllocated),
                "\(entry.filename): bitsAllocated must be 8 or 16, got \(metadata.bitsAllocated)")
            XCTAssertGreaterThanOrEqual(metadata.samplesPerPixel, 1,
                "\(entry.filename): samplesPerPixel must be ≥ 1")
            XCTAssertGreaterThanOrEqual(metadata.numberOfFrames, 1,
                "\(entry.filename): numberOfFrames must be ≥ 1")
            XCTAssertFalse(metadata.photometricInterpretation.isEmpty,
                "\(entry.filename): photometricInterpretation must be present")
        }
        XCTAssertGreaterThan(foundCount, 0,
            "Expected at least one fixture in Tests/Fixtures/CrossCodec/synthetic/")
    }

    /// .uncompressed branch convenience accessors work as expected.
    func testUncompressedFileConvenienceAccessors() throws {
        guard let url = try fixtureURL(filename: "ct_synth_small.dcm") else {
            throw XCTSkip("ct_synth_small.dcm fixture not available in this checkout")
        }
        let data = try Data(contentsOf: url)
        let parsed = try J2KDICOMFileParser.parse(data)

        XCTAssertFalse(parsed.isJ2KCompressed)
        XCTAssertEqual(parsed.metadata.transferSyntaxUID, "1.2.840.10008.1.2.1")
    }

    /// Metadata derived properties (effectiveBitsStored, bytesPerSample,
    /// frameSizeInBytes) compute correctly.
    func testMetadataDerivedProperties() throws {
        guard let url = try fixtureURL(filename: "mr_synth_small.dcm") else {
            throw XCTSkip("mr_synth_small.dcm fixture not available")
        }
        let data = try Data(contentsOf: url)
        let parsed = try J2KDICOMFileParser.parse(data)
        let m = parsed.metadata

        // bytesPerSample
        XCTAssertEqual(m.bytesPerSample,
                       max(1, (m.bitsAllocated + 7) / 8))

        // effectiveBitsStored: stored if non-zero, else allocated
        let expectedStored = m.bitsStored == 0 ? m.bitsAllocated : m.bitsStored
        XCTAssertEqual(m.effectiveBitsStored, expectedStored)

        // frameSizeInBytes: rows * columns * samples * bytes
        XCTAssertEqual(m.frameSizeInBytes,
                       m.rows * m.columns * m.samplesPerPixel * m.bytesPerSample)
    }
}
