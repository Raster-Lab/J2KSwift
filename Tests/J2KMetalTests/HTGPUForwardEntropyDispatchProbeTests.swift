// HTGPUForwardEntropyDispatchProbeTests.swift
//
// v6-alpha6 phase 0.5 — empirical gate to v6-alpha6 phase 1.
//
// Question this test answers (per
// `docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md` §5):
//
//   "Does the per-block GPU dispatch + memory-traffic floor leave
//    room for the actual entropy work to win against CPU's
//    parallel-codeblock encode?"
//
// CPU baseline target (from the v5.38 / v6.0.0 corpus encode tables):
//
//   - DX 2800×2288 single-tile encode: ~70 ms wall, of which ~32 ms
//     is HT entropy across ~2300 codeblocks at 64×64
//   - PX 2459×1316 single-tile encode: ~37 ms wall, ~17 ms entropy
//     across ~1100 codeblocks
//
// If the GPU dispatch probe — which does ZERO real entropy work but
// matches the read+write traffic shape — exceeds the CPU entropy
// budget for the same fixture size, GPU is dead for this stage and
// Phase 1 must pivot from approach B (GPU classify + CPU emit) to
// approach E (CPU-SIMD only).
//
// This is a diagnostic test only. It does not assert any
// performance threshold; it prints a markdown table the
// `RELEASING.md` step-2 reviewer can paste into a Phase 1 design
// note.

import XCTest
@testable import J2KCore
@testable import J2KMetal

final class HTGPUForwardEntropyDispatchProbeTests: XCTestCase {

    /// One realistic codeblock layout per medical-corpus fixture size,
    /// matching what the production encoder would emit for the
    /// HT-conformant 5/3 lossless path with 64×64 codeblocks.
    private struct CorpusFixture {
        let label: String
        let imageWidth: Int
        let imageHeight: Int
        let blockWidth: Int
        let blockHeight: Int
    }

    private func corpus() -> [CorpusFixture] {
        return [
            // 6 corpus fixtures spanning 200 KB → 6.4 MP. Block grid
            // assumes 64×64 codeblocks across the LL band of all 5
            // resolution levels (rough — real production block count
            // also includes HL/LH/HH bands at every level; adjust the
            // multiplier below if a tighter estimate is needed).
            CorpusFixture(label: "MR-small 180²",   imageWidth: 180,  imageHeight: 180,  blockWidth: 64, blockHeight: 64),
            CorpusFixture(label: "CT 512²",         imageWidth: 512,  imageHeight: 512,  blockWidth: 64, blockHeight: 64),
            CorpusFixture(label: "MR 886²",         imageWidth: 886,  imageHeight: 886,  blockWidth: 64, blockHeight: 64),
            CorpusFixture(label: "XA 1024²",        imageWidth: 1024, imageHeight: 1024, blockWidth: 64, blockHeight: 64),
            CorpusFixture(label: "PX 2459×1316",    imageWidth: 2459, imageHeight: 1316, blockWidth: 64, blockHeight: 64),
            CorpusFixture(label: "DX 2800×2288",    imageWidth: 2800, imageHeight: 2288, blockWidth: 64, blockHeight: 64),
        ]
    }

    /// Build descriptors that cover the image area with `blockW × blockH`
    /// codeblocks (last column / row may be smaller). Coefficient pool
    /// is `imageW × imageH` UInt32s; output capacity per block is
    /// `2 × blockW × blockH` bytes (a generous upper bound — real
    /// HT-conformant lossless rarely exceeds 1 byte per significant
    /// sample on natural images).
    private func makeDescriptors(_ f: CorpusFixture) -> (
        descriptors: [J2KMetalHTForwardBlockDescriptor],
        coefficients: [UInt32],
        outputByteCount: Int
    ) {
        var descriptors: [J2KMetalHTForwardBlockDescriptor] = []
        let blockCols = (f.imageWidth + f.blockWidth - 1) / f.blockWidth
        let blockRows = (f.imageHeight + f.blockHeight - 1) / f.blockHeight

        var coeffOffset: UInt32 = 0
        var outputOffset: UInt32 = 0
        for by in 0..<blockRows {
            for bx in 0..<blockCols {
                let bw = min(f.blockWidth, f.imageWidth - bx * f.blockWidth)
                let bh = min(f.blockHeight, f.imageHeight - by * f.blockHeight)
                let cap = UInt32(2 * bw * bh)  // 2 bytes/sample upper bound
                descriptors.append(J2KMetalHTForwardBlockDescriptor(
                    coeffOffset: coeffOffset,
                    outputOffset: outputOffset,
                    outputCapacity: cap,
                    width: UInt16(bw),
                    height: UInt16(bh)))
                coeffOffset += UInt32(bw * bh)
                outputOffset += cap
            }
        }

        // Coefficients: a deterministic sign-magnitude pseudo-random
        // walk (LCG). Bit-distribution doesn't matter for the probe;
        // the kernel only does light per-sample work. Seed is fixed
        // so successive runs produce identical traffic.
        let totalCoeffs = Int(coeffOffset)
        var coefficients = [UInt32](repeating: 0, count: totalCoeffs)
        var rng: UInt32 = 0xDEAD_BEEF
        for i in 0..<totalCoeffs {
            rng = rng &* 1_103_515_245 &+ 12_345
            // Sign bit + 14-bit magnitude — typical for 16-bit
            // medical inputs after HT-conformant sign-magnitude
            // normalisation.
            coefficients[i] = (rng & 0x80000000) | (rng & 0x3FFF)
        }

        return (descriptors, coefficients, Int(outputOffset))
    }

