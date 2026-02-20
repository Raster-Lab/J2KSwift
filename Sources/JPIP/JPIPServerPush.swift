//
// JPIPServerPush.swift
// J2KSwift
//
/// # JPIPServerPush
///
/// Server-initiated push for predictive prefetching in JPIP.
///
/// Provides viewport prediction based on navigation history,
/// resolution-level prefetch heuristics, spatial locality-based
/// tile prediction, push priority scheduling, bandwidth-aware
/// throttling, and server-side client cache tracking with delta delivery.

import Foundation
import J2KCore

// MARK: - Prefetch Configuration

/// Aggressiveness level for predictive prefetching.
///
/// Controls how aggressively the server pushes data bins ahead
/// of explicit client requests.
public enum JPIPPrefetchAggressiveness: Int, Sendable, Comparable {
    /// Minimal prefetching - only immediate neighbors.
    case minimal = 1

    /// Conservative prefetching - small prediction window.
    case conservative = 2

    /// Moderate prefetching - balanced prediction.
    case moderate = 3

    /// Aggressive prefetching - large prediction window.
    case aggressive = 4

    /// Maximum prefetching - push as much as bandwidth allows.
    case maximum = 5

    public static func < (lhs: JPIPPrefetchAggressiveness,
                          rhs: JPIPPrefetchAggressiveness) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Configuration for the predictive prefetching engine.
public struct JPIPPrefetchConfiguration: Sendable {
    /// Maximum number of data bins to prefetch per prediction cycle.
    public let maxPrefetchDepth: Int

    /// Aggressiveness of prefetch predictions.
    public let aggressiveness: JPIPPrefetchAggressiveness

    /// Maximum number of navigation history entries to retain.
    public let maxHistorySize: Int

    /// Whether to enable resolution-level prefetching.
    public let enableResolutionPrefetch: Bool

    /// Whether to enable spatial locality-based tile prediction.
    public let enableSpatialPrefetch: Bool

    /// Whether to enable viewport prediction from navigation history.
    public let enableViewportPrediction: Bool

    /// Minimum confidence threshold for predictions (0.0 - 1.0).
    public let predictionConfidenceThreshold: Double

    /// Maximum bandwidth fraction to use for push (0.0 - 1.0).
    public let maxPushBandwidthFraction: Double

    /// Creates a new prefetch configuration.
    ///
    /// - Parameters:
    ///   - maxPrefetchDepth: Max data bins per cycle (default: 64).
    ///   - aggressiveness: Prefetch aggressiveness (default: .moderate).
    ///   - maxHistorySize: Max navigation history entries (default: 100).
    ///   - enableResolutionPrefetch: Enable resolution prefetch (default: true).
    ///   - enableSpatialPrefetch: Enable spatial prefetch (default: true).
    ///   - enableViewportPrediction: Enable viewport prediction (default: true).
    ///   - predictionConfidenceThreshold: Min confidence (default: 0.3).
    ///   - maxPushBandwidthFraction: Max bandwidth for push (default: 0.5).
    public init(
        maxPrefetchDepth: Int = 64,
        aggressiveness: JPIPPrefetchAggressiveness = .moderate,
        maxHistorySize: Int = 100,
        enableResolutionPrefetch: Bool = true,
        enableSpatialPrefetch: Bool = true,
        enableViewportPrediction: Bool = true,
        predictionConfidenceThreshold: Double = 0.3,
        maxPushBandwidthFraction: Double = 0.5
    ) {
        self.maxPrefetchDepth = max(1, maxPrefetchDepth)
        self.aggressiveness = aggressiveness
        self.maxHistorySize = max(1, maxHistorySize)
        self.enableResolutionPrefetch = enableResolutionPrefetch
        self.enableSpatialPrefetch = enableSpatialPrefetch
        self.enableViewportPrediction = enableViewportPrediction
        self.predictionConfidenceThreshold = max(0.0, min(1.0, predictionConfidenceThreshold))
        self.maxPushBandwidthFraction = max(0.0, min(1.0, maxPushBandwidthFraction))
    }

    /// Default configuration.
    public static let `default` = JPIPPrefetchConfiguration()
}

// MARK: - Viewport and Navigation

/// Represents a viewport into a JPEG 2000 image.
public struct JPIPViewport: Sendable, Equatable {
    /// X offset of the viewport in the image coordinate space.
    public let x: Int

    /// Y offset of the viewport in the image coordinate space.
    public let y: Int

    /// Width of the viewport.
    public let width: Int

    /// Height of the viewport.
    public let height: Int

    /// Current resolution level being viewed.
    public let resolutionLevel: Int

    /// Creates a new viewport.
    ///
    /// - Parameters:
    ///   - x: X offset.
    ///   - y: Y offset.
    ///   - width: Viewport width.
    ///   - height: Viewport height.
    ///   - resolutionLevel: Resolution level.
    public init(x: Int, y: Int, width: Int, height: Int, resolutionLevel: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.resolutionLevel = resolutionLevel
    }

    /// The center X coordinate.
    public var centerX: Double {
        Double(x) + Double(width) / 2.0
    }

    /// The center Y coordinate.
    public var centerY: Double {
        Double(y) + Double(height) / 2.0
    }
}

/// A navigation history entry with timestamp.
public struct JPIPNavigationEntry: Sendable {
    /// The viewport at this point in navigation.
    public let viewport: JPIPViewport

    /// When the viewport was navigated to.
    public let timestamp: Date

    /// Creates a new navigation entry.
    ///
    /// - Parameters:
    ///   - viewport: The viewport.
    ///   - timestamp: Navigation timestamp.
    public init(viewport: JPIPViewport, timestamp: Date = Date()) {
        self.viewport = viewport
        self.timestamp = timestamp
    }
}

// MARK: - Push Priority

/// Priority level for server-initiated push operations.
///
/// Higher priority items are pushed first when bandwidth is limited.
/// Resolution data has highest priority, followed by spatial neighbors,
/// then quality layer refinement.
public enum JPIPPushPriority: Int, Sendable, Comparable {
    /// Resolution data for current viewport (highest priority).
    case resolution = 3

