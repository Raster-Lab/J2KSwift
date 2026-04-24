// J2KHTBlockDecoderConformant.swift
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

public enum HTBlockDecoderConformant {

    /// Decode a Part-15 codeblock produced by
    /// `HTBlockEncoderConformant.encode` + `HTBlockLayoutConformant.assemble`.
    /// Returns the reconstructed `width * height` coefficient array
    /// in OpenJPH sign-magnitude convention (bit 31 = sign, magnitude
    /// in bits below `p = 30 - missingMSBs`).
    public static func decode(
        block: [UInt8],
        width: Int,
        height: Int,
        missingMSBs: Int
    ) throws -> [UInt32] {
        guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
            throw HTBlockDecoderConformantError.malformedBlock
        }
        let magsgnBytes = Array(parsed.magsgn)
        let melVlcBytes = Array(parsed.melVlc)
        let scup = parsed.scup

        var state = DecodeState(
            melVlcBytes: melVlcBytes, scup: scup, magsgnBytes: magsgnBytes,
            width: width, height: height,
            p: UInt32(30 - missingMSBs))

        // Initial quad row (y = 0, 1) uses table0 with implicit
        // kappa = 1.
        state.decodeInitialRow()

        // Subsequent quad rows (y = 2, 4, ...) use table1. max_e
        // and c_q0 flow from eVal/cxVal buffers populated by the
        // previous row.
        var y = 2
        while y < height {
            state.decodeSubsequentRow(y: y)
            y += 2
        }

        return state.coefs
    }
}

// MARK: - Decode state machine

