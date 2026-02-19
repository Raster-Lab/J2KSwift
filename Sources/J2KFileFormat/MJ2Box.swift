/// # MJ2Box
///
/// ISO base media file format (ISO/IEC 14496-12) box structures for Motion JPEG 2000.
///
/// This module provides the box types required for Motion JPEG 2000 files,
/// which are based on the ISO base media file format used by MP4, MOV, and other
/// container formats.
///
/// ## Box Hierarchy
///
/// A typical MJ2 file has the following structure:
/// ```
/// - ftyp (file type)
/// - moov (movie)
///   - mvhd (movie header)
///   - trak (track)
///     - tkhd (track header)
///     - mdia (media)
///       - mdhd (media header)
///       - hdlr (handler)
///       - minf (media information)
///         - vmhd (video media header)
///         - dinf (data information)
///           - dref (data reference)
///         - stbl (sample table)
///           - stsd (sample description)
///           - stts (time-to-sample)
///           - stsc (sample-to-chunk)
///           - stsz (sample size)
///           - stco (chunk offset)
/// - mdat (media data)
/// ```

import Foundation
import J2KCore

// MARK: - Box Type Extensions

extension J2KBoxType {
    // MARK: - MJ2/ISO Base Media Format Box Types
    
    /// Movie box ('moov') - Container for all metadata
    public static let moov = J2KBoxType(string: "moov")
    
    /// Movie header box ('mvhd') - Overall movie information
    public static let mvhd = J2KBoxType(string: "mvhd")
    
    /// Track box ('trak') - Container for a single track
    public static let trak = J2KBoxType(string: "trak")
    
    /// Track header box ('tkhd') - Track-specific properties
    public static let tkhd = J2KBoxType(string: "tkhd")
    
    /// Media box ('mdia') - Container for media information
    public static let mdia = J2KBoxType(string: "mdia")
    
    /// Media header box ('mdhd') - Media-specific information
    public static let mdhd = J2KBoxType(string: "mdhd")
    
    /// Handler reference box ('hdlr') - Media type and handler
    public static let hdlr = J2KBoxType(string: "hdlr")
    
    /// Media information box ('minf') - Container for media-specific information
    public static let minf = J2KBoxType(string: "minf")
    
    /// Video media header box ('vmhd') - Video-specific properties
    public static let vmhd = J2KBoxType(string: "vmhd")
    
    /// Sound media header box ('smhd') - Audio-specific properties
    public static let smhd = J2KBoxType(string: "smhd")
    
    /// Data information box ('dinf') - Container for data reference
    public static let dinf = J2KBoxType(string: "dinf")
    
    /// Data reference box ('dref') - Data location information
    public static let dref = J2KBoxType(string: "dref")
    
    /// URL data entry box ('url ') - URL-based data reference (MJ2)
    public static let urlMJ2 = J2KBoxType(string: "url ")
    
    /// Sample table box ('stbl') - Container for sample information
    public static let stbl = J2KBoxType(string: "stbl")
    
    /// Sample description box ('stsd') - Sample format descriptions
    public static let stsd = J2KBoxType(string: "stsd")
    
    /// Time-to-sample box ('stts') - Time-to-sample mapping
    public static let stts = J2KBoxType(string: "stts")
    
    /// Sample-to-chunk box ('stsc') - Sample-to-chunk mapping
    public static let stsc = J2KBoxType(string: "stsc")
    
    /// Sample size box ('stsz') - Sample sizes
    public static let stsz = J2KBoxType(string: "stsz")
    
    /// Chunk offset box ('stco') - 32-bit chunk offsets
    public static let stco = J2KBoxType(string: "stco")
    
    /// Chunk offset 64 box ('co64') - 64-bit chunk offsets
    public static let co64 = J2KBoxType(string: "co64")
    
    /// Sync sample box ('stss') - Random access points (keyframes)
    public static let stss = J2KBoxType(string: "stss")
    
    /// Media data box ('mdat') - Container for actual media samples
    public static let mdat = J2KBoxType(string: "mdat")
    
    /// User data box ('udta') - User-defined metadata
    public static let udta = J2KBoxType(string: "udta")
    
    /// JPEG 2000 sample entry ('mjp2') - MJ2-specific sample description
    public static let mjp2 = J2KBoxType(string: "mjp2")
    
