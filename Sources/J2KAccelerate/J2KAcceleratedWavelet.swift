// J2KAcceleratedWavelet.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

/// Standalone filter specification for accelerated wavelet operations.
///
/// Defines the analysis and synthesis filter coefficients for an arbitrary
/// wavelet filter kernel. This type is self-contained within the J2KAccelerate
/// module and does not depend on J2KCodec.
///
/// Each filter pair (analysis/synthesis) contains lowpass and highpass
/// coefficients along with optional scaling factors.
///
/// ## Usage
///
/// ```swift
/// let filter = J2KAcceleratedWaveletFilter(
///     analysisLowpass: [0.7071067811865476, 0.7071067811865476],
///     analysisHighpass: [-0.7071067811865476, 0.7071067811865476],
///     synthesisLowpass: [0.7071067811865476, 0.7071067811865476],
///     synthesisHighpass: [0.7071067811865476, -0.7071067811865476]
/// )
/// ```
public struct J2KAcceleratedWaveletFilter: Sendable, Equatable {
    /// Analysis lowpass filter coefficients.
    public let analysisLowpass: [Double]

    /// Analysis highpass filter coefficients.
    public let analysisHighpass: [Double]

    /// Synthesis lowpass filter coefficients.
    public let synthesisLowpass: [Double]

    /// Synthesis highpass filter coefficients.
    public let synthesisHighpass: [Double]

    /// Scaling factor applied to the lowpass subband after analysis.
    public let lowpassScale: Double

    /// Scaling factor applied to the highpass subband after analysis.
    public let highpassScale: Double

    /// Creates a new wavelet filter specification.
    ///
    /// - Parameters:
    ///   - analysisLowpass: Analysis lowpass filter coefficients.
    ///   - analysisHighpass: Analysis highpass filter coefficients.
    ///   - synthesisLowpass: Synthesis lowpass filter coefficients.
    ///   - synthesisHighpass: Synthesis highpass filter coefficients.
    ///   - lowpassScale: Scaling factor for the lowpass subband. Defaults to 1.0.
    ///   - highpassScale: Scaling factor for the highpass subband. Defaults to 1.0.
    public init(
        analysisLowpass: [Double],
        analysisHighpass: [Double],
        synthesisLowpass: [Double],
        synthesisHighpass: [Double],
        lowpassScale: Double = 1.0,
        highpassScale: Double = 1.0
    ) {
        self.analysisLowpass = analysisLowpass
        self.analysisHighpass = analysisHighpass
        self.synthesisLowpass = synthesisLowpass
        self.synthesisHighpass = synthesisHighpass
        self.lowpassScale = lowpassScale
        self.highpassScale = highpassScale
    }
}

/// Accelerated wavelet transform for arbitrary filter kernels.
///
/// This type provides hardware-accelerated wavelet transform operations using
/// arbitrary filter coefficients specified by ``J2KAcceleratedWaveletFilter``.
/// On Apple platforms, it uses the Accelerate framework's `vDSP_convD` for
/// high-performance double-precision convolution. On other platforms, it falls
/// back to a manual convolution implementation.
///
/// ## Performance
///
/// On Apple platforms with Accelerate framework:
/// - Uses `vDSP_convD` for vectorized convolution
/// - Symmetric boundary extension for edge handling
/// - Efficient downsampling via stride-based extraction
///
/// ## Usage
///
/// ```swift
/// let filter = J2KAcceleratedWaveletFilter(
///     analysisLowpass: [0.7071067811865476, 0.7071067811865476],
///     analysisHighpass: [-0.7071067811865476, 0.7071067811865476],
///     synthesisLowpass: [0.7071067811865476, 0.7071067811865476],
///     synthesisHighpass: [0.7071067811865476, -0.7071067811865476]
/// )
/// let wavelet = J2KAcceleratedArbitraryWavelet(filter: filter)
///
/// let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
/// let (low, high) = try wavelet.forwardTransform1D(signal: signal)
/// let reconstructed = try wavelet.inverseTransform1D(lowpass: low, highpass: high)
/// ```
public struct J2KAcceleratedArbitraryWavelet: Sendable {
    /// The wavelet filter used for transform operations.
    public let filter: J2KAcceleratedWaveletFilter

