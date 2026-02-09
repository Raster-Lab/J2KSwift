/// # Bit-Plane Coder
///
/// Implementation of the EBCOT bit-plane coding algorithm for JPEG 2000.
///
/// The EBCOT (Embedded Block Coding with Optimized Truncation) algorithm encodes
/// wavelet coefficients using three coding passes per bit-plane:
/// 1. Significance Propagation Pass (SPP)
/// 2. Magnitude Refinement Pass (MRP)
/// 3. Cleanup Pass (CP)
///
/// ## Topics
///
/// ### Encoding
/// - ``BitPlaneCoder``
///
/// ### Decoding
/// - ``BitPlaneDecoder``

import Foundation
import J2KCore

// MARK: - Coding Pass Type

/// The type of coding pass in EBCOT bit-plane coding.
public enum CodingPassType: Sendable {
    /// Significance propagation pass.
    case significancePropagation
    
    /// Magnitude refinement pass.
    case magnitudeRefinement
    
    /// Cleanup pass.
    case cleanup
}

// MARK: - Coding Options

/// Configuration options for bit-plane coding.
///
/// These options control the encoding behavior, including bypass mode and termination.
public struct CodingOptions: Sendable {
    /// Enable selective arithmetic coding bypass mode.
    ///
    /// When enabled, magnitude refinement passes after a certain bit-plane
    /// use raw (bypass) mode instead of context-adaptive arithmetic coding.
    public let bypassEnabled: Bool
    
    /// The bit-plane index at which to start using bypass mode.
    ///
    /// Only applies when `bypassEnabled` is true. Bypass mode is used for
    /// magnitude refinement passes in bit-planes less than this threshold.
    /// A value of 0 disables bypass mode effectively.
    public let bypassThreshold: Int
    
    /// The termination mode for arithmetic coding.
    ///
    /// Controls how the MQ-coder terminates its encoded output. Different
    /// modes offer trade-offs between compression efficiency and error resilience.
    public let terminationMode: TerminationMode
    
    /// Whether to reset the encoder after each coding pass (predictable termination).
    ///
    /// When enabled, the encoder state is reset after each coding pass,
    /// allowing independent decoding of each pass. This is automatically
    /// enabled when `terminationMode` is `.predictable`.
    public var resetOnEachPass: Bool {
        return terminationMode == .predictable
    }
    
    /// Creates new coding options.
    ///
    /// - Parameters:
    ///   - bypassEnabled: Enable bypass mode (default: false).
    ///   - bypassThreshold: Bit-plane threshold for bypass (default: 0).
    ///   - terminationMode: The termination mode (default: `.default`).
    public init(
        bypassEnabled: Bool = false,
        bypassThreshold: Int = 0,
        terminationMode: TerminationMode = .default
    ) {
        self.bypassEnabled = bypassEnabled
        self.bypassThreshold = max(0, bypassThreshold)
        self.terminationMode = terminationMode
    }
    
    /// Default coding options (no bypass, default termination).
    public static let `default` = CodingOptions()
    
    /// Typical bypass configuration for improved speed.
    ///
    /// Enables bypass mode for magnitude refinement passes in the lower 4 bit-planes.
    public static let fastEncoding = CodingOptions(bypassEnabled: true, bypassThreshold: 4)
    
    /// Predictable termination for error resilience.
    ///
    /// Each coding pass can be independently decoded, enabling error resilience
    /// and parallel decoding at the cost of compression efficiency.
    public static let errorResilient = CodingOptions(terminationMode: .predictable)
    
    /// Near-optimal termination for better compression.
    ///
    /// Uses a tighter termination sequence to minimize wasted bits.
    public static let optimalCompression = CodingOptions(terminationMode: .nearOptimal)
}

// MARK: - Bit-Plane Coder

/// Encodes wavelet coefficients using EBCOT bit-plane coding.
///
/// The bit-plane coder processes coefficients from most significant to least
/// significant bit-plane. Each bit-plane is coded in three passes that handle
/// different coefficient states efficiently.
///
/// ## Example
///
/// ```swift
/// var coder = BitPlaneCoder(width: 32, height: 32, subband: .ll)
/// let coefficients: [Int32] = ... // Wavelet coefficients
/// let encoded = try coder.encode(coefficients: coefficients, bitDepth: 12)
/// ```
public struct BitPlaneCoder: Sendable {
    /// The width of the code-block.
    public let width: Int
    
