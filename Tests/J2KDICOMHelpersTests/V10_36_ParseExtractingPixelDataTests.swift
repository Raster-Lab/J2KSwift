// V10_36_ParseExtractingPixelDataTests.swift
//
// v10.24.0 — J2KDICOMHelpers Phase 3.1 parity gate. Verifies
// J2KDICOMFileParser.parseExtractingPixelData(_:) returns:
//   * `.j2kCompressed(metadata, pixelDataBytes)` for J2K-tagged files —
//     same bytes as parse(_:) would return
//   * `.uncompressed(metadata, pixelDataBytes)` for non-J2K files —
//     pixel data sliced from the (7FE0,0010) element's value bytes,
//     respecting the metadata's frameSizeInBytes × numberOfFrames

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KDICOMHelpers

final class V10_36_ParseExtractingPixelDataTests: XCTestCase {

    // MARK: - Fixture builders (mirror V10_33's pattern)

    private func makeImage(seed: UInt64 = 0xCAFEBABE) -> J2KImage {
        let w = 16, h = 16
        var bytes = Data(count: w * h * 2)
        var s = seed &* 6364136223846793005 &+ 1442695040888963407
        bytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<(w * h) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFF))
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: w, height: h,
            data: bytes, sampleByteOrder: .bigEndian)
        return J2KImage(width: w, height: h, components: [comp])
    }

    /// Hand-builds a minimal DICOM file with the given Transfer Syntax UID
    /// + image-pixel-module tags + a fixed-length Pixel Data element
    /// carrying the supplied bytes. Same scaffold as V10_33's J2K-tagged
    /// synthesis, but tweaked to support the uncompressed case (fixed-
    /// length pixel data instead of undefined-length encapsulated).
    private func buildSyntheticDICOMFile(
        transferSyntaxUID: String,
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        numberOfFrames: Int,
        pixelDataBytes: Data,
        encapsulated: Bool
    ) -> Data {
        var out = Data()
        out.reserveCapacity(132 + 200 + pixelDataBytes.count)

        // 128-byte preamble + DICM magic
        out.append(Data(repeating: 0, count: 128))
        out.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])

        // Group 0002: Transfer Syntax UID (Explicit VR LE)
        let uidBytes = transferSyntaxUID.data(using: .ascii)!
        let uidPadded = uidBytes.count % 2 == 0 ? uidBytes : uidBytes + Data([0x00])
        out.append(contentsOf: [0x02, 0x00, 0x10, 0x00, 0x55, 0x49])
        let uidLen = UInt16(uidPadded.count)
        out.append(UInt8(uidLen & 0xFF))
        out.append(UInt8((uidLen >> 8) & 0xFF))
        out.append(uidPadded)

        // Dataset (Explicit VR LE for the test UIDs we use)
        // Tags must be ascending: (0028,0002), (0028,0004), (0028,0008), (0028,0010), …
        appendShortVR(&out, group: 0x0028, element: 0x0002, vr: "US", value: u16LE(UInt16(samplesPerPixel)))
        let piPadded = photometricInterpretation.data(using: .ascii)!
            + (photometricInterpretation.count % 2 == 0 ? Data() : Data([0x20]))
        appendShortVR(&out, group: 0x0028, element: 0x0004, vr: "CS", value: piPadded)
        if numberOfFrames > 1 {
            let framesStr = "\(numberOfFrames)"
            let framesBytes = framesStr.data(using: .ascii)!
            let framesPadded = framesBytes.count % 2 == 0 ? framesBytes : framesBytes + Data([0x20])
            appendShortVR(&out, group: 0x0028, element: 0x0008, vr: "IS", value: framesPadded)
        }
        appendShortVR(&out, group: 0x0028, element: 0x0010, vr: "US", value: u16LE(UInt16(rows)))
        appendShortVR(&out, group: 0x0028, element: 0x0011, vr: "US", value: u16LE(UInt16(columns)))
        appendShortVR(&out, group: 0x0028, element: 0x0100, vr: "US", value: u16LE(UInt16(bitsAllocated)))
        if bitsStored != 0 {
            appendShortVR(&out, group: 0x0028, element: 0x0101, vr: "US", value: u16LE(UInt16(bitsStored)))
        }
        appendShortVR(&out, group: 0x0028, element: 0x0103, vr: "US", value: u16LE(0))

        // (7FE0,0010) Pixel Data
        out.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00, 0x4F, 0x42, 0x00, 0x00])  // tag + VR=OB + 2 reserved
        if encapsulated {
            // Undefined length + encapsulated item sequence (caller's bytes ARE the item sequence)
            out.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        } else {
            // Fixed length = pixelDataBytes.count (must be even per PS3.5 §6.4)
            let len = UInt32(pixelDataBytes.count)
            out.append(UInt8(len & 0xFF))
            out.append(UInt8((len >> 8) & 0xFF))
            out.append(UInt8((len >> 16) & 0xFF))
            out.append(UInt8((len >> 24) & 0xFF))
        }
        out.append(pixelDataBytes)
        return out
    }

    private func u16LE(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private func appendShortVR(
        _ data: inout Data, group: UInt16, element: UInt16, vr: String, value: Data
    ) {
        data.append(UInt8(group & 0xFF)); data.append(UInt8((group >> 8) & 0xFF))
        data.append(UInt8(element & 0xFF)); data.append(UInt8((element >> 8) & 0xFF))
        data.append(vr.data(using: .ascii)!)
        let len = UInt16(value.count)
        data.append(UInt8(len & 0xFF)); data.append(UInt8((len >> 8) & 0xFF))
        data.append(value)
    }

    // MARK: - J2K-tagged path

    /// For J2K-tagged transfer syntaxes, parseExtractingPixelData returns
    /// the SAME bytes as parse(_:) would have in the .j2kCompressed case.
    func testJ2KTaggedReturnsJ2KCompressedSameBytesAsParse() async throws {
        let image = makeImage()
        let cfg = J2KDICOMTransferSyntax.htj2kLossless.encodingConfiguration()
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let pixelDataSeq = J2KDICOMPixelDataEncapsulator
            .encapsulateFrames([codestream], includeBOT: false)

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.4.201",
            rows: image.height, columns: image.width,
            bitsAllocated: 16, bitsStored: 16,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            pixelDataBytes: pixelDataSeq, encapsulated: true)

        // Reference: existing parse(_:) returns J2KDICOMFile.j2kCompressed.
        let viaParse = try J2KDICOMFileParser.parse(dcm)
        guard case .j2kCompressed(let m1, let b1) = viaParse else {
            XCTFail("parse(_:) should return .j2kCompressed for HTJ2K UID")
            return
        }

        // New method: parseExtractingPixelData returns same bytes.
        let viaExtract = try J2KDICOMFileParser.parseExtractingPixelData(dcm)
        guard case .j2kCompressed(let m2, let b2) = viaExtract else {
            XCTFail("parseExtractingPixelData should return .j2kCompressed for HTJ2K UID")
            return
        }

        XCTAssertEqual(m1, m2, "Metadata must be identical across both parse paths.")
        XCTAssertEqual(b1, b2, "Pixel data bytes must be identical across both parse paths.")
        XCTAssertEqual(viaExtract.metadata.transferSyntaxUID, "1.2.840.10008.1.2.4.201")
        XCTAssertTrue(viaExtract.isJ2KCompressed)
    }

    // MARK: - Uncompressed path

    /// For uncompressed transfer syntax, parseExtractingPixelData returns
    /// the raw Pixel Data bytes computed from rows × columns × samples
    /// × bytesPerSample × frames.
    func testUncompressedReturnsRawPixelDataBytes() throws {
        // 16×16 16-bit unsigned MONOCHROME2 single-frame = 16*16*2 = 512 bytes
        let pixelData = Data((0..<512).map { UInt8(truncatingIfNeeded: $0) })

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.1",  // Explicit VR LE (uncompressed)
            rows: 16, columns: 16,
            bitsAllocated: 16, bitsStored: 16,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            pixelDataBytes: pixelData, encapsulated: false)

        let parsed = try J2KDICOMFileParser.parseExtractingPixelData(dcm)
        guard case .uncompressed(let metadata, let extracted) = parsed else {
            XCTFail("Expected .uncompressed for Explicit VR LE UID, got \(parsed)")
            return
        }
        XCTAssertEqual(metadata.transferSyntaxUID, "1.2.840.10008.1.2.1")
        XCTAssertEqual(extracted, pixelData,
            "Extracted pixel data must be byte-identical to the source.")
        XCTAssertEqual(extracted.count, metadata.frameSizeInBytes,
            "Single-frame extracted bytes must match frameSizeInBytes.")
        XCTAssertFalse(parsed.isJ2KCompressed)
    }

    /// Multi-frame uncompressed: extracted bytes = N × frameSize.
    func testUncompressedMultiFrameReturnsAllFrames() throws {
        // 8×8 8-bit MONOCHROME2 3-frame = 8*8*1*3 = 192 bytes
        let pixelData = Data((0..<192).map { UInt8(truncatingIfNeeded: $0) })

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.1",
            rows: 8, columns: 8,
            bitsAllocated: 8, bitsStored: 8,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 3,
            pixelDataBytes: pixelData, encapsulated: false)

        let parsed = try J2KDICOMFileParser.parseExtractingPixelData(dcm)
        guard case .uncompressed(let metadata, let extracted) = parsed else {
            XCTFail("Expected .uncompressed, got \(parsed)")
            return
        }
        XCTAssertEqual(metadata.numberOfFrames, 3)
        XCTAssertEqual(extracted, pixelData)
        XCTAssertEqual(extracted.count, metadata.frameSizeInBytes * 3)
    }

    /// Truncated source → throws .truncatedFile.
    func testUncompressedTruncatedThrows() throws {
        // Declare 16×16×2 = 512 bytes of pixel data but provide only 100.
        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.1",
            rows: 16, columns: 16,
            bitsAllocated: 16, bitsStored: 16,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            pixelDataBytes: Data(count: 100),  // too short
            encapsulated: false)

        XCTAssertThrowsError(try J2KDICOMFileParser.parseExtractingPixelData(dcm)) { error in
            if case .truncatedFile = error as? J2KDICOMFileError {
                // expected
            } else {
                XCTFail("Expected .truncatedFile, got \(error)")
            }
        }
    }

    // MARK: - J2KDICOMFileWithPixelData convenience

    /// .metadata, .pixelDataBytes, .isJ2KCompressed convenience accessors
    /// return correct values for each variant.
    func testConvenienceAccessors() {
        let metadata = J2KDICOMFileMetadata(
            transferSyntaxUID: "1.2.840.10008.1.2.4.201",
            rows: 16, columns: 16,
            bitsAllocated: 16, bitsStored: 16,
            pixelRepresentation: 0,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            planarConfiguration: 0)
        let bytes = Data([0xFF, 0x4F, 0xFF, 0xD9])

        let j2kCase = J2KDICOMFileWithPixelData.j2kCompressed(metadata: metadata, pixelDataBytes: bytes)
        XCTAssertEqual(j2kCase.metadata, metadata)
        XCTAssertEqual(j2kCase.pixelDataBytes, bytes)
        XCTAssertTrue(j2kCase.isJ2KCompressed)

        let uncompressedCase = J2KDICOMFileWithPixelData.uncompressed(metadata: metadata, pixelDataBytes: bytes)
        XCTAssertEqual(uncompressedCase.metadata, metadata)
        XCTAssertEqual(uncompressedCase.pixelDataBytes, bytes)
        XCTAssertFalse(uncompressedCase.isJ2KCompressed)
    }
}
