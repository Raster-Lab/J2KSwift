/// # MJ2StreamWriter
///
/// Streaming writer for Motion JPEG 2000 files.
///
/// This module provides progressive file writing with memory-efficient buffering
/// and support for large files (>4GB).

import Foundation
import J2KCore

// MARK: - Progress Update

/// Progress update during MJ2 creation.
public struct MJ2ProgressUpdate: Sendable {
    /// Current frame number (0-based).
    public let frameNumber: Int

    /// Total number of frames.
    public let totalFrames: Int

    /// Progress percentage (0.0 to 1.0).
    public var progress: Double {
        guard totalFrames > 0 else { return 0.0 }
        return Double(frameNumber) / Double(totalFrames)
    }

    /// Estimated file size so far (in bytes).
    public let estimatedSize: UInt64
}

// MARK: - Stream Writer

/// Streaming writer for MJ2 files.
///
/// `MJ2StreamWriter` handles progressive file writing, allowing frames to be
/// written one at a time without loading the entire file into memory. It manages
/// the ISO base media file format structure and updates metadata as frames are added.
///
/// The writer uses an actor to ensure thread-safe file operations.
actor MJ2StreamWriter {
    /// The output file URL.
    private let outputURL: URL

    /// File handle for writing.
    private var fileHandle: FileHandle?

    /// Current write position in the file.
    private var currentOffset: UInt64 = 0

    /// Sample table builder.
    private let sampleTableBuilder: MJ2SampleTableBuilder

    /// Configuration.
    private let configuration: MJ2CreationConfiguration

    /// Video track dimensions.
    private let width: Int
    private let height: Int

    /// Offset where mdat box begins.
    private var mdatOffset: UInt64 = 0

    /// Size of mdat box content (sum of all frame sizes).
    private var mdatSize: UInt64 = 0

    /// Whether the writer has been finalized.
    private var finalized = false

    /// Creates a new stream writer.
    ///
    /// - Parameters:
    ///   - outputURL: The URL where the MJ2 file will be written.
    ///   - width: Video frame width in pixels.
    ///   - height: Video frame height in pixels.
    ///   - configuration: MJ2 creation configuration.
    /// - Throws: ``J2KError`` if the file cannot be created.
    init(
        outputURL: URL,
        width: Int,
        height: Int,
        configuration: MJ2CreationConfiguration
    ) throws {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.configuration = configuration

        self.sampleTableBuilder = MJ2SampleTableBuilder(
            defaultDuration: configuration.timescale.frameDuration,
            use64BitOffsets: configuration.use64BitOffsets
        )

        // Validate configuration
        try configuration.validate(width: width, height: height)

        // Create the file
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        // Open for writing
        guard let handle = try? FileHandle(forWritingTo: outputURL) else {
            throw J2KError.internalError("Failed to open output file for writing")
        }
        self.fileHandle = handle

        // Write JP2 signature box (required for MJ2)
        var signatureData = Data()
        // Length (12 bytes total)
        signatureData.append(contentsOf: UInt32(12).bigEndianBytes)
        // Type ('jP  ')
        signatureData.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])
        // Content
        signatureData.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0A])
        try handle.write(contentsOf: signatureData)
        currentOffset = UInt64(signatureData.count)

        // Write ftyp box
        var data = Data()

        // Major brand
        let brand = configuration.profile.brandIdentifier
        data.append(contentsOf: brand.utf8.prefix(4).map { $0 })
        while data.count < 4 { data.append(0x20) } // Pad with spaces

        // Minor version
        data.append(contentsOf: [0, 0, 0, 0])

        // Compatible brands
        let brands = [brand, "mjp2", "jp2 "]
        for compatBrand in brands {
            data.append(contentsOf: compatBrand.utf8.prefix(4).map { $0 })
            while !data.count.isMultiple(of: 4) { data.append(0x20) }
        }

        // Write ftyp box
        var boxData = Data()
        let size = UInt32(8 + data.count)
        boxData.append(contentsOf: size.bigEndianBytes)
        boxData.append(contentsOf: J2KBoxType.ftyp.rawValue.bigEndianBytes)
        boxData.append(data)

        try handle.write(contentsOf: boxData)
        currentOffset = UInt64(boxData.count)

        // Prepare for mdat box (we'll write the header later)
        mdatOffset = currentOffset

        // Reserve space for mdat box header (16 bytes for extended size)
        let mdatHeaderSize: UInt64 = 16
        let placeholder = Data(count: Int(mdatHeaderSize))
        try handle.write(contentsOf: placeholder)
        currentOffset += mdatHeaderSize
    }

    /// Writes a frame to the file.
    ///
    /// - Parameters:
    ///   - frameData: The encoded JPEG 2000 codestream for this frame.
    ///   - isSync: Whether this is a sync sample (key frame).
    /// - Throws: ``J2KError`` if writing fails.
    func writeFrame(_ frameData: Data, isSync: Bool = true) async throws {
        guard !finalized else {
            throw J2KError.internalError("Cannot write frame after finalization")
        }

        // Record sample information
        let frameSize = UInt32(frameData.count)
        let frameOffset = currentOffset

        await sampleTableBuilder.addSample(
            size: frameSize,
            offset: frameOffset,
            isSync: isSync
        )

        // Write frame data
        try writeData(frameData)
        mdatSize += UInt64(frameData.count)
    }

    /// Returns the current frame count.
    var frameCount: Int {
        get async {
            await sampleTableBuilder.sampleCount
        }
    }

    /// Finalizes the file by writing the moov box.
    ///
    /// - Throws: ``J2KError`` if finalization fails.
    func finalize() async throws {
        guard !finalized else { return }
        finalized = true

        // Update mdat box header
        try updateMdatBoxHeader()

        // Build and write moov box
        try await writeMoovBox()

        // Close file
        try fileHandle?.synchronize()
        try fileHandle?.close()
        fileHandle = nil
    }

    /// Updates the mdat box header with the actual size.
    private func updateMdatBoxHeader() throws {
        guard let handle = fileHandle else {
            throw J2KError.internalError("File handle not available")
        }

        // Seek to mdat offset
        try handle.seek(toOffset: mdatOffset)

        // Write extended size format
        // Size = 1 indicates extended size
        var headerData = Data()
        headerData.append(contentsOf: UInt32(1).bigEndianBytes)  // size = 1
        headerData.append(contentsOf: J2KBoxType.mdat.rawValue.bigEndianBytes)    // type = 'mdat'

        // Extended size = header (16 bytes) + content
        let totalSize = 16 + mdatSize
        headerData.append(contentsOf: totalSize.bigEndianBytes)

        try handle.write(contentsOf: headerData)

        // Seek back to end
        try handle.seekToEnd()
    }

    /// Writes the movie box (moov) containing all metadata.
    private func writeMoovBox() async throws {
        var moovData = Data()

        // Movie header box (mvhd)
        moovData.append(try await buildMovieHeaderBox())

        // Track box (trak) - video track
        moovData.append(try await buildTrackBox())

        try writeBox(type: .moov, data: moovData)
    }

    /// Builds the movie header box (mvhd).
    private func buildMovieHeaderBox() async throws -> Data {
        let frameCount = await sampleTableBuilder.sampleCount
        let duration = UInt64(frameCount) * UInt64(configuration.timescale.frameDuration)

        let mvhd = MJ2MovieHeaderBox(
            creationTime: 0,  // Use 0 for simplicity (valid timestamp)
            modificationTime: 0,
            timescale: configuration.timescale.timescale,
            duration: duration,
            nextTrackID: 2
        )

        return try mvhd.write()
    }

    /// Builds the track box (trak) for the video track.
    private func buildTrackBox() async throws -> Data {
        var trakData = Data()

        // Track header (tkhd)
        trakData.append(try await buildTrackHeaderBox())

        // Media box (mdia)
        trakData.append(try await buildMediaBox())

        return wrapInBox(type: .trak, data: trakData)
    }

    /// Builds the track header box (tkhd).
    private func buildTrackHeaderBox() async throws -> Data {
        let frameCount = await sampleTableBuilder.sampleCount
        let duration = UInt64(frameCount) * UInt64(configuration.timescale.frameDuration)

        // Convert width/height to 16.16 fixed-point
        let widthFixed = UInt32(width) << 16
        let heightFixed = UInt32(height) << 16

        let tkhd = MJ2TrackHeaderBox(
            trackID: 1,
            creationTime: 0,
            modificationTime: 0,
            duration: duration,
            width: widthFixed,
            height: heightFixed
        )

        return try tkhd.write()
    }

    /// Builds the media box (mdia).
    private func buildMediaBox() async throws -> Data {
        var mdiaData = Data()

        // Media header (mdhd)
        mdiaData.append(try await buildMediaHeaderBox())

        // Handler reference (hdlr)
        mdiaData.append(buildHandlerBox())

        // Media information (minf)
        mdiaData.append(try await buildMediaInformationBox())

        return wrapInBox(type: .mdia, data: mdiaData)
    }

    /// Builds the media header box (mdhd).
    private func buildMediaHeaderBox() async throws -> Data {
        let frameCount = await sampleTableBuilder.sampleCount
        let duration = UInt64(frameCount) * UInt64(configuration.timescale.frameDuration)

        let mdhd = MJ2MediaHeaderBox(
            creationTime: 0,
            modificationTime: 0,
            timescale: configuration.timescale.timescale,
            duration: duration,
            language: "und"
        )

        return try mdhd.write()
    }

    /// Builds the handler reference box (hdlr).
    private func buildHandlerBox() -> Data {
        var data = Data()

        // Version and flags
        data.append(contentsOf: [0, 0, 0, 0])

        // Pre-defined
        data.append(contentsOf: [0, 0, 0, 0])

        // Handler type ('vide' for video)
        data.append(contentsOf: Array("vide".utf8))

        // Reserved
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        // Name (null-terminated string)
        let name = "JPEG 2000 Video Handler"
        data.append(contentsOf: name.utf8)
        data.append(0)

        return wrapInBox(type: .hdlr, data: data)
    }

    /// Builds the media information box (minf).
    private func buildMediaInformationBox() async throws -> Data {
        var minfData = Data()

        // Video media header (vmhd)
        minfData.append(buildVideoMediaHeaderBox())

        // Data information (dinf)
        minfData.append(buildDataInformationBox())

        // Sample table (stbl)
        minfData.append(try await buildSampleTableBox())

        return wrapInBox(type: .minf, data: minfData)
    }

    /// Builds the video media header box (vmhd).
    private func buildVideoMediaHeaderBox() -> Data {
        var data = Data()

        // Version and flags (flags = 1)
        data.append(contentsOf: [0, 0, 0, 1])

        // Graphics mode
        data.append(contentsOf: [0, 0])

        // Opcolor (R, G, B)
        data.append(contentsOf: [0, 0, 0, 0, 0, 0])

        return wrapInBox(type: .vmhd, data: data)
    }

    /// Builds the data information box (dinf).
    private func buildDataInformationBox() -> Data {
        var dinfData = Data()

        // Data reference box (dref)
        var drefData = Data()

        // Version and flags
        drefData.append(contentsOf: [0, 0, 0, 0])

        // Entry count (1)
        drefData.append(contentsOf: UInt32(1).bigEndianBytes)

        // URL entry (self-reference)
        var urlData = Data()
        // Version and flags (flags = 1 means data is in this file)
        urlData.append(contentsOf: [0, 0, 0, 1])
        drefData.append(wrapInBox(type: .urlMJ2, data: urlData))

        dinfData.append(wrapInBox(type: .dref, data: drefData))

        return wrapInBox(type: .dinf, data: dinfData)
    }

    /// Builds the sample table box (stbl).
    private func buildSampleTableBox() async throws -> Data {
        var stblData = Data()

        // Sample description (stsd)
        stblData.append(try buildSampleDescriptionBox())

        // Sample table boxes from builder
        let boxes = await sampleTableBuilder.buildAllBoxes()
        for box in boxes {
            stblData.append(box)
        }

        return wrapInBox(type: .stbl, data: stblData)
    }

    /// Builds the sample description box (stsd).
    private func buildSampleDescriptionBox() throws -> Data {
        // Create a minimal JP2 header for the sample entry
        // This is a placeholder - in production, should extract from first frame
        let sampleEntry = MJ2SampleEntry(
            width: UInt16(width),
            height: UInt16(height),
            depth: 24,
            jp2hData: nil  // Simplified for now
        )

        let stsd = MJ2SampleDescriptionBox(sampleEntry: sampleEntry)
        return try stsd.write()
    }

    /// Writes a box to the file.
    private func writeBox(type: J2KBoxType, data: Data) throws {
        let boxData = wrapInBox(type: type, data: data)
        try writeData(boxData)
    }

    /// Wraps data in a box.
    private func wrapInBox(type: J2KBoxType, data: Data) -> Data {
        var boxData = Data()

        // Box size (4 bytes) + box type (4 bytes) + data
        let size = UInt32(8 + data.count)
        boxData.append(contentsOf: size.bigEndianBytes)
        boxData.append(contentsOf: type.rawValue.bigEndianBytes)
        boxData.append(data)

        return boxData
    }

    /// Writes data to the file.
    private func writeData(_ data: Data) throws {
        guard let handle = fileHandle else {
            throw J2KError.internalError("File handle not available")
        }

        try handle.write(contentsOf: data)
        currentOffset += UInt64(data.count)
    }

    deinit {
        // Ensure file is closed
        try? fileHandle?.close()
    }
}
