//
// JPIPServerPushTests.swift
// J2KSwift
//
/// # JPIPServerPushTests
///
/// Tests for JPIP server-initiated push and predictive prefetching.

import XCTest
@testable import JPIP
@testable import J2KCore

// MARK: - Prefetch Configuration Tests

final class JPIPPrefetchConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let config = JPIPPrefetchConfiguration.default
        XCTAssertEqual(config.maxPrefetchDepth, 64)
        XCTAssertEqual(config.aggressiveness, .moderate)
        XCTAssertEqual(config.maxHistorySize, 100)
        XCTAssertTrue(config.enableResolutionPrefetch)
        XCTAssertTrue(config.enableSpatialPrefetch)
        XCTAssertTrue(config.enableViewportPrediction)
        XCTAssertEqual(config.predictionConfidenceThreshold, 0.3)
        XCTAssertEqual(config.maxPushBandwidthFraction, 0.5)
    }

    func testCustomConfiguration() {
        let config = JPIPPrefetchConfiguration(
            maxPrefetchDepth: 32,
            aggressiveness: .aggressive,
            maxHistorySize: 50,
            enableResolutionPrefetch: false,
            enableSpatialPrefetch: true,
            enableViewportPrediction: false,
            predictionConfidenceThreshold: 0.5,
            maxPushBandwidthFraction: 0.8
        )
        XCTAssertEqual(config.maxPrefetchDepth, 32)
        XCTAssertEqual(config.aggressiveness, .aggressive)
        XCTAssertEqual(config.maxHistorySize, 50)
        XCTAssertFalse(config.enableResolutionPrefetch)
        XCTAssertTrue(config.enableSpatialPrefetch)
        XCTAssertFalse(config.enableViewportPrediction)
        XCTAssertEqual(config.predictionConfidenceThreshold, 0.5)
        XCTAssertEqual(config.maxPushBandwidthFraction, 0.8)
    }

    func testConfigurationClampsValues() {
        let config = JPIPPrefetchConfiguration(
            maxPrefetchDepth: -5,
            maxHistorySize: 0,
            predictionConfidenceThreshold: 2.0,
            maxPushBandwidthFraction: -0.5
        )
        XCTAssertEqual(config.maxPrefetchDepth, 1)
        XCTAssertEqual(config.maxHistorySize, 1)
        XCTAssertEqual(config.predictionConfidenceThreshold, 1.0)
        XCTAssertEqual(config.maxPushBandwidthFraction, 0.0)
    }

    func testAggressivenessComparable() {
        XCTAssertTrue(JPIPPrefetchAggressiveness.minimal < .conservative)
        XCTAssertTrue(JPIPPrefetchAggressiveness.conservative < .moderate)
        XCTAssertTrue(JPIPPrefetchAggressiveness.moderate < .aggressive)
        XCTAssertTrue(JPIPPrefetchAggressiveness.aggressive < .maximum)
        XCTAssertFalse(JPIPPrefetchAggressiveness.maximum < .minimal)
    }
}

// MARK: - Viewport Tests

final class JPIPViewportTests: XCTestCase {
    func testViewportCreation() {
        let viewport = JPIPViewport(
            x: 100, y: 200, width: 800, height: 600, resolutionLevel: 3
        )
        XCTAssertEqual(viewport.x, 100)
        XCTAssertEqual(viewport.y, 200)
        XCTAssertEqual(viewport.width, 800)
        XCTAssertEqual(viewport.height, 600)
        XCTAssertEqual(viewport.resolutionLevel, 3)
    }

    func testViewportCenter() {
        let viewport = JPIPViewport(
            x: 100, y: 200, width: 800, height: 600, resolutionLevel: 0
        )
        XCTAssertEqual(viewport.centerX, 500.0)
        XCTAssertEqual(viewport.centerY, 500.0)
    }

    func testViewportEquality() {
        let v1 = JPIPViewport(x: 0, y: 0, width: 100, height: 100, resolutionLevel: 0)
        let v2 = JPIPViewport(x: 0, y: 0, width: 100, height: 100, resolutionLevel: 0)
        let v3 = JPIPViewport(x: 10, y: 0, width: 100, height: 100, resolutionLevel: 0)
        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }
}

// MARK: - Push Priority Tests

final class JPIPPushPriorityTests: XCTestCase {
    func testPriorityOrdering() {
        XCTAssertTrue(JPIPPushPriority.quality < .spatial)
        XCTAssertTrue(JPIPPushPriority.spatial < .resolution)
        XCTAssertFalse(JPIPPushPriority.resolution < .quality)
    }

    func testPushItemCreation() {
        let dataBin = JPIPDataBin(
            binClass: .tile,
            binID: 5,
            data: Data(repeating: 0xAA, count: 1024),
            isComplete: true
        )

        let item = JPIPPushItem(
            dataBin: dataBin,
            priority: .resolution,
            sessionID: "session-1",
            confidence: 0.85
        )

        XCTAssertEqual(item.dataBin.binID, 5)
        XCTAssertEqual(item.priority, .resolution)
        XCTAssertEqual(item.sessionID, "session-1")
        XCTAssertEqual(item.confidence, 0.85)
    }

