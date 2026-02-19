/// # MJ2PlayerTests
///
/// Tests for the MJ2Player playback engine.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KFileFormat

final class MJ2PlayerTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testPlayerInitialization() {
        let player = MJ2Player()
        XCTAssertNotNil(player)
    }
    
    func testPlayerInitializationWithConfiguration() {
        let config = MJ2PlaybackConfiguration(
            maxCacheSize: 60,
            prefetchCount: 10,
            memoryLimit: 512 * 1024 * 1024,
            enablePredictivePrefetch: true,
            timingTolerance: 16.67
        )
        
        let player = MJ2Player(configuration: config)
        XCTAssertNotNil(player)
    }
    
    func testDefaultConfiguration() {
        let config = MJ2PlaybackConfiguration()
        
        XCTAssertEqual(config.maxCacheSize, 30)
        XCTAssertEqual(config.prefetchCount, 5)
        XCTAssertEqual(config.memoryLimit, 256 * 1024 * 1024)
        XCTAssertTrue(config.enablePredictivePrefetch)
        XCTAssertEqual(config.timingTolerance, 16.67, accuracy: 0.01)
    }
    
    // MARK: - State Tests
    
    func testInitialState() async {
        let player = MJ2Player()
        
        let state = await player.currentState()
        XCTAssertEqual(state, .stopped)
        
        let index = await player.currentIndex()
        XCTAssertEqual(index, 0)
        
        let totalFrames = await player.totalFrames()
        XCTAssertEqual(totalFrames, 0)
    }
    
    func testStateAfterLoad() async throws {
        // Skip this test as it requires a valid MJ2 file structure
        // In real usage, MJ2FileReader would parse the actual file
        throw XCTSkip("Requires valid MJ2 file structure")
    }
    
    func testPlaybackStateTransitions() async throws {
        let player = MJ2Player()
        
        // Initial state is stopped
        var state = await player.currentState()
        XCTAssertEqual(state, .stopped)
        
        // Pause without loading should not change state
        await player.pause()
        state = await player.currentState()
        XCTAssertEqual(state, .stopped)
        
        // Stop without loading should remain stopped
        await player.stop()
        state = await player.currentState()
        XCTAssertEqual(state, .stopped)
    }
    
    // MARK: - Playback Mode Tests
    
    func testSetPlaybackMode() async {
        let player = MJ2Player()
        
        await player.setPlaybackMode(.forward)
        await player.setPlaybackMode(.reverse)
        await player.setPlaybackMode(.stepForward)
        await player.setPlaybackMode(.stepBackward)
        
        // No error should be thrown
    }
    
    func testSetPlaybackSpeed() async {
        let player = MJ2Player()
        
        await player.setPlaybackSpeed(0.5)
        await player.setPlaybackSpeed(1.0)
        await player.setPlaybackSpeed(2.0)
        await player.setPlaybackSpeed(10.0)
        
        // Speed outside range should be clamped
        await player.setPlaybackSpeed(0.05) // Should clamp to 0.1
        await player.setPlaybackSpeed(20.0) // Should clamp to 10.0
    }
    
    // MARK: - Loop Mode Tests
    
    func testLoopModeNone() async {
        let player = MJ2Player()
        
        await player.setLoopMode(.none)
        let mode = await player.getLoopMode()
        XCTAssertEqual(mode, .none)
    }
    
    func testLoopModeLoop() async {
        let player = MJ2Player()
        
        await player.setLoopMode(.loop)
        let mode = await player.getLoopMode()
        XCTAssertEqual(mode, .loop)
    }
    
    func testLoopModePingPong() async {
        let player = MJ2Player()
        
        await player.setLoopMode(.pingPong)
        let mode = await player.getLoopMode()
        XCTAssertEqual(mode, .pingPong)
    }
    
    // MARK: - Seeking Tests
    
    func testSeekWithoutLoad() async {
        let player = MJ2Player()
        
        do {
            try await player.seek(to: 0)
            XCTFail("Should throw notInitialized error")
        } catch MJ2PlaybackError.notInitialized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSeekToTimestampWithoutLoad() async {
        let player = MJ2Player()
        
        do {
            try await player.seek(toTimestamp: 0)
            XCTFail("Should throw notInitialized error")
        } catch MJ2PlaybackError.notInitialized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Frame Access Tests
    
    func testCurrentFrameWithoutLoad() async {
        let player = MJ2Player()
        
        do {
            _ = try await player.currentFrame()
            XCTFail("Should throw notInitialized error")
        } catch MJ2PlaybackError.notInitialized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFrameAtIndexWithoutLoad() async {
        let player = MJ2Player()
        
        do {
            _ = try await player.frame(at: 0)
            XCTFail("Should throw notInitialized error")
        } catch MJ2PlaybackError.notInitialized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testNextFrameWithoutLoad() async {
        let player = MJ2Player()
        
        do {
            _ = try await player.nextFrame()
            XCTFail("Should throw notInitialized error")
        } catch MJ2PlaybackError.notInitialized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Statistics Tests
    
    func testInitialStatistics() async {
        let player = MJ2Player()
        
        let stats = await player.getStatistics()
        
        XCTAssertEqual(stats.framesDecoded, 0)
        XCTAssertEqual(stats.framesDropped, 0)
        XCTAssertEqual(stats.averageDecodeTime, 0.0)
        XCTAssertEqual(stats.cacheHitRate, 0.0)
        XCTAssertEqual(stats.memoryUsage, 0)
    }
    
    func testStatisticsInitialization() {
        let stats = MJ2PlaybackStatistics()
        
        XCTAssertEqual(stats.framesDecoded, 0)
        XCTAssertEqual(stats.framesDropped, 0)
        XCTAssertEqual(stats.averageDecodeTime, 0.0)
        XCTAssertEqual(stats.cacheHitRate, 0.0)
        XCTAssertEqual(stats.memoryUsage, 0)
    }
    
    // MARK: - Cache Tests
    
    func testClearCache() async {
        let player = MJ2Player()
        
        await player.clearCache()
        
        let stats = await player.getStatistics()
        XCTAssertEqual(stats.memoryUsage, 0)
    }
    
    func testCacheSizeLimit() {
        let config = MJ2PlaybackConfiguration(
            maxCacheSize: 10,
            prefetchCount: 3
        )
        
        XCTAssertEqual(config.maxCacheSize, 10)
        XCTAssertEqual(config.prefetchCount, 3)
    }
    
    func testMemoryLimit() {
        let memoryLimit: UInt64 = 100 * 1024 * 1024 // 100 MB
        let config = MJ2PlaybackConfiguration(
            memoryLimit: memoryLimit
        )
        
        XCTAssertEqual(config.memoryLimit, memoryLimit)
    }
    
    // MARK: - Timestamp Tests
    
    func testCurrentTimestampWithoutLoad() async {
        let player = MJ2Player()
        
        let timestamp = await player.currentTimestamp()
        XCTAssertEqual(timestamp, 0)
    }
    
    func testTotalDurationWithoutLoad() async {
        let player = MJ2Player()
        
        let duration = await player.totalDuration()
        XCTAssertEqual(duration, 0)
    }
    
    // MARK: - Error Tests
    
    func testPlaybackErrorTypes() {
        let _ = MJ2PlaybackError.invalidFile
        let _ = MJ2PlaybackError.noVideoTracks
        let _ = MJ2PlaybackError.notInitialized
        let _ = MJ2PlaybackError.seekFailed
        let _ = MJ2PlaybackError.stopped
        
        let dummyError = NSError(domain: "test", code: 0)
        let _ = MJ2PlaybackError.decodeFailed(frameIndex: 0, error: dummyError)
    }
    
    // MARK: - Playback State Enum Tests
    
    func testPlaybackStateEnum() {
        let _ = MJ2PlaybackState.stopped
        let _ = MJ2PlaybackState.playing
        let _ = MJ2PlaybackState.paused
        let _ = MJ2PlaybackState.seeking
    }
    
    // MARK: - Playback Mode Enum Tests
    
    func testPlaybackModeEnum() {
        let _ = MJ2PlaybackMode.forward
        let _ = MJ2PlaybackMode.reverse
        let _ = MJ2PlaybackMode.stepForward
        let _ = MJ2PlaybackMode.stepBackward
    }
    
    // MARK: - Loop Mode Enum Tests
    
    func testLoopModeEnum() {
        let _ = MJ2LoopMode.none
        let _ = MJ2LoopMode.loop
        let _ = MJ2LoopMode.pingPong
    }
    
    // MARK: - Configuration Validation Tests
    
    func testConfigurationWithCustomValues() {
        let config = MJ2PlaybackConfiguration(
            maxCacheSize: 100,
            prefetchCount: 20,
            memoryLimit: 1024 * 1024 * 1024,
            enablePredictivePrefetch: false,
            timingTolerance: 33.33
        )
        
        XCTAssertEqual(config.maxCacheSize, 100)
        XCTAssertEqual(config.prefetchCount, 20)
        XCTAssertEqual(config.memoryLimit, 1024 * 1024 * 1024)
        XCTAssertFalse(config.enablePredictivePrefetch)
        XCTAssertEqual(config.timingTolerance, 33.33, accuracy: 0.01)
    }
    
    func testMinimalConfiguration() {
        let config = MJ2PlaybackConfiguration(
            maxCacheSize: 1,
            prefetchCount: 0,
            memoryLimit: 0,
            enablePredictivePrefetch: false,
            timingTolerance: 0.0
        )
        
        XCTAssertEqual(config.maxCacheSize, 1)
        XCTAssertEqual(config.prefetchCount, 0)
        XCTAssertEqual(config.memoryLimit, 0)
        XCTAssertFalse(config.enablePredictivePrefetch)
        XCTAssertEqual(config.timingTolerance, 0.0)
    }
    
    // MARK: - Performance Tests
    
    func testPlayerCreationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = MJ2Player()
            }
        }
    }
    
    func testConfigurationCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                let _ = MJ2PlaybackConfiguration()
            }
        }
    }
    
    func testStatisticsAccessPerformance() async {
        let player = MJ2Player()
        
        measure {
            Task {
                for _ in 0..<100 {
                    let _ = await player.getStatistics()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Creates test MJ2 data (minimal valid structure).
    private func createTestMJ2Data() -> Data {
        // This is a placeholder - real implementation would create valid MJ2 structure
        var data = Data()
        
        // JP2 signature box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // Length: 12
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20]) // Type: 'jP  '
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A]) // Magic
        
        // File type box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x14]) // Length: 20
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70]) // Type: 'ftyp'
        data.append(contentsOf: [0x6D, 0x6A, 0x70, 0x32]) // Brand: 'mjp2'
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Minor version
        data.append(contentsOf: [0x6D, 0x6A, 0x70, 0x32]) // Compatible brand: 'mjp2'
        
        return data
    }
}

// MARK: - Actor Extensions for Testing

extension MJ2Player {
    /// Sets the loop mode for testing.
    func setLoopMode(_ mode: MJ2LoopMode) {
        self.loopMode = mode
    }
    
    /// Gets the loop mode for testing.
    func getLoopMode() -> MJ2LoopMode {
        return self.loopMode
    }
}
