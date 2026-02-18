/// # JPIPProgressiveStreamingPipeline
///
/// Progressive streaming pipeline for multi-resolution tiled JPEG 2000 delivery.
///
/// Integrates multi-resolution tile management and adaptive quality engine
/// to provide efficient progressive streaming with real-time rate adaptation.

import Foundation
import J2KCore

/// Streaming mode for progressive delivery.
public enum JPIPStreamingMode: Sendable {
    /// Resolution-progressive: deliver low resolution first, then refine.
    case resolutionProgressive
    
    /// Quality-progressive: deliver low quality first, then enhance.
    case qualityProgressive
    
    /// Hybrid: combination of resolution and quality progression.
    case hybrid
}

/// Streaming statistics.
public struct JPIPStreamingStatistics: Sendable {
    /// Total bytes delivered.
    public var totalBytesDelivered: Int
    
    /// Total tiles delivered.
    public var totalTilesDelivered: Int
    
    /// Average delivery rate (bytes per second).
    public var averageDeliveryRate: Double
    
    /// Current quality level (0.0-1.0).
    public var currentQualityLevel: Double
    
    /// Current resolution level.
    public var currentResolutionLevel: Int
    
    /// Delivery time in milliseconds.
    public var deliveryTimeMs: Double
    
    /// Creates empty statistics.
    public init() {
        self.totalBytesDelivered = 0
        self.totalTilesDelivered = 0
        self.averageDeliveryRate = 0.0
        self.currentQualityLevel = 0.0
        self.currentResolutionLevel = 0
        self.deliveryTimeMs = 0.0
    }
}

/// Configuration for progressive streaming.
public struct JPIPStreamingConfiguration: Sendable {
    /// Streaming mode.
    public var mode: JPIPStreamingMode
    
    /// Target latency in milliseconds.
    public var targetLatency: Double
    
    /// Enable rate adaptation.
    public var enableRateAdaptation: Bool
    
    /// Minimum quality layers to deliver initially.
    public var minimumInitialLayers: Int
    
    /// Maximum concurrent tile deliveries.
    public var maxConcurrentDeliveries: Int
    
    /// Creates streaming configuration.
    ///
    /// - Parameters:
    ///   - mode: Streaming mode (default: hybrid).
    ///   - targetLatency: Target latency in ms (default: 100).
    ///   - enableRateAdaptation: Enable rate adaptation (default: true).
    ///   - minimumInitialLayers: Minimum initial layers (default: 1).
    ///   - maxConcurrentDeliveries: Max concurrent deliveries (default: 4).
    public init(
        mode: JPIPStreamingMode = .hybrid,
        targetLatency: Double = 100.0,
        enableRateAdaptation: Bool = true,
        minimumInitialLayers: Int = 1,
        maxConcurrentDeliveries: Int = 4
    ) {
        self.mode = mode
        self.targetLatency = targetLatency
        self.enableRateAdaptation = enableRateAdaptation
        self.minimumInitialLayers = minimumInitialLayers
        self.maxConcurrentDeliveries = maxConcurrentDeliveries
    }
}

/// Request for streaming a specific view window.
public struct JPIPViewWindowRequest: Sendable {
    /// View window region (x, y, width, height).
    public let region: (x: Int, y: Int, width: Int, height: Int)
    
    /// Target quality layers.
    public let targetQualityLayers: Int?
    
    /// Target resolution level.
    public let targetResolutionLevel: Int?
    
    /// Component indices to request.
    public let components: [Int]?
    
    /// Creates a view window request.
    ///
    /// - Parameters:
    ///   - region: View window region.
    ///   - targetQualityLayers: Optional target quality layers.
    ///   - targetResolutionLevel: Optional target resolution level.
    ///   - components: Optional component indices.
    public init(
        region: (x: Int, y: Int, width: Int, height: Int),
        targetQualityLayers: Int? = nil,
        targetResolutionLevel: Int? = nil,
        components: [Int]? = nil
    ) {
        self.region = region
        self.targetQualityLayers = targetQualityLayers
        self.targetResolutionLevel = targetResolutionLevel
        self.components = components
    }
}

