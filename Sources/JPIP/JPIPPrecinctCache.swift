/// # JPIPPrecinctCache
///
/// Precinct-based caching for JPIP protocol.

import Foundation
import J2KCore

/// Represents a precinct identifier for caching purposes.
public struct JPIPPrecinctID: Hashable, Sendable {
    /// The tile index.
    public let tile: Int
    
    /// The component index.
    public let component: Int
    
    /// The resolution level.
    public let resolution: Int
    
    /// The precinct position in X direction.
    public let precinctX: Int
    
    /// The precinct position in Y direction.
    public let precinctY: Int
    
    /// Creates a new precinct identifier.
    ///
    /// - Parameters:
    ///   - tile: The tile index.
    ///   - component: The component index.
    ///   - resolution: The resolution level.
    ///   - precinctX: The precinct X position.
    ///   - precinctY: The precinct Y position.
    public init(tile: Int, component: Int, resolution: Int, precinctX: Int, precinctY: Int) {
        self.tile = tile
        self.component = component
        self.resolution = resolution
        self.precinctX = precinctX
        self.precinctY = precinctY
    }
}

/// Represents cached precinct data with completion tracking.
public struct JPIPPrecinctData: Sendable {
    /// The precinct identifier.
    public let precinctID: JPIPPrecinctID
    
    /// The cached data.
    public let data: Data
    
    /// Whether this precinct is complete.
    public let isComplete: Bool
    
    /// Quality layers that have been received.
    public let receivedLayers: Set<Int>
    
    /// Timestamp when this data was cached.
    public let timestamp: Date
    
    /// Creates new precinct data.
    ///
    /// - Parameters:
    ///   - precinctID: The precinct identifier.
    ///   - data: The cached data.
    ///   - isComplete: Whether the precinct is complete.
    ///   - receivedLayers: Set of received quality layers.
    ///   - timestamp: When the data was cached.
    public init(
        precinctID: JPIPPrecinctID,
        data: Data,
        isComplete: Bool,
        receivedLayers: Set<Int>,
        timestamp: Date = Date()
    ) {
        self.precinctID = precinctID
        self.data = data
        self.isComplete = isComplete
        self.receivedLayers = receivedLayers
        self.timestamp = timestamp
    }
}

/// Manages precinct-based caching for JPIP.
public struct JPIPPrecinctCache: Sendable {
    /// Statistics for precinct caching.
    public struct Statistics: Sendable {
        /// Total number of precincts cached.
        public var totalPrecincts: Int = 0
        
        /// Number of complete precincts.
        public var completePrecincts: Int = 0
        
        /// Number of partial precincts.
        public var partialPrecincts: Int = 0
        
        /// Total size of cached precinct data.
        public var totalSize: Int = 0
        
        /// Number of precinct cache hits.
        public var hits: Int = 0
        
        /// Number of precinct cache misses.
        public var misses: Int = 0
        
        /// Completion rate (0.0 to 1.0).
        public var completionRate: Double {
            return totalPrecincts > 0 ? Double(completePrecincts) / Double(totalPrecincts) : 0.0
        }
        
