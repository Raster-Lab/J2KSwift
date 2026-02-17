// J2KEncodingPresets.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-07.
//

import Foundation
import J2KCore

/// # JPEG 2000 Encoding Presets
///
/// Predefined encoding configurations optimized for different use cases.
///
/// Encoding presets provide a simple way to choose between encoding speed,
/// file size, and quality without manually configuring all parameters.
///
/// ## Preset Types
///
/// - **Fast**: Optimized for encoding speed with acceptable quality
/// - **Balanced**: Default balanced settings for general use
/// - **Quality**: Optimized for maximum quality with slower encoding
///
/// ## Usage
///
/// ```swift
/// // Use a preset directly
/// let config = J2KEncodingPreset.fast.configuration(quality: 0.8)
/// let encoder = J2KEncoder(configuration: config)
///
/// // Or customize a preset
/// var customConfig = J2KEncodingPreset.balanced.configuration()
/// customConfig.decompositionLevels = 3
/// ```

// MARK: - Encoding Preset

/// Predefined encoding preset types.
public enum J2KEncodingPreset: String, Sendable, CaseIterable {
    /// Fast encoding with acceptable quality.
    ///
    /// - Fewer decomposition levels (3 levels)
    /// - Larger code blocks (64×64)
    /// - Fewer quality layers (3 layers)
    /// - No visual weighting
    /// - Single-threaded encoding
    ///
    /// **Performance:** 2-3× faster than balanced
    /// **Quality:** Good for preview/draft quality
    /// **Use cases:** Real-time encoding, thumbnails, previews
    case fast
    
    /// Balanced encoding for general use.
    ///
    /// - Standard decomposition levels (5 levels)
    /// - Medium code blocks (32×32)
    /// - Multiple quality layers (5 layers)
    /// - Optional visual weighting
    /// - Multi-threaded encoding
    ///
    /// **Performance:** Reference baseline
    /// **Quality:** Excellent for most use cases
    /// **Use cases:** General purpose, web delivery, storage
    case balanced
    
    /// Maximum quality encoding.
    ///
    /// - Maximum decomposition levels (6 levels)
    /// - Small code blocks (32×32)
    /// - Many quality layers (10 layers)
    /// - Visual weighting enabled
    /// - Multi-threaded with aggressive optimization
    ///
    /// **Performance:** 1.5-2× slower than balanced
    /// **Quality:** Best possible quality
    /// **Use cases:** Archival, medical imaging, professional photography
    case quality
    
    /// Creates an encoding configuration from this preset.
    ///
    /// - Parameters:
    ///   - quality: Overall quality factor (0.0 to 1.0). Default is 0.9.
    ///   - lossless: Whether to use lossless compression. Default is false.
    /// - Returns: A fully configured ``J2KEncodingConfiguration``.
    public func configuration(
        quality: Double = 0.9,
        lossless: Bool = false
    ) -> J2KEncodingConfiguration {
        switch self {
        case .fast:
            return J2KEncodingConfiguration(
                quality: quality,
                lossless: lossless,
                decompositionLevels: 3,
                codeBlockSize: (width: 64, height: 64),
                qualityLayers: 3,
                progressionOrder: .lrcp,  // Layer-resolution-component-position (simple)
                enableVisualWeighting: false,
                tileSize: (width: 512, height: 512),
                bitrateMode: .constantQuality,
                maxThreads: 1
            )
            
        case .balanced:
            return J2KEncodingConfiguration(
                quality: quality,
                lossless: lossless,
                decompositionLevels: 5,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 5,
                progressionOrder: .rpcl,  // Resolution-position-component-layer (good for streaming)
                enableVisualWeighting: quality < 1.0,  // Enable for lossy
                tileSize: (width: 1024, height: 1024),
                bitrateMode: .constantQuality,
                maxThreads: 0  // Auto-detect
            )
            
        case .quality:
            return J2KEncodingConfiguration(
                quality: quality,
                lossless: lossless,
                decompositionLevels: 6,
                codeBlockSize: (width: 32, height: 32),
                qualityLayers: 10,
                progressionOrder: .rpcl,
                enableVisualWeighting: quality < 1.0,
                tileSize: (width: 2048, height: 2048),
                bitrateMode: .constantQuality,
                maxThreads: 0
            )
        }
    }
}

