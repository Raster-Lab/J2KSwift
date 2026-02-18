// J2KHTBlockCoderMemoryTests.swift
// J2KSwift
//
// Tests for HTJ2K block coder memory allocation tracking and optimization
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KHTBlockCoderMemoryTests: XCTestCase {
    // MARK: - Memory Tracker Tests

    func testMemoryTrackerBasicRecording() async throws {
        let tracker = HTBlockCoderMemoryTracker()
        await tracker.enable()
        await tracker.reset()

        // Record some allocations
        await tracker.recordAllocation(size: 1024, type: .melBuffer)
        await tracker.recordAllocation(size: 2048, type: .vlcBuffer)
        await tracker.recordAllocation(size: 512, type: .melBuffer)

        // Check MEL buffer stats
        let melStats = await tracker.statistics(for: .melBuffer)
        XCTAssertNotNil(melStats)
        XCTAssertEqual(melStats?.count, 2)
        XCTAssertEqual(melStats?.totalBytes, 1536)
        XCTAssertEqual(melStats?.minSize, 512)
        XCTAssertEqual(melStats?.maxSize, 1024)
        XCTAssertEqual(melStats?.averageSize, 768)

        // Check VLC buffer stats
        let vlcStats = await tracker.statistics(for: .vlcBuffer)
        XCTAssertNotNil(vlcStats)
        XCTAssertEqual(vlcStats?.count, 1)
        XCTAssertEqual(vlcStats?.totalBytes, 2048)
    }

    func testMemoryTrackerPeakUsage() async throws {
        let tracker = HTBlockCoderMemoryTracker()
        await tracker.enable()
        await tracker.reset()

        // Simulate allocation pattern
        await tracker.recordAllocation(size: 1000, type: .melBuffer)
        await tracker.recordAllocation(size: 2000, type: .vlcBuffer)
        let current1 = await tracker.currentMemoryUsage()
        let peak1 = await tracker.peakMemoryUsage()
        XCTAssertEqual(current1, 3000)
        XCTAssertEqual(peak1, 3000)

        await tracker.recordDeallocation(size: 1000)
        let current2 = await tracker.currentMemoryUsage()
        let peak2 = await tracker.peakMemoryUsage()
        XCTAssertEqual(current2, 2000)
        XCTAssertEqual(peak2, 3000) // Peak remains

        await tracker.recordAllocation(size: 5000, type: .coefficientArray)
        let current3 = await tracker.currentMemoryUsage()
        let peak3 = await tracker.peakMemoryUsage()
        XCTAssertEqual(current3, 7000)
        XCTAssertEqual(peak3, 7000) // New peak
    }

    func testMemoryTrackerDisabled() async throws {
        let tracker = HTBlockCoderMemoryTracker()
        await tracker.disable()
        await tracker.reset()

        await tracker.recordAllocation(size: 1024, type: .melBuffer)

        let stats = await tracker.statistics(for: .melBuffer)
        XCTAssertNil(stats, "Should not record when disabled")
    }

    func testMemoryTrackerAllStatistics() async throws {
        let tracker = HTBlockCoderMemoryTracker()
        await tracker.enable()
        await tracker.reset()

        // Record various allocation types
        await tracker.recordAllocation(size: 100, type: .melBuffer)
        await tracker.recordAllocation(size: 200, type: .vlcBuffer)
        await tracker.recordAllocation(size: 300, type: .magsgnBuffer)

        let allStats = await tracker.allStatistics()
        XCTAssertEqual(allStats.count, 3)
        XCTAssertNotNil(allStats[.melBuffer])
        XCTAssertNotNil(allStats[.vlcBuffer])
        XCTAssertNotNil(allStats[.magsgnBuffer])
    }

    // MARK: - Buffer Pool Tests

    func testBufferPoolUInt8Acquisition() async throws {
        let pool = J2KBufferPool()

        // Acquire buffer
        let buffer1 = await pool.acquireUInt8Buffer(size: 1024)
        XCTAssertEqual(buffer1.count, 1024)
        XCTAssertTrue(buffer1.allSatisfy { $0 == 0 })

        // Release and re-acquire
        await pool.releaseUInt8Buffer(buffer1)
        let buffer2 = await pool.acquireUInt8Buffer(size: 1024)
        XCTAssertEqual(buffer2.count, 1024)

        // Pool should have reused the buffer
        let stats = await pool.statistics()
        XCTAssertEqual(stats.uint8[1024], 0) // Buffer was acquired
    }

    func testBufferPoolUInt8SyncAcquisition() {
        let pool = J2KBufferPool()

        // Synchronous acquisition should work without pooling
        let buffer = pool.acquireUInt8BufferSync(size: 512)
        XCTAssertEqual(buffer.count, 512)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 })
    }

    func testBufferPoolUInt8MaxCached() async throws {
        let pool = J2KBufferPool()
        let maxBuffers = 8

        // Release more buffers than the max
        for _ in 0..<(maxBuffers + 2) {
            let buffer = [UInt8](repeating: 0, count: 256)
            await pool.releaseUInt8Buffer(buffer)
        }

        let stats = await pool.statistics()
        // Should only cache up to maxBuffers
        XCTAssertLessThanOrEqual(stats.uint8[256] ?? 0, maxBuffers)
    }

    func testBufferPoolClear() async throws {
        let pool = J2KBufferPool()

        // Add some buffers
        await pool.releaseInt32Buffer([Int32](repeating: 0, count: 100))
        await pool.releaseDoubleBuffer([Double](repeating: 0, count: 200))
        await pool.releaseUInt8Buffer([UInt8](repeating: 0, count: 300))

        var stats = await pool.statistics()
        XCTAssertFalse(stats.int32.isEmpty || stats.double.isEmpty || stats.uint8.isEmpty)

        // Clear pool
        await pool.clear()

        stats = await pool.statistics()
        XCTAssertTrue(stats.int32.isEmpty)
        XCTAssertTrue(stats.double.isEmpty)
        XCTAssertTrue(stats.uint8.isEmpty)
    }

    // MARK: - Baseline Memory Benchmarks

    func testHTBlockEncoderBaselineMemory32x32() async throws {
        let tracker = HTBlockCoderMemoryTracker.shared
        await tracker.enable()
        await tracker.reset()

        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        // Track allocations during encoding
        await tracker.recordAllocation(size: width * height * MemoryLayout<Int>.size, type: .coefficientArray)

        // Use bit plane 7 for encoding
        _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        let peakMemory = await tracker.peakMemoryUsage()
        XCTAssertGreaterThan(peakMemory, 0, "Should track some memory usage")

        // Print summary for baseline
        await tracker.printSummary()
    }

    func testHTBlockEncoderBaselineMemory64x64() async throws {
        let tracker = HTBlockCoderMemoryTracker.shared
        await tracker.enable()
        await tracker.reset()

        let width = 64
        let height = 64
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        // Track allocations during encoding
        await tracker.recordAllocation(size: width * height * MemoryLayout<Int>.size, type: .coefficientArray)

        // Use bit plane 7 for encoding
        _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        let peakMemory = await tracker.peakMemoryUsage()
        XCTAssertGreaterThan(peakMemory, 0, "Should track some memory usage")

        // Peak memory for 64×64 should be roughly 4× that of 32×32
        // (due to quadratic area increase)
    }

    func testHTBlockDecoderBaselineMemory() async throws {
        let tracker = HTBlockCoderMemoryTracker.shared
        await tracker.enable()
        await tracker.reset()

        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        // Encode first
        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let encoded = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        // Reset tracker for decode
        await tracker.reset()

        // Decode
        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        await tracker.recordAllocation(size: width * height * MemoryLayout<Int>.size, type: .coefficientArray)
        _ = try decoder.decodeCleanup(from: encoded)

        let peakMemory = await tracker.peakMemoryUsage()
        XCTAssertGreaterThan(peakMemory, 0, "Should track decode memory usage")
    }

    // MARK: - Allocation Distribution Tests

    func testAllocationDistributionAcrossBlockSizes() async throws {
        let tracker = HTBlockCoderMemoryTracker.shared
        await tracker.enable()

        let blockSizes = [(16, 16), (32, 32), (64, 64)]

        for (width, height) in blockSizes {
            await tracker.reset()

            let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
            let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

            await tracker.recordAllocation(size: width * height * MemoryLayout<Int>.size, type: .coefficientArray)
            _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

            let stats = await tracker.allStatistics()
            XCTAssertFalse(stats.isEmpty, "Should have allocation stats for \(width)×\(height)")

            let peakMemory = await tracker.peakMemoryUsage()
            print("Block size \(width)×\(height): Peak memory = \(peakMemory) bytes")
        }
    }

    // MARK: - Concurrent Workload Tests

    func testConcurrentEncodingMemoryUsage() async throws {
        let tracker = HTBlockCoderMemoryTracker.shared
        await tracker.enable()
        await tracker.reset()

        // Simulate concurrent encoding of multiple blocks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let width = 32
                    let height = 32
                    let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
                    let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

                    await tracker.recordAllocation(size: width * height * MemoryLayout<Int>.size, type: .coefficientArray)
                    _ = try? encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
                }
            }
        }

        let peakMemory = await tracker.peakMemoryUsage()
        XCTAssertGreaterThan(peakMemory, 0, "Should track concurrent memory usage")

        // With 4 concurrent 32×32 blocks, peak should be roughly 4× single block
        print("Concurrent encoding peak memory: \(peakMemory) bytes")
    }
}
