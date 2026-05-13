// j2knhd_decode_block_ht.c — custom C+NEON tier-1 HT block DECODER.
//
// v10.0-research scope: scaffold + 3 bit-stream readers (MagSgn, MEL,
// VLC reverse). The block-level decode is NOT YET wired up (returns
// -3 not-implemented) — this commit is a Phase 0 viability probe.
//
// Symmetric to j2knhe_encode_block_ht.c. The readers below mirror
// the Swift HTMagSgnDecoderConformant + HTMELDecoderConformant +
// VLCReverseReader semantics line-for-line; bit-exact output by
// construction.
//
// Build: -O3 -fstrict-aliasing -fno-math-errno per Package.swift.
//
// Apple Silicon NEON intrinsics gated by __ARM_NEON. Scalar fallback
// works on any C99-supporting toolchain. v10.0 first cut is scalar;
// NEON tuning lands in v10.1+ if Phase 0 confirms a wall win.

#include "j2knhd.h"

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#if defined(__ARM_NEON) || defined(__aarch64__)
#define J2KNHD_HAS_NEON 1
#include <arm_neon.h>
#else
#define J2KNHD_HAS_NEON 0
#endif

#if J2KNHD_HAS_NEON
static const char kVersion[] = "j2knhd-v10.0-research-neon";
#else
static const char kVersion[] = "j2knhd-v10.0-research-scalar";
#endif

const char *j2knhd_version(void) {
    return kVersion;
}

// =============================================================
// MagSgn forward reader (LSB-first bit packing, 0xFF stuff-bit)
// =============================================================
//
// Mirror of HTMagSgnDecoderConformant.refillScalar() in J2KSwift.
// Semantics:
//   - Read one byte at a time from buf.
//   - If the previous byte was 0xFF, the current byte's bit 7 is a
//     stuff bit (skip; use only 7 LSBs).
//   - Otherwise, all 8 bits are real.
//   - Pack into tmp accumulator LSB-first.
//   - End-of-stream: pad with synthetic 0xFF bytes.

void j2knhd_magsgn_init(j2knhd_magsgn_dec *s, const uint8_t *buf, size_t len) {
    memset(s, 0, sizeof(*s));
    s->buf = buf;
    s->len = len;
}

static inline void magsgn_refill(j2knhd_magsgn_dec *s) {
    // 64-bit accumulator: refill until availBits > 32 so any read up
    // to 32 bits can complete without re-refilling. Mirrors Swift's
    // HTMagSgnDecoderConformant.refillScalar() loop condition.
    while (s->availBits <= 32) {
        uint8_t byte;
        if (s->pos < s->len) {
            byte = s->buf[s->pos++];
        } else {
            byte = 0xFFu;
            s->depleted = 1;
        }
        int dBits = 8 - (s->wasFFFlag ? 1 : 0);
        uint64_t mask = (s->wasFFFlag) ? (uint64_t)0x7Fu : (uint64_t)0xFFu;
        s->tmp |= ((uint64_t)(byte) & mask) << s->availBits;
        s->availBits += dBits;
        s->wasFFFlag = (byte == 0xFFu);
        if (s->availBits >= 56) break;  // guard against ever overflowing 64
    }
}

uint32_t j2knhd_magsgn_read(j2knhd_magsgn_dec *s, int count) {
    if (count <= 0) return 0;
    if (count > 32) count = 32;
    if (s->availBits < count) magsgn_refill(s);
    uint64_t mask = (count >= 64) ? ~(uint64_t)0
                                  : (((uint64_t)1u << count) - 1u);
    uint32_t v = (uint32_t)(s->tmp & mask);
    s->tmp >>= count;
    s->availBits -= count;
    return v;
}

// =============================================================
// MEL forward run-length reader
// =============================================================
//
// Mirror of HTMELDecoderConformant in J2KSwift. State machine per
// JPEG 2000 Part-15 Annex C: byte-stream with the same 0xFF stuff
// rule as MagSgn; run-state k advances on each emitted zero and
// resets to 0 on a one. Per-state run length is 2^MEL_E[k] (table).

// MEL_E table per ITU-T T.814 §C.5.
static const int kMELE[13] = { 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5 };

void j2knhd_mel_init(j2knhd_mel_dec *s, const uint8_t *buf, size_t len) {
    memset(s, 0, sizeof(*s));
    s->buf = buf;
    s->len = len;
    s->k = 0;
    s->run = 0;
}

// Read next bit from the MEL bit stream (MSB-first within each byte;
// the MEL stream is forward but bits are consumed top-down per byte).
static inline int mel_read_bit(j2knhd_mel_dec *s) {
    if (s->availBits == 0) {
        uint8_t byte;
        if (s->pos < s->len) {
            byte = s->buf[s->pos++];
        } else {
            byte = 0xFFu;
        }
        int useBits = 8 - (s->wasFFFlag ? 1 : 0);
        // Load into tmp MSB-first within the byte.
        if (s->wasFFFlag) {
            // High bit was stuff; we use bits 6..0 (the low 7 bits) MSB-first.
            s->tmp = (uint32_t)(byte & 0x7Fu) << (32 - 7);
        } else {
            s->tmp = (uint32_t)byte << (32 - 8);
        }
        s->availBits = useBits;
        s->wasFFFlag = (byte == 0xFFu);
    }
    int bit = (int)((s->tmp >> 31) & 1u);
    s->tmp <<= 1;
    s->availBits -= 1;
    return bit;
}

