//
// J2KMetalDWT53IntOddOriginBitExactTests.swift
// J2KSwift
//
// v7.1.0 H2 — bit-exact validation of the parity-aware odd-origin
// inverse 5/3 kernels (`j2k_dwt_inverse_53_horizontal_int_odd` /
// `j2k_dwt_inverse_53_vertical_int_odd`) against the CPU reference
// from `J2KDWT1DOptimized.inverseTransform53OddOriginSymmetric`.
//
// **Why parity matters**: ISO/IEC 15444-1 Annex F.4.1.1 — when the
// band's canvas origin is odd at a given decomposition level, the
// 5/3 lifting boundary handling is different from the even-origin
// case (right-mirror only on the L update; flipped interleave order;
// special left/right tail cases on the H update). The even-origin
// inverse kernel produces wrong pixels when fed odd-origin band
// data — that's the "Defect B" the v7.1.0 H phase is closing.
//
// This test pins the new kernels' bit-exactness; the multi-tile
// per-tile production wire-in lands in a follow-up PR.

import XCTest
@testable import J2KMetal
@testable import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

final class J2KMetalDWT53IntOddOriginBitExactTests: XCTestCase {

    // MARK: - CPU reference (replicated locally — same logic as
    // J2KDWT1DOptimized.inverseTransform53OddOriginSymmetric)

    private static func referenceOddOrigin1DInverse53(
        lowpass: [Int32], highpass: [Int32]
    ) -> [Int32] {
        let lowCount = lowpass.count
        let highCount = highpass.count
        let n = lowCount + highCount

        var L = lowpass
        var H = highpass

        // Edge: single H sample only (n=1, lowCount=0).
        if lowCount == 0 {
            return H
        }

        // Step 1: undo update on L.
        //   L[i] -= ((H[i] + H[i+1] + 2) >> 2)
        // with right mirror H[i+1] → H[highCount - 1] when i+1 ≥ highCount.
        for i in 0..<lowCount {
            let left = H[i]
            let right = (i + 1 < highCount) ? H[i + 1] : H[highCount - 1]
            L[i] = L[i] &- ((left &+ right &+ 2) >> 2)
        }

        // Step 2: undo predict on H.
        //   H[0]   += L[0]
        //   H[i]   += ((L[i-1] + L[i]) >> 1)        for 1 ≤ i < min(highCount, lowCount)
        //   H[lowCount] += L[lowCount-1]            (right tail when n odd)
        if highCount > 0 {
            H[0] = H[0] &+ L[0]
        }
        let interiorEnd = min(highCount, lowCount)
        for i in 1..<interiorEnd {
            H[i] = H[i] &+ ((L[i - 1] &+ L[i]) >> 1)
        }
        if highCount > lowCount {
            H[lowCount] = H[lowCount] &+ L[lowCount - 1]
        }

        // Interleave (odd-origin):
        //   x[2i]   = H[i]
        //   x[2i+1] = L[i]
        var result = [Int32](repeating: 0, count: n)
        for i in 0..<lowCount { result[2 * i + 1] = L[i] }
        for i in 0..<highCount { result[2 * i] = H[i] }
        return result
    }

    // MARK: - GPU dispatch helpers

