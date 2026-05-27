// V10_33_FileParserPreambleTests.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Preamble + magic + truncation validation. Verifies the parser
// rejects malformed inputs at the right boundary with the right
// typed error.

import XCTest
import Foundation
@testable import J2KDICOMHelpers

final class V10_33_FileParserPreambleTests: XCTestCase {

    func testEmptyDataRejected() {
        XCTAssertThrowsError(try J2KDICOMFileParser.parse(Data())) { error in
            XCTAssertEqual(error as? J2KDICOMFileError,
                           .invalidPreamble(size: 0))
        }
    }

    func testInputShorterThanPreambleRejected() {
        // 100 bytes < 132-byte minimum (128 preamble + 4 DICM)
        let short = Data(repeating: 0, count: 100)
        XCTAssertThrowsError(try J2KDICOMFileParser.parse(short)) { error in
            XCTAssertEqual(error as? J2KDICOMFileError,
                           .invalidPreamble(size: 100))
        }
    }

    func testInputExactly131BytesRejected() {
        // One byte short of the 132-byte minimum.
        let bytes = Data(repeating: 0, count: 131)
        XCTAssertThrowsError(try J2KDICOMFileParser.parse(bytes)) { error in
            XCTAssertEqual(error as? J2KDICOMFileError,
                           .invalidPreamble(size: 131))
        }
    }

    func testMissingDICMMagicRejected() {
        // 128-byte preamble + 4 bytes that are NOT "DICM"
        var bytes = Data(repeating: 0, count: 128)
        bytes.append(contentsOf: [0x4E, 0x4F, 0x50, 0x45])  // "NOPE"
        XCTAssertThrowsError(try J2KDICOMFileParser.parse(bytes)) { error in
            XCTAssertEqual(error as? J2KDICOMFileError,
                           .missingDICMMagic(actual: "NOPE"))
        }
    }

    func testDICMMagicAtCorrectOffsetButNoGroupZero002() {
        // Valid preamble + DICM magic, but the bytes after are random —
        // no recognisable group 0002 element + no Transfer Syntax UID.
        // Should throw invalidTransferSyntax (empty UID after group walk).
        var bytes = Data(repeating: 0, count: 128)
        bytes.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])  // "DICM"
        // Garbage after — first u16 LE != 0x0002 so the group-0002
        // loop exits immediately with an empty UID.
        bytes.append(contentsOf: Array(repeating: UInt8(0xFF), count: 32))
        XCTAssertThrowsError(try J2KDICOMFileParser.parse(bytes)) { error in
            if case .invalidTransferSyntax = error as? J2KDICOMFileError {
                // expected
            } else {
                XCTFail("Expected .invalidTransferSyntax, got \(error)")
            }
        }
    }
}
