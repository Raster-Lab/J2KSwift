//
// JP3DStreamingTypes.swift
// J2KSwift
//
/// # JP3DStreamingTypes
///
/// Core types for JPIP-based 3D progressive streaming of JP3D volumetric data.
///
/// This file defines the fundamental types used by the JP3D JPIP client and server
/// for 3D-aware progressive delivery, including viewport representation, data bins,
/// streaming sessions, and network state.
///
/// ## Topics
///
/// ### Viewport and Region Types
/// - ``JP3DViewFrustum``
/// - ``JP3DViewport``
/// - ``JP3DStreamingRegion``
///
/// ### Data Bin Types
/// - ``JP3DDataBin``
/// - ``JP3DPrecinct3D``
///
/// ### Session and Schedule Types
/// - ``JP3DStreamingSession``
/// - ``JP3DDeliverySchedule``
/// - ``JP3DCacheEntry``
///
/// ### Network and Statistics
/// - ``JP3DNetworkCondition``
/// - ``JP3DStreamingStatistics``
/// - ``JP3DProgressionMode``

import Foundation
import J2KCore

// MARK: - Viewport Types

/// A 3D view frustum for spatial culling in volumetric streaming.
///
/// The frustum is defined by a view origin and direction vectors, plus near/far
/// planes. Used to determine which tiles and precincts are visible to a viewer.
///
/// Example:
/// ```swift
/// let frustum = JP3DViewFrustum(
///     originX: 0, originY: 0, originZ: -100,
///     directionX: 0, directionY: 0, directionZ: 1,
///     nearPlane: 0.1, farPlane: 500.0,
///     fovDegrees: 60.0
/// )
/// ```
public struct JP3DViewFrustum: Sendable, Equatable {
    /// X component of the view origin.
    public let originX: Double
    /// Y component of the view origin.
    public let originY: Double
    /// Z component of the view origin.
    public let originZ: Double

    /// X component of the normalized view direction.
    public let directionX: Double
    /// Y component of the normalized view direction.
    public let directionY: Double
    /// Z component of the normalized view direction.
    public let directionZ: Double

    /// Near clipping plane distance.
    public let nearPlane: Double
    /// Far clipping plane distance.
    public let farPlane: Double
    /// Field of view in degrees (horizontal).
    public let fovDegrees: Double

    /// Creates a view frustum.
    ///
    /// - Parameters:
    ///   - originX: X coordinate of the view origin.
    ///   - originY: Y coordinate of the view origin.
    ///   - originZ: Z coordinate of the view origin.
    ///   - directionX: X component of the view direction.
    ///   - directionY: Y component of the view direction.
    ///   - directionZ: Z component of the view direction.
    ///   - nearPlane: Near clipping plane distance.
    ///   - farPlane: Far clipping plane distance.
    ///   - fovDegrees: Horizontal field of view in degrees.
    public init(
        originX: Double, originY: Double, originZ: Double,
        directionX: Double, directionY: Double, directionZ: Double,
        nearPlane: Double, farPlane: Double,
        fovDegrees: Double
    ) {
        self.originX = originX
        self.originY = originY
        self.originZ = originZ
        self.directionX = directionX
        self.directionY = directionY
        self.directionZ = directionZ
        self.nearPlane = nearPlane
        self.farPlane = farPlane
        self.fovDegrees = fovDegrees
    }

    /// Returns true if the frustum has valid geometry (non-zero direction, positive planes).
    public var isValid: Bool {
        let dirLen = directionX * directionX + directionY * directionY + directionZ * directionZ
        return dirLen > 1e-10 && nearPlane > 0 && farPlane > nearPlane && fovDegrees > 0 && fovDegrees < 360
    }

