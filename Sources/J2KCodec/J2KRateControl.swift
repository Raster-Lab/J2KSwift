//
// J2KRateControl.swift
// J2KSwift
//
/// # Rate Control
///
/// Implementation of rate-distortion optimisation for JPEG 2000 encoding.
///
/// Rate control determines how to allocate bits across different code blocks
/// and quality layers to achieve a target bitrate while maximising quality.
/// This module implements the PCRD-opt (Post Compression Rate Distortion
/// Optimisation) algorithm from ISO/IEC 15444-1.
///
/// ## Overview
///
/// The rate control process involves:
/// 1. Computing rate-distortion slopes for each coding pass
/// 2. Sorting truncation points by slope
/// 3. Selecting optimal truncation points to meet target rates
/// 4. Forming quality layers with selected passes
///
/// ## Usage
///
/// ```swift
/// // Create rate controller with target rates
/// let rateControl = J2KRateControl(targetRates: [0.5, 1.0, 2.0])
///
/// // Optimise layers for code blocks
/// let layers = try rateControl.optimizeLayers(
///     codeBlocks: codeBlocks,
///     totalPixels: width * height
/// )
/// ```

import Foundation
import J2KCore

// MARK: - Coding Pass Information

/// Information about a single coding pass within a code block.
///
/// Each coding pass represents a refinement of the quantized coefficients.
/// PCRD-opt uses the rate-distortion slope to determine which passes to include.
public struct CodingPassInfo: Sendable {
    /// The code-block index this pass belongs to.
    public let codeBlockIndex: Int

    /// The pass number (0-based) within the code block.
    public let passNumber: Int

    /// The cumulative number of bytes up to and including this pass.
    public let cumulativeBytes: Int

    /// The estimated distortion reduction from including this pass.
    ///
    /// Lower distortion is better. This represents the squared error
    /// reduction compared to not including the pass.
    public let distortion: Double

    /// The rate-distortion slope for this pass.
    ///
    /// Computed as: slope = ΔDistortion / ΔRate
    /// Higher slopes indicate better quality-per-bit.
    public let slope: Double

    /// Creates a new coding pass information structure.
    ///
    /// - Parameters:
    ///   - codeBlockIndex: The code-block index.
    ///   - passNumber: The pass number within the code-block.
    ///   - cumulativeBytes: Cumulative bytes up to this pass.
    ///   - distortion: Distortion reduction from this pass.
    ///   - slope: Rate-distortion slope.
    public init(
        codeBlockIndex: Int,
        passNumber: Int,
        cumulativeBytes: Int,
        distortion: Double,
        slope: Double
    ) {
        self.codeBlockIndex = codeBlockIndex
        self.passNumber = passNumber
        self.cumulativeBytes = cumulativeBytes
        self.distortion = distortion
        self.slope = slope
    }
}

// MARK: - Rate Control Mode

/// Defines the mode for rate control optimisation.
public enum RateControlMode: Sendable, Equatable {
    /// Target a specific bitrate in bits per pixel.
    ///
    /// The encoder will optimise to achieve the target bitrate
    /// while maximising quality.
    case targetBitrate(Double)

    /// Target a constant quality level.
    ///
    /// Quality ranges from 0.0 (lowest) to 1.0 (highest/lossless).
    /// The encoder will include passes until the quality threshold is met.
    case constantQuality(Double)

    /// Lossless mode - include all coding passes.
    case lossless
}

// MARK: - Rate Control Configuration

/// Configuration for rate-distortion optimisation.
public struct RateControlConfiguration: Sendable {
    /// The rate control mode.
    public let mode: RateControlMode

    /// The number of quality layers to generate.
    public let layerCount: Int

    /// Whether to use strict rate matching.
    ///
    /// When true, the encoder will not exceed target rates.
    /// When false, some tolerance is allowed for better quality.
    public let strictRateMatching: Bool

    /// The distortion estimation method.
    public let distortionEstimation: DistortionEstimationMethod

