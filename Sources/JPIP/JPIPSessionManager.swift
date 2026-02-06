/// # JPIPSession
///
/// Session management for JPIP protocol.

import Foundation
import J2KCore

/// Manages a JPIP session with a server.
public actor JPIPSession {
    /// The unique session identifier.
    public let sessionID: String
    
    /// The channel ID assigned by the server.
    public private(set) var channelID: String?
    
    /// The target image being accessed.
    public private(set) var target: String?
    
    /// Whether the session is active.
    public private(set) var isActive: Bool
    
    /// Cache model tracking what data the client has.
    private var cacheModel: JPIPCacheModel
    
    /// Creates a new JPIP session.
    ///
    /// - Parameter sessionID: A unique session identifier.
    public init(sessionID: String) {
        self.sessionID = sessionID
        self.isActive = false
        self.cacheModel = JPIPCacheModel()
    }
    
    /// Sets the channel ID for this session.
    ///
    /// - Parameter channelID: The channel ID from the server.
    internal func setChannelID(_ channelID: String) {
        self.channelID = channelID
    }
    
    /// Sets the target image for this session.
    ///
    /// - Parameter target: The target image identifier.
    internal func setTarget(_ target: String) {
        self.target = target
    }
    
    /// Activates the session.
    internal func activate() {
        self.isActive = true
    }
    
    /// Closes the session.
    ///
    /// - Throws: ``J2KError`` if closing fails.
    public func close() async throws {
        self.isActive = false
        self.channelID = nil
        self.target = nil
        self.cacheModel.clear()
    }
    
    /// Records that a data bin has been received.
    ///
    /// - Parameter dataBin: The data bin that was received.
    internal func recordDataBin(_ dataBin: JPIPDataBin) {
        cacheModel.addDataBin(dataBin)
    }
    
    /// Checks if a data bin is already in the cache.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: True if the bin is cached.
    public func hasDataBin(binClass: JPIPDataBinClass, binID: Int) -> Bool {
        return cacheModel.hasDataBin(binClass: binClass, binID: binID)
    }
}

/// Tracks cached JPIP data bins.
struct JPIPCacheModel: Sendable {
    /// Maps bin class and ID to cached bins.
    private var cachedBins: [String: JPIPDataBin]
    
    init() {
        self.cachedBins = [:]
    }
    
    /// Creates a cache key for a data bin.
    private func cacheKey(binClass: JPIPDataBinClass, binID: Int) -> String {
        return "\(binClass.rawValue):\(binID)"
    }
    
    /// Adds a data bin to the cache.
    mutating func addDataBin(_ dataBin: JPIPDataBin) {
        let key = cacheKey(binClass: dataBin.binClass, binID: dataBin.binID)
        cachedBins[key] = dataBin
    }
    
    /// Checks if a data bin is in the cache.
    func hasDataBin(binClass: JPIPDataBinClass, binID: Int) -> Bool {
        let key = cacheKey(binClass: binClass, binID: binID)
        return cachedBins[key] != nil
    }
    
    /// Clears all cached bins.
    mutating func clear() {
        cachedBins.removeAll()
    }
}