    /// Returns true if a voxel bounding box (given as ranges) intersects the frustum.
    ///
    /// Uses a conservative AABB test against the frustum direction and range.
    ///
    /// - Parameters:
    ///   - xRange: X coordinate range of the box.
    ///   - yRange: Y coordinate range of the box.
    ///   - zRange: Z coordinate range of the box.
    /// - Returns: `true` if the box may be visible.
    public func intersects(xRange: Range<Int>, yRange: Range<Int>, zRange: Range<Int>) -> Bool {
        guard isValid else { return false }
        // Conservative check: project box center onto view direction
        let cx = Double(xRange.lowerBound + xRange.upperBound) / 2.0
        let cy = Double(yRange.lowerBound + yRange.upperBound) / 2.0
        let cz = Double(zRange.lowerBound + zRange.upperBound) / 2.0
        let dx = cx - originX
        let dy = cy - originY
        let dz = cz - originZ
        let dot = dx * directionX + dy * directionY + dz * directionZ
        // Box half-diagonal
        let hw = Double(xRange.count) / 2.0
        let hh = Double(yRange.count) / 2.0
        let hd = Double(zRange.count) / 2.0
        let halfDiag = (hw * hw + hh * hh + hd * hd).squareRoot()
        return dot + halfDiag >= nearPlane && dot - halfDiag <= farPlane
    }
}

/// A 3D viewport combining a spatial region and an optional view frustum.
///
/// The viewport specifies the region of interest (axis-aligned bounding box)
/// and optionally a view frustum for perspective rendering. Used to drive
/// view-dependent streaming decisions.
///
/// Example:
/// ```swift
/// let viewport = JP3DViewport(
///     xRange: 0..<256, yRange: 0..<256, zRange: 0..<64,
///     frustum: nil
/// )
/// ```
public struct JP3DViewport: Sendable, Equatable {
    /// X-axis range of the viewport in voxel coordinates.
    public let xRange: Range<Int>
    /// Y-axis range of the viewport in voxel coordinates.
    public let yRange: Range<Int>
    /// Z-axis range of the viewport in voxel coordinates.
    public let zRange: Range<Int>
    /// Optional view frustum for perspective culling.
    public let frustum: JP3DViewFrustum?

    /// Creates a viewport.
    ///
    /// - Parameters:
    ///   - xRange: X-axis voxel range.
    ///   - yRange: Y-axis voxel range.
    ///   - zRange: Z-axis voxel range.
    ///   - frustum: Optional view frustum.
    public init(xRange: Range<Int>, yRange: Range<Int>, zRange: Range<Int>, frustum: JP3DViewFrustum? = nil) {
        self.xRange = xRange
        self.yRange = yRange
        self.zRange = zRange
        self.frustum = frustum
    }

    /// Returns true if the viewport region is empty (zero volume).
    public var isEmpty: Bool {
        xRange.isEmpty || yRange.isEmpty || zRange.isEmpty
    }

    /// Returns the intersection of this viewport's axis-aligned region with another.
    ///
    /// - Parameter other: The other viewport.
    /// - Returns: A new viewport covering only the intersection, or nil if disjoint.
    public func intersection(_ other: JP3DViewport) -> JP3DViewport? {
        let x = max(xRange.lowerBound, other.xRange.lowerBound)..<min(xRange.upperBound, other.xRange.upperBound)
        let y = max(yRange.lowerBound, other.yRange.lowerBound)..<min(yRange.upperBound, other.yRange.upperBound)
        let z = max(zRange.lowerBound, other.zRange.lowerBound)..<min(zRange.upperBound, other.zRange.upperBound)
        guard !x.isEmpty && !y.isEmpty && !z.isEmpty else { return nil }
        return JP3DViewport(xRange: x, yRange: y, zRange: z, frustum: frustum ?? other.frustum)
    }
}

/// A streaming region specifying a 3D ROI with quality and resolution parameters.
///
/// `JP3DStreamingRegion` extends a basic axis-aligned bounding box with the
/// quality layer and resolution level targets needed for JPIP delivery.
///
/// Example:
/// ```swift
/// let region = JP3DStreamingRegion(
///     xRange: 0..<128, yRange: 0..<128, zRange: 0..<32,
///     qualityLayer: 3, resolutionLevel: 2
/// )
/// ```
public struct JP3DStreamingRegion: Sendable, Equatable {
    /// X-axis voxel range.
    public let xRange: Range<Int>
    /// Y-axis voxel range.
    public let yRange: Range<Int>
    /// Z-axis voxel range.
    public let zRange: Range<Int>
    /// Target quality layer (0 = lowest, higher = better).
    public let qualityLayer: Int
    /// Target resolution level (0 = lowest, higher = finer).
    public let resolutionLevel: Int

