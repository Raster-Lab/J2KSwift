// J2KHTMagSgnCoderPart15.swift
// ISO/IEC 15444-15 MagSgn (magnitude-and-sign) stream coder.
//
// Ports OpenJPH 0.26's `ms_struct` encoder (`ojph_block_encoder.cpp`)
// and `frwd_struct64` decoder (`ojph_block_decoder64.cpp`). Scalar.
//
// The MagSgn stream is a forward-growing byte stream carrying the
// low-order magnitude + sign bits for every significant sample in a
// codeblock. The layout is:
//
// - bits are packed LSB-first into bytes (the first sample's bits
//   occupy the low-order bits of the first output byte);
// - after any emitted `0xFF` byte, the following byte's high bit is
//   reserved as a 0 stuff bit — so the decoder can always recognise
//   marker-segment escapes;
// - termination flushes the final partial byte padded with 1-bits;
//   if that flushed byte would be `0xFF` it is dropped instead (the
//   decoder substitutes 0xFF when it runs off the end of the stream,
//   so the trailing byte is implicit).
//
// This coder *does not* compute the neighborhood predictor itself —
// the U-value and epsilon derivations live in the cleanup-pass
// orchestrator (M5). It is purely the bit-packing transport layer
// for the magnitude/sign bits the cleanup pass has already computed.

import Foundation

// MARK: - Encoder

/// MagSgn forward bit emitter. Bits are packed LSB-first. After each
/// `0xFF` byte, the next byte reserves its high bit as a 0 stuff bit.
public struct HTMagSgnEncoderPart15 {
    public private(set) var bytes: [UInt8] = []
    private var tmp: UInt32 = 0
    private var usedBits: Int = 0
    private var maxBits: Int = 8

    public init() {}

    /// Emit the low-order `count` bits of `codeword`, LSB-first.
    public mutating func encode(codeword: UInt32, count: Int) {
        var cwd = codeword
        var len = count
        while len > 0 {
            let take = min(maxBits - usedBits, len)
            let mask: UInt32 = (take >= 32) ? ~UInt32(0) : ((UInt32(1) << take) - 1)
            tmp |= (cwd & mask) << usedBits
            usedBits += take
            cwd >>= take
            len -= take
            if usedBits >= maxBits {
                let byte = UInt8(tmp & 0xFF)
                bytes.append(byte)
                maxBits = (byte == 0xFF) ? 7 : 8
                tmp = 0
                usedBits = 0
            }
        }
    }

    /// Flush the final partial byte. Pads with 1-bits; if the padded
    /// byte is `0xFF` it is dropped (decoder feeds 0xFF when
    /// exhausted, so the trailing byte is implicit). Also handles the
    /// edge case where termination leaves a reserved-stuff-bit slot
    /// empty: the `pos--` rollback from `ms_terminate`.
    public mutating func finish() -> [UInt8] {
        if usedBits != 0 {
            let padBits = maxBits - usedBits
            let padMask: UInt32 = (padBits >= 32) ? ~UInt32(0)
                                                  : ((UInt32(1) << padBits) - 1)
            tmp |= padMask << usedBits
            let byte = UInt8(tmp & 0xFF)
            if byte != 0xFF {
                bytes.append(byte)
            }
            tmp = 0
            usedBits = 0
            maxBits = 8
        } else if maxBits == 7 {
            // ms_terminate: a pending reserved stuff-bit slot with no
            // real bits to follow means we over-committed one byte
            // position; roll it back.
            bytes.removeLast()
            maxBits = 8
        }
        return bytes
    }
}

// MARK: - Decoder

/// MagSgn forward bit reader. Bits are consumed LSB-first. Every
/// byte that follows a `0xFF` byte contributes only 7 bits (its high
/// bit is a reserved stuff bit). When the byte stream is exhausted,
/// `0xFF` is fed — matching OpenJPH's `frwd_read<X=0xFF>` convention.
public struct HTMagSgnDecoderPart15 {
    private let bytes: [UInt8]
    private var readIndex: Int = 0
    private var tmp: UInt64 = 0
    private var bits: Int = 0
    private var unstuff: Bool = false

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Read `count` bits (LSB-first) from the stream.
    public mutating func read(count: Int) -> UInt32 {
        precondition(count <= 32, "MagSgn read width > 32")
        if bits < count {
            refill()
        }
        let mask: UInt64 = (count >= 64) ? ~UInt64(0) : ((UInt64(1) << count) - 1)
        let v = UInt32(tmp & mask)
        tmp >>= count
        bits -= count
        return v
    }

    /// Refill the bit buffer so at least 32 bits are available (or
    /// stream-exhaust padding of 0xFF has been fed in).
    private mutating func refill() {
        while bits <= 32 {
            let byte: UInt8
            if readIndex < bytes.count {
                byte = bytes[readIndex]
                readIndex += 1
            } else {
                byte = 0xFF
            }
            let dBits = 8 - (unstuff ? 1 : 0)
            let mask: UInt8 = UInt8(0xFF) >> (unstuff ? 1 : 0)
            let value = UInt64(byte & mask)
            tmp |= value << bits
            bits += dBits
            unstuff = (byte == 0xFF)
        }
    }
}

// MARK: - Round-trip helper

/// High-level round-trip helpers for testing. `encodeBits` concatenates
/// a list of `(codeword, length)` pairs into a MagSgn byte stream;
/// `decodeBits` reads the same `(length)` widths back.
public enum HTMagSgnCoderPart15 {
    public static func encodeBits(_ items: [(value: UInt32, bits: Int)]) -> [UInt8] {
        var encoder = HTMagSgnEncoderPart15()
        for item in items {
            encoder.encode(codeword: item.value, count: item.bits)
        }
        return encoder.finish()
    }

    public static func decodeBits(_ bytes: [UInt8], widths: [Int]) -> [UInt32] {
        var decoder = HTMagSgnDecoderPart15(bytes: bytes)
        var out = [UInt32]()
        out.reserveCapacity(widths.count)
        for w in widths {
            out.append(decoder.read(count: w))
        }
        return out
    }
}
