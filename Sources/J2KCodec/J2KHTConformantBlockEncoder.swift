// J2KHTBlockEncoderConformant.swift
// ISO/IEC 15444-15 cleanup-pass codeblock encoder (scalar, 32-bit).
//
// Ports OpenJPH 0.26's `ojph_encode_codeblock32` from
// `ojph_block_encoder.cpp`. Walks a codeblock as pairs of 2x2 sample
// quads, building up rho/eps/u context per quad, then emits through
// the M1–M4 stream coders. Outputs a byte tuple that the block
// assembler (M5a) can wrap with the Scup trailer.
//
// Sample input convention matches OpenJPH: one `UInt32` per
// coefficient, with bit 31 holding the sign (1 = negative) and the
// magnitude in the bits below `p = 30 - missingMSBs`. A value of 0
// (including sign bit 0) means "zero coefficient, not significant".
//
// This implementation covers the cleanup pass only — SigProp / MagRef
// refinement passes are not emitted, matching OpenJPH's scalar path
// (`num_passes == 1`).

import Foundation

/// Cleanup-pass codeblock encoder (32-bit signed-magnitude path).
/// Produces the three Part-15 sub-streams separately; wrap with
/// `HTBlockLayoutConformant.assemble` to get the final on-wire block.
public enum HTBlockEncoderConformant {

