//
// JPIPCacheTests.swift
// J2KSwift
//
import XCTest
@testable import JPIP
@testable import J2KCore

/// Tests for JPIP cache management features.
final class JPIPCacheTests: XCTestCase {
    // MARK: - JPIPCacheModel Tests

    func testCacheModelInitialization() {
        let cache = JPIPCacheModel()
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.statistics.misses, 0)
        XCTAssertEqual(cache.statistics.totalSize, 0)
        XCTAssertEqual(cache.statistics.entryCount, 0)
        XCTAssertEqual(cache.statistics.evictions, 0)
        XCTAssertEqual(cache.statistics.hitRate, 0.0)
    }

    func testAddDataBinToCache() {
        var cache = JPIPCacheModel()
        let dataBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 1,
            data: Data([1, 2, 3, 4, 5]),
            isComplete: true
        )

        cache.addDataBin(dataBin)

        XCTAssertTrue(cache.hasDataBin(binClass: .mainHeader, binID: 1))
        XCTAssertEqual(cache.statistics.entryCount, 1)
        XCTAssertEqual(cache.statistics.totalSize, 5)
    }

    func testGetDataBinFromCache() {
        var cache = JPIPCacheModel()
        let testData = Data([1, 2, 3, 4, 5])
        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 42,
            data: testData,
            isComplete: true
        )

        cache.addDataBin(dataBin)

        let retrieved = cache.getDataBin(binClass: .precinct, binID: 42)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.binClass, .precinct)
        XCTAssertEqual(retrieved?.binID, 42)
        XCTAssertEqual(retrieved?.data, testData)
        XCTAssertEqual(cache.statistics.hits, 1)
        XCTAssertEqual(cache.statistics.misses, 0)
    }

    func testCacheMiss() {
        var cache = JPIPCacheModel()

        let retrieved = cache.getDataBin(binClass: .tileHeader, binID: 99)
        XCTAssertNil(retrieved)
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.statistics.misses, 1)
    }

    func testCacheHitRate() {
        var cache = JPIPCacheModel()
        let dataBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 1,
            data: Data([1, 2, 3]),
            isComplete: true
        )
        cache.addDataBin(dataBin)

        // 3 hits
        _ = cache.getDataBin(binClass: .mainHeader, binID: 1)
        _ = cache.getDataBin(binClass: .mainHeader, binID: 1)
        _ = cache.getDataBin(binClass: .mainHeader, binID: 1)

        // 2 misses
        _ = cache.getDataBin(binClass: .tileHeader, binID: 2)
        _ = cache.getDataBin(binClass: .precinct, binID: 3)

        XCTAssertEqual(cache.statistics.hits, 3)
        XCTAssertEqual(cache.statistics.misses, 2)
        XCTAssertEqual(cache.statistics.hitRate, 0.6, accuracy: 0.001)
    }

    func testUpdateExistingDataBin() {
        var cache = JPIPCacheModel()

        let dataBin1 = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data([1, 2, 3]),
            isComplete: false
        )
        cache.addDataBin(dataBin1)
        XCTAssertEqual(cache.statistics.totalSize, 3)

        let dataBin2 = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data([1, 2, 3, 4, 5, 6]),
            isComplete: true
        )
        cache.addDataBin(dataBin2)

        // Entry count should not increase
        XCTAssertEqual(cache.statistics.entryCount, 1)
        // Size should be updated
        XCTAssertEqual(cache.statistics.totalSize, 6)
    }

    func testCacheSizeLimit() {
        // Create a small cache that can only hold 100 bytes
        var cache = JPIPCacheModel(maxCacheSize: 100, maxEntries: 1000)

        // Add data bins that exceed the limit
        for i in 0..<10 {
            let dataBin = JPIPDataBin(
                binClass: .precinct,
                binID: i,
                data: Data(repeating: UInt8(i), count: 20),
                isComplete: true
            )
            cache.addDataBin(dataBin)
        }

        // Cache should have evicted entries to stay under limit
        XCTAssertLessThanOrEqual(cache.statistics.totalSize, 100)
        XCTAssertLessThanOrEqual(cache.statistics.entryCount, 5)
        XCTAssertGreaterThan(cache.statistics.evictions, 0)
    }

    func testCacheEntryLimit() {
        // Create a cache with a low entry limit
        var cache = JPIPCacheModel(maxCacheSize: 1_000_000, maxEntries: 5)

        // Add more entries than the limit
        for i in 0..<10 {
            let dataBin = JPIPDataBin(
                binClass: .precinct,
                binID: i,
                data: Data([UInt8(i)]),
                isComplete: true
            )
            cache.addDataBin(dataBin)
        }

        // Cache should have evicted entries to stay under limit
        XCTAssertLessThanOrEqual(cache.statistics.entryCount, 5)
        XCTAssertGreaterThan(cache.statistics.evictions, 0)
    }

    func testLRUEviction() {
        var cache = JPIPCacheModel(maxCacheSize: 50, maxEntries: 1000)

        // Add 3 bins of 20 bytes each (60 bytes total, exceeds 50)
        let dataBin1 = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data(repeating: 1, count: 20),
            isComplete: true
        )
        cache.addDataBin(dataBin1)
        Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure different timestamps

        let dataBin2 = JPIPDataBin(
            binClass: .precinct,
            binID: 2,
            data: Data(repeating: 2, count: 20),
            isComplete: true
        )
        cache.addDataBin(dataBin2)
        Thread.sleep(forTimeInterval: 0.01)

        let dataBin3 = JPIPDataBin(
            binClass: .precinct,
            binID: 3,
            data: Data(repeating: 3, count: 20),
            isComplete: true
        )
        cache.addDataBin(dataBin3)

        // The oldest entry (bin 1) should have been evicted
        XCTAssertFalse(cache.hasDataBin(binClass: .precinct, binID: 1))
        XCTAssertTrue(cache.hasDataBin(binClass: .precinct, binID: 2))
        XCTAssertTrue(cache.hasDataBin(binClass: .precinct, binID: 3))
    }

    func testInvalidateByBinClass() {
        var cache = JPIPCacheModel()

        cache.addDataBin(JPIPDataBin(binClass: .mainHeader, binID: 1, data: Data([1]), isComplete: true))
        cache.addDataBin(JPIPDataBin(binClass: .precinct, binID: 1, data: Data([2]), isComplete: true))
        cache.addDataBin(JPIPDataBin(binClass: .precinct, binID: 2, data: Data([3]), isComplete: true))
        cache.addDataBin(JPIPDataBin(binClass: .tileHeader, binID: 1, data: Data([4]), isComplete: true))

        XCTAssertEqual(cache.statistics.entryCount, 4)

        cache.invalidate(binClass: .precinct)

        XCTAssertEqual(cache.statistics.entryCount, 2)
        XCTAssertTrue(cache.hasDataBin(binClass: .mainHeader, binID: 1))
        XCTAssertFalse(cache.hasDataBin(binClass: .precinct, binID: 1))
        XCTAssertFalse(cache.hasDataBin(binClass: .precinct, binID: 2))
        XCTAssertTrue(cache.hasDataBin(binClass: .tileHeader, binID: 1))
    }

    func testInvalidateByAge() {
        var cache = JPIPCacheModel()

        cache.addDataBin(JPIPDataBin(binClass: .mainHeader, binID: 1, data: Data([1]), isComplete: true))

        // Wait a bit
        Thread.sleep(forTimeInterval: 0.1)
        let cutoffDate = Date()
        Thread.sleep(forTimeInterval: 0.1)

        cache.addDataBin(JPIPDataBin(binClass: .precinct, binID: 1, data: Data([2]), isComplete: true))

        XCTAssertEqual(cache.statistics.entryCount, 2)

        cache.invalidate(olderThan: cutoffDate)

        // Only the newer entry should remain
        XCTAssertEqual(cache.statistics.entryCount, 1)
        XCTAssertFalse(cache.hasDataBin(binClass: .mainHeader, binID: 1))
        XCTAssertTrue(cache.hasDataBin(binClass: .precinct, binID: 1))
    }

    func testClearCache() {
        var cache = JPIPCacheModel()

        cache.addDataBin(JPIPDataBin(binClass: .mainHeader, binID: 1, data: Data([1]), isComplete: true))
        cache.addDataBin(JPIPDataBin(binClass: .precinct, binID: 1, data: Data([2]), isComplete: true))

        XCTAssertEqual(cache.statistics.entryCount, 2)

        cache.clear()

        XCTAssertEqual(cache.statistics.entryCount, 0)
        XCTAssertEqual(cache.statistics.totalSize, 0)
        XCTAssertFalse(cache.hasDataBin(binClass: .mainHeader, binID: 1))
        XCTAssertFalse(cache.hasDataBin(binClass: .precinct, binID: 1))
    }

    // MARK: - JPIPPrecinctCache Tests

    func testPrecinctCacheInitialization() {
        let cache = JPIPPrecinctCache()
        XCTAssertEqual(cache.statistics.totalPrecincts, 0)
        XCTAssertEqual(cache.statistics.completePrecincts, 0)
        XCTAssertEqual(cache.statistics.partialPrecincts, 0)
        XCTAssertEqual(cache.statistics.totalSize, 0)
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.statistics.misses, 0)
    }

    func testAddPrecinctToCache() {
        var cache = JPIPPrecinctCache()

        let precinctID = JPIPPrecinctID(tile: 0, component: 0, resolution: 2, precinctX: 1, precinctY: 1)
        let precinctData = JPIPPrecinctData(
            precinctID: precinctID,
            data: Data([1, 2, 3, 4, 5]),
            isComplete: true,
            receivedLayers: [0, 1, 2]
        )

        cache.addPrecinct(precinctData)

        XCTAssertTrue(cache.hasPrecinct(precinctID))
        XCTAssertEqual(cache.statistics.totalPrecincts, 1)
        XCTAssertEqual(cache.statistics.completePrecincts, 1)
        XCTAssertEqual(cache.statistics.partialPrecincts, 0)
        XCTAssertEqual(cache.statistics.totalSize, 5)
    }

    func testAddPartialPrecinct() {
        var cache = JPIPPrecinctCache()

        let precinctID = JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0)
        let precinctData = JPIPPrecinctData(
            precinctID: precinctID,
            data: Data([1, 2, 3]),
            isComplete: false,
            receivedLayers: [0]
        )

        cache.addPrecinct(precinctData)

        XCTAssertTrue(cache.hasPrecinct(precinctID))
        XCTAssertEqual(cache.statistics.totalPrecincts, 1)
        XCTAssertEqual(cache.statistics.completePrecincts, 0)
        XCTAssertEqual(cache.statistics.partialPrecincts, 1)
    }

    func testGetPrecinctFromCache() {
        var cache = JPIPPrecinctCache()

        let precinctID = JPIPPrecinctID(tile: 1, component: 1, resolution: 3, precinctX: 2, precinctY: 3)
        let testData = Data([10, 20, 30, 40])
        let precinctData = JPIPPrecinctData(
            precinctID: precinctID,
            data: testData,
            isComplete: true,
            receivedLayers: [0, 1]
        )

        cache.addPrecinct(precinctData)

        let retrieved = cache.getPrecinct(precinctID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.precinctID, precinctID)
        XCTAssertEqual(retrieved?.data, testData)
        XCTAssertTrue(retrieved?.isComplete ?? false)
        XCTAssertEqual(retrieved?.receivedLayers, [0, 1])
        XCTAssertEqual(cache.statistics.hits, 1)
        XCTAssertEqual(cache.statistics.misses, 0)
    }

    func testPrecinctCacheMiss() {
        var cache = JPIPPrecinctCache()

        let precinctID = JPIPPrecinctID(tile: 5, component: 2, resolution: 1, precinctX: 0, precinctY: 0)
        let retrieved = cache.getPrecinct(precinctID)

        XCTAssertNil(retrieved)
        XCTAssertEqual(cache.statistics.hits, 0)
        XCTAssertEqual(cache.statistics.misses, 1)
    }

    func testIsPrecinctComplete() {
        var cache = JPIPPrecinctCache()

        let precinctID1 = JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0)
        let precinctID2 = JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0)

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: precinctID1,
            data: Data([1, 2, 3]),
            isComplete: true,
            receivedLayers: [0, 1, 2]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: precinctID2,
            data: Data([4, 5, 6]),
            isComplete: false,
            receivedLayers: [0]
        ))

        XCTAssertTrue(cache.isPrecinctComplete(precinctID1))
        XCTAssertFalse(cache.isPrecinctComplete(precinctID2))
    }

    func testGetPrecinctsByTile() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 1, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([2]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 1, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([3]),
            isComplete: true,
            receivedLayers: [0]
        ))

        let tile0Precincts = cache.getPrecincts(forTile: 0)
        let tile1Precincts = cache.getPrecincts(forTile: 1)

        XCTAssertEqual(tile0Precincts.count, 2)
        XCTAssertEqual(tile1Precincts.count, 1)
    }

    func testGetPrecinctsByResolution() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0),
            data: Data([2]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 1, precinctY: 0),
            data: Data([3]),
            isComplete: true,
            receivedLayers: [0]
        ))

        let res0Precincts = cache.getPrecincts(forResolution: 0)
        let res1Precincts = cache.getPrecincts(forResolution: 1)

        XCTAssertEqual(res0Precincts.count, 1)
        XCTAssertEqual(res1Precincts.count, 2)
    }

    func testMergePrecinct() {
        var cache = JPIPPrecinctCache()

        let precinctID = JPIPPrecinctID(tile: 0, component: 0, resolution: 2, precinctX: 1, precinctY: 1)

        // Add initial partial data
        let initial = cache.mergePrecinct(
            precinctID,
            data: Data([1, 2, 3]),
            layers: [0],
            isComplete: false
        )

        XCTAssertEqual(initial.receivedLayers, [0])
        XCTAssertEqual(initial.data.count, 3)
        XCTAssertFalse(initial.isComplete)

        // Merge additional data
        let merged = cache.mergePrecinct(
            precinctID,
            data: Data([4, 5, 6]),
            layers: [1, 2],
            isComplete: true
        )

        XCTAssertEqual(merged.receivedLayers, [0, 1, 2])
        XCTAssertEqual(merged.data.count, 6)
        XCTAssertTrue(merged.isComplete)
    }

    func testInvalidatePrecinctsByTile() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 1, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([2]),
            isComplete: true,
            receivedLayers: [0]
        ))

        XCTAssertEqual(cache.statistics.totalPrecincts, 2)

        cache.invalidate(tile: 0)

        XCTAssertEqual(cache.statistics.totalPrecincts, 1)
        XCTAssertFalse(cache.hasPrecinct(JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0)))
        XCTAssertTrue(cache.hasPrecinct(JPIPPrecinctID(tile: 1, component: 0, resolution: 0, precinctX: 0, precinctY: 0)))
    }

    func testInvalidatePrecinctsByResolution() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0),
            data: Data([2]),
            isComplete: true,
            receivedLayers: [0]
        ))

        XCTAssertEqual(cache.statistics.totalPrecincts, 2)

        cache.invalidate(resolution: 0)

        XCTAssertEqual(cache.statistics.totalPrecincts, 1)
        XCTAssertFalse(cache.hasPrecinct(JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0)))
        XCTAssertTrue(cache.hasPrecinct(JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0)))
    }

    func testPrecinctCacheSizeLimit() {
        // Create a small cache
        var cache = JPIPPrecinctCache(maxCacheSize: 100, maxPrecincts: 1000)

        // Add precincts that exceed the limit
        for i in 0..<10 {
            let precinctID = JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: i, precinctY: 0)
            cache.addPrecinct(JPIPPrecinctData(
                precinctID: precinctID,
                data: Data(repeating: UInt8(i), count: 20),
                isComplete: true,
                receivedLayers: [0]
            ))
        }

        // Cache should have evicted to stay under limit
        XCTAssertLessThanOrEqual(cache.statistics.totalSize, 100)
        XCTAssertLessThanOrEqual(cache.statistics.totalPrecincts, 5)
    }

    func testPrecinctCacheClear() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1, 2, 3]),
            isComplete: true,
            receivedLayers: [0]
        ))

        XCTAssertEqual(cache.statistics.totalPrecincts, 1)

        cache.clear()

        XCTAssertEqual(cache.statistics.totalPrecincts, 0)
        XCTAssertEqual(cache.statistics.completePrecincts, 0)
        XCTAssertEqual(cache.statistics.partialPrecincts, 0)
        XCTAssertEqual(cache.statistics.totalSize, 0)
    }

    func testPrecinctCompletionRate() {
        var cache = JPIPPrecinctCache()

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([1]),
            isComplete: true,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 1, precinctY: 0),
            data: Data([2]),
            isComplete: false,
            receivedLayers: [0]
        ))

        cache.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 2, precinctY: 0),
            data: Data([3]),
            isComplete: false,
            receivedLayers: [0]
        ))

        XCTAssertEqual(cache.statistics.completionRate, 1.0 / 3.0, accuracy: 0.001)
    }

    // MARK: - JPIPSession Integration Tests

    func testSessionCacheIntegration() async {
        let session = JPIPSession(sessionID: "test-cache")

        let dataBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 1,
            data: Data([1, 2, 3, 4, 5]),
            isComplete: true
        )

        await session.recordDataBin(dataBin)

        let hasBin = await session.hasDataBin(binClass: .mainHeader, binID: 1)
        XCTAssertTrue(hasBin)

        let stats = await session.getCacheStatistics()
        XCTAssertEqual(stats.entryCount, 1)
        XCTAssertEqual(stats.totalSize, 5)
    }

    func testSessionPrecinctCache() async {
        let session = JPIPSession(sessionID: "test-precinct")

        let precinctID = JPIPPrecinctID(tile: 0, component: 0, resolution: 1, precinctX: 0, precinctY: 0)
        let precinctData = JPIPPrecinctData(
            precinctID: precinctID,
            data: Data([10, 20, 30]),
            isComplete: true,
            receivedLayers: [0, 1]
        )

        await session.addPrecinct(precinctData)

        let hasPrecinct = await session.hasPrecinct(precinctID)
        XCTAssertTrue(hasPrecinct)

        let retrieved = await session.getPrecinct(precinctID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.data.count, 3)

        let stats = await session.getPrecinctStatistics()
        XCTAssertEqual(stats.totalPrecincts, 1)
        XCTAssertEqual(stats.completePrecincts, 1)
    }

    func testSessionCacheInvalidation() async {
        let session = JPIPSession(sessionID: "test-invalidation")

        await session.recordDataBin(JPIPDataBin(binClass: .mainHeader, binID: 1, data: Data([1]), isComplete: true))
        await session.recordDataBin(JPIPDataBin(binClass: .precinct, binID: 1, data: Data([2]), isComplete: true))
        await session.recordDataBin(JPIPDataBin(binClass: .precinct, binID: 2, data: Data([3]), isComplete: true))

        var stats = await session.getCacheStatistics()
        XCTAssertEqual(stats.entryCount, 3)

        await session.invalidateCache(binClass: .precinct)

        stats = await session.getCacheStatistics()
        XCTAssertEqual(stats.entryCount, 1)

        let hasMain = await session.hasDataBin(binClass: .mainHeader, binID: 1)
        let hasPrecinct1 = await session.hasDataBin(binClass: .precinct, binID: 1)
        let hasPrecinct2 = await session.hasDataBin(binClass: .precinct, binID: 2)

        XCTAssertTrue(hasMain)
        XCTAssertFalse(hasPrecinct1)
        XCTAssertFalse(hasPrecinct2)
    }

    func testSessionClose() async throws {
        let session = JPIPSession(sessionID: "test-close")

        await session.recordDataBin(JPIPDataBin(binClass: .mainHeader, binID: 1, data: Data([1, 2, 3]), isComplete: true))
        await session.addPrecinct(JPIPPrecinctData(
            precinctID: JPIPPrecinctID(tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0),
            data: Data([4, 5, 6]),
            isComplete: true,
            receivedLayers: [0]
        ))

        try await session.close()

        let stats = await session.getCacheStatistics()
        XCTAssertEqual(stats.entryCount, 0)
        XCTAssertEqual(stats.totalSize, 0)

        let precinctStats = await session.getPrecinctStatistics()
        XCTAssertEqual(precinctStats.totalPrecincts, 0)
    }
}