    /// JPEG 2000 header box ('jp2h') - JPEG 2000 header in sample entry
    public static let jp2h_mj2 = J2KBoxType(string: "jp2h")
}

// MARK: - Movie Header Box

/// Movie header box (mvhd).
///
/// Contains overall information about the movie including creation time,
/// modification time, timescale, and duration.
///
/// ## Box Structure
///
/// Version 0 (32-bit):
/// - Creation time (4 bytes)
/// - Modification time (4 bytes)
/// - Timescale (4 bytes)
/// - Duration (4 bytes)
/// - Rate (4 bytes) - typically 0x00010000 (1.0)
/// - Volume (2 bytes) - typically 0x0100 (full volume)
/// - Reserved (10 bytes)
/// - Matrix (36 bytes) - transformation matrix
/// - Pre-defined (24 bytes)
/// - Next track ID (4 bytes)
///
/// Version 1 (64-bit):
/// - Creation time (8 bytes)
/// - Modification time (8 bytes)
/// - Timescale (4 bytes)
/// - Duration (8 bytes)
/// - Rate, volume, matrix, etc. (same as version 0)
public struct MJ2MovieHeaderBox: J2KBox {
    public var boxType: J2KBoxType { .mvhd }
    
    /// Version (0 for 32-bit times, 1 for 64-bit times)
    public var version: UInt8
    
    /// Flags (always 0)
    public var flags: UInt32
    
    /// Creation time (seconds since midnight, Jan. 1, 1904, UTC)
    public var creationTime: UInt64
    
    /// Modification time (seconds since midnight, Jan. 1, 1904, UTC)
    public var modificationTime: UInt64
    
    /// Time scale (number of time units per second)
    public var timescale: UInt32
    
    /// Duration (in timescale units)
    public var duration: UInt64
    
    /// Preferred playback rate (1.0 = normal, typically 0x00010000)
    public var rate: Int32
    
    /// Preferred playback volume (1.0 = full, typically 0x0100)
    public var volume: Int16
    
    /// Transformation matrix for video (3x3 matrix stored as 9 values)
    public var matrix: [Int32]
    
    /// Next available track ID
    public var nextTrackID: UInt32
    
    /// Creates a movie header with the given parameters.
    ///
    /// - Parameters:
    ///   - creationTime: Creation timestamp
    ///   - modificationTime: Modification timestamp
    ///   - timescale: Time scale (units per second)
    ///   - duration: Duration in timescale units
    ///   - nextTrackID: Next available track ID
    public init(
        creationTime: UInt64 = 0,
        modificationTime: UInt64 = 0,
        timescale: UInt32,
        duration: UInt64,
        nextTrackID: UInt32 = 1
    ) {
        // Use version 1 if timestamps exceed 32-bit range
        self.version = (creationTime > UInt32.max || modificationTime > UInt32.max) ? 1 : 0
        self.flags = 0
        self.creationTime = creationTime
        self.modificationTime = modificationTime
        self.timescale = timescale
        self.duration = duration
        self.rate = 0x00010000 // 1.0
        self.volume = 0x0100 // Full volume
        // Identity matrix
        self.matrix = [
            0x00010000, 0, 0,
            0, 0x00010000, 0,
            0, 0, 0x40000000
        ]
        self.nextTrackID = nextTrackID
    }
    
    public func write() throws -> Data {
        var data = Data()
        
        // Version and flags
        data.append(version)
        data.append(UInt8((flags >> 16) & 0xFF))
        data.append(UInt8((flags >> 8) & 0xFF))
        data.append(UInt8(flags & 0xFF))
        
        if version == 1 {
            // 64-bit times
            data.append(contentsOf: creationTime.bigEndianBytes)
            data.append(contentsOf: modificationTime.bigEndianBytes)
            data.append(contentsOf: timescale.bigEndianBytes)
            data.append(contentsOf: duration.bigEndianBytes)
        } else {
            // 32-bit times
            data.append(contentsOf: UInt32(creationTime).bigEndianBytes)
            data.append(contentsOf: UInt32(modificationTime).bigEndianBytes)
            data.append(contentsOf: timescale.bigEndianBytes)
            data.append(contentsOf: UInt32(duration).bigEndianBytes)
        }
        
        // Rate and volume
        data.append(contentsOf: rate.bigEndianBytes)
        data.append(contentsOf: volume.bigEndianBytes)
        
        // Reserved (10 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 10))
        
        // Matrix (36 bytes)
        for value in matrix {
            data.append(contentsOf: value.bigEndianBytes)
        }
        
        // Pre-defined (24 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 24))
        
        // Next track ID
        data.append(contentsOf: nextTrackID.bigEndianBytes)
        
        return data
    }
    
