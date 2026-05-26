// V10_29_EncodingConfigurationParityTests.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1 parity gate.
//
// Verifies that for each lossless Transfer Syntax, the configuration
// returned by `encodingConfiguration(...)` actually drives the encoder
// into the right mode (HTJ2K vs Part 1, reversible vs irreversible),
// and produces a codestream that bit-exactly round-trips through the
// decoder.

import XCTest
import Foundation
@testable import J2KDICOMHelpers
@testable import J2KCore
@testable import J2KCodec

final class V10_29_EncodingConfigurationParityTests: XCTestCase {

    private func makeTestImage(
        width: Int = 64, height: Int = 64, seed: UInt64 = 0xCAFEBABE
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

    // MARK: - Configuration flag parity

    func testLosslessUIDsProduceLosslessConfiguration() {
        for ts in J2KDICOMTransferSyntax.allCases where ts.isLossless {
            let cfg = ts.encodingConfiguration(bitDepth: 16)
            XCTAssertTrue(cfg.lossless,
                "Lossless Transfer Syntax \(ts) must produce a lossless configuration.")
            XCTAssertTrue(cfg.useReversibleFilter,
                "Lossless Transfer Syntax \(ts) must use the reversible 5/3 filter.")
            XCTAssertEqual(cfg.quality, 1.0,
                "Lossless Transfer Syntax \(ts) must produce maximum quality.")
        }
    }

    func testLossyUIDsProduceLossyConfiguration() {
        for ts in J2KDICOMTransferSyntax.allCases where !ts.isLossless {
            let cfg = ts.encodingConfiguration(bitDepth: 16, psnrTarget: 40.0)
            XCTAssertFalse(cfg.lossless,
                "Lossy Transfer Syntax \(ts) must produce a lossy configuration.")
        }
    }

    func testHTJ2KUIDsSetHTJ2KFlag() {
        for ts in J2KDICOMTransferSyntax.allCases where ts.isHTJ2K {
            let cfg = ts.encodingConfiguration(bitDepth: 16)
            XCTAssertTrue(cfg.useHTJ2K,
                "HTJ2K Transfer Syntax \(ts) must set useHTJ2K = true.")
            XCTAssertEqual(cfg.htj2kBlockFormat, .conformant,
                "HTJ2K Transfer Syntax \(ts) must use the conformant Part-15 block format for DICOM interop.")
        }
    }

    func testPart1UIDsDoNotSetHTJ2KFlag() {
        for ts in J2KDICOMTransferSyntax.allCases where !ts.isHTJ2K {
            let cfg = ts.encodingConfiguration(bitDepth: 16)
            XCTAssertFalse(cfg.useHTJ2K,
                "Part-1 Transfer Syntax \(ts) must NOT set useHTJ2K (would emit a CAP marker).")
        }
    }

    // MARK: - End-to-end round-trip parity

    /// For each lossless Transfer Syntax that the codec supports
    /// end-to-end (j2kLossless, htj2kLossless), encode-then-decode a
    /// synthetic 64×64 16-bit image with the configuration the helper
    /// builds, and assert bit-exact reconstruction.
    func testLosslessRoundTripBitExact() async throws {
        // Restrict to the two production-supported lossless flavours:
        // j2kLossless (5/3 + EBCOT) and htj2kLossless (5/3 + HT).
        // The Part-2 multi-component variants and the lossy variants
        // need additional config knobs not in scope for Phase 1.
        let cases: [J2KDICOMTransferSyntax] = [.j2kLossless, .htj2kLossless]

        let image = makeTestImage()
        let originalBytes = image.components[0].data

        for ts in cases {
            let cfg = ts.encodingConfiguration(bitDepth: 16)
            let encoder = J2KEncoder(encodingConfiguration: cfg)
            let codestream = try await encoder.encode(image)
            XCTAssertGreaterThan(codestream.count, 0,
                "\(ts) encode produced empty codestream.")

            let decoder = J2KDecoder()
            let decoded = try await decoder.decode(codestream)
            XCTAssertEqual(decoded.components.count, 1,
                "\(ts) decode lost components.")
            XCTAssertEqual(decoded.components[0].data, originalBytes,
                "\(ts) lossless round-trip is not bit-exact.")
        }
    }
}
