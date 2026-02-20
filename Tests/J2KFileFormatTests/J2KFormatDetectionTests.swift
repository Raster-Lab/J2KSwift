//
// J2KFormatDetectionTests.swift
// J2KSwift
//
import XCTest
@testable import J2KFileFormat
@testable import J2KCore

/// Tests for the file format detection functionality.
final class J2KFormatDetectionTests: XCTestCase {
    // MARK: - J2KFormat Tests

    func testFormatFileExtensions() throws {
        XCTAssertEqual(J2KFormat.jp2.fileExtension, "jp2")
        XCTAssertEqual(J2KFormat.j2k.fileExtension, "j2k")
        XCTAssertEqual(J2KFormat.jpx.fileExtension, "jpx")
        XCTAssertEqual(J2KFormat.jpm.fileExtension, "jpm")
        XCTAssertEqual(J2KFormat.jph.fileExtension, "jph")
    }

    func testFormatMimeTypes() throws {
        XCTAssertEqual(J2KFormat.jp2.mimeType, "image/jp2")
        XCTAssertEqual(J2KFormat.j2k.mimeType, "image/j2k")
        XCTAssertEqual(J2KFormat.jpx.mimeType, "image/jpx")
        XCTAssertEqual(J2KFormat.jpm.mimeType, "image/jpm")
        XCTAssertEqual(J2KFormat.jph.mimeType, "image/jph")
    }

    // MARK: - J2KFormatDetector Tests

