//
// MJ2FileFormatTests.swift
// J2KSwift
//
/// # MJ2FileFormatTests
///
/// Unit tests for Motion JPEG 2000 file format support.
///
/// These tests verify the correct parsing and writing of MJ2 boxes
/// and file structures according to ISO/IEC 15444-3 and ISO/IEC 14496-12.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore

final class MJ2FileFormatTests: XCTestCase {
    // MARK: - Movie Header Box Tests

    func testMovieHeaderBoxWrite() throws {
        let mvhd = MJ2MovieHeaderBox(
            creationTime: 0,
            modificationTime: 0,
            timescale: 600,
            duration: 6000,
            nextTrackID: 2
        )

        let data = try mvhd.write()

        // Verify minimum size
        XCTAssertGreaterThanOrEqual(data.count, 100)

        // Verify version and flags
        XCTAssertEqual(data[0], 0) // Version 0

        // Verify timescale (at offset 12 for version 0)
        let timescale = data.readUInt32(at: 12)
        XCTAssertEqual(timescale, 600)

        // Verify duration (at offset 16 for version 0)
        let duration = data.readUInt32(at: 16)
        XCTAssertEqual(duration, 6000)
    }

    func testMovieHeaderBoxRoundTrip() throws {
        let original = MJ2MovieHeaderBox(
            creationTime: 1234567890,
            modificationTime: 1234567891,
            timescale: 600,
            duration: 6000,
            nextTrackID: 2
        )

        let data = try original.write()

        var parsed = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try parsed.read(from: data)

        XCTAssertEqual(parsed.timescale, original.timescale)
        XCTAssertEqual(parsed.duration, original.duration)
        XCTAssertEqual(parsed.nextTrackID, original.nextTrackID)
        XCTAssertEqual(parsed.rate, original.rate)
        XCTAssertEqual(parsed.volume, original.volume)
    }

    func testMovieHeaderBox64BitTime() throws {
        // Test with 64-bit timestamps
        let largeTime: UInt64 = 0x100000000 // Exceeds 32-bit range
        let mvhd = MJ2MovieHeaderBox(
            creationTime: largeTime,
            modificationTime: largeTime + 1,
            timescale: 600,
            duration: 6000,
            nextTrackID: 1
        )

        XCTAssertEqual(mvhd.version, 1) // Should use version 1

        let data = try mvhd.write()

        var parsed = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try parsed.read(from: data)

        XCTAssertEqual(parsed.version, 1)
        XCTAssertEqual(parsed.creationTime, largeTime)
        XCTAssertEqual(parsed.modificationTime, largeTime + 1)
    }

    // MARK: - Track Header Box Tests

    func testTrackHeaderBoxWrite() throws {
        let tkhd = MJ2TrackHeaderBox(
            trackID: 1,
            creationTime: 0,
            modificationTime: 0,
            duration: 6000,
            width: 1920,
            height: 1080
        )

        let data = try tkhd.write()

        // Verify minimum size
        XCTAssertGreaterThanOrEqual(data.count, 84)

        // Verify version
        XCTAssertEqual(data[0], 0) // Version 0

        // Verify flags (enabled, in movie, in preview)
        let flags = UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        XCTAssertEqual(flags, 0x000007)
    }

    func testTrackHeaderBoxRoundTrip() throws {
        let original = MJ2TrackHeaderBox(
            trackID: 1,
            creationTime: 1234567890,
            modificationTime: 1234567891,
            duration: 6000,
            width: 1920,
            height: 1080
        )

        let data = try original.write()

        var parsed = MJ2TrackHeaderBox(
            trackID: 1,
            duration: 0,
            width: 0,
            height: 0
        )
        try parsed.read(from: data)

        XCTAssertEqual(parsed.trackID, original.trackID)
        XCTAssertEqual(parsed.duration, original.duration)
        XCTAssertEqual(parsed.width, original.width)
        XCTAssertEqual(parsed.height, original.height)
        XCTAssertEqual(parsed.layer, original.layer)
        XCTAssertEqual(parsed.volume, original.volume)
    }

