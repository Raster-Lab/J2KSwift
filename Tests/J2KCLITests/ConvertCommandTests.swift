// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// ConvertCommandTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLICore

/// Tests for the convert command: format conversion with bit depth conversion.
final class ConvertCommandTests: XCTestCase {

    // MARK: - Argument parsing

    func testConvertArgumentParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.pgm"])
        XCTAssertEqual(opts["i"], "image.j2k")
        XCTAssertEqual(opts["o"], "image.pgm")
    }

    func testConvertWithBitDepth() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.pgm", "--bit-depth", "16"])
        XCTAssertEqual(opts["bit-depth"], "16")
    }

    func testConvertWithStripAlpha() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.ppm", "--strip-alpha"])
        XCTAssertEqual(opts["strip-alpha"], "true")
    }

    // MARK: - Format detection

    func testFormatDetectionFromExtension() {
        let extensions = ["j2k", "jp2", "jph", "j2c", "jpx"]
        for ext in extensions {
            XCTAssertTrue(isJPEG2000Extension(ext), "\(ext) should be a JPEG 2000 extension")
        }
    }

    func testNonJ2KFormatDetection() {
        let extensions = ["pgm", "ppm", "pnm", "raw", "png", "jpg"]
        for ext in extensions {
            XCTAssertFalse(isJPEG2000Extension(ext), "\(ext) should not be a JPEG 2000 extension")
        }
    }

    func testImageFormatDetection() {
        let extensions = ["pgm", "ppm", "pnm", "raw"]
        for ext in extensions {
            XCTAssertTrue(isImageExtension(ext), "\(ext) should be an image extension")
        }
    }

    // MARK: - Bit depth conversion logic

    func testBitDepthConversion8to16() {
        let input: [UInt8] = [0, 128, 255]
        let output = input.map { UInt16($0) << 8 }
        XCTAssertEqual(output, [0, 32768, 65280])
    }

    func testBitDepthConversion16to8() {
        let input: [UInt16] = [0, 32768, 65535]
        let output = input.map { UInt8($0 >> 8) }
        XCTAssertEqual(output, [0, 128, 255])
    }

    func testDICOMTransferSyntaxInfoAllowsJPEGProcess14Fallback() {
        let info = J2KCLI.dicomTransferSyntaxInfo(for: "1.2.840.10008.1.2.4.70")

        XCTAssertEqual(info.byteOrderSyntax, .explicitVRLittleEndian)
        XCTAssertTrue(info.isCompressed)
        XCTAssertFalse(info.isJPEG2000)
    }

    func testDICOMTransferSyntaxInfoFlagsJPEG2000Inputs() {
        let info = J2KCLI.dicomTransferSyntaxInfo(for: "1.2.840.10008.1.2.4.90")

        XCTAssertEqual(info.byteOrderSyntax, .explicitVRLittleEndian)
        XCTAssertTrue(info.isCompressed)
        XCTAssertTrue(info.isJPEG2000)
    }

    func testTIFFRoundTripSupports12BitGrayscale() throws {
        let samples: [UInt16] = [0, 1024, 2048, 4095]
        var pixelBytes = Data()
        for sample in samples {
            var bigEndian = sample.bigEndian
            withUnsafeBytes(of: &bigEndian) { pixelBytes.append(contentsOf: $0) }
        }

        let image = J2KImage(
            width: 2,
            height: 2,
            components: [
                J2KComponent(
                    index: 0,
                    bitDepth: 12,
                    signed: false,
                    width: 2,
                    height: 2,
                    data: pixelBytes
                )
            ]
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tiff")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(try J2KCLI.saveTIFF(image, to: url))
        let written = try Data(contentsOf: url)
        let reloaded = try J2KCLI.loadTIFF(written)

        XCTAssertEqual(reloaded.width, 2)
        XCTAssertEqual(reloaded.height, 2)
        XCTAssertEqual(reloaded.componentCount, 1)
        XCTAssertEqual(reloaded.components[0].data, pixelBytes)
    }

    func testLoadTIFFAcceptsTwelveBitMetadataFromOpenJPEG() throws {
        let samples: [UInt16] = [0, 256, 1024, 4095]
        var pixelBytes = Data()
        for sample in samples {
            var bigEndian = sample.bigEndian
            withUnsafeBytes(of: &bigEndian) { pixelBytes.append(contentsOf: $0) }
        }

        let image = J2KImage(
            width: 2,
            height: 2,
            components: [
                J2KComponent(
                    index: 0,
                    bitDepth: 12,
                    signed: false,
                    width: 2,
                    height: 2,
                    data: pixelBytes
                )
            ]
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tiff")
        defer { try? FileManager.default.removeItem(at: url) }

        try J2KCLI.saveTIFF(image, to: url)
        var written = try Data(contentsOf: url)
        try patchSingleComponentTIFFBitsPerSample(&written, to: 12)

        let reloaded = try J2KCLI.loadTIFF(written)
        XCTAssertEqual(reloaded.width, 2)
        XCTAssertEqual(reloaded.height, 2)
        XCTAssertEqual(reloaded.componentCount, 1)
        XCTAssertEqual(reloaded.components[0].bitDepth, 12)
        XCTAssertEqual(reloaded.components[0].data, pixelBytes)
    }

    func testLoadTIFFAcceptsPackedTwelveBitBigEndianData() throws {
        let samples: [UInt16] = [0x000, 0x123, 0xABC, 0xFFF]
        let tiffData = makePackedTwelveBitBigEndianTIFF(samples: samples, width: 2, height: 2)

        let reloaded = try J2KCLI.loadTIFF(tiffData)

        XCTAssertEqual(reloaded.width, 2)
        XCTAssertEqual(reloaded.height, 2)
        XCTAssertEqual(reloaded.componentCount, 1)
        XCTAssertEqual(reloaded.components[0].bitDepth, 12)

        var expected = Data()
        for sample in samples {
            var bigEndian = sample.bigEndian
            withUnsafeBytes(of: &bigEndian) { expected.append(contentsOf: $0) }
        }
        XCTAssertEqual(reloaded.components[0].data, expected)
    }

    func testLoadTIFFAcceptsOddWidthPackedTwelveBitStrips() throws {
        let samples: [UInt16] = [0x001, 0x123, 0x456, 0x789, 0xABC, 0xDEF]
        let tiffData = makePackedTwelveBitBigEndianTIFF(samples: samples, width: 3, height: 2, rowsPerStrip: 1)

        let reloaded = try J2KCLI.loadTIFF(tiffData)

        XCTAssertEqual(reloaded.width, 3)
        XCTAssertEqual(reloaded.height, 2)
        XCTAssertEqual(reloaded.componentCount, 1)
        XCTAssertEqual(reloaded.components[0].bitDepth, 12)

        var expected = Data()
        for sample in samples {
            var bigEndian = sample.bigEndian
            withUnsafeBytes(of: &bigEndian) { expected.append(contentsOf: $0) }
        }
        XCTAssertEqual(reloaded.components[0].data, expected)
    }

    func testLoadDICOMComposesMultiFrameStudyIntoMosaic() throws {
        let dicomData = makeTestDICOM(
            rows: 1,
            columns: 2,
            bitsAllocated: 8,
            bitsStored: 8,
            samplesPerPixel: 1,
            photometricInterpretation: "MONOCHROME2",
            numberOfFrames: 2,
            pixelData: Data([1, 2, 3, 4])
        )

        let image = try J2KCLI.loadDICOM(dicomData)

        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.componentCount, 1)
        XCTAssertEqual(Array(image.components[0].data), [1, 2, 3, 4])
    }

    // MARK: - Helpers

    private func makeTestDICOM(
        rows: UInt16,
        columns: UInt16,
        bitsAllocated: UInt16,
        bitsStored: UInt16,
        samplesPerPixel: UInt16,
        photometricInterpretation: String,
        numberOfFrames: Int,
        pixelData: Data
    ) -> Data {
        var data = Data(repeating: 0, count: 128)
        data.append("DICM".data(using: .ascii)!)

        appendElement(&data, group: 0x0002, element: 0x0010, vr: "UI", value: paddedASCII("1.2.840.10008.1.2.1"))
        appendElement(&data, group: 0x0028, element: 0x0002, vr: "US", value: le16(samplesPerPixel))
        appendElement(&data, group: 0x0028, element: 0x0004, vr: "CS", value: paddedASCII(photometricInterpretation))
        appendElement(&data, group: 0x0028, element: 0x0008, vr: "IS", value: paddedASCII(String(numberOfFrames)))
        appendElement(&data, group: 0x0028, element: 0x0010, vr: "US", value: le16(rows))
        appendElement(&data, group: 0x0028, element: 0x0011, vr: "US", value: le16(columns))
        appendElement(&data, group: 0x0028, element: 0x0100, vr: "US", value: le16(bitsAllocated))
        appendElement(&data, group: 0x0028, element: 0x0101, vr: "US", value: le16(bitsStored))
        appendElement(&data, group: 0x0028, element: 0x0102, vr: "US", value: le16(bitsStored &- 1))
        appendElement(&data, group: 0x0028, element: 0x0103, vr: "US", value: le16(0))
        appendElement(&data, group: 0x7FE0, element: 0x0010, vr: "OB", value: pixelData)

        return data
    }

    private func appendElement(_ data: inout Data, group: UInt16, element: UInt16, vr: String, value: Data) {
        data.append(le16(group))
        data.append(le16(element))
        data.append(vr.data(using: .ascii)!)

        let longValueVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        if longValueVRs.contains(vr) {
            data.append(contentsOf: [0, 0])
            data.append(le32(UInt32(value.count)))
        } else {
            data.append(le16(UInt16(value.count)))
        }

        data.append(value)
        if value.count % 2 != 0 {
            data.append(0)
        }
    }

    private func paddedASCII(_ string: String) -> Data {
        var data = Data(string.utf8)
        if data.count % 2 != 0 {
            data.append(0)
        }
        return data
    }

    private func patchSingleComponentTIFFBitsPerSample(_ data: inout Data, to bitsPerSample: UInt16) throws {
        guard data.count >= 8 else {
            throw NSError(domain: "ConvertCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "TIFF too small"])
        }

        let ifdOffset = Int(UInt32(data[4]) | (UInt32(data[5]) << 8) | (UInt32(data[6]) << 16) | (UInt32(data[7]) << 24))
        guard ifdOffset + 2 <= data.count else {
            throw NSError(domain: "ConvertCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "IFD offset out of range"])
        }

        let entryCount = Int(UInt16(data[ifdOffset]) | (UInt16(data[ifdOffset + 1]) << 8))
        for index in 0..<entryCount {
            let entryOffset = ifdOffset + 2 + index * 12
            guard entryOffset + 12 <= data.count else { break }

            let tag = UInt16(data[entryOffset]) | (UInt16(data[entryOffset + 1]) << 8)
            if tag == 258 {
                data[entryOffset + 8] = UInt8(bitsPerSample & 0x00FF)
                data[entryOffset + 9] = UInt8((bitsPerSample >> 8) & 0x00FF)
                data[entryOffset + 10] = 0
                data[entryOffset + 11] = 0
                return
            }
        }

        throw NSError(domain: "ConvertCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "BitsPerSample tag not found"])
    }

    private func makePackedTwelveBitBigEndianTIFF(samples: [UInt16], width: Int, height: Int, rowsPerStrip: Int? = nil) -> Data {
        precondition(samples.count == width * height)

        let stripRows = rowsPerStrip ?? height
        var pixelData = Data()
        var stripOffsets: [UInt32] = []
        var stripByteCounts: [UInt32] = []

        for rowStart in stride(from: 0, to: height, by: stripRows) {
            let actualRows = min(stripRows, height - rowStart)
            let startIndex = rowStart * width
            let endIndex = startIndex + actualRows * width
            let stripSamples = Array(samples[startIndex..<endIndex])

            stripOffsets.append(UInt32(8 + pixelData.count))
            let beforeCount = pixelData.count
            for chunkStart in stride(from: 0, to: stripSamples.count, by: 2) {
                let first = stripSamples[chunkStart] & 0x0FFF
                pixelData.append(UInt8((first >> 4) & 0xFF))

                if chunkStart + 1 < stripSamples.count {
                    let second = stripSamples[chunkStart + 1] & 0x0FFF
                    pixelData.append(UInt8(((first & 0x0F) << 4) | ((second >> 8) & 0x0F)))
                    pixelData.append(UInt8(second & 0xFF))
                } else {
                    pixelData.append(UInt8((first & 0x0F) << 4))
                }
            }
            stripByteCounts.append(UInt32(pixelData.count - beforeCount))
        }

        var tiff = Data()
        tiff.append(contentsOf: [0x4D, 0x4D])
        tiff.append(be16(42))
        let ifdOffset = UInt32(8 + pixelData.count)
        tiff.append(be32(ifdOffset))
        tiff.append(pixelData)

        let hasMultipleStrips = stripOffsets.count > 1
        let stripOffsetsArrayOffset = ifdOffset + UInt32(2 + 9 * 12 + 4)
        let stripByteCountsArrayOffset = stripOffsetsArrayOffset + UInt32(stripOffsets.count * 4)

        let entries: [(UInt16, UInt16, UInt32, UInt32)] = [
            (256, 4, 1, UInt32(width)),
            (257, 4, 1, UInt32(height)),
            (258, 3, 1, 12),
            (259, 3, 1, 1),
            (262, 3, 1, 1),
            (273, 4, UInt32(stripOffsets.count), hasMultipleStrips ? stripOffsetsArrayOffset : stripOffsets[0]),
            (277, 3, 1, 1),
            (278, 4, 1, UInt32(stripRows)),
            (279, 4, UInt32(stripByteCounts.count), hasMultipleStrips ? stripByteCountsArrayOffset : stripByteCounts[0])
        ]

        tiff.append(be16(UInt16(entries.count)))
        for (tag, type, count, value) in entries {
            tiff.append(be16(tag))
            tiff.append(be16(type))
            tiff.append(be32(count))
            let storedValue = (type == 3 && count == 1) ? (value << 16) : value
            tiff.append(be32(storedValue))
        }
        tiff.append(be32(0))

        if hasMultipleStrips {
            for offset in stripOffsets {
                tiff.append(be32(offset))
            }
            for byteCount in stripByteCounts {
                tiff.append(be32(byteCount))
            }
        }

        return tiff
    }

    private func be16(_ value: UInt16) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private func be32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private func le16(_ value: UInt16) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    private func le32(_ value: UInt32) -> Data {
        var littleEndian = value.littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }

    private func isJPEG2000Extension(_ ext: String) -> Bool {
        ["j2k", "jp2", "jph", "j2c", "jpx", "jpm"].contains(ext.lowercased())
    }

    private func isImageExtension(_ ext: String) -> Bool {
        ["pgm", "ppm", "pnm", "raw", "bmp", "tiff"].contains(ext.lowercased())
    }
}

#endif // os(macOS)
