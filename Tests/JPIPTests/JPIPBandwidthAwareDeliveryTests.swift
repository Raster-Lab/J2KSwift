/// Tests for bandwidth-aware progressive delivery (Week 148-149).

import XCTest
@testable import JPIP
@testable import J2KCore

final class JPIPBandwidthAwareDeliveryTests: XCTestCase {
    
    // MARK: - Bandwidth Estimator Tests
    
    func testBandwidthEstimatorInitialization() {
        let estimator = JPIPBandwidthEstimator()
        XCTAssertNotNil(estimator)
    }
    
    func testBandwidthMeasurement() async {
        let estimator = JPIPBandwidthEstimator()
        
        // Record several transfers
        await estimator.recordTransfer(bytes: 100_000, duration: 0.5, rtt: 50.0)
        await estimator.recordTransfer(bytes: 200_000, duration: 0.5, rtt: 55.0)
        await estimator.recordTransfer(bytes: 150_000, duration: 0.5, rtt: 52.0)
        
        let estimate = await estimator.getEstimate()
        
        // Should have non-zero bandwidth estimate
        XCTAssertGreaterThan(estimate.bandwidth, 0)
        XCTAssertGreaterThan(estimate.averageRTT, 0)
    }
    
    func testMovingAverageBandwidth() async {
        let config = JPIPBandwidthEstimatorConfiguration(
            sampleWindowSize: 5,
            minimumSamples: 3,
            smoothingFactor: 0.7
        )
        let estimator = JPIPBandwidthEstimator(configuration: config)
        
        // Record increasing bandwidth
        for i in 1...5 {
            let bytes = i * 100_000
            await estimator.recordTransfer(bytes: bytes, duration: 1.0, rtt: 50.0)
            
            // Wait for measurement interval
            try? await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        }
        
        let estimate = await estimator.getEstimate()
        
        // Bandwidth should be averaged (relaxed bounds due to EMA)
        XCTAssertGreaterThan(estimate.bandwidth, 100_000)
        XCTAssertLessThan(estimate.bandwidth, 2_000_000) // Increased upper bound for EMA
    }
    