    func testTrackHeaderBoxDimensions() throws {
        let tkhd = MJ2TrackHeaderBox(
            trackID: 1,
            duration: 3000,
            width: 3840,
            height: 2160
        )

        let data = try tkhd.write()

        var parsed = MJ2TrackHeaderBox(
            trackID: 1,
            duration: 0,
            width: 0,
            height: 0
        )
        try parsed.read(from: data)

        // Convert from 16.16 fixed-point
        let width = parsed.width >> 16
        let height = parsed.height >> 16

        XCTAssertEqual(width, 3840)
        XCTAssertEqual(height, 2160)
    }

    // MARK: - Media Header Box Tests

    func testMediaHeaderBoxWrite() throws {
        let mdhd = MJ2MediaHeaderBox(
            creationTime: 0,
            modificationTime: 0,
            timescale: 600,
            duration: 6000,
            language: "eng"
        )

        let data = try mdhd.write()

        // Verify minimum size
        XCTAssertGreaterThanOrEqual(data.count, 24)

        // Verify version
        XCTAssertEqual(data[0], 0) // Version 0
    }

    func testMediaHeaderBoxRoundTrip() throws {
        let original = MJ2MediaHeaderBox(
            creationTime: 1234567890,
            modificationTime: 1234567891,
            timescale: 600,
            duration: 6000,
            language: "eng"
        )

        let data = try original.write()

        var parsed = MJ2MediaHeaderBox(timescale: 1, duration: 0)
        try parsed.read(from: data)

        XCTAssertEqual(parsed.timescale, original.timescale)
        XCTAssertEqual(parsed.duration, original.duration)
        XCTAssertEqual(parsed.language, original.language)
    }

    func testMediaHeaderBoxLanguage() throws {
        let languages = ["eng", "fra", "deu", "spa", "ita", "jpn", "und"]

        for lang in languages {
            let mdhd = MJ2MediaHeaderBox(
                timescale: 600,
                duration: 6000,
                language: lang
            )

            let data = try mdhd.write()

            var parsed = MJ2MediaHeaderBox(timescale: 1, duration: 0)
            try parsed.read(from: data)

            XCTAssertEqual(parsed.language, mdhd.language)
        }
    }

    // MARK: - Sample Entry Tests

    func testSampleEntryWrite() throws {
        let sampleEntry = MJ2SampleEntry(
            width: 1920,
            height: 1080,
            depth: 24,
            jp2hData: nil
        )

        let data = try sampleEntry.write()

        // Verify minimum size (86 bytes)
        XCTAssertGreaterThanOrEqual(data.count, 86)

        // Verify format
        let format = String(data: data.subdata(in: 4..<8), encoding: .ascii)
        XCTAssertEqual(format, "mjp2")
    }

    func testSampleEntryRoundTrip() throws {
        let original = MJ2SampleEntry(
            width: 1920,
            height: 1080,
            depth: 24,
            jp2hData: nil
        )

        let data = try original.write()

        var parsed = MJ2SampleEntry(width: 0, height: 0)
        try parsed.read(from: data)

        XCTAssertEqual(parsed.format, original.format)
        XCTAssertEqual(parsed.width, original.width)
        XCTAssertEqual(parsed.height, original.height)
        XCTAssertEqual(parsed.depth, original.depth)
        XCTAssertEqual(parsed.frameCount, original.frameCount)
    }

    func testSampleEntryWithJP2Header() throws {
        // Create mock JP2 header data
        let jp2hData = Data([0x00, 0x00, 0x00, 0x10] + // Box length
                            [0x69, 0x68, 0x64, 0x72] + // 'ihdr'
                            Array(repeating: 0, count: 8))

        let sampleEntry = MJ2SampleEntry(
            width: 1920,
            height: 1080,
            depth: 24,
            jp2hData: jp2hData
        )

        let data = try sampleEntry.write()

        var parsed = MJ2SampleEntry(width: 0, height: 0)
        try parsed.read(from: data)

        XCTAssertNotNil(parsed.jp2hData)
        XCTAssertEqual(parsed.jp2hData, jp2hData)
    }

