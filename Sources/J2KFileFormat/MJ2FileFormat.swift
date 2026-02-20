//
// MJ2FileFormat.swift
// J2KSwift
//
/// # MJ2FileFormat
///
/// Motion JPEG 2000 (MJ2) file format support.
///
/// This module implements Motion JPEG 2000 (ISO/IEC 15444-3) file format
/// based on the ISO base media file format (ISO/IEC 14496-12). MJ2 extends
/// JPEG 2000 to support motion sequences with frame-level access.
///
/// ## File Structure
///
/// An MJ2 file consists of boxes (atoms) organized in a hierarchical structure:
/// - File type box (ftyp) - Identifies the file as MJ2
/// - Movie box (moov) - Contains all metadata
/// - Media data box (mdat) - Contains JPEG 2000 codestreams
///
/// ## Topics
///
/// ### File Format Detection
/// - ``MJ2Format``
/// - ``MJ2FormatDetector``
///
/// ### File Parsing
/// - ``MJ2FileReader``
/// - ``MJ2FileInfo``
/// - ``MJ2TrackInfo``

import Foundation
import J2KCore

// MARK: - Format Detection

/// MJ2 format types and brands.
public enum MJ2Format: String, Sendable {
    /// Motion JPEG 2000 Simple Profile
    case mj2s

    /// Motion JPEG 2000 General Profile
    case mj2

    /// Returns the brand identifier for this format.
    public var brandIdentifier: String {
        switch self {
        case .mj2s: return "mj2s"
        case .mj2: return "mjp2"
        }
    }

    /// Returns the file extension for this format.
    public var fileExtension: String {
        "mj2"
    }

    /// Returns the MIME type for this format.
    public var mimeType: String {
        "video/mj2"
    }
}

/// Detects Motion JPEG 2000 file format.
///
/// `MJ2FormatDetector` examines file signatures and box structures to determine
/// if a file is a valid Motion JPEG 2000 file.
///
/// ## Detection Process
///
/// 1. Verify JP2 signature box (same as JP2)
/// 2. Check file type box for MJ2 brand ('mjp2' or 'mj2s')
/// 3. Validate movie box structure
///
/// Example:
/// ```swift
/// let detector = MJ2FormatDetector()
/// if try detector.isMJ2File(data: fileData) {
///     print("Valid MJ2 file")
/// }
/// ```
public struct MJ2FormatDetector: Sendable {
    /// Creates a new MJ2 format detector.
    public init() {}

    /// Determines if the given data represents a valid MJ2 file.
    ///
    /// - Parameter data: The file data to examine.
    /// - Returns: `true` if the data is a valid MJ2 file.
    /// - Throws: ``J2KError`` if the data cannot be examined.
    public func isMJ2File(data: Data) throws -> Bool {
        guard data.count >= 20 else {
            return false
        }

        // Check JP2 signature (first 12 bytes)
        guard data.count >= 12 else {
            return false
        }

        let signatureLength = data.readUInt32(at: 0)
        guard signatureLength == 12 else {
            return false
        }

        let signatureType = String(data: data.subdata(in: 4..<8), encoding: .ascii)
        guard signatureType == "jP  " else {
            return false
        }

        let signatureContent: [UInt8] = [0x0D, 0x0A, 0x87, 0x0A]
        guard data[8..<12].elementsEqual(signatureContent) else {
            return false
        }

        // Check file type box for MJ2 brand
        var offset = 12
        guard offset + 8 <= data.count else {
            return false
        }

        _ = data.readUInt32(at: offset) // ftypLength not used
        let ftypType = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii)

        guard ftypType == "ftyp" else {
            return false
        }

        offset += 8
        guard offset + 4 <= data.count else {
            return false
        }

