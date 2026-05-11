// J2KHTBlockCoderConformantDispatch.swift
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
//   `HTBlockEncoderConformant.encode` + `HTBlockLayoutConformant.assemble`
//   in an `HTEncodedBlock` with `format = .conformant`.
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
    func encodeCleanupConformant(
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

        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: input,
            width: width, height: height,
            missingMSBs: missingMSBs)
        // v9.2 Path B Phase 3a — Data-returning assemble; one alloc per
        // single-block encode.
        let codedData = try HTBlockLayoutConformant.assembleData(
            magsgn: ms, mel: mel, vlc: vlc)

        return HTEncodedBlock(
            codedData: codedData,
            passType: .htCleanup,
            melLength: mel.count,
            vlcLength: vlc.count,
            magsgnLength: ms.count,
            bitPlane: 30 - missingMSBs,
            width: width,
            height: height,
            format: .conformant)
    }
}

extension HTBlockDecoder {

    /// Block-level Conformant decode. Returns coefficients in the
    /// block coder's raw OpenJPH sign-magnitude convention (bit 31 =
    /// sign, magnitude shifted left so MSB lands at bit `[31 - K_max]`).
    /// Callers that want pipeline-scale integer magnitudes should
    /// use `decodeCleanupConformant(rawBytes:missingMSBs:)` instead.
    func decodeCleanupConformant(
        from block: HTEncodedBlock
    ) throws -> [Int32] {
        guard block.format == .conformant else {
            throw J2KError.decodingError(
                "decodeCleanupConformant called on a non-conformant block")
        }
        let decoded = try HTBlockDecoderConformant.decode(
            block: [UInt8](block.codedData),
            width: width, height: height,
            missingMSBs: 0)
        return decoded.map { Int32(bitPattern: $0) }
    }

    /// Pipeline-level Conformant decode. Unlike `from block:`, this
    /// overload converts the block coder's shifted sign-magnitude
    /// output into the pipeline's Int32 integer-magnitude convention
    /// (sign in bit 31 via 2's complement, integer magnitude in the
    /// low bits).
    func decodeCleanupConformant(
        rawBytes: [UInt8],
        missingMSBs: Int
    ) throws -> [Int32] {
        let decoded = try HTBlockDecoderConformant.decode(
            block: rawBytes,
            width: width, height: height,
            missingMSBs: missingMSBs)
        // K_max = missingMSBs + 1, shift = 31 - K_max = 30 - missingMSBs.
        let shift = 30 - missingMSBs
        return decoded.map { uint in
            let sign = (uint & 0x8000_0000) != 0
            let mag = Int32((uint & 0x7FFF_FFFF) >> shift)
            return sign ? -mag : mag
        }
    }
}

/// COM-marker payloads used by the encoder to signal the HTJ2K
/// block-format selection to the decoder side. Standards-compliant
/// decoders (OpenJPH, Kakadu) ignore unknown COM payloads.
enum HTBlockFormatCOMSignature {
    /// Ccom bytes that flag the codestream as using the Part-15
    /// conformant block layout. ISO-8859-15 ASCII.
    static let conformant: [UInt8] = [
        0x4A, 0x32, 0x4B, 0x53, 0x57, 0x49, 0x46, 0x54, // "J2KSWIFT"
        0x2D, 0x48, 0x54, 0x3A,                         // "-HT:"
        0x63, 0x6F, 0x6E, 0x66, 0x6F, 0x72, 0x6D, 0x61, // "conforma"
        0x6E, 0x74                                      // "nt"
    ]
}

/// Heuristic detector for the conformant (Part-15) block wire format.
///
/// The custom v4.x format starts each block with a 6-byte header
/// `[melLen:2 | vlcLen:2 | magsgnLen:2]`; the cleanup-pass bytes are
/// those three segments (the header's sum), and refinement-pass
/// data (SigProp / MagRef) may follow. Conformant blocks have no
/// header — instead they end with a Scup trailer encoding
/// `mel_size + vlc_size` in the last 12 bits (split across the
/// final 2 bytes).
///
/// We default to `.custom` and only switch to `.conformant` when the
/// custom-format header is structurally invalid AND the Scup trailer
/// parses cleanly. This keeps existing v4.x codestreams on the
/// legacy decoder path.
public func detectHTBlockFormat(_ data: Data) -> HTBlockFormat {
    let n = data.count
    if n >= 6 {
        let melLen = (Int(data[data.startIndex + 0]) << 8)
                   | Int(data[data.startIndex + 1])
        let vlcLen = (Int(data[data.startIndex + 2]) << 8)
                   | Int(data[data.startIndex + 3])
        let msLen  = (Int(data[data.startIndex + 4]) << 8)
                   | Int(data[data.startIndex + 5])
        // Custom header is valid when the three segment lengths
        // cover the cleanup-pass bytes exactly (followed by zero or
        // more refinement-pass bytes). If melLen+vlcLen+msLen ≤
        // n - 6 AND each is non-zero-ish, assume custom.
        let cleanupLen = melLen + vlcLen + msLen
        if cleanupLen > 0 && cleanupLen + 6 <= n {
            return .custom
        }
    }
    if n >= 2 {
        let last = Int(data[data.endIndex - 1])
        let prev = Int(data[data.endIndex - 2])
        let scup = (last << 4) | (prev & 0x0F)
        if scup >= 2 && scup <= 4079 && scup <= n {
            return .conformant
        }
    }
    return .custom
}
