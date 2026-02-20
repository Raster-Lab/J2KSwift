/// # MJ2Player
///
/// Real-time playback engine for Motion JPEG 2000 files.
///
/// This module provides frame-accurate playback and seeking within Motion JPEG 2000 files,
/// with support for forward/reverse playback, speed control, and intelligent frame caching.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Playback Error

/// Errors that can occur during MJ2 playback.
public enum MJ2PlaybackError: Error, Sendable {
    /// The file is not a valid MJ2 file.
    case invalidFile

    /// No video tracks found in the file.
    case noVideoTracks

    /// The player is not initialized.
    case notInitialized

    /// Seek operation failed.
    case seekFailed

    /// Frame decoding failed.
    case decodeFailed(frameIndex: Int, error: Error)

    /// Playback was stopped.
    case stopped
}

// MARK: - Playback Mode

/// Playback modes supported by MJ2Player.
public enum MJ2PlaybackMode: Sendable {
    /// Normal forward playback.
    case forward

    /// Reverse playback.
    case reverse

    /// Single frame step forward.
    case stepForward

    /// Single frame step backward.
    case stepBackward
}

// MARK: - Loop Mode

/// Loop modes for playback.
public enum MJ2LoopMode: Sendable {
    /// No looping (stop at end).
    case none

    /// Loop from beginning.
    case loop

    /// Ping-pong (reverse direction at ends).
    case pingPong
}

// MARK: - Playback State

/// Current state of the player.
public enum MJ2PlaybackState: Sendable {
    /// Player is stopped.
    case stopped

    /// Player is playing.
    case playing

    /// Player is paused.
    case paused

    /// Player is seeking.
    case seeking
}

// MARK: - Playback Statistics

/// Statistics about playback performance.
public struct MJ2PlaybackStatistics: Sendable {
    /// Total frames decoded.
    public var framesDecoded: Int

    /// Total frames dropped.
    public var framesDropped: Int

    /// Average decode time in milliseconds.
    public var averageDecodeTime: Double

    /// Cache hit rate (0.0 to 1.0).
    public var cacheHitRate: Double

    /// Current memory usage in bytes.
    public var memoryUsage: UInt64

    /// Creates default statistics.
    public init() {
        self.framesDecoded = 0
        self.framesDropped = 0
        self.averageDecodeTime = 0.0
        self.cacheHitRate = 0.0
        self.memoryUsage = 0
    }
}

// MARK: - Frame Cache Entry

/// A cached decoded frame.
private struct CachedFrame: Sendable {
    let frameIndex: Int
    let image: J2KImage
    let timestamp: UInt64
    let accessTime: Date
    let memorySize: UInt64
}

// MARK: - Playback Configuration

/// Configuration for MJ2 playback.
public struct MJ2PlaybackConfiguration: Sendable {
    /// Maximum number of frames to cache.
    public var maxCacheSize: Int

    /// Number of frames to prefetch ahead.
    public var prefetchCount: Int

    /// Memory limit for cache in bytes (0 = no limit).
    public var memoryLimit: UInt64

    /// Whether to enable predictive prefetching.
    public var enablePredictivePrefetch: Bool

    /// Frame timing tolerance in milliseconds.
    public var timingTolerance: Double

    /// Creates default playback configuration.
    ///
    /// - Parameters:
    ///   - maxCacheSize: Maximum cached frames (default: 30).
    ///   - prefetchCount: Frames to prefetch (default: 5).
    ///   - memoryLimit: Memory limit in bytes (default: 256MB).
    ///   - enablePredictivePrefetch: Enable predictive prefetch (default: true).
    ///   - timingTolerance: Timing tolerance in ms (default: 16.67ms ≈ 60fps).
    public init(
        maxCacheSize: Int = 30,
        prefetchCount: Int = 5,
        memoryLimit: UInt64 = 256 * 1024 * 1024,
        enablePredictivePrefetch: Bool = true,
        timingTolerance: Double = 16.67
    ) {
        self.maxCacheSize = maxCacheSize
        self.prefetchCount = prefetchCount
        self.memoryLimit = memoryLimit
        self.enablePredictivePrefetch = enablePredictivePrefetch
        self.timingTolerance = timingTolerance
    }
}

// MARK: - MJ2 Player

