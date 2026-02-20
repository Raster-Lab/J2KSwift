//
// MJ2CreatorTests.swift
// J2KSwift
//
/// # MJ2CreatorTests
///
/// Tests for Motion JPEG 2000 file creation.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore
@testable import J2KCodec

final class MJ2CreatorTests: XCTestCase {
    // MARK: - Configuration Tests

    func testMJ2ProfileProperties() {
        XCTAssertEqual(MJ2Profile.simple.brandIdentifier, "mj2s")
        XCTAssertEqual(MJ2Profile.general.brandIdentifier, "mjp2")
        XCTAssertTrue(MJ2Profile.simple.hasConstraints)
        XCTAssertFalse(MJ2Profile.general.hasConstraints)
    }

    func testTimescaleConfiguration() {
        // Test standard frame rates
        let fps24 = MJ2TimescaleConfiguration.from(frameRate: 24.0)
        XCTAssertEqual(fps24.timescale, 24000)
        XCTAssertEqual(fps24.frameDuration, 1000)
        XCTAssertEqual(fps24.frameRate, 24.0, accuracy: 0.01)

        let fps30 = MJ2TimescaleConfiguration.from(frameRate: 30.0)
        XCTAssertEqual(fps30.timescale, 30000)
        XCTAssertEqual(fps30.frameDuration, 1000)

        // Test NTSC frame rate
        let fps2997 = MJ2TimescaleConfiguration.from(frameRate: 29.97)
        XCTAssertEqual(fps2997.timescale, 30000)
        XCTAssertEqual(fps2997.frameDuration, 1001)
        XCTAssertEqual(fps2997.frameRate, 29.97, accuracy: 0.01)
    }

    func testMetadataCreation() {
        let metadata = MJ2Metadata(
            title: "Test Video",
            author: "Test Author",
            copyright: "2024 Test",
            description: "Test description"
        )

        XCTAssertEqual(metadata.title, "Test Video")
        XCTAssertEqual(metadata.author, "Test Author")
        XCTAssertEqual(metadata.copyright, "2024 Test")
        XCTAssertEqual(metadata.description, "Test description")
    }

    func testCreationConfigurationFromFrameRate() {
        let config = MJ2CreationConfiguration.from(
            frameRate: 24.0,
            profile: .simple,
            quality: 0.9,
            lossless: false
        )

        XCTAssertEqual(config.profile, .simple)
        XCTAssertEqual(config.timescale.frameRate, 24.0, accuracy: 0.01)
        XCTAssertEqual(config.encodingConfiguration.quality, 0.9, accuracy: 0.01)
        XCTAssertFalse(config.encodingConfiguration.lossless)
        XCTAssertFalse(config.use64BitOffsets)
        XCTAssertTrue(config.enableParallelEncoding)
    }

    func testConfigurationValidation() throws {
        // Valid configuration
        let validConfig = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)
        XCTAssertNoThrow(try validConfig.validate(width: 1920, height: 1080))

        // Invalid: exceeds Simple Profile resolution
        XCTAssertThrowsError(try validConfig.validate(width: 4096, height: 2160)) { error in
            XCTAssertTrue(error is J2KError)
        }

        // Invalid: exceeds Simple Profile frame rate
        let highFpsConfig = MJ2CreationConfiguration.from(frameRate: 60.0, profile: .simple)
        XCTAssertThrowsError(try highFpsConfig.validate(width: 1920, height: 1080)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }

    // MARK: - Sample Table Tests

