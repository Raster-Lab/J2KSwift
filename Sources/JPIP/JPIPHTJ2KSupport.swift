//
// JPIPHTJ2KSupport.swift
// J2KSwift
//
/// # JPIPHTJ2KSupport
///
/// HTJ2K (High-Throughput JPEG 2000) support for the JPIP protocol.
///
/// This module provides HTJ2K format detection, capability signaling, and
/// format-aware metadata generation for JPIP streaming of HTJ2K images.

import Foundation
import J2KCore
import J2KFileFormat

/// Coding preference for JPIP requests indicating the desired block coding mode.
///
/// JPIP clients can signal a preference for HTJ2K or legacy JPEG 2000 coding
/// when requesting image data. The server will attempt to honor the preference
/// if the source image supports the requested mode.
public enum JPIPCodingPreference: String, Sendable {
    /// No preference; use whatever coding mode the image uses natively.
    case none = "none"

    /// Prefer HTJ2K (Part 15) high-throughput coding.
    case htj2k = "htj2k"

    /// Prefer legacy JPEG 2000 (Part 1) coding.
    case legacy = "legacy"
}

/// Information about a registered image's format and HTJ2K capabilities.
///
/// Tracks whether an image uses HTJ2K encoding, its format, and capabilities
/// to enable format-aware JPIP serving.
public struct JPIPImageInfo: Sendable {
    /// The file URL of the image.
    public let url: URL

    /// The detected JPEG 2000 format.
    public let format: J2KFormat

    /// Whether the image uses HTJ2K (Part 15) encoding.
    public let isHTJ2K: Bool

    /// The MIME type for JPIP responses serving this image.
    public var mimeType: String {
        format.mimeType
    }

    /// Creates a new image info.
    ///
    /// - Parameters:
    ///   - url: The file URL.
    ///   - format: The detected format.
    ///   - isHTJ2K: Whether the image uses HTJ2K.
    public init(url: URL, format: J2KFormat, isHTJ2K: Bool) {
        self.url = url
        self.format = format
        self.isHTJ2K = isHTJ2K
    }
}

/// Provides HTJ2K format detection and capability signaling for JPIP.
///
/// `JPIPHTJ2KSupport` is used by the JPIP server to detect whether registered
/// images use HTJ2K encoding and to generate appropriate capability headers
/// in JPIP responses.
///
/// Example:
/// ```swift
/// let support = JPIPHTJ2KSupport()
/// let info = try support.detectFormat(at: imageURL)
/// let headers = support.capabilityHeaders(for: info)
/// ```
public struct JPIPHTJ2KSupport: Sendable {
    /// Creates a new HTJ2K support helper.
    public init() {}

    /// Detects the JPEG 2000 format and HTJ2K capability of a file.
    ///
    /// Reads the file header to determine the format (JP2, J2K, JPH, etc.)
    /// and whether it uses HTJ2K encoding.
    ///
    /// - Parameter url: The file URL to analyze.
    /// - Returns: Image info with format and HTJ2K capability.
    /// - Throws: ``J2KError`` if the file cannot be read or parsed.
    public func detectFormat(at url: URL) throws -> JPIPImageInfo {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let detector = J2KFormatDetector()
        let format = try detector.detect(data: data)

        let isHTJ2K = format == .jph || detectCAPMarker(in: data)

        return JPIPImageInfo(url: url, format: format, isHTJ2K: isHTJ2K)
    }

    /// Generates JPIP capability headers for an image.
    ///
    /// Includes headers that signal HTJ2K support to the client, such as
    /// the content type and coding capabilities.
    ///
    /// - Parameter imageInfo: The image information.
    /// - Returns: A dictionary of HTTP headers.
    public func capabilityHeaders(for imageInfo: JPIPImageInfo) -> [String: String] {
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/octet-stream"
        headers["JPIP-tid"] = imageInfo.url.lastPathComponent

        if imageInfo.isHTJ2K {
            headers["JPIP-cap"] = "htj2k"
            headers["JPIP-pref"] = "htj2k"
        } else {
            headers["JPIP-cap"] = "j2k"
            headers["JPIP-pref"] = "j2k"
        }

        return headers
    }

    /// Generates metadata about an image including HTJ2K format information.
    ///
    /// Creates a metadata dictionary that JPIP clients can use to understand
    /// the image's format and capabilities before requesting image data.
    ///
    /// - Parameter imageInfo: The image information.
    /// - Returns: Encoded metadata as Data.
    public func generateFormatMetadata(for imageInfo: JPIPImageInfo) -> Data {
        var metadata: [String] = []
        metadata.append("format=\(imageInfo.format.rawValue)")
        metadata.append("htj2k=\(imageInfo.isHTJ2K)")
        metadata.append("mime=\(imageInfo.mimeType)")
        metadata.append("file=\(imageInfo.url.lastPathComponent)")
        return Data(metadata.joined(separator: "\n").utf8)
    }

    /// Checks if a coding preference is compatible with an image's format.
    ///
    /// - Parameters:
    ///   - preference: The client's coding preference.
    ///   - imageInfo: The image information.
    /// - Returns: `true` if the preference is compatible.
    public func isPreferenceCompatible(
        _ preference: JPIPCodingPreference,
        with imageInfo: JPIPImageInfo
    ) -> Bool {
        switch preference {
        case .none:
            return true
        case .htj2k:
            return imageInfo.isHTJ2K
        case .legacy:
            return !imageInfo.isHTJ2K || imageInfo.format == .jp2 || imageInfo.format == .j2k
        }
    }

    // MARK: - Private Helpers

    /// Detects the CAP marker in a JPEG 2000 codestream.
    ///
    /// The CAP (capabilities) marker (0xFF50) signals HTJ2K support in
    /// legacy J2K codestreams that may not use the JPH file wrapper.
    ///
    /// - Parameter data: The file data to search.
    /// - Returns: `true` if a CAP marker is found.
    private func detectCAPMarker(in data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let searchLimit = min(data.count, 4096)
        let bytes = [UInt8](data.prefix(searchLimit))

        // Look for CAP marker (0xFF50) in the main header
        for i in 0..<(bytes.count - 1) {
            if bytes[i] == 0xFF && bytes[i + 1] == 0x50 {
                return true
            }
        }

        return false
    }
}
