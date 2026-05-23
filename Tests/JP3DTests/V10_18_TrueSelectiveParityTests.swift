//
// V10_18_TrueSelectiveParityTests.swift
// J2KSwift
//
// v10.18-research — JP3D true partial-resolution / ROI parity oracle.
//
// Establishes the *specification* the JP3D codec MUST satisfy as the
// v10.18 arc replaces "decode then crop" / stubbed-resolutionLevel
// with true selective decode. These tests are the regression guard
// across Phases 2-4:
//
//   • Phase 2 (port `maxResolutionLevel` from 2D `extractTileData`
//     into JP3DSliceStackCodec): `testPartialResolutionShape` and
//     `testPartialResolutionLLBandIsAFullDecodeLLBand` are XCTSkip'd
//     today (the field is stubbed) and become active gates once
//     Phase 2 lands.
//
//   • Phase 3 (port ROI footprint-skip into JP3DROIDecoder, replacing
//     decode-then-crop): `testROIDecodeMatchesFullDecodeCropped`
//     guards bit-exactness across the change. Today it passes
//     trivially (the implementation IS decode-then-crop); after
//     Phase 3 it must still pass (true ROI must produce identical
//     output as the cropped full decode).
//
//   • Phase 4 (tile-skip): subsumed by the ROI parity test — if
//     tile-skip skips a tile whose footprint *does* overlap the
//     region, the ROI test will fail. So this file's parity gate
//     covers Phases 3 + 4 jointly.
//
//   • Baseline `testFullDecodeLosslessRoundTripBaseline` is a sanity
//     anchor: confirms our LCG-style synthesised volumes survive a
//     full encode/decode round-trip bit-exact, so any later parity
//     failure is unambiguously about partial-res / ROI, not the
//     underlying codec.

import XCTest
@testable import J2KCore
@testable import J2K3D

final class V10_18_TrueSelectiveParityTests: XCTestCase {

    // MARK: - Test fixture builder

