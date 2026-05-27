// V10_33_FileParserJ2KSynthesisTests.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Synthesises a J2K-tagged DICOM file at test setup time (no binary
// fixtures committed) by:
//   1. Encoding a small image via J2KEncoder (with config from
//      J2KDICOMTransferSyntax.htj2kLossless.encodingConfiguration()).
//   2. Wrapping the codestream as Pixel Data via
//      J2KDICOMPixelDataEncapsulator.encapsulateFrames(_:).
//   3. Prepending a minimal hand-built DICOM header (preamble + DICM +
//      group 0002 with htj2kLossless UID + dataset with image-pixel-
//      module tags + Pixel Data element).
//
// Then parses it back via J2KDICOMFileParser.parse(_:) and verifies:
//   - Returns .j2kCompressed
//   - Metadata round-trips (rows, columns, bits, photometric, etc.)
//   - pixelDataBytes round-trips through extractFrames(_:) to recover
//     the original codestream byte-identically.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KDICOMHelpers

final class V10_33_FileParserJ2KSynthesisTests: XCTestCase {

    /// Builds a tiny 16×16 16-bit single-component test image with
    /// deterministic LCG-generated voxels.
    private func makeTestImage(
        width: Int = 16, height: Int = 16, seed: UInt64 = 0xCAFEBABE
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

    /// Builds a hand-crafted DICOM file with the given Transfer Syntax
    /// UID and encapsulated Pixel Data. Uses ONLY the tags the parser
    /// reads (Image Pixel Module subset + Pixel Data); skips IODs that
    /// aren't needed for the parser test.
    private func buildSyntheticDICOMFile(
        transferSyntaxUID: String,
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        numberOfFrames: Int,
        pixelDataItemSequence: Data
    ) -> Data {
        var out = Data()
        out.reserveCapacity(132 + 200 + pixelDataItemSequence.count)

        // 128-byte preamble + DICM magic
        out.append(Data(repeating: 0, count: 128))
        out.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])  // "DICM"

        // --- Group 0002 (File Meta Information, always Explicit VR LE) ---
        // (0002,0010) Transfer Syntax UID, VR=UI
        // Element: tag (4B) + VR (2B "UI") + length (2B LE) + value
        let uidBytes = transferSyntaxUID.data(using: .ascii) ?? Data()
        // Pad UID to even length (DICOM PS3.5 §6.2 — UID padded with 0x00, not 0x20)
        let paddedUID: Data = uidBytes.count % 2 == 0
            ? uidBytes
            : uidBytes + Data([0x00])

        out.append(contentsOf: [0x02, 0x00, 0x10, 0x00])  // tag (0002,0010)
        out.append(contentsOf: [0x55, 0x49])              // VR = "UI"
        let uidLen = UInt16(paddedUID.count)
        out.append(UInt8(uidLen & 0xFF))
        out.append(UInt8((uidLen >> 8) & 0xFF))
        out.append(paddedUID)

        // --- Dataset (Explicit VR Little Endian for J2K UIDs) ---
        // Tags must be written in ascending (group, element) order per PS3.5 §7.

