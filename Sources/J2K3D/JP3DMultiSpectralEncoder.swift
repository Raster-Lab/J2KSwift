// JP3DMultiSpectralEncoder.swift
// J2KSwift
//
// Actor-based encoder for multi-spectral JP3D volumetric data.

import Foundation
import J2KCore

// MARK: - JP3DMultiSpectralEncoderConfiguration

/// Configuration for the multi-spectral JP3D encoder.
///
/// Wraps a base `JP3DEncoderConfiguration`, adds spectral-specific settings,
/// and controls per-band quality layers and inter-band decorrelation.
///
/// Example:
/// ```swift
/// let config = JP3DMultiSpectralEncoderConfiguration.default
/// ```
public struct JP3DMultiSpectralEncoderConfiguration: Sendable {
    /// The base JP3D encoding configuration (tiling, wavelet, etc.).
    public var baseConfiguration: JP3DEncoderConfiguration

    /// The spectral-specific configuration (mapping, normalisation, prediction).
    public var spectralConfig: JP3DSpectralConfiguration

    /// Number of quality layers encoded per spectral band.
    public var qualityLayersPerBand: Int

    /// When `true`, the encoder applies a spectral decorrelation transform
    /// (principal component approximation) before per-band compression.
    public var enableSpectralDecorelation: Bool

    /// Creates an encoder configuration.
    ///
    /// - Parameters:
    ///   - baseConfiguration: The base JP3D encoder configuration.
    ///   - spectralConfig: The spectral configuration.
    ///   - qualityLayersPerBand: Quality layers per band (clamped to ≥ 1).
    ///   - enableSpectralDecorelation: Whether to apply spectral decorrelation.
    public init(
        baseConfiguration: JP3DEncoderConfiguration,
        spectralConfig: JP3DSpectralConfiguration,
        qualityLayersPerBand: Int,
        enableSpectralDecorelation: Bool
    ) {
        self.baseConfiguration = baseConfiguration
        self.spectralConfig = spectralConfig
        self.qualityLayersPerBand = max(1, qualityLayersPerBand)
        self.enableSpectralDecorelation = enableSpectralDecorelation
    }

    /// Default encoder configuration: default JP3D settings, visible-light spectral
    /// config, 1 quality layer per band, and spectral decorrelation disabled.
    public static let `default` = JP3DMultiSpectralEncoderConfiguration(
        baseConfiguration: .lossless,
        spectralConfig: .default,
        qualityLayersPerBand: 1,
        enableSpectralDecorelation: false
    )
}

// MARK: - JP3DMultiSpectralEncodeResult

/// The result of encoding a multi-spectral volume.
///
/// Contains the encoded codestream bytes for each spectral band and
/// the spectral mapping that was used.
public struct JP3DMultiSpectralEncodeResult: Sendable {
    /// Encoded codestream data for each band; `encodedBands[b]` is the JP3D
    /// codestream for band `b`.
    public let encodedBands: [Data]

    /// The spectral mapping used during encoding.
    public let spectralMapping: JP3DSpectralMapping

    /// Creates an encode result.
    ///
    /// - Parameters:
    ///   - encodedBands: Per-band encoded data.
    ///   - spectralMapping: The spectral mapping used.
    public init(encodedBands: [Data], spectralMapping: JP3DSpectralMapping) {
        self.encodedBands = encodedBands
        self.spectralMapping = spectralMapping
    }

    /// The total number of encoded bytes across all bands.
    public var totalBytes: Int {
        encodedBands.reduce(0) { $0 + $1.count }
    }
}

// MARK: - JP3DMultiSpectralEncoder

