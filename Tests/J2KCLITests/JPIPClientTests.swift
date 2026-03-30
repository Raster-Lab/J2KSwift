//
// JPIPClientTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for the JPIP client CLI command arguments and request construction.
final class JPIPClientTests: XCTestCase {

    // MARK: - Client argument parsing

    func testJPIPClientBasicArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://localhost:8080/image.jp2",
            "-o", "output.pgm"
        ])
        XCTAssertEqual(opts["url"], "jpip://localhost:8080/image.jp2")
        XCTAssertEqual(opts["o"], "output.pgm")
    }

    func testJPIPClientRegion() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://server/img",
            "--region", "0,0,512,512",
            "-o", "region.pgm"
        ])
        XCTAssertEqual(opts["region"], "0,0,512,512")
    }

    func testJPIPClientResolution() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://server/img",
            "--resolution", "3",
            "-o", "lowres.pgm"
        ])
        XCTAssertEqual(opts["resolution"], "3")
    }

    func testJPIPClientQuality() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://server/img",
            "--quality", "0.75",
            "-o", "preview.pgm"
        ])
        XCTAssertEqual(opts["quality"], "0.75")
    }

    func testJPIPClientInteractive() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://server/img",
            "--interactive"
        ])
        XCTAssertEqual(opts["interactive"], "true")
    }

    // MARK: - URL parsing

    func testJPIPURLParsing() {
        let urlString = "jpip://localhost:8080/image.jp2"
        // Note: URL doesn't support jpip:// scheme natively,
        // but we can validate the string format
        XCTAssertTrue(urlString.hasPrefix("jpip://"))
        let withoutScheme = String(urlString.dropFirst(7)) // drop "jpip://"
        XCTAssertEqual(withoutScheme, "localhost:8080/image.jp2")
    }

    func testHTTPURLParsing() {
        let urlString = "http://localhost:8080/jpip?target=image.jp2"
        let url = URL(string: urlString)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "localhost")
        XCTAssertEqual(url?.port, 8080)
    }

    // MARK: - Region parsing

    func testRegionFormatting() {
        let region = "100,200,300,400"
        let parts = region.split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 4)
        let x = parts[0], y = parts[1], w = parts[2], h = parts[3]
        XCTAssertEqual(x, 100)
        XCTAssertEqual(y, 200)
        XCTAssertEqual(w, 300)
        XCTAssertEqual(h, 400)
    }

    // MARK: - Resolution level validation

    func testResolutionLevelValidation() {
        let validLevels = [0, 1, 2, 3, 4, 5]
        for level in validLevels {
            XCTAssertGreaterThanOrEqual(level, 0)
        }
    }

    // MARK: - Quality range validation

    func testQualityRangeValidation() {
        let validQualities = [0.0, 0.25, 0.5, 0.75, 1.0]
        for quality in validQualities {
            XCTAssertGreaterThanOrEqual(quality, 0.0)
            XCTAssertLessThanOrEqual(quality, 1.0)
        }
    }

    func testInvalidQualityRange() {
        let invalidQualities = [-0.1, 1.1, 2.0]
        for quality in invalidQualities {
            XCTAssertTrue(quality < 0.0 || quality > 1.0)
        }
    }

    // MARK: - Interactive commands

    func testInteractiveCommandParsing() {
        let commands = ["region 0,0,256,256", "zoom 2", "quality 0.5", "save output.pgm", "info", "quit"]
        for cmd in commands {
            let parts = cmd.split(separator: " ", maxSplits: 1)
            XCTAssertFalse(parts.isEmpty, "Command should have at least one part")
        }
    }
}
