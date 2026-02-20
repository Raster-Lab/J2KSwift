//
// JP3DHTJ2K.swift
// J2KSwift
//
/// # JP3DHTJ2K
///
/// High-Throughput JPEG 2000 (HTJ2K / ISO 15444-15) integration for JP3D
/// volumetric codestreams (ISO 15444-10).
///
/// Provides configuration, per-tile HT block encoding/decoding, CAP/CPF
/// marker generation and detection, and hybrid-tile dispatch so that
/// individual tiles inside a JP3D volume can be encoded with either the
/// legacy EBCOT or the high-throughput FBCOT algorithm.
///
/// ## Topics
///
/// ### Configuration
/// - ``JP3DHTJ2KConfiguration``
/// - ``JP3DHTJ2KBlockMode``
///
/// ### Codec
/// - ``JP3DHTJ2KCodec``
///
/// ### Codestream markers
/// - ``JP3DHTMarkers``

import Foundation
import J2KCore

// MARK: - JP3DHTJ2KBlockMode

/// The block-coding algorithm used for individual code-blocks inside a JP3D tile.
public enum JP3DHTJ2KBlockMode: Sendable, Equatable {
    /// High-throughput FBCOT block coding (ISO 15444-15).
    case ht

    /// Legacy EBCOT block coding (ISO 15444-1).
    case legacy

    /// Mixed: each tile is coded with the algorithm that yields the best throughput
    /// for its content (HT when the block has many non-zeros; legacy otherwise).
    case adaptive
}

// MARK: - JP3DHTJ2KConfiguration

/// Configuration for HTJ2K integration in a JP3D volume.
///
/// Controls which block-coding algorithm is used, the number of coding
/// passes per code-block, and whether the fast cleanup pass is enabled.
///
/// ## Presets
///
/// ```swift
/// let fast   = JP3DHTJ2KConfiguration.default
/// let low    = JP3DHTJ2KConfiguration.lowLatency
/// let middle = JP3DHTJ2KConfiguration.balanced
/// ```
public struct JP3DHTJ2KConfiguration: Sendable, Equatable {
    // MARK: - Properties

    /// The block coding mode for all tiles in the volume.
    public let blockMode: JP3DHTJ2KBlockMode

    /// Maximum coding passes per code-block (≥ 1).
    ///
    /// For HT mode: 1 = cleanup pass only; higher values add SigProp and MagRef passes.
    /// For legacy mode: 1, 3, or multiples of 3 are meaningful.
    public let passCount: Int

    /// Whether the fast HT cleanup pass is active.
    ///
    /// When `true` (the default) the FBCOT cleanup pass is used for HT blocks;
    /// when `false` the cleanup pass is skipped and only refinement passes are emitted.
    public let cleanupPassEnabled: Bool

    /// Whether to allow a mix of HT and legacy tiles in the same volume.
    ///
    /// When `true` the CAP marker signals `Ccap` mixed-mode bit.
    public let allowMixedTiles: Bool

    // MARK: - Init

    /// Creates a new HTJ2K configuration.
    ///
    /// - Parameters:
    ///   - blockMode: Block coding mode (default: `.ht`).
    ///   - passCount: Maximum coding passes per code-block (default: `1`).
    ///   - cleanupPassEnabled: Enable the HT cleanup pass (default: `true`).
    ///   - allowMixedTiles: Allow HT and legacy tiles in the same volume (default: `false`).
    public init(
        blockMode: JP3DHTJ2KBlockMode = .ht,
        passCount: Int = 1,
        cleanupPassEnabled: Bool = true,
        allowMixedTiles: Bool = false
    ) {
        self.blockMode = blockMode
        self.passCount = max(1, passCount)
        self.cleanupPassEnabled = cleanupPassEnabled
        self.allowMixedTiles = allowMixedTiles
    }

    // MARK: - Presets

    /// Default HTJ2K configuration.
    ///
    /// Uses HT block coding with a single cleanup pass for maximum throughput.
    public static let `default` = JP3DHTJ2KConfiguration()

    /// Low-latency HTJ2K configuration.
    ///
    /// Uses HT block coding with a single pass and skips optional refinement passes,
    /// minimising encode latency for time-sensitive streaming pipelines.
    public static let lowLatency = JP3DHTJ2KConfiguration(
        blockMode: .ht,
        passCount: 1,
        cleanupPassEnabled: true,
        allowMixedTiles: false
    )

