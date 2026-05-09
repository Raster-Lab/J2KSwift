// J2KHTMagSgnCoderConformant.swift
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
public struct HTMagSgnEncoderConformant {
    public private(set) var bytes: [UInt8] = []
    private var tmp: UInt32 = 0
    private var usedBits: Int = 0
    private var maxBits: Int = 8

    public init() {}

    /// v5.38 M8: reset to the post-`init()` state, **keeping** the
    /// `bytes` array's existing capacity. Used by the per-chunk
    /// reusable-buffer path in `applyEntropyCodingHTJ2KFused` so the
    /// 2300+ blocks of a DX 12 MP encode don't each allocate fresh
    /// internal buffers. Bit-exact equivalent of `var enc = HTMagSgnEncoderConformant()`.
    public mutating func reset() {
        bytes.removeAll(keepingCapacity: true)
        tmp = 0
        usedBits = 0
        maxBits = 8
    }

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
public struct HTMagSgnDecoderConformant {
    /// **v7.4 batched refill gate.** Default `true` — rigorous A/B
    /// benchmarking measured **+3.70 ms (5.9 %) DX 2800×2288 in-
    /// process decode improvement** for the SWAR-batched 4-byte
    /// refill vs the scalar byte-by-byte reference, clearing v7.4's
    /// 3 ms threshold for default-on enablement
    /// (`V740NeonRefillDXWallBenchmark`). Bit-exact-equivalent to
    /// scalar per `V740NeonRefillParityTests` (11/11 sweeps pass:
    /// all-zero, all-FF, alternating, FF at every batch position,
    /// 32 random seeds, stream-exhaust padding from FF-end, empty,
    /// tiny, sub-batch-size streams).
    ///
    /// Mechanism: 4-byte unaligned UInt32 load + SWAR
    /// (SIMD-within-a-register) 0xFF-detect. The common case (no
    /// 0xFF in the batch + no carried unstuff — ~99 % of batches at
    /// the corpus-typical FF-density of ~0.4 %) reduces to one
    /// 32-bit load and one OR-into-accumulator with no per-byte
    /// conditional. The slow fallback handles 0xFF-bearing batches
    /// scalar-byte-by-byte, identical to the scalar reference.
    ///
    /// Per-call microbench gain (V740NeonRefillMicrobench, median
    /// of 5):
    ///
    ///     width      | scalar ns | batched ns | speedup
    ///      3 bits    |   3.54    |   3.38     | 1.05×
    ///      7 bits    |   3.90    |   3.80     | 1.03×
    ///     14 bits    |   5.70    |   4.96     | 1.15×
    ///     32 bits    |  10.09    |   6.77     | 1.49×
    ///
    /// Tests can flip to `false` to verify the scalar path or
    /// reproduce A/B numbers.
    nonisolated(unsafe) public static var neonRefillEnabled: Bool = true

    private let bytes: ArraySlice<UInt8>
    private let bytesStart: Int
    private let bytesEnd: Int
    private var readIndex: Int   // position relative to bytesStart
    private var tmp: UInt64 = 0
    private var bits: Int = 0
    private var unstuff: Bool = false

    public init(bytes: [UInt8]) {
        self.init(bytes: bytes[...])
    }

    /// Slice-based init avoids the per-block `Array(parsed.magsgn)` copy
    /// that the legacy `[UInt8]` overload would force on the caller.
    public init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.bytesStart = bytes.startIndex
        self.bytesEnd = bytes.endIndex
        self.readIndex = 0
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
    ///
    /// Dispatches to `refillBatched` (v7.4 SIMD prototype) or
    /// `refillScalar` (v7.3 production path) based on the
    /// `neonRefillEnabled` static flag. Both paths produce
    /// bit-identical output by construction; the batched path is
    /// strictly an optimisation attempt with the same byte-by-byte
    /// semantics on its slow-fallback branch.
    @inline(__always)
    mutating func refill() {
        if HTMagSgnDecoderConformant.neonRefillEnabled {
            refillBatched()
        } else {
            refillScalar()
        }
    }

    /// **Scalar reference path** — v7.3.0 production refill.
    /// One byte at a time; promotes the slice to a raw pointer
    /// inside `withUnsafeBufferPointer` to avoid per-byte Array
    /// bounds checks (Phase 1b shape).
    @inline(__always)
    mutating func refillScalar() {
        var rIdx = readIndex
        var t = tmp
        var b = bits
        var u = unstuff

        bytes.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                let count = ptr.count
                while b <= 32 && rIdx < count {
                    let byte = base[rIdx]
                    rIdx += 1
                    let dBits = 8 - (u ? 1 : 0)
                    let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                    t |= UInt64(byte & mask) << b
                    b += dBits
                    u = (byte == 0xFF)
                }
            }
            // End-of-stream 0xFF padding.
            while b <= 32 {
                let byte: UInt8 = 0xFF
                let dBits = 8 - (u ? 1 : 0)
                let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                t |= UInt64(byte & mask) << b
                b += dBits
                u = (byte == 0xFF)
            }
        }

