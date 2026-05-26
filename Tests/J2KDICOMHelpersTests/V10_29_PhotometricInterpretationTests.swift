// V10_29_PhotometricInterpretationTests.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1 parity gate.
//
// Verifies the J2KDICOMPhotometricInterpretation ↔ J2KColorSpace
// mapping behaves as documented:
//   - Raw DICOM string values match PS3.3 §C.7.6.3.1.2
//   - `colorSpace` is total and well-typed
//   - reverse init returns nil for non-DICOM-mappable colour spaces
//     (hdr, hdrLinear, iccProfile, unknown)
//   - all 7 PhotometricInterpretation cases are covered by CaseIterable

import XCTest
import Foundation
@testable import J2KDICOMHelpers
@testable import J2KCore

final class V10_29_PhotometricInterpretationTests: XCTestCase {

    func testRawValuesMatchDICOMStandard() {
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.monochrome1.rawValue, "MONOCHROME1")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.monochrome2.rawValue, "MONOCHROME2")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.rgb.rawValue, "RGB")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrFull.rawValue, "YBR_FULL")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrFull422.rawValue, "YBR_FULL_422")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrRct.rawValue, "YBR_RCT")
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrIct.rawValue, "YBR_ICT")
    }

    func testCaseIterableCoversAllSeven() {
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.allCases.count, 7)
    }

    func testColorSpaceMapping() {
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.monochrome1.colorSpace, .grayscale)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.monochrome2.colorSpace, .grayscale)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.rgb.colorSpace, .sRGB)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrFull.colorSpace, .yCbCr)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrFull422.colorSpace, .yCbCr)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrRct.colorSpace, .yCbCr)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation.yBrIct.colorSpace, .yCbCr)
    }

    func testReverseFromColorSpaceWhenUnambiguous() {
        XCTAssertEqual(J2KDICOMPhotometricInterpretation(colorSpace: .grayscale), .monochrome2)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation(colorSpace: .sRGB), .rgb)
        XCTAssertEqual(J2KDICOMPhotometricInterpretation(colorSpace: .yCbCr), .yBrFull)
    }

    func testReverseFromColorSpaceReturnsNilForUnmappable() {
        XCTAssertNil(J2KDICOMPhotometricInterpretation(colorSpace: .hdr))
        XCTAssertNil(J2KDICOMPhotometricInterpretation(colorSpace: .hdrLinear))
        XCTAssertNil(J2KDICOMPhotometricInterpretation(colorSpace: .iccProfile(Data())))
        XCTAssertNil(J2KDICOMPhotometricInterpretation(colorSpace: .unknown))
    }

    func testRawValueRoundTrip() {
        for pi in J2KDICOMPhotometricInterpretation.allCases {
            let parsed = J2KDICOMPhotometricInterpretation(rawValue: pi.rawValue)
            XCTAssertEqual(parsed, pi)
        }
    }
}