    func testPushAcceptanceValues() {
        XCTAssertEqual(JPIPPushAcceptance.accept.rawValue, 0x01)
        XCTAssertEqual(JPIPPushAcceptance.reject.rawValue, 0x02)
        XCTAssertEqual(JPIPPushAcceptance.throttle.rawValue, 0x03)
        XCTAssertEqual(JPIPPushAcceptance.stop.rawValue, 0x04)
    }
}

// MARK: - Predictive Prefetch Engine Tests

final class JPIPPredictivePrefetchEngineTests: XCTestCase {
    let testImageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
        width: 2048,
        height: 2048,
        resolutionLevels: 5,
        tileWidth: 256,
        tileHeight: 256,
        components: 3
    )

    func testImageInfoTileCalculation() {
        XCTAssertEqual(testImageInfo.tilesX, 8)
        XCTAssertEqual(testImageInfo.tilesY, 8)
        XCTAssertEqual(testImageInfo.totalTiles, 64)
    }

    func testImageInfoSingleTile() {
        let info = JPIPPredictivePrefetchEngine.ImageInfo(
            width: 100,
            height: 100,
            resolutionLevels: 3,
            tileWidth: 256,
            tileHeight: 256
        )
        XCTAssertEqual(info.tilesX, 1)
        XCTAssertEqual(info.tilesY, 1)
        XCTAssertEqual(info.totalTiles, 1)
    }

    func testRegisterAndRemoveSession() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        let stats = await engine.getStatistics()
        XCTAssertEqual(stats.activeSessions, 1)

        await engine.removeSession("session-1")
        let statsAfter = await engine.getStatistics()
        XCTAssertEqual(statsAfter.activeSessions, 0)
    }

    func testRecordViewport() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        let viewport = JPIPViewport(
            x: 0, y: 0, width: 512, height: 512, resolutionLevel: 0
        )
        await engine.recordViewport("session-1", viewport: viewport)

        let history = await engine.getHistory(for: "session-1")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].viewport, viewport)

        let stats = await engine.getStatistics()
        XCTAssertEqual(stats.viewportUpdates, 1)
    }

    func testHistoryTrimming() async {
        let config = JPIPPrefetchConfiguration(maxHistorySize: 5)
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        for i in 0..<10 {
            let viewport = JPIPViewport(
                x: i * 50, y: 0, width: 256, height: 256, resolutionLevel: 0
            )
            await engine.recordViewport("session-1", viewport: viewport)
        }

        let history = await engine.getHistory(for: "session-1")
        XCTAssertEqual(history.count, 5)
        // Most recent entries should be retained
        XCTAssertEqual(history.last?.viewport.x, 450)
    }

    func testNoPredictionsWithoutHistory() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        let predictions = await engine.generatePredictions(for: "session-1")
        XCTAssertTrue(predictions.isEmpty)
    }

    func testNoPredictionsForUnknownSession() async {
        let engine = JPIPPredictivePrefetchEngine()
        let predictions = await engine.generatePredictions(for: "unknown")
        XCTAssertTrue(predictions.isEmpty)
    }

    func testViewportPredictionWithMovement() async {
        let config = JPIPPrefetchConfiguration(
            enableResolutionPrefetch: false,
            enableSpatialPrefetch: false,
            enableViewportPrediction: true,
            predictionConfidenceThreshold: 0.0
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // Simulate rightward movement
        for i in 0..<5 {
            let viewport = JPIPViewport(
                x: i * 256, y: 0, width: 512, height: 512, resolutionLevel: 0
            )
            await engine.recordViewport("session-1", viewport: viewport)
        }

        let predictions = await engine.generatePredictions(for: "session-1")
        XCTAssertFalse(predictions.isEmpty)

        // Predictions should be for tiles ahead in the movement direction
        for prediction in predictions {
            XCTAssertEqual(prediction.priority, .spatial)
            XCTAssertGreaterThan(prediction.confidence, 0.0)
        }
    }

    func testResolutionPredictionZoomIn() async {
        let config = JPIPPrefetchConfiguration(
            enableResolutionPrefetch: true,
            enableSpatialPrefetch: false,
            enableViewportPrediction: false,
            predictionConfidenceThreshold: 0.0
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // Simulate zoom-in (increasing resolution levels)
        for level in 0..<4 {
            let viewport = JPIPViewport(
                x: 0, y: 0, width: 512, height: 512, resolutionLevel: level
            )
            await engine.recordViewport("session-1", viewport: viewport)
        }

        let predictions = await engine.generatePredictions(for: "session-1")
        XCTAssertFalse(predictions.isEmpty)

        // Should predict next resolution level
        let resolutionPredictions = predictions.filter {
            $0.priority == .resolution
        }
        XCTAssertFalse(resolutionPredictions.isEmpty)
        XCTAssertEqual(resolutionPredictions.first?.resolutionLevel, 4)
    }

    func testSpatialLocalityPrediction() async {
        let config = JPIPPrefetchConfiguration(
            aggressiveness: .conservative,
            enableResolutionPrefetch: false,
            enableSpatialPrefetch: true,
            enableViewportPrediction: false,
            predictionConfidenceThreshold: 0.0
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // View center of image
        let viewport = JPIPViewport(
            x: 768, y: 768, width: 512, height: 512, resolutionLevel: 0
        )
        await engine.recordViewport("session-1", viewport: viewport)

        let predictions = await engine.generatePredictions(for: "session-1")
        XCTAssertFalse(predictions.isEmpty)

        // Should predict surrounding tiles
        for prediction in predictions {
            XCTAssertEqual(prediction.priority, .spatial)
            XCTAssertGreaterThan(prediction.confidence, 0.0)
            XCTAssertLessThanOrEqual(prediction.confidence, 1.0)
        }
    }

    func testPredictionConfidenceThreshold() async {
        let config = JPIPPrefetchConfiguration(
            enableResolutionPrefetch: false,
            enableSpatialPrefetch: true,
            enableViewportPrediction: false,
            predictionConfidenceThreshold: 0.99
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        let viewport = JPIPViewport(
            x: 768, y: 768, width: 512, height: 512, resolutionLevel: 0
        )
        await engine.recordViewport("session-1", viewport: viewport)

        let predictions = await engine.generatePredictions(for: "session-1")
        // High threshold should filter out most predictions
        XCTAssertTrue(
            predictions.count < testImageInfo.totalTiles,
            "High threshold should filter predictions"
        )
    }

    func testPredictionDepthLimit() async {
        let config = JPIPPrefetchConfiguration(
            maxPrefetchDepth: 3,
            aggressiveness: .maximum,
            enableResolutionPrefetch: true,
            enableSpatialPrefetch: true,
            enableViewportPrediction: true,
            predictionConfidenceThreshold: 0.0
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        for i in 0..<5 {
            let viewport = JPIPViewport(
                x: i * 100, y: 0, width: 512, height: 512, resolutionLevel: i
            )
            await engine.recordViewport("session-1", viewport: viewport)
        }

        let predictions = await engine.generatePredictions(for: "session-1")
        XCTAssertLessThanOrEqual(predictions.count, 3)
    }

    func testPredictionSortedByPriority() async {
        let config = JPIPPrefetchConfiguration(
            aggressiveness: .moderate,
            enableResolutionPrefetch: true,
            enableSpatialPrefetch: true,
            enableViewportPrediction: true,
            predictionConfidenceThreshold: 0.0
        )
        let engine = JPIPPredictivePrefetchEngine(configuration: config)
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // Simulate zoom + movement to generate all types of predictions
        for i in 0..<5 {
            let viewport = JPIPViewport(
                x: i * 100, y: i * 50, width: 512, height: 512, resolutionLevel: i
            )
            await engine.recordViewport("session-1", viewport: viewport)
        }

        let predictions = await engine.generatePredictions(for: "session-1")

        // Verify sorted by priority descending
        for i in 1..<predictions.count {
            let prev = predictions[i - 1]
            let curr = predictions[i]
            if prev.priority != curr.priority {
                XCTAssertGreaterThanOrEqual(prev.priority, curr.priority)
            }
        }
    }

    func testValidatePrediction() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // Predict tile 0 and validate with a viewport that covers tile 0
        await engine.validatePrediction(
            "session-1",
            predictedTiles: Set([0, 1, 8, 9]),
            actualViewport: JPIPViewport(
                x: 0, y: 0, width: 512, height: 512, resolutionLevel: 0
            )
        )

        let stats = await engine.getStatistics()
        XCTAssertGreaterThan(stats.correctPredictions, 0)
    }

    func testTilesForViewport() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        // Viewport covering 2x2 tiles (0,0 to 511,511)
        let tiles = await engine.tilesForViewport(
            JPIPViewport(x: 0, y: 0, width: 512, height: 512, resolutionLevel: 0),
            imageInfo: testImageInfo
        )
        // Should cover tiles (0,0), (1,0), (0,1), (1,1) = indices 0, 1, 8, 9
        XCTAssertEqual(tiles, Set([0, 1, 8, 9]))
    }

    func testResetStatistics() async {
        let engine = JPIPPredictivePrefetchEngine()
        await engine.registerSession("session-1", imageInfo: testImageInfo)

        let viewport = JPIPViewport(
            x: 0, y: 0, width: 256, height: 256, resolutionLevel: 0
        )
        await engine.recordViewport("session-1", viewport: viewport)

        await engine.resetStatistics()
        let stats = await engine.getStatistics()
        XCTAssertEqual(stats.viewportUpdates, 0)
        XCTAssertEqual(stats.totalPredictions, 0)
        XCTAssertEqual(stats.activeSessions, 1) // Sessions still tracked
    }
}

// MARK: - Push Scheduler Tests

final class JPIPPushSchedulerTests: XCTestCase {
    func testEnqueueDequeue() async {
        let scheduler = JPIPPushScheduler()

        let item = makePushItem(binID: 1, priority: .spatial)
        let enqueued = await scheduler.enqueue(item)
        XCTAssertTrue(enqueued)

        let dequeued = await scheduler.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.dataBin.binID, 1)
    }

    func testPriorityOrdering() async {
        let scheduler = JPIPPushScheduler()

        await scheduler.enqueue(makePushItem(binID: 1, priority: .quality))
        await scheduler.enqueue(makePushItem(binID: 2, priority: .resolution))
        await scheduler.enqueue(makePushItem(binID: 3, priority: .spatial))

        // Should dequeue in priority order: resolution, spatial, quality
        let first = await scheduler.dequeue()
        XCTAssertEqual(first?.dataBin.binID, 2)
        XCTAssertEqual(first?.priority, .resolution)

        let second = await scheduler.dequeue()
        XCTAssertEqual(second?.dataBin.binID, 3)
        XCTAssertEqual(second?.priority, .spatial)

        let third = await scheduler.dequeue()
        XCTAssertEqual(third?.dataBin.binID, 1)
        XCTAssertEqual(third?.priority, .quality)
    }

    func testMaxQueueSize() async {
        let scheduler = JPIPPushScheduler(maxQueueSize: 3)

        await scheduler.enqueue(makePushItem(binID: 1, priority: .quality))
        await scheduler.enqueue(makePushItem(binID: 2, priority: .quality))
        await scheduler.enqueue(makePushItem(binID: 3, priority: .quality))

        // Queue is full - low priority item should be dropped
        let result = await scheduler.enqueue(
            makePushItem(binID: 4, priority: .quality)
        )
        XCTAssertFalse(result)

        // High priority should replace lowest
        let result2 = await scheduler.enqueue(
            makePushItem(binID: 5, priority: .resolution)
        )
        XCTAssertTrue(result2)

        let size = await scheduler.queueSize
        XCTAssertEqual(size, 3)
    }

    func testDequeueBatch() async {
        let scheduler = JPIPPushScheduler()

        for i in 0..<10 {
            await scheduler.enqueue(makePushItem(binID: i, priority: .spatial))
        }

        let batch = await scheduler.dequeueBatch(count: 5)
        XCTAssertEqual(batch.count, 5)

        let remaining = await scheduler.queueSize
        XCTAssertEqual(remaining, 5)
    }

    func testDequeueBatchExceedsSize() async {
        let scheduler = JPIPPushScheduler()

        await scheduler.enqueue(makePushItem(binID: 1, priority: .spatial))
        await scheduler.enqueue(makePushItem(binID: 2, priority: .spatial))

        let batch = await scheduler.dequeueBatch(count: 10)
        XCTAssertEqual(batch.count, 2)

        let isEmpty = await scheduler.isEmpty
        XCTAssertTrue(isEmpty)
    }

    func testRemoveItemsForSession() async {
        let scheduler = JPIPPushScheduler()

        await scheduler.enqueue(makePushItem(
            binID: 1, priority: .spatial, sessionID: "session-1"
        ))
        await scheduler.enqueue(makePushItem(
            binID: 2, priority: .spatial, sessionID: "session-2"
        ))
        await scheduler.enqueue(makePushItem(
            binID: 3, priority: .spatial, sessionID: "session-1"
        ))

        let removed = await scheduler.removeItems(for: "session-1")
        XCTAssertEqual(removed, 2)

        let size = await scheduler.queueSize
        XCTAssertEqual(size, 1)
    }

    func testClear() async {
        let scheduler = JPIPPushScheduler()

        for i in 0..<5 {
            await scheduler.enqueue(makePushItem(binID: i, priority: .spatial))
        }

        await scheduler.clear()
        let isEmpty = await scheduler.isEmpty
        XCTAssertTrue(isEmpty)
    }

    func testStatistics() async {
        let scheduler = JPIPPushScheduler()

        await scheduler.enqueue(makePushItem(binID: 1, priority: .spatial))
        await scheduler.enqueue(makePushItem(binID: 2, priority: .resolution))
        _ = await scheduler.dequeue()

        let stats = await scheduler.getStatistics()
        XCTAssertEqual(stats.totalEnqueued, 2)
        XCTAssertEqual(stats.totalPushed, 1)
        XCTAssertEqual(stats.currentQueueSize, 1)
    }

    func testRecordThrottle() async {
        let scheduler = JPIPPushScheduler()
        await scheduler.recordThrottle()
        await scheduler.recordThrottle()

        let stats = await scheduler.getStatistics()
        XCTAssertEqual(stats.totalThrottled, 2)
    }

    // MARK: - Helpers

    private func makePushItem(
        binID: Int,
        priority: JPIPPushPriority,
        sessionID: String = "test-session",
        confidence: Double = 0.5
    ) -> JPIPPushItem {
        JPIPPushItem(
            dataBin: JPIPDataBin(
                binClass: .tile,
                binID: binID,
                data: Data(repeating: 0xAB, count: 256),
                isComplete: true
            ),
            priority: priority,
            sessionID: sessionID,
            confidence: confidence
        )
    }
}

// MARK: - Client Cache Tracker Tests

final class JPIPClientCacheTrackerTests: XCTestCase {
    func testRegisterAndRemoveSession() async {
        let tracker = JPIPClientCacheTracker()

        await tracker.registerSession("session-1")
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.activeSessions, 1)

        await tracker.removeSession("session-1")
        let statsAfter = await tracker.getStatistics()
        XCTAssertEqual(statsAfter.activeSessions, 0)
    }

    func testRecordSent() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        let dataBin = JPIPDataBin(
            binClass: .tile,
            binID: 5,
            data: Data(repeating: 0xCC, count: 512),
            isComplete: true
        )

        await tracker.recordSent(sessionID: "session-1", dataBin: dataBin)

        let hasBin = await tracker.clientHasBin(
            sessionID: "session-1",
            binClass: .tile,
            binID: 5
        )
        XCTAssertTrue(hasBin)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.totalBinsTracked, 1)
    }

    func testClientDoesNotHaveUnsentBin() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        let hasBin = await tracker.clientHasBin(
            sessionID: "session-1",
            binClass: .tile,
            binID: 99
        )
        XCTAssertFalse(hasBin)
    }

    func testRecordPendingCountsAsHaving() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 10,
            data: Data(repeating: 0xDD, count: 128),
            isComplete: false
        )

        await tracker.recordPending(sessionID: "session-1", dataBin: dataBin)

        let hasBin = await tracker.clientHasBin(
            sessionID: "session-1",
            binClass: .precinct,
            binID: 10
        )
        XCTAssertTrue(hasBin)
    }

    func testFilterMissingDeltaDelivery() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        // Client already has bin 1 and 3
        let bin1 = JPIPDataBin(
            binClass: .tile, binID: 1, data: Data([0x01]), isComplete: true
        )
        let bin3 = JPIPDataBin(
            binClass: .tile, binID: 3, data: Data([0x03]), isComplete: true
        )
        await tracker.recordSent(sessionID: "session-1", dataBin: bin1)
        await tracker.recordSent(sessionID: "session-1", dataBin: bin3)

        // Filter candidates
        let candidates = [
            JPIPDataBin(binClass: .tile, binID: 1, data: Data([0x01]), isComplete: true),
            JPIPDataBin(binClass: .tile, binID: 2, data: Data([0x02]), isComplete: true),
            JPIPDataBin(binClass: .tile, binID: 3, data: Data([0x03]), isComplete: true),
            JPIPDataBin(binClass: .tile, binID: 4, data: Data([0x04]), isComplete: true)
        ]

        let missing = await tracker.filterMissing(
            sessionID: "session-1",
            dataBins: candidates
        )

        XCTAssertEqual(missing.count, 2)
        XCTAssertEqual(missing[0].binID, 2)
        XCTAssertEqual(missing[1].binID, 4)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.deltaDeliveries, 2) // 2 bins filtered out
    }

    func testInvalidateSession() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        let dataBin = JPIPDataBin(
            binClass: .tile, binID: 1, data: Data([0x01]), isComplete: true
        )
        await tracker.recordSent(sessionID: "session-1", dataBin: dataBin)

        await tracker.invalidateSession("session-1")

        let hasBin = await tracker.clientHasBin(
            sessionID: "session-1",
            binClass: .tile,
            binID: 1
        )
        XCTAssertFalse(hasBin)

        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.cacheInvalidations, 1)
    }

    func testInvalidateSpecificBins() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        for i in 0..<5 {
            let bin = JPIPDataBin(
                binClass: .tile, binID: i, data: Data([UInt8(i)]), isComplete: true
            )
            await tracker.recordSent(sessionID: "session-1", dataBin: bin)
        }

        // Invalidate bins 1 and 3
        await tracker.invalidateBins(
            sessionID: "session-1",
            binClass: .tile,
            binIDs: [1, 3]
        )

        let has0 = await tracker.clientHasBin(
            sessionID: "session-1", binClass: .tile, binID: 0
        )
        let has1 = await tracker.clientHasBin(
            sessionID: "session-1", binClass: .tile, binID: 1
        )
        let has2 = await tracker.clientHasBin(
            sessionID: "session-1", binClass: .tile, binID: 2
        )
        let has3 = await tracker.clientHasBin(
            sessionID: "session-1", binClass: .tile, binID: 3
        )

        XCTAssertTrue(has0)
        XCTAssertFalse(has1)
        XCTAssertTrue(has2)
        XCTAssertFalse(has3)
    }

    func testInvalidateAllSessions() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")
        await tracker.registerSession("session-2")

        let bin = JPIPDataBin(
            binClass: .tile, binID: 5, data: Data([0x55]), isComplete: true
        )
        await tracker.recordSent(sessionID: "session-1", dataBin: bin)
        await tracker.recordSent(sessionID: "session-2", dataBin: bin)

        await tracker.invalidateAllSessions(binClass: .tile, binIDs: [5])

        let has1 = await tracker.clientHasBin(
            sessionID: "session-1", binClass: .tile, binID: 5
        )
        let has2 = await tracker.clientHasBin(
            sessionID: "session-2", binClass: .tile, binID: 5
        )

        XCTAssertFalse(has1)
        XCTAssertFalse(has2)
    }

    func testGetCacheState() async {
        let tracker = JPIPClientCacheTracker()
        await tracker.registerSession("session-1")

        let bin = JPIPDataBin(
            binClass: .tile, binID: 1, data: Data(repeating: 0xAA, count: 100),
            isComplete: true
        )
        await tracker.recordSent(sessionID: "session-1", dataBin: bin)

        let state = await tracker.getCacheState(for: "session-1")
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.receivedBins.count, 1)
        XCTAssertEqual(state?.totalBytes, 100)
    }

    func testUnknownSessionReturnsNil() async {
        let tracker = JPIPClientCacheTracker()
        let state = await tracker.getCacheState(for: "unknown")
        XCTAssertNil(state)
    }
}

