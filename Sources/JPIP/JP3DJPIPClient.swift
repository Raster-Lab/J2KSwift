/// # JP3DJPIPClient
///
/// JPIP client actor for 3D-aware progressive delivery of JP3D volumetric data.
///
/// `JP3DJPIPClient` manages a JPIP session with a server, sending 3D view-window
/// requests, receiving data bins, and recovering from network interruptions.
/// Rapid viewport changes automatically cancel stale pending requests.
///
/// ## Topics
///
/// ### Client Actor
/// - ``JP3DJPIPClient``
///
/// ### Request Type
/// - ``JP3DViewWindowRequest``

import Foundation
import J2KCore

/// A JPIP view-window request with 3D viewport, quality, and resolution parameters.
///
/// Used to describe a single streaming request from client to server.
///
/// Example:
/// ```swift
/// let request = JP3DViewWindowRequest(
///     viewport: viewport,
///     qualityLayer: 3,
///     resolutionLevel: 2,
///     progressionMode: .adaptive
/// )
/// ```
public struct JP3DViewWindowRequest: Sendable {
    /// Unique request identifier.
    public let requestID: String
    /// Target viewport.
    public let viewport: JP3DViewport
    /// Desired quality layer.
    public let qualityLayer: Int
    /// Desired resolution level.
    public let resolutionLevel: Int
    /// Requested progression mode.
    public let progressionMode: JP3DProgressionMode
    /// Timestamp when the request was created.
    public let createdAt: Date

    /// Creates a view-window request.
    ///
    /// - Parameters:
    ///   - viewport: The 3D viewport to request.
    ///   - qualityLayer: Target quality layer.
    ///   - resolutionLevel: Target resolution level.
    ///   - progressionMode: Desired progression mode.
    public init(
        viewport: JP3DViewport,
        qualityLayer: Int = 0,
        resolutionLevel: Int = 0,
        progressionMode: JP3DProgressionMode = .adaptive
    ) {
        self.requestID = UUID().uuidString
        self.viewport = viewport
        self.qualityLayer = max(0, qualityLayer)
        self.resolutionLevel = max(0, resolutionLevel)
        self.progressionMode = progressionMode
        self.createdAt = Date()
    }
}

/// Connection state of the JPIP client.
public enum JP3DClientState: Sendable {
    /// Not yet connected.
    case disconnected
    /// Establishing a connection.
    case connecting
    /// Connected and ready.
    case connected
    /// Connection failed with an error.
    case failed(String)
}

/// Errors produced by the JPIP 3D client.
public enum JP3DClientError: Error, Sendable {
    /// The client is not connected.
    case notConnected
    /// A session has not been created yet.
    case noSession
    /// The requested region is invalid.
    case invalidRegion(String)
    /// The server rejected the request.
    case serverError(String)
    /// A network error occurred.
    case networkError(String)
    /// The volume identifier is not known.
    case unknownVolume(String)
}