    public mutating func read(from data: Data) throws {
        guard data.count >= 100 else {
            throw J2KError.fileFormatError("Invalid mvhd box: too small")
        }
        
        var offset = 0
        
        // Version and flags
        version = data[offset]
        offset += 1
        flags = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
        offset += 3
        
        if version == 1 {
            creationTime = data.readUInt64(at: offset)
            offset += 8
            modificationTime = data.readUInt64(at: offset)
            offset += 8
            timescale = data.readUInt32(at: offset)
            offset += 4
            duration = data.readUInt64(at: offset)
            offset += 8
        } else {
            creationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            modificationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            timescale = data.readUInt32(at: offset)
            offset += 4
            duration = UInt64(data.readUInt32(at: offset))
            offset += 4
        }
        
        rate = data.readInt32(at: offset)
        offset += 4
        volume = data.readInt16(at: offset)
        offset += 2
        
        // Skip reserved (10 bytes)
        offset += 10
        
        // Read matrix
        matrix = []
        for _ in 0..<9 {
            matrix.append(data.readInt32(at: offset))
            offset += 4
        }
        
        // Skip pre-defined (24 bytes)
        offset += 24
        
        nextTrackID = data.readUInt32(at: offset)
    }
}

// MARK: - Track Header Box

/// Track header box (tkhd).
///
/// Contains properties of a single track, including dimensions, position,
/// and volume. For video tracks in MJ2, this specifies the video dimensions.
public struct MJ2TrackHeaderBox: J2KBox {
    public var boxType: J2KBoxType { .tkhd }
    
    /// Version (0 for 32-bit times, 1 for 64-bit times)
    public var version: UInt8
    
    /// Flags (bit 0 = track enabled, bit 1 = track in movie, bit 2 = track in preview)
    public var flags: UInt32
    
    /// Creation time
    public var creationTime: UInt64
    
    /// Modification time
    public var modificationTime: UInt64
    
    /// Track ID (unique identifier)
    public var trackID: UInt32
    
    /// Duration (in movie timescale units)
    public var duration: UInt64
    
    /// Layer (front-to-back ordering, 0 = normal)
    public var layer: Int16
    
    /// Alternate group (0 = no alternates)
    public var alternateGroup: Int16
    
    /// Volume (for audio tracks)
    public var volume: Int16
    
    /// Transformation matrix
    public var matrix: [Int32]
    
    /// Width (16.16 fixed-point)
    public var width: UInt32
    
    /// Height (16.16 fixed-point)
    public var height: UInt32
    
    /// Creates a track header for a video track.
    ///
    /// - Parameters:
    ///   - trackID: Unique track identifier
    ///   - creationTime: Creation timestamp
    ///   - modificationTime: Modification timestamp
    ///   - duration: Track duration in movie timescale
    ///   - width: Video width in pixels
    ///   - height: Video height in pixels
    public init(
        trackID: UInt32,
        creationTime: UInt64 = 0,
        modificationTime: UInt64 = 0,
        duration: UInt64,
        width: UInt32,
        height: UInt32
    ) {
        self.version = (creationTime > UInt32.max || modificationTime > UInt32.max) ? 1 : 0
        self.flags = 0x000007 // Track enabled, in movie, in preview
        self.creationTime = creationTime
        self.modificationTime = modificationTime
        self.trackID = trackID
        self.duration = duration
        self.layer = 0
        self.alternateGroup = 0
        self.volume = 0 // Not used for video
        // Identity matrix
        self.matrix = [
            0x00010000, 0, 0,
            0, 0x00010000, 0,
            0, 0, 0x40000000
        ]
        // Convert to 16.16 fixed-point
        self.width = width << 16
        self.height = height << 16
    }
    
