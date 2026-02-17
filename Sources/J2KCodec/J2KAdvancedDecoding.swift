// J2KAdvancedDecoding.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-07.
//

import Foundation
import J2KCore

/// # JPEG 2000 Advanced Decoding
///
/// Support for advanced decoding modes in JPEG 2000.
///
/// Advanced decoding allows selective extraction of image data based on:
/// - Quality layers (SNR progressive)
/// - Resolution levels (spatial progressive)
/// - Spatial regions (ROI decoding)
/// - Incremental data availability
///
/// ## Decoding Modes
///
/// - **Partial Decoding**: Decode up to specific quality layer or resolution
/// - **ROI Decoding**: Extract specific rectangular regions
/// - **Progressive Decoding**: Incrementally refine quality or resolution
/// - **Incremental Decoding**: Process data as it becomes available
///
/// ## Usage
///
/// ```swift
/// let decoder = J2KDecoder()
///
/// // Partial quality decoding (preview)
/// let preview = try decoder.decodePartial(
///     data,
///     options: J2KPartialDecodingOptions(maxLayer: 2)
/// )
///
/// // ROI decoding
/// let region = J2KRegion(x: 100, y: 100, width: 512, height: 512)
/// let roi = try decoder.decodeRegion(data, region: region)
///
/// // Resolution progressive (thumbnail)
/// let thumbnail = try decoder.decodeResolution(data, level: 2)
/// ```

// MARK: - Partial Decoding Options

/// Options for partial decoding operations.
public struct J2KPartialDecodingOptions: Sendable, Equatable {
    /// Maximum quality layer to decode (nil = all layers).
    public let maxLayer: Int?

    /// Maximum resolution level to decode (nil = full resolution).
    ///
    /// Resolution level 0 is the lowest resolution (thumbnail),
    /// higher levels progressively increase resolution.
    public let maxResolutionLevel: Int?

    /// Specific region to decode (nil = full image).
    public let region: J2KRegion?

    /// Enable early stopping optimization.
    ///
    /// When true, the decoder stops processing as soon as the requested
    /// quality/resolution is achieved, saving computation time.
    public let earlyStop: Bool

    /// Decode only specific components (nil = all components).
    ///
    /// For RGB images: [0, 1, 2] for R, G, B components.
    /// Can be used to decode grayscale from color images: [0] for Y component.
    public let components: [Int]?

    /// Creates new partial decoding options.
    ///
    /// - Parameters:
    ///   - maxLayer: Maximum quality layer to decode (default: nil for all layers).
    ///   - maxResolutionLevel: Maximum resolution level (default: nil for full resolution).
    ///   - region: Specific region to decode (default: nil for full image).
    ///   - earlyStop: Enable early stopping optimization (default: true).
    ///   - components: Specific components to decode (default: nil for all components).
    public init(
        maxLayer: Int? = nil,
        maxResolutionLevel: Int? = nil,
        region: J2KRegion? = nil,
        earlyStop: Bool = true,
        components: [Int]? = nil
    ) {
        self.maxLayer = maxLayer
        self.maxResolutionLevel = maxResolutionLevel
        self.region = region
        self.earlyStop = earlyStop
        self.components = components
    }

    /// Validates the options.
    ///
    /// - Parameters:
    ///   - imageWidth: Full image width.
    ///   - imageHeight: Full image height.
    ///   - maxLayers: Maximum available quality layers.
    ///   - maxLevels: Maximum decomposition levels.
    ///   - componentCount: Number of components in the image.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if options are invalid.
    public func validate(
        imageWidth: Int,
        imageHeight: Int,
        maxLayers: Int,
        maxLevels: Int,
        componentCount: Int
    ) throws {
        if let layer = maxLayer, layer < 0 || layer >= maxLayers {
            throw J2KError.invalidParameter("maxLayer must be in range [0, \(maxLayers))")
        }

        if let level = maxResolutionLevel, level < 0 || level > maxLevels {
            throw J2KError.invalidParameter("maxResolutionLevel must be in range [0, \(maxLevels)]")
        }

        if let region = region {
            try region.validate(imageWidth: imageWidth, imageHeight: imageHeight)
        }

        if let comps = components {
            if comps.isEmpty {
                throw J2KError.invalidParameter("components array cannot be empty")
            }

            for comp in comps {
                if comp < 0 || comp >= componentCount {
                    throw J2KError.invalidParameter("component \(comp) out of range [0, \(componentCount))")
                }
            }
        }
    }
}

