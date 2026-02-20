//
// JP3DTypes.swift
// J2KSwift
//
/// # JP3DTypes
///
/// 3D spatial types for ISO/IEC 15444-10 (JP3D) volumetric JPEG 2000.
///
/// This file provides spatial types for representing regions, tiles, and precincts
/// in three-dimensional space for JP3D encoding and decoding.
///
/// ## Topics
///
/// ### Spatial Types
/// - ``JP3DRegion``
/// - ``JP3DTile``
/// - ``JP3DPrecinct``

import Foundation
import J2KCore

/// Represents a three-dimensional region of interest within a volume.
///
/// A `JP3DRegion` defines a rectangular cuboid region specified by
/// start and end coordinates along each axis. Regions are used for
/// ROI specification in encoding, decoding, and streaming operations.
///
/// Example:
/// ```swift
/// let roi = JP3DRegion(x: 0..<128, y: 0..<128, z: 10..<20)
/// print("Volume: \(roi.volume) voxels")
/// ```
public struct JP3DRegion: Sendable, Equatable {
    /// The range along the X-axis.
    public let x: Range<Int>

    /// The range along the Y-axis.
    public let y: Range<Int>

    /// The range along the Z-axis.
    public let z: Range<Int>

    /// Creates a region with the specified ranges.
    ///
    /// - Parameters:
    ///   - x: The range along the X-axis.
    ///   - y: The range along the Y-axis.
    ///   - z: The range along the Z-axis.
    public init(x: Range<Int>, y: Range<Int>, z: Range<Int>) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Creates a region from origin coordinates and dimensions.
    ///
    /// - Parameters:
    ///   - originX: The starting X coordinate.
    ///   - originY: The starting Y coordinate.
    ///   - originZ: The starting Z coordinate.
    ///   - width: The extent along X.
    ///   - height: The extent along Y.
    ///   - depth: The extent along Z.
    public init(originX: Int, originY: Int, originZ: Int, width: Int, height: Int, depth: Int) {
        self.x = originX..<(originX + width)
        self.y = originY..<(originY + height)
        self.z = originZ..<(originZ + depth)
    }

    // MARK: - Properties

    /// The width of the region (extent along X).
    public var width: Int { x.count }

    /// The height of the region (extent along Y).
    public var height: Int { y.count }

    /// The depth of the region (extent along Z).
    public var depth: Int { z.count }

    /// The total number of voxels in this region.
    public var volume: Int { width * height * depth }

    /// Returns true if the region is empty (zero volume).
    public var isEmpty: Bool { width <= 0 || height <= 0 || depth <= 0 }

    /// Returns the intersection of this region with another region.
    ///
    /// - Parameter other: The other region to intersect with.
    /// - Returns: The intersection region, or nil if they don't overlap.
    public func intersection(_ other: JP3DRegion) -> JP3DRegion? {
        let xStart = max(x.lowerBound, other.x.lowerBound)
        let xEnd = min(x.upperBound, other.x.upperBound)
        let yStart = max(y.lowerBound, other.y.lowerBound)
        let yEnd = min(y.upperBound, other.y.upperBound)
        let zStart = max(z.lowerBound, other.z.lowerBound)
        let zEnd = min(z.upperBound, other.z.upperBound)

        guard xStart < xEnd && yStart < yEnd && zStart < zEnd else {
            return nil
        }

        return JP3DRegion(x: xStart..<xEnd, y: yStart..<yEnd, z: zStart..<zEnd)
    }

    /// Returns true if this region contains the specified point.
    ///
    /// - Parameters:
    ///   - px: The X coordinate.
    ///   - py: The Y coordinate.
    ///   - pz: The Z coordinate.
    /// - Returns: True if the point is within this region.
    public func contains(x px: Int, y py: Int, z pz: Int) -> Bool {
        x.contains(px) && y.contains(py) && z.contains(pz)
    }

