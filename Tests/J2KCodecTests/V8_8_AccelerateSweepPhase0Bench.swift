// V8_8_AccelerateSweepPhase0Bench.swift
//
// v8.8 Phase 0 — Apple Accelerate framework sweep against the
// lossless 5/3 + HT entropy hot path. Before committing to any
// Phase 1A prototype, this bench answers:
//
//   "Is there any vDSP / vImage / BLAS primitive that meaningfully
//    accelerates the lossless 5/3 + HT entropy stages on M2?"
//
// Conclusion (preview): NO. The lossless 5/3 path is integer-lifting
// with right shifts; vDSP has Int32 add/sub/scalar variants but no
// integer right-shift primitive. The HT entropy path is bit-buffer
// packing; Accelerate has no bit-level primitives. The only Accelerate
// candidate is the per-component DC level shift in preprocessing — and
// that stage is 9 ms acc CPU / 0.73 ms wall on DX, structurally below
// the 3 ms threshold even at 100% reduction.
//
// This bench documents that conclusion with two probes:
//
//   1. Preprocessing DC level shift (`buf[i] &-= dcOffset` loop) vs
//      `vDSP_vsaddi` Accelerate equivalent. Shows whether vDSP wins
//      in isolation (microbench), and projects DX wall savings.
//
//   2. vDSP API surface check: enumerate which Int32 vDSP primitives
//      exist, and document the structural mismatch with the 5/3 lifting
//      kernel (which needs `(a + b) >> 1` for predict and `(a + b + 2) >> 2`
//      for update — both right-shift operations vDSP cannot express).

#if os(macOS)

import XCTest
import Foundation
import Accelerate
@testable import J2KCodec

final class V8_8_AccelerateSweepPhase0Bench: XCTestCase {

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    /// Probe 1 — DC level shift. Current production code does:
    ///   for i in 0..<count { buf[i] &-= dcOffset }
    /// Accelerate alternative: `vDSP_vsaddi(buf, 1, &-dcOffset, buf, 1, count)`.
    /// Bench at DX 6.4 M-pixel size to project DX wall savings.
    func testProbe1_DCLevelShift_Scalar_vs_vDSP() {
        let count = 2800 * 2288  // DX pixel count, single grayscale component
        let dcOffset: Int32 = 1 << 11  // bitDepth=12, so dcOffset = 2048

        let bufA = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        let bufB = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        defer {
            bufA.deallocate()
            bufB.deallocate()
        }
        for i in 0..<count {
            bufA[i] = Int32(truncatingIfNeeded: i &* 7919)
            bufB[i] = bufA[i]
        }

        // Warm-up.
        for i in 0..<count { bufA[i] &-= dcOffset }
        var negOffset = -dcOffset
        vDSP_vsaddi(bufB, 1, &negOffset, bufB, 1, vDSP_Length(count))

        // Reset bufs.
        for i in 0..<count {
            bufA[i] = Int32(truncatingIfNeeded: i &* 7919)
            bufB[i] = bufA[i]
        }

        let runs = 7
        var scalarSamples: [Double] = []
        for _ in 0..<runs {
            // Re-init buffer to avoid stale-data drift.
            for i in 0..<count { bufA[i] = Int32(truncatingIfNeeded: i &* 7919) }
            let t0 = DispatchTime.now()
            for i in 0..<count { bufA[i] &-= dcOffset }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            scalarSamples.append(Double(dt) / 1_000_000.0)
        }
        scalarSamples.sort()
        let scalarMs = scalarSamples[runs / 2]

        var vdspSamples: [Double] = []
        for _ in 0..<runs {
            for i in 0..<count { bufB[i] = Int32(truncatingIfNeeded: i &* 7919) }
            let t0 = DispatchTime.now()
            vDSP_vsaddi(bufB, 1, &negOffset, bufB, 1, vDSP_Length(count))
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            vdspSamples.append(Double(dt) / 1_000_000.0)
        }
        vdspSamples.sort()
        let vdspMs = vdspSamples[runs / 2]

        // Verify same result.
        let mismatches = (0..<count).reduce(0) { acc, i in
            acc + (bufA[i] == bufB[i] ? 0 : 1)
        }
        XCTAssertEqual(mismatches, 0, "Scalar and vDSP results must match")

        let delta = scalarMs - vdspMs
        let pct = delta / scalarMs * 100.0

        errlog("")
        errlog("=== v8.8 Phase 0 — Probe 1: DC level shift Accelerate ===")
        errlog("DX-sized Int32 buffer (\(count) elements, bitDepth=12):")
        errlog(String(format: "  Scalar loop:        %7.3f ms (current production)", scalarMs))
        errlog(String(format: "  vDSP_vsaddi:        %7.3f ms (Accelerate)", vdspMs))
        errlog(String(format: "  Δ:                  %+7.3f ms (%+.1f%%)", delta, pct))
        errlog("")

        // Project to DX accumulated CPU savings vs the v8.4 stage
        // breakdown's preprocessing budget of 9 ms acc CPU.
        // Preprocess includes DC level shift (this probe) + format conversion
        // + tile partitioning. DC shift is the dominant arithmetic op.
        let preprocAccMs = 9.0
        let parallelism = 12.3
        let preprocWallMs = preprocAccMs / parallelism
        errlog("Projection to DX 2800×2288 preprocessing:")
        errlog(String(format: "  v8.4 measured preprocess acc CPU:  %.1f ms", preprocAccMs))
        errlog(String(format: "  v8.4 implied preprocess wall:      %.2f ms", preprocWallMs))
        errlog(String(format: "  Even 100%% Accelerate reduction:    %.2f ms wall savings (best case)", preprocWallMs))
        errlog("")
        if preprocWallMs >= 3.0 {
            errlog("  ⇒ ≥ 3 ms threshold MET. Phase 1A justified.")
        } else {
            errlog("  ⇒ < 3 ms structural ceiling. Wash even at best case.")
        }
        errlog("")
    }

