/// # MJ2PerformanceTests
///
/// Performance tests for Motion JPEG 2000 operations.
///
/// These tests measure encoding/decoding throughput, memory usage,
/// and other performance characteristics to ensure MJ2 operations
/// meet real-time requirements.

import XCTest
@testable import J2KCodec
@testable import J2KFileFormat
import J2KCore

final class MJ2PerformanceTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    /// Test image dimensions (small for fast tests)
    let testWidth = 640
    let testHeight = 480
    
    /// Number of frames for throughput tests
    let smallFrameCount = 5
    
    // MARK: - Encoding Performance Tests
    
    func testEncodingThroughput() async throws {
        // Measure frames per second for encoding
        let frames = createTestFrames(count: smallFrameCount, width: testWidth, height: testHeight)
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_throughput_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let startTime = Date()
        
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        
        let elapsed = Date().timeIntervalSince(startTime)
        let fps = Double(smallFrameCount) / elapsed
        
        print("Encoding throughput: \(String(format: "%.2f", fps)) fps")
        print("Total time: \(String(format: "%.2f", elapsed)) seconds")
        print("Average time per frame: \(String(format: "%.2f", elapsed * 1000.0 / Double(smallFrameCount))) ms")
        
        // Verify throughput is reasonable (> 1 fps for small frames)
        XCTAssertGreaterThan(fps, 1.0, "Encoding should achieve at least 1 fps")
    }
    
    // MARK: - Decoding Performance Tests
    
    func testDecodingThroughput() async throws {
        // Measure frames per second for decoding
        let frames = createTestFrames(count: smallFrameCount, width: testWidth, height: testHeight)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_decode_throughput_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Create test file
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        
        // Measure decoding throughput
        let extractor = MJ2Extractor()
        var options = MJ2ExtractionOptions()
        options.decodeFrames = true
        options.parallel = true
        
        let startTime = Date()
        _ = try await extractor.extract(from: tempURL, options: options)
        let elapsed = Date().timeIntervalSince(startTime)
        
        let fps = Double(smallFrameCount) / elapsed
        print("Decoding throughput: \(String(format: "%.2f", fps)) fps")
        print("Total time: \(String(format: "%.2f", elapsed)) seconds")
        print("Average time per frame: \(String(format: "%.2f", elapsed * 1000.0 / Double(smallFrameCount))) ms")
        
        // Verify throughput is reasonable (> 1 fps)
        XCTAssertGreaterThan(fps, 1.0, "Decoding should achieve at least 1 fps")
    }
    
    // MARK: - Memory Performance Tests
    
    func testMemoryAllocationEfficiency() async throws {
        // Test that memory allocations are reasonable
        let frames = createTestFrames(count: 3, width: 320, height: 240)
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_memory_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Get initial memory
        let initialMemory = getMemoryUsage()
        
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        
        // Get final memory
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory increase should be reasonable (< 50MB for small test)
        print("Memory increase: \(memoryIncrease / 1_000_000) MB")
        if memoryIncrease > 0 {
            XCTAssertLessThan(memoryIncrease, 50_000_000, "Memory usage should be reasonable")
        }
    }
    
    func testPlayerMemoryManagement() async throws {
        // Test that player manages cache memory properly
        let frames = createTestFrames(count: 15, width: 320, height: 240)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_player_mem_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Create test file
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        
        // Test player memory
        let playerConfig = MJ2PlaybackConfiguration(
            maxCacheSize: 5,  // Limit cache
            prefetchCount: 2,
            memoryLimit: 10_000_000,  // 10MB limit
            enablePredictivePrefetch: true,
            timingTolerance: 16.67
        )
        
        let player = MJ2Player(configuration: playerConfig)
        try await player.load(from: tempURL)
        
        // Play through some frames
        try await player.play()
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        await player.stop()
        
        // Check memory usage
        let stats = await player.getStatistics()
        print("Player memory usage: \(stats.memoryUsage / 1_000_000) MB")
        XCTAssertLessThan(stats.memoryUsage, playerConfig.memoryLimit * 3, "Player should respect memory limits")
    }
    
    // MARK: - I/O Performance Tests
    
    func testAsyncFileWriting() async throws {
        // Test that async file writing is efficient
        let frames = createTestFrames(count: smallFrameCount, width: 320, height: 240)
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_async_io_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let startTime = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("Async file writing took: \(String(format: "%.2f", elapsed)) seconds")
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
    
    func testBufferedReading() async throws {
        // Test that reading is efficient
        let frames = createTestFrames(count: smallFrameCount, width: 320, height: 240)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_buffered_read_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Create test file
        let config = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        
        // Measure reading
        let startTime = Date()
        let reader = MJ2FileReader()
        _ = try await reader.readFileInfo(from: try Data(contentsOf: tempURL))
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("Buffered reading took: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 1.0, "Reading should be fast")
    }
    
    // MARK: - Parallel Operations Tests
    
    func testParallelEncodingSpeedup() async throws {
        // Compare sequential vs parallel encoding
        let frames = createTestFrames(count: 10, width: 320, height: 240)
        let baseConfig = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)
        
        // Sequential timing
        let seqConfig = MJ2CreationConfiguration(
            profile: baseConfig.profile,
            timescale: baseConfig.timescale,
            encodingConfiguration: baseConfig.encodingConfiguration,
            metadata: baseConfig.metadata,
            audioTrack: baseConfig.audioTrack,
            use64BitOffsets: baseConfig.use64BitOffsets,
            maxFrameBufferCount: baseConfig.maxFrameBufferCount,
            enableParallelEncoding: false,
            parallelEncodingCount: baseConfig.parallelEncodingCount
        )
        
        let seqURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_seq_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: seqURL)
        }
        
        let seqStart = Date()
        let seqCreator = MJ2Creator(configuration: seqConfig)
        try await seqCreator.create(from: frames, outputURL: seqURL)
        let seqTime = Date().timeIntervalSince(seqStart)
        
        // Parallel timing
        let parConfig = MJ2CreationConfiguration(
            profile: baseConfig.profile,
            timescale: baseConfig.timescale,
            encodingConfiguration: baseConfig.encodingConfiguration,
            metadata: baseConfig.metadata,
            audioTrack: baseConfig.audioTrack,
            use64BitOffsets: baseConfig.use64BitOffsets,
            maxFrameBufferCount: baseConfig.maxFrameBufferCount,
            enableParallelEncoding: true,
            parallelEncodingCount: 4
        )
        
        let parURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_par_\(UUID().uuidString).mj2")
        defer {
            try? FileManager.default.removeItem(at: parURL)
        }
        
        let parStart = Date()
        let parCreator = MJ2Creator(configuration: parConfig)
        try await parCreator.create(from: frames, outputURL: parURL)
        let parTime = Date().timeIntervalSince(parStart)
        
        // Calculate speedup
        let speedup = seqTime / parTime
        print("Sequential time: \(String(format: "%.2f", seqTime))s")
        print("Parallel time: \(String(format: "%.2f", parTime))s")
        print("Speedup: \(String(format: "%.2f", speedup))x")
        
        // Parallel should not be significantly slower
        XCTAssertGreaterThan(speedup, 0.8, "Parallel encoding should not be significantly slower")
    }
    
    // MARK: - Helper Methods
    
    /// Creates test frames for benchmarking.
    private func createTestFrames(count: Int, width: Int, height: Int) -> [J2KImage] {
        var frames: [J2KImage] = []
        
        for _ in 0..<count {
            // Create a simple test image
            let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
            frames.append(image)
        }
        
        return frames
    }
    
    /// Gets current memory usage in bytes.
    private func getMemoryUsage() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
        #else
        // Memory profiling not available on this platform
        return 0
        #endif
    }
}