// MARK: - ROI Decoding Options

/// Options for region-of-interest decoding.
public struct J2KROIDecodingOptions: Sendable, Equatable {
    /// The region to decode.
    public let region: J2KRegion

    /// Maximum quality layer to decode (nil = all layers).
    public let maxLayer: Int?

    /// Components to decode (nil = all components).
    public let components: [Int]?

    /// Decoding strategy for the region.
    public let strategy: J2KROIDecodingStrategy

    /// Creates new ROI decoding options.
    ///
    /// - Parameters:
    ///   - region: The region to decode.
    ///   - maxLayer: Maximum quality layer (default: nil for all layers).
    ///   - components: Components to decode (default: nil for all).
    ///   - strategy: Decoding strategy (default: .direct).
    public init(
        region: J2KRegion,
        maxLayer: Int? = nil,
        components: [Int]? = nil,
        strategy: J2KROIDecodingStrategy = .direct
    ) {
        self.region = region
        self.maxLayer = maxLayer
        self.components = components
        self.strategy = strategy
    }

    /// Validates the options.
    ///
    /// - Parameters:
    ///   - imageWidth: Full image width.
    ///   - imageHeight: Full image height.
    ///   - maxLayers: Maximum available quality layers.
    ///   - componentCount: Number of components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if options are invalid.
    public func validate(
        imageWidth: Int,
        imageHeight: Int,
        maxLayers: Int,
        componentCount: Int
    ) throws {
        try region.validate(imageWidth: imageWidth, imageHeight: imageHeight)

        if let layer = maxLayer, layer < 0 || layer >= maxLayers {
            throw J2KError.invalidParameter("maxLayer must be in range [0, \(maxLayers))")
        }

        if let comps = components {
            if comps.isEmpty {
                throw J2KError.invalidParameter("components array cannot be empty")
            }

            for comp in comps {
                if comp < 0 || comp >= componentCount {
                    throw J2KError.invalidParameter("component \(comp) out of range [0, \(componentCount))")
                }
            }
        }
    }
}

/// Strategy for ROI decoding.
public enum J2KROIDecodingStrategy: Sendable, Equatable {
    /// Decode the entire image then extract the region.
    ///
    /// Simple but less efficient. Useful when multiple regions will be extracted.
    case fullImageExtraction

    /// Decode only the necessary data for the region.
    ///
    /// More efficient for single region extraction. Requires identifying
    /// which code-blocks contribute to the region.
    case direct

    /// Use cached full image if available, otherwise decode directly.
    case cached
}

// MARK: - Resolution Progressive Decoding

/// Options for resolution progressive decoding.
public struct J2KResolutionDecodingOptions: Sendable, Equatable {
    /// Target resolution level (0 = lowest/thumbnail, higher = more detail).
    public let level: Int

    /// Maximum quality layer to decode at this resolution.
    public let maxLayer: Int?

    /// Components to decode (nil = all components).
    public let components: [Int]?

    /// Whether to upscale to original dimensions.
    ///
    /// If true, the result is upscaled to the original image size.
    /// If false, returns the image at the decoded resolution.
    public let upscale: Bool

    /// Creates resolution decoding options.
    ///
    /// - Parameters:
    ///   - level: Target resolution level.
    ///   - maxLayer: Maximum quality layer (default: nil for all).
    ///   - components: Components to decode (default: nil for all).
    ///   - upscale: Upscale to original dimensions (default: false).
    public init(
        level: Int,
        maxLayer: Int? = nil,
        components: [Int]? = nil,
        upscale: Bool = false
    ) {
        self.level = level
        self.maxLayer = maxLayer
        self.components = components
        self.upscale = upscale
    }