// MARK: - Encoding Configuration

/// Comprehensive configuration for JPEG 2000 encoding.
public struct J2KEncodingConfiguration: Sendable {
    /// Overall quality factor (0.0 to 1.0).
    ///
    /// - 0.0: Maximum compression (lowest quality)
    /// - 1.0: Lossless or minimal compression (highest quality)
    public var quality: Double
    
    /// Whether to use lossless compression.
    ///
    /// When true, the encoder uses the reversible color transform (RCT)
    /// and reversible wavelet filter (5/3), ensuring perfect reconstruction.
    public var lossless: Bool
    
    /// Number of wavelet decomposition levels.
    ///
    /// - Valid range: 0-10
    /// - Default: 5 for balanced, 3 for fast, 6 for quality
    /// - More levels = better compression but slower encoding
    public var decompositionLevels: Int
    
    /// Size of code blocks for entropy coding.
    ///
    /// - Valid range: 4-1024 for each dimension
    /// - Default: 32×32 (balanced), 64×64 (fast)
    /// - Larger blocks = faster encoding, smaller blocks = better quality
    public var codeBlockSize: (width: Int, height: Int)
    
    /// Number of quality layers.
    ///
    /// - Valid range: 1-20
    /// - Default: 5 (balanced), 3 (fast), 10 (quality)
    /// - More layers = finer quality progression, slower encoding
    public var qualityLayers: Int
    
    /// Progression order for packet organization.
    ///
    /// Determines the order in which image data is encoded and streamed:
    /// - LRCP: Layer-Resolution-Component-Position (simple, good for quality)
    /// - RLCP: Resolution-Layer-Component-Position (progressive resolution)
    /// - RPCL: Resolution-Position-Component-Layer (best for streaming)
    /// - PCRL: Position-Component-Resolution-Layer (spatial locality)
    /// - CPRL: Component-Position-Resolution-Layer (component-by-component)
    public var progressionOrder: J2KProgressionOrder
    
    /// Whether to enable visual frequency weighting.
    ///
    /// When enabled, applies perceptual weighting to quantization based on
    /// the human visual system's contrast sensitivity function (CSF).
    public var enableVisualWeighting: Bool
    
    /// Tile size for tiled encoding.
    ///
    /// - (0, 0): No tiling (single tile)
    /// - Otherwise: Width and height of each tile in pixels
    /// - Tiling enables memory-efficient processing of large images
    public var tileSize: (width: Int, height: Int)
    
    /// Bitrate control mode.
    ///
    /// Determines how the encoder controls the output file size:
    /// - Constant quality: Target quality level
    /// - Constant bitrate: Target file size
    /// - Variable bitrate: Quality-constrained with size limit
    public var bitrateMode: J2KBitrateMode
    
    /// Maximum number of threads for parallel encoding.
    ///
    /// - 0: Auto-detect optimal thread count
    /// - 1: Single-threaded encoding
    /// - &gt;1: Use specified number of threads
    public var maxThreads: Int
    
    /// Whether to use HTJ2K (High-Throughput JPEG 2000) block coding.
    ///
    /// When enabled, uses the FBCOT (Fast Block Coder with Optimized Truncation)
    /// algorithm instead of traditional EBCOT, providing significantly faster
    /// encoding and decoding throughput as specified in ISO/IEC 15444-15.
    ///
    /// - Note: HTJ2K mode requires CAP and CPF markers to be written in the codestream.
    /// - Default: false (use legacy EBCOT block coding)
    public var useHTJ2K: Bool
    
    /// Whether to enable parallel code-block encoding.
    ///
    /// When enabled, independent code-blocks within a tile are encoded in parallel
    /// using Swift structured concurrency. This provides significant speedups for
    /// images with many code-blocks on multi-core systems.
    ///
    /// Each code-block in JPEG 2000 is an independent unit of entropy coding with
    /// its own MQ encoder state and context models, making them ideal for parallel
    /// processing without any synchronization overhead.
    ///
    /// - Default: true
    public var enableParallelCodeBlocks: Bool
    