    public func write() throws -> Data {
        var data = Data()
        
        // Version and flags
        data.append(version)
        data.append(UInt8((flags >> 16) & 0xFF))
        data.append(UInt8((flags >> 8) & 0xFF))
        data.append(UInt8(flags & 0xFF))
        
        if version == 1 {
            // 64-bit times
            data.append(contentsOf: creationTime.bigEndianBytes)
            data.append(contentsOf: modificationTime.bigEndianBytes)
            data.append(contentsOf: trackID.bigEndianBytes)
            data.append(contentsOf: UInt32(0).bigEndianBytes) // Reserved
            data.append(contentsOf: duration.bigEndianBytes)
        } else {
            // 32-bit times
            data.append(contentsOf: UInt32(creationTime).bigEndianBytes)
            data.append(contentsOf: UInt32(modificationTime).bigEndianBytes)
            data.append(contentsOf: trackID.bigEndianBytes)
            data.append(contentsOf: UInt32(0).bigEndianBytes) // Reserved
            data.append(contentsOf: UInt32(duration).bigEndianBytes)
        }
        
        // Reserved (8 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        
        // Layer and alternate group
        data.append(contentsOf: layer.bigEndianBytes)
        data.append(contentsOf: alternateGroup.bigEndianBytes)
        
        // Volume
        data.append(contentsOf: volume.bigEndianBytes)
        
        // Reserved (2 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 2))
        
        // Matrix (36 bytes)
        for value in matrix {
            data.append(contentsOf: value.bigEndianBytes)
        }
        
        // Width and height
        data.append(contentsOf: width.bigEndianBytes)
        data.append(contentsOf: height.bigEndianBytes)
        
        return data
    }
    
    public mutating func read(from data: Data) throws {
        guard data.count >= 84 else {
            throw J2KError.fileFormatError("Invalid tkhd box: too small")
        }
        
        var offset = 0
        
        // Version and flags
        version = data[offset]
        offset += 1
        flags = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
        offset += 3
        
        if version == 1 {
            creationTime = data.readUInt64(at: offset)
            offset += 8
            modificationTime = data.readUInt64(at: offset)
            offset += 8
            trackID = data.readUInt32(at: offset)
            offset += 4
            offset += 4 // Skip reserved
            duration = data.readUInt64(at: offset)
            offset += 8
        } else {
            creationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            modificationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            trackID = data.readUInt32(at: offset)
            offset += 4
            offset += 4 // Skip reserved
            duration = UInt64(data.readUInt32(at: offset))
            offset += 4
        }
        
        // Skip reserved (8 bytes)
        offset += 8
        
        layer = data.readInt16(at: offset)
        offset += 2
        alternateGroup = data.readInt16(at: offset)
        offset += 2
        volume = data.readInt16(at: offset)
        offset += 2
        
        // Skip reserved (2 bytes)
        offset += 2
        
        // Read matrix
        matrix = []
        for _ in 0..<9 {
            matrix.append(data.readInt32(at: offset))
            offset += 4
        }
        
        width = data.readUInt32(at: offset)
        offset += 4
        height = data.readUInt32(at: offset)
    }
}

// MARK: - Media Header Box

/// Media header box (mdhd).
///
/// Contains media-specific timing information including creation time,
/// modification time, timescale, and duration.
public struct MJ2MediaHeaderBox: J2KBox {
    public var boxType: J2KBoxType { .mdhd }
    
    /// Version (0 for 32-bit times, 1 for 64-bit times)
    public var version: UInt8
    
    /// Flags (always 0)
    public var flags: UInt32
    
    /// Creation time
    public var creationTime: UInt64
    
    /// Modification time
    public var modificationTime: UInt64
    
    /// Media timescale (time units per second)
    public var timescale: UInt32
    
    /// Duration (in timescale units)
    public var duration: UInt64
    
    /// Language code (ISO 639-2/T language code)
    public var language: UInt16
    