/// Real-time playback engine for Motion JPEG 2000 files.
///
/// `MJ2Player` provides frame-accurate playback with intelligent caching and seeking:
/// - Forward and reverse playback with variable speed
/// - Frame-accurate seeking with predictive prefetching
/// - LRU cache with memory pressure handling
/// - Playback statistics and dropped frame tracking
///
/// ## Basic Usage
///
/// ```swift
/// let player = MJ2Player()
/// try await player.load(from: fileURL)
///
/// // Start playback
/// try await player.play()
///
/// // Seek to specific frame
/// try await player.seek(to: 100)
///
/// // Get current frame
/// if let frame = try await player.currentFrame() {
///     // Display frame
/// }
/// ```
///
/// ## Playback Control
///
/// ```swift
/// // Variable speed playback
/// try await player.setPlaybackSpeed(2.0) // 2x speed
///
/// // Reverse playback
/// try await player.setPlaybackMode(.reverse)
///
/// // Loop modes
/// player.loopMode = .loop
/// ```
///
/// ## Frame Caching
///
/// ```swift
/// let config = MJ2PlaybackConfiguration(
///     maxCacheSize: 60,
///     prefetchCount: 10,
///     memoryLimit: 512 * 1024 * 1024
/// )
/// let player = MJ2Player(configuration: config)
/// ```
public actor MJ2Player {
    // MARK: - Properties

    /// Playback configuration.
    private let configuration: MJ2PlaybackConfiguration

    /// The JPEG 2000 decoder.
    private let decoder: J2KDecoder

    /// File data.
    private var fileData: Data?

    /// File information.
    private var fileInfo: MJ2FileInfo?

    /// Sample table.
    private var sampleTable: MJ2SampleTable?

    /// Frame metadata.
    private var frameMetadata: [MJ2FrameMetadata] = []

    /// Current frame index.
    private var currentFrameIndex: Int = 0

    /// Current playback state.
    private var state: MJ2PlaybackState = .stopped

    /// Current playback mode.
    private var playbackMode: MJ2PlaybackMode = .forward

    /// Current playback speed (1.0 = normal).
    private var playbackSpeed: Double = 1.0

    /// Loop mode.
    public var loopMode: MJ2LoopMode = .none

    /// Frame cache (LRU).
    private var frameCache: [Int: CachedFrame] = [:]

    /// Cache access order for LRU.
    private var cacheAccessOrder: [Int] = []

    /// Playback statistics.
    private var statistics = MJ2PlaybackStatistics()

    /// Total decode time for averaging.
    private var totalDecodeTime: Double = 0

    /// Cache hits.
    private var cacheHits: Int = 0

    /// Cache misses.
    private var cacheMisses: Int = 0

    // MARK: - Initialization

    /// Creates a new MJ2 player.
    ///
    /// - Parameter configuration: Playback configuration.
    public init(configuration: MJ2PlaybackConfiguration = MJ2PlaybackConfiguration()) {
        self.configuration = configuration
        self.decoder = J2KDecoder()
    }

    // MARK: - Loading

    /// Loads an MJ2 file for playback.
    ///
    /// - Parameter fileURL: The URL of the MJ2 file.
    /// - Throws: ``MJ2PlaybackError`` if loading fails.
    public func load(from fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        try await load(from: data)
    }

    /// Loads MJ2 data for playback.
    ///
    /// - Parameter data: The MJ2 file data.
    /// - Throws: ``MJ2PlaybackError`` if loading fails.
    public func load(from data: Data) async throws {
        // Parse file structure
        let reader = MJ2FileReader()
        let info = try await reader.readFileInfo(from: data)

        // Find video track
        guard info.tracks.contains(where: { $0.isVideo }) else {
            throw MJ2PlaybackError.noVideoTracks
        }

        // Store file data and info
        self.fileData = data
        self.fileInfo = info

        // Parse sample table (this is a placeholder - real implementation would parse from data)
        self.sampleTable = try parseSampleTable(from: data, fileInfo: info)

        // Build frame metadata
        self.frameMetadata = try buildFrameMetadata()

        // Reset state
        self.currentFrameIndex = 0
        self.state = .stopped
        self.frameCache.removeAll()
        self.cacheAccessOrder.removeAll()
        self.statistics = MJ2PlaybackStatistics()
    }

    // MARK: - Playback Control

    /// Starts or resumes playback.
    ///
    /// - Throws: ``MJ2PlaybackError`` if playback cannot start.
    public func play() async throws {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        state = .playing

        // Start prefetching
        try await prefetchFrames()
    }

    /// Pauses playback.
    public func pause() {
        // Only pause if playing
        if state == .playing {
            state = .paused
        }
    }

    /// Stops playback and resets to beginning.
    public func stop() {
        state = .stopped
        currentFrameIndex = 0
    }

    /// Sets the playback mode.
    ///
    /// - Parameter mode: The playback mode.
    public func setPlaybackMode(_ mode: MJ2PlaybackMode) {
        self.playbackMode = mode
    }

    /// Sets the playback speed.
    ///
    /// - Parameter speed: Playback speed multiplier (1.0 = normal).
    public func setPlaybackSpeed(_ speed: Double) {
        self.playbackSpeed = max(0.1, min(speed, 10.0))
    }

    // MARK: - Seeking

    /// Seeks to a specific frame.
    ///
    /// - Parameter frameIndex: The target frame index (0-based).
    /// - Throws: ``MJ2PlaybackError`` if seeking fails.
    public func seek(to frameIndex: Int) async throws {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        guard frameIndex >= 0 && frameIndex < frameMetadata.count else {
            throw MJ2PlaybackError.seekFailed
        }

        let previousState = state
        state = .seeking

        currentFrameIndex = frameIndex

        // Prefetch around target
        try await prefetchFrames()

        state = previousState
    }

    /// Seeks to a specific timestamp.
    ///
    /// - Parameter timestamp: The target timestamp in time units.
    /// - Throws: ``MJ2PlaybackError`` if seeking fails.
    public func seek(toTimestamp timestamp: UInt64) async throws {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        // Find closest frame
        var closestIndex = 0
        var minDiff = UInt64.max

        for (index, metadata) in frameMetadata.enumerated() {
            let diff = timestamp > metadata.timestamp
                ? timestamp - metadata.timestamp
                : metadata.timestamp - timestamp
            if diff < minDiff {
                minDiff = diff
                closestIndex = index
            }
        }

        try await seek(to: closestIndex)
    }

    // MARK: - Frame Access

    /// Advances to the next frame based on playback mode.
    ///
    /// - Returns: `true` if a valid frame is available, `false` if at boundary.
    /// - Throws: ``MJ2PlaybackError`` if frame advance fails.
    public func nextFrame() async throws -> Bool {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        switch playbackMode {
        case .forward, .stepForward:
            if currentFrameIndex < frameMetadata.count - 1 {
                currentFrameIndex += 1
                try await prefetchFrames()
                return true
            } else {
                return try await handlePlaybackBoundary()
            }

        case .reverse, .stepBackward:
            if currentFrameIndex > 0 {
                currentFrameIndex -= 1
                try await prefetchFrames()
                return true
            } else {
                return try await handlePlaybackBoundary()
            }
        }
    }

    /// Gets the current frame image.
    ///
    /// - Returns: The current frame image, or nil if not available.
    /// - Throws: ``MJ2PlaybackError`` if frame retrieval fails.
    public func currentFrame() async throws -> J2KImage? {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        guard currentFrameIndex >= 0 && currentFrameIndex < frameMetadata.count else {
            return nil
        }

        return try await getFrame(at: currentFrameIndex)
    }

    /// Gets a frame at a specific index.
    ///
    /// - Parameter index: The frame index.
    /// - Returns: The frame image.
    /// - Throws: ``MJ2PlaybackError`` if frame retrieval fails.
    public func frame(at index: Int) async throws -> J2KImage? {
        guard fileData != nil else {
            throw MJ2PlaybackError.notInitialized
        }

        guard index >= 0 && index < frameMetadata.count else {
            return nil
        }

        return try await getFrame(at: index)
    }

    // MARK: - State Queries

    /// Returns the current playback state.
    public func currentState() -> MJ2PlaybackState {
        state
    }

    /// Returns the current frame index.
    public func currentIndex() -> Int {
        currentFrameIndex
    }

    /// Returns the total number of frames.
    public func totalFrames() -> Int {
        frameMetadata.count
    }

    /// Returns the current timestamp.
    public func currentTimestamp() -> UInt64 {
        guard currentFrameIndex >= 0 && currentFrameIndex < frameMetadata.count else {
            return 0
        }
        return frameMetadata[currentFrameIndex].timestamp
    }

    /// Returns the total duration in time units.
    public func totalDuration() -> UInt64 {
        guard !frameMetadata.isEmpty else {
            return 0
        }
        return frameMetadata.last!.timestamp + UInt64(frameMetadata.last!.duration)
    }

    /// Returns playback statistics.
    public func getStatistics() -> MJ2PlaybackStatistics {
        var stats = statistics

        // Update cache hit rate
        let totalAccesses = cacheHits + cacheMisses
        if totalAccesses > 0 {
            stats.cacheHitRate = Double(cacheHits) / Double(totalAccesses)
        }

        // Update average decode time
        if statistics.framesDecoded > 0 {
            stats.averageDecodeTime = totalDecodeTime / Double(statistics.framesDecoded)
        }

        // Update memory usage
        stats.memoryUsage = frameCache.values.reduce(0) { $0 + $1.memorySize }

        return stats
    }

    // MARK: - Cache Management

    /// Clears the frame cache.
    public func clearCache() {
        frameCache.removeAll()
        cacheAccessOrder.removeAll()
        cacheHits = 0
        cacheMisses = 0
    }

    /// Prefetches frames around the current position.
    private func prefetchFrames() async throws {
        guard configuration.prefetchCount > 0 else {
            return
        }

        let prefetchIndices = calculatePrefetchIndices()

        for index in prefetchIndices {
            // Check if already cached
            if frameCache[index] != nil {
                continue
            }

            // Decode and cache
            _ = try await getFrame(at: index)
        }
    }

    /// Calculates which frames to prefetch.
    private func calculatePrefetchIndices() -> [Int] {
        var indices: [Int] = []

        // Always include current frame
        indices.append(currentFrameIndex)

        // Add frames based on playback direction
        let direction = (playbackMode == .reverse || playbackMode == .stepBackward) ? -1 : 1

        for offset in 1...configuration.prefetchCount {
            let index = currentFrameIndex + (offset * direction)
            if index >= 0 && index < frameMetadata.count {
                indices.append(index)
            }
        }

        // Predictive prefetching (both directions for seeking)
        if configuration.enablePredictivePrefetch {
            let reverseDirection = -direction
            for offset in 1...(configuration.prefetchCount / 2) {
                let index = currentFrameIndex + (offset * reverseDirection)
                if index >= 0 && index < frameMetadata.count {
                    indices.append(index)
                }
            }
        }

        return indices
    }

    /// Gets a frame from cache or decodes it.
    private func getFrame(at index: Int) async throws -> J2KImage {
        // Check cache first
        if let cached = frameCache[index] {
            cacheHits += 1
            updateCacheAccess(index: index)
            return cached.image
        }

        cacheMisses += 1

        // Decode frame
        let startTime = Date()
        let image = try await decodeFrame(at: index)
        let decodeTime = Date().timeIntervalSince(startTime) * 1000 // ms

        // Update statistics
        statistics.framesDecoded += 1
        totalDecodeTime += decodeTime

        // Cache the frame
        cacheFrame(index: index, image: image)

        return image
    }

    /// Decodes a frame from the file.
    private func decodeFrame(at index: Int) async throws -> J2KImage {
        guard let fileData = fileData else {
            throw MJ2PlaybackError.notInitialized
        }

        guard index >= 0 && index < frameMetadata.count else {
            throw MJ2PlaybackError.decodeFailed(frameIndex: index, error: MJ2PlaybackError.notInitialized)
        }

        let metadata = frameMetadata[index]

        // Extract frame data
        let start = Int(metadata.offset)
        let length = Int(metadata.size)
        let frameData = fileData.subdata(in: start..<(start + length))

        // Decode
        do {
            return try decoder.decode(frameData)
        } catch {
            throw MJ2PlaybackError.decodeFailed(frameIndex: index, error: error)
        }
    }

    /// Caches a decoded frame.
    private func cacheFrame(index: Int, image: J2KImage) {
        // Estimate memory size
        let memorySize = estimateFrameMemorySize(image)

        // Check memory limit
        if configuration.memoryLimit > 0 {
            evictToMemoryLimit(requiredSpace: memorySize)
        }

        // Check cache size limit
        if frameCache.count >= configuration.maxCacheSize {
            evictLRU()
        }

        // Add to cache
        let cached = CachedFrame(
            frameIndex: index,
            image: image,
            timestamp: frameMetadata[index].timestamp,
            accessTime: Date(),
            memorySize: memorySize
        )

        frameCache[index] = cached
        updateCacheAccess(index: index)
    }

    /// Updates cache access order for LRU.
    private func updateCacheAccess(index: Int) {
        // Remove from current position
        cacheAccessOrder.removeAll { $0 == index }

        // Add to end (most recently used)
        cacheAccessOrder.append(index)
    }

    /// Evicts the least recently used frame.
    private func evictLRU() {
        guard let lruIndex = cacheAccessOrder.first else {
            return
        }

        frameCache.removeValue(forKey: lruIndex)
        cacheAccessOrder.removeFirst()
    }

    /// Evicts frames until memory limit is satisfied.
    private func evictToMemoryLimit(requiredSpace: UInt64) {
        var currentMemory = frameCache.values.reduce(0) { $0 + $1.memorySize }

        while currentMemory + requiredSpace > configuration.memoryLimit && !cacheAccessOrder.isEmpty {
            evictLRU()
            currentMemory = frameCache.values.reduce(0) { $0 + $1.memorySize }
        }
    }

    /// Estimates memory size of a frame.
    private func estimateFrameMemorySize(_ image: J2KImage) -> UInt64 {
        var size: UInt64 = 0

        for component in image.components {
            // Each sample is stored in Int32 in J2KComponent
            size += UInt64(component.width * component.height * MemoryLayout<Int32>.size)
        }

        return size
    }

    // MARK: - Playback Logic

    /// Handles playback boundary (end of sequence).
    private func handlePlaybackBoundary() async throws -> Bool {
        switch loopMode {
        case .none:
            state = .stopped
            return false

        case .loop:
            // Return to start
            if playbackMode == .reverse || playbackMode == .stepBackward {
                currentFrameIndex = frameMetadata.count - 1
            } else {
                currentFrameIndex = 0
            }
            try await prefetchFrames()
            return true

        case .pingPong:
            // Reverse direction
            switch playbackMode {
            case .forward:
                playbackMode = .reverse
                currentFrameIndex = frameMetadata.count - 1
            case .reverse:
                playbackMode = .forward
                currentFrameIndex = 0
            case .stepForward:
                playbackMode = .stepBackward
            case .stepBackward:
                playbackMode = .stepForward
            }
            try await prefetchFrames()
            return true
        }
    }

    // MARK: - Sample Table Parsing

    /// Parses sample table from MJ2 data.
    private func parseSampleTable(from data: Data, fileInfo: MJ2FileInfo) throws -> MJ2SampleTable {
        // This is a placeholder implementation
        // Real implementation would parse stbl box and its children
        MJ2SampleTable(
            sampleSizes: [],
            chunkOffsets: [],
            sampleToChunk: [],
            timeToSample: [],
            syncSamples: nil
        )
    }

    /// Builds frame metadata from sample table.
    private func buildFrameMetadata() throws -> [MJ2FrameMetadata] {
        guard let sampleTable = sampleTable else {
            return []
        }

        var metadata: [MJ2FrameMetadata] = []
        var timestamp: UInt64 = 0

        // Build frame metadata from sample table
        // This is simplified - real implementation would properly iterate samples
        for index in 0..<sampleTable.sampleSizes.count {
            let size = sampleTable.sampleSizes[index]
            let duration = sampleTable.timeToSample.first?.sampleDelta ?? 1
            let isSync = sampleTable.syncSamples?.contains(UInt32(index + 1)) ?? true

            let frame = MJ2FrameMetadata(
                index: index,
                size: size,
                offset: 0, // Would be calculated from chunk offsets
                duration: duration,
                timestamp: timestamp,
                isSync: isSync
            )

            metadata.append(frame)
            timestamp += UInt64(duration)
        }

        return metadata
    }
}

// MARK: - Sample Table (Simplified)

/// Simplified sample table structure for player.
private struct MJ2SampleTable: Sendable {
    let sampleSizes: [UInt32]
    let chunkOffsets: [UInt64]
    let sampleToChunk: [SampleToChunkEntry]
    let timeToSample: [TimeToSampleEntry]
    let syncSamples: [UInt32]?

    struct SampleToChunkEntry: Sendable {
        let firstChunk: UInt32
        let samplesPerChunk: UInt32
        let sampleDescriptionIndex: UInt32
    }

    struct TimeToSampleEntry: Sendable {
        let sampleCount: UInt32
        let sampleDelta: UInt32
    }
}