        // (0028,0002) Samples per Pixel, VR=US
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0002, vr: "US",
                             value: u16LEData(UInt16(samplesPerPixel)))

        // (0028,0004) Photometric Interpretation, VR=CS
        let piBytes = photometricInterpretation.data(using: .ascii) ?? Data()
        let piPadded = piBytes.count % 2 == 0 ? piBytes : piBytes + Data([0x20])  // space-pad for CS
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0004, vr: "CS",
                             value: piPadded)

        // (0028,0008) Number of Frames, VR=IS — required for multi-frame
        if numberOfFrames > 1 {
            let frameStr = "\(numberOfFrames)"
            let frameBytes = frameStr.data(using: .ascii)!
            let framePadded = frameBytes.count % 2 == 0 ? frameBytes : frameBytes + Data([0x20])
            appendShortVRElement(to: &out, group: 0x0028, element: 0x0008, vr: "IS",
                                 value: framePadded)
        }

        // (0028,0010) Rows, VR=US
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0010, vr: "US",
                             value: u16LEData(UInt16(rows)))

        // (0028,0011) Columns, VR=US
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0011, vr: "US",
                             value: u16LEData(UInt16(columns)))

        // (0028,0100) Bits Allocated, VR=US
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0100, vr: "US",
                             value: u16LEData(UInt16(bitsAllocated)))

        // (0028,0101) Bits Stored, VR=US (if specified)
        if bitsStored != 0 {
            appendShortVRElement(to: &out, group: 0x0028, element: 0x0101, vr: "US",
                                 value: u16LEData(UInt16(bitsStored)))
        }

        // (0028,0103) Pixel Representation, VR=US
        appendShortVRElement(to: &out, group: 0x0028, element: 0x0103, vr: "US",
                             value: u16LEData(0))

        // (7FE0,0010) Pixel Data, VR=OB, undefined length (0xFFFFFFFF)
        // Long-VR header: tag (4B) + VR (2B) + 2 reserved + length (4B LE)
        out.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00])  // tag (7FE0,0010)
        out.append(contentsOf: [0x4F, 0x42])              // VR = "OB"
        out.append(contentsOf: [0x00, 0x00])              // 2 reserved
        out.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // length = undefined

        // Pixel Data Item sequence (BOT + frame items + delim per PS3.5 §A.4)
        out.append(pixelDataItemSequence)

        return out
    }

    private func u16LEData(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private func appendShortVRElement(
        to data: inout Data,
        group: UInt16,
        element: UInt16,
        vr: String,
        value: Data
    ) {
        // Write tag (4B LE)
        data.append(UInt8(group & 0xFF))
        data.append(UInt8((group >> 8) & 0xFF))
        data.append(UInt8(element & 0xFF))
        data.append(UInt8((element >> 8) & 0xFF))
        // Write VR (2B ASCII)
        data.append(vr.data(using: .ascii)!)
        // Write length (2B LE)
        let len = UInt16(value.count)
        data.append(UInt8(len & 0xFF))
        data.append(UInt8((len >> 8) & 0xFF))
        // Write value
        data.append(value)
    }

    // MARK: - Tests

    /// End-to-end: synthesize a J2K-tagged DICOM file, parse it, verify
    /// metadata, then extract the codestream via the decapsulator.
    func testRoundTripHTJ2KLosslessSingleFrame() async throws {
        let image = makeTestImage()
        let cfg = J2KDICOMTransferSyntax.htj2kLossless.encodingConfiguration()
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let pixelDataSeq = J2KDICOMPixelDataEncapsulator
            .encapsulateFrames([codestream], includeBOT: false)

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.4.201",
            rows: image.height,
            columns: image.width,
            bitsAllocated: 16,
            bitsStored: 16,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            pixelDataItemSequence: pixelDataSeq)

        let parsed = try J2KDICOMFileParser.parse(dcm)

        guard case .j2kCompressed(let metadata, let pixelData) = parsed else {
            XCTFail("Expected .j2kCompressed for HTJ2K Lossless UID, got \(parsed)")
            return
        }

        XCTAssertEqual(metadata.transferSyntaxUID, "1.2.840.10008.1.2.4.201")
        XCTAssertEqual(metadata.rows, image.height)
        XCTAssertEqual(metadata.columns, image.width)
        XCTAssertEqual(metadata.bitsAllocated, 16)
        XCTAssertEqual(metadata.bitsStored, 16)
        XCTAssertEqual(metadata.samplesPerPixel, 1)
        XCTAssertEqual(metadata.photometricInterpretation, "MONOCHROME2")
        XCTAssertEqual(metadata.numberOfFrames, 1)

        // The pixelDataBytes should round-trip through the decapsulator
        // to recover the original codestream byte-identically.
        let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelData)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], codestream,
            "J2K codestream must survive round-trip via Pixel Data Item sequence + parser + decapsulator.")
    }

    /// Multi-frame round-trip: 3 frames, BOT populated, decoded back via
    /// the decapsulator should match the originals.
    func testRoundTripHTJ2KLosslessMultiFrameWithBOT() async throws {
        // Three different LCG seeds so the frames have distinct content.
        let image0 = makeTestImage(seed: 0x1111_2222_3333_4444)
        let image1 = makeTestImage(seed: 0x5555_6666_7777_8888)
        let image2 = makeTestImage(seed: 0x9999_AAAA_BBBB_CCCC)
        let cfg = J2KDICOMTransferSyntax.htj2kLossless.encodingConfiguration()
        let cs0 = try await J2KEncoder(encodingConfiguration: cfg).encode(image0)
        let cs1 = try await J2KEncoder(encodingConfiguration: cfg).encode(image1)
        let cs2 = try await J2KEncoder(encodingConfiguration: cfg).encode(image2)

        let pixelDataSeq = J2KDICOMPixelDataEncapsulator
            .encapsulateFrames([cs0, cs1, cs2], includeBOT: true)

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.4.201",
            rows: 16, columns: 16, bitsAllocated: 16, bitsStored: 16,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 3,
            pixelDataItemSequence: pixelDataSeq)

        let parsed = try J2KDICOMFileParser.parse(dcm)

        guard case .j2kCompressed(let metadata, let pixelData) = parsed else {
            XCTFail("Expected .j2kCompressed, got \(parsed)")
            return
        }

        XCTAssertEqual(metadata.numberOfFrames, 3)

        let recovered = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelData)
        XCTAssertEqual(recovered.count, 3)
        XCTAssertEqual(recovered[0], cs0)
        XCTAssertEqual(recovered[1], cs1)
        XCTAssertEqual(recovered[2], cs2)
    }

    /// J2KLossless (Part 1, UID .90) also produces .j2kCompressed result.
    func testRoundTripJ2KLossless() async throws {
        let image = makeTestImage()
        let cfg = J2KDICOMTransferSyntax.j2kLossless.encodingConfiguration()
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let pixelDataSeq = J2KDICOMPixelDataEncapsulator
            .encapsulateFrames([codestream], includeBOT: false)

        let dcm = buildSyntheticDICOMFile(
            transferSyntaxUID: "1.2.840.10008.1.2.4.90",
            rows: image.height, columns: image.width,
            bitsAllocated: 16, bitsStored: 16,
            samplesPerPixel: 1, photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 1,
            pixelDataItemSequence: pixelDataSeq)

        let parsed = try J2KDICOMFileParser.parse(dcm)

        guard case .j2kCompressed(let metadata, _) = parsed else {
            XCTFail("Expected .j2kCompressed for J2K Lossless UID, got \(parsed)")
            return
        }
        XCTAssertEqual(metadata.transferSyntaxUID, "1.2.840.10008.1.2.4.90")
    }

    /// Non-J2K UID synthesises an .uncompressed result.
    /// Use a hand-built fake with Explicit VR LE UID but an empty
    /// (fixed-length 0) Pixel Data element so the parser can extract
    /// metadata without expecting encapsulation.
    func testNonJ2KUIDClassifiesAsUncompressed() throws {
        // Build a minimal "uncompressed" DICOM with a zero-length Pixel Data.
        var dcm = Data()
        dcm.append(Data(repeating: 0, count: 128))
        dcm.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])

        // (0002,0010) Transfer Syntax UID = "1.2.840.10008.1.2.1" (Explicit VR LE)
        let uid = "1.2.840.10008.1.2.1"
        let uidPadded = uid.data(using: .ascii)! + Data([0x00])  // 19 bytes → 20 (even)
        dcm.append(contentsOf: [0x02, 0x00, 0x10, 0x00, 0x55, 0x49])
        let uidLen = UInt16(uidPadded.count)
        dcm.append(UInt8(uidLen & 0xFF)); dcm.append(UInt8((uidLen >> 8) & 0xFF))
        dcm.append(uidPadded)

        // Image-pixel-module tags (use the same helper-emitted format
        // as the J2K synthesis path)
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0002, vr: "US", value: u16LEData(1))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0004, vr: "CS", value: "MONOCHROME2".data(using: .ascii)!)
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0010, vr: "US", value: u16LEData(16))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0011, vr: "US", value: u16LEData(16))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0100, vr: "US", value: u16LEData(16))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0103, vr: "US", value: u16LEData(0))

        // (7FE0,0010) Pixel Data, VR=OB, length 0 (fixed-length, no encapsulation)
        dcm.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00, 0x4F, 0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        let parsed = try J2KDICOMFileParser.parse(dcm)

        guard case .uncompressed(let metadata) = parsed else {
            XCTFail("Expected .uncompressed for Explicit VR LE UID, got \(parsed)")
            return
        }
        XCTAssertEqual(metadata.transferSyntaxUID, "1.2.840.10008.1.2.1")
        XCTAssertEqual(metadata.rows, 16)
        XCTAssertEqual(metadata.columns, 16)
        XCTAssertFalse(parsed.isJ2KCompressed)
    }

    /// File without a Pixel Data tag throws .missingPixelDataTag.
    func testMissingPixelDataThrowsTypedError() throws {
        var dcm = Data()
        dcm.append(Data(repeating: 0, count: 128))
        dcm.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])

        // Valid group 0002 with Transfer Syntax UID
        let uid = "1.2.840.10008.1.2.1"
        let uidPadded = uid.data(using: .ascii)! + Data([0x00])
        dcm.append(contentsOf: [0x02, 0x00, 0x10, 0x00, 0x55, 0x49])
        let uidLen = UInt16(uidPadded.count)
        dcm.append(UInt8(uidLen & 0xFF)); dcm.append(UInt8((uidLen >> 8) & 0xFF))
        dcm.append(uidPadded)

        // Image-pixel-module tags ONLY — no (7FE0,0010) Pixel Data tag
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0010, vr: "US", value: u16LEData(16))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0011, vr: "US", value: u16LEData(16))
        appendShortVRElement(to: &dcm, group: 0x0028, element: 0x0100, vr: "US", value: u16LEData(16))

        XCTAssertThrowsError(try J2KDICOMFileParser.parse(dcm)) { error in
            XCTAssertEqual(error as? J2KDICOMFileError, .missingPixelDataTag)
        }
    }
}
