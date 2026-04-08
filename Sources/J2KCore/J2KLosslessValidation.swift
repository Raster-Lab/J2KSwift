//
// J2KLosslessValidation.swift
// J2KSwift
//
/// Lossless roundtrip validation utilities.
///
/// Provides pixel-by-pixel comparison of images before and after
/// encode→decode roundtrip, with detailed mismatch diagnostics.
/// All comparisons are deterministic and use integer arithmetic only.

import Foundation

/// Diagnostic information for the first pixel mismatch found during
/// lossless validation.
public struct J2KLosslessMismatch: Sendable, CustomStringConvertible {
    /// Component (channel) index where the mismatch occurs.
    public let component: Int

    /// X coordinate of the mismatched pixel.
    public let x: Int

    /// Y coordinate of the mismatched pixel.
    public let y: Int

    /// Expected (original) sample value.
    public let expected: Int

    /// Actual (decoded) sample value.
    public let actual: Int

    /// Signed difference (expected − actual).
    public var difference: Int { expected - actual }

    public var description: String {
        "Mismatch at component \(component), pixel (\(x), \(y)): " +
        "expected \(expected), got \(actual) (diff \(difference))"
    }
}

/// Result of a lossless validation pass.
public enum J2KLosslessResult: Sendable {
    /// All pixels match exactly.
    case bitExact

    /// One or more pixels differ. Contains the first mismatch found,
    /// total mismatch count, and maximum absolute error.
    case mismatch(
        first: J2KLosslessMismatch,
        totalMismatches: Int,
        maxAbsoluteError: Int
    )
}

/// Deterministic lossless validation engine.
///
/// Compares two ``J2KImage`` instances pixel-by-pixel across all
/// components, reporting detailed diagnostics on the first mismatch.
public enum J2KLosslessValidator {

    /// Compare two images pixel-by-pixel.
    ///
    /// - Parameters:
    ///   - original: The reference image (before encoding).
    ///   - decoded: The image after encode→decode roundtrip.
    /// - Returns: `.bitExact` if every sample matches, or `.mismatch` with
    ///   diagnostic details.
    /// - Throws: ``J2KError`` if images have incompatible dimensions.
    public static func validate(
        original: J2KImage,
        decoded: J2KImage
    ) throws -> J2KLosslessResult {
        guard original.width == decoded.width,
              original.height == decoded.height,
              original.componentCount == decoded.componentCount else {
            throw J2KError.invalidParameter(
                "Dimension mismatch: original \(original.width)×\(original.height)×\(original.componentCount) " +
                "vs decoded \(decoded.width)×\(decoded.height)×\(decoded.componentCount)")
        }

        var firstMismatch: J2KLosslessMismatch?
        var totalMismatches = 0
        var maxAbsError = 0

        for ci in 0..<original.componentCount {
            let origComp = original.components[ci]
            let decoComp = decoded.components[ci]

            let width = origComp.width
            let height = origComp.height
            let pixelCount = width * height
            let bps = origComp.bitDepth <= 8 ? 1 : 2

            for i in 0..<pixelCount {
                let o = readSample(origComp.data, index: i, bytesPerSample: bps, signed: origComp.signed)
                let d = readSample(decoComp.data, index: i, bytesPerSample: bps, signed: decoComp.signed)

                if o != d {
                    let x = i % width
                    let y = i / width
                    let absErr = abs(o - d)

                    if firstMismatch == nil {
                        firstMismatch = J2KLosslessMismatch(
                            component: ci, x: x, y: y,
                            expected: o, actual: d)
                    }
                    totalMismatches += 1
                    if absErr > maxAbsError { maxAbsError = absErr }
                }
            }
        }

        if let first = firstMismatch {
            return .mismatch(
                first: first,
                totalMismatches: totalMismatches,
                maxAbsoluteError: maxAbsError)
        }
        return .bitExact
    }

    /// Format a detailed diagnostic string for a validation result.
    ///
    /// - Parameters:
    ///   - result: The validation result.
    ///   - label: Optional label for the test case.
    /// - Returns: A multi-line diagnostic string.
    public static func diagnosticString(
        _ result: J2KLosslessResult,
        label: String? = nil
    ) -> String {
        let prefix = label.map { "[\($0)] " } ?? ""
        switch result {
        case .bitExact:
            return "\(prefix)Lossless validation: PASS (bit-exact)"
        case .mismatch(let first, let total, let maxErr):
            return """
            \(prefix)Lossless validation: FAIL
              First mismatch: \(first)
              Total mismatches: \(total)
              Maximum absolute error: \(maxErr)
            """
        }
    }

    // MARK: - Internal

    @inline(__always)
    private static func readSample(
        _ data: Data, index: Int, bytesPerSample: Int, signed: Bool
    ) -> Int {
        if bytesPerSample == 1 {
            guard index < data.count else { return 0 }
            if signed {
                return Int(Int8(bitPattern: data[index]))
            }
            return Int(data[index])
        } else {
            let idx = index * 2
            guard idx + 1 < data.count else { return 0 }
            // Big-endian (matches encoder/decoder convention)
            let raw = UInt16(data[idx]) << 8 | UInt16(data[idx + 1])
            if signed {
                return Int(Int16(bitPattern: raw))
            }
            return Int(raw)
        }
    }
}
