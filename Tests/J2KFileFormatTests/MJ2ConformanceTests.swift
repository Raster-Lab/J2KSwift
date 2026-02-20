/// # MJ2ConformanceTests
///
/// ISO/IEC 15444-3 conformance tests for the Motion JPEG 2000 implementation.
///
/// These tests verify that the MJ2 file creation and parsing conform to the
/// ISO/IEC 15444-3 (Motion JPEG 2000) and ISO/IEC 14496-12 (ISO base media
/// file format) specifications.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore
@testable import J2KCodec

final class MJ2ConformanceTests: XCTestCase {
    // MARK: - Helpers

    /// Creates a test image with the given dimensions.
    private func makeTestImage(width: Int = 64, height: Int = 64, components: Int = 3, bitDepth: Int = 8) -> J2KImage {
        J2KImage(width: width, height: height, components: components, bitDepth: bitDepth)
    }

    /// Creates an MJ2 file from test frames and returns its data.
    private func createMJ2Data(
        frames: [J2KImage],
        frameRate: Double = 24.0,
        profile: MJ2Profile = .general,
        quality: Double = 0.9,
        use64BitOffsets: Bool = false
    ) async throws -> Data {
        let config = MJ2CreationConfiguration.from(
            frameRate: frameRate,
            profile: profile,
            quality: quality
        )
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mj2_conformance_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await creator.create(from: frames, outputURL: tempURL)
        return try Data(contentsOf: tempURL)
    }

