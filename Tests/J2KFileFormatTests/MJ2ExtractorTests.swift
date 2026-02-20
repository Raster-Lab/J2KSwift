//
// MJ2ExtractorTests.swift
// J2KSwift
//
/// # MJ2ExtractorTests
///
/// Tests for Motion JPEG 2000 frame extraction.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore
@testable import J2KCodec

final class MJ2ExtractorTests: XCTestCase {
    // MARK: - Frame Metadata Tests

    func testFrameMetadataCreation() {
        let metadata = MJ2FrameMetadata(
            index: 0,
            size: 1000,
            offset: 8192,
            duration: 1000,
            timestamp: 0,
            isSync: true
        )

        XCTAssertEqual(metadata.index, 0)
        XCTAssertEqual(metadata.size, 1000)
        XCTAssertEqual(metadata.offset, 8192)
        XCTAssertEqual(metadata.duration, 1000)
        XCTAssertEqual(metadata.timestamp, 0)
        XCTAssertTrue(metadata.isSync)
    }

    // MARK: - Frame Sequence Tests

    func testFrameSequenceEmpty() {
        let sequence = MJ2FrameSequence(frames: [])

        XCTAssertEqual(sequence.count, 0)
        XCTAssertEqual(sequence.totalDuration, 0)
        XCTAssertTrue(sequence.syncFrames.isEmpty)
    }

    func testFrameSequenceSingleFrame() {
        let metadata = MJ2FrameMetadata(
            index: 0,
            size: 1000,
            offset: 0,
            duration: 1000,
            timestamp: 0,
            isSync: true
        )
        let frame = MJ2FrameSequence.Frame(metadata: metadata, data: Data(count: 1000))
        let sequence = MJ2FrameSequence(frames: [frame])

        XCTAssertEqual(sequence.count, 1)
        XCTAssertEqual(sequence.totalDuration, 1000)
        XCTAssertEqual(sequence.syncFrames.count, 1)
    }

    func testFrameSequenceMultipleFrames() {
        var frames: [MJ2FrameSequence.Frame] = []

        for i in 0..<10 {
            let metadata = MJ2FrameMetadata(
                index: i,
                size: 1000,
                offset: UInt64(i * 1000),
                duration: 1000,
                timestamp: UInt64(i * 1000),
                isSync: i.isMultiple(of: 3) // Every 3rd frame is a sync frame
            )
            let frame = MJ2FrameSequence.Frame(metadata: metadata, data: Data(count: 1000))
            frames.append(frame)
        }

        let sequence = MJ2FrameSequence(frames: frames)

        XCTAssertEqual(sequence.count, 10)
        XCTAssertEqual(sequence.totalDuration, 10000)
        XCTAssertEqual(sequence.syncFrames.count, 4) // Frames 0, 3, 6, 9
    }

    func testFrameSequenceFrameAtIndex() {
        let metadata = MJ2FrameMetadata(
            index: 0,
            size: 1000,
            offset: 0,
            duration: 1000,
            timestamp: 0,
            isSync: true
        )
        let frame = MJ2FrameSequence.Frame(metadata: metadata, data: Data(count: 1000))
        let sequence = MJ2FrameSequence(frames: [frame])

        XCTAssertNotNil(sequence.frame(at: 0))
        XCTAssertNil(sequence.frame(at: 1))
        XCTAssertNil(sequence.frame(at: -1))
    }

    func testFrameSequenceFramesInRange() {
        var frames: [MJ2FrameSequence.Frame] = []

        for i in 0..<10 {
            let metadata = MJ2FrameMetadata(
                index: i,
                size: 1000,
                offset: UInt64(i * 1000),
                duration: 1000,
                timestamp: UInt64(i * 1000),
                isSync: true
            )
            let frame = MJ2FrameSequence.Frame(metadata: metadata, data: Data(count: 1000))
            frames.append(frame)
        }

        let sequence = MJ2FrameSequence(frames: frames)

        let rangeFrames = sequence.frames(in: 2..<5)
        XCTAssertEqual(rangeFrames.count, 3)
        XCTAssertEqual(rangeFrames[0].metadata.index, 2)
        XCTAssertEqual(rangeFrames[2].metadata.index, 4)
    }

    func testFrameSequenceFramesInTimestampRange() {
        var frames: [MJ2FrameSequence.Frame] = []

        for i in 0..<10 {
            let metadata = MJ2FrameMetadata(
                index: i,
                size: 1000,
                offset: UInt64(i * 1000),
                duration: 1000,
                timestamp: UInt64(i * 1000),
                isSync: true
            )
            let frame = MJ2FrameSequence.Frame(metadata: metadata, data: Data(count: 1000))
            frames.append(frame)
        }

        let sequence = MJ2FrameSequence(frames: frames)

        // Get frames from timestamp 2000 to 5000
        let timestampFrames = sequence.frames(timestampRange: 2000..<5000)
        XCTAssertEqual(timestampFrames.count, 3) // Frames 2, 3, 4
        XCTAssertEqual(timestampFrames[0].metadata.timestamp, 2000)
        XCTAssertEqual(timestampFrames[2].metadata.timestamp, 4000)
    }

    // MARK: - Extraction Strategy Tests

