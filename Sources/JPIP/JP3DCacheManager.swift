/// # JP3DCacheManager
///
/// 3D-aware cache manager for volumetric JPIP data bins.
///
/// Stores data bins with spatial metadata and supports multiple eviction policies:
/// LRU (least recently used), spatial proximity, view frustum visibility, and
/// resolution level. Tracks hit/miss statistics for adaptive scheduling.
///
/// ## Topics
///
/// ### Cache Actor
/// - ``JP3DCacheManager``
///
/// ### Statistics
/// - ``JP3DCacheStatistics``

import Foundation
import J2KCore

/// Statistics for the cache manager.
public struct JP3DCacheStatistics: Sendable {
    /// Total number of cache lookup requests.
    public let totalRequests: Int
    /// Number of cache hits.
    public let hits: Int
    /// Number of cache misses.
    public let misses: Int
    /// Number of entries evicted since creation.
    public let evictions: Int
    /// Current memory usage in bytes.
    public let memoryUsage: Int
    /// Current number of entries.
    public let entryCount: Int
    /// Fraction of requests satisfied from cache.
    public var hitRate: Double {
        totalRequests > 0 ? Double(hits) / Double(totalRequests) : 0.0
    }
    /// Fraction of available cache memory currently used.
    public var memoryUtilization: Double {
        maxMemoryBytes > 0 ? Double(memoryUsage) / Double(maxMemoryBytes) : 0.0
    }
    /// Maximum allowed memory (stored for utilization calculation).
    let maxMemoryBytes: Int

    /// Creates cache statistics.
    public init(
        totalRequests: Int, hits: Int, misses: Int, evictions: Int,
        memoryUsage: Int, entryCount: Int, maxMemoryBytes: Int
    ) {
        self.totalRequests = totalRequests
        self.hits = hits
        self.misses = misses
        self.evictions = evictions
        self.memoryUsage = memoryUsage
        self.entryCount = entryCount
        self.maxMemoryBytes = maxMemoryBytes
    }
}

/// Cache eviction strategy selector.
public enum JP3DCacheEvictionStrategy: Sendable {
    /// Remove the least recently used entries.
    case lru
    /// Remove entries farthest from a spatial center point.
    case spatialProximity(centerX: Double, centerY: Double, centerZ: Double)
    /// Remove entries not visible in the given frustum.
    case viewFrustum(JP3DViewFrustum)
    /// Remove entries at or below a specific resolution level.
    case resolutionLevel(Int)
    /// Remove entries from a specific region.
    case region(JP3DStreamingRegion)
}