/// Actor-based encoder for multi-spectral JP3D volumetric data.
///
/// Encodes each spectral band independently using JP3D compression, with
/// optional inter-band prediction to exploit spectral correlations.
///
/// Example:
/// ```swift
/// let encoder = JP3DMultiSpectralEncoder()
/// let result = try await encoder.encode(volume, configuration: .default)
/// print("Encoded \(result.totalBytes) bytes")
/// ```
public actor JP3DMultiSpectralEncoder {
    /// Creates a new multi-spectral encoder.
    public init() {}

    // MARK: - Public Interface

    /// Encodes a multi-spectral volume into per-band JP3D codestreams.
    ///
    /// - Parameters:
    ///   - volume: The multi-spectral volume to encode.
    ///   - configuration: Encoder configuration.
    /// - Returns: The encode result containing per-band codestreams.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the volume is malformed.
    public func encode(
        _ volume: JP3DMultiSpectralVolume,
        configuration: JP3DMultiSpectralEncoderConfiguration = .default
    ) async throws -> JP3DMultiSpectralEncodeResult {
        guard volume.bandCount == volume.samplesPerBand.count else {
            throw J2KError.invalidParameter(
                "Band count (\(volume.bandCount)) does not match samplesPerBand count " +
                "(\(volume.samplesPerBand.count))"
            )
        }

        var processed = volume.samplesPerBand
        if configuration.spectralConfig.enableInterBandPrediction {
            processed = applyInterBandPrediction(processed)
        }
        if configuration.enableSpectralDecorelation {
            processed = applySpectralDecorelation(processed)
        }

        let encodedBands: [Data] = processed.enumerated().map { (index, samples) in
            encodeBand(
                samples: samples,
                bandIndex: index,
                width: volume.width,
                height: volume.height,
                depth: volume.depth,
                qualityLayers: configuration.qualityLayersPerBand
            )
        }

        return JP3DMultiSpectralEncodeResult(
            encodedBands: encodedBands,
            spectralMapping: configuration.spectralConfig.spectralMapping
        )
    }

    /// Computes descriptive statistics for all bands in a multi-spectral volume.
    ///
    /// - Parameter volume: The volume to analyse.
    /// - Returns: Per-band mean, standard deviation, minimum, and maximum.
    public func computeStatistics(
        _ volume: JP3DMultiSpectralVolume
    ) async -> JP3DMultiSpectralStatistics {
        var means = [Double](repeating: 0, count: volume.bandCount)
        var stdDevs = [Double](repeating: 0, count: volume.bandCount)
        var mins = [Double](repeating: 0, count: volume.bandCount)
        var maxs = [Double](repeating: 0, count: volume.bandCount)

        for (b, samples) in volume.samplesPerBand.enumerated() {
            guard !samples.isEmpty else { continue }
            let n = Double(samples.count)
            let minVal = Double(samples.min() ?? 0)
            let maxVal = Double(samples.max() ?? 0)
            let sum = samples.reduce(0.0) { $0 + Double($1) }
            let mean = sum / n
            let variance = samples.reduce(0.0) { acc, v in
                let d = Double(v) - mean
                return acc + d * d
            } / n
            means[b] = mean
            stdDevs[b] = variance.squareRoot()
            mins[b] = minVal
            maxs[b] = maxVal
        }

        return JP3DMultiSpectralStatistics(
            meanPerBand: means,
            stdDevPerBand: stdDevs,
            minPerBand: mins,
            maxPerBand: maxs
        )
    }

    // MARK: - Private Helpers

    /// Encodes a single band's sample data to a JP3D codestream stub.
    private func encodeBand(
        samples: [Float],
        bandIndex: Int,
        width: Int, height: Int, depth: Int,
        qualityLayers: Int
    ) -> Data {
        // Scaffold: produce a placeholder codestream header + quantised byte stream.
        var data = Data()
        // 4-byte magic
        data.append(contentsOf: [0x4A, 0x50, 0x33, 0x44]) // JP3D
        // 4-byte band index
        withUnsafeBytes(of: UInt32(bandIndex).bigEndian) { data.append(contentsOf: $0) }
        // 4-byte sample count
        withUnsafeBytes(of: UInt32(samples.count).bigEndian) { data.append(contentsOf: $0) }
        // Quantised payload (8-bit truncation for scaffold)
        for s in samples {
            let clamped = max(0, min(1, s))
            data.append(UInt8(clamped * 255))
        }
        return data
    }

    /// Applies inter-band prediction (band-differencing) to exploit spectral correlation.
    private func applyInterBandPrediction(_ samplesPerBand: [[Float]]) -> [[Float]] {
        guard samplesPerBand.count > 1 else { return samplesPerBand }
        var result = samplesPerBand
        for b in stride(from: samplesPerBand.count - 1, through: 1, by: -1) {
            result[b] = zip(samplesPerBand[b], samplesPerBand[b - 1]).map { $0 - $1 }
        }
        return result
    }

    /// Applies a simple spectral decorrelation (subtract per-band mean).
    private func applySpectralDecorelation(_ samplesPerBand: [[Float]]) -> [[Float]] {
        samplesPerBand.map { samples in
            guard !samples.isEmpty else { return samples }
            let mean = Float(samples.reduce(0.0) { $0 + Double($1) } / Double(samples.count))
            return samples.map { $0 - mean }
        }
    }
}