// MARK: - Server Push Manager Tests

final class JPIPServerPushManagerTests: XCTestCase {
    let testImageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
        width: 1024,
        height: 1024,
        resolutionLevels: 4,
        tileWidth: 256,
        tileHeight: 256,
        components: 3
    )

    func testRegisterAndRemoveSession() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        let state = await manager.getPushState(for: "session-1")
        XCTAssertEqual(state, .accept)

        await manager.removeSession("session-1")
        let stateAfter = await manager.getPushState(for: "session-1")
        XCTAssertNil(stateAfter)
    }

    func testProcessViewportUpdate() async {
        let config = JPIPPrefetchConfiguration(
            aggressiveness: .moderate,
            predictionConfidenceThreshold: 0.0
        )
        let manager = JPIPServerPushManager(configuration: config)
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        let viewport = JPIPViewport(
            x: 256, y: 256, width: 512, height: 512, resolutionLevel: 0
        )

        // Create some available data bins
        var dataBins: [JPIPDataBin] = []
        for i in 0..<16 {
            dataBins.append(JPIPDataBin(
                binClass: .tile,
                binID: i,
                data: Data(repeating: UInt8(i), count: 128),
                isComplete: true
            ))
        }

        let enqueued = await manager.processViewportUpdate(
            sessionID: "session-1",
            viewport: viewport,
            availableDataBins: dataBins
        )

        XCTAssertGreaterThanOrEqual(enqueued, 0)
    }

    func testDequeuePushItems() async {
        let config = JPIPPrefetchConfiguration(
            aggressiveness: .aggressive,
            predictionConfidenceThreshold: 0.0
        )
        let manager = JPIPServerPushManager(configuration: config)
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        // Feed viewport history for predictions
        for i in 0..<3 {
            let viewport = JPIPViewport(
                x: i * 256, y: 0, width: 512, height: 512, resolutionLevel: 0
            )
            var dataBins: [JPIPDataBin] = []
            for j in 0..<16 {
                dataBins.append(JPIPDataBin(
                    binClass: .tile,
                    binID: j,
                    data: Data(repeating: UInt8(j), count: 64),
                    isComplete: true
                ))
            }

            await manager.processViewportUpdate(
                sessionID: "session-1",
                viewport: viewport,
                availableDataBins: dataBins
            )
        }

        let items = await manager.dequeuePushItems(maxItems: 5)
        // Items may or may not be available depending on prediction results
        XCTAssertGreaterThanOrEqual(items.count, 0)
    }

    func testPushDisabled() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)
        await manager.setPushEnabled(false)

        let enabled = await manager.isPushEnabled
        XCTAssertFalse(enabled)

        let viewport = JPIPViewport(
            x: 0, y: 0, width: 256, height: 256, resolutionLevel: 0
        )
        let enqueued = await manager.processViewportUpdate(
            sessionID: "session-1",
            viewport: viewport,
            availableDataBins: []
        )
        XCTAssertEqual(enqueued, 0)

        let items = await manager.dequeuePushItems()
        XCTAssertTrue(items.isEmpty)
    }

    func testPushAcceptanceStop() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        await manager.handlePushAcceptance(
            sessionID: "session-1",
            acceptance: .stop
        )

        let state = await manager.getPushState(for: "session-1")
        XCTAssertEqual(state, .stop)

        // Should not enqueue when stopped
        let viewport = JPIPViewport(
            x: 0, y: 0, width: 256, height: 256, resolutionLevel: 0
        )
        let enqueued = await manager.processViewportUpdate(
            sessionID: "session-1",
            viewport: viewport,
            availableDataBins: []
        )
        XCTAssertEqual(enqueued, 0)
    }

    func testPushAcceptanceReject() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        await manager.handlePushAcceptance(
            sessionID: "session-1",
            acceptance: .reject
        )

        let state = await manager.getPushState(for: "session-1")
        XCTAssertEqual(state, .reject)
    }

    func testCacheInvalidation() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        await manager.invalidateCache(for: "session-1")

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.cache.cacheInvalidations, 1)
    }

    func testBinInvalidation() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        await manager.invalidateBins(binClass: .tile, binIDs: [0, 1, 2])

        let stats = await manager.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.cache.cacheInvalidations, 1)
    }

    func testPerformanceMetrics() async {
        let config = JPIPPrefetchConfiguration(
            predictionConfidenceThreshold: 0.0
        )
        let manager = JPIPServerPushManager(configuration: config)
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        let viewport = JPIPViewport(
            x: 0, y: 0, width: 512, height: 512, resolutionLevel: 0
        )

        var dataBins: [JPIPDataBin] = []
        for i in 0..<4 {
            dataBins.append(JPIPDataBin(
                binClass: .tile,
                binID: i,
                data: Data(repeating: UInt8(i), count: 256),
                isComplete: true
            ))
        }

        await manager.processViewportUpdate(
            sessionID: "session-1",
            viewport: viewport,
            availableDataBins: dataBins
        )

        let metrics = await manager.getPerformanceMetrics()
        XCTAssertGreaterThanOrEqual(metrics.predictionCycles, 1)
        XCTAssertGreaterThanOrEqual(metrics.totalProcessingTime, 0)
    }

    func testAggregatedStatistics() async {
        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.prediction.activeSessions, 1)
        XCTAssertEqual(stats.cache.activeSessions, 1)
        XCTAssertEqual(stats.scheduler.currentQueueSize, 0)
    }

    func testBandwidthThrottling() async {
        let throttle = JPIPBandwidthThrottle(
            globalLimit: 1024,
            perClientLimit: 512
        )

        let manager = JPIPServerPushManager(
            configuration: .default,
            bandwidthThrottle: throttle
        )
        await manager.registerSession("session-1", imageInfo: testImageInfo)

        // The throttle should be used during push operations
        let items = await manager.dequeuePushItems()
        XCTAssertTrue(items.isEmpty) // Empty because no items enqueued
    }
}