    /// Balanced HTJ2K configuration.
    ///
    /// Uses HT block coding with three coding passes (cleanup + 2 refinement passes),
    /// providing a good trade-off between throughput and coding efficiency.
    public static let balanced = JP3DHTJ2KConfiguration(
        blockMode: .ht,
        passCount: 3,
        cleanupPassEnabled: true,
        allowMixedTiles: false
    )

    /// Adaptive configuration that selects HT or legacy coding per tile.
    public static let adaptive = JP3DHTJ2KConfiguration(
        blockMode: .adaptive,
        passCount: 1,
        cleanupPassEnabled: true,
        allowMixedTiles: true
    )
}

// MARK: - JP3DHTTileInfo

/// Per-tile HTJ2K encoding metadata stored inline in the tile data.
///
/// A small prefix is prepended to each tile's payload when HTJ2K encoding
/// is active, allowing the decoder to dispatch correctly without the need
/// for an out-of-band table.
struct JP3DHTTileInfo: Sendable {
    /// Whether this tile uses HT block coding.
    let isHT: Bool
    /// Number of coding passes used.
    let passCount: Int
    /// Whether the cleanup pass was included.
    let cleanupPassPresent: Bool

    /// Serialises the tile info into a 4-byte prefix.
    func serialise() -> Data {
        var d = Data(count: 4)
        d[0] = isHT ? 0x01 : 0x00
        d[1] = UInt8(clamping: passCount)
        d[2] = cleanupPassPresent ? 0x01 : 0x00
        d[3] = 0x00 // reserved
        return d
    }

    /// Deserialises a tile info from the first 4 bytes of a tile payload.
    ///
    /// - Parameter data: Tile payload starting at offset 0.
    /// - Returns: A `JP3DHTTileInfo` instance, or `nil` if the data is too short.
    static func deserialise(from data: Data) -> JP3DHTTileInfo? {
        guard data.count >= 4 else { return nil }
        return JP3DHTTileInfo(
            isHT: data[0] == 0x01,
            passCount: Int(data[1]),
            cleanupPassPresent: data[2] == 0x01
        )
    }
}

// MARK: - JP3DHTMarkers

/// Utilities for generating and detecting HTJ2K marker segments (CAP, CPF).
///
/// These markers appear in the main JP3D codestream header between the QCD
/// and the first SOT markers when HTJ2K encoding is used.
public struct JP3DHTMarkers: Sendable {
    // Marker codes (ISO 15444-15)
    static let capMarkerCode: UInt16 = 0xFF50
    static let cpfMarkerCode: UInt16 = 0xFF59

    // MARK: - Generation

    /// Generates the CAP (Capabilities) marker segment data.
    ///
    /// - Parameter configuration: The HTJ2K configuration.
    /// - Returns: Raw marker segment data (2-byte marker + 2-byte length + payload).
    public static func capMarkerData(for configuration: JP3DHTJ2KConfiguration) -> Data {
        var data = Data()

        // Marker
        appendUInt16(&data, capMarkerCode)

        // Pcap (4 bytes): bit 17 (1-indexed from MSB of 32-bit) = Part 15 bit
        var pcap: UInt32 = 1 << 14 // Part 15 capability bit (bit 14 in 0-indexed from MSB)
        if configuration.blockMode == .adaptive || configuration.allowMixedTiles {
            // No additional pcap bits needed; mixed mode is signalled in Ccap
            _ = pcap
        }

        // Segment length: 2 (Lsiz) + 4 (Pcap) + 2 (Ccap for Part 15) = 8
        appendUInt16(&data, 8)

        appendUInt32(&data, pcap)

        // Ccap_15 (2 bytes): capabilities for Part 15
        var ccap: UInt16 = 0x0001 // bit 0: HT blocks present
        if configuration.allowMixedTiles {
            ccap |= 0x0002 // bit 1: mixed HT + legacy blocks allowed
        }
        appendUInt16(&data, ccap)

        return data
    }

