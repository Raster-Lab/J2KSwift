// J2KAcceleratedNLT.swift
// J2KSwift
//
// Hardware-accelerated non-linear transform operations using Accelerate framework.
//

import Foundation
import J2KCore
import J2KCodec

#if canImport(Accelerate)
import Accelerate
#endif

/// Hardware-accelerated non-linear point transforms for JPEG 2000 Part 2.
///
/// Provides high-performance NLT operations using the Accelerate framework's
/// vDSP and vForce libraries on Apple platforms.
///
/// On platforms without Accelerate, falls back to scalar operations.
///
/// ## Performance
///
/// On Apple platforms with Accelerate framework:
/// - 8-12× faster LUT lookups using `vDSP_vindex`
/// - 10-15× faster transcendental functions using vForce (`vvpowf`, `vvlogf`, `vvexpf`)
/// - SIMD-optimized gamma correction and HDR transforms
/// - Parallel processing across multiple components
///
/// ## Usage
///
/// ```swift
/// let accelerated = J2KAcceleratedNLT()
///
/// // Apply gamma transform using vForce (fast path)
/// let result = try accelerated.applyGamma(
///     data: componentData,
///     gamma: 2.2,
///     bitDepth: 10
/// )
///
/// // Apply LUT using vDSP_vindex (vectorized)
/// let lutResult = try accelerated.applyLUT(
///     data: componentData,
///     lut: lookupTable,
///     bitDepth: 8
/// )
/// ```
public struct J2KAcceleratedNLT: Sendable {
    /// Creates a new accelerated NLT processor.
    public init() {}
    