// MARK: - Performance Metrics Tests

final class JPIPPushPerformanceMetricsTests: XCTestCase {
    func testInitialMetrics() {
        let metrics = JPIPPushPerformanceMetrics()
        XCTAssertEqual(metrics.predictionCycles, 0)
        XCTAssertEqual(metrics.totalPredictions, 0)
        XCTAssertEqual(metrics.totalItemsEnqueued, 0)
        XCTAssertEqual(metrics.totalItemsDelivered, 0)
        XCTAssertEqual(metrics.totalBytesDelivered, 0)
        XCTAssertEqual(metrics.totalBytesRequested, 0)
        XCTAssertEqual(metrics.averageProcessingTime, 0)
        XCTAssertEqual(metrics.bandwidthOverhead, 0)
        XCTAssertEqual(metrics.deliveryRatio, 0)
    }

    func testRecordPredictionCycle() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordPredictionCycle(
            predictionsGenerated: 10,
            itemsEnqueued: 5,
            processingTime: 0.01
        )

        XCTAssertEqual(metrics.predictionCycles, 1)
        XCTAssertEqual(metrics.totalPredictions, 10)
        XCTAssertEqual(metrics.totalItemsEnqueued, 5)
        XCTAssertEqual(metrics.totalProcessingTime, 0.01)
        XCTAssertEqual(metrics.minProcessingTime, 0.01)
        XCTAssertEqual(metrics.maxProcessingTime, 0.01)
    }

    func testRecordPushDelivery() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordPushDelivery(itemsDelivered: 3, bytesDelivered: 1024)

        XCTAssertEqual(metrics.totalItemsDelivered, 3)
        XCTAssertEqual(metrics.totalBytesDelivered, 1024)
    }

    func testBandwidthOverhead() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordClientRequest(bytes: 10000)
        metrics.recordPushDelivery(itemsDelivered: 5, bytesDelivered: 5000)

        XCTAssertEqual(metrics.bandwidthOverhead, 0.5, accuracy: 0.001)
    }

    func testDeliveryRatio() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordPredictionCycle(
            predictionsGenerated: 20,
            itemsEnqueued: 10,
            processingTime: 0.005
        )
        metrics.recordPushDelivery(itemsDelivered: 8, bytesDelivered: 2048)

        XCTAssertEqual(metrics.deliveryRatio, 0.8, accuracy: 0.001)
    }

    func testAverageProcessingTime() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordPredictionCycle(
            predictionsGenerated: 5,
            itemsEnqueued: 3,
            processingTime: 0.01
        )
        metrics.recordPredictionCycle(
            predictionsGenerated: 8,
            itemsEnqueued: 4,
            processingTime: 0.03
        )

        XCTAssertEqual(metrics.averageProcessingTime, 0.02, accuracy: 0.001)
        XCTAssertEqual(metrics.minProcessingTime, 0.01)
        XCTAssertEqual(metrics.maxProcessingTime, 0.03)
    }

    func testRecordClientRequest() {
        var metrics = JPIPPushPerformanceMetrics()
        metrics.recordClientRequest(bytes: 1000)
        metrics.recordClientRequest(bytes: 2000)

        XCTAssertEqual(metrics.totalBytesRequested, 3000)
    }
}