    /// One deterministic 16-bit grayscale test volume used across the
    /// file. Smaller than the bench fixtures (compile-time test, not
    /// a bench) but large enough that resolution-level-1 produces
    /// meaningful spatial downsampling. Same LCG synthesis the
    /// J2KBenchApp Volumes tab uses, so behaviour observed here maps
    /// directly to what the iOS MPR viewer renders for the
    /// `mr_3d_small` / `ct_3d_small` corpus fixtures.
    private func makeLCGVolume(
        width: Int = 64, height: Int = 64, depth: Int = 8,
        bitDepth: Int = 16, seed: UInt64 = 0xC0FFEE
    ) -> J2KVolume {
        let bytesPerSample = (bitDepth + 7) / 8
        let voxelCount = width * height * depth
        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: voxelCount * bytesPerSample)
        var s: UInt64 = seed &* 6364136223846793005 &+ 1442695040888963407
        data.withUnsafeMutableBytes { raw in
            if bytesPerSample == 1 {
                let p = raw.bindMemory(to: UInt8.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    p[i] = UInt8(truncatingIfNeeded: Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                }
            } else {
                let p = raw.bindMemory(to: UInt16.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                }
            }
        }
        let comp = J2KVolumeComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height, depth: depth,
            data: data)
        return J2KVolume(
            width: width, height: height, depth: depth,
            components: [comp])
    }

    /// Reads a single voxel as an Int, honouring the component's bit
    /// depth and the little-endian byte order J2KVolumeComponent uses
    /// (per `JP3DDecoderTests.makeTestVolume`).
    private func voxelValue(in volume: J2KVolume,
                            x: Int, y: Int, z: Int,
                            comp: Int = 0) -> Int {
        guard comp < volume.components.count else { return 0 }
        let c = volume.components[comp]
        let bps = c.bytesPerSample
        let i = ((z * c.height * c.width) + y * c.width + x) * bps
        guard i + bps <= c.data.count else { return 0 }
        return c.data.withUnsafeBytes { raw -> Int in
            switch bps {
            case 1: return Int(raw[i])
            case 2: return Int(raw[i]) | (Int(raw[i + 1]) << 8)
            case 3: return Int(raw[i]) | (Int(raw[i + 1]) << 8) | (Int(raw[i + 2]) << 16)
            case 4: return Int(raw[i]) | (Int(raw[i + 1]) << 8)
                  | (Int(raw[i + 2]) << 16) | (Int(raw[i + 3]) << 24)
            default: return 0
            }
        }
    }

    private func encodeLossless(_ volume: J2KVolume) async throws -> Data {
        let cfg = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
        return try await JP3DEncoder(configuration: cfg).encode(volume).data
    }

    // MARK: - Baseline: full-decode lossless round-trip

    /// Sanity anchor: an LCG-noise volume survives encode→decode
    /// bit-exact via the canonical JP3DDecoder. If this fails, any
    /// partial-res / ROI parity failure below is meaningless — fix
    /// the codec round-trip first.
    func testFullDecodeLosslessRoundTripBaseline() async throws {
        let volume = makeLCGVolume()
        let codestream = try await encodeLossless(volume)
        let decoded = try await JP3DDecoder().decode(codestream).volume

        XCTAssertEqual(decoded.width,  volume.width)
        XCTAssertEqual(decoded.height, volume.height)
        XCTAssertEqual(decoded.depth,  volume.depth)
        XCTAssertEqual(decoded.components.count, volume.components.count)

        for z in 0..<volume.depth {
            for y in 0..<volume.height {
                for x in 0..<volume.width {
                    let want = voxelValue(in: volume,  x: x, y: y, z: z)
                    let got  = voxelValue(in: decoded, x: x, y: y, z: z)
                    if want != got {
                        XCTFail("Voxel mismatch at (\(x),\(y),\(z)): "
                                + "want=\(want) got=\(got)")
                        return
                    }
                }
            }
        }
    }

    // MARK: - ROI parity (Phase 3 + Phase 4 regression guard)

    /// **Specification**: for any sub-volume region R inside the full
    /// volume, `JP3DROIDecoder.decode(.., region: R).volume` is
    /// bit-identical to the in-region voxels of
    /// `JP3DDecoder.decode(..).volume`.
    ///
    /// Today: passes trivially because JP3DROIDecoder *is* decode-
    /// then-crop. After Phase 3 (true footprint-skip) and Phase 4
    /// (tile-skip), it must STILL pass — the v10.18 changes are
    /// performance optimisations, not behaviour changes.
    func testROIDecodeMatchesFullDecodeCropped() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 8)
        let codestream = try await encodeLossless(volume)
        let full = try await JP3DDecoder().decode(codestream).volume

        // Centre-ish region (offsets even so the encoder's 2x sub-
        // sampled tile grid doesn't fight the boundary).
        let region = JP3DRegion(x: 16..<48, y: 16..<48, z: 2..<6)
        let roi = try await JP3DROIDecoder().decode(codestream, region: region).volume

        XCTAssertEqual(roi.width,  region.x.count)
        XCTAssertEqual(roi.height, region.y.count)
        XCTAssertEqual(roi.depth,  region.z.count)

        for (zi, z) in region.z.enumerated() {
            for (yi, y) in region.y.enumerated() {
                for (xi, x) in region.x.enumerated() {
                    let want = voxelValue(in: full, x: x, y: y, z: z)
                    let got  = voxelValue(in: roi, x: xi, y: yi, z: zi)
                    if want != got {
                        XCTFail("ROI voxel mismatch at "
                                + "full(\(x),\(y),\(z)) "
                                + "roi(\(xi),\(yi),\(zi)): "
                                + "want=\(want) got=\(got)")
                        return
                    }
                }
            }
        }
    }

    /// Edge-region variant: a region at the (0,0,0) corner.
    /// Catches off-by-one in any future origin-handling logic when
    /// Phase 3's code-block footprint-skip lands.
    func testROIDecodeMatchesFullDecodeCroppedAtCorner() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 8)
        let codestream = try await encodeLossless(volume)
        let full = try await JP3DDecoder().decode(codestream).volume

        let region = JP3DRegion(x: 0..<24, y: 0..<24, z: 0..<4)
        let roi = try await JP3DROIDecoder().decode(codestream, region: region).volume

        for (zi, z) in region.z.enumerated() {
            for (yi, y) in region.y.enumerated() {
                for (xi, x) in region.x.enumerated() {
                    let want = voxelValue(in: full, x: x, y: y, z: z)
                    let got  = voxelValue(in: roi, x: xi, y: yi, z: zi)
                    if want != got {
                        XCTFail("Corner-ROI voxel mismatch at "
                                + "full(\(x),\(y),\(z)) "
                                + "roi(\(xi),\(yi),\(zi)): "
                                + "want=\(want) got=\(got)")
                        return
                    }
                }
            }
        }
    }

    // MARK: - Partial-resolution parity (Phase 2 specification)

    /// **Specification**: `JP3DDecoderConfiguration.resolutionLevel = K`
    /// produces a volume with dimensions ⌈W / 2^K⌉ × ⌈H / 2^K⌉ × D
    /// (Z is per-slice so not affected by the X/Y wavelet
    /// resolution).
    ///
    /// POST-PHASE-2 (v10.18-research): this test is an active gate.
    /// JP3DDecoderConfiguration.resolutionLevel = K routes through
    /// JP3DSliceStackCodec.decode(..., resolutionLevel: K) which in
    /// turn routes each per-slice 2D codestream through
    /// J2KDecoder.decodeResolution(level: N-K) (v10.5.0).
    func testPartialResolutionShape() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 8)
        let codestream = try await encodeLossless(volume)

        let cfg = JP3DDecoderConfiguration(resolutionLevel: 1)
        let half = try await JP3DDecoder(configuration: cfg).decode(codestream).volume

        XCTAssertEqual(half.width,  (volume.width + 1) / 2,
                       "Phase 2: resolutionLevel=1 must downsample X by 2")
        XCTAssertEqual(half.height, (volume.height + 1) / 2,
                       "Phase 2: resolutionLevel=1 must downsample Y by 2")
        XCTAssertEqual(half.depth,  volume.depth,
                       "Phase 2: Z is per-slice — resolutionLevel doesn't downsample Z")
    }

    /// **Specification**: the partial-resolution decode of a JP3D
    /// volume at level K is — slice-by-slice — the 2D codec's
    /// `decodeResolution(level: N-K)` applied to that slice's
    /// codestream. Because JP3D slices are independent 2D
    /// codestreams (JP3DSliceStackCodec) and Phase 2 routes the
    /// per-slice 2D decode through `decodeResolution`, the JP3D
    /// partial-res output for slice z is *exactly* the 2D
    /// partial-res output applied to that slice.
    ///
    /// The structural property follows directly from the Phase 2
    /// implementation; this test asserts a measurable consequence:
    /// **deterministic per-slice output** (two decodes at the same
    /// `resolutionLevel` must produce byte-identical voxels) and the
    /// **dimension contract** above. A whole-slice byte-exact oracle
    /// against the 2D decoder would require per-slice codestream
    /// extraction (an internal-only path); the deterministic +
    /// dimensional contract is the user-visible specification.
    func testPartialResolutionDeterministic() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 8)
        let codestream = try await encodeLossless(volume)

        let cfg = JP3DDecoderConfiguration(resolutionLevel: 1)
        let a = try await JP3DDecoder(configuration: cfg).decode(codestream).volume
        let b = try await JP3DDecoder(configuration: cfg).decode(codestream).volume

        XCTAssertEqual(a.width,  b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.depth,  b.depth)
        XCTAssertEqual(a.components.count, b.components.count)
        XCTAssertEqual(a.components.first?.data, b.components.first?.data)
    }

    /// **Specification**: at resolutionLevel = 0 (the default), the
    /// partial-res code path collapses to the full-resolution code
    /// path bit-exact. This is the backward-compatibility gate for
    /// Phase 2 — the existing JP3DDecoderTests suite asserts full-
    /// decode correctness; this test localises the contract to the
    /// new code path so a regression here surfaces with a smaller
    /// blast radius.
    func testResolutionLevel0IsBitExactFullDecode() async throws {
        let volume = makeLCGVolume(width: 48, height: 48, depth: 6)
        let codestream = try await encodeLossless(volume)

        let defaultDecoder = try await JP3DDecoder().decode(codestream).volume
        let level0Cfg = JP3DDecoderConfiguration(resolutionLevel: 0)
        let level0    = try await JP3DDecoder(configuration: level0Cfg)
            .decode(codestream).volume

        XCTAssertEqual(defaultDecoder.width,  level0.width)
        XCTAssertEqual(defaultDecoder.height, level0.height)
        XCTAssertEqual(defaultDecoder.depth,  level0.depth)
        XCTAssertEqual(defaultDecoder.components.first?.data,
                       level0.components.first?.data,
                       "Phase 2 backward-compat: resolutionLevel:0 must be "
                       + "bit-identical to the default (no-config) decode.")
    }

    /// Higher-K validity gate: resolutionLevel=2 also produces a
    /// well-formed volume (just downsampled twice). Catches off-by-
    /// one in iteration over K (e.g. shifting K wrong by one in
    /// `down()` or in the 2D-level mapping).
    func testPartialResolutionLevel2Shape() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 6)
        let codestream = try await encodeLossless(volume)

        let cfg = JP3DDecoderConfiguration(resolutionLevel: 2)
        let quarter = try await JP3DDecoder(configuration: cfg).decode(codestream).volume

        XCTAssertEqual(quarter.width,  (volume.width + 3) / 4,
                       "Phase 2: resolutionLevel=2 must downsample X by 4")
        XCTAssertEqual(quarter.height, (volume.height + 3) / 4,
                       "Phase 2: resolutionLevel=2 must downsample Y by 4")
        XCTAssertEqual(quarter.depth,  volume.depth)
    }

    /// Composition tripwire — combining `resolutionLevel > 0` with a
    /// ROI decoder is the Phase 5 future-work case. JP3DSliceStackCodec
    /// throws today rather than silently producing wrong output. When
    /// Phase 5 wires the combination through, this test will start
    /// passing the (currently absent) success branch — at that point
    /// invert the assertion to check the combined output instead.
    func testCombinedResolutionLevelAndROIIsPhase5Future() async throws {
        let volume = makeLCGVolume(width: 64, height: 64, depth: 8)
        let codestream = try await encodeLossless(volume)

        let cfg = JP3DDecoderConfiguration(resolutionLevel: 1)
        let region = JP3DRegion(x: 16..<48, y: 16..<48, z: 0..<4)

        do {
            _ = try await JP3DROIDecoder(configuration: cfg).decode(
                codestream, region: region)
            XCTFail("Phase 5 has landed — invert this assertion to verify "
                    + "the combined output instead.")
        } catch {
            // Expected today: JP3DSliceStackCodec.decode throws when
            // both resolutionLevel > 0 AND regionOfInterest are set.
            // The check happens per-tile during the ROI decode, so we
            // accept any error here.
        }
    }
}
