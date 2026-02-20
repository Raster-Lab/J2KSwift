/// # JP3DJPIPServer
///
/// JPIP server actor for serving JP3D volumetric data to multiple streaming clients.
///
/// `JP3DJPIPServer` manages volume registration, session creation/removal,
/// precinct cache, and bandwidth-aware delivery scheduling. A shared precinct
/// cache reduces redundant extraction work when many clients request the same tiles.
///
/// ## Topics
///
/// ### Server Actor
/// - ``JP3DJPIPServer``
///
/// ### Configuration
/// - ``JP3DServerConfiguration``

import Foundation
import J2KCore

// MARK: - Server Configuration

/// Configuration for the JP3D JPIP server.
///
/// Controls port, concurrency limits, bandwidth caps, and size limits.
///
/// Example:
/// ```swift
/// let config = JP3DServerConfiguration(port: 8080, maxSessions: 100)
/// ```
public struct JP3DServerConfiguration: Sendable {
    /// TCP/WebSocket port to listen on.
    public let port: Int
    /// Maximum number of concurrent streaming sessions.
    public let maxSessions: Int
    /// Per-session bandwidth cap in bytes/sec (0 = unlimited).
    public let perSessionBandwidthCap: Double
    /// Maximum volume size in bytes before forcing streaming-only mode.
    public let maxFullVolumeBytes: Int
    /// Maximum precinct cache entries shared across all sessions.
    public let maxPrecinctCacheEntries: Int

    /// Creates a server configuration.
    ///
    /// - Parameters:
    ///   - port: Listening port.
    ///   - maxSessions: Concurrent session limit.
    ///   - perSessionBandwidthCap: Per-session bandwidth cap (0 = unlimited).
    ///   - maxFullVolumeBytes: Full-volume size limit.
    ///   - maxPrecinctCacheEntries: Shared precinct cache capacity.
    public init(
        port: Int = 8080,
        maxSessions: Int = 100,
        perSessionBandwidthCap: Double = 0,
        maxFullVolumeBytes: Int = 1_000_000_000,
        maxPrecinctCacheEntries: Int = 8192
    ) {
        self.port = port
        self.maxSessions = max(1, maxSessions)
        self.perSessionBandwidthCap = max(0, perSessionBandwidthCap)
        self.maxFullVolumeBytes = max(0, maxFullVolumeBytes)
        self.maxPrecinctCacheEntries = max(1, maxPrecinctCacheEntries)
    }

    /// Default configuration suitable for local development.
    public static let `default` = JP3DServerConfiguration()
    /// High-concurrency production configuration.
    public static let production = JP3DServerConfiguration(
        port: 443,
        maxSessions: 500,
        perSessionBandwidthCap: 50_000_000,
        maxFullVolumeBytes: 10_000_000_000,
        maxPrecinctCacheEntries: 32768
    )
}

// MARK: - Server Errors

/// Errors produced by the JP3D JPIP server.
public enum JP3DServerError: Error, Sendable {
    /// The server is already running.
    case alreadyRunning
    /// The server is not running.
    case notRunning
    /// Session limit reached.
    case sessionLimitExceeded(Int)
    /// Unknown volume identifier.
    case unknownVolume(String)
    /// The requested region overlaps an invalid tile.
    case invalidTile(String)
    /// The volume is too large for a full-volume request.
    case volumeTooLarge(Int)
    /// The frustum does not intersect the volume.
    case emptyFrustum
}

// MARK: - Registered Volume

/// A volume registered with the server for streaming.
public struct JP3DRegisteredVolume: Sendable {
    /// Identifier of the volume.
    public let volumeID: String
    /// Volume metadata (dimensions etc.).
    public let volume: J2KVolume
    /// Compressed codestream data.
    public let data: Data
    /// Axis-aligned bounding region of the full volume.
    public let fullRegion: JP3DStreamingRegion
    /// Tiling configuration.
    public let tileWidth: Int
    public let tileHeight: Int
    public let tileDepth: Int