    /// Optional MCT configuration for distortion adjustment.
    ///
    /// When provided, rate-distortion optimisation accounts for
    /// improved compression efficiency from MCT decorrelation.
    public let mctConfiguration: J2KMCTEncodingConfiguration?

    /// Number of image components for MCT distortion estimation.
    public let componentCount: Int

    /// Creates a new rate control configuration.
    ///
    /// - Parameters:
    ///   - mode: The rate control mode.
    ///   - layerCount: Number of quality layers (default: 1).
    ///   - strictRateMatching: Whether to strictly match target rates (default: true).
    ///   - distortionEstimation: Distortion estimation method (default: .normBased).
    ///   - mctConfiguration: Optional MCT configuration for distortion adjustment (default: nil).
    ///   - componentCount: Number of image components (default: 3).
    public init(
        mode: RateControlMode,
        layerCount: Int = 1,
        strictRateMatching: Bool = true,
        distortionEstimation: DistortionEstimationMethod = .normBased,
        mctConfiguration: J2KMCTEncodingConfiguration? = nil,
        componentCount: Int = 3
    ) {
        self.mode = mode
        self.layerCount = layerCount
        self.strictRateMatching = strictRateMatching
        self.distortionEstimation = distortionEstimation
        self.mctConfiguration = mctConfiguration
        self.componentCount = componentCount
    }

    /// Creates a configuration for lossless encoding.
    public static var lossless: RateControlConfiguration {
        RateControlConfiguration(mode: .lossless, layerCount: 1)
    }

    /// Creates a configuration for a target bitrate.
    ///
    /// - Parameters:
    ///   - bitrate: Target bitrate in bits per pixel.
    ///   - layerCount: Number of progressive layers (default: 1).
    /// - Returns: A rate control configuration.
    public static func targetBitrate(_ bitrate: Double, layerCount: Int = 1) -> RateControlConfiguration {
        RateControlConfiguration(
            mode: .targetBitrate(bitrate),
            layerCount: layerCount
        )
    }

    /// Creates a configuration for constant quality encoding.
    ///
    /// - Parameters:
    ///   - quality: Quality level (0.0 to 1.0).
    ///   - layerCount: Number of progressive layers (default: 1).
    /// - Returns: A rate control configuration.
    public static func constantQuality(_ quality: Double, layerCount: Int = 1) -> RateControlConfiguration {
        let clampedQuality = max(0.0, min(1.0, quality))
        return RateControlConfiguration(
            mode: .constantQuality(clampedQuality),
            layerCount: layerCount
        )
    }
}

// MARK: - Distortion Estimation Method

/// Method for estimating distortion in rate-distortion optimisation.
public enum DistortionEstimationMethod: Sendable, Equatable {
    /// Use norm-based estimation (fast, approximate).
    ///
    /// Estimates distortion from the number of coding passes
    /// and coefficient magnitudes without full reconstruction.
    case normBased

    /// Use MSE-based estimation (slower, accurate).
    ///
    /// Computes mean squared error by actually reconstructing
    /// the signal with each truncation point.
    case mseBased

    /// Use a simplified estimation based on bit-plane significance.
    ///
    /// Fast estimation suitable for real-time encoding.
    case simplified
}

// MARK: - Rate Control

/// Implements rate-distortion optimisation for JPEG 2000 encoding.
///
/// This class uses the PCRD-opt algorithm to determine optimal truncation
/// points for code-block contributions across quality layers.
///
/// ## Algorithm Overview
///
/// 1. **Compute R-D Slopes**: For each coding pass in each code-block,
///    compute the rate-distortion slope (quality improvement per bit).
///
/// 2. **Sort Truncation Points**: Create a list of all possible truncation
///    points sorted by descending slope.
///
/// 3. **Select Optimal Points**: For each quality layer, select truncation
///    points that maximise quality while meeting the rate constraint.
///
/// 4. **Form Layers**: Generate quality layer structures with the selected
///    code-block contributions.
///
/// ## Example
///
/// ```swift
/// let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
/// let rateControl = J2KRateControl(configuration: config)
///
/// let layers = try rateControl.optimizeLayers(
///     codeBlocks: encodedBlocks,
///     totalPixels: image.width * image.height
/// )
/// ```
public struct J2KRateControl: Sendable {
    /// The rate control configuration.
    public let configuration: RateControlConfiguration

