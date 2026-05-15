// v10.2-research Phase D1.5-A — MagSgn SWAR-4 microbench vs Swift production.
//
// Phase D1.5-A gate: C SWAR-4 ≥ 1.10× Swift production on sparse + random
// corpora (Swift production = v7.4 4-byte SWAR refill, default-on). If
// the gate fails, D1.5-A closes per the v10.2 probe doc stop trigger.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_2_MagSgnSWARMicrobench: XCTestCase {

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

    private struct Stats { let median: Double; let min: Double; let p99: Double }

    private static func summarise(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        let med = sorted[sorted.count / 2]
        let p99idx = Int(Double(sorted.count - 1) * 0.99)
        return Stats(median: med, min: sorted.first!, p99: sorted[p99idx])
    }

    private static func makeWidths(count: Int, seed: UInt64) -> [Int] {
        var state = seed | 1
        var widths: [Int] = []
        widths.reserveCapacity(count)
        for _ in 0..<count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            widths.append(Int((state >> 28) & 0x0F) + 1)
        }
        return widths
    }

    private static func benchSwiftProduction(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        HTMagSgnDecoderConformant.neonRefillEnabled = true
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        defer {
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
        }
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = HTMagSgnDecoderConformant(bytes: bytes)
            for w in widths {
                _ = dec.read(count: w)
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func benchCSwar(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = j2knhd_magsgn()
            bytes.withUnsafeBufferPointer { buf in
                j2knhd_magsgn_init_swar(&dec, buf.baseAddress, buf.count)
                for w in widths {
                    _ = j2knhd_magsgn_read(&dec, Int32(w))
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func benchCScalar(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = j2knhd_magsgn()
            bytes.withUnsafeBufferPointer { buf in
                j2knhd_magsgn_init(&dec, buf.baseAddress, buf.count)
                for w in widths {
                    _ = j2knhd_magsgn_read(&dec, Int32(w))
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    func testPhaseD1_5A_swarMicrobench() {
        let sparse  = [UInt8](repeating: 0x00, count: 256)
        let dense   = [UInt8](repeating: 0xFF, count: 256)
        let random  = Self.makeRandomBytes(count: 256, seed: 0xABCDEF1234567890)
        let widths  = Self.makeWidths(count: 64, seed: 0xC0FFEE)
        for _ in 0..<2 {
            _ = Self.benchSwiftProduction(sparse, widths: widths, streams: 200)
            _ = Self.benchCSwar(sparse, widths: widths, streams: 200)
        }
        struct Row {
            let label: String
            let swiftProd: Stats
            let cScalar: Stats
            let cSwar: Stats
            let ratioVsProd: Double  // swiftProd / cSwar
            let ratioVsScalarC: Double  // cScalar / cSwar
        }
        var rows: [Row] = []
        let streams = 5_000
        for (label, bytes) in [
            ("sparse 256B (00s)", sparse),
            ("dense 256B (FFs)", dense),
            ("random 256B",      random)
        ] {
            let sProd  = Self.benchSwiftProduction(bytes, widths: widths, streams: streams)
            let cScal  = Self.benchCScalar(bytes, widths: widths, streams: streams)
            let cSwar  = Self.benchCSwar(bytes, widths: widths, streams: streams)
            rows.append(Row(label: label,
                            swiftProd: sProd,
                            cScalar: cScal,
                            cSwar: cSwar,
                            ratioVsProd: sProd.median / cSwar.median,
                            ratioVsScalarC: cScal.median / cSwar.median))
        }
        print("")
        print("=== V10_2_MAGSGN_SWAR_MICROBENCH_BEGIN ===")
        print("MagSgn per-read cost — Swift production (v7.4 SWAR) vs C scalar vs C SWAR-4")
        print("M2 release, \(widths.count) read() calls per stream, \(streams) streams sampled per row")
        print("")
        print("| Corpus | Swift prod ns/call | C scalar ns/call | C SWAR-4 ns/call | SWAR vs prod | SWAR vs C scalar |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let prodPerCall  = r.swiftProd.median / Double(widths.count)
            let scalPerCall  = r.cScalar.median  / Double(widths.count)
            let swarPerCall  = r.cSwar.median    / Double(widths.count)
            print(String(format: "| %@ | %.1f | %.1f | %.1f | %.2fx | %.2fx |",
                         r.label, prodPerCall, scalPerCall, swarPerCall,
                         r.ratioVsProd, r.ratioVsScalarC))
        }
        print("")
        // Phase D1.5-A gate: SWAR ≥ 1.10x Swift production on sparse + random.
        let sparseRow = rows.first { $0.label.hasPrefix("sparse") }!
        let randomRow = rows.first { $0.label.hasPrefix("random") }!
        let geoCriticalPair = sqrt(sparseRow.ratioVsProd * randomRow.ratioVsProd)
        print(String(format: "Geo mean (sparse + random) SWAR vs Swift production: %.2fx", geoCriticalPair))
        print("Phase D1.5-A gate: ≥ 1.10x.")
        if geoCriticalPair >= 1.10 {
            print("Status: PASS — C SWAR-4 clears Phase D1.5-A gate. Proceed to D1.5-B (per-block integration).")
        } else if geoCriticalPair >= 1.00 {
            print("Status: MARGINAL — C SWAR-4 ties or slightly beats Swift production on common cases.")
            print("Per v10.2 stop trigger (\"SWAR ≤ 1.05x Swift production → close\"):")
            if geoCriticalPair <= 1.05 {
                print("  ACTION: close D1.5-A. MagSgn lever ceiling reached even with NEON SWAR.")
            } else {
                print("  Borderline (1.05-1.10x); judgement call. Consider Phase D1.5-B integration A/B.")
            }
        } else {
            print("Status: FAIL — C SWAR-4 slower than Swift production. Close D1.5-A.")
        }
        print("=== V10_2_MAGSGN_SWAR_MICROBENCH_END ===")
        print("")
        for r in rows {
            XCTAssertGreaterThan(r.swiftProd.median, 0)
            XCTAssertGreaterThan(r.cSwar.median, 0)
        }
    }
}
#endif