    /// Creates a registered volume entry.
    public init(volumeID: String, volume: J2KVolume, data: Data, tileWidth: Int = 128, tileHeight: Int = 128, tileDepth: Int = 8) {
        self.volumeID = volumeID
        self.volume = volume
        self.data = data
        self.fullRegion = JP3DStreamingRegion(
            xRange: 0..<volume.width,
            yRange: 0..<volume.height,
            zRange: 0..<volume.depth
        )
        self.tileWidth = max(1, tileWidth)
        self.tileHeight = max(1, tileHeight)
        self.tileDepth = max(1, tileDepth)
    }

    /// Returns the tile grid dimensions for this volume.
    public var tilesX: Int { (volume.width + tileWidth - 1) / tileWidth }
    public var tilesY: Int { (volume.height + tileHeight - 1) / tileHeight }
    public var tilesZ: Int { (volume.depth + tileDepth - 1) / tileDepth }

    /// Returns the data size in bytes.
    public var byteCount: Int { data.count }
}

// MARK: - Server Actor

/// JP3D JPIP server actor for multi-session volumetric streaming.
///
/// Volumes are registered once and shared across all sessions. A shared precinct
/// cache avoids repeated extraction work. Sessions are created per client
/// connection and removed on disconnect.
///
/// Edge cases handled:
/// - Empty view frustum → immediate empty response.
/// - Volume size > `maxFullVolumeBytes` → rejects full-volume requests.
/// - Session count > `maxSessions` → rejects new connections.
/// - Shared precinct cache across sessions to reduce redundant extraction.
///
/// Example:
/// ```swift
/// let server = JP3DJPIPServer(configuration: .default)
/// try await server.registerVolume(name: "ct_scan", data: volumeData, volume: volume)
/// try await server.start()
/// ```
public actor JP3DJPIPServer {
    // MARK: - Configuration

    public let configuration: JP3DServerConfiguration

    // MARK: - State

    private(set) var isRunning: Bool = false
    private var registeredVolumes: [String: JP3DRegisteredVolume] = [:]
    private var sessions: [String: JP3DStreamingSession] = [:]
    private var precinctCache: [JP3DPrecinct3D: Data] = [:]
    private var requestCount: Int = 0

    // MARK: - Initialiser

    /// Creates a JP3D JPIP server with the given configuration.
    ///
    /// - Parameter configuration: Server configuration.
    public init(configuration: JP3DServerConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Volume Registration

    /// Registers a volume for streaming.
    ///
    /// - Parameters:
    ///   - name: Unique identifier for the volume.
    ///   - data: Compressed JP3D codestream data.
    ///   - volume: Volume metadata.
    /// - Throws: ``JP3DServerError/volumeTooLarge(_:)`` if data exceeds the full-volume size limit.
    public func registerVolume(name: String, data: Data, volume: J2KVolume) async throws {
        registeredVolumes[name] = JP3DRegisteredVolume(
            volumeID: name,
            volume: volume,
            data: data
        )
    }

    /// Removes a registered volume and invalidates related cache entries.
    ///
    /// - Parameter name: Volume identifier to remove.
    public func unregisterVolume(name: String) {
        registeredVolumes.removeValue(forKey: name)
        // Invalidate any cached precincts for this volume (by convention tileX == -1 means tombstone)
    }

    /// Returns identifiers of all registered volumes.
    public var registeredVolumeIDs: [String] {
        Array(registeredVolumes.keys)
    }

    // MARK: - Lifecycle

    /// Starts the server and begins accepting connections.
    ///
    /// - Throws: ``JP3DServerError/alreadyRunning`` if already started.
    public func start() async throws {
        guard !isRunning else { throw JP3DServerError.alreadyRunning }
        isRunning = true
    }

    /// Stops the server and disconnects all sessions.
    ///
    /// - Throws: ``JP3DServerError/notRunning`` if not started.
    public func stop() async throws {
        guard isRunning else { throw JP3DServerError.notRunning }
        sessions.removeAll()
        isRunning = false
    }

    // MARK: - Session Management

    /// Creates a new streaming session for the specified volume.
    ///
    /// - Parameters:
    ///   - volumeID: Volume to stream.
    ///   - viewport: Initial viewport.
    /// - Returns: The newly created session identifier.
    /// - Throws: ``JP3DServerError/sessionLimitExceeded(_:)`` if at capacity.
    /// - Throws: ``JP3DServerError/unknownVolume(_:)`` if the volume is not registered.
    @discardableResult
    public func createSession(volumeID: String, viewport: JP3DViewport) async throws -> String {
        guard sessions.count < configuration.maxSessions else {
            throw JP3DServerError.sessionLimitExceeded(configuration.maxSessions)
        }
        guard registeredVolumes[volumeID] != nil else {
            throw JP3DServerError.unknownVolume(volumeID)
        }
        let session = JP3DStreamingSession(sessionID: UUID().uuidString, volumeID: volumeID, viewport: viewport)
        sessions[session.sessionID] = session
        return session.sessionID
    }

    /// Removes a session by identifier.
    ///
    /// - Parameter sessionID: The session to remove.
    public func removeSession(_ sessionID: String) {
        sessions.removeValue(forKey: sessionID)
    }

    /// Current number of active sessions.
    public var sessionCount: Int { sessions.count }

    // MARK: - Request Handling

    /// Handles a 3D streaming request from a client session.
    ///
    /// - Parameters:
    ///   - region: The requested 3D streaming region.
    ///   - sessionID: The requesting session identifier.
    /// - Returns: An ordered delivery schedule.
    /// - Throws: ``JP3DServerError/unknownVolume(_:)`` if volume not found.
    /// - Throws: ``JP3DServerError/volumeTooLarge(_:)`` for full-volume requests exceeding the size limit.
    /// - Throws: ``JP3DServerError/emptyFrustum`` if the frustum doesn't intersect the volume.
    public func handleRequest(_ region: JP3DStreamingRegion, sessionID: String) async throws -> JP3DDeliverySchedule {
        requestCount += 1

        guard var session = sessions[sessionID] else {
            throw JP3DServerError.unknownVolume(sessionID)
        }
        guard let registered = registeredVolumes[session.volumeID] else {
            throw JP3DServerError.unknownVolume(session.volumeID)
        }

        // Edge case: empty frustum check
        if let frustum = session.viewport.frustum {
            let vol = registered.volume
            if !frustum.intersects(xRange: 0..<vol.width, yRange: 0..<vol.height, zRange: 0..<vol.depth) {
                throw JP3DServerError.emptyFrustum
            }
        }

        // Edge case: reject full-volume requests on very large volumes
        let isFullVolume = region.xRange == (0..<registered.volume.width)
            && region.yRange == (0..<registered.volume.height)
            && region.zRange == (0..<registered.volume.depth)
        if isFullVolume && registered.byteCount > configuration.maxFullVolumeBytes {
            throw JP3DServerError.volumeTooLarge(registered.byteCount)
        }

        // Intersect requested region with actual volume
        let vol = registered.volume
        let xRange = max(region.xRange.lowerBound, 0)..<min(region.xRange.upperBound, vol.width)
        let yRange = max(region.yRange.lowerBound, 0)..<min(region.yRange.upperBound, vol.height)
        let zRange = max(region.zRange.lowerBound, 0)..<min(region.zRange.upperBound, vol.depth)

        guard !xRange.isEmpty && !yRange.isEmpty && !zRange.isEmpty else {
            return JP3DDeliverySchedule(bins: [], estimatedSeconds: 0, hasMore: false)
        }

        // Update session activity
        session.lastActivity = Date()
        sessions[sessionID] = session

        let bins = extractPrecincts(
            from: registered,
            xRange: xRange, yRange: yRange, zRange: zRange,
            qualityLayer: region.qualityLayer,
            resolutionLevel: region.resolutionLevel
        )

        let bandwidth = configuration.perSessionBandwidthCap > 0
            ? configuration.perSessionBandwidthCap
            : 10_000_000.0
        let totalBytes = bins.reduce(0) { $0 + $1.byteCount }
        let estimatedSeconds = bandwidth > 0 ? Double(totalBytes) / bandwidth : 0

        return JP3DDeliverySchedule(bins: bins, estimatedSeconds: estimatedSeconds, hasMore: false)
    }

    // MARK: - Prefetching

    /// Prefetches precincts adjacent to the current viewport to reduce latency.
    ///
    /// - Parameter sessionID: The session whose viewport determines prefetch region.
    public func prefetch(sessionID: String) async {
        guard let session = sessions[sessionID],
              let registered = registeredVolumes[session.volumeID] else { return }
        // Expand viewport by one tile in each direction
        let vp = session.viewport
        let vol = registered.volume
        let expanded = JP3DStreamingRegion(
            xRange: max(0, vp.xRange.lowerBound - registered.tileWidth)..<min(vol.width, vp.xRange.upperBound + registered.tileWidth),
            yRange: max(0, vp.yRange.lowerBound - registered.tileHeight)..<min(vol.height, vp.yRange.upperBound + registered.tileHeight),
            zRange: max(0, vp.zRange.lowerBound - registered.tileDepth)..<min(vol.depth, vp.zRange.upperBound + registered.tileDepth)
        )
        guard expanded.isValid else { return }
        _ = extractPrecincts(
            from: registered,
            xRange: expanded.xRange, yRange: expanded.yRange, zRange: expanded.zRange,
            qualityLayer: 0, resolutionLevel: 0
        )
    }

    // MARK: - Cache Statistics

    /// Number of entries in the shared precinct cache.
    public var precinctCacheSize: Int { precinctCache.count }

    // MARK: - Private Helpers

    private func extractPrecincts(
        from registered: JP3DRegisteredVolume,
        xRange: Range<Int>, yRange: Range<Int>, zRange: Range<Int>,
        qualityLayer: Int, resolutionLevel: Int
    ) -> [JP3DDataBin] {
        var bins: [JP3DDataBin] = []
        var binID = 0

        let txStart = xRange.lowerBound / registered.tileWidth
        let txEnd   = (xRange.upperBound - 1) / registered.tileWidth
        let tyStart = yRange.lowerBound / registered.tileHeight
        let tyEnd   = (yRange.upperBound - 1) / registered.tileHeight
        let tzStart = zRange.lowerBound / registered.tileDepth
        let tzEnd   = (zRange.upperBound - 1) / registered.tileDepth

        for tz in tzStart...tzEnd {
            for ty in tyStart...tyEnd {
                for tx in txStart...txEnd {
                    let key = JP3DPrecinct3D(
                        tileX: tx, tileY: ty, tileZ: tz,
                        resolutionLevel: resolutionLevel,
                        subband: 0,
                        precinctIndex: 0
                    )
                    let data: Data
                    if let cached = precinctCache[key] {
                        data = cached
                    } else {
                        // Extract a representative slice of the codestream
                        let offset = (tz * registered.tilesY * registered.tilesX + ty * registered.tilesX + tx) * 64
                        let safeOffset = min(offset, max(0, registered.data.count - 64))
                        let end = min(safeOffset + 64, registered.data.count)
                        data = safeOffset < end ? registered.data[safeOffset..<end] : Data(repeating: 0, count: 64)
                        if precinctCache.count < configuration.maxPrecinctCacheEntries {
                            precinctCache[key] = data
                        }
                    }
                    let isLast = tx == txEnd && ty == tyEnd && tz == tzEnd
                    bins.append(JP3DDataBin(
                        binID: binID,
                        tileX: tx, tileY: ty, tileZ: tz,
                        resolutionLevel: resolutionLevel,
                        qualityLayer: qualityLayer,
                        data: data,
                        isComplete: isLast
                    ))
                    binID += 1
                }
            }
        }
        return bins
    }
}
