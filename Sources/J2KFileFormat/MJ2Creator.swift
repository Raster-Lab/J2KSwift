/// # MJ2Creator
///
/// Motion JPEG 2000 file creation from image sequences.
///
/// This module provides the main API for creating MJ2 files from sequences of images,
/// with support for parallel encoding, progress reporting, and rate control.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Creation Error

/// Errors that can occur during MJ2 creation.
public enum MJ2CreationError: Error, Sendable {
    /// No frames were provided.
    case noFrames

    /// Frame dimensions don't match the first frame.
    case inconsistentDimensions(expected: (Int, Int), got: (Int, Int))

    /// Frame component count doesn't match the first frame.
    case inconsistentComponents(expected: Int, got: Int)

    /// Creation was cancelled.
    case cancelled

    /// Encoding failed for a frame.
    case encodingFailed(frameIndex: Int, error: Error)
}

// MARK: - MJ2 Creator

/// Creates Motion JPEG 2000 files from image sequences.
///
/// `MJ2Creator` handles the complete process of creating an MJ2 file:
/// 1. Validates input frames
/// 2. Encodes each frame as JPEG 2000
/// 3. Writes frames to file with proper timing
/// 4. Generates sample tables and metadata
/// 5. Finalizes the MJ2 file structure
///
/// The creator is implemented as an actor to ensure thread-safe operations
/// and enable parallel frame encoding when configured.
///
/// ## Basic Usage
///
/// ```swift
/// let config = MJ2CreationConfiguration.from(frameRate: 30.0)
/// let creator = MJ2Creator(configuration: config)
///
/// let frames: [J2KImage] = // ... load frames
/// try await creator.create(from: frames, outputURL: outputURL)
/// ```
///
/// ## Progress Reporting
///
/// ```swift
/// try await creator.create(from: frames, outputURL: outputURL) { update in
///     print("Frame \(update.frameNumber + 1)/\(update.totalFrames)")
/// }
/// ```
public actor MJ2Creator {
    /// The configuration for MJ2 creation.
    public let configuration: MJ2CreationConfiguration

    /// The JPEG 2000 encoder.
    private let encoder: J2KEncoder

    /// Whether creation should be cancelled.
    private var shouldCancel = false

    /// Creates a new MJ2 creator.
    ///
    /// - Parameter configuration: Configuration for MJ2 creation.
    public init(configuration: MJ2CreationConfiguration) {
        self.configuration = configuration
        self.encoder = J2KEncoder(encodingConfiguration: configuration.encodingConfiguration)
    }

    /// Creates an MJ2 file from a sequence of images.
    ///
    /// - Parameters:
    ///   - frames: The sequence of images to encode.
    ///   - outputURL: The URL where the MJ2 file will be written.
    ///   - progress: Optional progress callback.
    /// - Throws: ``MJ2CreationError`` or ``J2KError`` if creation fails.
    public func create(
        from frames: [J2KImage],
        outputURL: URL,
        progress: ((MJ2ProgressUpdate) -> Void)? = nil
    ) async throws {
        // Reset cancellation flag
        shouldCancel = false

        // Validate input
        guard !frames.isEmpty else {
            throw MJ2CreationError.noFrames
        }

        // Validate all frames have consistent dimensions and components
        let firstFrame = frames[0]
        for (_, frame) in frames.enumerated() {
            if frame.width != firstFrame.width || frame.height != firstFrame.height {
                throw MJ2CreationError.inconsistentDimensions(
                    expected: (firstFrame.width, firstFrame.height),
                    got: (frame.width, frame.height)
                )
            }

            if frame.components.count != firstFrame.components.count {
                throw MJ2CreationError.inconsistentComponents(
                    expected: firstFrame.components.count,
                    got: frame.components.count
                )
            }
        }

        // Create stream writer
        let writer = try MJ2StreamWriter(
            outputURL: outputURL,
            width: firstFrame.width,
            height: firstFrame.height,
            configuration: configuration
        )

        // Encode and write frames
        if configuration.enableParallelEncoding && frames.count > 1 {
            try await encodeFramesInParallel(frames: frames, writer: writer, progress: progress)
        } else {
            try await encodeFramesSequentially(frames: frames, writer: writer, progress: progress)
        }

        // Check for cancellation
        if shouldCancel {
            throw MJ2CreationError.cancelled
        }

        // Finalize the file
        try await writer.finalize()
    }

    /// Encodes frames sequentially.
    private func encodeFramesSequentially(
        frames: [J2KImage],
        writer: MJ2StreamWriter,
        progress: ((MJ2ProgressUpdate) -> Void)?
    ) async throws {
        for (index, frame) in frames.enumerated() {
            // Check for cancellation
            if shouldCancel {
                throw MJ2CreationError.cancelled
            }

            // Encode frame
            let frameData = try await encodeFrame(frame, index: index)

            // Write to file
            try await writer.writeFrame(frameData, isSync: true)

            // Report progress
            if let progress = progress {
                let estimatedSize = UInt64(await writer.frameCount) * UInt64(frameData.count)
                let update = MJ2ProgressUpdate(
                    frameNumber: index,
                    totalFrames: frames.count,
                    estimatedSize: estimatedSize
                )
                progress(update)
            }
        }
    }

    /// Encodes frames in parallel.
    private func encodeFramesInParallel(
        frames: [J2KImage],
        writer: MJ2StreamWriter,
        progress: ((MJ2ProgressUpdate) -> Void)?
    ) async throws {
        // Determine parallelism level
        let parallelCount = configuration.parallelEncodingCount > 0
            ? configuration.parallelEncodingCount
            : min(ProcessInfo.processInfo.processorCount, configuration.maxFrameBufferCount)

        // Process frames in batches
        var currentIndex = 0

        while currentIndex < frames.count {
            // Check for cancellation
            if shouldCancel {
                throw MJ2CreationError.cancelled
            }

            // Determine batch size
            let batchSize = min(parallelCount, frames.count - currentIndex)
            let batchEnd = currentIndex + batchSize
            let batch = Array(frames[currentIndex..<batchEnd])

            // Encode batch in parallel
            let encodedFrames = try await withThrowingTaskGroup(
                of: (index: Int, data: Data).self
            ) { group in
                for (offset, frame) in batch.enumerated() {
                    let frameIndex = currentIndex + offset
                    group.addTask {
                        let data = try await self.encodeFrame(frame, index: frameIndex)
                        return (frameIndex, data)
                    }
                }

                // Collect results
                var results: [(index: Int, data: Data)] = []
                for try await result in group {
                    results.append(result)
                }

                // Sort by index to maintain order
                return results.sorted { $0.index < $1.index }
            }

            // Write frames in order
            for (frameIndex, frameData) in encodedFrames {
                try await writer.writeFrame(frameData, isSync: true)

                // Report progress
                if let progress = progress {
                    let estimatedSize = UInt64(await writer.frameCount) * UInt64(frameData.count)
                    let update = MJ2ProgressUpdate(
                        frameNumber: frameIndex,
                        totalFrames: frames.count,
                        estimatedSize: estimatedSize
                    )
                    progress(update)
                }
            }

            currentIndex = batchEnd
        }
    }

    /// Encodes a single frame.
    private func encodeFrame(_ frame: J2KImage, index: Int) async throws -> Data {
        do {
            return try encoder.encode(frame)
        } catch {
            throw MJ2CreationError.encodingFailed(frameIndex: index, error: error)
        }
    }

    /// Cancels the current creation operation.
    ///
    /// The creation will stop after the current frame or batch completes.
    public func cancel() {
        shouldCancel = true
    }
}