    /// Creates a new rate control instance.
    ///
    /// - Parameter configuration: The rate control configuration.
    public init(configuration: RateControlConfiguration) {
        self.configuration = configuration
    }

    /// Convenience initializer with target bitrates for each layer.
    ///
    /// - Parameter targetRates: Target bitrates in bits per pixel for each layer.
    public init(targetRates: [Double]) {
        precondition(!targetRates.isEmpty, "Must provide at least one target rate")

        // Use the highest rate as the main target
        let maxRate = targetRates.max() ?? targetRates[0]
        self.configuration = .targetBitrate(maxRate, layerCount: targetRates.count)
    }

    // MARK: - Layer Optimisation

    /// Optimizes quality layers using PCRD-opt algorithm.
    ///
    /// - Parameters:
    ///   - codeBlocks: The encoded code-blocks.
    ///   - totalPixels: Total number of pixels in the image.
    /// - Returns: An array of optimised quality layers.
    /// - Throws: ``J2KError`` if optimisation fails.
    public func optimizeLayers(
        codeBlocks: [J2KCodeBlock],
        totalPixels: Int
    ) throws -> [QualityLayer] {
        guard !codeBlocks.isEmpty else {
            throw J2KError.invalidParameter("Code blocks array is empty")
        }

        guard totalPixels > 0 else {
            throw J2KError.invalidParameter("Total pixels must be positive")
        }

        // Handle lossless mode
        if case .lossless = configuration.mode {
            return [createLosslessLayer(codeBlocks: codeBlocks)]
        }

        // Compute coding pass information with R-D slopes
        let passInfos = try computeCodingPassInfo(codeBlocks: codeBlocks)

        // Generate target rates for each layer
        let targetRates = try computeLayerTargetRates(totalPixels: totalPixels)

        // Form layers using PCRD-opt
        var layers = [QualityLayer]()
        // Track cumulative pass counts per block across layers
        var cumulativePassCounts = [Int: Int]() // blockIndex → total passes so far

        for (layerIndex, targetRate) in targetRates.enumerated() {
            let targetBytes = Int(targetRate * Double(totalPixels) / 8.0)

            let (layer, updatedCounts) = try formLayerPCRDOpt(
                layerIndex: layerIndex,
                targetBytes: targetBytes,
                passInfos: passInfos,
                previousPassCounts: cumulativePassCounts,
                codeBlocks: codeBlocks
            )

            layers.append(layer)
            cumulativePassCounts = updatedCounts
        }

        return layers
    }

    // MARK: - Private Methods