    /// Creates a new encoding configuration.
    ///
    /// - Parameters:
    ///   - quality: Overall quality factor (default: 0.9).
    ///   - lossless: Whether to use lossless compression (default: false).
    ///   - decompositionLevels: Number of wavelet decomposition levels (default: 5).
    ///   - codeBlockSize: Code block dimensions (default: 32×32).
    ///   - qualityLayers: Number of quality layers (default: 5).
    ///   - progressionOrder: Packet progression order (default: .rpcl).
    ///   - enableVisualWeighting: Enable perceptual weighting (default: false).
    ///   - tileSize: Tile dimensions, (0,0) for no tiling (default: no tiling).
    ///   - bitrateMode: Bitrate control mode (default: .constantQuality).
    ///   - maxThreads: Maximum encoding threads, 0 for auto (default: 0).
    ///   - useHTJ2K: Use HTJ2K block coding (default: false).
    ///   - enableParallelCodeBlocks: Enable parallel code-block encoding (default: true).
    public init(
        quality: Double = 0.9,
        lossless: Bool = false,
        decompositionLevels: Int = 5,
        codeBlockSize: (width: Int, height: Int) = (32, 32),
        qualityLayers: Int = 5,
        progressionOrder: J2KProgressionOrder = .rpcl,
        enableVisualWeighting: Bool = false,
        tileSize: (width: Int, height: Int) = (0, 0),
        bitrateMode: J2KBitrateMode = .constantQuality,
        maxThreads: Int = 0,
        useHTJ2K: Bool = false,
        enableParallelCodeBlocks: Bool = true
    ) {
        self.quality = max(0.0, min(1.0, quality))
        self.lossless = lossless
        self.decompositionLevels = max(0, min(10, decompositionLevels))
        self.codeBlockSize = (
            width: max(4, min(1024, codeBlockSize.width)),
            height: max(4, min(1024, codeBlockSize.height))
        )
        self.qualityLayers = max(1, min(20, qualityLayers))
        self.progressionOrder = progressionOrder
        self.enableVisualWeighting = enableVisualWeighting
        self.tileSize = (
            width: max(0, tileSize.width),
            height: max(0, tileSize.height)
        )
        self.bitrateMode = bitrateMode
        self.maxThreads = max(0, maxThreads)
        self.useHTJ2K = useHTJ2K
        self.enableParallelCodeBlocks = enableParallelCodeBlocks
    }
    
    /// Validates the configuration parameters.
    ///
    /// - Throws: ``J2KError/invalidParameter(_:)`` if any parameters are invalid.
    public func validate() throws {
        if quality < 0.0 || quality > 1.0 {
            throw J2KError.invalidParameter("Quality must be between 0.0 and 1.0, got \(quality)")
        }
        
        if decompositionLevels < 0 || decompositionLevels > 10 {
            throw J2KError.invalidParameter("Decomposition levels must be between 0 and 10, got \(decompositionLevels)")
        }
        
        if codeBlockSize.width < 4 || codeBlockSize.width > 1024 {
            throw J2KError.invalidParameter("Code block width must be between 4 and 1024, got \(codeBlockSize.width)")
        }
        
        if codeBlockSize.height < 4 || codeBlockSize.height > 1024 {
            throw J2KError.invalidParameter("Code block height must be between 4 and 1024, got \(codeBlockSize.height)")
        }
        
        if qualityLayers < 1 || qualityLayers > 20 {
            throw J2KError.invalidParameter("Quality layers must be between 1 and 20, got \(qualityLayers)")
        }
        
        if tileSize.width < 0 || tileSize.height < 0 {
            throw J2KError.invalidParameter("Tile size must be non-negative")
        }
        
        if maxThreads < 0 {
            throw J2KError.invalidParameter("Max threads must be non-negative, got \(maxThreads)")
        }
    }
}

// MARK: - Progression Order

