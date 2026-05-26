// V10_29_TransferSyntaxRoundTripTests.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1 parity gate.
//
// For each J2KDICOMTransferSyntax case:
//   - Constructed-via-UID equals original case
//   - `var uid` round-trip
//   - `isLossless` / `isHTJ2K` / `isPart2` flags match expected truth table
//   - Whitespace + trailing-NUL UID parsing tolerated
//   - Unknown UID returns nil

import XCTest
import Foundation
@testable import J2KDICOMHelpers

final class V10_29_TransferSyntaxRoundTripTests: XCTestCase {

    // MARK: - Round-trip

    func testUIDRoundTripForEveryCase() {
        for ts in J2KDICOMTransferSyntax.allCases {
            let uid = ts.uid
            XCTAssertFalse(uid.isEmpty, "UID must be non-empty for \(ts)")
            let parsed = J2KDICOMTransferSyntax(uid: uid)
            XCTAssertEqual(parsed, ts,
                "Round-trip via UID failed for \(ts): parsed back as \(String(describing: parsed))")
        }
    }

    func testEveryCaseHasUniqueUID() {
        let uids = J2KDICOMTransferSyntax.allCases.map { $0.uid }
        let unique = Set(uids)
        XCTAssertEqual(uids.count, unique.count,
            "Every Transfer Syntax case must have a unique UID. Found duplicates in: \(uids)")
    }

    // MARK: - Classification truth table

    func testIsLosslessTruthTable() {
        // Per DICOM PS3.5 Annex A.
        XCTAssertTrue(J2KDICOMTransferSyntax.j2kLossless.isLossless)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kLossy.isLossless)
        XCTAssertTrue(J2KDICOMTransferSyntax.j2kPart2MulticompLossless.isLossless)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kPart2Multicomp.isLossless)
        XCTAssertTrue(J2KDICOMTransferSyntax.htj2kLossless.isLossless)
        XCTAssertFalse(J2KDICOMTransferSyntax.htj2kLossyConstant.isLossless)
        XCTAssertFalse(J2KDICOMTransferSyntax.htj2kLossy.isLossless)
    }

    func testIsHTJ2KTruthTable() {
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kLossless.isHTJ2K)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kLossy.isHTJ2K)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kPart2MulticompLossless.isHTJ2K)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kPart2Multicomp.isHTJ2K)
        XCTAssertTrue(J2KDICOMTransferSyntax.htj2kLossless.isHTJ2K)
        XCTAssertTrue(J2KDICOMTransferSyntax.htj2kLossyConstant.isHTJ2K)
        XCTAssertTrue(J2KDICOMTransferSyntax.htj2kLossy.isHTJ2K)
    }

    func testIsPart2TruthTable() {
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kLossless.isPart2)
        XCTAssertFalse(J2KDICOMTransferSyntax.j2kLossy.isPart2)
        XCTAssertTrue(J2KDICOMTransferSyntax.j2kPart2MulticompLossless.isPart2)
        XCTAssertTrue(J2KDICOMTransferSyntax.j2kPart2Multicomp.isPart2)
        XCTAssertFalse(J2KDICOMTransferSyntax.htj2kLossless.isPart2)
        XCTAssertFalse(J2KDICOMTransferSyntax.htj2kLossyConstant.isPart2)
        XCTAssertFalse(J2KDICOMTransferSyntax.htj2kLossy.isPart2)
    }

    // MARK: - Lenient UID parsing

    func testTrailingNULTolerated() {
        // DICOM UID VRs may be NUL-padded for even length per PS3.5 §6.2.
        let parsed = J2KDICOMTransferSyntax(uid: "1.2.840.10008.1.2.4.201\0")
        XCTAssertEqual(parsed, .htj2kLossless)
    }

    func testWhitespaceTrimmed() {
        let parsed = J2KDICOMTransferSyntax(uid: "  1.2.840.10008.1.2.4.90  ")
        XCTAssertEqual(parsed, .j2kLossless)
    }

    // MARK: - Negative

    func testUnknownUIDReturnsNil() {
        XCTAssertNil(J2KDICOMTransferSyntax(uid: "1.2.840.10008.1.2.1"))    // Explicit VR Little Endian — non-J2K
        XCTAssertNil(J2KDICOMTransferSyntax(uid: "1.2.840.10008.1.2.4.50")) // JPEG Baseline — non-J2K
        XCTAssertNil(J2KDICOMTransferSyntax(uid: ""))
        XCTAssertNil(J2KDICOMTransferSyntax(uid: "not-a-uid"))
    }

    func testCaseIterableCoversAllSevenUIDs() {
        XCTAssertEqual(J2KDICOMTransferSyntax.allCases.count, 7,
            "DICOM Part 5 Annex A registers exactly 7 JPEG 2000 / HTJ2K UIDs as of this release.")
    }
}
