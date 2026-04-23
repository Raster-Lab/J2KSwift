// J2KHTBlockDecoderPart15.swift
// ISO/IEC 15444-15 cleanup-pass codeblock decoder (scalar, 32-bit).
//
// Reference implementation that mirrors the encoder (M5b) step-for-
// step. Rather than porting OpenJPH's fast 1024-entry decoder
// lookup, this decoder walks the cleanup-pass tuple by tuple and
// matches the next VLC bits against the source codebook (table0.h /
// table1.h) by linear search — O(n) per quad but simple to verify
// against the encoder. OpenJPH's fast tables are a further
// optimization that can replace this once cross-codec validation
// passes (M7).

import Foundation

/// Forward bit reader for the MEL stream (shared with the M2
/// decoder). Re-exported here as a thin alias to keep the
/// block-decoder's API self-contained.
public enum HTBlockDecoderPart15 {

    /// Decode a Part-15 codeblock produced by
    /// `HTBlockEncoderPart15.encode` followed by
    /// `HTBlockLayoutPart15.assemble`. Returns the reconstructed
    /// `width * height` coefficient array in OpenJPH sign-magnitude
    /// convention (bit 31 = sign, magnitude in bits below `p`).
    public static func decode(
        block: [UInt8],
        width: Int,
        height: Int,
        missingMSBs: Int
    ) throws -> [UInt32] {
        guard let parsed = HTBlockLayoutPart15.parse(block: block) else {
            throw HTBlockDecoderPart15Error.malformedBlock
        }
        let magsgnBytes = Array(parsed.magsgn)
        let melVlcBytes = Array(parsed.melVlc)
        let scup = parsed.scup

        // MEL reads forward from the start of the MEL+VLC region.
        // VLC reads backward from the end (after the Scup bytes).
        // For the reverse-VLC reader we need a forward bit reader
        // starting at the end of the block and progressing toward
        // the front — we materialize the VLC bit stream by reading
        // bits LSB-first from `block[lcup-2]`'s high nibble then
        // back through earlier bytes.
        //
        // Because my reference decoder doesn't need tight buffer
        // management, I rematerialize both streams as `[UInt8]` and
        // parse linearly.

        var melDec = HTMELDecoderPart15(bytes: melVlcBytes)
        var vlcReader = VLCReverseReader(melVlcBytes: melVlcBytes, scup: scup)
        var magsgnDec = HTMagSgnDecoderPart15(bytes: magsgnBytes)

        let p = UInt32(30 - missingMSBs)

        var coefs = [UInt32](repeating: 0, count: width * height)

        // Build "decoder lookups" from the source tables on demand:
        // given (c_q, next bits, is-initial-row), find the matching
        // `(rho, u_off, cwd_len, e_k, e_1)`.
        func lookup(
            c_q: Int,
            bits: Int,
            initialLine: Bool
        ) -> (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int) {
            let src = initialLine ? vlcSrcTable0 : vlcSrcTable1
            var best: VLCSrc? = nil
            for e in src where e.c_q == c_q {
                let mask = (1 << e.cwd_len) - 1
                if (bits & mask) == e.cwd {
                    // Last match wins (mirrors OpenJPH's
                    // overwrite-on-collision decoder-table build).
                    best = e
                }
            }
            guard let b = best else {
                preconditionFailure(
                    "no VLC match for c_q=\(c_q) bits=0x\(String(bits, radix: 16))")
            }
            return (b.rho, b.u_off, b.cwd_len, b.e_k, b.e_1)
        }

        /// MEL run state: repeatedly produce events via the run
        /// packing convention.
        var melRun = melDec.nextRun()
        func nextMELEvent() -> Bool {
            melRun -= 2
            let isOne = (melRun == -1)
            if melRun < 0 {
                melRun = melDec.nextRun()
            }
            return isOne
        }

        // Decode a U-value from the reverse VLC stream. Mirrors
        // OpenJPH's per-quad UVLC prefix+suffix layout. For a pair
        // of quads, OpenJPH emits in the order:
        //    pre_q0, pre_q1, suf_q0, suf_q1
        // with u_q0 > 2 && u_q1 > 2 using tbl[u-2] entries, the
        // (>2, >0) asymmetric case using tbl[u_q0] + 1-bit for q1,
        // and the default using tbl[u_q0] + tbl[u_q1].
        //
        // Decoding requires knowing which branch was taken — which
        // depends on u_off flags from the VLC tuple plus MEL events
        // (for initial row when both u_offs are set).
        func decodeUVLCPair(
            u_off0: Int,
            u_off1: Int,
            initialRow: Bool
        ) -> (Int, Int) {
            if u_off0 == 0 && u_off1 == 0 {
                return (0, 0)
            }
            // Read u-prefix unary for each active u_off. Prefix is
            // 1..3 bits depending on value: "1" = 1, "01" = 2,
            // "001" = 3, "000" = 4.
            func readPrefix() -> Int {
                let b0 = Int(vlcReader.read(count: 1))
                if b0 == 1 { return 1 }
                let b1 = Int(vlcReader.read(count: 1))
                if b1 == 1 { return 2 }
                let b2 = Int(vlcReader.read(count: 1))
                if b2 == 1 { return 3 }
                return 4
            }
            if initialRow && u_off0 == 1 && u_off1 == 1 {
                // MEL event tells us whether u_q0 > 2 || u_q1 > 2.
                let melEvent = nextMELEvent()
                if melEvent {
                    // min(u_q0, u_q1) > 2: both use tbl[u-2] layout.
                    let pre0 = readPrefix()
                    let pre1 = readPrefix()
                    let u0 = decodeFromPrefix(pre0) + 2
                    let u1 = decodeFromPrefix(pre1) + 2
                    return (u0, u1)
                } else {
                    // At least one <= 2.
                    let pre0 = readPrefix()
                    let u0Candidate = decodeFromPrefix(pre0)
                    if u0Candidate > 2 {
                        // u_q0 > 2, u_q1 ∈ {1, 2} — 1-bit for q1.
                        let bit = Int(vlcReader.read(count: 1))
                        return (u0Candidate, bit + 1)
                    }
                    let pre1 = readPrefix()
                    let u1Candidate = decodeFromPrefix(pre1)
                    return (u0Candidate, u1Candidate)
                }
            } else {
                // Non-initial row or u_off = 0 for one quad.
                let u0: Int
                let u1: Int
                if u_off0 != 0 {
                    let p0 = readPrefix()
                    u0 = decodeFromPrefix(p0)
                } else {
                    u0 = 0
                }
                if u_off1 != 0 {
                    let p1 = readPrefix()
                    u1 = decodeFromPrefix(p1)
                } else {
                    u1 = 0
                }
                return (u0, u1)
            }
        }

        // Prefix-to-u decoding for u ∈ 0..4: prefix length 1..4
        // maps to 1..4. (u = 0 yields no prefix, handled by caller
        // via u_off == 0.)
        func decodeFromPrefix(_ len: Int) -> Int {
            // OpenJPH's uvlc_tbl encoding: u=1 → "1", u=2 → "10",
            // u=3 → "100" + "0" suffix, u=4 → "100" + "1" suffix.
            // So the 3-bit "001" prefix means "u ∈ {3, 4}" and we
            // read 1 more suffix bit; otherwise u == len directly.
            if len == 3 {
                let suf = Int(vlcReader.read(count: 1))
                return 3 + suf
            }
            if len == 4 {
                // 4-bit "0001" prefix → u ∈ {5..36} via 5-bit suffix
                // + optional 4-bit extension for u >= 33.
                let suf = Int(vlcReader.read(count: 5))
                if suf < 28 {
                    return 5 + suf
                }
                let ext = Int(vlcReader.read(count: 4))
                return 33 + (suf - 28) + 4 * ext
            }
            return len
        }

        // Write the decoded coefficient at (x, y), reconstructing
        // sign-magnitude value from (eQ, m-bit MagSgn payload).
        func placeSample(
            x: Int, y: Int,
            eQ: Int,
            m: Int
        ) {
            guard x < width, y < height else { return }
            // Build payload high bits from eQ; low m bits from
            // MagSgn stream. OpenJPH encoder wrote
            // `s = (μ_p - 2) + sign` (i.e. 2μ_p minus 2 with sign
            // added). The decoder inverts:
            //   mag = 2^eQ ... 2^(eQ+1) range, i.e. μ_p - 1 has top
            //   bit at position eQ-1.
            //
            // Concretely: payload (m bits) = (μ_p - 1) low bits |
            // sign. The high bits of (μ_p - 1) equal (1 << (eQ-1))
            // when eQ > 0.
            let payload = magsgnDec.read(count: m)
            // Reconstruct (μ_p - 1): the eQ-th bit (counting from 1)
            // is always 1 for significant samples with exponent eQ;
            // the bits below encode the remainder.
            //
            // m = Uq - e_bit; when e_bit == 1 the remaining bits are
            // below the implicit top bit (position eQ-1).
            //
            // Full (μ_p - 1) = top_bit | (payload low m bits,
            // shifted so the sign bit is in the LSB).
            let sign = UInt32(payload & 1)
            let mag = (payload >> 1) | (UInt32(1) << (eQ - 1))
            // Coefficient in OpenJPH convention: value = mag << p;
            // sign bit in MSB.
            var coef: UInt32 = (mag + 1) << p
            if sign != 0 {
                coef |= 0x8000_0000
            }
            coefs[y * width + x] = coef
        }

        // --- Decode quad row y = 0 (initial line using table0) ---

        var c_q0 = 0
        var y = 0
        var x = 0
        while x < width {
            let head = Int(vlcReader.peek(maxBits: 7))
            let look0 = lookup(c_q: c_q0, bits: head, initialLine: true)
            _ = vlcReader.read(count: look0.cwd_len)
            let rho0 = look0.rho
            // If c_q0 == 0 we have a MEL event telling us whether
            // rho is zero or non-zero. If MEL says "zero", override
            // the VLC-derived rho to 0.
            var effectiveRho0 = rho0
            if c_q0 == 0 {
                let melSig = nextMELEvent()
                if !melSig { effectiveRho0 = 0 }
            }
            // The `emb` bits are read AFTER the codeword when
            // u_off == 1, embedded in the MagSgn magnitude stream?
            // No — in OpenJPH the embedded e_k/e_1 are implicit from
            // the VLC entry selection. The encoder emitted
            // eps = which-of-4-samples-had-max-exponent bits in the
            // VLC codeword; the decoder recovers them from the
            // tuple's e_k + e_1 fields.

            // Compute next quad's context from this quad's rho.
            let rho1Ctx = (effectiveRho0 >> 1) | (effectiveRho0 & 1)

            // Second quad of the pair (if fits in block width).
            var effectiveRho1 = 0
            var look1 = (rho: 0, u_off: 0, cwd_len: 0, e_k: 0, e_1: 0)
            if x + 2 < width {
                let c_q1 = rho1Ctx
                let head1 = Int(vlcReader.peek(maxBits: 7))
                look1 = lookup(c_q: c_q1, bits: head1, initialLine: true)
                _ = vlcReader.read(count: look1.cwd_len)
                effectiveRho1 = look1.rho
                if c_q1 == 0 {
                    let melSig = nextMELEvent()
                    if !melSig { effectiveRho1 = 0 }
                }
            }

            let (u_q0, u_q1) = decodeUVLCPair(
                u_off0: look0.u_off, u_off1: look1.u_off, initialRow: true)
            let Uq0 = u_q0 + 1
            let Uq1 = u_q1 + 1

            // Read MagSgn bits for each significant sample in the
            // first quad.
            readQuadSamples(baseX: x, baseY: 0,
                            rho: effectiveRho0, Uq: Uq0,
                            e_k: look0.e_k, e_1: look0.e_1,
                            magsgnDec: &magsgnDec,
                            coefs: &coefs, width: width, height: height,
                            p: p)
            if x + 2 < width {
                readQuadSamples(baseX: x + 2, baseY: 0,
                                rho: effectiveRho1, Uq: Uq1,
                                e_k: look1.e_k, e_1: look1.e_1,
                                magsgnDec: &magsgnDec,
                                coefs: &coefs, width: width, height: height,
                                p: p)
            }

            c_q0 = (effectiveRho1 >> 1) | (effectiveRho1 & 1)
            x += 4
        }

        // Subsequent rows: implementation parked pending M5c
        // refinement — the initial-row logic above validates the
        // encoder/decoder interface for height <= 2. Blocks taller
        // than 2 are flagged as unsupported by this reference
        // decoder.
        _ = y
        if height > 2 {
            throw HTBlockDecoderPart15Error.heightGreaterThanOneRowUnsupported
        }

        return coefs
    }