    /// Validates the options.
    ///
    /// - Parameters:
    ///   - maxLevels: Maximum decomposition levels.
    ///   - maxLayers: Maximum quality layers.
    ///   - componentCount: Number of components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if options are invalid.
    public func validate(maxLevels: Int, maxLayers: Int, componentCount: Int) throws {
        if level < 0 || level > maxLevels {
            throw J2KError.invalidParameter("level must be in range [0, \(maxLevels)]")
        }

        if let layer = maxLayer, layer < 0 || layer >= maxLayers {
            throw J2KError.invalidParameter("maxLayer must be in range [0, \(maxLayers))")
        }

        if let comps = components {
            if comps.isEmpty {
                throw J2KError.invalidParameter("components array cannot be empty")
            }

            for comp in comps {
                if comp < 0 || comp >= componentCount {
                    throw J2KError.invalidParameter("component \(comp) out of range [0, \(componentCount))")
                }
            }
        }
    }

    /// Calculates the decoded image dimensions at this resolution level.
    ///
    /// - Parameters:
    ///   - fullWidth: Full image width.
    ///   - fullHeight: Full image height.
    /// - Returns: Tuple of (width, height) at the target resolution level.
    public func calculatedDimensions(fullWidth: Int, fullHeight: Int) -> (width: Int, height: Int) {
        let divisor = 1 << level
        let width = (fullWidth + divisor - 1) / divisor
        let height = (fullHeight + divisor - 1) / divisor
        return (width, height)
    }
}

// MARK: - Quality Progressive Decoding

/// Options for quality progressive decoding.
public struct J2KQualityDecodingOptions: Sendable, Equatable {
    /// Target quality layer.
    public let layer: Int

    /// Components to decode (nil = all components).
    public let components: [Int]?

    /// Whether to include all previous layers.
    ///
    /// If true, decodes all layers up to and including the target layer.
    /// If false, decodes only the target layer (incremental refinement).
    public let cumulative: Bool

    /// Creates quality decoding options.
    ///
    /// - Parameters:
    ///   - layer: Target quality layer.
    ///   - components: Components to decode (default: nil for all).
    ///   - cumulative: Include all previous layers (default: true).
    public init(
        layer: Int,
        components: [Int]? = nil,
        cumulative: Bool = true
    ) {
        self.layer = layer
        self.components = components
        self.cumulative = cumulative
    }

    /// Validates the options.
    ///
    /// - Parameters:
    ///   - maxLayers: Maximum quality layers.
    ///   - componentCount: Number of components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if options are invalid.
    public func validate(maxLayers: Int, componentCount: Int) throws {
        if layer < 0 || layer >= maxLayers {
            throw J2KError.invalidParameter("layer must be in range [0, \(maxLayers))")
        }

        if let comps = components {
            if comps.isEmpty {
                throw J2KError.invalidParameter("components array cannot be empty")
            }

            for comp in comps {
                if comp < 0 || comp >= componentCount {
                    throw J2KError.invalidParameter("component \(comp) out of range [0, \(componentCount))")
                }
            }
        }
    }
}

// MARK: - Incremental Decoding

/// State for incremental decoding operations.
///
/// Maintains decoder state across multiple partial data updates,
/// enabling progressive decoding as data arrives over a network.
public final class J2KIncrementalDecoder: Sendable {
    /// The current decoding state.
    private let state: State

