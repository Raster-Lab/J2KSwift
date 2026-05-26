// V10_29_CodestreamDetectionTests.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1 parity gate.
//
// Encodes a small image via each supported Transfer Syntax's
// configuration, then asserts that `J2KDICOMCodestreamDetector.detect`
// returns the matching Transfer Syntax. This validates that the
// detector's CAP-marker check correctly distinguishes Part-1 vs Part-15
// codestreams produced by J2KSwift's own encoder.

import XCTest
import Foundation
@testable import J2KDICOMHelpers
@testable import J2KCore
@testable import J2KCodec

final class V10_29_CodestreamDetectionTests: XCTestCase {

    private func makeTestImage(
        width: Int = 64, height: Int = 64, seed: UInt64 = 0x1234_5678
    ) -> J2KImage {
        var bytes = Data(count: width * height * 2)
        var s = seed &* 6364136223846793005 &+ 1442695040888963407
        bytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<(width * height) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFF))
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height,
            data: bytes, sampleByteOrder: .bigEndian)
        return J2KImage(width: width, height: height, components: [comp])
    }

    // MARK: - Positive detection

    func testDetectJ2KLossless() async throws {
        let image = makeTestImage()
        let cfg = J2KDICOMTransferSyntax.j2kLossless.encodingConfiguration()
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let detected = J2KDICOMCodestreamDetector.detect(codestream)
        XCTAssertEqual(detected, .j2kLossless,
            "Codestream produced by .j2kLossless configuration should detect as .j2kLossless (no CAP marker).")
    }

    func testDetectHTJ2KLossless() async throws {
        let image = makeTestImage()
        let cfg = J2KDICOMTransferSyntax.htj2kLossless.encodingConfiguration()
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let detected = J2KDICOMCodestreamDetector.detect(codestream)
        XCTAssertEqual(detected, .htj2kLossless,
            "Codestream produced by .htj2kLossless configuration should detect as .htj2kLossless (CAP marker present).")
    }

    // MARK: - Negative — non-J2K bytes

    func testEmptyDataReturnsNil() {
        XCTAssertNil(J2KDICOMCodestreamDetector.detect(Data()))
    }

    func testTruncatedDataReturnsNil() {
        XCTAssertNil(J2KDICOMCodestreamDetector.detect(Data([0xFF])))
    }

    func testNonJ2KBytesReturnNil() {
        // JPEG SOI marker — recognisable image format, but not J2K.
        let jpegSOI = Data([0xFF, 0xD8, 0xFF, 0xE0])
        XCTAssertNil(J2KDICOMCodestreamDetector.detect(jpegSOI),
            "JPEG file (starting with SOI 0xFFD8) must NOT be misdetected as J2K.")

        // PNG signature.
        let pngSig = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertNil(J2KDICOMCodestreamDetector.detect(pngSig),
            "PNG file must NOT be misdetected as J2K.")

        // Random non-codestream bytes.
        let random = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        XCTAssertNil(J2KDICOMCodestreamDetector.detect(random))
    }

    // MARK: - Boundary

    func testSOCOnlyTruncatedReturnsFallback() {
        // SOC marker but truncated immediately after. Conservative
        // classification: fall back to legacy Part-1 lossless.
        let socOnly = Data([0xFF, 0x4F])
        let detected = J2KDICOMCodestreamDetector.detect(socOnly)
        // Either nil (too short) or .j2kLossless (conservative fallback)
        // are acceptable. The contract says nil for `count < 4`.
        XCTAssertNil(detected)
    }
}
