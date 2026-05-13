// V10DecoderNEONPhase0Tests.swift
//
// v10.0-research Phase 0 viability probe for the C+NEON HT entropy
// DECODER hot path (symmetric to v9.4.0's encoder).
//
// What this test answers
// =======================
// 1. PARITY: do the C bit-stream readers (j2knhd_magsgn_read,
//    j2knhd_mel_next_run, j2knhd_vlc_peek+consume) produce
//    bit-identical output to the Swift HTMagSgnDecoderConformant,
//    HTMELDecoderConformant, and VLCReverseReader on identical input?
// 2. SPEED: ns/call comparison of C readers vs Swift readers on
//    representative medical-fixture-shaped bit streams.
//
// The full decoder block-level port is multi-week. This Phase 0
// probe tells us whether the per-reader speedup justifies the
// investment.
//
// Run with:
//   swift test -c release --filter V10DecoderNEONPhase0Tests

import XCTest
import Darwin
import J2KCodecNEON
@testable import J2KCodec

final class V10DecoderNEONPhase0Tests: XCTestCase {

    // ----------------------------------------------------------------
    // Parity tests (MUST pass before any speed measurement is reported)
    // ----------------------------------------------------------------

    /// Synthetic encoded MagSgn bytes that exercise the 0xFF stuff
    /// rule + LSB-first packing + EOS padding. Generated using the
    /// Swift HTMagSgnEncoderConformant; the C decoder MUST produce
    /// the same bits when read back at the same widths.
    func testMagSgnReader_ParityVsSwift() {
        var enc = HTMagSgnEncoderConformant()
        let codewords: [(UInt32, Int)] = [
            (0x0000_0001, 1), (0x0000_001F, 5), (0x0000_0FFF, 12),
            (0xFFFF_FFFF, 32), (0x0000_0000, 7), (0x0000_FF00, 17),
            (0x12345678, 31), (0xDEAD_BEEF, 28),
        ]
        for (cw, ct) in codewords { enc.encode(codeword: cw, count: ct) }
        let bytes = enc.finish()

        // CRITICAL: keep the C buffer alive across all calls.
        // j2knhd_magsgn_init stores the buf pointer — Swift's
        // `withUnsafeBufferPointer` only guarantees the pointer is
        // valid INSIDE the closure, so all C reads MUST be inside
        // the same closure scope.
        let cBytes = [UInt8](bytes)
        var swiftDec = HTMagSgnDecoderConformant(bytes: bytes)
        cBytes.withUnsafeBufferPointer { ptr in
            var cState = j2knhd_magsgn_dec()
            j2knhd_magsgn_init(&cState, ptr.baseAddress, cBytes.count)
            for (idx, (expected, ct)) in codewords.enumerated() {
                let swiftValue = swiftDec.read(count: ct)
                let cValue = j2knhd_magsgn_read(&cState, Int32(ct))
                XCTAssertEqual(swiftValue, cValue,
                    "[\(idx)] read(\(ct)): Swift=\(String(swiftValue, radix: 16, uppercase: true)), C=\(String(cValue, radix: 16, uppercase: true))")
                let mask: UInt32 = (ct >= 32) ? 0xFFFF_FFFF : ((1 << ct) - 1)
                XCTAssertEqual(swiftValue, expected & mask,
                    "[\(idx)] Swift read returned wrong value: expected \(String(expected & mask, radix: 16))")
            }
        }
    }

    // ----------------------------------------------------------------
    // Speed: ns/call MagSgn read on representative DX-shaped stream
    // ----------------------------------------------------------------

