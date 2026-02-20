/// # JPIPMultiResolutionTileManager
///
/// Manages multi-resolution tiled streaming with adaptive quality.
///
/// Handles resolution-level aware tile decomposition, independent quality
/// layer selection per tile, and dynamic tile priority management based on
/// viewport visibility.

import Foundation
import J2KCore

/// Represents a tile at a specific resolution level.
public struct JPIPTile: Sendable, Hashable {
    /// Tile column index.
    public let x: Int

    /// Tile row index.
    public let y: Int

    /// Resolution level (0 = lowest, higher = higher resolution).
    public let resolutionLevel: Int

    /// Component index.
    public let component: Int

    /// Creates a new tile identifier.
    ///
    /// - Parameters:
    ///   - x: Tile column index.
    ///   - y: Tile row index.
    ///   - resolutionLevel: Resolution level.
    ///   - component: Component index.
    public init(x: Int, y: Int, resolutionLevel: Int, component: Int) {
        self.x = x
        self.y = y
        self.resolutionLevel = resolutionLevel
        self.component = component
    }
}

/// Priority level for tile delivery.
public enum JPIPTilePriority: Int, Sendable, Comparable {
    /// Background tiles (not visible).
    case background = 0

    /// Low priority (visible but not in focus).
    case low = 1

    /// Normal priority (visible).
    case normal = 2

    /// High priority (in viewport center).
    case high = 3

    /// Critical priority (immediate viewport).
    case critical = 4