    func testExtractionStrategyAll() {
        let strategy = MJ2ExtractionStrategy.all

        switch strategy {
        case .all:
            XCTAssertTrue(true)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testExtractionStrategySyncOnly() {
        let strategy = MJ2ExtractionStrategy.syncOnly

        switch strategy {
        case .syncOnly:
            XCTAssertTrue(true)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testExtractionStrategyRange() {
        let strategy = MJ2ExtractionStrategy.range(start: 10, end: 20)

        switch strategy {
        case let .range(start, end):
            XCTAssertEqual(start, 10)
            XCTAssertEqual(end, 20)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testExtractionStrategyTimestampRange() {
        let strategy = MJ2ExtractionStrategy.timestampRange(start: 1000, end: 5000)

        switch strategy {
        case let .timestampRange(start, end):
            XCTAssertEqual(start, 1000)
            XCTAssertEqual(end, 5000)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testExtractionStrategySkip() {
        let strategy = MJ2ExtractionStrategy.skip(interval: 5)

        switch strategy {
        case .skip(let interval):
            XCTAssertEqual(interval, 5)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testExtractionStrategySingle() {
        let strategy = MJ2ExtractionStrategy.single(index: 42)

        switch strategy {
        case .single(let index):
            XCTAssertEqual(index, 42)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    // MARK: - Output Strategy Tests

    func testOutputStrategyMemory() {
        let strategy = MJ2OutputStrategy.memory

        switch strategy {
        case .memory:
            XCTAssertTrue(true)
        default:
            XCTFail("Unexpected strategy")
        }
    }

    func testOutputStrategyDefaultNaming() {
        let naming = MJ2OutputStrategy.defaultNaming(prefix: "frame")

        XCTAssertEqual(naming(0), "frame_000000.j2k")
        XCTAssertEqual(naming(1), "frame_000001.j2k")
        XCTAssertEqual(naming(999), "frame_000999.j2k")
        XCTAssertEqual(naming(1000), "frame_001000.j2k")
    }

    // MARK: - Extraction Options Tests

    func testExtractionOptionsDefaults() {
        let options = MJ2ExtractionOptions()

        switch options.strategy {
        case .all:
            XCTAssertTrue(true)
        default:
            XCTFail("Default strategy should be .all")
        }

        switch options.outputStrategy {
        case .memory:
            XCTAssertTrue(true)
        default:
            XCTFail("Default output strategy should be .memory")
        }

        XCTAssertFalse(options.decodeFrames)
        XCTAssertTrue(options.parallel)
        XCTAssertNil(options.trackID)
    }

    func testExtractionOptionsCustom() {
        let options = MJ2ExtractionOptions(
            strategy: .syncOnly,
            outputStrategy: .imageSequence(
                directory: URL(fileURLWithPath: "/tmp/frames"),
                prefix: "test"
            ),
            decodeFrames: true,
            parallel: false,
            trackID: 1
        )

        switch options.strategy {
        case .syncOnly:
            XCTAssertTrue(true)
        default:
            XCTFail("Strategy should be .syncOnly")
        }

        XCTAssertTrue(options.decodeFrames)
        XCTAssertFalse(options.parallel)
        XCTAssertEqual(options.trackID, 1)
    }

    // MARK: - Integration Tests

    func testCreateAndExtractRoundTrip() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<5 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Extract frames
        let extractor = MJ2Extractor()
        let sequence = try await extractor.extract(from: tempURL)

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 5)

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testExtractWithRangeStrategy() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<10 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Extract frames 2-5
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .range(start: 2, end: 5))
        let sequence = try await extractor.extract(from: tempURL, options: options)

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 3)
        XCTAssertEqual(sequence?.frames[0].metadata.index, 2)
        XCTAssertEqual(sequence?.frames[2].metadata.index, 4)

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testExtractWithSkipStrategy() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<10 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Extract every 3rd frame
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .skip(interval: 3))
        let sequence = try await extractor.extract(from: tempURL, options: options)

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 4) // Frames 0, 3, 6, 9

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testExtractWithSingleFrameStrategy() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<5 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Extract single frame
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .single(index: 2))
        let sequence = try await extractor.extract(from: tempURL, options: options)

        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 1)
        XCTAssertEqual(sequence?.frames[0].metadata.index, 2)

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testExtractToFiles() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<3 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Extract to files
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("frames_\(UUID().uuidString)")
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(
            outputStrategy: .imageSequence(directory: outputDir, prefix: "frame")
        )
        let sequence = try await extractor.extract(from: tempURL, options: options)

        // Should return nil for file output
        XCTAssertNil(sequence)

        // Verify files were created
        let files = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: outputDir)
    }

    func testExtractWithInvalidRange() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<5 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Try to extract invalid range
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .range(start: 10, end: 20))

        do {
            _ = try await extractor.extract(from: tempURL, options: options)
            XCTFail("Should throw error for invalid range")
        } catch let error as MJ2ExtractionError {
            switch error {
            case .invalidFrameRange:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type")
            }
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testExtractorCancellation() async throws {
        // Create a simple MJ2 file with test frames
        let creator = MJ2Creator(configuration: MJ2CreationConfiguration.from(frameRate: 30.0))

        // Create test frames
        var testFrames: [J2KImage] = []
        for _ in 0..<100 {
            let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            testFrames.append(image)
        }

        // Create MJ2 file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mj2")
        try await creator.create(from: testFrames, outputURL: tempURL)

        // Start extraction and cancel
        let extractor = MJ2Extractor()

        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            await extractor.cancel()
        }

        do {
            _ = try await extractor.extract(from: tempURL)
            // May or may not complete before cancellation
        } catch let error as MJ2ExtractionError {
            switch error {
            case .cancelled:
                XCTAssertTrue(true)
            default:
                XCTFail("Wrong error type")
            }
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}