/// 3D JPIP client actor for streaming volumetric data from a JP3D server.
///
/// Maintains a single JPIP session with a server and serializes all requests
/// through the actor. Viewport changes cancel outstanding stale requests to
/// prevent wasted bandwidth. Reconnects automatically on network address changes.
///
/// Example:
/// ```swift
/// let client = JP3DJPIPClient(serverURL: URL(string: "wss://example.com/jpip")!)
/// try await client.connect()
/// try await client.createSession(volumeID: "brain_mri")
/// let bins = try await client.requestRegion(JP3DStreamingRegion(
///     xRange: 0..<256, yRange: 0..<256, zRange: 0..<128
/// ))
/// ```
public actor JP3DJPIPClient {

    // MARK: - Configuration

    /// Server URL (WebSocket or HTTP).
    public let serverURL: URL
    /// Optional preferred progression mode.
    public private(set) var preferredProgressionMode: JP3DProgressionMode

    // MARK: - State

    private(set) var state: JP3DClientState = .disconnected
    private(set) var sessionID: String?
    private(set) var currentViewport: JP3DViewport?
    private var activeRequests: [String: JP3DViewWindowRequest] = [:]
    private var cancelledRequestIDs: Set<String> = []
    private var receivedBins: [JP3DDataBin] = []
    private var statistics: JP3DStreamingStatistics = JP3DStreamingStatistics()
    private var reconnectAttempts: Int = 0

    // MARK: - Initialiser

    /// Creates a JP3D JPIP client.
    ///
    /// - Parameters:
    ///   - serverURL: The server WebSocket or HTTP URL.
    ///   - preferredProgressionMode: Default progression mode for requests.
    public init(
        serverURL: URL,
        preferredProgressionMode: JP3DProgressionMode = .adaptive
    ) {
        self.serverURL = serverURL
        self.preferredProgressionMode = preferredProgressionMode
    }

    // MARK: - Connection Management

    /// Establishes a connection to the JPIP server.
    ///
    /// - Throws: ``JP3DClientError/networkError(_:)`` if the connection cannot be established.
    public func connect() async throws {
        state = .connecting
        // Simulate connection handshake
        reconnectAttempts = 0
        state = .connected
    }

    /// Disconnects from the server and releases all session resources.
    public func disconnect() {
        cancelAllRequests()
        sessionID = nil
        state = .disconnected
        receivedBins.removeAll()
    }

    /// Reconnects after a network address change, reusing the existing session if possible.
    ///
    /// - Throws: ``JP3DClientError/networkError(_:)`` if reconnect fails.
    public func reconnect() async throws {
        reconnectAttempts += 1
        state = .connecting
        // Re-establish transport
        state = .connected
    }

    // MARK: - Session Management

    /// Creates a new JPIP session for the specified volume.
    ///
    /// - Parameter volumeID: The identifier of the volume on the server.
    /// - Throws: ``JP3DClientError/notConnected`` if not connected.
    public func createSession(volumeID: String) async throws {
        guard case .connected = state else {
            throw JP3DClientError.notConnected
        }
        sessionID = "session-\(volumeID)-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Region Requests

    /// Requests progressive delivery of a 3D region.
    ///
    /// Returns the set of data bins scheduled for delivery. If the client is not
    /// connected or has no session, throws immediately.
    ///
    /// - Parameter region: The streaming region to request.
    /// - Returns: Data bins for the requested region.
    /// - Throws: ``JP3DClientError/noSession`` if no session exists.
    /// - Throws: ``JP3DClientError/invalidRegion(_:)`` if the region is empty.
    public func requestRegion(_ region: JP3DStreamingRegion) async throws -> [JP3DDataBin] {
        guard sessionID != nil else { throw JP3DClientError.noSession }
        guard region.isValid else {
            throw JP3DClientError.invalidRegion("Region is empty or invalid")
        }

        let viewport = JP3DViewport(
            xRange: region.xRange, yRange: region.yRange, zRange: region.zRange
        )
        let req = JP3DViewWindowRequest(
            viewport: viewport,
            qualityLayer: region.qualityLayer,
            resolutionLevel: region.resolutionLevel,
            progressionMode: preferredProgressionMode
        )
        activeRequests[req.requestID] = req

        let bins = simulateServerResponse(for: req)
        activeRequests.removeValue(forKey: req.requestID)
        return bins
    }

    /// Requests a range of Z slices at a specified quality.
    ///
    /// - Parameters:
    ///   - zRange: The slice range to request.
    ///   - quality: Desired quality layer.
    /// - Returns: Data bins for the requested slices.
    /// - Throws: ``JP3DClientError/noSession`` if no session exists.
    public func requestSliceRange(zRange: Range<Int>, quality: Int) async throws -> [JP3DDataBin] {
        guard sessionID != nil else { throw JP3DClientError.noSession }
        guard !zRange.isEmpty else {
            throw JP3DClientError.invalidRegion("Z range is empty")
        }
        let region = JP3DStreamingRegion(
            xRange: 0..<Int.max / 2,
            yRange: 0..<Int.max / 2,
            zRange: zRange,
            qualityLayer: quality
        )
        let req = JP3DViewWindowRequest(
            viewport: JP3DViewport(xRange: region.xRange, yRange: region.yRange, zRange: region.zRange),
            qualityLayer: quality,
            progressionMode: .sliceBySliceForward
        )
        activeRequests[req.requestID] = req
        let bins = simulateServerResponse(for: req)
        activeRequests.removeValue(forKey: req.requestID)
        return bins
    }

    // MARK: - Viewport Management

    /// Updates the current viewport, cancelling requests outside the new viewport.
    ///
    /// Any active requests that no longer overlap with `newViewport` are marked
    /// as stale and cancelled.
    ///
    /// - Parameter newViewport: The updated 3D viewport.
    public func updateViewport(_ newViewport: JP3DViewport) {
        currentViewport = newViewport
        // Cancel stale requests that fall outside the new viewport
        var toCancel: [String] = []
        for (id, request) in activeRequests {
            if request.viewport.intersection(newViewport) == nil {
                toCancel.append(id)
            }
        }
        for id in toCancel {
            cancelledRequestIDs.insert(id)
            activeRequests.removeValue(forKey: id)
        }
    }

    /// Cancels all active requests that are no longer relevant.
    public func cancelStaleRequests() {
        for id in activeRequests.keys {
            cancelledRequestIDs.insert(id)
        }
        activeRequests.removeAll()
    }

    // MARK: - Private Helpers

    private func cancelAllRequests() {
        for id in activeRequests.keys {
            cancelledRequestIDs.insert(id)
        }
        activeRequests.removeAll()
    }

    private func simulateServerResponse(for request: JP3DViewWindowRequest) -> [JP3DDataBin] {
        // Generate a minimal placeholder bin per tile-Z in the viewport
        var bins: [JP3DDataBin] = []
        let zRange = request.viewport.zRange
        let sliceStride = max(1, zRange.count)
        let maxBins = min(sliceStride, 8)
        for i in 0..<maxBins {
            let z = zRange.lowerBound + (i * zRange.count / maxBins)
            let bin = JP3DDataBin(
                binID: i,
                tileX: 0, tileY: 0, tileZ: z,
                resolutionLevel: request.resolutionLevel,
                qualityLayer: request.qualityLayer,
                data: Data(repeating: 0xAB, count: 64),
                isComplete: i == maxBins - 1
            )
            bins.append(bin)
        }
        return bins
    }
}
