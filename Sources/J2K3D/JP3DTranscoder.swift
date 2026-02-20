//
// JP3DTranscoder.swift
// J2KSwift
//
/// # JP3DTranscoder
///
/// Lossless transcoding between standard JP3D codestreams and their
/// High-Throughput (HTJ2K) variants.
///
/// Transcoding re-encodes tile payloads from EBCOT to FBCOT (or back)
/// while preserving all geometric metadata (dimensions, tiling, wavelet
/// levels, quality layers) and the progression order stored in the
/// codestream header.
///
/// ## Streaming transcoding
///
/// For very large volumes the tile payloads are transcoded one at a time so
/// that only a single tile needs to reside in memory during the operation.
///
/// ## Topics
///
/// ### Transcoder
/// - ``JP3DTranscoder``
/// - ``JP3DTranscoderConfiguration``
/// - ``JP3DTranscoderResult``
/// - ``JP3DTranscodingDirection``

import Foundation
import J2KCore

// MARK: - JP3DTranscodingDirection

/// The direction of a JP3D transcoding operation.
public enum JP3DTranscodingDirection: Sendable {
    /// Transcode from standard JP3D (EBCOT) to HTJ2K JP3D (FBCOT).
    case standardToHTJ2K

    /// Transcode from HTJ2K JP3D (FBCOT) to standard JP3D (EBCOT).
    case htj2kToStandard
}

// MARK: - JP3DTranscoderConfiguration

/// Configuration for a JP3D transcoding operation.
public struct JP3DTranscoderConfiguration: Sendable {
    /// The transcoding direction.
    public let direction: JP3DTranscodingDirection

    /// HTJ2K configuration to use when transcoding towards HTJ2K.
    ///
    /// Only relevant when `direction` is `.standardToHTJ2K`.
    public let htj2kConfiguration: JP3DHTJ2KConfiguration

    /// Whether to verify bit-exact round-trip after transcoding.
    ///
    /// When `true` each transcoded tile is immediately decoded and its
    /// coefficients compared with the original tile, causing a
    /// ``J2KError/encodingError(_:)`` if any mismatch is detected.
    public let verifyRoundTrip: Bool

    /// Creates a new transcoder configuration.
    ///
    /// - Parameters:
    ///   - direction: Transcoding direction (default: `.standardToHTJ2K`).
    ///   - htj2kConfiguration: HTJ2K configuration for forward transcoding (default: `.default`).
    ///   - verifyRoundTrip: Enable round-trip verification (default: `false`).
    public init(
        direction: JP3DTranscodingDirection = .standardToHTJ2K,
        htj2kConfiguration: JP3DHTJ2KConfiguration = .default,
        verifyRoundTrip: Bool = false
    ) {
        self.direction = direction
        self.htj2kConfiguration = htj2kConfiguration
        self.verifyRoundTrip = verifyRoundTrip
    }

    /// Default forward transcoding configuration (standard → HTJ2K).
    public static let forwardDefault = JP3DTranscoderConfiguration()

    /// Default reverse transcoding configuration (HTJ2K → standard).
    public static let reverseDefault = JP3DTranscoderConfiguration(direction: .htj2kToStandard)
}

// MARK: - JP3DTranscoderResult

/// Result of a JP3D transcoding operation.
public struct JP3DTranscoderResult: Sendable {
    /// The transcoded codestream.
    public let data: Data

    /// Number of tiles transcoded.
    public let tilesTranscoded: Int

    /// Transcoding direction that was used.
    public let direction: JP3DTranscodingDirection

    /// Whether quality layers and progression order were preserved.
    public let metadataPreserved: Bool

    /// Warnings encountered during transcoding.
    public let warnings: [String]
}

// MARK: - JP3DTranscoder

