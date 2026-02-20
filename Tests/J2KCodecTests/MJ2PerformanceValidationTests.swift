/// # MJ2PerformanceValidationTests
///
/// Performance validation tests for Motion JPEG 2000 operations.
///
/// These tests validate encoding benchmarks, playback performance,
/// memory efficiency, I/O performance, cross-platform capabilities,
/// and scalability characteristics of MJ2 operations.

import XCTest
@testable import J2KCodec
@testable import J2KCore
@testable import J2KFileFormat

final class MJ2PerformanceValidationTests: XCTestCase {
    // MARK: - Encoding Benchmarks

    func testSingleFrameEncodingTime() async throws {
        let frame = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_single_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let startTime = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: [frame], outputURL: tempURL)
        let elapsed = Date().timeIntervalSince(startTime)

        print("Single frame encoding time: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 10.0, "Single frame encoding should complete within 10 seconds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testMultiFrameEncodingThroughput() async throws {
        let frames = createTestFrames(count: 3, width: 64, height: 64)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_multi_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let startTime = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let elapsed = Date().timeIntervalSince(startTime)

        let fps = Double(frames.count) / elapsed
        print("Multi-frame encoding throughput: \(String(format: "%.2f", fps)) fps")
        print("Total time for \(frames.count) frames: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertGreaterThan(fps, 0.1, "Encoding throughput should be reasonable")
    }

    func testEncodingWithDifferentQualities() async throws {
        let frames = createTestFrames(count: 1, width: 64, height: 64)
        let qualities: [Double] = [0.5, 0.75, 0.95]
        var timings: [Double: Double] = [:]

        for quality in qualities {
            let config = MJ2CreationConfiguration.from(
                frameRate: 24.0, profile: .simple, quality: quality
            )
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf_val_q\(quality)_\(UUID().uuidString).mj2")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let startTime = Date()
            let creator = MJ2Creator(configuration: config)
            try await creator.create(from: frames, outputURL: tempURL)
            let elapsed = Date().timeIntervalSince(startTime)

            timings[quality] = elapsed
            print("Quality \(quality) encoding time: \(String(format: "%.2f", elapsed * 1000)) ms")
        }

        for quality in qualities {
            XCTAssertNotNil(timings[quality], "Should have timing for quality \(quality)")
            XCTAssertLessThan(timings[quality]!, 10.0, "Encoding at quality \(quality) should complete within 10 seconds")
        }
    }

    func testLosslessEncodingTime() async throws {
        let frames = createTestFrames(count: 1, width: 64, height: 64)
        let config = MJ2CreationConfiguration.from(
            frameRate: 24.0, profile: .simple, lossless: true
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_lossless_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let startTime = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let elapsed = Date().timeIntervalSince(startTime)

        print("Lossless encoding time: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 10.0, "Lossless encoding should complete within 10 seconds")
    }

    func testEncodingDifferentResolutions() async throws {
        let resolutions: [(Int, Int)] = [(32, 32), (64, 64), (128, 128)]
        var timings: [(String, Double)] = []

        for (width, height) in resolutions {
            let frames = createTestFrames(count: 1, width: width, height: height)
            let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf_val_res\(width)_\(UUID().uuidString).mj2")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let startTime = Date()
            let creator = MJ2Creator(configuration: config)
            try await creator.create(from: frames, outputURL: tempURL)
            let elapsed = Date().timeIntervalSince(startTime)

            let label = "\(width)x\(height)"
            timings.append((label, elapsed))
            print("Resolution \(label) encoding time: \(String(format: "%.2f", elapsed * 1000)) ms")
        }

        for (label, elapsed) in timings {
            XCTAssertLessThan(elapsed, 15.0, "\(label) encoding should complete within 15 seconds")
        }
    }

    // MARK: - Playback Performance

    func testPlayerInitializationTime() async throws {
        let startTime = Date()
        _ = MJ2Player()
        let elapsed = Date().timeIntervalSince(startTime)

        print("Player initialization time: \(String(format: "%.4f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 1.0, "Player initialization should be nearly instant")
    }

    func testPlayerConfigurationCreation() async throws {
        let startTime = Date()
        for _ in 0..<100 {
            _ = MJ2PlaybackConfiguration(
                maxCacheSize: 30,
                prefetchCount: 5,
                memoryLimit: 256_000_000,
                enablePredictivePrefetch: true,
                timingTolerance: 16.67
            )
        }
        let elapsed = Date().timeIntervalSince(startTime)

        print("100 configuration creations: \(String(format: "%.4f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 1.0, "Configuration creation should be fast")
    }

    func testPlaybackStatisticsAccess() async throws {
        let player = MJ2Player()
        let startTime = Date()
        let stats = await player.getStatistics()
        let elapsed = Date().timeIntervalSince(startTime)

        print("Statistics access time: \(String(format: "%.4f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 1.0, "Statistics access should be fast")
        XCTAssertEqual(stats.framesDecoded, 0, "Initial stats should have zero decoded frames")
    }

    func testCacheConfigurationPerformance() async throws {
        let cacheSizes = [5, 10, 30, 60, 120]
        let startTime = Date()
        for size in cacheSizes {
            _ = MJ2PlaybackConfiguration(
                maxCacheSize: size,
                prefetchCount: size / 5,
                memoryLimit: UInt64(size) * 1_000_000
            )
        }
        let elapsed = Date().timeIntervalSince(startTime)

        print("Cache configuration (\(cacheSizes.count) configs): \(String(format: "%.4f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 1.0, "Cache configuration should be fast")
    }

    // MARK: - Memory Validation

    func testCreationMemoryBaseline() async throws {
        let initialMemory = getMemoryUsage()
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)
        _ = MJ2Creator(configuration: config)
        let finalMemory = getMemoryUsage()

        let memoryDelta = finalMemory > initialMemory ? finalMemory - initialMemory : 0
        print("Creator memory baseline: \(memoryDelta / 1_000) KB")
        if memoryDelta > 0 {
            XCTAssertLessThan(memoryDelta, 10_000_000, "Creator should use less than 10MB")
        }
    }

    func testImageCreationMemory() async throws {
        let initialMemory = getMemoryUsage()
        var images: [J2KImage] = []
        for _ in 0..<10 {
            images.append(J2KImage(width: 64, height: 64, components: 3, bitDepth: 8))
        }
        let finalMemory = getMemoryUsage()

        let memoryDelta = finalMemory > initialMemory ? finalMemory - initialMemory : 0
        print("10 images (64x64) memory: \(memoryDelta / 1_000) KB")
        XCTAssertEqual(images.count, 10, "Should have created 10 images")
        if memoryDelta > 0 {
            XCTAssertLessThan(memoryDelta, 20_000_000, "10 small images should use less than 20MB")
        }
    }

    func testConfigurationMemoryFootprint() async throws {
        let initialMemory = getMemoryUsage()
        var configs: [MJ2CreationConfiguration] = []
        for i in 0..<50 {
            configs.append(
                MJ2CreationConfiguration.from(
                    frameRate: Double(24 + i),
                    profile: .simple,
                    quality: Double(i) / 50.0
                )
            )
        }
        let finalMemory = getMemoryUsage()

        let memoryDelta = finalMemory > initialMemory ? finalMemory - initialMemory : 0
        print("50 configurations memory: \(memoryDelta / 1_000) KB")
        XCTAssertEqual(configs.count, 50, "Should have created 50 configurations")
        if memoryDelta > 0 {
            XCTAssertLessThan(memoryDelta, 5_000_000, "Configurations should be lightweight")
        }
    }

    func testSampleTableBuilderMemory() async throws {
        let initialMemory = getMemoryUsage()
        let builder = MJ2SampleTableBuilder(defaultDuration: 1000, use64BitOffsets: false)
        for i in 0..<100 {
            await builder.addSample(
                size: UInt32(1024 + i),
                offset: UInt64(i * 1024),
                isSync: i % 10 == 0
            )
        }
        let count = await builder.sampleCount
        let finalMemory = getMemoryUsage()

        let memoryDelta = finalMemory > initialMemory ? finalMemory - initialMemory : 0
        print("Sample table builder (100 samples) memory: \(memoryDelta / 1_000) KB")
        XCTAssertEqual(count, 100, "Should have added 100 samples")
        if memoryDelta > 0 {
            XCTAssertLessThan(memoryDelta, 5_000_000, "Sample table should be memory efficient")
        }
    }

    // MARK: - I/O Performance

    func testFileWriteAndReadBack() async throws {
        let frames = createTestFrames(count: 3, width: 64, height: 64)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_io_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write
        let writeStart = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let writeElapsed = Date().timeIntervalSince(writeStart)

        // Read back
        let readStart = Date()
        let reader = MJ2FileReader()
        let data = try Data(contentsOf: tempURL)
        _ = try await reader.readFileInfo(from: data)
        let readElapsed = Date().timeIntervalSince(readStart)

        print("Write time: \(String(format: "%.2f", writeElapsed * 1000)) ms")
        print("Read time: \(String(format: "%.2f", readElapsed * 1000)) ms")
        XCTAssertLessThan(readElapsed, writeElapsed * 5, "Reading should not be drastically slower than writing")
    }

    func testFormatDetectionSpeed() async throws {
        let frames = createTestFrames(count: 1, width: 32, height: 32)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_detect_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let data = try Data(contentsOf: tempURL)

        let detector = MJ2FormatDetector()
        let startTime = Date()
        let isMJ2 = try detector.isMJ2File(data: data)
        let elapsed = Date().timeIntervalSince(startTime)

        print("Format detection time: \(String(format: "%.4f", elapsed * 1000)) ms")
        XCTAssertTrue(isMJ2, "Should detect valid MJ2 file")
        XCTAssertLessThan(elapsed, 1.0, "Format detection should be very fast")
    }

    func testFileInfoReadingSpeed() async throws {
        let frames = createTestFrames(count: 3, width: 64, height: 64)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_info_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let creator = MJ2Creator(configuration: config)
        try await creator.create(from: frames, outputURL: tempURL)
        let data = try Data(contentsOf: tempURL)

        let reader = MJ2FileReader()
        let startTime = Date()
        let info = try await reader.readFileInfo(from: data)
        let elapsed = Date().timeIntervalSince(startTime)

        print("File info reading time: \(String(format: "%.4f", elapsed * 1000)) ms")
        print("Tracks found: \(info.tracks.count)")
        XCTAssertLessThan(elapsed, 2.0, "File info reading should be fast")
    }

    // MARK: - Cross-Platform Validation

    func testPlatformCapabilitiesDetection() async throws {
        let startTime = Date()
        let platform = MJ2PlatformCapabilities.currentPlatform
        let hasVideoToolbox = MJ2PlatformCapabilities.hasVideoToolbox
        let hasMetal = MJ2PlatformCapabilities.hasMetal
        let architecture = MJ2PlatformCapabilities.architecture
        let elapsed = Date().timeIntervalSince(startTime)

        print("Platform detection time: \(String(format: "%.4f", elapsed * 1000)) ms")
        print("Platform: \(platform), VideoToolbox: \(hasVideoToolbox), Metal: \(hasMetal), Arch: \(architecture)")
        XCTAssertLessThan(elapsed, 1.0, "Platform detection should be nearly instant")
        XCTAssertFalse(architecture.isEmpty, "Architecture should be detected")
    }

    func testEncoderFactoryCreation() async throws {
        let startTime = Date()
        let encoders = MJ2EncoderFactory.detectAvailableEncoders()
        let elapsed = Date().timeIntervalSince(startTime)

        print("Encoder factory detection time: \(String(format: "%.4f", elapsed * 1000)) ms")
        print("Available encoders: \(encoders.count)")
        XCTAssertLessThan(elapsed, 2.0, "Encoder detection should be fast")
    }

    func testSoftwareEncoderStartup() async throws {
        let config = MJ2SoftwareEncoderConfiguration.h264Default

        let startTime = Date()
        let encoder = MJ2SoftwareEncoder(configuration: config)
        try await encoder.startEncoding()
        let elapsed = Date().timeIntervalSince(startTime)

        print("Software encoder startup time: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 5.0, "Software encoder startup should be fast")

        await encoder.cancelEncoding()
    }

    // MARK: - Scalability

    func testFrameCountScaling() async throws {
        let frameCounts = [1, 3, 5]
        var timings: [(Int, Double)] = []

        for count in frameCounts {
            let frames = createTestFrames(count: count, width: 32, height: 32)
            let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf_val_scale\(count)_\(UUID().uuidString).mj2")
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let startTime = Date()
            let creator = MJ2Creator(configuration: config)
            try await creator.create(from: frames, outputURL: tempURL)
            let elapsed = Date().timeIntervalSince(startTime)

            timings.append((count, elapsed))
            print("\(count) frame(s) encoding time: \(String(format: "%.2f", elapsed * 1000)) ms")
        }

        for (count, elapsed) in timings {
            XCTAssertLessThan(elapsed, 30.0, "Encoding \(count) frames should complete within 30 seconds")
        }
    }

    func testRepeatedImageCreationPerformance() async throws {
        let image = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        let config = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_repeated_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let startTime = Date()
        let creator = MJ2Creator(configuration: config)
        try await creator.createRepeated(
            image: image,
            frameCount: 5,
            outputURL: tempURL
        )
        let elapsed = Date().timeIntervalSince(startTime)

        print("createRepeated (5 frames) time: \(String(format: "%.2f", elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 30.0, "createRepeated should complete within 30 seconds")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testParallelVsSequentialCreation() async throws {
        let frames = createTestFrames(count: 3, width: 64, height: 64)
        let baseConfig = MJ2CreationConfiguration.from(frameRate: 24.0, profile: .simple)

        // Sequential
        let seqConfig = MJ2CreationConfiguration(
            profile: baseConfig.profile,
            timescale: baseConfig.timescale,
            encodingConfiguration: baseConfig.encodingConfiguration,
            metadata: baseConfig.metadata,
            audioTrack: baseConfig.audioTrack,
            use64BitOffsets: baseConfig.use64BitOffsets,
            maxFrameBufferCount: baseConfig.maxFrameBufferCount,
            enableParallelEncoding: false,
            parallelEncodingCount: 1
        )

        let seqURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_val_seq_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: seqURL) }

        let seqStart = Date()
        let seqCreator = MJ2Creator(configuration: seqConfig)
        try await seqCreator.create(from: frames, outputURL: seqURL)
        let seqTime = Date().timeIntervalSince(seqStart)

        // Parallel
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
            .appendingPathComponent("perf_val_par_\(UUID().uuidString).mj2")
        defer { try? FileManager.default.removeItem(at: parURL) }

        let parStart = Date()
        let parCreator = MJ2Creator(configuration: parConfig)
        try await parCreator.create(from: frames, outputURL: parURL)
        let parTime = Date().timeIntervalSince(parStart)

        let ratio = seqTime / parTime
        print("Sequential time: \(String(format: "%.2f", seqTime * 1000)) ms")
        print("Parallel time: \(String(format: "%.2f", parTime * 1000)) ms")
        print("Speedup ratio: \(String(format: "%.2f", ratio))x")
        XCTAssertGreaterThan(ratio, 0.5, "Parallel encoding should not be drastically slower")
    }

    // MARK: - Helper Methods

    /// Creates test frames for benchmarking.
    private func createTestFrames(count: Int, width: Int, height: Int) -> [J2KImage] {
        (0..<count).map { _ in
            J2KImage(width: width, height: height, components: 3, bitDepth: 8)
        }
    }

    /// Gets current memory usage in bytes.
    private func getMemoryUsage() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
        #else
        return 0
        #endif
    }
}