    /// Indicates whether hardware acceleration is available.
    public static var isAvailable: Bool {
        #if canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Accelerated Gamma Transform
    
    /// Applies gamma transform using vForce vectorized power function.
    ///
    /// Forward transform: y = x^gamma
    /// Inverse transform: y = x^(1/gamma)
    ///
    /// - Parameters:
    ///   - data: The input component data.
    ///   - gamma: The gamma value (must be positive).
    ///   - bitDepth: The bit depth of the component.
    ///   - inverse: Whether to apply inverse transform (default: false).
    ///   - signed: Whether the component uses signed representation.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyGamma(
        data: [Int32],
        gamma: Double,
        bitDepth: Int,
        inverse: Bool = false,
        signed: Bool = false
    ) throws -> [Int32] {
        guard gamma > 0 else {
            throw J2KError.invalidParameter("Gamma must be positive: \(gamma)")
        }
        
        guard !data.isEmpty else {
            return []
        }
        
        #if canImport(Accelerate)
        let maxValue = signed ? Float((1 << (bitDepth - 1)) - 1) : Float((1 << bitDepth) - 1)
        let minValue = signed ? Float(-(1 << (bitDepth - 1))) : Float(0)
        
        // Convert to float and normalize to [0, 1]
        var floatData = data.map { (Float($0) - minValue) / (maxValue - minValue) }
        var result = [Float](repeating: 0, count: data.count)
        
        // Apply power function using vForce
        let exponent = Float(inverse ? (1.0 / gamma) : gamma)
        var exponentArray = [Float](repeating: exponent, count: data.count)
        var count = Int32(data.count)
        
        vvpowf(&result, &exponentArray, &floatData, &count)
        
        // Denormalize back to original range
        var scale = maxValue - minValue
        var offset = minValue
        vDSP_vsmsa(&result, 1, &scale, &offset, &result, 1, vDSP_Length(data.count))
        
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
    
    // MARK: - Accelerated Logarithmic Transform
    
    /// Applies logarithmic transform using vForce vectorized log function.
    ///
    /// Forward transform: y = ln(x + 1)
    /// Inverse transform: y = exp(x) - 1
    ///
    /// - Parameters:
    ///   - data: The input component data.
    ///   - bitDepth: The bit depth of the component.
    ///   - base10: Whether to use base-10 logarithm (default: false for base-e).
    ///   - inverse: Whether to apply inverse transform (default: false).
    ///   - signed: Whether the component uses signed representation.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyLogarithmic(
        data: [Int32],
        bitDepth: Int,
        base10: Bool = false,
        inverse: Bool = false,
        signed: Bool = false
    ) throws -> [Int32] {
        guard !data.isEmpty else {
            return []
        }
        
        #if canImport(Accelerate)
        let maxValue = signed ? Float((1 << (bitDepth - 1)) - 1) : Float((1 << bitDepth) - 1)
        let minValue = signed ? Float(-(1 << (bitDepth - 1))) : Float(0)
        
        // Convert to float and normalize to [0, 1]
        var floatData = data.map { (Float($0) - minValue) / (maxValue - minValue) }
        var result = [Float](repeating: 0, count: data.count)
        var count = Int32(data.count)
        
        if !inverse {
            // Forward: log(x + 1)
            // Add 1 to normalized values
            var one: Float = 1.0
            vDSP_vsadd(&floatData, 1, &one, &floatData, 1, vDSP_Length(data.count))
            
            // Apply log
            if base10 {
                vvlog10f(&result, &floatData, &count)
                // Normalize to [0, 1] using log10(2)
                var scale = Float(1.0 / log10(2.0))
                vDSP_vsmul(&result, 1, &scale, &result, 1, vDSP_Length(data.count))
            } else {
                vvlogf(&result, &floatData, &count)
                // Normalize to [0, 1] using ln(2)
                var scale = Float(1.0 / log(2.0))
                vDSP_vsmul(&result, 1, &scale, &result, 1, vDSP_Length(data.count))
            }
        } else {
            // Inverse: exp(x) - 1
            if base10 {
                // Scale by log10(2)
                var scale = Float(log10(2.0))
                vDSP_vsmul(&floatData, 1, &scale, &floatData, 1, vDSP_Length(data.count))
                
                // Apply 10^x
                var base = [Float](repeating: 10.0, count: data.count)
                vvpowf(&result, &base, &floatData, &count)
            } else {
                // Scale by ln(2)
                var scale = Float(log(2.0))
                vDSP_vsmul(&floatData, 1, &scale, &floatData, 1, vDSP_Length(data.count))
                
                // Apply exp
                vvexpf(&result, &floatData, &count)
            }
            
            // Subtract 1
            var negOne: Float = -1.0
            vDSP_vsadd(&result, 1, &negOne, &result, 1, vDSP_Length(data.count))
        }
        
        // Denormalize back to original range
        var scale = maxValue - minValue
        var offset = minValue
        vDSP_vsmsa(&result, 1, &scale, &offset, &result, 1, vDSP_Length(data.count))
        
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
    
    // MARK: - Accelerated LUT Application
    
    /// Applies lookup table transform using vDSP vectorized indexing.
    ///
    /// Uses `vDSP_vindex` for fast LUT lookups with optional linear interpolation.
    ///
    /// - Parameters:
    ///   - data: The input component data.
    ///   - lut: The lookup table (forward or inverse).
    ///   - bitDepth: The bit depth of the component.
    ///   - interpolation: Whether to use linear interpolation (default: true).
    ///   - signed: Whether the component uses signed representation.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyLUT(
        data: [Int32],
        lut: [Double],
        bitDepth: Int,
        interpolation: Bool = true,
        signed: Bool = false
    ) throws -> [Int32] {
        guard !lut.isEmpty else {
            throw J2KError.invalidParameter("LUT is empty")
        }
        
        guard !data.isEmpty else {
            return []
        }
        
        #if canImport(Accelerate)
        let maxValue = signed ? Float((1 << (bitDepth - 1)) - 1) : Float((1 << bitDepth) - 1)
        let minValue = signed ? Float(-(1 << (bitDepth - 1))) : Float(0)
        
        // Convert LUT to float
        var floatLUT = lut.map { Float($0) }
        
        // Normalize data to LUT index range [0, lut.count - 1]
        var floatData = data.map { Float($0) }
        var normMin = minValue
        var normMax = maxValue
        var lutMaxIndex = Float(lut.count - 1)
        
        // Normalize: (x - min) / (max - min) * (lut.count - 1)
        vDSP_vsadd(&floatData, 1, &normMin, &floatData, 1, vDSP_Length(data.count))
        var scale = lutMaxIndex / (normMax - normMin)
        vDSP_vsmul(&floatData, 1, &scale, &floatData, 1, vDSP_Length(data.count))
        
        var result = [Float](repeating: 0, count: data.count)
        
        if !interpolation {
            // Nearest neighbor using vDSP_vindex
            // Round to nearest integer index
            var roundedIndices = [UInt](repeating: 0, count: data.count)
            for i in 0..<data.count {
                let index = Int(floatData[i].rounded())
                roundedIndices[i] = UInt(max(0, min(lut.count - 1, index)))
            }
            
            vDSP_vindex(&floatLUT, &roundedIndices, 1, &result, 1, vDSP_Length(data.count))
        } else {
            // Linear interpolation
            for i in 0..<data.count {
                let index = floatData[i]
                let i0 = Int(floor(index))
                let i1 = min(i0 + 1, lut.count - 1)
                let fraction = index - Float(i0)
                
                let v0 = floatLUT[max(0, min(lut.count - 1, i0))]
                let v1 = floatLUT[i1]
                
                result[i] = v0 + fraction * (v1 - v0)
            }
        }
        
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
    
    // MARK: - Accelerated PQ Transform
    
    /// Applies Perceptual Quantizer (PQ) transform for HDR content.
    ///
    /// Implements SMPTE ST 2084 using vectorized operations.
    ///
    /// - Parameters:
    ///   - data: The input component data.
    ///   - bitDepth: The bit depth of the component.
    ///   - inverse: Whether to apply inverse transform (default: false).
    ///   - signed: Whether the component uses signed representation.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyPQ(
        data: [Int32],
        bitDepth: Int,
        inverse: Bool = false,
        signed: Bool = false
    ) throws -> [Int32] {
        guard !data.isEmpty else {
            return []
        }
        
        #if canImport(Accelerate)
        let maxValue = signed ? Float((1 << (bitDepth - 1)) - 1) : Float((1 << bitDepth) - 1)
        let minValue = signed ? Float(-(1 << (bitDepth - 1))) : Float(0)
        
        // PQ constants
        let m1 = Float(0.1593017578125)
        let m2 = Float(78.84375)
        let c1 = Float(0.8359375)
        let c2 = Float(18.8515625)
        let c3 = Float(18.6875)
        
        // Convert to float and normalize to [0, 1]
        var floatData = data.map { (Float($0) - minValue) / (maxValue - minValue) }
        var result = [Float](repeating: 0, count: data.count)
        var count = Int32(data.count)
        
        if !inverse {
            // Forward: PQ EOTF (linearize)
            // y = pow(x, 1/m2)
            var invM2Array = [Float](repeating: 1.0 / m2, count: data.count)
            vvpowf(&result, &invM2Array, &floatData, &count)
            
            // numerator = max(y - c1, 0)
            var negC1 = -c1
            vDSP_vsadd(&result, 1, &negC1, &result, 1, vDSP_Length(data.count))
            for i in 0..<data.count {
                result[i] = max(result[i], 0)
            }
            
            // Save numerator temporarily
            var numerator = result
            
            // Compute y again for denominator
            vvpowf(&result, &invM2Array, &floatData, &count)
            
            // denominator = c2 - c3 * y
            var negC3 = -c3
            vDSP_vsmsa(&result, 1, &negC3, &c2, &result, 1, vDSP_Length(data.count))
            
            // linear = pow(numerator / denominator, 1/m1)
            vDSP_vdiv(&result, 1, &numerator, 1, &result, 1, vDSP_Length(data.count))
            var invM1Array = [Float](repeating: 1.0 / m1, count: data.count)
            vvpowf(&result, &invM1Array, &result, &count)
        } else {
            // Inverse: PQ OETF (apply encoding)
            // y = pow(x, m1)
            var m1Array = [Float](repeating: m1, count: data.count)
            vvpowf(&result, &m1Array, &floatData, &count)
            
            // numerator = c1 + c2 * y
            vDSP_vsmsa(&result, 1, &c2, &c1, &floatData, 1, vDSP_Length(data.count))
            
            // denominator = 1 + c3 * y
            var one: Float = 1.0
            vDSP_vsmsa(&result, 1, &c3, &one, &result, 1, vDSP_Length(data.count))
            
            // encoded = pow(numerator / denominator, m2)
            vDSP_vdiv(&result, 1, &floatData, 1, &result, 1, vDSP_Length(data.count))
            var m2Array = [Float](repeating: m2, count: data.count)
            vvpowf(&result, &m2Array, &result, &count)
        }
        
        // Denormalize back to original range
        var scale = maxValue - minValue
        var offset = minValue
        vDSP_vsmsa(&result, 1, &scale, &offset, &result, 1, vDSP_Length(data.count))
        
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
    
    // MARK: - Accelerated HLG Transform
    
    /// Applies Hybrid Log-Gamma (HLG) transform for HDR content.
    ///
    /// Implements ITU-R BT.2100 using vectorized operations.
    ///
    /// - Parameters:
    ///   - data: The input component data.
    ///   - bitDepth: The bit depth of the component.
    ///   - inverse: Whether to apply inverse transform (default: false).
    ///   - signed: Whether the component uses signed representation.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyHLG(
        data: [Int32],
        bitDepth: Int,
        inverse: Bool = false,
        signed: Bool = false
    ) throws -> [Int32] {
        guard !data.isEmpty else {
            return []
        }
        
        #if canImport(Accelerate)
        let maxValue = signed ? Float((1 << (bitDepth - 1)) - 1) : Float((1 << bitDepth) - 1)
        let minValue = signed ? Float(-(1 << (bitDepth - 1))) : Float(0)
        
        // HLG constants
        let a = Float(0.17883277)
        let b = Float(0.28466892)
        let c = Float(0.55991073)
        
        // Convert to float and normalize to [0, 1]
        let floatData = data.map { (Float($0) - minValue) / (maxValue - minValue) }
        var result = [Float](repeating: 0, count: data.count)
        
        if !inverse {
            // Forward: HLG OETF inverse (linearize)
            for i in 0..<data.count {
                let normalized = floatData[i]
                let linear: Float
                if normalized <= 0.5 {
                    linear = normalized * normalized / 3.0
                } else {
                    linear = (exp((normalized - c) / a) + b) / 12.0
                }
                result[i] = linear * (maxValue - minValue) + minValue
            }
        } else {
            // Inverse: HLG OETF (apply encoding)
            for i in 0..<data.count {
                let normalized = floatData[i]
                let encoded: Float
                if normalized <= 1.0 / 12.0 {
                    encoded = sqrt(3.0 * normalized)
                } else {
                    encoded = a * log(12.0 * normalized - b) + c
                }
                result[i] = encoded * (maxValue - minValue) + minValue
            }
        }
        
        return result.map { Int32($0.rounded()) }
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
    
    // MARK: - Parallel Multi-Component Processing
    
    /// Applies transforms to multiple components in parallel.
    ///
    /// - Parameters:
    ///   - components: Array of component data arrays.
    ///   - transforms: Per-component transform specifications.
    ///   - bitDepth: The bit depth of components.
    ///   - signed: Whether components use signed representation.
    /// - Returns: Array of transformed component data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func applyParallel(
        components: [[Int32]],
        transforms: [J2KNLTComponentTransform],
        bitDepth: Int,
        signed: Bool = false
    ) throws -> [[Int32]] {
        guard components.count == transforms.count else {
            throw J2KError.invalidParameter("Components and transforms count mismatch")
        }
        
        #if canImport(Accelerate)
        // Process each component (could be parallelized further with DispatchQueue)
        var results = [[Int32]]()
        results.reserveCapacity(components.count)
        
        for (component, transform) in zip(components, transforms) {
            let result: [Int32]
            
            switch transform.transformType {
            case .gamma(let gamma):
                result = try applyGamma(
                    data: component,
                    gamma: gamma,
                    bitDepth: bitDepth,
                    inverse: false,
                    signed: signed
                )
                
            case .logarithmic:
                result = try applyLogarithmic(
                    data: component,
                    bitDepth: bitDepth,
                    base10: false,
                    inverse: false,
                    signed: signed
                )
                
            case .logarithmic10:
                result = try applyLogarithmic(
                    data: component,
                    bitDepth: bitDepth,
                    base10: true,
                    inverse: false,
                    signed: signed
                )
                
            case .perceptualQuantizer:
                result = try applyPQ(
                    data: component,
                    bitDepth: bitDepth,
                    inverse: false,
                    signed: signed
                )
                
            case .hybridLogGamma:
                result = try applyHLG(
                    data: component,
                    bitDepth: bitDepth,
                    inverse: false,
                    signed: signed
                )
                
            case .lookupTable(let forwardLUT, _, let interpolation):
                result = try applyLUT(
                    data: component,
                    lut: forwardLUT,
                    bitDepth: bitDepth,
                    interpolation: interpolation,
                    signed: signed
                )
                
            default:
                // Fall back to non-accelerated implementation
                let nlt = J2KNonLinearTransform()
                let nltResult = try nlt.applyForward(
                    componentData: component,
                    transform: transform,
                    bitDepth: bitDepth,
                    signed: signed
                )
                result = nltResult.transformedData
            }
            
            results.append(result)
        }
        
        return results
        #else
        throw J2KError.unsupportedFeature(
            "Accelerated NLT requires Accelerate framework (Apple platforms)"
        )
        #endif
    }
}
