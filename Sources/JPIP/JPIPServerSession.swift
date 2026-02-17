/// # JPIPServerSession
///
/// Server-side session management for JPIP clients.

import Foundation
import J2KCore

/// Represents a server-side session for a JPIP client.
///
/// Each session tracks what data the client has received (cache model)
/// and maintains state for progressive image transmission.
public actor JPIPServerSession {
    /// The unique session identifier.
    nonisolated public let sessionID: String

    /// The channel ID for this session.
    nonisolated public let channelID: String

    /// The target image being accessed.
    nonisolated public let target: String

    /// Whether the session is active.
    public private(set) var isActive: Bool

    /// Last activity timestamp.
    public private(set) var lastActivity: Date

    /// Client cache model tracking what data has been sent.
    private var clientCache: JPIPCacheModel

    /// Session metadata.
    private var metadata: [String: String]

    /// Total bytes sent in this session.
    public private(set) var totalBytesSent: Int

    /// Total requests handled in this session.
    public private(set) var totalRequests: Int

    /// Creates a new server session.
    ///
    /// - Parameters:
    ///   - sessionID: Unique session identifier.
    ///   - channelID: Channel ID for the client.
    ///   - target: Target image name.
    public init(sessionID: String, channelID: String, target: String) {
        self.sessionID = sessionID
        self.channelID = channelID
        self.target = target
        self.isActive = true
        self.lastActivity = Date()
        self.clientCache = JPIPCacheModel()
        self.metadata = [:]
        self.totalBytesSent = 0
        self.totalRequests = 0
    }

    /// Updates the last activity timestamp.
    public func updateActivity() {
        self.lastActivity = Date()
    }

    /// Records that a request was handled.
    ///
    /// - Parameter bytesSent: Number of bytes sent in the response.
    public func recordRequest(bytesSent: Int) {
        self.totalRequests += 1
        self.totalBytesSent += bytesSent
        updateActivity()
    }

    /// Checks if a data bin has been sent to the client.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: True if the bin was already sent.
    public func hasDataBin(binClass: JPIPDataBinClass, binID: Int) -> Bool {
        return clientCache.hasDataBin(binClass: binClass, binID: binID)
    }

    /// Records that a data bin was sent to the client.
    ///
    /// - Parameter dataBin: The data bin that was sent.
    public func recordSentDataBin(_ dataBin: JPIPDataBin) {
        clientCache.addDataBin(dataBin)
    }

    /// Gets the client cache statistics.
    ///
    /// - Returns: Cache statistics.
    public func getCacheStatistics() -> JPIPCacheModel.Statistics {
        return clientCache.statistics
    }

    /// Sets metadata for the session.
    ///
    /// - Parameters:
    ///   - key: Metadata key.
    ///   - value: Metadata value.
    public func setMetadata(_ key: String, value: String) {
        metadata[key] = value
    }

    /// Gets metadata from the session.
    ///
    /// - Parameter key: Metadata key.
    /// - Returns: Metadata value if found.
    public func getMetadata(_ key: String) -> String? {
        return metadata[key]
    }

    /// Checks if the session has timed out.
    ///
    /// - Parameter timeout: Timeout duration in seconds.
    /// - Returns: True if the session has timed out.
    public func hasTimedOut(timeout: TimeInterval) -> Bool {
        return Date().timeIntervalSince(lastActivity) > timeout
    }

    /// Closes the session and cleans up resources.
    public func close() {
        self.isActive = false
        self.clientCache.clear()
        self.metadata.removeAll()
    }

    /// Gets session information for debugging.
    ///
    /// - Returns: Dictionary with session information.
    public func getInfo() -> SessionInfo {
        return SessionInfo(
            sessionID: sessionID,
            channelID: channelID,
            target: target,
            isActive: isActive,
            lastActivity: lastActivity,
            totalBytesSent: totalBytesSent,
            totalRequests: totalRequests,
            cacheSize: clientCache.statistics.totalSize,
            cacheEntries: clientCache.statistics.entryCount
        )
    }

    /// Session information struct.
    public struct SessionInfo: Sendable {
        public let sessionID: String
        public let channelID: String
        public let target: String
        public let isActive: Bool
        public let lastActivity: Date
        public let totalBytesSent: Int
        public let totalRequests: Int
        public let cacheSize: Int
        public let cacheEntries: Int
    }
}