    // MARK: - Sample Description Box Tests

    func testSampleDescriptionBoxWrite() throws {
        let sampleEntry = MJ2SampleEntry(
            width: 1920,
            height: 1080,
            depth: 24
        )

        let stsd = MJ2SampleDescriptionBox(sampleEntry: sampleEntry)

        let data = try stsd.write()

        // Verify minimum size
        XCTAssertGreaterThanOrEqual(data.count, 8)

        // Verify version
        XCTAssertEqual(data[0], 0)

        // Verify entry count
        let entryCount = data.readUInt32(at: 4)
        XCTAssertEqual(entryCount, 1)
    }

    func testSampleDescriptionBoxRoundTrip() throws {
        let originalEntry = MJ2SampleEntry(
            width: 1920,
            height: 1080,
            depth: 24
        )

        let original = MJ2SampleDescriptionBox(sampleEntry: originalEntry)

        let data = try original.write()

        var parsed = MJ2SampleDescriptionBox(
            sampleEntry: MJ2SampleEntry(width: 0, height: 0)
        )
        try parsed.read(from: data)

        XCTAssertEqual(parsed.sampleEntry.width, originalEntry.width)
        XCTAssertEqual(parsed.sampleEntry.height, originalEntry.height)
        XCTAssertEqual(parsed.sampleEntry.depth, originalEntry.depth)
    }

    // MARK: - Format Detection Tests

    func testMJ2FormatDetection() throws {
        // Create minimal MJ2 file signature
        var data = Data()

        // JP2 signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // Length: 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // Type: 'jP  '
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // Signature

        // File type box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // Length: 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // Type: 'ftyp'
        data.append(contentsOf: [0x6D, 0x6A, 0x70, 0x32]) // Brand: 'mjp2'
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Minor version
        data.append(contentsOf: [0x6D, 0x6A, 0x70, 0x32]) // Compatible brand

        let detector = MJ2FormatDetector()
        XCTAssertTrue(try detector.isMJ2File(data: data))

        let format = try detector.detectFormat(data: data)
        XCTAssertEqual(format, .mj2)
    }

