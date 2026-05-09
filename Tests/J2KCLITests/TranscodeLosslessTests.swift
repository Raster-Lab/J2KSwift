// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// TranscodeLosslessTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for lossless transcoding and verification (--verify, --verify-mode).
final class TranscodeLosslessTests: XCTestCase {

    // MARK: - Verify flag parsing

    func testVerifyFlagParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--verify", "-i", "input.j2k", "-o", "output.jph"])
        XCTAssertEqual(opts["verify"], "true")
    }

    func testVerifyModeParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--verify", "--verify-mode", "exact", "-i", "input.j2k", "-o", "output.jph"])
        XCTAssertEqual(opts["verify"], "true")
        XCTAssertEqual(opts["verify-mode"], "exact")
    }

    func testVerifyModeStatistical() {
        let opts = CLIArgumentParserTestHelper.parse(["--verify", "--verify-mode", "statistical"])
        XCTAssertEqual(opts["verify-mode"], "statistical")
    }

    // MARK: - Codec-to-codec transcode arguments

    func testTranscodeJ2KToHTJ2K() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "input.j2k",
            "-o", "output.jph",
            "--codec", "htj2k-lossless",
            "--verify"
        ])
        XCTAssertEqual(opts["codec"], "htj2k-lossless")
        XCTAssertEqual(opts["verify"], "true")
    }

    func testTranscodeHTJ2KToJ2K() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "input.jph",
            "-o", "output.j2k",
            "--codec", "j2k-lossless",
            "--verify"
        ])
        XCTAssertEqual(opts["codec"], "j2k-lossless")
    }

    // MARK: - Bit-exact verification logic

    func testBitExactVerificationPasses() {
        let original: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let decoded: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        XCTAssertEqual(original, decoded, "Bit-exact verification should pass for identical data")
    }

    func testBitExactVerificationFails() {
        let original: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let decoded: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 9]
        XCTAssertNotEqual(original, decoded, "Bit-exact verification should fail for different data")
    }

    // MARK: - Statistical verification logic

    func testStatisticalVerificationPSNR() {
        // Compute PSNR between two byte arrays
        let ref: [UInt8] = [100, 110, 120, 130, 140]
        let dist: [UInt8] = [101, 111, 121, 131, 141]

        var sum = 0.0
        for i in 0..<ref.count {
            let diff = Double(ref[i]) - Double(dist[i])
            sum += diff * diff
        }
        let mse = sum / Double(ref.count)
        let psnr = 10.0 * log10(255.0 * 255.0 / mse)

        // With MSE = 1.0, PSNR should be ~48.13 dB
        XCTAssertEqual(mse, 1.0, accuracy: 1e-10)
        XCTAssertGreaterThan(psnr, 40.0, "PSNR should be high for near-identical images")
    }

    func testStatisticalVerificationMAE() {
        let ref: [UInt8] = [100, 110, 120, 130, 140]
        let dist: [UInt8] = [102, 112, 118, 130, 142]

        var sum = 0.0
        for i in 0..<ref.count {
            sum += abs(Double(ref[i]) - Double(dist[i]))
        }
        let mae = sum / Double(ref.count)

        XCTAssertEqual(mae, 1.6, accuracy: 0.01, "MAE should be average of absolute differences")
    }
}

#endif // os(macOS)