    /// Read magnitude-sign bits for up to 4 samples of a quad,
    /// placing reconstructed coefficients into `coefs`.
    fileprivate static func readQuadSamples(
        baseX: Int, baseY: Int,
        rho: Int, Uq: Int,
        e_k: Int, e_1: Int,
        magsgnDec: inout HTMagSgnDecoderPart15,
        coefs: inout [UInt32], width: Int, height: Int,
        p: UInt32
    ) {
        let offsets = [(0, 0), (0, 1), (1, 0), (1, 1)]
        for i in 0..<4 {
            let bit = (rho >> i) & 1
            if bit == 0 { continue }
            // e_bit = 1 when this sample's e_q hit e_qmax (indicated
            // by e_k bit at position i, with e_1 bit at position i
            // telling us the value of the sample's top bit).
            let eBit = (e_k >> i) & 1
            let m = Uq - eBit
            let payload = magsgnDec.read(count: m)
            // Reconstruct magnitude and sign from payload. The
            // encoder packed `s = 2*(μ_p - 1) + sign` masked to m
            // bits. To undo: magnitude high bit is implicit (from
            // e_qmax); sign is payload LSB.
            let sign = UInt32(payload & 1)
            let magLow = payload >> 1
            // When the sample's e_q equals e_qmax (e_bit == 1), the
            // implicit top bit lies at position (Uq - 1); otherwise
            // the encoder emitted full Uq bits so no implicit.
            let topBit: UInt32 = (eBit == 1) ? (UInt32(1) << (Uq - 1)) : 0
            let mag = magLow | topBit
            // Also honor the per-sample e_1 bit: when set, the
            // sample's e_q equals e_qmax so the payload's high bit
            // is also implicit. The (e_k, e_1) selection by the
            // encoder guarantees these bits match.
            _ = e_1
            let (dx, dy) = offsets[i]
            let xi = baseX + dx
            let yi = baseY + dy
            if xi >= width || yi >= height { continue }
            var coef = (mag + 1) << p
            if sign != 0 { coef |= 0x8000_0000 }
            coefs[yi * width + xi] = coef
        }
    }
}