    /// Creates a media header with the given parameters.
    ///
    /// - Parameters:
    ///   - creationTime: Creation timestamp
    ///   - modificationTime: Modification timestamp
    ///   - timescale: Time scale (units per second)
    ///   - duration: Duration in timescale units
    ///   - language: ISO 639-2/T language code (default: 'und' for undefined)
    public init(
        creationTime: UInt64 = 0,
        modificationTime: UInt64 = 0,
        timescale: UInt32,
        duration: UInt64,
        language: String = "und"
    ) {
        self.version = (creationTime > UInt32.max || modificationTime > UInt32.max) ? 1 : 0
        self.flags = 0
        self.creationTime = creationTime
        self.modificationTime = modificationTime
        self.timescale = timescale
        self.duration = duration
        
        // Convert 3-letter language code to packed ISO 639-2/T format
        // Each character is packed as 5 bits (a=1, b=2, ..., z=26)
        var code: UInt16 = 0
        let chars = Array(language.lowercased().prefix(3))
        for (i, char) in chars.enumerated() {
            if let ascii = char.asciiValue, ascii >= 97 && ascii <= 122 {
                let value = UInt16(ascii - 96) // a=1, b=2, ..., z=26
                code |= value << (10 - i * 5)
            }
        }
        self.language = code
    }
    
    public func write() throws -> Data {
        var data = Data()
        
        // Version and flags
        data.append(version)
        data.append(UInt8((flags >> 16) & 0xFF))
        data.append(UInt8((flags >> 8) & 0xFF))
        data.append(UInt8(flags & 0xFF))
        
        if version == 1 {
            // 64-bit times
            data.append(contentsOf: creationTime.bigEndianBytes)
            data.append(contentsOf: modificationTime.bigEndianBytes)
            data.append(contentsOf: timescale.bigEndianBytes)
            data.append(contentsOf: duration.bigEndianBytes)
        } else {
            // 32-bit times
            data.append(contentsOf: UInt32(creationTime).bigEndianBytes)
            data.append(contentsOf: UInt32(modificationTime).bigEndianBytes)
            data.append(contentsOf: timescale.bigEndianBytes)
            data.append(contentsOf: UInt32(duration).bigEndianBytes)
        }
        
        // Language
        data.append(contentsOf: language.bigEndianBytes)
        
        // Pre-defined (2 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 2))
        
        return data
    }
    
    public mutating func read(from data: Data) throws {
        guard data.count >= 24 else {
            throw J2KError.fileFormatError("Invalid mdhd box: too small")
        }
        
        var offset = 0
        
        // Version and flags
        version = data[offset]
        offset += 1
        flags = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
        offset += 3
        
        if version == 1 {
            creationTime = data.readUInt64(at: offset)
            offset += 8
            modificationTime = data.readUInt64(at: offset)
            offset += 8
            timescale = data.readUInt32(at: offset)
            offset += 4
            duration = data.readUInt64(at: offset)
            offset += 8
        } else {
            creationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            modificationTime = UInt64(data.readUInt32(at: offset))
            offset += 4
            timescale = data.readUInt32(at: offset)
            offset += 4
            duration = UInt64(data.readUInt32(at: offset))
            offset += 4
        }
        
        language = data.readUInt16(at: offset)
    }
}

// MARK: - Sample Description Box

/// Sample description box (stsd).
///
/// Contains descriptions of the sample formats used in the track.
/// For MJ2, this contains JPEG 2000-specific sample descriptions.
public struct MJ2SampleDescriptionBox: J2KBox {
    public var boxType: J2KBoxType { .stsd }
    
    /// Version (always 0)
    public var version: UInt8
    
    /// Flags (always 0)
    public var flags: UInt32
    
    /// Sample entry for JPEG 2000 video
    public var sampleEntry: MJ2SampleEntry
    
    /// Creates a sample description box with a JPEG 2000 sample entry.
    ///
    /// - Parameter sampleEntry: The JPEG 2000 sample entry
    public init(sampleEntry: MJ2SampleEntry) {
        self.version = 0
        self.flags = 0
        self.sampleEntry = sampleEntry
    }
    
    public func write() throws -> Data {
        var data = Data()
        
        // Version and flags
        data.append(version)
        data.append(UInt8((flags >> 16) & 0xFF))
        data.append(UInt8((flags >> 8) & 0xFF))
        data.append(UInt8(flags & 0xFF))
        
        // Entry count (always 1 for MJ2)
        data.append(contentsOf: UInt32(1).bigEndianBytes)
        
        // Sample entry
        let entryData = try sampleEntry.write()
        data.append(entryData)
        
        return data
    }
    
