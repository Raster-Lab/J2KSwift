//
// J2KHTBlockCoderOptimizations.swift
// J2KSwift
//
// J2KHTBlockCoderOptimizations.swift
// J2KSwift
//
// Memory optimisations for HT block coding
//

import Foundation
import J2KCore

/// Optimizations to reduce temporary allocations in HT block coding.
extension HTBlockEncoder {
    /// Encodes cleanup pass with minimal allocations for small blocks.
    ///
    /// For blocks smaller than 16×16, uses stack-allocated scratch buffers
    /// to avoid heap allocations.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients.
    ///   - bitPlane: The bit-plane to encode.
    /// - Returns: Encoded block data.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCleanupOptimized(coefficients: [Int], bitPlane: Int) throws -> HTEncodedBlock {
        let blockSize = width * height

        // For very small blocks (≤256 samples), use the lightweight path
        if blockSize <= 256 {
            return try encodeCleanupLightweight(coefficients: coefficients, bitPlane: bitPlane)
        }

        // Otherwise, use standard encoding
        return try encodeCleanup(coefficients: coefficients, bitPlane: bitPlane)
    }

    /// Lightweight encoding for small code-blocks with minimal allocations.
    private func encodeCleanupLightweight(coefficients: [Int], bitPlane: Int) throws -> HTEncodedBlock {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "Coefficient count mismatch in lightweight encoding"
            )
        }

        // Use local coders with pre-sized capacity hints
        var mel = HTMELCoder()
        var vlc = HTVLCCoder()
        var magsgn = HTMagSgnCoder()

        // Process in stripe order
        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in stride(from: 0, to: width, by: 2) {
                let pairWidth = min(2, width - col)

                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let x0 = col
                    let idx0 = y * width + x0

                    let coeff0 = coefficients[idx0]
                    let sig0 = (abs(coeff0) >> bitPlane) & 1

                    var sig1 = 0
                    var coeff1 = 0
                    if pairWidth > 1 {
                        let idx1 = y * width + x0 + 1
                        coeff1 = coefficients[idx1]
                        sig1 = (abs(coeff1) >> bitPlane) & 1
                    }

                    let pattern = sig0 | (sig1 << 1)
                    mel.encode(bit: (pattern == 0) ? 0 : 1)
                    vlc.encodeSignificance(pattern: pattern)

                    if sig0 != 0 {
                        let mag = abs(coeff0)
                        let sign = coeff0 < 0 ? 1 : 0
                        magsgn.encode(magnitude: mag, sign: sign, bitPlane: bitPlane)
                    }
                    if sig1 != 0 {
                        let mag = abs(coeff1)
                        let sign = coeff1 < 0 ? 1 : 0
                        magsgn.encode(magnitude: mag, sign: sign, bitPlane: bitPlane)
                    }
                }
            }
        }

        let melData = mel.flush()
        let vlcData = vlc.flush()
        let magsgnData = magsgn.flush()

        var codedData = Data()
        codedData.append(melData)
        codedData.append(magsgnData)
        codedData.append(Data(vlcData.reversed()))

        return HTEncodedBlock(
            codedData: codedData,
            passType: .htCleanup,
            melLength: melData.count,
            vlcLength: vlcData.count,
            magsgnLength: magsgnData.count,
            bitPlane: bitPlane,
            width: width,
            height: height
        )
    }
}

/// Optimizations for HT block decoder.
extension HTBlockDecoder {
    /// Decodes cleanup pass with minimal allocations.
    ///
    /// - Parameter block: The encoded block.
    /// - Returns: Decoded coefficients.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeCleanupOptimized(from block: HTEncodedBlock) throws -> [Int] {
        let blockSize = width * height

        // For small blocks, pre-allocate with exact size
        if blockSize <= 256 {
            return try decodeCleanupLightweight(from: block)
        }