    public static func < (lhs: JPIPTilePriority, rhs: JPIPTilePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Represents a tile with its delivery priority and quality requirements.
public struct JPIPPrioritizedTile: Sendable {
    /// The tile identifier.
    public let tile: JPIPTile

    /// Delivery priority.
    public let priority: JPIPTilePriority

    /// Target quality layers for this tile.
    public let targetLayers: Int

    /// Viewport visibility score (0.0 = not visible, 1.0 = fully visible).
    public let visibilityScore: Double

    /// Creates a prioritized tile.
    ///
    /// - Parameters:
    ///   - tile: The tile identifier.
    ///   - priority: Delivery priority.
    ///   - targetLayers: Target quality layers.
    ///   - visibilityScore: Viewport visibility score (0.0-1.0).
    public init(tile: JPIPTile, priority: JPIPTilePriority, targetLayers: Int, visibilityScore: Double) {
        self.tile = tile
        self.priority = priority
        self.targetLayers = targetLayers
        self.visibilityScore = visibilityScore
    }
}

/// Configuration for multi-resolution tile management.
public struct JPIPTileConfiguration: Sendable {
    /// Number of resolution levels.
    public var resolutionLevels: Int

    /// Tile size at full resolution (width, height).
    public var tileSize: (width: Int, height: Int)

    /// Number of components (e.g., 3 for RGB).
    public var componentCount: Int

    /// Maximum quality layers.
    public var maxQualityLayers: Int

    /// Viewport size (width, height).
    public var viewportSize: (width: Int, height: Int)?

    /// Creates a tile configuration.
    ///
    /// - Parameters:
    ///   - resolutionLevels: Number of resolution levels.
    ///   - tileSize: Tile size at full resolution.
    ///   - componentCount: Number of components.
    ///   - maxQualityLayers: Maximum quality layers.
    ///   - viewportSize: Optional viewport size.
    public init(
        resolutionLevels: Int,
        tileSize: (width: Int, height: Int),
        componentCount: Int,
        maxQualityLayers: Int,
        viewportSize: (width: Int, height: Int)? = nil
    ) {
        self.resolutionLevels = resolutionLevels
        self.tileSize = tileSize
        self.componentCount = componentCount
        self.maxQualityLayers = maxQualityLayers
        self.viewportSize = viewportSize
    }
}

/// Manages multi-resolution tiled streaming.
///
/// Decomposes images into resolution levels and tiles, assigns priorities
/// based on viewport visibility, and manages independent quality layer
/// selection per tile.
///
/// Example:
/// ```swift
/// let config = JPIPTileConfiguration(
///     resolutionLevels: 5,
///     tileSize: (256, 256),
///     componentCount: 3,
///     maxQualityLayers: 8
/// )
/// let manager = JPIPMultiResolutionTileManager(
///     imageSize: (4096, 4096),
///     configuration: config
/// )
/// let tiles = manager.getTilesForResolution(3)
/// ```
public actor JPIPMultiResolutionTileManager {
    /// Image dimensions (width, height) at full resolution.
    public let imageSize: (width: Int, height: Int)

    /// Tile configuration.
    public let configuration: JPIPTileConfiguration

    /// Current viewport region (x, y, width, height).
    private var viewport: (x: Int, y: Int, width: Int, height: Int)?

    /// Tile priority queue.
    private var priorityQueue: [JPIPPrioritizedTile]

    /// Tile granularity adjustment factor (1.0 = default, 2.0 = half resolution).
    private var granularityFactor: Double

    /// Creates a multi-resolution tile manager.
    ///
    /// - Parameters:
    ///   - imageSize: Image dimensions at full resolution.
    ///   - configuration: Tile configuration.
    public init(imageSize: (width: Int, height: Int), configuration: JPIPTileConfiguration) {
        self.imageSize = imageSize
        self.configuration = configuration
        self.viewport = nil
        self.priorityQueue = []
        self.granularityFactor = 1.0
    }

    /// Updates the viewport region.
    ///
    /// Recalculates tile priorities based on the new viewport.
    ///
    /// - Parameter viewport: The viewport region (x, y, width, height).
    public func updateViewport(_ viewport: (x: Int, y: Int, width: Int, height: Int)) {
        self.viewport = viewport
        rebuildPriorityQueue()
    }

    /// Gets all tiles for a specific resolution level.
    ///
    /// - Parameter resolutionLevel: The resolution level (0 = lowest).
    /// - Returns: Array of tiles at that resolution.
    public func getTilesForResolution(_ resolutionLevel: Int) -> [JPIPTile] {
        guard resolutionLevel >= 0 && resolutionLevel < configuration.resolutionLevels else {
            return []
        }

        // Calculate image dimensions at this resolution
        let scale = pow(2.0, Double(resolutionLevel))
        let resWidth = Int(Double(imageSize.width) / scale)
        let resHeight = Int(Double(imageSize.height) / scale)

        // Calculate tile dimensions at this resolution
        let tileDim = getTileDimensionsForResolution(resolutionLevel)

        // Calculate number of tiles needed
        let tilesX = (resWidth + tileDim.width - 1) / tileDim.width
        let tilesY = (resHeight + tileDim.height - 1) / tileDim.height

        var tiles: [JPIPTile] = []
        for component in 0..<configuration.componentCount {
            for y in 0..<tilesY {
                for x in 0..<tilesX {
                    tiles.append(JPIPTile(
                        x: x,
                        y: y,
                        resolutionLevel: resolutionLevel,
                        component: component
                    ))
                }
            }
        }

        return tiles
    }

    /// Gets the prioritized tile queue.
    ///
    /// Returns tiles ordered by priority (highest first).
    ///
    /// - Returns: Ordered array of prioritized tiles.
    public func getPriorityQueue() -> [JPIPPrioritizedTile] {
        priorityQueue
    }

    /// Gets quality layers for a specific tile based on its priority.
    ///
    /// - Parameter tile: The tile to query.
    /// - Returns: Number of quality layers to request.
    public func getQualityLayers(for tile: JPIPTile) -> Int {
        // Find the tile in priority queue
        if let prioritized = priorityQueue.first(where: { $0.tile == tile }) {
            return prioritized.targetLayers
        }

        // Default to maximum layers if not in queue
        return configuration.maxQualityLayers
    }

    /// Adjusts tile granularity dynamically.
    ///
    /// Allows reducing tile resolution during high load or low bandwidth.
    ///
    /// - Parameter factor: Granularity factor (1.0 = normal, 2.0 = coarser).
    public func setGranularityFactor(_ factor: Double) {
        self.granularityFactor = max(1.0, factor)
        rebuildPriorityQueue()
    }

    /// Gets current granularity factor.
    ///
    /// - Returns: The current granularity factor.
    public func getGranularityFactor() -> Double {
        granularityFactor
    }

    // MARK: - Private Methods

    /// Rebuilds the priority queue based on current viewport.
    private func rebuildPriorityQueue() {
        var newQueue: [JPIPPrioritizedTile] = []

        // Generate prioritized tiles for all resolution levels
        for resLevel in 0..<configuration.resolutionLevels {
            let tiles = getTilesForResolution(resLevel)

            for tile in tiles {
                let priority = calculatePriority(for: tile)
                let visibilityScore = calculateVisibilityScore(for: tile)
                let targetLayers = calculateTargetLayers(
                    priority: priority,
                    visibilityScore: visibilityScore
                )

                newQueue.append(JPIPPrioritizedTile(
                    tile: tile,
                    priority: priority,
                    targetLayers: targetLayers,
                    visibilityScore: visibilityScore
                ))
            }
        }

        // Sort by priority (highest first), then by visibility score
        newQueue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.visibilityScore > rhs.visibilityScore
        }

        self.priorityQueue = newQueue
    }

    /// Calculates priority for a tile based on viewport visibility.
    private func calculatePriority(for tile: JPIPTile) -> JPIPTilePriority {
        guard let viewport = self.viewport else {
            return .normal
        }

        let tileDim = getTileDimensionsForResolution(tile.resolutionLevel)
        let scale = pow(2.0, Double(tile.resolutionLevel))

        // Tile bounds at full resolution
        let tileX = Int(Double(tile.x * tileDim.width) * scale)
        let tileY = Int(Double(tile.y * tileDim.height) * scale)
        let tileWidth = Int(Double(tileDim.width) * scale)
        let tileHeight = Int(Double(tileDim.height) * scale)

        // Check intersection with viewport
        let intersects = rectanglesIntersect(
            (tileX, tileY, tileWidth, tileHeight),
            (viewport.x, viewport.y, viewport.width, viewport.height)
        )

        if !intersects {
            return .background
        }

        // Calculate center distance from viewport center
        let tileCenterX = tileX + tileWidth / 2
        let tileCenterY = tileY + tileHeight / 2
        let viewportCenterX = viewport.x + viewport.width / 2
        let viewportCenterY = viewport.y + viewport.height / 2

        let dx = Double(tileCenterX - viewportCenterX)
        let dy = Double(tileCenterY - viewportCenterY)
        let distance = sqrt(dx * dx + dy * dy)
        let maxDistance = sqrt(
            Double(viewport.width * viewport.width + viewport.height * viewport.height)
        )
        let normalizedDistance = distance / maxDistance

        // Assign priority based on distance and resolution level
        if normalizedDistance < 0.2 && tile.resolutionLevel >= configuration.resolutionLevels - 2 {
            return .critical
        } else if normalizedDistance < 0.4 {
            return .high
        } else if normalizedDistance < 0.7 {
            return .normal
        } else {
            return .low
        }
    }

    /// Calculates visibility score for a tile.
    private func calculateVisibilityScore(for tile: JPIPTile) -> Double {
        guard let viewport = self.viewport else {
            return 0.0
        }

        let tileDim = getTileDimensionsForResolution(tile.resolutionLevel)
        let scale = pow(2.0, Double(tile.resolutionLevel))

        // Tile bounds at full resolution
        let tileX = Int(Double(tile.x * tileDim.width) * scale)
        let tileY = Int(Double(tile.y * tileDim.height) * scale)
        let tileWidth = Int(Double(tileDim.width) * scale)
        let tileHeight = Int(Double(tileDim.height) * scale)

        // Calculate intersection area
        let intersectionArea = calculateIntersectionArea(
            (tileX, tileY, tileWidth, tileHeight),
            (viewport.x, viewport.y, viewport.width, viewport.height)
        )

        let tileArea = tileWidth * tileHeight
        return Double(intersectionArea) / Double(tileArea)
    }

    /// Calculates target quality layers based on priority and visibility.
    private func calculateTargetLayers(
        priority: JPIPTilePriority,
        visibilityScore: Double
    ) -> Int {
        let baseLayers: Int

        switch priority {
        case .critical:
            baseLayers = configuration.maxQualityLayers
        case .high:
            baseLayers = (configuration.maxQualityLayers * 3) / 4
        case .normal:
            baseLayers = configuration.maxQualityLayers / 2
        case .low:
            baseLayers = configuration.maxQualityLayers / 4
        case .background:
            baseLayers = 1
        }

        // Adjust based on visibility score
        let adjustedLayers = Int(Double(baseLayers) * visibilityScore)
        return max(1, min(configuration.maxQualityLayers, adjustedLayers))
    }

    /// Gets tile dimensions for a specific resolution level.
    private func getTileDimensionsForResolution(_ resolutionLevel: Int) -> (width: Int, height: Int) {
        let scale = pow(2.0, Double(resolutionLevel))
        let adjustedWidth = Int(Double(configuration.tileSize.width) / scale * granularityFactor)
        let adjustedHeight = Int(Double(configuration.tileSize.height) / scale * granularityFactor)
        return (max(1, adjustedWidth), max(1, adjustedHeight))
    }

    /// Checks if two rectangles intersect.
    private func rectanglesIntersect(
        _ rect1: (x: Int, y: Int, width: Int, height: Int),
        _ rect2: (x: Int, y: Int, width: Int, height: Int)
    ) -> Bool {
        let left1 = rect1.x
        let right1 = rect1.x + rect1.width
        let top1 = rect1.y
        let bottom1 = rect1.y + rect1.height

        let left2 = rect2.x
        let right2 = rect2.x + rect2.width
        let top2 = rect2.y
        let bottom2 = rect2.y + rect2.height

        return !(right1 <= left2 || right2 <= left1 || bottom1 <= top2 || bottom2 <= top1)
    }

    /// Calculates intersection area between two rectangles.
    private func calculateIntersectionArea(
        _ rect1: (x: Int, y: Int, width: Int, height: Int),
        _ rect2: (x: Int, y: Int, width: Int, height: Int)
    ) -> Int {
        let left = max(rect1.x, rect2.x)
        let right = min(rect1.x + rect1.width, rect2.x + rect2.width)
        let top = max(rect1.y, rect2.y)
        let bottom = min(rect1.y + rect1.height, rect2.y + rect2.height)

        if right <= left || bottom <= top {
            return 0
        }

        return (right - left) * (bottom - top)
    }
}
