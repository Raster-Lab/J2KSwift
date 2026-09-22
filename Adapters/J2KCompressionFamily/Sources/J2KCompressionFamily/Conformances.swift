// CompressionFamily conformances for J2KSwift's public types.
//
// Moved here from `Sources/J2KCore/CompressionFamilyConformance.swift` and
// `Sources/J2KCodec/CompressionFamilyConformance.swift` so that the J2KSwift
// package resolves without CompressionFamily (suite contract 0.8.0 §4). The
// conformances are retroactive: both the types and the protocols are declared
// in other modules, so a client must import this module for them to apply.
//
// The protocol definitions live in the shared `CompressionFamily` package.
// Callers can write codec-agnostic generic code against them:
//
//     func encodeAndExtractBytes<E: CompressionEncoder>(
//         _ encoder: E, image: E.Image
//     ) async throws -> Data {
//         (try await encoder.encode(image)).data
//     }

import Foundation
import CompressionFamily
import J2KCore
import J2KCodec

// J2KImage already exposes width: Int and height: Int.
extension J2KImage: @retroactive CompressionImage {}

// J2KError already conforms to LocalizedError + Sendable.
extension J2KError: @retroactive CompressionError {}

// J2KEncoder.encode(_ image: J2KImage) async throws -> Data already matches
// the CompressionEncoder shape. `Data` carries the default `CompressionOutput`
// conformance from the shared package.
extension J2KEncoder: @retroactive CompressionEncoder {
    public typealias Image = J2KImage
    public typealias Output = Data
}

// J2KDecoder.decode(_ data: Data) async throws -> J2KImage already matches
// CompressionDecoder.
extension J2KDecoder: @retroactive CompressionDecoder {
    public typealias Image = J2KImage
}