// MARK: - Convenience Methods

extension MJ2Creator {
    /// Creates an MJ2 file from a single image repeated multiple times.
    ///
    /// This is useful for creating test files or simple animations.
    ///
    /// - Parameters:
    ///   - image: The image to repeat.
    ///   - frameCount: Number of times to repeat the image.
    ///   - outputURL: The URL where the MJ2 file will be written.
    ///   - progress: Optional progress callback.
    /// - Throws: ``MJ2CreationError`` or ``J2KError`` if creation fails.
    public func createRepeated(
        image: J2KImage,
        frameCount: Int,
        outputURL: URL,
        progress: ((MJ2ProgressUpdate) -> Void)? = nil
    ) async throws {
        guard frameCount > 0 else {
            throw MJ2CreationError.noFrames
        }

        let frames = Array(repeating: image, count: frameCount)
        try await create(from: frames, outputURL: outputURL, progress: progress)
    }

    /// Creates an MJ2 file from images loaded from URLs.
    ///
    /// - Parameters:
    ///   - imageURLs: URLs of images to load and encode.
    ///   - outputURL: The URL where the MJ2 file will be written.
    ///   - progress: Optional progress callback.
    /// - Throws: ``MJ2CreationError`` or ``J2KError`` if creation fails.
    public func createFromFiles(
        imageURLs: [URL],
        outputURL: URL,
        progress: ((MJ2ProgressUpdate) -> Void)? = nil
    ) async throws {
        // Note: This is a placeholder. In practice, would need image loading functionality.
        // For now, throw an error indicating this is not yet implemented.
        throw J2KError.notImplemented("Image loading from files not yet implemented")
    }
}
