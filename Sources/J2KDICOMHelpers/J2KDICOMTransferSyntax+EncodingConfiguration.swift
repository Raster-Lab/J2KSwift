// J2KDICOMTransferSyntax+EncodingConfiguration.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1
//
// Maps a DICOM Transfer Syntax UID enum to a J2KEncodingConfiguration that,
// when used with `J2KEncoder`, produces a codestream that's compatible with
// the requested UID's wire format (Part 1 vs Part 15 / lossless vs lossy).
//
// Mirrors the pattern in Sources/J2KCLI/DICOMSupport.swift:217-240 but
// lifts it to a public, library-consumer-callable API.

import Foundation
import J2KCore
import J2KCodec

extension J2KDICOMTransferSyntax {

    /// Builds a `J2KEncodingConfiguration` whose output codestream matches
    /// this DICOM Transfer Syntax's wire format.
    ///
    /// For lossless UIDs, the returned configuration sets `lossless = true`
    /// (which forces `useReversibleFilter = true` per `J2KEncodingConfiguration`'s
    /// invariant) and `quality = 1.0`. For lossy UIDs, it sets a default
    /// `quality = psnrTarget / 50.0` (clamped to `[0.0, 1.0]`), `lossless = false`,
    /// and `useReversibleFilter = false` (selecting the irreversible 9/7
    /// DWT + ICT path).
    ///
    /// HTJ2K UIDs set `useHTJ2K = true` and `htj2kBlockFormat = .conformant`
    /// (so the resulting codestream is interoperable with OpenJPH 0.26+ and
    /// other Part-15 decoders — see [J2KEncodingConfiguration.htj2kBlockFormat]
    /// docs for the trade-off).
    ///
    /// Other knobs default to `J2KEncodingConfiguration`'s defaults — callers
    /// who need to override (e.g., a specific number of decomposition levels,
    /// a different progression order, a tile grid, multi-layer) should
    /// construct `J2KEncodingConfiguration` directly with the returned
    /// configuration as a starting point.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// import J2KDICOMHelpers
    /// import J2KCodec
    ///
    /// let ts = J2KDICOMTransferSyntax(uid: "1.2.840.10008.1.2.4.201")!
    /// let cfg = ts.encodingConfiguration(bitDepth: 16)
    /// let encoder = J2KEncoder(encodingConfiguration: cfg)
    /// let codestream = try await encoder.encode(image)
    /// ```
    ///
    /// - Parameters:
    ///   - bitDepth: The bit depth of the source image (e.g., 8, 12, 16).
    ///               Used only as a hint for default code-block sizing;
    ///               not embedded in the configuration (the image's
    ///               per-component bit depth is the authoritative value
    ///               at encode time).
    ///   - psnrTarget: Target PSNR for lossy UIDs (default 40 dB).
    ///                 Ignored for lossless UIDs.
    /// - Returns: A `J2KEncodingConfiguration` matching this Transfer Syntax.
    public func encodingConfiguration(
        bitDepth: Int = 16,
        psnrTarget: Double = 40.0
    ) -> J2KEncodingConfiguration {
        let quality: Double
        if isLossless {
            quality = 1.0
        } else {
            // Map a PSNR target into the [0, 1] quality scale that the
            // encoder accepts. The mapping is a rough rule-of-thumb
            // anchored at 50 dB ↔ quality 1.0 (effectively lossless on
            // most natural images). Callers who want a precise R-D
            // operating point should construct J2KEncodingConfiguration
            // directly and set `bitrateMode = .constantBitrate(...)`.
            quality = max(0.0, min(1.0, psnrTarget / 50.0))
        }
        _ = bitDepth  // reserved for future block-size heuristics

        return J2KEncodingConfiguration(
            quality: quality,
            lossless: isLossless,
            useHTJ2K: isHTJ2K,
            useReversibleFilter: isLossless,
            htj2kBlockFormat: .conformant)
    }
}
