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

#ifdef __cplusplus
}
#endif

#endif // J2KNHD_H
