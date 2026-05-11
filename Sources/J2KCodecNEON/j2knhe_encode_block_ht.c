// j2knhe_encode_block_ht.c — custom C+NEON tier-1 HT block encoder.
//
// v9.4-research scope: this file currently contains a STUB that
// returns immediately with empty output streams. Day 1 milestone is
// "SwiftPM C target compiles and Swift can call into it." The actual
// encoder algorithm + NEON tuning lands in Day 2-3. Once that is in,
// bit-exact parity is gated by V94NEONHotPathParityTests against the
// existing v9.3 Swift path.

#include "j2knhe.h"
#include "j2knhe_tables.h"

#include <string.h>

// Architecture detection. Only ARM64 will pull in NEON intrinsics; on
// other targets we fall back to a portable scalar implementation. v9.4-
// research only ships on Apple Silicon so NEON is the expected path.
#if defined(__ARM_NEON) || defined(__aarch64__)
#define J2KNHE_HAS_NEON 1
#include <arm_neon.h>
#else
#define J2KNHE_HAS_NEON 0
#endif

#if J2KNHE_HAS_NEON
static const char kVersion[] = "j2knhe-v9.4-research-neon-stub";
#else
static const char kVersion[] = "j2knhe-v9.4-research-scalar-stub";
#endif

const char *j2knhe_version(void) {
    return kVersion;
}

int j2knhe_encode_block_ht32(
    const uint32_t *coefficients,
    uint32_t width, uint32_t height,
    uint32_t missing_msbs,
    uint8_t *magsgn_buf, size_t magsgn_cap, size_t *magsgn_len,
    uint8_t *mel_buf,    size_t mel_cap,    size_t *mel_len,
    uint8_t *vlc_buf,    size_t vlc_cap,    size_t *vlc_len)
{
    // Input validation — match the Swift path's preconditions.
    if (width == 0 || width > 64 || height == 0 || height > 64) {
        return -2;
    }
    if (missing_msbs >= 30) {
        return -2;
    }
    if (coefficients == NULL) {
        return -2;
    }

    // STUB: produce empty output streams. Day 2-3 fills the actual
    // encoder body. Suppress unused-parameter warnings; the buffers
    // and capacities are inspected once the algorithm is in.
    (void)coefficients;
    (void)missing_msbs;
    (void)magsgn_buf; (void)magsgn_cap;
    (void)mel_buf;    (void)mel_cap;
    (void)vlc_buf;    (void)vlc_cap;

    if (magsgn_len) *magsgn_len = 0;
    if (mel_len)    *mel_len    = 0;
    if (vlc_len)    *vlc_len    = 0;

    return 0;
}
