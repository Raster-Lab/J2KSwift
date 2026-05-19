// j2knhd_decode_block_ht.c — integrated HT block decoder (scalar C).
// v10.2-research Phase D1.5-B.
//
// Bit-exact mirror of `HTBlockDecoderConformant.decode` in
// Sources/J2KCodec/J2KHTConformantBlockDecoder.swift. Wires the three
// state machines (MEL via j2knhd_mel, VLC reverse-reader via j2knhd_vlc,
// MagSgn via j2knhd_magsgn) into the row-dispatch state machine.
//
// Implementation notes:
//   * Per-row scratch buffers (eVal, cxVal) are stack-allocated for the
//     max 64×64 block size — bounded at ((width+3)/4)*2 + 2 = 34 entries.
//   * lookupVLC takes the 1024-entry table as a caller-provided pointer;
//     Swift wires vlcDecoderTable0Conformant / vlcDecoderTable1Conformant
//     in `J2KHTConformantTables.swift`.
//   * readQuadSamples uses the SCALAR reconstruction path (mirrors
//     Swift's readQuadSamplesScalar; the SIMD variant is a future
//     retrofit gated on Phase D1.5-C wall measurement).
//   * The block header parse logic mirrors HTBlockLayoutConformant.parse:
//     scup = (block[lcup-1] << 4) | (block[lcup-2] & 0x0F).

#include <string.h>
#include <assert.h>

#include "j2knhd.h"

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define J2KNHD_HAVE_NEON 1
#else
#define J2KNHD_HAVE_NEON 0
#endif

#define J2KNHD_MAX_BLOCK_DIM 64

typedef struct {
    j2knhd_mel_t     mel;
    j2knhd_vlc_t     vlc;
    j2knhd_magsgn_t  mag;
    uint32_t         width;
    uint32_t         height;
    uint32_t         p;                          ///< 30 − missing_msbs
    uint32_t        *coefs;                       ///< caller-owned, width*height
    const uint16_t  *vlc_table0;
    const uint16_t  *vlc_table1;
    uint8_t          eVal[((J2KNHD_MAX_BLOCK_DIM + 3) / 4) * 2 + 2];
    uint8_t          cxVal[((J2KNHD_MAX_BLOCK_DIM + 3) / 4) * 2 + 2];
    size_t           scratch_count;
    int64_t          mel_run;
    bool             reconstruct_use_simd;        ///< v10.6: select between scalar (false) and NEON SIMD (true) per-quad reconstruction
} j2knhd_decode_state_t;

// ---- helpers ----------------------------------------------------------------

static inline bool next_mel_event(j2knhd_decode_state_t *s) {
    s->mel_run -= 2;
    bool is_one = (s->mel_run == -1);
    if (s->mel_run < 0) {
        s->mel_run = j2knhd_mel_next_run(&s->mel);
    }
    return is_one;
}

typedef struct {
    int rho;
    int u_off;
    int cwd_len;
    int e_k;
    int e_1;
} j2knhd_vlc_lookup_t;

static inline j2knhd_vlc_lookup_t lookup_vlc(j2knhd_decode_state_t *s,
                                             int c_q, int bits,
                                             bool initial_line) {
    const uint16_t *tbl = initial_line ? s->vlc_table0 : s->vlc_table1;
    int idx = (c_q << 7) | (bits & 0x7F);
    int entry = (int)tbl[idx];
    j2knhd_vlc_lookup_t r;
    r.cwd_len = entry & 0x7;
    r.u_off   = (entry >> 3) & 0x1;
    r.rho     = (entry >> 4) & 0xF;
    r.e_1     = (entry >> 8) & 0xF;
    r.e_k     = (entry >> 12) & 0xF;
    return r;
}

static inline int read_prefix(j2knhd_decode_state_t *s) {
    int b0 = (int)j2knhd_vlc_read(&s->vlc, 1);
    if (b0 == 1) return 1;
    int b1 = (int)j2knhd_vlc_read(&s->vlc, 1);
    if (b1 == 1) return 2;
    int b2 = (int)j2knhd_vlc_read(&s->vlc, 1);
    if (b2 == 1) return 3;
    return 4;
}

static inline int decode_from_prefix(j2knhd_decode_state_t *s, int len) {
    if (len == 3) {
        int suf = (int)j2knhd_vlc_read(&s->vlc, 1);
        return 3 + suf;
    }
    if (len == 4) {
        int suf = (int)j2knhd_vlc_read(&s->vlc, 5);
        if (suf < 28) return 5 + suf;
        int ext = (int)j2knhd_vlc_read(&s->vlc, 4);
        return 33 + (suf - 28) + 4 * ext;
    }
    return len;
}