    /// Creates a streaming region.
    ///
    /// - Parameters:
    ///   - xRange: X-axis range.
    ///   - yRange: Y-axis range.
    ///   - zRange: Z-axis range.
    ///   - qualityLayer: Desired quality layer.
    ///   - resolutionLevel: Desired resolution level.
    public init(
        xRange: Range<Int>, yRange: Range<Int>, zRange: Range<Int>,
        qualityLayer: Int = 0, resolutionLevel: Int = 0
    ) {
        self.xRange = xRange
        self.yRange = yRange
        self.zRange = zRange
        self.qualityLayer = max(0, qualityLayer)
        self.resolutionLevel = max(0, resolutionLevel)
    }

    /// Returns true if the region is empty (zero volume).
    public var isEmpty: Bool {
        xRange.isEmpty || yRange.isEmpty || zRange.isEmpty
    }

    /// Returns true if the region is valid (non-empty with non-negative quality/resolution).
    public var isValid: Bool {
        !isEmpty && qualityLayer >= 0 && resolutionLevel >= 0
    }
}

// MARK: - Data Bin Types

/// A 3D-specific JPIP data bin carrying precinct data for a volumetric tile.
///
/// Extends the 2D data bin concept with tile Z-coordinate, resolution, and
/// quality information needed to reconstruct a 3D volume progressively.
///
/// Example:
/// ```swift
/// let bin = JP3DDataBin(
///     binID: 42, tileX: 0, tileY: 0, tileZ: 1,
///     resolutionLevel: 2, qualityLayer: 1,
///     data: precinctData, isComplete: false
/// )
/// ```
public struct JP3DDataBin: Sendable {
    /// Unique bin identifier within the session.
    public let binID: Int
    /// Tile column index.
    public let tileX: Int
    /// Tile row index.
    public let tileY: Int
    /// Tile slice index (Z-axis).
    public let tileZ: Int
    /// Resolution level this bin belongs to.
    public let resolutionLevel: Int
    /// Quality layer of this bin.
    public let qualityLayer: Int
    /// Encoded precinct data.
    public let data: Data
    /// Whether this bin contains the complete precinct data.
    public let isComplete: Bool

    /// Creates a 3D data bin.
    ///
    /// - Parameters:
    ///   - binID: Unique identifier.
    ///   - tileX: Tile column.
    ///   - tileY: Tile row.
    ///   - tileZ: Tile Z-slice.
    ///   - resolutionLevel: Resolution level.
    ///   - qualityLayer: Quality layer.
    ///   - data: Precinct data bytes.
    ///   - isComplete: Whether all data is included.
    public init(
        binID: Int, tileX: Int, tileY: Int, tileZ: Int,
        resolutionLevel: Int, qualityLayer: Int,
        data: Data, isComplete: Bool
    ) {
        self.binID = binID
        self.tileX = tileX
        self.tileY = tileY
        self.tileZ = tileZ
        self.resolutionLevel = resolutionLevel
        self.qualityLayer = qualityLayer
        self.data = data
        self.isComplete = isComplete
    }

    /// Size of the data payload in bytes.
    public var byteCount: Int { data.count }
}

/// Identifies a single 3D precinct by tile coordinates, subband, and precinct index.
///
/// Used as a cache key and for server-side precinct extraction.
public struct JP3DPrecinct3D: Sendable, Hashable {
    /// Tile column index.
    public let tileX: Int
    /// Tile row index.
    public let tileY: Int
    /// Tile Z-slice index.
    public let tileZ: Int
    /// Resolution level.
    public let resolutionLevel: Int
    /// Subband identifier (e.g., 0 = LL, 1–7 = high-frequency subbands).
    public let subband: Int
    /// Precinct index within the subband.
    public let precinctIndex: Int