    /// Thread-safe state management.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var buffer: Data = Data()
        var isComplete: Bool = false
        var lastDecodedLayer: Int = -1
        var lastDecodedLevel: Int = -1
    }

    /// Creates a new incremental decoder.
    public init() {
        self.state = State()
    }

    /// Appends new data to the decoder.
    ///
    /// - Parameter data: New data chunk to append.
    public func append(_ data: Data) {
        state.lock.lock()
        defer { state.lock.unlock() }

        state.buffer.append(data)
    }

    /// Marks the data stream as complete.
    public func complete() {
        state.lock.lock()
        defer { state.lock.unlock() }

        state.isComplete = true
    }

    /// Checks if enough data is available to decode.
    ///
    /// - Returns: True if decoding can proceed.
    public func canDecode() -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }

        // Simple heuristic: need at least header data
        return state.buffer.count > 100
    }

    /// Attempts to decode with currently available data.
    ///
    /// - Parameter options: Decoding options.
    /// - Returns: Decoded image if sufficient data is available, nil otherwise.
    /// - Throws: ``J2KError`` if decoding fails.
    public func tryDecode(options: J2KPartialDecodingOptions = J2KPartialDecodingOptions()) throws -> J2KImage? {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard canDecode() else {
            return nil
        }

        // In a real implementation, this would:
        // 1. Parse what data is available
        // 2. Decode up to the available quality layers
        // 3. Track what has been decoded
        // 4. Return partial results

        // For now, this is a placeholder
        throw J2KError.notImplemented("Incremental decoding not yet fully implemented")
    }

    /// Gets the current buffer size.
    ///
    /// - Returns: Number of bytes currently buffered.
    public func bufferSize() -> Int {
        state.lock.lock()
        defer { state.lock.unlock() }

        return state.buffer.count
    }

    /// Checks if the data stream is complete.
    ///
    /// - Returns: True if `complete()` has been called.
    public func isComplete() -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }

        return state.isComplete
    }

    /// Resets the decoder state.
    public func reset() {
        state.lock.lock()
        defer { state.lock.unlock() }

        state.buffer.removeAll()
        state.isComplete = false
        state.lastDecodedLayer = -1
        state.lastDecodedLevel = -1
    }
}

// MARK: - Decoder Extensions

extension J2KDecoder {
    /// Decodes a JPEG 2000 image with partial decoding options.
    ///
    /// Allows selective decoding of quality layers, resolution levels,
    /// regions, and components.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 data to decode.
    ///   - options: Partial decoding options.
    /// - Returns: The decoded image (potentially partial).
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodePartial(_ data: Data, options: J2KPartialDecodingOptions) throws -> J2KImage {
        // Placeholder implementation
        // In reality, this would:
        // 1. Parse the codestream header
        // 2. Identify required code-blocks based on options
        // 3. Decode only the necessary data
        // 4. Reconstruct the image at the requested quality/resolution

        throw J2KError.notImplemented("Partial decoding not yet fully implemented")
    }

    /// Decodes a specific region of interest from a JPEG 2000 image.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 data to decode.
    ///   - options: ROI decoding options.
    /// - Returns: The decoded region as an image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeRegion(_ data: Data, options: J2KROIDecodingOptions) throws -> J2KImage {
        // Placeholder implementation
        // In reality, this would:
        // 1. Identify code-blocks that overlap with the region
        // 2. Decode only those code-blocks
        // 3. Extract and reconstruct the requested region