// UVLC pair decoding — initial row (with MEL arbitration when both u_off).
static inline void decode_uvlc_pair_initial(j2knhd_decode_state_t *s,
                                            int u_off0, int u_off1,
                                            int *u_q0, int *u_q1) {
    if (u_off0 == 0 && u_off1 == 0) { *u_q0 = 0; *u_q1 = 0; return; }
    if (u_off0 == 1 && u_off1 == 1) {
        bool mel_event = next_mel_event(s);
        if (mel_event) {
            int p0 = read_prefix(s);
            int p1 = read_prefix(s);
            int s0 = decode_from_prefix(s, p0);
            int s1 = decode_from_prefix(s, p1);
            *u_q0 = s0 + 2; *u_q1 = s1 + 2; return;
        }
        int p0 = read_prefix(s);
        if (p0 >= 3) {
            int bit = (int)j2knhd_vlc_read(&s->vlc, 1);
            int u0 = decode_from_prefix(s, p0);
            *u_q0 = u0; *u_q1 = bit + 1; return;
        }
        int p1 = read_prefix(s);
        int u0 = decode_from_prefix(s, p0);
        int u1 = decode_from_prefix(s, p1);
        *u_q0 = u0; *u_q1 = u1; return;
    }
    *u_q0 = (u_off0 != 0) ? decode_from_prefix(s, read_prefix(s)) : 0;
    *u_q1 = (u_off1 != 0) ? decode_from_prefix(s, read_prefix(s)) : 0;
}

// UVLC pair — subsequent row (pre0, pre1, suf0, suf1 unconditional).
static inline void decode_uvlc_pair_subsequent(j2knhd_decode_state_t *s,
                                               int u_off0, int u_off1,
                                               int *u_q0, int *u_q1) {
    int len0 = (u_off0 != 0) ? read_prefix(s) : 0;
    int len1 = (u_off1 != 0) ? read_prefix(s) : 0;
    *u_q0 = (u_off0 != 0) ? decode_from_prefix(s, len0) : 0;
    *u_q1 = (u_off1 != 0) ? decode_from_prefix(s, len1) : 0;
}

// Sample reconstruction (scalar). Mirrors readQuadSamplesScalar.
static inline void read_quad_samples_scalar(j2knhd_decode_state_t *s,
                                            int baseX, int baseY,
                                            int rho, int Uq, int e_k, int e_1) {
    if (rho == 0) return;
    static const int offsets[4][2] = { {0,0}, {0,1}, {1,0}, {1,1} };
    for (int i = 0; i < 4; i++) {
        int bit = (rho >> i) & 1;
        if (bit == 0) continue;
        int eBit  = (e_k >> i) & 1;
        int e1Bit = (e_1 >> i) & 1;
        int m = Uq - eBit;
        uint32_t payload = j2knhd_magsgn_read(&s->mag, m);
        uint32_t sign = payload & 1u;
        uint32_t mask = (m >= 32) ? ~(uint32_t)0 : (((uint32_t)1 << m) - 1u);
        uint32_t v_n = payload & mask;
        v_n |= (uint32_t)e1Bit << m;
        v_n |= 1u;
        int dx = offsets[i][0], dy = offsets[i][1];
        int xi = baseX + dx;
        int yi = baseY + dy;
        if ((uint32_t)xi >= s->width || (uint32_t)yi >= s->height) continue;
        uint32_t coef = (v_n + 2u) << (s->p - 1u);
        if (sign != 0) coef |= 0x80000000u;
        s->coefs[(size_t)yi * s->width + (size_t)xi] = coef;
    }
}