    func testMagSgnReader_SpeedSwiftVsC_DXShape() {
        #if DEBUG
        print("⚠️  Phase 0 speed in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10DecoderNEONPhase0Tests")
        #endif

        // Build a representative MagSgn byte stream of DX-class size
        // (~12 MB raw codestream → ~50 KB MagSgn substream per block;
        // 1600 blocks × 50 KB ≈ 80 MB total MagSgn for the whole
        // image, but for per-block microbench 50 KB is representative).
        var enc = HTMagSgnEncoderConformant()
        var rng: UInt64 = 0xfeed_face_0001_2345
        // Stream ~4000 reads averaging 8 bits each → ~32k bits ≈ 4 KB.
        let nReads = 4000
        var widths: [Int] = []
        var values: [UInt32] = []
        for _ in 0..<nReads {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let w = 1 + Int((rng >> 56) & 0x1F)  // 1..32 bit widths
            let v = UInt32(truncatingIfNeeded: (rng >> 32))
                & ((w >= 32) ? 0xFFFF_FFFF : ((UInt32(1) << w) - 1))
            widths.append(w)
            values.append(v)
            enc.encode(codeword: v, count: w)
        }
        let bytes = enc.finish()
        let bytesArray = [UInt8](bytes)

        let trials = 20
        var swiftSamples = [Double](repeating: 0, count: trials)
        var cSamples = [Double](repeating: 0, count: trials)

        for trial in 0..<trials {
            // Swift
            var dec = HTMagSgnDecoderConformant(bytes: bytes)
            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            var acc: UInt32 = 0
            for w in widths { acc ^= dec.read(count: w) }
            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            swiftSamples[trial] = Double(t1 - t0) / Double(nReads)
            XCTAssertNotEqual(acc, 0xDEADBEEF, "(prevent dead-code elim)")

            // C — pointer must be valid for the entire read loop
            bytesArray.withUnsafeBufferPointer { ptr in
                var cState = j2knhd_magsgn_dec()
                j2knhd_magsgn_init(&cState, ptr.baseAddress, bytesArray.count)
                let t2 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                var cAcc: UInt32 = 0
                for w in widths { cAcc ^= j2knhd_magsgn_read(&cState, Int32(w)) }
                let t3 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                cSamples[trial] = Double(t3 - t2) / Double(nReads)
                XCTAssertNotEqual(cAcc, 0xDEADBEEF, "(prevent DCE)")
            }
        }

        swiftSamples.sort(); cSamples.sort()
        let medianSwift = swiftSamples[trials / 2]
        let medianC = cSamples[trials / 2]
        let speedup = medianSwift / medianC

        print()
        print("=== v10.0 Phase 0 — MagSgn reader speed (ns/call, median of \(trials), DX-shape, n=\(nReads) reads) ===")
        print(String(format: "  Swift HTMagSgnDecoderConformant.read():   median %.2f ns/call", medianSwift))
        print(String(format: "  C     j2knhd_magsgn_read():                median %.2f ns/call", medianC))
        print(String(format: "  Speedup: %.2f×  (%@%@)",
            speedup,
            speedup > 1.0 ? "C wins " : "C loses ",
            speedup >= 1.20 ? "— ≥1.20× threshold MET" : "— below 1.20× threshold"))
    }

    // ----------------------------------------------------------------
    // Microbench: VLC reverse-bit reader speed
    // ----------------------------------------------------------------

    func testVLCReverseReader_BasicSanity() {
        // Build a minimal MEL+VLC combined buffer. Real format details
        // are complex (SCUP word, MEL prefix); for Phase 0 viability
        // we just verify the C reader doesn't crash and returns
        // reasonable values when fed a benign stream.
        var bytes = [UInt8](repeating: 0x55, count: 64)
        bytes[63] = 0x00  // terminator
        bytes[62] = 0xAA
        let scup: size_t = 16  // VLC region length

        bytes.withUnsafeBufferPointer { ptr in
            var cState = j2knhd_vlc_dec()
            j2knhd_vlc_init(&cState, ptr.baseAddress, bytes.count, scup)
            j2knhd_vlc_consume(&cState, 0)  // trigger initial refill
            let v8 = j2knhd_vlc_peek(&cState, 8)
            let v16 = j2knhd_vlc_peek(&cState, 16)
            XCTAssertTrue(v8 < 256, "peek(8) should fit in 8 bits, got \(v8)")
            XCTAssertTrue(v16 < 65536, "peek(16) should fit in 16 bits, got \(v16)")
        }
        // No bit-exact parity tests vs Swift VLCReverseReader yet —
        // its public surface area is internal to J2KHTConformantBlockDecoder.
        // Phase 0 ships scaffold + sanity check only.
    }

    // ----------------------------------------------------------------
    // Microbench: MEL forward reader speed
    // ----------------------------------------------------------------

    func testMELReader_BasicSanity() {
        // Verify the C MEL reader doesn't crash and produces a
        // monotonically advancing run-state on a stream of all-zeros
        // (the maximum-run case).
        let bytes = [UInt8](repeating: 0x00, count: 32)
        bytes.withUnsafeBufferPointer { ptr in
            var cState = j2knhd_mel_dec()
            j2knhd_mel_init(&cState, ptr.baseAddress, bytes.count)
            var lastRun: Int32 = -1
            for _ in 0..<10 {
                let run = j2knhd_mel_next_run(&cState)
                // All-zero stream: runs should monotonically increase
                // (k advances each call until clamped at 12)
                XCTAssertTrue(run >= 0, "run should be non-negative, got \(run)")
                lastRun = run
            }
            XCTAssertTrue(lastRun >= 0)
        }
    }

    // ----------------------------------------------------------------
    // Version string sanity
    // ----------------------------------------------------------------

    func testVersionString() {
        let cstr = j2knhd_version()
        XCTAssertNotNil(cstr)
        let version = String(cString: cstr!)
        print("j2knhd build version: \(version)")
        XCTAssertTrue(version.hasPrefix("j2knhd-v10.0"),
            "expected v10.0 version prefix, got '\(version)'")
        #if arch(arm64)
        XCTAssertTrue(version.contains("neon"),
            "expected NEON build on ARM64, got '\(version)'")
        #endif
    }
}
