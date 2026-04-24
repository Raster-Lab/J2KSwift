// J2KHTBlockFormatConfigTests.swift
// Smoke tests for the HTBlockFormat configuration flag wired into
// J2KEncodingConfiguration. Full pipeline integration lands with the
// M7 cross-codec validation work — for now the tests only assert
// the flag is carried through the config without disturbing the
// default behavior.

import XCTest
@testable import J2KCodec

final class HTBlockFormatConfigTests: XCTestCase {

    /// Default stays `.custom` in v5.1.0. The v5.1 work brought the
    /// decoder-side dispatch online (so `.conformant` now fully
    /// round-trips through J2KSwift's own decode API at power-of-2
    /// code block sizes), but a remaining non-power-of-2 subband
    /// issue in the shared block-coder keeps us from flipping the
    /// default until the encoder geometry is fixed.
    func testDefaultIsCustomFormat() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.htj2kBlockFormat, .custom)
    }

    /// Opt-in to the Part-15 format via the init parameter.
    func testExplicitConformantSelectable() {
        let config = J2KEncodingConfiguration(htj2kBlockFormat: .conformant)
        XCTAssertEqual(config.htj2kBlockFormat, .conformant)
    }

    /// Mutation after construction must be allowed (useful for
    /// per-call overrides during testing / migration).
    func testHTBlockFormatMutable() {
        var config = J2KEncodingConfiguration()
        config.htj2kBlockFormat = .conformant
        XCTAssertEqual(config.htj2kBlockFormat, .conformant)
    }

    /// The enum must be `CaseIterable` so CLI / config surfaces can
    /// enumerate the available choices.
    func testHTBlockFormatIsCaseIterable() {
        XCTAssertEqual(HTBlockFormat.allCases.count, 2)
        XCTAssertTrue(HTBlockFormat.allCases.contains(.custom))
        XCTAssertTrue(HTBlockFormat.allCases.contains(.conformant))
    }
}