    /// Spatially adjacent tiles to current viewport.
    case spatial = 2

    /// Quality layer refinement for already-delivered data.
    case quality = 1

    public static func < (lhs: JPIPPushPriority, rhs: JPIPPushPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A scheduled push item with priority and data bin.
public struct JPIPPushItem: Sendable {
    /// The data bin to push.
    public let dataBin: JPIPDataBin

    /// Push priority.
    public let priority: JPIPPushPriority

    /// Target session ID.
    public let sessionID: String

    /// Confidence score from prediction (0.0 - 1.0).
    public let confidence: Double

    /// Creates a new push item.
    ///
    /// - Parameters:
    ///   - dataBin: The data bin to push.
    ///   - priority: Push priority.
    ///   - sessionID: Target session.
    ///   - confidence: Prediction confidence.
    public init(
        dataBin: JPIPDataBin,
        priority: JPIPPushPriority,
        sessionID: String,
        confidence: Double
    ) {
        self.dataBin = dataBin
        self.priority = priority
        self.sessionID = sessionID
        self.confidence = confidence
    }
}

// MARK: - Push Acceptance Protocol

/// Client response to a server push offer.
public enum JPIPPushAcceptance: UInt8, Sendable {
    /// Accept the pushed data.
    case accept = 0x01

    /// Reject the pushed data.
    case reject = 0x02

    /// Accept but reduce push rate.
    case throttle = 0x03

    /// Stop all push for this session.
    case stop = 0x04
}

// MARK: - Predictive Prefetch Engine

/// Engine for predicting what data bins a client will need next.
///
/// Uses viewport navigation history to predict movement direction,
/// resolution-level transitions, and spatial locality patterns
/// to generate prefetch recommendations.
public actor JPIPPredictivePrefetchEngine {
    /// Configuration for the engine.
    private let configuration: JPIPPrefetchConfiguration

    /// Per-session navigation history.
    private var sessionHistory: [String: [JPIPNavigationEntry]]

    /// Per-session image dimensions (needed for tile calculations).
    private var sessionImageInfo: [String: ImageInfo]

    /// Statistics.
    private var stats: Statistics

    /// Image information needed for tile calculations.
    public struct ImageInfo: Sendable {
        /// Full image width.
        public let width: Int

        /// Full image height.
        public let height: Int

        /// Number of resolution levels.
        public let resolutionLevels: Int

        /// Tile width.
        public let tileWidth: Int

        /// Tile height.
        public let tileHeight: Int

        /// Number of components.
        public let components: Int

        /// Creates a new image info.
        public init(
            width: Int,
            height: Int,
            resolutionLevels: Int,
            tileWidth: Int = 256,
            tileHeight: Int = 256,
            components: Int = 3
        ) {
            self.width = width
            self.height = height
            self.resolutionLevels = resolutionLevels
            self.tileWidth = max(1, tileWidth)
            self.tileHeight = max(1, tileHeight)
            self.components = max(1, components)
        }

        /// Number of tiles in X direction.
        public var tilesX: Int {
            max(1, (width + tileWidth - 1) / tileWidth)
        }

        /// Number of tiles in Y direction.
        public var tilesY: Int {
            max(1, (height + tileHeight - 1) / tileHeight)
        }

        /// Total number of tiles.
        public var totalTiles: Int {
            tilesX * tilesY
        }
    }

    /// Prediction statistics.
    public struct Statistics: Sendable {
        /// Total predictions generated.
        public var totalPredictions: Int

        /// Predictions that were later validated as correct.
        public var correctPredictions: Int

        /// Total viewport updates received.
        public var viewportUpdates: Int

        /// Total sessions tracked.
        public var activeSessions: Int

        /// Prediction accuracy rate (0.0 - 1.0).
        public var accuracy: Double {
            guard totalPredictions > 0 else { return 0.0 }
            return Double(correctPredictions) / Double(totalPredictions)
        }

        /// Creates empty statistics.
        public init() {
            self.totalPredictions = 0
            self.correctPredictions = 0
            self.viewportUpdates = 0
            self.activeSessions = 0
        }
    }

    /// Creates a new predictive prefetch engine.
    ///
    /// - Parameter configuration: Prefetch configuration.
    public init(configuration: JPIPPrefetchConfiguration = .default) {
        self.configuration = configuration
        self.sessionHistory = [:]
        self.sessionImageInfo = [:]
        self.stats = Statistics()
    }

    /// Registers image information for a session.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - imageInfo: Image dimensions and tiling information.
    public func registerSession(
        _ sessionID: String,
        imageInfo: ImageInfo
    ) {
        sessionImageInfo[sessionID] = imageInfo
        sessionHistory[sessionID] = []
        stats.activeSessions = sessionImageInfo.count
    }

    /// Removes a session from tracking.
    ///
    /// - Parameter sessionID: The session identifier.
    public func removeSession(_ sessionID: String) {
        sessionHistory.removeValue(forKey: sessionID)
        sessionImageInfo.removeValue(forKey: sessionID)
        stats.activeSessions = sessionImageInfo.count
    }

    /// Records a viewport update for navigation history.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - viewport: The new viewport.
    public func recordViewport(_ sessionID: String, viewport: JPIPViewport) {
        stats.viewportUpdates += 1

        var history = sessionHistory[sessionID] ?? []
        history.append(JPIPNavigationEntry(viewport: viewport))

        // Trim to max history size
        if history.count > configuration.maxHistorySize {
            history.removeFirst(history.count - configuration.maxHistorySize)
        }

        sessionHistory[sessionID] = history
    }

    /// Validates a previous prediction against actual viewport.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - predictedTiles: Previously predicted tile indices.
    ///   - actualViewport: The actual viewport the user navigated to.
    public func validatePrediction(
        _ sessionID: String,
        predictedTiles: Set<Int>,
        actualViewport: JPIPViewport
    ) {
        guard let imageInfo = sessionImageInfo[sessionID] else { return }

        let actualTiles = tilesForViewport(actualViewport, imageInfo: imageInfo)
        let hits = predictedTiles.intersection(actualTiles)

        if !hits.isEmpty {
            stats.correctPredictions += hits.count
        }
    }

    /// Generates prefetch predictions for a session.
    ///
    /// Combines viewport prediction, resolution prefetching, and spatial
    /// locality analysis to produce a prioritized list of tile indices
    /// that should be prefetched.
    ///
    /// - Parameter sessionID: The session identifier.
    /// - Returns: Array of predicted prefetch items with priority and confidence.
    public func generatePredictions(
        for sessionID: String
    ) -> [PrefetchPrediction] {
        guard let imageInfo = sessionImageInfo[sessionID],
              let history = sessionHistory[sessionID],
              !history.isEmpty else {
            return []
        }

        var predictions: [PrefetchPrediction] = []

        // 1. Viewport prediction based on navigation history
        if configuration.enableViewportPrediction {
            let viewportPredictions = predictViewportMovement(
                history: history,
                imageInfo: imageInfo
            )
            predictions.append(contentsOf: viewportPredictions)
        }

        // 2. Resolution-level prefetch heuristics
        if configuration.enableResolutionPrefetch {
            let resolutionPredictions = predictResolutionChanges(
                history: history,
                imageInfo: imageInfo
            )
            predictions.append(contentsOf: resolutionPredictions)
        }

        // 3. Spatial locality-based tile prediction
        if configuration.enableSpatialPrefetch {
            let spatialPredictions = predictSpatialLocality(
                history: history,
                imageInfo: imageInfo
            )
            predictions.append(contentsOf: spatialPredictions)
        }

        // Filter by confidence threshold
        predictions = predictions.filter {
            $0.confidence >= configuration.predictionConfidenceThreshold
        }

        // Sort by priority (descending) then confidence (descending)
        predictions.sort { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            return a.confidence > b.confidence
        }

        // Limit to max prefetch depth
        let limit = min(predictions.count, configuration.maxPrefetchDepth)
        predictions = Array(predictions.prefix(limit))

        stats.totalPredictions += predictions.count
        return predictions
    }

    /// Gets the current prediction statistics.
    ///
    /// - Returns: Prediction statistics.
    public func getStatistics() -> Statistics {
        stats
    }

    /// Gets the navigation history for a session.
    ///
    /// - Parameter sessionID: The session identifier.
    /// - Returns: The navigation history entries.
    public func getHistory(for sessionID: String) -> [JPIPNavigationEntry] {
        sessionHistory[sessionID] ?? []
    }

    /// Resets statistics.
    public func resetStatistics() {
        stats = Statistics()
        stats.activeSessions = sessionImageInfo.count
    }

    // MARK: - Viewport Prediction

    /// Predicts next viewport based on navigation movement vector.
    private func predictViewportMovement(
        history: [JPIPNavigationEntry],
        imageInfo: ImageInfo
    ) -> [PrefetchPrediction] {
        guard history.count >= 2 else { return [] }

        let recent = Array(history.suffix(min(5, history.count)))

        // Compute average movement vector from recent history
        var totalDX: Double = 0
        var totalDY: Double = 0
        var count = 0

        for i in 1..<recent.count {
            let prev = recent[i - 1].viewport
            let curr = recent[i].viewport
            totalDX += curr.centerX - prev.centerX
            totalDY += curr.centerY - prev.centerY
            count += 1
        }

        guard count > 0 else { return [] }

        let avgDX = totalDX / Double(count)
        let avgDY = totalDY / Double(count)

        // Predict next viewport by extrapolating movement
        let current = recent.last!.viewport
        let depthFactor = Double(configuration.aggressiveness.rawValue)

        let predictedX = Int(current.centerX + avgDX * depthFactor)
        let predictedY = Int(current.centerY + avgDY * depthFactor)

        let predictedViewport = JPIPViewport(
            x: max(0, predictedX - current.width / 2),
            y: max(0, predictedY - current.height / 2),
            width: current.width,
            height: current.height,
            resolutionLevel: current.resolutionLevel
        )

        let predictedTiles = tilesForViewport(predictedViewport, imageInfo: imageInfo)
        let currentTiles = tilesForViewport(current, imageInfo: imageInfo)
        let newTiles = predictedTiles.subtracting(currentTiles)

        // Confidence decreases with movement magnitude (larger moves are less predictable)
        let moveMagnitude = sqrt(avgDX * avgDX + avgDY * avgDY)
        let maxDim = Double(max(imageInfo.width, imageInfo.height))
        let confidence = max(0.1, 1.0 - (moveMagnitude / maxDim))

        return newTiles.map { tile in
            PrefetchPrediction(
                tileIndex: tile,
                resolutionLevel: current.resolutionLevel,
                priority: .spatial,
                confidence: confidence
            )
        }
    }

    // MARK: - Resolution Prediction

    /// Predicts resolution level changes (zoom in/out patterns).
    private func predictResolutionChanges(
        history: [JPIPNavigationEntry],
        imageInfo: ImageInfo
    ) -> [PrefetchPrediction] {
        guard history.count >= 2 else { return [] }

        let recent = Array(history.suffix(min(5, history.count)))
        let current = recent.last!.viewport

        // Detect resolution change trend
        var resChanges: [Int] = []
        for i in 1..<recent.count {
            let delta = recent[i].viewport.resolutionLevel
                - recent[i - 1].viewport.resolutionLevel
            if delta != 0 {
                resChanges.append(delta)
            }
        }

        var predictions: [PrefetchPrediction] = []

        if !resChanges.isEmpty {
            // Predict continuation of zoom direction
            let avgChange = Double(resChanges.reduce(0, +)) / Double(resChanges.count)
            let nextLevel: Int

            if avgChange > 0 {
                nextLevel = min(current.resolutionLevel + 1,
                                imageInfo.resolutionLevels - 1)
            } else {
                nextLevel = max(current.resolutionLevel - 1, 0)
            }

            if nextLevel != current.resolutionLevel {
                let currentTiles = tilesForViewport(current, imageInfo: imageInfo)
                let confidence = min(1.0, Double(resChanges.count) * 0.3)

                for tile in currentTiles {
                    predictions.append(PrefetchPrediction(
                        tileIndex: tile,
                        resolutionLevel: nextLevel,
                        priority: .resolution,
                        confidence: confidence
                    ))
                }
            }
        } else {
            // No resolution changes - prefetch next quality layer
            let currentTiles = tilesForViewport(current, imageInfo: imageInfo)
            for tile in currentTiles {
                predictions.append(PrefetchPrediction(
                    tileIndex: tile,
                    resolutionLevel: current.resolutionLevel,
                    priority: .quality,
                    confidence: 0.4
                ))
            }
        }

        return predictions
    }

    // MARK: - Spatial Locality Prediction

    /// Predicts spatially adjacent tiles based on current viewport.
    private func predictSpatialLocality(
        history: [JPIPNavigationEntry],
        imageInfo: ImageInfo
    ) -> [PrefetchPrediction] {
        guard let current = history.last?.viewport else { return [] }

        let currentTiles = tilesForViewport(current, imageInfo: imageInfo)
        let neighborRadius = configuration.aggressiveness.rawValue

        var neighborTiles = Set<Int>()

        for tile in currentTiles {
            let tileX = tile % imageInfo.tilesX
            let tileY = tile / imageInfo.tilesX

            for dy in -neighborRadius...neighborRadius {
                for dx in -neighborRadius...neighborRadius {
                    if dx == 0 && dy == 0 { continue }

                    let nx = tileX + dx
                    let ny = tileY + dy

                    if nx >= 0 && nx < imageInfo.tilesX &&
                       ny >= 0 && ny < imageInfo.tilesY {
                        let neighborIndex = ny * imageInfo.tilesX + nx
                        neighborTiles.insert(neighborIndex)
                    }
                }
            }
        }

        // Remove tiles already in the current viewport
        neighborTiles.subtract(currentTiles)

        // Confidence decreases with distance from viewport center
        let centerTileX = Double(current.x + current.width / 2) / Double(imageInfo.tileWidth)
        let centerTileY = Double(current.y + current.height / 2) / Double(imageInfo.tileHeight)

        return neighborTiles.map { tile in
            let tileX = Double(tile % imageInfo.tilesX)
            let tileY = Double(tile / imageInfo.tilesX)

            let distance = sqrt(
                (tileX - centerTileX) * (tileX - centerTileX)
                + (tileY - centerTileY) * (tileY - centerTileY)
            )

            let maxDistance = Double(neighborRadius) * sqrt(2.0)
            let confidence = max(0.1, 1.0 - (distance / max(1.0, maxDistance)))

            return PrefetchPrediction(
                tileIndex: tile,
                resolutionLevel: current.resolutionLevel,
                priority: .spatial,
                confidence: confidence
            )
        }
    }

    // MARK: - Tile Calculation

    /// Calculates tile indices covered by a viewport.
    internal func tilesForViewport(
        _ viewport: JPIPViewport,
        imageInfo: ImageInfo
    ) -> Set<Int> {
        let startTileX = max(0, viewport.x / imageInfo.tileWidth)
        let startTileY = max(0, viewport.y / imageInfo.tileHeight)
        let endTileX = min(
            imageInfo.tilesX - 1,
            (viewport.x + viewport.width - 1) / imageInfo.tileWidth
        )
        let endTileY = min(
            imageInfo.tilesY - 1,
            (viewport.y + viewport.height - 1) / imageInfo.tileHeight
        )

        var tiles = Set<Int>()
        for ty in startTileY...endTileY {
            for tx in startTileX...endTileX {
                tiles.insert(ty * imageInfo.tilesX + tx)
            }
        }
        return tiles
    }
}

/// A single prefetch prediction with metadata.
public struct PrefetchPrediction: Sendable {
    /// Tile index to prefetch.
    public let tileIndex: Int

    /// Resolution level for the prefetch.
    public let resolutionLevel: Int

    /// Push priority classification.
    public let priority: JPIPPushPriority

    /// Confidence score (0.0 - 1.0).
    public let confidence: Double

    /// Creates a new prediction.
    ///
    /// - Parameters:
    ///   - tileIndex: Tile index.
    ///   - resolutionLevel: Resolution level.
    ///   - priority: Push priority.
    ///   - confidence: Confidence score.
    public init(
        tileIndex: Int,
        resolutionLevel: Int,
        priority: JPIPPushPriority,
        confidence: Double
    ) {
        self.tileIndex = tileIndex
        self.resolutionLevel = resolutionLevel
        self.priority = priority
        self.confidence = max(0.0, min(1.0, confidence))
    }
}

// MARK: - Push Scheduler

/// Schedules and prioritizes server push operations.
///
/// Manages a queue of push items sorted by priority, respects
/// bandwidth limits, and tracks push delivery state.
public actor JPIPPushScheduler {
    /// Pending push items sorted by priority.
    private var pendingItems: [JPIPPushItem]

    /// Maximum items in the queue.
    private let maxQueueSize: Int

    /// Statistics.
    private var stats: Statistics

    /// Push scheduling statistics.
    public struct Statistics: Sendable {
        /// Total items enqueued.
        public var totalEnqueued: Int

        /// Total items dequeued and pushed.
        public var totalPushed: Int

        /// Total items dropped (queue full or rejected).
        public var totalDropped: Int

        /// Total items throttled.
        public var totalThrottled: Int

        /// Current queue size.
        public var currentQueueSize: Int

        /// Total bytes pushed.
        public var totalBytesPushed: Int

        /// Creates empty statistics.
        public init() {
            self.totalEnqueued = 0
            self.totalPushed = 0
            self.totalDropped = 0
            self.totalThrottled = 0
            self.currentQueueSize = 0
            self.totalBytesPushed = 0
        }
    }

    /// Creates a new push scheduler.
    ///
    /// - Parameter maxQueueSize: Maximum items in queue (default: 1000).
    public init(maxQueueSize: Int = 1000) {
        self.maxQueueSize = max(1, maxQueueSize)
        self.pendingItems = []
        self.stats = Statistics()
    }

    /// Enqueues a push item with priority ordering.
    ///
    /// Items are inserted in priority order (highest first).
    /// If the queue is full, the lowest-priority item is dropped.
    ///
    /// - Parameter item: The push item to enqueue.
    /// - Returns: True if enqueued, false if dropped.
    @discardableResult
    public func enqueue(_ item: JPIPPushItem) -> Bool {
        stats.totalEnqueued += 1

        if pendingItems.count >= maxQueueSize {
            // Drop lowest priority item if new item has higher priority
            if let last = pendingItems.last,
               item.priority > last.priority {
                pendingItems.removeLast()
                stats.totalDropped += 1
            } else {
                stats.totalDropped += 1
                return false
            }
        }

        // Insert in priority order (highest first)
        let insertIndex = pendingItems.firstIndex {
            $0.priority < item.priority ||
            ($0.priority == item.priority && $0.confidence < item.confidence)
        } ?? pendingItems.endIndex

        pendingItems.insert(item, at: insertIndex)
        stats.currentQueueSize = pendingItems.count
        return true
    }

    /// Dequeues the highest-priority push item.
    ///
    /// - Returns: The next push item, or nil if empty.
    public func dequeue() -> JPIPPushItem? {
        guard !pendingItems.isEmpty else { return nil }

        let item = pendingItems.removeFirst()
        stats.totalPushed += 1
        stats.totalBytesPushed += item.dataBin.data.count
        stats.currentQueueSize = pendingItems.count
        return item
    }

    /// Dequeues up to N highest-priority items.
    ///
    /// - Parameter count: Maximum items to dequeue.
    /// - Returns: Array of push items.
    public func dequeueBatch(count: Int) -> [JPIPPushItem] {
        let n = min(count, pendingItems.count)
        guard n > 0 else { return [] }

        let batch = Array(pendingItems.prefix(n))
        pendingItems.removeFirst(n)

        stats.totalPushed += batch.count
        stats.totalBytesPushed += batch.reduce(0) { $0 + $1.dataBin.data.count }
        stats.currentQueueSize = pendingItems.count
        return batch
    }

    /// Removes all pending items for a session.
    ///
    /// - Parameter sessionID: The session to clear.
    /// - Returns: Number of items removed.
    @discardableResult
    public func removeItems(for sessionID: String) -> Int {
        let before = pendingItems.count
        pendingItems.removeAll { $0.sessionID == sessionID }
        let removed = before - pendingItems.count
        stats.currentQueueSize = pendingItems.count
        return removed
    }

    /// Records that a push was throttled.
    public func recordThrottle() {
        stats.totalThrottled += 1
    }

    /// Gets the current queue size.
    public var queueSize: Int {
        pendingItems.count
    }

    /// Whether the queue is empty.
    public var isEmpty: Bool {
        pendingItems.isEmpty
    }

    /// Clears all pending items.
    public func clear() {
        let dropped = pendingItems.count
        pendingItems.removeAll()
        stats.totalDropped += dropped
        stats.currentQueueSize = 0
    }

    /// Gets scheduler statistics.
    ///
    /// - Returns: Push scheduling statistics.
    public func getStatistics() -> Statistics {
        stats
    }

    /// Resets statistics.
    public func resetStatistics() {
        stats = Statistics()
        stats.currentQueueSize = pendingItems.count
    }
}

// MARK: - Client Cache Tracker

/// Server-side tracking of what data bins each client has received.
///
/// Enables delta delivery by tracking client cache state so only
/// missing data bins are pushed, avoiding redundant transmissions.
public actor JPIPClientCacheTracker {
    /// Per-session cache tracking.
    private var sessionCaches: [String: ClientCacheState]

    /// Statistics.
    private var stats: Statistics

    /// Represents the server's view of a client's cache state.
    public struct ClientCacheState: Sendable {
        /// Set of data bin keys the client has received.
        public var receivedBins: Set<String>

        /// Set of data bin keys that have been pushed but not confirmed.
        public var pendingBins: Set<String>

        /// Last update timestamp.
        public var lastUpdate: Date

        /// Total bytes tracked.
        public var totalBytes: Int

        /// Creates an empty cache state.
        public init() {
            self.receivedBins = []
            self.pendingBins = []
            self.lastUpdate = Date()
            self.totalBytes = 0
        }
    }

    /// Cache tracking statistics.
    public struct Statistics: Sendable {
        /// Total sessions tracked.
        public var activeSessions: Int

        /// Total bins tracked across all sessions.
        public var totalBinsTracked: Int

        /// Total delta deliveries (bins skipped due to cache hit).
        public var deltaDeliveries: Int

        /// Total redundant pushes avoided.
        public var redundantPushesAvoided: Int

        /// Total cache invalidations performed.
        public var cacheInvalidations: Int

        /// Creates empty statistics.
        public init() {
            self.activeSessions = 0
            self.totalBinsTracked = 0
            self.deltaDeliveries = 0
            self.redundantPushesAvoided = 0
            self.cacheInvalidations = 0
        }
    }

    /// Creates a new client cache tracker.
    public init() {
        self.sessionCaches = [:]
        self.stats = Statistics()
    }

    /// Registers a session for cache tracking.
    ///
    /// - Parameter sessionID: The session identifier.
    public func registerSession(_ sessionID: String) {
        sessionCaches[sessionID] = ClientCacheState()
        stats.activeSessions = sessionCaches.count
    }

    /// Removes a session from cache tracking.
    ///
    /// - Parameter sessionID: The session identifier.
    public func removeSession(_ sessionID: String) {
        sessionCaches.removeValue(forKey: sessionID)
        stats.activeSessions = sessionCaches.count
    }

    /// Records that a data bin was sent to a client.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - dataBin: The data bin that was sent.
    public func recordSent(
        sessionID: String,
        dataBin: JPIPDataBin
    ) {
        let key = binKey(binClass: dataBin.binClass, binID: dataBin.binID)
        sessionCaches[sessionID]?.receivedBins.insert(key)
        sessionCaches[sessionID]?.pendingBins.remove(key)
        sessionCaches[sessionID]?.totalBytes += dataBin.data.count
        sessionCaches[sessionID]?.lastUpdate = Date()
        stats.totalBinsTracked += 1
    }

    /// Records that a push is pending delivery.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - dataBin: The data bin being pushed.
    public func recordPending(
        sessionID: String,
        dataBin: JPIPDataBin
    ) {
        let key = binKey(binClass: dataBin.binClass, binID: dataBin.binID)
        sessionCaches[sessionID]?.pendingBins.insert(key)
    }

    /// Checks if a client already has a data bin (delta delivery check).
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: True if the client already has this bin.
    public func clientHasBin(
        sessionID: String,
        binClass: JPIPDataBinClass,
        binID: Int
    ) -> Bool {
        let key = binKey(binClass: binClass, binID: binID)
        guard let cache = sessionCaches[sessionID] else { return false }

        let hasBin = cache.receivedBins.contains(key)
            || cache.pendingBins.contains(key)

        if hasBin {
            stats.redundantPushesAvoided += 1
        }
        return hasBin
    }

    /// Filters data bins to only those missing from client cache (delta delivery).
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - dataBins: Candidate data bins.
    /// - Returns: Only the bins the client doesn't have.
    public func filterMissing(
        sessionID: String,
        dataBins: [JPIPDataBin]
    ) -> [JPIPDataBin] {
        guard let cache = sessionCaches[sessionID] else { return dataBins }

        let filtered = dataBins.filter { bin in
            let key = binKey(binClass: bin.binClass, binID: bin.binID)
            return !cache.receivedBins.contains(key)
                && !cache.pendingBins.contains(key)
        }

        stats.deltaDeliveries += (dataBins.count - filtered.count)
        return filtered
    }

    /// Invalidates all cached bins for a session (e.g., server-side image update).
    ///
    /// - Parameter sessionID: The session identifier.
    public func invalidateSession(_ sessionID: String) {
        sessionCaches[sessionID]?.receivedBins.removeAll()
        sessionCaches[sessionID]?.pendingBins.removeAll()
        sessionCaches[sessionID]?.totalBytes = 0
        sessionCaches[sessionID]?.lastUpdate = Date()
        stats.cacheInvalidations += 1
    }

    /// Invalidates specific bins for a session (e.g., partial image update).
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - binClass: The bin class to invalidate.
    ///   - binIDs: The bin IDs to invalidate.
    public func invalidateBins(
        sessionID: String,
        binClass: JPIPDataBinClass,
        binIDs: [Int]
    ) {
        for binID in binIDs {
            let key = binKey(binClass: binClass, binID: binID)
            sessionCaches[sessionID]?.receivedBins.remove(key)
            sessionCaches[sessionID]?.pendingBins.remove(key)
        }
        sessionCaches[sessionID]?.lastUpdate = Date()
        stats.cacheInvalidations += 1
    }

    /// Invalidates bins for all sessions (broadcast invalidation on image update).
    ///
    /// - Parameters:
    ///   - binClass: The bin class to invalidate.
    ///   - binIDs: The bin IDs to invalidate.
    public func invalidateAllSessions(
        binClass: JPIPDataBinClass,
        binIDs: [Int]
    ) {
        for sessionID in sessionCaches.keys {
            invalidateBins(
                sessionID: sessionID,
                binClass: binClass,
                binIDs: binIDs
            )
        }
    }

    /// Gets the cache state for a session.
    ///
    /// - Parameter sessionID: The session identifier.
    /// - Returns: The client cache state, or nil if not tracked.
    public func getCacheState(
        for sessionID: String
    ) -> ClientCacheState? {
        sessionCaches[sessionID]
    }

    /// Gets the tracking statistics.
    ///
    /// - Returns: Cache tracking statistics.
    public func getStatistics() -> Statistics {
        stats
    }

    /// Resets statistics.
    public func resetStatistics() {
        stats = Statistics()
        stats.activeSessions = sessionCaches.count
    }

    /// Creates a unique key for a data bin.
    private func binKey(binClass: JPIPDataBinClass, binID: Int) -> String {
        "\(binClass.rawValue):\(binID)"
    }
}

// MARK: - Server Push Manager

/// Orchestrates server-initiated push for predictive prefetching.
///
/// Combines the predictive prefetch engine, push scheduler, client
/// cache tracker, and bandwidth throttle into a cohesive push system
/// for JPIP WebSocket transport.
public actor JPIPServerPushManager {
    /// The predictive prefetch engine.
    public let prefetchEngine: JPIPPredictivePrefetchEngine

    /// The push scheduler.
    public let pushScheduler: JPIPPushScheduler

    /// The client cache tracker.
    public let cacheTracker: JPIPClientCacheTracker

    /// The bandwidth throttle (optional).
    private let bandwidthThrottle: JPIPBandwidthThrottle?

    /// Configuration.
    private let configuration: JPIPPrefetchConfiguration

    /// Whether push is globally enabled.
    private var pushEnabled: Bool

    /// Per-session push acceptance state.
    private var sessionPushState: [String: JPIPPushAcceptance]

    /// Performance metrics.
    private var metrics: JPIPPushPerformanceMetrics

    /// Creates a new server push manager.
    ///
    /// - Parameters:
    ///   - configuration: Prefetch configuration.
    ///   - bandwidthThrottle: Optional bandwidth throttle.
    ///   - maxQueueSize: Maximum push queue size (default: 1000).
    public init(
        configuration: JPIPPrefetchConfiguration = .default,
        bandwidthThrottle: JPIPBandwidthThrottle? = nil,
        maxQueueSize: Int = 1000
    ) {
        self.configuration = configuration
        self.prefetchEngine = JPIPPredictivePrefetchEngine(
            configuration: configuration
        )
        self.pushScheduler = JPIPPushScheduler(maxQueueSize: maxQueueSize)
        self.cacheTracker = JPIPClientCacheTracker()
        self.bandwidthThrottle = bandwidthThrottle
        self.pushEnabled = true
        self.sessionPushState = [:]
        self.metrics = JPIPPushPerformanceMetrics()
    }

    /// Registers a session for push management.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - imageInfo: Image information for tile calculations.
    public func registerSession(
        _ sessionID: String,
        imageInfo: JPIPPredictivePrefetchEngine.ImageInfo
    ) async {
        await prefetchEngine.registerSession(sessionID, imageInfo: imageInfo)
        await cacheTracker.registerSession(sessionID)
        sessionPushState[sessionID] = .accept
    }

    /// Removes a session from push management.
    ///
    /// - Parameter sessionID: The session identifier.
    public func removeSession(_ sessionID: String) async {
        await prefetchEngine.removeSession(sessionID)
        await cacheTracker.removeSession(sessionID)
        await pushScheduler.removeItems(for: sessionID)
        sessionPushState.removeValue(forKey: sessionID)
    }

    /// Processes a viewport update and generates push items.
    ///
    /// This is the main entry point for triggering predictive push.
    /// When a client reports a new viewport, the engine predicts
    /// what data bins should be pushed and enqueues them.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - viewport: The new viewport.
    ///   - availableDataBins: Data bins available for the image.
    /// - Returns: Number of push items enqueued.
    @discardableResult
    public func processViewportUpdate(
        sessionID: String,
        viewport: JPIPViewport,
        availableDataBins: [JPIPDataBin]
    ) async -> Int {
        guard pushEnabled else { return 0 }
        guard sessionPushState[sessionID] != .stop else { return 0 }

        let startTime = Date()

        // Record viewport
        await prefetchEngine.recordViewport(sessionID, viewport: viewport)

        // Generate predictions
        let predictions = await prefetchEngine.generatePredictions(
            for: sessionID
        )

        // Match predictions to available data bins
        var matchedBins: [JPIPDataBin] = []
        for prediction in predictions {
            let matchingBins = availableDataBins.filter { bin in
                bin.binID == prediction.tileIndex
            }
            matchedBins.append(contentsOf: matchingBins)
        }

        // Delta delivery - filter out bins client already has
        let missingBins = await cacheTracker.filterMissing(
            sessionID: sessionID,
            dataBins: matchedBins
        )

        // Create push items with priorities
        var enqueued = 0
        for (index, bin) in missingBins.enumerated() {
            let prediction = predictions.first {
                $0.tileIndex == bin.binID
            }

            let item = JPIPPushItem(
                dataBin: bin,
                priority: prediction?.priority ?? .quality,
                sessionID: sessionID,
                confidence: prediction?.confidence ?? 0.5
            )

            if await pushScheduler.enqueue(item) {
                await cacheTracker.recordPending(
                    sessionID: sessionID,
                    dataBin: bin
                )
                enqueued += 1
            }

            // Respect max prefetch depth
            if index >= configuration.maxPrefetchDepth - 1 { break }
        }

        // Record metrics
        let elapsed = Date().timeIntervalSince(startTime)
        metrics.recordPredictionCycle(
            predictionsGenerated: predictions.count,
            itemsEnqueued: enqueued,
            processingTime: elapsed
        )

        return enqueued
    }

    /// Dequeues and returns push items ready for delivery.
    ///
    /// Respects bandwidth throttling and per-session push acceptance.
    ///
    /// - Parameter maxItems: Maximum items to dequeue (default: 16).
    /// - Returns: Array of push items ready for delivery.
    public func dequeuePushItems(maxItems: Int = 16) async -> [JPIPPushItem] {
        guard pushEnabled else { return [] }

        var items: [JPIPPushItem] = []
        var remaining = maxItems

        while remaining > 0 {
            guard let item = await pushScheduler.dequeue() else { break }

            // Check session push acceptance
            if sessionPushState[item.sessionID] == .stop {
                continue
            }

            // Check bandwidth throttle
            if let throttle = bandwidthThrottle {
                let canSend = await throttle.canSend(
                    clientID: item.sessionID,
                    bytes: item.dataBin.data.count
                )
                if !canSend {
                    await pushScheduler.recordThrottle()
                    // Re-enqueue if throttled (it goes back to queue)
                    await pushScheduler.enqueue(item)
                    break
                }
            }

            // Check if session wants throttling
            if sessionPushState[item.sessionID] == .throttle {
                items.append(item)
                break // Only deliver one at a time when throttled
            }

            items.append(item)
            remaining -= 1
        }

        // Record delivered bytes
        for item in items {
            await cacheTracker.recordSent(
                sessionID: item.sessionID,
                dataBin: item.dataBin
            )
            if let throttle = bandwidthThrottle {
                await throttle.recordSent(
                    clientID: item.sessionID,
                    bytes: item.dataBin.data.count
                )
            }
        }

        metrics.recordPushDelivery(
            itemsDelivered: items.count,
            bytesDelivered: items.reduce(0) { $0 + $1.dataBin.data.count }
        )

        return items
    }

    /// Handles a client's push acceptance response.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - acceptance: The client's acceptance response.
    public func handlePushAcceptance(
        sessionID: String,
        acceptance: JPIPPushAcceptance
    ) async {
        sessionPushState[sessionID] = acceptance

        if acceptance == .stop || acceptance == .reject {
            await pushScheduler.removeItems(for: sessionID)
        }
    }

    /// Invalidates cache for a session (server-side image update).
    ///
    /// - Parameter sessionID: The session to invalidate.
    public func invalidateCache(for sessionID: String) async {
        await cacheTracker.invalidateSession(sessionID)
    }

    /// Invalidates specific bins across all sessions (image update).
    ///
    /// - Parameters:
    ///   - binClass: The bin class to invalidate.
    ///   - binIDs: The bin IDs to invalidate.
    public func invalidateBins(
        binClass: JPIPDataBinClass,
        binIDs: [Int]
    ) async {
        await cacheTracker.invalidateAllSessions(
            binClass: binClass,
            binIDs: binIDs
        )
    }

    /// Enables or disables push globally.
    ///
    /// - Parameter enabled: Whether push should be enabled.
    public func setPushEnabled(_ enabled: Bool) async {
        pushEnabled = enabled
        if !enabled {
            await pushScheduler.clear()
        }
    }

    /// Whether push is currently enabled.
    public var isPushEnabled: Bool {
        pushEnabled
    }

    /// Gets the push acceptance state for a session.
    ///
    /// - Parameter sessionID: The session identifier.
    /// - Returns: The push acceptance state.
    public func getPushState(
        for sessionID: String
    ) -> JPIPPushAcceptance? {
        sessionPushState[sessionID]
    }

    /// Gets the performance metrics.
    ///
    /// - Returns: Push performance metrics.
    public func getPerformanceMetrics() -> JPIPPushPerformanceMetrics {
        metrics
    }

    /// Gets comprehensive statistics from all subsystems.
    ///
    /// - Returns: Aggregated statistics.
    public func getStatistics() async -> AggregatedStatistics {
        let predictionStats = await prefetchEngine.getStatistics()
        let schedulerStats = await pushScheduler.getStatistics()
        let cacheStats = await cacheTracker.getStatistics()

        return AggregatedStatistics(
            prediction: predictionStats,
            scheduler: schedulerStats,
            cache: cacheStats,
            performance: metrics
        )
    }

    /// Aggregated statistics from all push subsystems.
    public struct AggregatedStatistics: Sendable {
        /// Prediction engine statistics.
        public let prediction: JPIPPredictivePrefetchEngine.Statistics

        /// Push scheduler statistics.
        public let scheduler: JPIPPushScheduler.Statistics

        /// Cache tracker statistics.
        public let cache: JPIPClientCacheTracker.Statistics

        /// Performance metrics.
        public let performance: JPIPPushPerformanceMetrics
    }
}

// MARK: - Performance Metrics

/// Performance metrics for server-initiated push.
///
/// Tracks time-to-first-display improvements, bandwidth overhead,
/// and prediction accuracy for push performance validation.
public struct JPIPPushPerformanceMetrics: Sendable {
    /// Total prediction cycles executed.
    public var predictionCycles: Int

    /// Total predictions generated across all cycles.
    public var totalPredictions: Int

    /// Total push items enqueued.
    public var totalItemsEnqueued: Int

    /// Total push items delivered.
    public var totalItemsDelivered: Int

    /// Total bytes delivered via push.
    public var totalBytesDelivered: Int

    /// Total bytes requested by clients (for overhead calculation).
    public var totalBytesRequested: Int

    /// Sum of prediction processing times (for averaging).
    public var totalProcessingTime: TimeInterval

    /// Minimum processing time observed.
    public var minProcessingTime: TimeInterval

    /// Maximum processing time observed.
    public var maxProcessingTime: TimeInterval

    /// Creates empty metrics.
    public init() {
        self.predictionCycles = 0
        self.totalPredictions = 0
        self.totalItemsEnqueued = 0
        self.totalItemsDelivered = 0
        self.totalBytesDelivered = 0
        self.totalBytesRequested = 0
        self.totalProcessingTime = 0
        self.minProcessingTime = .infinity
        self.maxProcessingTime = 0
    }

    /// Average processing time per prediction cycle.
    public var averageProcessingTime: TimeInterval {
        guard predictionCycles > 0 else { return 0 }
        return totalProcessingTime / Double(predictionCycles)
    }

    /// Bandwidth overhead ratio (push bytes / requested bytes).
    ///
    /// A value of 0.5 means 50% extra bandwidth used for push.
    /// A value of 0.0 means no push bandwidth used.
    public var bandwidthOverhead: Double {
        guard totalBytesRequested > 0 else { return 0 }
        return Double(totalBytesDelivered) / Double(totalBytesRequested)
    }

    /// Push delivery ratio (items delivered / items enqueued).
    public var deliveryRatio: Double {
        guard totalItemsEnqueued > 0 else { return 0 }
        return Double(totalItemsDelivered) / Double(totalItemsEnqueued)
    }

    /// Records a prediction cycle.
    mutating func recordPredictionCycle(
        predictionsGenerated: Int,
        itemsEnqueued: Int,
        processingTime: TimeInterval
    ) {
        predictionCycles += 1
        totalPredictions += predictionsGenerated
        totalItemsEnqueued += itemsEnqueued
        totalProcessingTime += processingTime
        minProcessingTime = min(minProcessingTime, processingTime)
        maxProcessingTime = max(maxProcessingTime, processingTime)
    }

    /// Records push delivery.
    mutating func recordPushDelivery(
        itemsDelivered: Int,
        bytesDelivered: Int
    ) {
        totalItemsDelivered += itemsDelivered
        totalBytesDelivered += bytesDelivered
    }

    /// Records client-initiated request bytes for overhead calculation.
    public mutating func recordClientRequest(bytes: Int) {
        totalBytesRequested += bytes
    }
}
