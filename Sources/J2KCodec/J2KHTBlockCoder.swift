/// # HTJ2K Block Coder
///
/// Implementation of the FBCOT (Fast Block Coder with Optimized Truncation) algorithm
/// for HTJ2K (High-Throughput JPEG 2000) as specified in ISO/IEC 15444-15.
///
/// The HT block coder replaces the traditional EBCOT Tier-1 coding with a significantly
/// faster algorithm that uses three distinct coding primitives:
/// - **MEL (Modular Embedded Length)**: Run-length coding for significance context
/// - **VLC (Variable Length Coding)**: Fixed-to-variable coding for significance/sign
/// - **MagSgn (Magnitude and Sign)**: Raw magnitude and sign bits
///
/// ## Topics
///
/// ### Coding Primitives
/// - ``HTMELCoder``
/// - ``HTVLCCoder``
/// - ``HTMagSgnCoder``
///
/// ### Block Coding
/// - ``HTBlockEncoder``
/// - ``HTBlockDecoder``

import Foundation
import J2KCore

// MARK: - HT Coding Mode

/// Identifies whether a code-block uses legacy EBCOT or HTJ2K block coding.
///
/// ISO/IEC 15444-15 allows mixed codestreams where some code-blocks use legacy
/// JPEG 2000 coding and others use the HT block coder within the same tile.
enum HTCodingMode: Sendable, Equatable {
    /// Legacy JPEG 2000 Part 1 EBCOT block coding.
    case legacy

    /// High-Throughput JPEG 2000 (Part 15) FBCOT block coding.
    case ht
}

// MARK: - HT Coding Pass

/// The type of coding pass in HTJ2K block coding.
///
/// The HT block coder uses a different set of passes compared to legacy EBCOT.
/// The cleanup pass is the primary coding pass, while SigProp and MagRef
/// provide refinement for progressive quality.
enum HTCodingPassType: Sendable, Equatable {
    /// HT cleanup pass — the primary pass encoding significance, sign, and magnitude.
    ///
    /// Uses MEL, VLC, and MagSgn coding primitives.
    case htCleanup

    /// HT significance propagation pass.
    ///
    /// Encodes newly significant samples found during refinement.
    case htSigProp

    /// HT magnitude refinement pass.
    ///
    /// Refines the magnitude of already-significant samples.
    case htMagRef
}

// MARK: - MEL Coder

/// Modular Embedded Length coder for HTJ2K.
///
/// The MEL coder is a run-length coder that compresses runs of zero-context
/// significance decisions in the HT cleanup pass. It adaptively adjusts the
/// run length threshold based on the observed data.
///
/// The MEL encoder produces a byte stream that grows from the beginning of the
/// coded data buffer, while the VLC stream grows from the end.
struct HTMELCoder: Sendable {
    /// Current run count.
    private var run: Int = 0

    /// Current run-length threshold (number of zeros to emit a 0 MEL bit).
    private var threshold: Int = 0

    /// MEL state index for adaptive threshold selection.
    private var stateIndex: Int = 0

    /// Output buffer for MEL-encoded data.
    private var buffer: [UInt8] = []

    /// Bit accumulator for partial byte output.
    private var bitBuffer: UInt32 = 0

    /// Number of valid bits in the bit accumulator.
    private var bitCount: Int = 0

    /// MEL threshold table for adaptive run-length selection.
    ///
    /// Each entry is a power-of-2 run threshold: 2^t[i].
    private static let thresholdTable: [Int] = [
        0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 6, 7, 8
    ]

    /// Creates a new MEL coder.
    init() {}

    /// Encodes a single context decision (0 = insignificant, 1 = significant).
    ///
    /// - Parameter bit: The context decision bit.
    mutating func encode(bit: Int) {
        if bit == 0 {
            run += 1
            let limit = 1 << Self.thresholdTable[stateIndex]
            if run >= limit {
                emitBit(0)
                run = 0
                if stateIndex < Self.thresholdTable.count - 1 {
                    stateIndex += 1
                }
            }
        } else {
            emitBit(1)
            let remainingBits = Self.thresholdTable[stateIndex]
            // Emit the run count using `remainingBits` bits
            for shift in stride(from: remainingBits - 1, through: 0, by: -1) {
                emitBit((run >> shift) & 1)
            }
            run = 0
            if stateIndex > 0 {
                stateIndex -= 1
            }
        }
    }