        let brand = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii)
        return brand == "mjp2" || brand == "mj2s"
    }

    /// Detects the specific MJ2 format variant.
    ///
    /// - Parameter data: The file data to examine.
    /// - Returns: The detected MJ2 format.
    /// - Throws: ``J2KError`` if the file is not a valid MJ2 file.
    public func detectFormat(data: Data) throws -> MJ2Format {
        guard try isMJ2File(data: data) else {
            throw J2KError.fileFormatError("Not a valid MJ2 file")
        }

        // Read brand from ftyp box (at offset 20)
        guard data.count >= 24 else {
            throw J2KError.fileFormatError("MJ2 file too small")
        }

        let brand = String(data: data.subdata(in: 20..<24), encoding: .ascii)

        if brand == "mj2s" {
            return .mj2s
        } else {
            return .mj2
        }
    }
}

// MARK: - File Information

/// Information about an MJ2 file.
///
/// Contains metadata and structural information extracted from an MJ2 file.
public struct MJ2FileInfo: Sendable {
    /// MJ2 format variant
    public var format: MJ2Format

    /// Movie creation time (seconds since Jan. 1, 1904 UTC)
    public var creationTime: UInt64

    /// Movie modification time (seconds since Jan. 1, 1904 UTC)
    public var modificationTime: UInt64

    /// Movie timescale (time units per second)
    public var timescale: UInt32

    /// Movie duration (in timescale units)
    public var duration: UInt64

    /// Duration in seconds
    public var durationSeconds: Double {
        Double(duration) / Double(timescale)
    }

    /// List of tracks in the file
    public var tracks: [MJ2TrackInfo]

    /// Video tracks only
    public var videoTracks: [MJ2TrackInfo] {
        tracks.filter { $0.isVideo }
    }

    /// Creates file information with the given parameters.
    ///
    /// - Parameters:
    ///   - format: MJ2 format variant
    ///   - creationTime: Creation timestamp
    ///   - modificationTime: Modification timestamp
    ///   - timescale: Time scale
    ///   - duration: Duration in timescale units
    ///   - tracks: List of tracks
    public init(
        format: MJ2Format,
        creationTime: UInt64,
        modificationTime: UInt64,
        timescale: UInt32,
        duration: UInt64,
        tracks: [MJ2TrackInfo]
    ) {
        self.format = format
        self.creationTime = creationTime
        self.modificationTime = modificationTime
        self.timescale = timescale
        self.duration = duration
        self.tracks = tracks
    }
}

/// Information about an MJ2 track.
///
/// Contains metadata about a single track in an MJ2 file.
public struct MJ2TrackInfo: Sendable {
    /// Track ID (unique identifier)
    public var trackID: UInt32

    /// Track creation time
    public var creationTime: UInt64

    /// Track modification time
    public var modificationTime: UInt64

    /// Track duration (in movie timescale units)
    public var duration: UInt64

    /// Track width (pixels)
    public var width: UInt32

    /// Track height (pixels)
    public var height: UInt32

    /// Media timescale (time units per second)
    public var mediaTimescale: UInt32

    /// Media duration (in media timescale units)
    public var mediaDuration: UInt64

    /// Number of samples (frames) in the track
    public var sampleCount: Int

    /// Language code
    public var language: String

    /// Whether this is a video track
    public var isVideo: Bool

    /// Frame rate (frames per second)
    public var frameRate: Double {
        guard mediaDuration > 0 else { return 0 }
        return Double(sampleCount) * Double(mediaTimescale) / Double(mediaDuration)
    }