    /// Creates a new accelerated arbitrary wavelet transform processor.
    ///
    /// - Parameter filter: The wavelet filter specification to use for transforms.
    public init(filter: J2KAcceleratedWaveletFilter) {
        self.filter = filter
    }

    // MARK: - Availability Check

    /// Indicates whether hardware acceleration is available on this platform.
    ///
    /// Returns `true` on Apple platforms where the Accelerate framework is available,
    /// `false` otherwise. When `false`, software fallback implementations are used.
    public static var isAvailable: Bool {
        #if canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Convolution

    /// Performs 1D convolution of a signal with a filter kernel.
    ///
    /// On Apple platforms, uses `vDSP_convD` for hardware-accelerated
    /// double-precision convolution. On other platforms, uses a manual
    /// convolution loop as a software fallback.
    ///
    /// - Parameters:
    ///   - signal: The input signal to convolve.
    ///   - filter: The filter kernel coefficients.
    /// - Returns: The convolution result with length `signal.count + filter.count - 1`.
    public func convolve(signal: [Double], filter: [Double]) -> [Double] {
        let signalCount = signal.count
        let filterCount = filter.count
        guard signalCount > 0 && filterCount > 0 else {
            return []
        }

        let resultCount = signalCount + filterCount - 1
        var result = [Double](repeating: 0.0, count: resultCount)

        #if canImport(Accelerate)
        // vDSP_convD computes the correlation; to get convolution we reverse the filter.
        let reversedFilter = [Double](filter.reversed())
        reversedFilter.withUnsafeBufferPointer { filterPtr in
            signal.withUnsafeBufferPointer { signalPtr in
                result.withUnsafeMutableBufferPointer { resultPtr in
                    vDSP_convD(
                        signalPtr.baseAddress!, 1,
                        filterPtr.baseAddress!, 1,
                        resultPtr.baseAddress!, 1,
                        vDSP_Length(resultCount),
                        vDSP_Length(filterCount)
                    )
                }
            }
        }
        #else
        for i in 0..<resultCount {
            var sum = 0.0
            for j in 0..<filterCount {
                let signalIdx = i - j
                if signalIdx >= 0 && signalIdx < signalCount {
                    sum += signal[signalIdx] * filter[j]
                }
            }
            result[i] = sum
        }
        #endif

        return result
    }

    // MARK: - Forward Transform

    /// Performs an accelerated 1D forward wavelet transform.
    ///
    /// Applies the analysis filter pair to decompose the input signal into
    /// lowpass (approximation) and highpass (detail) subbands. The signal is
    /// symmetrically extended at the boundaries before convolution, and the
    /// result is downsampled by a factor of 2.
    ///
    /// - Parameter signal: Input signal. Must have at least 2 elements.
    /// - Returns: A tuple containing the lowpass and highpass subbands.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the signal has fewer than 2 elements.
    ///
    /// Example:
    /// ```swift
    /// let (low, high) = try wavelet.forwardTransform1D(signal: signal)
    /// ```
    public func forwardTransform1D(signal: [Double]) throws -> (lowpass: [Double], highpass: [Double]) {
        guard signal.count >= 2 else {
            throw J2KError.invalidParameter("Signal must have at least 2 elements, got \(signal.count)")
        }

        let lowFilter = filter.analysisLowpass
        let highFilter = filter.analysisHighpass

        guard !lowFilter.isEmpty && !highFilter.isEmpty else {
            throw J2KError.invalidParameter("Analysis filter coefficients must not be empty")
        }

        // Symmetric boundary extension
        let maxFilterLen = max(lowFilter.count, highFilter.count)
        let extensionSize = maxFilterLen - 1
        let extended = symmetricExtend(signal: signal, extensionSize: extensionSize)

        // Convolve with analysis filters
        let lowConv = convolve(signal: extended, filter: lowFilter)
        let highConv = convolve(signal: extended, filter: highFilter)

        // The valid region starts after the boundary extension and filter delay
        let offset = extensionSize + (maxFilterLen - 1) / 2

        // Downsample by 2 — extract every other sample from the valid region
        let outputLen = (signal.count + 1) / 2
        var lowpass = [Double](repeating: 0.0, count: outputLen)
        var highpass = [Double](repeating: 0.0, count: outputLen)

        for i in 0..<outputLen {
            let idx = offset + i * 2
            if idx < lowConv.count {
                lowpass[i] = lowConv[idx] * filter.lowpassScale
            }
            if idx < highConv.count {
                highpass[i] = highConv[idx] * filter.highpassScale
            }
        }

        return (lowpass: lowpass, highpass: highpass)
    }

    // MARK: - Inverse Transform

    /// Performs an accelerated 1D inverse wavelet transform.
    ///
    /// Reconstructs the original signal from its lowpass and highpass subbands
    /// by upsampling by 2, convolving with synthesis filters, and summing the
    /// results.
    ///
    /// - Parameters:
    ///   - lowpass: Lowpass (approximation) coefficients.
    ///   - highpass: Highpass (detail) coefficients.
    /// - Returns: The reconstructed signal.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if subbands are empty or have incompatible sizes.
    ///
    /// Example:
    /// ```swift
    /// let reconstructed = try wavelet.inverseTransform1D(lowpass: low, highpass: high)
    /// ```
    public func inverseTransform1D(lowpass: [Double], highpass: [Double]) throws -> [Double] {
        guard !lowpass.isEmpty && !highpass.isEmpty else {
            throw J2KError.invalidParameter("Subbands cannot be empty")
        }

        guard abs(lowpass.count - highpass.count) <= 1 else {
            throw J2KError.invalidParameter(
                "Subband size mismatch: lowpass has \(lowpass.count), highpass has \(highpass.count)"
            )
        }

        let synthLow = filter.synthesisLowpass
        let synthHigh = filter.synthesisHighpass

        guard !synthLow.isEmpty && !synthHigh.isEmpty else {
            throw J2KError.invalidParameter("Synthesis filter coefficients must not be empty")
        }

        // Determine reconstructed signal length
        let outputLen = lowpass.count + highpass.count

        // Upsample by 2: insert zeros between samples
        var upsampledLow = [Double](repeating: 0.0, count: outputLen)
        var upsampledHigh = [Double](repeating: 0.0, count: outputLen)

        // Undo scaling and upsample
        for i in 0..<lowpass.count {
            upsampledLow[i * 2] = lowpass[i] / filter.lowpassScale
        }
        for i in 0..<highpass.count {
            let idx = i * 2 + 1
            if idx < outputLen {
                upsampledHigh[idx] = highpass[i] / filter.highpassScale
            }
        }

        // Convolve with synthesis filters
        let lowConv = convolve(signal: upsampledLow, filter: synthLow)
        let highConv = convolve(signal: upsampledHigh, filter: synthHigh)

        // Sum the two synthesis filter outputs, extracting the valid region
        let filterDelay = (max(synthLow.count, synthHigh.count) - 1) / 2
        var result = [Double](repeating: 0.0, count: outputLen)
        for i in 0..<outputLen {
            let idx = filterDelay + i
            let lowVal = idx < lowConv.count ? lowConv[idx] : 0.0
            let highVal = idx < highConv.count ? highConv[idx] : 0.0
            result[i] = lowVal + highVal
        }

        return result
    }

    // MARK: - Private Helpers

    /// Extends the signal symmetrically at both boundaries.
    ///
    /// - Parameters:
    ///   - signal: The input signal.
    ///   - extensionSize: Number of samples to mirror at each boundary.
    /// - Returns: The extended signal.
    private func symmetricExtend(signal: [Double], extensionSize: Int) -> [Double] {
        guard extensionSize > 0 else { return signal }

        let n = signal.count
        var extended = [Double](repeating: 0.0, count: n + 2 * extensionSize)

        // Mirror left boundary
        for i in 0..<extensionSize {
            let mirrorIdx = min(extensionSize - 1 - i, n - 1)
            extended[i] = signal[mirrorIdx]
        }

        // Copy original signal
        for i in 0..<n {
            extended[extensionSize + i] = signal[i]
        }

        // Mirror right boundary
        for i in 0..<extensionSize {
            let mirrorIdx = max(n - 1 - i, 0)
            extended[extensionSize + n + i] = signal[mirrorIdx]
        }

        return extended
    }
}
