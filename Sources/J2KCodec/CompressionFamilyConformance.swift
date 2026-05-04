// CompressionFamily conformances for J2KSwift's J2KCodec types.
// J2KImage / J2KError conformances live in J2KCore.
//
// The protocol definitions live in the shared `CompressionFamily`
// package; JXLSwift adopts the same protocols so callers can write
// codec-agnostic generic code.

import Foundation
import CompressionFamily
import J2KCore

// J2KEncoder.encode(_ image: J2KImage) async throws -> Data
// already matches the CompressionEncoder shape. `Data` carries
// the default `CompressionOutput` conformance from the shared
// package.
extension J2KEncoder: CompressionEncoder {
    public typealias Image = J2KImage
    public typealias Output = Data
}

// J2KDecoder.decode(_ data: Data) async throws -> J2KImage
// already matches CompressionDecoder.
extension J2KDecoder: CompressionDecoder {
    public typealias Image = J2KImage
}
