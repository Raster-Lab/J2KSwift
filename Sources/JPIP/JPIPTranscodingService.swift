/// # JPIPTranscodingService
///
/// On-the-fly transcoding service for JPIP protocol.
///
/// Provides automatic format conversion between legacy JPEG 2000 and HTJ2K
/// during JPIP serving, enabling clients to receive data in their preferred
/// coding format regardless of the source image format.

import Foundation
import J2KCore
import J2KCodec

/// Provides on-the-fly transcoding for JPIP streaming.
///
/// When a JPIP client requests data in a coding format different from the
/// source image's native format, this service transparently transcodes the
/// data using the `J2KTranscoder`. Results are cached to avoid redundant
/// transcoding of the same data.
///
/// Example:
/// ```swift
/// let service = JPIPTranscodingService()
/// let result = try service.transcode(
///     data: codestreamData,
///     from: .legacy,
///     to: .htj2k
/// )
/// ```
public struct JPIPTranscodingService: Sendable {

    /// The underlying transcoder.
    private let transcoder: J2KTranscoder

    /// Creates a new transcoding service.
    ///
    /// - Parameter configuration: Transcoding configuration (default: `.default`).
    public init(configuration: TranscodingConfiguration = .default) {
        self.transcoder = J2KTranscoder(configuration: configuration)
    }

    /// Transcodes codestream data to the requested coding format.
    ///
    /// If the source data is already in the requested format, returns it unchanged.
    /// Otherwise, performs lossless transcoding between legacy JPEG 2000 and HTJ2K.
    ///
    /// - Parameters:
    ///   - data: The source codestream data.
    ///   - preference: The client's coding preference.
    ///   - sourceIsHTJ2K: Whether the source data uses HTJ2K encoding.
    /// - Returns: The transcoding result containing the (possibly transcoded) data.
    /// - Throws: ``J2KError`` if transcoding fails.
    public func transcode(
        data: Data,
        preference: JPIPCodingPreference,
        sourceIsHTJ2K: Bool
    ) throws -> JPIPTranscodingResult {
        // Determine if transcoding is needed
        let direction = determineDirection(preference: preference, sourceIsHTJ2K: sourceIsHTJ2K)

        guard let direction = direction else {
            // No transcoding needed - format matches preference or no preference
            return JPIPTranscodingResult(
                data: data,
                wasTranscoded: false,
                direction: nil,
                transcodingTime: 0
            )
        }

        // Perform transcoding
        let result = try transcoder.transcode(data, direction: direction)

        return JPIPTranscodingResult(
            data: result.data,
            wasTranscoded: true,
            direction: direction,
            transcodingTime: result.transcodingTime
        )
    }

    /// Determines the transcoding direction based on client preference and source format.
    ///
    /// - Parameters:
    ///   - preference: The client's coding preference.
    ///   - sourceIsHTJ2K: Whether the source uses HTJ2K.
    /// - Returns: The required direction, or `nil` if no transcoding is needed.
    public func determineDirection(
        preference: JPIPCodingPreference,
        sourceIsHTJ2K: Bool
    ) -> TranscodingDirection? {
        switch preference {
        case .none:
            return nil
        case .htj2k:
            return sourceIsHTJ2K ? nil : .legacyToHT
        case .legacy:
            return sourceIsHTJ2K ? .htToLegacy : nil
        }
    }

    /// Checks whether transcoding is needed for a given preference and source format.
    ///
    /// - Parameters:
    ///   - preference: The client's coding preference.
    ///   - sourceIsHTJ2K: Whether the source uses HTJ2K.
    /// - Returns: `true` if transcoding would be required.
    public func needsTranscoding(
        preference: JPIPCodingPreference,
        sourceIsHTJ2K: Bool
    ) -> Bool {
        return determineDirection(preference: preference, sourceIsHTJ2K: sourceIsHTJ2K) != nil
    }
}

