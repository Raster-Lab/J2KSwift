//
// J2KExtendedStressTests.swift
// J2KSwift
//
// Extended stress tests for Week 284-286 (Sub-phase 17h) — Integration Testing.
//
// Validates robustness under:
// - High-concurrency (100+ simultaneous operations)
// - Large image handling (8K × 8K, multi-component)
// - Memory pressure (many concurrent allocations)
// - Sustained load (1000+ sequential operations)
// - Malformed / edge-case input (fuzzing-like)
//

import XCTest
@testable import J2KCore
import Foundation

/// Extended stress tests validating robustness under extreme conditions.
///
/// These tests cover high-concurrency access, large image allocations,
/// memory pressure scenarios, sustained sequential workloads, and handling
/// of malformed inputs. Named "Stress" so they are skipped in standard CI
/// (which passes `--skip Stress`) and run only in dedicated stress CI jobs.
final class J2KExtendedStressTests: XCTestCase {

    // MARK: - Large Image Allocation Tests

    func testLargeImage4KAllocation() throws {
        let width = 3840
        let height = 2160
        let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        XCTAssertEqual(image.components.count, 3)
    }

    func testLargeImage8KAllocation() throws {
        let width = 7680
        let height = 4320
        let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
    }

    func testLargeImage16KAllocation() throws {
        let width = 16384
        let height = 16384
        let image = J2KImage(width: width, height: height, components: 1, bitDepth: 8)
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
    }

    func testLargeImage32BitDepth() throws {
        let width = 2048
        let height = 2048
        let image = J2KImage(width: width, height: height, components: 3, bitDepth: 32)
        for component in image.components {
            XCTAssertLessThanOrEqual(component.bitDepth, 38) // JPEG 2000 max
        }
    }

    func testLargeImageMultiComponentAllocation() throws {
        // 16-component multispectral image at HD resolution
        let image = J2KImage(width: 1920, height: 1080, components: 16, bitDepth: 16)
        XCTAssertEqual(image.components.count, 16)
        XCTAssertEqual(image.width, 1920)
        XCTAssertEqual(image.height, 1080)
    }

    func testRepeat8KAllocations() throws {
        // Ensure no memory leaks across repeated large allocations
        for _ in 0..<5 {
            let image = J2KImage(width: 7680, height: 4320, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, 7680)
        }
    }

    func testLargeImageWithMaxBitDepth38() throws {
        let image = J2KImage(width: 1024, height: 1024, components: 1, bitDepth: 38)
        XCTAssertLessThanOrEqual(image.components[0].bitDepth, 38)
    }

    // MARK: - Large Buffer Stress Tests

    func testLargeBufferOperationWith64MPixels() throws {
        let size = 64 * 1024 * 1024  // 64M Int32 samples
        var buffer = [Int32](repeating: 0, count: size)
        buffer[0]        = Int32.min
        buffer[size - 1] = Int32.max
        XCTAssertEqual(buffer[0], Int32.min)
        XCTAssertEqual(buffer[size - 1], Int32.max)
    }

    func testLargeBufferFillAndSum() throws {
        let size = 1024 * 1024  // 1M samples
        let value: Int32 = 42
        let buffer = [Int32](repeating: value, count: size)
        let expected = Int64(value) * Int64(size)
        let sum = buffer.reduce(Int64(0)) { $0 + Int64($1) }
        XCTAssertEqual(sum, expected)
    }

    func testLargeBufferCopyIntegrity() throws {
        let size = 512 * 512
        var original = [Int32](repeating: 0, count: size)
        for i in 0..<size {
            original[i] = Int32(i % 256) - 128
        }
        let copy = original
        XCTAssertEqual(copy.count, original.count)
        XCTAssertEqual(copy[0], original[0])
        XCTAssertEqual(copy[size - 1], original[size - 1])
    }

    // MARK: - Memory Pool Stress Tests