        /// Hit rate (0.0 to 1.0).
        public var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }
    }
    
    /// Cached precincts mapped by precinct ID.
    private var precincts: [JPIPPrecinctID: JPIPPrecinctData]
    
    /// Cache statistics.
    private(set) var statistics: Statistics
    
    /// Maximum cache size in bytes.
    private let maxCacheSize: Int
    
    /// Maximum number of precincts to cache.
    private let maxPrecincts: Int
    
    /// Creates a new precinct cache.
    ///
    /// - Parameters:
    ///   - maxCacheSize: Maximum cache size in bytes (default: 200 MB).
    ///   - maxPrecincts: Maximum number of precincts (default: 5,000).
    public init(maxCacheSize: Int = 200 * 1024 * 1024, maxPrecincts: Int = 5_000) {
        self.precincts = [:]
        self.statistics = Statistics()
        self.maxCacheSize = maxCacheSize
        self.maxPrecincts = maxPrecincts
    }
    
    /// Adds or updates a precinct in the cache.
    ///
    /// - Parameter precinctData: The precinct data to cache.
    public mutating func addPrecinct(_ precinctData: JPIPPrecinctData) {
        let id = precinctData.precinctID
        
        // Update statistics if this is a new precinct
        if precincts[id] == nil {
            statistics.totalPrecincts += 1
            if precinctData.isComplete {
                statistics.completePrecincts += 1
            } else {
                statistics.partialPrecincts += 1
            }
        } else {
            // Update completion status if changed
            if let existing = precincts[id] {
                statistics.totalSize -= existing.data.count
                if !existing.isComplete && precinctData.isComplete {
                    statistics.completePrecincts += 1
                    statistics.partialPrecincts -= 1
                }
            }
        }
        
        // Check if we need to evict precincts
        while (statistics.totalSize + precinctData.data.count > maxCacheSize || 
               statistics.totalPrecincts > maxPrecincts) && !precincts.isEmpty {
            evictOldest()
        }
        
        precincts[id] = precinctData
        statistics.totalSize += precinctData.data.count
    }
    
    /// Retrieves a precinct from the cache.
    ///
    /// - Parameter precinctID: The precinct identifier.
    /// - Returns: The cached precinct data, or nil if not found.
    public mutating func getPrecinct(_ precinctID: JPIPPrecinctID) -> JPIPPrecinctData? {
        if let data = precincts[precinctID] {
            statistics.hits += 1
            return data
        } else {
            statistics.misses += 1
            return nil
        }
    }
    
    /// Checks if a precinct is in the cache.
    ///
    /// - Parameter precinctID: The precinct identifier.
    /// - Returns: True if the precinct is cached.
    public func hasPrecinct(_ precinctID: JPIPPrecinctID) -> Bool {
        return precincts[precinctID] != nil
    }
    
    /// Checks if a precinct is complete.
    ///
    /// - Parameter precinctID: The precinct identifier.
    /// - Returns: True if the precinct is complete, false if partial or not cached.
    public func isPrecinctComplete(_ precinctID: JPIPPrecinctID) -> Bool {
        return precincts[precinctID]?.isComplete ?? false
    }
    
    /// Gets all precincts for a given tile.
    ///
    /// - Parameter tile: The tile index.
    /// - Returns: Array of precinct data for the tile.
    public func getPrecincts(forTile tile: Int) -> [JPIPPrecinctData] {
        return precincts.values.filter { $0.precinctID.tile == tile }
    }
    
    /// Gets all precincts for a given resolution level.
    ///
    /// - Parameter resolution: The resolution level.
    /// - Returns: Array of precinct data for the resolution.
    public func getPrecincts(forResolution resolution: Int) -> [JPIPPrecinctData] {
        return precincts.values.filter { $0.precinctID.resolution == resolution }
    }
    
    /// Invalidates all precincts for a tile.
    ///
    /// - Parameter tile: The tile index to invalidate.
    public mutating func invalidate(tile: Int) {
        let toRemove = precincts.filter { $0.value.precinctID.tile == tile }
        for (id, data) in toRemove {
            precincts.removeValue(forKey: id)
            statistics.totalSize -= data.data.count
            statistics.totalPrecincts -= 1
            if data.isComplete {
                statistics.completePrecincts -= 1
            } else {
                statistics.partialPrecincts -= 1
            }
        }
    }
    
    /// Invalidates all precincts for a resolution level.
    ///
    /// - Parameter resolution: The resolution level to invalidate.
    public mutating func invalidate(resolution: Int) {
        let toRemove = precincts.filter { $0.value.precinctID.resolution == resolution }
        for (id, data) in toRemove {
            precincts.removeValue(forKey: id)
            statistics.totalSize -= data.data.count
            statistics.totalPrecincts -= 1
            if data.isComplete {
                statistics.completePrecincts -= 1
            } else {
                statistics.partialPrecincts -= 1
            }
        }
    }
    
    /// Clears all cached precincts.
    public mutating func clear() {
        precincts.removeAll()
        statistics = Statistics()
    }
    
    /// Evicts the oldest precinct from the cache.
    private mutating func evictOldest() {
        guard let oldest = precincts.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        
        if let data = precincts.removeValue(forKey: oldest.key) {
            statistics.totalSize -= data.data.count
            statistics.totalPrecincts -= 1
            if data.isComplete {
                statistics.completePrecincts -= 1
            } else {
                statistics.partialPrecincts -= 1
            }
        }
    }
    
    /// Merges partial precinct data with existing cached data.
    ///
    /// If the precinct already exists in the cache, this method merges the new
    /// data with the existing data by combining received layers.
    ///
    /// - Parameters:
    ///   - precinctID: The precinct identifier.
    ///   - data: The new data to merge.
    ///   - layers: The quality layers in the new data.
    ///   - isComplete: Whether the precinct is now complete.
    /// - Returns: The merged precinct data.
    public mutating func mergePrecinct(
        _ precinctID: JPIPPrecinctID,
        data: Data,
        layers: Set<Int>,
        isComplete: Bool
    ) -> JPIPPrecinctData {
        if let existing = precincts[precinctID] {
            // Merge layers
            var mergedLayers = existing.receivedLayers
            mergedLayers.formUnion(layers)
            
            // Combine data (in real implementation, this would be more sophisticated)
            var mergedData = existing.data
            mergedData.append(data)
            
            let merged = JPIPPrecinctData(
                precinctID: precinctID,
                data: mergedData,
                isComplete: isComplete || existing.isComplete,
                receivedLayers: mergedLayers
            )
            
            addPrecinct(merged)
            return merged
        } else {
            let newData = JPIPPrecinctData(
                precinctID: precinctID,
                data: data,
                isComplete: isComplete,
                receivedLayers: layers
            )
            addPrecinct(newData)
            return newData
        }
    }
}
