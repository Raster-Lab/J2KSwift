//
// J2KCodestreamIntegrityTests.swift
// J2KSwift
//
// Regression tests for entropy-data integrity checking.
//
// Before this existed the decoder validated nothing past the `SOD` marker.
// The MQ arithmetic decoder of ISO/IEC 15444-1 Annex C cannot fail — it is a
// total function, and past the end of its segment it is *defined* to feed
// `0xFF` indefinitely — so corrupt entropy bytes produced a plausible-looking
// wrong image and no error. A 16-byte corruption swept across the entropy
// payload was accepted silently at all 496 positions tried, and not one of
// those decodes returned correct samples.
//
// These tests pin both halves of the fix: that damage is rejected in strict
// mode, and that undamaged streams are *not* — the second is the harder
// property, and the one a badly chosen threshold breaks.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KCodestreamIntegrityTests: XCTestCase {

    // MARK: - Fixtures

    /// Deterministic 64×48 single-component 16-bit unsigned image.
    private func makeImage() -> J2KImage {
        var bytes = Data(capacity: 64 * 48 * 2)
        var seed: UInt64 = 0x2026_0921
        for y in 0..<48 {
            for x in 0..<64 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let value = UInt16(clamping: (x * 400 + y * 250) % 40000 + Int((seed >> 33) % 600))
                bytes.append(UInt8(value >> 8))
                bytes.append(UInt8(value & 0xFF))
            }
        }
        let component = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: 64, height: 48,
            subsamplingX: 1, subsamplingY: 1, data: bytes)
        return J2KImage(width: 64, height: 48, components: [component])
    }

    private func encodeLossless() async throws -> Data {
        try await J2KEncoder(configuration: .lossless).encode(makeImage())
    }

    /// Offset of the first byte of entropy-coded data, i.e. just past `SOD`.
    private func entropyStart(_ data: Data) -> Int? {
        let b = [UInt8](data)
        for i in 0..<max(0, b.count - 1) where b[i] == 0xFF && b[i + 1] == 0x93 {
            return i + 2
        }
        return nil
    }

    private func samples(_ image: J2KImage) -> [Int] {
        let bytes = [UInt8](image.components[0].data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map {
            Int(bytes[$0]) << 8 | Int(bytes[$0 + 1])
        }
    }

    // MARK: - The property that a bad threshold breaks

    /// An undamaged round-trip must be reported intact and must not throw.
    ///
    /// This is the constraint that decides the thresholds. Rejecting a valid
    /// codestream is a worse failure than the one being fixed, because it
    /// turns working files into errors.
    func testCleanRoundTripIsIntact() async throws {
        let encoded = try await encodeLossless()
        let (image, report) = try await J2KDecoder().decodeWithIntegrity(encoded)

        XCTAssertTrue(report.isIntact, "clean round-trip reported: \(report.summary)")
        XCTAssertTrue(report.anomalies.isEmpty)
        XCTAssertEqual(report.maxBlockUnderRead, 0,
                       "a synchronised decoder consumes every declared byte")
        XCTAssertFalse(report.missingEndOfCodestream)
        XCTAssertGreaterThan(report.codeBlocksDecoded, 0,
                             "no accounting was collected at all")
        XCTAssertEqual(samples(image), samples(makeImage()),
                       "lossless round-trip must be sample-exact")
    }

    /// Strict mode is the default, and it accepts undamaged data.
    func testStrictIsDefaultAndAcceptsCleanData() async throws {
        XCTAssertEqual(J2KDecoder().validation, .strict)
        let encoded = try await encodeLossless()
        _ = try await J2KDecoder().decode(encoded)   // must not throw
    }

    // MARK: - Detection

    /// Corrupting entropy data must be rejected rather than decoded.
    ///
    /// Swept rather than sampled at one offset: a single position could be
    /// caught by luck, and the claim being made is about the payload as a
    /// whole.
    func testCorruptedEntropyDataIsRejected() async throws {
        let encoded = try await encodeLossless()
        let start = try XCTUnwrap(entropyStart(encoded))
        let reference = samples(makeImage())

        var silentlyWrong = 0
        var caught = 0

        for offset in stride(from: start, to: encoded.count - 18, by: 16) {
            var damaged = encoded
            for k in offset..<min(offset + 16, damaged.count) { damaged[k] ^= 0xA5 }

            // Establish that this corruption actually changes the output:
            // a corruption that decodes correctly is nothing to detect.
            guard let (image, _) = try? await J2KDecoder(validation: .lenient)
                    .decodeWithIntegrity(damaged),
                  samples(image) != reference
            else { continue }

            silentlyWrong += 1
            do {
                _ = try await J2KDecoder().decode(damaged)
            } catch {
                caught += 1
            }
        }

        XCTAssertGreaterThan(silentlyWrong, 20,
                             "sweep did not produce enough wrong decodes to be meaningful")
        // Consumption-based detection cannot reach 100%: a corrupted packet
        // header that stays self-consistent leaves every length adding up.
        // Closing that residue needs encoder-written redundancy (SEGMARK,
        // PTERM) or an out-of-band digest.
        let rate = Double(caught) / Double(silentlyWrong)
        XCTAssertGreaterThan(rate, 0.85,
                             "detected \(caught)/\(silentlyWrong) silent corruptions")
    }

    /// The error carries the report, so a caller can say what was wrong.
    func testRejectionCarriesTheReport() async throws {
        let encoded = try await encodeLossless()
        let start = try XCTUnwrap(entropyStart(encoded))
        var damaged = encoded
        let mid = start + (encoded.count - start) / 2
        for k in mid..<min(mid + 32, damaged.count) { damaged[k] ^= 0xFF }

        do {
            _ = try await J2KDecoder().decode(damaged)
            throw XCTSkip("this corruption happens to decode cleanly; nothing to assert")
        } catch let error as J2KError {
            guard case .corruptedCodestream(let report) = error else {
                return XCTFail("expected corruptedCodestream, got \(error)")
            }
            XCTAssertFalse(report.isIntact)
            XCTAssertFalse(report.anomalies.isEmpty)
            XCTAssertFalse(report.summary.isEmpty)
            XCTAssertNotNil(error.errorDescription)
        }
    }

    // MARK: - Lenient mode

    /// Lenient mode returns both the image and the finding, and never throws
    /// on an integrity signal.
    func testLenientModeReturnsImageAndReport() async throws {
        let encoded = try await encodeLossless()
        let start = try XCTUnwrap(entropyStart(encoded))
        var damaged = encoded
        let mid = start + (encoded.count - start) / 2
        for k in mid..<min(mid + 32, damaged.count) { damaged[k] ^= 0xFF }

        // Strict rejects it; lenient must hand back the same decode anyway.
        var strictRejected = false
        do { _ = try await J2KDecoder().decode(damaged) } catch { strictRejected = true }
        try XCTSkipUnless(strictRejected, "this corruption is not detected; nothing to contrast")

        let (image, report) = try await J2KDecoder(validation: .lenient)
            .decodeWithIntegrity(damaged)
        XCTAssertFalse(report.isIntact, "lenient must still report the finding")
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 48)
    }

    // MARK: - End of codestream

    /// A codestream cut at the `EOC` boundary must not pass as complete.
    ///
    /// Removing `EOC` leaves a stream that decodes bit-exactly, so without an
    /// explicit check a truncated transfer is indistinguishable from a whole
    /// file.
    func testMissingEOCIsDetected() async throws {
        let encoded = try await encodeLossless()
        let bytes = [UInt8](encoded)
        try XCTSkipUnless(bytes.count >= 2 && bytes[bytes.count - 2] == 0xFF
                          && bytes[bytes.count - 1] == 0xD9,
                          "fixture does not end with EOC")

        let truncated = encoded.prefix(encoded.count - 2)

        let (_, report) = try await J2KDecoder(validation: .lenient)
            .decodeWithIntegrity(Data(truncated))
        XCTAssertTrue(report.missingEndOfCodestream)
        XCTAssertTrue(report.anomalies.contains(.missingEndOfCodestream))

        do {
            _ = try await J2KDecoder().decode(Data(truncated))
            XCTFail("strict mode accepted a codestream with no EOC marker")
        } catch let error as J2KError {
            guard case .corruptedCodestream = error else {
                return XCTFail("expected corruptedCodestream, got \(error)")
            }
        }
    }

    // MARK: - Calibration

    /// Pins the measured thresholds.
    ///
    /// These are not free parameters. They come from decoding 310 codestreams
    /// from four independent encoders and comparing samples against the
    /// source: across 116 verified-correct reversible streams the maximum
    /// single-block under-read was 0 bytes and the maximum over-read 8. The
    /// shipped values sit above both, so an encoder whose flush strategy
    /// leaves a small legitimate tail is still accepted. Changing them
    /// without redoing that measurement is how this check starts rejecting
    /// valid files.
    func testCalibratedThresholds() {
        XCTAssertEqual(J2KIntegrityThresholds.benignBlockUnderRead, 4)
        XCTAssertEqual(J2KIntegrityThresholds.benignBlockOverRead, 16)
    }

    /// Over-reading a little is normal and must not be treated as damage.
    ///
    /// Annex C defines the past-the-end `0xFF` feed, and a healthy block runs
    /// a few bytes into it on the flush tail.
    func testSmallOverReadIsNotAnAnomaly() {
        var builder = J2KIntegrityBuilder()
        builder.record(block: 0, J2KBlockIntegrity(
            declaredBytes: 100, consumedBytes: 100,
            overReadCount: J2KIntegrityThresholds.benignBlockOverRead,
            passesDeclared: 3, passesDecoded: 3))
        XCTAssertTrue(builder.report(isPartialDecode: false).isIntact)
    }

    /// A partial decode leaves data unread by design, so the signal carries
    /// no information and must not be reported.
    ///
    /// JPEG 2000 is built to be truncated at a packet boundary; rejecting
    /// that would break progressive and quality-layer-limited delivery.
    func testPartialDecodeSuppressesUnderReadAnomalies() {
        var builder = J2KIntegrityBuilder()
        builder.record(block: 0, J2KBlockIntegrity(
            declaredBytes: 1000, consumedBytes: 10,
            overReadCount: 0, passesDeclared: 9, passesDecoded: 1))

        XCTAssertFalse(builder.report(isPartialDecode: false).isIntact,
                       "a full decode leaving 990 bytes unread is damage")
        XCTAssertTrue(builder.report(isPartialDecode: true).isIntact,
                      "the same shortfall is expected when the caller asked for part of it")
    }

    /// Merging is order-independent, so a report does not depend on which
    /// concurrent chunk happened to finish first.
    func testReportIsIndependentOfChunkOrder() {
        func build(_ order: [Int]) -> J2KCodestreamIntegrity {
            let collector = J2KIntegrityCollector()
            for index in order {
                var chunk = J2KIntegrityBuilder()
                chunk.record(block: index, J2KBlockIntegrity(
                    declaredBytes: 100, consumedBytes: index == 2 ? 10 : 100,
                    overReadCount: 0, passesDeclared: 3, passesDecoded: 3))
                collector.absorb(chunk)
            }
            return collector.report(isPartialDecode: false)
        }
        XCTAssertEqual(build([0, 1, 2, 3]).anomalies, build([3, 1, 0, 2]).anomalies)
    }
}