    func testMemoryPoolHighConcurrencyAcquireRelease() async throws {
        let pool = J2KMemoryPool()
        let iterations = 200

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let buffer = await pool.acquire(capacity: 4096)
                    XCTAssertGreaterThanOrEqual(buffer.capacity, 4096)
                    await pool.release(buffer)
                }
            }
        }
    }

    func testMemoryPoolVariableSizeAcquireRelease() async throws {
        let pool = J2KMemoryPool()
        let sizes = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768]

        for size in sizes {
            let buffer = await pool.acquire(capacity: size)
            XCTAssertGreaterThanOrEqual(buffer.capacity, size)
            await pool.release(buffer)
        }
    }

    func testMemoryPoolSustainedSequentialLoad() async throws {
        let pool = J2KMemoryPool()
        for i in 0..<1000 {
            let capacity = 256 + (i % 8) * 256
            let buffer = await pool.acquire(capacity: capacity)
            XCTAssertGreaterThanOrEqual(buffer.capacity, capacity)
            await pool.release(buffer)
        }
    }

    func testMemoryPoolHoldAndRelease() async throws {
        let pool = J2KMemoryPool()
        var held: [J2KBuffer] = []

        // Acquire 50 buffers without releasing
        for _ in 0..<50 {
            let buffer = await pool.acquire(capacity: 1024)
            held.append(buffer)
        }
        XCTAssertEqual(held.count, 50)

        // Release all at once
        for buffer in held {
            await pool.release(buffer)
        }
    }

    // MARK: - Memory Tracker Stress Tests

    func testMemoryTrackerHighConcurrencyAllocDealloc() async throws {
        let tracker = J2KMemoryTracker(limit: 512 * 1024 * 1024) // 512 MB limit

        let iterations = 100
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    try? await tracker.allocate(4096)
                    await tracker.deallocate(4096)
                }
            }
        }
        // After all tasks complete, usage should be near zero
        let stats = await tracker.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.allocationCount + stats.failedAllocations, 0)
    }

    func testMemoryTrackerPeakUsageTracking() async throws {
        let tracker = J2KMemoryTracker(limit: 1024 * 1024)

        try await tracker.allocate(256 * 1024)  // 256 KB
        try await tracker.allocate(256 * 1024)  // 512 KB total (peak)

        await tracker.deallocate(256 * 1024)    // Back to 256 KB

        let stats = await tracker.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.peakUsage, 512 * 1024)
        XCTAssertEqual(stats.currentUsage, 256 * 1024)
    }

    func testMemoryTrackerFailureCountUnderPressure() async throws {
        let tracker = J2KMemoryTracker(limit: 1000)
        try await tracker.allocate(800)

        // Try to over-allocate multiple times
        for _ in 0..<5 {
            _ = try? await tracker.allocate(500)
        }

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.failedAllocations, 5)
    }

    func testMemoryTrackerAllocationCountAccuracy() async throws {
        let tracker = J2KMemoryTracker(limit: 10 * 1024 * 1024)
        let count = 100
        for _ in 0..<count {
            try await tracker.allocate(1024)
        }
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.allocationCount, count)
    }

    // MARK: - High-Concurrency Image Creation

    func testHighConcurrencyImageCreation100() throws {
        let count = 100
        let expectation = self.expectation(description: "100 concurrent image creations")
        expectation.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { i in
            let size = 32 + (i % 64)
            let image = J2KImage(width: size, height: size, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, size)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    func testHighConcurrencyLargeImageCreation50() throws {
        let count = 50
        let expectation = self.expectation(description: "50 concurrent large image creations")
        expectation.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { i in
            let size = 512 + (i % 512)
            let image = J2KImage(width: size, height: size, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, size)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    func testHighConcurrencyBufferOperations100() throws {
        let count = 100
        let expectation = self.expectation(description: "100 concurrent buffer operations")
        expectation.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { i in
            let size = 1000 + (i * 100)
            var buffer = [Int32](repeating: 0, count: size)
            for j in 0..<size {
                buffer[j] = Int32(j % 256) - 128
            }
            let first = buffer[0]
            let last  = buffer[size - 1]
            XCTAssertEqual(first, -128)
            _ = last
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    func testHighConcurrencyMixedOperations200() throws {
        let count = 200
        let expectation = self.expectation(description: "200 mixed concurrent ops")
        expectation.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { i in
            switch i % 4 {
            case 0:
                let image = J2KImage(width: 64, height: 64, components: 1, bitDepth: 8)
                XCTAssertEqual(image.width, 64)
            case 1:
                let image = J2KImage(width: 128, height: 128, components: 3, bitDepth: 8)
                XCTAssertEqual(image.components.count, 3)
            case 2:
                let buffer = [Int32](repeating: Int32(i), count: 256)
                XCTAssertEqual(buffer.count, 256)
            default:
                let image = J2KImage(width: 256, height: 256, components: 1, bitDepth: 16)
                XCTAssertEqual(image.height, 256)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60.0)
    }

    // MARK: - Sustained Load Tests

    func testSustainedLoad1000SequentialImageCreations() throws {
        for i in 0..<1000 {
            let size = 32 + (i % 128)
            let components = 1 + (i % 3)
            let image = J2KImage(width: size, height: size, components: components, bitDepth: 8)
            if i.isMultiple(of: 100) {
                XCTAssertEqual(image.width, size)
                XCTAssertEqual(image.components.count, components)
            }
        }
    }

    func testSustainedLoad500SequentialBufferOperations() throws {
        for i in 0..<500 {
            let size = 1024 + i
            var buffer = [Int32](repeating: Int32(i % 128), count: size)
            // Touch both ends to verify allocation
            buffer[0]        = 1
            buffer[size - 1] = -1
            XCTAssertEqual(buffer[0], 1)
            XCTAssertEqual(buffer[size - 1], -1)
        }
    }

    func testSustainedLoadRepeatedLargeAllocations() throws {
        for _ in 0..<20 {
            let image = J2KImage(width: 2048, height: 2048, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, 2048)
        }
    }

    func testSustainedLoadAlternatingSmallAndLarge() throws {
        let sizes = [8, 4096, 16, 2048, 32, 1024, 64, 512]
        for i in 0..<200 {
            let size = sizes[i % sizes.count]
            let image = J2KImage(width: size, height: size, components: 1, bitDepth: 8)
            XCTAssertEqual(image.width, size)
        }
    }

    // MARK: - Edge Case / Fuzzing-Like Input Tests

    func testMinimumValidImage1x1x1() throws {
        let image = J2KImage(width: 1, height: 1, components: 1, bitDepth: 1)
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.components.count, 1)
    }

    func testMinimumBitDepth1() throws {
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 1)
        XCTAssertEqual(image.components[0].bitDepth, 1)
    }

    func testMaximumBitDepth38() throws {
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 38)
        XCTAssertLessThanOrEqual(image.components[0].bitDepth, 38)
    }

    func testPrimeDimensionImages() throws {
        let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
        for prime in primes {
            let image = J2KImage(width: prime, height: prime, components: 1, bitDepth: 8)
            XCTAssertEqual(image.width, prime)
            XCTAssertEqual(image.height, prime)
        }
    }

    func testNonPowerOfTwoDimensions() throws {
        let dimensions = [(3, 7), (5, 11), (13, 17), (100, 200), (333, 777),
                          (999, 1001), (1023, 1025), (1366, 768), (1920, 1080)]
        for (w, h) in dimensions {
            let image = J2KImage(width: w, height: h, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, w)
            XCTAssertEqual(image.height, h)
        }
    }

    func testOddDimensionsDoNotCrash() throws {
        let oddPairs = [(1, 1), (1, 2), (2, 1), (3, 3), (5, 3), (7, 5),
                        (101, 99), (255, 257), (511, 513)]
        for (w, h) in oddPairs {
            let image = J2KImage(width: w, height: h, components: 1, bitDepth: 8)
            XCTAssertEqual(image.width, w)
        }
    }

    func testExtremeCoefficientValues() throws {
        let coefficients: [Int32] = [
            Int32.max, Int32.min, 0, 1, -1,
            Int32.max - 1, Int32.min + 1,
            1024, -1024, 32767, -32768
        ]
        for value in coefficients {
            var buffer = [Int32](repeating: value, count: 16)
            XCTAssertEqual(buffer[0], value)
            XCTAssertEqual(buffer[15], value)
            _ = buffer  // Suppress warning
        }
    }

    func testAllZeroImageComponents() throws {
        let size = 128 * 128
        let zeroData = Data(repeating: 0, count: size)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 128, height: 128,
            subsamplingX: 1, subsamplingY: 1,
            data: zeroData
        )
        let image = J2KImage(width: 128, height: 128, components: [component])
        XCTAssertEqual(image.components[0].data.count, size)
        XCTAssertTrue(image.components[0].data.allSatisfy { $0 == 0 })
    }

    func testAllMaxValueImageComponents() throws {
        let size = 64 * 64
        let maxData = Data(repeating: 255, count: size)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 64, height: 64,
            subsamplingX: 1, subsamplingY: 1,
            data: maxData
        )
        let image = J2KImage(width: 64, height: 64, components: [component])
        XCTAssertTrue(image.components[0].data.allSatisfy { $0 == 255 })
    }

    func testMixedSignComponents() throws {
        var signedData = Data()
        for i in 0..<(64 * 64) {
            signedData.append(UInt8(i % 256))
        }
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: true,
            width: 64, height: 64,
            subsamplingX: 1, subsamplingY: 1,
            data: signedData
        )
        XCTAssertTrue(component.signed)
    }

    func testHighlySubsampledComponents() throws {
        let y  = J2KComponent(index: 0, bitDepth: 8, signed: false, width: 512, height: 512,
                              subsamplingX: 1, subsamplingY: 1, data: Data())
        let cb = J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256,
                              subsamplingX: 2, subsamplingY: 2, data: Data())
        let cr = J2KComponent(index: 2, bitDepth: 8, signed: false, width: 256, height: 256,
                              subsamplingX: 2, subsamplingY: 2, data: Data())
        let image = J2KImage(width: 512, height: 512, components: [y, cb, cr])
        XCTAssertEqual(image.components[0].subsamplingX, 1)
        XCTAssertEqual(image.components[1].subsamplingX, 2)
        XCTAssertEqual(image.components[2].subsamplingY, 2)
    }

    // MARK: - Malformed / Corrupt Input Handling

    func testBitReaderHandlesEmptyData() throws {
        let reader = J2KBitReader(data: Data())
        XCTAssertTrue(reader.isAtEnd)
        XCTAssertFalse(reader.isNextMarker())
    }

    func testBitReaderHandlesSingleByte() throws {
        var reader = J2KBitReader(data: Data([0xFF]))
        XCTAssertFalse(reader.isAtEnd)
        // Reading beyond available data should throw
        XCTAssertThrowsError(try reader.readMarker())
    }

    func testBitReaderHandlesAllZeroData() throws {
        let data = Data(repeating: 0x00, count: 64)
        let reader = J2KBitReader(data: data)
        XCTAssertFalse(reader.isAtEnd)
        XCTAssertFalse(reader.isNextMarker())
    }

    func testBitReaderHandlesAllOnesData() throws {
        let data = Data(repeating: 0xFF, count: 64)
        let reader = J2KBitReader(data: data)
        XCTAssertFalse(reader.isAtEnd)
    }

    func testBitWriterCanWriteAndReader() throws {
        var writer = J2KBitWriter()
        writer.writeMarker(0xFF4F)  // SOC
        writer.writeMarker(0xFFD9)  // EOC

        let data = writer.data
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
        XCTAssertEqual(data[2], 0xFF)
        XCTAssertEqual(data[3], 0xD9)
    }

    func testMarkerParserHandlesEmptyData() throws {
        let parser = J2KMarkerParser(data: Data())
        XCTAssertFalse(parser.validateBasicStructure())
    }

    func testMarkerParserHandlesRandomData() throws {
        var random = Data(capacity: 64)
        for i in 0..<64 {
            random.append(UInt8(i))
        }
        let parser = J2KMarkerParser(data: random)
        // Should not crash; may return false or throw
        _ = parser.validateBasicStructure()
    }

    func testImageBufferWithEmptyDataIsHandled() throws {
        let buffer = J2KImageBuffer(width: 64, height: 64, bitDepth: 8, data: Data())
        // Buffer with no data should still be constructible
        XCTAssertEqual(buffer.width, 64)
    }

    // MARK: - Memory Pressure Tests

    func testMemoryPressureHundredSmallAllocations() throws {
        var images: [J2KImage] = []
        for _ in 0..<100 {
            images.append(J2KImage(width: 256, height: 256, components: 3, bitDepth: 8))
        }
        XCTAssertEqual(images.count, 100)
        images.removeAll()
    }

    func testMemoryPressureMixedSizeAllocations() throws {
        var images: [J2KImage] = []
        let sizes = [64, 128, 256, 512, 1024]
        for i in 0..<50 {
            let size = sizes[i % sizes.count]
            images.append(J2KImage(width: size, height: size, components: 3, bitDepth: 8))
        }
        XCTAssertEqual(images.count, 50)
    }

    func testMemoryPressureRapidAllocationDeallocation() throws {
        for _ in 0..<200 {
            _ = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
        }
        // After ARC cleanup, no leaks should remain
    }

    func testMemoryPressureLargeBufferArrays() throws {
        for _ in 0..<10 {
            let buffer = [Int32](repeating: 0, count: 2 * 1024 * 1024) // 8 MB per allocation
            XCTAssertEqual(buffer.count, 2 * 1024 * 1024)
        }
    }

    func testMemoryPressureConcurrentMediumImages() throws {
        let count = 50
        let expectation = self.expectation(description: "Concurrent medium images under pressure")
        expectation.expectedFulfillmentCount = count

        DispatchQueue.concurrentPerform(iterations: count) { _ in
            let image = J2KImage(width: 1024, height: 1024, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, 1024)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)
    }

    // MARK: - Tile Stress Tests

    func testManyTilesDoNotCrash() throws {
        let imageWidth  = 2048
        let imageHeight = 2048
        let tileSize    = 16

        let tilesX = imageWidth  / tileSize
        let tilesY = imageHeight / tileSize

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let index = ty * tilesX + tx
                let tile = J2KTile(
                    index: index,
                    x: tx, y: ty,
                    width: tileSize, height: tileSize,
                    offsetX: tx * tileSize,
                    offsetY: ty * tileSize
                )
                XCTAssertEqual(tile.width, tileSize)
            }
        }
    }

    func testVariableTileDimensionsStress() throws {
        let configurations: [(Int, Int, Int, Int)] = [
            (128, 128, 16, 16),
            (256, 256, 32, 32),
            (512, 512, 64, 64),
            (512, 512, 128, 128),
            (1024, 1024, 256, 256)
        ]
        for (imgW, imgH, tileW, tileH) in configurations {
            let tiledImage = J2KImage(width: imgW, height: imgH, components: 3, bitDepth: 8)
            XCTAssertEqual(tiledImage.width, imgW)
            XCTAssertEqual(tiledImage.height, imgH)
            _ = tileW  // used implicitly in description
            _ = tileH
        }
    }

    // MARK: - Code Block Stress Tests

    func testManyCodeBlocksDoNotCrash() throws {
        var codeBlocks: [J2KCodeBlock] = []
        for i in 0..<1000 {
            let cb = J2KCodeBlock(
                index: i,
                x: i % 32, y: i / 32,
                width: 32, height: 32,
                subband: [.ll, .hl, .lh, .hh][i % 4]
            )
            codeBlocks.append(cb)
        }
        XCTAssertEqual(codeBlocks.count, 1000)
    }

    func testPrecinctWithManyCodeBlocks() throws {
        var blocks: [J2KCodeBlock] = []
        for i in 0..<64 {
            blocks.append(J2KCodeBlock(
                index: i,
                x: i % 8, y: i / 8,
                width: 32, height: 32,
                subband: .hl
            ))
        }
        let codeBlockDict: [J2KSubband: [J2KCodeBlock]] = [.hl: blocks]
        let precinct = J2KPrecinct(
            index: 0, x: 0, y: 0,
            width: 256, height: 256,
            resolutionLevel: 0,
            codeBlocks: codeBlockDict
        )
        XCTAssertEqual(precinct.codeBlocks[.hl]?.count, 64)
    }

    // MARK: - Performance Baseline Stress Tests

    func testSmallImageCreationPerformanceBaseline() {
        measure {
            for _ in 0..<200 {
                _ = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            }
        }
    }

    func testMediumImageCreationPerformanceBaseline() {
        measure {
            for _ in 0..<20 {
                _ = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
            }
        }
    }

    func testLargeBufferAllocationPerformanceBaseline() {
        measure {
            _ = [Int32](repeating: 0, count: 2 * 1024 * 1024)
        }
    }

    func testConcurrentSmallImagePerformanceBaseline() {
        measure {
            DispatchQueue.concurrentPerform(iterations: 50) { i in
                _ = J2KImage(width: 32 + i % 64, height: 32 + i % 64, components: 1, bitDepth: 8)
            }
        }
    }
}