#if J2KNHD_HAVE_NEON
// v10.6-research: NEON SIMD reconstruction. Mirrors
// `HTBlockDecoderConformant.readQuadSamplesSIMD` in the Swift codec.
// MagSgn reads are still serial (the bit stream is sequential), but the
// post-read arithmetic — mask/v_n/coef/sign build — runs lane-parallel
// in a single NEON 128-bit register.
//
// Bit-exact equivalent of `read_quad_samples_scalar` by construction:
// same arithmetic, same boundary semantics. The lane-parallel path
// uses NEON `vshlq_u32` which produces 0 when the shift count is ≥ 32
// — matching Swift's `1 &<< 32 = 0` wraparound on `(1 << m) - 1`
// (yielding `~0u`), so the `m == 32` edge case is bit-exact too.
static inline void read_quad_samples_simd(j2knhd_decode_state_t *s,
                                          int baseX, int baseY,
                                          int rho, int Uq, int e_k, int e_1) {
    if (rho == 0) return;

    int r0 = (rho     ) & 1;
    int r1 = (rho >> 1) & 1;
    int r2 = (rho >> 2) & 1;
    int r3 = (rho >> 3) & 1;

    int32_t mArr[4];
    mArr[0] = (int32_t)(Uq - ((e_k     ) & 1));
    mArr[1] = (int32_t)(Uq - ((e_k >> 1) & 1));
    mArr[2] = (int32_t)(Uq - ((e_k >> 2) & 1));
    mArr[3] = (int32_t)(Uq - ((e_k >> 3) & 1));

    // Serial MagSgn reads — the bit stream is sequential per quad.
    uint32_t pArr[4] = { 0u, 0u, 0u, 0u };
    if (r0) pArr[0] = j2knhd_magsgn_read(&s->mag, (int)mArr[0]);
    if (r1) pArr[1] = j2knhd_magsgn_read(&s->mag, (int)mArr[1]);
    if (r2) pArr[2] = j2knhd_magsgn_read(&s->mag, (int)mArr[2]);
    if (r3) pArr[3] = j2knhd_magsgn_read(&s->mag, (int)mArr[3]);

    uint32x4_t payloads = vld1q_u32(pArr);
    int32x4_t  ms       = vld1q_s32(mArr);
    uint32x4_t one      = vdupq_n_u32(1u);

    // mask = (1 << m) - 1. For m == 32, vshlq_u32(1, 32) → 0 per ARMv8,
    // and 0 - 1 wraps to 0xFFFFFFFF (bit-exact with the Swift scalar
    // `(m >= 32) ? ~0 : (1 << m) - 1` branch).
    uint32x4_t mask = vsubq_u32(vshlq_u32(one, ms), one);

    uint32_t e1Arr[4];
    e1Arr[0] = (uint32_t)((e_1     ) & 1);
    e1Arr[1] = (uint32_t)((e_1 >> 1) & 1);
    e1Arr[2] = (uint32_t)((e_1 >> 2) & 1);
    e1Arr[3] = (uint32_t)((e_1 >> 3) & 1);
    uint32x4_t e1v = vld1q_u32(e1Arr);

    uint32x4_t signs = vandq_u32(payloads, one);
    uint32x4_t v_n   = vorrq_u32(vorrq_u32(
                          vandq_u32(payloads, mask),
                          vshlq_u32(e1v, ms)), one);

    int32x4_t  pShift   = vdupq_n_s32((int32_t)s->p - 1);
    int32x4_t  signShift= vdupq_n_s32(31);
    uint32x4_t coefs4   = vshlq_u32(vaddq_u32(v_n, vdupq_n_u32(2u)), pShift);
    coefs4 = vorrq_u32(coefs4, vshlq_u32(signs, signShift));

    uint32_t coefsArr[4];
    vst1q_u32(coefsArr, coefs4);

    // Conditional per-lane stores. The bounds check + rho gate match
    // the scalar path exactly so inactive lanes leave coefs[] unmodified.
    static const int offsets[4][2] = { {0,0}, {0,1}, {1,0}, {1,1} };
    int rs[4] = { r0, r1, r2, r3 };
    for (int i = 0; i < 4; i++) {
        if (rs[i] == 0) continue;
        int dx = offsets[i][0], dy = offsets[i][1];
        int xi = baseX + dx;
        int yi = baseY + dy;
        if ((uint32_t)xi >= s->width || (uint32_t)yi >= s->height) continue;
        s->coefs[(size_t)yi * s->width + (size_t)xi] = coefsArr[i];
    }
}
#endif // J2KNHD_HAVE_NEON

// v10.6 dispatcher — routes to SIMD or scalar reconstruction based on
// the per-decode `reconstruct_use_simd` flag. SIMD path is only built
// on NEON-capable targets; on non-NEON builds (Linux x86_64 CI) we
// always take the scalar path regardless of the flag.
static inline void read_quad_samples(j2knhd_decode_state_t *s,
                                     int baseX, int baseY,
                                     int rho, int Uq, int e_k, int e_1) {
#if J2KNHD_HAVE_NEON
    if (s->reconstruct_use_simd) {
        read_quad_samples_simd(s, baseX, baseY, rho, Uq, e_k, e_1);
        return;
    }
#endif
    read_quad_samples_scalar(s, baseX, baseY, rho, Uq, e_k, e_1);
}

