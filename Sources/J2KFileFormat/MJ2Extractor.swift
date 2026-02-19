/// # MJ2Extractor
///
/// Frame extraction from Motion JPEG 2000 files.
///
/// This module provides the main API for extracting frames from MJ2 files,
/// with support for various extraction strategies and output options.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Extraction Error

/// Errors that can occur during MJ2 extraction.
public enum MJ2ExtractionError: Error, Sendable {
    /// The file is not a valid MJ2 file.
    case invalidFile
    
    /// No video tracks found in the file.
    case noVideoTracks
    
    /// The specified track was not found.
    case trackNotFound(trackID: UInt32)
    
    /// The specified frame range is invalid.
    case invalidFrameRange(start: Int, end: Int, available: Int)
    
    /// The specified timestamp range is invalid.
    case invalidTimestampRange
    
    /// Frame extraction failed.
    case extractionFailed(frameIndex: Int, error: Error)
    
    /// Extraction was cancelled.
    case cancelled
}

// MARK: - Extraction Strategy

/// Strategy for selecting which frames to extract.
public enum MJ2ExtractionStrategy: Sendable {
    /// Extract all frames.
    case all
    
    /// Extract only sync frames (key frames).
    case syncOnly
    
    /// Extract a specific frame range.
    case range(start: Int, end: Int)
    
    /// Extract frames by timestamp range (in time units).
    case timestampRange(start: UInt64, end: UInt64)
    
    /// Extract every Nth frame.
    case skip(interval: Int)
    
    /// Extract a single frame.
    case single(index: Int)
}

// MARK: - Output Strategy

/// Strategy for outputting extracted frames.
public enum MJ2OutputStrategy: Sendable {
    /// In-memory frame array.
    case memory
    
    /// Individual JPEG 2000 files with custom naming.
    case files(directory: URL, naming: @Sendable (Int) -> String)
    
    /// Image sequence with default naming.
    case imageSequence(directory: URL, prefix: String)
    
    /// Default naming function for image sequences.
    public static func defaultNaming(prefix: String) -> @Sendable (Int) -> String {
        { index in "\(prefix)_\(String(format: "%06d", index)).j2k" }
    }
}

// MARK: - Extraction Options

/// Options for frame extraction.
public struct MJ2ExtractionOptions: Sendable {
    /// The extraction strategy.
    public var strategy: MJ2ExtractionStrategy
    
    /// The output strategy.
    public var outputStrategy: MJ2OutputStrategy
    
    /// Whether to decode frames to images.
    public var decodeFrames: Bool
    
    /// Whether to extract in parallel.
    public var parallel: Bool
    
    /// Track ID to extract (nil for first video track).
    public var trackID: UInt32?
    
    /// Creates extraction options.
    ///
    /// - Parameters:
    ///   - strategy: Extraction strategy (default: .all).
    ///   - outputStrategy: Output strategy (default: .memory).
    ///   - decodeFrames: Whether to decode frames (default: false).
    ///   - parallel: Whether to extract in parallel (default: true).
    ///   - trackID: Track ID to extract (default: nil).
    public init(
        strategy: MJ2ExtractionStrategy = .all,
        outputStrategy: MJ2OutputStrategy = .memory,
        decodeFrames: Bool = false,
        parallel: Bool = true,
        trackID: UInt32? = nil
    ) {
        self.strategy = strategy
        self.outputStrategy = outputStrategy
        self.decodeFrames = decodeFrames
        self.parallel = parallel
        self.trackID = trackID
    }
}

// MARK: - MJ2 Extractor

