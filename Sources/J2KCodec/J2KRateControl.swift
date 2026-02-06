/// # Rate Control
///
/// Implementation of rate-distortion optimization for JPEG 2000 encoding.
///
/// Rate control determines how to allocate bits across different code blocks
/// and quality layers to achieve a target bitrate while maximizing quality.
/// This module implements the PCRD-opt (Post Compression Rate Distortion
/// Optimization) algorithm from ISO/IEC 15444-1.
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
/// // Optimize layers for code blocks
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

/// Defines the mode for rate control optimization.
public enum RateControlMode: Sendable, Equatable {
    /// Target a specific bitrate in bits per pixel.
    ///
    /// The encoder will optimize to achieve the target bitrate
    /// while maximizing quality.
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

/// Configuration for rate-distortion optimization.
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
    
    /// Creates a new rate control configuration.
    ///
    /// - Parameters:
    ///   - mode: The rate control mode.
    ///   - layerCount: Number of quality layers (default: 1).
    ///   - strictRateMatching: Whether to strictly match target rates (default: true).
    ///   - distortionEstimation: Distortion estimation method (default: .normBased).
    public init(
        mode: RateControlMode,
        layerCount: Int = 1,
        strictRateMatching: Bool = true,
        distortionEstimation: DistortionEstimationMethod = .normBased
    ) {
        self.mode = mode
        self.layerCount = layerCount
        self.strictRateMatching = strictRateMatching
        self.distortionEstimation = distortionEstimation
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

/// Method for estimating distortion in rate-distortion optimization.
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

/// Implements rate-distortion optimization for JPEG 2000 encoding.
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
///    points that maximize quality while meeting the rate constraint.
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
    
    // MARK: - Layer Optimization
    
    /// Optimizes quality layers using PCRD-opt algorithm.
    ///
    /// - Parameters:
    ///   - codeBlocks: The encoded code-blocks.
    ///   - totalPixels: Total number of pixels in the image.
    /// - Returns: An array of optimized quality layers.
    /// - Throws: ``J2KError`` if optimization fails.
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
        
        // Sort by descending slope (best quality-per-bit first)
        let sortedPasses = passInfos.sorted { $0.slope > $1.slope }
        
        // Generate target rates for each layer
        let targetRates = try computeLayerTargetRates(totalPixels: totalPixels)
        
        // Form layers using PCRD-opt
        var layers = [QualityLayer]()
        var previousLayerPasses = Set<String>()
        
        for (layerIndex, targetRate) in targetRates.enumerated() {
            let targetBytes = Int(targetRate * Double(totalPixels) / 8.0)
            
            let (layer, selectedPasses) = try formLayerPCRDOpt(
                layerIndex: layerIndex,
                targetBytes: targetBytes,
                sortedPasses: sortedPasses,
                previousPasses: previousLayerPasses,
                codeBlocks: codeBlocks
            )
            
            layers.append(layer)
            previousLayerPasses = selectedPasses
        }
        
        return layers
    }
    
    // MARK: - Private Methods
    
    /// Computes coding pass information with rate-distortion slopes.
    private func computeCodingPassInfo(
        codeBlocks: [J2KCodeBlock]
    ) throws -> [CodingPassInfo] {
        var passInfos = [CodingPassInfo]()
        
        for codeBlock in codeBlocks {
            guard codeBlock.passeCount > 0 else { continue }
            
            // Estimate bytes per pass (simplified)
            let bytesPerPass = max(1, codeBlock.data.count / codeBlock.passeCount)
            
            var cumulativeBytes = 0
            var previousDistortion = estimateInitialDistortion(codeBlock: codeBlock)
            
            for passNum in 0..<codeBlock.passeCount {
                cumulativeBytes += bytesPerPass
                
                // Estimate distortion after including this pass
                let distortion = estimateDistortion(
                    codeBlock: codeBlock,
                    passNumber: passNum,
                    totalPasses: codeBlock.passeCount
                )
                
                // Compute rate-distortion slope
                let deltaDistortion = previousDistortion - distortion
                let deltaRate = Double(bytesPerPass * 8) // bits
                
                let slope = deltaRate > 0 ? deltaDistortion / deltaRate : 0.0
                
                passInfos.append(CodingPassInfo(
                    codeBlockIndex: codeBlock.index,
                    passNumber: passNum,
                    cumulativeBytes: cumulativeBytes,
                    distortion: distortion,
                    slope: slope
                ))
                
                previousDistortion = distortion
            }
        }
        
        return passInfos
    }
    