/// Result of a JPIP transcoding operation.
///
/// Contains the output data along with metadata about whether transcoding
/// was performed and how long it took.
public struct JPIPTranscodingResult: Sendable {
    /// The output data (original or transcoded).
    public let data: Data

    /// Whether transcoding was actually performed.
    public let wasTranscoded: Bool

    /// The transcoding direction, if transcoding occurred.
    public let direction: TranscodingDirection?

    /// Time taken for transcoding in seconds (0 if not transcoded).
    public let transcodingTime: TimeInterval

    /// Creates a new transcoding result.
    ///
    /// - Parameters:
    ///   - data: The output data.
    ///   - wasTranscoded: Whether transcoding was performed.
    ///   - direction: The transcoding direction.
    ///   - transcodingTime: Time taken for transcoding.
    public init(
        data: Data,
        wasTranscoded: Bool,
        direction: TranscodingDirection?,
        transcodingTime: TimeInterval
    ) {
        self.data = data
        self.wasTranscoded = wasTranscoded
        self.direction = direction
        self.transcodingTime = transcodingTime
    }
}

/// Cache for transcoded JPIP data to avoid redundant conversions.
///
/// Stores previously transcoded results keyed by a hash of the source data
/// and the target format, enabling efficient re-serving of transcoded data.
public actor JPIPTranscodingCache {
    /// Cached entry containing transcoded data.
    private struct CacheEntry {
        let data: Data
        let direction: TranscodingDirection
        let timestamp: Date
    }

    /// Cached transcoded data keyed by source hash + direction.
    private var cache: [String: CacheEntry]

    /// Maximum cache size in bytes.
    private let maxCacheSize: Int

    /// Current cache size in bytes.
    private var currentSize: Int

    /// Cache statistics.
    public private(set) var hits: Int
    public private(set) var misses: Int

    /// Creates a new transcoding cache.
    ///
    /// - Parameter maxCacheSize: Maximum cache size in bytes (default: 256 MB).
    public init(maxCacheSize: Int = 256 * 1024 * 1024) {
        self.cache = [:]
        self.maxCacheSize = maxCacheSize
        self.currentSize = 0
        self.hits = 0
        self.misses = 0
    }

    /// Retrieves cached transcoded data.
    ///
    /// - Parameters:
    ///   - sourceHash: Hash of the source data.
    ///   - direction: The transcoding direction.
    /// - Returns: The cached data if available.
    public func get(sourceHash: String, direction: TranscodingDirection) -> Data? {
        let key = "\(sourceHash):\(direction.rawValue)"
        if let entry = cache[key] {
            hits += 1
            return entry.data
        }
        misses += 1
        return nil
    }

    /// Stores transcoded data in the cache.
    ///
    /// - Parameters:
    ///   - data: The transcoded data.
    ///   - sourceHash: Hash of the source data.
    ///   - direction: The transcoding direction.
    public func put(data: Data, sourceHash: String, direction: TranscodingDirection) {
        let key = "\(sourceHash):\(direction.rawValue)"

        // Evict if over size limit
        while currentSize + data.count > maxCacheSize && !cache.isEmpty {
            evictOldest()
        }

        // Remove existing entry if present
        if let existing = cache[key] {
            currentSize -= existing.data.count
        }

        cache[key] = CacheEntry(
            data: data,
            direction: direction,
            timestamp: Date()
        )
        currentSize += data.count
    }

    /// Clears all cached entries.
    public func clear() {
        cache.removeAll()
        currentSize = 0
    }

    /// Gets the number of cached entries.
    public var count: Int {
        return cache.count
    }

    /// Gets the current cache size in bytes.
    public var size: Int {
        return currentSize
    }

    /// Evicts the oldest cache entry.
    private func evictOldest() {
        guard let oldest = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        currentSize -= oldest.value.data.count
        cache.removeValue(forKey: oldest.key)
    }
}
