/// Tests for multi-resolution tiled streaming with adaptive quality.

import XCTest
@testable import JPIP
@testable import J2KCore

final class JPIPProgressiveStreamingTests: XCTestCase {
    // MARK: - Multi-Resolution Tile Manager Tests

    func testTileManagerInitialization() throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 5,
            tileSize: (256, 256),
            componentCount: 3,
            maxQualityLayers: 8
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (4096, 4096),
            configuration: config
        )

        XCTAssertNotNil(manager)
    }

    func testTileGeneration() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        // Get tiles at resolution level 2
        let tiles = await manager.getTilesForResolution(2)

        // At resolution 2, image is 256x256 (1024 / 2^2)
        // With tile size 64x64 (256 / 2^2), should have 4x4 = 16 tiles per component
        XCTAssertEqual(tiles.count, 16)

        // Verify all tiles have correct resolution level
        for tile in tiles {
            XCTAssertEqual(tile.resolutionLevel, 2)
        }
    }

    func testViewportUpdate() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        // Update viewport
        await manager.updateViewport((x: 0, y: 0, width: 512, height: 512))

        // Get priority queue
        let queue = await manager.getPriorityQueue()

        // Should have tiles prioritized
        XCTAssertFalse(queue.isEmpty)

        // First tiles should have higher priority
        if queue.count > 1 {
            XCTAssertGreaterThanOrEqual(queue[0].priority, queue[queue.count - 1].priority)
        }
    }

    func testTilePrioritization() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        // Set viewport to center region
        await manager.updateViewport((x: 256, y: 256, width: 512, height: 512))

        let queue = await manager.getPriorityQueue()

        // Find tiles in viewport center (should be critical or high priority)
        let centerTiles = queue.filter {
            $0.visibilityScore > 0.5 && $0.priority >= .high
        }

        XCTAssertFalse(centerTiles.isEmpty, "Should have high-priority tiles in viewport")
    }

    func testQualityLayerSelection() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        await manager.updateViewport((x: 0, y: 0, width: 512, height: 512))

        let queue = await manager.getPriorityQueue()
        guard let firstTile = queue.first else {
            XCTFail("Expected at least one tile")
            return
        }

        // High-priority tiles should get more quality layers
        let layers = await manager.getQualityLayers(for: firstTile.tile)
        XCTAssertGreaterThan(layers, 0)
        XCTAssertLessThanOrEqual(layers, config.maxQualityLayers)
    }

    func testGranularityAdjustment() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        // Default granularity
        let factor1 = await manager.getGranularityFactor()
        XCTAssertEqual(factor1, 1.0)

        // Increase granularity
        await manager.setGranularityFactor(2.0)
        let factor2 = await manager.getGranularityFactor()
        XCTAssertEqual(factor2, 2.0)
    }

    // MARK: - Adaptive Quality Engine Tests

    func testQualityEngineInitialization() {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5
        )

        XCTAssertNotNil(engine)
    }

    func testQualityDecisionHighBandwidth() async throws {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5
        )

        let bandwidthState = JPIPBandwidthState(
            availableBandwidth: 10_000_000  // 10 MB/s
        )

        let decision = await engine.determineQuality(
            bandwidthState: bandwidthState,
            targetLatency: 100.0
        )

        // High bandwidth should result in high quality
        // Note: due to smoothing, first decision starts from initial state
        XCTAssertGreaterThanOrEqual(decision.targetQualityLayers, 4)
        XCTAssertGreaterThanOrEqual(decision.targetResolutionLevel, 2)
        XCTAssertFalse(decision.useProgressiveMode)
    }

    func testQualityDecisionLowBandwidth() async throws {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5
        )

        let bandwidthState = JPIPBandwidthState(
            availableBandwidth: 500_000  // 500 KB/s
        )

        let decision = await engine.determineQuality(
            bandwidthState: bandwidthState,
            targetLatency: 100.0
        )

        // Low bandwidth should result in lower quality
        XCTAssertLessThanOrEqual(decision.targetQualityLayers, 3)
        XCTAssertTrue(decision.useProgressiveMode)
    }

    func testQualitySmoothing() async throws {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5,
            smoothingFactor: 0.8
        )

        // First decision with high bandwidth
        let highBandwidth = JPIPBandwidthState(availableBandwidth: 10_000_000)
        _ = await engine.determineQuality(bandwidthState: highBandwidth, targetLatency: 100.0)

        let quality1 = await engine.getCurrentQuality()

        // Sudden drop in bandwidth
        let lowBandwidth = JPIPBandwidthState(availableBandwidth: 1_000_000)
        _ = await engine.determineQuality(bandwidthState: lowBandwidth, targetLatency: 100.0)

        let quality2 = await engine.getCurrentQuality()

        // Quality should decrease smoothly, not drop immediately to minimum
        XCTAssertGreaterThan(quality2.layers, 1)
        XCTAssertLessThan(quality2.layers, quality1.layers)
    }

    func testQoEMetricsTracking() async throws {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5
        )

        // Record events
        await engine.recordFirstByte()
        await engine.recordInteractive()
        await engine.recordLatency(50.0)
        await engine.recordRebuffering()

        let metrics = await engine.getQoEMetrics()

        // Verify metrics are being tracked
        XCTAssertGreaterThan(metrics.timeToFirstByte, 0.0)
        XCTAssertGreaterThan(metrics.timeToInteractive, 0.0)
        XCTAssertGreaterThan(metrics.averageLatency, 0.0)
        XCTAssertEqual(metrics.rebufferingCount, 1)
    }

    func testCongestionDetection() async throws {
        let engine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: 8,
            maxResolutionLevels: 5
        )

        let congestedState = JPIPBandwidthState(
            availableBandwidth: 2_000_000,
            congestionDetected: true
        )

        let decision = await engine.determineQuality(
            bandwidthState: congestedState,
            targetLatency: 100.0
        )

        // Congestion should reduce resolution level
        XCTAssertLessThan(decision.targetResolutionLevel, 4)
    }

    // MARK: - Progressive Streaming Pipeline Tests

    func testPipelineInitialization() {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 5,
            tileSize: (256, 256),
            componentCount: 3,
            maxQualityLayers: 8
        )

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (4096, 4096),
            tileConfiguration: tileConfig
        )

        XCTAssertNotNil(pipeline)
    }

    func testResolutionProgressiveStreaming() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        var streamConfig = JPIPStreamingConfiguration()
        streamConfig.mode = .resolutionProgressive

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig,
            streamingConfiguration: streamConfig
        )

        let request = JPIPViewWindowRequest(
            region: (0, 0, 512, 512)
        )

        let dataBins = await pipeline.streamViewWindow(request)

        // Should generate data bins
        XCTAssertFalse(dataBins.isEmpty)

        // Verify bins are precinct bins
        for bin in dataBins {
            XCTAssertEqual(bin.binClass, .precinct)
        }
    }

    func testQualityProgressiveStreaming() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        var streamConfig = JPIPStreamingConfiguration()
        streamConfig.mode = .qualityProgressive

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig,
            streamingConfiguration: streamConfig
        )

        let request = JPIPViewWindowRequest(
            region: (0, 0, 512, 512)
        )

        let dataBins = await pipeline.streamViewWindow(request)

        XCTAssertFalse(dataBins.isEmpty)
    }

    func testHybridProgressiveStreaming() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        var streamConfig = JPIPStreamingConfiguration()
        streamConfig.mode = .hybrid

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig,
            streamingConfiguration: streamConfig
        )

        let request = JPIPViewWindowRequest(
            region: (0, 0, 512, 512)
        )

        let dataBins = await pipeline.streamViewWindow(request)

        XCTAssertFalse(dataBins.isEmpty)
    }

    func testBandwidthAdaptation() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig
        )

        // High bandwidth
        await pipeline.adaptRate(measuredBandwidth: 10_000_000)

        let request1 = JPIPViewWindowRequest(region: (0, 0, 512, 512))
        let bins1 = await pipeline.streamViewWindow(request1)

        // Low bandwidth
        await pipeline.adaptRate(measuredBandwidth: 500_000)

        let request2 = JPIPViewWindowRequest(region: (0, 0, 512, 512))
        let bins2 = await pipeline.streamViewWindow(request2)

        // Both should produce data, but potentially different amounts
        XCTAssertFalse(bins1.isEmpty)
        XCTAssertFalse(bins2.isEmpty)
    }

    func testStreamingStatistics() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig
        )

        let request = JPIPViewWindowRequest(region: (0, 0, 512, 512))
        _ = await pipeline.streamViewWindow(request)

        let stats = await pipeline.getStatistics()

        // Verify statistics are being tracked
        XCTAssertGreaterThan(stats.totalBytesDelivered, 0)
        XCTAssertGreaterThan(stats.totalTilesDelivered, 0)
        XCTAssertGreaterThan(stats.deliveryTimeMs, 0.0)
    }

    func testRoundTripTimeTracking() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig
        )

        await pipeline.updateRoundTripTime(50.0)

        let metrics = await pipeline.getQoEMetrics()
        XCTAssertGreaterThan(metrics.averageLatency, 0.0)
    }

    // MARK: - Integration Tests

    func testEndToEndProgressiveStreaming() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 4,
            tileSize: (256, 256),
            componentCount: 3,
            maxQualityLayers: 8
        )

        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (2048, 2048),
            tileConfiguration: tileConfig
        )

        // Simulate progressive viewport requests
        let viewports: [(x: Int, y: Int, width: Int, height: Int)] = [
            (0, 0, 512, 512),
            (256, 256, 512, 512),
            (512, 0, 512, 512)
        ]

        var totalDataDelivered = 0

        for viewport in viewports {
            let request = JPIPViewWindowRequest(region: viewport)
            let bins = await pipeline.streamViewWindow(request)

            XCTAssertFalse(bins.isEmpty)
            totalDataDelivered += bins.reduce(0) { $0 + $1.data.count }
        }

        XCTAssertGreaterThan(totalDataDelivered, 0)

        let stats = await pipeline.getStatistics()
        XCTAssertEqual(stats.totalBytesDelivered, totalDataDelivered)
    }

    func testMultipleResolutionLevels() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 5,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (8192, 8192),
            configuration: config
        )

        // Test each resolution level
        for level in 0..<5 {
            let tiles = await manager.getTilesForResolution(level)
            XCTAssertFalse(tiles.isEmpty, "No tiles at resolution \(level)")

            // Verify all tiles are at the correct level
            for tile in tiles {
                XCTAssertEqual(tile.resolutionLevel, level)
            }
        }
    }

    func testViewportVisibilityCalculation() async throws {
        let config = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 4
        )

        let manager = JPIPMultiResolutionTileManager(
            imageSize: (1024, 1024),
            configuration: config
        )

        // Set small viewport in corner
        await manager.updateViewport((x: 0, y: 0, width: 256, height: 256))

        let queue = await manager.getPriorityQueue()

        // Some tiles should be fully visible
        let fullyVisible = queue.filter { $0.visibilityScore > 0.9 }
        XCTAssertFalse(fullyVisible.isEmpty, "Expected some fully visible tiles")

        // Some tiles should be invisible
        let invisible = queue.filter { $0.visibilityScore == 0.0 }
        XCTAssertFalse(invisible.isEmpty, "Expected some invisible tiles")
    }
}