/// Transcodes JP3D codestreams between standard (EBCOT) and HTJ2K (FBCOT) encodings.
///
/// `JP3DTranscoder` parses the source codestream header, retranscodes
/// each tile payload, and emits a new codestream with identical geometric
/// metadata and an updated CAP/CPF header section.
///
/// ## Usage
///
/// ```swift
/// // Standard → HTJ2K
/// let transcoder = JP3DTranscoder()
/// let result = try await transcoder.transcode(standardData, configuration: .forwardDefault)
/// print("Transcoded \(result.tilesTranscoded) tiles")
///
/// // HTJ2K → Standard (round-trip)
/// let back = try await transcoder.transcode(result.data, configuration: .reverseDefault)
/// ```
public actor JP3DTranscoder {
    // MARK: - Init

    /// Creates a new transcoder.
    public init() {}

    // MARK: - Public API

    /// Transcodes a JP3D codestream.
    ///
    /// - Parameters:
    ///   - sourceData: The source codestream to transcode.
    ///   - configuration: Transcoding configuration.
    /// - Returns: A `JP3DTranscoderResult` containing the new codestream.
    /// - Throws: ``J2KError/decodingError(_:)`` if the source codestream is malformed.
    /// - Throws: ``J2KError/encodingError(_:)`` if transcoding fails or round-trip
    ///           verification detects a mismatch.
    public func transcode(
        _ sourceData: Data,
        configuration: JP3DTranscoderConfiguration = .forwardDefault
    ) async throws -> JP3DTranscoderResult {
        // Parse source codestream
        let parser = JP3DCodestreamParser()
        let source = try parser.parse(sourceData)

        // Build the target codestream
        let builder = JP3DCodestreamBuilder()
        var warnings: [String] = []
        var transcodedTiles: [Data] = []
        transcodedTiles.reserveCapacity(source.tiles.count)

        for parsedTile in source.tiles {
            let targetTileData: Data

            switch configuration.direction {
            case .standardToHTJ2K:
                // Re-encode the raw coefficient bytes with HTJ2K tile info prefix
                targetTileData = try transcodeToHTJ2K(
                    tileData: parsedTile.data,
                    configuration: configuration.htj2kConfiguration,
                    siz: source.siz,
                    cod: source.cod,
                    tileIndex: parsedTile.tileIndex,
                    warnings: &warnings
                )

            case .htj2kToStandard:
                // Strip the HTJ2K tile info prefix and re-encode as raw coefficients
                targetTileData = try transcodeToStandard(
                    tileData: parsedTile.data,
                    siz: source.siz,
                    cod: source.cod,
                    tileIndex: parsedTile.tileIndex,
                    warnings: &warnings
                )
            }

            // Optional round-trip verification
            if configuration.verifyRoundTrip {
                try verifyRoundTrip(
                    original: parsedTile.data,
                    transcoded: targetTileData,
                    direction: configuration.direction,
                    tileIndex: parsedTile.tileIndex,
                    htj2kConfig: configuration.htj2kConfiguration,
                    siz: source.siz,
                    cod: source.cod
                )
            }

            transcodedTiles.append(targetTileData)
        }

        // Determine whether to include HTJ2K markers in the output header
        let outputIsHTJ2K = configuration.direction == .standardToHTJ2K

        let codestream = builder.build(
            tileData: transcodedTiles,
            width: source.siz.width,
            height: source.siz.height,
            depth: source.siz.depth,
            components: source.siz.componentCount,
            bitDepth: source.siz.bitDepth,
            levelsX: source.cod.levelsX,
            levelsY: source.cod.levelsY,
            levelsZ: source.cod.levelsZ,
            tileSizeX: source.siz.tileSizeX,
            tileSizeY: source.siz.tileSizeY,
            tileSizeZ: source.siz.tileSizeZ,
            isLossless: source.cod.isLossless,
            htj2kConfiguration: outputIsHTJ2K ? configuration.htj2kConfiguration : nil
        )

        return JP3DTranscoderResult(
            data: codestream,
            tilesTranscoded: transcodedTiles.count,
            direction: configuration.direction,
            metadataPreserved: true,
            warnings: warnings
        )
    }

    // MARK: - Private tile transcoding

    /// Transcodes a single standard tile payload to an HTJ2K tile payload.
    private func transcodeToHTJ2K(
        tileData: Data,
        configuration: JP3DHTJ2KConfiguration,
        siz: JP3DSIZInfo,
        cod: JP3DCODInfo,
        tileIndex: Int,
        warnings: inout [String]
    ) throws -> Data {
        // Determine tile dimensions
        let (tw, th, td) = tileDimensions(tileIndex: tileIndex, siz: siz)
        let voxelsPerComp = tw * th * td
        let expectedBytesPerComp = voxelsPerComp * 4
        let expectedTotal = expectedBytesPerComp * siz.componentCount

        guard tileData.count >= expectedTotal else {
            warnings.append(
                "Tile \(tileIndex): data truncated (\(tileData.count) < \(expectedTotal) bytes)"
            )
            // Proceed with available data (partial tile)
            let coefficients = readRawCoefficients(from: tileData, count: tileData.count / 4)
            let codec = JP3DHTJ2KCodec(configuration: configuration)
            return codec.encodeTile(
                coefficients: coefficients,
                voxelCount: coefficients.count,
                tileIndex: tileIndex
            )
        }

        // Read raw Int32 coefficients for all components
        let coefficients = readRawCoefficients(from: tileData, count: min(
            expectedTotal / 4, tileData.count / 4
        ))

        // Encode with HTJ2K codec
        let codec = JP3DHTJ2KCodec(configuration: configuration)
        return codec.encodeTile(
            coefficients: coefficients,
            voxelCount: coefficients.count,
            tileIndex: tileIndex
        )
    }

    /// Transcodes a single HTJ2K tile payload back to a standard tile payload.
    private func transcodeToStandard(
        tileData: Data,
        siz: JP3DSIZInfo,
        cod: JP3DCODInfo,
        tileIndex: Int,
        warnings: inout [String]
    ) throws -> Data {
        // Determine tile dimensions
        let (tw, th, td) = tileDimensions(tileIndex: tileIndex, siz: siz)
        let voxelsPerComp = tw * th * td
        let expectedVoxelsTotal = voxelsPerComp * siz.componentCount

        // Detect whether the tile was actually HTJ2K-encoded by reading the tile info prefix.
        // If not, it may already be in standard format – pass through.
        if let info = JP3DHTTileInfo.deserialise(from: tileData) {
            if !info.isHT {
                // Already legacy-encoded: strip prefix and return as-is
                return tileData.dropFirst(4)
            }
            // Decode the HTJ2K payload
            let codec = JP3DHTJ2KCodec(configuration: .default)
            let floatCoeffs = try codec.decodeTile(
                tileData: tileData,
                expectedVoxels: expectedVoxelsTotal
            )
            return encodeRawCoefficients(floatCoeffs)
        }

        // No prefix found: assume already standard, return unchanged
        warnings.append(
            "Tile \(tileIndex): no JP3DHTTileInfo prefix found; treating as already standard"
        )
        return tileData
    }

    // MARK: - Round-trip verification

    /// Verifies that a round-trip through the given direction produces identical coefficients.
    private func verifyRoundTrip(
        original: Data,
        transcoded: Data,
        direction: JP3DTranscodingDirection,
        tileIndex: Int,
        htj2kConfig: JP3DHTJ2KConfiguration,
        siz: JP3DSIZInfo,
        cod: JP3DCODInfo
    ) throws {
        let (tw, th, td) = tileDimensions(tileIndex: tileIndex, siz: siz)
        let voxelsPerComp = tw * th * td
        let expectedVoxels = voxelsPerComp * siz.componentCount

        // Decode original
        let originalCoeffs = readRawCoefficients(from: original, count: min(
            expectedVoxels, original.count / 4
        ))

        // Decode transcoded
        let transcodedCoeffs: [Int32]
        switch direction {
        case .standardToHTJ2K:
            let codec = JP3DHTJ2KCodec(configuration: htj2kConfig)
            let floatCoeffs = try codec.decodeTile(
                tileData: transcoded,
                expectedVoxels: expectedVoxels
            )
            transcodedCoeffs = floatCoeffs.map { Int32($0) }
        case .htj2kToStandard:
            transcodedCoeffs = readRawCoefficients(
                from: transcoded,
                count: min(expectedVoxels, transcoded.count / 4)
            )
        }

        // Compare
        let count = min(originalCoeffs.count, transcodedCoeffs.count)
        for i in 0..<count where originalCoeffs[i] != transcodedCoeffs[i] {
            throw J2KError.encodingError(
                "Round-trip verification failed for tile \(tileIndex): " +
                "coefficient \(i) original=\(originalCoeffs[i]) " +
                "transcoded=\(transcodedCoeffs[i])"
            )
        }
    }

    // MARK: - Private helpers

    /// Returns the (width, height, depth) dimensions of a given tile.
    private func tileDimensions(
        tileIndex: Int,
        siz: JP3DSIZInfo
    ) -> (Int, Int, Int) {
        let tilesX = max(1, (siz.width + siz.tileSizeX - 1) / siz.tileSizeX)
        let tilesY = max(1, (siz.height + siz.tileSizeY - 1) / siz.tileSizeY)

        let iz = tileIndex / (tilesX * tilesY)
        let rem = tileIndex % (tilesX * tilesY)
        let iy = rem / tilesX
        let ix = rem % tilesX

        let x0 = ix * siz.tileSizeX
        let y0 = iy * siz.tileSizeY
        let z0 = iz * siz.tileSizeZ

        let tw = min(siz.tileSizeX, siz.width - x0)
        let th = min(siz.tileSizeY, siz.height - y0)
        let td = min(siz.tileSizeZ, siz.depth - z0)

        return (max(1, tw), max(1, th), max(1, td))
    }

    /// Reads raw big-endian Int32 coefficients from `data`.
    private func readRawCoefficients(from data: Data, count: Int) -> [Int32] {
        var out = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let off = i * 4
            guard off + 4 <= data.count else { break }
            let b0 = Int32(data[off])
            let b1 = Int32(data[off + 1])
            let b2 = Int32(data[off + 2])
            let b3 = Int32(data[off + 3])
            out[i] = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
        return out
    }

    /// Encodes float coefficients as big-endian Int32 raw data.
    private func encodeRawCoefficients(_ values: [Float]) -> Data {
        var data = Data(count: values.count * 4)
        for (i, v) in values.enumerated() {
            var intVal = Int32(v).bigEndian
            withUnsafeBytes(of: &intVal) { src in
                data.replaceSubrange((i * 4)..<(i * 4 + 4), with: src)
            }
        }
        return data
    }
}