    /// Flushes any remaining data in the MEL coder.
    ///
    /// - Returns: The MEL-encoded byte stream.
    mutating func flush() -> Data {
        // Emit remaining run if any
        if run > 0 {
            // Pad with 0-bits since the run didn't complete
            emitBit(0)
        }
        // Flush bit buffer
        while bitCount > 0 {
            buffer.append(UInt8((bitBuffer >> 24) & 0xFF))
            bitBuffer <<= 8
            bitCount = max(0, bitCount - 8)
        }
        return Data(buffer)
    }

    /// Emits a single bit to the output stream.
    private mutating func emitBit(_ bit: Int) {
        bitBuffer |= UInt32(bit & 1) << (31 - bitCount)
        bitCount += 1
        if bitCount >= 8 {
            let byte = UInt8((bitBuffer >> 24) & 0xFF)
            buffer.append(byte)
            bitBuffer <<= 8
            bitCount -= 8
        }
    }

    /// Decodes a single context decision from MEL-encoded data.
    ///
    /// - Parameter reader: The bit reader positioned at MEL data.
    /// - Returns: The decoded context decision (0 or 1).
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    mutating func decode(from reader: inout J2KBitReader) throws -> Int {
        if run > 0 {
            run -= 1
            return 0
        }

        guard reader.bytesRemaining > 0 || bitCount > 0 else {
            return 0
        }

        let bit = try readBit(from: &reader)
        if bit == 0 {
            // Run continues — set run to the threshold value
            let limit = 1 << Self.thresholdTable[stateIndex]
            run = limit - 1
            if stateIndex < Self.thresholdTable.count - 1 {
                stateIndex += 1
            }
            return 0
        } else {
            // Run ends — read remaining bits to get run length
            let remainingBits = Self.thresholdTable[stateIndex]
            var runLength = 0
            for _ in 0..<remainingBits {
                let b = try readBit(from: &reader)
                runLength = (runLength << 1) | b
            }
            run = runLength
            if stateIndex > 0 {
                stateIndex -= 1
            }
            if run > 0 {
                run -= 1
                return 0
            }
            return 1
        }
    }

    /// Reads a single bit from the reader.
    private mutating func readBit(from reader: inout J2KBitReader) throws -> Int {
        if bitCount <= 0 {
            guard reader.bytesRemaining > 0 else {
                return 0
            }
            let byte = try reader.readUInt8()
            bitBuffer = UInt32(byte) << 24
            bitCount = 8
        }
        let bit = Int((bitBuffer >> 31) & 1)
        bitBuffer <<= 1
        bitCount -= 1
        return bit
    }
}

// MARK: - VLC Coder

/// Variable Length Coder for HTJ2K.
///
/// The VLC coder uses a fixed-to-variable code mapping to encode significance
/// and sign information for pairs of samples (quad-pairs) in the HT cleanup pass.
/// The VLC stream is written from the end of the coded data buffer, growing toward
/// the beginning, while MEL data grows from the beginning.
struct HTVLCCoder: Sendable {
    /// Output buffer for VLC-encoded data.
    private var buffer: [UInt8] = []

    /// Bit accumulator.
    private var bitBuffer: UInt32 = 0

    /// Number of valid bits in the accumulator.
    private var bitCount: Int = 0

    /// VLC table for significance pattern encoding (2 samples per entry).
    ///
    /// Maps significance patterns to (codeword, length) pairs.
    /// Pattern bits: [sig0, sig1] where sig=1 means sample is significant.
    private static let vlcTable: [(code: UInt8, length: Int)] = [
        (0b0, 1),     // pattern 0b00: neither significant
        (0b10, 2),    // pattern 0b01: second significant
        (0b110, 3),   // pattern 0b10: first significant
        (0b111, 3)    // pattern 0b11: both significant
    ]

    /// Creates a new VLC coder.
    init() {}

    /// Encodes a significance pattern for a pair of samples.
    ///
    /// - Parameter pattern: A 2-bit significance pattern (0-3).
    mutating func encodeSignificance(pattern: Int) {
        let clampedPattern = pattern & 0x03
        let entry = Self.vlcTable[clampedPattern]
        emitBits(Int(entry.code), count: entry.length)
    }

    /// Encodes a sign bit (0 = positive, 1 = negative).
    ///
    /// - Parameter sign: The sign bit.
    mutating func encodeSign(_ sign: Int) {
        emitBits(sign & 1, count: 1)
    }