    func testMJ2SimpleProfileDetection() throws {
        // Create minimal MJ2 Simple Profile file signature
        var data = Data()

        // JP2 signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A])

        // File type box with 'mj2s' brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14])
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70])
        data.append(contentsOf: [0x6D, 0x6A, 0x32, 0x73]) // Brand: 'mj2s'
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x6D, 0x6A, 0x32, 0x73])

        let detector = MJ2FormatDetector()
        XCTAssertTrue(try detector.isMJ2File(data: data))

        let format = try detector.detectFormat(data: data)
        XCTAssertEqual(format, .mj2s)
    }

    func testNonMJ2FileRejection() throws {
        // Create a JP2 (not MJ2) file signature
        var data = Data()

        // JP2 signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A])

        // File type box with 'jp2 ' brand
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14])
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70])
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20]) // Brand: 'jp2 '
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20])

        let detector = MJ2FormatDetector()
        XCTAssertFalse(try detector.isMJ2File(data: data))
    }

    func testInvalidSignatureRejection() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])

        let detector = MJ2FormatDetector()
        XCTAssertFalse(try detector.isMJ2File(data: data))
    }

    // MARK: - Box Type Tests

    func testBoxTypeConstants() {
        XCTAssertEqual(J2KBoxType.moov.stringValue, "moov")
        XCTAssertEqual(J2KBoxType.mvhd.stringValue, "mvhd")
        XCTAssertEqual(J2KBoxType.trak.stringValue, "trak")
        XCTAssertEqual(J2KBoxType.tkhd.stringValue, "tkhd")
        XCTAssertEqual(J2KBoxType.mdia.stringValue, "mdia")
        XCTAssertEqual(J2KBoxType.mdhd.stringValue, "mdhd")
        XCTAssertEqual(J2KBoxType.stsd.stringValue, "stsd")
        XCTAssertEqual(J2KBoxType.mjp2.stringValue, "mjp2")
        XCTAssertEqual(J2KBoxType.mdat.stringValue, "mdat")
    }

    // MARK: - Integer Extension Tests

    func testBigEndianBytes() {
        let u16: UInt16 = 0x1234
        XCTAssertEqual(u16.bigEndianBytes, [0x12, 0x34])

        let u32: UInt32 = 0x12345678
        XCTAssertEqual(u32.bigEndianBytes, [0x12, 0x34, 0x56, 0x78])

        let u64: UInt64 = 0x123456789ABCDEF0
        XCTAssertEqual(u64.bigEndianBytes, [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])

        let i16: Int16 = 0x1234
        XCTAssertEqual(i16.bigEndianBytes, [0x12, 0x34])

        let i32: Int32 = 0x12345678
        XCTAssertEqual(i32.bigEndianBytes, [0x12, 0x34, 0x56, 0x78])
    }

    // MARK: - Data Extension Tests

    func testDataReading() {
        let data = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])

        XCTAssertEqual(data.readUInt16(at: 0), 0x1234)
        XCTAssertEqual(data.readUInt16(at: 2), 0x5678)

        XCTAssertEqual(data.readUInt32(at: 0), 0x12345678)
        XCTAssertEqual(data.readUInt32(at: 4), 0x9ABCDEF0)

        XCTAssertEqual(data.readUInt64(at: 0), 0x123456789ABCDEF0)
    }

    // MARK: - File Info Tests

    func testFileInfoDurationCalculation() {
        let fileInfo = MJ2FileInfo(
            format: .mj2,
            creationTime: 0,
            modificationTime: 0,
            timescale: 600,
            duration: 6000,
            tracks: []
        )

        XCTAssertEqual(fileInfo.durationSeconds, 10.0)
    }

    func testTrackInfoFrameRateCalculation() {
        let trackInfo = MJ2TrackInfo(
            trackID: 1,
            creationTime: 0,
            modificationTime: 0,
            duration: 6000,
            width: 1920,
            height: 1080,
            mediaTimescale: 600,
            mediaDuration: 6000,
            sampleCount: 300,
            language: "und",
            isVideo: true
        )

        XCTAssertEqual(trackInfo.frameRate, 30.0, accuracy: 0.001)
    }

    func testVideoTracksFilter() {
        let videoTrack = MJ2TrackInfo(
            trackID: 1,
            creationTime: 0,
            modificationTime: 0,
            duration: 6000,
            width: 1920,
            height: 1080,
            mediaTimescale: 600,
            mediaDuration: 6000,
            sampleCount: 300,
            language: "und",
            isVideo: true
        )

        let audioTrack = MJ2TrackInfo(
            trackID: 2,
            creationTime: 0,
            modificationTime: 0,
            duration: 6000,
            width: 0,
            height: 0,
            mediaTimescale: 48000,
            mediaDuration: 480000,
            sampleCount: 1000,
            language: "und",
            isVideo: false
        )

        let fileInfo = MJ2FileInfo(
            format: .mj2,
            creationTime: 0,
            modificationTime: 0,
            timescale: 600,
            duration: 6000,
            tracks: [videoTrack, audioTrack]
        )

        XCTAssertEqual(fileInfo.videoTracks.count, 1)
        XCTAssertEqual(fileInfo.videoTracks.first?.trackID, 1)
    }

    // MARK: - Format Properties Tests

    func testFormatProperties() {
        XCTAssertEqual(MJ2Format.mj2.brandIdentifier, "mjp2")
        XCTAssertEqual(MJ2Format.mj2s.brandIdentifier, "mj2s")

        XCTAssertEqual(MJ2Format.mj2.fileExtension, "mj2")
        XCTAssertEqual(MJ2Format.mj2s.fileExtension, "mj2")

        XCTAssertEqual(MJ2Format.mj2.mimeType, "video/mj2")
        XCTAssertEqual(MJ2Format.mj2s.mimeType, "video/mj2")
    }
}
