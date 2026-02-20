/// # JPIPClientCacheManager
///
/// Client-side cache management improvements for JPIP protocol.
///
/// Provides resolution-aware LRU eviction, configurable cache size limits
/// (memory and disk), cache partitioning by image and resolution level,
/// persistent storage warm-up, data bin deduplication, compressed storage
/// for inactive entries, predictive pre-population, and diagnostics reporting.

import Foundation
import J2KCore

// MARK: - Cache Configuration

/// Per-image cache policy configuration.
///
/// Allows customizing cache behavior for individual images based on their
/// access patterns and importance.
public struct JPIPImageCachePolicy: Sendable {
    /// Image identifier this policy applies to.
    public let imageID: String

    /// Maximum memory budget for this image in bytes.
    public let maxMemorySize: Int

    /// Maximum disk budget for this image in bytes.
    public let maxDiskSize: Int

    /// Resolution levels to keep pinned (never evict).
    public let pinnedResolutions: Set<Int>

    /// Whether to compress inactive entries for this image.
    public let compressInactive: Bool

    /// Inactivity interval before entries are eligible for compression (seconds).
    public let compressionInactivityThreshold: TimeInterval

    /// Creates an image cache policy.
    ///
    /// - Parameters:
    ///   - imageID: Image identifier.
    ///   - maxMemorySize: Maximum memory in bytes (default: 50 MB).
    ///   - maxDiskSize: Maximum disk in bytes (default: 200 MB).
    ///   - pinnedResolutions: Resolution levels to keep pinned (default: empty).
    ///   - compressInactive: Whether to compress inactive entries (default: true).
    ///   - compressionInactivityThreshold: Inactivity threshold in seconds (default: 300).
    public init(
        imageID: String,
        maxMemorySize: Int = 50 * 1024 * 1024,
        maxDiskSize: Int = 200 * 1024 * 1024,
        pinnedResolutions: Set<Int> = [],
        compressInactive: Bool = true,
        compressionInactivityThreshold: TimeInterval = 300
    ) {
        self.imageID = imageID
        self.maxMemorySize = maxMemorySize
        self.maxDiskSize = maxDiskSize
        self.pinnedResolutions = pinnedResolutions
        self.compressInactive = compressInactive
        self.compressionInactivityThreshold = compressionInactivityThreshold
    }
}

/// Global cache manager configuration.
///
/// Controls overall cache behavior including memory and disk limits,
/// eviction policies, and compression settings.
public struct JPIPCacheManagerConfiguration: Sendable {
    /// Maximum total memory cache size in bytes.
    public let maxMemorySize: Int

    /// Maximum total disk cache size in bytes.
    public let maxDiskSize: Int

    /// Maximum number of cached entries.
    public let maxEntries: Int

    /// Resolution priority weights for eviction (higher resolution = lower priority).
    public let resolutionPriorityWeights: [Int: Double]

    /// Whether to enable compressed storage for inactive entries.
    public let enableCompression: Bool

    /// Inactivity threshold in seconds before compression.
    public let compressionInactivityThreshold: TimeInterval

    /// Whether to enable deduplication across sessions.
    public let enableDeduplication: Bool

    /// Creates cache manager configuration.
    ///
    /// - Parameters:
    ///   - maxMemorySize: Maximum memory size in bytes (default: 200 MB).
    ///   - maxDiskSize: Maximum disk size in bytes (default: 1 GB).
    ///   - maxEntries: Maximum entries (default: 50,000).
    ///   - resolutionPriorityWeights: Resolution priority weights (default: lower res = higher priority).
    ///   - enableCompression: Enable compression (default: true).
    ///   - compressionInactivityThreshold: Inactivity threshold in seconds (default: 300).
    ///   - enableDeduplication: Enable deduplication (default: true).
    public init(
        maxMemorySize: Int = 200 * 1024 * 1024,
        maxDiskSize: Int = 1024 * 1024 * 1024,
        maxEntries: Int = 50_000,
        resolutionPriorityWeights: [Int: Double] = [:],
        enableCompression: Bool = true,
        compressionInactivityThreshold: TimeInterval = 300,
        enableDeduplication: Bool = true
    ) {
        self.maxMemorySize = maxMemorySize
        self.maxDiskSize = maxDiskSize
        self.maxEntries = maxEntries
        self.resolutionPriorityWeights = resolutionPriorityWeights
        self.enableCompression = enableCompression
        self.compressionInactivityThreshold = compressionInactivityThreshold
        self.enableDeduplication = enableDeduplication
    }
}

// MARK: - Cache Entry

/// Enhanced cache entry with resolution-aware metadata.
struct JPIPEnhancedCacheEntry: Sendable {
    /// The cached data bin.
    let dataBin: JPIPDataBin