    /// Dispatch `j2k_dwt_inverse_53_horizontal_int_odd` for one or
    /// more rows and return the interleaved output.
    #if canImport(Metal)
    private func dispatchHorizOdd(
        lowpass: [Int32], highpass: [Int32],
        width: Int, height: Int
    ) async throws -> [Int32] {
        let device = J2KMetalDevice()
        try await device.initialize()
        let queue = try await device.commandQueue()
        let library = J2KMetalShaderLibrary()
        try await library.loadShaders(device: queue.device)
        let pipeline = try await library.computePipeline(for: .dwtInverse53HorizontalIntOdd)

        let lpBytes = lowpass.count * MemoryLayout<Int32>.stride
        let hpBytes = highpass.count * MemoryLayout<Int32>.stride
        let outCount = width * height
        let outBytes = outCount * MemoryLayout<Int32>.stride
        guard let lpBuf = queue.device.makeBuffer(length: max(4, lpBytes), options: .storageModeShared),
              let hpBuf = queue.device.makeBuffer(length: max(4, hpBytes), options: .storageModeShared),
              let outBuf = queue.device.makeBuffer(length: outBytes, options: .storageModeShared)
        else {
            XCTFail("Metal buffer allocation failed"); return []
        }
        if !lowpass.isEmpty {
            lowpass.withUnsafeBytes { src in
                lpBuf.contents().copyMemory(from: src.baseAddress!, byteCount: lpBytes)
            }
        }
        if !highpass.isEmpty {
            highpass.withUnsafeBytes { src in
                hpBuf.contents().copyMemory(from: src.baseAddress!, byteCount: hpBytes)
            }
        }
        memset(outBuf.contents(), 0, outBytes)

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            XCTFail("Failed to create command buffer/encoder"); return []
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(lpBuf, offset: 0, index: 0)
        enc.setBuffer(hpBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        var w = UInt32(width), h = UInt32(height)
        enc.setBytes(&w, length: 4, index: 3)
        enc.setBytes(&h, length: 4, index: 4)
        let grid = MTLSize(width: 1, height: height, depth: 1)
        let tg = MTLSize(width: 1, height: min(height, 32), depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
        await cb.completed()

        return [Int32](unsafeUninitializedCapacity: outCount) { dst, init_ in
            memcpy(dst.baseAddress!, outBuf.contents(), outBytes)
            init_ = outCount
        }
    }

    /// Dispatch the vertical odd-origin kernel.
    private func dispatchVertOdd(
        lowpass: [Int32], highpass: [Int32],
        width: Int, height: Int
    ) async throws -> [Int32] {
        let device = J2KMetalDevice()
        try await device.initialize()
        let queue = try await device.commandQueue()
        let library = J2KMetalShaderLibrary()
        try await library.loadShaders(device: queue.device)
        let pipeline = try await library.computePipeline(for: .dwtInverse53VerticalIntOdd)

        let lpBytes = lowpass.count * MemoryLayout<Int32>.stride
        let hpBytes = highpass.count * MemoryLayout<Int32>.stride
        let outCount = width * height
        let outBytes = outCount * MemoryLayout<Int32>.stride
        guard let lpBuf = queue.device.makeBuffer(length: max(4, lpBytes), options: .storageModeShared),
              let hpBuf = queue.device.makeBuffer(length: max(4, hpBytes), options: .storageModeShared),
              let outBuf = queue.device.makeBuffer(length: outBytes, options: .storageModeShared)
        else {
            XCTFail("Metal buffer allocation failed"); return []
        }
        if !lowpass.isEmpty {
            lowpass.withUnsafeBytes { src in
                lpBuf.contents().copyMemory(from: src.baseAddress!, byteCount: lpBytes)
            }
        }
        if !highpass.isEmpty {
            highpass.withUnsafeBytes { src in
                hpBuf.contents().copyMemory(from: src.baseAddress!, byteCount: hpBytes)
            }
        }
        memset(outBuf.contents(), 0, outBytes)

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            XCTFail("Failed to create command buffer/encoder"); return []
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(lpBuf, offset: 0, index: 0)
        enc.setBuffer(hpBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        var w = UInt32(width), h = UInt32(height)
        enc.setBytes(&w, length: 4, index: 3)
        enc.setBytes(&h, length: 4, index: 4)
        let grid = MTLSize(width: width, height: 1, depth: 1)
        let tg = MTLSize(width: min(width, 32), height: 1, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
        await cb.completed()

        return [Int32](unsafeUninitializedCapacity: outCount) { dst, init_ in
            memcpy(dst.baseAddress!, outBuf.contents(), outBytes)
            init_ = outCount
        }
    }
    #endif

    // MARK: - Helper: build per-row band data from interleaved pixels

    /// Given a row of pixels with **odd-origin** parity, produce the
    /// L (image-odd positions) and H (image-even positions) band rows.
    /// Used for round-trip tests (forward parity-aware odd → inverse
    /// parity-aware odd should recover the original).
    private static func splitOddOrigin(_ row: [Int32]) -> (L: [Int32], H: [Int32]) {
        var L: [Int32] = []
        var H: [Int32] = []
        for (i, v) in row.enumerated() {
            if i % 2 == 0 { H.append(v) } else { L.append(v) }
        }
        return (L, H)
    }

    // MARK: - 1D bit-exact tests

    /// Sanity: even-width row → lowCount == highCount (e.g. width=8
    /// gives lowCount=4, highCount=4).
    func testHoriz_EvenWidth_8_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 8, height = 1
        let lp: [Int32] = [10, 20, 30, 40]
        let hp: [Int32] = [-1, 2, -3, 4]
        let cpu = Self.referenceOddOrigin1DInverse53(lowpass: lp, highpass: hp)
        let gpu = try await dispatchHorizOdd(lowpass: lp, highpass: hp, width: width, height: height)
        XCTAssertEqual(gpu, cpu, "8-wide odd-origin horizontal mismatch")
    }

    /// Odd width — n odd → highCount > lowCount (right tail fires).
    func testHoriz_OddWidth_9_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 9, height = 1
        let lp: [Int32] = [10, 20, 30, 40]              // lowCount = 4
        let hp: [Int32] = [-1, 2, -3, 4, 5]             // highCount = 5
        let cpu = Self.referenceOddOrigin1DInverse53(lowpass: lp, highpass: hp)
        let gpu = try await dispatchHorizOdd(lowpass: lp, highpass: hp, width: width, height: height)
        XCTAssertEqual(gpu, cpu, "9-wide odd-origin horizontal mismatch")
    }

    /// Width=1 — only one H sample under odd-origin layout. Goes
    /// straight to output[0].
    func testHoriz_Width1_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 1, height = 1
        let lp: [Int32] = []
        let hp: [Int32] = [42]
        let cpu = Self.referenceOddOrigin1DInverse53(lowpass: lp, highpass: hp)
        let gpu = try await dispatchHorizOdd(lowpass: lp, highpass: hp, width: width, height: height)
        XCTAssertEqual(gpu, cpu, "Width=1 edge case mismatch")
    }

    /// Multiple rows in one dispatch — exercises the per-row `gid.y`
    /// indexing.
    func testHoriz_MultipleRows_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 7, height = 4   // lowCount=3, highCount=4 per row
        let perRowLow = 3, perRowHigh = 4
        var lp: [Int32] = []
        var hp: [Int32] = []
        var rng: UInt32 = 0xCAFE_BABE
        for _ in 0..<height {
            for _ in 0..<perRowLow {
                rng = rng &* 1_103_515_245 &+ 12_345
                lp.append(Int32(bitPattern: rng) >> 8)
            }
            for _ in 0..<perRowHigh {
                rng = rng &* 1_103_515_245 &+ 12_345
                hp.append(Int32(bitPattern: rng) >> 8)
            }
        }
        let gpu = try await dispatchHorizOdd(lowpass: lp, highpass: hp, width: width, height: height)
        for r in 0..<height {
            let lpRow = Array(lp[(r * perRowLow)..<((r + 1) * perRowLow)])
            let hpRow = Array(hp[(r * perRowHigh)..<((r + 1) * perRowHigh)])
            let cpuRow = Self.referenceOddOrigin1DInverse53(lowpass: lpRow, highpass: hpRow)
            let gpuRow = Array(gpu[(r * width)..<((r + 1) * width)])
            XCTAssertEqual(gpuRow, cpuRow, "row \(r) odd-origin mismatch")
        }
    }