    /// Computes coding pass information with rate-distortion slopes.
    ///
    /// Uses actual per-pass byte counts from EBCOT encoding and a
    /// bit-plane distortion model where each bit-plane contributes
    /// distortion proportional to `(2^bitPlane)^2` per sample.
    private func computeCodingPassInfo(
        codeBlocks: [J2KCodeBlock]
    ) throws -> [CodingPassInfo] {
        var passInfos = [CodingPassInfo]()

        for codeBlock in codeBlocks {
            guard codeBlock.passeCount > 0 else { continue }

            let samples = Double(codeBlock.width * codeBlock.height)

            // Compute per-pass byte increments from passSegmentLengths.
            // If segment lengths are available, use them directly (each entry
            // is the incremental byte count for that pass).
            // Otherwise, distribute total bytes evenly across passes.
            let passBytes: [Int]
            if !codeBlock.passSegmentLengths.isEmpty &&
               codeBlock.passSegmentLengths.count == codeBlock.passeCount {
                passBytes = codeBlock.passSegmentLengths
            } else {
                // Fallback: evenly distribute
                let avg = max(1, codeBlock.data.count / max(1, codeBlock.passeCount))
                passBytes = [Int](repeating: avg, count: codeBlock.passeCount)
            }

            // Each coding pass refines one bit-plane in a 3-pass cycle:
            //   pass 0,1,2 → bit-plane (activeBitPlanes - 1)  [MSB]
            //   pass 3,4,5 → bit-plane (activeBitPlanes - 2)
            //   ...
            // The distortion contribution of a single bit-plane p is
            //   D_p ≈ samples × (2^p)^2 / 3
            // (divided by 3 because the bit-plane has 3 sub-passes).
            let activeBitPlanes = max(1, (codeBlock.passeCount + 2) / 3)

            var cumulativeBytes = 0
            var cumulativeDistortionReduction = 0.0

            for passNum in 0..<codeBlock.passeCount {
                let deltaBytes = passBytes[passNum]
                cumulativeBytes += deltaBytes

                // Which bit-plane does this pass refine?
                let bitPlane = activeBitPlanes - 1 - (passNum / 3)
                let safeBitPlane = max(0, bitPlane)

                // Distortion reduction for this pass
                let bitPlaneValue = pow(2.0, Double(safeBitPlane))
                let deltaDistortion = samples * bitPlaneValue * bitPlaneValue / 3.0

                cumulativeDistortionReduction += deltaDistortion

                // R-D slope = ΔD / ΔR (distortion reduction per bit)
                let deltaBits = Double(deltaBytes) * 8.0
                let slope = deltaBits > 0 ? deltaDistortion / deltaBits : 0.0

                passInfos.append(CodingPassInfo(
                    codeBlockIndex: codeBlock.index,
                    passNumber: passNum,
                    cumulativeBytes: cumulativeBytes,
                    distortion: deltaDistortion,
                    slope: slope
                ))
            }
        }

        return passInfos
    }

    /// Computes target rates for each quality layer.
    private func computeLayerTargetRates(totalPixels: Int) throws -> [Double] {
        switch configuration.mode {
        case .targetBitrate(let bitrate):
            // Generate progressive rates up to target
            var rates = [Double]()
            for i in 1...configuration.layerCount {
                let layerRate = bitrate * Double(i) / Double(configuration.layerCount)
                rates.append(layerRate)
            }
            return rates

        case .constantQuality(let quality):
            // For constant quality, estimate required rate
            let estimatedRate = qualityToBitrate(quality)
            var rates = [Double]()
            for i in 1...configuration.layerCount {
                let layerRate = estimatedRate * Double(i) / Double(configuration.layerCount)
                rates.append(layerRate)
            }
            return rates

        case .lossless:
            // Should not reach here (handled separately)
            throw J2KError.internalError("Lossless mode should be handled separately")
        }
    }

    /// Estimates bitrate required for a given quality level.
    private func qualityToBitrate(_ quality: Double) -> Double {
        // Empirical model: higher quality needs exponentially more bits
        // Quality 0.5 ≈ 1 bpp, Quality 0.9 ≈ 4 bpp, Quality 1.0 = lossless
        if quality >= 1.0 {
            return 24.0 // Typical lossless rate
        }

        // Logarithmic mapping
        let minRate = 0.1  // Minimum bitrate (very low quality)
        let maxRate = 8.0  // High quality bitrate

        return minRate + (maxRate - minRate) * pow(quality, 2.0)
    }

