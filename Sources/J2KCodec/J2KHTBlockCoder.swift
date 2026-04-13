//
// J2KHTBlockCoder.swift
// J2KSwift
//
/// # HTJ2K Block Coder
///
/// Implementation of the FBCOT (Fast Block Coder with Optimised Truncation) algorithm
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

// MARK: - Fast Bit Writer

/// High-throughput bit writer using a 64-bit word accumulator.
///
/// Replaces the per-bit `emitBit()` + per-byte `buffer.append()` pattern
/// with bulk word-level writes. The 64-bit accumulator can hold up to 56 bits
/// before flushing, allowing multi-bit operations without per-byte branches.
///
/// Pre-allocates the output buffer to worst-case size, eliminating dynamic
/// array growth during encoding.
struct HTFastBitWriter: Sendable {
    /// Pre-allocated output buffer.
    private var buffer: [UInt8]

    /// Current write position in the buffer.
    private var pos: Int = 0

    /// 64-bit bit accumulator — bits are packed MSB-first from bit 63 down.
    private var accum: UInt64 = 0

    /// Number of valid bits in the accumulator (0..56).
    private var bits: Int = 0

    /// Creates a fast bit writer with a pre-allocated buffer.
    ///
    /// - Parameter capacity: Maximum number of bytes the output can contain.
    init(capacity: Int) {
        buffer = [UInt8](repeating: 0, count: capacity)
    }

    /// Emits 1 to 32 bits from the MSB side of `value`.
    ///
    /// - Parameters:
    ///   - value: The bits to emit (right-aligned, MSB first).
    ///   - count: Number of bits to emit (1..32).
    @inline(__always)
    mutating func emitBits(_ value: Int, count: Int) {
        // Shift value into the top of accum, just below existing bits
        accum |= UInt64(value & ((1 << count) - 1)) << (64 - bits - count)
        bits += count
        // Flush complete bytes when accumulator has ≥ 8 bits
        while bits >= 8 {
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum <<= 8
            bits -= 8
        }
    }

    /// Emits a single bit.
    @inline(__always)
    mutating func emitBit(_ bit: Int) {
        accum |= UInt64(bit & 1) << (63 - bits)
        bits += 1
        if bits >= 8 {
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum <<= 8
            bits -= 8
        }
    }

    /// Flushes any remaining bits (zero-padded) and returns the output as Data.
    mutating func flush() -> Data {
        if bits > 0 {
            // Pad to byte boundary
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum = 0
            bits = 0
        }
        return Data(buffer[0..<pos])
    }

    /// Returns the number of bytes written so far (excluding partial byte).
    var byteCount: Int { pos + (bits > 0 ? 1 : 0) }

    /// Resets the writer for reuse without reallocating the buffer.
    ///
    /// The existing buffer is kept if large enough; only the write position
    /// and accumulator are cleared. If `capacity` exceeds the current buffer
    /// size, the buffer is grown.
    ///
    /// - Parameter capacity: The minimum buffer capacity needed.
    @inline(__always)
    mutating func reset(capacity: Int) {
        if buffer.count < capacity {
            buffer = [UInt8](repeating: 0, count: capacity)
        }
        pos = 0
        accum = 0
        bits = 0
    }

    /// Flushes remaining bits and copies output directly to a destination pointer.
    ///
    /// Avoids creating an intermediate `Data` object — the output bytes are
    /// written directly to `dest`, which must have room for at least `byteCount`
    /// bytes.
    ///
    /// - Parameter dest: Destination pointer with room for at least `byteCount` bytes.
    /// - Returns: The number of bytes written.
    @inline(__always)
    @discardableResult
    mutating func flushTo(_ dest: UnsafeMutablePointer<UInt8>) -> Int {
        if bits > 0 {
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum = 0
            bits = 0
        }
        buffer.withUnsafeBufferPointer { src in
            dest.update(from: src.baseAddress!, count: pos)
        }
        return pos
    }