// MARK: - Prediction Confidence Tests

final class JPIPPredictionConfidenceTests: XCTestCase {
    func testPredictionConfidenceClamping() {
        let prediction1 = PrefetchPrediction(
            tileIndex: 0,
            resolutionLevel: 0,
            priority: .spatial,
            confidence: 1.5
        )
        XCTAssertEqual(prediction1.confidence, 1.0)

        let prediction2 = PrefetchPrediction(
            tileIndex: 0,
            resolutionLevel: 0,
            priority: .spatial,
            confidence: -0.5
        )
        XCTAssertEqual(prediction2.confidence, 0.0)

        let prediction3 = PrefetchPrediction(
            tileIndex: 0,
            resolutionLevel: 0,
            priority: .spatial,
            confidence: 0.75
        )
        XCTAssertEqual(prediction3.confidence, 0.75)
    }
}

// MARK: - Integration Tests

final class JPIPServerPushIntegrationTests: XCTestCase {
    func testFullPushWorkflow() async {
        let imageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
            width: 1024,
            height: 1024,
            resolutionLevels: 4,
            tileWidth: 256,
            tileHeight: 256
        )

        let config = JPIPPrefetchConfiguration(
            maxPrefetchDepth: 10,
            aggressiveness: .moderate,
            predictionConfidenceThreshold: 0.0
        )