    public mutating func read(from data: Data) throws {
        guard data.count >= 8 else {
            throw J2KError.fileFormatError("Invalid stsd box: too small")
        }
        
        var offset = 0
        
        // Version and flags
        version = data[offset]
        offset += 1
        flags = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
        offset += 3
        
        // Entry count
        let entryCount = data.readUInt32(at: offset)
        offset += 4
        
        guard entryCount >= 1 else {
            throw J2KError.fileFormatError("Invalid stsd box: no entries")
        }
        
        // Read first sample entry
        let entryData = data.subdata(in: offset..<data.count)
        try sampleEntry.read(from: entryData)
    }
}

// MARK: - MJ2 Sample Entry

/// JPEG 2000 sample entry for MJ2 files.
///
/// Describes the format of JPEG 2000 video samples in an MJ2 track.
public struct MJ2SampleEntry: Sendable {
    /// Sample entry type (always 'mjp2')
    public var format: J2KBoxType = .mjp2
    
    /// Width of video frames
    public var width: UInt16
    
    /// Height of video frames
    public var height: UInt16
    
    /// Horizontal resolution (pixels per inch, 16.16 fixed-point, typically 72 dpi)
    public var horizontalResolution: UInt32
    
    /// Vertical resolution (pixels per inch, 16.16 fixed-point, typically 72 dpi)
    public var verticalResolution: UInt32
    
    /// Frame count (always 1 for video)
    public var frameCount: UInt16
    
    /// Compressor name (32 bytes, Pascal string)
    public var compressorName: String
    
    /// Bit depth (typically 24 for RGB)
    public var depth: UInt16
    
    /// JPEG 2000 header boxes (jp2h containing ihdr, colr, etc.)
    public var jp2hData: Data?
    
    /// Creates a JPEG 2000 sample entry.
    ///
    /// - Parameters:
    ///   - width: Frame width
    ///   - height: Frame height
    ///   - depth: Bit depth (default: 24)
    ///   - jp2hData: Optional JPEG 2000 header data
    public init(
        width: UInt16,
        height: UInt16,
        depth: UInt16 = 24,
        jp2hData: Data? = nil
    ) {
        self.width = width
        self.height = height
        self.horizontalResolution = 0x00480000 // 72 dpi in 16.16 fixed-point
        self.verticalResolution = 0x00480000
        self.frameCount = 1
        self.compressorName = "Motion JPEG 2000"
        self.depth = depth
        self.jp2hData = jp2hData
    }
    
    /// Writes the sample entry to binary data.
    ///
    /// - Returns: The serialized sample entry data.
    /// - Throws: ``J2KError`` if writing fails.
    public func write() throws -> Data {
        var data = Data()
        
        // Size placeholder (will be calculated at end)
        let sizeOffset = data.count
        data.append(contentsOf: UInt32(0).bigEndianBytes)
        
        // Format ('mjp2')
        data.append(contentsOf: format.rawValue.bigEndianBytes)
        
        // Reserved (6 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 6))
        
        // Data reference index (always 1)
        data.append(contentsOf: UInt16(1).bigEndianBytes)
        
        // Pre-defined (16 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        
        // Width and height
        data.append(contentsOf: width.bigEndianBytes)
        data.append(contentsOf: height.bigEndianBytes)
        
        // Resolutions
        data.append(contentsOf: horizontalResolution.bigEndianBytes)
        data.append(contentsOf: verticalResolution.bigEndianBytes)
        
        // Reserved (4 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 4))
        
        // Frame count
        data.append(contentsOf: frameCount.bigEndianBytes)
        
        // Compressor name (32 bytes, Pascal string format)
        var nameBytes = [UInt8](repeating: 0, count: 32)
        let name = compressorName.prefix(31)
        nameBytes[0] = UInt8(name.count)
        for (i, byte) in name.utf8.enumerated() {
            nameBytes[i + 1] = byte
        }
        data.append(contentsOf: nameBytes)
        
        // Depth
        data.append(contentsOf: depth.bigEndianBytes)
        
        // Pre-defined (2 bytes, color table ID = -1)
        data.append(contentsOf: UInt16(0xFFFF).bigEndianBytes)
        
        // JP2 header box (if present)
        if let jp2hData = jp2hData {
            // Write jp2h box
            let jp2hSize = UInt32(8 + jp2hData.count)
            data.append(contentsOf: jp2hSize.bigEndianBytes)
            data.append(contentsOf: J2KBoxType.jp2h.rawValue.bigEndianBytes)
            data.append(jp2hData)
        }
        
        // Update size
        let totalSize = UInt32(data.count)
        data.replaceSubrange(sizeOffset..<(sizeOffset + 4), with: totalSize.bigEndianBytes)
        
        return data
    }
    
