// JP3DSpectralAnalysis.swift
// J2KSwift
//
// Spectral index computation and inter-band correlation analysis for JP3D volumes.

import Foundation
import J2KCore

// MARK: - JP3DSpectralIndex

/// Standard normalised spectral indices for remote-sensing analysis.
public enum JP3DSpectralIndex: Sendable, Equatable, CaseIterable {
    /// Normalised Difference Vegetation Index (NDVI).
    ///
    /// NDVI = (NIR − Red) / (NIR + Red). Values range from −1 to +1;
    /// positive values indicate vegetation.
    case ndvi

    /// Normalised Difference Water Index (NDWI).
    ///
    /// NDWI = (Green − NIR) / (Green + NIR). Positive values indicate open water.
    case ndwi

    /// Normalised Difference Built-up Index (NDBI).
    ///
    /// NDBI = (SWIR − NIR) / (SWIR + NIR). Positive values indicate urban areas.
    case ndbi
}

// MARK: - JP3DSpectralIndexResult

/// The computed values for a single spectral index over a multi-spectral volume.
///
/// `values` contains one entry per Z-slice; each entry is a `[Float]` of
/// `width * height` values in row-major order.
public struct JP3DSpectralIndexResult: Sendable {
    /// The spectral index that was computed.
    public let index: JP3DSpectralIndex

    /// Per-Z-slice index values; `values[z]` has `width * height` entries.
    public let values: [[Float]]

    /// Creates a spectral index result.
    ///
    /// - Parameters:
    ///   - index: The spectral index.
    ///   - values: Per-Z-slice arrays of computed index values.
    public init(index: JP3DSpectralIndex, values: [[Float]]) {
        self.index = index
        self.values = values
    }
}

// MARK: - JP3DSpectralAnalyser

/// Actor that computes spectral indices and inter-band correlation matrices
/// for multi-spectral JP3D volumes.
///
/// Example:
/// ```swift
/// let analyser = JP3DSpectralAnalyser()
/// let result = try await analyser.computeIndex(volume, index: .ndvi)
/// ```
public actor JP3DSpectralAnalyser {
    /// Creates a new spectral analyser.
    public init() {}

    // MARK: - Public Interface

    /// Computes the specified spectral index over all Z-slices of a volume.
    ///
    /// Band assignment follows the spectral mapping of the volume:
    /// - **NDVI**: requires bands with wavelengths closest to Red (~665 nm) and NIR (~842 nm).
    /// - **NDWI**: requires bands closest to Green (~560 nm) and NIR (~842 nm).
    /// - **NDBI**: requires bands closest to NIR (~842 nm) and SWIR (~1610 nm).
    ///
    /// - Parameters:
    ///   - volume: The multi-spectral volume.
    ///   - index: The spectral index to compute.
    /// - Returns: A ``JP3DSpectralIndexResult`` with per-Z-slice arrays.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if required bands are missing.
    public func computeIndex(
        _ volume: JP3DMultiSpectralVolume,
        index: JP3DSpectralIndex
    ) async throws -> JP3DSpectralIndexResult {
        let (bandA, bandB) = try resolveBandPair(for: index, in: volume)
        let planeSize = volume.width * volume.height

        let slices: [[Float]] = (0..<volume.depth).map { z in
            let offset = z * planeSize
            return (0..<planeSize).map { p in
                let i = offset + p
                guard i < volume.samplesPerBand[bandA].count,
                      i < volume.samplesPerBand[bandB].count else { return 0 }
                let a = volume.samplesPerBand[bandA][i]
                let b = volume.samplesPerBand[bandB][i]
                let denom = a + b
                return denom == 0 ? 0 : (b - a) / denom
            }
        }

        return JP3DSpectralIndexResult(index: index, values: slices)
    }

    /// Computes the Pearson inter-band correlation matrix for a multi-spectral volume.
    ///
    /// Returns a `bandCount × bandCount` matrix where entry `[i][j]` is the
    /// Pearson correlation coefficient between band `i` and band `j`.
    ///
    /// - Parameter volume: The multi-spectral volume.
    /// - Returns: A 2-D array of correlation coefficients.
    public func computeCorrelationMatrix(
        _ volume: JP3DMultiSpectralVolume
    ) async -> [[Double]] {
        let n = volume.bandCount
        guard n > 0 else { return [] }

        // Pre-compute means.
        let means: [Double] = volume.samplesPerBand.map { samples in
            guard !samples.isEmpty else { return 0 }
            return samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count)
        }

        // Pre-compute standard deviations.
        let stds: [Double] = volume.samplesPerBand.enumerated().map { (b, samples) in
            guard !samples.isEmpty else { return 1 }
            let mu = means[b]
            let variance = samples.reduce(0.0) { acc, v in
                let d = Double(v) - mu; return acc + d * d
            } / Double(samples.count)
            return max(1e-12, variance.squareRoot())
        }

        var matrix = [[Double]](
            repeating: [Double](repeating: 0, count: n),
            count: n
        )

        for i in 0..<n {
            for j in i..<n {
                if i == j {
                    matrix[i][j] = 1.0
                } else {
                    let sampA = volume.samplesPerBand[i]
                    let sampB = volume.samplesPerBand[j]
                    let count = min(sampA.count, sampB.count)
                    guard count > 0 else { continue }
                    var cov = 0.0
                    for k in 0..<count {
                        cov += (Double(sampA[k]) - means[i]) * (Double(sampB[k]) - means[j])
                    }
                    cov /= Double(count)
                    let r = cov / (stds[i] * stds[j])
                    matrix[i][j] = r
                    matrix[j][i] = r
                }
            }
        }

        return matrix
    }

    // MARK: - Private Helpers

    /// Resolves the two band indices required for a given spectral index.
    ///
    /// - Parameters:
    ///   - index: The spectral index.
    ///   - volume: The volume whose bands are searched.
    /// - Returns: A tuple `(bandA, bandB)` where `bandA` is the first operand
    ///   and `bandB` is the second operand in the index formula.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the volume has fewer than
    ///   two bands.
    private func resolveBandPair(
        for index: JP3DSpectralIndex,
        in volume: JP3DMultiSpectralVolume
    ) throws -> (Int, Int) {
        guard volume.bandCount >= 2 else {
            throw J2KError.invalidParameter(
                "At least 2 bands are required to compute spectral index \(index)"
            )
        }

        func closestBand(to targetNm: Double) -> Int {
            volume.bands.enumerated().min(by: {
                abs($0.element.wavelengthNanometres - targetNm) <
                abs($1.element.wavelengthNanometres - targetNm)
            })?.offset ?? 0
        }

        switch index {
        case .ndvi:
            // (NIR − Red) / (NIR + Red) → bandA=Red, bandB=NIR
            return (closestBand(to: 665), closestBand(to: 842))
        case .ndwi:
            // (Green − NIR) / (Green + NIR) → bandA=Green, bandB=NIR
            return (closestBand(to: 560), closestBand(to: 842))
        case .ndbi:
            // (SWIR − NIR) / (SWIR + NIR) → bandA=NIR, bandB=SWIR
            return (closestBand(to: 842), closestBand(to: 1610))
        }
    }
}
