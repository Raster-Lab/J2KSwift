//
// JPIPResponse.swift
// J2KSwift
//
/// # JPIPResponse
///
/// Types for JPIP response parsing.

import Foundation
import J2KCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Represents a JPIP response from the server.
public struct JPIPResponse: Sendable {
    /// The channel ID (cid) from JPIP-cnew header, if present.
    public let channelID: String?

    /// The response data.
    public let data: Data

    /// HTTP status code.
    public let statusCode: Int

    /// All HTTP headers.
    public let headers: [String: String]

    /// Creates a new JPIP response.
    ///
    /// - Parameters:
    ///   - channelID: Optional channel ID from JPIP-cnew header.
    ///   - data: The response data.
    ///   - statusCode: HTTP status code.
    ///   - headers: HTTP headers.
    public init(channelID: String?, data: Data, statusCode: Int, headers: [String: String]) {
        self.channelID = channelID
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

/// Parser for JPIP response headers.
public struct JPIPResponseParser: Sendable {
    /// Parses the JPIP-cnew header to extract channel ID.
    ///
    /// - Parameter header: The JPIP-cnew header value.
    /// - Returns: The channel ID if found, nil otherwise.
    ///
    /// Example header: "cid=1942302,path=/jp2,transport=http"
    public static func parseChannelID(from header: String) -> String? {
        // Split by comma and look for cid field
        let fields = header.split(separator: ",")
        for field in fields {
            let parts = field.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if key == "cid" {
                    return value
                }
            }
        }
        return nil
    }

    /// Parses HTTP headers from URLResponse.
    ///
    /// - Parameter response: The HTTP URL response.
    /// - Returns: A dictionary of headers.
    public static func parseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                headers[keyString] = valueString
            }
        }
        return headers
    }

    /// Extracts channel ID from response headers.
    ///
    /// - Parameter headers: HTTP response headers.
    /// - Returns: The channel ID if present.
    public static func extractChannelID(from headers: [String: String]) -> String? {
        // Look for JPIP-cnew header (case-insensitive)
        for (key, value) in headers {
            if key.lowercased() == "jpip-cnew" {
                return parseChannelID(from: value)
            }
        }
        return nil
    }
}

/// Represents a JPIP data bin class.
public enum JPIPDataBinClass: Int, Sendable {
    /// Main header data bin.
    case mainHeader = 0

    /// Tile header data bin.
    case tileHeader = 1

    /// Precinct data bin.
    case precinct = 2

    /// Tile data bin.
    case tile = 3

    /// Extended precinct data bin.
    case extendedPrecinct = 4

    /// Metadata data bin.
    case metadata = 5
}

/// Represents a JPIP data bin.
public struct JPIPDataBin: Sendable {
    /// The data bin class.
    public let binClass: JPIPDataBinClass

    /// Class identifier (for compatibility).
    public var classID: JPIPDataBinClass { binClass }

    /// The data bin ID.
    public let binID: Int

    /// The data content.
    public var data: Data

    /// Whether this is the complete bin.
    public let isComplete: Bool

    /// Quality layer for precinct data bins.
    public var qualityLayer: Int

    /// Tile index for tile-based data bins.
    public var tileIndex: Int

    /// Creates a new data bin.
    ///
    /// - Parameters:
    ///   - binClass: The bin class.
    ///   - binID: The bin identifier.
    ///   - data: The data content.
    ///   - isComplete: Whether this is the complete bin.
    ///   - qualityLayer: Quality layer (default: 0).
    ///   - tileIndex: Tile index (default: 0).
    public init(
        binClass: JPIPDataBinClass,
        binID: Int,
        data: Data,
        isComplete: Bool,
        qualityLayer: Int = 0,
        tileIndex: Int = 0
    ) {
        self.binClass = binClass
        self.binID = binID
        self.data = data
        self.isComplete = isComplete
        self.qualityLayer = qualityLayer
        self.tileIndex = tileIndex
    }
}