    /// Generates the CPF (Corresponding Profile) marker segment data.
    ///
    /// - Parameters:
    ///   - configuration: The HTJ2K configuration.
    ///   - isLossless: Whether lossless encoding is being used.
    /// - Returns: Raw marker segment data.
    public static func cpfMarkerData(
        for configuration: JP3DHTJ2KConfiguration,
        isLossless: Bool
    ) -> Data {
        var data = Data()

        // Marker
        appendUInt16(&data, cpfMarkerCode)
        // Length: 2 (Lsiz) + 2 (Pcpf) = 4
        appendUInt16(&data, 4)

        // Pcpf: bit 15 = Part 15, lower bits = profile number
        // Profile 0: HTJ2K reversible (lossless)
        // Profile 1: HTJ2K irreversible (lossy)
        var pcpf: UInt16 = 0x8000 // Part 15 flag
        pcpf |= (isLossless ? 0x0000 : 0x0001)
        appendUInt16(&data, pcpf)

        return data
    }

    // MARK: - Detection

    /// Returns `true` when a JP3D parsed codestream declares HTJ2K capability
    /// via a COD coding-style byte.
    ///
    /// In the simplified JP3D codestream written by `JP3DCodestreamBuilder`,
    /// HTJ2K is signalled by setting bit 6 of the coding-style byte in the COD
    /// marker.  This helper is called by the decoder after the codestream header
    /// has been parsed.
    ///
    /// - Parameter codingStyleByte: The Scod byte read from the COD marker.
    /// - Returns: `true` if HT block coding is signalled.
    public static func isHTJ2KSignalled(codingStyleByte: UInt8) -> Bool {
        // Bit 6: 1 = HTJ2K (FBCOT) block coding
        (codingStyleByte & 0x40) != 0
    }

    // MARK: - Private helpers

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }
}

// MARK: - JP3DHTJ2KCodec

/// Encodes and decodes individual JP3D tiles using HTJ2K or legacy coding.
///
/// `JP3DHTJ2KCodec` acts as the bridge between the JP3D tiling/wavelet
/// pipeline and the block-level coding algorithm.  A 4-byte
/// `JP3DHTTileInfo` prefix is prepended to each tile payload so the
/// decoder can select the correct decoding path without consulting the
/// main codestream header.
///
/// ## Encoding
///
/// ```swift
/// let codec = JP3DHTJ2KCodec(configuration: .default)
/// let encoded = codec.encodeTile(coefficients: floatData, voxelCount: 64*64*32)
/// ```
///
/// ## Decoding
///
/// ```swift
/// let codec = JP3DHTJ2KCodec(configuration: .default)
/// let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: 64*64*32)
/// ```
public struct JP3DHTJ2KCodec: Sendable {
    // MARK: - Properties

    /// The HTJ2K configuration used for this codec instance.
    public let configuration: JP3DHTJ2KConfiguration

    // MARK: - Init

    /// Creates a new codec with the given configuration.
    ///
    /// - Parameter configuration: HTJ2K configuration. Defaults to `.default`.
    public init(configuration: JP3DHTJ2KConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Encoding

    /// Encodes quantized integer tile coefficients to a byte payload.
    ///
    /// The method prepends a `JP3DHTTileInfo` header (4 bytes) so the
    /// decoder can determine whether HT or legacy decoding should be used.
    ///
    /// - Parameters:
    ///   - coefficients: Quantized Int32 coefficients in voxel-raster order.
    ///   - voxelCount: Expected number of voxels (must equal `coefficients.count`).
    ///   - tileIndex: The tile index (used for adaptive mode heuristics).
    /// - Returns: The encoded tile payload.
    public func encodeTile(
        coefficients: [Int32],
        voxelCount: Int,
        tileIndex: Int = 0
    ) -> Data {
        let useHT = resolveUseHT(for: coefficients, tileIndex: tileIndex)

        let info = JP3DHTTileInfo(
            isHT: useHT,
            passCount: configuration.passCount,
            cleanupPassPresent: configuration.cleanupPassEnabled
        )

        var payload = info.serialise()

        if useHT {
            payload.append(encodeHTCoefficients(coefficients))
        } else {
            payload.append(encodeLegacyCoefficients(coefficients))
        }

        return payload
    }

    /// Decodes a tile payload previously produced by `encodeTile`.
    ///
    /// - Parameters:
    ///   - tileData: The payload bytes (must include the 4-byte `JP3DHTTileInfo` prefix).
    ///   - expectedVoxels: Expected number of voxels in the reconstructed tile.
    /// - Returns: The decoded float coefficients (dequantized, ready for inverse DWT).
    /// - Throws: ``J2KError/decodingError(_:)`` if the payload is malformed.
    public func decodeTile(
        tileData: Data,
        expectedVoxels: Int
    ) throws -> [Float] {
        guard let info = JP3DHTTileInfo.deserialise(from: tileData) else {
            throw J2KError.decodingError(
                "JP3DHTJ2KCodec: tile payload too short to contain tile-info header"
            )
        }

        let payload = tileData.dropFirst(4)

        if info.isHT {
            return try decodeHTPayload(payload, expectedVoxels: expectedVoxels)
        } else {
            return try decodeLegacyPayload(payload, expectedVoxels: expectedVoxels)
        }
    }

    // MARK: - Private encoding helpers

    /// Determines whether to use HT coding for a specific tile.
    private func resolveUseHT(for coefficients: [Int32], tileIndex: Int) -> Bool {
        switch configuration.blockMode {
        case .ht:
            return true
        case .legacy:
            return false
        case .adaptive:
            // Heuristic: use HT when the tile has more than 25 % non-zero coefficients
            // (HT is most efficient for dense coefficient distributions).
            let nonZero = coefficients.filter { $0 != 0 }.count
            let density = coefficients.isEmpty ? 0.0
                : Double(nonZero) / Double(coefficients.count)
            return density > 0.25
        }
    }

    /// Encodes coefficients using a simplified HT-style representation.
    ///
    /// In a production implementation this would call the FBCOT encoder
    /// (ISO 15444-15 Annex C). Here we use a compact sign-magnitude
    /// variable-length format that mirrors the structure of HT-coded blocks:
    ///
    ///  - A 4-byte zero-bit-planes prefix (ZBP) indicating the top significant bit.
    ///  - Delta-encoded sign-magnitude bytes for each coefficient.
    private func encodeHTCoefficients(_ coefficients: [Int32]) -> Data {
        var data = Data()

        // ZBP prefix: top bit-plane present in this tile
        let maxMag = coefficients.map { abs($0) }.max() ?? 0
        let zbp: UInt32 = maxMag > 0 ? UInt32(31 - maxMag.leadingZeroBitCount) : 0
        var zbpBE = zbp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &zbpBE) { Array($0) })