    /// Flushes the VLC coder and returns the encoded data.
    ///
    /// - Returns: The VLC-encoded byte stream.
    mutating func flush() -> Data {
        // Pad to byte boundary
        while bitCount % 8 != 0 {
            emitBits(0, count: 1)
        }
        while bitCount > 0 {
            buffer.append(UInt8((bitBuffer >> 24) & 0xFF))
            bitBuffer <<= 8
            bitCount -= 8
        }
        return Data(buffer)
    }

    /// Emits multiple bits to the output.
    private mutating func emitBits(_ value: Int, count: Int) {
        for shift in stride(from: count - 1, through: 0, by: -1) {
            let bit = (value >> shift) & 1
            bitBuffer |= UInt32(bit) << (31 - bitCount)
            bitCount += 1
            if bitCount >= 8 {
                buffer.append(UInt8((bitBuffer >> 24) & 0xFF))
                bitBuffer <<= 8
                bitCount -= 8
            }
        }
    }

    /// Decodes a significance pattern from VLC-encoded data.
    ///
    /// - Parameter reader: The bit reader positioned at VLC data.
    /// - Returns: A 2-bit significance pattern.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeSignificance(from reader: inout J2KBitReader) throws -> Int {
        guard reader.bytesRemaining > 0 || reader.position > 0 else {
            return 0
        }
        let firstBit = try readVLCBit(from: &reader)
        if firstBit == 0 {
            return 0  // Neither significant
        }
        let secondBit = try readVLCBit(from: &reader)
        if secondBit == 0 {
            return 1  // Second significant only
        }
        let thirdBit = try readVLCBit(from: &reader)
        if thirdBit == 0 {
            return 2  // First significant only
        }
        return 3  // Both significant
    }

    /// Reads a single VLC bit.
    private func readVLCBit(from reader: inout J2KBitReader) throws -> Int {
        guard reader.bytesRemaining > 0 else {
            return 0
        }
        return try reader.readBit() ? 1 : 0
    }
}

// MARK: - MagSgn Coder

/// Magnitude and Sign coder for HTJ2K.
///
/// The MagSgn coder encodes the magnitude and sign of significant wavelet
/// coefficients in the HT cleanup pass. It writes raw (uncompressed) bits
/// for the magnitude values and sign bits of samples identified as significant.
///
/// The magnitude is encoded as `|coefficient| - 1` using the number of bits
/// determined by the most significant bit position.
struct HTMagSgnCoder: Sendable {
    /// Output buffer for magnitude/sign data.
    private var buffer: [UInt8] = []

    /// Bit accumulator.
    private var bitBuffer: UInt32 = 0

    /// Number of valid bits in the accumulator.
    private var bitCount: Int = 0

    /// Creates a new MagSgn coder.
    init() {}

    /// Encodes the magnitude and sign of a significant coefficient.
    ///
    /// - Parameters:
    ///   - magnitude: The absolute value of the coefficient (must be > 0).
    ///   - sign: The sign bit (0 = positive, 1 = negative).
    ///   - bitPlane: The current bit-plane being encoded.
    mutating func encode(magnitude: Int, sign: Int, bitPlane: Int) {
        guard magnitude > 0 else { return }

        // Encode sign bit
        emitBit(sign & 1)

        // Encode magnitude minus 1 in the remaining bit-planes
        let magMinus1 = magnitude - 1
        let numBits = max(0, bitPlane)
        for shift in stride(from: numBits - 1, through: 0, by: -1) {
            emitBit((magMinus1 >> shift) & 1)
        }
    }

    /// Flushes the MagSgn coder and returns the encoded data.
    ///
    /// - Returns: The MagSgn-encoded byte stream.
    mutating func flush() -> Data {
        // Pad to byte boundary
        while bitCount % 8 != 0 {
            emitBit(0)
        }
        while bitCount > 0 {
            buffer.append(UInt8((bitBuffer >> 24) & 0xFF))
            bitBuffer <<= 8
            bitCount -= 8
        }
        return Data(buffer)
    }

    /// Emits a single bit.
    private mutating func emitBit(_ bit: Int) {
        bitBuffer |= UInt32(bit & 1) << (31 - bitCount)
        bitCount += 1
        if bitCount >= 8 {
            buffer.append(UInt8((bitBuffer >> 24) & 0xFF))
            bitBuffer <<= 8
            bitCount -= 8
        }
    }