    /// Flushes remaining bits and copies output in reversed order to a destination.
    ///
    /// Used for VLC data which is stored reversed in the HT coded data format.
    ///
    /// - Parameter dest: Destination pointer with room for at least `byteCount` bytes.
    /// - Returns: The number of bytes written.
    @inline(__always)
    @discardableResult
    mutating func flushToReversed(_ dest: UnsafeMutablePointer<UInt8>) -> Int {
        if bits > 0 {
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum = 0
            bits = 0
        }
        buffer.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            for i in 0..<pos {
                dest[i] = base[pos - 1 - i]
            }
        }
        return pos
    }

    /// Flushes remaining bits and appends the output directly to a Data buffer.
    ///
    /// More efficient than `flush()` when combining multiple writers into a larger
    /// buffer — avoids creating an intermediate Data object per writer.
    ///
    /// - Parameter data: The Data buffer to append output bytes to.
    /// - Returns: The number of bytes appended.
    @inline(__always)
    @discardableResult
    mutating func flushAppending(to data: inout Data) -> Int {
        if bits > 0 {
            buffer[pos] = UInt8((accum >> 56) & 0xFF)
            pos += 1
            accum = 0
            bits = 0
        }
        buffer.withUnsafeBufferPointer { ptr in
            data.append(ptr.baseAddress!, count: pos)
        }
        return pos
    }
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

    /// Whether the next decode call should return 1 (significant).
    ///
    /// Set after consuming a terminated run of zeros — the significant
    /// decision that caused the run termination is delivered on the next call.
    private var pendingSignificant: Bool = false

    /// Current run-length threshold (number of zeros to emit a 0 MEL bit).
    private var threshold: Int = 0

    /// MEL state index for adaptive threshold selection.
    private var stateIndex: Int = 0

    /// High-throughput bit writer for MEL output.
    private var writer: HTFastBitWriter

    /// Bit accumulator for partial byte during decoding.
    private var bitBuffer: UInt32 = 0

    /// Number of valid bits in the bit accumulator (decode only).
    private var bitCount: Int = 0

    /// MEL threshold table for adaptive run-length selection.
    ///
    /// Each entry is a power-of-2 run threshold: 2^t[i].
    private static let thresholdTable: [Int] = [
        0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5, 6, 7, 8
    ]

    /// Creates a new MEL coder.
    ///
    /// - Parameter capacity: Pre-allocated output buffer size in bytes.
    init(capacity: Int = 256) {
        writer = HTFastBitWriter(capacity: capacity)
    }

    /// Resets the MEL coder for reuse without reallocating the buffer.
    @inline(__always)
    mutating func reset(capacity: Int) {
        run = 0
        pendingSignificant = false
        threshold = 0
        stateIndex = 0
        bitBuffer = 0
        bitCount = 0
        writer.reset(capacity: capacity)
    }

    /// Encodes a single context decision (0 = insignificant, 1 = significant).
    ///
    /// - Parameter bit: The context decision bit.
    @inline(__always)
    mutating func encode(bit: Int) {
        if bit == 0 {
            run += 1
            let limit = 1 << Self.thresholdTable[stateIndex]
            if run >= limit {
                writer.emitBit(0)
                run = 0
                if stateIndex < Self.thresholdTable.count - 1 {
                    stateIndex += 1
                }
            }
        } else {
            writer.emitBit(1)
            let remainingBits = Self.thresholdTable[stateIndex]
            // Emit the run count using `remainingBits` bits in one call
            if remainingBits > 0 {
                writer.emitBits(run, count: remainingBits)
            }
            run = 0
            if stateIndex > 0 {
                stateIndex -= 1
            }
        }
    }

    /// The number of output bytes (including any partial byte in the accumulator).
    var byteCount: Int { writer.byteCount }

    /// Flushes any remaining data in the MEL coder.
    ///
    /// - Returns: The MEL-encoded byte stream.
    mutating func flush() -> Data {
        // Do NOT emit a run-completion bit for a partial trailing run.
        // The decoder handles an exhausted MEL reader by falling back to VLC,
        // which correctly returns pattern 0 (neither significant) for the
        // trailing insignificant pairs.
        return writer.flush()
    }

    /// Flushes and copies output directly to a destination pointer.
    @inline(__always)
    @discardableResult
    mutating func flushTo(_ dest: UnsafeMutablePointer<UInt8>) -> Int {
        writer.flushTo(dest)
    }

    /// Decodes a single context decision from MEL-encoded data.
    ///
    /// A MEL "1" bit signals a terminated run: `runLength` insignificant pairs
    /// followed by one significant pair. The decoder delivers `runLength` zeros
    /// then one "1". The `pendingSignificant` flag tracks the deferred "1".
    ///
    /// - Parameter reader: The bit reader positioned at MEL data.
    /// - Returns: The decoded context decision (0 or 1).
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    mutating func decode(from reader: inout J2KBitReader) throws -> Int {
        // Consume remaining zeros from a run BEFORE delivering
        // the pending significant decision. A terminated MEL run
        // encodes N zeros followed by 1 significant — the run zeros
        // must all be delivered before the trailing significant.
        if run > 0 {
            run -= 1
            return 0
        }

        // Deliver the deferred significant decision after all run zeros
        if pendingSignificant {
            pendingSignificant = false
            return 1
        }

        guard reader.bytesRemaining > 0 || bitCount > 0 else {
            return 0
        }

        let bit = try readBit(from: &reader)
        if bit == 0 {
            // Complete run of `limit` insignificant pairs
            let limit = 1 << Self.thresholdTable[stateIndex]
            run = limit - 1  // this call consumes 1; remaining = limit-1
            if stateIndex < Self.thresholdTable.count - 1 {
                stateIndex += 1
            }
            return 0
        } else {
            // Terminated run: `runLength` zeros then 1 significant
            let remainingBits = Self.thresholdTable[stateIndex]
            var runLength = 0
            for _ in 0..<remainingBits {
                let b = try readBit(from: &reader)
                runLength = (runLength << 1) | b
            }
            if stateIndex > 0 {
                stateIndex -= 1
            }
            if runLength > 0 {
                run = runLength - 1  // this call consumes 1 zero
                pendingSignificant = true  // deliver "1" after the zeros
                return 0
            }
            return 1  // immediate significant (no preceding zeros)
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
    /// High-throughput bit writer for VLC output.
    private var writer: HTFastBitWriter

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
    ///
    /// - Parameter capacity: Pre-allocated output buffer size in bytes.
    init(capacity: Int = 256) {
        writer = HTFastBitWriter(capacity: capacity)
    }

    /// Resets the VLC coder for reuse without reallocating the buffer.
    @inline(__always)
    mutating func reset(capacity: Int) {
        writer.reset(capacity: capacity)
    }

    /// Encodes a significance pattern for a pair of samples.
    ///
    /// - Parameter pattern: A 2-bit significance pattern (0-3).
    @inline(__always)
    mutating func encodeSignificance(pattern: Int) {
        let clampedPattern = pattern & 0x03
        let entry = Self.vlcTable[clampedPattern]
        writer.emitBits(Int(entry.code), count: entry.length)
    }

    /// Encodes a sign bit (0 = positive, 1 = negative).
    ///
    /// - Parameter sign: The sign bit.
    @inline(__always)
    mutating func encodeSign(_ sign: Int) {
        writer.emitBit(sign & 1)
    }

    /// The number of output bytes (including any partial byte in the accumulator).
    var byteCount: Int { writer.byteCount }

    /// Flushes the VLC coder and returns the encoded data.
    ///
    /// - Returns: The VLC-encoded byte stream.
    mutating func flush() -> Data {
        return writer.flush()
    }

    /// Flushes and copies output in reversed order directly to a destination.
    @inline(__always)
    @discardableResult
    mutating func flushToReversed(_ dest: UnsafeMutablePointer<UInt8>) -> Int {
        writer.flushToReversed(dest)
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
    /// High-throughput bit writer for MagSgn output.
    private var writer: HTFastBitWriter

    /// Creates a new MagSgn coder.
    ///
    /// - Parameter capacity: Pre-allocated output buffer size in bytes.
    init(capacity: Int = 1024) {
        writer = HTFastBitWriter(capacity: capacity)
    }

    /// Resets the MagSgn coder for reuse without reallocating the buffer.
    @inline(__always)
    mutating func reset(capacity: Int) {
        writer.reset(capacity: capacity)
    }

    /// Encodes the magnitude and sign of a significant coefficient.
    ///
    /// Uses bulk bit emission: packs sign + lower magnitude bits into a single
    /// value and emits them in one `emitBits` call, avoiding per-bit function
    /// call overhead.
    ///
    /// - Parameters:
    ///   - magnitude: The absolute value of the coefficient (must be > 0).
    ///   - sign: The sign bit (0 = positive, 1 = negative).
    ///   - bitPlane: The current bit-plane being encoded.
    @inline(__always)
    mutating func encode(magnitude: Int, sign: Int, bitPlane: Int) {
        guard magnitude > 0 else { return }

        // The significance bit (bit at bitPlane) is already communicated via
        // VLC/MEL, so MagSgn encodes: [sign | lowerBits] where lowerBits =
        // magnitude - (1 << bitPlane), fitting in exactly `bitPlane` bits.
        let lowerBits = magnitude - (1 << bitPlane)
        let totalBits = 1 + bitPlane  // sign + magnitude bits
        // Pack sign into MSB, lower bits below
        let packed = ((sign & 1) << bitPlane) | lowerBits
        writer.emitBits(packed, count: totalBits)
    }

    /// The number of output bytes (including any partial byte in the accumulator).
    var byteCount: Int { writer.byteCount }

    /// Flushes the MagSgn coder and returns the encoded data.
    ///
    /// - Returns: The MagSgn-encoded byte stream.
    mutating func flush() -> Data {
        return writer.flush()
    }

    /// Flushes and copies output directly to a destination pointer.
    @inline(__always)
    @discardableResult
    mutating func flushTo(_ dest: UnsafeMutablePointer<UInt8>) -> Int {
        writer.flushTo(dest)
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

        // Read magnitude bits below the significance bit-plane.
        // These represent (magnitude - (1 << bitPlane)).
        let numBits = max(0, bitPlane)
        var lowerBits = 0
        for _ in 0..<numBits {
            let bit = try reader.readBit() ? 1 : 0
            lowerBits = (lowerBits << 1) | bit
        }

        let magnitude = (1 << bitPlane) + lowerBits
        return sign == 1 ? -magnitude : magnitude
    }
}

// MARK: - HT Block Encoder

/// HTJ2K block encoder implementing the FBCOT algorithm.
///
/// The HT block encoder encodes wavelet coefficients in a code-block using
/// the Fast Block Coder with Optimised Truncation. It produces coded data
/// consisting of interleaved MEL, VLC, and MagSgn streams.
///
/// The encoder processes coefficients in stripe-based order (4 rows at a time)
/// and produces a single cleanup pass, optionally followed by fused
/// SigProp+MagRef refinement passes.
///
/// Performance optimizations:
/// - 64-bit word-level bit accumulators in all coding primitives
/// - Pre-allocated output buffers (no dynamic array growth)
/// - Bulk MagSgn emission (sign + magnitude in one `emitBits` call)
/// - VLC data reversed in-place (no `Data(reversed())` copy)
/// - Fused SigProp + MagRef into single scan per bit-plane
/// - UInt64-packed significance bitfield (8× denser than `[Bool]`)
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

    /// Encodes wavelet coefficients using the HT cleanup pass (Int32 primary path).
    ///
    /// The cleanup pass is the primary coding pass in HTJ2K. It processes all
    /// samples in the code-block and produces significance, sign, and magnitude
    /// information using the MEL, VLC, and MagSgn coding primitives.
    ///
    /// This overload accepts `[Int32]` directly, avoiding a redundant copy when
    /// coefficients are already stored as `Int32` in the encoder pipeline.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - bitPlane: The most significant bit-plane to encode.
    /// - Returns: A tuple of the encoded block, significance state, packed significance bitfield, and absolute magnitudes.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCleanup(coefficients: [Int32], bitPlane: Int) throws -> (block: HTEncodedBlock, significanceState: [Bool], sigPacked: [UInt64], absMags: [Int32]) {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "Coefficient count \(coefficients.count) does not match block size \(width)x\(height)"
            )
        }

        let count = coefficients.count
        let bp32 = Int32(bitPlane)

        // Pre-compute absolute magnitudes using SIMD4<Int32> vectorisation
        // (fits in a single 128-bit NEON register). Sign bits are NOT stored
        // separately — they are read directly from the coefficient array in the
        // encoding loop, eliminating one array allocation per block.
        // Significance bits are packed into UInt64 words (64 samples per word)
        // for 8× density vs [Bool] and bulk bitwise operations in refinement.
        var absMags = [Int32](repeating: 0, count: count)
        let sigWordCount = (count + 63) / 64
        var sigPacked = [UInt64](repeating: 0, count: sigWordCount)

        coefficients.withUnsafeBufferPointer { srcPtr in
            absMags.withUnsafeMutableBufferPointer { magPtr in
                guard let src = srcPtr.baseAddress,
                      let mag = magPtr.baseAddress else { return }

                let simdCount = count / 4

                for i in 0..<simdCount {
                    let offset = i &* 4
                    let v = SIMD4<Int32>(
                        src[offset], src[offset &+ 1],
                        src[offset &+ 2], src[offset &+ 3]
                    )

                    // Absolute value
                    let negative = v .< SIMD4<Int32>.zero
                    let absV = v.replacing(
                        with: SIMD4<Int32>.zero &- v, where: negative
                    )

                    mag[offset] = absV[0]; mag[offset &+ 1] = absV[1]
                    mag[offset &+ 2] = absV[2]; mag[offset &+ 3] = absV[3]

                    // Pack significance into UInt64 bitfield
                    let shifted = absV &>> SIMD4<Int32>(repeating: bp32)
                    let masked = shifted & SIMD4<Int32>(repeating: 1)
                    for lane in 0..<4 {
                        if masked[lane] != 0 {
                            let idx = offset + lane
                            sigPacked[idx >> 6] |= 1 << (idx & 63)
                        }
                    }
                }

                // Scalar remainder
                let remStart = simdCount &* 4
                for i in remStart..<count {
                    let coeff = src[i]
                    let absVal = coeff < 0 ? (0 &- coeff) : coeff
                    mag[i] = absVal
                    if (absVal >> bp32) & 1 != 0 {
                        sigPacked[i >> 6] |= 1 << (i & 63)
                    }
                }
            }
        }

        // Worst-case output sizes per coding primitive:
        // MEL: ~1 bit per sample pair + run overhead ≈ count/8 bytes
        // VLC: 3 bits per significant pair ≈ count/4 bytes
        // MagSgn: (1 + bitPlane) bits per significant sample ≈ count * (bitPlane+1) / 8
        let maxMelBytes = max(16, count / 4)
        let maxVlcBytes = max(16, count / 2)
        let maxMagsgnBytes = max(16, count * (bitPlane + 2) / 8)

        var mel = HTMELCoder(capacity: maxMelBytes)
        var vlc = HTVLCCoder(capacity: maxVlcBytes)
        var magsgn = HTMagSgnCoder(capacity: maxMagsgnBytes)

        // Process in 4-row stripes (standard JPEG 2000 stripe ordering).
        // Uses unsafe pointer access to eliminate bounds checking in the hot loop.
        // Sign bits are read directly from the coefficient array, avoiding the
        // separate signBits array allocation.
        let numStripes = (height + 3) / 4
        sigPacked.withUnsafeBufferPointer { sigPtr in
            absMags.withUnsafeBufferPointer { magPtr in
                coefficients.withUnsafeBufferPointer { coefPtr in
                    let sigBase = sigPtr.baseAddress!
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        for col in stride(from: 0, to: width, by: 2) {
                            let pairWidth = min(2, width - col)

                            for row in 0..<stripeHeight {
                                let y = stripe * 4 + row
                                let idx0 = y * width + col

                                let sig0 = Int((sigBase[idx0 >> 6] >> (idx0 & 63)) & 1)

                                var sig1 = 0
                                if pairWidth > 1 {
                                    let idx1 = idx0 + 1
                                    sig1 = Int((sigBase[idx1 >> 6] >> (idx1 & 63)) & 1)
                                }

                                // Encode significance via MEL and VLC
                                let pattern = sig0 | (sig1 << 1)
                                mel.encode(bit: (pattern == 0) ? 0 : 1)
                                if pattern != 0 {
                                    vlc.encodeSignificance(pattern: pattern)
                                }

                                // Encode magnitude/sign for significant samples (bulk emission)
                                if sig0 != 0 {
                                    magsgn.encode(magnitude: Int(magBase[idx0]), sign: coefBase[idx0] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                                if sig1 != 0 {
                                    let idx1 = idx0 + 1
                                    magsgn.encode(magnitude: Int(magBase[idx1]), sign: coefBase[idx1] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Zero-copy data assembly: flush each coder directly into the combined
        // output buffer, avoiding 3 intermediate Data allocations and the
        // separate VLC reversal loop. The format is:
        // [melLen:2 | vlcLen:2 | magsgnLen:2 | MEL data | MagSgn data | VLC data (reversed)]
        let melBytes = mel.byteCount
        let vlcBytes = vlc.byteCount
        let magsgnBytes = magsgn.byteCount
        let totalSize = 6 + melBytes + magsgnBytes + vlcBytes
        var codedData = Data(count: totalSize)
        codedData.withUnsafeMutableBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            // Stream length header (big-endian UInt16 each)
            ptr[0] = UInt8((melBytes >> 8) & 0xFF)
            ptr[1] = UInt8(melBytes & 0xFF)
            ptr[2] = UInt8((vlcBytes >> 8) & 0xFF)
            ptr[3] = UInt8(vlcBytes & 0xFF)
            ptr[4] = UInt8((magsgnBytes >> 8) & 0xFF)
            ptr[5] = UInt8(magsgnBytes & 0xFF)
            // Copy streams directly into output (no intermediate Data objects)
            mel.flushTo(ptr + 6)
            magsgn.flushTo(ptr + 6 + melBytes)
            vlc.flushToReversed(ptr + 6 + melBytes + magsgnBytes)
        }

        let block = HTEncodedBlock(
            codedData: codedData,
            passType: .htCleanup,
            melLength: melBytes,
            vlcLength: vlcBytes,
            magsgnLength: magsgnBytes,
            bitPlane: bitPlane,
            width: width,
            height: height
        )

        // Derive Bool significanceState from sigPacked for callers that need it
        // (e.g. direct-API tests). The pipeline uses sigPacked directly.
        let significanceState = (0..<count).map { i in
            (sigPacked[i >> 6] >> UInt64(i & 63)) & 1 != 0
        }
        return (block: block, significanceState: significanceState, sigPacked: sigPacked, absMags: absMags)
    }

    /// Encodes wavelet coefficients using the HT cleanup pass (convenience for `[Int]` callers).
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - bitPlane: The most significant bit-plane to encode.
    /// - Returns: An ``HTEncodedBlock`` containing the coded data and metadata.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCleanup(coefficients: [Int], bitPlane: Int) throws -> HTEncodedBlock {
        let (block, _, _, _) = try encodeCleanup(coefficients: coefficients.map { Int32($0) }, bitPlane: bitPlane)
        return block
    }

    /// Encodes the HT cleanup pass using caller-provided reusable arrays.
    ///
    /// This variant avoids per-block allocation of `absMags` and `sigPacked`
    /// arrays. The caller pre-allocates these once per thread and passes them
    /// in for repeated use across code-blocks.
    ///
    /// The provided arrays must be at least `width * height` elements (absMags)
    /// and `(width * height + 63) / 64` words (sigPacked). The caller must
    /// clear `sigPacked` before each call.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - bitPlane: The most significant bit-plane to encode.
    ///   - absMags: Pre-allocated absolute magnitude array (overwritten).
    ///   - sigPacked: Pre-allocated and zeroed significance bitfield (overwritten).
    /// - Returns: The encoded cleanup pass block.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCleanupReusing(
        coefficients: [Int32],
        bitPlane: Int,
        absMags: inout [Int32],
        sigPacked: inout [UInt64]
    ) throws -> HTEncodedBlock {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "Coefficient count \(coefficients.count) does not match block size \(width)x\(height)"
            )
        }

        let count = coefficients.count
        let bp32 = Int32(bitPlane)

        // Compute absolute magnitudes + significance using SIMD4<Int32>
        coefficients.withUnsafeBufferPointer { srcPtr in
            absMags.withUnsafeMutableBufferPointer { magPtr in
                sigPacked.withUnsafeMutableBufferPointer { sigPtr in
                    guard let src = srcPtr.baseAddress,
                          let mag = magPtr.baseAddress,
                          let sig = sigPtr.baseAddress else { return }

                    let simdCount = count / 4
                    for i in 0..<simdCount {
                        let offset = i &* 4
                        let v = SIMD4<Int32>(
                            src[offset], src[offset &+ 1],
                            src[offset &+ 2], src[offset &+ 3]
                        )
                        let negative = v .< SIMD4<Int32>.zero
                        let absV = v.replacing(with: SIMD4<Int32>.zero &- v, where: negative)
                        mag[offset] = absV[0]; mag[offset &+ 1] = absV[1]
                        mag[offset &+ 2] = absV[2]; mag[offset &+ 3] = absV[3]

                        let shifted = absV &>> SIMD4<Int32>(repeating: bp32)
                        let masked = shifted & SIMD4<Int32>(repeating: 1)
                        for lane in 0..<4 {
                            if masked[lane] != 0 {
                                let idx = offset + lane
                                sig[idx >> 6] |= 1 << (idx & 63)
                            }
                        }
                    }
                    let remStart = simdCount &* 4
                    for i in remStart..<count {
                        let coeff = src[i]
                        let absVal = coeff < 0 ? (0 &- coeff) : coeff
                        mag[i] = absVal
                        if (absVal >> bp32) & 1 != 0 {
                            sig[i >> 6] |= 1 << (i & 63)
                        }
                    }
                }
            }
        }

        // Create fresh coders (local variables, no exclusivity conflict with arrays)
        let maxMelBytes = max(16, count / 4)
        let maxVlcBytes = max(16, count / 2)
        let maxMagsgnBytes = max(16, count * (bitPlane + 2) / 8)
        var mel = HTMELCoder(capacity: maxMelBytes)
        var vlc = HTVLCCoder(capacity: maxVlcBytes)
        var magsgn = HTMagSgnCoder(capacity: maxMagsgnBytes)

        // Process in stripe order using unsafe pointer access
        let numStripes = (height + 3) / 4
        sigPacked.withUnsafeBufferPointer { sigPtr in
            absMags.withUnsafeBufferPointer { magPtr in
                coefficients.withUnsafeBufferPointer { coefPtr in
                    let sigBase = sigPtr.baseAddress!
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        for col in stride(from: 0, to: width, by: 2) {
                            let pairWidth = min(2, width - col)
                            for row in 0..<stripeHeight {
                                let y = stripe * 4 + row
                                let idx0 = y * width + col
                                let sig0 = Int((sigBase[idx0 >> 6] >> (idx0 & 63)) & 1)
                                var sig1 = 0
                                if pairWidth > 1 {
                                    let idx1 = idx0 + 1
                                    sig1 = Int((sigBase[idx1 >> 6] >> (idx1 & 63)) & 1)
                                }
                                let pattern = sig0 | (sig1 << 1)
                                mel.encode(bit: (pattern == 0) ? 0 : 1)
                                if pattern != 0 {
                                    vlc.encodeSignificance(pattern: pattern)
                                }
                                if sig0 != 0 {
                                    magsgn.encode(magnitude: Int(magBase[idx0]), sign: coefBase[idx0] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                                if sig1 != 0 {
                                    let idx1 = idx0 + 1
                                    magsgn.encode(magnitude: Int(magBase[idx1]), sign: coefBase[idx1] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Zero-copy data assembly
        let melBytes = mel.byteCount
        let vlcBytes = vlc.byteCount
        let magsgnBytes = magsgn.byteCount
        let totalSize = 6 + melBytes + magsgnBytes + vlcBytes
        var codedData = Data(count: totalSize)
        codedData.withUnsafeMutableBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            ptr[0] = UInt8((melBytes >> 8) & 0xFF)
            ptr[1] = UInt8(melBytes & 0xFF)
            ptr[2] = UInt8((vlcBytes >> 8) & 0xFF)
            ptr[3] = UInt8(vlcBytes & 0xFF)
            ptr[4] = UInt8((magsgnBytes >> 8) & 0xFF)
            ptr[5] = UInt8(magsgnBytes & 0xFF)
            mel.flushTo(ptr + 6)
            magsgn.flushTo(ptr + 6 + melBytes)
            vlc.flushToReversed(ptr + 6 + melBytes + magsgnBytes)
        }

        return HTEncodedBlock(
            codedData: codedData,
            passType: .htCleanup,
            melLength: melBytes,
            vlcLength: vlcBytes,
            magsgnLength: magsgnBytes,
            bitPlane: bitPlane,
            width: width,
            height: height
        )
    }

    /// Encodes the HT cleanup pass using caller-provided reusable arrays and coders.
    ///
    /// This variant avoids ALL per-block allocation by reusing pre-allocated
    /// MEL, VLC, and MagSgn coders in addition to `absMags` and `sigPacked`.
    /// The coders are reset internally with appropriate capacities.
    func encodeCleanupFullyReusing(
        coefficients: [Int32],
        bitPlane: Int,
        absMags: inout [Int32],
        sigPacked: inout [UInt64],
        mel: inout HTMELCoder,
        vlc: inout HTVLCCoder,
        magsgn: inout HTMagSgnCoder
    ) throws -> HTEncodedBlock {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "Coefficient count \(coefficients.count) does not match block size \(width)x\(height)"
            )
        }

        let count = coefficients.count
        let bp32 = Int32(bitPlane)

        // Compute absolute magnitudes + significance using SIMD4<Int32>
        coefficients.withUnsafeBufferPointer { srcPtr in
            absMags.withUnsafeMutableBufferPointer { magPtr in
                sigPacked.withUnsafeMutableBufferPointer { sigPtr in
                    guard let src = srcPtr.baseAddress,
                          let mag = magPtr.baseAddress,
                          let sig = sigPtr.baseAddress else { return }

                    let simdCount = count / 4
                    for i in 0..<simdCount {
                        let offset = i &* 4
                        let v = SIMD4<Int32>(
                            src[offset], src[offset &+ 1],
                            src[offset &+ 2], src[offset &+ 3]
                        )
                        let negative = v .< SIMD4<Int32>.zero
                        let absV = v.replacing(with: SIMD4<Int32>.zero &- v, where: negative)
                        mag[offset] = absV[0]; mag[offset &+ 1] = absV[1]
                        mag[offset &+ 2] = absV[2]; mag[offset &+ 3] = absV[3]

                        let shifted = absV &>> SIMD4<Int32>(repeating: bp32)
                        let masked = shifted & SIMD4<Int32>(repeating: 1)
                        for lane in 0..<4 {
                            if masked[lane] != 0 {
                                let idx = offset + lane
                                sig[idx >> 6] |= 1 << (idx & 63)
                            }
                        }
                    }
                    let remStart = simdCount &* 4
                    for i in remStart..<count {
                        let coeff = src[i]
                        let absVal = coeff < 0 ? (0 &- coeff) : coeff
                        mag[i] = absVal
                        if (absVal >> bp32) & 1 != 0 {
                            sig[i >> 6] |= 1 << (i & 63)
                        }
                    }
                }
            }
        }

        // Reset pre-allocated coders
        let maxMelBytes = max(16, count / 4)
        let maxVlcBytes = max(16, count / 2)
        let maxMagsgnBytes = max(16, count * (bitPlane + 2) / 8)
        mel.reset(capacity: maxMelBytes)
        vlc.reset(capacity: maxVlcBytes)
        magsgn.reset(capacity: maxMagsgnBytes)

        // Process in stripe order using unsafe pointer access
        let numStripes = (height + 3) / 4
        sigPacked.withUnsafeBufferPointer { sigPtr in
            absMags.withUnsafeBufferPointer { magPtr in
                coefficients.withUnsafeBufferPointer { coefPtr in
                    let sigBase = sigPtr.baseAddress!
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        for col in stride(from: 0, to: width, by: 2) {
                            let pairWidth = min(2, width - col)
                            for row in 0..<stripeHeight {
                                let y = stripe * 4 + row
                                let idx0 = y * width + col
                                let sig0 = Int((sigBase[idx0 >> 6] >> (idx0 & 63)) & 1)
                                var sig1 = 0
                                if pairWidth > 1 {
                                    let idx1 = idx0 + 1
                                    sig1 = Int((sigBase[idx1 >> 6] >> (idx1 & 63)) & 1)
                                }
                                let pattern = sig0 | (sig1 << 1)
                                mel.encode(bit: (pattern == 0) ? 0 : 1)
                                if pattern != 0 {
                                    vlc.encodeSignificance(pattern: pattern)
                                }
                                if sig0 != 0 {
                                    magsgn.encode(magnitude: Int(magBase[idx0]), sign: coefBase[idx0] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                                if sig1 != 0 {
                                    let idx1 = idx0 + 1
                                    magsgn.encode(magnitude: Int(magBase[idx1]), sign: coefBase[idx1] < 0 ? 1 : 0, bitPlane: bitPlane)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Zero-copy data assembly
        let melBytes = mel.byteCount
        let vlcBytes = vlc.byteCount
        let magsgnBytes = magsgn.byteCount
        let totalSize = 6 + melBytes + magsgnBytes + vlcBytes
        var codedData = Data(count: totalSize)
        codedData.withUnsafeMutableBytes { buf in
            guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            ptr[0] = UInt8((melBytes >> 8) & 0xFF)
            ptr[1] = UInt8(melBytes & 0xFF)
            ptr[2] = UInt8((vlcBytes >> 8) & 0xFF)
            ptr[3] = UInt8(vlcBytes & 0xFF)
            ptr[4] = UInt8((magsgnBytes >> 8) & 0xFF)
            ptr[5] = UInt8(magsgnBytes & 0xFF)
            mel.flushTo(ptr + 6)
            magsgn.flushTo(ptr + 6 + melBytes)
            vlc.flushToReversed(ptr + 6 + melBytes + magsgnBytes)
        }

        return HTEncodedBlock(
            codedData: codedData,
            passType: .htCleanup,
            melLength: melBytes,
            vlcLength: vlcBytes,
            magsgnLength: magsgnBytes,
            bitPlane: bitPlane,
            width: width,
            height: height
        )
    }

    /// Encodes a fused SigProp + MagRef refinement pass using caller-provided
    /// reusable writers and arrays.
    ///
    /// This variant eliminates per-pass writer allocation by reusing pre-allocated
    /// writers that the caller resets between calls. It also batches MagRef bit
    /// emission per stripe column (up to 4 bits at once) to reduce per-sample
    /// function call overhead.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - absMags: Pre-computed absolute magnitudes (from cleanup).
    ///   - sigPacked: UInt64-packed significance bitfield (updated in-place).
    ///   - bitPlane: The bit-plane for this refinement pass.
    ///   - output: Data buffer to append encoded bytes to.
    ///   - sigPropWriter: Pre-allocated SigProp writer (must be reset by caller).
    ///   - magRefWriter: Pre-allocated MagRef writer (must be reset by caller).
    /// - Returns: A tuple of (sigPropBytes, magRefBytes) byte counts.
    func encodeFusedRefinementReusing(
        coefficients: [Int32],
        absMags: [Int32],
        sigPacked: inout [UInt64],
        bitPlane: Int,
        output: inout Data,
        sigPropWriter: inout HTFastBitWriter,
        magRefWriter: inout HTFastBitWriter
    ) -> (sigPropBytes: Int, magRefBytes: Int) {
        let bp32 = Int32(bitPlane)

        let numStripes = (height + 3) / 4
        absMags.withUnsafeBufferPointer { magPtr in
            coefficients.withUnsafeBufferPointer { coefPtr in
                sigPacked.withUnsafeMutableBufferPointer { sigPtr in
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!
                    let sigBase = sigPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        let baseY = stripe * 4
                        for col in 0..<width {
                            // Batch MagRef bits per stripe column: collect up to 4
                            // bits destined for the MagRef writer and emit them in
                            // one emitBits call instead of up to 4 emitBit calls.
                            var magBits = 0
                            var magCount = 0

                            for row in 0..<stripeHeight {
                                let y = baseY + row
                                let idx = y * width + col

                                let wordIdx = idx >> 6
                                let bitIdx = idx & 63
                                let isSignificant = (sigBase[wordIdx] >> bitIdx) & 1 != 0

                                if isSignificant {
                                    // Pack MSB-first: shift left and OR in new bit so
                                    // row-0's bit occupies the MSB, matching the
                                    // MSB-first emission order of emitBits.
                                    magBits = (magBits << 1) | Int((magBase[idx] >> bp32) & 1)
                                    magCount += 1
                                } else {
                                    let bit = Int((magBase[idx] >> bp32) & 1)
                                    sigPropWriter.emitBit(bit)
                                    if bit != 0 {
                                        sigPropWriter.emitBit(coefBase[idx] < 0 ? 1 : 0)
                                        sigBase[wordIdx] |= 1 << bitIdx
                                    }
                                }
                            }

                            if magCount > 0 {
                                magRefWriter.emitBits(magBits, count: magCount)
                            }
                        }
                    }
                }
            }
        }

        let sigPropBytes = sigPropWriter.flushAppending(to: &output)
        let magRefBytes = magRefWriter.flushAppending(to: &output)
        return (sigPropBytes, magRefBytes)
    }

    /// Encodes a fused SigProp + MagRef refinement pass for a single bit-plane.
    /// passes — the fused encoder produces the same byte streams, just more efficiently.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - absMags: Pre-computed absolute magnitudes.
    ///   - sigPacked: UInt64-packed significance bitfield (updated in-place).
    ///   - bitPlane: The bit-plane for this refinement pass.
    /// - Returns: A tuple of (sigPropData, magRefData) byte streams.
    func encodeFusedRefinement(
        coefficients: [Int32],
        absMags: [Int32],
        sigPacked: inout [UInt64],
        bitPlane: Int
    ) -> (sigPropData: Data, magRefData: Data) {
        let count = width * height
        let bp32 = Int32(bitPlane)
        // Worst case: 2 bits per non-significant sample (bit + sign), 1 bit per significant
        let maxBytes = max(4, (count * 2 + 7) / 8)
        var sigPropWriter = HTFastBitWriter(capacity: maxBytes)
        var magRefWriter = HTFastBitWriter(capacity: maxBytes)

        // Single scan in stripe order — fuse SigProp and MagRef.
        // Uses unsafe pointer access to eliminate bounds checking.
        let numStripes = (height + 3) / 4
        absMags.withUnsafeBufferPointer { magPtr in
            coefficients.withUnsafeBufferPointer { coefPtr in
                sigPacked.withUnsafeMutableBufferPointer { sigPtr in
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!
                    let sigBase = sigPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        for col in 0..<width {
                            for row in 0..<stripeHeight {
                                let y = stripe * 4 + row
                                let idx = y * width + col

                                let wordIdx = idx >> 6
                                let bitIdx = idx & 63
                                let isSignificant = (sigBase[wordIdx] >> bitIdx) & 1 != 0

                                if isSignificant {
                                    // MagRef: emit the bit at this bit-plane for significant samples
                                    let bit = Int((magBase[idx] >> bp32) & 1)
                                    magRefWriter.emitBit(bit)
                                } else {
                                    // SigProp: check if this sample becomes significant at this bit-plane
                                    let bit = Int((magBase[idx] >> bp32) & 1)
                                    sigPropWriter.emitBit(bit)

                                    if bit != 0 {
                                        // Also encode sign
                                        sigPropWriter.emitBit(coefBase[idx] < 0 ? 1 : 0)
                                        // Update significance in packed bitfield
                                        sigBase[wordIdx] |= 1 << bitIdx
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return (sigPropWriter.flush(), magRefWriter.flush())
    }

    /// Encodes a fused SigProp + MagRef refinement pass, appending output directly
    /// to a shared Data buffer.
    ///
    /// This variant avoids creating intermediate Data objects per pass, instead
    /// appending the encoded bytes directly to the caller's output buffer.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - absMags: Pre-computed absolute magnitudes.
    ///   - sigPacked: UInt64-packed significance bitfield (updated in-place).
    ///   - bitPlane: The bit-plane for this refinement pass.
    ///   - output: Data buffer to append encoded bytes to.
    /// - Returns: A tuple of (sigPropBytes, magRefBytes) byte counts.
    func encodeFusedRefinementDirect(
        coefficients: [Int32],
        absMags: [Int32],
        sigPacked: inout [UInt64],
        bitPlane: Int,
        output: inout Data
    ) -> (sigPropBytes: Int, magRefBytes: Int) {
        let count = width * height
        let bp32 = Int32(bitPlane)
        let maxBytes = max(4, (count * 2 + 7) / 8)
        var sigPropWriter = HTFastBitWriter(capacity: maxBytes)
        var magRefWriter = HTFastBitWriter(capacity: maxBytes)

        let numStripes = (height + 3) / 4
        absMags.withUnsafeBufferPointer { magPtr in
            coefficients.withUnsafeBufferPointer { coefPtr in
                sigPacked.withUnsafeMutableBufferPointer { sigPtr in
                    let magBase = magPtr.baseAddress!
                    let coefBase = coefPtr.baseAddress!
                    let sigBase = sigPtr.baseAddress!

                    for stripe in 0..<numStripes {
                        let stripeHeight = min(4, height - stripe * 4)
                        for col in 0..<width {
                            for row in 0..<stripeHeight {
                                let y = stripe * 4 + row
                                let idx = y * width + col

                                let wordIdx = idx >> 6
                                let bitIdx = idx & 63
                                let isSignificant = (sigBase[wordIdx] >> bitIdx) & 1 != 0

                                if isSignificant {
                                    let bit = Int((magBase[idx] >> bp32) & 1)
                                    magRefWriter.emitBit(bit)
                                } else {
                                    let bit = Int((magBase[idx] >> bp32) & 1)
                                    sigPropWriter.emitBit(bit)

                                    if bit != 0 {
                                        sigPropWriter.emitBit(coefBase[idx] < 0 ? 1 : 0)
                                        sigBase[wordIdx] |= 1 << bitIdx
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let sigPropBytes = sigPropWriter.flushAppending(to: &output)
        let magRefBytes = magRefWriter.flushAppending(to: &output)
        return (sigPropBytes, magRefBytes)
    }

    /// Encodes the HT significance propagation pass (Int32 primary path).
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
        coefficients: [Int32],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError("Coefficient count mismatch")
        }
        guard significanceState.count == width * height else {
            throw J2KError.encodingError("Significance state count mismatch")
        }

        let count = width * height
        let bp32 = Int32(bitPlane)
        let maxBytes = max(4, (count * 2 + 7) / 8)
        var writer = HTFastBitWriter(capacity: maxBytes)

        // Process ALL non-significant samples in stripe order.
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

                    let coeff = coefficients[idx]
                    let absCoeff = coeff < 0 ? (0 &- coeff) : coeff
                    let bit = Int((absCoeff >> bp32) & 1)
                    writer.emitBit(bit)

                    if bit != 0 {
                        // Also encode sign
                        writer.emitBit(coeff < 0 ? 1 : 0)
                    }
                }
            }
        }

        return writer.flush()
    }

    /// Encodes the HT significance propagation pass (convenience for `[Int]` callers).
    func encodeSigProp(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        try encodeSigProp(
            coefficients: coefficients.map { Int32($0) },
            significanceState: significanceState,
            bitPlane: bitPlane
        )
    }

    /// Encodes the HT magnitude refinement pass (Int32 primary path).
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
        coefficients: [Int32],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError("Coefficient count mismatch")
        }

        let count = width * height
        let bp32 = Int32(bitPlane)
        let maxBytes = max(4, (count + 7) / 8)
        var writer = HTFastBitWriter(capacity: maxBytes)

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
                        let absCoeff = coeff < 0 ? (0 &- coeff) : coeff
                        let bit = Int((absCoeff >> bp32) & 1)
                        writer.emitBit(bit)
                    }
                }
            }
        }

        return writer.flush()
    }

    /// Encodes the HT magnitude refinement pass (convenience for `[Int]` callers).
    func encodeMagRef(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int
    ) throws -> Data {
        try encodeMagRef(
            coefficients: coefficients.map { Int32($0) },
            significanceState: significanceState,
            bitPlane: bitPlane
        )
    }

    /// Checks whether any neighbor of the given sample is significant.
    private func hasSignificantNeighbor(x: Int, y: Int, state: [Bool]) -> Bool {
        let offsets = [(-1, -1), (0, -1), (1, -1),
                       (-1, 0), (1, 0),
                       (-1, 1), (0, 1), (1, 1)]
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

        // The coded data has a 6-byte length header:
        // [melLen:2 | vlcLen:2 | magsgnLen:2 | MEL data | MagSgn data | VLC data (reversed)]
        guard let header = HTStreamHeader.read(from: data) else {
            // Empty or trivial block — all zeros
            return coefficients
        }

        let payloadStart = data.startIndex + HTStreamHeader.size
        let melEnd = payloadStart + header.melLen
        let magsgnEnd = melEnd + header.magsgnLen

        guard melEnd <= data.endIndex && magsgnEnd <= data.endIndex
              && (magsgnEnd + header.vlcLen) <= data.endIndex else {
            throw J2KError.decodingError("Invalid stream lengths in HT encoded block")
        }

        let melData = data[payloadStart..<melEnd]
        let magsgnData = data[melEnd..<magsgnEnd]
        let vlcDataReversed = data[magsgnEnd..<(magsgnEnd + header.vlcLen)]
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
                    if melDecision != 0 {
                        // Decode VLC significance pattern only when MEL says
                        // the pair is significant. The encoder only writes VLC
                        // entries for significant pairs.
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

    /// Decodes HT-encoded code-block data from raw codestream bytes.
    ///
    /// This method is used by the main decoder pipeline to decode HT blocks
    /// that flow through the standard JPEG 2000 packet structure. The raw data
    /// contains a self-describing cleanup pass followed by optional refinement passes.
    ///
    /// The cleanup pass data includes a 6-byte header with stream lengths:
    /// `[melLen:2 | vlcLen:2 | magsgnLen:2 | MEL | MagSgn | VLC_reversed]`
    ///
    /// Refinement passes (SigProp + MagRef) follow the cleanup pass data and are
    /// delimited by `passSegmentLengths`.
    ///
    /// - Parameters:
    ///   - data: The raw code-block data from the codestream.
    ///   - passCount: Total number of coding passes.
    ///   - bitDepth: The bit depth (Kb) for this code-block.
    ///   - zeroBitPlanes: Number of zero bit-planes above the MSB.
    ///   - passSegmentLengths: Byte lengths per pass segment (optional).
    /// - Returns: The decoded wavelet coefficients as `[Int32]`.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeFromCodestream(
        data: Data,
        passCount: Int,
        bitDepth: Int,
        zeroBitPlanes: Int,
        passSegmentLengths: [Int] = []
    ) throws -> [Int32] {
        guard passCount > 0 else {
            return [Int32](repeating: 0, count: width * height)
        }

        // Determine the top bit-plane from zeroBitPlanes and bitDepth
        let topBitPlane = max(0, bitDepth - zeroBitPlanes - 1)

        // Parse the cleanup pass header to determine its length.
        // The 6-byte header encodes melLen + vlcLen + magsgnLen.
        guard let header = HTStreamHeader.read(from: data) else {
            // Trivial block with no significant coefficients
            return [Int32](repeating: 0, count: width * height)
        }

        let cleanupLen = HTStreamHeader.size + header.melLen + header.magsgnLen + header.vlcLen
        let cleanupEnd = min(data.startIndex + cleanupLen, data.endIndex)

        let cleanupData = Data(data[data.startIndex..<cleanupEnd])

        let block = HTEncodedBlock(
            codedData: cleanupData,
            passType: .htCleanup,
            melLength: header.melLen,
            vlcLength: header.vlcLen,
            magsgnLength: header.magsgnLen,
            bitPlane: topBitPlane,
            width: width,
            height: height
        )
        var coefficients = try decodeCleanup(from: block)

        // Apply refinement passes (SigProp + MagRef pairs) from the remaining data.
        // The refinement data forms a continuous bit-packed stream. When per-pass
        // segment lengths are provided, use them to split the data. Otherwise,
        // process the remaining data as one continuous reader.
        let refinementPassCount = passCount - 1
        if refinementPassCount > 0 && cleanupEnd < data.endIndex {
            var significanceState = coefficients.map { $0 != 0 }

            if !passSegmentLengths.isEmpty {
                // Per-pass segments provided — split into individual segments
                var segments: [Data] = []
                // Skip the first segment length (cleanup pass)
                var offset = data.startIndex + (passSegmentLengths.isEmpty ? 0 : passSegmentLengths[0])
                for i in 1..<passSegmentLengths.count {
                    let end = min(offset + passSegmentLengths[i], data.endIndex)
                    segments.append(Data(data[offset..<end]))
                    offset = end
                }

                var passIdx = 0
                var bp = topBitPlane - 1

                while passIdx < segments.count && bp >= 0 {
                    // Save pre-SigProp significance for MagRef (encoder uses same state)
                    let preSigPropState = significanceState
                    let sigPropResult = try decodeSigProp(
                        coefficients: coefficients,
                        sigPropData: segments[passIdx],
                        significanceState: significanceState,
                        bitPlane: bp
                    )
                    coefficients = sigPropResult.coefficients
                    passIdx += 1

                    if passIdx < segments.count {
                        // Use pre-SigProp state to match encoder
                        coefficients = try decodeMagRef(
                            coefficients: coefficients,
                            magRefData: segments[passIdx],
                            significanceState: preSigPropState,
                            bitPlane: bp
                        )
                        passIdx += 1
                    }
                    // Update significance after both passes
                    significanceState = sigPropResult.significanceState
                    bp -= 1
                }
            } else {
                // No per-pass segment lengths — read refinement from continuous stream.
                // Each SigProp/MagRef pass is independently byte-aligned (the encoder
                // flushes each pass to a byte boundary). After decoding each pass we
                // must align the reader to the next byte before reading the next pass.
                let refinementData = Data(data[cleanupEnd..<data.endIndex])
                var reader = J2KBitReader(data: refinementData)
                reader.setByteStuffing(false)
                var bp = topBitPlane - 1
                var passesDecoded = 0

                while bp >= 0 && passesDecoded < refinementPassCount && reader.bytesRemaining > 0 {
                    // SigProp pass — decode using current significance state.
                    // IMPORTANT: save pre-SigProp significance for MagRef, because
                    // the encoder uses the SAME significance state for both SigProp
                    // and MagRef at the same bit-plane.
                    let preSigPropState = significanceState
                    let sigResult = try decodeSigPropFromReader(
                        coefficients: coefficients,
                        significanceState: significanceState,
                        bitPlane: bp,
                        reader: &reader
                    )
                    coefficients = sigResult.coefficients
                    passesDecoded += 1
                    // Align to next byte boundary (skip padding from encoder flush)
                    try reader.alignToByte()

                    // MagRef pass — use pre-SigProp significance state to match
                    // the encoder, which hadn't updated significance yet.
                    if passesDecoded < refinementPassCount && reader.bytesRemaining > 0 {
                        coefficients = try decodeMagRefFromReader(
                            coefficients: coefficients,
                            significanceState: preSigPropState,
                            bitPlane: bp,
                            reader: &reader
                        )
                        passesDecoded += 1
                        try reader.alignToByte()
                    }

                    // NOW update significance state (after both passes at this bp)
                    significanceState = sigResult.significanceState
                    bp -= 1
                }
            }
        }

        // Convert Int to Int32
        return coefficients.map { Int32($0) }
    }

    // MARK: - Continuous Stream Refinement Decoders

    /// Decodes the SigProp pass from a continuous reader (no per-pass framing).
    private func decodeSigPropFromReader(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int,
        reader: inout J2KBitReader
    ) throws -> (coefficients: [Int], significanceState: [Bool]) {
        var coeffs = coefficients
        var sigState = significanceState

        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    if sigState[idx] { continue }

                    guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
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

        return (coeffs, sigState)
    }

    /// Decodes the MagRef pass from a continuous reader (no per-pass framing).
    private func decodeMagRefFromReader(
        coefficients: [Int],
        significanceState: [Bool],
        bitPlane: Int,
        reader: inout J2KBitReader
    ) throws -> [Int] {
        var coeffs = coefficients

        let numStripes = (height + 3) / 4
        for stripe in 0..<numStripes {
            let stripeHeight = min(4, height - stripe * 4)
            for col in 0..<width {
                for row in 0..<stripeHeight {
                    let y = stripe * 4 + row
                    let idx = y * width + col

                    if significanceState[idx] {
                        guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
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
                       (-1, 0), (1, 0),
                       (-1, 1), (0, 1), (1, 1)]
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

/// Parsed 6-byte stream length header from HT cleanup pass data.
///
/// Format: `[melLen:2 | vlcLen:2 | magsgnLen:2]` (big-endian UInt16 values).
private struct HTStreamHeader {
    /// Size of the header in bytes.
    static let size = 6

    /// Length of the MEL stream in bytes.
    let melLen: Int

    /// Length of the VLC stream in bytes.
    let vlcLen: Int

    /// Length of the MagSgn stream in bytes.
    let magsgnLen: Int

    /// Reads the 6-byte header from the start of `data`.
    ///
    /// - Parameter data: Data containing the header (must have at least 6 bytes).
    /// - Returns: The parsed header, or `nil` if data is too short.
    static func read(from data: Data) -> HTStreamHeader? {
        guard data.count >= size else { return nil }
        let s = data.startIndex
        let mel = Int(data[s]) << 8 | Int(data[s + 1])
        let vlc = Int(data[s + 2]) << 8 | Int(data[s + 3])
        let mag = Int(data[s + 4]) << 8 | Int(data[s + 5])
        return HTStreamHeader(melLen: mel, vlcLen: vlc, magsgnLen: mag)
    }
}

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
}
