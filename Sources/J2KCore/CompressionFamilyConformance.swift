// CompressionFamily conformances for J2KSwift's J2KCore types.
// J2KEncoder / J2KDecoder conformances live in J2KCodec.
//
// The protocol definitions live in the shared `CompressionFamily`
// package. JXLSwift conforms its types to the same protocols so
// callers can write codec-agnostic code that works across the
// family:
//
//     func encodeAndExtractBytes<E: CompressionEncoder>(
//         _ encoder: E, image: E.Image
//     ) async throws -> Data {
//         (try await encoder.encode(image)).data
//     }
//
//     // Works with either:
//     let jxlBytes = try await encodeAndExtractBytes(JXLEncoder(), image: jxlImage)
//     let j2kBytes = try await encodeAndExtractBytes(J2KEncoder(), image: j2kImage)

import Foundation
import CompressionFamily

// J2KImage already exposes width: Int and height: Int.
extension J2KImage: CompressionImage {}

// J2KError already conforms to LocalizedError + Sendable.
extension J2KError: CompressionError {}
