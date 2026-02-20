/// # JP3DConfiguration
///
/// Configuration types for JP3D volumetric JPEG 2000 encoding.
///
/// This file provides configuration structures for 3D tiling, progression orders,
/// compression modes, and wavelet coefficient storage.
///
/// ## Topics
///
/// ### Configuration Types
/// - ``JP3DTilingConfiguration``
/// - ``JP3DProgressionOrder``
/// - ``JP3DCompressionMode``
/// - ``J2K3DCoefficients``

import Foundation
import J2KCore

/// Configuration for 3D tile decomposition in JP3D.
///
/// Tiles are the fundamental unit of independent processing in JP3D. This
/// configuration specifies tile sizes along each axis and provides presets
/// for common use cases.
///
/// Example:
/// ```swift
/// let config = JP3DTilingConfiguration.streaming
/// print("Tile size: \(config.tileSizeX)×\(config.tileSizeY)×\(config.tileSizeZ)")
/// ```
public struct JP3DTilingConfiguration: Sendable, Equatable {
    /// The tile size along the X-axis in voxels.
    public let tileSizeX: Int

    /// The tile size along the Y-axis in voxels.
    public let tileSizeY: Int

    /// The tile size along the Z-axis in voxels.
    public let tileSizeZ: Int

    /// Creates a tiling configuration with the specified tile sizes.
    ///
    /// - Parameters:
    ///   - tileSizeX: Tile size along X (default: 256).
    ///   - tileSizeY: Tile size along Y (default: 256).
    ///   - tileSizeZ: Tile size along Z (default: 16).
    public init(tileSizeX: Int = 256, tileSizeY: Int = 256, tileSizeZ: Int = 16) {
        self.tileSizeX = max(1, tileSizeX)
        self.tileSizeY = max(1, tileSizeY)
        self.tileSizeZ = max(1, tileSizeZ)
    }

    // MARK: - Presets

    /// Default tiling configuration (256×256×16).
    public static let `default` = JP3DTilingConfiguration(
        tileSizeX: 256, tileSizeY: 256, tileSizeZ: 16
    )

    /// Streaming-optimized tiling configuration (128×128×8).
    ///
    /// Smaller tiles for lower latency progressive delivery.
    public static let streaming = JP3DTilingConfiguration(
        tileSizeX: 128, tileSizeY: 128, tileSizeZ: 8
    )

    /// Batch processing tiling configuration (512×512×32).
    ///
    /// Larger tiles for higher compression efficiency.
    public static let batch = JP3DTilingConfiguration(
        tileSizeX: 512, tileSizeY: 512, tileSizeZ: 32
    )

    // MARK: - Tile Grid Computation