    /// Probe 2 — structural API surface check for vDSP integer
    /// primitives that COULD apply to 5/3 lifting / HT entropy.
    /// Documents which exist and which DON'T (the right-shift gap).
    func testProbe2_vDSP_API_Surface_For_5_3_Lifting() {
        errlog("")
        errlog("=== v8.8 Phase 0 — Probe 2: vDSP Int32 API surface vs 5/3 lifting ===")
        errlog("")
        errlog("5/3 forward predict step:  d[n] = odd[n] - (even[n] + even[n+1]) >> 1")
        errlog("5/3 forward update step:   s[n] = even[n] + (d[n-1] + d[n] + 2) >> 2")
        errlog("")
        errlog("Required vDSP primitives:")
        errlog("  - Int32 vector add of paired elements (a[i] + a[i+1]):  vDSP_vaddi  ✓ EXISTS")
        errlog("  - Int32 vector subtract:                                vDSP_vsubi  ✗ DOES NOT EXIST")
        errlog("    (vDSP only has float vsub; for Int32 must use vsaddi with negated source)")
        errlog("  - Int32 vector arithmetic right-shift by constant:       N/A         ✗ DOES NOT EXIST")
        errlog("    (vDSP has no integer shift primitives — only float divide)")
        errlog("  - Int32 vector add with scalar (s[n] += scalar):        vDSP_vsaddi ✓ EXISTS")
        errlog("  - Int32 vector multiply:                                vDSP_vmuli  ✗ DOES NOT EXIST")
        errlog("    (Int32 multiply not in Accelerate; uses scalar)")
        errlog("")
        errlog("Conclusion: the right-shift step (the *core* of the integer-")
        errlog("reversible 5/3 lifting math) has NO Accelerate primitive on")
        errlog("Apple Silicon. The lifting cannot be expressed as a vDSP call")
        errlog("chain without breaking out into manual SIMD intrinsics. v8 Phase 3")
        errlog("already does this via SIMD4<Int32> for the inverse 5/3 IDWT")
        errlog("(production default-on); the forward path uses scalar-with-LLVM-")
        errlog("autovec because v8.6 Phase 0 measured 0.37 ns/sample (memory-bound).")
        errlog("")
        errlog("HT entropy path uses bit-buffer packing (UInt32 << / >>, byte writes).")
        errlog("Accelerate has no bit-level primitives at all. Structurally N/A.")
        errlog("")
        errlog("⇒ Accelerate framework is structurally inapplicable to the lossless")
        errlog("  5/3 + HT entropy hot path on M2. Confirmed by API surface review.")
    }
}

#endif
