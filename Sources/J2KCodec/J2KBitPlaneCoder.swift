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
    
    /// Creates a new bit-plane coder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    public init(width: Int, height: Int, subband: J2KSubband) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
    }
    
    /// Encodes wavelet coefficients using EBCOT bit-plane coding.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to encode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - maxPasses: Maximum number of coding passes to generate (optional).
    /// - Returns: A tuple containing the encoded data and the number of coding passes.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        coefficients: [Int32],
        bitDepth: Int,
        maxPasses: Int? = nil
    ) throws -> (data: Data, passCount: Int, zeroBitPlanes: Int) {
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
        
        var passCount = 0
        let maxPassLimit = maxPasses ?? (3 * activeBitPlanes)
        
        // Process each bit-plane from MSB to LSB
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << bitPlane
            
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
            }
            
            // Pass 2: Magnitude Refinement Pass
            if passCount < maxPassLimit {
                encodeMagnitudeRefinementPass(
                    magnitudes: magnitudes,
                    states: &states,
                    firstRefineFlags: &firstRefineFlags,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates
                )
                passCount += 1
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
            }
            
            // Clear coded-this-pass flags for next bit-plane
            for i in 0..<states.count {
                states[i].remove(.codedThisPass)
            }
        }
        
        let encodedData = encoder.finish()
        return (encodedData, passCount, zeroBitPlanes)
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
    /// by coding additional bits from subsequent bit-planes.
    private func encodeMagnitudeRefinementPass(
        magnitudes: [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Only process coefficients that are significant and not coded this pass
                guard states[idx].contains(.significant) else { continue }
                guard !states[idx].contains(.codedThisPass) else { continue }
                
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
                
                // Get the bit value
                let bitValue = (magnitudes[idx] & bitMask) != 0
                
                // Encode the magnitude bit
                encoder.encode(symbol: bitValue, context: &contexts[magContext])
                
                // Update refinement flag
                if isFirstRefinement {
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
                if isEligibleForRunLengthCoding(
                    x: x,
                    stripeStart: stripeY,
                    stripeEnd: stripeEnd,
                    states: states
                ) {
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
                }
                
                // Process individually (either not eligible for RLC, or RLC flag indicated significance)
                for y in stripeY..<stripeEnd {
                    let idx = y * width + x
                    
                    // Skip if already coded
                    if states[idx].contains(.codedThisPass) || states[idx].contains(.significant) {
                        continue
                    }
                    
                    // Get neighbors
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
    
    /// Creates a new bit-plane decoder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    public init(width: Int, height: Int, subband: J2KSubband) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
    }
    
    /// Decodes wavelet coefficients from EBCOT encoded data.
    ///
    /// - Parameters:
    ///   - data: The encoded data.
    ///   - passCount: The number of coding passes to decode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - zeroBitPlanes: The number of zero bit-planes.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        data: Data,
        passCount: Int,
        bitDepth: Int,
        zeroBitPlanes: Int
    ) throws -> [Int32] {
        // Initialize coefficient arrays
        var magnitudes = [UInt32](repeating: 0, count: width * height)
        var signs = [Bool](repeating: false, count: width * height)
        var states = [CoefficientState](repeating: [], count: width * height)
        var firstRefineFlags = [Bool](repeating: false, count: width * height)
        
        // Initialize MQ decoder and contexts
        var decoder = MQDecoder(data: data)
        var contextStates = ContextStateArray()
        
        let activeBitPlanes = bitDepth - zeroBitPlanes
        var passesDecoded = 0
        
        // Process each bit-plane from MSB to LSB
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << bitPlane
            
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
            }
            
            // Pass 2: Magnitude Refinement Pass
            if passesDecoded < passCount {
                decodeMagnitudeRefinementPass(
                    magnitudes: &magnitudes,
                    states: &states,
                    firstRefineFlags: &firstRefineFlags,
                    bitMask: bitMask,
                    decoder: &decoder,
                    contexts: &contextStates
                )
                passesDecoded += 1
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
    private func decodeMagnitudeRefinementPass(
        magnitudes: inout [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray
    ) {
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                // Only process coefficients that are significant and not coded this pass
                guard states[idx].contains(.significant) else { continue }
                guard !states[idx].contains(.codedThisPass) else { continue }
                
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
                
                // Decode the magnitude bit
                let bitValue = decoder.decode(context: &contexts[magContext])
                
                // Update magnitude
                if bitValue {
                    magnitudes[idx] = magnitudes[idx] | bitMask
                }
                
                // Update refinement flag
                if isFirstRefinement {
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
                if canUseRunLengthDecoding(
                    x: x,
                    stripeStart: stripeY,
                    stripeEnd: stripeEnd,
                    states: states
                ) {
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
                }
                
                // Process individually (either not eligible for RLC, or RLC flag indicated significance)
                for y in stripeY..<stripeEnd {
                    let idx = y * width + x
                    
                    // Skip if already coded
                    if states[idx].contains(.codedThisPass) || states[idx].contains(.significant) {
                        continue
                    }
                    
                    // Get neighbors
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
    }
    
    /// Checks if run-length decoding can be used for a column in a stripe.
    private func canUseRunLengthDecoding(
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
    
    /// Encodes a code-block.
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
        let coder = BitPlaneCoder(width: width, height: height, subband: subband)
        let (data, passCount, zeroBitPlanes) = try coder.encode(
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
            zeroBitPlanes: zeroBitPlanes
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
    
    /// Decodes a code-block.
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
        let decoder = BitPlaneDecoder(
            width: codeBlock.width,
            height: codeBlock.height,
            subband: codeBlock.subband
        )
        
        return try decoder.decode(
            data: codeBlock.data,
            passCount: codeBlock.passeCount,
            bitDepth: bitDepth,
            zeroBitPlanes: codeBlock.zeroBitPlanes
        )
    }
}