// recoverEQBottomRow — derive bottom-row e_q (positions 1 + 3) from
// reconstructed coefficients. Mirrors recoverEQBottomRow.
static inline void recover_eq_bottom_row(j2knhd_decode_state_t *s,
                                         int rho, int baseX, int baseY,
                                         int *eQ1, int *eQ3) {
    if (rho == 0) { *eQ1 = 0; *eQ3 = 0; return; }
    *eQ1 = 0;
    if (((rho >> 1) & 1) != 0) {
        int yi = baseY + 1;
        if ((uint32_t)baseX < s->width && (uint32_t)yi < s->height) {
            uint32_t mag = s->coefs[(size_t)yi * s->width + (size_t)baseX] & 0x7FFFFFFFu;
            uint32_t v_n = (mag >> (s->p - 1u)) - 2u;
            uint32_t twoMu = v_n | 1u;
            *eQ1 = 32 - __builtin_clz(twoMu);
        }
    }
    *eQ3 = 0;
    if (((rho >> 3) & 1) != 0) {
        int xi = baseX + 1;
        int yi = baseY + 1;
        if ((uint32_t)xi < s->width && (uint32_t)yi < s->height) {
            uint32_t mag = s->coefs[(size_t)yi * s->width + (size_t)xi] & 0x7FFFFFFFu;
            uint32_t v_n = (mag >> (s->p - 1u)) - 2u;
            uint32_t twoMu = v_n | 1u;
            *eQ3 = 32 - __builtin_clz(twoMu);
        }
    }
}

// ---- row decode -------------------------------------------------------------

static void decode_initial_row(j2knhd_decode_state_t *s) {
    int lep = 0;
    int lcxp = 0;
    int c_q0 = 0;
    int x = 0;
    while (x < (int)s->width) {
        int rho0 = 0;
        j2knhd_vlc_lookup_t look0 = {0,0,0,0,0};
        if (c_q0 == 0) {
            if (next_mel_event(s)) {
                int head = (int)j2knhd_vlc_peek(&s->vlc, 7);
                look0 = lookup_vlc(s, c_q0, head, true);
                j2knhd_vlc_consume(&s->vlc, look0.cwd_len);
                rho0 = look0.rho;
            }
        } else {
            int head = (int)j2knhd_vlc_peek(&s->vlc, 7);
            look0 = lookup_vlc(s, c_q0, head, true);
            j2knhd_vlc_consume(&s->vlc, look0.cwd_len);
            rho0 = look0.rho;
        }

        int rho1 = 0;
        j2knhd_vlc_lookup_t look1 = {0,0,0,0,0};
        if (x + 2 < (int)s->width) {
            int c_q1 = (rho0 >> 1) | (rho0 & 1);
            if (c_q1 == 0) {
                if (next_mel_event(s)) {
                    int head1 = (int)j2knhd_vlc_peek(&s->vlc, 7);
                    look1 = lookup_vlc(s, c_q1, head1, true);
                    j2knhd_vlc_consume(&s->vlc, look1.cwd_len);
                    rho1 = look1.rho;
                }
            } else {
                int head1 = (int)j2knhd_vlc_peek(&s->vlc, 7);
                look1 = lookup_vlc(s, c_q1, head1, true);
                j2knhd_vlc_consume(&s->vlc, look1.cwd_len);
                rho1 = look1.rho;
            }
        }

        int u_q0, u_q1;
        decode_uvlc_pair_initial(s,
            rho0 != 0 ? look0.u_off : 0,
            rho1 != 0 ? look1.u_off : 0,
            &u_q0, &u_q1);
        int Uq0 = u_q0 + 1;  // kappa = 1 initial row
        int Uq1 = u_q1 + 1;

        read_quad_samples(s, x, 0, rho0, Uq0, look0.e_k, look0.e_1);
        if (x + 2 < (int)s->width) {
            read_quad_samples(s, x + 2, 0, rho1, Uq1, look1.e_k, look1.e_1);
        }

        int eQ0_0, eQ0_1;
        recover_eq_bottom_row(s, rho0, x, 0, &eQ0_0, &eQ0_1);
        if ((uint8_t)eQ0_0 > s->eVal[lep]) s->eVal[lep] = (uint8_t)eQ0_0;
        lep += 1;
        s->eVal[lep] = (uint8_t)eQ0_1;
        s->cxVal[lcxp] = s->cxVal[lcxp] | (uint8_t)((rho0 & 2) >> 1);
        lcxp += 1;
        s->cxVal[lcxp] = (uint8_t)((rho0 & 8) >> 3);
        if (x + 2 < (int)s->width) {
            int eQ1_0, eQ1_1;
            recover_eq_bottom_row(s, rho1, x + 2, 0, &eQ1_0, &eQ1_1);
            if ((uint8_t)eQ1_0 > s->eVal[lep]) s->eVal[lep] = (uint8_t)eQ1_0;
            lep += 1;
            s->eVal[lep] = (uint8_t)eQ1_1;
            s->cxVal[lcxp] = s->cxVal[lcxp] | (uint8_t)((rho1 & 2) >> 1);
            lcxp += 1;
            s->cxVal[lcxp] = (uint8_t)((rho1 & 8) >> 3);
        }

        c_q0 = (rho1 >> 1) | (rho1 & 1);
        x += 4;
    }
    if (lep + 1 < (int)s->scratch_count) s->eVal[lep + 1] = 0;
}

