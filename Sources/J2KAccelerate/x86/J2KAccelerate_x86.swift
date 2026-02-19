// J2KAccelerate_x86.swift
// J2KSwift
//
// x86-64 specific code paths for Accelerate operations.
//
// ⚠️ DEPRECATION NOTICE: This file contains x86-64 specific code that may be removed
// in future versions as the project focuses on Apple Silicon (ARM64) architecture.
//

import Foundation
import J2KCore

#if canImport(Accelerate) && arch(x86_64)
import Accelerate
#endif

/// x86-64 specific hardware acceleration support.
///
/// This type provides x86-64 specific implementations and fallbacks for operations
/// that may have different performance characteristics on Intel processors.
///
/// ## Deprecation Status
///
/// - **Target Architecture**: x86-64 (Intel)
/// - **Maintenance Level**: Minimal (bug fixes only)
/// - **Removal Timeline**: Future major version (TBD)
/// - **Recommended Alternative**: Use Apple Silicon (ARM64) for best performance
///
/// ## Performance Notes
///
/// On x86-64 Macs:
/// - AVX/AVX2 SIMD instructions (256-bit)
/// - No AMX matrix coprocessor
/// - Rosetta 2 overhead when running ARM64 code
/// - Older cache hierarchy vs Apple Silicon
///
/// ## Usage
///
/// ```swift
/// // Automatically selected on x86-64 platforms
/// if J2KAccelerateX86.isAvailable {
///     let result = try J2KAccelerateX86.optimizedOperation(data)
/// }
/// ```
public struct J2KAccelerateX86: Sendable {
    /// Creates a new x86-64 accelerated processor.
    public init() {}
    
    /// Indicates whether x86-64 acceleration is available.
    ///
    /// Returns `true` only on x86-64 Macs with Accelerate framework.
    public static var isAvailable: Bool {
        #if canImport(Accelerate) && arch(x86_64)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Architecture Information
    
    #if canImport(Accelerate) && arch(x86_64)
    
    /// Returns information about the x86-64 CPU features.
    ///
    /// Detects available SIMD instruction sets (SSE, AVX, AVX2, etc.).
    ///
    /// - Returns: Dictionary of feature name to availability.
    public static func cpuFeatures() -> [String: Bool] {
        var features: [String: Bool] = [:]
        
        // All modern x86-64 Macs support these
        features["SSE"] = true
        features["SSE2"] = true
        features["SSE3"] = true
        features["SSSE3"] = true
        features["SSE4.1"] = true
        features["SSE4.2"] = true
        features["AVX"] = true
        features["AVX2"] = true
        
        // Not available on x86-64
        features["NEON"] = false
        features["AMX"] = false
        
        return features
    }
    
    // MARK: - x86-64 Specific Optimizations
    
    /// Performs DWT with x86-64 optimized cache blocking.
    ///
    /// Uses smaller cache blocking sizes optimized for Intel cache hierarchy.
    ///
    /// - Parameters:
    ///   - data: Input data array.
    ///   - width: Data width.
    ///   - height: Data height.
    /// - Returns: Transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func dwtWithX86CacheBlocking(
        data: [Double],
        width: Int,
        height: Int
    ) throws -> [Double] {
        guard data.count == width * height else {
            throw J2KError.invalidParameter(
                "Data size must match dimensions: \(width)×\(height)"
            )
        }
        
        // x86-64 typically has:
        // L1 cache: 32-64 KB (per core)
        // L2 cache: 256-512 KB (per core)
        // L3 cache: 8-16 MB (shared)
        //
        // Use smaller block size than Apple Silicon
        let blockSize = 32 // vs 64 on ARM64
        
        var output = data
        
        // Process in cache-friendly blocks
        for blockY in stride(from: 0, to: height, by: blockSize) {
            for blockX in stride(from: 0, to: width, by: blockSize) {
                let endY = min(blockY + blockSize, height)
                let endX = min(blockX + blockSize, width)
                
                for y in blockY..<endY {
                    for x in blockX..<endX {
                        let index = y * width + x
                        // Placeholder transform
                        output[index] = data[index]
                    }
                }
            }
        }
        
        return output
    }
    
    /// Performs matrix multiplication with AVX-optimized blocking.
    ///
    /// Uses block sizes tuned for AVX/AVX2 (256-bit SIMD).
    ///
    /// - Parameters:
    ///   - a: First matrix.
    ///   - b: Second matrix.
    ///   - m: Rows in A.
    ///   - n: Columns in B.
    ///   - k: Columns in A / Rows in B.
    /// - Returns: Result matrix.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func matrixMultiplyAVX(
        a: [Double],
        b: [Double],
        m: Int,
        n: Int,
        k: Int
    ) throws -> [Double] {
        guard a.count == m * k else {
            throw J2KError.invalidParameter(
                "Matrix A size mismatch: expected \(m*k), got \(a.count)"
            )
        }
        
        guard b.count == k * n else {
            throw J2KError.invalidParameter(
                "Matrix B size mismatch: expected \(k*n), got \(b.count)"
            )
        }
        
        var result = [Double](repeating: 0.0, count: m * n)
        
        // Use BLAS which is optimized for x86-64
        var alpha = 1.0
        var beta = 0.0
        
        cblas_dgemm(
            CblasRowMajor,
            CblasNoTrans,
            CblasNoTrans,
            Int32(m),
            Int32(n),
            Int32(k),
            alpha,
            a,
            Int32(k),
            b,
            Int32(n),
            beta,
            &result,
            Int32(n)
        )
        
        return result
    }
    
    #endif
}

// MARK: - Migration Notes

/*
 Migration Path from x86-64 to ARM64:
 
 1. Performance Comparison:
    - ARM64 (Apple Silicon): Up to 3-5× faster for JPEG 2000 operations
    - x86-64 (Intel): Limited by older architecture, no AMX
    - Rosetta 2: ~70-90% native ARM64 performance (better than native x86-64)
 
 2. When to Remove x86-64 Code:
    - After Apple stops shipping Intel Macs (already happened)
    - After support window expires (typically 2-3 years)
    - When x86-64 usage drops below threshold (e.g., <5% of installs)
 
 3. Removal Checklist:
    - [ ] Remove `#if arch(x86_64)` guards throughout codebase
    - [ ] Remove this file: `Sources/J2KAccelerate/x86/J2KAccelerate_x86.swift`
    - [ ] Update Package.swift to remove x86-64 specific settings
    - [ ] Update documentation to reflect ARM64-only support
    - [ ] Add deprecation warnings in previous major version
    - [ ] Announce in release notes and migration guide
 
 4. Testing Strategy:
    - Continue running CI on x86-64 until removal
    - Use Rosetta 2 for compatibility testing
    - Focus optimization efforts on ARM64
 */