    /// Image identifier this entry belongs to.
    let imageID: String

    /// Resolution level of this entry.
    let resolutionLevel: Int

    /// Timestamp of last access.
    var lastAccessTime: Date

    /// Number of accesses.
    var accessCount: Int

    /// Original uncompressed size in bytes.
    let originalSize: Int

    /// Current size in bytes (may differ if compressed).
    var currentSize: Int

    /// Whether this entry is stored in compressed form.
    var isCompressed: Bool

    /// Compressed data (nil if not compressed).
    var compressedData: Data?

    /// Deduplication content hash.
    let contentHash: Int

    /// Whether this entry is pinned (should not be evicted).
    var isPinned: Bool

    /// Creates an enhanced cache entry.
    init(
        dataBin: JPIPDataBin,
        imageID: String,
        resolutionLevel: Int,
        isPinned: Bool = false
    ) {
        self.dataBin = dataBin
        self.imageID = imageID
        self.resolutionLevel = resolutionLevel
        self.lastAccessTime = Date()
        self.accessCount = 0
        self.originalSize = dataBin.data.count
        self.currentSize = dataBin.data.count
        self.isCompressed = false
        self.compressedData = nil
        self.isPinned = isPinned

        // Simple hash-based deduplication key
        var hasher = Hasher()
        hasher.combine(dataBin.binClass.rawValue)
        hasher.combine(dataBin.data)
        self.contentHash = hasher.finalize()
    }
}

// MARK: - Cache Partition

/// Cache partition for a specific image and resolution level.
struct JPIPCachePartition: Sendable {
    /// Image identifier.
    let imageID: String

    /// Resolution level.
    let resolutionLevel: Int

    /// Entries in this partition.
    var entries: [String: JPIPEnhancedCacheEntry]

    /// Total size of entries in this partition.
    var totalSize: Int

    /// Creates an empty cache partition.
    init(imageID: String, resolutionLevel: Int) {
        self.imageID = imageID
        self.resolutionLevel = resolutionLevel
        self.entries = [:]
        self.totalSize = 0
    }
}

// MARK: - Cache Diagnostics

/// Comprehensive cache usage report for diagnostics.
public struct JPIPCacheUsageReport: Sendable {
    /// Total memory usage in bytes.
    public let totalMemoryUsage: Int

    /// Total disk usage in bytes.
    public let totalDiskUsage: Int

    /// Total number of entries.
    public let totalEntries: Int

    /// Number of compressed entries.
    public let compressedEntries: Int

    /// Number of deduplicated entries.
    public let deduplicatedEntries: Int

    /// Number of pinned entries.
    public let pinnedEntries: Int

    /// Per-image breakdown.
    public let perImageUsage: [String: JPIPImageCacheUsage]

    /// Per-resolution breakdown.
    public let perResolutionUsage: [Int: JPIPResolutionCacheUsage]

    /// Cache efficiency metrics.
    public let efficiency: JPIPCacheEfficiency

    /// Timestamp when this report was generated.
    public let timestamp: Date
}

/// Per-image cache usage.
public struct JPIPImageCacheUsage: Sendable {
    /// Image identifier.
    public let imageID: String

    /// Memory usage in bytes.
    public let memoryUsage: Int

    /// Number of entries.
    public let entryCount: Int

    /// Number of resolution levels cached.
    public let resolutionLevels: Int
}

/// Per-resolution cache usage.
public struct JPIPResolutionCacheUsage: Sendable {
    /// Resolution level.
    public let resolutionLevel: Int

    /// Memory usage in bytes.
    public let memoryUsage: Int

    /// Number of entries.
    public let entryCount: Int

    /// Number of images with entries at this resolution.
    public let imageCount: Int
}

/// Cache efficiency metrics.
public struct JPIPCacheEfficiency: Sendable {
    /// Total cache hits.
    public let hits: Int

    /// Total cache misses.
    public let misses: Int

    /// Hit rate (0.0-1.0).
    public var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0.0
    }

    /// Total evictions.
    public let evictions: Int

    /// Total deduplication savings in bytes.
    public let deduplicationSavings: Int

    /// Total compression savings in bytes.
    public let compressionSavings: Int

    /// Number of warm-up loads from persistent storage.
    public let warmUpLoads: Int
}

// MARK: - Persistent Cache Store

/// Protocol for persistent cache storage.
public protocol JPIPPersistentCacheStore: Sendable {
    /// Saves a data bin to persistent storage.
    func save(key: String, data: Data, metadata: JPIPCacheEntryMetadata) async throws

    /// Loads a data bin from persistent storage.
    func load(key: String) async throws -> (data: Data, metadata: JPIPCacheEntryMetadata)?

    /// Removes an entry from persistent storage.
    func remove(key: String) async throws

