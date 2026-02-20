//
// JPIPAdaptiveQualityEngine.swift
// J2KSwift
//
/// # JPIPAdaptiveQualityEngine
///
/// Adaptive quality management for JPIP streaming.
///
/// Dynamically adjusts quality layer selection and resolution scaling
/// based on available bandwidth, tracks Quality of Experience (QoE)
/// metrics, and ensures smooth quality transitions during streaming.

import Foundation
import J2KCore

/// Quality of Experience (QoE) metrics.
public struct JPIPQoEMetrics: Sendable {
    /// Average quality level delivered (0.0-1.0).
    public var averageQuality: Double

    /// Quality stability (lower is better, measures variance).
    public var qualityStability: Double

    /// Average latency in milliseconds.
    public var averageLatency: Double

    /// Rebuffering events count.
    public var rebufferingCount: Int

    /// Time to first byte (ms).
    public var timeToFirstByte: Double

    /// Time to interactive (ms).
    public var timeToInteractive: Double

    /// Creates QoE metrics.
    public init(
        averageQuality: Double = 0.0,
        qualityStability: Double = 0.0,
        averageLatency: Double = 0.0,
        rebufferingCount: Int = 0,
        timeToFirstByte: Double = 0.0,
        timeToInteractive: Double = 0.0
    ) {
        self.averageQuality = averageQuality
        self.qualityStability = qualityStability
        self.averageLatency = averageLatency
        self.rebufferingCount = rebufferingCount
        self.timeToFirstByte = timeToFirstByte
        self.timeToInteractive = timeToInteractive
    }
}

/// Bandwidth state for adaptive streaming.
public struct JPIPBandwidthState: Sendable {
    /// Estimated available bandwidth in bytes per second.
    public var availableBandwidth: Int

    /// Bandwidth trend (positive = increasing, negative = decreasing).
    public var bandwidthTrend: Double

    /// Congestion detected flag.
    public var congestionDetected: Bool

    /// Network round-trip time in milliseconds.
    public var roundTripTime: Double

    /// Creates a bandwidth state.
    public init(
        availableBandwidth: Int,
        bandwidthTrend: Double = 0.0,
        congestionDetected: Bool = false,
        roundTripTime: Double = 0.0
    ) {
        self.availableBandwidth = availableBandwidth
        self.bandwidthTrend = bandwidthTrend
        self.congestionDetected = congestionDetected
        self.roundTripTime = roundTripTime
    }
}

/// Quality adjustment decision.
public struct JPIPQualityDecision: Sendable {
    /// Target quality layers (1-based).
    public let targetQualityLayers: Int

    /// Target resolution level (0 = lowest).
    public let targetResolutionLevel: Int

    /// Whether to use progressive mode.
    public let useProgressiveMode: Bool

    /// Estimated data size for this quality in bytes.
    public let estimatedDataSize: Int

    /// Creates a quality decision.
    public init(
        targetQualityLayers: Int,
        targetResolutionLevel: Int,
        useProgressiveMode: Bool,
        estimatedDataSize: Int
    ) {
        self.targetQualityLayers = targetQualityLayers
        self.targetResolutionLevel = targetResolutionLevel
        self.useProgressiveMode = useProgressiveMode
        self.estimatedDataSize = estimatedDataSize
    }
}

