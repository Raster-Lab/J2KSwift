// J2KNLTMarker.swift
// J2KSwift
//
// NLT marker segment support for ISO/IEC 15444-2 Part 2.
//

import Foundation
import J2KCore

/// # NLT Marker Segment
///
/// The NLT (Non-Linear Transform) marker segment signals non-linear point
/// transforms in the JPEG 2000 Part 2 codestream.
///
/// ## Marker Format
///
/// ```
/// NLT marker: 0xFF90 (Part 2 extension)
/// Lnlt: Marker segment length (2 bytes)
/// Cnlt: Number of components with transforms (2 bytes)
/// For each component:
///   ICnlt: Component index (2 bytes)
///   Tnlt: Transform type (1 byte)
///   Pnlt: Parameter data (variable length)
/// ```

// MARK: - NLT Marker Segment

/// NLT marker segment for JPEG 2000 Part 2 codestream.
public struct J2KNLTMarkerSegment: Sendable, Equatable {
    /// The NLT marker code (0xFF90).
    ///
    /// Part 2 marker for non-linear transforms.
    public static let markerCode: UInt16 = 0xFF90
    
    /// Per-component transform specifications.
    public let transforms: [J2KNLTComponentTransform]
    
    /// Creates an NLT marker segment.
    ///
    /// - Parameter transforms: Per-component transforms.
    public init(transforms: [J2KNLTComponentTransform]) {
        self.transforms = transforms
    }
    
    // MARK: - Encoding
    
    /// Encodes the NLT marker segment to binary data.
    ///
    /// - Returns: The encoded marker segment data.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    public func encode() throws -> Data {
        var data = Data()
        
        // Marker code (2 bytes)
        data.append(UInt8(J2KNLTMarkerSegment.markerCode >> 8))
        data.append(UInt8(J2KNLTMarkerSegment.markerCode & 0xFF))
        
        // Calculate segment length and parameter data
        var parameterData = Data()
        
        // Number of components (2 bytes)
        let componentCount = UInt16(transforms.count)
        parameterData.append(UInt8(componentCount >> 8))
        parameterData.append(UInt8(componentCount & 0xFF))
        
        // Encode each component transform
        for transform in transforms {
            // Component index (2 bytes)
            let index = UInt16(transform.componentIndex)
            parameterData.append(UInt8(index >> 8))
            parameterData.append(UInt8(index & 0xFF))
            
            // Transform type and parameters
            let typeData = try encodeTransformType(transform.transformType)
            parameterData.append(typeData)
        }
        
        // Segment length (2 bytes): length field + parameter data
        let length = UInt16(2 + parameterData.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        
        // Parameter data
        data.append(parameterData)
        
        return data
    }
    
    /// Encodes a transform type to binary data.
    private func encodeTransformType(_ type: J2KNLTTransformType) throws -> Data {
        var data = Data()
        
        switch type {
        case .identity:
            data.append(0x00)  // Transform type: identity
            
        case .gamma(let gamma):
            data.append(0x01)  // Transform type: gamma
            // Encode gamma as IEEE 754 double (8 bytes)
            var gammaValue = gamma
            let gammaBytes = withUnsafeBytes(of: &gammaValue) { Data($0) }
            data.append(gammaBytes)
            
        case .logarithmic:
            data.append(0x02)  // Transform type: logarithmic (base-e)
            
        case .logarithmic10:
            data.append(0x03)  // Transform type: logarithmic (base-10)
            
        case .exponential:
            data.append(0x04)  // Transform type: exponential
            
        case .perceptualQuantizer:
            data.append(0x05)  // Transform type: PQ (SMPTE ST 2084)
            
        case .hybridLogGamma:
            data.append(0x06)  // Transform type: HLG (ITU-R BT.2100)
            
        case .lookupTable(let forwardLUT, let inverseLUT, let interpolation):
            data.append(0x10)  // Transform type: LUT
            
            // Interpolation flag (1 byte)
            data.append(interpolation ? 0x01 : 0x00)
            
            // Forward LUT size (2 bytes)
            let forwardSize = UInt16(forwardLUT.count)
            data.append(UInt8(forwardSize >> 8))
            data.append(UInt8(forwardSize & 0xFF))
            
            // Forward LUT data (doubles)
            for value in forwardLUT {
                var doubleValue = value
                let bytes = withUnsafeBytes(of: &doubleValue) { Data($0) }
                data.append(bytes)
            }
            
            // Inverse LUT size (2 bytes)
            let inverseSize = UInt16(inverseLUT.count)
            data.append(UInt8(inverseSize >> 8))
            data.append(UInt8(inverseSize & 0xFF))
            
            // Inverse LUT data (doubles)
            for value in inverseLUT {
                var doubleValue = value
                let bytes = withUnsafeBytes(of: &doubleValue) { Data($0) }
                data.append(bytes)
            }
            
        case .piecewiseLinear(let breakpoints, let values):
            data.append(0x11)  // Transform type: piecewise linear
            
            guard breakpoints.count == values.count else {
                throw J2KError.encodingError("Breakpoints and values count mismatch")
            }
            
            // Number of segments (2 bytes)
            let segmentCount = UInt16(breakpoints.count)
            data.append(UInt8(segmentCount >> 8))
            data.append(UInt8(segmentCount & 0xFF))
            
            // Breakpoint and value pairs
            for i in 0..<breakpoints.count {
                var breakpoint = breakpoints[i]
                var value = values[i]
                
                let bpBytes = withUnsafeBytes(of: &breakpoint) { Data($0) }
                let valBytes = withUnsafeBytes(of: &value) { Data($0) }
                
                data.append(bpBytes)
                data.append(valBytes)
            }
            
        case .custom(let parameters, let function):
            data.append(0xFF)  // Transform type: custom
            
            // Function name length (1 byte)
            let functionBytes = function.utf8
            guard functionBytes.count < 256 else {
                throw J2KError.encodingError("Function name too long")
            }
            data.append(UInt8(functionBytes.count))
            
            // Function name
            data.append(contentsOf: functionBytes)
            
            // Number of parameters (2 bytes)
            let paramCount = UInt16(parameters.count)
            data.append(UInt8(paramCount >> 8))
            data.append(UInt8(paramCount & 0xFF))
            
            // Parameter values
            for param in parameters {
                var paramValue = param
                let bytes = withUnsafeBytes(of: &paramValue) { Data($0) }
                data.append(bytes)
            }
        }
        
        return data
    }
    
