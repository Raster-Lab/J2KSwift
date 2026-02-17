/// # JPIPRequest
///
/// Types for JPIP request construction.

import Foundation

/// Represents a JPIP request with various parameters.
public struct JPIPRequest: Sendable {
    /// The target image identifier (filename or path).
    public var target: String

    /// Full size of the image window (width, height).
    public var fsiz: (width: Int, height: Int)?

    /// Region size within the full image (width, height).
    public var rsiz: (width: Int, height: Int)?

    /// Region offset (x, y) from top-left corner.
    public var roff: (x: Int, y: Int)?

    /// Number of quality layers to request.
    public var layers: Int?

    /// Channel ID for stateful sessions.
    public var cid: String?

    /// Whether to request a new channel.
    public var cnew: JPIPChannelType?

    /// Maximum length of response data in bytes.
    public var len: Int?

    /// Component indices to request (e.g., [0, 1] for red and green channels).
    public var comps: [Int]?

    /// Resolution levels to request (lower values = lower resolution).
    public var reslevels: Int?

    /// Whether to request metadata only.
    public var metadata: Bool?

    /// Coding preference for HTJ2K or legacy JPEG 2000 responses.
    public var codingPreference: JPIPCodingPreference?

    /// Creates a new JPIP request.
    ///
    /// - Parameter target: The target image identifier.
    public init(target: String) {
        self.target = target
    }

    /// Builds the URL query string for this request.
    ///
    /// - Returns: A dictionary of query parameters.
    public func buildQueryItems() -> [String: String] {
        var items: [String: String] = [:]

        items["target"] = target

        if let fsiz = fsiz {
            items["fsiz"] = "\(fsiz.width),\(fsiz.height)"
        }

        if let rsiz = rsiz {
            items["rsiz"] = "\(rsiz.width),\(rsiz.height)"
        }

        if let roff = roff {
            items["roff"] = "\(roff.x),\(roff.y)"
        }

        if let layers = layers {
            items["layers"] = "\(layers)"
        }

        if let cid = cid {
            items["cid"] = cid
        }

        if let cnew = cnew {
            items["cnew"] = cnew.rawValue
        }

        if let len = len {
            items["len"] = "\(len)"
        }

        if let comps = comps, !comps.isEmpty {
            items["comps"] = comps.map { "\($0)" }.joined(separator: ",")
        }

        if let reslevels = reslevels {
            items["reslevels"] = "\(reslevels)"
        }

        if let metadata = metadata, metadata {
            items["meta"] = "yes"
        }

        if let codingPreference = codingPreference, codingPreference != .none {
            items["pref"] = codingPreference.rawValue
        }

        return items
    }
}

/// Channel types for JPIP requests.
public enum JPIPChannelType: String, Sendable {
    /// HTTP channel.
    case http = "http"

    /// HTTP with TCP (persistent connection).
    case httpTcp = "http-tcp"
}

extension JPIPRequest {
    /// Creates a request for a specific region of interest.
    ///
    /// - Parameters:
    ///   - target: The target image identifier.
    ///   - x: The x-coordinate of the region.
    ///   - y: The y-coordinate of the region.
    ///   - width: The width of the region.
    ///   - height: The height of the region.
    ///   - layers: Optional number of quality layers.
    /// - Returns: A configured JPIP request.
    public static func regionRequest(
        target: String,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        layers: Int? = nil
    ) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.roff = (x, y)
        request.rsiz = (width, height)
        request.layers = layers
        return request
    }

    /// Creates a request for a specific resolution.
    ///
    /// - Parameters:
    ///   - target: The target image identifier.
    ///   - width: The desired width.
    ///   - height: The desired height.
    ///   - layers: Optional number of quality layers.
    /// - Returns: A configured JPIP request.
    public static func resolutionRequest(
        target: String,
        width: Int,
        height: Int,
        layers: Int? = nil
    ) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.fsiz = (width, height)
        request.layers = layers
        return request
    }

    /// Creates a request for a specific resolution level.
    ///
    /// - Parameters:
    ///   - target: The target image identifier.
    ///   - level: The resolution level (0 = full resolution, higher values = lower resolution).
    ///   - layers: Optional number of quality layers.
    /// - Returns: A configured JPIP request.
    public static func resolutionLevelRequest(
        target: String,
        level: Int,
        layers: Int? = nil
    ) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.reslevels = level
        request.layers = layers
        return request
    }

    /// Creates a request for specific image components.
    ///
    /// - Parameters:
    ///   - target: The target image identifier.
    ///   - components: Array of component indices to request (e.g., [0, 1] for R and G channels).
    ///   - layers: Optional number of quality layers.
    /// - Returns: A configured JPIP request.
    public static func componentRequest(
        target: String,
        components: [Int],
        layers: Int? = nil
    ) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.comps = components
        request.layers = layers
        return request
    }

    /// Creates a request for progressive quality with increasing layers.
    ///
    /// - Parameters:
    ///   - target: The target image identifier.
    ///   - upToLayers: The maximum number of quality layers to request.
    /// - Returns: A configured JPIP request.
    public static func progressiveQualityRequest(
        target: String,
        upToLayers: Int
    ) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.layers = upToLayers
        return request
    }

    /// Creates a request for metadata only (no image data).
    ///
    /// - Parameter target: The target image identifier.
    /// - Returns: A configured JPIP request.
    public static func metadataRequest(target: String) -> JPIPRequest {
        var request = JPIPRequest(target: target)
        request.metadata = true
        return request
    }
}