static void decode_subsequent_row(j2knhd_decode_state_t *s, int y) {
    int lep = 0;
    int lcxp = 0;
    int maxE_a = (int)s->eVal[0];
    if ((int)s->eVal[1] > maxE_a) maxE_a = (int)s->eVal[1];
    int maxE = maxE_a - 1;
    s->eVal[0] = 0;
    int c_q0 = (int)s->cxVal[0] + ((int)s->cxVal[1] << 2);
    s->cxVal[0] = 0;

    int x = 0;
    while (x < (int)s->width) {
        int rho0 = 0;
        j2knhd_vlc_lookup_t look0 = {0,0,0,0,0};
        if (c_q0 == 0) {
            if (next_mel_event(s)) {
                int head = (int)j2knhd_vlc_peek(&s->vlc, 7);
                look0 = lookup_vlc(s, c_q0, head, false);
                j2knhd_vlc_consume(&s->vlc, look0.cwd_len);
                rho0 = look0.rho;
            }
        } else {
            int head = (int)j2knhd_vlc_peek(&s->vlc, 7);
            look0 = lookup_vlc(s, c_q0, head, false);
            j2knhd_vlc_consume(&s->vlc, look0.cwd_len);
            rho0 = look0.rho;
        }
        int kappaA = ((rho0 & (rho0 - 1)) != 0)
            ? ((maxE >= 1) ? maxE : 1) : 1;

        s->cxVal[lcxp] = s->cxVal[lcxp] | (uint8_t)((rho0 & 2) >> 1);
        lcxp += 1;
        int c_q1 = (int)s->cxVal[lcxp] + ((int)s->cxVal[lcxp + 1] << 2);
        s->cxVal[lcxp] = (uint8_t)((rho0 & 8) >> 3);

        int rho1 = 0;
        j2knhd_vlc_lookup_t look1 = {0,0,0,0,0};
        if (x + 2 < (int)s->width) {
            c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2);
            if (c_q1 == 0) {
                if (next_mel_event(s)) {
                    int head1 = (int)j2knhd_vlc_peek(&s->vlc, 7);
                    look1 = lookup_vlc(s, c_q1, head1, false);
                    j2knhd_vlc_consume(&s->vlc, look1.cwd_len);
                    rho1 = look1.rho;
                }
            } else {
                int head1 = (int)j2knhd_vlc_peek(&s->vlc, 7);
                look1 = lookup_vlc(s, c_q1, head1, false);
                j2knhd_vlc_consume(&s->vlc, look1.cwd_len);
                rho1 = look1.rho;
            }
            s->cxVal[lcxp] = s->cxVal[lcxp] | (uint8_t)((rho1 & 2) >> 1);
            lcxp += 1;
            c_q0 = (int)s->cxVal[lcxp] + ((int)s->cxVal[lcxp + 1] << 2);
            s->cxVal[lcxp] = (uint8_t)((rho1 & 8) >> 3);
        }

        int u_q0, u_q1;
        decode_uvlc_pair_subsequent(s,
            rho0 != 0 ? look0.u_off : 0,
            rho1 != 0 ? look1.u_off : 0,
            &u_q0, &u_q1);

        int Uq0 = u_q0 + kappaA;
        read_quad_samples(s, x, y, rho0, Uq0, look0.e_k, look0.e_1);

        int eQ0_0, eQ0_1;
        recover_eq_bottom_row(s, rho0, x, y, &eQ0_0, &eQ0_1);
        if ((uint8_t)eQ0_0 > s->eVal[lep]) s->eVal[lep] = (uint8_t)eQ0_0;
        lep += 1;
        int maxE_after_q0_a = (int)s->eVal[lep];
        if ((int)s->eVal[lep + 1] > maxE_after_q0_a) maxE_after_q0_a = (int)s->eVal[lep + 1];
        int maxEAfterQ0 = maxE_after_q0_a - 1;
        s->eVal[lep] = (uint8_t)eQ0_1;

        int kappaB = 1;
        if (x + 2 < (int)s->width) {
            kappaB = ((rho1 & (rho1 - 1)) != 0)
                ? ((maxEAfterQ0 >= 1) ? maxEAfterQ0 : 1) : 1;
            int Uq1 = u_q1 + kappaB;
            read_quad_samples(s, x + 2, y, rho1, Uq1, look1.e_k, look1.e_1);

            int eQ1_0, eQ1_1;
            recover_eq_bottom_row(s, rho1, x + 2, y, &eQ1_0, &eQ1_1);
            if ((uint8_t)eQ1_0 > s->eVal[lep]) s->eVal[lep] = (uint8_t)eQ1_0;
            lep += 1;
            int maxE_a2 = (int)s->eVal[lep];
            if ((int)s->eVal[lep + 1] > maxE_a2) maxE_a2 = (int)s->eVal[lep + 1];
            maxE = maxE_a2 - 1;
            s->eVal[lep] = (uint8_t)eQ1_1;
        } else {
            maxE = maxEAfterQ0;
        }

        (void)kappaB;
        c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2);
        x += 4;
    }
}

