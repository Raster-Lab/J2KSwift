//
// JPIPSessionManager.swift
// J2KSwift
//
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

    /// Precinct-based cache for fine-grained data management.
    private var precinctCache: JPIPPrecinctCache

    /// Creates a new JPIP session.
    ///
    /// - Parameter sessionID: A unique session identifier.
    public init(sessionID: String) {
        self.sessionID = sessionID
        self.isActive = false
        self.cacheModel = JPIPCacheModel()
        self.precinctCache = JPIPPrecinctCache()
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
        self.precinctCache.clear()
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
        cacheModel.hasDataBin(binClass: binClass, binID: binID)
    }

    /// Retrieves a cached data bin.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: The cached data bin, or nil if not found.
    public func getDataBin(binClass: JPIPDataBinClass, binID: Int) -> JPIPDataBin? {
        cacheModel.getDataBin(binClass: binClass, binID: binID)
    }

    /// Gets the current cache statistics.
    ///
    /// - Returns: Cache statistics including hits, misses, and size.
    public func getCacheStatistics() -> JPIPCacheModel.Statistics {
        cacheModel.statistics
    }

    /// Invalidates cached entries by bin class.
    ///
    /// - Parameter binClass: The bin class to invalidate.
    public func invalidateCache(binClass: JPIPDataBinClass) {
        cacheModel.invalidate(binClass: binClass)
    }

    /// Invalidates cached entries older than a given date.
    ///
    /// - Parameter date: Entries older than this date will be removed.
    public func invalidateCache(olderThan date: Date) {
        cacheModel.invalidate(olderThan: date)
    }

    /// Adds a precinct to the cache.
    ///
    /// - Parameter precinctData: The precinct data to cache.
    public func addPrecinct(_ precinctData: JPIPPrecinctData) {
        precinctCache.addPrecinct(precinctData)
    }

    /// Retrieves a cached precinct.
    ///
    /// - Parameter precinctID: The precinct identifier.
    /// - Returns: The cached precinct data, or nil if not found.
    public func getPrecinct(_ precinctID: JPIPPrecinctID) -> JPIPPrecinctData? {
        precinctCache.getPrecinct(precinctID)
    }

    /// Checks if a precinct is in the cache.
    ///
    /// - Parameter precinctID: The precinct identifier.
    /// - Returns: True if the precinct is cached.
    public func hasPrecinct(_ precinctID: JPIPPrecinctID) -> Bool {
        precinctCache.hasPrecinct(precinctID)
    }

    /// Gets precinct cache statistics.
    ///
    /// - Returns: Precinct cache statistics.
    public func getPrecinctStatistics() -> JPIPPrecinctCache.Statistics {
        precinctCache.statistics
    }

    /// Merges partial precinct data with existing cached data.
    ///
    /// - Parameters:
    ///   - precinctID: The precinct identifier.
    ///   - data: The new data to merge.
    ///   - layers: The quality layers in the new data.
    ///   - isComplete: Whether the precinct is now complete.
    /// - Returns: The merged precinct data.
    public func mergePrecinct(
        _ precinctID: JPIPPrecinctID,
        data: Data,
        layers: Set<Int>,
        isComplete: Bool
    ) -> JPIPPrecinctData {
        precinctCache.mergePrecinct(precinctID, data: data, layers: layers, isComplete: isComplete)
    }

    /// Invalidates precincts for a specific tile.
    ///
    /// - Parameter tile: The tile index to invalidate.
    public func invalidatePrecincts(tile: Int) {
        precinctCache.invalidate(tile: tile)
    }

    /// Invalidates precincts for a specific resolution level.
    ///
    /// - Parameter resolution: The resolution level to invalidate.
    public func invalidatePrecincts(resolution: Int) {
        precinctCache.invalidate(resolution: resolution)
    }
}

/// Tracks cached JPIP data bins with advanced management features.
///
/// Provides client-side caching with:
/// - Precinct-based tracking
/// - Cache statistics
/// - LRU eviction policy
/// - Selective invalidation
public struct JPIPCacheModel: Sendable {
    /// Represents a cached entry with metadata.
    struct CacheEntry: Sendable {
        /// The cached data bin.
        let dataBin: JPIPDataBin

        /// Timestamp when the entry was added or last accessed.
        let timestamp: Date

        /// Number of times this entry has been accessed.
        var accessCount: Int

        /// Size of the data in bytes.
        let size: Int

        /// Creates a new cache entry.
        init(dataBin: JPIPDataBin, timestamp: Date = Date(), accessCount: Int = 0) {
            self.dataBin = dataBin
            self.timestamp = timestamp
            self.accessCount = accessCount
            self.size = dataBin.data.count
        }
    }

    /// Cache statistics.
    public struct Statistics: Sendable {
        /// Total number of cache hits.
        public var hits: Int = 0

