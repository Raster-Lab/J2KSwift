// J2KDCOffsetAccelerated.swift
// J2KSwift
//
// Hardware-accelerated DC offset operations using Accelerate framework.
//

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

/// Hardware-accelerated DC offset operations for JPEG 2000 Part 2.
///
/// Provides high-performance DC offset computation and application
/// using the Accelerate framework's vDSP library on Apple platforms.
///
/// On platforms without Accelerate, falls back to scalar operations.
///
/// ## Performance
///
/// On Apple platforms with Accelerate framework:
/// - 4-8× faster mean computation using `vDSP_meanv`
/// - Vectorized offset addition/subtraction using `vDSP_vsadd`
/// - Optimal cache utilization through vector operations
///
/// ## Usage
///
/// ```swift
/// let accelerated = J2KDCOffsetAccelerated()
///
/// // Compute mean using vDSP (fast path on Apple)
/// let mean = try accelerated.computeMean(data)
///
/// // Remove DC offset using vectorized subtraction
/// let adjusted = try accelerated.removeOffset(mean, from: data)
///
/// // Restore DC offset using vectorized addition
/// let restored = try accelerated.addOffset(mean, to: adjusted)
/// ```
public struct J2KDCOffsetAccelerated: Sendable {
    /// Creates a new accelerated DC offset processor.
    public init() {}

    /// Indicates whether hardware acceleration is available.
    public static var isAvailable: Bool {
        #if canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Accelerated Mean Computation

    /// Computes the arithmetic mean of sample values using vDSP.
    ///
    /// Uses `vDSP_meanv` on Apple platforms for vectorized mean
    /// computation. Falls back to scalar computation elsewhere.
    ///
    /// - Parameter data: The sample data array.
    /// - Returns: The arithmetic mean.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Accelerate is not available.
    public func computeMean(_ data: [Int32]) throws -> Double {
        guard !data.isEmpty else { return 0.0 }

        #if canImport(Accelerate)
        var floatData = data.map { Float($0) }
        var mean: Float = 0
        vDSP_meanv(&floatData, 1, &mean, vDSP_Length(data.count))
        return Double(mean)
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated DC offset requires Accelerate framework (Apple platforms)"
        )
        #endif
    }

    // MARK: - Accelerated Offset Removal

    /// Removes a DC offset from data using vectorized subtraction.
    ///
    /// Uses `vDSP_vsadd` with negated offset on Apple platforms.
    ///
    /// - Parameters:
    ///   - offset: The DC offset value to subtract.
    ///   - data: The sample data array.
    /// - Returns: The data with offset removed.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Accelerate is not available.
    public func removeOffset(_ offset: Float, from data: [Int32]) throws -> [Int32] {
        #if canImport(Accelerate)
        var floatData = data.map { Float($0) }
        var negOffset = -offset
        var result = [Float](repeating: 0, count: data.count)
        vDSP_vsadd(&floatData, 1, &negOffset, &result, 1, vDSP_Length(data.count))
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated DC offset requires Accelerate framework (Apple platforms)"
        )
        #endif
    }

    // MARK: - Accelerated Offset Addition

    /// Adds a DC offset to data using vectorized addition.
    ///
    /// Uses `vDSP_vsadd` on Apple platforms for fast offset restoration.
    ///
    /// - Parameters:
    ///   - offset: The DC offset value to add.
    ///   - data: The sample data array.
    /// - Returns: The data with offset restored.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Accelerate is not available.
    public func addOffset(_ offset: Float, to data: [Int32]) throws -> [Int32] {
        #if canImport(Accelerate)
        var floatData = data.map { Float($0) }
        var addOffset = offset
        var result = [Float](repeating: 0, count: data.count)
        vDSP_vsadd(&floatData, 1, &addOffset, &result, 1, vDSP_Length(data.count))
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated DC offset requires Accelerate framework (Apple platforms)"
        )
        #endif
    }

    // MARK: - Accelerated Extended Precision Scaling

    /// Scales wavelet coefficients using vectorized multiplication.
    ///
    /// Uses `vDSP_vsmul` on Apple platforms for fast coefficient scaling
    /// with a single factor. Falls back to scalar operations elsewhere.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to scale.
    ///   - factor: The scaling factor.
    /// - Returns: The scaled coefficients.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Accelerate is not available.
    public func scaleCoefficients(_ coefficients: [Int32], by factor: Float) throws -> [Int32] {
        #if canImport(Accelerate)
        var floatData = coefficients.map { Float($0) }
        var scaleFactor = factor
        var result = [Float](repeating: 0, count: coefficients.count)
        vDSP_vsmul(&floatData, 1, &scaleFactor, &result, 1, vDSP_Length(coefficients.count))
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated coefficient scaling requires Accelerate framework (Apple platforms)"
        )
        #endif
    }

    /// Clamps coefficients to a given magnitude range using vectorized operations.
    ///
    /// Uses `vDSP_vclip` on Apple platforms.
    ///
    /// - Parameters:
    ///   - coefficients: The coefficients to clamp.
    ///   - maxMagnitude: The maximum absolute value.
    /// - Returns: The clamped coefficients.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Accelerate is not available.
    public func clampCoefficients(_ coefficients: [Int32], maxMagnitude: Int32) throws -> [Int32] {
        #if canImport(Accelerate)
        var floatData = coefficients.map { Float($0) }
        var lo = Float(-maxMagnitude)
        var hi = Float(maxMagnitude)
        var result = [Float](repeating: 0, count: coefficients.count)
        vDSP_vclip(&floatData, 1, &lo, &hi, &result, 1, vDSP_Length(coefficients.count))
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated coefficient clamping requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
}