    /// The height of the code-block.
    public let height: Int
    
    /// The subband type for context formation.
    public let subband: J2KSubband
    
    /// The context modeler for this subband.
    private let contextModeler: ContextModeler
    
    /// The neighbor calculator.
    private let neighborCalculator: NeighborCalculator
    
    /// Coding options for this encoder.
    private let options: CodingOptions
    
    /// Creates a new bit-plane coder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    ///   - options: Coding options (default: `.default`).
    public init(width: Int, height: Int, subband: J2KSubband, options: CodingOptions = .default) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
        self.options = options
    }
    
    /// Encodes wavelet coefficients using EBCOT bit-plane coding.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to encode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - maxPasses: Maximum number of coding passes to generate (optional).
    /// - Returns: A tuple containing the encoded data, the number of coding passes,
    ///   the number of zero bit-planes, and per-pass segment lengths (empty if not predictable termination).
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        coefficients: [Int32],
        bitDepth: Int,
        maxPasses: Int? = nil
    ) throws -> (data: Data, passCount: Int, zeroBitPlanes: Int, passSegmentLengths: [Int]) {
        guard coefficients.count == width * height else {
            throw J2KError.invalidParameter("Coefficient count mismatch")
        }
        
        // Find the number of zero bit-planes (MSBs that are all zero)
        let (magnitudes, signs) = separateMagnitudesAndSigns(coefficients)
        let maxMagnitude = magnitudes.max() ?? 0
        let activeBitPlanes = maxMagnitude > 0 ? Int(log2(Double(maxMagnitude))) + 1 : 0
        let zeroBitPlanes = max(0, bitDepth - activeBitPlanes)
        
        // Initialize state arrays
        var states = [CoefficientState](repeating: [], count: width * height)
        var firstRefineFlags = [Bool](repeating: false, count: width * height)
        let signArray = signs
        
        // Initialize MQ encoder and contexts
        var encoder = MQEncoder()
        var contextStates = ContextStateArray()
        
        // For predictable termination, we collect pass data separately
        var passDataSegments: [Data] = []
        
        var passCount = 0
        let maxPassLimit = maxPasses ?? (3 * activeBitPlanes)
        
        // Process each bit-plane from MSB to LSB
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << bitPlane
            
            // Determine if bypass mode should be used for this bit-plane
            let useBypass = options.bypassEnabled && bitPlane < options.bypassThreshold
            
            // Pass 1: Significance Propagation Pass
            if passCount < maxPassLimit {
                encodeSignificancePropagationPass(
                    magnitudes: magnitudes,
                    signs: signArray,
                    states: &states,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates
                )
                passCount += 1
                
                // For predictable mode, finish and reset after each pass
                if options.resetOnEachPass {
                    let passData = encoder.finish(mode: options.terminationMode)
                    passDataSegments.append(passData)
                    encoder.reset()
                    contextStates.reset()
                }
            }
            
            // Pass 2: Magnitude Refinement Pass
            if passCount < maxPassLimit {
                // Prepare for bypass mode if enabled
                if useBypass {
                    encoder.prepareForBypass()
                }
                
                encodeMagnitudeRefinementPass(
                    magnitudes: magnitudes,
                    states: &states,
                    firstRefineFlags: &firstRefineFlags,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates,
                    useBypass: useBypass
                )
                passCount += 1
                
                // For predictable mode, finish and reset after each pass
                if options.resetOnEachPass {
                    let passData = encoder.finish(mode: options.terminationMode)
                    passDataSegments.append(passData)
                    encoder.reset()
                    contextStates.reset()
                }
            }
            
            // Pass 3: Cleanup Pass
            if passCount < maxPassLimit {
                encodeCleanupPass(
                    magnitudes: magnitudes,
                    signs: signArray,
                    states: &states,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates
                )
                passCount += 1
                
                // For predictable mode, finish and reset after each pass
                if options.resetOnEachPass {
                    let passData = encoder.finish(mode: options.terminationMode)
                    passDataSegments.append(passData)
                    encoder.reset()
                    contextStates.reset()
                }
            }
            
            // Clear coded-this-pass flags for next bit-plane
            for i in 0..<states.count {
                states[i].remove(.codedThisPass)
            }
        }
        
        // Finish encoding
        let encodedData: Data
        var segmentLengths: [Int] = []
        if options.resetOnEachPass {
            // Concatenate all pass data segments
            var combinedData = Data()
            for segment in passDataSegments {
                segmentLengths.append(segment.count)
                combinedData.append(segment)
            }
            encodedData = combinedData
        } else {
            // Single termination at the end
            encodedData = encoder.finish(mode: options.terminationMode)
        }
        
        return (encodedData, passCount, zeroBitPlanes, segmentLengths)
    }
    
    /// Separates coefficients into magnitudes and signs.
    private func separateMagnitudesAndSigns(_ coefficients: [Int32]) -> ([UInt32], [Bool]) {
        var magnitudes = [UInt32](repeating: 0, count: coefficients.count)
        var signs = [Bool](repeating: false, count: coefficients.count)
        
        for (i, coeff) in coefficients.enumerated() {
            if coeff < 0 {
                magnitudes[i] = UInt32(-coeff)
                signs[i] = true
            } else {
                magnitudes[i] = UInt32(coeff)
                signs[i] = false
            }
        }
        
        return (magnitudes, signs)
    }
    
    // MARK: - Significance Propagation Pass
    
    /// Encodes the significance propagation pass.
    ///
    /// This pass codes coefficients that are not yet significant but have at least
    /// one significant neighbor. It exploits the spatial correlation between
    /// neighboring coefficients.
    private func encodeSignificancePropagationPass(
        magnitudes: [UInt32],
        signs: [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Skip if already significant or coded this pass
                if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                    continue
                }
                
                // Check if any neighbors are significant
                let neighbors = neighborCalculator.calculate(
                    x: x, y: y,
                    states: states,
                    signs: signs
                )
                
                // Only process if at least one neighbor is significant
                guard neighbors.hasAny else { continue }
                
                // Get significance context
                let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                
                // Check if this coefficient becomes significant at this bit-plane
                let isSignificant = (magnitudes[idx] & bitMask) != 0
                
                // Encode significance bit
                encoder.encode(symbol: isSignificant, context: &contexts[sigContext])
                
                if isSignificant {
                    // Encode sign
                    let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                    let signBit = signs[idx]
                    let codedSign = signBit != xorBit // XOR with prediction
                    encoder.encode(symbol: codedSign, context: &contexts[signContext])
                    
                    // Update state
                    states[idx].insert(.significant)
                    if signBit {
                        states[idx].insert(.signBit)
                    }
                }
                
                states[idx].insert(.codedThisPass)
            }
        }
    }
    
    // MARK: - Magnitude Refinement Pass
    
    /// Encodes the magnitude refinement pass.
    ///
    /// This pass refines the magnitude of coefficients that are already significant
    /// by coding additional bits from subsequent bit-planes. Can use bypass mode
    /// for improved encoding speed.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - encoder: The MQ encoder.
    ///   - contexts: The context states.
    ///   - useBypass: Whether to use bypass (raw) mode instead of arithmetic coding.
    private func encodeMagnitudeRefinementPass(
        magnitudes: [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray,
        useBypass: Bool = false
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Only process coefficients that are significant and not coded this pass
                guard states[idx].contains(.significant) else { continue }
                guard !states[idx].contains(.codedThisPass) else { continue }
                
                // Get the bit value
                let bitValue = (magnitudes[idx] & bitMask) != 0
                
                if useBypass {
                    // Use bypass (raw) mode - no context
                    encoder.encodeBypass(symbol: bitValue)
                } else {
                    // Use context-adaptive arithmetic coding
                    // Check if this is the first refinement
                    let isFirstRefinement = !firstRefineFlags[idx]
                    
                    // Get neighbors to determine context
                    let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
                    let hasSignificantNeighbors = neighbors.hasAny
                    
                    // Get magnitude refinement context
                    let magContext = contextModeler.magnitudeRefinementContext(
                        firstRefinement: isFirstRefinement,
                        neighborsWereSignificant: hasSignificantNeighbors
                    )
                    
                    // Encode the magnitude bit
                    encoder.encode(symbol: bitValue, context: &contexts[magContext])
                }
                
                // Update refinement flag
                if !firstRefineFlags[idx] {
                    firstRefineFlags[idx] = true
                }
                
                states[idx].insert(.codedThisPass)
            }
        }
    }
    
    // MARK: - Cleanup Pass
    
    /// Encodes the cleanup pass.
    ///
    /// This pass codes all remaining coefficients that were not coded in the
    /// significance propagation or magnitude refinement passes. It uses run-length
    /// coding for efficiency when processing stripes of 4 rows.
    private func encodeCleanupPass(
        magnitudes: [UInt32],
        signs: [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray
    ) {
        // Process in stripes of 4 rows
        let stripeHeight = 4
        
        for stripeY in stride(from: 0, to: height, by: stripeHeight) {
            let stripeEnd = min(stripeY + stripeHeight, height)
            
            for x in 0..<width {
                // Check if this column is eligible for run-length coding
                let eligible = isEligibleForRunLengthCoding(
                    x: x,
                    stripeStart: stripeY,
                    stripeEnd: stripeEnd,
                    states: states
                )
                
                if eligible {
                    // Check if any coefficient in the column becomes significant
                    let hasSignificant = anyBecomeSignificant(
                        x: x,
                        stripeStart: stripeY,
                        stripeEnd: stripeEnd,
                        magnitudes: magnitudes,
                        bitMask: bitMask
                    )
                    
                    // Encode run-length flag: true if at least one becomes significant
                    encoder.encode(symbol: hasSignificant, context: &contexts[.runLength])
                    
                    if !hasSignificant {
                        // All coefficients remain zero, mark as coded and skip
                        for y in stripeY..<stripeEnd {
                            let idx = y * width + x
                            states[idx].insert(.codedThisPass)
                        }
                        continue
                    }
                } else {
                }
                
                // Process individually (either not eligible for RLC, or RLC flag indicated significance)
                // Per ISO/IEC 15444-1, states are updated immediately as each coefficient
                // is processed, so subsequent coefficients see updated neighbor states.
                
                for y in stripeY..<stripeEnd {
                    let idx = y * width + x
                    
                    // Skip if already coded or significant
                    if states[idx].contains(.codedThisPass) || states[idx].contains(.significant) {
                        continue
                    }
                    
                    // Get neighbors (using current state which includes any updates
                    // from previously processed coefficients in this stripe column)
                    let neighbors = neighborCalculator.calculate(
                        x: x, y: y,
                        states: states,
                        signs: signs
                    )
                    
                    // Get significance context
                    let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                    
                    // Check if significant
                    let isSignificant = (magnitudes[idx] & bitMask) != 0
                    
                    // Encode significance
                    encoder.encode(symbol: isSignificant, context: &contexts[sigContext])
                    
                    if isSignificant {
                        // Encode sign
                        let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                        let signBit = signs[idx]
                        let codedSign = signBit != xorBit
                        encoder.encode(symbol: codedSign, context: &contexts[signContext])
                        
                        // Update state immediately
                        states[idx].insert(.significant)
                        if signBit {
                            states[idx].insert(.signBit)
                        }
                    }
                    
                    states[idx].insert(.codedThisPass)
                }
            }
        }
    }
    
    /// Checks if a column is eligible for run-length coding.
    ///
    /// A column is eligible if all coefficients are not yet significant,
    /// not already coded, and have no significant neighbors.
    private func isEligibleForRunLengthCoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState]
    ) -> Bool {
        for y in stripeStart..<stripeEnd {
            let idx = y * width + x
            
            // Can't use RLC if any coefficient is already significant or coded
            if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                return false
            }
            
            // Can't use RLC if any neighbor is significant
            let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
            if neighbors.hasAny {
                return false
            }
        }
        
        return true
    }
    
    /// Checks if any coefficient in a column becomes significant at this bit-plane.
    private func anyBecomeSignificant(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        magnitudes: [UInt32],
        bitMask: UInt32
    ) -> Bool {
        for y in stripeStart..<stripeEnd {
            let idx = y * width + x
            if (magnitudes[idx] & bitMask) != 0 {
                return true
            }
        }
        return false
    }
    
    /// Checks if run-length coding can be used for a column in a stripe (legacy method for encoder).
    ///
    /// This checks both eligibility AND that no coefficients become significant.
    /// Kept for backwards compatibility but prefer using isEligibleForRunLengthCoding + anyBecomeSignificant.
    private func canUseRunLengthCoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState],
        magnitudes: [UInt32],
        bitMask: UInt32
    ) -> Bool {
        return isEligibleForRunLengthCoding(x: x, stripeStart: stripeStart, stripeEnd: stripeEnd, states: states) &&
               !anyBecomeSignificant(x: x, stripeStart: stripeStart, stripeEnd: stripeEnd, magnitudes: magnitudes, bitMask: bitMask)
    }
}