/// Progression order for JPEG 2000 packet organization.
public enum J2KProgressionOrder: String, Sendable, CaseIterable {
    /// Layer-Resolution-Component-Position progression.
    ///
    /// Encodes by quality layer first, then resolution, then component, then spatial position.
    /// Good for quality-progressive applications.
    case lrcp = "LRCP"
    
    /// Resolution-Layer-Component-Position progression.
    ///
    /// Encodes by resolution first, then quality layer, then component, then spatial position.
    /// Good for resolution-progressive applications.
    case rlcp = "RLCP"
    
    /// Resolution-Position-Component-Layer progression.
    ///
    /// Encodes by resolution first, then spatial position, then component, then quality layer.
    /// Best for streaming and progressive download.
    case rpcl = "RPCL"
    
    /// Position-Component-Resolution-Layer progression.
    ///
    /// Encodes by spatial position first, then component, then resolution, then quality layer.
    /// Good for spatial locality and region-of-interest applications.
    case pcrl = "PCRL"
    
    /// Component-Position-Resolution-Layer progression.
    ///
    /// Encodes by component first, then spatial position, then resolution, then quality layer.
    /// Good for applications that process components separately.
    case cprl = "CPRL"
}

// MARK: - Bitrate Mode

/// Bitrate control modes for encoding.
public enum J2KBitrateMode: Sendable, Equatable {
    /// Constant quality mode.
    ///
    /// Maintains consistent quality across the image.
    /// File size varies based on image complexity.
    case constantQuality
    
    /// Constant bitrate mode.
    ///
    /// Targets a specific file size or bitrate.
    /// Quality varies to achieve the target size.
    ///
    /// - Parameter bitsPerPixel: Target bits per pixel (e.g., 0.5 for 2:1 compression).
    case constantBitrate(bitsPerPixel: Double)
    
    /// Variable bitrate mode.
    ///
    /// Maintains quality above a threshold while respecting a maximum file size.
    ///
    /// - Parameters:
    ///   - minQuality: Minimum quality to maintain (0.0-1.0).
    ///   - maxBitsPerPixel: Maximum bits per pixel allowed.
    case variableBitrate(minQuality: Double, maxBitsPerPixel: Double)
    
    /// Lossless mode.
    ///
    /// Perfect reconstruction, no quality loss.
    /// File size varies significantly based on image content.
    case lossless
}

// MARK: - Preset Extensions

extension J2KEncodingPreset: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fast:
            return "Fast (2-3× faster, good quality)"
        case .balanced:
            return "Balanced (optimal quality/speed)"
        case .quality:
            return "Quality (best quality, slower)"
        }
    }
}

extension J2KBitrateMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .constantQuality:
            return "Constant Quality"
        case .constantBitrate(let bpp):
            return "Constant Bitrate (\(String(format: "%.2f", bpp)) bpp)"
        case .variableBitrate(let minQuality, let maxBpp):
            return "Variable Bitrate (min quality: \(String(format: "%.2f", minQuality)), max: \(String(format: "%.2f", maxBpp)) bpp)"
        case .lossless:
            return "Lossless"
        }
    }
}

// MARK: - Configuration Equatable Conformance

extension J2KEncodingConfiguration: Equatable {
    public static func == (lhs: J2KEncodingConfiguration, rhs: J2KEncodingConfiguration) -> Bool {
        return lhs.quality == rhs.quality &&
            lhs.lossless == rhs.lossless &&
            lhs.decompositionLevels == rhs.decompositionLevels &&
            lhs.codeBlockSize.width == rhs.codeBlockSize.width &&
            lhs.codeBlockSize.height == rhs.codeBlockSize.height &&
            lhs.qualityLayers == rhs.qualityLayers &&
            lhs.progressionOrder == rhs.progressionOrder &&
            lhs.enableVisualWeighting == rhs.enableVisualWeighting &&
            lhs.tileSize.width == rhs.tileSize.width &&
            lhs.tileSize.height == rhs.tileSize.height &&
            lhs.bitrateMode == rhs.bitrateMode &&
            lhs.maxThreads == rhs.maxThreads
    }
}
