/// # JP3DTiling
///
/// 3D tiling implementation for JP3D volumetric encoding.
///
/// Provides tile decomposition, voxel data extraction from volumes,
/// and boundary handling for partial tiles at volume edges.
///
/// ## Topics
///
/// ### Tiling Types
/// - ``JP3DTileDecomposer``
/// - ``JP3DTileData``

import Foundation
import J2KCore

/// Data extracted from a single 3D tile.
///
/// Contains the voxel data for a specific tile region within a volume,
/// for all components.
public struct JP3DTileData: Sendable {
    /// The tile this data belongs to.
    public let tile: JP3DTile

    /// The component index.
    public let componentIndex: Int

    /// Voxel data as Float values in row-major order: index = z*width*height + y*width + x.
    public let data: [Float]

    /// The width of this tile's data.
    public var width: Int { tile.width }

    /// The height of this tile's data.
    public var height: Int { tile.height }

    /// The depth of this tile's data.
    public var depth: Int { tile.depth }
}

/// Decomposes a volume into tiles and extracts tile data.
///
/// `JP3DTileDecomposer` handles the decomposition of a `J2KVolume` into
/// independent tiles suitable for parallel encoding. It correctly handles
/// partial tiles at volume boundaries.
///
/// Example:
/// ```swift
/// let decomposer = JP3DTileDecomposer(configuration: .default)
/// let tiles = decomposer.decompose(volume: volume)
/// let tileData = try decomposer.extractTileData(
///     from: volume, tile: tiles[0], componentIndex: 0
/// )
/// ```
public struct JP3DTileDecomposer: Sendable {
    /// The tiling configuration.
    public let configuration: JP3DTilingConfiguration

    /// Creates a tile decomposer with the given configuration.
    ///
    /// - Parameter configuration: The tiling configuration. Defaults to `.default`.
    public init(configuration: JP3DTilingConfiguration = .default) {
        self.configuration = configuration
    }

    /// Decomposes a volume into tiles.
    ///
    /// Computes all tiles covering the given volume, with partial tiles
    /// at the right, bottom, and back edges clamped to volume dimensions.
    ///
    /// - Parameter volume: The volume to decompose.
    /// - Returns: All tiles covering the volume.
    public func decompose(volume: J2KVolume) -> [JP3DTile] {
        // Clamp tile sizes to volume dimensions
        let effectiveConfig = clampedConfiguration(for: volume)
        return effectiveConfig.allTiles(
            volumeWidth: volume.width,
            volumeHeight: volume.height,
            volumeDepth: volume.depth
        )
    }

    /// Extracts voxel data for a specific tile and component.
    ///
    /// - Parameters:
    ///   - volume: The source volume.
    ///   - tile: The tile to extract data for.
    ///   - componentIndex: The component index.
    /// - Returns: The extracted tile data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the component index is out of range.
    public func extractTileData(
        from volume: J2KVolume,
        tile: JP3DTile,
        componentIndex: Int
    ) throws -> JP3DTileData {
        guard componentIndex >= 0, componentIndex < volume.components.count else {
            throw J2KError.invalidParameter(
                "Component index \(componentIndex) out of range [0, \(volume.components.count))"
            )
        }

        let component = volume.components[componentIndex]
        let tw = tile.width
        let th = tile.height
        let td = tile.depth
        let bytesPerSample = component.bytesPerSample
        var data = [Float](repeating: 0, count: tw * th * td)

        let region = tile.region
        for z in 0..<td {
            let srcZ = region.z.lowerBound + z
            guard srcZ < component.depth else { continue }
            for y in 0..<th {
                let srcY = region.y.lowerBound + y
                guard srcY < component.height else { continue }
                for x in 0..<tw {
                    let srcX = region.x.lowerBound + x
                    guard srcX < component.width else { continue }
                    let srcIdx = srcZ * component.width * component.height + srcY * component.width + srcX
                    let byteOffset = srcIdx * bytesPerSample
                    let dstIdx = z * tw * th + y * tw + x
                    if byteOffset + bytesPerSample <= component.data.count {
                        data[dstIdx] = readSample(
                            from: component.data,
                            at: byteOffset,
                            bytesPerSample: bytesPerSample,
                            signed: component.signed
                        )
                    }
                }
            }
        }

        return JP3DTileData(tile: tile, componentIndex: componentIndex, data: data)
    }

    /// Reads a single sample value from component data bytes.
    private func readSample(
        from data: Data, at offset: Int, bytesPerSample: Int, signed: Bool
    ) -> Float {
        var value: Int = 0
        for b in 0..<bytesPerSample {
            value |= Int(data[offset + b]) << (b * 8)
        }
        if signed && bytesPerSample > 0 {
            let signBit = 1 << (bytesPerSample * 8 - 1)
            if value & signBit != 0 {
                value -= (signBit << 1)
            }
        }
        return Float(value)
    }

    /// Returns a tiling configuration clamped to volume dimensions.
    ///
    /// If tile sizes exceed the volume, they are clamped to the volume dimensions
    /// so a single tile covers the entire volume.
    ///
    /// - Parameter volume: The volume.
    /// - Returns: A clamped tiling configuration.
    public func clampedConfiguration(for volume: J2KVolume) -> JP3DTilingConfiguration {
        return JP3DTilingConfiguration(
            tileSizeX: min(configuration.tileSizeX, max(1, volume.width)),
            tileSizeY: min(configuration.tileSizeY, max(1, volume.height)),
            tileSizeZ: min(configuration.tileSizeZ, max(1, volume.depth))
        )
    }

    /// Returns the tile grid dimensions for a volume.
    ///
    /// - Parameter volume: The volume.
    /// - Returns: (tilesX, tilesY, tilesZ).
    public func tileGrid(for volume: J2KVolume) -> (tilesX: Int, tilesY: Int, tilesZ: Int) {
        return configuration.tileGrid(
            volumeWidth: volume.width,
            volumeHeight: volume.height,
            volumeDepth: volume.depth
        )
    }
}