// MARK: - Bit-Plane Decoder

/// Decodes wavelet coefficients using EBCOT bit-plane decoding.
///
/// The bit-plane decoder reverses the encoding process, reconstructing
/// wavelet coefficients from the compressed bitstream.
public struct BitPlaneDecoder: Sendable {
    /// The width of the code-block.
    public let width: Int
    
    /// The height of the code-block.
    public let height: Int
    
    /// The subband type for context formation.
    public let subband: J2KSubband
    
    /// The context modeler for this subband.
    private let contextModeler: ContextModeler
    
    /// The neighbor calculator.
    private let neighborCalculator: NeighborCalculator
    
    /// Coding options for this decoder.
    private let options: CodingOptions
    
    /// Creates a new bit-plane decoder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    ///   - options: Coding options (default: `.default`).
    public init(width: Int, height: Int, subband: J2KSubband, options: CodingOptions = .default) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
        self.options = options
    }
    
    /// Decodes wavelet coefficients from EBCOT encoded data.
    ///
    /// - Parameters:
    ///   - data: The encoded data.
    ///   - passCount: The number of coding passes to decode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - zeroBitPlanes: The number of zero bit-planes.
    ///   - passSegmentLengths: Per-pass segment byte lengths for predictable termination (empty for default).
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        data: Data,
        passCount: Int,
        bitDepth: Int,
        zeroBitPlanes: Int,
        passSegmentLengths: [Int] = []
    ) throws -> [Int32] {
        // Initialize coefficient arrays
        var magnitudes = [UInt32](repeating: 0, count: width * height)
        var signs = [Bool](repeating: false, count: width * height)
        var states = [CoefficientState](repeating: [], count: width * height)
        var firstRefineFlags = [Bool](repeating: false, count: width * height)
        
        // Determine if we need per-pass segment decoding
        let usePerPassSegments = !passSegmentLengths.isEmpty
        
        // For per-pass segments, split data into individual segments
        var passSegments: [Data] = []
        if usePerPassSegments {
            let totalSegmentLength = passSegmentLengths.reduce(0, +)
            guard totalSegmentLength <= data.count else {
                throw J2KError.invalidParameter(
                    "Pass segment lengths total (\(totalSegmentLength)) exceeds data size (\(data.count))"
                )
            }
            var offset = 0
            for length in passSegmentLengths {
                let end = offset + length
                passSegments.append(Data(data[offset..<end]))
                offset = end
            }
        }
        
        // Initialize MQ decoder and contexts
        var decoder: MQDecoder
        var contextStates = ContextStateArray()
        var passSegmentIndex = 0
        
        if usePerPassSegments && !passSegments.isEmpty {
            decoder = MQDecoder(data: passSegments[0])
            passSegmentIndex = 1
        } else {
            decoder = MQDecoder(data: data)
        }
        
        let activeBitPlanes = bitDepth - zeroBitPlanes
        var passesDecoded = 0
        
        // Process each bit-plane from MSB to LSB
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << bitPlane
            
            // Determine if bypass mode should be used for this bit-plane
            let useBypass = options.bypassEnabled && bitPlane < options.bypassThreshold
            
            // Pass 1: Significance Propagation Pass
            if passesDecoded < passCount {
                decodeSignificancePropagationPass(
                    magnitudes: &magnitudes,
                    signs: &signs,
                    states: &states,
                    bitMask: bitMask,
                    decoder: &decoder,
                    contexts: &contextStates
                )
                passesDecoded += 1
                
                // For predictable termination, reset decoder for next pass
                if usePerPassSegments && passSegmentIndex < passSegments.count {
                    decoder = MQDecoder(data: passSegments[passSegmentIndex])
                    contextStates.reset()
                    passSegmentIndex += 1
                }
            }
            
            // Pass 2: Magnitude Refinement Pass
            if passesDecoded < passCount {
                // Prepare for bypass mode if enabled
                if useBypass {
                    decoder.prepareForBypass()
                }
                
                decodeMagnitudeRefinementPass(
                    magnitudes: &magnitudes,
                    states: &states,
                    firstRefineFlags: &firstRefineFlags,
                    bitMask: bitMask,
                    decoder: &decoder,
                    contexts: &contextStates,
                    useBypass: useBypass
                )
                passesDecoded += 1
                
                // For predictable termination, reset decoder for next pass
                if usePerPassSegments && passSegmentIndex < passSegments.count {
                    decoder = MQDecoder(data: passSegments[passSegmentIndex])
                    contextStates.reset()
                    passSegmentIndex += 1
                }
            }
            
            // Pass 3: Cleanup Pass
            if passesDecoded < passCount {
                decodeCleanupPass(
                    magnitudes: &magnitudes,
                    signs: &signs,
                    states: &states,
                    bitMask: bitMask,
                    decoder: &decoder,
                    contexts: &contextStates
                )
                passesDecoded += 1
                
                // For predictable termination, reset decoder for next pass
                if usePerPassSegments && passSegmentIndex < passSegments.count {
                    decoder = MQDecoder(data: passSegments[passSegmentIndex])
                    contextStates.reset()
                    passSegmentIndex += 1
                }
            }
            
            // Clear coded-this-pass flags for next bit-plane
            for i in 0..<states.count {
                states[i].remove(.codedThisPass)
            }
        }
        
        // Reconstruct signed coefficients
        var coefficients = [Int32](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            if signs[i] {
                coefficients[i] = -Int32(magnitudes[i])
            } else {
                coefficients[i] = Int32(magnitudes[i])
            }
        }
        
        return coefficients
    }
    
    // MARK: - Significance Propagation Pass (Decode)
    
    /// Decodes the significance propagation pass.
    private func decodeSignificancePropagationPass(
        magnitudes: inout [UInt32],
        signs: inout [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Skip if already significant or coded this pass
                if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                    continue
                }
                
                // Check if any neighbors are significant
                let neighbors = neighborCalculator.calculate(
                    x: x, y: y,
                    states: states,
                    signs: signs
                )
                
                // Only process if at least one neighbor is significant
                guard neighbors.hasAny else { continue }
                
                // Get significance context
                let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                
                // Decode significance bit
                let isSignificant = decoder.decode(context: &contexts[sigContext])
                
                if isSignificant {
                    // Decode sign
                    let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                    let codedSign = decoder.decode(context: &contexts[signContext])
                    let signBit = codedSign != xorBit
                    
                    // Update coefficient
                    magnitudes[idx] = magnitudes[idx] | bitMask
                    signs[idx] = signBit
                    
                    // Update state
                    states[idx].insert(.significant)
                    if signBit {
                        states[idx].insert(.signBit)
                    }
                }
                
                states[idx].insert(.codedThisPass)
            }
        }
    }
    
    // MARK: - Magnitude Refinement Pass (Decode)
    
    /// Decodes the magnitude refinement pass.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes being reconstructed.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - decoder: The MQ decoder.
    ///   - contexts: The context states.
    ///   - useBypass: Whether bypass (raw) mode was used during encoding.
    private func decodeMagnitudeRefinementPass(
        magnitudes: inout [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray,
        useBypass: Bool = false
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Only process coefficients that are significant and not coded this pass
                guard states[idx].contains(.significant) else { continue }
                guard !states[idx].contains(.codedThisPass) else { continue }
                
                // Decode the magnitude bit
                let bitValue: Bool
                if useBypass {
                    // Use bypass (raw) mode - no context
                    bitValue = decoder.decodeBypass()
                } else {
                    // Use context-adaptive arithmetic decoding
                    // Check if this is the first refinement
                    let isFirstRefinement = !firstRefineFlags[idx]
                    
                    // Get neighbors to determine context
                    let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
                    let hasSignificantNeighbors = neighbors.hasAny
                    
                    // Get magnitude refinement context
                    let magContext = contextModeler.magnitudeRefinementContext(
                        firstRefinement: isFirstRefinement,
                        neighborsWereSignificant: hasSignificantNeighbors
                    )
                    
                    bitValue = decoder.decode(context: &contexts[magContext])
                }
                
                // Update magnitude
                if bitValue {
                    magnitudes[idx] = magnitudes[idx] | bitMask
                }
                
                // Update refinement flag
                if !firstRefineFlags[idx] {
                    firstRefineFlags[idx] = true
                }
                
                states[idx].insert(.codedThisPass)
            }
        }
    }
    
    // MARK: - Cleanup Pass (Decode)
    
    /// Decodes the cleanup pass.
    private func decodeCleanupPass(
        magnitudes: inout [UInt32],
        signs: inout [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray
    ) {
        // Process in stripes of 4 rows
        let stripeHeight = 4
        
        for stripeY in stride(from: 0, to: height, by: stripeHeight) {
            let stripeEnd = min(stripeY + stripeHeight, height)
            
            for x in 0..<width {
                // Check if this column is eligible for run-length decoding
                let eligible = canUseRunLengthDecoding(
                    x: x,
                    stripeStart: stripeY,
                    stripeEnd: stripeEnd,
                    states: states
                )
                
                if eligible {
                    // Decode run-length flag: true if at least one becomes significant
                    let hasSignificant = decoder.decode(context: &contexts[.runLength])
                    
                    if !hasSignificant {
                        // All coefficients remain zero, mark as coded and skip
                        for y in stripeY..<stripeEnd {
                            let idx = y * width + x
                            states[idx].insert(.codedThisPass)
                        }
                        continue
                    }
                } else {
                }
                
                // Process individually (either not eligible for RLC, or RLC flag indicated significance)
                // Per ISO/IEC 15444-1, states are updated immediately as each coefficient
                // is processed, so subsequent coefficients see updated neighbor states.
                
                for y in stripeY..<stripeEnd {
                    let idx = y * width + x
                    
                    // Skip if already coded or significant
                    if states[idx].contains(.codedThisPass) || states[idx].contains(.significant) {
                        continue
                    }
                    
                    // Get neighbors (using current state which includes any updates
                    // from previously processed coefficients in this stripe column)
                    let neighbors = neighborCalculator.calculate(
                        x: x, y: y,
                        states: states,
                        signs: signs
                    )
                    
                    // Get significance context
                    let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                    
                    // Decode significance
                    let isSignificant = decoder.decode(context: &contexts[sigContext])
                    
                    if isSignificant {
                        // Decode sign
                        let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                        let codedSign = decoder.decode(context: &contexts[signContext])
                        let signBit = codedSign != xorBit
                        
                        // Update coefficient magnitude
                        magnitudes[idx] = magnitudes[idx] | bitMask
                        signs[idx] = signBit
                        
                        // Update state immediately
                        states[idx].insert(.significant)
                        if signBit {
                            states[idx].insert(.signBit)
                        }
                    }
                    
                    states[idx].insert(.codedThisPass)
                }
            }
        }
    }
    
     /// Checks if run-length decoding can be used for a column in a stripe.
    ///
    /// This is the decoder equivalent of `isEligibleForRunLengthCoding` in the encoder.
    /// It checks eligibility based on coefficient and neighbor states.
    ///
    /// NOTE: This function must be kept in sync with BitPlaneCoder.isEligibleForRunLengthCoding
    private func canUseRunLengthDecoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState]
    ) -> Bool {
        // This must match isEligibleForRunLengthCoding in the encoder
        for y in stripeStart..<stripeEnd {
            let idx = y * width + x
            
            // Can't use RLC if any coefficient is already significant or coded
            if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                return false
            }
            
            // Can't use RLC if any neighbor is significant
            let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
            if neighbors.hasAny {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Code-Block Encoder

/// Encodes a complete code-block using EBCOT.
///
/// This is a high-level wrapper around the bit-plane coder that handles
/// the complete encoding of a JPEG 2000 code-block.
public struct CodeBlockEncoder: Sendable {
    /// The maximum code-block width.
    public static let maxWidth = 64
    
    /// The maximum code-block height.
    public static let maxHeight = 64
    
    /// The default code-block width.
    public static let defaultWidth = 64
    
    /// The default code-block height.
    public static let defaultHeight = 64
    
    /// Creates a new code-block encoder.
    public init() {}
    
    /// Encodes a code-block with default options.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in the code-block.
    ///   - width: The width of the code-block.
    ///   - height: The height of the code-block.
    ///   - subband: The subband type.
    ///   - bitDepth: The bit depth of the coefficients.
    /// - Returns: The encoded code-block data with metadata.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        coefficients: [Int32],
        width: Int,
        height: Int,
        subband: J2KSubband,
        bitDepth: Int
    ) throws -> J2KCodeBlock {
        return try encode(
            coefficients: coefficients,
            width: width,
            height: height,
            subband: subband,
            bitDepth: bitDepth,
            options: .default
        )
    }
    
    /// Encodes a code-block with custom coding options.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in the code-block.
    ///   - width: The width of the code-block.
    ///   - height: The height of the code-block.
    ///   - subband: The subband type.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - options: Coding options (bypass mode, termination, etc.).
    /// - Returns: The encoded code-block data with metadata.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        coefficients: [Int32],
        width: Int,
        height: Int,
        subband: J2KSubband,
        bitDepth: Int,
        options: CodingOptions
    ) throws -> J2KCodeBlock {
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (data, passCount, zeroBitPlanes, passSegmentLengths) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )
        
        return J2KCodeBlock(
            index: 0,
            x: 0,
            y: 0,
            width: width,
            height: height,
            subband: subband,
            data: data,
            passeCount: passCount,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: passSegmentLengths
        )
    }
}