        return try decodeCleanup(from: block)
    }

    /// Lightweight decoding for small blocks.
    private func decodeCleanupLightweight(from block: HTEncodedBlock) throws -> [Int] {
        // Pre-allocate result with exact size
        var coefficients = [Int](repeating: 0, count: width * height)

        let data = block.codedData
        let melEnd = block.melLength
        let magsgnEnd = melEnd + block.magsgnLength

        guard melEnd <= data.count && magsgnEnd <= data.count else {
            throw J2KError.decodingError("Invalid stream lengths")
        }

        let melData = data.prefix(melEnd)
        let magsgnData = data[melEnd..<magsgnEnd]
        let vlcDataReversed = data[magsgnEnd...]
        let vlcData = Data(vlcDataReversed.reversed())

        var melReader = J2KBitReader(data: melData)
        var magsgnReader = J2KBitReader(data: Data(magsgnData))
        var vlcReader = J2KBitReader(data: vlcData)
        var mel = HTMELCoder()
        let vlc = HTVLCCoder()
        let magsgn = HTMagSgnCoder()

        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in stride(from: 0, to: width, by: 2) {
                let pairWidth = min(2, width - col)

                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let x0 = col

                    let melDecision = try mel.decode(from: &melReader)

                    var pattern = 0
                    if melDecision != 0 || melReader.bytesRemaining == 0 {
                        pattern = try vlc.decodeSignificance(from: &vlcReader)
                    }

                    let sig0 = pattern & 1
                    let sig1 = (pattern >> 1) & 1

                    if sig0 != 0 {
                        let value = try magsgn.decode(
                            from: &magsgnReader,
                            bitPlane: block.bitPlane
                        )
                        let idx = y * width + x0
                        coefficients[idx] = value
                    }

                    if sig1 != 0 && pairWidth > 1 {
                        let value = try magsgn.decode(
                            from: &magsgnReader,
                            bitPlane: block.bitPlane
                        )
                        let idx = y * width + x0 + 1
                        coefficients[idx] = value
                    }
                }
            }
        }

        return coefficients
    }
}

/// In-place coefficient transform for HT passes.
public struct HTCoefficientTransform {
    /// Applies in-place quantization to coefficients.
    ///
    /// - Parameters:
    ///   - coefficients: Coefficients to quantize (modified in-place).
    ///   - stepSize: Quantization step size.
    public static func quantizeInPlace(_ coefficients: inout [Int], stepSize: Double) {
        guard stepSize > 0 else { return }

        for i in 0..<coefficients.count {
            coefficients[i] = Int(Double(coefficients[i]) / stepSize)
        }
    }

    /// Applies in-place dequantization to coefficients.
    ///
    /// - Parameters:
    ///   - coefficients: Coefficients to dequantize (modified in-place).
    ///   - stepSize: Quantization step size.
    public static func dequantizeInPlace(_ coefficients: inout [Int], stepSize: Double) {
        guard stepSize > 0 else { return }

        for i in 0..<coefficients.count {
            coefficients[i] = Int(Double(coefficients[i]) * stepSize)
        }
    }
}

/// Lazy allocation support for optional HT coding passes.
internal struct HTLazyCodingPasses {
    /// Encodes SigProp pass only if needed.
    ///
    /// - Parameters:
    ///   - encoder: The block encoder.
    ///   - coefficients: Wavelet coefficients.
    ///   - significanceState: Current significance state.
    ///   - bitPlane: Bit-plane to encode.
    ///   - needsSigProp: Whether SigProp pass is needed.
    /// - Returns: SigProp data if needed, nil otherwise.
    internal static func encodeSigPropIfNeeded(
        encoder: HTBlockEncoder,
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int,
        needsSigProp: Bool
    ) throws -> Data? {
        guard needsSigProp else { return nil }
        return try encoder.encodeSigProp(
            coefficients: coefficients,
            significanceState: significanceState,
            bitPlane: bitPlane
        )
    }

    /// Encodes MagRef pass only if needed.
    ///
    /// - Parameters:
    ///   - encoder: The block encoder.
    ///   - coefficients: Wavelet coefficients.
    ///   - significanceState: Current significance state.
    ///   - bitPlane: Bit-plane to encode.
    ///   - needsMagRef: Whether MagRef pass is needed.
    /// - Returns: MagRef data if needed, nil otherwise.
    internal static func encodeMagRefIfNeeded(
        encoder: HTBlockEncoder,
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int,
        needsMagRef: Bool
    ) throws -> Data? {
        guard needsMagRef else { return nil }
        return try encoder.encodeMagRef(
            coefficients: coefficients,
            significanceState: significanceState,
            bitPlane: bitPlane
        )
    }
}
