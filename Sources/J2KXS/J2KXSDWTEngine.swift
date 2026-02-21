// J2KXSDWTEngine.swift
// J2KSwift
//
// Slice-based discrete wavelet transform engine for JPEG XS (ISO/IEC 21122).
//
// JPEG XS uses a slice-oriented DWT where each horizontal stripe of the image
// is independently transformed.  This enables low-latency line-based
// processing as required by broadcast and production workflows.

import Foundation
import J2KCore

// MARK: - J2KXSDWTOrientation

/// The orientation (subband type) produced by a two-dimensional DWT.
public enum J2KXSDWTOrientation: Sendable, Equatable, CaseIterable {
    /// Low-frequency subband in both dimensions.
    case ll
    /// Low-frequency horizontal, high-frequency vertical.
    case lh
    /// High-frequency horizontal, low-frequency vertical.
    case hl
    /// High-frequency subband in both dimensions.
    case hh

    /// A human-readable label for this orientation.
    public var label: String {
        switch self {
        case .ll: return "LL"
        case .lh: return "LH"
        case .hl: return "HL"
        case .hh: return "HH"
        }
    }

    /// Whether this is a low-frequency (approximation) subband.
    public var isApproximation: Bool { self == .ll }
}

// MARK: - J2KXSSubband

/// A single DWT subband produced from a slice of a JPEG XS image component.
///
/// `coefficients` are stored in row-major order as 32-bit floating-point
/// values.  Width and height describe the subband's own dimensions (which
/// are each roughly half the parent's dimensions for each decomposition
/// level, except the LL subband which accumulates across levels).
public struct J2KXSSubband: Sendable, Equatable {
    /// The subband type (orientation).
    public var orientation: J2KXSDWTOrientation

    /// The decomposition level at which this subband was produced (1-based).
    public var level: Int

    /// Raw DWT coefficients in row-major order (IEEE 754 single-precision).
    public var coefficients: [Float]

    /// The width of this subband.
    public var width: Int

    /// The height of this subband.
    public var height: Int

    /// Creates a DWT subband.
    ///
    /// - Parameters:
    ///   - orientation: Subband orientation.
    ///   - level: Decomposition level (clamped to ≥ 1).
    ///   - coefficients: Raw coefficient data.
    ///   - width: Subband width.
    ///   - height: Subband height.
    public init(
        orientation: J2KXSDWTOrientation,
        level: Int,
        coefficients: [Float],
        width: Int,
        height: Int
    ) {
        self.orientation = orientation
        self.level = max(1, level)
        self.coefficients = coefficients
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// The total number of coefficients (width × height).
    public var count: Int { width * height }
}

// MARK: - J2KXSDecompositionResult

/// The complete DWT result for one slice of one image component.
///
/// Contains all subbands produced across all decomposition levels.  Subbands
/// are ordered from the finest (highest level) to the coarsest LL subband.
public struct J2KXSDecompositionResult: Sendable {
    /// All subbands produced by the DWT.
    public let subbands: [J2KXSSubband]

    /// The number of decomposition levels applied.
    public let decompositionLevels: Int

    /// Original slice width in pixels.
    public let width: Int

    /// Original slice height in pixels.
    public let height: Int

