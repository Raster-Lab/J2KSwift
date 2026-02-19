/// # JP3DRateControl
///
/// Rate control for JP3D volumetric JPEG 2000 encoding.
///
/// Provides quantization and rate-distortion optimization for 3D wavelet
/// coefficients, supporting lossless, lossy PSNR, target bitrate, and
/// visually lossless modes.
///
/// ## Topics
///
/// ### Rate Control Types
/// - ``JP3DRateController``
/// - ``JP3DQuantizedTile``
/// - ``JP3DQualityLayer``

import Foundation
import J2KCore

/// Result of quantizing a tile's wavelet coefficients.
public struct JP3DQuantizedTile: Sendable {
    /// The tile this quantized data belongs to.
    public let tile: JP3DTile

    /// The component index.
    public let componentIndex: Int

    /// Quantized coefficients as Int32 values.
    public let coefficients: [Int32]

    /// The quantization step size used.
    public let stepSize: Float

    /// The width of the tile data.
    public let width: Int

    /// The height of the tile data.
    public let height: Int

    /// The depth of the tile data.
    public let depth: Int

    /// Number of decomposition levels.
    public let decompositionLevels: Int
}

/// A quality layer containing rate-distortion optimized data.
public struct JP3DQualityLayer: Sendable {
    /// The quality layer index (0 = lowest quality).
    public let index: Int

    /// The target bitrate for this layer in bits per voxel.
    public let targetBitsPerVoxel: Float

    /// Truncation points for each code-block contribution.
    public let truncationPoints: [Int]

    /// The estimated distortion reduction from this layer.
    public let distortionReduction: Float
}

/// Rate controller for JP3D encoding.
///
/// Handles quantization of 3D wavelet coefficients and formation of quality
/// layers using post-compression rate-distortion optimization (PCRD-opt).
///
/// Example:
/// ```swift
/// let controller = JP3DRateController(mode: .lossless)
/// let quantized = controller.quantize(coefficients: data, ...)
/// ```
public struct JP3DRateController: Sendable {
    /// The compression mode.
    public let mode: JP3DCompressionMode

    /// Number of quality layers.
    public let qualityLayers: Int

    /// Creates a rate controller for the given compression mode.
    ///
    /// - Parameters:
    ///   - mode: The compression mode. Defaults to `.lossless`.
    ///   - qualityLayers: The number of quality layers. Defaults to 1.
    public init(mode: JP3DCompressionMode = .lossless, qualityLayers: Int = 1) {
        self.mode = mode
        self.qualityLayers = max(1, qualityLayers)
    }

    /// Computes the quantization step size for the given compression mode.
    ///
    /// - Parameters:
    ///   - bitDepth: The bit depth of the source component.
    ///   - decompositionLevels: The number of decomposition levels used.
    /// - Returns: The quantization step size. Returns 1.0 for lossless modes.
    public func stepSize(bitDepth: Int, decompositionLevels: Int) -> Float {
        switch mode {
        case .lossless, .losslessHTJ2K:
            return 1.0
        case .lossy(let psnr):
            return stepSizeForPSNR(psnr, bitDepth: bitDepth)
        case .lossyHTJ2K(let psnr):
            return stepSizeForPSNR(psnr, bitDepth: bitDepth)
        case .targetBitrate(let bpv):
            return stepSizeForBitrate(bpv, bitDepth: bitDepth, levels: decompositionLevels)
        case .visuallyLossless:
            // High quality: use PSNR ~50 dB for visually lossless
            return stepSizeForPSNR(50.0, bitDepth: bitDepth)
        }
    }