    /// Creates a 3D precinct identifier.
    public init(tileX: Int, tileY: Int, tileZ: Int, resolutionLevel: Int, subband: Int, precinctIndex: Int) {
        self.tileX = tileX
        self.tileY = tileY
        self.tileZ = tileZ
        self.resolutionLevel = resolutionLevel
        self.subband = subband
        self.precinctIndex = precinctIndex
    }
}

// MARK: - Session and Schedule Types

/// Streaming session state for a single JP3D JPIP connection.
///
/// Tracks the session identifier, active viewport, current progression mode,
/// and acknowledged data bin IDs for resumable streaming.
public struct JP3DStreamingSession: Sendable {
    /// Unique session identifier.
    public let sessionID: String
    /// Volume being streamed.
    public let volumeID: String
    /// Current viewport.
    public var viewport: JP3DViewport
    /// Active progression mode.
    public var progressionMode: JP3DProgressionMode
    /// Set of acknowledged data bin IDs (for resume support).
    public var acknowledgedBins: Set<Int>
    /// Session creation timestamp.
    public let createdAt: Date
    /// Last activity timestamp.
    public var lastActivity: Date

    /// Creates a streaming session.
    ///
    /// - Parameters:
    ///   - sessionID: Unique session identifier.
    ///   - volumeID: Identifier of the volume being streamed.
    ///   - viewport: Initial viewport.
    ///   - progressionMode: Initial progression mode.
    public init(
        sessionID: String,
        volumeID: String,
        viewport: JP3DViewport,
        progressionMode: JP3DProgressionMode = .adaptive
    ) {
        self.sessionID = sessionID
        self.volumeID = volumeID
        self.viewport = viewport
        self.progressionMode = progressionMode
        self.acknowledgedBins = []
        self.createdAt = Date()
        self.lastActivity = Date()
    }
}

/// An ordered list of data bins to deliver in a single streaming pass.
///
/// The schedule is computed by the server based on viewport, network conditions,
/// and progression mode. Bins are ordered from highest to lowest priority.
public struct JP3DDeliverySchedule: Sendable {
    /// Ordered data bins to deliver.
    public let bins: [JP3DDataBin]
    /// Total estimated bytes in this schedule.
    public let totalBytes: Int
    /// Estimated delivery time at the current bandwidth (seconds).
    public let estimatedSeconds: Double
    /// Whether more data is available after this schedule.
    public let hasMore: Bool

    /// Creates a delivery schedule.
    ///
    /// - Parameters:
    ///   - bins: Ordered data bins.
    ///   - estimatedSeconds: Estimated delivery duration.
    ///   - hasMore: Whether additional data follows.
    public init(bins: [JP3DDataBin], estimatedSeconds: Double, hasMore: Bool) {
        self.bins = bins
        self.totalBytes = bins.reduce(0) { $0 + $1.byteCount }
        self.estimatedSeconds = estimatedSeconds
        self.hasMore = hasMore
    }
}

/// A cache entry storing a 3D data bin with spatial metadata for eviction decisions.
public struct JP3DCacheEntry: Sendable {
    /// Cached data bin.
    public let bin: JP3DDataBin
    /// Spatial region covered by this entry.
    public let region: JP3DStreamingRegion
    /// Time when this entry was last accessed.
    public var lastAccessed: Date
    /// Number of times this entry has been accessed.
    public var accessCount: Int
    /// Memory cost in bytes.
    public var byteCount: Int { bin.byteCount }

    /// Creates a cache entry.
    ///
    /// - Parameters:
    ///   - bin: The data bin to cache.
    ///   - region: Spatial region covered.
    public init(bin: JP3DDataBin, region: JP3DStreamingRegion) {
        self.bin = bin
        self.region = region
        self.lastAccessed = Date()
        self.accessCount = 1
    }
}

// MARK: - Network and Statistics

