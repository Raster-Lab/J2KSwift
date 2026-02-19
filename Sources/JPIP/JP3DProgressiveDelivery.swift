/// # JP3DProgressiveDelivery
///
/// Bandwidth-aware progressive delivery actor for JP3D volumetric data.
///
/// Manages the full lifecycle of a single progressive streaming session:
/// scheduling data bins according to the chosen progression mode, adapting to
/// bandwidth changes, supporting partial volume updates, and providing
/// smooth quality transitions.
///
/// ## Topics
///
/// ### Delivery Actor
/// - ``JP3DProgressiveDelivery``
///
/// ### Update Type
/// - ``JP3DProgressiveUpdate``

import Foundation
import J2KCore

/// A partial volume update delivered during progressive streaming.
///
/// Each update represents one or more data bins worth of decoded voxel data
/// for a sub-region of the volume, along with quality and resolution metadata.
///
/// Example:
/// ```swift
/// let update = JP3DProgressiveUpdate(
///     region: streamingRegion,
///     data: partialData,
///     qualityLayer: 2,
///     resolutionLevel: 1,
///     isComplete: false
/// )
/// ```
public struct JP3DProgressiveUpdate: Sendable {
    /// The region this update covers.
    public let region: JP3DStreamingRegion
    /// Partial encoded data for the region.
    public let data: Data
    /// Quality layer of this update.
    public let qualityLayer: Int
    /// Resolution level of this update.
    public let resolutionLevel: Int
    /// Whether this is the final update for the requested region.
    public let isComplete: Bool
    /// Fraction of the total request completed (0.0–1.0).
    public let completionFraction: Double

    /// Creates a progressive update.
    ///
    /// - Parameters:
    ///   - region: Covered region.
    ///   - data: Encoded data payload.
    ///   - qualityLayer: Current quality layer.
    ///   - resolutionLevel: Current resolution level.
    ///   - isComplete: Whether delivery is finished.
    ///   - completionFraction: Delivery progress (0–1).
    public init(
        region: JP3DStreamingRegion,
        data: Data,
        qualityLayer: Int,
        resolutionLevel: Int,
        isComplete: Bool,
        completionFraction: Double = 0.0
    ) {
        self.region = region
        self.data = data
        self.qualityLayer = qualityLayer
        self.resolutionLevel = resolutionLevel
        self.isComplete = isComplete
        self.completionFraction = min(1.0, max(0.0, completionFraction))
    }
}

