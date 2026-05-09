// V8_1_Phase1B_ParityTests.swift
//
// v8.1 Phase 1B production-integration parity. Sweeps the
// `HTMagSgnDecoderConformant.swarRefill8Enabled` flag across the
// scalar / v7.4-batched / v8.1-batched-8 paths and asserts that
// each path produces bit-identical `read(count:)` sequences on
// the same input bytes. This is the production-side analogue of
// the Phase 1A prototype parity sweep — but operating on the real
// `HTMagSgnDecoderConformant` struct (the one production code
// instantiates), not a separate prototype struct.
//
// The dispatch order is:
//   - swarRefill8Enabled = true                          → refillBatched8
//   - swarRefill8Enabled = false, neonRefillEnabled = true → refillBatched
//   - swarRefill8Enabled = false, neonRefillEnabled = false → refillScalar
//
// All three must produce the same read sequence. The 128-bit
// accumulator branch in `read()` is gated on `swarRefill8Enabled`,
// so this test also implicitly verifies that branch is bit-exact
// against the v7.4 64-bit shift on the same input.

import XCTest
@testable import J2KCodec

final class V8_1_Phase1B_ParityTests: XCTestCase {

    private func read(
        bytes: [UInt8],
        widths: [Int],
        useSwar8: Bool,
        useV74Batched: Bool
    ) -> [UInt32] {
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        defer {
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
        }
        HTMagSgnDecoderConformant.swarRefill8Enabled = useSwar8
        HTMagSgnDecoderConformant.neonRefillEnabled = useV74Batched
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var values: [UInt32] = []
        values.reserveCapacity(widths.count)
        for w in widths { values.append(dec.read(count: w)) }
        return values
    }

    /// Compares all three refill paths on the same input sequence.
    /// Asserts pairwise bit-equality.
    private func compareThreePaths(
        bytes: [UInt8],
        widths: [Int],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scalarSeq = read(bytes: bytes, widths: widths,
                             useSwar8: false, useV74Batched: false)
        let v74Seq    = read(bytes: bytes, widths: widths,
                             useSwar8: false, useV74Batched: true)
        let v81Seq    = read(bytes: bytes, widths: widths,
                             useSwar8: true,  useV74Batched: true)

        for i in 0..<widths.count {
            if scalarSeq[i] != v74Seq[i] {
                XCTFail("[\(label)] scalar≠v7.4 at i=\(i) w=\(widths[i]): " +
                    "scalar=0x\(String(scalarSeq[i], radix: 16)) " +
                    "v7.4=0x\(String(v74Seq[i], radix: 16))",
                    file: file, line: line)
                return
            }
            if scalarSeq[i] != v81Seq[i] {
                XCTFail("[\(label)] scalar≠v8.1 at i=\(i) w=\(widths[i]): " +
                    "scalar=0x\(String(scalarSeq[i], radix: 16)) " +
                    "v8.1=0x\(String(v81Seq[i], radix: 16))",
                    file: file, line: line)
                return
            }
        }
    }

    // MARK: - Boundary patterns

    func testParity_AllZero() {
        let bytes = [UInt8](repeating: 0x00, count: 64)
        let widths = (0..<32).map { _ in 14 }
        compareThreePaths(bytes: bytes, widths: widths, label: "all-zero × 64")
    }

    func testParity_AllFF_StuffBitsConstrained() {
        // Valid stream: 0xFF must be followed by a byte whose high
        // bit is 0. Pattern: [0xFF, 0x7F, 0xFF, 0x7F, ...].
        var bytes: [UInt8] = []
        for _ in 0..<32 { bytes.append(0xFF); bytes.append(0x7F) }
        let widths = (0..<32).map { _ in 14 }
        compareThreePaths(bytes: bytes, widths: widths, label: "FF/7F × 32")
    }

    func testParity_FFAtEvery8byteBatchBoundary() {
        // Place 0xFF at byte index 7 (last of first 8-byte batch),
        // 15 (last of second batch), etc. 0x00 at index 8, 16, …
        // — so the 0xFF's stuff-bit forces an unstuff at the
        // start of the NEXT 8-byte batch (the batch-spanning
        // case the prototype must handle correctly).
        var bytes = [UInt8](repeating: 0x55, count: 64)
        for i in stride(from: 7, to: 64, by: 8) {
            bytes[i] = 0xFF
            if i + 1 < bytes.count { bytes[i + 1] = 0x00 }
        }
        let widths = (0..<32).map { _ in 14 }
        compareThreePaths(bytes: bytes, widths: widths, label: "FF at 8-byte boundaries")
    }

    func testParity_FFInMiddleOfBatch() {
        // 0xFF in the middle of an 8-byte batch — slow-path fires
        // for that batch, fast-path for adjacent batches.
        var bytes = [UInt8](repeating: 0x55, count: 64)
        bytes[3] = 0xFF
        bytes[4] = 0x55  // already; high bit is 0
        bytes[20] = 0xFF
        bytes[21] = 0x10
        let widths = (0..<32).map { _ in 14 }
        compareThreePaths(bytes: bytes, widths: widths, label: "FF mid-batch")
    }

    // MARK: - Density sweep

    func testParity_RandomFFDensities() {
        let densities: [Double] = [0.0, 0.004, 0.01, 0.05, 0.10, 0.25]
        let seeds: [UInt64] = [0x1, 0xC0FFEE, 0xDEAD_BEEF, 0x123_456_789]
        for density in densities {
            for seed in seeds {
                let bytes = makeBytes(byteCount: 4096, ffProbability: density, seed: seed)
                for w in [3, 7, 14, 32] {
                    let widths = (0..<200).map { _ in w }
                    compareThreePaths(
                        bytes: bytes, widths: widths,
                        label: "rand density=\(density) seed=\(String(seed, radix: 16)) w=\(w)")
                }
            }
        }
    }

    // MARK: - Stream-exhaustion padding

    func testParity_StreamExhaustionPadding() {
        for size in [0, 1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33] {
            let bytes = (0..<size).map { UInt8($0 & 0x7F) }
            for w in [3, 7, 14, 32] {
                let widths = (0..<10).map { _ in w }
                compareThreePaths(bytes: bytes, widths: widths,
                    label: "exhaust size=\(size) w=\(w)")
            }
        }
    }

    // MARK: - Mixed read widths in one stream

    func testParity_MixedWidths() {
        let bytes = makeBytes(byteCount: 4096, ffProbability: 0.05, seed: 0xABC_DEF)
        // Realistic mix: short codewords, occasional 32-bit reads.
        let widths: [Int] = [
            3, 7, 5, 14, 4, 8, 12, 16, 22, 32, 1, 2, 9, 11, 14, 32, 7,
            5, 8, 14, 14, 14, 32, 10, 6, 4, 14, 14, 28, 31, 32, 1
        ]
        compareThreePaths(bytes: bytes, widths: widths, label: "mixed widths")
    }

    // MARK: - Helpers

    private func makeBytes(
        byteCount: Int,
        ffProbability: Double,
        seed: UInt64
    ) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        let threshold = UInt64(Double(UInt64.max) * ffProbability)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b: UInt8
            if lastWasFF {
                b = UInt8(truncatingIfNeeded: rng.next() & 0x7F)
                lastWasFF = false
            } else if rng.next() < threshold {
                b = 0xFF
                lastWasFF = true
            } else {
                b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
                if b == 0xFF { b = 0xFE }
                lastWasFF = false
            }
            out.append(b)
        }
        return out
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
