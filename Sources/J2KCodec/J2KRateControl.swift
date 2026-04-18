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

    /// Whether the encoder uses the reversible (5/3) wavelet filter.
    ///
    /// Controls which wavelet synthesis norm table is used for PCRD
    /// distortion weighting. For 9/7 irreversible, the quantization
    /// step sizes already incorporate the norms, so weighting is not applied.
    public let useReversibleFilter: Bool

    /// Number of coding passes per bit-plane in the entropy coder.
    ///
    /// Standard JPEG 2000 (EBCOT) uses 3 passes per bit-plane:
    /// significance propagation, magnitude refinement, and cleanup.
    /// HTJ2K uses 1 cleanup pass (first bit-plane only) then 2 passes
    /// per refinement bit-plane (SigProp + MagRef), so `passesPerBitPlane = 2`
    /// with the first coded plane using only 1 pass.
    public let passesPerBitPlane: Int

    /// Creates a new rate control configuration.
    ///
    /// - Parameters:
    ///   - mode: The rate control mode.
    ///   - layerCount: Number of quality layers (default: 1).
    ///   - strictRateMatching: Whether to strictly match target rates (default: true).
    ///   - distortionEstimation: Distortion estimation method (default: .normBased).
    ///   - mctConfiguration: Optional MCT configuration for distortion adjustment (default: nil).
    ///   - componentCount: Number of image components (default: 3).
    ///   - useReversibleFilter: Whether using the 5/3 reversible wavelet (default: true).
    public init(
        mode: RateControlMode,
        layerCount: Int = 1,
        strictRateMatching: Bool = true,
        distortionEstimation: DistortionEstimationMethod = .normBased,
        mctConfiguration: J2KMCTEncodingConfiguration? = nil,
        componentCount: Int = 3,
        useReversibleFilter: Bool = true,
        passesPerBitPlane: Int = 3
    ) {
        self.mode = mode
        self.layerCount = layerCount
        self.strictRateMatching = strictRateMatching
        self.distortionEstimation = distortionEstimation
        self.mctConfiguration = mctConfiguration
        self.componentCount = componentCount
        self.useReversibleFilter = useReversibleFilter
        self.passesPerBitPlane = passesPerBitPlane
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

        let profiling = ProcessInfo.processInfo.environment["J2K_PROFILE"] != nil
        var rateStart = CFAbsoluteTimeGetCurrent()

        // Compute coding pass information with R-D slopes
        let passInfos = try computeCodingPassInfo(codeBlocks: codeBlocks)

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("      PROFILE rcPassInfos: \(passInfos.count) passes in \(String(format: "%.4f", t - rateStart))s")
            rateStart = t
        }

        // Sort by descending slope (best quality-per-bit first).
        // When slopes tie, prefer smaller and earlier truncation points so
        // higher-rate encodes extend lower-rate choices instead of replacing
        // them with unstable later-pass candidates.
        let sortedPasses = passInfos.sorted { lhs, rhs in
            if lhs.slope != rhs.slope {
                return lhs.slope > rhs.slope
            }
            if lhs.cumulativeBytes != rhs.cumulativeBytes {
                return lhs.cumulativeBytes < rhs.cumulativeBytes
            }
            if lhs.passNumber != rhs.passNumber {
                return lhs.passNumber < rhs.passNumber
            }
            return lhs.codeBlockIndex < rhs.codeBlockIndex
        }

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("      PROFILE rcSort: \(String(format: "%.4f", t - rateStart))s")
            rateStart = t
        }

        // Debug: dump PCRD pass info
        let dumpPCRD = ProcessInfo.processInfo.environment["J2K_DUMP_PCRD"] != nil
        if dumpPCRD {
            print("PCRD_DEBUG: totalPixels=\(totalPixels), codeBlocks=\(codeBlocks.count)")
            // Group passes by code block index
            var blockPassInfos: [Int: [CodingPassInfo]] = [:]
            for pi in passInfos {
                blockPassInfos[pi.codeBlockIndex, default: []].append(pi)
            }
            for (idx, passes) in blockPassInfos.sorted(by: { $0.key < $1.key }) {
                let cb = codeBlocks.first { $0.index == idx }!
                let firstSlope = passes.first?.slope ?? 0
                let maxSlope = passes.map { $0.slope }.max() ?? 0
                let totalBytes = passes.last?.cumulativeBytes ?? 0
                print("  block=\(idx) sub=\(cb.subband) res=\(cb.resolutionLevel) comp=\(cb.componentIndex) passes=\(passes.count) bytes=\(totalBytes) maxSlope=\(String(format: "%.2f", maxSlope)) firstSlope=\(String(format: "%.2f", firstSlope)) sqSum=\(String(format: "%.1f", cb.coefficientSquaredSum))")
            }
        }

        // Generate target rates for each layer
        let targetRates = try computeLayerTargetRates(totalPixels: totalPixels)

        // Form layers using PCRD-opt
        var layers = [QualityLayer]()
        var previousLayerPasses = Set<Int64>()
        var previousBlockCumulativeBytes = [Int: Int]()

        for (layerIndex, targetRate) in targetRates.enumerated() {
            let targetBytes = Int(targetRate * Double(totalPixels) / 8.0)

            if dumpPCRD {
                print("PCRD_LAYER: layer=\(layerIndex) targetRate=\(String(format: "%.3f", targetRate)) targetBytes=\(targetBytes)")
            }

            let (layer, selectedPasses, blockCumBytes) = try formLayerPCRDOpt(
                layerIndex: layerIndex,
                targetBytes: targetBytes,
                totalPixels: totalPixels,
                sortedPasses: sortedPasses,
                previousPasses: previousLayerPasses,
                codeBlocks: codeBlocks,
                previousBlockCumulativeBytes: previousBlockCumulativeBytes
            )

            if dumpPCRD {
                emitLayerDiagnostics(
                    layerIndex: layerIndex,
                    targetBytes: targetBytes,
                    actualBytes: blockCumBytes.values.reduce(0, +),
                    cumulativeBlockBytes: blockCumBytes,
                    codeBlocks: codeBlocks
                )
            }

            layers.append(layer)
            previousLayerPasses = selectedPasses
            previousBlockCumulativeBytes = blockCumBytes
        }

        if profiling {
            let t = CFAbsoluteTimeGetCurrent()
            print("      PROFILE rcLayers: \(layers.count) layers in \(String(format: "%.4f", t - rateStart))s")
        }

        return layers
    }

    // MARK: - Private Methods

    /// L2 norms of the 5/3 (reversible) wavelet synthesis basis functions.
    ///
    /// Indexed by [orient][decomposition_level] where orient: 0=LL, 1=HL, 2=LH, 3=HH
    /// and decomposition_level 0=finest detail up to 9 (max 10 DWT levels).
    /// Values sourced from ISO/IEC 15444-1 Annex E / OpenJPEG reference implementation.
    private static let dwtNorms53: [[Double]] = [
        // LL
        [1.000, 1.500, 2.750, 5.375, 10.688, 21.344, 42.656, 85.281, 170.531, 341.031],
        // HL
        [1.038, 1.592, 2.919, 5.703, 11.330, 22.607, 45.183, 90.335, 180.637, 361.243],
        // LH
        [1.038, 1.592, 2.919, 5.703, 11.330, 22.607, 45.183, 90.335, 180.637, 361.243],
        // HH
        [0.7186, 0.966, 1.649, 3.079, 5.969, 11.777, 23.410, 46.684, 93.233, 186.331],
    ]

    /// L2 norms of the 9/7 (irreversible) wavelet synthesis basis functions.
    private static let dwtNorms97: [[Double]] = [
        // LL
        [1.000, 1.965, 4.177, 8.403, 16.811, 33.622, 67.244, 134.489, 268.978, 537.957],
        // HL
        [2.022, 3.989, 8.355, 17.004, 34.027, 68.054, 136.108, 272.216, 544.432, 1088.864],
        // LH
        [2.022, 3.989, 8.355, 17.004, 34.027, 68.054, 136.108, 272.216, 544.432, 1088.864],
        // HH
        [2.080, 3.865, 8.307, 17.187, 34.726, 69.453, 138.905, 277.810, 555.621, 1111.242],
    ]

    /// Pre-computed powers of 4: pow4Table[p] = 4^p for p in 0..<32.
    /// Replaces expensive pow() calls in distortion estimation hot loops.
    private static let pow4Table: [Double] = (0..<32).map { Double(1 << (2 * $0)) }

    /// Computes coding pass information with rate-distortion slopes.
    private func computeCodingPassInfo(
        codeBlocks: [J2KCodeBlock]
    ) throws -> [CodingPassInfo] {
        let totalPasses = codeBlocks.reduce(0) { $0 + $1.passeCount }
        var passInfos = [CodingPassInfo]()
        passInfos.reserveCapacity(totalPasses)

        // Determine the total number of decomposition levels (NL) from
        // the maximum resolution level across all code blocks.
        var maxResLevel = 0
        for cb in codeBlocks { maxResLevel = max(maxResLevel, cb.resolutionLevel) }

        for codeBlock in codeBlocks {
            guard codeBlock.passeCount > 0 else { continue }

            // Wavelet synthesis norm weighting for PCRD (WMSE model).
            //
            // For the 5/3 reversible wavelet: coefficient-domain distortion
            // does NOT equal pixel-domain MSE because the wavelet is
            // biorthogonal and integer coefficients have no quantization
            // step normalization. Weight by the full squared L2 norm.
            //
            // For the 9/7 irreversible wavelet:
            //   step_b = Δ_base / K_b  (K_b = synthesis L2 norm)
            //   c_q    = coeff / step_b = coeff × K_b / Δ_base
            //   Pixel error from 1 unit of c_q error = step_b × K_b = Δ_base
            //
            // Therefore MSE_pixel = Δ_base² × Σ e_q², which is the SAME
            // constant for all subbands. For cross-subband PCRD comparison,
            // pixel distortion = coeff_distortion × (1/K_b)² ∝ 1/norm_b².
            // This lets PCRD correctly prioritize LL (energy-dominant) over
            // fine-detail HL/HH subbands without double-counting the norms.
            let subbandWeight: Double
            if maxResLevel > 0 {
                let resLevel = codeBlock.resolutionLevel
                let orient: Int
                let dwtLevel: Int  // 0-indexed decomposition level (0 = finest detail)

                if resLevel == 0 {
                    // LL subband at the coarsest level
                    orient = 0  // LL
                    dwtLevel = maxResLevel - 1
                } else {
                    // Detail subband: DWT level = NL - resolutionLevel (0-indexed)
                    dwtLevel = maxResLevel - resLevel
                    switch codeBlock.subband {
                    case .ll: orient = 0
                    case .hl: orient = 1
                    case .lh: orient = 2
                    case .hh: orient = 3
                    }
                }

                if configuration.useReversibleFilter {
                    // 5/3 reversible: full squared norm weighting needed because
                    // integer coefficients have no quantization step normalization.
                    let clampedLevel = min(dwtLevel, Self.dwtNorms53[0].count - 1)
                    let norm = Self.dwtNorms53[orient][clampedLevel]
                    subbandWeight = norm * norm
                } else {
                    // 9/7 irreversible: quantization step sizes FULLY incorporate
                    // the wavelet norms (Δ_b = Δ_base / K_b). The pixel-domain MSE
                    // contribution from subband b is:
                    //
                    //   MSE_pixel = step_b² × K_b² × Σ(error_q)²
                    //             = (Δ_base/K_b)² × K_b² × Σ(error_q)²
                    //             = Δ_base² × Σ(error_q)²
                    //
                    // Since Δ_base is constant across subbands, all subbands
                    // contribute equally to pixel MSE per unit of quantized-domain
                    // distortion. This matches OpenJPEG's t1_getwmsedec() which
                    // computes w2 = 8192 × step² × norm² = 8192 × Δ_base² (constant).
                    //
                    // Therefore, equal PCRD weight for all subbands is correct.
                    subbandWeight = 1.0
                }
            } else {
                subbandWeight = 1.0
            }

            // For multi-component lossy images using ICT, prioritize the first
            // transformed component (luminance-like Y) slightly over chroma.
            // This improves low-bitrate RGB quality without altering the overall
            // byte budget or affecting grayscale/high-bit-depth single-component paths.
            let componentWeight: Double
            if !configuration.useReversibleFilter && configuration.componentCount >= 3 {
                switch codeBlock.componentIndex {
                case 0:
                    componentWeight = 1.35
                case 1, 2:
                    componentWeight = 0.90
                default:
                    componentWeight = 1.0
                }
            } else {
                componentWeight = 1.0
            }
            let effectiveWeight = subbandWeight * componentWeight

            // Use tracked per-pass byte counts when available, otherwise estimate
            let hasPerPassBytes = !codeBlock.cumulativePassBytes.isEmpty
                && codeBlock.cumulativePassBytes.count >= codeBlock.passeCount

            // Use actual per-pass distortion when the encoder provided it.
            // This is especially important for HTJ2K medical workloads, where
            // the coarse population-only fallback can mis-rank truncation points
            // even though the block coder has already measured real distortion
            // reduction for each emitted pass.
            let hasActualDistortion = !codeBlock.cumulativePassDistortion.isEmpty
                && codeBlock.cumulativePassDistortion.count >= codeBlock.passeCount

            let initialDistortion = estimateInitialDistortion(codeBlock: codeBlock) * effectiveWeight

            var previousCumulativeBytes = 0
            var previousDistortion = initialDistortion
            var blockPassInfos = [CodingPassInfo]()
            blockPassInfos.reserveCapacity(codeBlock.passeCount)

            for passNum in 0..<codeBlock.passeCount {
                let cumulativeBytes: Int
                if hasPerPassBytes {
                    cumulativeBytes = codeBlock.cumulativePassBytes[passNum]
                } else {
                    // Fallback: uniform estimate
                    let bytesPerPass = max(1, codeBlock.data.count / codeBlock.passeCount)
                    cumulativeBytes = (passNum + 1) * bytesPerPass
                }

                let passBytes = max(0, cumulativeBytes - previousCumulativeBytes)

                let htPassWeight: Double
                if configuration.passesPerBitPlane == 2 && configuration.componentCount == 1 {
                    if passNum == 0 {
                        htPassWeight = configuration.useReversibleFilter ? 0.82 : 0.92
                    } else if passNum.isMultiple(of: 2) {
                        htPassWeight = configuration.useReversibleFilter ? 1.32 : 1.14
                    } else {
                        htPassWeight = configuration.useReversibleFilter ? 1.14 : 1.06
                    }
                } else {
                    htPassWeight = 1.0
                }

                let distortion: Double
                if hasActualDistortion {
                    // Actual remaining distortion from the encoder's tracked pass data.
                    // These cumulativePassDistortion values are interpreted in the
                    // quantised coefficient domain (sum of m²−e² reductions).
                    // Apply the same subbandWeight to convert to pixel MSE.
                    let remaining = max(0.0, codeBlock.coefficientSquaredSum - codeBlock.cumulativePassDistortion[passNum])
                    distortion = remaining * effectiveWeight * htPassWeight
                } else {
                    // Fallback: model-based estimate
                    distortion = estimateDistortion(
                        codeBlock: codeBlock,
                        passNumber: passNum,
                        totalPasses: codeBlock.passeCount
                    ) * effectiveWeight * htPassWeight
                }

                // Compute rate-distortion slope.
                // Some refinement passes do not increase the terminated byte count;
                // they should be treated as effectively free quality gains rather
                // than penalized as a synthetic 1-byte increase.
                let deltaDistortion = max(0.0, previousDistortion - distortion)
                let deltaRate = Double(passBytes * 8) // bits

                let slope: Double
                if deltaDistortion <= 0 {
                    slope = 0.0
                } else if deltaRate == 0 {
                    slope = Double.greatestFiniteMagnitude
                } else {
                    slope = deltaDistortion / deltaRate
                }

                blockPassInfos.append(CodingPassInfo(
                    codeBlockIndex: codeBlock.index,
                    passNumber: passNum,
                    cumulativeBytes: cumulativeBytes,
                    distortion: distortion,
                    slope: slope
                ))

                previousCumulativeBytes = cumulativeBytes
                previousDistortion = distortion
            }

            guard !blockPassInfos.isEmpty else { continue }

            // Collapse truncation points with identical cumulative byte counts.
            // Later zero-byte refinement passes dominate earlier ones at the same
            // rate, so keep only the furthest pass and recompute the effective
            // slope against the previous distinct-byte point.
            var collapsedPassInfos = [CodingPassInfo]()
            collapsedPassInfos.reserveCapacity(blockPassInfos.count)
            var groupStart = 0
            var previousFrontierBytes = 0
            var previousFrontierDistortion = initialDistortion
            var previousFrontierSlope = Double.greatestFiniteMagnitude

            while groupStart < blockPassInfos.count {
                let groupBytes = blockPassInfos[groupStart].cumulativeBytes
                var groupEnd = groupStart
                while groupEnd + 1 < blockPassInfos.count &&
                        blockPassInfos[groupEnd + 1].cumulativeBytes == groupBytes {
                    groupEnd += 1
                }

                let representative = blockPassInfos[groupEnd]
                let frontierDeltaDistortion = max(0.0, previousFrontierDistortion - representative.distortion)
                let frontierDeltaRate = Double(max(0, representative.cumulativeBytes - previousFrontierBytes) * 8)

                let frontierSlope: Double
                if frontierDeltaDistortion <= 0 {
                    frontierSlope = 0.0
                } else if frontierDeltaRate == 0 {
                    frontierSlope = Double.greatestFiniteMagnitude
                } else {
                    frontierSlope = min(frontierDeltaDistortion / frontierDeltaRate, previousFrontierSlope)
                    previousFrontierSlope = frontierSlope
                }

                collapsedPassInfos.append(CodingPassInfo(
                    codeBlockIndex: representative.codeBlockIndex,
                    passNumber: representative.passNumber,
                    cumulativeBytes: representative.cumulativeBytes,
                    distortion: representative.distortion,
                    slope: frontierSlope
                ))

                previousFrontierBytes = representative.cumulativeBytes
                previousFrontierDistortion = representative.distortion
                groupStart = groupEnd + 1
            }

            passInfos.append(contentsOf: collapsedPassInfos)
        }

        return passInfos
    }

    /// Estimates the initial distortion (before any coding passes).
    ///
    /// Computes the initial distortion (before any coding passes).
    ///
    /// When the code block has actual coefficient squared sum data, uses
    /// it directly (this is the sum of squared quantized magnitudes).
    /// Otherwise falls back to a model-based estimate.
    private func estimateInitialDistortion(codeBlock: J2KCodeBlock) -> Double {
        // Use actual coefficient data when available
        if codeBlock.coefficientSquaredSum > 0 {
            return codeBlock.coefficientSquaredSum
        }

        // Fallback: model-based estimate
        let samples = codeBlock.width * codeBlock.height
        let significantBitPlanes = max(1, codeBlock.passeCount / 3)
        let bitPlaneWeight = Double(1 << min(significantBitPlanes, 30))
        return Double(samples) * bitPlaneWeight
    }

    /// Estimates distortion for a code-block after a given number of passes.
    ///
    /// When `bitPlanePopulation` data is available (count of coefficients per
    /// MSB position), uses population-weighted distortion that accurately
    /// reflects the actual coefficient distribution. This is far more accurate
    /// than the generic 4× per plane model for natural images where most
    /// coefficients are small (heavy-tailed distribution).
    ///
    /// Falls back to the generic exponential model when population data is
    /// unavailable.
    private func estimateDistortion(
        codeBlock: J2KCodeBlock,
        passNumber: Int,
        totalPasses: Int
    ) -> Double {
        let initialDistortion = estimateInitialDistortion(codeBlock: codeBlock)

        // Use population-based model when available
        let pop = codeBlock.bitPlanePopulation
        if !pop.isEmpty {
            return estimateDistortionFromPopulation(
                population: pop,
                passNumber: passNumber,
                totalPasses: totalPasses,
                zeroBitPlanes: codeBlock.zeroBitPlanes,
                initialDistortion: initialDistortion
            )
        }

        // Fallback: generic exponential model
        // Standard JPEG 2000: 3 coding passes per bit-plane (SPP, MagRef, Cleanup)
        // HTJ2K: 1 cleanup pass + 2 passes per refinement bit-plane (SigProp, MagRef)
        // Each bit plane reduces distortion by factor of 4
        let ppbp = configuration.passesPerBitPlane
        let codedPlanes: Int
        let codedPlanesRemainder: Int
        if ppbp == 2 {
            // HTJ2K: pass 0 = cleanup (1 plane), then 2 passes per additional plane
            codedPlanes = passNumber == 0 ? 1 : 1 + passNumber / 2
            codedPlanesRemainder = passNumber == 0 ? 0 : passNumber % 2
        } else {
            // Standard: 3 passes per plane
            codedPlanes = (passNumber + 1) / 3
            codedPlanesRemainder = (passNumber + 1) % 3
        }
        let intReduction = Self.pow4Table[min(codedPlanes, 31)]
        // Fractional sub-plane: approximate 4^(r/3) with linear interpolation
        let fracFactor = codedPlanesRemainder == 0 ? 1.0
            : (codedPlanesRemainder == 1 ? 1.587 : 2.52)  // 4^(1/3), 4^(2/3)
        let distortionReduction = 1.0 / (intReduction * fracFactor)

        return initialDistortion * distortionReduction
    }

    /// Population-weighted distortion estimation.
    ///
    /// Uses the actual coefficient magnitude distribution (from
    /// `bitPlanePopulation`) to compute remaining distortion after coding
    /// a given number of passes.
    ///
    /// The population array has `population[p]` = count of coefficients
    /// whose quantized magnitude has MSB at bit position p. Bit planes
    /// are coded from the highest MSB downward; each 3 passes code one
    /// bit plane.
    ///
    /// After coding k bit planes from the top:
    /// - Coefficients with MSB in the coded range have been (partially) refined.
    ///   Their remaining error ≈ 4^(lowestCodedPlane) / 3 per coefficient.
    /// - Coefficients with MSB below the coded range are still unknown.
    ///   Their distortion ≈ (1.5 × 2^p)² per coefficient (expected magnitude²).
    private func estimateDistortionFromPopulation(
        population: [Int],
        passNumber: Int,
        totalPasses: Int,
        zeroBitPlanes: Int,
        initialDistortion: Double
    ) -> Double {
        let numBitPlanes = population.count
        guard numBitPlanes > 0 else {
            let ppbp = configuration.passesPerBitPlane
            let codedPlanes: Int
            if ppbp == 2 {
                codedPlanes = passNumber == 0 ? 1 : 1 + passNumber / 2
            } else {
                codedPlanes = (passNumber + 1) / 3
            }
            return initialDistortion / Self.pow4Table[min(codedPlanes, 31)]
        }

        // Bit planes are coded from MSB down. The top 'zeroBitPlanes' are
        // all-zero (no coefficients there), so actual coding starts from
        // plane (numBitPlanes - 1 - zeroBitPlanes) and goes down.
        let topCodedPlane = numBitPlanes - 1 - zeroBitPlanes
        guard topCodedPlane >= 0 else {
            return 0.0
        }

        // Number of bit planes coded so far.
        // Standard JPEG 2000: 3 passes per plane.
        // HTJ2K: 1 cleanup pass + 2 passes per refinement plane.
        let ppbp = configuration.passesPerBitPlane
        let codedPlanes: Int
        if ppbp == 2 {
            codedPlanes = passNumber == 0 ? 1 : 1 + passNumber / 2
        } else {
            codedPlanes = Int((passNumber + 1) / 3)
        }
        let lowestCodedPlane = max(0, topCodedPlane - codedPlanes + 1)

        var remainingDistortion = 0.0

        for p in 0..<numBitPlanes {
            let count = population[p]
            guard count > 0 else { continue }

            if p >= lowestCodedPlane && p <= topCodedPlane {
                // This plane has been coded. Remaining error per coefficient
                // is approximately (2^lowestCodedPlane)² / 3, representing
                // the uncoded bits below the lowest coded plane.
                let errorPerCoeff = Self.pow4Table[min(lowestCodedPlane, 31)] / 3.0
                remainingDistortion += Double(count) * errorPerCoeff
            } else if p < lowestCodedPlane {
                // This plane has NOT been coded. Coefficients are still
                // unknown to the decoder → full magnitude error.
                // Expected magnitude² ≈ 2.25 × 4^p for uniform dist in [2^p, 2^(p+1))
                let errorPerCoeff = 2.25 * Self.pow4Table[min(p, 31)]
                remainingDistortion += Double(count) * errorPerCoeff
            }
            // Planes above topCodedPlane are all-zero (zeroBitPlanes), no contribution
        }

        // Normalize: the ratio of remaining distortion to initial should
        // give the distortion fraction. Using the population-derived
        // initial distortion for consistency.
        let popInitial = populationBasedInitialDistortion(population: population)
        if popInitial > 0 {
            // Scale to match the actual initial distortion
            return initialDistortion * (remainingDistortion / popInitial)
        }

        return remainingDistortion
    }

    /// Computes initial distortion from population data (for normalization).
    private func populationBasedInitialDistortion(population: [Int]) -> Double {
        var total = 0.0
        for p in 0..<population.count {
            let count = population[p]
            guard count > 0 else { continue }
            // Expected magnitude² for coefficients with MSB at p:
            // magnitude ∈ [2^p, 2^(p+1)), expected(m²) ≈ 2.25 × 4^p
            total += Double(count) * 2.25 * Self.pow4Table[min(p, 31)]
        }
        return total
    }

    /// Computes target rates for each quality layer.
    private func computeLayerTargetRates(totalPixels: Int) throws -> [Double] {
        switch configuration.mode {
        case .targetBitrate(let bitrate):
            // Generate progressive rates up to target.
            // HTJ2K can benefit from a small matched-rate allowance on
            // single-component medical imagery, but the previous blanket
            // 16–35% inflation systematically produced oversized codestreams.
            // Keep only a narrow low-rate compensation so compression stays
            // close to J2K while preserving the quality guard rails.
            let effectiveBitrate: Double
            if configuration.passesPerBitPlane == 2,
               configuration.componentCount == 1 {
                let compensation: Double
                if configuration.useReversibleFilter {
                    if bitrate <= 0.50 {
                        compensation = 1.25
                    } else if bitrate <= 1.00 {
                        compensation = 1.22
                    } else if bitrate <= 1.50 {
                        compensation = 1.14
                    } else {
                        compensation = 1.05
                    }
                } else {
                    if bitrate <= 0.50 {
                        compensation = 1.08
                    } else if bitrate <= 1.00 {
                        compensation = 1.05
                    } else {
                        compensation = 1.02
                    }
                }
                effectiveBitrate = bitrate * compensation
            } else {
                effectiveBitrate = bitrate
            }

            var rates = [Double]()
            for i in 1...configuration.layerCount {
                let layerRate = effectiveBitrate * Double(i) / Double(configuration.layerCount)
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
    ///
    /// Returns bits-per-pixel across ALL components. The base mapping is
    /// calibrated for a single component (matching OpenJPEG grayscale),
    /// then scaled by `componentCount` so that multi-component images
    /// (e.g. RGB) receive proportionally more bits.
    ///
    /// Single-component reference points:
    /// - q=0.95 → ~2.0 bpp/component (near-lossless)
    /// - q=0.80 → ~1.0 bpp/component (high visual quality)
    /// - q=0.50 → ~0.4 bpp/component (medium quality, matches OpenJPEG -r 20 for 8-bit)
    /// - q=0.20 → ~0.15 bpp/component (low quality)
    private func qualityToBitrate(_ quality: Double) -> Double {
        let baseBpp: Double
        if quality >= 1.0 {
            baseBpp = 8.0 // Near-lossless
        } else if quality >= 0.95 {
            baseBpp = 2.0 + (quality - 0.95) * 120.0   // 2.0→8.0 for q 0.95→1.0
        } else if quality >= 0.80 {
            baseBpp = 1.0 + (quality - 0.80) * 6.667   // 1.0→2.0 for q 0.80→0.95
        } else if quality >= 0.50 {
            baseBpp = 0.4 + (quality - 0.50) * 2.0     // 0.4→1.0 for q 0.50→0.80
        } else if quality >= 0.20 {
            baseBpp = 0.15 + (quality - 0.20) * 0.833  // 0.15→0.4 for q 0.20→0.50
        } else {
            baseBpp = 0.05 + quality * 0.5             // 0.05→0.15 for q 0→0.20
        }
        // Scale by component count: RGB needs 3× the bits of grayscale
        // at the same visual quality. totalPixels is spatial (W×H), so
        // the budget bpp × W × H / 8 must cover all component data.
        return baseBpp * Double(configuration.componentCount)
    }

    /// Forms a single quality layer using PCRD-opt algorithm.
    private func formLayerPCRDOpt(
        layerIndex: Int,
        targetBytes: Int,
        totalPixels: Int,
        sortedPasses: [CodingPassInfo],
        previousPasses: Set<Int64>,
        codeBlocks: [J2KCodeBlock],
        previousBlockCumulativeBytes: [Int: Int]
    ) throws -> (QualityLayer, Set<Int64>, [Int: Int]) {
        var contributions = [Int: Int](minimumCapacity: codeBlocks.count)
        var selectedPasses = previousPasses
        var blockCumulativeBytes = previousBlockCumulativeBytes

        let dumpPCRD = ProcessInfo.processInfo.environment["J2K_DUMP_PCRD"] != nil
        var currentBytes = blockCumulativeBytes.values.reduce(0, +)

        var consecutiveSkips = 0
        let maxConsecutiveSkips = 64
        var fallbackPass: CodingPassInfo?
        var fallbackIncrementalBytes = Int.max
        var nearTargetOvershootPass: CodingPassInfo?
        var nearTargetOvershootBytes = Int.max

        let profiling = ProcessInfo.processInfo.environment["J2K_PROFILE"] != nil
        var iterations = 0

        for passInfo in sortedPasses {
            iterations += 1
            let passKey = (Int64(passInfo.codeBlockIndex) &<< 32) | Int64(passInfo.passNumber)
            if selectedPasses.contains(passKey) {
                continue
            }

            let previousBlockBytes = blockCumulativeBytes[passInfo.codeBlockIndex] ?? 0
            let incrementalBytes = max(0, passInfo.cumulativeBytes - previousBlockBytes)

            if shouldDeferHTDeepRefinement(
                passInfo: passInfo,
                incrementalBytes: incrementalBytes,
                currentBytes: currentBytes,
                targetBytes: targetBytes,
                sortedPasses: sortedPasses,
                selectedPasses: selectedPasses,
                contributions: contributions,
                blockCumulativeBytes: blockCumulativeBytes
            ) {
                if dumpPCRD {
                    let formattedSlope = String(format: "%.2f", passInfo.slope)
                    print("PCRD_DEFER: block=\(passInfo.codeBlockIndex) pass=\(passInfo.passNumber) slope=\(formattedSlope) incBytes=\(incrementalBytes) current=\(currentBytes) target=\(targetBytes)")
                }
                consecutiveSkips += 1
                continue
            }

            if configuration.strictRateMatching && currentBytes + incrementalBytes > targetBytes {
                if currentBytes == 0 && incrementalBytes > 0 {
                    let isBetterFallback = incrementalBytes < fallbackIncrementalBytes ||
                        (incrementalBytes == fallbackIncrementalBytes && passInfo.slope > (fallbackPass?.slope ?? 0.0))
                    if isBetterFallback {
                        fallbackPass = passInfo
                        fallbackIncrementalBytes = incrementalBytes
                    }
                } else if incrementalBytes > 0 {
                    let overshootBytes = currentBytes + incrementalBytes - targetBytes
                    let undershootBytes = max(0, targetBytes - currentBytes)
                    let overshootWindowDivisor = configuration.passesPerBitPlane == 2 ? 8 : 16
                    let allowedOvershoot = max(1, targetBytes / overshootWindowDivisor)

                    if overshootBytes > 0 && overshootBytes < undershootBytes && overshootBytes <= allowedOvershoot {
                        let isBetterNearTarget = overshootBytes < nearTargetOvershootBytes ||
                            (overshootBytes == nearTargetOvershootBytes && passInfo.slope > (nearTargetOvershootPass?.slope ?? 0.0))
                        if isBetterNearTarget {
                            nearTargetOvershootPass = passInfo
                            nearTargetOvershootBytes = overshootBytes
                        }
                    }
                }

                if dumpPCRD {
                    print("PCRD_SKIP: block=\(passInfo.codeBlockIndex) pass=\(passInfo.passNumber) slope=\(String(format: "%.2f", passInfo.slope)) incBytes=\(incrementalBytes) cumBytes=\(passInfo.cumulativeBytes) current=\(currentBytes) target=\(targetBytes)")
                }
                consecutiveSkips += 1
                if currentBytes > 0 && consecutiveSkips >= maxConsecutiveSkips {
                    break
                }
                continue
            }

            consecutiveSkips = 0

            contributions[passInfo.codeBlockIndex] = max(
                contributions[passInfo.codeBlockIndex] ?? 0,
                passInfo.passNumber + 1
            )
            blockCumulativeBytes[passInfo.codeBlockIndex] = max(
                blockCumulativeBytes[passInfo.codeBlockIndex] ?? 0,
                passInfo.cumulativeBytes
            )
            currentBytes += incrementalBytes
            if passInfo.passNumber >= 0 {
                for prefixPass in 0...passInfo.passNumber {
                    let prefixKey = (Int64(passInfo.codeBlockIndex) &<< 32) | Int64(prefixPass)
                    selectedPasses.insert(prefixKey)
                }
            }

            if currentBytes >= targetBytes {
                if configuration.strictRateMatching {
                    continue
                }
                break
            }
        }

        if contributions.isEmpty, let fallbackPass {
            contributions[fallbackPass.codeBlockIndex] = fallbackPass.passNumber + 1
            blockCumulativeBytes[fallbackPass.codeBlockIndex] = fallbackPass.cumulativeBytes
            currentBytes = fallbackPass.cumulativeBytes
            if fallbackPass.passNumber >= 0 {
                for prefixPass in 0...fallbackPass.passNumber {
                    let prefixKey = (Int64(fallbackPass.codeBlockIndex) &<< 32) | Int64(prefixPass)
                    selectedPasses.insert(prefixKey)
                }
            }
        } else if currentBytes < targetBytes, let nearTargetOvershootPass {
            let passKey = (Int64(nearTargetOvershootPass.codeBlockIndex) &<< 32) | Int64(nearTargetOvershootPass.passNumber)
            if !selectedPasses.contains(passKey) {
                let previousBlockBytes = blockCumulativeBytes[nearTargetOvershootPass.codeBlockIndex] ?? 0
                let incrementalBytes = max(0, nearTargetOvershootPass.cumulativeBytes - previousBlockBytes)
                let overshootBytes = currentBytes + incrementalBytes - targetBytes
                let undershootBytes = max(0, targetBytes - currentBytes)
                let overshootWindowDivisor = configuration.passesPerBitPlane == 2 ? 8 : 16
                let allowedOvershoot = max(1, targetBytes / overshootWindowDivisor)

                if incrementalBytes > 0 && overshootBytes > 0 && overshootBytes < undershootBytes && overshootBytes <= allowedOvershoot {
                    contributions[nearTargetOvershootPass.codeBlockIndex] = max(
                        contributions[nearTargetOvershootPass.codeBlockIndex] ?? 0,
                        nearTargetOvershootPass.passNumber + 1
                    )
                    blockCumulativeBytes[nearTargetOvershootPass.codeBlockIndex] = max(
                        blockCumulativeBytes[nearTargetOvershootPass.codeBlockIndex] ?? 0,
                        nearTargetOvershootPass.cumulativeBytes
                    )
                    currentBytes += incrementalBytes
                    if nearTargetOvershootPass.passNumber >= 0 {
                        for prefixPass in 0...nearTargetOvershootPass.passNumber {
                            let prefixKey = (Int64(nearTargetOvershootPass.codeBlockIndex) &<< 32) | Int64(prefixPass)
                            selectedPasses.insert(prefixKey)
                        }
                    }
                }
            }
        }

        if profiling {
            print("        PROFILE formLayer: \(iterations) iters, \(contributions.count) blocks, target=\(targetBytes) actual=\(currentBytes)")
        }

        let layer = QualityLayer(
            index: layerIndex,
            targetRate: Double(targetBytes * 8) / Double(totalPixels),
            codeBlockContributions: contributions
        )

        return (layer, selectedPasses, blockCumulativeBytes)
    }

    /// Returns whether a deep HT refinement frontier should be deferred in favour
    /// of a comparable cheaper first-pass coverage candidate from another block.
    ///
    /// This helps the strict single-layer HTJ2K matched-rate path avoid spending
    /// the remaining budget on a deep late refinement when a new block can still
    /// contribute clinically useful structure at nearly the same slope.
    private func shouldDeferHTDeepRefinement(
        passInfo: CodingPassInfo,
        incrementalBytes: Int,
        currentBytes: Int,
        targetBytes: Int,
        sortedPasses: [CodingPassInfo],
        selectedPasses: Set<Int64>,
        contributions: [Int: Int],
        blockCumulativeBytes: [Int: Int]
    ) -> Bool {
        guard configuration.passesPerBitPlane == 2,
              configuration.strictRateMatching,
              configuration.componentCount == 1 else {
            return false
        }

        let existingContribution = contributions[passInfo.codeBlockIndex] ?? 0
        let remainingBudget = targetBytes - currentBytes

        guard existingContribution > 0,
              passInfo.passNumber >= 2,
              incrementalBytes > 1,
              remainingBudget > 0,
              incrementalBytes >= remainingBudget,
              remainingBudget <= max(3, targetBytes / 6) else {
            return false
        }

        for alternativePass in sortedPasses {
            let alternativeKey = (Int64(alternativePass.codeBlockIndex) &<< 32) | Int64(alternativePass.passNumber)
            if selectedPasses.contains(alternativeKey) {
                continue
            }
            if alternativePass.codeBlockIndex == passInfo.codeBlockIndex {
                continue
            }
            if (contributions[alternativePass.codeBlockIndex] ?? 0) > 0 {
                continue
            }

            let alternativeIncrementalBytes = max(
                0,
                alternativePass.cumulativeBytes - (blockCumulativeBytes[alternativePass.codeBlockIndex] ?? 0)
            )
            if alternativePass.passNumber > 1 {
                continue
            }
            if alternativeIncrementalBytes == 0 || alternativeIncrementalBytes >= incrementalBytes {
                continue
            }
            if currentBytes + alternativeIncrementalBytes > targetBytes {
                continue
            }
            if alternativePass.slope < passInfo.slope * 0.90 {
                continue
            }

            return true
        }

        return false
    }

    /// Emits optional per-layer PCRD diagnostics for debugging rate allocation.
    private func emitLayerDiagnostics(
        layerIndex: Int,
        targetBytes: Int,
        actualBytes: Int,
        cumulativeBlockBytes: [Int: Int],
        codeBlocks: [J2KCodeBlock]
    ) {
        let undershoot = targetBytes > 0
            ? Double(targetBytes - actualBytes) / Double(targetBytes)
            : 0.0
        let formattedUndershoot = String(format: "%.3f", undershoot)
        print(
            "PCRD_SUMMARY: layer=\(layerIndex) targetBytes=\(targetBytes) actualBytes=\(actualBytes) undershoot=\(formattedUndershoot) blocks=\(cumulativeBlockBytes.count)"
        )

        var availableByComponent = [Int: Int]()
        var actualByComponent = [Int: Int]()

        for block in codeBlocks {
            availableByComponent[block.componentIndex, default: 0] += block.data.count
        }

        let blockByIndex = Dictionary(uniqueKeysWithValues: codeBlocks.map { ($0.index, $0) })
        for (blockIndex, bytes) in cumulativeBlockBytes {
            guard let block = blockByIndex[blockIndex] else { continue }
            actualByComponent[block.componentIndex, default: 0] += bytes
        }

        let totalAvailable = max(1, availableByComponent.values.reduce(0, +))
        let components = availableByComponent.keys.sorted()
        if components.count > 1 {
            for component in components {
                let availableBytes = availableByComponent[component] ?? 0
                let targetShare = Double(availableBytes) / Double(totalAvailable)
                let componentTarget = Int((Double(targetBytes) * targetShare).rounded())
                let componentActual = actualByComponent[component] ?? 0
                print(
                    "PCRD_COMPONENT: layer=\(layerIndex) comp=\(component) targetBytes=\(componentTarget) actualBytes=\(componentActual) availableBytes=\(availableBytes)"
                )
            }
        }
    }

    /// Creates a lossless quality layer with all coding passes.
    private func createLosslessLayer(codeBlocks: [J2KCodeBlock]) -> QualityLayer {
        var contributions = [Int: Int]()
        let dumpPasses = ProcessInfo.processInfo.environment["J2K_DUMP_PASSES"] != nil

        for codeBlock in codeBlocks where codeBlock.passeCount > 0 {
            if dumpPasses {
                print("LOSSLESS_LAYER: block=\(codeBlock.index) passeCount=\(codeBlock.passeCount) data=\(codeBlock.data.count)")
            }
            contributions[codeBlock.index] = codeBlock.passeCount
        }

        return QualityLayer(
            index: 0,
            targetRate: nil,
            codeBlockContributions: contributions
        )
    }
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
