// v10.2-research Phase D1.5-A — 4-byte SWAR MagSgn parity oracle.
//
// Compares the new C SWAR-4 refill path (`j2knhd_magsgn_init_swar` +
// `j2knhd_magsgn_read`) against the C scalar path (`j2knhd_magsgn_init`
// + `j2knhd_magsgn_read`) on identical byte streams + identical read
// plans. Bit-exact byte-by-byte parity is the gate.
//
// Also runs the same byte+plan combos against the Swift production
// path (HTMagSgnDecoderConformant with v7.4 SWAR enabled) — a triple-
// path equivalence check. If any of the three diverges on any seed,
// the SWAR port has a bug and must be fixed before D1.5-B.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_2_MagSgnSWARParityTests: XCTestCase {

    private struct ReadPlan { let widths: [Int] }

    private static func plan(seed: UInt64, length: Int) -> ReadPlan {
        var state = seed | 1
        var widths: [Int] = []
        widths.reserveCapacity(length)
        for _ in 0..<length {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            widths.append(Int((state >> 28) & 0x1F) + 1)
        }
        return ReadPlan(widths: widths)
    }

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

    private func cScalar(_ bytes: [UInt8], plan: ReadPlan) -> [UInt32] {
        var dec = j2knhd_magsgn()
        var out: [UInt32] = []
        out.reserveCapacity(plan.widths.count)
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_magsgn_init(&dec, buf.baseAddress, buf.count)
            for w in plan.widths {
                out.append(j2knhd_magsgn_read(&dec, Int32(w)))
            }
        }
        return out
    }

    private func cSwar(_ bytes: [UInt8], plan: ReadPlan) -> [UInt32] {
        var dec = j2knhd_magsgn()
        var out: [UInt32] = []
        out.reserveCapacity(plan.widths.count)
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_magsgn_init_swar(&dec, buf.baseAddress, buf.count)
            for w in plan.widths {
                out.append(j2knhd_magsgn_read(&dec, Int32(w)))
            }
        }
        return out
    }

    private func swiftProd(_ bytes: [UInt8], plan: ReadPlan) -> [UInt32] {
        // Swift production = v7.4 SWAR refill enabled (the default).
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        HTMagSgnDecoderConformant.neonRefillEnabled = true
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        defer {
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
        }
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var out: [UInt32] = []
        out.reserveCapacity(plan.widths.count)
        for w in plan.widths {
            out.append(dec.read(count: w))
        }
        return out
    }

    private func assertTripleParity(_ bytes: [UInt8], plan: ReadPlan, label: String) {
        let s = cScalar(bytes, plan: plan)
        let w = cSwar(bytes, plan: plan)
        let p = swiftProd(bytes, plan: plan)
        XCTAssertEqual(s, w, "\(label): C scalar vs C SWAR diverged")
        XCTAssertEqual(s, p, "\(label): C scalar vs Swift production diverged")
    }

    // MARK: - Dictionary edge cases

    func testParity_empty() {
        assertTripleParity([], plan: Self.plan(seed: 1, length: 32), label: "empty")
    }

    func testParity_allZeros() {
        assertTripleParity([UInt8](repeating: 0x00, count: 64),
                           plan: Self.plan(seed: 2, length: 96), label: "all-zero")
    }

    func testParity_allFF() {
        assertTripleParity([UInt8](repeating: 0xFF, count: 64),
                           plan: Self.plan(seed: 3, length: 96), label: "all-FF")
    }

    /// FF in every batch position (positions 0..15 within a 32-byte
    /// stream). Exercises FF-stuff carry across the SWAR batch boundary.
    func testParity_ffAtEveryPosition_32bytes() {
        for k in 0..<32 {
            var bytes = [UInt8](repeating: 0x55, count: 32)
            bytes[k] = 0xFF
            assertTripleParity(bytes,
                               plan: Self.plan(seed: UInt64(k) &+ 4, length: 48),
                               label: "FF-at-\(k)")
        }
    }

    /// Two FFs at adjacent positions. Carry-stuff across both bytes.
    func testParity_doubleFF_atBatchBoundaries() {
        for k in 0..<16 {
            var bytes = [UInt8](repeating: 0x55, count: 24)
            bytes[k] = 0xFF
            bytes[k + 1] = 0xFF
            assertTripleParity(bytes,
                               plan: Self.plan(seed: UInt64(k) &+ 100, length: 32),
                               label: "FFFF-at-\(k)")
        }
    }

    // MARK: - Random sweep (heavy)

    func testParity_randomBytesRandomWidths_512Trials() {
        for trial in 0..<512 {
            let len = 1 + trial % 96
            let bytes = Self.makeRandomBytes(count: len, seed: UInt64(trial) &* 0xC2B2AE3D27D4EB4F)
            let plan = Self.plan(seed: UInt64(trial) &* 0x9E3779B97F4A7C15, length: 96)
            assertTripleParity(bytes, plan: plan, label: "rand-\(trial)-len\(len)")
        }
    }

    func testParity_largeStreams() {
        for trial in 0..<64 {
            let len = 256 + trial * 32
            let bytes = Self.makeRandomBytes(count: len, seed: UInt64(0x5E5E5E5E5E5E5E5E) &+ UInt64(trial))
            let plan = Self.plan(seed: UInt64(trial) &+ 0xABCDEF, length: 1024)
            assertTripleParity(bytes, plan: plan, label: "large-\(trial)-len\(len)")
        }
    }

    /// Streams composed entirely of bytes ≥ 0x80, which exercise more
    /// of the slow path (most batches will hit at least one 0xFF
    /// candidate when uniformly distributed).
    func testParity_highByteHeavy() {
        for trial in 0..<32 {
            var state = (UInt64(trial) &* 0xDEADBEEF) | 1
            var bytes = [UInt8](repeating: 0, count: 256)
            for i in 0..<bytes.count {
                state &*= 6364136223846793005
                state &+= 1442695040888963407
                bytes[i] = UInt8(0x80 | ((state >> 32) & 0x7F))
            }
            let plan = Self.plan(seed: UInt64(trial), length: 256)
            assertTripleParity(bytes, plan: plan, label: "high-\(trial)")
        }
    }
}
#endif