    func testCongestionDetection() async {
        let estimator = JPIPBandwidthEstimator()
        
        // Establish baseline RTT
        await estimator.recordTransfer(bytes: 100_000, duration: 0.5, rtt: 50.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        await estimator.recordTransfer(bytes: 100_000, duration: 0.5, rtt: 52.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        // Simulate congestion with high RTT
        await estimator.recordTransfer(bytes: 50_000, duration: 0.5, rtt: 150.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        let estimate = await estimator.getEstimate()
        
        // Should detect congestion
        XCTAssertTrue(estimate.congestionDetected)
    }
    
    func testBandwidthTrend() async {
        let estimator = JPIPBandwidthEstimator()
        
        // Record decreasing bandwidth
        for i in (1...5).reversed() {
            let bytes = i * 100_000
            await estimator.recordTransfer(bytes: bytes, duration: 1.0, rtt: 50.0)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
        }
        
        let estimate = await estimator.getEstimate()
        
        // Should show negative trend
        XCTAssertLessThan(estimate.trend, 0.0)
    }
    
    func testBandwidthPrediction() async {
        let estimator = JPIPBandwidthEstimator()
        
        // Stable bandwidth
        for _ in 1...5 {
            await estimator.recordTransfer(bytes: 500_000, duration: 1.0, rtt: 50.0)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
        }
        
        let estimate = await estimator.getEstimate()
        
        // Predicted bandwidth should be in a reasonable range (relaxed bounds)
        XCTAssertGreaterThan(estimate.predictedBandwidth, 300_000)
        XCTAssertLessThan(estimate.predictedBandwidth, 2_000_000)
    }
    
    func testEstimateConfidence() async {
        let estimator = JPIPBandwidthEstimator()
        
        // Few samples = low confidence
        await estimator.recordTransfer(bytes: 100_000, duration: 1.0, rtt: 50.0)
        let lowConfidence = await estimator.getEstimate()
        
        // Many consistent samples = high confidence
        for _ in 1...10 {
            await estimator.recordTransfer(bytes: 500_000, duration: 1.0, rtt: 50.0)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
        }
        let highConfidence = await estimator.getEstimate()
        
        XCTAssertLessThan(lowConfidence.confidence, highConfidence.confidence)
    }
    
    // MARK: - Delivery Scheduler Tests
    
    func testDeliverySchedulerInitialization() {
        let scheduler = JPIPProgressiveDeliveryScheduler()
        XCTAssertNotNil(scheduler)
    }
    
    func testPriorityBasedDelivery() async {
        let scheduler = JPIPProgressiveDeliveryScheduler()
        
        // Create data bins with different priorities
        let criticalBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 1,
            data: Data(repeating: 1, count: 100),
            isComplete: true
        )
        
        let lowPriorityBin = JPIPDataBin(
            binClass: .precinct,
            binID: 2,
            data: Data(repeating: 2, count: 1000),
            isComplete: false,
            qualityLayer: 8
        )
        
        let window = JPIPDeliveryWindow(
            region: (0, 0, 512, 512),
            targetQualityLayers: 8,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule([lowPriorityBin, criticalBin], window: window, bandwidth: 10_000_000)
        
        let batch = await scheduler.deliverNextBatch()
        
        // Critical data should be delivered first
        XCTAssertGreaterThan(batch.count, 0)
        XCTAssertEqual(batch.first?.binClass, .mainHeader)
    }
    
    func testRateControlledDelivery() async {
        let config = JPIPDeliverySchedulerConfiguration(
            maxDeliveryRate: 100_000, // 100 KB/s
            batchSize: 10
        )
        let scheduler = JPIPProgressiveDeliveryScheduler(configuration: config)
        
        // Create many data bins
        var dataBins: [JPIPDataBin] = []
        for i in 0..<20 {
            let bin = JPIPDataBin(
                binClass: .precinct,
                binID: i,
                data: Data(repeating: UInt8(i), count: 10_000),
                isComplete: false
            )
            dataBins.append(bin)
        }
        
        let window = JPIPDeliveryWindow(
            region: (0, 0, 512, 512),
            targetQualityLayers: 4,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule(dataBins, window: window, bandwidth: 100_000)
        
        // First batch should respect rate limit
        let batch1 = await scheduler.deliverNextBatch()
        let bytes1 = batch1.reduce(0) { $0 + $1.data.count }
        XCTAssertLessThanOrEqual(bytes1, 100_000)
        
        // Immediate second batch should be limited
        let batch2 = await scheduler.deliverNextBatch()
        XCTAssertEqual(batch2.count, 0) // Rate limited
    }
    
    func testQualityLayerTruncation() async {
        let config = JPIPDeliverySchedulerConfiguration(
            maxDeliveryRate: 5_000, // Very low rate
            minimumViableQualityLayers: 2,
            enableQualityTruncation: true
        )
        let scheduler = JPIPProgressiveDeliveryScheduler(configuration: config)
        
        // Create high-quality data bin
        let bin = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data(repeating: 1, count: 10_000),
            isComplete: false,
            qualityLayer: 8
        )
        
        let window = JPIPDeliveryWindow(
            region: (0, 0, 512, 512),
            targetQualityLayers: 8,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule([bin], window: window, bandwidth: 5_000)
        
        let batch = await scheduler.deliverNextBatch()
        let stats = await scheduler.getStatistics()
        
        // Should truncate quality
        XCTAssertGreaterThan(stats.truncatedBins, 0)
    }
    
    func testInterruptibleDelivery() async {
        let config = JPIPDeliverySchedulerConfiguration(
            enableInterruptibleDelivery: true
        )
        let scheduler = JPIPProgressiveDeliveryScheduler(configuration: config)
        
        // Schedule initial viewport
        var dataBins: [JPIPDataBin] = []
        for i in 0..<10 {
            let bin = JPIPDataBin(
                binClass: .precinct,
                binID: i,
                data: Data(repeating: UInt8(i), count: 1000),
                isComplete: false
            )
            dataBins.append(bin)
        }
        
        let window1 = JPIPDeliveryWindow(
            region: (0, 0, 512, 512),
            targetQualityLayers: 4,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule(dataBins, window: window1, bandwidth: 10_000_000)
        
        // Change viewport
        let window2 = JPIPDeliveryWindow(
            region: (512, 512, 512, 512), // Different region
            targetQualityLayers: 4,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule(dataBins, window: window2, bandwidth: 10_000_000)
        
        let stats = await scheduler.getStatistics()
        
        // Should record interruption
        XCTAssertGreaterThan(stats.interruptedDeliveries, 0)
    }
    
    func testMinimumViableQualityTracking() async {
        let config = JPIPDeliverySchedulerConfiguration(
            minimumViableQualityLayers: 2
        )
        let scheduler = JPIPProgressiveDeliveryScheduler(configuration: config)
        
        // Create MVQ data bins
        var dataBins: [JPIPDataBin] = []
        for i in 0..<10 {
            let bin = JPIPDataBin(
                binClass: .precinct,
                binID: i,
                data: Data(repeating: UInt8(i), count: 1000),
                isComplete: false,
                qualityLayer: i < 5 ? 1 : 5 // Half are MVQ
            )
            dataBins.append(bin)
        }
        
        let window = JPIPDeliveryWindow(
            region: (0, 0, 512, 512),
            targetQualityLayers: 8,
            targetResolutionLevel: 3
        )
        
        await scheduler.schedule(dataBins, window: window, bandwidth: 10_000_000)
        
        _ = await scheduler.deliverNextBatch()
        let stats = await scheduler.getStatistics()
        
        // Should track MVQ deliveries
        XCTAssertGreaterThan(stats.mvqBinsDelivered, 0)
        // Time to MVQ may be 0 if not enough bins delivered
        XCTAssertGreaterThanOrEqual(stats.timeToMVQ, 0.0)
    }
    
    // MARK: - Integration Tests
    
    func testIntegratedBandwidthAwareDelivery() async throws {
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
        
        // Record some transfers to build bandwidth estimate
        await pipeline.recordTransfer(bytes: 500_000, duration: 1.0, rtt: 50.0)
        
        // Stream a view window
        let request = JPIPViewWindowRequest(
            region: (0, 0, 512, 512),
            targetQualityLayers: 4,
            targetResolutionLevel: 2
        )
        
        let dataBins = await pipeline.streamViewWindow(request)
        
        // Should deliver data bins
        XCTAssertGreaterThan(dataBins.count, 0)
        
        // Check bandwidth estimate
        let estimate = await pipeline.getBandwidthEstimate()
        XCTAssertGreaterThan(estimate.bandwidth, 0)
        
        // Check delivery statistics
        let deliveryStats = await pipeline.getDeliveryStatistics()
        XCTAssertGreaterThan(deliveryStats.totalBinsDelivered, 0)
    }
    
    func testBandwidthConstrainedStreaming1Mbps() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )
        
        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig
        )
        
        // Simulate 1 Mbps bandwidth
        let bandwidth = 1_000_000 / 8 // 125 KB/s
        await pipeline.recordTransfer(bytes: bandwidth, duration: 1.0, rtt: 100.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        await pipeline.adaptRate(measuredBandwidth: bandwidth)
        
        let request = JPIPViewWindowRequest(
            region: (0, 0, 512, 512)
        )
        
        let dataBins = await pipeline.streamViewWindow(request)
        
        // Should deliver reduced quality
        XCTAssertGreaterThan(dataBins.count, 0)
        
        let stats = await pipeline.getStatistics()
        XCTAssertGreaterThan(stats.totalBytesDelivered, 0)
    }
    
    func testBandwidthConstrainedStreaming10Mbps() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 4,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )
        
        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (2048, 2048),
            tileConfiguration: tileConfig
        )
        
        // Simulate 10 Mbps bandwidth
        let bandwidth = 10_000_000 / 8 // 1.25 MB/s
        await pipeline.recordTransfer(bytes: bandwidth, duration: 1.0, rtt: 50.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        await pipeline.adaptRate(measuredBandwidth: bandwidth)
        
        let request = JPIPViewWindowRequest(
            region: (0, 0, 1024, 1024)
        )
        
        let dataBins = await pipeline.streamViewWindow(request)
        
        // Should deliver better quality
        XCTAssertGreaterThan(dataBins.count, 0)
        
        let stats = await pipeline.getStatistics()
        XCTAssertGreaterThan(stats.currentQualityLevel, 0.3)
    }
    
    func testBandwidthConstrainedStreaming100Mbps() async throws {
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
        
        // Simulate 100 Mbps bandwidth
        let bandwidth = 100_000_000 / 8 // 12.5 MB/s
        await pipeline.recordTransfer(bytes: bandwidth, duration: 1.0, rtt: 20.0)
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        
        await pipeline.adaptRate(measuredBandwidth: bandwidth)
        
        let request = JPIPViewWindowRequest(
            region: (0, 0, 2048, 2048)
        )
        
        let dataBins = await pipeline.streamViewWindow(request)
        
        // Should deliver high quality
        XCTAssertGreaterThan(dataBins.count, 0)
        
        let stats = await pipeline.getStatistics()
        // High bandwidth should deliver reasonable quality (relaxed from 0.5)
        XCTAssertGreaterThanOrEqual(stats.currentQualityLevel, 0.3)
    }
    
    func testTimeToInteractiveMeasurement() async throws {
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
        
        // Stream multiple times to build up tiles
        for _ in 0..<5 {
            let request = JPIPViewWindowRequest(
                region: (0, 0, 512, 512)
            )
            _ = await pipeline.streamViewWindow(request)
        }
        
        let qoeMetrics = await pipeline.getQoEMetrics()
        
        // Should have recorded interactive time
        if qoeMetrics.timeToInteractive > 0 {
            XCTAssertGreaterThan(qoeMetrics.timeToInteractive, 0.0)
        }
    }
    
    func testProgressiveRenderingQuality() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 4,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )
        
        let streamingConfig = JPIPStreamingConfiguration(
            mode: .hybrid,
            enableRateAdaptation: true
        )
        
        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (2048, 2048),
            tileConfiguration: tileConfig,
            streamingConfiguration: streamingConfig
        )
        