/// All mutable state for a codeblock decode session. Holds the three
/// stream readers, scratch buffers for inter-row context, and the
/// output coefficient array.
fileprivate struct DecodeState {
    var melDec: HTMELDecoderConformant
    var vlcReader: VLCReverseReader
    var magsgnDec: HTMagSgnDecoderConformant
    let width: Int
    let height: Int
    let p: UInt32

    /// Per-row scratch: max e_q from the bottom row of each quad in
    /// the previous row (consumed when computing max_e for subsequent
    /// rows). Sized with +2 guard slots.
    var eVal: [UInt8]
    /// Per-row scratch: rho's bottom-row bits from the previous row
    /// (feeds c_q context for subsequent rows).
    var cxVal: [UInt8]

    var coefs: [UInt32]

    /// MEL run-state: OpenJPH's packed "2*count | terminator" value.
    var melRun: Int

    init(
        melVlcBytes: [UInt8], scup: Int,
        magsgnBytes: [UInt8],
        width: Int, height: Int, p: UInt32
    ) {
        self.melDec = HTMELDecoderConformant(bytes: melVlcBytes)
        self.vlcReader = VLCReverseReader(
            melVlcBytes: melVlcBytes, scup: scup)
        self.magsgnDec = HTMagSgnDecoderConformant(bytes: magsgnBytes)
        self.width = width
        self.height = height
        self.p = p
        let guarded = ((width + 3) / 4) * 2 + 2
        self.eVal = [UInt8](repeating: 0, count: guarded)
        self.cxVal = [UInt8](repeating: 0, count: guarded)
        self.coefs = [UInt32](repeating: 0, count: width * height)
        self.melRun = self.melDec.nextRun()
    }

    mutating func nextMELEvent() -> Bool {
        melRun -= 2
        let isOne = (melRun == -1)
        if melRun < 0 {
            melRun = melDec.nextRun()
        }
        return isOne
    }

    /// Fast VLC lookup via OpenJPH's 1024-entry reverse-table
    /// (indexed by `(c_q << 7) | bits7`, packed as
    /// `e_k|e_1|rho|u_off|cwd_len`). Constant-time per codeword.
    @inline(__always)
    func lookupVLC(
        c_q: Int, bits: Int, initialLine: Bool
    ) -> (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int) {
        let tbl = initialLine
            ? vlcDecoderTable0Conformant
            : vlcDecoderTable1Conformant
        let idx = (c_q << 7) | (bits & 0x7F)
        let entry = Int(tbl[idx])
        let cwd_len = entry & 0x7
        let u_off   = (entry >> 3) & 0x1
        let rho     = (entry >> 4) & 0xF
        let e_1     = (entry >> 8) & 0xF
        let e_k     = (entry >> 12) & 0xF
        return (rho: rho, u_off: u_off, cwd_len: cwd_len, e_k: e_k, e_1: e_1)
    }

    /// Unary prefix reader for UVLC: 1→1, 01→2, 001→3, 000→4.
    mutating func readPrefix() -> Int {
        let b0 = Int(vlcReader.read(count: 1))
        if b0 == 1 { return 1 }
        let b1 = Int(vlcReader.read(count: 1))
        if b1 == 1 { return 2 }
        let b2 = Int(vlcReader.read(count: 1))
        if b2 == 1 { return 3 }
        return 4
    }

    /// Map a prefix length to the base u value, reading any
    /// additional suffix/extension bits as required.
    mutating func decodeFromPrefix(_ len: Int) -> Int {
        if len == 3 {
            let suf = Int(vlcReader.read(count: 1))
            return 3 + suf
        }
        if len == 4 {
            let suf = Int(vlcReader.read(count: 5))
            if suf < 28 { return 5 + suf }
            let ext = Int(vlcReader.read(count: 4))
            return 33 + (suf - 28) + 4 * ext
        }
        return len
    }

    /// Decode a u-value pair per OpenJPH's branch structure for the
    /// initial row (with MEL arbitration when both u_off are set).
    ///
    /// Encoder wire layout (matches every branch in
    /// `HTBlockEncoderConformant.encode` initial-row UVLC):
    /// - No-u-values branch: nothing emitted.
    /// - Both u_off=1 + MEL=1 (both u > 2 after +2 shift): `pre0, pre1,
    ///   suf0, suf1` — prefixes first, then suffixes.
    /// - Both u_off=1 + MEL=0 + u_q0 > 2: `pre0, 1-bit-for-u_q1, suf0`.
    /// - Both u_off=1 + MEL=0 + u_q0 ≤ 2: `pre0, pre1, (suf0=∅), suf1`
    ///   — u_q0 has no suffix so only u_q1's suffix is read.
    /// - One u_off: `pre, suf` for the active quad.
    mutating func decodeUVLCPairInitial(
        u_off0: Int, u_off1: Int
    ) -> (Int, Int) {
        if u_off0 == 0 && u_off1 == 0 { return (0, 0) }
        if u_off0 == 1 && u_off1 == 1 {
            let melEvent = nextMELEvent()
            if melEvent {
                let p0 = readPrefix()
                let p1 = readPrefix()
                let s0 = decodeFromPrefix(p0)
                let s1 = decodeFromPrefix(p1)
                return (s0 + 2, s1 + 2)
            }
            let p0 = readPrefix()
            // Encoder emits u_q1's 1-bit marker BEFORE suf0 when
            // u_q0 > 2 (i.e. prefix length 3 or 4). Read that bit
            // first, then let decodeFromPrefix(p0) consume suf0.
            if p0 >= 3 {
                let bit = Int(vlcReader.read(count: 1))
                let u0 = decodeFromPrefix(p0)
                return (u0, bit + 1)
            }
            // u_q0 ≤ 2 path: encoder writes `pre0, pre1, (no suf0), suf1`.
            let p1 = readPrefix()
            let u0 = decodeFromPrefix(p0)
            let u1 = decodeFromPrefix(p1)
            return (u0, u1)
        }
        // Exactly one u_off is set: encoder wrote `pre, suf` for that
        // quad; decoder reads the same in sequence.
        let u0 = (u_off0 != 0) ? decodeFromPrefix(readPrefix()) : 0
        let u1 = (u_off1 != 0) ? decodeFromPrefix(readPrefix()) : 0
        return (u0, u1)
    }

    /// Subsequent-row UVLC: encoder writes `pre0, pre1, suf0, suf1` in
    /// that order unconditionally (with the suffix slots being empty
    /// when the prefix length is 1 or 2). The decoder must read both
    /// prefixes first and only then consume the suffixes — reading
    /// prefix+suffix interleaved per quad desyncs the stream whenever
    /// the first quad has a non-empty suffix.
    mutating func decodeUVLCPairSubsequent(
        u_off0: Int, u_off1: Int
    ) -> (Int, Int) {
        let len0 = (u_off0 != 0) ? readPrefix() : 0
        let len1 = (u_off1 != 0) ? readPrefix() : 0
        let u0 = (u_off0 != 0) ? decodeFromPrefix(len0) : 0
        let u1 = (u_off1 != 0) ? decodeFromPrefix(len1) : 0
        return (u0, u1)
    }

    // MARK: - Row decoding

    mutating func decodeInitialRow() {
        var lep = 0
        var lcxp = 0
        var c_q0 = 0
        var x = 0
        while x < width {
            // When c_q=0 the encoder reads a MEL event first and
            // only emits a VLC codeword if rho is non-zero. Mirror
            // that sequence or we eat into the next token's bits.
            var rho0 = 0
            var look0: (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int)
                = (0, 0, 0, 0, 0)
            if c_q0 == 0 {
                if nextMELEvent() {
                    let head = Int(vlcReader.peek(maxBits: 7))
                    look0 = lookupVLC(c_q: c_q0, bits: head, initialLine: true)
                    _ = vlcReader.read(count: look0.cwd_len)
                    rho0 = look0.rho
                }
            } else {
                let head = Int(vlcReader.peek(maxBits: 7))
                look0 = lookupVLC(c_q: c_q0, bits: head, initialLine: true)
                _ = vlcReader.read(count: look0.cwd_len)
                rho0 = look0.rho
            }

            var rho1 = 0
            var look1: (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int)
                = (0, 0, 0, 0, 0)
            if x + 2 < width {
                let c_q1 = (rho0 >> 1) | (rho0 & 1)
                if c_q1 == 0 {
                    if nextMELEvent() {
                        let head1 = Int(vlcReader.peek(maxBits: 7))
                        look1 = lookupVLC(c_q: c_q1, bits: head1,
                                          initialLine: true)
                        _ = vlcReader.read(count: look1.cwd_len)
                        rho1 = look1.rho
                    }
                } else {
                    let head1 = Int(vlcReader.peek(maxBits: 7))
                    look1 = lookupVLC(c_q: c_q1, bits: head1, initialLine: true)
                    _ = vlcReader.read(count: look1.cwd_len)
                    rho1 = look1.rho
                }
            }

            let (u_q0, u_q1) = decodeUVLCPairInitial(
                u_off0: rho0 != 0 ? look0.u_off : 0,
                u_off1: rho1 != 0 ? look1.u_off : 0)
            let Uq0 = u_q0 + 1  // kappa = 1 for initial row
            let Uq1 = u_q1 + 1

            readQuadSamples(
                baseX: x, baseY: 0,
                rho: rho0, Uq: Uq0,
                e_k: look0.e_k, e_1: look0.e_1)
            if x + 2 < width {
                readQuadSamples(
                    baseX: x + 2, baseY: 0,
                    rho: rho1, Uq: Uq1,
                    e_k: look1.e_k, e_1: look1.e_1)
            }

            // Mirror encoder's e_q/rho recovery for bookkeeping.
            // For the decoder we can recover eQ[1] and eQ[3] from
            // whether the samples were significant and their
            // reconstructed magnitude bit widths. We use them only to
            // populate eVal/cxVal for the next row.
            let eQ0 = recoverEQ(rho: rho0, baseX: x, baseY: 0)
            eVal[lep] = max(eVal[lep], UInt8(eQ0.1)); lep += 1
            eVal[lep] = UInt8(eQ0.3)
            cxVal[lcxp] = cxVal[lcxp] | UInt8((rho0 & 2) >> 1); lcxp += 1
            cxVal[lcxp] = UInt8((rho0 & 8) >> 3)
            if x + 2 < width {
                let eQ1 = recoverEQ(rho: rho1, baseX: x + 2, baseY: 0)
                eVal[lep] = max(eVal[lep], UInt8(eQ1.1)); lep += 1
                eVal[lep] = UInt8(eQ1.3)
                cxVal[lcxp] = cxVal[lcxp] | UInt8((rho1 & 2) >> 1); lcxp += 1
                cxVal[lcxp] = UInt8((rho1 & 8) >> 3)
            }

            c_q0 = (rho1 >> 1) | (rho1 & 1)
            x += 4
        }
        if lep + 1 < eVal.count { eVal[lep + 1] = 0 }
    }

    mutating func decodeSubsequentRow(y: Int) {
        var lep = 0
        var lcxp = 0
        var maxE = max(Int(eVal[0]), Int(eVal[1])) - 1
        eVal[0] = 0
        var c_q0 = Int(cxVal[0]) + (Int(cxVal[1]) << 2)
        cxVal[0] = 0

        var x = 0
        while x < width {
            // Step 1: decode VLC (+MEL gate) for both quads of the
            // pair. c_q1 is read from cxVal AFTER the first quad's
            // lcxp update — mirrors encoder's read-then-overwrite
            // ordering.
            var rho0 = 0
            var look0: (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int)
                = (0, 0, 0, 0, 0)
            if c_q0 == 0 {
                if nextMELEvent() {
                    let head = Int(vlcReader.peek(maxBits: 7))
                    look0 = lookupVLC(c_q: c_q0, bits: head, initialLine: false)
                    _ = vlcReader.read(count: look0.cwd_len)
                    rho0 = look0.rho
                }
            } else {
                let head = Int(vlcReader.peek(maxBits: 7))
                look0 = lookupVLC(c_q: c_q0, bits: head, initialLine: false)
                _ = vlcReader.read(count: look0.cwd_len)
                rho0 = look0.rho
            }
            let kappaA = ((rho0 & (rho0 - 1)) != 0) ? max(1, maxE) : 1

            // Advance lcxp partially to discover c_q1's source slot
            // (the encoder reads c_q1 BEFORE writing its own lcxp).
            cxVal[lcxp] = cxVal[lcxp] | UInt8((rho0 & 2) >> 1); lcxp += 1
            var c_q1 = Int(cxVal[lcxp]) + (Int(cxVal[lcxp + 1]) << 2)
            cxVal[lcxp] = UInt8((rho0 & 8) >> 3)

            var rho1 = 0
            var look1: (rho: Int, u_off: Int, cwd_len: Int, e_k: Int, e_1: Int)
                = (0, 0, 0, 0, 0)
            if x + 2 < width {
                c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2)
                if c_q1 == 0 {
                    if nextMELEvent() {
                        let head1 = Int(vlcReader.peek(maxBits: 7))
                        look1 = lookupVLC(c_q: c_q1, bits: head1,
                                          initialLine: false)
                        _ = vlcReader.read(count: look1.cwd_len)
                        rho1 = look1.rho
                    }
                } else {
                    let head1 = Int(vlcReader.peek(maxBits: 7))
                    look1 = lookupVLC(c_q: c_q1, bits: head1, initialLine: false)
                    _ = vlcReader.read(count: look1.cwd_len)
                    rho1 = look1.rho
                }
                cxVal[lcxp] = cxVal[lcxp] | UInt8((rho1 & 2) >> 1); lcxp += 1
                c_q0 = Int(cxVal[lcxp]) + (Int(cxVal[lcxp + 1]) << 2)
                cxVal[lcxp] = UInt8((rho1 & 8) >> 3)
            }

            // Step 2: UVLC for the pair (encoder emits both quads'
            // u values after both VLC codewords).
            let (u_q0, u_q1) = decodeUVLCPairSubsequent(
                u_off0: rho0 != 0 ? look0.u_off : 0,
                u_off1: rho1 != 0 ? look1.u_off : 0)

            // Step 3: decode MagSgn for quad 0. Must happen before we
            // can derive eQ0 for the eVal/max_e bookkeeping that
            // feeds kappaB.
            let Uq0 = u_q0 + kappaA
            readQuadSamples(
                baseX: x, baseY: y,
                rho: rho0, Uq: Uq0,
                e_k: look0.e_k, e_1: look0.e_1)

            // Step 4: update eVal using quad 0's reconstructed e_q.
            // The encoder's equivalent sequence is:
            //   lep[0] = max(lep[0], e_q[1]); lep++;
            //   max_e = max(lep[0], lep[1]) - 1;
            //   lep[0] = e_q[3];
            let eQ0pair = recoverEQ(rho: rho0, baseX: x, baseY: y)
            eVal[lep] = max(eVal[lep], UInt8(eQ0pair.1)); lep += 1
            let maxEAfterQ0 = max(Int(eVal[lep]), Int(eVal[lep + 1])) - 1
            eVal[lep] = UInt8(eQ0pair.3)

            // Step 5: kappaB and MagSgn for quad 1.
            var kappaB = 1
            if x + 2 < width {
                kappaB = ((rho1 & (rho1 - 1)) != 0) ? max(1, maxEAfterQ0) : 1
                let Uq1 = u_q1 + kappaB
                readQuadSamples(
                    baseX: x + 2, baseY: y,
                    rho: rho1, Uq: Uq1,
                    e_k: look1.e_k, e_1: look1.e_1)

                let eQ1pair = recoverEQ(rho: rho1, baseX: x + 2, baseY: y)
                eVal[lep] = max(eVal[lep], UInt8(eQ1pair.1)); lep += 1
                maxE = max(Int(eVal[lep]), Int(eVal[lep + 1])) - 1
                eVal[lep] = UInt8(eQ1pair.3)
            } else {
                maxE = maxEAfterQ0
            }

            c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2)
            x += 4
        }
    }

    // MARK: - Sample reconstruction

    /// Read MagSgn bits for each significant sample of the quad and
    /// place reconstructed (bin-center) coefficients into `coefs`.
    mutating func readQuadSamples(
        baseX: Int, baseY: Int,
        rho: Int, Uq: Int,
        e_k: Int, e_1: Int
    ) {
        let offsets = [(0, 0), (0, 1), (1, 0), (1, 1)]
        for i in 0..<4 {
            let bit = (rho >> i) & 1
            if bit == 0 { continue }
            let eBit = (e_k >> i) & 1
            let e1Bit = (e_1 >> i) & 1
            let m = Uq - eBit
            let payload = magsgnDec.read(count: m)
            let sign = UInt32(payload & 1)
            let mask: UInt32 = (m >= 32) ? ~UInt32(0)
                                         : ((UInt32(1) << m) - 1)
            var v_n: UInt32 = payload & mask
            v_n |= UInt32(e1Bit) << m
            v_n |= 1
            let (dx, dy) = offsets[i]
            let xi = baseX + dx
            let yi = baseY + dy
            if xi >= width || yi >= height { continue }
            var coef: UInt32 = (v_n &+ 2) << (p &- 1)
            if sign != 0 { coef |= 0x8000_0000 }
            coefs[yi * width + xi] = coef
        }
    }

    /// Derive e_q for the 4 samples of a quad from the reconstructed
    /// coefficients already placed in `coefs`. Returns a 4-tuple
    /// indexed by in-quad position (col * 2 + row). Only indices 1
    /// and 3 are used by the eVal bookkeeping, but the helper returns
    /// all four for uniformity.
    func recoverEQ(rho: Int, baseX: Int, baseY: Int)
        -> (Int, Int, Int, Int)
    {
        let offsets = [(0, 0), (0, 1), (1, 0), (1, 1)]
        var result = (0, 0, 0, 0)
        for i in 0..<4 {
            if (rho >> i) & 1 == 0 { continue }
            let (dx, dy) = offsets[i]
            let xi = baseX + dx
            let yi = baseY + dy
            if xi >= width || yi >= height { continue }
            let mag = coefs[yi * width + xi] & 0x7FFF_FFFF
            // Invert (v_n + 2) << (p - 1). Ignoring sign:
            //   v_n + 2 = mag >> (p - 1)
            //   v_n = (mag >> (p-1)) - 2
            // Then eQ is position of top bit of (v_n + 1) in
            // 2-indexed terms matching encoder's
            // `eQ = 32 - leadingZeroBitCount(val)` convention where
            // `val = 2μ_p - 1`.
            let v_n = (mag >> (p &- 1)) &- 2
            // v_n has bit structure `... e1 | payload | 1`, so
            // effectively `v_n | 1 = (v_n + 1)` rounds to the encoder's
            // `2μ_p - 1`.
            // The encoder's eQ was `32 - leadingZeroBits(2μ_p - 1)`,
            // i.e. 1-indexed position of MSB of (2μ_p - 1).
            let twoMuMinusOne = v_n | 1
            let eQ = 32 - twoMuMinusOne.leadingZeroBitCount
            switch i {
            case 0: result.0 = eQ
            case 1: result.1 = eQ
            case 2: result.2 = eQ
            case 3: result.3 = eQ
            default: break
            }
        }
        return result
    }
}

public enum HTBlockDecoderConformantError: Error {
    case malformedBlock
}

/// Forward bit reader over the reverse VLC stream. Reads LSB-first
/// from `melVlcBytes[scup - 2]`'s high nibble, then through earlier
/// bytes. Skips the last byte (which holds Scup's high 8 bits).
fileprivate struct VLCReverseReader {
    private let melVlcBytes: [UInt8]
    private let scup: Int
    private var byteIdx: Int
    private var tmp: UInt64 = 0
    private var bits: Int = 0
    private var unstuff: Bool = false

    init(melVlcBytes: [UInt8], scup: Int) {
        self.melVlcBytes = melVlcBytes
        self.scup = scup
        self.byteIdx = scup - 2
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
            // FF-stuff rule: drop bit 7 only when prior byte was
            // > 0x8F AND this byte's low 7 bits are all ones
            // (i.e. val is 0x7F or 0xFF). Mirrors OpenJPH's
            // `rev_read8` precisely — see ojph_block_decoder64.cpp:322.
            let t: Int = (unstuff && (Int(byte) & 0x7F) == 0x7F) ? 1 : 0
            let dBits = 8 - t
            let mask: UInt8 = (t == 1) ? 0x7F : 0xFF
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
