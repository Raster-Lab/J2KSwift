/// # MJ2IntegrationTests
///
/// End-to-end integration tests for Motion JPEG 2000 operations.
/// Tests creation, extraction, playback, and file info round trips.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore
@testable import J2KCodec

final class MJ2IntegrationTests: XCTestCase {
    
    // MARK: - Creation-Extraction Round Trip
    
    func testCreateAndExtractSingleFrame() async throws {
        let image = J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_single_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: [image], outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let sequence = try await extractor.extract(from: tempURL)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 1)
    }
    
    func testCreateAndExtractMultipleFrames() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_multi_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let sequence = try await extractor.extract(from: tempURL)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 3)
    }
    
    func testCreateAndExtractWithSimpleProfile() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_simple_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let sequence = try await extractor.extract(from: tempURL)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 3)
    }
    
    func testCreateAndExtractWithGeneralProfile() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .general, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_general_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let sequence = try await extractor.extract(from: tempURL)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 3)
    }
    
    // MARK: - Creation-Player Round Trip
    
    func testCreateAndLoadInPlayer() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_player_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        
        let state = await player.currentState()
        XCTAssertEqual(state, .stopped)
        
        let totalFrames = await player.totalFrames()
        XCTAssertEqual(totalFrames, 3)
    }
    
    func testCreateAndGetPlayerStatistics() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_stats_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        
        let stats = await player.getStatistics()
        XCTAssertEqual(stats.framesDecoded, 0)
        XCTAssertEqual(stats.framesDropped, 0)
        XCTAssertEqual(stats.averageDecodeTime, 0.0)
    }
    
    // MARK: - File Info Validation
    
    func testFileInfoFromCreatedFile() async throws {
        let frames = (0..<5).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_info_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let data = try Data(contentsOf: tempURL)
        let reader = MJ2FileReader()
        let fileInfo = try await reader.readFileInfo(from: data)
        
        XCTAssertGreaterThan(fileInfo.timescale, 0)
        XCTAssertGreaterThan(fileInfo.duration, 0)
        XCTAssertFalse(fileInfo.tracks.isEmpty)
        XCTAssertFalse(fileInfo.videoTracks.isEmpty)
    }
    
    func testFileInfoTrackDimensions() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_dims_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let data = try Data(contentsOf: tempURL)
        let reader = MJ2FileReader()
        let fileInfo = try await reader.readFileInfo(from: data)
        
        let videoTrack = fileInfo.videoTracks.first
        XCTAssertNotNil(videoTrack)
        XCTAssertEqual(videoTrack?.width, 64)
        XCTAssertEqual(videoTrack?.height, 64)
    }
    
    func testFileInfoDuration() async throws {
        let frameCount = 5
        let frameRate = 24.0
        let frames = (0..<frameCount).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: frameRate, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_dur_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let data = try Data(contentsOf: tempURL)
        let reader = MJ2FileReader()
        let fileInfo = try await reader.readFileInfo(from: data)
        
        let expectedDuration = Double(frameCount) / frameRate
        XCTAssertEqual(fileInfo.durationSeconds, expectedDuration, accuracy: 0.1)
    }
    
    func testFileInfoFormatDetection() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_detect_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let data = try Data(contentsOf: tempURL)
        let detector = MJ2FormatDetector()
        XCTAssertTrue(try detector.isMJ2File(data: data))
        
        let format = try detector.detectFormat(data: data)
        XCTAssertTrue(format == .mj2 || format == .mj2s)
    }
    
    // MARK: - Configuration Variations
    
    func testCreationWithDifferentFrameRates() async throws {
        let image = J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        let frameRates: [Double] = [24.0, 30.0, 60.0]
        
        for fps in frameRates {
            let config = MJ2CreationConfiguration.from(frameRate: fps, profile: .general, quality: 0.9)
            let creator = MJ2Creator(configuration: config)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_fps\(Int(fps))_\(UUID().uuidString).mj2")
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            try await creator.create(from: [image], outputURL: tempURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "Failed to create MJ2 at \(fps) fps")
        }
    }
    
    func testCreationWithLosslessConfig() async throws {
        let frames = (0..<2).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .general, lossless: true)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_lossless_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }
    
    func testCreationWithQualityConfig() async throws {
        let frames = (0..<2).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .general, quality: 0.5, lossless: false)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_quality_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
    
    func testCreationWithMetadata() async throws {
        let frames = (0..<2).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let metadata = MJ2Metadata(
            title: "Integration Test",
            author: "Test Suite",
            copyright: "2024 Test",
            description: "Integration test video"
        )
        
        let config = MJ2CreationConfiguration(
            timescale: MJ2TimescaleConfiguration.from(frameRate: 24.0),
            encodingConfiguration: J2KEncodingConfiguration(quality: 0.9),
            metadata: metadata
        )
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_meta_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
    
    // MARK: - Extraction Strategies
    
    func testExtractAllFrames() async throws {
        let frames = (0..<5).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_all_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .all)
        let sequence = try await extractor.extract(from: tempURL, options: options)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 5)
    }
    
    func testExtractSingleFrameStrategy() async throws {
        let frames = (0..<5).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_single_s_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .single(index: 2))
        let sequence = try await extractor.extract(from: tempURL, options: options)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 1)
        XCTAssertEqual(sequence?.frames[0].metadata.index, 2)
    }
    
    func testExtractRangeStrategy() async throws {
        let frames = (0..<10).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_range_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .range(start: 2, end: 5))
        let sequence = try await extractor.extract(from: tempURL, options: options)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 3)
        XCTAssertEqual(sequence?.frames[0].metadata.index, 2)
        XCTAssertEqual(sequence?.frames[2].metadata.index, 4)
    }
    
    func testExtractSkipStrategy() async throws {
        let frames = (0..<10).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_skip_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        let options = MJ2ExtractionOptions(strategy: .skip(interval: 3))
        let sequence = try await extractor.extract(from: tempURL, options: options)
        
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.count, 4) // Frames 0, 3, 6, 9
    }
    
    // MARK: - Player Modes
    
    func testPlayerForwardMode() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_fwd_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        await player.setPlaybackMode(.forward)
        
        let state = await player.currentState()
        XCTAssertEqual(state, .stopped)
    }
    
    func testPlayerReverseMode() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_rev_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        await player.setPlaybackMode(.reverse)
        
        let state = await player.currentState()
        XCTAssertEqual(state, .stopped)
    }
    
    func testPlayerLoopModes() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_loop_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        
        await player.setLoopMode(.none)
        var mode = await player.getLoopMode()
        XCTAssertEqual(mode, .none)
        
        await player.setLoopMode(.loop)
        mode = await player.getLoopMode()
        XCTAssertEqual(mode, .loop)
        
        await player.setLoopMode(.pingPong)
        mode = await player.getLoopMode()
        XCTAssertEqual(mode, .pingPong)
    }
    
    func testPlayerSpeedSettings() async throws {
        let frames = (0..<3).map { _ in
            J2KImage(width: 32, height: 32, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_speed_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let player = MJ2Player()
        try await player.load(from: tempURL)
        
        await player.setPlaybackSpeed(0.5)
        await player.setPlaybackSpeed(1.0)
        await player.setPlaybackSpeed(2.0)
        
        let state = await player.currentState()
        XCTAssertEqual(state, .stopped)
    }
    
    // MARK: - Error Recovery
    
    func testExtractFromInvalidData() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_invalid_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let randomData = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
        try randomData.write(to: tempURL)
        
        let extractor = MJ2Extractor()
        
        do {
            _ = try await extractor.extract(from: tempURL)
            XCTFail("Should throw error for invalid data")
        } catch {
            // Expected: extraction should fail gracefully
            XCTAssertTrue(true)
        }
    }
    
    func testPlayerLoadInvalidData() async throws {
        let randomData = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
        
        let player = MJ2Player()
        
        do {
            try await player.load(from: randomData)
            XCTFail("Should throw error for invalid data")
        } catch {
            // Expected: player should handle invalid data gracefully
            XCTAssertTrue(true)
        }
    }
    
    func testCreateWithEmptyFrames() async throws {
        let config = MJ2CreationConfiguration.from(frameRate: 24.0)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_empty_\(UUID().uuidString).mj2")
        
        do {
            try await creator.create(from: [], outputURL: tempURL)
            XCTFail("Should throw noFrames error")
        } catch let error as MJ2CreationError {
            if case .noFrames = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Multi-Track
    
    func testCreateAndReadMultipleVideoInfo() async throws {
        let frames = (0..<5).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_track_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let data = try Data(contentsOf: tempURL)
        let reader = MJ2FileReader()
        let fileInfo = try await reader.readFileInfo(from: data)
        
        XCTAssertFalse(fileInfo.videoTracks.isEmpty)
        
        for track in fileInfo.videoTracks {
            XCTAssertGreaterThan(track.trackID, 0)
            XCTAssertTrue(track.isVideo)
            XCTAssertGreaterThan(track.sampleCount, 0)
        }
    }
    
    func testExtractorCancellation() async throws {
        let frames = (0..<100).map { _ in
            J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
        
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, quality: 0.9)
        let creator = MJ2Creator(configuration: config)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("integration_cancel_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await creator.create(from: frames, outputURL: tempURL)
        
        let extractor = MJ2Extractor()
        
        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await extractor.cancel()
        }
        
        do {
            _ = try await extractor.extract(from: tempURL)
            // May complete before cancellation takes effect
        } catch let error as MJ2ExtractionError {
            if case .cancelled = error {
                // Expected cancellation
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}
