//
// MJ2SampleTable.swift
// J2KSwift
//
/// # MJ2SampleTable
///
/// Sample table generation for Motion JPEG 2000 files.
///
/// This module provides builders for creating ISO base media format sample tables,
/// which describe the location, size, and timing of video frames in an MJ2 file.

import Foundation
import J2KCore

// MARK: - Sample Table Entry

/// Information about a single frame in the MJ2 file.
struct MJ2FrameInfo: Sendable {
    /// Sample size in bytes.
    let size: UInt32

    /// Chunk offset in the file.
    let offset: UInt64

    /// Sample duration in time units.
    let duration: UInt32

    /// Whether this is a sync sample (key frame).
    let isSync: Bool
}

// MARK: - Sample Table Builder

/// Builds sample tables for MJ2 files.
///
/// The sample table builder accumulates information about encoded frames
/// and generates the required ISO base media format sample table boxes.
///
/// Sample tables include:
/// - `stsz`: Sample sizes
/// - `stsc`: Sample-to-chunk mapping
/// - `stco`/`co64`: Chunk offsets
/// - `stts`: Time-to-sample
/// - `stss`: Sync samples
actor MJ2SampleTableBuilder {
    /// Accumulated sample entries.
    private var samples: [MJ2FrameInfo] = []

    /// Default sample duration (in time units).
    private let defaultDuration: UInt32

    /// Whether to use 64-bit offsets.
    private let use64BitOffsets: Bool

    /// Creates a new sample table builder.
    ///
    /// - Parameters:
    ///   - defaultDuration: Default frame duration in time units.
    ///   - use64BitOffsets: Whether to use 64-bit chunk offsets.
    init(defaultDuration: UInt32, use64BitOffsets: Bool = false) {
        self.defaultDuration = defaultDuration
        self.use64BitOffsets = use64BitOffsets
    }

    /// Adds a sample to the table.
    ///
    /// - Parameters:
    ///   - size: Sample size in bytes.
    ///   - offset: Sample offset in the file.
    ///   - duration: Sample duration (nil uses default).
    ///   - isSync: Whether this is a sync sample.
    func addSample(size: UInt32, offset: UInt64, duration: UInt32? = nil, isSync: Bool = true) {
        let entry = MJ2FrameInfo(
            size: size,
            offset: offset,
            duration: duration ?? defaultDuration,
            isSync: isSync
        )
        samples.append(entry)
    }

    /// Returns the number of samples added.
    var sampleCount: Int {
        samples.count
    }

    /// Builds the sample size box (stsz).
    ///
    /// - Returns: Data for the stsz box.
    func buildSampleSizeBox() -> Data {
        var data = Data()

        // Check if all samples have the same size
        let allSame = !samples.isEmpty && samples.allSatisfy { $0.size == samples[0].size }

        // Version and flags
        data.append(contentsOf: [0, 0, 0, 0])

        // Sample size (0 if variable)
        let sampleSize = allSame ? samples[0].size : 0
        data.append(contentsOf: sampleSize.bigEndianBytes)

        // Sample count
        data.append(contentsOf: UInt32(samples.count).bigEndianBytes)

        // Entry table (only if variable size)
        if !allSame {
            for sample in samples {
                data.append(contentsOf: sample.size.bigEndianBytes)
            }
        }

        return wrapInBox(type: .stsz, data: data)
    }

    /// Builds the sample-to-chunk box (stsc).
    ///
    /// For simplicity, we use one sample per chunk.
    ///
    /// - Returns: Data for the stsc box.
    func buildSampleToChunkBox() -> Data {
        var data = Data()

        // Version and flags
        data.append(contentsOf: [0, 0, 0, 0])

        // Entry count (1 entry: all chunks have 1 sample)
        data.append(contentsOf: UInt32(1).bigEndianBytes)

        // Entry: first_chunk=1, samples_per_chunk=1, sample_description_index=1
        data.append(contentsOf: UInt32(1).bigEndianBytes)  // first_chunk
        data.append(contentsOf: UInt32(1).bigEndianBytes)  // samples_per_chunk
        data.append(contentsOf: UInt32(1).bigEndianBytes)  // sample_description_index

        return wrapInBox(type: .stsc, data: data)
    }

    /// Builds the chunk offset box (stco or co64).
    ///
    /// - Returns: Data for the stco or co64 box.
    func buildChunkOffsetBox() -> Data {
        var data = Data()

        if use64BitOffsets {
            // co64: 64-bit chunk offsets
            // Version and flags
            data.append(contentsOf: [0, 0, 0, 0])

            // Entry count
            data.append(contentsOf: UInt32(samples.count).bigEndianBytes)

            // Offsets (64-bit)
            for sample in samples {
                data.append(contentsOf: sample.offset.bigEndianBytes)
            }

            return wrapInBox(type: .co64, data: data)
        } else {
            // stco: 32-bit chunk offsets
            // Version and flags
            data.append(contentsOf: [0, 0, 0, 0])

            // Entry count
            data.append(contentsOf: UInt32(samples.count).bigEndianBytes)

            // Offsets (32-bit)
            for sample in samples {
                let offset32 = UInt32(min(sample.offset, UInt64(UInt32.max)))
                data.append(contentsOf: offset32.bigEndianBytes)
            }

            return wrapInBox(type: .stco, data: data)
        }
    }

    /// Builds the time-to-sample box (stts).
    ///
    /// - Returns: Data for the stts box.
    func buildTimeToSampleBox() -> Data {
        var data = Data()

        // Version and flags
        data.append(contentsOf: [0, 0, 0, 0])

        // Compress consecutive samples with same duration
        var entries: [(count: UInt32, duration: UInt32)] = []

        for sample in samples {
            if let last = entries.last, last.duration == sample.duration {
                entries[entries.count - 1].count += 1
            } else {
                entries.append((count: 1, duration: sample.duration))
            }
        }

        // Entry count
        data.append(contentsOf: UInt32(entries.count).bigEndianBytes)

        // Entries
        for entry in entries {
            data.append(contentsOf: entry.count.bigEndianBytes)
            data.append(contentsOf: entry.duration.bigEndianBytes)
        }

        return wrapInBox(type: .stts, data: data)
    }

    /// Builds the sync sample box (stss).
    ///
    /// - Returns: Data for the stss box, or nil if all samples are sync samples.
    func buildSyncSampleBox() -> Data? {
        // If all samples are sync samples, stss box is optional
        let allSync = samples.allSatisfy { $0.isSync }
        guard !allSync else { return nil }

        var data = Data()

        // Version and flags
        data.append(contentsOf: [0, 0, 0, 0])

        // Collect sync sample indices (1-based)
        let syncIndices = samples.enumerated()
            .filter { $0.element.isSync }
            .map { UInt32($0.offset + 1) }

        // Entry count
        data.append(contentsOf: UInt32(syncIndices.count).bigEndianBytes)

        // Sync sample indices
        for index in syncIndices {
            data.append(contentsOf: index.bigEndianBytes)
        }

        return wrapInBox(type: .stss, data: data)
    }

    /// Builds all sample table boxes.
    ///
    /// - Returns: An array of box data in the correct order.
    func buildAllBoxes() -> [Data] {
        var boxes: [Data] = []

        boxes.append(buildSampleSizeBox())
        boxes.append(buildSampleToChunkBox())
        boxes.append(buildChunkOffsetBox())
        boxes.append(buildTimeToSampleBox())

        if let stss = buildSyncSampleBox() {
            boxes.append(stss)
        }

        return boxes
    }

    /// Wraps data in a box with the specified type.
    private func wrapInBox(type: J2KBoxType, data: Data) -> Data {
        var boxData = Data()

        // Box size (4 bytes) + box type (4 bytes) + data
        let size = UInt32(8 + data.count)
        boxData.append(contentsOf: size.bigEndianBytes)
        boxData.append(contentsOf: type.rawValue.bigEndianBytes)
        boxData.append(data)

        return boxData
    }
}

// MARK: - UInt Extensions (using existing bigEndianBytes from MJ2Box.swift)
