// j2knhd.h — J2K NEON HT Decoder (J2K NHD)
// v10.1-research — symmetric counterpart to j2knhe (HT encoder).
// Phase D1 Phase 0 scope: scalar-only C ports of the per-block decode
// state machines, evaluated against the Swift reference for the
// ≥10% per-block speedup gate before any NEON retrofit.
//
// This first commit ports the MEL state machine only:
//   - Swift reference: `HTMELDecoderConformant` in
//     Sources/J2KCodec/J2KHTConformantMELCoder.swift
//   - Parity oracle: V10_1_MELParityTests (random byte streams +
//     dictionary edge cases)
//
// Bit-exact contract: given any byte sequence, the C decoder must
// emit the same packed run values in the same order as the Swift
// decoder, up to and including the post-EOF 0xFF pad behaviour
// (OpenJPH convention).
//
// Memory model: caller-owned input buffer. The decoder holds no
// heap-allocated state; callers stack-allocate `j2knhd_mel_t` and
// pass it into the entry points.

#ifndef J2KNHD_H
#define J2KNHD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// MEL decoder state. Caller-owned. Lifetime is bounded by the input
/// byte buffer pointed to by `bytes`.
typedef struct j2knhd_mel {
    const uint8_t *bytes;   ///< caller-owned input buffer
    size_t bytes_len;       ///< length of `bytes` in bytes
    size_t read_index;      ///< absolute byte position in `bytes`
    uint64_t tmp;           ///< 64-bit bit buffer, MSB-first consumption
    int bits;               ///< valid bits currently in `tmp` (top-aligned)
    bool unstuff;           ///< if true, next byte's high bit is reserved
    int state;              ///< MEL state machine index, [0, 12]
} j2knhd_mel_t;

/// Initialise a MEL decoder over `bytes[0..bytes_len)`.
/// Pre: `dec != NULL`, `bytes != NULL || bytes_len == 0`.
/// Bit-exact equivalent of `HTMELDecoderConformant(bytes:)`.
void j2knhd_mel_init(j2knhd_mel_t *dec,
                     const uint8_t *bytes,
                     size_t bytes_len);

/// Returns the next packed run value. Format matches OpenJPH:
///   - low bit 0 → `run >> 1` zero events, no terminator
///   - low bit 1 → `run >> 1` zero events followed by a `1` event
/// Bit-exact equivalent of `HTMELDecoderConformant.nextRun()`.
int64_t j2knhd_mel_next_run(j2knhd_mel_t *dec);

// ---------------------------------------------------------------------------
// MagSgn forward bit reader.
//
// LSB-first consumption; every byte that follows a 0xFF byte contributes
// only 7 bits (its high bit is a reserved stuff bit). When the byte stream
// is exhausted, 0xFF is fed (matches OpenJPH `frwd_read<X=0xFF>`).
//
// Swift reference: `HTMagSgnDecoderConformant` scalar path in
// Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift lines 191-385.
// (The v7.4 4-byte SWAR + v8.1 8-byte SWAR refill paths are Swift-side
// micro-optimisations that the scalar reference is the canonical truth
// for; the C port ports the scalar path only.)

typedef struct j2knhd_magsgn {
    const uint8_t *bytes;
    size_t bytes_len;
    size_t read_index;
    uint64_t tmp;           ///< 64-bit bit buffer, LSB-first consumption
    int bits;               ///< valid bits in `tmp` (low-aligned)
    bool unstuff;           ///< if true, next byte's high bit is reserved
} j2knhd_magsgn_t;

/// Initialise a MagSgn decoder over `bytes[0..bytes_len)`.
void j2knhd_magsgn_init(j2knhd_magsgn_t *dec,
                        const uint8_t *bytes,
                        size_t bytes_len);

/// Read `count` LSB-first bits from the stream. `count` MUST be in
/// [0, 32]. Bit-exact equivalent of `HTMagSgnDecoderConformant.read(count:)`.
uint32_t j2knhd_magsgn_read(j2knhd_magsgn_t *dec, int count);

// ---------------------------------------------------------------------------
// VLC reverse-byte reader.
//
// LSB-first bit accumulator over a byte buffer consumed in REVERSE.
// The first byte read is `bytes[scup - 2]`, of which only the high
// nibble (with possible top-bit unstuff) is consumed. Subsequent bytes
// are `bytes[scup - 3]`, `bytes[scup - 4]`, etc. Once byte_idx drops
// below 0 the stream is exhausted; further bits are 0 (unlike MEL /
// MagSgn which pad with 0xFF).
//
// FF-stuff rule (different from MagSgn!): drop bit 7 only when the
// PRIOR byte was > 0x8F AND the current byte's low 7 bits are all 1
// (i.e. value is 0x7F or 0xFF). After consumption, `unstuff` is set
// from `byte > 0x8F`.
//
// Swift reference: `VLCReverseReader` (fileprivate struct) in
// Sources/J2KCodec/J2KHTConformantBlockDecoder.swift lines 692-899.
// The C port mirrors `refillScalar` (lines 738-760), the production
// path (the v7.4 SWAR `refillBatched` is bit-exact equivalent and
// gated behind the `VLCReverseReaderTesting.batchedRefillEnabled`
// opt-in flag, default false).

typedef struct j2knhd_vlc {
    const uint8_t *bytes;
    size_t bytes_len;
    int32_t scup;
    int32_t byte_idx;       ///< signed; may go negative when stream exhausted
    uint64_t tmp;           ///< 64-bit bit buffer, LSB-first consumption
    int bits;               ///< valid bits in `tmp` (low-aligned)
    bool unstuff;           ///< if true, prior byte was > 0x8F (FF-stuff carry)
} j2knhd_vlc_t;

/// Initialise a VLC reverse-reader. Consumes the high nibble of
/// `bytes[scup - 2]` immediately (mirrors Swift `init(melVlcBytes:scup:)`).
/// Bit-exact equivalent of `VLCReverseReader.init`.
void j2knhd_vlc_init(j2knhd_vlc_t *dec,
                     const uint8_t *bytes,
                     size_t bytes_len,
                     int32_t scup);

/// Returns the low `max_bits` bits of the accumulator without
/// consuming them. `max_bits` MUST be in [0, 64].
/// Bit-exact equivalent of `VLCReverseReader.peek(maxBits:)`.
uint64_t j2knhd_vlc_peek(j2knhd_vlc_t *dec, int max_bits);

/// Consume `count` bits already inspected via a prior peek. Discards
/// the value. Bit-exact equivalent of `VLCReverseReader.consume(count:)`.
void j2knhd_vlc_consume(j2knhd_vlc_t *dec, int count);

/// Read + return `count` low bits (combined peek + consume).
/// Bit-exact equivalent of `VLCReverseReader.read(count:)`.
uint64_t j2knhd_vlc_read(j2knhd_vlc_t *dec, int count);

#ifdef __cplusplus
}
#endif

#endif // J2KNHD_H