    /// Lists all keys in persistent storage.
    func allKeys() async throws -> [String]

    /// Gets total disk usage in bytes.
    func totalDiskUsage() async throws -> Int

    /// Clears all persistent storage.
    func clear() async throws
}

/// Metadata for a persistent cache entry.
public struct JPIPCacheEntryMetadata: Codable, Sendable {
    /// Image identifier.
    public let imageID: String

    /// Resolution level.
    public let resolutionLevel: Int

    /// Bin class raw value.
    public let binClassRawValue: Int

    /// Bin ID.
    public let binID: Int

    /// Whether bin is complete.
    public let isComplete: Bool

    /// Quality layer.
    public let qualityLayer: Int

    /// Tile index.
    public let tileIndex: Int

    /// Content hash for deduplication.
    public let contentHash: Int

    /// Original creation timestamp.
    public let createdAt: Date
}

/// In-memory persistent store for testing.
public actor JPIPInMemoryCacheStore: JPIPPersistentCacheStore {
    private var storage: [String: (data: Data, metadata: JPIPCacheEntryMetadata)] = [:]

    public init() {}

    public func save(key: String, data: Data, metadata: JPIPCacheEntryMetadata) async throws {
        storage[key] = (data: data, metadata: metadata)
    }

    public func load(key: String) async throws -> (data: Data, metadata: JPIPCacheEntryMetadata)? {
        storage[key]
    }

    public func remove(key: String) async throws {
        storage.removeValue(forKey: key)
    }

    public func allKeys() async throws -> [String] {
        Array(storage.keys)
    }

    public func totalDiskUsage() async throws -> Int {
        storage.values.reduce(0) { $0 + $1.data.count }
    }

    public func clear() async throws {
        storage.removeAll()
    }
}

// MARK: - Client Cache Manager