    /// Encode a codeblock's cleanup pass.
    ///
    /// - Parameters:
    ///   - coefficients: `width * height` sign-magnitude coefficients
    ///     in row-major order.
    ///   - width: block width, in samples (must be >= 1).
    ///   - height: block height, in samples (must be >= 1).
    ///   - missingMSBs: number of insignificant leading bits in the
    ///     sign-magnitude representation (= `Kmsbs` / "missing MSBs"
    ///     from ITU T.814).
    /// - Returns: `(magsgn, mel, vlc)` tuple, each ready to hand to
    ///   `HTBlockLayoutConformant.assemble`. Note: `vlc` is in forward
    ///   on-wire byte order (ending with `0xFF` sentinel).
    public static func encode(
        coefficients: [UInt32],
        width: Int,
        height: Int,
        missingMSBs: Int
    ) -> (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8]) {
        precondition(coefficients.count == width * height,
                     "coefficient count mismatch")
        precondition(missingMSBs < 30, "missingMSBs must leave room for data")

        var magsgnEnc = HTMagSgnEncoderConformant()
        var melEnc = HTMELEncoderConformant()
        var vlcEnc = HTReverseBitEmitterConformant()

        let p = UInt32(30 - missingMSBs)

        // Per-row scratch state: lep carries the max e_q across the
        // two bottom samples of adjacent quads from the previous row;
        // lcxp carries the rho-derived context for the next row.
        //
        // We size these with +2 guard slots like OpenJPH (one for the
        // absent earlier quad, one for beyond-the-end).
        let guardedWidth = ((width + 3) / 4) * 2 + 2
        var eVal = [UInt8](repeating: 0, count: guardedWidth)
        var cxVal = [UInt8](repeating: 0, count: guardedWidth)

        // Fetch one sample's magnitude-exponent and signed payload.
        // Returns (significant: Bool, eQ: Int, payload: UInt32).
        // The "payload" is `v_n = 2*(mu_p - 1) + sign` as documented in
        // T.814 eqn. 5.
        func sampleInfo(_ t: UInt32) -> (Bool, Int, UInt32) {
            // val = 2*t >> p & ~1 — isolate 2μ_p, clearing the sign
            // bit's contribution.
            var val = (t &+ t) >> p
            val &= ~UInt32(1)
            if val == 0 { return (false, 0, 0) }
            val &-= 1                     // 2μ_p - 1
            let lz = val.leadingZeroBitCount
            let eQ = 32 - lz
            let sign = UInt32((t >> 31) & 1)
            let payload = (val &- 1) &+ sign
            return (true, eQ, payload)
        }

        // Read one sample at (x, y), returning zero info if out of
        // bounds on either axis.
        func fetch(_ x: Int, _ y: Int) -> UInt32 {
            guard x < width, y < height else { return 0 }
            return coefficients[y * width + x]
        }

        // Process a single quad (4 samples in a 2x2 block at
        // (baseX, baseY)).
        func processQuad(
            baseX: Int, baseY: Int
        ) -> (rho: Int, eQMax: Int, eQ: [Int], s: [UInt32]) {
            var rho = 0
            var eQ = [0, 0, 0, 0]
            var s:  [UInt32] = [0, 0, 0, 0]
            var eQMax = 0
            // Sample layout within a quad: (col, row) in
            // [(0,0), (0,1), (1,0), (1,1)] — OpenJPH walks the
            // (col, row) positions as index = 2*col + row (column-
            // major within the quad).
            let offsets = [(0, 0), (0, 1), (1, 0), (1, 1)]
            for (i, (dx, dy)) in offsets.enumerated() {
                let t = fetch(baseX + dx, baseY + dy)
                let (sig, e, payload) = sampleInfo(t)
                if sig {
                    rho |= (1 << i)
                    eQ[i] = e
                    s[i]  = payload
                    if e > eQMax { eQMax = e }
                }
            }
            return (rho, eQMax, eQ, s)
        }

        // --- Initial row of quads (y = 0, 1) ---

        var c_q0 = 0
        var y = 0

        var lep = 0      // index into eVal
        var lcxp = 0     // index into cxVal
        eVal[lep] = 0
        cxVal[lcxp] = 0

        if height > 0 {
            var spX = 0
            while spX < width {
                let (rho0, eQMax0, eQ0, s0) = processQuad(baseX: spX, baseY: 0)
                let Uq0 = max(eQMax0, 1)
                let u_q0 = Uq0 - 1

                var eps0 = 0
                if u_q0 > 0 {
                    if eQ0[0] == eQMax0 { eps0 |= 1 }
                    if eQ0[1] == eQMax0 { eps0 |= 2 }
                    if eQ0[2] == eQMax0 { eps0 |= 4 }
                    if eQ0[3] == eQMax0 { eps0 |= 8 }
                }

                // lep / lcxp bookkeeping: the max e_q from the quad's
                // bottom row carries forward; rho's bottom bits feed
                // the next row's context.
                eVal[lep] = max(eVal[lep], UInt8(eQ0[1])); lep += 1
                eVal[lep] = UInt8(eQ0[3])
                cxVal[lcxp] = cxVal[lcxp] | UInt8((rho0 & 2) >> 1); lcxp += 1
                cxVal[lcxp] = UInt8((rho0 & 8) >> 3)

                let tuple0 = Int(vlcTable0Conformant[
                    (c_q0 << 8) | (rho0 << 4) | eps0])
                vlcEnc.encode(codeword: tuple0 >> 8, count: (tuple0 >> 4) & 0x7)

                if c_q0 == 0 {
                    melEnc.encode(eventIsOne: rho0 != 0)
                }

                // Emit MagSgn bits for each significant sample.
                for i in 0..<4 {
                    let bit = (rho0 >> i) & 1
                    if bit == 1 {
                        let eBit = (tuple0 >> i) & 1
                        let m = Uq0 - eBit
                        let mask: UInt32 = (m >= 32) ? ~UInt32(0)
                                                    : ((UInt32(1) << m) - 1)
                        magsgnEnc.encode(codeword: s0[i] & mask, count: m)
                    }
                }

                // Second quad of the pair (might be out of bounds).
                var rho1 = 0
                var u_q1 = 0
                if spX + 2 < width {
                    let (_rho1, eQMax1, eQ1, s1) =
                        processQuad(baseX: spX + 2, baseY: 0)
                    rho1 = _rho1
                    let c_q1 = (rho0 >> 1) | (rho0 & 1)
                    let Uq1 = max(eQMax1, 1)
                    u_q1 = Uq1 - 1
                    var eps1 = 0
                    if u_q1 > 0 {
                        if eQ1[0] == eQMax1 { eps1 |= 1 }
                        if eQ1[1] == eQMax1 { eps1 |= 2 }
                        if eQ1[2] == eQMax1 { eps1 |= 4 }
                        if eQ1[3] == eQMax1 { eps1 |= 8 }
                    }
                    eVal[lep] = max(eVal[lep], UInt8(eQ1[1])); lep += 1
                    eVal[lep] = UInt8(eQ1[3])
                    cxVal[lcxp] = cxVal[lcxp] | UInt8((rho1 & 2) >> 1); lcxp += 1
                    cxVal[lcxp] = UInt8((rho1 & 8) >> 3)

                    let tuple1 = Int(vlcTable0Conformant[
                        (c_q1 << 8) | (rho1 << 4) | eps1])
                    vlcEnc.encode(codeword: tuple1 >> 8, count: (tuple1 >> 4) & 0x7)

                    if c_q1 == 0 {
                        melEnc.encode(eventIsOne: rho1 != 0)
                    }

                    for i in 0..<4 {
                        let bit = (rho1 >> i) & 1
                        if bit == 1 {
                            let eBit = (tuple1 >> i) & 1
                            let m = Uq1 - eBit
                            let mask: UInt32 = (m >= 32) ? ~UInt32(0)
                                                        : ((UInt32(1) << m) - 1)
                            magsgnEnc.encode(codeword: s1[i] & mask, count: m)
                        }
                    }
                }

                // u-value encoding for this quad pair.
                if u_q0 > 0 && u_q1 > 0 {
                    melEnc.encode(eventIsOne: min(u_q0, u_q1) > 2)
                }
                if u_q0 > 2 && u_q1 > 2 {
                    let e0 = uvlcTableConformant[u_q0 - 2]
                    let e1 = uvlcTableConformant[u_q1 - 2]
                    vlcEnc.encode(codeword: Int(e0.pre), count: Int(e0.preLen))
                    vlcEnc.encode(codeword: Int(e1.pre), count: Int(e1.preLen))
                    vlcEnc.encode(codeword: Int(e0.suf), count: Int(e0.sufLen))
                    vlcEnc.encode(codeword: Int(e1.suf), count: Int(e1.sufLen))
                } else if u_q0 > 2 && u_q1 > 0 {
                    let e0 = uvlcTableConformant[u_q0]
                    vlcEnc.encode(codeword: Int(e0.pre), count: Int(e0.preLen))
                    vlcEnc.encode(codeword: u_q1 - 1, count: 1)
                    vlcEnc.encode(codeword: Int(e0.suf), count: Int(e0.sufLen))
                } else {
                    let e0 = uvlcTableConformant[u_q0]
                    let e1 = uvlcTableConformant[u_q1]
                    vlcEnc.encode(codeword: Int(e0.pre), count: Int(e0.preLen))
                    vlcEnc.encode(codeword: Int(e1.pre), count: Int(e1.preLen))
                    vlcEnc.encode(codeword: Int(e0.suf), count: Int(e0.sufLen))
                    vlcEnc.encode(codeword: Int(e1.suf), count: Int(e1.sufLen))
                }

                c_q0 = (rho1 >> 1) | (rho1 & 1)
                spX += 4
            }
        }
        // Mark the end-of-row sentinel in eVal.
        if lep + 1 < eVal.count { eVal[lep + 1] = 0 }

        // --- Subsequent quad rows (y = 2, 4, ...) ---

        y = 2
        while y < height {
            lep = 0
            var maxE = max(Int(eVal[0]), Int(eVal[1])) - 1
            eVal[0] = 0
            lcxp = 0
            c_q0 = Int(cxVal[0]) + (Int(cxVal[1]) << 2)
            cxVal[0] = 0

            var spX = 0
            while spX < width {
                let (rho0, eQMax0, eQ0, s0) = processQuad(baseX: spX, baseY: y)
                let kappaA = ((rho0 & (rho0 - 1)) != 0) ? max(1, maxE) : 1
                let Uq0 = max(eQMax0, kappaA)
                let u_q0 = Uq0 - kappaA
                var eps0 = 0
                if u_q0 > 0 {
                    if eQ0[0] == eQMax0 { eps0 |= 1 }
                    if eQ0[1] == eQMax0 { eps0 |= 2 }
                    if eQ0[2] == eQMax0 { eps0 |= 4 }
                    if eQ0[3] == eQMax0 { eps0 |= 8 }
                }
                eVal[lep] = max(eVal[lep], UInt8(eQ0[1])); lep += 1
                maxE = max(Int(eVal[lep]), Int(eVal[lep + 1])) - 1
                eVal[lep] = UInt8(eQ0[3])
                cxVal[lcxp] = cxVal[lcxp] | UInt8((rho0 & 2) >> 1); lcxp += 1
                var c_q1 = Int(cxVal[lcxp]) + (Int(cxVal[lcxp + 1]) << 2)
                cxVal[lcxp] = UInt8((rho0 & 8) >> 3)

                let tuple0 = Int(vlcTable1Conformant[
                    (c_q0 << 8) | (rho0 << 4) | eps0])
                vlcEnc.encode(codeword: tuple0 >> 8, count: (tuple0 >> 4) & 0x7)
                if c_q0 == 0 {
                    melEnc.encode(eventIsOne: rho0 != 0)
                }
                for i in 0..<4 {
                    let bit = (rho0 >> i) & 1
                    if bit == 1 {
                        let eBit = (tuple0 >> i) & 1
                        let m = Uq0 - eBit
                        let mask: UInt32 = (m >= 32) ? ~UInt32(0)
                                                    : ((UInt32(1) << m) - 1)
                        magsgnEnc.encode(codeword: s0[i] & mask, count: m)
                    }
                }

                var rho1 = 0
                var u_q1 = 0
                if spX + 2 < width {
                    let (_rho1, eQMax1, eQ1, s1) =
                        processQuad(baseX: spX + 2, baseY: y)
                    rho1 = _rho1
                    let kappaB = ((rho1 & (rho1 - 1)) != 0) ? max(1, maxE) : 1
                    c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2)
                    let Uq1 = max(eQMax1, kappaB)
                    u_q1 = Uq1 - kappaB
                    var eps1 = 0
                    if u_q1 > 0 {
                        if eQ1[0] == eQMax1 { eps1 |= 1 }
                        if eQ1[1] == eQMax1 { eps1 |= 2 }
                        if eQ1[2] == eQMax1 { eps1 |= 4 }
                        if eQ1[3] == eQMax1 { eps1 |= 8 }
                    }
                    eVal[lep] = max(eVal[lep], UInt8(eQ1[1])); lep += 1
                    maxE = max(Int(eVal[lep]), Int(eVal[lep + 1])) - 1
                    eVal[lep] = UInt8(eQ1[3])
                    cxVal[lcxp] = cxVal[lcxp] | UInt8((rho1 & 2) >> 1); lcxp += 1
                    c_q0 = Int(cxVal[lcxp]) + (Int(cxVal[lcxp + 1]) << 2)
                    cxVal[lcxp] = UInt8((rho1 & 8) >> 3)

                    let tuple1 = Int(vlcTable1Conformant[
                        (c_q1 << 8) | (rho1 << 4) | eps1])
                    vlcEnc.encode(codeword: tuple1 >> 8, count: (tuple1 >> 4) & 0x7)
                    if c_q1 == 0 {
                        melEnc.encode(eventIsOne: rho1 != 0)
                    }
                    for i in 0..<4 {
                        let bit = (rho1 >> i) & 1
                        if bit == 1 {
                            let eBit = (tuple1 >> i) & 1
                            let m = Uq1 - eBit
                            let mask: UInt32 = (m >= 32) ? ~UInt32(0)
                                                        : ((UInt32(1) << m) - 1)
                            magsgnEnc.encode(codeword: s1[i] & mask, count: m)
                        }
                    }
                }

                // Subsequent rows use unconditional UVLC per quad.
                let e0 = uvlcTableConformant[u_q0]
                let e1 = uvlcTableConformant[u_q1]
                vlcEnc.encode(codeword: Int(e0.pre), count: Int(e0.preLen))
                vlcEnc.encode(codeword: Int(e1.pre), count: Int(e1.preLen))
                vlcEnc.encode(codeword: Int(e0.suf), count: Int(e0.sufLen))
                vlcEnc.encode(codeword: Int(e1.suf), count: Int(e1.sufLen))

                c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2)
                spX += 4
            }
            y += 2
        }

        let magsgnBytes = magsgnEnc.finish()
        let melBytes = melEnc.finish()
        let vlcBytes = vlcEnc.finish()
        return (magsgnBytes, melBytes, vlcBytes)
    }
}