        switch options.strategy {
        case .fullImageExtraction:
            // Decode full image then extract
            let fullImage = try decode(data)
            return try extractRegion(from: fullImage, region: options.region)

        case .direct, .cached:
            // Direct decoding (not yet implemented)
            throw J2KError.notImplemented("Direct ROI decoding not yet fully implemented")
        }
    }

    /// Decodes a JPEG 2000 image at a specific resolution level.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 data to decode.
    ///   - options: Resolution decoding options.
    /// - Returns: The decoded image at the requested resolution.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeResolution(_ data: Data, options: J2KResolutionDecodingOptions) throws -> J2KImage {
        // Placeholder implementation
        // In reality, this would:
        // 1. Decode only the required wavelet subbands
        // 2. Perform partial inverse DWT up to the target level
        // 3. Optionally upscale to original dimensions

        throw J2KError.notImplemented("Resolution progressive decoding not yet fully implemented")
    }

    /// Decodes a JPEG 2000 image up to a specific quality layer.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 data to decode.
    ///   - options: Quality decoding options.
    /// - Returns: The decoded image at the requested quality.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeQuality(_ data: Data, options: J2KQualityDecodingOptions) throws -> J2KImage {
        // Placeholder implementation
        // In reality, this would:
        // 1. Parse packet headers
        // 2. Decode only packets up to the target layer
        // 3. Reconstruct the image with available quality

        throw J2KError.notImplemented("Quality progressive decoding not yet fully implemented")
    }

    // MARK: - Helper Methods

    /// Extracts a region from a decoded image.
    ///
    /// - Parameters:
    ///   - image: The full image.
    ///   - region: The region to extract.
    /// - Returns: A new image containing only the specified region.
    /// - Throws: ``J2KError`` if extraction fails.
    private func extractRegion(from image: J2KImage, region: J2KRegion) throws -> J2KImage {
        try region.validate(imageWidth: image.width, imageHeight: image.height)

        // Create new components with extracted data
        let regionComponents = image.components.map { component in
            var regionData = Data(count: region.width * region.height)

            for y in 0..<region.height {
                let srcY = region.y + y
                let dstOffset = y * region.width
                let srcOffset = srcY * image.width + region.x

                for x in 0..<region.width {
                    regionData[dstOffset + x] = component.data[srcOffset + x]
                }
            }

            return J2KComponent(
                index: component.index,
                bitDepth: component.bitDepth,
                signed: component.signed,
                width: region.width,
                height: region.height,
                subsamplingX: component.subsamplingX,
                subsamplingY: component.subsamplingY,
                data: regionData
            )
        }

        // Create new image with region dimensions
        return J2KImage(
            width: region.width,
            height: region.height,
            components: regionComponents,
            colorSpace: image.colorSpace
        )
    }
}

// MARK: - CustomStringConvertible

extension J2KPartialDecodingOptions: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if let layer = maxLayer {
            parts.append("maxLayer: \(layer)")
        }

        if let level = maxResolutionLevel {
            parts.append("maxLevel: \(level)")
        }

        if let region = region {
            parts.append("region: \(region)")
        }

        if let comps = components {
            parts.append("components: \(comps)")
        }

        if earlyStop {
            parts.append("earlyStop: true")
        }

        return "J2KPartialDecodingOptions(\(parts.joined(separator: ", ")))"
    }
}

extension J2KROIDecodingOptions: CustomStringConvertible {
    public var description: String {
        var parts = ["region: \(region)"]

        if let layer = maxLayer {
            parts.append("maxLayer: \(layer)")
        }

        if let comps = components {
            parts.append("components: \(comps)")
        }

        parts.append("strategy: \(strategy)")

        return "J2KROIDecodingOptions(\(parts.joined(separator: ", ")))"
    }
}

extension J2KROIDecodingStrategy: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fullImageExtraction:
            return "fullImageExtraction"
        case .direct:
            return "direct"
        case .cached:
            return "cached"
        }
    }
}

extension J2KResolutionDecodingOptions: CustomStringConvertible {
    public var description: String {
        var parts = ["level: \(level)"]

        if let layer = maxLayer {
            parts.append("maxLayer: \(layer)")
        }

        if let comps = components {
            parts.append("components: \(comps)")
        }

        if upscale {
            parts.append("upscale: true")
        }

        return "J2KResolutionDecodingOptions(\(parts.joined(separator: ", ")))"
    }
}

extension J2KQualityDecodingOptions: CustomStringConvertible {
    public var description: String {
        var parts = ["layer: \(layer)"]

        if let comps = components {
            parts.append("components: \(comps)")
        }

        if cumulative {
            parts.append("cumulative: true")
        }

        return "J2KQualityDecodingOptions(\(parts.joined(separator: ", ")))"
    }
}
