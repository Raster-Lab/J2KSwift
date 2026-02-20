/// # MJ2FrameSequence
///
/// Frame sequence organization for Motion JPEG 2000 extraction.
///
/// This module provides types for organizing and accessing extracted frames
/// from MJ2 files.

import Foundation
import J2KCore

// MARK: - Frame Metadata

/// Metadata for a single frame in an MJ2 file.
public struct MJ2FrameMetadata: Sendable {
    /// Frame index (0-based).
    public let index: Int

    /// Frame size in bytes.
    public let size: UInt32

    /// Frame offset in the file.
    public let offset: UInt64

    /// Frame duration in time units.
    public let duration: UInt32

    /// Frame timestamp in time units.
    public let timestamp: UInt64

    /// Whether this is a sync sample (key frame).
    public let isSync: Bool

    /// Creates frame metadata.
    ///
    /// - Parameters:
    ///   - index: Frame index.
    ///   - size: Frame size in bytes.
    ///   - offset: Frame offset in the file.
    ///   - duration: Frame duration in time units.
    ///   - timestamp: Frame timestamp in time units.
    ///   - isSync: Whether this is a sync sample.
    public init(
        index: Int,
        size: UInt32,
        offset: UInt64,
        duration: UInt32,
        timestamp: UInt64,
        isSync: Bool
    ) {
        self.index = index
        self.size = size
        self.offset = offset
        self.duration = duration
        self.timestamp = timestamp
        self.isSync = isSync
    }
}

// MARK: - Frame Sequence

/// A sequence of frames extracted from an MJ2 file.
///
/// `MJ2FrameSequence` provides organized access to extracted frames
/// with metadata about timing and synchronization.
///
/// Example:
/// ```swift
/// let sequence = try await extractor.extract(from: fileURL)
/// for frame in sequence.frames {
///     print("Frame \(frame.metadata.index) at \(frame.metadata.timestamp)")
/// }
/// ```
public struct MJ2FrameSequence: Sendable {
    /// Individual frame with its data and metadata.
    public struct Frame: Sendable {
        /// Frame metadata.
        public let metadata: MJ2FrameMetadata

        /// Frame codestream data.
        public let data: Data

        /// Decoded image (lazily decoded).
        public var image: J2KImage?

        /// Creates a frame.
        ///
        /// - Parameters:
        ///   - metadata: Frame metadata.
        ///   - data: Frame codestream data.
        public init(metadata: MJ2FrameMetadata, data: Data) {
            self.metadata = metadata
            self.data = data
        }
    }

    /// All frames in the sequence.
    public let frames: [Frame]

    /// Total number of frames.
    public var count: Int {
        frames.count
    }

    /// Duration in time units.
    public var totalDuration: UInt64 {
        guard let last = frames.last else { return 0 }
        return last.metadata.timestamp + UInt64(last.metadata.duration)
    }

    /// Sync frames only.
    public var syncFrames: [Frame] {
        frames.filter { $0.metadata.isSync }
    }

    /// Creates a frame sequence.
    ///
    /// - Parameter frames: The frames in the sequence.
    public init(frames: [Frame]) {
        self.frames = frames
    }

    /// Gets a frame by index.
    ///
    /// - Parameter index: The frame index.
    /// - Returns: The frame, or nil if index is out of bounds.
    public func frame(at index: Int) -> Frame? {
        guard index >= 0 && index < frames.count else {
            return nil
        }
        return frames[index]
    }

    /// Gets frames in a range.
    ///
    /// - Parameter range: The index range.
    /// - Returns: Frames in the range.
    public func frames(in range: Range<Int>) -> [Frame] {
        let start = max(0, range.lowerBound)
        let end = min(frames.count, range.upperBound)
        guard start < end else { return [] }
        return Array(frames[start..<end])
    }

    /// Gets frames within a timestamp range.
    ///
    /// - Parameter range: The timestamp range (in time units).
    /// - Returns: Frames in the timestamp range.
    public func frames(timestampRange range: Range<UInt64>) -> [Frame] {
        frames.filter { frame in
            let start = frame.metadata.timestamp
            let end = start + UInt64(frame.metadata.duration)
            return start < range.upperBound && end > range.lowerBound
        }
    }
}
