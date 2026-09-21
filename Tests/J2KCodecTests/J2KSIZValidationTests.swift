//
// J2KSIZValidationTests.swift
// J2KSwift
//
// Regression tests for SIZ reference-grid validation (ISO/IEC 15444-1
// Table A.9).
//
// Before this validation existed, `parseSIZMarker` accepted every field
// verbatim and the decoder then performed trapping `Int` arithmetic on it:
//
//   *** Swift runtime failure: arithmetic overflow ***
//   DecoderPipeline.decode(_:progress:) at J2KDecoderPipeline.swift:537
//
// — i.e. `metadata.width * metadata.height`, reached by XOR-ing 16 bytes
// over Xsiz/Ysiz. A trap is not a catchable decode failure, so a malformed
// codestream aborted the host process rather than failing the decode.
//
// These tests pin the fix. Without it, the end-to-end cases below do not
// fail — they crash the test runner.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KSIZValidationTests: XCTestCase {

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
            width: 64, height: 48, data: bytes,
            sampleByteOrder: .bigEndian)
        return J2KImage(width: 64, height: 48, components: [component], colorSpace: .grayscale)
    }

    private func encodeLossless() async throws -> Data {
        try await J2KEncoder(configuration: .lossless).encode(makeImage())
    }

    /// Byte offset of the SIZ marker segment's first field (Lsiz).
    private func sizSegmentOffset(in codestream: Data) throws -> Int {
        let bytes = [UInt8](codestream)
        for i in 0..<max(0, bytes.count - 1) where bytes[i] == 0xFF && bytes[i + 1] == 0x51 {
            return i + 2
        }
        throw XCTSkip("codestream contains no SIZ marker")
    }

    /// SIZ field layout after Lsiz(2) + Rsiz(2), as 4-byte big-endian words.
    private enum SIZField: Int {
        case xsiz = 0, ysiz = 1, xOsiz = 2, yOsiz = 3
        case xtsiz = 4, ytsiz = 5, xtOsiz = 6, ytOsiz = 7
    }

    /// Overwrites one 32-bit SIZ field in a copy of `codestream`.
    private func patching(
        _ codestream: Data, _ field: SIZField, to value: UInt32
    ) throws -> Data {
        var patched = codestream
        let at = try sizSegmentOffset(in: codestream) + 4 + field.rawValue * 4
        let base = patched.startIndex
        patched[base + at + 0] = UInt8((value >> 24) & 0xFF)
        patched[base + at + 1] = UInt8((value >> 16) & 0xFF)
        patched[base + at + 2] = UInt8((value >> 8) & 0xFF)
        patched[base + at + 3] = UInt8(value & 0xFF)
        return patched
    }

    private func assertDecodeThrows(
        _ codestream: Data, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let image = try await J2KDecoder().decode(codestream)
            XCTFail(
                "\(message): expected a thrown error, but decode returned a "
                + "\(image.width)×\(image.height) image",
                file: file, line: line)
        } catch is J2KError {
            // Expected: a recoverable decode failure the caller can handle.
        } catch {
            XCTFail("\(message): expected J2KError, got \(error)", file: file, line: line)
        }
    }

    // MARK: - The reported repro

    /// XOR-ing 16 bytes across Xsiz/Ysiz used to abort the process with
    /// `Swift runtime failure: arithmetic overflow`. It must now throw.
    func testCorruptedSIZDimensionsThrowInsteadOfTrapping() async throws {
        let codestream = try await encodeLossless()
        var corrupted = codestream
        let base = corrupted.startIndex
        for i in 8..<24 {
            corrupted[base + i] ^= 0xFF
        }
        await assertDecodeThrows(corrupted, "16-byte XOR over Xsiz/Ysiz")
    }

    /// The maximal case: Xsiz × Ysiz overflows `Int` outright.
    func testMaximalDimensionsThrowInsteadOfTrapping() async throws {
        let codestream = try await encodeLossless()
        var patched = try patching(codestream, .xsiz, to: UInt32.max)
        patched = try patching(patched, .ysiz, to: UInt32.max)
        await assertDecodeThrows(patched, "Xsiz = Ysiz = 2^32 − 1")
    }

    /// A zero tile size divides by zero in `numTilesX` / `numTilesY`.
    func testZeroTileSizeThrowsInsteadOfTrapping() async throws {
        let codestream = try await encodeLossless()
        await assertDecodeThrows(
            try patching(codestream, .xtsiz, to: 0), "XTsiz = 0")
        await assertDecodeThrows(
            try patching(codestream, .ytsiz, to: 0), "YTsiz = 0")
    }

    func testZeroImageDimensionThrows() async throws {
        let codestream = try await encodeLossless()
        await assertDecodeThrows(
            try patching(codestream, .xsiz, to: 0), "Xsiz = 0")
        await assertDecodeThrows(
            try patching(codestream, .ysiz, to: 0), "Ysiz = 0")
    }

    /// Validation must not reject codestreams the encoder actually produces.
    func testValidCodestreamStillDecodesBitExact() async throws {
        let original = makeImage()
        let decoded = try await J2KDecoder().decode(
            try await J2KEncoder(configuration: .lossless).encode(original))

        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(
            decoded.components[0].data, original.components[0].data,
            "SIZ validation must not perturb a valid lossless round-trip")
    }

    // MARK: - validateSIZ unit coverage (ISO/IEC 15444-1 Table A.9)

    /// Table A.9 values the encoder emits for an untiled 64×48 image.
    private func validateSIZ(
        xsiz: Int = 64, ysiz: Int = 48,
        xOsiz: Int = 0, yOsiz: Int = 0,
        xtsiz: Int = 64, ytsiz: Int = 48,
        xtOsiz: Int = 0, ytOsiz: Int = 0,
        csiz: Int = 1
    ) throws {
        try DecoderPipeline.validateSIZ(
            xsiz: xsiz, ysiz: ysiz, xOsiz: xOsiz, yOsiz: yOsiz,
            xtsiz: xtsiz, ytsiz: ytsiz, xtOsiz: xtOsiz, ytOsiz: ytOsiz,
            csiz: csiz)
    }

    private func assertRejects(
        _ expression: () throws -> Void, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
            XCTAssertTrue(
                error is J2KError,
                "\(message): expected J2KError, got \(error)", file: file, line: line)
        }
    }

    func testValidateSIZAcceptsWellFormedFields() throws {
        XCTAssertNoThrow(try validateSIZ(), "the encoder's own SIZ must validate")
        // Tiled, offset reference grid — all within Table A.9.
        XCTAssertNoThrow(
            try validateSIZ(
                xsiz: 2048, ysiz: 2048, xOsiz: 16, yOsiz: 16,
                xtsiz: 512, ytsiz: 512, xtOsiz: 0, ytOsiz: 0, csiz: 3))
        // Maximal single-axis extent is legal so long as the product fits.
        XCTAssertNoThrow(
            try validateSIZ(xsiz: Int(UInt32.max), ysiz: 1,
                            xtsiz: Int(UInt32.max), ytsiz: 1))
    }

    func testValidateSIZRejectsEmptyReferenceGrid() {
        assertRejects({ try validateSIZ(xsiz: 0) }, "Xsiz = 0")
        assertRejects({ try validateSIZ(ysiz: 0) }, "Ysiz = 0")
    }

    func testValidateSIZRejectsImageOffsetOutsideGrid() {
        assertRejects({ try validateSIZ(xOsiz: 64) }, "XOsiz == Xsiz")
        assertRejects({ try validateSIZ(yOsiz: 48) }, "YOsiz == Ysiz")
        assertRejects({ try validateSIZ(xOsiz: 100) }, "XOsiz > Xsiz")
    }

    func testValidateSIZRejectsZeroTileSize() {
        assertRejects({ try validateSIZ(xtsiz: 0) }, "XTsiz = 0")
        assertRejects({ try validateSIZ(ytsiz: 0) }, "YTsiz = 0")
    }

    func testValidateSIZRejectsTileOffsetViolations() {
        // XTOsiz must not exceed XOsiz.
        assertRejects(
            { try validateSIZ(xOsiz: 4, yOsiz: 4, xtOsiz: 8, ytOsiz: 0) },
            "XTOsiz > XOsiz")
        assertRejects(
            { try validateSIZ(xOsiz: 4, yOsiz: 4, xtOsiz: 0, ytOsiz: 8) },
            "YTOsiz > YOsiz")
        // The first tile must reach the image origin: XTOsiz + XTsiz > XOsiz.
        assertRejects(
            { try validateSIZ(xOsiz: 32, yOsiz: 0, xtsiz: 8, xtOsiz: 0) },
            "first tile ends before XOsiz")
    }

    func testValidateSIZRejectsComponentCountOutOfRange() {
        assertRejects({ try validateSIZ(csiz: 0) }, "Csiz = 0")
        assertRejects({ try validateSIZ(csiz: 16385) }, "Csiz > 16384")
        XCTAssertNoThrow(try validateSIZ(csiz: 16384), "Csiz = 16384 is legal")
    }

    /// The trap this suite exists for: each axis is individually legal,
    /// but the product overflows `Int`.
    func testValidateSIZRejectsPixelCountOverflow() {
        assertRejects(
            { try validateSIZ(xsiz: Int(UInt32.max), ysiz: Int(UInt32.max),
                              xtsiz: Int(UInt32.max), ytsiz: Int(UInt32.max)) },
            "Xsiz × Ysiz overflows Int")
    }
}