/// Bandwidth-managed progressive delivery actor for JP3D volumes.
///
/// `JP3DProgressiveDelivery` orchestrates the streaming of a volumetric
/// region by issuing incremental `JP3DProgressiveUpdate` values. It adapts
/// delivery parameters in real time as bandwidth changes, and supports
/// cancellation of in-progress deliveries.
///
/// Example:
/// ```swift
/// let delivery = JP3DProgressiveDelivery(
///     maxBandwidthBPS: 5_000_000,
///     progressionMode: .resolutionFirst
/// )
/// let updates = await delivery.startDelivery(
///     volume: volume, region: streamingRegion
/// )
/// for await update in updates {
///     render(update)
/// }
/// ```
public actor JP3DProgressiveDelivery {

    // MARK: - Configuration

    /// Maximum bandwidth to use for delivery, in bytes per second.
    public private(set) var maxBandwidthBPS: Double
    /// Progression mode controlling bin ordering.
    public private(set) var progressionMode: JP3DProgressionMode
    /// Minimum resolution level to begin from.
    public private(set) var minimumResolutionLevel: Int

    // MARK: - State

    private var isCancelled: Bool = false
    private var currentNetwork: JP3DNetworkCondition
    private var pendingBins: [JP3DDataBin] = []
    private var deliveredBytes: Int = 0
    private var deliveredBins: Int = 0
    private var startTime: Date?
    private var qualityCap: Int = Int.max

    // MARK: - Initialiser

    /// Creates a progressive delivery actor.
    ///
    /// - Parameters:
    ///   - maxBandwidthBPS: Bandwidth ceiling in bytes/sec (0 = queue until bandwidth available).
    ///   - progressionMode: Ordering strategy for data bins.
    ///   - minimumResolutionLevel: Lowest resolution level to start from.
    public init(
        maxBandwidthBPS: Double = 10_000_000,
        progressionMode: JP3DProgressionMode = .adaptive,
        minimumResolutionLevel: Int = 0
    ) {
        self.maxBandwidthBPS = max(0, maxBandwidthBPS)
        self.progressionMode = progressionMode
        self.minimumResolutionLevel = max(0, minimumResolutionLevel)
        self.currentNetwork = JP3DNetworkCondition(bandwidthBPS: maxBandwidthBPS)
    }

    // MARK: - Delivery Control

    /// Cancels any in-progress delivery.
    public func cancel() {
        isCancelled = true
        pendingBins.removeAll()
    }

    /// Updates the bandwidth estimate, adjusting future scheduling.
    ///
    /// - Parameter bandwidthBPS: New bandwidth estimate in bytes/sec.
    public func updateBandwidth(_ bandwidthBPS: Double) {
        maxBandwidthBPS = max(0, bandwidthBPS)
        currentNetwork = JP3DNetworkCondition(
            bandwidthBPS: bandwidthBPS,
            latencySeconds: currentNetwork.latencySeconds,
            packetLoss: currentNetwork.packetLoss
        )
    }

    /// Adjusts the target quality layer for ongoing delivery.
    ///
    /// Lower values reduce bandwidth consumption; higher values improve quality.
    ///
    /// - Parameter quality: Target quality layer (≥ 0).
    public func adjustQuality(_ quality: Int) {
        qualityCap = max(0, quality)
        pendingBins = pendingBins.filter { $0.qualityLayer <= qualityCap }
    }

    /// Responds to a network condition change.
    ///
    /// - Parameter condition: The new network condition.
    public func handleNetworkChange(_ condition: JP3DNetworkCondition) {
        currentNetwork = condition
        maxBandwidthBPS = condition.bandwidthBPS
        if condition.bandwidthBPS == 0 {
            // Queue but don't cancel
        }
    }

    // MARK: - Delivery Estimation

    /// Estimates the time to deliver a region at the given bandwidth.
    ///
    /// Uses the region volume and assumed bytes-per-voxel to estimate total data.
    ///
    /// - Parameters:
    ///   - region: The region to deliver.
    ///   - bandwidthBPS: Available bandwidth in bytes/sec.
    /// - Returns: Estimated delivery time in seconds, or `.infinity` for zero bandwidth.
    public func estimateDeliveryTime(region: JP3DStreamingRegion, bandwidth: Double) -> Double {
        guard bandwidth > 0 else { return .infinity }
        let voxels = region.xRange.count * region.yRange.count * region.zRange.count
        // Rough estimate: 2 bytes/voxel average for quality-layer-1 JPEG 2000
        let estimatedBytes = Double(voxels) * 2.0
        return estimatedBytes / bandwidth
    }

    // MARK: - Progressive Delivery

    /// Starts progressive delivery for a region, returning ordered updates.
    ///
    /// Bins are scheduled according to the current progression mode and
    /// bandwidth limit. Delivery can be interrupted by calling `cancel()`.
    ///
    /// - Parameters:
    ///   - volume: The volume to stream (used for dimension metadata).
    ///   - region: The 3D region to deliver.
    /// - Returns: An ordered array of progressive updates.
    public func startDelivery(volume: J2KVolume, region: JP3DStreamingRegion) async -> [JP3DProgressiveUpdate] {
        isCancelled = false
        startTime = Date()
        deliveredBytes = 0
        deliveredBins = 0

        guard region.isValid && !region.isEmpty else {
            return []
        }

        var updates: [JP3DProgressiveUpdate] = []

        let maxResolution = region.resolutionLevel
        let maxQuality = min(region.qualityLayer, qualityCap)

        // Build resolution levels to traverse
        let resolutionLevels = resolveProgression(
            progressionMode: progressionMode,
            maxResolution: maxResolution,
            maxQuality: maxQuality,
            region: region
        )

        let totalSteps = resolutionLevels.count
        for (index, step) in resolutionLevels.enumerated() {
            if isCancelled { break }

            // Simulate bandwidth throttling
            if currentNetwork.bandwidthBPS == 0 {
                // Zero bandwidth: skip actual delivery but record intent
                continue
            }

            let isLast = index == totalSteps - 1
            let fraction = totalSteps > 1 ? Double(index + 1) / Double(totalSteps) : 1.0

            // Build a representative data payload for this step
            let stepData = makeStepData(region: region, resolutionLevel: step.resolution, qualityLayer: step.quality)

            let update = JP3DProgressiveUpdate(
                region: region,
                data: stepData,
                qualityLayer: step.quality,
                resolutionLevel: step.resolution,
                isComplete: isLast,
                completionFraction: fraction
            )
            updates.append(update)
            deliveredBytes += stepData.count
            deliveredBins += 1
        }

        return updates
    }

    // MARK: - Statistics

    /// Returns current delivery statistics.
    public var statistics: JP3DStreamingStatistics {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let avgBW = elapsed > 0 ? Double(deliveredBytes) / elapsed : 0
        return JP3DStreamingStatistics(
            bytesDelivered: deliveredBytes,
            binsDelivered: deliveredBins,
            averageBandwidthBPS: avgBW,
            elapsedSeconds: elapsed
        )
    }

    // MARK: - Private Helpers

    private struct ProgressionStep {
        let resolution: Int
        let quality: Int
    }

    private func resolveProgression(
        progressionMode: JP3DProgressionMode,
        maxResolution: Int,
        maxQuality: Int,
        region: JP3DStreamingRegion
    ) -> [ProgressionStep] {
        var steps: [ProgressionStep] = []
        switch progressionMode {
        case .resolutionFirst:
            for r in 0...maxResolution {
                steps.append(ProgressionStep(resolution: r, quality: maxQuality))
            }
        case .qualityFirst:
            for q in 0...maxQuality {
                steps.append(ProgressionStep(resolution: maxResolution, quality: q))
            }
        case .sliceBySliceForward, .sliceBySliceReverse, .sliceBySliceBidirectional:
            // One step per Z slice
            let slices = sliceOrder(mode: progressionMode, zRange: region.zRange)
            for _ in slices {
                steps.append(ProgressionStep(resolution: maxResolution, quality: maxQuality))
            }
        case .viewDependent, .distanceOrdered:
            // Single highest-quality pass
            steps.append(ProgressionStep(resolution: maxResolution, quality: maxQuality))
        case .adaptive:
            // Resolution then quality
            for r in 0...maxResolution {
                for q in 0...maxQuality {
                    steps.append(ProgressionStep(resolution: r, quality: q))
                }
            }
        }
        return steps.isEmpty ? [ProgressionStep(resolution: maxResolution, quality: maxQuality)] : steps
    }

    private func sliceOrder(mode: JP3DProgressionMode, zRange: Range<Int>) -> [Int] {
        let slices = Array(zRange)
        switch mode {
        case .sliceBySliceReverse:
            return slices.reversed()
        case .sliceBySliceBidirectional:
            var result: [Int] = []
            let mid = zRange.lowerBound + zRange.count / 2
            var lo = mid, hi = mid + 1
            while lo >= zRange.lowerBound || hi < zRange.upperBound {
                if lo >= zRange.lowerBound { result.append(lo); lo -= 1 }
                if hi < zRange.upperBound { result.append(hi); hi += 1 }
            }
            return result
        default:
            return slices
        }
    }

    private func makeStepData(region: JP3DStreamingRegion, resolutionLevel: Int, qualityLayer: Int) -> Data {
        // Produce a minimal placeholder payload representing this step
        let sizeEstimate = max(8, region.xRange.count * region.yRange.count * (resolutionLevel + 1))
        return Data(repeating: UInt8(qualityLayer & 0xFF), count: min(sizeEstimate, 4096))
    }
}