    /// Forms a single quality layer using PCRD-opt algorithm.
    ///
    /// Uses bisection search on the distortion slope threshold to find
    /// the optimal set of coding passes that fits within the target byte
    /// budget. All passes with slope ≥ threshold are included; those
    /// below are excluded.
    ///
    /// Layer contributions are cumulative: each layer's `codeBlockContributions`
    /// maps blockIndex → total passes up to and including this layer.
    /// The caller (generateTileData) computes incremental data per layer
    /// by subtracting previous layer passes.
    private func formLayerPCRDOpt(
        layerIndex: Int,
        targetBytes: Int,
        passInfos: [CodingPassInfo],
        previousPassCounts: [Int: Int],
        codeBlocks: [J2KCodeBlock]
    ) throws -> (QualityLayer, [Int: Int]) {
        // Build a lookup: blockIndex → [passNumber → CodingPassInfo]
        // for efficient cumulative byte retrieval.
        var passLookup = [Int: [Int: CodingPassInfo]]()
        for info in passInfos {
            passLookup[info.codeBlockIndex, default: [:]][info.passNumber] = info
        }

        // Candidate passes: only those beyond what previous layers included.
        let candidates = passInfos.filter { pass in
            let prev = previousPassCounts[pass.codeBlockIndex] ?? 0
            return pass.passNumber >= prev
        }

        guard !candidates.isEmpty else {
            // No new passes available; carry forward previous counts
            let layer = QualityLayer(
                index: layerIndex,
                targetRate: nil,
                codeBlockContributions: previousPassCounts
            )
            return (layer, previousPassCounts)
        }

        // Compute bytes already committed by previous layers
        var previousBytes = 0
        for (blockIdx, prevPasses) in previousPassCounts {
            if prevPasses > 0, let info = passLookup[blockIdx]?[prevPasses - 1] {
                previousBytes += info.cumulativeBytes
            }
        }

        // Bisection search on slope threshold.
        let maxSlope = candidates.max(by: { $0.slope < $1.slope })?.slope ?? 0
        var lo = 0.0
        var hi = maxSlope * 1.1

        // For a given threshold, determine which passes to select and
        // total cumulative bytes (including previous layers).
        func evaluate(threshold: Double) -> (bytes: Int, counts: [Int: Int]) {
            var counts = previousPassCounts // start with prior layer passes
            var totalBytes = previousBytes

            for pass in candidates {
                if pass.slope >= threshold {
                    let blockIdx = pass.codeBlockIndex
                    let passEnd = pass.passNumber + 1

                    // Keep the highest sequential pass per block
                    if let existing = counts[blockIdx] {
                        if passEnd > existing {
                            counts[blockIdx] = passEnd
                        }
                    } else {
                        counts[blockIdx] = passEnd
                    }
                }
            }

            // Recompute total bytes from cumulative counts
            totalBytes = 0
            for (blockIdx, passCount) in counts {
                if passCount > 0, let info = passLookup[blockIdx]?[passCount - 1] {
                    totalBytes += info.cumulativeBytes
                }
            }

            return (totalBytes, counts)
        }

        // Binary search for optimal threshold
        var bestCounts = previousPassCounts
        for _ in 0..<40 {
            let mid = (lo + hi) / 2.0
            let result = evaluate(threshold: mid)

            if result.bytes <= targetBytes {
                bestCounts = result.counts
                hi = mid // try to include more passes (lower threshold)
            } else {
                lo = mid // exclude more passes (higher threshold)
            }
        }

        // If nothing was added beyond previous (very tight budget),
        // at least keep the previous layer contributions
        let hasNewPasses = bestCounts.contains { key, value in
            value > (previousPassCounts[key] ?? 0)
        }
        if !hasNewPasses {
            // Try including everything to see if it fits
            let allResult = evaluate(threshold: 0.0)
            if allResult.bytes <= targetBytes {
                bestCounts = allResult.counts
            }
        }

        let layer = QualityLayer(
            index: layerIndex,
            targetRate: Double(targetBytes * 8) / Double(max(1, passInfos.count)),
            codeBlockContributions: bestCounts
        )

        return (layer, bestCounts)
    }

    /// Creates a lossless quality layer with all coding passes.
    private func createLosslessLayer(codeBlocks: [J2KCodeBlock]) -> QualityLayer {
        var contributions = [Int: Int]()

        for codeBlock in codeBlocks where codeBlock.passeCount > 0 {
            contributions[codeBlock.index] = codeBlock.passeCount
        }

        return QualityLayer(
            index: 0,
            targetRate: nil,
            codeBlockContributions: contributions
        )
    }

