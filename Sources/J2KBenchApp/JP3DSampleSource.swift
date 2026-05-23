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

    /// Build a JP3DFixture's voxel volume. Dispatches on
    /// `fixture.kind`:
    ///   • `.lcg` (default) — deterministic 64-bit LCG noise (the
    ///     legacy bench synthesis; multiplier matches the 2D side's
    ///     `J2KSampleSource.synthesize`).
    ///   • everything else — anatomical phantom from
    ///     `JP3DPhantomGenerator`, with per-modality mm spacing so the
    ///     MPR viewer's axial/sagittal/coronal panes render with
    ///     correct anatomical proportions.
    ///
    /// Single component throughout (the modalities in this bench are
    /// all grayscale).
    static func synthesize(_ fixture: JP3DFixture) -> J2KVolume {
        return JP3DPhantomGenerator.generate(
            kind: fixture.kind,
            width: fixture.width, height: fixture.height, depth: fixture.depth,
            bitDepth: fixture.bitDepth,
            seed: fixture.seed)
    }
}