/// 3D-aware cache actor for volumetric JPIP data bins.
///
/// All reads and writes are serialized through the actor, making the cache safe
/// for concurrent use from multiple streaming sessions. Eviction policies account
/// for spatial position, view frustum, resolution level, and recency.
///
/// Example:
/// ```swift
/// let cache = JP3DCacheManager(maxMemoryBytes: 512 * 1024 * 1024, maxEntries: 4096)
/// try await cache.store(key: precinctID, data: binData, region: region, resolutionLevel: 2)
/// if let data = await cache.retrieve(key: precinctID) {
///     // use cached data
/// }
/// ```
public actor JP3DCacheManager {

    // MARK: - Configuration

    /// Maximum memory the cache may use in bytes.
    public let maxMemoryBytes: Int
    /// Maximum number of cache entries.
    public let maxEntries: Int

    // MARK: - State

    private var entries: [JP3DPrecinct3D: JP3DCacheEntry] = [:]
    private var totalMemoryBytes: Int = 0

    // Statistics counters
    private var statTotalRequests: Int = 0
    private var statHits: Int = 0
    private var statEvictions: Int = 0

    // MARK: - Initialiser

    /// Creates a cache manager with the specified capacity.
    ///
    /// - Parameters:
    ///   - maxMemoryBytes: Maximum bytes to use for cached data.
    ///   - maxEntries: Maximum number of entries to hold.
    public init(maxMemoryBytes: Int = 256 * 1024 * 1024, maxEntries: Int = 2048) {
        self.maxMemoryBytes = max(1, maxMemoryBytes)
        self.maxEntries = max(1, maxEntries)
    }

    // MARK: - Public API

    /// Stores a data bin in the cache.
    ///
    /// If the cache is at capacity, an LRU eviction pass is performed before
    /// inserting the new entry. Entries that exceed the total memory limit
    /// trigger additional eviction until space is available.
    ///
    /// - Parameters:
    ///   - key: Precinct identifier used as cache key.
    ///   - bin: The data bin to store.
    ///   - region: Spatial region covered by the bin.
    public func store(key: JP3DPrecinct3D, bin: JP3DDataBin, region: JP3DStreamingRegion) {
        // Replace existing entry
        if let existing = entries[key] {
            totalMemoryBytes -= existing.byteCount
        }
        let entry = JP3DCacheEntry(bin: bin, region: region)
        entries[key] = entry
        totalMemoryBytes += entry.byteCount

        // Evict if over limits
        evictIfNeeded()
    }

    /// Retrieves a data bin from the cache, updating access statistics.
    ///
    /// - Parameter key: Precinct identifier.
    /// - Returns: The cached bin, or `nil` on cache miss.
    public func retrieve(key: JP3DPrecinct3D) -> JP3DDataBin? {
        statTotalRequests += 1
        if var entry = entries[key] {
            entry.lastAccessed = Date()
            entry.accessCount += 1
            entries[key] = entry
            statHits += 1
            return entry.bin
        }
        return nil
    }

    /// Explicitly evicts entries using the specified strategy.
    ///
    /// - Parameters:
    ///   - strategy: The eviction strategy to apply.
    ///   - targetFraction: Fraction of current entries to evict (0–1, default 0.25).
    public func evict(strategy: JP3DCacheEvictionStrategy, targetFraction: Double = 0.25) {
        let targetCount = max(1, Int(Double(entries.count) * targetFraction))
        switch strategy {
        case .lru:
            evictLRU(count: targetCount)
        case .spatialProximity(let cx, let cy, let cz):
            evictBySpatialDistance(centerX: cx, centerY: cy, centerZ: cz, count: targetCount)
        case .viewFrustum(let frustum):
            evictOutsideFrustum(frustum: frustum)
        case .resolutionLevel(let level):
            evictByResolutionLevel(level)
        case .region(let region):
            evictRegion(region)
        }
    }

    /// Invalidates all cached entries that overlap a given region.
    ///
    /// - Parameter region: The region to invalidate.
    public func invalidateRegion(_ region: JP3DStreamingRegion) {
        evictRegion(region)
    }

    /// Removes all entries from the cache.
    public func clear() {
        entries.removeAll()
        totalMemoryBytes = 0
    }

    /// Current cache statistics.
    public var statistics: JP3DCacheStatistics {
        JP3DCacheStatistics(
            totalRequests: statTotalRequests,
            hits: statHits,
            misses: statTotalRequests - statHits,
            evictions: statEvictions,
            memoryUsage: totalMemoryBytes,
            entryCount: entries.count,
            maxMemoryBytes: maxMemoryBytes
        )
    }

    /// Current number of cached entries.
    public var entryCount: Int { entries.count }

    /// Current memory used by cached data in bytes.
    public var memoryUsed: Int { totalMemoryBytes }

    // MARK: - Private Eviction Helpers

    private func evictIfNeeded() {
        while entries.count > maxEntries || totalMemoryBytes > maxMemoryBytes {
            if entries.isEmpty { break }
            evictLRU(count: 1)
        }
    }

    private func evictLRU(count: Int) {
        let sorted = entries.sorted { a, b in
            a.value.lastAccessed < b.value.lastAccessed
        }
        let toRemove = sorted.prefix(count)
        for (key, entry) in toRemove {
            entries.removeValue(forKey: key)
            totalMemoryBytes -= entry.byteCount
            statEvictions += 1
        }
    }

    private func evictBySpatialDistance(centerX: Double, centerY: Double, centerZ: Double, count: Int) {
        let sorted = entries.sorted { a, b in
            distance(entry: a.value, cx: centerX, cy: centerY, cz: centerZ)
                > distance(entry: b.value, cx: centerX, cy: centerY, cz: centerZ)
        }
        let toRemove = sorted.prefix(count)
        for (key, entry) in toRemove {
            entries.removeValue(forKey: key)
            totalMemoryBytes -= entry.byteCount
            statEvictions += 1
        }
    }

    private func evictOutsideFrustum(frustum: JP3DViewFrustum) {
        var toRemove: [JP3DPrecinct3D] = []
        for (key, entry) in entries {
            let r = entry.region
            if !frustum.intersects(xRange: r.xRange, yRange: r.yRange, zRange: r.zRange) {
                toRemove.append(key)
            }
        }
        for key in toRemove {
            if let entry = entries.removeValue(forKey: key) {
                totalMemoryBytes -= entry.byteCount
                statEvictions += 1
            }
        }
    }

    private func evictByResolutionLevel(_ level: Int) {
        var toRemove: [JP3DPrecinct3D] = []
        for (key, _) in entries where key.resolutionLevel <= level {
            toRemove.append(key)
        }
        for key in toRemove {
            if let entry = entries.removeValue(forKey: key) {
                totalMemoryBytes -= entry.byteCount
                statEvictions += 1
            }
        }
    }

    private func evictRegion(_ region: JP3DStreamingRegion) {
        var toRemove: [JP3DPrecinct3D] = []
        for (key, entry) in entries {
            let r = entry.region
            let xOverlap = r.xRange.overlaps(region.xRange)
            let yOverlap = r.yRange.overlaps(region.yRange)
            let zOverlap = r.zRange.overlaps(region.zRange)
            if xOverlap && yOverlap && zOverlap {
                toRemove.append(key)
            }
        }
        for key in toRemove {
            if let entry = entries.removeValue(forKey: key) {
                totalMemoryBytes -= entry.byteCount
                statEvictions += 1
            }
        }
    }

    private func distance(entry: JP3DCacheEntry, cx: Double, cy: Double, cz: Double) -> Double {
        let r = entry.region
        let ex = Double(r.xRange.lowerBound + r.xRange.upperBound) / 2.0
        let ey = Double(r.yRange.lowerBound + r.yRange.upperBound) / 2.0
        let ez = Double(r.zRange.lowerBound + r.zRange.upperBound) / 2.0
        let dx = ex - cx, dy = ey - cy, dz = ez - cz
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