    /// Optimizes quality layers and returns metrics alongside layers.
    ///
    /// - Parameters:
    ///   - codeBlocks: The encoded code-blocks.
    ///   - totalPixels: Total number of pixels in the image.
    /// - Returns: A tuple of (layers, metrics).
    /// - Throws: ``J2KError`` if optimisation fails.
    public func optimizeLayersWithMetrics(
        codeBlocks: [J2KCodeBlock],
        totalPixels: Int
    ) throws -> (layers: [QualityLayer], metrics: PCRDMetrics) {
        let layers = try optimizeLayers(codeBlocks: codeBlocks, totalPixels: totalPixels)

        // Compute metrics per layer
        var layerMetrics = [PCRDLayerMetrics]()
        for layer in layers {
            var layerBytes = 0
            var contributingBlocks = 0

            for (blockIdx, passCount) in layer.codeBlockContributions {
                contributingBlocks += 1
                if let block = codeBlocks.first(where: { $0.index == blockIdx }) {
                    layerBytes += truncatedSize(block: block, passes: passCount)
                }
            }

            let actualBpp = totalPixels > 0
                ? Double(layerBytes * 8) / Double(totalPixels) : 0.0

            layerMetrics.append(PCRDLayerMetrics(
                layerIndex: layer.index,
                targetBpp: layer.targetRate.map { $0 / Double(max(1, codeBlocks.count)) * Double(totalPixels) / 8.0 },
                actualBytes: layerBytes,
                actualBpp: actualBpp,
                contributingBlocks: contributingBlocks,
                totalBlocks: codeBlocks.count
            ))
        }

        let totalCodedBytes = codeBlocks.reduce(0) { $0 + $1.data.count }
        let selectedBytes = layerMetrics.last?.actualBytes ?? totalCodedBytes

        let metrics = PCRDMetrics(
            totalCodedBytes: totalCodedBytes,
            selectedBytes: selectedBytes,
            totalPixels: totalPixels,
            layerMetrics: layerMetrics,
            compressionRatio: totalPixels > 0
                ? Double(totalPixels) / Double(max(1, selectedBytes)) : 1.0
        )

        return (layers, metrics)
    }

    /// Computes truncated byte count for a given number of passes.
    private func truncatedSize(block: J2KCodeBlock, passes: Int) -> Int {
        if passes >= block.passeCount {
            return block.data.count
        }
        if !block.passSegmentLengths.isEmpty && block.passSegmentLengths.count >= passes {
            return block.passSegmentLengths.prefix(passes).reduce(0, +)
        }
        return block.data.count * passes / max(1, block.passeCount)
    }
}

// MARK: - PCRD Metrics

/// Metrics from post-compression rate-distortion optimisation.
///
/// Contains target vs actual size information and per-layer details
/// for evaluating PCRD-opt effectiveness.
public struct PCRDMetrics: Sendable {
    /// Total bytes from all code-blocks before truncation.
    public let totalCodedBytes: Int

    /// Total bytes selected after PCRD-opt truncation.
    public let selectedBytes: Int

    /// Total pixel count of the image.
    public let totalPixels: Int

    /// Per-layer metrics.
    public let layerMetrics: [PCRDLayerMetrics]

    /// Overall compression ratio (pixels / selected bytes).
    public let compressionRatio: Double

    /// Savings as a percentage: (1 - selected/total) × 100.
    public var savingsPercent: Double {
        guard totalCodedBytes > 0 else { return 0 }
        return (1.0 - Double(selectedBytes) / Double(totalCodedBytes)) * 100.0
    }

    /// Actual bits per pixel.
    public var actualBpp: Double {
        guard totalPixels > 0 else { return 0 }
        return Double(selectedBytes * 8) / Double(totalPixels)
    }
}

/// Per-layer metrics from PCRD-opt.
public struct PCRDLayerMetrics: Sendable {
    /// The layer index.
    public let layerIndex: Int

    /// Target bits per pixel for this layer (nil for lossless).
    public let targetBpp: Double?

    /// Actual bytes in this layer.
    public let actualBytes: Int

    /// Actual bits per pixel achieved.
    public let actualBpp: Double

    /// Number of code-blocks contributing to this layer.
    public let contributingBlocks: Int

    /// Total number of code-blocks in the image.
    public let totalBlocks: Int
}

// MARK: - Rate-Distortion Statistics