// MARK: - Code-Block Decoder

/// Decodes a complete code-block using EBCOT.
///
/// This is a high-level wrapper around the bit-plane decoder that handles
/// the complete decoding of a JPEG 2000 code-block.
public struct CodeBlockDecoder: Sendable {
    /// Creates a new code-block decoder.
    public init() {}
    
    /// Decodes a code-block with default options.
    ///
    /// - Parameters:
    ///   - codeBlock: The encoded code-block.
    ///   - bitDepth: The bit depth of the coefficients.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        codeBlock: J2KCodeBlock,
        bitDepth: Int
    ) throws -> [Int32] {
        return try decode(codeBlock: codeBlock, bitDepth: bitDepth, options: .default)
    }
    
    /// Decodes a code-block with custom coding options.
    ///
    /// - Parameters:
    ///   - codeBlock: The encoded code-block.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - options: Coding options that were used during encoding.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        codeBlock: J2KCodeBlock,
        bitDepth: Int,
        options: CodingOptions
    ) throws -> [Int32] {
        let decoder = BitPlaneDecoder(
            width: codeBlock.width,
            height: codeBlock.height,
            subband: codeBlock.subband,
            options: options
        )
        
        return try decoder.decode(
            data: codeBlock.data,
            passCount: codeBlock.passeCount,
            bitDepth: bitDepth,
            zeroBitPlanes: codeBlock.zeroBitPlanes,
            passSegmentLengths: codeBlock.passSegmentLengths
        )
    }
}