    /// Decodes a magnitude and sign from the MagSgn stream.
    ///
    /// - Parameters:
    ///   - reader: The bit reader positioned at MagSgn data.
    ///   - bitPlane: The current bit-plane being decoded.
    /// - Returns: The decoded signed coefficient value.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decode(from reader: inout J2KBitReader, bitPlane: Int) throws -> Int {
        // Read sign bit
        let sign = try reader.readBit() ? 1 : 0

        // Read magnitude bits
        let numBits = max(0, bitPlane)
        var magMinus1 = 0
        for _ in 0..<numBits {
            let bit = try reader.readBit() ? 1 : 0
            magMinus1 = (magMinus1 << 1) | bit
        }

        let magnitude = magMinus1 + 1
        return sign == 1 ? -magnitude : magnitude
    }
}

// MARK: - HT Block Encoder

/// HTJ2K block encoder implementing the FBCOT algorithm.
///
/// The HT block encoder encodes wavelet coefficients in a code-block using
/// the Fast Block Coder with Optimized Truncation. It produces coded data
/// consisting of interleaved MEL, VLC, and MagSgn streams.
///
/// The encoder processes coefficients in stripe-based order (4 rows at a time)
/// and produces a single cleanup pass, optionally followed by SigProp and
/// MagRef refinement passes.
///
/// Example:
/// ```swift
/// let encoder = HTBlockEncoder(width: 32, height: 32, subband: .hh)
/// let result = try encoder.encode(coefficients: coeffs, bitPlane: 7)
/// ```
struct HTBlockEncoder: Sendable {
    /// The width of the code-block.
    let width: Int

    /// The height of the code-block.
    let height: Int

    /// The subband this code-block belongs to.
    let subband: J2KSubband

    /// Creates a new HT block encoder.
    ///
    /// - Parameters:
    ///   - width: The code-block width in samples.
    ///   - height: The code-block height in samples.
    ///   - subband: The wavelet subband.
    init(width: Int, height: Int, subband: J2KSubband) {
        self.width = width
        self.height = height
        self.subband = subband
    }