/// Statistics from rate-distortion optimisation.
///
/// Provides information about the optimisation process for analysis
/// and debugging.
public struct RateDistortionStats: Sendable {
    /// The actual bitrate achieved for each layer (bits per pixel).
    public let actualRates: [Double]

    /// The target bitrates that were requested (bits per pixel).
    public let targetRates: [Double]

    /// The estimated distortion for each layer.
    public let distortions: [Double]

    /// The number of code-blocks contributing to each layer.
    public let codeBlockCounts: [Int]

    /// Creates new rate-distortion statistics.
    ///
    /// - Parameters:
    ///   - actualRates: Actual achieved bitrates.
    ///   - targetRates: Target bitrates.
    ///   - distortions: Distortion estimates.
    ///   - codeBlockCounts: Code-block counts per layer.
    public init(
        actualRates: [Double],
        targetRates: [Double],
        distortions: [Double],
        codeBlockCounts: [Int]
    ) {
        self.actualRates = actualRates
        self.targetRates = targetRates
        self.distortions = distortions
        self.codeBlockCounts = codeBlockCounts
    }
}

// MARK: - DC Offset Rate-Distortion Integration

/// Adjusts rate-distortion calculations for DC offset-aware encoding.
///
/// When DC offset is applied, the effective energy of wavelet coefficients
/// is reduced (data is centered around zero), which improves compression
/// efficiency. This utility helps estimate the distortion improvement
/// from DC offset removal.
///
/// ## How It Works
///
/// DC offset removal shifts the mean of component data to zero,
/// reducing the magnitude of low-frequency wavelet coefficients.
/// This results in better quantization efficiency and lower bitrate
/// for equivalent quality.
///
/// ## Usage
///
/// ```swift
/// let adjustment = J2KDCOffsetDistortionAdjustment(
///     dcOffsets: offsetResults,
///     bitDepths: [8, 8, 8]
/// )
/// let factor = adjustment.compressionEfficiencyGain(forComponent: 0)
/// ```
public struct J2KDCOffsetDistortionAdjustment: Sendable {
    /// Per-component DC offset values.
    public let offsets: [J2KDCOffsetValue]

    /// Per-component bit depths.
    public let bitDepths: [Int]

    /// Creates a DC offset distortion adjustment.
    ///
    /// - Parameters:
    ///   - offsets: Per-component DC offset values.
    ///   - bitDepths: Per-component bit depths.
    public init(offsets: [J2KDCOffsetValue], bitDepths: [Int]) {
        self.offsets = offsets
        self.bitDepths = bitDepths
    }

    /// Estimates the compression efficiency gain from DC offset removal.
    ///
    /// Returns a factor (>= 1.0) indicating how much more efficiently
    /// the component can be compressed after DC offset removal.
    ///
    /// - Parameter componentIndex: The component index.
    /// - Returns: The efficiency gain factor (1.0 = no gain).
    public func compressionEfficiencyGain(forComponent componentIndex: Int) -> Double {
        guard componentIndex < offsets.count,
              componentIndex < bitDepths.count else {
            return 1.0
        }

        let offset = offsets[componentIndex]
        let bitDepth = bitDepths[componentIndex]

        guard offset.value != 0.0, bitDepth > 0 else {
            return 1.0
        }

        // The efficiency gain is proportional to the ratio of the offset
        // to the dynamic range. Higher offset relative to range = more gain.
        let maxValue = Double(1 << bitDepth)
        let normalizedOffset = abs(offset.value) / maxValue
        // Typical gain: 5-15% for non-zero mean images
        return 1.0 + normalizedOffset * 0.15
    }

    /// Adjusts a distortion value for DC offset-aware encoding.
    ///
    /// Scales the distortion estimate to account for reduced coefficient
    /// energy after DC offset removal.
    ///
    /// - Parameters:
    ///   - distortion: The original distortion estimate.
    ///   - componentIndex: The component index.
    /// - Returns: The adjusted distortion estimate.
    public func adjustDistortion(_ distortion: Double, forComponent componentIndex: Int) -> Double {
        let gain = compressionEfficiencyGain(forComponent: componentIndex)
        return distortion / gain
    }
}