/// Adaptive quality engine for JPIP streaming.
///
/// Monitors bandwidth conditions and adjusts quality settings dynamically
/// to optimize user experience. Tracks QoE metrics and provides smooth
/// quality transitions.
///
/// Example:
/// ```swift
/// let engine = JPIPAdaptiveQualityEngine(
///     maxQualityLayers: 8,
///     maxResolutionLevels: 5
/// )
/// 
/// let bandwidthState = JPIPBandwidthState(availableBandwidth: 5_000_000)
/// let decision = await engine.determineQuality(
///     bandwidthState: bandwidthState,
///     targetLatency: 100.0
/// )
/// ```
public actor JPIPAdaptiveQualityEngine {
    /// Maximum quality layers available.
    public let maxQualityLayers: Int

    /// Maximum resolution levels available.
    public let maxResolutionLevels: Int

    /// Current quality state.
    private var currentQualityLayers: Int

    /// Current resolution level.
    private var currentResolutionLevel: Int

    /// QoE metrics tracker.
    private var qoeMetrics: JPIPQoEMetrics

    /// Quality history for stability calculation.
    private var qualityHistory: [Double]

    /// Maximum history size for moving averages.
    private let maxHistorySize: Int

    /// Smoothing factor for transitions (0.0-1.0, higher = smoother).
    private var smoothingFactor: Double

    /// Session start time.
    private let sessionStartTime: Date

    /// First byte received time.
    private var firstByteTime: Date?

    /// Interactive time (when first useful data is available).
    private var interactiveTime: Date?

    /// Creates an adaptive quality engine.
    ///
    /// - Parameters:
    ///   - maxQualityLayers: Maximum quality layers.
    ///   - maxResolutionLevels: Maximum resolution levels.
    ///   - smoothingFactor: Quality transition smoothing (0.0-1.0).
    public init(
        maxQualityLayers: Int,
        maxResolutionLevels: Int,
        smoothingFactor: Double = 0.7
    ) {
        self.maxQualityLayers = maxQualityLayers
        self.maxResolutionLevels = maxResolutionLevels
        self.currentQualityLayers = maxQualityLayers / 2
        self.currentResolutionLevel = maxResolutionLevels / 2
        self.qoeMetrics = JPIPQoEMetrics()
        self.qualityHistory = []
        self.maxHistorySize = 20
        self.smoothingFactor = max(0.0, min(1.0, smoothingFactor))
        self.sessionStartTime = Date()
    }

    /// Determines optimal quality settings based on bandwidth state.
    ///
    /// - Parameters:
    ///   - bandwidthState: Current bandwidth conditions.
    ///   - targetLatency: Target latency in milliseconds.
    /// - Returns: Quality decision with recommended settings.
    public func determineQuality(
        bandwidthState: JPIPBandwidthState,
        targetLatency: Double = 100.0
    ) -> JPIPQualityDecision {
        // Calculate target quality based on bandwidth
        let targetQuality = calculateTargetQuality(
            bandwidth: bandwidthState.availableBandwidth,
            rtt: bandwidthState.roundTripTime,
            targetLatency: targetLatency
        )

        // Apply smoothing to prevent abrupt changes
        let smoothedQuality = applySmoothing(targetQuality)

        // Determine resolution level
        let resolutionLevel = determineResolutionLevel(
            bandwidth: bandwidthState.availableBandwidth,
            congestionDetected: bandwidthState.congestionDetected
        )

        // Estimate data size
        let estimatedSize = estimateDataSize(
            qualityLayers: smoothedQuality.layers,
            resolutionLevel: resolutionLevel
        )

        // Update current state
        currentQualityLayers = smoothedQuality.layers
        currentResolutionLevel = resolutionLevel

        // Record quality for stability tracking
        recordQuality(smoothedQuality.normalizedQuality)

        return JPIPQualityDecision(
            targetQualityLayers: smoothedQuality.layers,
            targetResolutionLevel: resolutionLevel,
            useProgressiveMode: bandwidthState.availableBandwidth < 1_000_000,
            estimatedDataSize: estimatedSize
        )
    }

    /// Records first byte received.
    public func recordFirstByte() {
        if firstByteTime == nil {
            firstByteTime = Date()
            let ttfb = Date().timeIntervalSince(sessionStartTime) * 1000.0
            qoeMetrics.timeToFirstByte = ttfb
        }
    }

    /// Records interactive state achieved.
    public func recordInteractive() {
        if interactiveTime == nil {
            interactiveTime = Date()
            let tti = Date().timeIntervalSince(sessionStartTime) * 1000.0
            qoeMetrics.timeToInteractive = tti
        }
    }

    /// Records a rebuffering event.
    public func recordRebuffering() {
        qoeMetrics.rebufferingCount += 1
    }

    /// Records latency measurement.
    ///
    /// - Parameter latency: Latency in milliseconds.
    public func recordLatency(_ latency: Double) {
        // Exponential moving average
        if qoeMetrics.averageLatency == 0.0 {
            qoeMetrics.averageLatency = latency
        } else {
            qoeMetrics.averageLatency = 0.8 * qoeMetrics.averageLatency + 0.2 * latency
        }
    }

    /// Gets current QoE metrics.
    ///
    /// - Returns: Current QoE metrics.
    public func getQoEMetrics() -> JPIPQoEMetrics {
        qoeMetrics
    }

    /// Gets current quality settings.
    ///
    /// - Returns: Tuple of (quality layers, resolution level).
    public func getCurrentQuality() -> (layers: Int, resolutionLevel: Int) {
        (currentQualityLayers, currentResolutionLevel)
    }

    /// Sets smoothing factor for quality transitions.
    ///
    /// - Parameter factor: Smoothing factor (0.0-1.0, higher = smoother).
    public func setSmoothingFactor(_ factor: Double) {
        self.smoothingFactor = max(0.0, min(1.0, factor))
    }

    // MARK: - Private Methods

    /// Calculates target quality based on bandwidth and latency.
    private func calculateTargetQuality(
        bandwidth: Int,
        rtt: Double,
        targetLatency: Double
    ) -> (layers: Int, normalizedQuality: Double) {
        // Define bandwidth thresholds (bytes per second)
        let thresholds: [(bandwidth: Int, layers: Int)] = [
            (10_000_000, maxQualityLayers),          // 10 MB/s: max quality
            (5_000_000, maxQualityLayers * 3 / 4),   // 5 MB/s: 75% quality
            (2_000_000, maxQualityLayers / 2),       // 2 MB/s: 50% quality
            (1_000_000, maxQualityLayers / 3),       // 1 MB/s: 33% quality
            (500_000, maxQualityLayers / 4),         // 500 KB/s: 25% quality
            (0, 1)                                    // < 500 KB/s: minimum
        ]

        var targetLayers = 1
        for threshold in thresholds {
            if bandwidth >= threshold.bandwidth {
                targetLayers = threshold.layers
                break
            }
        }

        // Adjust for latency
        if rtt > targetLatency * 1.5 {
            targetLayers = max(1, targetLayers - 2)
        } else if rtt > targetLatency {
            targetLayers = max(1, targetLayers - 1)
        }

        let normalizedQuality = Double(targetLayers) / Double(maxQualityLayers)
        return (max(1, min(maxQualityLayers, targetLayers)), normalizedQuality)
    }

    /// Applies smoothing to quality transitions.
    private func applySmoothing(
        _ target: (layers: Int, normalizedQuality: Double)
    ) -> (layers: Int, normalizedQuality: Double) {
        // Exponential moving average
        let smoothedLayers = Int(
            smoothingFactor * Double(currentQualityLayers) +
            (1.0 - smoothingFactor) * Double(target.layers)
        )

        let clampedLayers = max(1, min(maxQualityLayers, smoothedLayers))
        let normalizedQuality = Double(clampedLayers) / Double(maxQualityLayers)

        return (clampedLayers, normalizedQuality)
    }

    /// Determines optimal resolution level based on bandwidth.
    private func determineResolutionLevel(
        bandwidth: Int,
        congestionDetected: Bool
    ) -> Int {
        var targetLevel: Int

        if bandwidth >= 10_000_000 {
            targetLevel = maxResolutionLevels - 1
        } else if bandwidth >= 5_000_000 {
            targetLevel = maxResolutionLevels - 2
        } else if bandwidth >= 2_000_000 {
            targetLevel = maxResolutionLevels / 2
        } else if bandwidth >= 1_000_000 {
            targetLevel = maxResolutionLevels / 3
        } else {
            targetLevel = 0
        }

        // Reduce resolution if congestion detected
        if congestionDetected {
            targetLevel = max(0, targetLevel - 1)
        }

        // Smooth resolution changes
        let smoothedLevel = Int(
            0.6 * Double(currentResolutionLevel) + 0.4 * Double(targetLevel)
        )

        return max(0, min(maxResolutionLevels - 1, smoothedLevel))
    }

    /// Estimates data size for given quality settings.
    private func estimateDataSize(qualityLayers: Int, resolutionLevel: Int) -> Int {
        // Rough estimation: each quality layer adds ~15% to base size
        // Each resolution level doubles the data
        let baseSize = 100_000 // 100 KB base
        let resolutionMultiplier = pow(2.0, Double(resolutionLevel))
        let qualityMultiplier = 1.0 + (Double(qualityLayers) * 0.15)

        return Int(Double(baseSize) * resolutionMultiplier * qualityMultiplier)
    }

    /// Records quality value for stability tracking.
    private func recordQuality(_ quality: Double) {
        qualityHistory.append(quality)

        if qualityHistory.count > maxHistorySize {
            qualityHistory.removeFirst()
        }

        updateQoEMetrics()
    }

    /// Updates QoE metrics based on quality history.
    private func updateQoEMetrics() {
        guard !qualityHistory.isEmpty else { return }

        // Calculate average quality
        let sum = qualityHistory.reduce(0.0, +)
        qoeMetrics.averageQuality = sum / Double(qualityHistory.count)

        // Calculate quality stability (standard deviation)
        if qualityHistory.count > 1 {
            let mean = qoeMetrics.averageQuality
            let variance = qualityHistory.reduce(0.0) { result, quality in
                let diff = quality - mean
                return result + (diff * diff)
            } / Double(qualityHistory.count)
            qoeMetrics.qualityStability = sqrt(variance)
        }
    }
}
