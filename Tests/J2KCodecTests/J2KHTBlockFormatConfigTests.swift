// J2KHTBlockFormatConfigTests.swift
// Smoke tests for the HTBlockFormat configuration flag wired into
// J2KEncodingConfiguration. Full pipeline integration lands with the
// M7 cross-codec validation work — for now the tests only assert
// the flag is carried through the config without disturbing the
// default behavior.

import XCTest
@testable import J2KCodec

final class HTBlockFormatConfigTests: XCTestCase {

    /// Default configuration must still produce the legacy custom
    /// format so v4.x deployments are not silently upgraded.
    func testDefaultIsCustomFormat() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.htj2kBlockFormat, .custom)
    }

    /// Opt-in to the Part-15 format via the init parameter.
    func testExplicitPart15Selectable() {
        let config = J2KEncodingConfiguration(htj2kBlockFormat: .part15)
        XCTAssertEqual(config.htj2kBlockFormat, .part15)
    }

    /// Mutation after construction must be allowed (useful for
    /// per-call overrides during testing / migration).
    func testHTBlockFormatMutable() {
        var config = J2KEncodingConfiguration()
        config.htj2kBlockFormat = .part15
        XCTAssertEqual(config.htj2kBlockFormat, .part15)
    }

    /// The enum must be `CaseIterable` so CLI / config surfaces can
    /// enumerate the available choices.
    func testHTBlockFormatIsCaseIterable() {
        XCTAssertEqual(HTBlockFormat.allCases.count, 2)
        XCTAssertTrue(HTBlockFormat.allCases.contains(.custom))
        XCTAssertTrue(HTBlockFormat.allCases.contains(.part15))
    }
}