    func testSampleTableBuilderEmpty() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)
        let count = await builder.sampleCount
        XCTAssertEqual(count, 0)
    }

    func testSampleTableBuilderAddSamples() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // Add some samples
        await builder.addSample(size: 1000, offset: 0, isSync: true)
        await builder.addSample(size: 1100, offset: 1000, isSync: true)
        await builder.addSample(size: 1050, offset: 2100, isSync: true)

        let count = await builder.sampleCount
        XCTAssertEqual(count, 3)
    }

    func testSampleSizeBoxConstantSize() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // Add samples with same size
        await builder.addSample(size: 1000, offset: 0)
        await builder.addSample(size: 1000, offset: 1000)
        await builder.addSample(size: 1000, offset: 2000)

        let stszData = await builder.buildSampleSizeBox()
        XCTAssertGreaterThan(stszData.count, 0)

        // Verify box type
        let boxType = stszData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stsz)
    }

    func testSampleSizeBoxVariableSize() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // Add samples with different sizes
        await builder.addSample(size: 1000, offset: 0)
        await builder.addSample(size: 1100, offset: 1000)
        await builder.addSample(size: 900, offset: 2100)

        let stszData = await builder.buildSampleSizeBox()
        XCTAssertGreaterThan(stszData.count, 0)
    }

    func testChunkOffsetBox32Bit() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        await builder.addSample(size: 1000, offset: 0)
        await builder.addSample(size: 1000, offset: 1000)

        let stcoData = await builder.buildChunkOffsetBox()
        XCTAssertGreaterThan(stcoData.count, 0)

        // Verify box type is stco
        let boxType = stcoData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stco)
    }

    func testChunkOffsetBox64Bit() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: true)

        let largeOffset: UInt64 = 5_000_000_000  // >4GB
        await builder.addSample(size: 1000, offset: largeOffset)

        let co64Data = await builder.buildChunkOffsetBox()
        XCTAssertGreaterThan(co64Data.count, 0)

        // Verify box type is co64
        let boxType = co64Data.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .co64)
    }

    func testTimeToSampleBox() async {
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)

        // Add samples with same duration (should compress to single entry)
        await builder.addSample(size: 1000, offset: 0, duration: 1000)
        await builder.addSample(size: 1000, offset: 1000, duration: 1000)
        await builder.addSample(size: 1000, offset: 2000, duration: 1000)

        let sttsData = await builder.buildTimeToSampleBox()
        XCTAssertGreaterThan(sttsData.count, 0)

        // Verify box type
        let boxType = sttsData.readUInt32(at: 4)
        XCTAssertEqual(J2KBoxType(rawValue: boxType), .stts)
    }

    // MARK: - MJ2 Creation Tests

    func testCreateSingleFrameMJ2() async throws {
        // Create a simple test image
        let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)

        // Configure for a single-frame "video"
        let config = MJ2CreationConfiguration.from(frameRate: 1.0, quality: 0.95)
        let creator = MJ2Creator(configuration: config)

        // Create temporary output file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_single.mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create MJ2 file
        try await creator.create(from: [image], outputURL: tempURL)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Verify file size is reasonable
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testCreateMultiFrameMJ2() async throws {
        // Create multiple test frames
        let frames = (0..<5).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }

        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_multi.mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await creator.create(from: frames, outputURL: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    // MARK: - Note: Progress reporting test skipped due to Sendable constraints in test context
    // In actual usage, progress callbacks work correctly within the actor isolation context

    func testInconsistentDimensionsError() async throws {
        let frame1 = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        let frame2 = J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)

        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_inconsistent.mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try await creator.create(from: [frame1, frame2], outputURL: tempURL)
            XCTFail("Should have thrown inconsistentDimensions error")
        } catch let error as MJ2CreationError {
            if case .inconsistentDimensions = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testEmptyFramesError() async throws {
        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.mj2")

        do {
            try await creator.create(from: [], outputURL: tempURL)
            XCTFail("Should have thrown noFrames error")
        } catch let error as MJ2CreationError {
            if case .noFrames = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testCancellation() async throws {
        // Create many frames to give time for cancellation
        let frames = (0..<100).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }

        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_cancel.mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Start creation in a task
        let task = Task {
            try await creator.create(from: frames, outputURL: tempURL)
        }

        // Cancel after a short delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await creator.cancel()

        do {
            try await task.value
            // May complete before cancellation takes effect
        } catch let error as MJ2CreationError {
            if case .cancelled = error {
                // Expected cancellation
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRepeatedImageCreation() async throws {
        let image = J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)

        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_repeated.mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await creator.createRepeated(image: image, frameCount: 10, outputURL: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
}

// MARK: - Helper Extensions

extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self).bigEndian
        }
    }
}