    // MARK: - Decoding
    
    /// Decodes an NLT marker segment from binary data.
    ///
    /// - Parameter data: The marker segment data (without marker code).
    /// - Returns: The decoded NLT marker segment.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    public static func decode(from data: Data) throws -> J2KNLTMarkerSegment {
        guard data.count >= 4 else {
            throw J2KError.decodingError("NLT marker segment too short")
        }
        
        var offset = 0
        
        // Length (2 bytes) - already consumed by parser
        let length = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        
        guard data.count >= length else {
            throw J2KError.decodingError("NLT marker segment truncated")
        }
        
        // Number of components (2 bytes)
        guard offset + 2 <= data.count else {
            throw J2KError.decodingError("Cannot read component count")
        }
        let componentCount = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        
        var transforms = [J2KNLTComponentTransform]()
        transforms.reserveCapacity(componentCount)
        
        // Decode each component transform
        for _ in 0..<componentCount {
            guard offset + 2 <= data.count else {
                throw J2KError.decodingError("Cannot read component index")
            }
            
            // Component index (2 bytes)
            let componentIndex = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
            
            // Transform type and parameters
            let (transformType, bytesRead) = try decodeTransformType(from: data, offset: offset)
            offset += bytesRead
            
            let transform = J2KNLTComponentTransform(
                componentIndex: componentIndex,
                transformType: transformType
            )
            transforms.append(transform)
        }
        