        readIndex = rIdx
        tmp = t
        bits = b
        unstuff = u
    }

    /// **v7.4 batched-refill prototype.** Processes 4 bytes per
    /// iteration when ≥ 4 stream bytes remain. Uses a SWAR
    /// (SIMD-within-a-register) 0xFF-detect to fast-path the common
    /// case (no 0xFF in the batch + no carried unstuff) — that case
    /// reduces to one unaligned UInt32 load, one OR-into-accumulator,
    /// and a constant 32-bit advance, with no per-byte conditional.
    /// Falls back to scalar byte-at-a-time inside the batch when
    /// 0xFF is detected or carried unstuff is set.
    ///
    /// Bit-exact equivalent of `refillScalar` by construction —
    /// the slow-fallback branch IS the scalar byte loop on those
    /// 4 bytes; the fast branch only fires when the SWAR test
    /// guarantees the same outcome (no unstuffing applied to any
    /// of the 4 bytes).
    @inline(__always)
    mutating func refillBatched() {
        var rIdx = readIndex
        var t = tmp
        var b = bits
        var u = unstuff

        bytes.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                let count = ptr.count

                // 4-byte batched fast path. b ∈ [0, 31] on entry
                // (caller gates on bits < count with count ≤ 32);
                // adding 32 bits gives b ≤ 63, fits in UInt64
                // accumulator.
                while b <= 32 && rIdx + 4 <= count {
                    // Unaligned 32-bit load from rIdx.
                    let p32 = UnsafeRawPointer(base.advanced(by: rIdx))
                        .loadUnaligned(as: UInt32.self)
                    // SWAR zero-byte detect on (p32 ^ 0xFFFFFFFF):
                    // each lane in `inv` becomes (byte ^ 0xFF). A
                    // byte is 0xFF iff its `inv` lane is 0. The
                    // standard SWAR-zero test produces a non-zero
                    // result iff any byte equals 0xFF.
                    let inv = p32 ^ 0xFFFFFFFF
                    let hasZero = (inv &- 0x01010101) & ~inv & 0x80808080
                    let anyFF = hasZero != 0

                    if !anyFF && !u {
                        // Fast path — none of the 4 bytes are 0xFF
                        // and no unstuff carried in. Each byte
                        // contributes its full 8 bits; no masking,
                        // no per-byte branching. The whole batch
                        // becomes one unaligned 32-bit load + one
                        // OR-into-tmp at the current bit offset.
                        t |= UInt64(p32) << b
                        b += 32
                        rIdx += 4
                        // u remains false
                    } else {
                        // Slow path — at least one 0xFF in the
                        // batch or carried unstuff. Process the 4
                        // bytes byte-by-byte (identical body to
                        // `refillScalar`'s inner loop).
                        var k = 0
                        while k < 4 {
                            let byte = base[rIdx]
                            rIdx += 1
                            let dBits = 8 - (u ? 1 : 0)
                            let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                            t |= UInt64(byte & mask) << b
                            b += dBits
                            u = (byte == 0xFF)
                            k += 1
                            // Early-out if we've over-filled bits;
                            // the outer `while b <= 32` condition
                            // would also exit, but that defers the
                            // check to the next iteration after
                            // consuming all 4 bytes.
                            if b > 32 { break }
                        }
                    }
                }

                // Tail: byte-at-a-time for remaining stream.
                while b <= 32 && rIdx < count {
                    let byte = base[rIdx]
                    rIdx += 1
                    let dBits = 8 - (u ? 1 : 0)
                    let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                    t |= UInt64(byte & mask) << b
                    b += dBits
                    u = (byte == 0xFF)
                }
            }
            // End-of-stream 0xFF padding.
            while b <= 32 {
                let byte: UInt8 = 0xFF
                let dBits = 8 - (u ? 1 : 0)
                let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                t |= UInt64(byte & mask) << b
                b += dBits
                u = (byte == 0xFF)
            }
        }

        readIndex = rIdx
        tmp = t
        bits = b
        unstuff = u
    }
}

// MARK: - Round-trip helper

/// High-level round-trip helpers for testing. `encodeBits` concatenates
/// a list of `(codeword, length)` pairs into a MagSgn byte stream;
/// `decodeBits` reads the same `(length)` widths back.
public enum HTMagSgnCoderConformant {
    public static func encodeBits(_ items: [(value: UInt32, bits: Int)]) -> [UInt8] {
        var encoder = HTMagSgnEncoderConformant()
        for item in items {
            encoder.encode(codeword: item.value, count: item.bits)
        }
        return encoder.finish()
    }

    public static func decodeBits(_ bytes: [UInt8], widths: [Int]) -> [UInt32] {
        var decoder = HTMagSgnDecoderConformant(bytes: bytes)
        var out = [UInt32]()
        out.reserveCapacity(widths.count)
        for w in widths {
            out.append(decoder.read(count: w))
        }
        return out
    }
}