/// Progressive streaming pipeline for JPIP.
///
/// Orchestrates multi-resolution tiled streaming with adaptive quality
/// based on bandwidth conditions. Supports resolution-progressive,
/// quality-progressive, and hybrid streaming modes.
///
/// Example:
/// ```swift
/// let tileConfig = JPIPTileConfiguration(
///     resolutionLevels: 5,
///     tileSize: (256, 256),
///     componentCount: 3,
///     maxQualityLayers: 8
/// )
/// 
/// let pipeline = JPIPProgressiveStreamingPipeline(
///     imageSize: (4096, 4096),
///     tileConfiguration: tileConfig
/// )
/// 
/// let request = JPIPViewWindowRequest(region: (0, 0, 1024, 1024))
/// let dataBins = await pipeline.streamViewWindow(request)
/// ```
public actor JPIPProgressiveStreamingPipeline {
    /// Tile manager.
    private let tileManager: JPIPMultiResolutionTileManager
    
    /// Adaptive quality engine.
    private let qualityEngine: JPIPAdaptiveQualityEngine
    
    /// Bandwidth estimator.
    private let bandwidthEstimator: JPIPBandwidthEstimator
    
    /// Delivery scheduler.
    private let deliveryScheduler: JPIPProgressiveDeliveryScheduler
    
    /// Streaming configuration.
    public var configuration: JPIPStreamingConfiguration
    
    /// Current bandwidth state.
    private var bandwidthState: JPIPBandwidthState
    
    /// Streaming statistics.
    private var statistics: JPIPStreamingStatistics
    
    /// Start time for rate calculation.
    private var streamingStartTime: Date?
    
    /// Data bin generator.
    private let dataBinGenerator: JPIPDataBinGenerator
    
    /// Creates a progressive streaming pipeline.
    ///
    /// - Parameters:
    ///   - imageSize: Image dimensions at full resolution.
    ///   - tileConfiguration: Tile configuration.
    ///   - streamingConfiguration: Streaming configuration.
    public init(
        imageSize: (width: Int, height: Int),
        tileConfiguration: JPIPTileConfiguration,
        streamingConfiguration: JPIPStreamingConfiguration = JPIPStreamingConfiguration()
    ) {
        self.tileManager = JPIPMultiResolutionTileManager(
            imageSize: imageSize,
            configuration: tileConfiguration
        )
        self.qualityEngine = JPIPAdaptiveQualityEngine(
            maxQualityLayers: tileConfiguration.maxQualityLayers,
            maxResolutionLevels: tileConfiguration.resolutionLevels
        )
        self.bandwidthEstimator = JPIPBandwidthEstimator()
        self.deliveryScheduler = JPIPProgressiveDeliveryScheduler()
        self.configuration = streamingConfiguration
        self.bandwidthState = JPIPBandwidthState(availableBandwidth: 5_000_000)
        self.statistics = JPIPStreamingStatistics()
        self.dataBinGenerator = JPIPDataBinGenerator()
    }
    
    /// Streams a view window progressively.
    ///
    /// Generates prioritized data bins for the requested view window,
    /// adapting quality and resolution based on bandwidth conditions.
    ///
    /// - Parameter request: View window request.
    /// - Returns: Array of data bins to deliver.
    public func streamViewWindow(_ request: JPIPViewWindowRequest) async -> [JPIPDataBin] {
        streamingStartTime = Date()
        
        // Update viewport in tile manager
        await tileManager.updateViewport(request.region)
        
        // Get bandwidth estimate
        let bandwidthEstimate = await bandwidthEstimator.getEstimate()
        
        // Update bandwidth state with estimate
        self.bandwidthState = JPIPBandwidthState(
            availableBandwidth: bandwidthEstimate.bandwidth,
            bandwidthTrend: bandwidthEstimate.trend,
            congestionDetected: bandwidthEstimate.congestionDetected,
            roundTripTime: bandwidthEstimate.averageRTT
        )
        
        // Determine quality settings
        let qualityDecision = await qualityEngine.determineQuality(
            bandwidthState: bandwidthState,
            targetLatency: configuration.targetLatency
        )
        
        // Get prioritized tiles
        let prioritizedTiles = await tileManager.getPriorityQueue()
        
        // Generate data bins based on streaming mode
        var dataBins: [JPIPDataBin] = []
        
        switch configuration.mode {
        case .resolutionProgressive:
            dataBins = generateResolutionProgressiveBins(
                tiles: prioritizedTiles,
                qualityDecision: qualityDecision
            )
        case .qualityProgressive:
            dataBins = generateQualityProgressiveBins(
                tiles: prioritizedTiles,
                qualityDecision: qualityDecision
            )
        case .hybrid:
            dataBins = generateHybridProgressiveBins(
                tiles: prioritizedTiles,
                qualityDecision: qualityDecision
            )
        }
        
        // Schedule data bins for delivery
        let deliveryWindow = JPIPDeliveryWindow(
            region: request.region,
            targetQualityLayers: request.targetQualityLayers ?? qualityDecision.targetQualityLayers,
            targetResolutionLevel: request.targetResolutionLevel ?? qualityDecision.targetResolutionLevel
        )
        
        await deliveryScheduler.schedule(
            dataBins,
            window: deliveryWindow,
            bandwidth: bandwidthEstimate.predictedBandwidth
        )
        
        // Get next batch from scheduler
        let deliveredBins = await deliveryScheduler.deliverNextBatch()
        
        // Update statistics
        updateStatistics(dataBins: deliveredBins, qualityDecision: qualityDecision)
        
        // Record first byte and interactive milestones
        if statistics.totalBytesDelivered == 0 && !deliveredBins.isEmpty {
            await qualityEngine.recordFirstByte()
        }
        
        if statistics.totalTilesDelivered >= 10 {
            await qualityEngine.recordInteractive()
        }
        
        return deliveredBins
    }
    
    /// Updates bandwidth state.
    ///
    /// - Parameter state: New bandwidth state.
    public func updateBandwidthState(_ state: JPIPBandwidthState) {
        self.bandwidthState = state
    }
    
    /// Gets current streaming statistics.
    ///
    /// - Returns: Streaming statistics.
    public func getStatistics() -> JPIPStreamingStatistics {
        return statistics
    }
    
    /// Gets current QoE metrics.
    ///
    /// - Returns: QoE metrics from quality engine.
    public func getQoEMetrics() async -> JPIPQoEMetrics {
        return await qualityEngine.getQoEMetrics()
    }
    
    /// Gets current bandwidth estimate.
    ///
    /// - Returns: Bandwidth estimate with trend and congestion info.
    public func getBandwidthEstimate() async -> JPIPBandwidthEstimate {
        return await bandwidthEstimator.getEstimate()
    }
    
    /// Gets delivery scheduler statistics.
    ///
    /// - Returns: Delivery statistics.
    public func getDeliveryStatistics() async -> JPIPDeliveryStatistics {
        return await deliveryScheduler.getStatistics()
    }
    
    /// Records a data transfer for bandwidth tracking.
    ///
    /// - Parameters:
    ///   - bytes: Number of bytes transferred.
    ///   - duration: Transfer duration in seconds.
    ///   - rtt: Round-trip time in milliseconds.
    public func recordTransfer(bytes: Int, duration: TimeInterval, rtt: Double) async {
        await bandwidthEstimator.recordTransfer(bytes: bytes, duration: duration, rtt: rtt)
    }
    
    /// Adapts streaming rate based on network conditions.
    ///
    /// - Parameter measuredBandwidth: Measured bandwidth in bytes per second.
    public func adaptRate(measuredBandwidth: Int) async {
        guard configuration.enableRateAdaptation else { return }
        
        // Record bandwidth measurement
        let duration = 1.0 // Assume 1-second measurement interval
        await bandwidthEstimator.recordTransfer(
            bytes: measuredBandwidth,
            duration: duration,
            rtt: bandwidthState.roundTripTime
        )
        
        // Get updated estimate
        let estimate = await bandwidthEstimator.getEstimate()
        
        self.bandwidthState = JPIPBandwidthState(
            availableBandwidth: estimate.bandwidth,
            bandwidthTrend: estimate.trend,
            congestionDetected: estimate.congestionDetected,
            roundTripTime: estimate.averageRTT
        )
        
        // Update delivery scheduler bandwidth
        await deliveryScheduler.updateBandwidth(estimate.predictedBandwidth)
        
        // Adjust tile granularity if congested
        if estimate.congestionDetected {
            await tileManager.setGranularityFactor(2.0)
        } else {
            await tileManager.setGranularityFactor(1.0)
        }
    }
    
    /// Updates round-trip time measurement.
    ///
    /// - Parameter rtt: Round-trip time in milliseconds.
    public func updateRoundTripTime(_ rtt: Double) async {
        self.bandwidthState = JPIPBandwidthState(
            availableBandwidth: bandwidthState.availableBandwidth,
            bandwidthTrend: bandwidthState.bandwidthTrend,
            congestionDetected: bandwidthState.congestionDetected,
            roundTripTime: rtt
        )
        
        await qualityEngine.recordLatency(rtt)
    }
    
    // MARK: - Private Methods
    
    /// Generates data bins in resolution-progressive mode.
    private func generateResolutionProgressiveBins(
        tiles: [JPIPPrioritizedTile],
        qualityDecision: JPIPQualityDecision
    ) -> [JPIPDataBin] {
        var bins: [JPIPDataBin] = []
        
        // Start from lowest resolution, progress upward
        for resLevel in 0...qualityDecision.targetResolutionLevel {
            let tilesAtResolution = tiles.filter { $0.tile.resolutionLevel == resLevel }
            
            // Prioritize by visibility
            let sortedTiles = tilesAtResolution.sorted { $0.priority > $1.priority }
            
            for prioritizedTile in sortedTiles.prefix(configuration.maxConcurrentDeliveries) {
                let layers = min(configuration.minimumInitialLayers, prioritizedTile.targetLayers)
                bins.append(contentsOf: createDataBinsForTile(
                    prioritizedTile.tile,
                    qualityLayers: layers
                ))
            }
        }
        
        return bins
    }
    
    /// Generates data bins in quality-progressive mode.
    private func generateQualityProgressiveBins(
        tiles: [JPIPPrioritizedTile],
        qualityDecision: JPIPQualityDecision
    ) -> [JPIPDataBin] {
        var bins: [JPIPDataBin] = []
        
        // Get tiles at target resolution
        let targetTiles = tiles.filter {
            $0.tile.resolutionLevel == qualityDecision.targetResolutionLevel
        }
        
        // Deliver progressively by quality layers
        for layer in 1...qualityDecision.targetQualityLayers {
            for prioritizedTile in targetTiles.prefix(configuration.maxConcurrentDeliveries) {
                if layer <= prioritizedTile.targetLayers {
                    bins.append(contentsOf: createDataBinsForTile(
                        prioritizedTile.tile,
                        qualityLayers: layer
                    ))
                }
            }
        }
        
        return bins
    }
    
    /// Generates data bins in hybrid progressive mode.
    private func generateHybridProgressiveBins(
        tiles: [JPIPPrioritizedTile],
        qualityDecision: JPIPQualityDecision
    ) -> [JPIPDataBin] {
        var bins: [JPIPDataBin] = []
        
        // First pass: low resolution, low quality for quick preview
        let previewResolution = max(0, qualityDecision.targetResolutionLevel - 2)
        let previewTiles = tiles.filter { $0.tile.resolutionLevel == previewResolution }
        
        for prioritizedTile in previewTiles.prefix(configuration.maxConcurrentDeliveries) {
            bins.append(contentsOf: createDataBinsForTile(
                prioritizedTile.tile,
                qualityLayers: configuration.minimumInitialLayers
            ))
        }
        
        // Second pass: target resolution with progressive quality
        let targetTiles = tiles.filter {
            $0.tile.resolutionLevel == qualityDecision.targetResolutionLevel &&
            $0.priority >= .normal
        }
        
        for prioritizedTile in targetTiles.prefix(configuration.maxConcurrentDeliveries) {
            let targetLayers = min(
                qualityDecision.targetQualityLayers,
                prioritizedTile.targetLayers
            )
            
            bins.append(contentsOf: createDataBinsForTile(
                prioritizedTile.tile,
                qualityLayers: targetLayers
            ))
        }
        
        return bins
    }
    
    /// Creates data bins for a specific tile.
    private func createDataBinsForTile(
        _ tile: JPIPTile,
        qualityLayers: Int
    ) -> [JPIPDataBin] {
        // Create synthetic data bins for the tile
        // In a real implementation, this would extract actual precinct data
        
        var bins: [JPIPDataBin] = []
        
        // Calculate tile ID (simplified)
        let tileID = tile.y * 100 + tile.x
        
        // Create a precinct data bin for each quality layer
        for layer in 0..<qualityLayers {
            let precinctID = tileID * 10 + layer
            let syntheticData = Data(repeating: UInt8(layer), count: 1024)
            
            bins.append(JPIPDataBin(
                binClass: .precinct,
                binID: precinctID,
                data: syntheticData,
                isComplete: layer == qualityLayers - 1
            ))
        }
        
        return bins
    }
    
    /// Updates streaming statistics.
    private func updateStatistics(
        dataBins: [JPIPDataBin],
        qualityDecision: JPIPQualityDecision
    ) {
        let bytesDelivered = dataBins.reduce(0) { $0 + $1.data.count }
        statistics.totalBytesDelivered += bytesDelivered
        statistics.totalTilesDelivered += dataBins.count
        
        if let startTime = streamingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            statistics.deliveryTimeMs = elapsed * 1000.0
            
            if elapsed > 0 {
                statistics.averageDeliveryRate = Double(statistics.totalBytesDelivered) / elapsed
            }
        }
        
        statistics.currentQualityLevel = Double(qualityDecision.targetQualityLayers) /
                                        Double(qualityEngine.maxQualityLayers)
        statistics.currentResolutionLevel = qualityDecision.targetResolutionLevel
    }
    
    /// Calculates bandwidth trend.
    private func calculateBandwidthTrend(_ measuredBandwidth: Int) -> Double {
        let currentBandwidth = bandwidthState.availableBandwidth
        if currentBandwidth == 0 { return 0.0 }
        
        return Double(measuredBandwidth - currentBandwidth) / Double(currentBandwidth)
    }
    
    /// Detects network congestion.
    private func detectCongestion(_ measuredBandwidth: Int) -> Bool {
        // Congestion if bandwidth dropped by more than 30%
        let threshold = Double(bandwidthState.availableBandwidth) * 0.7
        return Double(measuredBandwidth) < threshold
    }
}