// ---- public entry point -----------------------------------------------------

int j2knhd_decode_block_ht32(
    const uint8_t *block, size_t block_len,
    uint32_t width, uint32_t height, uint32_t missing_msbs,
    const uint16_t *vlc_table0,
    const uint16_t *vlc_table1,
    bool magsgn_use_swar4,
    bool reconstruct_use_simd,
    uint32_t *coefs_out
) {
    // Validate dimensions.
    if (width == 0 || width > J2KNHD_MAX_BLOCK_DIM ||
        height == 0 || height > J2KNHD_MAX_BLOCK_DIM ||
        missing_msbs > 29) {
        return J2KNHD_E_DIMENSIONS;
    }
    // Parse block header: scup = (block[lcup-1] << 4) | (block[lcup-2] & 0x0F).
    if (block_len < 2) return J2KNHD_E_MALFORMED;
    int scup = ((int)block[block_len - 1] << 4)
             + ((int)(block[block_len - 2] & 0x0F));
    if (scup < 2 || (size_t)scup > block_len || scup > 4079) {
        return J2KNHD_E_MALFORMED;
    }
    size_t split = block_len - (size_t)scup;
    // magsgn = block[0..split); melVlc = block[split..lcup).

    // Init state.
    j2knhd_decode_state_t s;
    j2knhd_mel_init(&s.mel, block + split, (size_t)scup);
    j2knhd_vlc_init(&s.vlc, block + split, (size_t)scup, scup);
    if (magsgn_use_swar4) {
        j2knhd_magsgn_init_swar(&s.mag, block, split);
    } else {
        j2knhd_magsgn_init(&s.mag, block, split);
    }
    s.width = width;
    s.height = height;
    s.p = 30u - missing_msbs;
    s.coefs = coefs_out;
    s.vlc_table0 = vlc_table0;
    s.vlc_table1 = vlc_table1;
    s.scratch_count = ((size_t)(width + 3) / 4) * 2 + 2;
    s.reconstruct_use_simd = reconstruct_use_simd;
    memset(s.eVal,  0, sizeof(s.eVal));
    memset(s.cxVal, 0, sizeof(s.cxVal));
    memset(coefs_out, 0, sizeof(uint32_t) * (size_t)width * (size_t)height);
    s.mel_run = j2knhd_mel_next_run(&s.mel);

    decode_initial_row(&s);
    int y = 2;
    while (y < (int)height) {
        decode_subsequent_row(&s, y);
        y += 2;
    }
    return J2KNHD_OK;
}
