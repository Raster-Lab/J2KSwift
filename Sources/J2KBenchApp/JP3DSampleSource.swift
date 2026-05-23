//
// JP3DSampleSource.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// The 3D analogue of `J2KSampleSource`. Builds synthetic JP3D volumes
// for the bench (LCG noise, deterministic per-fixture `seed`) and
// configures the canonical lossless HT-J2K JP3D encoder used by the
// bench / parity-oracle pipelines.
//
// J2KVolumeComponent stores multi-byte samples **little-endian** in
// `data` — confirmed by JP3DDecoderTests.swift helper `makeTestVolume`
// (`data[idx*bps + b] = UInt8(value >> (b*8))`). LCG synthesis writes
// the same way so a round-trip through the JP3D codec is bit-exact.

import Foundation
import J2KCore
import J2K3D

enum JP3DSampleSource {

    // MARK: - Encoder factory

    /// Canonical lossless HT-J2K JP3D encoder used by the bench, parity
    /// oracle, and Volumes-viewer round-trip. Matches the medical-archive
    /// target: lossless HTJ2K, default tiling, auto Z-delta.
    static func losslessHTEncoder() -> JP3DEncoder {
        let cfg = JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K,
            tiling: .default,
            progressionOrder: .lrcps,
            qualityLayers: 1,
            levelsX: 3,
            levelsY: 3,
            levelsZ: 1,        // slice-stack: Z-axis is by-slice, not 3D-wavelet
            parallelEncoding: true,
            zDeltaMode: .auto)
        return JP3DEncoder(configuration: cfg)
    }

    // MARK: - LCG volume synthesis

    /// Build a JP3DFixture's voxel volume from a deterministic 64-bit
    /// LCG seeded by `fixture.seed`. Same multiplier as the 2D
    /// `J2KSampleSource.synthesize` (`1442695040888963407`) so the
    /// synthesised data has comparable entropy across the 2D and 3D
    /// benches.
    ///
    /// Single component (modalities in this bench are grayscale — CT /
    /// MR / US — so 1 component matches reality and keeps the encoder
    /// path linear).
    static func synthesize(_ fixture: JP3DFixture) -> J2KVolume {
        let w = fixture.width
        let h = fixture.height
        let d = fixture.depth
        let voxelCount = w * h * d
        let bitDepth = fixture.bitDepth
        let bytesPerSample = (bitDepth + 7) / 8
        precondition(bytesPerSample == 1 || bytesPerSample == 2,
                     "JP3D bench supports 8-bit or 16-bit fixtures only")

        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: voxelCount * bytesPerSample)
        var s: UInt64 = fixture.seed &* 6364136223846793005 &+ 1442695040888963407

        data.withUnsafeMutableBytes { rawPtr in
            if bytesPerSample == 1 {
                let buf = rawPtr.bindMemory(to: UInt8.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    let sample = Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1)
                    buf[i] = UInt8(truncatingIfNeeded: sample)
                }
            } else {
                // 16-bit little-endian, matching JP3DDecoderTests.makeTestVolume
                let buf = rawPtr.bindMemory(to: UInt16.self)
                for i in 0..<voxelCount {
                    s = s &* 6364136223846793005 &+ 1442695040888963407
                    let sample = Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1)
                    buf[i] = UInt16(truncatingIfNeeded: sample)
                }
            }
        }

        let comp = J2KVolumeComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: w, height: h, depth: d,
            subsamplingX: 1, subsamplingY: 1, subsamplingZ: 1,
            data: data)

        // Spacing 1.0/axis is a sensible default for synthetic fixtures;
        // the MPR viewer reads spacing to size axial/sagittal/coronal
        // panes proportionally. Real DICOM would supply actual mm
        // spacing; synthetic uses isotropic.
        return J2KVolume(
            width: w, height: h, depth: d,
            components: [comp],
            spacingX: 1.0, spacingY: 1.0, spacingZ: 1.0)
    }
}