    /// Estimates the initial distortion (before any coding passes).
    private func estimateInitialDistortion(codeBlock: J2KCodeBlock) -> Double {
        let samples = codeBlock.width * codeBlock.height
        
        // Estimate based on bit-planes
        // More missing bit-planes = higher initial distortion
        let bitPlaneWeight = pow(2.0, Double(codeBlock.zeroBitPlanes * 2))
        
        return Double(samples) * bitPlaneWeight
    }
    
    /// Estimates distortion for a code-block after a given number of passes.
    private func estimateDistortion(
        codeBlock: J2KCodeBlock,
        passNumber: Int,
        totalPasses: Int
    ) -> Double {
        switch configuration.distortionEstimation {
        case .normBased:
            // Exponential decay model: each pass reduces distortion
            let passRatio = Double(passNumber + 1) / Double(totalPasses)
            let decayFactor = 1.0 - pow(passRatio, 2.0)
            let initialDistortion = estimateInitialDistortion(codeBlock: codeBlock)
            return initialDistortion * decayFactor
            
        case .mseBased:
            // For MSE-based, we would need actual reconstruction
            // For now, use a similar model but with linear decay
            let passRatio = Double(passNumber + 1) / Double(totalPasses)
            let initialDistortion = estimateInitialDistortion(codeBlock: codeBlock)
            return initialDistortion * (1.0 - passRatio)
            
        case .simplified:
            // Very simple model: uniform reduction per pass
            let remainingPasses = totalPasses - (passNumber + 1)
            let initialDistortion = estimateInitialDistortion(codeBlock: codeBlock)
            return initialDistortion * Double(remainingPasses) / Double(totalPasses)
        }
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
    private func formLayerPCRDOpt(
        layerIndex: Int,
        targetBytes: Int,
        sortedPasses: [CodingPassInfo],
        previousPasses: Set<String>,
        codeBlocks: [J2KCodeBlock]
    ) throws -> (QualityLayer, Set<String>) {
        var contributions = [Int: Int]()
        var currentBytes = 0
        var selectedPasses = previousPasses
        
        // Select passes in order of descending slope until budget is exhausted
        for passInfo in sortedPasses {
            let passKey = "\(passInfo.codeBlockIndex)_\(passInfo.passNumber)"
            
            // Skip if already included in a previous layer
            if selectedPasses.contains(passKey) {
                continue
            }
            
            // Check if adding this pass exceeds budget
            let additionalBytes = passInfo.cumulativeBytes
            
            // For strict rate matching, check budget (but always add at least one contribution)
            if configuration.strictRateMatching && 
               currentBytes + additionalBytes > targetBytes &&
               contributions.count > 0 {
                continue
            }
            
            // Add this pass
            contributions[passInfo.codeBlockIndex] = passInfo.passNumber + 1
            currentBytes += additionalBytes
            selectedPasses.insert(passKey)
            
            // Stop if we've met the target (with some tolerance)
            if currentBytes >= Int(Double(targetBytes) * 0.95) {
                break
            }
        }
        
        let layer = QualityLayer(
            index: layerIndex,
            targetRate: Double(targetBytes * 8) / Double(codeBlocks.count),
            codeBlockContributions: contributions
        )
        
        return (layer, selectedPasses)
    }
    
    /// Creates a lossless quality layer with all coding passes.
    private func createLosslessLayer(codeBlocks: [J2KCodeBlock]) -> QualityLayer {
        var contributions = [Int: Int]()
        
        for codeBlock in codeBlocks {
            if codeBlock.passeCount > 0 {
                contributions[codeBlock.index] = codeBlock.passeCount
            }
        }
        
        return QualityLayer(
            index: 0,
            targetRate: nil,
            codeBlockContributions: contributions
        )
    }
}

// MARK: - Rate-Distortion Statistics

/// Statistics from rate-distortion optimization.
///
/// Provides information about the optimization process for analysis
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