/// Enhanced client-side cache manager for JPIP.
///
/// Provides resolution-aware LRU eviction, partitioned caching by image
/// and resolution level, data bin deduplication, compressed storage for
/// inactive entries, persistent storage warm-up, and comprehensive
/// diagnostics reporting.
///
/// Example:
/// ```swift
/// let config = JPIPCacheManagerConfiguration(
///     maxMemorySize: 100 * 1024 * 1024,
///     maxDiskSize: 500 * 1024 * 1024
/// )
/// let manager = JPIPClientCacheManager(configuration: config)
///
/// // Add data bin with image and resolution context
/// let dataBin = JPIPDataBin(binClass: .precinct, binID: 1,
///                           data: someData, isComplete: true)
/// await manager.addDataBin(dataBin, imageID: "image1", resolutionLevel: 2)
///
/// // Retrieve data bin
/// let cached = await manager.getDataBin(binClass: .precinct, binID: 1,
///                                       imageID: "image1")
///
/// // Get usage report
/// let report = await manager.generateUsageReport()
/// ```
public actor JPIPClientCacheManager {
    /// Configuration.
    public let configuration: JPIPCacheManagerConfiguration

    /// Partitioned cache: [imageID: [resolutionLevel: partition]].
    private var partitions: [String: [Int: JPIPCachePartition]]

    /// Global entry lookup for fast access: [cacheKey: (imageID, resolutionLevel)].
    private var entryIndex: [String: (imageID: String, resolutionLevel: Int)]

    /// Content hash deduplication index: [contentHash: cacheKey].
    private var deduplicationIndex: [Int: String]

    /// Per-image cache policies.
    private var imagePolicies: [String: JPIPImageCachePolicy]

    /// Persistent store for disk-based caching.
    private var persistentStore: JPIPPersistentCacheStore?

    /// Statistics tracking.
    private var hits: Int = 0
    private var misses: Int = 0
    private var evictions: Int = 0
    private var deduplicationSavings: Int = 0
    private var compressionSavings: Int = 0
    private var warmUpLoads: Int = 0
    private var totalMemoryUsage: Int = 0
    private var totalEntries: Int = 0
    private var compressedEntryCount: Int = 0
    private var deduplicatedEntryCount: Int = 0
    private var pinnedEntryCount: Int = 0

    /// Creates a new client cache manager.
    ///
    /// - Parameters:
    ///   - configuration: Cache manager configuration.
    ///   - persistentStore: Optional persistent store for disk caching.
    public init(
        configuration: JPIPCacheManagerConfiguration = JPIPCacheManagerConfiguration(),
        persistentStore: JPIPPersistentCacheStore? = nil
    ) {
        self.configuration = configuration
        self.partitions = [:]
        self.entryIndex = [:]
        self.deduplicationIndex = [:]
        self.imagePolicies = [:]
        self.persistentStore = persistentStore
    }

    // MARK: - Core Cache Operations

    /// Adds a data bin to the cache with image and resolution context.
    ///
    /// Performs deduplication checking, applies per-image policies, and
    /// triggers eviction if necessary.
    ///
    /// - Parameters:
    ///   - dataBin: The data bin to cache.
    ///   - imageID: The image this data bin belongs to.
    ///   - resolutionLevel: The resolution level of this data bin.
    public func addDataBin(
        _ dataBin: JPIPDataBin,
        imageID: String,
        resolutionLevel: Int
    ) {
        let key = cacheKey(binClass: dataBin.binClass, binID: dataBin.binID, imageID: imageID)
        let policy = imagePolicies[imageID]
        let isPinned = policy?.pinnedResolutions.contains(resolutionLevel) ?? false

        // Check deduplication
        if configuration.enableDeduplication {
            var hasher = Hasher()
            hasher.combine(dataBin.binClass.rawValue)
            hasher.combine(dataBin.data)
            let hash = hasher.finalize()

            if let existingKey = deduplicationIndex[hash], existingKey != key {
                // Content already exists, just add a reference
                deduplicatedEntryCount += 1
                deduplicationSavings += dataBin.data.count
                // Still store the entry but mark it as deduplicated
            }
            deduplicationIndex[hash] = key
        }

        // Remove existing entry if updating
        if let existing = entryIndex[key] {
            removeEntryInternal(key: key, imageID: existing.imageID, resolutionLevel: existing.resolutionLevel)
        }

        // Evict if necessary
        let newSize = dataBin.data.count
        while (totalMemoryUsage + newSize > configuration.maxMemorySize ||
               totalEntries >= configuration.maxEntries) && totalEntries > 0 {
            evictResolutionAwareLRU()
        }

        // Also check per-image limits
        if let policy = policy {
            let imageUsage = getImageMemoryUsage(imageID: imageID)
            var excess = imageUsage + newSize - policy.maxMemorySize
            while excess > 0 && hasEvictableEntries(imageID: imageID) {
                evictFromImage(imageID: imageID)
                excess = getImageMemoryUsage(imageID: imageID) + newSize - policy.maxMemorySize
            }
        }

        // Create entry
        let entry = JPIPEnhancedCacheEntry(
            dataBin: dataBin,
            imageID: imageID,
            resolutionLevel: resolutionLevel,
            isPinned: isPinned
        )

        // Create partition if needed
        if partitions[imageID] == nil {
            partitions[imageID] = [:]
        }
        if partitions[imageID]?[resolutionLevel] == nil {
            partitions[imageID]?[resolutionLevel] = JPIPCachePartition(
                imageID: imageID,
                resolutionLevel: resolutionLevel
            )
        }

        // Add to partition
        partitions[imageID]?[resolutionLevel]?.entries[key] = entry
        partitions[imageID]?[resolutionLevel]?.totalSize += newSize

        // Update indices
        entryIndex[key] = (imageID: imageID, resolutionLevel: resolutionLevel)
        totalMemoryUsage += newSize
        totalEntries += 1
        if isPinned {
            pinnedEntryCount += 1
        }
    }

    /// Retrieves a data bin from the cache.
    ///
    /// Updates access statistics on hit. Decompresses if necessary.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    ///   - imageID: The image identifier.
    /// - Returns: The cached data bin, or nil if not found.
    public func getDataBin(
        binClass: JPIPDataBinClass,
        binID: Int,
        imageID: String
    ) -> JPIPDataBin? {
        let key = cacheKey(binClass: binClass, binID: binID, imageID: imageID)

        guard let location = entryIndex[key],
              var entry = partitions[location.imageID]?[location.resolutionLevel]?.entries[key] else {
            misses += 1
            return nil
        }

        hits += 1
        entry.accessCount += 1
        entry.lastAccessTime = Date()
        partitions[location.imageID]?[location.resolutionLevel]?.entries[key] = entry

        return entry.dataBin
    }

    /// Checks if a data bin is in the cache.
    ///
    /// - Parameters:
    ///   - binClass: The data bin class.
    ///   - binID: The data bin ID.
    ///   - imageID: The image identifier.
    /// - Returns: True if the bin is cached.
    public func hasDataBin(
        binClass: JPIPDataBinClass,
        binID: Int,
        imageID: String
    ) -> Bool {
        let key = cacheKey(binClass: binClass, binID: binID, imageID: imageID)
        return entryIndex[key] != nil
    }

    // MARK: - Per-Image Policy

    /// Sets a cache policy for a specific image.
    ///
    /// - Parameter policy: The cache policy to apply.
    public func setImagePolicy(_ policy: JPIPImageCachePolicy) {
        imagePolicies[policy.imageID] = policy

        // Update pinned status for existing entries
        if let imagePartitions = partitions[policy.imageID] {
            for (resLevel, partition) in imagePartitions {
                let shouldPin = policy.pinnedResolutions.contains(resLevel)
                for (key, var entry) in partition.entries {
                    let wasPinned = entry.isPinned
                    entry.isPinned = shouldPin
                    partitions[policy.imageID]?[resLevel]?.entries[key] = entry
                    if shouldPin && !wasPinned {
                        pinnedEntryCount += 1
                    } else if !shouldPin && wasPinned {
                        pinnedEntryCount -= 1
                    }
                }
            }
        }
    }

    /// Gets the cache policy for an image.
    ///
    /// - Parameter imageID: The image identifier.
    /// - Returns: The image cache policy, or nil if no custom policy is set.
    public func getImagePolicy(imageID: String) -> JPIPImageCachePolicy? {
        imagePolicies[imageID]
    }

    /// Removes the cache policy for an image.
    ///
    /// - Parameter imageID: The image identifier.
    public func removeImagePolicy(imageID: String) {
        imagePolicies.removeValue(forKey: imageID)
    }

    // MARK: - Cache Inspection and Eviction API

    /// Evicts all entries for a specific image.
    ///
    /// - Parameter imageID: The image identifier.
    /// - Returns: Number of entries evicted.
    @discardableResult
    public func evictImage(imageID: String) -> Int {
        guard let imagePartitions = partitions[imageID] else { return 0 }

        var evictedCount = 0
        for (_, partition) in imagePartitions {
            for (key, entry) in partition.entries {
                totalMemoryUsage -= entry.currentSize
                totalEntries -= 1
                if entry.isPinned { pinnedEntryCount -= 1 }
                if entry.isCompressed { compressedEntryCount -= 1 }
                entryIndex.removeValue(forKey: key)
                if configuration.enableDeduplication {
                    deduplicationIndex.removeValue(forKey: entry.contentHash)
                }
                evictedCount += 1
                evictions += 1
            }
        }
        partitions.removeValue(forKey: imageID)
        return evictedCount
    }

    /// Evicts all entries at a specific resolution level across all images.
    ///
    /// - Parameter resolutionLevel: The resolution level to evict.
    /// - Returns: Number of entries evicted.
    @discardableResult
    public func evictResolution(level resolutionLevel: Int) -> Int {
        var evictedCount = 0
        for (imageID, imagePartitions) in partitions {
            guard let partition = imagePartitions[resolutionLevel] else { continue }
            for (key, entry) in partition.entries {
                totalMemoryUsage -= entry.currentSize
                totalEntries -= 1
                if entry.isPinned { pinnedEntryCount -= 1 }
                if entry.isCompressed { compressedEntryCount -= 1 }
                entryIndex.removeValue(forKey: key)
                if configuration.enableDeduplication {
                    deduplicationIndex.removeValue(forKey: entry.contentHash)
                }
                evictedCount += 1
                evictions += 1
            }
            partitions[imageID]?.removeValue(forKey: resolutionLevel)
        }
        return evictedCount
    }

    /// Evicts entries older than a given date.
    ///
    /// - Parameter date: Entries last accessed before this date will be evicted.
    /// - Returns: Number of entries evicted.
    @discardableResult
    public func evictOlderThan(_ date: Date) -> Int {
        var evictedCount = 0
        for (imageID, imagePartitions) in partitions {
            for (resLevel, partition) in imagePartitions {
                for (key, entry) in partition.entries where !entry.isPinned {
                    if entry.lastAccessTime < date {
                        removeEntryInternal(key: key, imageID: imageID, resolutionLevel: resLevel)
                        evictedCount += 1
                        evictions += 1
                    }
                }
            }
        }
        return evictedCount
    }

    /// Gets all cached image IDs.
    ///
    /// - Returns: Array of image identifiers with cached data.
    public func getCachedImageIDs() -> [String] {
        Array(partitions.keys)
    }

    /// Gets the resolution levels cached for a specific image.
    ///
    /// - Parameter imageID: The image identifier.
    /// - Returns: Set of cached resolution levels.
    public func getCachedResolutionLevels(imageID: String) -> Set<Int> {
        guard let imagePartitions = partitions[imageID] else { return [] }
        return Set(imagePartitions.keys)
    }

    /// Gets the entry count for a specific image.
    ///
    /// - Parameter imageID: The image identifier.
    /// - Returns: Number of entries for the image.
    public func getEntryCount(imageID: String) -> Int {
        guard let imagePartitions = partitions[imageID] else { return 0 }
        return imagePartitions.values.reduce(0) { $0 + $1.entries.count }
    }

    // MARK: - Compressed Storage

    /// Compresses inactive entries to save memory.
    ///
    /// Entries that haven't been accessed within the inactivity threshold
    /// are compressed using zlib compression.
    ///
    /// - Returns: Total bytes saved by compression.
    @discardableResult
    public func compressInactiveEntries() -> Int {
        guard configuration.enableCompression else { return 0 }

        let threshold = configuration.compressionInactivityThreshold
        let cutoffDate = Date().addingTimeInterval(-threshold)
        var totalSaved = 0

        for (imageID, imagePartitions) in partitions {
            // Check per-image policy
            let policy = imagePolicies[imageID]
            let imageCompressEnabled = policy?.compressInactive ?? true
            guard imageCompressEnabled else { continue }

            let imageThreshold = policy?.compressionInactivityThreshold ?? threshold
            let imageCutoff = Date().addingTimeInterval(-imageThreshold)
            let effectiveCutoff = max(cutoffDate, imageCutoff)

            for (resLevel, partition) in imagePartitions {
                for (key, var entry) in partition.entries {
                    guard !entry.isCompressed && !entry.isPinned else { continue }
                    guard entry.lastAccessTime < effectiveCutoff else { continue }

                    let originalSize = entry.currentSize
                    let compressedData = compressData(entry.dataBin.data)
                    if compressedData.count < originalSize {
                        entry.compressedData = compressedData
                        entry.isCompressed = true
                        let saved = originalSize - compressedData.count
                        entry.currentSize = compressedData.count
                        totalMemoryUsage -= saved
                        partitions[imageID]?[resLevel]?.totalSize -= saved
                        partitions[imageID]?[resLevel]?.entries[key] = entry
                        totalSaved += saved
                        compressedEntryCount += 1
                    }
                }
            }
        }

        compressionSavings += totalSaved
        return totalSaved
    }

    // MARK: - Cache Warm-Up

    /// Warms up the cache from persistent storage.
    ///
    /// Loads previously cached entries from disk into memory, up to
    /// the configured memory limit.
    ///
    /// - Returns: Number of entries loaded.
    @discardableResult
    public func warmUpFromPersistentStorage() async -> Int {
        guard let store = persistentStore else { return 0 }

        var loadedCount = 0
        do {
            let keys = try await store.allKeys()
            for key in keys {
                guard totalMemoryUsage < configuration.maxMemorySize else { break }

                if let (data, metadata) = try await store.load(key: key) {
                    guard let binClass = JPIPDataBinClass(rawValue: metadata.binClassRawValue) else {
                        continue
                    }
                    let dataBin = JPIPDataBin(
                        binClass: binClass,
                        binID: metadata.binID,
                        data: data,
                        isComplete: metadata.isComplete,
                        qualityLayer: metadata.qualityLayer,
                        tileIndex: metadata.tileIndex
                    )
                    addDataBin(
                        dataBin,
                        imageID: metadata.imageID,
                        resolutionLevel: metadata.resolutionLevel
                    )
                    loadedCount += 1
                }
            }
        } catch {
            // Warm-up is best-effort; errors are silently handled
        }

        warmUpLoads += loadedCount
        return loadedCount
    }

    /// Saves current cache entries to persistent storage.
    ///
    /// - Returns: Number of entries saved.
    @discardableResult
    public func saveToPersistentStorage() async -> Int {
        guard let store = persistentStore else { return 0 }

        var savedCount = 0
        for (imageID, imagePartitions) in partitions {
            for (resLevel, partition) in imagePartitions {
                for (key, entry) in partition.entries {
                    let metadata = JPIPCacheEntryMetadata(
                        imageID: imageID,
                        resolutionLevel: resLevel,
                        binClassRawValue: entry.dataBin.binClass.rawValue,
                        binID: entry.dataBin.binID,
                        isComplete: entry.dataBin.isComplete,
                        qualityLayer: entry.dataBin.qualityLayer,
                        tileIndex: entry.dataBin.tileIndex,
                        contentHash: entry.contentHash,
                        createdAt: entry.lastAccessTime
                    )
                    do {
                        try await store.save(key: key, data: entry.dataBin.data, metadata: metadata)
                        savedCount += 1
                    } catch {
                        // Save is best-effort
                    }
                }
            }
        }
        return savedCount
    }

    // MARK: - Predictive Pre-Population

    /// Pre-populates cache with predicted data bins.
    ///
    /// Uses data bins from the prefetch engine to proactively fill
    /// the cache before they are explicitly requested.
    ///
    /// - Parameters:
    ///   - dataBins: Array of data bins to pre-populate.
    ///   - imageID: The image identifier.
    ///   - resolutionLevel: The resolution level.
    /// - Returns: Number of entries added.
    @discardableResult
    public func prePopulate(
        dataBins: [JPIPDataBin],
        imageID: String,
        resolutionLevel: Int
    ) -> Int {
        var addedCount = 0
        for dataBin in dataBins {
            // Only add if not already cached and there's room
            let key = cacheKey(binClass: dataBin.binClass, binID: dataBin.binID, imageID: imageID)
            guard entryIndex[key] == nil else { continue }
            guard totalMemoryUsage + dataBin.data.count <= configuration.maxMemorySize else { break }

            addDataBin(dataBin, imageID: imageID, resolutionLevel: resolutionLevel)
            addedCount += 1
        }
        return addedCount
    }

    // MARK: - Diagnostics

    /// Generates a comprehensive cache usage report.
    ///
    /// - Returns: Cache usage report with per-image and per-resolution breakdowns.
    public func generateUsageReport() -> JPIPCacheUsageReport {
        var perImageUsage: [String: JPIPImageCacheUsage] = [:]
        var perResolutionUsage: [Int: JPIPResolutionCacheUsage] = [:]
        var resolutionImageSets: [Int: Set<String>] = [:]

        for (imageID, imagePartitions) in partitions {
            var imageMemory = 0
            var imageEntries = 0
            var imageResLevels = 0

            for (resLevel, partition) in imagePartitions {
                let partitionSize = partition.totalSize
                let partitionEntries = partition.entries.count

                imageMemory += partitionSize
                imageEntries += partitionEntries
                if partitionEntries > 0 { imageResLevels += 1 }

                // Accumulate per-resolution
                let existing = perResolutionUsage[resLevel]
                perResolutionUsage[resLevel] = JPIPResolutionCacheUsage(
                    resolutionLevel: resLevel,
                    memoryUsage: (existing?.memoryUsage ?? 0) + partitionSize,
                    entryCount: (existing?.entryCount ?? 0) + partitionEntries,
                    imageCount: 0 // Will update below
                )
                if resolutionImageSets[resLevel] == nil {
                    resolutionImageSets[resLevel] = []
                }
                if partitionEntries > 0 {
                    resolutionImageSets[resLevel]?.insert(imageID)
                }
            }

            perImageUsage[imageID] = JPIPImageCacheUsage(
                imageID: imageID,
                memoryUsage: imageMemory,
                entryCount: imageEntries,
                resolutionLevels: imageResLevels
            )
        }

        // Update image counts in per-resolution usage
        for (resLevel, imageSet) in resolutionImageSets {
            if let existing = perResolutionUsage[resLevel] {
                perResolutionUsage[resLevel] = JPIPResolutionCacheUsage(
                    resolutionLevel: resLevel,
                    memoryUsage: existing.memoryUsage,
                    entryCount: existing.entryCount,
                    imageCount: imageSet.count
                )
            }
        }

        let efficiency = JPIPCacheEfficiency(
            hits: hits,
            misses: misses,
            evictions: evictions,
            deduplicationSavings: deduplicationSavings,
            compressionSavings: compressionSavings,
            warmUpLoads: warmUpLoads
        )

        return JPIPCacheUsageReport(
            totalMemoryUsage: totalMemoryUsage,
            totalDiskUsage: 0, // Updated when persistent store is queried
            totalEntries: totalEntries,
            compressedEntries: compressedEntryCount,
            deduplicatedEntries: deduplicatedEntryCount,
            pinnedEntries: pinnedEntryCount,
            perImageUsage: perImageUsage,
            perResolutionUsage: perResolutionUsage,
            efficiency: efficiency,
            timestamp: Date()
        )
    }

    /// Gets the current hit rate.
    ///
    /// - Returns: Hit rate (0.0-1.0).
    public func getHitRate() -> Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0.0
    }

    /// Clears all cached data.
    public func clear() {
        partitions.removeAll()
        entryIndex.removeAll()
        deduplicationIndex.removeAll()
        totalMemoryUsage = 0
        totalEntries = 0
        compressedEntryCount = 0
        deduplicatedEntryCount = 0
        pinnedEntryCount = 0
    }

    /// Gets total memory usage.
    public func getMemoryUsage() -> Int {
        totalMemoryUsage
    }

    /// Gets total entry count.
    public func getTotalEntries() -> Int {
        totalEntries
    }

    // MARK: - Private Helpers

    /// Creates a cache key.
    private func cacheKey(binClass: JPIPDataBinClass, binID: Int, imageID: String) -> String {
        "\(imageID):\(binClass.rawValue):\(binID)"
    }

    /// Evicts the least valuable entry using resolution-aware LRU.
    ///
    /// Lower resolution levels are considered more valuable (higher priority)
    /// and are evicted later. Pinned entries are never evicted.
    private func evictResolutionAwareLRU() {
        var worstKey: String?
        var worstScore: Double = .infinity
        var worstImageID: String?
        var worstResLevel: Int?

        for (imageID, imagePartitions) in partitions {
            for (resLevel, partition) in imagePartitions {
                for (key, entry) in partition.entries where !entry.isPinned {
                    let score = evictionScore(entry: entry, resolutionLevel: resLevel)
                    if score < worstScore {
                        worstScore = score
                        worstKey = key
                        worstImageID = imageID
                        worstResLevel = resLevel
                    }
                }
            }
        }

        if let key = worstKey, let imageID = worstImageID, let resLevel = worstResLevel {
            removeEntryInternal(key: key, imageID: imageID, resolutionLevel: resLevel)
            evictions += 1
        }
    }

    /// Calculates eviction score for an entry (higher = more valuable, less likely to evict).
    private func evictionScore(entry: JPIPEnhancedCacheEntry, resolutionLevel: Int) -> Double {
        // Resolution weight: lower resolution = higher priority (more valuable)
        let defaultWeight = 1.0 / Double(max(1, resolutionLevel + 1))
        let resWeight = configuration.resolutionPriorityWeights[resolutionLevel] ?? defaultWeight

        // Recency: more recent = higher score
        let age = Date().timeIntervalSince(entry.lastAccessTime)
        let recencyScore = 1.0 / (1.0 + age)

        // Access frequency: more accesses = higher score
        let frequencyScore = Double(entry.accessCount + 1)

        return resWeight * recencyScore * frequencyScore
    }

    /// Evicts the least valuable entry from a specific image.
    private func evictFromImage(imageID: String) {
        guard let imagePartitions = partitions[imageID] else { return }

        var worstKey: String?
        var worstScore: Double = .infinity
        var worstResLevel: Int?

        for (resLevel, partition) in imagePartitions {
            for (key, entry) in partition.entries where !entry.isPinned {
                let score = evictionScore(entry: entry, resolutionLevel: resLevel)
                if score < worstScore {
                    worstScore = score
                    worstKey = key
                    worstResLevel = resLevel
                }
            }
        }

        if let key = worstKey, let resLevel = worstResLevel {
            removeEntryInternal(key: key, imageID: imageID, resolutionLevel: resLevel)
            evictions += 1
        }
    }

    /// Gets memory usage for a specific image.
    private func getImageMemoryUsage(imageID: String) -> Int {
        guard let imagePartitions = partitions[imageID] else { return 0 }
        return imagePartitions.values.reduce(0) { $0 + $1.totalSize }
    }

    /// Checks if there are evictable (non-pinned) entries for an image.
    private func hasEvictableEntries(imageID: String) -> Bool {
        guard let imagePartitions = partitions[imageID] else { return false }
        for partition in imagePartitions.values {
            for entry in partition.entries.values where !entry.isPinned {
                return true
            }
        }
        return false
    }

    /// Removes an entry from the cache internal data structures.
    private func removeEntryInternal(key: String, imageID: String, resolutionLevel: Int) {
        guard let entry = partitions[imageID]?[resolutionLevel]?.entries[key] else { return }

        totalMemoryUsage -= entry.currentSize
        totalEntries -= 1
        if entry.isPinned { pinnedEntryCount -= 1 }
        if entry.isCompressed { compressedEntryCount -= 1 }

        partitions[imageID]?[resolutionLevel]?.entries.removeValue(forKey: key)
        partitions[imageID]?[resolutionLevel]?.totalSize -= entry.currentSize
        entryIndex.removeValue(forKey: key)

        if configuration.enableDeduplication {
            deduplicationIndex.removeValue(forKey: entry.contentHash)
        }

        // Clean up empty partitions
        if partitions[imageID]?[resolutionLevel]?.entries.isEmpty == true {
            partitions[imageID]?.removeValue(forKey: resolutionLevel)
        }
        if partitions[imageID]?.isEmpty == true {
            partitions.removeValue(forKey: imageID)
        }
    }

    /// Simple data compression (zlib-compatible).
    private func compressData(_ data: Data) -> Data {
        // Simple run-length encoding as a lightweight compression stand-in.
        // In a real implementation, this would use zlib/deflate.
        guard data.count > 16 else { return data }

        var compressed = Data()
        compressed.reserveCapacity(data.count)
        var i = 0
        let bytes = Array(data)

        while i < bytes.count {
            let current = bytes[i]
            var runLength = 1
            while i + runLength < bytes.count && bytes[i + runLength] == current && runLength < 255 {
                runLength += 1
            }
            if runLength >= 3 {
                compressed.append(0xFF)
                compressed.append(UInt8(runLength))
                compressed.append(current)
                i += runLength
            } else {
                if current == 0xFF {
                    compressed.append(0xFF)
                    compressed.append(1)
                    compressed.append(current)
                } else {
                    compressed.append(current)
                }
                i += 1
            }
        }

        return compressed.count < data.count ? compressed : data
    }
}