    /// Vertical version of the basic 8-wide / 4-row case.
    func testVert_8x4_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 4, height = 8     // height even → lowCount=4, highCount=4
        let lpRows = 4, hpRows = 4
        var lp = [Int32](repeating: 0, count: lpRows * width)
        var hp = [Int32](repeating: 0, count: hpRows * width)
        var rng: UInt32 = 0xDEAD_BEEF
        for i in 0..<(lpRows * width) {
            rng = rng &* 1_103_515_245 &+ 12_345
            lp[i] = Int32(bitPattern: rng) >> 8
        }
        for i in 0..<(hpRows * width) {
            rng = rng &* 1_103_515_245 &+ 12_345
            hp[i] = Int32(bitPattern: rng) >> 8
        }

        let gpu = try await dispatchVertOdd(lowpass: lp, highpass: hp, width: width, height: height)

        // CPU reference per column.
        for col in 0..<width {
            var lpCol = [Int32](repeating: 0, count: lpRows)
            var hpCol = [Int32](repeating: 0, count: hpRows)
            for i in 0..<lpRows { lpCol[i] = lp[i * width + col] }
            for i in 0..<hpRows { hpCol[i] = hp[i * width + col] }
            let cpuCol = Self.referenceOddOrigin1DInverse53(lowpass: lpCol, highpass: hpCol)
            var gpuCol = [Int32](repeating: 0, count: height)
            for i in 0..<height { gpuCol[i] = gpu[i * width + col] }
            XCTAssertEqual(gpuCol, cpuCol, "col \(col) vertical odd-origin mismatch")
        }
    }

    /// Vertical odd height — exercises the right-tail H[lowCount] += L[lowCount-1]
    /// branch.
    func testVert_OddHeight_9_BitExact() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let width = 4, height = 9    // height odd → lowCount=4, highCount=5
        let lpRows = 4, hpRows = 5
        var lp = [Int32](repeating: 0, count: lpRows * width)
        var hp = [Int32](repeating: 0, count: hpRows * width)
        var rng: UInt32 = 0xFEED_F00D
        for i in 0..<(lpRows * width) {
            rng = rng &* 1_103_515_245 &+ 12_345
            lp[i] = Int32(bitPattern: rng) >> 8
        }
        for i in 0..<(hpRows * width) {
            rng = rng &* 1_103_515_245 &+ 12_345
            hp[i] = Int32(bitPattern: rng) >> 8
        }

        let gpu = try await dispatchVertOdd(lowpass: lp, highpass: hp, width: width, height: height)
        for col in 0..<width {
            var lpCol = [Int32](repeating: 0, count: lpRows)
            var hpCol = [Int32](repeating: 0, count: hpRows)
            for i in 0..<lpRows { lpCol[i] = lp[i * width + col] }
            for i in 0..<hpRows { hpCol[i] = hp[i * width + col] }
            let cpuCol = Self.referenceOddOrigin1DInverse53(lowpass: lpCol, highpass: hpCol)
            var gpuCol = [Int32](repeating: 0, count: height)
            for i in 0..<height { gpuCol[i] = gpu[i * width + col] }
            XCTAssertEqual(gpuCol, cpuCol, "col \(col) odd-height mismatch")
        }
    }

    // MARK: - Random sweep (deterministic)

    func testHorizRandomSweep_DeterministicSeeds() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        for seed in [UInt32(0xA1B2_C3D4),
                     UInt32(0xCAFE_F00D),
                     UInt32(0x0123_4567)] {
            for width in [2, 3, 4, 5, 6, 7, 8, 11, 16, 31, 32, 64, 65, 100] {
                let lpCount = width / 2
                let hpCount = width - lpCount
                guard hpCount > 0 else { continue }
                var rng = seed
                var lp = [Int32](repeating: 0, count: lpCount)
                var hp = [Int32](repeating: 0, count: hpCount)
                for i in 0..<lpCount {
                    rng = rng &* 1_103_515_245 &+ 12_345
                    lp[i] = Int32(bitPattern: rng) >> 12
                }
                for i in 0..<hpCount {
                    rng = rng &* 1_103_515_245 &+ 12_345
                    hp[i] = Int32(bitPattern: rng) >> 12
                }
                let cpu = Self.referenceOddOrigin1DInverse53(lowpass: lp, highpass: hp)
                let gpu = try await dispatchHorizOdd(lowpass: lp, highpass: hp,
                                                     width: width, height: 1)
                XCTAssertEqual(gpu, cpu,
                    "[seed=\(String(seed, radix: 16)) w=\(width)] random horiz odd-origin mismatch")
            }
        }
    }
}