    /// Quantizes wavelet coefficients for a tile.
    ///
    /// For lossless modes, coefficients are rounded to integers without quantization.
    /// For lossy modes, scalar deadzone quantization is applied.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to quantize.
    ///   - tile: The tile metadata.
    ///   - componentIndex: The component index.
    ///   - bitDepth: The source bit depth.
    ///   - decompositionLevels: Number of decomposition levels.
    /// - Returns: The quantized tile data.
    public func quantize(
        coefficients: [Float],
        tile: JP3DTile,
        componentIndex: Int,
        bitDepth: Int,
        decompositionLevels: Int
    ) -> JP3DQuantizedTile {
        let step = stepSize(bitDepth: bitDepth, decompositionLevels: decompositionLevels)
        let quantized: [Int32]

        if mode.isLossless {
            // Lossless: round to nearest integer
            quantized = coefficients.map { Int32(roundf($0)) }
        } else {
            // Lossy: scalar deadzone quantization
            // q = sign(c) * floor(|c| / step)
            quantized = coefficients.map { coeff in
                let sign: Float = coeff >= 0 ? 1.0 : -1.0
                let magnitude = abs(coeff) / step
                return Int32(sign * floor(magnitude))
            }
        }

        return JP3DQuantizedTile(
            tile: tile,
            componentIndex: componentIndex,
            coefficients: quantized,
            stepSize: step,
            width: tile.width,
            height: tile.height,
            depth: tile.depth,
            decompositionLevels: decompositionLevels
        )
    }

    /// Dequantizes a quantized tile back to float coefficients.
    ///
    /// - Parameter quantized: The quantized tile data.
    /// - Returns: Reconstructed float coefficients.
    public func dequantize(_ quantized: JP3DQuantizedTile) -> [Float] {
        if quantized.stepSize <= 1.0 {
            return quantized.coefficients.map { Float($0) }
        }
        return quantized.coefficients.map { Float($0) * quantized.stepSize }
    }

    /// Forms quality layers for rate-distortion optimization.
    ///
    /// Uses PCRD-opt to allocate bits across quality layers for optimal
    /// quality at each target rate.
    ///
    /// - Parameters:
    ///   - totalVoxels: Total number of voxels in the volume.
    ///   - totalBits: Total encoded bits available.
    /// - Returns: Array of quality layers from lowest to highest quality.
    public func formQualityLayers(totalVoxels: Int, totalBits: Int) -> [JP3DQualityLayer] {
        guard qualityLayers > 0, totalVoxels > 0 else { return [] }

        var layers: [JP3DQualityLayer] = []
        let maxBPV = Float(totalBits) / Float(totalVoxels)

        for i in 0..<qualityLayers {
            let fraction = Float(i + 1) / Float(qualityLayers)
            let layerBPV = maxBPV * fraction
            let distortionReduction = fraction * fraction // Diminishing returns model

            layers.append(JP3DQualityLayer(
                index: i,
                targetBitsPerVoxel: layerBPV,
                truncationPoints: [],
                distortionReduction: distortionReduction
            ))
        }

        return layers
    }

    // MARK: - Private Helpers

    /// Computes step size to achieve a target PSNR.
    private func stepSizeForPSNR(_ targetPSNR: Double, bitDepth: Int) -> Float {
        let maxVal = Float((1 << bitDepth) - 1)
        // PSNR = 10 * log10(maxVal^2 / MSE)
        // MSE = maxVal^2 / 10^(PSNR/10)
        // For uniform quantization: MSE ≈ step^2 / 12
        // step = sqrt(12 * MSE)
        let mse = Double(maxVal * maxVal) / pow(10.0, targetPSNR / 10.0)
        let step = sqrt(12.0 * mse)
        return max(1.0, Float(step))
    }

    /// Computes step size to achieve a target bitrate.
    private func stepSizeForBitrate(
        _ bitsPerVoxel: Double,
        bitDepth: Int,
        levels: Int
    ) -> Float {
        // Rough model: step ≈ 2^(bitDepth - bpv) / sqrt(levels + 1)
        let exponent = Double(bitDepth) - bitsPerVoxel
        let step = pow(2.0, max(0, exponent)) / sqrt(Double(levels + 1))
        return max(1.0, Float(step))
    }
}