    /// Encodes wavelet coefficients using the HT cleanup pass.
    ///
    /// The cleanup pass is the primary coding pass in HTJ2K. It processes all
    /// samples in the code-block and produces significance, sign, and magnitude
    /// information using the MEL, VLC, and MagSgn coding primitives.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - bitPlane: The most significant bit-plane to encode.
    /// - Returns: An ``HTEncodedBlock`` containing the coded data and metadata.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCleanup(coefficients: [Int], bitPlane: Int) throws -> HTEncodedBlock {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "Coefficient count \(coefficients.count) does not match block size \(width)x\(height)"
            )
        }

        var mel = HTMELCoder()
        var vlc = HTVLCCoder()
        var magsgn = HTMagSgnCoder()

        // Process in 4-row stripes (standard JPEG 2000 stripe ordering)
        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in stride(from: 0, to: width, by: 2) {
                let pairWidth = min(2, width - col)

                // Process pairs of columns within the stripe
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

                    // Encode significance via MEL and VLC
                    let pattern = sig0 | (sig1 << 1)
                    mel.encode(bit: (pattern == 0) ? 0 : 1)
                    vlc.encodeSignificance(pattern: pattern)

                    // Encode magnitude/sign for significant samples
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

        // Flush all coding primitives
        let melData = mel.flush()
        let vlcData = vlc.flush()
        let magsgnData = magsgn.flush()

        // Combine into a single coded data buffer:
        // [MEL data | MagSgn data | VLC data (reversed)]
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

    /// Encodes the HT significance propagation pass.
    ///
    /// This pass encodes samples that become newly significant at a refinement
    /// bit-plane. It is used for progressive quality improvement.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - significanceState: Current significance state for each sample.
    ///   - bitPlane: The bit-plane for this refinement pass.
    /// - Returns: The encoded data for the SigProp pass.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeSigProp(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError("Coefficient count mismatch")
        }
        guard significanceState.count == width * height else {
            throw J2KError.encodingError("Significance state count mismatch")
        }

        var output: [UInt8] = []
        var bitBuffer: UInt8 = 0
        var bitPos = 0

        // Process samples in stripe order
        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    // Skip already-significant samples
                    if significanceState[idx] {
                        continue
                    }

                    // Check if any neighbor is significant (significance propagation)
                    if hasSignificantNeighbor(x: col, y: y, state: significanceState) {
                        let coeff = coefficients[idx]
                        let bit = (abs(coeff) >> bitPlane) & 1

                        bitBuffer |= UInt8(bit) << bitPos
                        bitPos += 1

                        if bit != 0 {
                            // Also encode sign
                            let sign: UInt8 = coeff < 0 ? 1 : 0
                            bitBuffer |= sign << bitPos
                            bitPos += 1
                        }

                        if bitPos >= 8 {
                            output.append(bitBuffer)
                            bitBuffer = 0
                            bitPos = 0
                        }
                    }
                }
            }
        }

        // Flush remaining bits
        if bitPos > 0 {
            output.append(bitBuffer)
        }

        return Data(output)
    }

    /// Encodes the HT magnitude refinement pass.
    ///
    /// This pass refines the magnitude of already-significant samples by
    /// encoding additional bit-planes.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - significanceState: Current significance state for each sample.
    ///   - bitPlane: The bit-plane for this refinement pass.
    /// - Returns: The encoded data for the MagRef pass.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeMagRef(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError("Coefficient count mismatch")
        }

        var output: [UInt8] = []
        var bitBuffer: UInt8 = 0
        var bitPos = 0

        // Process in stripe order — only already-significant samples
        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    if significanceState[idx] {
                        let coeff = coefficients[idx]
                        let bit = (abs(coeff) >> bitPlane) & 1

                        bitBuffer |= UInt8(bit) << bitPos
                        bitPos += 1

                        if bitPos >= 8 {
                            output.append(bitBuffer)
                            bitBuffer = 0
                            bitPos = 0
                        }
                    }
                }
            }
        }

        // Flush remaining bits
        if bitPos > 0 {
            output.append(bitBuffer)
        }

        return Data(output)
    }

    /// Checks whether any neighbor of the given sample is significant.
    private func hasSignificantNeighbor(x: Int, y: Int, state: [Bool]) -> Bool {
        let offsets = [(-1, -1), (0, -1), (1, -1),
                       (-1, 0),           (1, 0),
                       (-1, 1),  (0, 1),  (1, 1)]
        for (dx, dy) in offsets {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                if state[ny * width + nx] {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - HT Block Decoder

/// HTJ2K block decoder implementing the FBCOT decoding algorithm.
///
/// The HT block decoder decodes wavelet coefficients from coded data produced
/// by the HT block encoder. It reverses the MEL, VLC, and MagSgn coding to
/// reconstruct the original wavelet coefficients.
///
/// Example:
/// ```swift
/// let decoder = HTBlockDecoder(width: 32, height: 32, subband: .hh)
/// let coefficients = try decoder.decodeCleanup(from: encodedBlock)
/// ```
struct HTBlockDecoder: Sendable {
    /// The width of the code-block.
    let width: Int

    /// The height of the code-block.
    let height: Int

    /// The subband this code-block belongs to.
    let subband: J2KSubband

    /// Creates a new HT block decoder.
    ///
    /// - Parameters:
    ///   - width: The code-block width in samples.
    ///   - height: The code-block height in samples.
    ///   - subband: The wavelet subband.
    init(width: Int, height: Int, subband: J2KSubband) {
        self.width = width
        self.height = height
        self.subband = subband
    }

    /// Decodes the HT cleanup pass.
    ///
    /// - Parameter block: The encoded block data.
    /// - Returns: The decoded wavelet coefficients in raster order.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeCleanup(from block: HTEncodedBlock) throws -> [Int] {
        guard block.passType == .htCleanup else {
            throw J2KError.decodingError("Expected HT cleanup pass, got \(block.passType)")
        }

        var coefficients = [Int](repeating: 0, count: width * height)
        let data = block.codedData

        // Split the coded data into the three streams
        let melEnd = block.melLength
        let magsgnEnd = melEnd + block.magsgnLength

        guard melEnd <= data.count && magsgnEnd <= data.count else {
            throw J2KError.decodingError("Invalid stream lengths in HT encoded block")
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

        // Decode in the same stripe order as encoding
        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in stride(from: 0, to: width, by: 2) {
                let pairWidth = min(2, width - col)

                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let x0 = col

                    // Decode MEL decision (any significant?)
                    let melDecision = try mel.decode(from: &melReader)

                    var pattern = 0
                    if melDecision != 0 || melReader.bytesRemaining == 0 {
                        // Decode VLC significance pattern
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

    /// Applies the HT significance propagation pass to refine coefficients.
    ///
    /// - Parameters:
    ///   - coefficients: The current coefficient values (modified in-place via return).
    ///   - sigPropData: The SigProp encoded data.
    ///   - significanceState: Current significance state (modified via return).
    ///   - bitPlane: The bit-plane for this refinement pass.
    /// - Returns: A tuple of updated coefficients and significance state.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeSigProp(
        coefficients: [Int],
        sigPropData: Data,
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> (coefficients: [Int], significanceState: [Bool]) {
        var coeffs = coefficients
        var sigState = significanceState
        var reader = J2KBitReader(data: sigPropData)

        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    if sigState[idx] {
                        continue
                    }

                    if hasSignificantNeighbor(x: col, y: y, state: sigState) {
                        guard reader.bytesRemaining > 0 else { break }
                        let bit = try reader.readBit()
                        if bit {
                            let sign = try reader.readBit()
                            let magnitude = 1 << bitPlane
                            coeffs[idx] = sign ? -magnitude : magnitude
                            sigState[idx] = true
                        }
                    }
                }
            }
        }

        return (coeffs, sigState)
    }

    /// Applies the HT magnitude refinement pass.
    ///
    /// - Parameters:
    ///   - coefficients: The current coefficient values.
    ///   - magRefData: The MagRef encoded data.
    ///   - significanceState: Current significance state.
    ///   - bitPlane: The bit-plane for refinement.
    /// - Returns: The updated coefficients.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeMagRef(
        coefficients: [Int],
        magRefData: Data,
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> [Int] {
        var coeffs = coefficients
        var reader = J2KBitReader(data: magRefData)

        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    if significanceState[idx] {
                        guard reader.bytesRemaining > 0 else { break }
                        let bit = try reader.readBit()
                        if bit {
                            let refinement = 1 << bitPlane
                            if coeffs[idx] > 0 {
                                coeffs[idx] |= refinement
                            } else {
                                coeffs[idx] = -(abs(coeffs[idx]) | refinement)
                            }
                        }
                    }
                }
            }
        }

        return coeffs
    }

    /// Checks whether any neighbor of the given sample is significant.
    private func hasSignificantNeighbor(x: Int, y: Int, state: [Bool]) -> Bool {
        let offsets = [(-1, -1), (0, -1), (1, -1),
                       (-1, 0),           (1, 0),
                       (-1, 1),  (0, 1),  (1, 1)]
        for (dx, dy) in offsets {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                if state[ny * width + nx] {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Encoded Block

/// Represents an HTJ2K-encoded code-block.
///
/// Contains the coded data and metadata from an HT block encoding operation,
/// including the lengths of the individual coding primitive streams.
struct HTEncodedBlock: Sendable {
    /// The combined coded data (MEL + MagSgn + reversed VLC).
    let codedData: Data

    /// The type of coding pass that produced this data.
    let passType: HTCodingPassType

    /// The length of the MEL stream in bytes.
    let melLength: Int

    /// The length of the VLC stream in bytes.
    let vlcLength: Int

    /// The length of the MagSgn stream in bytes.
    let magsgnLength: Int

    /// The bit-plane at which encoding was performed.
    let bitPlane: Int

    /// The code-block width.
    let width: Int

    /// The code-block height.
    let height: Int

    /// Creates a new HT encoded block.
    ///
    /// - Parameters:
    ///   - codedData: The combined coded data.
    ///   - passType: The coding pass type.
    ///   - melLength: Length of the MEL stream.
    ///   - vlcLength: Length of the VLC stream.
    ///   - magsgnLength: Length of the MagSgn stream.
    ///   - bitPlane: The encoded bit-plane.
    ///   - width: The code-block width.
    ///   - height: The code-block height.
    init(
        codedData: Data,
        passType: HTCodingPassType,
        melLength: Int,
        vlcLength: Int,
        magsgnLength: Int,
        bitPlane: Int,
        width: Int,
        height: Int
    ) {
        self.codedData = codedData
        self.passType = passType
        self.melLength = melLength
        self.vlcLength = vlcLength
        self.magsgnLength = magsgnLength
        self.bitPlane = bitPlane
        self.width = width
        self.height = height
    }
}
