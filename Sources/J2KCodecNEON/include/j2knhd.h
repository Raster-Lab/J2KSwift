// j2knhd.h — J2K NEON HT Decoder (J2K NHD)
// v10.0-research — custom C+NEON tier-1 entropy block DECODER for
// JPEG 2000 Part-15 (HT). Symmetric to j2knhe (encoder, v9.4.0).
//
// Apple Silicon (ARM64 NEON) is the primary target; the scalar
// fallback also works on any C99-supporting toolchain.
//
// Bit-exact equivalent of HTBlockDecoderConformant.decode in the
// J2KSwift Swift codebase. Validated against the parity sweep in
// Tests/J2KCodecTests/V10DecoderNEONParityTests.swift (will be added
// alongside this header in the same research session).

#ifndef J2KNHD_H
#define J2KNHD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Decoder entry point — bit-exact inverse of `j2knhe_encode_block_ht32`.
///
/// Input convention:
///   - `magsgn_buf`/`magsgn_len`: forward MagSgn byte stream produced
///     by the encoder.
///   - `melvlc_buf`/`melvlc_len`/`scup`: combined MEL+VLC byte stream.
///     MEL is forward at byte 0; VLC is reverse-bit-stream stored at
///     the end starting `melvlc_len - scup` bytes before EOF. Format
///     matches `HTBlockLayoutConformant.parse(block:)` output.
///   - `width`, `height`: in [1, 64] (v10 first-cut scope).
///   - `missing_msbs`: in [0, 29] per T.814.
///
/// Output:
///   - `coefficients_out`: pre-allocated `uint32_t` array of size
///     `width * height`. Filled in row-major order with OpenJPH
///     sign-magnitude convention (bit 31 = sign, magnitude in low bits
///     below `p = 30 - missing_msbs`).
///
/// Returns:
///    0 on success
///   -1 if input stream is malformed / truncated
///   -2 on invalid input parameters (width/height/missing_msbs out of range)
///   -3 NOT YET IMPLEMENTED — v10.0-research scaffold-only build
int j2knhd_decode_block_ht32(
    const uint8_t *magsgn_buf, size_t magsgn_len,
    const uint8_t *melvlc_buf, size_t melvlc_len,
    size_t scup,
    uint32_t width,
    uint32_t height,
    uint32_t missing_msbs,
    uint32_t *coefficients_out);

/// Returns a static version string identifying the build.
const char *j2knhd_version(void);

// --- Microbench-grade exports for Phase 0 viability measurement ---
//
// The full decoder is multi-week scope. To produce a go/no-go signal
// overnight, the C target exports the three bit-stream readers
// individually. The microbench harness calls them in tight loops on
// representative data and compares to the Swift readers.

/// Forward MagSgn reader state. Caller-allocated.
typedef struct j2knhd_magsgn_dec {
    const uint8_t *buf;
    size_t         len;
    size_t         pos;     // next byte to consume
    uint64_t       tmp;     // partial-byte accumulator (LSB-first, 64-bit)
    int            availBits;
    int            wasFFFlag;
    int            depleted;
} j2knhd_magsgn_dec;

void j2knhd_magsgn_init(j2knhd_magsgn_dec *s, const uint8_t *buf, size_t len);
uint32_t j2knhd_magsgn_read(j2knhd_magsgn_dec *s, int count);

/// MEL run-length reader state. Caller-allocated.
typedef struct j2knhd_mel_dec {
    const uint8_t *buf;
    size_t         len;
    size_t         pos;
    uint32_t       tmp;
    int            availBits;
    int            wasFFFlag;
    int            k;       // MEL run-state index in [0, 12]
    int            run;     // current run state value
} j2knhd_mel_dec;

void j2knhd_mel_init(j2knhd_mel_dec *s, const uint8_t *buf, size_t len);
int  j2knhd_mel_next_run(j2knhd_mel_dec *s);

/// VLC reverse-bit reader state. Caller-allocated.
typedef struct j2knhd_vlc_dec {
    const uint8_t *buf;     // points to the MEL+VLC combined byte buffer
    size_t         len;     // total length
    size_t         scup;    // SCUP value (VLC region length in bytes)
    size_t         pos;     // descending byte pointer; starts at len-scup-1
    uint32_t       tmp;     // bit buffer (MSB-first for reverse-bit consumption)
    int            availBits;
} j2knhd_vlc_dec;

void j2knhd_vlc_init(j2knhd_vlc_dec *s, const uint8_t *melvlc_buf,
                     size_t melvlc_len, size_t scup);
uint32_t j2knhd_vlc_peek(const j2knhd_vlc_dec *s, int count);
void     j2knhd_vlc_consume(j2knhd_vlc_dec *s, int count);

#ifdef __cplusplus
}
#endif

#endif // J2KNHD_H