/// Extracts frames from Motion JPEG 2000 files.
///
/// `MJ2Extractor` handles the complete process of extracting frames from MJ2 files:
/// 1. Parses file structure and sample tables
/// 2. Extracts frame data based on strategy
/// 3. Optionally decodes frames to images
/// 4. Outputs frames according to output strategy
///
/// The extractor is implemented as an actor to ensure thread-safe operations
/// and enable parallel frame extraction when configured.
///
/// ## Basic Usage
///
/// ```swift
/// let extractor = MJ2Extractor()
/// let sequence = try await extractor.extract(from: fileURL)
/// print("Extracted \(sequence.count) frames")
/// ```
///
/// ## Extraction Strategies
///
/// ```swift
/// // Extract only key frames
/// let options = MJ2ExtractionOptions(strategy: .syncOnly)
/// let keyFrames = try await extractor.extract(from: fileURL, options: options)
///
/// // Extract a specific range
/// let options = MJ2ExtractionOptions(strategy: .range(start: 10, end: 20))
/// let rangeFrames = try await extractor.extract(from: fileURL, options: options)
/// ```
///
/// ## Output Options
///
/// ```swift
/// // Save to individual files
/// let options = MJ2ExtractionOptions(
///     outputStrategy: .imageSequence(directory: outputDir, prefix: "frame")
/// )
/// try await extractor.extract(from: fileURL, options: options)
/// ```
public actor MJ2Extractor {
    /// The JPEG 2000 decoder.
    private let decoder: J2KDecoder
    
    /// Whether extraction should be cancelled.
    private var shouldCancel = false
    
    /// Creates a new MJ2 extractor.
    public init() {
        self.decoder = J2KDecoder()
    }
    
    /// Cancels the current extraction.
    public func cancel() {
        shouldCancel = true
    }
    
    /// Extracts frames from an MJ2 file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the MJ2 file.
    ///   - options: Extraction options.
    ///   - progress: Optional progress callback.
    /// - Returns: The extracted frame sequence (for memory output) or nil (for file output).
    /// - Throws: ``MJ2ExtractionError`` or ``J2KError`` if extraction fails.
    public func extract(
        from fileURL: URL,
        options: MJ2ExtractionOptions = MJ2ExtractionOptions(),
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> MJ2FrameSequence? {
        // Reset cancellation flag
        shouldCancel = false
        
        // Load file data
        let fileData = try Data(contentsOf: fileURL)
        
        return try await extract(from: fileData, options: options, progress: progress)
    }
    
    /// Extracts frames from MJ2 data.
    ///
    /// - Parameters:
    ///   - data: The MJ2 file data.
    ///   - options: Extraction options.
    ///   - progress: Optional progress callback.
    /// - Returns: The extracted frame sequence (for memory output) or nil (for file output).
    /// - Throws: ``MJ2ExtractionError`` or ``J2KError`` if extraction fails.
    public func extract(
        from data: Data,
        options: MJ2ExtractionOptions = MJ2ExtractionOptions(),
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> MJ2FrameSequence? {
        // Parse file structure
        let reader = MJ2FileReader()
        let fileInfo = try await reader.readFileInfo(from: data)
        
        // Find video track
        guard let trackInfo = findTrack(in: fileInfo, trackID: options.trackID) else {
            throw MJ2ExtractionError.noVideoTracks
        }
        
        // Parse sample tables
        let sampleTable = try parseSampleTable(from: data, fileInfo: fileInfo)
        
        // Determine which frames to extract
        let frameIndices = try selectFrames(
            strategy: options.strategy,
            sampleTable: sampleTable,
            trackInfo: trackInfo
        )
        
        // Extract frames
        let frames = try await extractFrames(
            data: data,
            sampleTable: sampleTable,
            indices: frameIndices,
            options: options,
            progress: progress
        )
        
        // Handle output strategy
        switch options.outputStrategy {
        case .memory:
            return MJ2FrameSequence(frames: frames)
            
        case .files(let directory, let naming):
            try await writeFramesToFiles(frames: frames, directory: directory, naming: naming)
            return nil
            
        case .imageSequence(let directory, let prefix):
            let naming = MJ2OutputStrategy.defaultNaming(prefix: prefix)
            try await writeFramesToFiles(frames: frames, directory: directory, naming: naming)
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    /// Finds the appropriate video track.
    private func findTrack(in fileInfo: MJ2FileInfo, trackID: UInt32?) -> MJ2TrackInfo? {
        if let trackID = trackID {
            return fileInfo.videoTracks.first { $0.trackID == trackID }
        } else {
            return fileInfo.videoTracks.first
        }
    }
    
    /// Parses sample table from file data.
    private func parseSampleTable(from data: Data, fileInfo: MJ2FileInfo) throws -> SampleTable {
        // Find moov box
        guard let moovData = findBox(type: .moov, in: data) else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Find first video track
        guard let trakData = findBox(type: .trak, in: moovData) else {
            throw MJ2ExtractionError.noVideoTracks
        }
        
        // Find media box
        guard let mdiaData = findBox(type: .mdia, in: trakData) else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Find media information box
        guard let minfData = findBox(type: .minf, in: mdiaData) else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Find sample table box
        guard let stblData = findBox(type: .stbl, in: minfData) else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Parse sample sizes
        guard let stszData = findBox(type: .stsz, in: stblData) else {
            throw MJ2ExtractionError.invalidFile
        }
        let sizes = try parseSampleSizes(from: stszData)
        
        // Parse chunk offsets
        var offsets: [UInt64] = []
        if let stcoData = findBox(type: .stco, in: stblData) {
            offsets = try parseChunkOffsets32(from: stcoData)
        } else if let co64Data = findBox(type: .co64, in: stblData) {
            offsets = try parseChunkOffsets64(from: co64Data)
        } else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Parse sample-to-chunk
        guard let stscData = findBox(type: .stsc, in: stblData) else {
            throw MJ2ExtractionError.invalidFile
        }
        let sampleToChunk = try parseSampleToChunk(from: stscData)
        
        // Parse time-to-sample
        guard let sttsData = findBox(type: .stts, in: stblData) else {
            throw MJ2ExtractionError.invalidFile
        }
        let durations = try parseTimeToSample(from: sttsData, sampleCount: sizes.count)
        
        // Parse sync samples (optional)
        var syncSamples = Set<Int>()
        if let stssData = findBox(type: .stss, in: stblData) {
            syncSamples = try parseSyncSamples(from: stssData)
        } else {
            // All samples are sync samples if stss is not present
            syncSamples = Set(0..<sizes.count)
        }
        
        // Build frame table
        let frames = try buildFrameTable(
            sizes: sizes,
            chunkOffsets: offsets,
            sampleToChunk: sampleToChunk,
            durations: durations,
            syncSamples: syncSamples
        )
        
        return SampleTable(frames: frames)
    }
    
    /// Finds a box of the specified type in data.
    private func findBox(type: J2KBoxType, in data: Data) -> Data? {
        var offset = 0
        while offset < data.count {
            guard offset + 8 <= data.count else {
                break
            }
            
            let boxLength = Int(data.readUInt32(at: offset))
            let boxType = J2KBoxType(rawValue: data.readUInt32(at: offset + 4))
            
            guard boxLength >= 8 && offset + boxLength <= data.count else {
                break
            }
            
            if boxType == type {
                return data.subdata(in: (offset + 8)..<(offset + boxLength))
            }
            
            offset += boxLength
        }
        
        return nil
    }
    
    /// Parses sample sizes from stsz box.
    private func parseSampleSizes(from data: Data) throws -> [UInt32] {
        guard data.count >= 12 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let sampleSize = data.readUInt32(at: 4)
        let sampleCount = Int(data.readUInt32(at: 8))
        
        if sampleSize != 0 {
            // All samples have the same size
            return Array(repeating: sampleSize, count: sampleCount)
        } else {
            // Variable sizes
            guard data.count >= 12 + sampleCount * 4 else {
                throw MJ2ExtractionError.invalidFile
            }
            
            var sizes: [UInt32] = []
            for i in 0..<sampleCount {
                let size = data.readUInt32(at: 12 + i * 4)
                sizes.append(size)
            }
            return sizes
        }
    }
    
    /// Parses 32-bit chunk offsets from stco box.
    private func parseChunkOffsets32(from data: Data) throws -> [UInt64] {
        guard data.count >= 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let entryCount = Int(data.readUInt32(at: 4))
        
        guard data.count >= 8 + entryCount * 4 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        var offsets: [UInt64] = []
        for i in 0..<entryCount {
            let offset = UInt64(data.readUInt32(at: 8 + i * 4))
            offsets.append(offset)
        }
        return offsets
    }
    
    /// Parses 64-bit chunk offsets from co64 box.
    private func parseChunkOffsets64(from data: Data) throws -> [UInt64] {
        guard data.count >= 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let entryCount = Int(data.readUInt32(at: 4))
        
        guard data.count >= 8 + entryCount * 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        var offsets: [UInt64] = []
        for i in 0..<entryCount {
            let offset = data.readUInt64(at: 8 + i * 8)
            offsets.append(offset)
        }
        return offsets
    }
    
    /// Parses sample-to-chunk mapping from stsc box.
    private func parseSampleToChunk(from data: Data) throws -> [(firstChunk: Int, samplesPerChunk: Int)] {
        guard data.count >= 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let entryCount = Int(data.readUInt32(at: 4))
        
        guard data.count >= 8 + entryCount * 12 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        var entries: [(Int, Int)] = []
        for i in 0..<entryCount {
            let firstChunk = Int(data.readUInt32(at: 8 + i * 12))
            let samplesPerChunk = Int(data.readUInt32(at: 12 + i * 12))
            // Skip sampleDescriptionIndex
            entries.append((firstChunk, samplesPerChunk))
        }
        return entries
    }
    
    /// Parses time-to-sample from stts box.
    private func parseTimeToSample(from data: Data, sampleCount: Int) throws -> [UInt32] {
        guard data.count >= 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let entryCount = Int(data.readUInt32(at: 4))
        
        guard data.count >= 8 + entryCount * 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        var durations: [UInt32] = []
        for i in 0..<entryCount {
            let count = Int(data.readUInt32(at: 8 + i * 8))
            let duration = data.readUInt32(at: 12 + i * 8)
            
            for _ in 0..<count {
                durations.append(duration)
            }
        }
        
        return durations
    }
    
    /// Parses sync samples from stss box.
    private func parseSyncSamples(from data: Data) throws -> Set<Int> {
        guard data.count >= 8 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        // Skip version/flags
        let entryCount = Int(data.readUInt32(at: 4))
        
        guard data.count >= 8 + entryCount * 4 else {
            throw MJ2ExtractionError.invalidFile
        }
        
        var syncSamples = Set<Int>()
        for i in 0..<entryCount {
            let sampleNumber = Int(data.readUInt32(at: 8 + i * 4)) - 1 // Convert to 0-based
            syncSamples.insert(sampleNumber)
        }
        return syncSamples
    }
    
    /// Builds frame table from sample table data.
    private func buildFrameTable(
        sizes: [UInt32],
        chunkOffsets: [UInt64],
        sampleToChunk: [(firstChunk: Int, samplesPerChunk: Int)],
        durations: [UInt32],
        syncSamples: Set<Int>
    ) throws -> [MJ2FrameMetadata] {
        var frames: [MJ2FrameMetadata] = []
        var currentSample = 0
        var timestamp: UInt64 = 0
        
        // Iterate through chunks
        for chunkIndex in 0..<chunkOffsets.count {
            let chunkOffset = chunkOffsets[chunkIndex]
            
            // Find samples per chunk for this chunk
            var samplesPerChunk = 1
            for (firstChunk, samples) in sampleToChunk.reversed() {
                if chunkIndex + 1 >= firstChunk {
                    samplesPerChunk = samples
                    break
                }
            }
            
            // Process samples in this chunk
            var sampleOffset = chunkOffset
            for _ in 0..<samplesPerChunk {
                guard currentSample < sizes.count else {
                    break
                }
                
                let size = sizes[currentSample]
                let duration = currentSample < durations.count ? durations[currentSample] : 0
                let isSync = syncSamples.contains(currentSample)
                
                let metadata = MJ2FrameMetadata(
                    index: currentSample,
                    size: size,
                    offset: sampleOffset,
                    duration: duration,
                    timestamp: timestamp,
                    isSync: isSync
                )
                frames.append(metadata)
                
                sampleOffset += UInt64(size)
                timestamp += UInt64(duration)
                currentSample += 1
            }
        }
        
        return frames
    }
    
    /// Selects which frames to extract based on strategy.
    private func selectFrames(
        strategy: MJ2ExtractionStrategy,
        sampleTable: SampleTable,
        trackInfo: MJ2TrackInfo
    ) throws -> [Int] {
        switch strategy {
        case .all:
            return Array(0..<sampleTable.frames.count)
            
        case .syncOnly:
            return sampleTable.frames.enumerated().compactMap { index, frame in
                frame.isSync ? index : nil
            }
            
        case .range(let start, let end):
            guard start >= 0 && end <= sampleTable.frames.count && start < end else {
                throw MJ2ExtractionError.invalidFrameRange(
                    start: start,
                    end: end,
                    available: sampleTable.frames.count
                )
            }
            return Array(start..<end)
            
        case .timestampRange(let startTime, let endTime):
            return sampleTable.frames.enumerated().compactMap { index, frame in
                let frameStart = frame.timestamp
                let frameEnd = frameStart + UInt64(frame.duration)
                return (frameStart < endTime && frameEnd > startTime) ? index : nil
            }
            
        case .skip(let interval):
            guard interval > 0 else {
                return []
            }
            return stride(from: 0, to: sampleTable.frames.count, by: interval).map { $0 }
            
        case .single(let index):
            guard index >= 0 && index < sampleTable.frames.count else {
                throw MJ2ExtractionError.invalidFrameRange(
                    start: index,
                    end: index + 1,
                    available: sampleTable.frames.count
                )
            }
            return [index]
        }
    }
    
    /// Extracts frames from file data.
    private func extractFrames(
        data: Data,
        sampleTable: SampleTable,
        indices: [Int],
        options: MJ2ExtractionOptions,
        progress: ((Int, Int) -> Void)?
    ) async throws -> [MJ2FrameSequence.Frame] {
        var frames: [MJ2FrameSequence.Frame] = []
        
        if options.parallel {
            // Parallel extraction
            frames = try await withThrowingTaskGroup(of: (Int, MJ2FrameSequence.Frame).self) { group in
                for (index, frameIndex) in indices.enumerated() {
                    group.addTask {
                        let frame = try await self.extractFrame(
                            data: data,
                            metadata: sampleTable.frames[frameIndex],
                            decode: options.decodeFrames
                        )
                        return (index, frame)
                    }
                }
                
                var result: [(Int, MJ2FrameSequence.Frame)] = []
                for try await item in group {
                    result.append(item)
                    progress?(result.count, indices.count)
                    
                    if shouldCancel {
                        throw MJ2ExtractionError.cancelled
                    }
                }
                
                // Sort by original index
                return result.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
        } else {
            // Sequential extraction
            for (index, frameIndex) in indices.enumerated() {
                let frame = try await extractFrame(
                    data: data,
                    metadata: sampleTable.frames[frameIndex],
                    decode: options.decodeFrames
                )
                frames.append(frame)
                progress?(index + 1, indices.count)
                
                if shouldCancel {
                    throw MJ2ExtractionError.cancelled
                }
            }
        }
        
        return frames
    }
    
    /// Extracts a single frame.
    private func extractFrame(
        data: Data,
        metadata: MJ2FrameMetadata,
        decode: Bool
    ) async throws -> MJ2FrameSequence.Frame {
        // Extract frame data
        let start = Int(metadata.offset)
        let end = start + Int(metadata.size)
        
        guard end <= data.count else {
            throw MJ2ExtractionError.extractionFailed(
                frameIndex: metadata.index,
                error: J2KError.fileFormatError("Frame data out of bounds")
            )
        }
        
        let frameData = data.subdata(in: start..<end)
        
        // Optionally decode
        var frame = MJ2FrameSequence.Frame(metadata: metadata, data: frameData)
        
        if decode {
            do {
                let image = try decoder.decode(frameData)
                frame.image = image
            } catch {
                throw MJ2ExtractionError.extractionFailed(
                    frameIndex: metadata.index,
                    error: error
                )
            }
        }
        
        return frame
    }
    
    /// Writes frames to individual files.
    private func writeFramesToFiles(
        frames: [MJ2FrameSequence.Frame],
        directory: URL,
        naming: @Sendable (Int) -> String
    ) async throws {
        // Create directory if needed
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Write each frame
        for frame in frames {
            let filename = naming(frame.metadata.index)
            let fileURL = directory.appendingPathComponent(filename)
            try frame.data.write(to: fileURL)
        }
    }
}

// MARK: - Sample Table

/// Internal sample table representation.
private struct SampleTable {
    let frames: [MJ2FrameMetadata]
}