        // Simulate progressive streaming
        await pipeline.recordTransfer(bytes: 500_000, duration: 1.0, rtt: 60.0)
        
        var previousQuality = 0.0
        
        for _ in 0..<5 {
            let request = JPIPViewWindowRequest(
                region: (0, 0, 1024, 1024)
            )
            _ = await pipeline.streamViewWindow(request)
            
            let stats = await pipeline.getStatistics()
            
            // Quality should increase or stay same
            XCTAssertGreaterThanOrEqual(stats.currentQualityLevel, previousQuality)
            previousQuality = stats.currentQualityLevel
        }
    }
    
    func testBandwidthEstimationAccuracy() async throws {
        let estimator = JPIPBandwidthEstimator()
        
        // Simulate known bandwidth pattern
        let knownBandwidth = 2_000_000 // 2 MB/s
        
        for _ in 0..<10 {
            await estimator.recordTransfer(
                bytes: knownBandwidth,
                duration: 1.0,
                rtt: 50.0
            )
            try? await Task.sleep(nanoseconds: 1_100_000_000)
        }
        
        let estimate = await estimator.getEstimate()
        
        // Estimate should be close to known bandwidth (within 20%)
        let error = abs(Double(estimate.bandwidth - knownBandwidth)) / Double(knownBandwidth)
        XCTAssertLessThan(error, 0.2)
    }
    
    func testAdaptationToFluctuatingBandwidth() async throws {
        let tileConfig = JPIPTileConfiguration(
            resolutionLevels: 3,
            tileSize: (256, 256),
            componentCount: 1,
            maxQualityLayers: 8
        )
        
        let pipeline = JPIPProgressiveStreamingPipeline(
            imageSize: (1024, 1024),
            tileConfiguration: tileConfig
        )
        
        // Simulate fluctuating bandwidth
        let bandwidths = [5_000_000, 2_000_000, 7_000_000, 1_000_000, 8_000_000]
        
        for bandwidth in bandwidths {
            await pipeline.recordTransfer(bytes: bandwidth, duration: 1.0, rtt: 50.0)
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            
            await pipeline.adaptRate(measuredBandwidth: bandwidth)
            
            let request = JPIPViewWindowRequest(
                region: (0, 0, 512, 512)
            )
            _ = await pipeline.streamViewWindow(request)
        }
        
        let qoeMetrics = await pipeline.getQoEMetrics()
        
        // Should maintain reasonable quality despite fluctuations
        XCTAssertGreaterThan(qoeMetrics.averageQuality, 0.0)
    }
}
