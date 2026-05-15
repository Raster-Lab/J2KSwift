// v10.1-research Phase D1 Phase 0 — VLC reverse-reader per-call microbench.
//
// Times Swift `VLCReverseReader` (scalar refill path, via
// `VLCReverseReaderTesting.runScalarReadPlan`) vs the scalar C
// `j2knhd_vlc_read()` over deterministic random byte corpora.
// VLC is the last of the three state-machine probes; combined with
// MEL (1.25-1.33×) and MagSgn (1.39×) this completes the Phase 0
// per-state-machine sweep for D1.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_VLCMicrobench: XCTestCase {

    private static func makeRandomBytes(count: Int, seed: UInt64) -> [UInt8] {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            bytes[i] = UInt8((state >> 32) & 0xFF)
        }
        return bytes
    }

    private struct Stats {
        let median: Double
        let min: Double
        let p99: Double
    }

    private static func summarise(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return Stats(median: 0, min: 0, p99: 0) }
        let p99idx = Int(Double(sorted.count - 1) * 0.99)
        return Stats(
            median: sorted[sorted.count / 2],
            min: sorted.first!,
            p99: sorted[p99idx])
    }

    /// Swift per-stream timing: total time for `widths.count` `read()`
    /// calls on a fresh `VLCReverseReader`. Pins the scalar refill
    /// path so we measure against the canonical reference. The
    /// helper itself is in `VLCReverseReaderTesting` since the
    /// struct is fileprivate; the helper sets/restores the flag
    /// and runs the scalar reads in a tight loop with no extra
    /// per-call allocation.
    private static func benchSwift(_ bytes: [UInt8], scup: Int, widths: [Int], streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = VLCReverseReaderTesting.runScalarReadPlan(
                bytes: bytes, scup: scup, widths: widths)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func benchC(_ bytes: [UInt8], scup: Int, widths: [Int], streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = j2knhd_vlc()
            bytes.withUnsafeBufferPointer { buf in
                j2knhd_vlc_init(&dec, buf.baseAddress, buf.count, Int32(scup))
                for w in widths {
                    _ = j2knhd_vlc_read(&dec, Int32(w))
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    func testPhaseD1Phase0_vlcMicrobench() {
        // Three input corpora; bytes determine refill cost. The
        // reverse-direction means we start consuming from byte[scup-2]
        // and walk backwards, so the input shape "from the back" is
        // what actually matters.
        let sparse = [UInt8](repeating: 0x00, count: 256)
        let dense  = [UInt8](repeating: 0xFF, count: 256)
        let random = Self.makeRandomBytes(count: 256, seed: 0x55AA00FFC0FFEE01)

        // Widths chosen to mimic real decoder usage:
        //   - 7-bit peek (table lookup)
        //   - cwd_len in [1..7]
        //   - occasional UVLC reads up to 16 bits
        var widthState: UInt64 = 0xC2B2AE3D27D4EB4F
        var widths: [Int] = []
        widths.reserveCapacity(64)
        for _ in 0..<64 {
            widthState &*= 6364136223846793005
            widthState &+= 1442695040888963407
            // Bias towards 1-7 bit reads (mimics VLC consume widths).
            let r = Int(widthState >> 28) & 0x1F
            widths.append(r < 16 ? (1 + (r % 7)) : (1 + (r % 24)))
        }

        let streams = 5_000

        // Warmups
        for _ in 0..<2 {
            _ = Self.benchSwift(random, scup: 128, widths: widths, streams: 200)
            _ = Self.benchC(random, scup: 128, widths: widths, streams: 200)
        }

        struct Row {
            let label: String
            let swift: Stats
            let c: Stats
            let ratio: Double
        }
        var rows: [Row] = []
        for (label, bytes) in [
            ("sparse 256B (00s)", sparse),
            ("dense 256B (FFs)", dense),
            ("random 256B", random)
        ] {
            let s = Self.benchSwift(bytes, scup: 128, widths: widths, streams: streams)
            let c = Self.benchC(bytes, scup: 128, widths: widths, streams: streams)
            rows.append(Row(label: label, swift: s, c: c, ratio: s.median / c.median))
        }

        print("")
        print("=== V10_1_VLC_MICROBENCH_BEGIN ===")
        print("VLC reverse-reader per-call cost — Swift VLCReverseReader (scalar pinned) vs scalar C j2knhd_vlc")
        print("M2 release, \(widths.count) read() calls per stream (mix of 1-7 + occasional 16-bit), \(streams) streams sampled per row")
        print("scup = 128, byte stream walked backwards from byte[126] to byte[0]")
        print("")
        print("| Corpus | Swift median ns/stream | Swift ns/call | C median ns/stream | C ns/call | Speedup |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let swiftPerCall = r.swift.median / Double(widths.count)
            let cPerCall = r.c.median / Double(widths.count)
            print(String(format: "| %@ | %.0f | %.1f | %.0f | %.1f | %.2fx |",
                         r.label, r.swift.median, swiftPerCall,
                         r.c.median, cPerCall, r.ratio))
        }
        print("")
        let geoMean = rows.map { $0.ratio }.reduce(1.0, *)
        let nthRoot = pow(geoMean, 1.0 / Double(rows.count))
        print(String(format: "Geometric mean speedup: %.2fx", nthRoot))
        print("Phase D1 Phase 0 gate threshold: ≥ 1.10x.")
        if nthRoot >= 1.10 {
            print("Status: PASS — VLC scalar C clears per-call gate.")
        } else if nthRoot >= 1.00 {
            print("Status: MARGINAL — VLC faster but below 10% threshold. Combined gate (MEL + MagSgn + VLC) still informative.")
        } else {
            print("Status: FAIL — VLC scalar C not faster than scalar Swift.")
        }
        print("=== V10_1_VLC_MICROBENCH_END ===")
        print("")

        for r in rows {
            XCTAssertGreaterThan(r.swift.median, 0)
            XCTAssertGreaterThan(r.c.median, 0)
        }
    }
}
#endif