/// Current network condition estimate for adaptive streaming.
public struct JP3DNetworkCondition: Sendable {
    /// Estimated available bandwidth in bytes per second.
    public let bandwidthBPS: Double
    /// Estimated round-trip latency in seconds.
    public let latencySeconds: Double
    /// Packet loss rate in [0, 1].
    public let packetLoss: Double

    /// Creates a network condition.
    ///
    /// - Parameters:
    ///   - bandwidthBPS: Available bandwidth (bytes/sec).
    ///   - latencySeconds: Round-trip latency.
    ///   - packetLoss: Packet loss fraction.
    public init(bandwidthBPS: Double, latencySeconds: Double = 0.02, packetLoss: Double = 0.0) {
        self.bandwidthBPS = max(0, bandwidthBPS)
        self.latencySeconds = max(0, latencySeconds)
        self.packetLoss = min(1, max(0, packetLoss))
    }

    /// A zero-bandwidth condition (queuing mode).
    public static let zeroBandwidth = JP3DNetworkCondition(bandwidthBPS: 0)
    /// A typical LAN condition.
    public static let lan = JP3DNetworkCondition(bandwidthBPS: 125_000_000)
    /// A typical broadband condition (50 Mbps).
    public static let broadband = JP3DNetworkCondition(bandwidthBPS: 6_250_000)
    /// A slow mobile condition (1 Mbps).
    public static let slowMobile = JP3DNetworkCondition(bandwidthBPS: 125_000, latencySeconds: 0.1)
}

/// Statistics collected during a JP3D streaming session.
public struct JP3DStreamingStatistics: Sendable {
    /// Total bytes delivered.
    public let bytesDelivered: Int
    /// Total number of data bins delivered.
    public let binsDelivered: Int
    /// Number of cancelled (stale) requests.
    public let cancelledRequests: Int
    /// Number of viewport updates received.
    public let viewportUpdates: Int
    /// Average bandwidth achieved (bytes/sec).
    public let averageBandwidthBPS: Double
    /// Session elapsed time in seconds.
    public let elapsedSeconds: Double

    /// Creates streaming statistics.
    public init(
        bytesDelivered: Int = 0,
        binsDelivered: Int = 0,
        cancelledRequests: Int = 0,
        viewportUpdates: Int = 0,
        averageBandwidthBPS: Double = 0,
        elapsedSeconds: Double = 0
    ) {
        self.bytesDelivered = bytesDelivered
        self.binsDelivered = binsDelivered
        self.cancelledRequests = cancelledRequests
        self.viewportUpdates = viewportUpdates
        self.averageBandwidthBPS = averageBandwidthBPS
        self.elapsedSeconds = elapsedSeconds
    }
}

// MARK: - Progression Mode

/// Defines how 3D volumetric data is progressively delivered during streaming.
///
/// The mode controls the ordering of data bins from server to client,
/// enabling different application-level priorities (quality vs. spatial coverage).
///
/// Example:
/// ```swift
/// let scheduler = JP3DDeliveryScheduler(mode: .sliceBySliceForward)
/// ```
public enum JP3DProgressionMode: String, Sendable, CaseIterable {
    /// Coarse-to-fine: deliver lowest resolution first, then refine.
    case resolutionFirst = "resolution_first"

    /// Low-to-high quality: deliver all tiles at low quality first.
    case qualityFirst = "quality_first"

    /// Deliver slices in ascending Z order.
    case sliceBySliceForward = "slice_forward"

    /// Deliver slices in descending Z order.
    case sliceBySliceReverse = "slice_reverse"

    /// Deliver slices outward from the center Z slice in both directions.
    case sliceBySliceBidirectional = "slice_bidirectional"

    /// Prioritize tiles visible in the current view frustum.
    case viewDependent = "view_dependent"

    /// Deliver tiles in ascending distance from the viewpoint origin.
    case distanceOrdered = "distance_ordered"

    /// Combine bandwidth and view-awareness for best perceived quality.
    case adaptive = "adaptive"
}
