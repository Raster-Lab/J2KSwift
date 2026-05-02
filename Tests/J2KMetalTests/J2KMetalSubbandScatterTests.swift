// J2KMetalSubbandScatterTests.swift
//
// v5.7.0 (M4P-1) standalone bit-exactness test for the
// `j2k_subband_scatter` Metal kernel. Builds a synthetic
// codeblock buffer + per-block placement descriptors, runs the
// kernel, and asserts the per-subband 2D output matches an
// equivalent CPU-side scatter.

import XCTest
import J2KMetal

final class J2KMetalSubbandScatterTests: XCTestCase {

    /// Deterministic Int32 generator — gives a non-trivial pattern
    /// so we catch off-by-one offset / stride mistakes.
    private func makeBlockData(
        width: Int, height: Int, seed: Int32
    ) -> [Int32] {
        var out = [Int32](repeating: 0, count: width * height)
        for r in 0..<height {
            for c in 0..<width {
                out[r * width + c] = seed &* 100 &+ Int32(r * width + c)
            }
        }
        return out
    }

    /// Reference CPU scatter — does what the GPU kernel should do
    /// per descriptor. The test asserts GPU == CPU bitwise.
    private func cpuScatter(
        descriptors: [J2KMetalSubbandScatterDescriptor],
        codeblocks: [Int32],
        llDims: (Int, Int),
        lhDims: (Int, Int),
        hlDims: (Int, Int),
        hhDims: (Int, Int)
    ) -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32]) {
        var ll = [Int32](repeating: 0, count: llDims.0 * llDims.1)
        var lh = [Int32](repeating: 0, count: lhDims.0 * lhDims.1)
        var hl = [Int32](repeating: 0, count: hlDims.0 * hlDims.1)
        var hh = [Int32](repeating: 0, count: hhDims.0 * hhDims.1)
        for d in descriptors {
            for row in 0..<Int(d.blockHeight) {
                for col in 0..<Int(d.blockWidth) {
                    let src = Int(d.codeblockOffset) + row * Int(d.blockWidth) + col
                    let dstX = Int(d.subbandX) + col
                    let dstY = Int(d.subbandY) + row
                    let dstIdx = dstY * Int(d.subbandStride) + dstX
                    let value = codeblocks[src]
                    switch d.targetSubband {
                    case 0: ll[dstIdx] = value
                    case 1: lh[dstIdx] = value
                    case 2: hl[dstIdx] = value
                    default: hh[dstIdx] = value
                    }
                }
            }
        }
        return (ll, lh, hl, hh)
    }

    /// Single-codeblock-per-subband, rectangular subband grid: the
    /// minimum case that still touches all 4 subband bindings.
    func testSingleBlockPerSubband() async throws {
        try XCTSkipUnless(J2KMetalSubbandScatter.isAvailable, "Metal not available")

        let llDims = (32, 32)
        let lhDims = (32, 32)
        let hlDims = (32, 32)
        let hhDims = (32, 32)

        var codeblocks: [Int32] = []
        var descriptors: [J2KMetalSubbandScatterDescriptor] = []

        for (i, target) in zip(0..., [J2KMetalSubbandTarget.ll, .lh, .hl, .hh]) {
            let blockData = makeBlockData(width: 32, height: 32, seed: Int32(i + 1))
            let offset = UInt32(codeblocks.count)
            codeblocks.append(contentsOf: blockData)
            descriptors.append(J2KMetalSubbandScatterDescriptor(
                codeblockOffset: offset,
                blockWidth: 32, blockHeight: 32,
                subbandX: 0, subbandY: 0,
                subbandStride: 32,
                targetSubband: target.rawValue))
        }

        let scatter = J2KMetalSubbandScatter()
        let gpu = try await scatter.run(
            descriptors: descriptors, codeblocks: codeblocks,
            llDimensions: llDims, lhDimensions: lhDims,
            hlDimensions: hlDims, hhDimensions: hhDims)

        let cpu = cpuScatter(
            descriptors: descriptors, codeblocks: codeblocks,
            llDims: llDims, lhDims: lhDims, hlDims: hlDims, hhDims: hhDims)

        XCTAssertEqual(gpu.ll, cpu.ll, "LL mismatch")
        XCTAssertEqual(gpu.lh, cpu.lh, "LH mismatch")
        XCTAssertEqual(gpu.hl, cpu.hl, "HL mismatch")
        XCTAssertEqual(gpu.hh, cpu.hh, "HH mismatch")
    }

    /// Multiple codeblocks tiling each subband, varying block sizes
    /// within a subband. Stresses (subbandX, subbandY) placement
    /// and the block-bounds checks inside the kernel.
    func testTiledMultiBlockPerSubband() async throws {
        try XCTSkipUnless(J2KMetalSubbandScatter.isAvailable, "Metal not available")

        let subbandW = 64, subbandH = 64
        let dims = (subbandW, subbandH)

        var codeblocks: [Int32] = []
        var descriptors: [J2KMetalSubbandScatterDescriptor] = []

        // Tile each subband with 32x32 blocks (4 blocks per subband).
        for target in [J2KMetalSubbandTarget.ll, .lh, .hl, .hh] {
            for blkRow in 0..<2 {
                for blkCol in 0..<2 {
                    let blkIndex: Int32 = Int32(blkRow * 2 + blkCol) + 1
                    let seed: Int32 = Int32(target.rawValue) * 100 + blkIndex
                    let blockData = makeBlockData(
                        width: 32, height: 32, seed: seed)
                    let offset = UInt32(codeblocks.count)
                    codeblocks.append(contentsOf: blockData)
                    descriptors.append(J2KMetalSubbandScatterDescriptor(
                        codeblockOffset: offset,
                        blockWidth: 32, blockHeight: 32,
                        subbandX: UInt32(blkCol * 32),
                        subbandY: UInt32(blkRow * 32),
                        subbandStride: UInt32(subbandW),
                        targetSubband: target.rawValue))
                }
            }
        }

        let scatter = J2KMetalSubbandScatter()
        let gpu = try await scatter.run(
            descriptors: descriptors, codeblocks: codeblocks,
            llDimensions: dims, lhDimensions: dims,
            hlDimensions: dims, hhDimensions: dims)

        let cpu = cpuScatter(
            descriptors: descriptors, codeblocks: codeblocks,
            llDims: dims, lhDims: dims, hlDims: dims, hhDims: dims)

        XCTAssertEqual(gpu.ll, cpu.ll, "LL tiled mismatch")
        XCTAssertEqual(gpu.lh, cpu.lh, "LH tiled mismatch")
        XCTAssertEqual(gpu.hl, cpu.hl, "HL tiled mismatch")
        XCTAssertEqual(gpu.hh, cpu.hh, "HH tiled mismatch")
    }

    /// Mixed block sizes (some smaller than the grid's max). The
    /// kernel must respect each block's own width/height and not
    /// scatter past it. Padded-zero subband regions stay zero.
    func testMixedBlockSizes() async throws {
        try XCTSkipUnless(J2KMetalSubbandScatter.isAvailable, "Metal not available")

        let subbandW = 80, subbandH = 80
        let dims = (subbandW, subbandH)

        var codeblocks: [Int32] = []
        var descriptors: [J2KMetalSubbandScatterDescriptor] = []

        // Two blocks into LL: a 64×40 at (0,0) and a 16×40 at (64,0).
        let big = makeBlockData(width: 64, height: 40, seed: 7)
        let bigOffset = UInt32(codeblocks.count)
        codeblocks.append(contentsOf: big)
        descriptors.append(J2KMetalSubbandScatterDescriptor(
            codeblockOffset: bigOffset,
            blockWidth: 64, blockHeight: 40,
            subbandX: 0, subbandY: 0,
            subbandStride: UInt32(subbandW),
            targetSubband: J2KMetalSubbandTarget.ll.rawValue))

        let small = makeBlockData(width: 16, height: 40, seed: 11)
        let smallOffset = UInt32(codeblocks.count)
        codeblocks.append(contentsOf: small)
        descriptors.append(J2KMetalSubbandScatterDescriptor(
            codeblockOffset: smallOffset,
            blockWidth: 16, blockHeight: 40,
            subbandX: 64, subbandY: 0,
            subbandStride: UInt32(subbandW),
            targetSubband: J2KMetalSubbandTarget.ll.rawValue))

        let scatter = J2KMetalSubbandScatter()
        let gpu = try await scatter.run(
            descriptors: descriptors, codeblocks: codeblocks,
            llDimensions: dims, lhDimensions: dims,
            hlDimensions: dims, hhDimensions: dims)

        let cpu = cpuScatter(
            descriptors: descriptors, codeblocks: codeblocks,
            llDims: dims, lhDims: dims, hlDims: dims, hhDims: dims)

        XCTAssertEqual(gpu.ll, cpu.ll, "mixed-size LL mismatch")
        // The other subbands had no descriptors → must be all zeros.
        XCTAssertTrue(gpu.lh.allSatisfy { $0 == 0 })
        XCTAssertTrue(gpu.hl.allSatisfy { $0 == 0 })
        XCTAssertTrue(gpu.hh.allSatisfy { $0 == 0 })
    }
}
