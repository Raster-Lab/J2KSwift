// v9.5 Phase 5 — per-block ns measurement against the C+NEON path.
//
// Provides a single Swift-side timing harness around
// `j2knhe_encode_block_ht32` to isolate per-block / per-quad wall and
// inform Phase 5A/5B/5C/5D scope. Reports ns/block + ns/quad at
// representative HT block shapes (32×32, 64×64, sparse vs dense).

import XCTest
import Darwin
@testable import J2KCodec
import J2KCodecNEON

final class V95Phase5MicrobenchTests: XCTestCase {

    /// LCG-seeded synthetic block: produces a mix of significant and
    /// non-significant samples, with realistic eQ distribution.
    private func makeBlock(width: Int, height: Int,
                            missingMSBs: Int,
                            seed: UInt64,
                            density: Int) -> [UInt32]
    {
        // density: percentage of significant samples (0..100). Higher
        // density → more emit work per quad.
        let count = width * height
        let p = 30 - missingMSBs
        var coefs = [UInt32](repeating: 0, count: count)
        var lcg = seed
        for i in 0..<count {
            lcg = lcg &* 6364136223846793005 &+ 1442695040888963407
            let r = Int(UInt32(truncatingIfNeeded: lcg >> 32) & 0x7F)
            if r >= density {
                coefs[i] = 0
                continue
            }
            // Significant sample: 8-bit magnitude shifted into the
            // bit-precision window.
            let val = UInt32(truncatingIfNeeded: lcg >> 40) & 0xFF
            let sign: UInt32 = (val & 0x1) != 0 ? 0x8000_0000 : 0
            coefs[i] = sign | (UInt32(val | 1) << UInt32(p))
        }
        return coefs
    }

    private func benchBlock(width: Int, height: Int,
                             missingMSBs: Int, density: Int,
                             label: String)
    {
        let N = 200_000
        let coefs = makeBlock(width: width, height: height,
                              missingMSBs: missingMSBs, seed: 0x9E37_79B9_7F4A_7C15,
                              density: density)
        let cap = 16384
        let magBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        let melBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        let vlcBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer {
            magBuf.deallocate(); melBuf.deallocate(); vlcBuf.deallocate()
        }
        var magLen: Int = 0, melLen: Int = 0, vlcLen: Int = 0

        // Warm-up
        _ = coefs.withUnsafeBufferPointer { buf in
            j2knhe_encode_block_ht32(
                buf.baseAddress!, UInt32(width), UInt32(height),
                UInt32(missingMSBs),
                magBuf, cap, &magLen,
                melBuf, cap, &melLen,
                vlcBuf, cap, &vlcLen)
        }

        let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        _ = coefs.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for _ in 0..<N {
                _ = j2knhe_encode_block_ht32(
                    base, UInt32(width), UInt32(height),
                    UInt32(missingMSBs),
                    magBuf, cap, &magLen,
                    melBuf, cap, &melLen,
                    vlcBuf, cap, &vlcLen)
            }
        }
        let elapsedNs = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0)
        let nsPerBlock = elapsedNs / Double(N)
        let quadsPerBlock = (width / 2) * (height / 2)
        let nsPerQuad = nsPerBlock / Double(quadsPerBlock)
        let totalBytes = magLen + melLen + vlcLen
        print(String(format: "| %@ | %d×%d | mMSB=%d | dens=%d%% | %.0f ns/block | %.1f ns/quad | out=%d bytes |",
                     label, width, height, missingMSBs, density, nsPerBlock, nsPerQuad, totalBytes))
    }

    /// Sweeps per-block ns across HT block shapes and density profiles.
    /// Identifies whether classifier, MagSgn, or VLC dominates per-quad
    /// wall on M4 — informs Phase 5A-D scope.
    func testPerBlockNsAcrossShapesAndDensities() {
        print("=== v9.5 Phase 5 — per-block ns microbench (C+NEON path) ===")
        print("Processor: Apple M4 (\(ProcessInfo.processInfo.activeProcessorCount) procs)")
        print("Configuration: HT-conformant, j2knhe_encode_block_ht32, N=200000 per row")
        print()
        print("| Label | w×h | missingMSBs | density | ns/block | ns/quad | output bytes |")
        print("|---|---|---|---|---|---|---|")
        benchBlock(width: 32, height: 32, missingMSBs: 8,  density: 30, label: "ct-like-mid")
        benchBlock(width: 32, height: 32, missingMSBs: 8,  density: 5,  label: "ct-like-sparse")
        benchBlock(width: 32, height: 32, missingMSBs: 8,  density: 80, label: "ct-like-dense")
        benchBlock(width: 64, height: 64, missingMSBs: 5,  density: 30, label: "dx-like-mid")
        benchBlock(width: 64, height: 64, missingMSBs: 5,  density: 5,  label: "dx-like-sparse")
        benchBlock(width: 64, height: 64, missingMSBs: 5,  density: 80, label: "dx-like-dense")
        benchBlock(width: 64, height: 64, missingMSBs: 12, density: 30, label: "high-mMSB-mid")
        print()
        print("Per-quad budget estimate (M4 NEON encoder, warm cache):")
        print("- Classifier: per V91Phase1A microbench, ~2-5 ns/quad on M4.")
        print("- Remainder (= ns/quad - classifier ns) = emit + bookkeeping.")
    }
}
