// JP3DMultiSpectralTypes.swift
// J2KSwift
//
// Multi-spectral JP3D data types for Phase 19.
//
// JPEG XS (ISO/IEC 21122) is a lightweight, visually lossless codec.
// This module supports multi-spectral and hyperspectral JP3D volumetric imaging.

import Foundation

// MARK: - JP3DSpectralBand

/// A single spectral band in a multi-spectral JP3D volume.
///
/// Each band corresponds to a specific wavelength range in the electromagnetic
/// spectrum, enabling multi-spectral and hyperspectral image processing.
///
/// Example:
/// ```swift
/// let band = JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red")
/// print(band.wavelengthNanometres) // 665.0
/// ```
public struct JP3DSpectralBand: Sendable, Equatable {
    /// The zero-based index of this band within its volume.
    public let bandIndex: Int

    /// The centre wavelength of this band in nanometres.
    public let wavelengthNanometres: Double

    /// A human-readable description for this band (e.g. "Red", "Near-Infrared").
    public let description: String

    /// Creates a spectral band with the given index, wavelength, and description.
    ///
    /// - Parameters:
    ///   - bandIndex: The zero-based band index.
    ///   - wavelengthNanometres: Centre wavelength in nanometres.
    ///   - description: Human-readable band label.
    public init(bandIndex: Int, wavelengthNanometres: Double, description: String) {
        self.bandIndex = bandIndex
        self.wavelengthNanometres = wavelengthNanometres
        self.description = description
    }
}

// MARK: - JP3DSpectralMapping

/// A mapping from band indices to centre wavelengths.
///
/// Provides factory presets for common multi-spectral configurations as well
/// as a factory for arbitrary hyperspectral band counts.
///
/// Example:
/// ```swift
/// let mapping = JP3DSpectralMapping.visible
/// print(mapping.bands.count) // 3
/// ```
public struct JP3DSpectralMapping: Sendable, Equatable {
    /// The ordered spectral bands in this mapping.
    public let bands: [JP3DSpectralBand]

    /// Creates a spectral mapping with the given bands.
    ///
    /// - Parameter bands: An ordered array of spectral bands.
    public init(bands: [JP3DSpectralBand]) {
        self.bands = bands
    }

    // MARK: Presets

    /// Visible-light RGB mapping (Red 665 nm, Green 560 nm, Blue 490 nm).
    public static var visible: JP3DSpectralMapping {
        JP3DSpectralMapping(bands: [
            JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red"),
            JP3DSpectralBand(bandIndex: 1, wavelengthNanometres: 560.0, description: "Green"),
            JP3DSpectralBand(bandIndex: 2, wavelengthNanometres: 490.0, description: "Blue"),
        ])
    }

    /// Near-infrared mapping (Red 665 nm, NIR 842 nm, SWIR 1610 nm).
    public static var nearInfrared: JP3DSpectralMapping {
        JP3DSpectralMapping(bands: [
            JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red"),
            JP3DSpectralBand(bandIndex: 1, wavelengthNanometres: 842.0, description: "NIR"),
            JP3DSpectralBand(bandIndex: 2, wavelengthNanometres: 1610.0, description: "SWIR"),
        ])
    }

    /// Hyperspectral mapping with evenly spaced bands from 400 nm to 2500 nm.
    ///
    /// - Parameter bandCount: The number of spectral bands (minimum 1).
    /// - Returns: A `JP3DSpectralMapping` with `bandCount` evenly spaced bands.
    public static func hyperspectral(bandCount: Int) -> JP3DSpectralMapping {
        let count = max(1, bandCount)
        let startNm = 400.0
        let endNm = 2500.0
        let step = count > 1 ? (endNm - startNm) / Double(count - 1) : 0.0
        let bands = (0..<count).map { i in
            let nm = startNm + Double(i) * step
            return JP3DSpectralBand(bandIndex: i, wavelengthNanometres: nm, description: "Band \(i)")
        }
        return JP3DSpectralMapping(bands: bands)
    }
}

// MARK: - JP3DMultiSpectralVolume

/// A multi-spectral volumetric data container for JP3D encoding.
///
/// Stores per-band samples for a 3-D spatial volume (width × height × depth),
/// where each band contains `width * height * depth` `Float` samples laid out
/// in `x + y * width + z * width * height` order.
///
/// Example:
/// ```swift
/// let volume = JP3DMultiSpectralVolume(
///     width: 64, height: 64, depth: 8,
///     bands: JP3DSpectralMapping.visible.bands,
///     samplesPerBand: Array(repeating: Array(repeating: 0.5, count: 64*64*8), count: 3)
/// )
/// print(volume.bandCount)   // 3
/// print(volume.voxelCount)  // 32768
/// ```
public struct JP3DMultiSpectralVolume: Sendable {
    /// The width (X extent) of the volume in voxels.
    public let width: Int