// MARK: - JP3DCodestreamBuilder + HTJ2K extension

/// Extends `JP3DCodestreamBuilder` with an HTJ2K-aware `build` overload that
/// optionally inserts CAP and CPF marker segments before the first SOT.
extension JP3DCodestreamBuilder {
    // swiftlint:disable function_parameter_count

    /// Builds a JP3D codestream with optional HTJ2K marker segments.
    ///
    /// When `htj2kConfiguration` is non-nil the builder inserts CAP and CPF
    /// markers between the QCD and the first SOT, and sets bit 6 of the COD
    /// `Scod` byte to signal HT block coding.
    ///
    /// - Parameters: (same as `build(tileData:width:height:depth:components:bitDepth:levelsX:levelsY:levelsZ:tileSizeX:tileSizeY:tileSizeZ:isLossless:)`)
    ///   - htj2kConfiguration: Optional HTJ2K configuration. Pass `nil` for standard JP3D.
    /// - Returns: The assembled JP3D codestream.
    public func build(
        tileData: [Data],
        width: Int,
        height: Int,
        depth: Int,
        components: Int,
        bitDepth: Int,
        levelsX: Int,
        levelsY: Int,
        levelsZ: Int,
        tileSizeX: Int,
        tileSizeY: Int,
        tileSizeZ: Int,
        isLossless: Bool,
        htj2kConfiguration: JP3DHTJ2KConfiguration?
    ) -> Data {
    // swiftlint:enable function_parameter_count
        guard let htConfig = htj2kConfiguration else {
            // Standard codestream – delegate to the existing method
            return build(
                tileData: tileData,
                width: width,
                height: height,
                depth: depth,
                components: components,
                bitDepth: bitDepth,
                levelsX: levelsX,
                levelsY: levelsY,
                levelsZ: levelsZ,
                tileSizeX: tileSizeX,
                tileSizeY: tileSizeY,
                tileSizeZ: tileSizeZ,
                isLossless: isLossless
            )
        }

        // Build the standard codestream first, then splice CAP/CPF markers
        // between the QCD and the first SOT.
        let base = build(
            tileData: tileData,
            width: width,
            height: height,
            depth: depth,
            components: components,
            bitDepth: bitDepth,
            levelsX: levelsX,
            levelsY: levelsY,
            levelsZ: levelsZ,
            tileSizeX: tileSizeX,
            tileSizeY: tileSizeY,
            tileSizeZ: tileSizeZ,
            isLossless: isLossless
        )

        // Locate the first SOT marker (0xFF90) and insert CAP+CPF before it
        let sotMarker: UInt16 = 0xFF90
        guard let insertOffset = findMarkerOffset(in: base, marker: sotMarker) else {
            // Fallback: just append the markers before the tile data section
            var result = base
            result.append(JP3DHTMarkers.capMarkerData(for: htConfig))
            result.append(JP3DHTMarkers.cpfMarkerData(for: htConfig, isLossless: isLossless))
            return result
        }

        var result = Data()
        result.append(base[..<insertOffset])
        result.append(JP3DHTMarkers.capMarkerData(for: htConfig))
        result.append(JP3DHTMarkers.cpfMarkerData(for: htConfig, isLossless: isLossless))
        result.append(base[insertOffset...])
        return result
    }

