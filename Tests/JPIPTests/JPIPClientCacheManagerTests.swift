//
// JPIPClientCacheManagerTests.swift
// J2KSwift
//
import XCTest
@testable import JPIP
@testable import J2KCore

/// Tests for JPIP client-side cache management improvements.
final class JPIPClientCacheManagerTests: XCTestCase {
    // MARK: - Basic Cache Operations

    func testCacheManagerInitialization() async {
        let manager = JPIPClientCacheManager()
        let report = await manager.generateUsageReport()
        XCTAssertEqual(report.totalMemoryUsage, 0)
        XCTAssertEqual(report.totalEntries, 0)
        XCTAssertEqual(report.compressedEntries, 0)
        XCTAssertEqual(report.deduplicatedEntries, 0)
        XCTAssertEqual(report.pinnedEntries, 0)
    }

    func testAddAndRetrieveDataBin() async {
        let manager = JPIPClientCacheManager()
        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data([1, 2, 3, 4, 5]),
            isComplete: true
        )

        await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 2)

        let retrieved = await manager.getDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.data, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(retrieved?.binClass, .precinct)
        XCTAssertEqual(retrieved?.binID, 1)
    }

    func testCacheMiss() async {
        let manager = JPIPClientCacheManager()

        let result = await manager.getDataBin(
            binClass: .precinct, binID: 99, imageID: "nonexistent"
        )
        XCTAssertNil(result)

        let hitRate = await manager.getHitRate()
        XCTAssertEqual(hitRate, 0.0)
    }

    func testHasDataBin() async {
        let manager = JPIPClientCacheManager()
        let dataBin = JPIPDataBin(
            binClass: .mainHeader, binID: 1,
            data: Data([1, 2, 3]), isComplete: true
        )

        await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 0)

        let has = await manager.hasDataBin(
            binClass: .mainHeader, binID: 1, imageID: "img1"
        )
        XCTAssertTrue(has)

        let hasNot = await manager.hasDataBin(
            binClass: .mainHeader, binID: 2, imageID: "img1"
        )
        XCTAssertFalse(hasNot)
    }

    func testClearCache() async {
        let manager = JPIPClientCacheManager()

        for i in 0..<5 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i)]), isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 0)
        }

        let entriesBefore = await manager.getTotalEntries()
        XCTAssertEqual(entriesBefore, 5)

        await manager.clear()

        let entriesAfter = await manager.getTotalEntries()
        XCTAssertEqual(entriesAfter, 0)
        let memoryAfter = await manager.getMemoryUsage()
        XCTAssertEqual(memoryAfter, 0)
    }

    // MARK: - Resolution-Aware LRU Eviction

    func testResolutionAwareLRUEviction() async {
        // Create cache with small memory limit
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 50,
            maxEntries: 1000
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Add entry at low resolution (high priority — should survive)
        let lowRes = JPIPDataBin(
            binClass: .precinct, binID: 1,
            data: Data(repeating: 1, count: 20), isComplete: true
        )
        await manager.addDataBin(lowRes, imageID: "img1", resolutionLevel: 0)

        // Small delay for timestamp differentiation
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Add entry at high resolution (low priority — should be evicted first)
        let highRes = JPIPDataBin(
            binClass: .precinct, binID: 2,
            data: Data(repeating: 2, count: 20), isComplete: true
        )
        await manager.addDataBin(highRes, imageID: "img1", resolutionLevel: 5)

        try? await Task.sleep(nanoseconds: 10_000_000)

        // Add another entry that causes eviction
        let trigger = JPIPDataBin(
            binClass: .precinct, binID: 3,
            data: Data(repeating: 3, count: 20), isComplete: true
        )
        await manager.addDataBin(trigger, imageID: "img1", resolutionLevel: 1)

        // Low resolution entry should survive; high resolution should be evicted
        let hasLowRes = await manager.hasDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertTrue(hasLowRes, "Low resolution entry should survive eviction")

        let hasTrigger = await manager.hasDataBin(
            binClass: .precinct, binID: 3, imageID: "img1"
        )
        XCTAssertTrue(hasTrigger, "Newly added entry should be present")

        let memUsage = await manager.getMemoryUsage()
        XCTAssertLessThanOrEqual(memUsage, 50)
    }

    func testEvictionUnderMemoryPressure() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 100,
            maxEntries: 100
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Add entries that exceed memory limit
        for i in 0..<10 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data(repeating: UInt8(i), count: 20),
                isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: i % 3)
        }

        let memUsage = await manager.getMemoryUsage()
        XCTAssertLessThanOrEqual(memUsage, 100)

        let report = await manager.generateUsageReport()
        XCTAssertGreaterThan(report.efficiency.evictions, 0)
    }

    func testEntryLimitEviction() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 1_000_000,
            maxEntries: 5
        )
        let manager = JPIPClientCacheManager(configuration: config)

        for i in 0..<10 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i)]), isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 0)
        }

        let entries = await manager.getTotalEntries()
        XCTAssertLessThanOrEqual(entries, 5)
    }

    // MARK: - Cache Partitioning

    func testCachePartitionByImage() async {
        let manager = JPIPClientCacheManager()

        // Add entries for two different images
        for i in 0..<3 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i)]), isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 0)
        }

        for i in 0..<2 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i + 10)]), isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img2", resolutionLevel: 0)
        }

        let imageIDs = await manager.getCachedImageIDs()
        XCTAssertEqual(Set(imageIDs), Set(["img1", "img2"]))

        let img1Count = await manager.getEntryCount(imageID: "img1")
        XCTAssertEqual(img1Count, 3)

        let img2Count = await manager.getEntryCount(imageID: "img2")
        XCTAssertEqual(img2Count, 2)
    }

    func testCachePartitionByResolution() async {
        let manager = JPIPClientCacheManager()

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1, data: Data([1]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2, data: Data([2]), isComplete: true),
            imageID: "img1", resolutionLevel: 1
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 3, data: Data([3]), isComplete: true),
            imageID: "img1", resolutionLevel: 2
        )

        let resLevels = await manager.getCachedResolutionLevels(imageID: "img1")
        XCTAssertEqual(resLevels, Set([0, 1, 2]))
    }

    // MARK: - Per-Image Policy

    func testPerImagePolicyPinnedResolutions() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 50,
            maxEntries: 1000
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Pin resolution level 0
        let policy = JPIPImageCachePolicy(
            imageID: "img1",
            pinnedResolutions: [0]
        )
        await manager.setImagePolicy(policy)

        // Add pinned entry (resolution 0)
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data(repeating: 1, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        // Add non-pinned entry
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2,
                        data: Data(repeating: 2, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 3
        )

        // Add trigger entry to force eviction
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 3,
                        data: Data(repeating: 3, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 4
        )

        // Pinned entry should survive
        let hasPinned = await manager.hasDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertTrue(hasPinned, "Pinned resolution entry should not be evicted")
    }

    func testPerImagePolicyMemoryLimit() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 1_000_000,
            maxEntries: 1000
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Set strict per-image limit
        let policy = JPIPImageCachePolicy(
            imageID: "img1",
            maxMemorySize: 50
        )
        await manager.setImagePolicy(policy)

        // Add entries that exceed per-image limit
        for i in 0..<5 {
            await manager.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: i,
                            data: Data(repeating: UInt8(i), count: 20), isComplete: true),
                imageID: "img1", resolutionLevel: i
            )
        }

        let report = await manager.generateUsageReport()
        let imgUsage = report.perImageUsage["img1"]
        XCTAssertNotNil(imgUsage)
        XCTAssertLessThanOrEqual(imgUsage?.memoryUsage ?? 0, 60) // Allow some tolerance
    }

    func testSetAndGetImagePolicy() async {
        let manager = JPIPClientCacheManager()

        let policy = JPIPImageCachePolicy(
            imageID: "img1",
            maxMemorySize: 10 * 1024 * 1024,
            pinnedResolutions: [0, 1]
        )
        await manager.setImagePolicy(policy)

        let retrieved = await manager.getImagePolicy(imageID: "img1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.imageID, "img1")
        XCTAssertEqual(retrieved?.pinnedResolutions, [0, 1])

        await manager.removeImagePolicy(imageID: "img1")
        let removed = await manager.getImagePolicy(imageID: "img1")
        XCTAssertNil(removed)
    }

    // MARK: - Eviction API

    func testEvictImage() async {
        let manager = JPIPClientCacheManager()

        for i in 0..<3 {
            await manager.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: i,
                            data: Data([UInt8(i)]), isComplete: true),
                imageID: "img1", resolutionLevel: 0
            )
        }
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 0,
                        data: Data([10]), isComplete: true),
            imageID: "img2", resolutionLevel: 0
        )

        let evicted = await manager.evictImage(imageID: "img1")
        XCTAssertEqual(evicted, 3)

        let entries = await manager.getTotalEntries()
        XCTAssertEqual(entries, 1)

        let hasImg2 = await manager.hasDataBin(
            binClass: .precinct, binID: 0, imageID: "img2"
        )
        XCTAssertTrue(hasImg2)
    }

    func testEvictResolutionLevel() async {
        let manager = JPIPClientCacheManager()

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data([1]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2,
                        data: Data([2]), isComplete: true),
            imageID: "img1", resolutionLevel: 2
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 3,
                        data: Data([3]), isComplete: true),
            imageID: "img2", resolutionLevel: 2
        )

        let evicted = await manager.evictResolution(level: 2)
        XCTAssertEqual(evicted, 2)

        let hasRes0 = await manager.hasDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertTrue(hasRes0)

        let hasRes2 = await manager.hasDataBin(
            binClass: .precinct, binID: 2, imageID: "img1"
        )
        XCTAssertFalse(hasRes2)
    }

    func testEvictOlderThan() async {
        let manager = JPIPClientCacheManager()

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data([1]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec
        let cutoff = Date()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2,
                        data: Data([2]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        let evicted = await manager.evictOlderThan(cutoff)
        XCTAssertEqual(evicted, 1)

        let hasOld = await manager.hasDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertFalse(hasOld)

        let hasNew = await manager.hasDataBin(
            binClass: .precinct, binID: 2, imageID: "img1"
        )
        XCTAssertTrue(hasNew)
    }

    // MARK: - Deduplication

    func testDataBinDeduplication() async {
        let config = JPIPCacheManagerConfiguration(enableDeduplication: true)
        let manager = JPIPClientCacheManager(configuration: config)

        let sharedData = Data([1, 2, 3, 4, 5])

        // Add same data under two different images
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: sharedData, isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: sharedData, isComplete: true),
            imageID: "img2", resolutionLevel: 0
        )

        let report = await manager.generateUsageReport()
        XCTAssertGreaterThan(report.deduplicatedEntries, 0)
        XCTAssertGreaterThan(report.efficiency.deduplicationSavings, 0)
    }

    // MARK: - Compressed Storage

    func testCompressInactiveEntries() async {
        let config = JPIPCacheManagerConfiguration(
            enableCompression: true,
            compressionInactivityThreshold: 0.0 // Immediate compression eligibility
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Add entries with compressible data (repeated bytes)
        for i in 0..<5 {
            let dataBin = JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data(repeating: UInt8(i), count: 100),
                isComplete: true
            )
            await manager.addDataBin(dataBin, imageID: "img1", resolutionLevel: 0)
        }

        let memBefore = await manager.getMemoryUsage()

        // Wait a tiny bit to ensure timestamps are past threshold
        try? await Task.sleep(nanoseconds: 10_000_000)

        let saved = await manager.compressInactiveEntries()

        let memAfter = await manager.getMemoryUsage()
        let report = await manager.generateUsageReport()

        XCTAssertGreaterThan(saved, 0, "Should have saved some bytes via compression")
        XCTAssertLessThan(memAfter, memBefore, "Memory usage should decrease after compression")
        XCTAssertGreaterThan(report.compressedEntries, 0)
    }

    func testCompressionDisabled() async {
        let config = JPIPCacheManagerConfiguration(enableCompression: false)
        let manager = JPIPClientCacheManager(configuration: config)

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data(repeating: 0, count: 100), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        let saved = await manager.compressInactiveEntries()
        XCTAssertEqual(saved, 0)
    }

    // MARK: - Persistent Storage Warm-Up

    func testWarmUpFromPersistentStorage() async {
        let store = JPIPInMemoryCacheStore()

        // Pre-populate persistent store
        for i in 0..<3 {
            let metadata = JPIPCacheEntryMetadata(
                imageID: "img1",
                resolutionLevel: i,
                binClassRawValue: JPIPDataBinClass.precinct.rawValue,
                binID: i,
                isComplete: true,
                qualityLayer: 0,
                tileIndex: 0,
                contentHash: i,
                createdAt: Date()
            )
            try? await store.save(
                key: "img1:\(JPIPDataBinClass.precinct.rawValue):\(i)",
                data: Data(repeating: UInt8(i), count: 10),
                metadata: metadata
            )
        }

        let manager = JPIPClientCacheManager(persistentStore: store)

        let loaded = await manager.warmUpFromPersistentStorage()
        XCTAssertEqual(loaded, 3)

        let entries = await manager.getTotalEntries()
        XCTAssertEqual(entries, 3)

        let report = await manager.generateUsageReport()
        XCTAssertEqual(report.efficiency.warmUpLoads, 3)
    }

    func testSaveToPersistentStorage() async {
        let store = JPIPInMemoryCacheStore()
        let manager = JPIPClientCacheManager(persistentStore: store)

        for i in 0..<3 {
            await manager.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: i,
                            data: Data([UInt8(i)]), isComplete: true),
                imageID: "img1", resolutionLevel: 0
            )
        }

        let saved = await manager.saveToPersistentStorage()
        XCTAssertEqual(saved, 3)

        let keys = try? await store.allKeys()
        XCTAssertEqual(keys?.count, 3)
    }

    func testCachePersistenceAcrossRestarts() async {
        let store = JPIPInMemoryCacheStore()

        // Simulate first session
        let manager1 = JPIPClientCacheManager(persistentStore: store)
        for i in 0..<3 {
            await manager1.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: i,
                            data: Data([UInt8(i), UInt8(i + 1)]),
                            isComplete: true),
                imageID: "img1", resolutionLevel: i
            )
        }
        let savedCount = await manager1.saveToPersistentStorage()
        XCTAssertEqual(savedCount, 3)

        // Simulate restart with new manager
        let manager2 = JPIPClientCacheManager(persistentStore: store)
        let loadedCount = await manager2.warmUpFromPersistentStorage()
        XCTAssertEqual(loadedCount, 3)

        // Verify data is accessible
        for i in 0..<3 {
            let hasBin = await manager2.hasDataBin(
                binClass: .precinct, binID: i, imageID: "img1"
            )
            XCTAssertTrue(hasBin, "Bin \(i) should be restored from persistent storage")
        }
    }

    // MARK: - Predictive Pre-Population

    func testPrePopulateCache() async {
        let manager = JPIPClientCacheManager()

        let dataBins = (0..<5).map { i in
            JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i)]), isComplete: true
            )
        }

        let added = await manager.prePopulate(
            dataBins: dataBins, imageID: "img1", resolutionLevel: 1
        )
        XCTAssertEqual(added, 5)

        let entries = await manager.getTotalEntries()
        XCTAssertEqual(entries, 5)
    }

    func testPrePopulateSkipsDuplicates() async {
        let manager = JPIPClientCacheManager()

        // Add an existing entry
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 0,
                        data: Data([0]), isComplete: true),
            imageID: "img1", resolutionLevel: 1
        )

        let dataBins = (0..<3).map { i in
            JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data([UInt8(i)]), isComplete: true
            )
        }

        let added = await manager.prePopulate(
            dataBins: dataBins, imageID: "img1", resolutionLevel: 1
        )
        XCTAssertEqual(added, 2, "Should only add bins not already in cache")
    }

    func testPrePopulateRespectsMemoryLimit() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 30,
            maxEntries: 100
        )
        let manager = JPIPClientCacheManager(configuration: config)

        let dataBins = (0..<10).map { i in
            JPIPDataBin(
                binClass: .precinct, binID: i,
                data: Data(repeating: UInt8(i), count: 10),
                isComplete: true
            )
        }

        let added = await manager.prePopulate(
            dataBins: dataBins, imageID: "img1", resolutionLevel: 0
        )
        XCTAssertLessThanOrEqual(added, 3, "Should stop when memory limit reached")
    }

    // MARK: - Hit Rate Monitoring

    func testHitRateMonitoring() async {
        let manager = JPIPClientCacheManager()

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data([1]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        // 3 hits
        _ = await manager.getDataBin(binClass: .precinct, binID: 1, imageID: "img1")
        _ = await manager.getDataBin(binClass: .precinct, binID: 1, imageID: "img1")
        _ = await manager.getDataBin(binClass: .precinct, binID: 1, imageID: "img1")

        // 2 misses
        _ = await manager.getDataBin(binClass: .precinct, binID: 2, imageID: "img1")
        _ = await manager.getDataBin(binClass: .precinct, binID: 3, imageID: "img1")

        let hitRate = await manager.getHitRate()
        XCTAssertEqual(hitRate, 0.6, accuracy: 0.001)

        let report = await manager.generateUsageReport()
        XCTAssertEqual(report.efficiency.hits, 3)
        XCTAssertEqual(report.efficiency.misses, 2)
        XCTAssertEqual(report.efficiency.hitRate, 0.6, accuracy: 0.001)
    }

    // MARK: - Diagnostics

    func testUsageReport() async {
        let manager = JPIPClientCacheManager()

        // Add entries across images and resolutions
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data(repeating: 1, count: 10), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2,
                        data: Data(repeating: 2, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 1
        )
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data(repeating: 3, count: 15), isComplete: true),
            imageID: "img2", resolutionLevel: 0
        )

        let report = await manager.generateUsageReport()

        XCTAssertEqual(report.totalEntries, 3)
        XCTAssertEqual(report.totalMemoryUsage, 45)

        // Per-image breakdown
        XCTAssertEqual(report.perImageUsage.count, 2)
        XCTAssertEqual(report.perImageUsage["img1"]?.entryCount, 2)
        XCTAssertEqual(report.perImageUsage["img1"]?.memoryUsage, 30)
        XCTAssertEqual(report.perImageUsage["img2"]?.entryCount, 1)
        XCTAssertEqual(report.perImageUsage["img2"]?.memoryUsage, 15)

        // Per-resolution breakdown
        XCTAssertEqual(report.perResolutionUsage[0]?.entryCount, 2)
        XCTAssertEqual(report.perResolutionUsage[0]?.imageCount, 2)
        XCTAssertEqual(report.perResolutionUsage[1]?.entryCount, 1)
        XCTAssertEqual(report.perResolutionUsage[1]?.imageCount, 1)
    }

    func testUsageReportResolutionLevelCount() async {
        let manager = JPIPClientCacheManager()

        for res in 0..<4 {
            await manager.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: res,
                            data: Data([UInt8(res)]), isComplete: true),
                imageID: "img1", resolutionLevel: res
            )
        }

        let report = await manager.generateUsageReport()
        XCTAssertEqual(report.perImageUsage["img1"]?.resolutionLevels, 4)
    }

    // MARK: - Multi-Image Concurrent Caching

    func testMultiImageConcurrentCaching() async {
        let manager = JPIPClientCacheManager()
        let imageCount = 10
        let entriesPerImage = 5

        // Add entries concurrently for multiple images
        await withTaskGroup(of: Void.self) { group in
            for img in 0..<imageCount {
                group.addTask {
                    for entry in 0..<entriesPerImage {
                        let dataBin = JPIPDataBin(
                            binClass: .precinct, binID: entry,
                            data: Data([UInt8(img), UInt8(entry)]),
                            isComplete: true
                        )
                        await manager.addDataBin(
                            dataBin, imageID: "img\(img)",
                            resolutionLevel: entry % 3
                        )
                    }
                }
            }
        }

        let totalEntries = await manager.getTotalEntries()
        XCTAssertEqual(totalEntries, imageCount * entriesPerImage)

        let imageIDs = await manager.getCachedImageIDs()
        XCTAssertEqual(imageIDs.count, imageCount)
    }

    // MARK: - Update Existing Entry

    func testUpdateExistingEntry() async {
        let manager = JPIPClientCacheManager()

        // Add initial entry
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data([1, 2, 3]), isComplete: false),
            imageID: "img1", resolutionLevel: 0
        )

        let memBefore = await manager.getMemoryUsage()
        XCTAssertEqual(memBefore, 3)

        // Update with larger data
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data([1, 2, 3, 4, 5, 6]), isComplete: true),
            imageID: "img1", resolutionLevel: 0
        )

        let entries = await manager.getTotalEntries()
        XCTAssertEqual(entries, 1, "Entry count should not increase on update")

        let memAfter = await manager.getMemoryUsage()
        XCTAssertEqual(memAfter, 6, "Memory usage should reflect updated data")

        let retrieved = await manager.getDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertEqual(retrieved?.data.count, 6)
        XCTAssertEqual(retrieved?.isComplete, true)
    }

    // MARK: - Configuration

    func testCustomResolutionWeights() async {
        let config = JPIPCacheManagerConfiguration(
            maxMemorySize: 50,
            maxEntries: 100,
            resolutionPriorityWeights: [0: 10.0, 1: 5.0, 2: 1.0, 3: 0.1]
        )
        let manager = JPIPClientCacheManager(configuration: config)

        // Add entries at different resolutions
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 1,
                        data: Data(repeating: 1, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 0 // weight 10.0 — highest priority
        )

        try? await Task.sleep(nanoseconds: 10_000_000)

        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 2,
                        data: Data(repeating: 2, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 3 // weight 0.1 — lowest priority
        )

        try? await Task.sleep(nanoseconds: 10_000_000)

        // Trigger eviction
        await manager.addDataBin(
            JPIPDataBin(binClass: .precinct, binID: 3,
                        data: Data(repeating: 3, count: 20), isComplete: true),
            imageID: "img1", resolutionLevel: 1 // weight 5.0
        )

        // Highest priority entry (res 0, weight 10.0) should survive
        let hasHighPriority = await manager.hasDataBin(
            binClass: .precinct, binID: 1, imageID: "img1"
        )
        XCTAssertTrue(hasHighPriority, "High-priority resolution should survive")
    }

    // MARK: - Cache Hit Rate Benchmarking

    func testCacheHitRateBenchmark() async {
        let manager = JPIPClientCacheManager()

        // Populate cache with 100 entries
        for i in 0..<100 {
            await manager.addDataBin(
                JPIPDataBin(binClass: .precinct, binID: i,
                            data: Data([UInt8(i % 256)]), isComplete: true),
                imageID: "img1", resolutionLevel: i % 5
            )
        }

        // Access 80% of existing entries (hits)
        for i in 0..<80 {
            _ = await manager.getDataBin(
                binClass: .precinct, binID: i, imageID: "img1"
            )
        }

        // Access 20 non-existing entries (misses)
        for i in 100..<120 {
            _ = await manager.getDataBin(
                binClass: .precinct, binID: i, imageID: "img1"
            )
        }

        let hitRate = await manager.getHitRate()
        XCTAssertEqual(hitRate, 0.8, accuracy: 0.001)
    }

    // MARK: - Persistent Store Tests

    func testInMemoryCacheStore() async throws {
        let store = JPIPInMemoryCacheStore()

        let metadata = JPIPCacheEntryMetadata(
            imageID: "img1", resolutionLevel: 0,
            binClassRawValue: 2, binID: 1,
            isComplete: true, qualityLayer: 0,
            tileIndex: 0, contentHash: 12345,
            createdAt: Date()
        )

        try await store.save(key: "test", data: Data([1, 2, 3]), metadata: metadata)

        let loaded = try await store.load(key: "test")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.data, Data([1, 2, 3]))
        XCTAssertEqual(loaded?.metadata.imageID, "img1")

        let usage = try await store.totalDiskUsage()
        XCTAssertEqual(usage, 3)

        let keys = try await store.allKeys()
        XCTAssertEqual(keys.count, 1)

        try await store.remove(key: "test")
        let afterRemove = try await store.load(key: "test")
        XCTAssertNil(afterRemove)

        try await store.save(key: "a", data: Data([1]), metadata: metadata)
        try await store.save(key: "b", data: Data([2]), metadata: metadata)
        try await store.clear()
        let afterClear = try await store.allKeys()
        XCTAssertEqual(afterClear.count, 0)
    }
}
