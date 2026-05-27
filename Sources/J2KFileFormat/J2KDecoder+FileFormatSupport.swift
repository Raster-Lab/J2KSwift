// J2KDecoder+FileFormatSupport.swift
//
// v10.22.0 — JP2-box auto-handling + file/URL convenience for J2KDecoder.
//
// Lives in the `J2KFileFormat` module rather than `J2KCodec` because
// J2KFileFormat already depends on J2KCodec; adding J2KFileFormat as
// a dep of J2KCodec would create a cycle. Consumers `import J2KFileFormat`
// to get these methods on `J2KDecoder`.
//
// Before v10.22.0, `J2KDecoder.decode(_:)` only accepted raw J2K
// codestream bytes (starting with the SOC marker `0xFF 0x4F`). Most
// `.jp2` / `.jph` / `.jpx` files in the wild are JP2-box-wrapped —
// the codestream sits inside a `jp2c` (Contiguous Codestream) box,
// preceded by signature + filetype + JP2 header boxes. Consumers had
// to hand-roll the box walk (or use `J2KFileReader.extractCodestream`)
// before they could call `decode`.
//
// v10.22.0 closes that gap with two thin wrappers:
//   * `decodeAnyFormat(_:Data)` — auto-detects format via
//     `J2KFormatDetector.detect(data:)`; for `.j2k` passes through to
//     `decode(_:)`; for `.jp2`/`.jpx`/`.jpm`/`.jph` calls
//     `J2KFileReader.extractCodestream(from:)` first.
//   * `decodeFile(at:URL)` — thin `Data(contentsOf:)` + `decodeAnyFormat`.

import Foundation
import J2KCore
import J2KCodec

extension J2KDecoder {

    /// v10.22.0 — decode J2K bytes that may be raw codestream OR
    /// JP2-box-wrapped (`.jp2` / `.jpx` / `.jpm` / `.jph`).
    ///
    /// The format is detected automatically via
    /// ``J2KFormatDetector/detect(data:)``. For `.j2k` (raw codestream)
    /// the bytes are passed straight to ``J2KDecoder/decode(_:)``. For
    /// box-based formats the J2K codestream is first extracted via
    /// ``J2KFileReader/extractCodestream(from:)`` (which walks the box
    /// hierarchy looking for the `jp2c` Contiguous Codestream box).
    ///
    /// - Parameter data: Either a raw J2K codestream (starts with
    ///   SOC `0xFF 0x4F`) or JP2-family box bytes (start with the
    ///   12-byte JP2 signature box).
    /// - Returns: The decoded ``J2KImage``.
    /// - Throws: ``J2KError`` if format detection fails, the
    ///   codestream extraction fails, or the decode fails.
    public func decodeAnyFormat(_ data: Data) async throws -> J2KImage {
        let format = try J2KFormatDetector().detect(data: data)
        switch format {
        case .j2k:
            // Raw codestream — pass through.
            return try await self.decode(data)
        case .jp2, .jpx, .jpm, .jph:
            // Box-wrapped — extract the jp2c contents first.
            let reader = J2KFileReader()
            let codestream = try reader.extractCodestream(from: data)
            return try await self.decode(codestream)
        }
    }

    /// v10.22.0 — read a `.j2k` / `.jp2` / `.jpx` / `.jph` file from
    /// disk and decode it. Auto-detects the format.
    ///
    /// Equivalent to:
    /// ```swift
    /// let data = try Data(contentsOf: url)
    /// return try await decoder.decodeAnyFormat(data)
    /// ```
    /// but discoverable from the decoder's own surface (with `import
    /// J2KFileFormat`).
    ///
    /// - Parameter url: A local file URL.
    /// - Returns: The decoded ``J2KImage``.
    /// - Throws: I/O errors via ``Data/init(contentsOf:)`` plus
    ///   anything ``decodeAnyFormat(_:)`` throws.
    public func decodeFile(at url: URL) async throws -> J2KImage {
        let data = try Data(contentsOf: url)
        return try await decodeAnyFormat(data)
    }
}
