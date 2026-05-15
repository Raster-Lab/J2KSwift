// j2knhd_magsgn.c — scalar C port of HTMagSgnDecoderConformant.
// v10.1-research Phase D1.
//
// Bit-exact mirror of `HTMagSgnDecoderConformant` scalar path in
// Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift lines 244-385.
//
// Forward bit reader, LSB-first consumption. FF-stuff rule: when the
// previous byte was 0xFF, the next byte's high bit is reserved (only
// the low 7 bits contribute).

#include "j2knhd.h"

void j2knhd_magsgn_init(j2knhd_magsgn_t *dec,
                        const uint8_t *bytes,
                        size_t bytes_len) {
    dec->bytes = bytes;
    dec->bytes_len = bytes_len;
    dec->read_index = 0;
    dec->tmp = 0;
    dec->bits = 0;
    dec->unstuff = false;
}

// Refill: feed bytes (then 0xFF padding) until `bits > 32`.
// Mirrors Swift `refillScalar()` lines 345-381 exactly.
static inline void j2knhd_magsgn_refill(j2knhd_magsgn_t *dec) {
    while (dec->bits <= 32 && dec->read_index < dec->bytes_len) {
        uint8_t byte = dec->bytes[dec->read_index];
        dec->read_index += 1;
        int d_bits = 8 - (dec->unstuff ? 1 : 0);
        uint8_t mask = (uint8_t)0xFF >> (dec->unstuff ? 1 : 0);
        dec->tmp |= ((uint64_t)(byte & mask)) << dec->bits;
        dec->bits += d_bits;
        dec->unstuff = (byte == 0xFF);
    }
    while (dec->bits <= 32) {
        // End-of-stream 0xFF padding per OpenJPH convention.
        uint8_t byte = 0xFF;
        int d_bits = 8 - (dec->unstuff ? 1 : 0);
        uint8_t mask = (uint8_t)0xFF >> (dec->unstuff ? 1 : 0);
        dec->tmp |= ((uint64_t)(byte & mask)) << dec->bits;
        dec->bits += d_bits;
        dec->unstuff = (byte == 0xFF);
    }
}

uint32_t j2knhd_magsgn_read(j2knhd_magsgn_t *dec, int count) {
    // Swift precondition: count <= 32.
    if (dec->bits < count) {
        j2knhd_magsgn_refill(dec);
    }
    uint64_t mask = (count >= 64) ? ~(uint64_t)0 : (((uint64_t)1 << count) - 1);
    uint32_t v = (uint32_t)(dec->tmp & mask);
    dec->tmp >>= count;
    dec->bits -= count;
    return v;
}