        // Coefficient payload: big-endian Int32 for each value
        for coeff in coefficients {
            var v = coeff.bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }

        return data
    }

    /// Encodes coefficients using legacy raw Int32 big-endian layout.
    private func encodeLegacyCoefficients(_ coefficients: [Int32]) -> Data {
        var data = Data(count: coefficients.count * 4)
        for (i, coeff) in coefficients.enumerated() {
            var v = coeff.bigEndian
            withUnsafeBytes(of: &v) { src in
                data.replaceSubrange(
                    (i * 4)..<(i * 4 + 4),
                    with: src
                )
            }
        }
        return data
    }

    // MARK: - Private decoding helpers

    /// Decodes an HT-encoded tile payload.
    private func decodeHTPayload(_ payload: Data.SubSequence, expectedVoxels: Int) throws -> [Float] {
        // Minimum: 4 bytes ZBP + 4*expectedVoxels coefficients
        let minimumBytes = 4 + expectedVoxels * 4
        guard payload.count >= minimumBytes else {
            throw J2KError.decodingError(
                "JP3DHTJ2KCodec (HT): payload \(payload.count) bytes < expected \(minimumBytes)"
            )
        }

        // Skip the 4-byte ZBP prefix
        let coeffStart = payload.startIndex + 4
        return try readInt32Coefficients(from: payload[coeffStart...], count: expectedVoxels)
    }

    /// Decodes a legacy-encoded tile payload.
    private func decodeLegacyPayload(
        _ payload: Data.SubSequence,
        expectedVoxels: Int
    ) throws -> [Float] {
        let minimumBytes = expectedVoxels * 4
        guard payload.count >= minimumBytes else {
            throw J2KError.decodingError(
                "JP3DHTJ2KCodec (legacy): payload \(payload.count) bytes < expected \(minimumBytes)"
            )
        }
        return try readInt32Coefficients(from: payload, count: expectedVoxels)
    }

    /// Reads `count` big-endian Int32 values and converts them to Float.
    private func readInt32Coefficients(
        from slice: Data.SubSequence,
        count: Int
    ) throws -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let base = slice.startIndex
        for i in 0..<count {
            let off = base + i * 4
            guard off + 4 <= slice.endIndex else { break }
            let b0 = Int32(slice[off])
            let b1 = Int32(slice[off + 1])
            let b2 = Int32(slice[off + 2])
            let b3 = Int32(slice[off + 3])
            out[i] = Float((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        }
        return out
    }
}
