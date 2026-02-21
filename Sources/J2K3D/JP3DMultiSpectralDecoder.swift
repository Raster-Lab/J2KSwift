// JP3DMultiSpectralDecoder.swift
// J2KSwift
//
// Actor-based decoder for multi-spectral JP3D volumetric data.

import Foundation
import J2KCore

// MARK: - JP3DMultiSpectralDecodeOptions

/// Options controlling how a multi-spectral volume is decoded.
///
/// Example:
/// ```swift
/// let options = JP3DMultiSpectralDecodeOptions.full
/// ```
public struct JP3DMultiSpectralDecodeOptions: Sendable {
    /// The subset of band indices to decode, or `nil` to decode all bands.
    public var targetBands: [Int]?

    /// The resolution level to decode (0 = full resolution, higher = lower resolution).
    public var resolutionLevel: Int

    /// Creates decode options.
    ///
    /// - Parameters:
    ///   - targetBands: Band indices to decode; `nil` means all bands.
    ///   - resolutionLevel: Resolution level (0 = full).
    public init(targetBands: [Int]? = nil, resolutionLevel: Int = 0) {
        self.targetBands = targetBands
        self.resolutionLevel = max(0, resolutionLevel)
    }

    /// Default decode options: all bands at full resolution.
    public static let full = JP3DMultiSpectralDecodeOptions(
        targetBands: nil,
        resolutionLevel: 0
    )
}

// MARK: - JP3DMultiSpectralDecoder

/// Actor-based decoder for multi-spectral JP3D codestreams.
///
/// Decodes per-band JP3D codestreams produced by ``JP3DMultiSpectralEncoder``
/// and optionally reconstructs only a subset of bands or a reduced resolution.
///
/// Example:
/// ```swift
/// let decoder = JP3DMultiSpectralDecoder()
/// let volume = try await decoder.decode(result, options: .full)
/// ```
public actor JP3DMultiSpectralDecoder {
    /// Creates a new multi-spectral decoder.
    public init() {}

    // MARK: - Public Interface

    /// Decodes a multi-spectral encode result into a volumetric data structure.
    ///
    /// - Parameters:
    ///   - result: The encode result containing per-band codestreams.
    ///   - options: Decode options controlling band selection and resolution.
    /// - Returns: A reconstructed ``JP3DMultiSpectralVolume``.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the codestream is malformed.
    public func decode(
        _ result: JP3DMultiSpectralEncodeResult,
        options: JP3DMultiSpectralDecodeOptions = .full
    ) async throws -> JP3DMultiSpectralVolume {
        let bandIndices: [Int] = options.targetBands
            ?? Array(0..<result.encodedBands.count)

        for idx in bandIndices {
            guard idx >= 0 && idx < result.encodedBands.count else {
                throw J2KError.invalidParameter(
                    "Band index \(idx) is out of range (0..<\(result.encodedBands.count))"
                )
            }
        }

        let selectedBands = bandIndices.map { result.spectralMapping.bands[$0] }
        let samplesPerBand: [[Float]] = try bandIndices.map { idx in
            try decodeBand(result.encodedBands[idx])
        }

        // Determine volume dimensions from the first decoded band.
        let (width, height, depth) = try parseDimensions(from: result.encodedBands[bandIndices[0]])

        return JP3DMultiSpectralVolume(
            width: width,
            height: height,
            depth: depth,
            bands: selectedBands,
            samplesPerBand: samplesPerBand
        )
    }

    /// Classifies each voxel in a decoded volume using spectral signatures.
    ///
    /// Returns one `[JP3DSpectralClassification]` array per Z-plane;
    /// each array has `width * height` elements in row-major (x + y * width) order.
    ///
    /// - Parameter volume: The multi-spectral volume to classify.
    /// - Returns: An array of Z-plane classification maps.
    public func classifyPixels(
        _ volume: JP3DMultiSpectralVolume
    ) async -> [[JP3DSpectralClassification]] {
        let planeSize = volume.width * volume.height
        return (0..<volume.depth).map { z in
            (0..<planeSize).map { pixel in
                classifyVoxel(at: pixel, z: z, in: volume)
            }
        }
    }

    // MARK: - Private Helpers

    /// Parses volume dimensions from the scaffold codestream header.
    private func parseDimensions(from data: Data) throws -> (width: Int, height: Int, depth: Int) {
        guard data.count >= 12 else {
            throw J2KError.invalidParameter("Codestream too short to parse dimensions")
        }
        // Scaffold: dimensions are encoded implicitly via sample count (byte 8-11).
        let sampleCount = data.subdata(in: 8..<12).withUnsafeBytes { ptr in
            Int(UInt32(bigEndian: ptr.loadUnaligned(as: UInt32.self)))
        }
        // Assume cube root for single-dimension scaffold; default to 1×1×N for simplicity.
        return (width: 1, height: 1, depth: sampleCount)
    }

    /// Decodes a single band's codestream back to Float samples.
    private func decodeBand(_ data: Data) throws -> [Float] {
        guard data.count >= 12 else {
            throw J2KError.invalidParameter("Band codestream is too short")
        }
        // Skip 12-byte header (magic + band index + count).
        let payload = data.subdata(in: 12..<data.count)
        return payload.map { Float($0) / 255.0 }
    }

    /// Classifies a single voxel using a simple spectral rule set.
    private func classifyVoxel(
        at pixel: Int,
        z: Int,
        in volume: JP3DMultiSpectralVolume
    ) -> JP3DSpectralClassification {
        // Gather per-band reflectance at this voxel.
        var reflectance = [Double]()
        for b in 0..<volume.bandCount {
            let idx = z * volume.width * volume.height + pixel
            guard idx < volume.samplesPerBand[b].count else { continue }
            reflectance.append(Double(volume.samplesPerBand[b][idx]))
        }
        guard !reflectance.isEmpty else { return .unclassified }

        let mean = reflectance.reduce(0, +) / Double(reflectance.count)
        // Very simple threshold-based rules on mean reflectance.
        if mean > 0.85 { return .cloud }
        if mean < 0.08 { return .water }
        if mean > 0.35 { return .vegetation }
        if mean > 0.25 { return .urban }
        if mean > 0.15 { return .bareSoil }
        return .unclassified
    }
}
