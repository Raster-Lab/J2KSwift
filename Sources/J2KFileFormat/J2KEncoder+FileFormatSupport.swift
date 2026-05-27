// J2KEncoder+FileFormatSupport.swift
//
// v10.23.0 — write-side counterpart to v10.22.0's `J2KDecoder.decodeFile`
// + `decodeAnyFormat` extensions. Lives in the `J2KFileFormat` module
// for the same reason: `J2KFileFormat` depends on `J2KCodec`, so
// extensions that bridge encoder ↔ box wrappers belong here to avoid
// a J2KCodec → J2KFileFormat dependency cycle.
//
// Before v10.23.0, consumers using `J2KEncoder` (with its rich
// `J2KEncodingConfiguration` — HTJ2K, multi-tile, custom quality
// layers, etc.) had to write to disk through `J2KFileWriter.write`
// which re-encodes via the simpler `J2KConfiguration` (quality +
// lossless only). That meant the rich encoding choices made via
// `J2KEncoder` were discarded at write time.
//
// v10.23.0 closes the gap:
//   * `encodeToFormat(_:format:)` — encodes via `self.encode(image)`
//     (preserving the encoder's configuration), then wraps via
//     `J2KFileWriter.wrap(codestream:headerForImage:)` (new in
//     v10.23.0, exposes the previously-private box builders).
//   * `encodeFile(_:to:format:)` — thin write-to-disk wrapper.

import Foundation
import J2KCore
import J2KCodec

extension J2KEncoder {

    /// v10.23.0 — encode an image with this encoder's configuration
    /// and wrap the resulting codestream in the requested file format's
    /// box structure (no re-encoding).
    ///
    /// For `.j2k`, returns the raw codestream bytes unchanged. For
    /// `.jp2`/`.jph`/`.jpx`/`.jpm`, wraps via the canonical box
    /// builders (signature + filetype + JP2 header + jp2c contiguous
    /// codestream box, per ISO/IEC 15444-1 §I.4).
    ///
    /// Symmetric counterpart to ``J2KDecoder/decodeAnyFormat(_:)``
    /// (v10.22.0).
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - format: Target file format. Defaults to `.jp2`.
    /// - Returns: The complete file bytes (codestream for `.j2k`,
    ///   box-wrapped for the others).
    /// - Throws: Any error from `self.encode(_:)` or the box wrapper.
    public func encodeToFormat(
        _ image: J2KImage,
        format: J2KFormat = .jp2
    ) async throws -> Data {
        let codestream = try await self.encode(image)
        let writer = J2KFileWriter(format: format)
        return try writer.wrap(codestream: codestream, headerForImage: image)
    }

    /// v10.23.0 — encode an image with this encoder's configuration,
    /// wrap in the requested file format, and write to disk.
    ///
    /// Equivalent to:
    /// ```swift
    /// let bytes = try await encoder.encodeToFormat(image, format: format)
    /// try bytes.write(to: url, options: .atomic)
    /// ```
    /// but discoverable from the encoder's own surface (with
    /// `import J2KFileFormat`).
    ///
    /// Symmetric counterpart to ``J2KDecoder/decodeFile(at:)``
    /// (v10.22.0).
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - url: Destination file URL.
    ///   - format: Target file format. Defaults to `.jp2`.
    /// - Throws: Encode errors, box-wrap errors, or I/O errors
    ///   (via `Data.write(to:options:)`).
    public func encodeFile(
        _ image: J2KImage,
        to url: URL,
        format: J2KFormat = .jp2
    ) async throws {
        let bytes = try await encodeToFormat(image, format: format)
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw J2KError.ioError(
                "Failed to write file to \(url.path): \(error.localizedDescription)")
        }
    }
}
