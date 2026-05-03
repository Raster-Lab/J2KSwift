// J2KHTBlockFormatConfigTests.swift
// Smoke tests for the HTBlockFormat configuration flag wired into
// J2KEncodingConfiguration. Full pipeline integration lands with the
// M7 cross-codec validation work — for now the tests only assert
// the flag is carried through the config without disturbing the
// default behavior.

import XCTest
@testable import J2KCodec

final class HTBlockFormatConfigTests: XCTestCase {

    /// Default is `.conformant` (Part-15 / ISO 15444-15). The flip
    /// from `.custom` happened after v5.1.0 once the decoder-side
    /// COM-marker dispatch and K_max widening (v5.1.1) shipped.
    /// v5.15.0 ratified non-power-of-2 lossless via three independent
    /// probes; v5.16.0 ratified lossy via the K_max conformance fix.
    /// `.conformant` is now the recommended default — it produces
    /// codestreams interoperable with any Part-15 decoder.
    func testDefaultIsConformantFormat() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.htj2kBlockFormat, .conformant)
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