    /// Phase 0.5 deliverable — dispatch probe across the full medical
    /// corpus. Prints a markdown table of (blockCount, GPU kernel ms,
    /// wall ms, gridded throughput) per fixture. No assertions on
    /// timing; only assertion is that the kernel runs without crash
    /// and writes the expected number of output bytes.
    func testForwardEntropyDispatchProbe_AcrossMedicalCorpus() async throws {
        try XCTSkipUnless(J2KMetalHTForwardDispatchProbe.isAvailable,
                          "Metal not available")
        #if DEBUG
        print("⚠️  Phase 0.5 dispatch probe running in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTGPUForwardEntropyDispatchProbeTests")
        #endif

        let probe = J2KMetalHTForwardDispatchProbe()

        print("=== v6-alpha6 Phase 0.5 — forward HT entropy dispatch probe ===")
        print("(Per-block synthetic work; not a real encoder. Output shape:")
        print(" reads W×H UInt32 coefficients, writes ~half that many bytes.")
        print(" Empirical gate to Phase 1 approach pick — see")
        print(" `docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md` §4.)")
        print()
        print("| fixture | blocks | coefs | bytes out | wall ms | GPU ms | ns/block |")
        print("|---|---:|---:|---:|---:|---:|---:|")

        for f in corpus() {
            let (descs, coeffs, outBytes) = makeDescriptors(f)

            // Warm-up: first dispatch pays the Metal session init
            // cost; we want steady-state numbers.
            _ = try await probe.run(
                descriptors: descs, coefficients: coeffs,
                outputByteCount: outBytes)

            // Three runs, take the median.
            var wallSec: [Double] = []
            var gpuSec: [Double] = []
            var lastOutput: [UInt8] = []
            for _ in 0..<3 {
                let (out, stats) = try await probe.run(
                    descriptors: descs, coefficients: coeffs,
                    outputByteCount: outBytes)
                wallSec.append(stats.wallClockSeconds)
                gpuSec.append(stats.gpuKernelSeconds)
                lastOutput = out
            }
            wallSec.sort(); gpuSec.sort()
            let wallMs = wallSec[1] * 1000.0
            let gpuMs  = gpuSec[1]  * 1000.0
            let nsPerBlock = (gpuSec[1] / Double(descs.count)) * 1_000_000_000.0

            // Sanity: kernel must have written *something* into the
            // output pool (not all-zero), or the dispatch silently
            // no-op'd.
            XCTAssertEqual(lastOutput.count, outBytes,
                "output byte count mismatch for \(f.label)")
            let nonZero = lastOutput.contains { $0 != 0 }
            XCTAssertTrue(nonZero,
                "kernel produced all-zero output for \(f.label) — silent no-op?")

            print(String(format: "| %@ | %d | %d | %d | %6.2f | %6.2f | %8.1f |",
                f.label, descs.count, coeffs.count, outBytes,
                wallMs, gpuMs, nsPerBlock))
        }

        print()
        print("Reading the table:")
        print("  - `GPU ms` is the steady-state per-fixture kernel cost")
        print("    (gpuStartTime → gpuEndTime, excludes upload + readback)")
        print("  - `ns/block` is the per-codeblock GPU compute floor.")
        print("    Real entropy work has to fit in this budget OR be")
        print("    fast enough that the per-block parallelism wins.")
        print("  - CPU baseline for DX entropy: ~32 ms / 2300 blocks =")
        print("    ~14000 ns/block. If GPU `ns/block` for DX is")
        print("    significantly lower, approach B (GPU classify) is")
        print("    viable; if higher, pivot to approach E (CPU-SIMD).")
    }
}