public enum HTBlockDecoderPart15Error: Error {
    case malformedBlock
    case heightGreaterThanOneRowUnsupported
}

/// Forward bit reader over the reverse VLC stream. Reads LSB-first
/// from `melVlcBytes[scup - 2]`'s high nibble, then through earlier
/// bytes. Skips the last byte (which holds Scup's high 8 bits).
fileprivate struct VLCReverseReader {
    private let melVlcBytes: [UInt8]
    private let scup: Int
    private var byteIdx: Int  // index within melVlcBytes, walks down
    private var tmp: UInt64 = 0
    private var bits: Int = 0
    private var unstuff: Bool = false

    init(melVlcBytes: [UInt8], scup: Int) {
        self.melVlcBytes = melVlcBytes
        self.scup = scup
        // Start at scup - 2 (the second-to-last byte of the
        // MEL+VLC region). The last byte is Scup's high 8 bits.
        self.byteIdx = scup - 2
        // Load the high nibble of melVlcBytes[scup-2] as the first
        // 4 bits (LSB-first).
        if byteIdx >= 0 {
            let b = melVlcBytes[byteIdx]
            let highNibble = UInt64(b >> 4)
            let t = ((highNibble & 0x7) == 0x7) ? UInt64(1) : UInt64(0)
            let val = highNibble & (0xF >> t)
            tmp = val
            bits = Int(4 - t)
            unstuff = val > 0x8
            byteIdx -= 1
        }
    }

    private mutating func refill() {
        while bits <= 32 {
            let byte: UInt8
            if byteIdx >= 0 {
                byte = melVlcBytes[byteIdx]
                byteIdx -= 1
            } else {
                byte = 0
            }
            let dBits = 8 - (unstuff ? 1 : 0)
            let mask: UInt8 = UInt8(0xFF) >> (unstuff ? 1 : 0)
            let value = UInt64(byte & mask)
            tmp |= value << bits
            bits += dBits
            unstuff = (byte > 0x8F)
        }
    }

    mutating func peek(maxBits: Int) -> UInt64 {
        if bits < maxBits { refill() }
        let m: UInt64 = (maxBits >= 64) ? ~UInt64(0) : ((UInt64(1) << maxBits) - 1)
        return tmp & m
    }

    mutating func read(count: Int) -> UInt64 {
        if bits < count { refill() }
        let m: UInt64 = (count >= 64) ? ~UInt64(0) : ((UInt64(1) << count) - 1)
        let v = tmp & m
        tmp >>= count
        bits -= count
        return v
    }
}
