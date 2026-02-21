// J2KXSQuantiser.swift
// J2KSwift
//
// Quantisation and dequantisation for JPEG XS (ISO/IEC 21122).
//
// JPEG XS uses a uniform scalar quantiser with a configurable dead-zone
// offset.  Each subband has its own step size derived from the target
// bit-rate and visual masking model.

import Foundation
import J2KCore

// MARK: - J2KXSQuantisationParameters

/// Per-subband quantisation parameters for a JPEG XS encode.
///
/// The step size controls the granularity of quantisation; a larger step
/// size yields higher compression at the cost of reconstruction fidelity.
/// The dead-zone offset widens the zero-output region around zero, which
/// reduces high-frequency noise in visually smooth regions.
///
/// Example:
/// ```swift
/// let params = J2KXSQuantisationParameters(stepSize: 4.0, deadZoneOffset: 0.5)
/// ```
public struct J2KXSQuantisationParameters: Sendable, Equatable {
    /// The quantisation step size (Δ).  Must be > 0.
    public var stepSize: Float

    /// Dead-zone expansion factor applied around zero (0 … 1).
    /// A value of 0 gives a uniform quantiser; 1 doubles the zero region.
    public var deadZoneOffset: Float

    /// Creates quantisation parameters.
    ///
    /// - Parameters:
    ///   - stepSize: Quantisation step size (clamped to > 0).
    ///   - deadZoneOffset: Dead-zone expansion factor (clamped to 0 … 1).
    public init(stepSize: Float, deadZoneOffset: Float = 0.0) {
        self.stepSize = max(Float.leastNormalMagnitude, stepSize)
        self.deadZoneOffset = min(max(0, deadZoneOffset), 1.0)
    }

    /// Default parameters — step size 1.0, no dead zone.
    public static let `default` = J2KXSQuantisationParameters(stepSize: 1.0)

    /// Fine parameters — step size 0.5, slight dead zone.
    public static let fine = J2KXSQuantisationParameters(stepSize: 0.5, deadZoneOffset: 0.1)

    /// Coarse parameters — step size 8.0, moderate dead zone.
    public static let coarse = J2KXSQuantisationParameters(stepSize: 8.0, deadZoneOffset: 0.3)
}

// MARK: - J2KXSQuantisedCoefficients

/// Quantised integer coefficients for one subband.
///
/// Stores the subband orientation and level alongside the quantised values
/// and the step-size index that was used.  The step-size index is written
/// into the JPEG XS codestream so the decoder can reconstruct the original
/// parameters.
public struct J2KXSQuantisedCoefficients: Sendable {
    /// The subband orientation.
    public let orientation: J2KXSDWTOrientation

    /// The decomposition level (1-based).
    public let level: Int

    /// The quantised coefficient values.
    public let values: [Int32]

    /// The step-size index stored in the codestream.
    public let stepIndex: Int

    /// The actual step size derived from `stepIndex`.
    public let stepSize: Float

    /// Subband width.
    public let width: Int

    /// Subband height.
    public let height: Int

    /// Creates a quantised coefficient block.
    ///
    /// - Parameters:
    ///   - orientation: Subband orientation.
    ///   - level: Decomposition level.
    ///   - values: Quantised values.
    ///   - stepIndex: Step-size table index.
    ///   - stepSize: Actual step size used.
    ///   - width: Subband width.
    ///   - height: Subband height.
    public init(
        orientation: J2KXSDWTOrientation,
        level: Int,
        values: [Int32],
        stepIndex: Int,
        stepSize: Float,
        width: Int,
        height: Int
    ) {
        self.orientation = orientation
        self.level = level
        self.values = values
        self.stepIndex = stepIndex
        self.stepSize = stepSize
        self.width = width
        self.height = height
    }

    /// The number of quantised coefficients.
    public var count: Int { values.count }
}

// MARK: - J2KXSQuantiser

/// Quantiser and dequantiser for JPEG XS subbands.
///
/// Applies uniform mid-tread scalar quantisation with configurable step
/// size and dead-zone offset.  Dequantisation applies the mid-point
/// reconstruction rule.
///
/// Example:
/// ```swift
/// let quantiser = J2KXSQuantiser()
/// let quantised = await quantiser.quantise(subband: subband, parameters: .default)
/// let reconstructed = await quantiser.dequantise(quantised)
/// ```
public actor J2KXSQuantiser {
    /// Total coefficient values processed (for diagnostics).
    private(set) var processedCoefficientCount: Int = 0

    /// Creates a new quantiser.
    public init() {}

    // MARK: Quantise

    /// Quantises the coefficients of a DWT subband.
    ///
    /// - Parameters:
    ///   - subband: The DWT subband to quantise.
    ///   - parameters: Quantisation parameters (step size and dead zone).
    /// - Returns: A ``J2KXSQuantisedCoefficients`` block.
    public func quantise(
        subband: J2KXSSubband,
        parameters: J2KXSQuantisationParameters
    ) async -> J2KXSQuantisedCoefficients {
        let Δ = parameters.stepSize
        let dz = parameters.deadZoneOffset
        let halfDZ = Δ * (1.0 + dz) * 0.5

        let values = subband.coefficients.map { x -> Int32 in
            let sign: Float = x < 0 ? -1 : 1
            let abs = abs(x)
            if abs < halfDZ { return 0 }
            return Int32((sign * (abs - halfDZ) / Δ).rounded(.towardZero))
        }

        let stepIndex = Int(log2(Double(Δ)) + 128).clamped(to: 0...255)

        processedCoefficientCount += values.count
        return J2KXSQuantisedCoefficients(
            orientation: subband.orientation,
            level: subband.level,
            values: values,
            stepIndex: stepIndex,
            stepSize: Δ,
            width: subband.width,
            height: subband.height
        )
    }

    // MARK: Dequantise

    /// Reconstructs floating-point coefficients from a quantised block.
    ///
    /// Uses mid-point reconstruction: `q̂ = (q + 0.5) × Δ` for q ≠ 0,
    /// and 0 for the zero region.
    ///
    /// - Parameter quantised: The quantised coefficient block.
    /// - Returns: A ``J2KXSSubband`` with reconstructed coefficients.
    public func dequantise(
        _ quantised: J2KXSQuantisedCoefficients
    ) async -> J2KXSSubband {
        let Δ = quantised.stepSize
        let coefficients = quantised.values.map { q -> Float in
            guard q != 0 else { return 0 }
            let sign: Float = q < 0 ? -1 : 1
            return sign * (Float(abs(q)) + 0.5) * Δ
        }

        processedCoefficientCount += coefficients.count
        return J2KXSSubband(
            orientation: quantised.orientation,
            level: quantised.level,
            coefficients: coefficients,
            width: quantised.width,
            height: quantised.height
        )
    }

    // MARK: Diagnostics

    /// Resets the processed-coefficient counter.
    public func resetStatistics() {
        processedCoefficientCount = 0
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