    /// Returns a region clamped to the given volume dimensions.
    ///
    /// - Parameters:
    ///   - width: The maximum width (X extent).
    ///   - height: The maximum height (Y extent).
    ///   - depth: The maximum depth (Z extent).
    /// - Returns: A new region clamped to valid bounds.
    public func clamped(toWidth width: Int, height: Int, depth: Int) -> JP3DRegion {
        let clampedX = max(0, x.lowerBound)..<min(width, x.upperBound)
        let clampedY = max(0, y.lowerBound)..<min(height, y.upperBound)
        let clampedZ = max(0, z.lowerBound)..<min(depth, z.upperBound)
        return JP3DRegion(x: clampedX, y: clampedY, z: clampedZ)
    }
}

/// Represents a three-dimensional tile in a JP3D volume.
///
/// Tiles are the fundamental unit of independent encoding/decoding in JP3D.
/// Each tile can be processed independently, enabling parallel processing.
public struct JP3DTile: Sendable, Equatable {
    /// The tile index along the X-axis.
    public let indexX: Int

    /// The tile index along the Y-axis.
    public let indexY: Int

    /// The tile index along the Z-axis.
    public let indexZ: Int

    /// The region of the volume covered by this tile.
    public let region: JP3DRegion

    /// Creates a new 3D tile.
    ///
    /// - Parameters:
    ///   - indexX: The tile index along X.
    ///   - indexY: The tile index along Y.
    ///   - indexZ: The tile index along Z.
    ///   - region: The spatial region covered by this tile.
    public init(indexX: Int, indexY: Int, indexZ: Int, region: JP3DRegion) {
        self.indexX = indexX
        self.indexY = indexY
        self.indexZ = indexZ
        self.region = region
    }

    /// The linear index of this tile in a tile grid.
    ///
    /// - Parameters:
    ///   - tilesX: Total tiles along X.
    ///   - tilesY: Total tiles along Y.
    /// - Returns: The linear tile index.
    public func linearIndex(tilesX: Int, tilesY: Int) -> Int {
        indexZ * tilesX * tilesY + indexY * tilesX + indexX
    }

    /// The width of this tile in voxels.
    public var width: Int { region.width }

    /// The height of this tile in voxels.
    public var height: Int { region.height }

    /// The depth of this tile in voxels.
    public var depth: Int { region.depth }
}

/// Represents a three-dimensional precinct in the wavelet decomposition.
///
/// Precincts provide spatial indexing within a resolution level for
/// progressive and ROI decoding. Each precinct groups code-blocks
/// within a spatial region at a specific decomposition level.
public struct JP3DPrecinct: Sendable, Equatable {
    /// The precinct index along the X-axis.
    public let indexX: Int

    /// The precinct index along the Y-axis.
    public let indexY: Int

    /// The precinct index along the Z-axis.
    public let indexZ: Int

    /// The resolution level of this precinct.
    public let resolutionLevel: Int

    /// The component index.
    public let componentIndex: Int

    /// The spatial region covered by this precinct.
    public let region: JP3DRegion

    /// Creates a new 3D precinct.
    ///
    /// - Parameters:
    ///   - indexX: Precinct index along X.
    ///   - indexY: Precinct index along Y.
    ///   - indexZ: Precinct index along Z.
    ///   - resolutionLevel: The decomposition level.
    ///   - componentIndex: The component index.
    ///   - region: The spatial region covered.
    public init(
        indexX: Int,
        indexY: Int,
        indexZ: Int,
        resolutionLevel: Int,
        componentIndex: Int,
        region: JP3DRegion
    ) {
        self.indexX = indexX
        self.indexY = indexY
        self.indexZ = indexZ
        self.resolutionLevel = resolutionLevel
        self.componentIndex = componentIndex
        self.region = region
    }

    /// The linear index of this precinct in a precinct grid.
    ///
    /// - Parameters:
    ///   - precinctsX: Total precincts along X.
    ///   - precinctsY: Total precincts along Y.
    /// - Returns: The linear precinct index.
    public func linearIndex(precinctsX: Int, precinctsY: Int) -> Int {
        indexZ * precinctsX * precinctsY + indexY * precinctsX + indexX
    }
}