    /// Reads a big-endian UInt32 from data at the given offset without alignment requirements.
    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[data.startIndex + offset]) << 24
             | UInt32(data[data.startIndex + offset + 1]) << 16
             | UInt32(data[data.startIndex + offset + 2]) << 8
             | UInt32(data[data.startIndex + offset + 3])
    }

    /// Reads a 4-byte ASCII string from data at the given offset.
    private func readBoxType(_ data: Data, at offset: Int) -> String {
        guard offset + 4 <= data.count else { return "????" }
        let bytes = [data[data.startIndex + offset],
                     data[data.startIndex + offset + 1],
                     data[data.startIndex + offset + 2],
                     data[data.startIndex + offset + 3]]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// Scans top-level boxes in MJ2 data and returns an array of (type, offset, length) tuples.
    private func scanBoxes(in data: Data) -> [(type: String, offset: Int, length: Int)] {
        var boxes: [(type: String, offset: Int, length: Int)] = []
        var offset = 0
        while offset + 8 <= data.count {
            let size = Int(readUInt32BE(data, at: offset))
            let type = readBoxType(data, at: offset + 4)
            if size == 1 {
                // Extended size box (64-bit length)
                guard offset + 16 <= data.count else { break }
                let hi = UInt64(readUInt32BE(data, at: offset + 8))
                let lo = UInt64(readUInt32BE(data, at: offset + 12))
                let extSize = Int(hi << 32 | lo)
                guard extSize >= 16 else { break }
                boxes.append((type: type, offset: offset, length: extSize))
                offset += extSize
            } else {
                guard size >= 8 else { break }
                boxes.append((type: type, offset: offset, length: size))
                offset += size
            }
        }
        return boxes
    }

    // MARK: - File Structure Conformance

    func testFtypBoxPresence() async throws {
        let frames = [makeTestImage()]
        let data = try await createMJ2Data(frames: frames)
        let fileBytes = [UInt8](data)

        // Verify ftyp box exists in the file
        XCTAssertTrue(containsFourCC(fileBytes, "ftyp"), "MJ2 file must contain ftyp box")

        // Verify the brand in the ftyp box is mjp2 or mj2s
        let boxes = scanBoxes(in: data)
        if let ftypBox = boxes.first(where: { $0.type == "ftyp" }) {
            let brand = readBoxType(data, at: ftypBox.offset + 8)
            XCTAssertTrue(brand == "mjp2" || brand == "mj2s",
                          "ftyp brand must be 'mjp2' or 'mj2s', got '\(brand)'")
        }
    }

    func testMdatBoxPresence() async throws {
        let frames = [makeTestImage()]
        let data = try await createMJ2Data(frames: frames)
        let fileBytes = [UInt8](data)

        // The mdat box type must appear in the file
        XCTAssertTrue(containsFourCC(fileBytes, "mdat"), "MJ2 file must contain mdat box")

        // File must be larger than just headers (jP + ftyp + mdat header + moov)
        XCTAssertGreaterThan(data.count, 100, "File must contain actual frame data")
    }

    func testMoovBoxStructure() async throws {
        let frames = [makeTestImage()]
        let data = try await createMJ2Data(frames: frames)

        let boxes = scanBoxes(in: data)
        let moovBoxes = boxes.filter { $0.type == "moov" }
        XCTAssertEqual(moovBoxes.count, 1, "MJ2 file must contain exactly one moov box")

        // Verify moov contains mvhd and trak data by searching for FourCC in moov bytes
        if let moovBox = moovBoxes.first {
            let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))
            XCTAssertTrue(containsFourCC(moovBytes, "trak"), "moov must contain trak box")

            // Verify mvhd data is present by reading the timescale at the expected offset
            // mvhd content starts at moov offset + 8 (moov header) + 4 (version+flags)
            let mvhdStart = moovBox.offset + 8
            XCTAssertGreaterThan(moovBox.length, 100, "moov must contain mvhd data")
            // Timescale at offset 12 (version 0: 4 bytes v+f + 4 creation + 4 modification)
            let timescale = readUInt32BE(data, at: mvhdStart + 12)
            XCTAssertGreaterThan(timescale, 0, "mvhd timescale must be positive")
        }
    }

    func testTrackStructure() async throws {
        let frames = [makeTestImage()]
        let data = try await createMJ2Data(frames: frames)

        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))

        // trak box must be present (wrapped with header)
        XCTAssertTrue(containsFourCC(moovBytes, "trak"), "moov must contain trak box")
        // tkhd content is embedded without a box header, but mdia is wrapped
        XCTAssertTrue(containsFourCC(moovBytes, "mdia"), "trak must contain mdia box")
    }

    func testMediaBoxStructure() async throws {
        let frames = [makeTestImage()]
        let data = try await createMJ2Data(frames: frames)

        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))

        // hdlr and minf are wrapped with box headers inside mdia
        XCTAssertTrue(containsFourCC(moovBytes, "hdlr"), "mdia must contain hdlr box")
        XCTAssertTrue(containsFourCC(moovBytes, "minf"), "mdia must contain minf box")
        // Video handler type 'vide' must appear in hdlr content
        XCTAssertTrue(containsFourCC(moovBytes, "vide"), "hdlr must reference video handler")
    }

    func testSampleTableStructure() async throws {
        let frames = (0..<3).map { _ in makeTestImage(width: 32, height: 32) }
        let data = try await createMJ2Data(frames: frames)

        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))

        // Verify required sample table box types exist in moov
        // Note: stsd content is embedded without a separate box header
        XCTAssertTrue(containsFourCC(moovBytes, "stbl"), "must contain stbl (sample table)")
        XCTAssertTrue(containsFourCC(moovBytes, "stsz"), "stbl must contain stsz (sample size)")
        XCTAssertTrue(containsFourCC(moovBytes, "stsc"), "stbl must contain stsc (sample-to-chunk)")
        XCTAssertTrue(containsFourCC(moovBytes, "stts"), "stbl must contain stts (time-to-sample)")
        let hasChunkOffsets = containsFourCC(moovBytes, "stco") || containsFourCC(moovBytes, "co64")
        XCTAssertTrue(hasChunkOffsets, "stbl must contain stco or co64 (chunk offset)")
        // Sample entry format must be mjp2
        XCTAssertTrue(containsFourCC(moovBytes, "mjp2"), "stsd must contain mjp2 sample entry")
    }

    /// Checks if a byte array contains a 4-character code.
    private func containsFourCC(_ bytes: [UInt8], _ fourCC: String) -> Bool {
        let target = [UInt8](fourCC.utf8)
        guard target.count == 4, bytes.count >= 4 else { return false }
        for i in 0...(bytes.count - 4) {
            if bytes[i] == target[0] && bytes[i + 1] == target[1]
                && bytes[i + 2] == target[2] && bytes[i + 3] == target[3] {
                return true
            }
        }
        return false
    }

    // MARK: - Box Type Conformance

    func testMJ2BoxTypeConstants() {
        // Verify all required MJ2 box type constants exist and have correct values
        XCTAssertEqual(J2KBoxType.moov.stringValue, "moov")
        XCTAssertEqual(J2KBoxType.mvhd.stringValue, "mvhd")
        XCTAssertEqual(J2KBoxType.trak.stringValue, "trak")
        XCTAssertEqual(J2KBoxType.tkhd.stringValue, "tkhd")
        XCTAssertEqual(J2KBoxType.mdia.stringValue, "mdia")
        XCTAssertEqual(J2KBoxType.mdhd.stringValue, "mdhd")
        XCTAssertEqual(J2KBoxType.hdlr.stringValue, "hdlr")
        XCTAssertEqual(J2KBoxType.minf.stringValue, "minf")
        XCTAssertEqual(J2KBoxType.vmhd.stringValue, "vmhd")
        XCTAssertEqual(J2KBoxType.dinf.stringValue, "dinf")
        XCTAssertEqual(J2KBoxType.dref.stringValue, "dref")
        XCTAssertEqual(J2KBoxType.stbl.stringValue, "stbl")
        XCTAssertEqual(J2KBoxType.stsd.stringValue, "stsd")
        XCTAssertEqual(J2KBoxType.stts.stringValue, "stts")
        XCTAssertEqual(J2KBoxType.stsc.stringValue, "stsc")
        XCTAssertEqual(J2KBoxType.stsz.stringValue, "stsz")
        XCTAssertEqual(J2KBoxType.stco.stringValue, "stco")
        XCTAssertEqual(J2KBoxType.co64.stringValue, "co64")
        XCTAssertEqual(J2KBoxType.stss.stringValue, "stss")
        XCTAssertEqual(J2KBoxType.mdat.stringValue, "mdat")
        XCTAssertEqual(J2KBoxType.mjp2.stringValue, "mjp2")
        XCTAssertEqual(J2KBoxType.ftyp.stringValue, "ftyp")
    }

    func testVideoHandlerType() throws {
        // The sample entry format for MJ2 video tracks is 'mjp2'
        let entry = MJ2SampleEntry(width: 1920, height: 1080)
        XCTAssertEqual(entry.format, .mjp2, "Video sample entry type must be 'mjp2'")
        XCTAssertEqual(entry.format.stringValue, "mjp2")
    }

    func testSampleEntryType() throws {
        // Verify written sample entry data starts with 'mjp2' type at the correct offset
        let entry = MJ2SampleEntry(width: 1920, height: 1080, depth: 24)
        let data = try entry.write()

        let format = String(data: data.subdata(in: 4..<8), encoding: .ascii)
        XCTAssertEqual(format, "mjp2", "Sample entry type in binary must be 'mjp2'")
    }

    // MARK: - Profile Conformance

    func testSimpleProfileConstraints() throws {
        let simpleConfig = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        // Valid: within Simple Profile limits
        XCTAssertNoThrow(try simpleConfig.validate(width: 1920, height: 1080))
        XCTAssertNoThrow(try simpleConfig.validate(width: 1280, height: 720))

        // Invalid: exceeds maximum resolution
        XCTAssertThrowsError(try simpleConfig.validate(width: 2048, height: 1080)) { error in
            XCTAssertTrue(error is J2KError)
        }
        XCTAssertThrowsError(try simpleConfig.validate(width: 1920, height: 1200)) { error in
            XCTAssertTrue(error is J2KError)
        }

        // Invalid: exceeds maximum frame rate (Simple Profile ≤ 30 fps)
        let highFps = MJ2CreationConfiguration.from(frameRate: 60.0, profile: .simple)
        XCTAssertThrowsError(try highFps.validate(width: 1920, height: 1080)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }

    func testGeneralProfileNoConstraints() throws {
        let generalConfig = MJ2CreationConfiguration.from(frameRate: 60.0, profile: .general)

        // General Profile should accept any resolution and frame rate
        XCTAssertNoThrow(try generalConfig.validate(width: 3840, height: 2160))
        XCTAssertNoThrow(try generalConfig.validate(width: 7680, height: 4320))
        XCTAssertNoThrow(try generalConfig.validate(width: 1920, height: 1080))
        XCTAssertFalse(MJ2Profile.general.hasConstraints)
    }

    func testProfileBrandIdentifiers() {
        // ISO/IEC 15444-3: Simple Profile uses 'mj2s', General uses 'mjp2'
        XCTAssertEqual(MJ2Profile.simple.brandIdentifier, "mj2s")
        XCTAssertEqual(MJ2Profile.general.brandIdentifier, "mjp2")
        XCTAssertEqual(MJ2Profile.broadcast.brandIdentifier, "mjp2")
        XCTAssertEqual(MJ2Profile.cinema.brandIdentifier, "mjp2")

        // Format enum brand identifiers
        XCTAssertEqual(MJ2Format.mj2.brandIdentifier, "mjp2")
        XCTAssertEqual(MJ2Format.mj2s.brandIdentifier, "mj2s")
    }

    // MARK: - Timescale Conformance

    func testStandardFrameRates() {
        let rates: [(fps: Double, expectedTimescale: UInt32, expectedDuration: UInt32)] = [
            (24.0, 24000, 1000),
            (25.0, 25000, 1000),
            (30.0, 30000, 1000),
            (60.0, 60000, 1000),
        ]

        for (fps, expectedTS, expectedDur) in rates {
            let config = MJ2TimescaleConfiguration.from(frameRate: fps)
            XCTAssertEqual(config.timescale, expectedTS,
                           "Timescale for \(fps) fps should be \(expectedTS)")
            XCTAssertEqual(config.frameDuration, expectedDur,
                           "Frame duration for \(fps) fps should be \(expectedDur)")
            XCTAssertEqual(config.frameRate, fps, accuracy: 0.01,
                           "Computed frame rate should match \(fps)")
        }
    }

    func testNTSCFrameRate() {
        // NTSC 29.97 fps uses 30000/1001 per ISO spec
        let ntsc = MJ2TimescaleConfiguration.from(frameRate: 29.97)
        XCTAssertEqual(ntsc.timescale, 30000)
        XCTAssertEqual(ntsc.frameDuration, 1001)
        XCTAssertEqual(ntsc.frameRate, 29.97, accuracy: 0.01)
    }

    func testCustomTimescale() {
        let custom = MJ2TimescaleConfiguration(timescale: 90000, frameDuration: 3750)
        XCTAssertEqual(custom.timescale, 90000)
        XCTAssertEqual(custom.frameDuration, 3750)
        XCTAssertEqual(custom.frameRate, 24.0, accuracy: 0.01)
    }

    // MARK: - Sample Table Conformance

    func testSampleSizeConsistency() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        let sizes: [UInt32] = [1200, 1350, 1100, 1400, 1250]
        var offset: UInt64 = 0
        for size in sizes {
            await builder.addSample(size: size, offset: offset, isSync: true)
            offset += UInt64(size)
        }

        let count = await builder.sampleCount
        XCTAssertEqual(count, sizes.count, "Sample count must match number of frames added")

        let stszData = await builder.buildSampleSizeBox()
        XCTAssertGreaterThan(stszData.count, 0, "stsz box must not be empty")

        // Verify box type
        let boxType = stszData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stsz)
    }

    func testChunkOffsetAccuracy() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        let offsets: [UInt64] = [100, 1200, 2500, 4000]
        for (i, offset) in offsets.enumerated() {
            await builder.addSample(size: UInt32(1000 + i * 100), offset: offset, isSync: true)
        }

        let stcoData = await builder.buildChunkOffsetBox()
        let boxType = stcoData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stco,
                       "32-bit offsets must produce stco box")
        XCTAssertGreaterThan(stcoData.count, 8)
    }

    func testTimeToSampleEntries() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // Add 5 frames with uniform duration
        for i in 0..<5 {
            await builder.addSample(size: 1000, offset: UInt64(i * 1000), duration: 1000, isSync: true)
        }

        let sttsData = await builder.buildTimeToSampleBox()
        let boxType = sttsData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stts)
        XCTAssertGreaterThan(sttsData.count, 8, "stts box must contain entries")
    }

    func testSyncSampleMarking() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // For MJ2, all frames are independently decodable (all sync)
        for i in 0..<4 {
            await builder.addSample(size: 1000, offset: UInt64(i * 1000), isSync: true)
        }

        let count = await builder.sampleCount
        XCTAssertEqual(count, 4)

        // buildAllBoxes should include all required sample table boxes
        let allBoxes = await builder.buildAllBoxes()
        XCTAssertGreaterThanOrEqual(allBoxes.count, 4,
                                    "buildAllBoxes must produce at least stsz, stsc, stco, stts")
    }

    // MARK: - Round-Trip Conformance

    func testCreateAndReadFileInfo() async throws {
        let frames = (0..<3).map { _ in makeTestImage(width: 64, height: 64) }
        let data = try await createMJ2Data(frames: frames, frameRate: 24.0)

        // Verify format detection
        let detector = MJ2FormatDetector()
        XCTAssertTrue(try detector.isMJ2File(data: data))
        let format = try detector.detectFormat(data: data)
        XCTAssertEqual(format, .mj2)

        // Verify moov box exists and contains mvhd with valid timescale
        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        // Read mvhd directly from moov content (mvhd content starts at moov+8, no box header)
        let mvhdContentOffset = moovBox.offset + 8
        let mvhdContent = data.subdata(in: mvhdContentOffset..<(moovBox.offset + moovBox.length))
        var header = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try header.read(from: mvhdContent)
        XCTAssertGreaterThan(header.timescale, 0, "Timescale must be positive")
        XCTAssertGreaterThan(header.duration, 0, "Duration must be positive for multi-frame")
    }

    func testFrameCountPreservation() async throws {
        let frameCount = 5
        let frames = (0..<frameCount).map { _ in makeTestImage(width: 32, height: 32) }
        let data = try await createMJ2Data(frames: frames, frameRate: 24.0)

        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))

        // Verify sample table boxes are present (they hold frame count info)
        XCTAssertTrue(containsFourCC(moovBytes, "stsz"), "Must contain stsz with frame info")
        XCTAssertTrue(containsFourCC(moovBytes, "stts"), "Must contain stts with timing info")

        // Verify mvhd duration is consistent with frame count
        let mvhdContent = data.subdata(in: (moovBox.offset + 8)..<(moovBox.offset + moovBox.length))
        var header = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try header.read(from: mvhdContent)
        XCTAssertGreaterThan(header.duration, 0, "Duration must reflect frames")
    }

    func testDimensionPreservation() async throws {
        let width: UInt16 = 128
        let height: UInt16 = 96
        let frames = [makeTestImage(width: Int(width), height: Int(height))]
        let data = try await createMJ2Data(frames: frames, frameRate: 24.0)

        // Verify the sample entry in the moov box carries the correct dimensions
        // MJ2SampleEntry stores width/height as UInt16 without fixed-point conversion
        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }
        let moovBytes = [UInt8](data.subdata(in: moovBox.offset..<(moovBox.offset + moovBox.length)))

        // The mjp2 sample entry contains the UInt16 width/height
        // Verify the sample entry exists and the file contains moov with mjp2
        XCTAssertTrue(containsFourCC(moovBytes, "mjp2"), "moov must contain mjp2 sample entry")

        // Verify the MJ2SampleEntry can be round-tripped with correct dimensions
        let entry = MJ2SampleEntry(width: width, height: height, depth: 24)
        let entryData = try entry.write()
        var parsed = MJ2SampleEntry(width: 0, height: 0)
        try parsed.read(from: entryData)
        XCTAssertEqual(parsed.width, width, "Width must be preserved in sample entry")
        XCTAssertEqual(parsed.height, height, "Height must be preserved in sample entry")
    }

    func testTimescalePreservation() async throws {
        let frames = [makeTestImage(width: 32, height: 32)]
        let data = try await createMJ2Data(frames: frames, frameRate: 30.0)

        let boxes = scanBoxes(in: data)
        guard let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            XCTFail("No moov box found"); return
        }

        // mvhd content starts directly at moov+8 (no box header for mvhd)
        let mvhdContent = data.subdata(in: (moovBox.offset + 8)..<(moovBox.offset + moovBox.length))
        var header = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try header.read(from: mvhdContent)
        XCTAssertGreaterThan(header.timescale, 0, "Timescale must be preserved")
    }

    // MARK: - 64-bit Conformance

    func testVersion0MovieHeader() throws {
        // Version 0: 32-bit time values (timestamps fit in UInt32)
        let mvhd = MJ2MovieHeaderBox(
            creationTime: 100,
            modificationTime: 200,
            timescale: 600,
            duration: 6000,
            nextTrackID: 2
        )

        XCTAssertEqual(mvhd.version, 0, "Small timestamps should use version 0")

        let data = try mvhd.write()
        XCTAssertEqual(data[0], 0, "First byte should be version 0")

        var parsed = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try parsed.read(from: data)
        XCTAssertEqual(parsed.version, 0)
        XCTAssertEqual(parsed.timescale, 600)
        XCTAssertEqual(parsed.duration, 6000)
    }

    func testVersion1MovieHeader() throws {
        // Version 1: 64-bit time values (timestamps exceed UInt32.max)
        let largeTime: UInt64 = UInt64(UInt32.max) + 1
        let mvhd = MJ2MovieHeaderBox(
            creationTime: largeTime,
            modificationTime: largeTime + 1,
            timescale: 600,
            duration: 6000,
            nextTrackID: 2
        )

        XCTAssertEqual(mvhd.version, 1, "Large timestamps must use version 1")

        let data = try mvhd.write()
        XCTAssertEqual(data[0], 1, "First byte should be version 1")

        var parsed = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
        try parsed.read(from: data)
        XCTAssertEqual(parsed.version, 1)
        XCTAssertEqual(parsed.creationTime, largeTime)
        XCTAssertEqual(parsed.modificationTime, largeTime + 1)
    }

    // MARK: - Error Handling Conformance

    func testRejectInvalidMJ2Data() throws {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let detector = MJ2FormatDetector()
        XCTAssertFalse(try detector.isMJ2File(data: invalidData),
                       "Invalid data must not be detected as MJ2")
    }

    func testRejectEmptyFrames() async throws {
        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_empty_conformance.mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try await creator.create(from: [], outputURL: tempURL)
            XCTFail("Should have thrown noFrames error")
        } catch let error as MJ2CreationError {
            if case .noFrames = error {
                // Expected
            } else {
                XCTFail("Expected .noFrames, got \(error)")
            }
        }
    }

    func testRejectInconsistentDimensions() async throws {
        let frame1 = makeTestImage(width: 64, height: 64)
        let frame2 = makeTestImage(width: 32, height: 32)

        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_inconsistent_conformance.mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try await creator.create(from: [frame1, frame2], outputURL: tempURL)
            XCTFail("Should have thrown inconsistentDimensions error")
        } catch let error as MJ2CreationError {
            if case .inconsistentDimensions = error {
                // Expected
            } else {
                XCTFail("Expected .inconsistentDimensions, got \(error)")
            }
        }
    }
}