        /// Total number of cache misses.
        public var misses: Int = 0

        /// Total size of cached data in bytes.
        public var totalSize: Int = 0

        /// Number of entries in cache.
        public var entryCount: Int = 0

        /// Number of evictions performed.
        public var evictions: Int = 0

        /// Cache hit rate (0.0 to 1.0).
        public var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }
    }

    /// Maps bin class and ID to cached entries.
    private var cachedBins: [String: CacheEntry]

    /// Cache statistics.
    public private(set) var statistics: Statistics

    /// Maximum cache size in bytes (default: 100 MB).
    private let maxCacheSize: Int

    /// Maximum number of cached entries (default: 10,000).
    private let maxEntries: Int

    /// Creates a new cache model.
    ///
    /// - Parameters:
    ///   - maxCacheSize: Maximum cache size in bytes (default: 100 MB).
    ///   - maxEntries: Maximum number of entries (default: 10,000).
    public init(maxCacheSize: Int = 100 * 1024 * 1024, maxEntries: Int = 10_000) {
        self.cachedBins = [:]
        self.statistics = Statistics()
        self.maxCacheSize = maxCacheSize
        self.maxEntries = maxEntries
    }

    /// Creates a cache key for a data bin.
    private func cacheKey(binClass: JPIPDataBinClass, binID: Int) -> String {
        "\(binClass.rawValue):\(binID)"
    }

    /// Adds a data bin to the cache.
    ///
    /// If the cache is full, performs LRU eviction before adding.
    ///
    /// - Parameter dataBin: The data bin to cache.
    mutating func addDataBin(_ dataBin: JPIPDataBin) {
        let key = cacheKey(binClass: dataBin.binClass, binID: dataBin.binID)
        let newSize = dataBin.data.count

        // If entry exists, update it
        if var existingEntry = cachedBins[key] {
            statistics.totalSize -= existingEntry.size
            existingEntry = CacheEntry(
                dataBin: dataBin,
                timestamp: Date(),
                accessCount: existingEntry.accessCount
            )
            cachedBins[key] = existingEntry
            statistics.totalSize += newSize
            return
        }

        // Check if we need to evict entries
        while (statistics.totalSize + newSize > maxCacheSize ||
               statistics.entryCount >= maxEntries) && !cachedBins.isEmpty {
            evictLRU()
        }

        // Add new entry
        let entry = CacheEntry(dataBin: dataBin)
        cachedBins[key] = entry
        statistics.totalSize += newSize
        statistics.entryCount += 1
    }

    /// Retrieves a data bin from the cache.
    ///
    /// Updates access statistics on hit.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: The cached data bin, or nil if not found.
    mutating func getDataBin(binClass: JPIPDataBinClass, binID: Int) -> JPIPDataBin? {
        let key = cacheKey(binClass: binClass, binID: binID)

        if var entry = cachedBins[key] {
            statistics.hits += 1
            entry.accessCount += 1
            cachedBins[key] = entry
            return entry.dataBin
        } else {
            statistics.misses += 1
            return nil
        }
    }

    /// Checks if a data bin is in the cache.
    ///
    /// Does not update access statistics.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    /// - Returns: True if the bin is cached.
    func hasDataBin(binClass: JPIPDataBinClass, binID: Int) -> Bool {
        let key = cacheKey(binClass: binClass, binID: binID)
        return cachedBins[key] != nil
    }

    /// Evicts the least recently used entry from the cache.
    private mutating func evictLRU() {
        guard let oldestKey = cachedBins.min(by: { $0.value.timestamp < $1.value.timestamp })?.key else {
            return
        }

        if let entry = cachedBins.removeValue(forKey: oldestKey) {
            statistics.totalSize -= entry.size
            statistics.entryCount -= 1
            statistics.evictions += 1
        }
    }

    /// Invalidates cache entries by bin class.
    ///
    /// - Parameter binClass: The bin class to invalidate.
    mutating func invalidate(binClass: JPIPDataBinClass) {
        let keysToRemove = cachedBins.keys.filter { key in
            key.hasPrefix("\(binClass.rawValue):")
        }

        for key in keysToRemove {
            if let entry = cachedBins.removeValue(forKey: key) {
                statistics.totalSize -= entry.size
                statistics.entryCount -= 1
            }
        }
    }

    /// Invalidates cache entries older than a given date.
    ///
    /// - Parameter date: Entries older than this date will be removed.
    mutating func invalidate(olderThan date: Date) {
        let keysToRemove = cachedBins.filter { $0.value.timestamp < date }.map { $0.key }

        for key in keysToRemove {
            if let entry = cachedBins.removeValue(forKey: key) {
                statistics.totalSize -= entry.size
                statistics.entryCount -= 1
            }
        }
    }

    /// Clears all cached bins.
    mutating func clear() {
        cachedBins.removeAll()
        statistics = Statistics()
    }
}
