/// # JPIPProgressiveDeliveryScheduler
///
/// Progressive delivery scheduler for bandwidth-aware JPIP streaming.
///
/// Implements rate-controlled data bin emission with priority-based ordering,
/// quality layer truncation at bandwidth limits, and interruptible delivery.

import Foundation
import J2KCore

/// Delivery priority level.
public enum JPIPDeliveryPriority: Int, Sendable, Comparable {
    /// Critical data (must be delivered first).
    case critical = 4

    /// High priority data.
    case high = 3

    /// Medium priority data.
    case medium = 2

    /// Low priority data.
    case low = 1

    /// Background data (deferred refinement).
    case background = 0

    public static func < (lhs: JPIPDeliveryPriority, rhs: JPIPDeliveryPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Scheduled data bin for delivery.
public struct JPIPScheduledDataBin: Sendable {
    /// Data bin to deliver.
    public let dataBin: JPIPDataBin

    /// Delivery priority.
    public let priority: JPIPDeliveryPriority

    /// Estimated size in bytes.
    public let estimatedSize: Int

    /// Target quality layer (for truncation).
    public let targetQualityLayer: Int

    /// Tile identifier (for viewport tracking).
    public let tileID: String

    /// Whether this is minimum-viable-quality data.
    public let isMinimumViable: Bool

    /// Creates a scheduled data bin.
    public init(
        dataBin: JPIPDataBin,
        priority: JPIPDeliveryPriority,
        estimatedSize: Int,
        targetQualityLayer: Int,
        tileID: String,
        isMinimumViable: Bool = false
    ) {
        self.dataBin = dataBin
        self.priority = priority
        self.estimatedSize = estimatedSize
        self.targetQualityLayer = targetQualityLayer
        self.tileID = tileID
        self.isMinimumViable = isMinimumViable
    }
}

/// Delivery window for viewport changes.
public struct JPIPDeliveryWindow: Sendable {
    /// View region (x, y, width, height).
    public let region: (x: Int, y: Int, width: Int, height: Int)

    /// Target quality layers.
    public let targetQualityLayers: Int

    /// Target resolution level.
    public let targetResolutionLevel: Int

    /// Creates a delivery window.
    public init(
        region: (x: Int, y: Int, width: Int, height: Int),
        targetQualityLayers: Int,
        targetResolutionLevel: Int
    ) {
        self.region = region
        self.targetQualityLayers = targetQualityLayers
        self.targetResolutionLevel = targetResolutionLevel
    }
}

/// Delivery statistics.
public struct JPIPDeliveryStatistics: Sendable {
    /// Total data bins delivered.
    public var totalBinsDelivered: Int

    /// Total bytes delivered.
    public var totalBytesDelivered: Int

    /// Critical data bins delivered.
    public var criticalBinsDelivered: Int

    /// Minimum-viable-quality bins delivered.
    public var mvqBinsDelivered: Int

    /// Truncated bins (quality reduced).
    public var truncatedBins: Int

    /// Interrupted deliveries (viewport change).
    public var interruptedDeliveries: Int

    /// Average delivery rate (bytes per second).
    public var averageDeliveryRate: Double

    /// Time to first tile (milliseconds).
    public var timeToFirstTile: Double

    /// Time to minimum viable quality (milliseconds).
    public var timeToMVQ: Double

    /// Creates empty statistics.
    public init() {
        self.totalBinsDelivered = 0
        self.totalBytesDelivered = 0
        self.criticalBinsDelivered = 0
        self.mvqBinsDelivered = 0
        self.truncatedBins = 0
        self.interruptedDeliveries = 0
        self.averageDeliveryRate = 0.0
        self.timeToFirstTile = 0.0
        self.timeToMVQ = 0.0
    }
}

/// Configuration for delivery scheduler.
public struct JPIPDeliverySchedulerConfiguration: Sendable {
    /// Maximum delivery rate in bytes per second (nil = unlimited).
    public var maxDeliveryRate: Int?

    /// Minimum viable quality layers.
    public var minimumViableQualityLayers: Int

    /// Background refinement quality layers.
    public var backgroundRefinementLayers: Int

    /// Enable quality layer truncation.
    public var enableQualityTruncation: Bool

    /// Enable interruptible delivery.
    public var enableInterruptibleDelivery: Bool

    /// Delivery batch size.
    public var batchSize: Int

    /// Creates delivery scheduler configuration.
    ///
    /// - Parameters:
    ///   - maxDeliveryRate: Max delivery rate (default: nil).
    ///   - minimumViableQualityLayers: MVQ layers (default: 2).
    ///   - backgroundRefinementLayers: Background layers (default: 6).
    ///   - enableQualityTruncation: Enable truncation (default: true).
    ///   - enableInterruptibleDelivery: Enable interruption (default: true).
    ///   - batchSize: Batch size (default: 10).
    public init(
        maxDeliveryRate: Int? = nil,
        minimumViableQualityLayers: Int = 2,
        backgroundRefinementLayers: Int = 6,
        enableQualityTruncation: Bool = true,
        enableInterruptibleDelivery: Bool = true,
        batchSize: Int = 10
    ) {
        self.maxDeliveryRate = maxDeliveryRate
        self.minimumViableQualityLayers = minimumViableQualityLayers
        self.backgroundRefinementLayers = backgroundRefinementLayers
        self.enableQualityTruncation = enableQualityTruncation
        self.enableInterruptibleDelivery = enableInterruptibleDelivery
        self.batchSize = batchSize
    }
}

/// Progressive delivery scheduler for bandwidth-aware streaming.
///
/// Manages data bin delivery with rate control, priority-based ordering,
/// quality layer truncation, and support for viewport changes.
///
/// Example:
/// ```swift
/// let scheduler = JPIPProgressiveDeliveryScheduler()
///
/// // Schedule data bins
/// await scheduler.schedule(bins, window: window, bandwidth: 2_000_000)
///
/// // Deliver next batch
/// let batch = await scheduler.deliverNextBatch()
/// ```
public actor JPIPProgressiveDeliveryScheduler {
    /// Configuration.
    public let configuration: JPIPDeliverySchedulerConfiguration

    /// Scheduled data bins priority queue.
    private var queue: [JPIPScheduledDataBin]

    /// Current delivery window.
    private var currentWindow: JPIPDeliveryWindow?

    /// Current bandwidth estimate (bytes per second).
    private var currentBandwidth: Int

    /// Delivery statistics.
    private var statistics: JPIPDeliveryStatistics

    /// Start time for statistics.
    private let startTime: Date

    /// First tile delivery time.
    private var firstTileTime: Date?

    /// MVQ achieved time.
    private var mvqTime: Date?

    /// Last delivery time for rate control.
    private var lastDeliveryTime: Date?

    /// Bytes delivered in current interval.
    private var intervalBytesDelivered: Int

    /// Creates a progressive delivery scheduler.
    ///
    /// - Parameter configuration: Scheduler configuration.
    public init(configuration: JPIPDeliverySchedulerConfiguration = JPIPDeliverySchedulerConfiguration()) {
        self.configuration = configuration
        self.queue = []
        self.currentBandwidth = 5_000_000 // Default: 5 MB/s
        self.statistics = JPIPDeliveryStatistics()
        self.startTime = Date()
        self.intervalBytesDelivered = 0
    }

    /// Schedules data bins for delivery.
    ///
    /// - Parameters:
    ///   - dataBins: Data bins to schedule.
    ///   - window: Delivery window.
    ///   - bandwidth: Current bandwidth estimate in bytes per second.
    public func schedule(
        _ dataBins: [JPIPDataBin],
        window: JPIPDeliveryWindow,
        bandwidth: Int
    ) {
        // Check for viewport change
        if let current = currentWindow {
            if current.region != window.region {
                handleViewportChange(newWindow: window)
            }
        }

        currentWindow = window
        currentBandwidth = bandwidth

        // Convert data bins to scheduled bins with priorities
        let scheduledBins = prioritizeDataBins(dataBins, window: window, bandwidth: bandwidth)

        // Add to queue
        queue.append(contentsOf: scheduledBins)

        // Sort by priority
        sortQueue()
    }

    /// Delivers next batch of data bins.
    ///
    /// Returns data bins respecting rate limits and priorities.
    ///
    /// - Returns: Array of data bins to deliver.
    public func deliverNextBatch() -> [JPIPDataBin] {
        guard !queue.isEmpty else { return [] }

        // Apply rate control
        let availableBytes = calculateAvailableBytes()
        guard availableBytes > 0 else { return [] }

        // Deliver batch respecting rate limit
        var batch: [JPIPDataBin] = []
        var batchSize = 0
        var binsDelivered = 0

        while !queue.isEmpty && binsDelivered < configuration.batchSize {
            let scheduled = queue.first!

            // Check if we can deliver this bin
            if batchSize + scheduled.estimatedSize > availableBytes {
                // Apply quality truncation if enabled
                if configuration.enableQualityTruncation {
                    if let truncated = truncateQuality(scheduled, availableBytes: availableBytes - batchSize) {
                        batch.append(truncated.dataBin)
                        batchSize += truncated.estimatedSize
                        statistics.truncatedBins += 1
                        queue.removeFirst()
                        binsDelivered += 1
                        continue
                    }
                }
                break
            }

            // Deliver bin
            batch.append(scheduled.dataBin)
            batchSize += scheduled.estimatedSize
            queue.removeFirst()
            binsDelivered += 1

            // Update statistics
            updateStatistics(scheduled: scheduled)
        }

        // Record delivery for rate control
        recordDelivery(bytes: batchSize)

        return batch
    }

    /// Updates bandwidth estimate.
    ///
    /// - Parameter bandwidth: New bandwidth estimate in bytes per second.
    public func updateBandwidth(_ bandwidth: Int) {
        currentBandwidth = bandwidth
    }

    /// Clears scheduled data bins.
    public func clear() {
        queue.removeAll()
        intervalBytesDelivered = 0
    }

    /// Gets delivery statistics.
    ///
    /// - Returns: Current delivery statistics.
    public func getStatistics() -> JPIPDeliveryStatistics {
        statistics
    }

    /// Gets queue size.
    ///
    /// - Returns: Number of scheduled data bins.
    public func getQueueSize() -> Int {
        queue.count
    }

    // MARK: - Private Methods

    /// Prioritizes data bins based on viewport and quality.
    private func prioritizeDataBins(
        _ dataBins: [JPIPDataBin],
        window: JPIPDeliveryWindow,
        bandwidth: Int
    ) -> [JPIPScheduledDataBin] {
        var scheduled: [JPIPScheduledDataBin] = []

        for dataBin in dataBins {
            // Determine priority based on data bin type and location
            let priority = determinePriority(dataBin: dataBin, window: window)

            // Check if this is minimum-viable-quality data
            let isMVQ = dataBin.classID == .precinct && dataBin.qualityLayer <= configuration.minimumViableQualityLayers

            // Estimate size
            let size = dataBin.data.count

            // Determine target quality layer
            let targetLayer = determineTargetQualityLayer(
                dataBin: dataBin,
                bandwidth: bandwidth,
                window: window
            )

            let scheduledBin = JPIPScheduledDataBin(
                dataBin: dataBin,
                priority: priority,
                estimatedSize: size,
                targetQualityLayer: targetLayer,
                tileID: "\(dataBin.tileIndex)",
                isMinimumViable: isMVQ
            )

            scheduled.append(scheduledBin)
        }

        return scheduled
    }

    /// Determines delivery priority for a data bin.
    private func determinePriority(dataBin: JPIPDataBin, window: JPIPDeliveryWindow) -> JPIPDeliveryPriority {
        // Main header and tile headers are critical
        if dataBin.classID == .mainHeader || dataBin.classID == .tileHeader {
            return .critical
        }

        // Minimum-viable-quality precincts are high priority
        if dataBin.classID == .precinct && dataBin.qualityLayer <= configuration.minimumViableQualityLayers {
            return .high
        }

        // Mid-quality layers are medium priority
        if dataBin.classID == .precinct && dataBin.qualityLayer <= configuration.minimumViableQualityLayers + 2 {
            return .medium
        }

        // Background refinement is low priority
        if dataBin.classID == .precinct && dataBin.qualityLayer <= configuration.backgroundRefinementLayers {
            return .low
        }

        // Everything else is background
        return .background
    }

    /// Determines target quality layer based on bandwidth.
    private func determineTargetQualityLayer(
        dataBin: JPIPDataBin,
        bandwidth: Int,
        window: JPIPDeliveryWindow
    ) -> Int {
        // Low bandwidth: deliver only MVQ
        if bandwidth < 1_000_000 {
            return configuration.minimumViableQualityLayers
        }

        // Medium bandwidth: deliver up to mid-quality
        if bandwidth < 5_000_000 {
            return configuration.minimumViableQualityLayers + 2
        }

        // High bandwidth: deliver full quality
        return window.targetQualityLayers
    }

    /// Truncates quality layer for a scheduled bin.
    private func truncateQuality(_ scheduled: JPIPScheduledDataBin, availableBytes: Int) -> JPIPScheduledDataBin? {
        // Can only truncate precinct data
        guard scheduled.dataBin.classID == .precinct else { return nil }

        // Already at minimum quality
        guard scheduled.dataBin.qualityLayer > configuration.minimumViableQualityLayers else { return nil }

        // Estimate truncated size (proportional to quality layers)
        let truncatedLayers = configuration.minimumViableQualityLayers
        let originalLayers = scheduled.dataBin.qualityLayer
        let truncatedSize = (scheduled.estimatedSize * truncatedLayers) / max(1, originalLayers)

        guard truncatedSize <= availableBytes else { return nil }

        // Create truncated data bin
        let truncatedData = Data(scheduled.dataBin.data.prefix(truncatedSize))
        var truncatedBin = scheduled.dataBin
        truncatedBin.data = truncatedData
        truncatedBin.qualityLayer = truncatedLayers

        return JPIPScheduledDataBin(
            dataBin: truncatedBin,
            priority: scheduled.priority,
            estimatedSize: truncatedSize,
            targetQualityLayer: truncatedLayers,
            tileID: scheduled.tileID,
            isMinimumViable: true
        )
    }

    /// Handles viewport change by interrupting delivery.
    private func handleViewportChange(newWindow: JPIPDeliveryWindow) {
        guard configuration.enableInterruptibleDelivery else { return }

        statistics.interruptedDeliveries += 1

        // Reprioritize queue based on new viewport
        // For now, we'll just re-sort; in a full implementation,
        // we might discard out-of-viewport background tiles
        sortQueue()
    }

    /// Sorts queue by priority.
    private func sortQueue() {
        queue.sort { lhs, rhs in
            // Higher priority first
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            // MVQ first within same priority
            if lhs.isMinimumViable != rhs.isMinimumViable {
                return lhs.isMinimumViable
            }

            // Maintain original order
            return false
        }
    }

    /// Calculates available bytes for current interval.
    private func calculateAvailableBytes() -> Int {
        guard let maxRate = configuration.maxDeliveryRate else {
            return Int.max // Unlimited
        }

        let now = Date()

        // Reset interval every second
        if let last = lastDeliveryTime {
            if now.timeIntervalSince(last) >= 1.0 {
                intervalBytesDelivered = 0
            }
        }

        // Calculate remaining bytes for this interval
        let intervalLimit = min(maxRate, currentBandwidth)
        return max(0, intervalLimit - intervalBytesDelivered)
    }

    /// Records delivery for rate control.
    private func recordDelivery(bytes: Int) {
        intervalBytesDelivered += bytes
        lastDeliveryTime = Date()
    }

    /// Updates statistics for delivered bin.
    private func updateStatistics(scheduled: JPIPScheduledDataBin) {
        statistics.totalBinsDelivered += 1
        statistics.totalBytesDelivered += scheduled.estimatedSize

        if scheduled.priority == .critical {
            statistics.criticalBinsDelivered += 1
        }

        if scheduled.isMinimumViable {
            statistics.mvqBinsDelivered += 1
        }

        // Record first tile time
        if firstTileTime == nil && scheduled.dataBin.classID == .precinct {
            firstTileTime = Date()
            statistics.timeToFirstTile = Date().timeIntervalSince(startTime) * 1000.0
        }

        // Record MVQ time
        if mvqTime == nil && statistics.mvqBinsDelivered >= 10 {
            mvqTime = Date()
            statistics.timeToMVQ = Date().timeIntervalSince(startTime) * 1000.0
        }

        // Update average delivery rate
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0 {
            statistics.averageDeliveryRate = Double(statistics.totalBytesDelivered) / elapsed
        }
    }
}