// MARK: - MCT Rate-Distortion Integration

/// Adjusts rate-distortion calculations for MCT-aware encoding.
///
/// When MCT is applied, component decorrelation reduces redundancy across
/// components, improving compression efficiency. This utility estimates
/// the distortion improvement from MCT application.
///
/// ## How It Works
///
/// MCT transforms components to remove inter-component correlation,
/// concentrating energy in fewer components. This improves quantization
/// efficiency and reduces bitrate for equivalent quality.
///
/// ## Usage
///
/// ```swift
/// let adjustment = J2KMCTDistortionAdjustment(
///     configuration: mctConfig,
///     componentCount: 4
/// )
/// let factor = adjustment.compressionEfficiencyGain()
/// ```
public struct J2KMCTDistortionAdjustment: Sendable {
    /// MCT encoding configuration.
    public let configuration: J2KMCTEncodingConfiguration

    /// Number of image components.
    public let componentCount: Int

    /// Creates an MCT distortion adjustment.
    ///
    /// - Parameters:
    ///   - configuration: MCT encoding configuration.
    ///   - componentCount: Number of image components.
    public init(configuration: J2KMCTEncodingConfiguration, componentCount: Int) {
        self.configuration = configuration
        self.componentCount = componentCount
    }

    /// Estimates the compression efficiency gain from MCT application.
    ///
    /// Returns a factor (>= 1.0) indicating how much more efficiently
    /// components can be compressed after MCT decorrelation.
    ///
    /// The efficiency gain depends on:
    /// - Component count (more components = higher potential gain)
    /// - Transform type (array-based vs dependency)
    /// - Whether extended precision is used
    ///
    /// - Returns: The efficiency gain factor (1.0 = no gain).
    public func compressionEfficiencyGain() -> Double {
        switch configuration.mode {
        case .disabled:
            return 1.0

        case .arrayBased:
            // Array-based MCT provides decorrelation across all components
            // Typical gain: 10-30% for multi-spectral (4+ components)
            // Gain increases with component count
            let baseGain = componentCount >= 4 ? 0.15 : 0.08
            let componentBonus = Double(max(0, componentCount - 3)) * 0.03
            return 1.0 + baseGain + componentBonus

        case .dependency:
            // Dependency transforms are more efficient for sparse correlation
            // Typical gain: 12-35% for multi-spectral imagery
            let baseGain = componentCount >= 4 ? 0.18 : 0.10
            let componentBonus = Double(max(0, componentCount - 3)) * 0.035
            return 1.0 + baseGain + componentBonus

        case .adaptive:
            // Adaptive selection provides optimal transform per tile
            // Highest gain: 15-40% through content-aware decorrelation
            let baseGain = componentCount >= 4 ? 0.22 : 0.12
            let componentBonus = Double(max(0, componentCount - 3)) * 0.04
            return 1.0 + baseGain + componentBonus
        }
    }

    /// Adjusts a distortion value for MCT-aware encoding.
    ///
    /// Scales the distortion estimate to account for improved decorrelation
    /// after MCT application.
    ///
    /// - Parameter distortion: The original distortion estimate.
    /// - Returns: The adjusted distortion estimate.
    public func adjustDistortion(_ distortion: Double) -> Double {
        let gain = compressionEfficiencyGain()
        return distortion / gain
    }

    /// Estimates the distortion improvement for a specific tile.
    ///
    /// When per-tile MCT is configured, different tiles may have
    /// different decorrelation efficiency.
    ///
    /// - Parameters:
    ///   - distortion: The original distortion estimate.
    ///   - tileIndex: The tile index.
    /// - Returns: The adjusted distortion estimate.
    public func adjustDistortion(_ distortion: Double, forTile tileIndex: Int) -> Double {
        // Check for per-tile override
        if configuration.perTileMCT[tileIndex] != nil {
            // Per-tile MCT typically provides better efficiency
            // due to spatial content adaptation
            let gain = compressionEfficiencyGain() * 1.05
            return distortion / gain
        }

        // Use global MCT efficiency
        return adjustDistortion(distortion)
    }
}