    func testDetectJ2KCodestream() throws {
        // J2K codestream starts with SOC marker (0xFF4F)
        let data = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x10])
        let detector = J2KFormatDetector()

        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .j2k)
    }

    func testDetectJP2Format() throws {
        // JP2 file signature
        var data = Data()

        // Signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // signature content

        // File type box with JP2 brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // length = 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20]) // "jp2 " brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // minor version
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20]) // compatibility brand

        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .jp2)
    }

    func testDetectJPXFormat() throws {
        // JPX file signature
        var data = Data()

        // Signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // signature content

        // File type box with JPX brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // length = 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x78, 0x20]) // "jpx " brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // minor version
        data.append(contentsOf: [0x6A, 0x70, 0x78, 0x20]) // compatibility brand

        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .jpx)
    }

    func testDetectJPMFormat() throws {
        // JPM file signature
        var data = Data()

        // Signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // signature content

        // File type box with JPM brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // length = 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x6D, 0x20]) // "jpm " brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // minor version
        data.append(contentsOf: [0x6A, 0x70, 0x6D, 0x20]) // compatibility brand

        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .jpm)
    }

    func testDetectJPHFormat() throws {
        // JPH file signature (HTJ2K)
        var data = Data()

        // Signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // signature content

        // File type box with JPH brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // length = 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x68, 0x20]) // "jph " brand (HTJ2K)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // minor version
        data.append(contentsOf: [0x6A, 0x70, 0x68, 0x20]) // compatibility brand

        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .jph)
    }

    func testDetectJP2WithoutFtyp() throws {
        // JP2 signature without ftyp box should default to JP2
        var data = Data()

        // Signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // signature content

        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)
        XCTAssertEqual(format, .jp2)
    }

    func testIsValidJPEG2000WithJ2K() throws {
        let data = Data([0xFF, 0x4F, 0xFF, 0x51])
        let detector = J2KFormatDetector()

        XCTAssertTrue(detector.isValidJPEG2000(data))
    }

    func testIsValidJPEG2000WithJP2() throws {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A])

        let detector = J2KFormatDetector()
        XCTAssertTrue(detector.isValidJPEG2000(data))
    }

    func testIsValidJPEG2000WithInvalidData() throws {
        let detector = J2KFormatDetector()

        // Empty data
        XCTAssertFalse(detector.isValidJPEG2000(Data()))

        // Too small
        XCTAssertFalse(detector.isValidJPEG2000(Data([0xFF])))

        // Random data
        XCTAssertFalse(detector.isValidJPEG2000(Data([0x00, 0x00, 0x00, 0x00])))

        // Almost looks like JP2 but wrong signature
        var almostJP2 = Data()
        almostJP2.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        almostJP2.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        almostJP2.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Wrong content
        XCTAssertFalse(detector.isValidJPEG2000(almostJP2))
    }

    func testDetectDataTooSmall() throws {
        let detector = J2KFormatDetector()

        XCTAssertThrowsError(try detector.detect(data: Data())) { error in
            guard case J2KError.fileFormatError = error else {
                XCTFail("Expected fileFormatError")
                return
            }
        }

        XCTAssertThrowsError(try detector.detect(data: Data([0xFF]))) { error in
            guard case J2KError.fileFormatError = error else {
                XCTFail("Expected fileFormatError")
                return
            }
        }
    }

    func testDetectInvalidFormat() throws {
        let detector = J2KFormatDetector()

        // Random data that's not J2K or JP2
        let data = Data([0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

        XCTAssertThrowsError(try detector.detect(data: data)) { error in
            guard case J2KError.fileFormatError = error else {
                XCTFail("Expected fileFormatError")
                return
            }
        }
    }

    // MARK: - J2KFileReader Tests

    func testFileReaderDetectFormatJ2K() throws {
        let data = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x10])
        let reader = J2KFileReader()

        let format = try reader.detectFormat(data: data)
        XCTAssertEqual(format, .j2k)
    }

    func testFileReaderDetectFormatJP2() throws {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A])

        let reader = J2KFileReader()
        let format = try reader.detectFormat(data: data)
        XCTAssertEqual(format, .jp2)
    }

    // MARK: - Integration Tests

    func testReadJ2KCodestreamHeader() throws {
        // Create a minimal valid J2K codestream
        var data = Data()

        // SOC marker
        data.append(contentsOf: [0xFF, 0x4F])

        // SIZ marker segment
        data.append(contentsOf: [0xFF, 0x51]) // marker
        data.append(contentsOf: [0x00, 0x29]) // length = 41 (2 + 36 + 3 for 1 component)
        data.append(contentsOf: [0x00, 0x00]) // Rsiz = 0 (no profile)
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // Xsiz = 512
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // Ysiz = 512
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XOsiz = 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YOsiz = 0
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // XTsiz = 512
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // YTsiz = 512
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XTOsiz = 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YTOsiz = 0
        data.append(contentsOf: [0x00, 0x01]) // Csiz = 1 component
        data.append(contentsOf: [0x07]) // Ssiz = 8 bits unsigned
        data.append(contentsOf: [0x01]) // XRsiz = 1
        data.append(contentsOf: [0x01]) // YRsiz = 1

        // Validate the structure
        let parser = J2KMarkerParser(data: data)
        XCTAssertTrue(parser.validateBasicStructure())

        let segments = try parser.parseMainHeader()
        XCTAssertGreaterThanOrEqual(segments.count, 2) // At least SOC and SIZ

        // Check SIZ segment was parsed correctly
        let sizSegment = segments.first { $0.marker == .siz }
        XCTAssertNotNil(sizSegment)
        XCTAssertEqual(sizSegment?.data.count, 39) // SIZ segment data length for 1 component
    }

    func testReadMultiComponentImage() throws {
        // Create a J2K codestream with 3 components (RGB)
        var data = Data()

        // SOC marker
        data.append(contentsOf: [0xFF, 0x4F])

        // SIZ marker segment for 3 components
        data.append(contentsOf: [0xFF, 0x51]) // marker
        data.append(contentsOf: [0x00, 0x2F]) // length = 47 (2 + 36 + 9 for 3 components)
        data.append(contentsOf: [0x00, 0x00]) // Rsiz
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Xsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Ysiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XOsiz
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YOsiz
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // XTsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // YTsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XTOsiz
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YTOsiz
        data.append(contentsOf: [0x00, 0x03]) // Csiz = 3 components
        // Component 0 (R)
        data.append(contentsOf: [0x07]) // Ssiz = 8 bits
        data.append(contentsOf: [0x01]) // XRsiz
        data.append(contentsOf: [0x01]) // YRsiz
        // Component 1 (G)
        data.append(contentsOf: [0x07]) // Ssiz = 8 bits
        data.append(contentsOf: [0x01]) // XRsiz
        data.append(contentsOf: [0x01]) // YRsiz
        // Component 2 (B)
        data.append(contentsOf: [0x07]) // Ssiz = 8 bits
        data.append(contentsOf: [0x01]) // XRsiz
        data.append(contentsOf: [0x01]) // YRsiz

        let parser = J2KMarkerParser(data: data)
        XCTAssertTrue(parser.validateBasicStructure())

        let segments = try parser.parseMainHeader()
        let sizSegment = segments.first { $0.marker == .siz }
        XCTAssertNotNil(sizSegment)
        XCTAssertEqual(sizSegment?.data.count, 45) // SIZ segment data for 3 components
    }
}