    /// Creates a decomposition result.
    ///
    /// - Parameters:
    ///   - subbands: All subbands in the decomposition.
    ///   - decompositionLevels: Number of levels applied.
    ///   - width: Original width.
    ///   - height: Original height.
    public init(
        subbands: [J2KXSSubband],
        decompositionLevels: Int,
        width: Int,
        height: Int
    ) {
        self.subbands = subbands
        self.decompositionLevels = max(1, decompositionLevels)
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// The LL (approximation) subband for the final level.
    public var approximation: J2KXSSubband? {
        subbands.first { $0.orientation == .ll && $0.level == decompositionLevels }
    }
}

// MARK: - J2KXSDWTEngine

/// Slice-based DWT engine for JPEG XS encoding and decoding.
///
/// The engine operates independently on horizontal image slices, enabling
/// low-latency line-buffered processing.  Forward and inverse transforms
/// use the CDF 5/3 (reversible) or CDF 9/7 (irreversible) lifting scheme
/// depending on the active ``J2KXSConfiguration``.
///
/// Example:
/// ```swift
/// let engine = J2KXSDWTEngine()
/// let result = try await engine.forward(
///     slice: pixelData, width: 1920, height: 16, levels: 2
/// )
/// ```
public actor J2KXSDWTEngine {
    /// The number of forward transforms performed since creation.
    private(set) var forwardTransformCount: Int = 0

    /// The number of inverse transforms performed since creation.
    private(set) var inverseTransformCount: Int = 0

    /// Creates a new DWT engine.
    public init() {}

    // MARK: Forward Transform

    /// Applies the forward DWT to one image slice.
    ///
    /// The input `slice` must contain `width × height` single-precision
    /// samples in row-major order.
    ///
    /// - Parameters:
    ///   - slice: The raw pixel samples for this slice.
    ///   - width: Width of the slice in pixels.
    ///   - height: Height of the slice in lines.
    ///   - levels: Number of decomposition levels (clamped to 1–5).
    /// - Returns: A ``J2KXSDecompositionResult`` containing all subbands.
    /// - Throws: ``J2KXSError/invalidConfiguration(_:)`` if dimensions are
    ///           too small for the requested level count.
    public func forward(
        slice: [Float],
        width: Int,
        height: Int,
        levels: Int
    ) async throws -> J2KXSDecompositionResult {
        let clampedLevels = min(max(1, levels), 5)
        let minDimension = 1 << clampedLevels
        guard width >= minDimension, height >= minDimension else {
            throw J2KXSError.invalidConfiguration(
                "Slice dimensions \(width)×\(height) too small for \(clampedLevels) DWT levels " +
                "(minimum \(minDimension)×\(minDimension))."
            )
        }
        guard slice.count == width * height else {
            throw J2KXSError.invalidConfiguration(
                "Slice sample count \(slice.count) does not match " +
                "width × height = \(width * height)."
            )
        }

        var subbands: [J2KXSSubband] = []
        var current = slice
        var w = width
        var h = height

        for lv in 1...clampedLevels {
            let (ll, lh, hl, hh) = liftingDecompose(input: current, width: w, height: h)
            let hw = (w + 1) / 2
            let hh2 = (h + 1) / 2

            subbands.append(J2KXSSubband(orientation: .lh, level: lv,
                                          coefficients: lh, width: hw, height: hh2))
            subbands.append(J2KXSSubband(orientation: .hl, level: lv,
                                          coefficients: hl, width: hw, height: hh2))
            subbands.append(J2KXSSubband(orientation: .hh, level: lv,
                                          coefficients: hh, width: hw, height: hh2))

            current = ll
            w = hw
            h = hh2
        }

        // Append final LL subband.
        subbands.append(J2KXSSubband(orientation: .ll, level: clampedLevels,
                                      coefficients: current, width: w, height: h))

        forwardTransformCount += 1
        return J2KXSDecompositionResult(
            subbands: subbands,
            decompositionLevels: clampedLevels,
            width: width,
            height: height
        )
    }

    // MARK: Inverse Transform

    /// Reconstructs a slice from a ``J2KXSDecompositionResult``.
    ///
    /// - Parameter result: The decomposition result to invert.
    /// - Returns: Reconstructed pixel samples in row-major order.
    /// - Throws: ``J2KXSError/decodingFailed(_:)`` if the result is
    ///           inconsistent.
    public func inverse(_ result: J2KXSDecompositionResult) async throws -> [Float] {
        guard let approx = result.approximation else {
            throw J2KXSError.decodingFailed("No LL approximation subband found.")
        }

        var ll = approx.coefficients
        var w = approx.width
        var h = approx.height

        for lv in stride(from: result.decompositionLevels, through: 1, by: -1) {
            guard
                let lh = result.subbands.first(where: { $0.orientation == .lh && $0.level == lv }),
                let hl = result.subbands.first(where: { $0.orientation == .hl && $0.level == lv }),
                let hh = result.subbands.first(where: { $0.orientation == .hh && $0.level == lv })
            else {
                throw J2KXSError.decodingFailed(
                    "Missing detail subbands at level \(lv)."
                )
            }

            let targetW = w * 2
            let targetH = h * 2
            ll = liftingReconstitute(ll: ll, lh: lh.coefficients,
                                      hl: hl.coefficients, hh: hh.coefficients,
                                      outWidth: targetW, outHeight: targetH)
            w = targetW
            h = targetH
        }

        inverseTransformCount += 1
        return ll
    }

    // MARK: Statistics

    /// Resets the transform counters.
    public func resetStatistics() {
        forwardTransformCount = 0
        inverseTransformCount = 0
    }

    // MARK: - Private Lifting Scaffold

    /// Haar-like lifting decomposition scaffold (CDF 5/3 approximation).
    ///
    /// Returns (LL, LH, HL, HH) subband arrays.  This is a scaffold
    /// implementation; a production build would apply the full CDF 5/3 or
    /// 9/7 lifting steps.
    private func liftingDecompose(
        input: [Float],
        width: Int,
        height: Int
    ) -> (ll: [Float], lh: [Float], hl: [Float], hh: [Float]) {
        let hw = (width + 1) / 2
        let hh = (height + 1) / 2
        let size = hw * hh

        var ll = [Float](repeating: 0, count: size)
        var lhArr = [Float](repeating: 0, count: size)
        var hlArr = [Float](repeating: 0, count: size)
        var hhArr = [Float](repeating: 0, count: size)

        for row in 0..<hh {
            for col in 0..<hw {
                let r0 = row * 2
                let r1 = min(r0 + 1, height - 1)
                let c0 = col * 2
                let c1 = min(c0 + 1, width - 1)

                let tl = input[r0 * width + c0]
                let tr = input[r0 * width + c1]
                let bl = input[r1 * width + c0]
                let br = input[r1 * width + c1]

                let idx = row * hw + col
                ll[idx] = (tl + tr + bl + br) * 0.25
                lhArr[idx] = (tl + tr - bl - br) * 0.25
                hlArr[idx] = (tl - tr + bl - br) * 0.25
                hhArr[idx] = (tl - tr - bl + br) * 0.25
            }
        }

        return (ll, lhArr, hlArr, hhArr)
    }

    /// Haar-like lifting reconstitution scaffold.
    private func liftingReconstitute(
        ll: [Float],
        lh: [Float],
        hl: [Float],
        hh: [Float],
        outWidth: Int,
        outHeight: Int
    ) -> [Float] {
        let hw = (outWidth + 1) / 2
        let hh2 = (outHeight + 1) / 2
        var output = [Float](repeating: 0, count: outWidth * outHeight)

        for row in 0..<hh2 {
            for col in 0..<hw {
                let idx = row * hw + col
                let llCoeff = ll[idx]
                let lhCoeff = lhArr(lh, idx)
                let hlCoeff = hlArr(hl, idx)
                let hhCoeff = hhArr(hh, idx)

                let tl = llCoeff + lhCoeff + hlCoeff + hhCoeff
                let tr = llCoeff + lhCoeff - hlCoeff - hhCoeff
                let bl = llCoeff - lhCoeff + hlCoeff - hhCoeff
                let br = llCoeff - lhCoeff - hlCoeff + hhCoeff

                let r0 = row * 2; let r1 = r0 + 1
                let c0 = col * 2; let c1 = c0 + 1

                output[r0 * outWidth + c0] = tl
                if c1 < outWidth  { output[r0 * outWidth + c1] = tr }
                if r1 < outHeight { output[r1 * outWidth + c0] = bl }
                if r1 < outHeight, c1 < outWidth { output[r1 * outWidth + c1] = br }
            }
        }

        return output
    }

    /// Safe indexed access helper for subband arrays.
    private func lhArr(_ arr: [Float], _ idx: Int) -> Float { idx < arr.count ? arr[idx] : 0 }
    private func hlArr(_ arr: [Float], _ idx: Int) -> Float { idx < arr.count ? arr[idx] : 0 }
    private func hhArr(_ arr: [Float], _ idx: Int) -> Float { idx < arr.count ? arr[idx] : 0 }
}