    /// The height (Y extent) of the volume in voxels.
    public let height: Int

    /// The depth (Z extent) of the volume in voxels.
    public let depth: Int

    /// The spectral band definitions for this volume.
    public let bands: [JP3DSpectralBand]

    /// Per-band sample data; `samplesPerBand[b]` contains `width*height*depth` `Float` values.
    public let samplesPerBand: [[Float]]

    /// Creates a multi-spectral volume.
    ///
    /// - Parameters:
    ///   - width: Volume width in voxels.
    ///   - height: Volume height in voxels.
    ///   - depth: Volume depth in voxels.
    ///   - bands: Spectral band definitions.
    ///   - samplesPerBand: Float samples for each band; must match `bands.count`.
    public init(
        width: Int,
        height: Int,
        depth: Int,
        bands: [JP3DSpectralBand],
        samplesPerBand: [[Float]]
    ) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.depth = max(1, depth)
        self.bands = bands
        self.samplesPerBand = samplesPerBand
    }

    // MARK: Computed Properties

    /// The number of spectral bands.
    public var bandCount: Int { bands.count }

    /// The total number of voxels per band (`width * height * depth`).
    public var voxelCount: Int { width * height * depth }

    /// The minimum and maximum centre wavelength across all bands (in nanometres).
    ///
    /// Returns `nil` when the volume has no bands.
    public var spectralRange: (min: Double, max: Double)? {
        guard !bands.isEmpty else { return nil }
        let wavelengths = bands.map(\.wavelengthNanometres)
        return (wavelengths.min()!, wavelengths.max()!)
    }
}

// MARK: - JP3DSpectralClassification

/// Coarse land-cover / material classification labels produced by spectral analysis.
public enum JP3DSpectralClassification: Sendable, Equatable, CaseIterable {
    /// No classification available.
    case unclassified
    /// Vegetated area (grass, forest, crops).
    case vegetation
    /// Open water (lakes, rivers, ocean).
    case water
    /// Urban or built-up land.
    case urban
    /// Exposed soil or rock with no vegetation cover.
    case bareSoil
    /// Cloud or thick aerosol cover.
    case cloud
}

// MARK: - JP3DMultiSpectralStatistics

/// Descriptive statistics computed across all bands in a multi-spectral volume.
///
/// Each array is indexed by band number and has `bandCount` elements.
public struct JP3DMultiSpectralStatistics: Sendable {
    /// Per-band arithmetic mean of sample values.
    public let meanPerBand: [Double]

    /// Per-band standard deviation of sample values.
    public let stdDevPerBand: [Double]

    /// Per-band minimum sample value.
    public let minPerBand: [Double]

    /// Per-band maximum sample value.
    public let maxPerBand: [Double]

    /// Creates a statistics object.
    ///
    /// - Parameters:
    ///   - meanPerBand: Per-band mean values.
    ///   - stdDevPerBand: Per-band standard deviation values.
    ///   - minPerBand: Per-band minimum values.
    ///   - maxPerBand: Per-band maximum values.
    public init(
        meanPerBand: [Double],
        stdDevPerBand: [Double],
        minPerBand: [Double],
        maxPerBand: [Double]
    ) {
        self.meanPerBand = meanPerBand
        self.stdDevPerBand = stdDevPerBand
        self.minPerBand = minPerBand
        self.maxPerBand = maxPerBand
    }
}

// MARK: - JP3DSpectralConfiguration

/// Configuration for multi-spectral JP3D encoding.
///
/// Controls the spectral mapping used, normalisation range for sample values,
/// and whether inter-band prediction is applied during encoding.
public struct JP3DSpectralConfiguration: Sendable {
    /// The spectral band mapping for this volume.
    public var spectralMapping: JP3DSpectralMapping

    /// The normalisation range applied to sample values before encoding.
    public var normalisationRange: ClosedRange<Double>

    /// When `true`, the encoder applies inter-band prediction to exploit
    /// correlations between adjacent spectral bands.
    public var enableInterBandPrediction: Bool

    /// Creates a spectral configuration.
    ///
    /// - Parameters:
    ///   - spectralMapping: The spectral mapping to use.
    ///   - normalisationRange: The normalisation range for sample values.
    ///   - enableInterBandPrediction: Whether to apply inter-band prediction.
    public init(
        spectralMapping: JP3DSpectralMapping,
        normalisationRange: ClosedRange<Double>,
        enableInterBandPrediction: Bool
    ) {
        self.spectralMapping = spectralMapping
        self.normalisationRange = normalisationRange
        self.enableInterBandPrediction = enableInterBandPrediction
    }

    /// Default spectral configuration using visible-light mapping, [0, 1] normalisation,
    /// and inter-band prediction disabled.
    public static let `default` = JP3DSpectralConfiguration(
        spectralMapping: .visible,
        normalisationRange: 0.0...1.0,
        enableInterBandPrediction: false
    )
}
