// V740NeonRefillParityTests.swift
//
// v7.4 NEON MagSgn refill — exhaustive bit-exact comparison of the
// scalar `refillScalar` reference path against the `refillBatched`
// SIMD-batched path. The batched path's correctness rests on the
// SWAR 0xFF-detect being equivalent to the scalar byte-by-byte
// detect; this gate proves that empirically across many byte
// sequences with realistic and adversarial 0xFF patterns.

import XCTest
@testable import J2KCodec

final class V740NeonRefillParityTests: XCTestCase {

    /// Read N bits from both paths on the same input bytes and
    /// assert byte-by-byte equality of the read sequence.
    private func compareReads(
        bytes: [UInt8],
        widths: [Int],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prev = HTMagSgnDecoderConformant.neonRefillEnabled
        defer { HTMagSgnDecoderConformant.neonRefillEnabled = prev }

        HTMagSgnDecoderConformant.neonRefillEnabled = false
        var scalar = HTMagSgnDecoderConformant(bytes: bytes)
        var scalarValues: [UInt32] = []
        for w in widths { scalarValues.append(scalar.read(count: w)) }

        HTMagSgnDecoderConformant.neonRefillEnabled = true
        var batched = HTMagSgnDecoderConformant(bytes: bytes)
        var batchedValues: [UInt32] = []
        for w in widths { batchedValues.append(batched.read(count: w)) }

        XCTAssertEqual(scalarValues.count, batchedValues.count,
            "[\(label)] read count mismatch", file: file, line: line)
        for i in 0..<min(scalarValues.count, batchedValues.count) {
            if scalarValues[i] != batchedValues[i] {
                XCTFail("[\(label)] read \(i) (width \(widths[i])): " +
                    "scalar=0x\(String(scalarValues[i], radix: 16)) " +
                    "batched=0x\(String(batchedValues[i], radix: 16))",
                    file: file, line: line)
                return
            }
        }
    }

    // MARK: - Sweep 1: all-zero, all-FF, alternating

    func testParity_AllZero() {
        let bytes: [UInt8] = [UInt8](repeating: 0x00, count: 64)
        let widths = (0..<32).map { _ in 14 }
        compareReads(bytes: bytes, widths: widths, label: "all-zero × 64")
    }

    func testParity_AllFF() {
        let bytes: [UInt8] = [UInt8](repeating: 0xFF, count: 64)
        let widths = (0..<32).map { _ in 14 }
        compareReads(bytes: bytes, widths: widths, label: "all-FF × 64 (max unstuff)")
    }

    func testParity_AlternatingFF00() {
        var bytes: [UInt8] = []
        for _ in 0..<32 { bytes.append(0xFF); bytes.append(0x00) }
        let widths = (0..<32).map { _ in 14 }
        compareReads(bytes: bytes, widths: widths, label: "FF/00 alternating × 64")
    }

    func testParity_AlternatingFFAA() {
        var bytes: [UInt8] = []
        for _ in 0..<32 { bytes.append(0xFF); bytes.append(0xAA) }
        let widths = (0..<32).map { _ in 14 }
        compareReads(bytes: bytes, widths: widths,
            label: "FF/AA alternating (high-bit unstuff exercised)")
    }

    // MARK: - Sweep 2: 0xFF at every position in a 4-byte batch

    /// Cover every 0xFF position (0..3) across batch boundaries —
    /// exercises the SWAR detect for each lane and the slow-path
    /// fallback. Each test places a 0xFF at one position in each
    /// 4-byte batch group and fills the rest with random bytes.
    func testParity_FFAtEachPositionInBatch() {
        for ffPos in 0..<4 {
            var rng = SplitMix64(seed: 0x1234_5678_DEAD_BEEF | UInt64(ffPos))
            var bytes: [UInt8] = []
            for batch in 0..<16 {
                for j in 0..<4 {
                    if j == ffPos {
                        bytes.append(0xFF)
                    } else {
                        bytes.append(UInt8(rng.next() & 0x7E))  // avoid accidental FF
                    }
                }
                _ = batch
            }
            let widths = (0..<14).map { _ in 14 }
            compareReads(bytes: bytes, widths: widths,
                label: "FF at batch position \(ffPos)")
        }
    }

    // MARK: - Sweep 3: random byte sequences

    func testParity_RandomSweep32Seeds() {
        for seedIdx in 0..<32 {
            let seed = UInt64(seedIdx) &* 0x9E37_79B9_7F4A_7C15 | 1
            var rng = SplitMix64(seed: seed)
            // Realistic-ish density of 0xFF (~0.4%) plus broad
            // byte distribution.
            var bytes: [UInt8] = []
            for _ in 0..<256 {
                let r = rng.next()
                if r < UInt64(0xFF_FF_FF_FF / 256) * 1 {
                    bytes.append(0xFF)
                } else {
                    bytes.append(UInt8(r & 0xFF))
                }
            }
            // Mixed read widths.
            var widths: [Int] = []
            var widthRng = SplitMix64(seed: seed ^ 0xDEAD_BEEF)
            for _ in 0..<60 {
                widths.append(Int(widthRng.next() & 0x1F) + 1)  // 1..32
            }
            compareReads(bytes: bytes, widths: widths,
                label: "random seed \(seedIdx)")
        }
    }

    // MARK: - Sweep 4: stream-exhaust padding

    /// Exercise the 0xFF padding path. The batched fast path and
    /// scalar tail both feed the same `while b <= 32 { byte = 0xFF
    /// }` once the stream runs out.
    func testParity_StreamExhaustPadding() {
        // 8 bytes — enough to refill once batched (32 bits) but
        // then we read 200 widths totalling > 256 bits so we pad.
        let bytes: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0]
        let widths = (0..<200).map { _ in 7 }
        compareReads(bytes: bytes, widths: widths,
            label: "8 bytes + 0xFF padding for 200 reads")
    }

    func testParity_StreamExhaustPaddingFromFFEnd() {
        // Stream ending in 0xFF — tests that carried unstuff state
        // is preserved across the buffer-to-padding boundary.
        let bytes: [UInt8] = [0x12, 0x34, 0xFF, 0x00, 0xFF]
        let widths = (0..<200).map { _ in 7 }
        compareReads(bytes: bytes, widths: widths,
            label: "stream ending in 0xFF then padding")
    }

    // MARK: - Sweep 5: empty / tiny streams

    func testParity_EmptyStream() {
        compareReads(bytes: [], widths: [7, 14, 32],
            label: "empty stream → all 0xFF padding")
    }

    func testParity_OneByteStreams() {
        for byte in [UInt8(0x00), 0x7F, 0x80, 0xAA, 0xFE, 0xFF] {
            compareReads(bytes: [byte], widths: [7, 7, 7, 7, 7],
                label: "1 byte = 0x\(String(byte, radix: 16))")
        }
    }

    func testParity_ThreeByteStreamUnderBatchSize() {
        // < 4 bytes: batched path can never use its fast 4-byte
        // step; it must still produce identical output via the
        // scalar tail loop.
        compareReads(bytes: [0x12, 0xFF, 0x80],
            widths: [7, 7, 7, 7, 7, 7, 7, 7, 7, 7],
            label: "3 bytes (< batch size)")
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
