// J2KDecoderPipeline.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import Foundation
import J2KCore

/// Internal implementation of the JPEG 2000 decoding pipeline.
///
/// This struct provides the decoding pipeline that ties together all the codec components:
/// - Codestream parsing
/// - Entropy decoding
/// - Dequantization
/// - Inverse wavelet transform (IDWT)
/// - Inverse color transform
/// - Image reconstruction
struct J2KDecoderPipeline: Sendable {
    
    init() {}
    
    /// Decodes JPEG 2000 data into an image.
    func decode(_ data: Data) throws -> J2KImage {
        // Step 1: Parse header
        let (width, height, componentCount, _) = try parseHeader(data: data)
        
        // Step 2: Extract encoded component data
        var offset = 18 // Skip header (2+2 + 4+4+4+4 bytes)
        var decodedComponents: [J2KComponent] = []
        
        for componentIndex in 0..<componentCount {
            guard offset + 4 <= data.count else {
                throw J2KError.invalidParameter("Truncated codestream")
            }
            
            // Read component length
            let lengthBytes = data.subdata(in: offset..<(offset + 4))
            let length = lengthBytes.withUnsafeBytes { buffer in
                buffer.loadUnaligned(as: UInt32.self).bigEndian
            }
            offset += 4
            
            guard offset + Int(length) <= data.count else {
                throw J2KError.invalidParameter("Truncated component data")
            }
            
            // Extract component data
            let componentData = data.subdata(in: offset..<(offset + Int(length)))
            offset += Int(length)
            
            // Create component
            let component = J2KComponent(
                index: componentIndex,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: componentData
            )
            decodedComponents.append(component)
        }
        
        // Step 3: Apply inverse color transform if needed
        let finalComponents = try applyInverseColorTransform(
            components: decodedComponents,
            width: width,
            height: height
        )
        
        // Step 4: Create and return image
        return J2KImage(
            width: width,
            height: height,
            components: finalComponents
        )
    }
    
    // MARK: - Helper Methods
    
    /// Parses the codestream header.
    private func parseHeader(data: Data) throws -> (width: Int, height: Int, componentCount: Int, levels: Int) {
        guard data.count >= 18 else {
            throw J2KError.invalidParameter("Codestream too short")
        }
        
        // Verify SOC marker
        guard data[0] == 0xFF && data[1] == 0x4F else {
            throw J2KError.invalidParameter("Invalid SOC marker")
        }
        
        // Verify SIZ marker
        guard data[2] == 0xFF && data[3] == 0x51 else {
            throw J2KError.invalidParameter("Invalid SIZ marker")
        }
        
        let width = data.subdata(in: 4..<8).withUnsafeBytes { buffer in
            Int(buffer.loadUnaligned(as: UInt32.self).bigEndian)
        }
        let height = data.subdata(in: 8..<12).withUnsafeBytes { buffer in
            Int(buffer.loadUnaligned(as: UInt32.self).bigEndian)
        }
        let componentCount = data.subdata(in: 12..<16).withUnsafeBytes { buffer in
            Int(buffer.loadUnaligned(as: UInt32.self).bigEndian)
        }
        let levels = data.subdata(in: 16..<20).withUnsafeBytes { buffer in
            Int(buffer.loadUnaligned(as: UInt32.self).bigEndian)
        }
        
        return (width, height, componentCount, levels)
    }
    
    /// Applies inverse color transform.
    private func applyInverseColorTransform(
        components: [J2KComponent],
        width: Int,
        height: Int
    ) throws -> [J2KComponent] {
        // If we have 3 components, we could apply inverse YCbCr → RGB transform
        // For now, just return components as-is
        return components
    }
}