    /// Computes the number of tiles along each axis for the given volume dimensions.
    ///
    /// - Parameters:
    ///   - volumeWidth: The width of the volume.
    ///   - volumeHeight: The height of the volume.
    ///   - volumeDepth: The depth of the volume.
    /// - Returns: A tuple of (tilesX, tilesY, tilesZ).
    public func tileGrid(
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> (tilesX: Int, tilesY: Int, tilesZ: Int) {
        let tx = max(1, (volumeWidth + tileSizeX - 1) / tileSizeX)
        let ty = max(1, (volumeHeight + tileSizeY - 1) / tileSizeY)
        let tz = max(1, (volumeDepth + tileSizeZ - 1) / tileSizeZ)
        return (tx, ty, tz)
    }

    /// Returns the total number of tiles for the given volume dimensions.
    ///
    /// - Parameters:
    ///   - volumeWidth: The width of the volume.
    ///   - volumeHeight: The height of the volume.
    ///   - volumeDepth: The depth of the volume.
    /// - Returns: The total number of tiles.
    public func totalTiles(
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> Int {
        let grid = tileGrid(
            volumeWidth: volumeWidth, volumeHeight: volumeHeight, volumeDepth: volumeDepth
        )
        return grid.tilesX * grid.tilesY * grid.tilesZ
    }

    /// Computes the tile at the given grid indices for the specified volume.
    ///
    /// The tile region is clamped to the volume dimensions for boundary tiles.
    ///
    /// - Parameters:
    ///   - indexX: The tile index along X.
    ///   - indexY: The tile index along Y.
    ///   - indexZ: The tile index along Z.
    ///   - volumeWidth: The width of the volume.
    ///   - volumeHeight: The height of the volume.
    ///   - volumeDepth: The depth of the volume.
    /// - Returns: The `JP3DTile` at the given indices.
    public func tile(
        atX indexX: Int, y indexY: Int, z indexZ: Int,
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> JP3DTile {
        let startX = indexX * tileSizeX
        let startY = indexY * tileSizeY
        let startZ = indexZ * tileSizeZ
        let endX = min(startX + tileSizeX, volumeWidth)
        let endY = min(startY + tileSizeY, volumeHeight)
        let endZ = min(startZ + tileSizeZ, volumeDepth)

        let region = JP3DRegion(
            x: startX..<endX,
            y: startY..<endY,
            z: startZ..<endZ
        )

        return JP3DTile(indexX: indexX, indexY: indexY, indexZ: indexZ, region: region)
    }

    /// Computes all tiles for the given volume dimensions.
    ///
    /// - Parameters:
    ///   - volumeWidth: The width of the volume.
    ///   - volumeHeight: The height of the volume.
    ///   - volumeDepth: The depth of the volume.
    /// - Returns: An array of all tiles covering the volume.
    public func allTiles(
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> [JP3DTile] {
        let grid = tileGrid(
            volumeWidth: volumeWidth, volumeHeight: volumeHeight, volumeDepth: volumeDepth
        )
        var tiles: [JP3DTile] = []
        tiles.reserveCapacity(grid.tilesX * grid.tilesY * grid.tilesZ)

        for iz in 0..<grid.tilesZ {
            for iy in 0..<grid.tilesY {
                for ix in 0..<grid.tilesX {
                    tiles.append(
                        tile(
                            atX: ix, y: iy, z: iz,
                            volumeWidth: volumeWidth,
                            volumeHeight: volumeHeight,
                            volumeDepth: volumeDepth
                        )
                    )
                }
            }
        }

        return tiles
    }

    /// Returns tiles that intersect with the given region.
    ///
    /// - Parameters:
    ///   - region: The region of interest.
    ///   - volumeWidth: The width of the volume.
    ///   - volumeHeight: The height of the volume.
    ///   - volumeDepth: The depth of the volume.
    /// - Returns: An array of tiles that intersect the region.
    public func tilesIntersecting(
        region: JP3DRegion,
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> [JP3DTile] {
        let startTileX = max(0, region.x.lowerBound / tileSizeX)
        let startTileY = max(0, region.y.lowerBound / tileSizeY)
        let startTileZ = max(0, region.z.lowerBound / tileSizeZ)

        let grid = tileGrid(
            volumeWidth: volumeWidth, volumeHeight: volumeHeight, volumeDepth: volumeDepth
        )
        let endTileX = min(grid.tilesX, (region.x.upperBound + tileSizeX - 1) / tileSizeX)
        let endTileY = min(grid.tilesY, (region.y.upperBound + tileSizeY - 1) / tileSizeY)
        let endTileZ = min(grid.tilesZ, (region.z.upperBound + tileSizeZ - 1) / tileSizeZ)

        var result: [JP3DTile] = []

        for iz in startTileZ..<endTileZ {
            for iy in startTileY..<endTileY {
                for ix in startTileX..<endTileX {
                    result.append(
                        tile(
                            atX: ix, y: iy, z: iz,
                            volumeWidth: volumeWidth,
                            volumeHeight: volumeHeight,
                            volumeDepth: volumeDepth
                        )
                    )
                }
            }
        }

        return result
    }

    /// Validates the tiling configuration.
    ///
    /// - Throws: ``J2KError/invalidTileConfiguration(_:)`` if tile sizes are invalid.
    public func validate() throws {
        guard tileSizeX > 0 && tileSizeY > 0 && tileSizeZ > 0 else {
            throw J2KError.invalidTileConfiguration(
                "Tile dimensions must be positive: \(tileSizeX)×\(tileSizeY)×\(tileSizeZ)"
            )
        }
    }
}

/// Progression order for JP3D encoding.
///
/// Defines the order in which data is organized in the JP3D codestream,
/// affecting how the volume can be progressively decoded.
public enum JP3DProgressionOrder: String, Sendable, Equatable, CaseIterable {
    /// Layer-Resolution-Component-Position-Slice.
    ///
    /// Default quality-scalable progression. Quality layers are delivered first,
    /// enabling progressive quality improvement.
    case lrcps = "LRCPS"

    /// Resolution-Layer-Component-Position-Slice.
    ///
    /// Resolution-first progression. Enables progressive resolution improvement
    /// from coarse to fine.
    case rlcps = "RLCPS"

    /// Position-Component-Resolution-Layer-Slice.
    ///
    /// Spatial-first progression. Groups data by spatial position for efficient
    /// ROI access.
    case pcrls = "PCRLS"

    /// Slice-Layer-Resolution-Component-Position.
    ///
    /// Z-axis first progression. Delivers complete slices sequentially, useful
    /// for slice-by-slice viewing.
    case slrcp = "SLRCP"

    /// Component-Position-Resolution-Layer-Slice.
    ///
    /// Component-first progression. Groups data by component for efficient
    /// multi-spectral/hyperspectral processing.
    case cprls = "CPRLS"
}

/// Compression mode for JP3D encoding.
///
/// Specifies the compression strategy, including lossless, lossy, and
/// HTJ2K-accelerated variants.
public enum JP3DCompressionMode: Sendable, Equatable {
    /// Mathematically lossless compression using 5/3 reversible wavelet.
    case lossless

    /// Lossy compression using 9/7 irreversible wavelet with target PSNR.
    ///
    /// - Parameter psnr: Target peak signal-to-noise ratio in dB.
    case lossy(psnr: Double)

    /// Lossy compression with target bitrate.
    ///
    /// - Parameter bitsPerVoxel: Target bits per voxel.
    case targetBitrate(bitsPerVoxel: Double)

    /// Visually lossless compression.
    ///
    /// Uses high-quality lossy settings that produce imperceptible distortion
    /// for typical viewing conditions.
    case visuallyLossless

    /// Lossless compression using HTJ2K for high throughput.
    case losslessHTJ2K

    /// Lossy compression using HTJ2K for high throughput.
    ///
    /// - Parameter psnr: Target peak signal-to-noise ratio in dB.
    case lossyHTJ2K(psnr: Double)

    /// Whether this mode produces mathematically lossless output.
    public var isLossless: Bool {
        switch self {
        case .lossless, .losslessHTJ2K:
            return true
        default:
            return false
        }
    }

    /// Whether this mode uses HTJ2K encoding.
    public var isHTJ2K: Bool {
        switch self {
        case .losslessHTJ2K, .lossyHTJ2K:
            return true
        default:
            return false
        }
    }
}

/// Storage for 3D wavelet coefficients.
///
/// `J2K3DCoefficients` stores the output of a 3D discrete wavelet transform,
/// organized by decomposition level and subband.
public struct J2K3DCoefficients: Sendable {
    /// The width of the coefficient array.
    public let width: Int

    /// The height of the coefficient array.
    public let height: Int

    /// The depth of the coefficient array.
    public let depth: Int

    /// The number of decomposition levels.
    public let decompositionLevels: Int

    /// The coefficient data stored as Float values.
    public var data: [Float]

    /// Creates a coefficient storage with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The width of the coefficient array.
    ///   - height: The height of the coefficient array.
    ///   - depth: The depth of the coefficient array.
    ///   - decompositionLevels: The number of wavelet decomposition levels.
    public init(width: Int, height: Int, depth: Int, decompositionLevels: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.depth = max(1, depth)
        self.decompositionLevels = max(0, decompositionLevels)
        self.data = [Float](repeating: 0, count: self.width * self.height * self.depth)
    }

    /// The total number of coefficients.
    public var count: Int {
        width * height * depth
    }

    /// Accesses a coefficient at the given 3D coordinates.
    ///
    /// - Parameters:
    ///   - x: The X coordinate.
    ///   - y: The Y coordinate.
    ///   - z: The Z coordinate.
    /// - Returns: The coefficient value.
    public subscript(x: Int, y: Int, z: Int) -> Float {
        get {
            data[z * width * height + y * width + x]
        }
        set {
            data[z * width * height + y * width + x] = newValue
        }
    }
}

/// 3D subband identifier for volumetric wavelet decomposition.
///
/// In a 3D wavelet transform, each decomposition level produces 8 subbands
/// (2³ from filtering along 3 axes).
public enum JP3DSubband: String, Sendable, Equatable, CaseIterable {
    /// Low-Low-Low (approximation).
    case lll = "LLL"

    /// High-Low-Low (X detail).
    case hll = "HLL"

    /// Low-High-Low (Y detail).
    case lhl = "LHL"

    /// High-High-Low (XY detail).
    case hhl = "HHL"

    /// Low-Low-High (Z detail).
    case llh = "LLH"

    /// High-Low-High (XZ detail).
    case hlh = "HLH"

    /// Low-High-High (YZ detail).
    case lhh = "LHH"

    /// High-High-High (XYZ detail).
    case hhh = "HHH"
}