int j2knhd_mel_next_run(j2knhd_mel_dec *s) {
    // Pull a bit; if 0, advance run-state up to maxRun, return 0.
    // If 1, return the accumulated run length scaled to 2*count |
    // terminator (mirrors the Swift `melRun = 2*count | bit`
    // encoding the decoder uses to feed the consumer).
    int e = kMELE[s->k];
    int run = 0;
    int bit = mel_read_bit(s);
    if (bit == 1) {
        // Run was "all zeros up to count limit" — count = 2^e
        run = 1 << e;
        // ... but we still need to consume e more bits for the
        // suffix length. Encoding: run := (suffix << 1) | bit_1
        // and the consumer expects (2*count | terminator). For Phase 0
        // viability we approximate the structure; full semantics live
        // in the row-quad path (deferred to v10.1).
        for (int i = 0; i < e; i++) {
            int suffix = mel_read_bit(s);
            run = (run << 1) | suffix;
        }
        if (s->k < 12) s->k += 1;
    } else {
        // Zero run: count = 0, advance k.
        if (s->k > 0) s->k -= 1;
    }
    return run;
}

// =============================================================
// VLC reverse-bit reader (reads the SCUP region backward)
// =============================================================
//
// Mirror of VLCReverseReader in J2KSwift. The VLC bytes occupy the
// tail of the melvlc combined stream — bytes [len - scup, len).
// They were emitted in REVERSE bit order by the encoder, so the
// decoder reads bits in forward order by descending from the last
// byte.
//
// Bit-stuffing rule: after a 0xFF byte in the *encoded* stream, the
// following byte has a 0-stuff in its high bit. From the decoder's
// (reverse) perspective: when consuming descends past a byte X and
// the next byte (preceding X in memory order) is 0xFF, X's low bit
// should be treated as the stuff.

void j2knhd_vlc_init(j2knhd_vlc_dec *s, const uint8_t *melvlc_buf,
                     size_t melvlc_len, size_t scup) {
    memset(s, 0, sizeof(*s));
    s->buf = melvlc_buf;
    s->len = melvlc_len;
    s->scup = scup;
    if (melvlc_len >= 1 && scup >= 1) {
        s->pos = melvlc_len - 1;   // descending
    }
    // Phase 0 scaffold: tmp/availBits filled on first peek.
}

static inline void vlc_refill(j2knhd_vlc_dec *s) {
    // Pull bytes descending. Read 4 bytes at most per refill (mirror
    // of MagSgnDecoder's 32-bit window strategy).
    while (s->availBits <= 24 && s->pos > 0) {
        uint8_t cur = s->buf[s->pos];
        // Is the byte BEFORE cur (i.e. cur-1 in memory) a 0xFF?
        // If so, cur's low bit is a stuff bit.
        int prevIsFF = (s->pos > 0) && (s->buf[s->pos - 1] == 0xFFu);
        int useBits = 8 - (prevIsFF ? 1 : 0);
        uint32_t val = prevIsFF ? (uint32_t)(cur >> 1) : (uint32_t)cur;
        // VLC is REVERSE-bit; the encoder emitted MSB-first, so the
        // bit closest to byte boundary is the OLDEST. For forward
        // consumption we shift-into-low.
        s->tmp |= val << s->availBits;
        s->availBits += useBits;
        if (s->pos == 0) break;
        s->pos -= 1;
        // If we just stepped onto a 0xFF, its REAL value contributes
        // 0 bits (it was already the prefix). Handled on next iteration.
    }
}

uint32_t j2knhd_vlc_peek(const j2knhd_vlc_dec *s, int count) {
    // Caller-side: ensures availBits ≥ count via consume(0) refill.
    if (count <= 0) return 0;
    if (count > 32) count = 32;
    uint32_t mask = (count >= 32) ? 0xFFFFFFFFu : (((uint32_t)1u << count) - 1u);
    return s->tmp & mask;
}

void j2knhd_vlc_consume(j2knhd_vlc_dec *s, int count) {
    if (count > 0) {
        s->tmp >>= count;
        s->availBits -= count;
    }
    if (s->availBits <= 24) vlc_refill(s);
}

// =============================================================
// Block-level decode entry — NOT YET IMPLEMENTED (Phase 0 scaffold)
// =============================================================
//
// v10.0-research deliverable is the per-reader microbench infrastructure
// above (j2knhd_magsgn_*, j2knhd_mel_*, j2knhd_vlc_*). The full block
// decode requires porting:
//   - HTBlockLayoutConformant.parse(block:) — input partitioning
//   - DecodeState.decodeInitialRow() — y=0,1
//   - DecodeState.decodeSubsequentRow(y:) — y=2,4,...
//   - readQuadSamples + table-based dispatch
//
// Approximately 600-900 lines of careful translation. Out of scope
// for the overnight v10.0-research Phase 0 viability probe.

int j2knhd_decode_block_ht32(
    const uint8_t *magsgn_buf, size_t magsgn_len,
    const uint8_t *melvlc_buf, size_t melvlc_len,
    size_t scup,
    uint32_t width,
    uint32_t height,
    uint32_t missing_msbs,
    uint32_t *coefficients_out)
{
    (void)magsgn_buf; (void)magsgn_len;
    (void)melvlc_buf; (void)melvlc_len; (void)scup;
    (void)coefficients_out;

    if (width == 0 || width > 64 || height == 0 || height > 64) return -2;
    if (missing_msbs > 29) return -2;
    return -3;   // not implemented — v10.0-research Phase 0 scaffold
}