    /// Reads the sample entry from binary data.
    ///
    /// - Parameter data: The sample entry data.
    /// - Throws: ``J2KError`` if parsing fails.
    public mutating func read(from data: Data) throws {
        guard data.count >= 86 else {
            throw J2KError.fileFormatError("Invalid sample entry: too small")
        }
        
        var offset = 0
        
        // Size
        let size = data.readUInt32(at: offset)
        offset += 4
        
        // Format
        format = J2KBoxType(rawValue: data.readUInt32(at: offset))
        offset += 4
        
        guard format == .mjp2 else {
            throw J2KError.fileFormatError("Invalid sample entry format: expected 'mjp2', got '\(format.stringValue)'")
        }
        
        // Skip reserved and data reference index (8 bytes)
        offset += 8
        
        // Skip pre-defined (16 bytes)
        offset += 16
        
        // Width and height
        width = data.readUInt16(at: offset)
        offset += 2
        height = data.readUInt16(at: offset)
        offset += 2
        
        // Resolutions
        horizontalResolution = data.readUInt32(at: offset)
        offset += 4
        verticalResolution = data.readUInt32(at: offset)
        offset += 4
        
        // Skip reserved (4 bytes)
        offset += 4
        
        // Frame count
        frameCount = data.readUInt16(at: offset)
        offset += 2
        
        // Compressor name (32 bytes, Pascal string)
        let nameLength = Int(data[offset])
        offset += 1
        if nameLength > 0 && nameLength <= 31 {
            let nameData = data.subdata(in: offset..<(offset + nameLength))
            compressorName = String(data: nameData, encoding: .utf8) ?? ""
        }
        offset += 31 // Skip rest of name field
        
        // Depth
        depth = data.readUInt16(at: offset)
        offset += 2
        
        // Skip color table ID (2 bytes)
        offset += 2
        
        // Read jp2h box if present
        if offset < Int(size) {
            let remainingData = data.subdata(in: offset..<Int(size))
            if remainingData.count >= 8 {
                let boxSize = remainingData.readUInt32(at: 0)
                let boxType = J2KBoxType(rawValue: remainingData.readUInt32(at: 4))
                if boxType == .jp2h && boxSize > 8 {
                    jp2hData = remainingData.subdata(in: 8..<Int(boxSize))
                }
            }
        }
    }
}

// MARK: - Data Extensions

extension Data {
    /// Reads a UInt16 value at the specified offset in big-endian format.
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
    
    /// Reads a UInt32 value at the specified offset in big-endian format.
    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 |
        UInt32(self[offset + 1]) << 16 |
        UInt32(self[offset + 2]) << 8 |
        UInt32(self[offset + 3])
    }
    
    /// Reads a UInt64 value at the specified offset in big-endian format.
    func readUInt64(at offset: Int) -> UInt64 {
        UInt64(self[offset]) << 56 |
        UInt64(self[offset + 1]) << 48 |
        UInt64(self[offset + 2]) << 40 |
        UInt64(self[offset + 3]) << 32 |
        UInt64(self[offset + 4]) << 24 |
        UInt64(self[offset + 5]) << 16 |
        UInt64(self[offset + 6]) << 8 |
        UInt64(self[offset + 7])
    }
    
    /// Reads an Int16 value at the specified offset in big-endian format.
    func readInt16(at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(at: offset))
    }
    
    /// Reads an Int32 value at the specified offset in big-endian format.
    func readInt32(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(at: offset))
    }
}

// MARK: - Integer Extensions

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

extension UInt64 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 56) & 0xFF),
            UInt8((self >> 48) & 0xFF),
            UInt8((self >> 40) & 0xFF),
            UInt8((self >> 32) & 0xFF),
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

extension Int16 {
    var bigEndianBytes: [UInt8] {
        UInt16(bitPattern: self).bigEndianBytes
    }
}

extension Int32 {
    var bigEndianBytes: [UInt8] {
        UInt32(bitPattern: self).bigEndianBytes
    }
}