    /// Creates track information with the given parameters.
    ///
    /// - Parameters:
    ///   - trackID: Track identifier
    ///   - creationTime: Creation timestamp
    ///   - modificationTime: Modification timestamp
    ///   - duration: Duration in movie timescale
    ///   - width: Video width
    ///   - height: Video height
    ///   - mediaTimescale: Media time scale
    ///   - mediaDuration: Media duration
    ///   - sampleCount: Number of frames
    ///   - language: Language code
    ///   - isVideo: Whether this is a video track
    public init(
        trackID: UInt32,
        creationTime: UInt64,
        modificationTime: UInt64,
        duration: UInt64,
        width: UInt32,
        height: UInt32,
        mediaTimescale: UInt32,
        mediaDuration: UInt64,
        sampleCount: Int,
        language: String,
        isVideo: Bool
    ) {
        self.trackID = trackID
        self.creationTime = creationTime
        self.modificationTime = modificationTime
        self.duration = duration
        self.width = width
        self.height = height
        self.mediaTimescale = mediaTimescale
        self.mediaDuration = mediaDuration
        self.sampleCount = sampleCount
        self.language = language
        self.isVideo = isVideo
    }
}

// MARK: - File Reader

/// Reader for Motion JPEG 2000 files.
///
/// `MJ2FileReader` provides methods for reading and parsing MJ2 files,
/// extracting metadata, and accessing individual frames.
///
/// Example:
/// ```swift
/// let reader = MJ2FileReader()
/// let fileInfo = try await reader.readFileInfo(from: fileData)
/// print("Duration: \(fileInfo.durationSeconds) seconds")
/// print("Frame rate: \(fileInfo.videoTracks.first?.frameRate ?? 0) fps")
/// ```
public actor MJ2FileReader {
    /// Creates a new MJ2 file reader.
    public init() {}

    /// Reads file information from MJ2 data.
    ///
    /// This method parses the file structure and extracts metadata without
    /// reading the actual frame data.
    ///
    /// - Parameter data: The MJ2 file data.
    /// - Returns: Information about the MJ2 file.
    /// - Throws: ``J2KError`` if the file cannot be parsed.
    public func readFileInfo(from data: Data) throws -> MJ2FileInfo {
        // Detect format
        let detector = MJ2FormatDetector()
        let format = try detector.detectFormat(data: data)

        // Find and parse movie box
        var creationTime: UInt64 = 0
        var modificationTime: UInt64 = 0
        var timescale: UInt32 = 1
        var duration: UInt64 = 0
        var tracks: [MJ2TrackInfo] = []

        // Iterate through top-level boxes
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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .moov {
                // Parse movie box
                let movieInfo = try parseMovieBox(data: boxData)
                creationTime = movieInfo.creationTime
                modificationTime = movieInfo.modificationTime
                timescale = movieInfo.timescale
                duration = movieInfo.duration
                tracks = movieInfo.tracks
                break
            }

            offset += boxLength
        }

        return MJ2FileInfo(
            format: format,
            creationTime: creationTime,
            modificationTime: modificationTime,
            timescale: timescale,
            duration: duration,
            tracks: tracks
        )
    }

    /// Parses a movie box (moov).
    private func parseMovieBox(data: Data) throws -> (
        creationTime: UInt64,
        modificationTime: UInt64,
        timescale: UInt32,
        duration: UInt64,
        tracks: [MJ2TrackInfo]
    ) {
        var creationTime: UInt64 = 0
        var modificationTime: UInt64 = 0
        var timescale: UInt32 = 1
        var duration: UInt64 = 0
        var tracks: [MJ2TrackInfo] = []

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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .mvhd {
                // Parse movie header
                var mvhd = MJ2MovieHeaderBox(timescale: 1, duration: 0, nextTrackID: 1)
                try mvhd.read(from: boxData)
                creationTime = mvhd.creationTime
                modificationTime = mvhd.modificationTime
                timescale = mvhd.timescale
                duration = mvhd.duration
            } else if boxType == .trak {
                // Parse track
                if let trackInfo = try? parseTrackBox(data: boxData, movieTimescale: timescale) {
                    tracks.append(trackInfo)
                }
            }

            offset += boxLength
        }

        return (creationTime, modificationTime, timescale, duration, tracks)
    }

    /// Parses a track box (trak).
    private func parseTrackBox(data: Data, movieTimescale: UInt32) throws -> MJ2TrackInfo? {
        var trackID: UInt32 = 0
        var creationTime: UInt64 = 0
        var modificationTime: UInt64 = 0
        var duration: UInt64 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var mediaTimescale: UInt32 = 1
        var mediaDuration: UInt64 = 0
        var sampleCount = 0
        var language = "und"
        var isVideo = false

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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .tkhd {
                // Parse track header
                var tkhd = MJ2TrackHeaderBox(
                    trackID: 1,
                    duration: 0,
                    width: 0,
                    height: 0
                )
                try tkhd.read(from: boxData)
                trackID = tkhd.trackID
                creationTime = tkhd.creationTime
                modificationTime = tkhd.modificationTime
                duration = tkhd.duration
                width = tkhd.width >> 16 // Convert from 16.16 fixed-point
                height = tkhd.height >> 16
            } else if boxType == .mdia {
                // Parse media box
                let mediaInfo = try parseMediaBox(data: boxData)
                mediaTimescale = mediaInfo.timescale
                mediaDuration = mediaInfo.duration
                sampleCount = mediaInfo.sampleCount
                language = mediaInfo.language
                isVideo = mediaInfo.isVideo
            }

            offset += boxLength
        }

        return MJ2TrackInfo(
            trackID: trackID,
            creationTime: creationTime,
            modificationTime: modificationTime,
            duration: duration,
            width: width,
            height: height,
            mediaTimescale: mediaTimescale,
            mediaDuration: mediaDuration,
            sampleCount: sampleCount,
            language: language,
            isVideo: isVideo
        )
    }

    /// Parses a media box (mdia).
    private func parseMediaBox(data: Data) throws -> (
        timescale: UInt32,
        duration: UInt64,
        sampleCount: Int,
        language: String,
        isVideo: Bool
    ) {
        var timescale: UInt32 = 1
        var duration: UInt64 = 0
        var sampleCount = 0
        var language = "und"
        var isVideo = false

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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .mdhd {
                // Parse media header
                var mdhd = MJ2MediaHeaderBox(timescale: 1, duration: 0)
                try mdhd.read(from: boxData)
                timescale = mdhd.timescale
                duration = mdhd.duration

                // Decode language code
                let code = mdhd.language
                if code > 0 {
                    let c1 = Character(UnicodeScalar((code >> 10) & 0x1F + 0x60)!)
                    let c2 = Character(UnicodeScalar((code >> 5) & 0x1F + 0x60)!)
                    let c3 = Character(UnicodeScalar(code & 0x1F + 0x60)!)
                    language = String([c1, c2, c3])
                }
            } else if boxType == .hdlr {
                // Check handler type to determine if this is video
                // hdlr box structure: version(1) + flags(3) + pre_defined(4) + handler_type(4) + ...
                if boxData.count >= 12 {
                    let handlerType = String(data: boxData.subdata(in: 8..<12), encoding: .ascii)
                    isVideo = (handlerType == "vide")
                }
            } else if boxType == .minf {
                // Parse media information to get sample count
                if let count = try? parseSampleCount(from: boxData) {
                    sampleCount = count
                }
            }

            offset += boxLength
        }

        return (timescale, duration, sampleCount, language, isVideo)
    }

    /// Parses sample count from media information box.
    private func parseSampleCount(from data: Data) throws -> Int? {
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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .stbl {
                // Look for stsz (sample size) box
                return try parseSampleCountFromSampleTable(data: boxData)
            }

            offset += boxLength
        }

        return nil
    }

    /// Parses sample count from sample table box.
    private func parseSampleCountFromSampleTable(data: Data) throws -> Int? {
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

            let boxData = data.subdata(in: (offset + 8)..<(offset + boxLength))

            if boxType == .stsz {
                // Parse sample size box to get sample count
                guard boxData.count >= 12 else {
                    return nil
                }
                // Skip version/flags (4 bytes) and sample size (4 bytes)
                let count = Int(boxData.readUInt32(at: 8))
                return count
            }

            offset += boxLength
        }

        return nil
    }
}