        return J2KNLTMarkerSegment(transforms: transforms)
    }
    
    /// Decodes a transform type from binary data.
    private static func decodeTransformType(
        from data: Data,
        offset: Int
    ) throws -> (J2KNLTTransformType, Int) {
        guard offset < data.count else {
            throw J2KError.decodingError("Cannot read transform type")
        }
        
        let typeCode = data[offset]
        var bytesRead = 1
        
        switch typeCode {
        case 0x00:
            return (.identity, bytesRead)
            
        case 0x01:
            // Gamma transform
            guard offset + 1 + 8 <= data.count else {
                throw J2KError.decodingError("Cannot read gamma value")
            }
            let gammaData = data[(offset + 1)..<(offset + 1 + 8)]
            let gamma = gammaData.withUnsafeBytes { $0.load(as: Double.self) }
            bytesRead += 8
            return (.gamma(gamma), bytesRead)
            
        case 0x02:
            return (.logarithmic, bytesRead)
            
        case 0x03:
            return (.logarithmic10, bytesRead)
            
        case 0x04:
            return (.exponential, bytesRead)
            
        case 0x05:
            return (.perceptualQuantizer, bytesRead)
            
        case 0x06:
            return (.hybridLogGamma, bytesRead)
            
        case 0x10:
            // LUT transform
            guard offset + 1 + 1 <= data.count else {
                throw J2KError.decodingError("Cannot read interpolation flag")
            }
            let interpolation = data[offset + 1] != 0
            bytesRead += 1
            
            // Forward LUT size
            guard offset + bytesRead + 2 <= data.count else {
                throw J2KError.decodingError("Cannot read forward LUT size")
            }
            let forwardSize = Int(data[offset + bytesRead]) << 8 | Int(data[offset + bytesRead + 1])
            bytesRead += 2
            
            // Forward LUT data
            guard offset + bytesRead + forwardSize * 8 <= data.count else {
                throw J2KError.decodingError("Cannot read forward LUT data")
            }
            var forwardLUT = [Double]()
            forwardLUT.reserveCapacity(forwardSize)
            for _ in 0..<forwardSize {
                let valueData = data[(offset + bytesRead)..<(offset + bytesRead + 8)]
                let value = valueData.withUnsafeBytes { $0.load(as: Double.self) }
                forwardLUT.append(value)
                bytesRead += 8
            }
            
            // Inverse LUT size
            guard offset + bytesRead + 2 <= data.count else {
                throw J2KError.decodingError("Cannot read inverse LUT size")
            }
            let inverseSize = Int(data[offset + bytesRead]) << 8 | Int(data[offset + bytesRead + 1])
            bytesRead += 2
            
            // Inverse LUT data
            guard offset + bytesRead + inverseSize * 8 <= data.count else {
                throw J2KError.decodingError("Cannot read inverse LUT data")
            }
            var inverseLUT = [Double]()
            inverseLUT.reserveCapacity(inverseSize)
            for _ in 0..<inverseSize {
                let valueData = data[(offset + bytesRead)..<(offset + bytesRead + 8)]
                let value = valueData.withUnsafeBytes { $0.load(as: Double.self) }
                inverseLUT.append(value)
                bytesRead += 8
            }
            
            return (.lookupTable(forwardLUT: forwardLUT, inverseLUT: inverseLUT, interpolation: interpolation), bytesRead)
            
        case 0x11:
            // Piecewise linear transform
            guard offset + bytesRead + 2 <= data.count else {
                throw J2KError.decodingError("Cannot read segment count")
            }
            let segmentCount = Int(data[offset + bytesRead]) << 8 | Int(data[offset + bytesRead + 1])
            bytesRead += 2
            
            guard offset + bytesRead + segmentCount * 16 <= data.count else {
                throw J2KError.decodingError("Cannot read piecewise linear data")
            }
            
            var breakpoints = [Double]()
            var values = [Double]()
            breakpoints.reserveCapacity(segmentCount)
            values.reserveCapacity(segmentCount)
            
            for _ in 0..<segmentCount {
                let bpData = data[(offset + bytesRead)..<(offset + bytesRead + 8)]
                let breakpoint = bpData.withUnsafeBytes { $0.load(as: Double.self) }
                bytesRead += 8
                
                let valData = data[(offset + bytesRead)..<(offset + bytesRead + 8)]
                let value = valData.withUnsafeBytes { $0.load(as: Double.self) }
                bytesRead += 8
                
                breakpoints.append(breakpoint)
                values.append(value)
            }
            
            return (.piecewiseLinear(breakpoints: breakpoints, values: values), bytesRead)
            
        case 0xFF:
            // Custom transform
            guard offset + bytesRead + 1 <= data.count else {
                throw J2KError.decodingError("Cannot read function name length")
            }
            let functionLength = Int(data[offset + bytesRead])
            bytesRead += 1
            
            guard offset + bytesRead + functionLength <= data.count else {
                throw J2KError.decodingError("Cannot read function name")
            }
            let functionData = data[(offset + bytesRead)..<(offset + bytesRead + functionLength)]
            guard let function = String(data: functionData, encoding: .utf8) else {
                throw J2KError.decodingError("Invalid function name encoding")
            }
            bytesRead += functionLength
            
            // Parameter count
            guard offset + bytesRead + 2 <= data.count else {
                throw J2KError.decodingError("Cannot read parameter count")
            }
            let paramCount = Int(data[offset + bytesRead]) << 8 | Int(data[offset + bytesRead + 1])
            bytesRead += 2
            
            guard offset + bytesRead + paramCount * 8 <= data.count else {
                throw J2KError.decodingError("Cannot read parameters")
            }
            
            var parameters = [Double]()
            parameters.reserveCapacity(paramCount)
            
            for _ in 0..<paramCount {
                let paramData = data[(offset + bytesRead)..<(offset + bytesRead + 8)]
                let param = paramData.withUnsafeBytes { $0.load(as: Double.self) }
                parameters.append(param)
                bytesRead += 8
            }
            
            return (.custom(parameters: parameters, function: function), bytesRead)
            
        default:
            throw J2KError.decodingError("Unknown NLT transform type: 0x\(String(typeCode, radix: 16))")
        }
    }
}

// MARK: - Validation

extension J2KNLTMarkerSegment {
    /// Validates the NLT marker segment.
    ///
    /// - Returns: `true` if the marker segment is valid.
    public func validate() -> Bool {
        // Check for duplicate component indices
        let indices = transforms.map { $0.componentIndex }
        let uniqueIndices = Set(indices)
        guard indices.count == uniqueIndices.count else {
            return false
        }
        
        // Validate each transform
        for transform in transforms {
            guard transform.componentIndex >= 0 else {
                return false
            }
            
            // Validate transform-specific constraints
            switch transform.transformType {
            case .gamma(let gamma):
                guard gamma > 0 else {
                    return false
                }
                
            case .lookupTable(let forwardLUT, let inverseLUT, _):
                guard !forwardLUT.isEmpty && !inverseLUT.isEmpty else {
                    return false
                }
                
            case .piecewiseLinear(let breakpoints, let values):
                guard breakpoints.count == values.count && !breakpoints.isEmpty else {
                    return false
                }
                // Check that breakpoints are sorted
                for i in 1..<breakpoints.count {
                    guard breakpoints[i] >= breakpoints[i - 1] else {
                        return false
                    }
                }
                
            default:
                break
            }
        }
        
        return true
    }
}
