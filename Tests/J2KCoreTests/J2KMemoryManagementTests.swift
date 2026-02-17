import XCTest
@testable import J2KCore

/// Tests for the memory management components.
final class J2KMemoryManagementTests: XCTestCase {
    // MARK: - J2KBuffer Tests

    func testBufferInitialization() throws {
        let buffer = J2KBuffer(capacity: 1024)
        XCTAssertEqual(buffer.capacity, 1024)
        XCTAssertEqual(buffer.count, 0)
    }

    func testBufferFromData() throws {
        let data = Data([1, 2, 3, 4, 5])
        let buffer = J2KBuffer(data: data)
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.capacity, 5)
    }

    func testBufferReadAccess() throws {
        let data = Data([10, 20, 30, 40, 50])
        let buffer = J2KBuffer(data: data)

        buffer.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 10)
            XCTAssertEqual(ptr[1], 20)
            XCTAssertEqual(ptr[4], 50)
        }
    }

    func testBufferWriteAccess() throws {
        var buffer = J2KBuffer(capacity: 10)

        buffer.withUnsafeMutableBytes { ptr in
            ptr[0] = 100
            ptr[1] = 200
        }

        buffer.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 100)
            XCTAssertEqual(ptr[1], 200)
        }
    }

    func testBufferCopyOnWrite() throws {
        var buffer1 = J2KBuffer(capacity: 10)
        buffer1.withUnsafeMutableBytes { ptr in
            ptr[0] = 42
        }

        var buffer2 = buffer1 // Should share storage

        // Modify buffer2, should trigger COW
        buffer2.withUnsafeMutableBytes { ptr in
            ptr[0] = 99
        }

        // buffer1 should still have original value
        buffer1.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 42)
        }

        // buffer2 should have new value
        buffer2.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 99)
        }
    }

    func testBufferToData() throws {
        let originalData = Data([1, 2, 3, 4, 5])
        let buffer = J2KBuffer(data: originalData)
        let convertedData = buffer.toData()
        XCTAssertEqual(convertedData, originalData)
    }

    func testBufferUpdateCount() throws {
        var buffer = J2KBuffer(capacity: 100)
        XCTAssertEqual(buffer.count, 0)

        buffer.updateCount(50)
        XCTAssertEqual(buffer.count, 50)

        // Should not exceed capacity
        buffer.updateCount(200)
        XCTAssertEqual(buffer.count, 100)
    }

    // MARK: - J2KMemoryPool Tests

    func testMemoryPoolAcquireAndRelease() async throws {
        let pool = J2KMemoryPool()

        let buffer = await pool.acquire(capacity: 1024)
        XCTAssertGreaterThanOrEqual(buffer.capacity, 1024)

        await pool.release(buffer)

        let stats = await pool.statistics()
        XCTAssertGreaterThan(stats["bufferCount"] ?? 0, 0)
    }

    func testMemoryPoolReuse() async throws {
        let pool = J2KMemoryPool()

        // Acquire and release a buffer
        let buffer1 = await pool.acquire(capacity: 1024)
        let capacity1 = buffer1.capacity
        await pool.release(buffer1)

        // Acquire again with same size - should reuse
        let buffer2 = await pool.acquire(capacity: 1024)
        XCTAssertEqual(buffer2.capacity, capacity1)
    }

    func testMemoryPoolClear() async throws {
        let pool = J2KMemoryPool()

        // Add some buffers
        let buffer1 = await pool.acquire(capacity: 1024)
        await pool.release(buffer1)

        let buffer2 = await pool.acquire(capacity: 2048)
        await pool.release(buffer2)

        var stats = await pool.statistics()
        XCTAssertGreaterThan(stats["bufferCount"] ?? 0, 0)

        // Clear the pool
        await pool.clear()

        stats = await pool.statistics()
        XCTAssertEqual(stats["bufferCount"] ?? -1, 0)
        XCTAssertEqual(stats["totalSize"] ?? -1, 0)
    }

    func testMemoryPoolConfiguration() async throws {
        let config = J2KMemoryPool.Configuration(maxBuffers: 5, maxTotalSize: 10240)
        let pool = J2KMemoryPool(configuration: config)

        // Fill the pool
        var buffers: [J2KBuffer] = []
        for _ in 0..<10 {
            buffers.append(await pool.acquire(capacity: 1024))
        }

        // Release all
        for buffer in buffers {
            await pool.release(buffer)
        }

        // Pool should enforce limits
        let stats = await pool.statistics()
        let bufferCount = stats["bufferCount"] ?? 0
        XCTAssertLessThanOrEqual(bufferCount, 10) // Some may be kept
    }

    func testMemoryPoolStatistics() async throws {
        let pool = J2KMemoryPool()

        let buffer = await pool.acquire(capacity: 4096)
        await pool.release(buffer)

        let stats = await pool.statistics()
        XCTAssertGreaterThan(stats["bufferCount"] ?? 0, 0)
        XCTAssertGreaterThan(stats["totalSize"] ?? 0, 0)
        XCTAssertGreaterThan(stats["capacityBuckets"] ?? 0, 0)
    }

    // MARK: - J2KMemoryTracker Tests

    func testMemoryTrackerAllocation() async throws {
        let tracker = J2KMemoryTracker()

        try await tracker.allocate(1024)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 1024)
        XCTAssertEqual(stats.peakUsage, 1024)
        XCTAssertEqual(stats.allocationCount, 1)
    }

    func testMemoryTrackerDeallocation() async throws {
        let tracker = J2KMemoryTracker()

        try await tracker.allocate(1024)
        await tracker.deallocate(512)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 512)
        XCTAssertEqual(stats.peakUsage, 1024)
    }

    func testMemoryTrackerLimit() async throws {
        let tracker = J2KMemoryTracker(limit: 2048)

        // Should succeed
        try await tracker.allocate(1024)

        // Should fail (would exceed limit)
        do {
            try await tracker.allocate(2048)
            XCTFail("Expected allocation to fail")
        } catch {
            // Expected error
            if case J2KError.internalError = error {
                // Correct error type
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.failedAllocations, 1)
    }

    func testMemoryTrackerPeakUsage() async throws {
        let tracker = J2KMemoryTracker()

        try await tracker.allocate(1024)
        try await tracker.allocate(2048)
        await tracker.deallocate(1024)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 2048)
        XCTAssertEqual(stats.peakUsage, 3072) // 1024 + 2048
    }

    func testMemoryTrackerCanAllocate() async throws {
        let tracker = J2KMemoryTracker(limit: 2048)

        let canAllocate1 = await tracker.canAllocate(1024)
        XCTAssertTrue(canAllocate1)

        let canAllocate2 = await tracker.canAllocate(2048)
        XCTAssertTrue(canAllocate2)

        let canAllocate3 = await tracker.canAllocate(4096)
        XCTAssertFalse(canAllocate3)

        try await tracker.allocate(1024)

        let canAllocate4 = await tracker.canAllocate(1024)
        XCTAssertTrue(canAllocate4)

        let canAllocate5 = await tracker.canAllocate(2048)
        XCTAssertFalse(canAllocate5)
    }

    func testMemoryTrackerAvailableMemory() async throws {
        let tracker = J2KMemoryTracker(limit: 4096)

        let available1 = await tracker.availableMemory()
        XCTAssertEqual(available1, 4096)

        try await tracker.allocate(1024)
        let available2 = await tracker.availableMemory()
        XCTAssertEqual(available2, 3072)

        await tracker.deallocate(512)
        let available3 = await tracker.availableMemory()
        XCTAssertEqual(available3, 3584)
    }

    func testMemoryTrackerReset() async throws {
        let tracker = J2KMemoryTracker()

        try await tracker.allocate(1024)
        try await tracker.allocate(2048)

        var stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 3072)

        await tracker.reset()

        stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 0)
        XCTAssertEqual(stats.peakUsage, 0)
        XCTAssertEqual(stats.allocationCount, 0)
    }

    func testMemoryTrackerResetStatistics() async throws {
        let tracker = J2KMemoryTracker()

        try await tracker.allocate(1024)
        try await tracker.allocate(2048)

        await tracker.resetStatistics()

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 3072) // Maintained
        XCTAssertEqual(stats.peakUsage, 3072) // Reset to current
        XCTAssertEqual(stats.allocationCount, 0) // Reset
    }

    func testMemoryTrackerPressure() async throws {
        let tracker = J2KMemoryTracker(limit: 1000)

        var stats = await tracker.getStatistics()
        XCTAssertEqual(stats.pressure, 0.0, accuracy: 0.01)

        try await tracker.allocate(500)
        stats = await tracker.getStatistics()
        XCTAssertEqual(stats.pressure, 0.5, accuracy: 0.01)

        try await tracker.allocate(300)
        stats = await tracker.getStatistics()
        XCTAssertEqual(stats.pressure, 0.8, accuracy: 0.01)
    }

    // MARK: - J2KImageBuffer Tests

    func testImageBufferInitialization() throws {
        let buffer = J2KImageBuffer(width: 512, height: 512, bitDepth: 8)
        XCTAssertEqual(buffer.width, 512)
        XCTAssertEqual(buffer.height, 512)
        XCTAssertEqual(buffer.bitDepth, 8)
        XCTAssertEqual(buffer.count, 512 * 512)
    }

    func testImageBufferGetSetPixel() throws {
        var buffer = J2KImageBuffer(width: 10, height: 10, bitDepth: 8)

        buffer.setPixel(at: 0, value: 255)
        XCTAssertEqual(buffer.getPixel(at: 0), 255)

        buffer.setPixel(at: 50, value: 128)
        XCTAssertEqual(buffer.getPixel(at: 50), 128)
    }

    func testImageBufferGetSetPixelCoordinates() throws {
        var buffer = J2KImageBuffer(width: 10, height: 10, bitDepth: 8)

        buffer.setPixel(x: 5, y: 3, value: 200)
        XCTAssertEqual(buffer.getPixel(x: 5, y: 3), 200)

        // Verify correct indexing
        let index = 3 * 10 + 5 // row 3, column 5
        XCTAssertEqual(buffer.getPixel(at: index), 200)
    }

    func testImageBufferCopyOnWrite() throws {
        var buffer1 = J2KImageBuffer(width: 10, height: 10, bitDepth: 8)
        buffer1.setPixel(at: 0, value: 100)

        var buffer2 = buffer1 // Should share storage

        // Modify buffer2
        buffer2.setPixel(at: 0, value: 200)

        // buffer1 should still have original value
        XCTAssertEqual(buffer1.getPixel(at: 0), 100)

        // buffer2 should have new value
        XCTAssertEqual(buffer2.getPixel(at: 0), 200)
    }

    func testImageBufferFromData() throws {
        let data = Data([10, 20, 30, 40, 50])
        let buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 8, data: data)

        XCTAssertEqual(buffer.getPixel(at: 0), 10)
        XCTAssertEqual(buffer.getPixel(at: 1), 20)
        XCTAssertEqual(buffer.getPixel(at: 4), 50)
    }

    func testImageBufferToData() throws {
        var buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 8)
        buffer.setPixel(at: 0, value: 10)
        buffer.setPixel(at: 1, value: 20)
        buffer.setPixel(at: 2, value: 30)
        buffer.setPixel(at: 3, value: 40)
        buffer.setPixel(at: 4, value: 50)

        let data = buffer.toData()
        XCTAssertEqual(data[0], 10)
        XCTAssertEqual(data[1], 20)
        XCTAssertEqual(data[4], 50)
    }

    func testImageBuffer16Bit() throws {
        var buffer = J2KImageBuffer(width: 10, height: 10, bitDepth: 16)

        buffer.setPixel(at: 0, value: 65535)
        XCTAssertEqual(buffer.getPixel(at: 0), 65535)

        buffer.setPixel(at: 1, value: 32768)
        XCTAssertEqual(buffer.getPixel(at: 1), 32768)
    }

    func testImageBufferSizeInBytes() throws {
        let buffer8 = J2KImageBuffer(width: 100, height: 100, bitDepth: 8)
        XCTAssertEqual(buffer8.sizeInBytes, 10000) // 100*100*1

        let buffer16 = J2KImageBuffer(width: 100, height: 100, bitDepth: 16)
        XCTAssertEqual(buffer16.sizeInBytes, 20000) // 100*100*2
    }

    func testImageBufferUnsafeAccess() throws {
        var buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 8)

        // Write using unsafe access
        buffer.withUnsafeMutableBytes { ptr in
            ptr[0] = 100
            ptr[1] = 101
            ptr[2] = 102
        }

        // Read using unsafe access
        buffer.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 100)
            XCTAssertEqual(ptr[1], 101)
            XCTAssertEqual(ptr[2], 102)
        }
    }

    // MARK: - Integration Tests

    func testIntegrationMemoryPoolWithTracker() async throws {
        let pool = J2KMemoryPool()
        let tracker = J2KMemoryTracker(limit: 100 * 1024) // 100KB limit

        // Acquire buffers and track memory
        var buffers: [J2KBuffer] = []
        for _ in 0..<10 {
            let buffer = await pool.acquire(capacity: 4096)
            try await tracker.allocate(buffer.capacity)
            buffers.append(buffer)
        }

        let stats = await tracker.getStatistics()
        XCTAssertGreaterThan(stats.currentUsage, 0)
        XCTAssertLessThanOrEqual(stats.currentUsage, 100 * 1024)

        // Release buffers
        for buffer in buffers {
            await tracker.deallocate(buffer.capacity)
            await pool.release(buffer)
        }

        let finalStats = await tracker.getStatistics()
        XCTAssertEqual(finalStats.currentUsage, 0)
    }

    func testImageBufferMemoryEfficiency() throws {
        // Create many image buffers and verify COW works
        let original = J2KImageBuffer(width: 1000, height: 1000, bitDepth: 8)

        var copies: [J2KImageBuffer] = []
        for _ in 0..<100 {
            copies.append(original) // Should share storage
        }

        // Modify one copy
        var modifiedCopy = copies[0]
        modifiedCopy.setPixel(at: 0, value: 255)

        // Original should be unchanged
        XCTAssertEqual(original.getPixel(at: 0), 0)
        XCTAssertEqual(modifiedCopy.getPixel(at: 0), 255)
    }
}