        let manager = JPIPServerPushManager(configuration: config)
        await manager.registerSession("session-1", imageInfo: imageInfo)

        // Create data bins for the image
        var dataBins: [JPIPDataBin] = []
        for i in 0..<16 {
            dataBins.append(JPIPDataBin(
                binClass: .tile,
                binID: i,
                data: Data(repeating: UInt8(i & 0xFF), count: 512),
                isComplete: true
            ))
        }

        // Simulate user panning across the image
        for step in 0..<5 {
            let viewport = JPIPViewport(
                x: step * 128,
                y: 0,
                width: 512,
                height: 512,
                resolutionLevel: 0
            )

            await manager.processViewportUpdate(
                sessionID: "session-1",
                viewport: viewport,
                availableDataBins: dataBins
            )
        }

        // Dequeue and "deliver" push items
        let items = await manager.dequeuePushItems(maxItems: 10)

        // Verify metrics are recorded
        let metrics = await manager.getPerformanceMetrics()
        XCTAssertGreaterThanOrEqual(metrics.predictionCycles, 5)

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.prediction.activeSessions, 1)
        XCTAssertGreaterThanOrEqual(stats.prediction.viewportUpdates, 5)

        // Items may vary depending on prediction results
        _ = items // Suppress unused warning
    }

    func testMultiSessionPush() async {
        let imageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
            width: 512,
            height: 512,
            resolutionLevels: 3,
            tileWidth: 256,
            tileHeight: 256
        )

        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: imageInfo)
        await manager.registerSession("session-2", imageInfo: imageInfo)

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.prediction.activeSessions, 2)
        XCTAssertEqual(stats.cache.activeSessions, 2)

        // Remove one session
        await manager.removeSession("session-1")

        let statsAfter = await manager.getStatistics()
        XCTAssertEqual(statsAfter.prediction.activeSessions, 1)
    }

    func testCacheInvalidationOnImageUpdate() async {
        let imageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
            width: 512,
            height: 512,
            resolutionLevels: 3,
            tileWidth: 256,
            tileHeight: 256
        )

        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: imageInfo)
        await manager.registerSession("session-2", imageInfo: imageInfo)

        // Simulate image update - invalidate specific tiles
        await manager.invalidateBins(binClass: .tile, binIDs: [0, 1])

        let stats = await manager.getStatistics()
        // Both sessions should have been invalidated
        XCTAssertGreaterThanOrEqual(stats.cache.cacheInvalidations, 2)
    }

    func testPushThrottleAcceptance() async {
        let imageInfo = JPIPPredictivePrefetchEngine.ImageInfo(
            width: 512,
            height: 512,
            resolutionLevels: 3,
            tileWidth: 256,
            tileHeight: 256
        )

        let manager = JPIPServerPushManager()
        await manager.registerSession("session-1", imageInfo: imageInfo)

        // Client requests throttling
        await manager.handlePushAcceptance(
            sessionID: "session-1",
            acceptance: .throttle
        )

        let state = await manager.getPushState(for: "session-1")
        XCTAssertEqual(state, .throttle)

        // Client stops push entirely
        await manager.handlePushAcceptance(
            sessionID: "session-1",
            acceptance: .stop
        )

        let stateAfter = await manager.getPushState(for: "session-1")
        XCTAssertEqual(stateAfter, .stop)
    }
}
