// J2KHTBlockCoderPart15Dispatch.swift
// Dispatch layer that lets existing HTBlockEncoder / HTBlockDecoder
// callers opt into the ISO/IEC 15444-15 conformant path via the
// `HTBlockFormat` configuration flag, without touching the v4.x
// custom-format code paths.
//
// Responsibilities:
// - Translate between the pipeline's Int32 sign-magnitude coefficient
//   convention (sign in bit 31, magnitude in the low bits) and the
//   Part-15 encoder's UInt32 convention.
// - Wrap the raw Part-15 bytes produced by
//   `HTBlockEncoderPart15.encode` + `HTBlockLayoutPart15.assemble`
//   in an `HTEncodedBlock` with `format = .part15`.
// - Invert the wrap for the decoder side.

import Foundation
import J2KCore

extension HTBlockEncoder {

    /// Encode a codeblock using the ISO/IEC 15444-15 conformant
    /// cleanup pass. Emits bytes that OpenJPH 0.26+ can decode.
    ///
    /// `missingMSBs` corresponds to the Kmsbs / p-bit convention from
    /// ITU T.814: `p = 30 - missingMSBs`. Pass `0` for the default
    /// 30-bit bit-plane path.
    ///
    /// Input coefficients use the pipeline's `Int32` sign-magnitude
    /// convention: bit 31 is the sign; the magnitude occupies the
    /// low 31 bits and is expected to align to the bit-plane.
    func encodeCleanupPart15(
        coefficients: [Int32],
        missingMSBs: Int = 0
    ) throws -> HTEncodedBlock {
        guard coefficients.count == width * height else {
            throw J2KError.encodingError(
                "coefficient count mismatch (\(coefficients.count) " +
                "vs \(width * height))")
        }

        // Reinterpret Int32 bit pattern as UInt32; sign bit and
        // magnitude bits are identical on a 2's complement platform
        // (which is the only platform Swift supports).
        let input = coefficients.map { UInt32(bitPattern: $0) }

        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: input,
            width: width, height: height,
            missingMSBs: missingMSBs)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)

        return HTEncodedBlock(
            codedData: Data(block),
            passType: .htCleanup,
            melLength: mel.count,
            vlcLength: vlc.count,
            magsgnLength: ms.count,
            bitPlane: 30 - missingMSBs,
            width: width,
            height: height,
            format: .part15)
    }
}

extension HTBlockDecoder {

    /// Decode a Part-15 codeblock (produced by
    /// `encodeCleanupPart15` or by OpenJPH). Returns coefficients in
    /// the pipeline's Int32 sign-magnitude convention.
    func decodeCleanupPart15(
        from block: HTEncodedBlock,
        missingMSBs: Int = 0
    ) throws -> [Int32] {
        guard block.format == .part15 else {
            throw J2KError.decodingError(
                "decodeCleanupPart15 called on a non-Part-15 block")
        }
        let raw = [UInt8](block.codedData)
        let decoded = try HTBlockDecoderPart15.decode(
            block: raw,
            width: width, height: height,
            missingMSBs: missingMSBs)
        return decoded.map { Int32(bitPattern: $0) }
    }
}