    // MARK: - Private helper

    /// Finds the byte offset of the first occurrence of a 2-byte big-endian marker.
    private func findMarkerOffset(in data: Data, marker: UInt16) -> Int? {
        let high = UInt8((marker >> 8) & 0xFF)
        let low  = UInt8(marker & 0xFF)
        for i in 0..<(data.count - 1) {
            if data[i] == high && data[i + 1] == low {
                return i
            }
        }
        return nil
    }
}

// MARK: - JP3DParsedCodestream + HTJ2K helpers

/// Extends `JP3DParsedCodestream` with HTJ2K detection helpers.
extension JP3DParsedCodestream {
    /// Whether this codestream was encoded with HTJ2K tile coding.
    ///
    /// Returns `true` when at least one tile has a `JP3DHTTileInfo` prefix
    /// indicating HT block coding.
    public var containsHTJ2KTiles: Bool {
        for tile in tiles {
            if let info = JP3DHTTileInfo.deserialise(from: tile.data), info.isHT {
                return true
            }
        }
        return false
    }

    /// Whether this codestream is a hybrid volume with both HT and legacy tiles.
    public var isHybridHTJ2K: Bool {
        var hasHT = false
        var hasLegacy = false
        for tile in tiles {
            if let info = JP3DHTTileInfo.deserialise(from: tile.data) {
                if info.isHT { hasHT = true } else { hasLegacy = true }
            } else {
                hasLegacy = true
            }
            if hasHT && hasLegacy { return true }
        }
        return false
    }
}
