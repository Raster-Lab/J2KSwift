/// Tests for JP3D HTJ2K Integration (Week 226-228).
///
/// Validates HTJ2K configuration, per-tile encoding/decoding, CAP/CPF marker
/// generation, hybrid tile volumes, transcoding, and edge cases as specified
/// in ISO/IEC 15444-10 with HTJ2K extension (ISO/IEC 15444-15).

import XCTest
@testable import J2KCore
@testable import J2K3D

final class JP3DHTJ2KTests: XCTestCase {
    // MARK: - Helpers

    /// Creates a test volume with simple gradient data.
    private func makeTestVolume(
        width: Int, height: Int, depth: Int,
        componentCount: Int = 1, bitDepth: Int = 8
    ) -> J2KVolume {
        let bytesPerSample = (bitDepth + 7) / 8
        var components: [J2KVolumeComponent] = []
        for c in 0..<componentCount {
            var data = Data(count: width * height * depth * bytesPerSample)
            for z in 0..<depth {
                for y in 0..<height {
                    for x in 0..<width {
                        let idx = z * width * height + y * width + x
                        let value = (x + y * 2 + z * 3 + c * 5) % 256
                        for b in 0..<bytesPerSample {
                            data[idx * bytesPerSample + b] =
                                UInt8(truncatingIfNeeded: value >> (b * 8))
                        }
                    }
                }
            }
            components.append(J2KVolumeComponent(
                index: c, bitDepth: bitDepth, signed: false,
                width: width, height: height, depth: depth,
                data: data
            ))
        }
        return J2KVolume(width: width, height: height, depth: depth, components: components)
    }

    // MARK: - JP3DHTJ2KConfiguration tests

    func testDefaultConfigurationPreset() {
        let config = JP3DHTJ2KConfiguration.default
        XCTAssertEqual(config.blockMode, .ht)
        XCTAssertEqual(config.passCount, 1)
        XCTAssertTrue(config.cleanupPassEnabled)
        XCTAssertFalse(config.allowMixedTiles)
    }

    func testLowLatencyPreset() {
        let config = JP3DHTJ2KConfiguration.lowLatency
        XCTAssertEqual(config.blockMode, .ht)
        XCTAssertEqual(config.passCount, 1)
        XCTAssertTrue(config.cleanupPassEnabled)
        XCTAssertFalse(config.allowMixedTiles)
    }

    func testBalancedPreset() {
        let config = JP3DHTJ2KConfiguration.balanced
        XCTAssertEqual(config.blockMode, .ht)
        XCTAssertEqual(config.passCount, 3)
        XCTAssertTrue(config.cleanupPassEnabled)
        XCTAssertFalse(config.allowMixedTiles)
    }

    func testAdaptivePreset() {
        let config = JP3DHTJ2KConfiguration.adaptive
        XCTAssertEqual(config.blockMode, .adaptive)
        XCTAssertTrue(config.allowMixedTiles)
    }

    func testCustomConfiguration() {
        let config = JP3DHTJ2KConfiguration(
            blockMode: .legacy,
            passCount: 5,
            cleanupPassEnabled: false,
            allowMixedTiles: true
        )
        XCTAssertEqual(config.blockMode, .legacy)
        XCTAssertEqual(config.passCount, 5)
        XCTAssertFalse(config.cleanupPassEnabled)
        XCTAssertTrue(config.allowMixedTiles)
    }

    func testPassCountClampedToOne() {
        let config = JP3DHTJ2KConfiguration(passCount: 0)
        XCTAssertEqual(config.passCount, 1, "passCount must be at least 1")
    }

    func testConfigurationEquality() {
        let a = JP3DHTJ2KConfiguration.default
        let b = JP3DHTJ2KConfiguration.default
        XCTAssertEqual(a, b)
    }

    func testConfigurationInequality() {
        let a = JP3DHTJ2KConfiguration.default
        let b = JP3DHTJ2KConfiguration.balanced
        XCTAssertNotEqual(a, b)
    }

    // MARK: - JP3DHTJ2KBlockMode tests

    func testBlockModeHTEquality() {
        XCTAssertEqual(JP3DHTJ2KBlockMode.ht, JP3DHTJ2KBlockMode.ht)
    }

    func testBlockModeLegacyEquality() {
        XCTAssertEqual(JP3DHTJ2KBlockMode.legacy, JP3DHTJ2KBlockMode.legacy)
    }

    func testBlockModeInequality() {
        XCTAssertNotEqual(JP3DHTJ2KBlockMode.ht, JP3DHTJ2KBlockMode.legacy)
    }

    // MARK: - JP3DHTJ2KCodec encoding tests

    func testCodecEncodesTileWithHTMode() {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let coefficients: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]
        let encoded = codec.encodeTile(coefficients: coefficients, voxelCount: coefficients.count)
        // Minimum: 4-byte tile-info prefix + 4-byte ZBP header + raw Int32 coefficients
        let tileInfoSize = 4
        let zbpSize = 4
        XCTAssertGreaterThanOrEqual(encoded.count, tileInfoSize + zbpSize + coefficients.count * 4)
        // Verify tile-info header signals HT
        XCTAssertEqual(encoded[0], 0x01, "First byte should signal HT mode")
    }

    func testCodecEncodesTileWithLegacyMode() {
        let config = JP3DHTJ2KConfiguration(blockMode: .legacy)
        let codec = JP3DHTJ2KCodec(configuration: config)
        let coefficients: [Int32] = [10, 20, 30, 40]
        let encoded = codec.encodeTile(coefficients: coefficients, voxelCount: coefficients.count)
        XCTAssertGreaterThanOrEqual(encoded.count, 4, "Should have at least the tile-info prefix")
        // Tile-info header must signal legacy mode
        XCTAssertEqual(encoded[0], 0x00, "First byte should signal legacy mode")
    }

    func testCodecDecodesTileHTRoundTrip() throws {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let original: [Int32] = [0, 100, -50, 200, -120, 33, 0, 1]
        let encoded = codec.encodeTile(coefficients: original, voxelCount: original.count)
        let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: original.count)

        XCTAssertEqual(decoded.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(decoded[i], Float(original[i]),
                           "Coefficient \(i) mismatch after round-trip")
        }
    }

    func testCodecDecodesTileLegacyRoundTrip() throws {
        let config = JP3DHTJ2KConfiguration(blockMode: .legacy)
        let codec = JP3DHTJ2KCodec(configuration: config)
        let original: [Int32] = [5, -5, 12, -12, 0, 255, 1, -1]
        let encoded = codec.encodeTile(coefficients: original, voxelCount: original.count)
        let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: original.count)

        XCTAssertEqual(decoded.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(decoded[i], Float(original[i]))
        }
    }

    func testCodecDecodeThrowsOnTruncatedData() {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let tooShort = Data([0x01, 0x01, 0x01]) // 3 bytes < 4-byte minimum
        XCTAssertThrowsError(try codec.decodeTile(tileData: tooShort, expectedVoxels: 4))
    }

    func testCodecAdaptiveModeSelectsHTForDenseData() {
        let config = JP3DHTJ2KConfiguration(blockMode: .adaptive)
        let codec = JP3DHTJ2KCodec(configuration: config)
        // Dense data (> 25% non-zero) should be encoded as HT
        let dense: [Int32] = (0..<16).map { Int32($0 + 1) }
        let encoded = codec.encodeTile(coefficients: dense, voxelCount: dense.count)
        XCTAssertEqual(encoded[0], 0x01, "Dense data should use HT mode in adaptive")
    }

    func testCodecAdaptiveModeSelectsLegacyForSparseData() {
        let config = JP3DHTJ2KConfiguration(blockMode: .adaptive)
        let codec = JP3DHTJ2KCodec(configuration: config)
        // Sparse data (≤ 25% non-zero) should be encoded as legacy
        var sparse = [Int32](repeating: 0, count: 16)
        sparse[0] = 1 // Only 1/16 = 6.25% non-zero
        let encoded = codec.encodeTile(coefficients: sparse, voxelCount: sparse.count)
        XCTAssertEqual(encoded[0], 0x00, "Sparse data should use legacy mode in adaptive")
    }

    func testCodecEncodeDecodeZeroCoefficients() throws {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let zeros = [Int32](repeating: 0, count: 8)
        let encoded = codec.encodeTile(coefficients: zeros, voxelCount: zeros.count)
        let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: zeros.count)
        XCTAssertEqual(decoded, [Float](repeating: 0, count: zeros.count))
    }

    // MARK: - CAP / CPF marker tests

    func testCAPMarkerContainsCorrectMagicBytes() {
        let capData = JP3DHTMarkers.capMarkerData(for: .default)
        // First 2 bytes: CAP marker = 0xFF50
        XCTAssertEqual(capData[0], 0xFF)
        XCTAssertEqual(capData[1], 0x50)
    }

    func testCPFMarkerContainsCorrectMagicBytes() {
        let cpfData = JP3DHTMarkers.cpfMarkerData(for: .default, isLossless: true)
        // First 2 bytes: CPF marker = 0xFF59
        XCTAssertEqual(cpfData[0], 0xFF)
        XCTAssertEqual(cpfData[1], 0x59)
    }

    func testCAPMarkerLengthForDefaultConfig() {
        let capData = JP3DHTMarkers.capMarkerData(for: .default)
        // Segment length field (bytes 2–3) should be 8
        let len = (UInt16(capData[2]) << 8) | UInt16(capData[3])
        XCTAssertEqual(len, 8)
    }

    func testCPFMarkerLengthForLosslessConfig() {
        let cpfData = JP3DHTMarkers.cpfMarkerData(for: .default, isLossless: true)
        // Segment length field (bytes 2–3) should be 4
        let len = (UInt16(cpfData[2]) << 8) | UInt16(cpfData[3])
        XCTAssertEqual(len, 4)
    }

    func testCAPMarkerMixedModeBitSet() {
        let mixedConfig = JP3DHTJ2KConfiguration(allowMixedTiles: true)
        let capData = JP3DHTMarkers.capMarkerData(for: mixedConfig)
        // Ccap_15 (last 2 bytes) bit 1 should be set for mixed mode
        let ccap = (UInt16(capData[capData.count - 2]) << 8) | UInt16(capData[capData.count - 1])
        XCTAssertNotEqual(ccap & 0x0002, 0, "Mixed-mode bit must be set")
    }

    func testHTJ2KSignalledDetection() {
        XCTAssertTrue(JP3DHTMarkers.isHTJ2KSignalled(codingStyleByte: 0x40))
        XCTAssertTrue(JP3DHTMarkers.isHTJ2KSignalled(codingStyleByte: 0xFF))
        XCTAssertFalse(JP3DHTMarkers.isHTJ2KSignalled(codingStyleByte: 0x00))
        XCTAssertFalse(JP3DHTMarkers.isHTJ2KSignalled(codingStyleByte: 0x3F))
    }

    // MARK: - JP3DCodestreamBuilder HTJ2K extension

    func testBuilderWithHTJ2KConfigInsertsCAPMarker() {
        let builder = JP3DCodestreamBuilder()
        let tileData = Data(repeating: 0xAB, count: 16)
        let stream = builder.build(
            tileData: [tileData],
            width: 4, height: 4, depth: 4,
            components: 1, bitDepth: 8,
            levelsX: 1, levelsY: 1, levelsZ: 1,
            tileSizeX: 4, tileSizeY: 4, tileSizeZ: 4,
            isLossless: true,
            htj2kConfiguration: .default
        )
        // Search for CAP marker 0xFF50 in the codestream
        let hasCAPMarker = findMarker(in: stream, high: 0xFF, low: 0x50)
        XCTAssertTrue(hasCAPMarker, "HTJ2K codestream should contain CAP marker")
    }

    func testBuilderWithHTJ2KConfigInsertsCPFMarker() {
        let builder = JP3DCodestreamBuilder()
        let tileData = Data(repeating: 0xAB, count: 16)
        let stream = builder.build(
            tileData: [tileData],
            width: 4, height: 4, depth: 4,
            components: 1, bitDepth: 8,
            levelsX: 1, levelsY: 1, levelsZ: 1,
            tileSizeX: 4, tileSizeY: 4, tileSizeZ: 4,
            isLossless: true,
            htj2kConfiguration: .default
        )
        let hasCPFMarker = findMarker(in: stream, high: 0xFF, low: 0x59)
        XCTAssertTrue(hasCPFMarker, "HTJ2K codestream should contain CPF marker")
    }

    func testBuilderWithoutHTJ2KConfigOmitsCAPMarker() {
        let builder = JP3DCodestreamBuilder()
        let tileData = Data(repeating: 0xAB, count: 16)
        let stream = builder.build(
            tileData: [tileData],
            width: 4, height: 4, depth: 4,
            components: 1, bitDepth: 8,
            levelsX: 1, levelsY: 1, levelsZ: 1,
            tileSizeX: 4, tileSizeY: 4, tileSizeZ: 4,
            isLossless: true,
            htj2kConfiguration: nil
        )
        let hasCAPMarker = findMarker(in: stream, high: 0xFF, low: 0x50)
        XCTAssertFalse(hasCAPMarker, "Standard codestream must not contain CAP marker")
    }

    // MARK: - JP3DEncoder HTJ2K presets

    func testHTJ2KLosslessPreset() {
        let config = JP3DEncoderConfiguration.htj2kLossless
        XCTAssertTrue(config.compressionMode.isHTJ2K)
        XCTAssertTrue(config.compressionMode.isLossless)
    }

    func testHTJ2KLossyPreset() {
        let config = JP3DEncoderConfiguration.htj2kLossy(psnr: 38.0)
        XCTAssertTrue(config.compressionMode.isHTJ2K)
        XCTAssertFalse(config.compressionMode.isLossless)
    }

    func testHTJ2KLossyDefaultPSNR() {
        let config = JP3DEncoderConfiguration.htj2kLossy()
        // Just verify it doesn't throw and returns a valid config
        XCTAssertTrue(config.compressionMode.isHTJ2K)
    }

    // MARK: - Full encode + decode round-trip with HTJ2K

    func testHTJ2KEncodeDecodeRoundTrip() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let result = try await encoder.encode(volume)
        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertTrue(result.isLossless)

        let decoder = JP3DDecoder()
        let decResult = try await decoder.decode(result.data)
        XCTAssertEqual(decResult.volume.width, volume.width)
        XCTAssertEqual(decResult.volume.height, volume.height)
        XCTAssertEqual(decResult.volume.depth, volume.depth)
    }

    func testHTJ2KEncodeDecodeVoxelValues() async throws {
        // Flat volume (all same value) should round-trip exactly
        let width = 4
        let height = 4
        let depth = 2
        var data = Data(count: width * height * depth)
        for i in 0..<data.count { data[i] = 42 }
        let component = J2KVolumeComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, depth: depth,
            data: data
        )
        let volume = J2KVolume(width: width, height: height, depth: depth, components: [component])

        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let encResult = try await encoder.encode(volume)

        let decoder = JP3DDecoder()
        let decResult = try await decoder.decode(encResult.data)

        let out = decResult.volume.components[0].data
        for i in 0..<out.count {
            XCTAssertEqual(out[i], 42, "Voxel \(i) should be 42 after round-trip")
        }
    }

    // MARK: - Hybrid tile volume

    func testParsedCodestreamContainsHTJ2KTilesAfterHTJ2KEncode() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let result = try await encoder.encode(volume)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(result.data)
        XCTAssertTrue(codestream.containsHTJ2KTiles,
                      "HTJ2K-encoded codestream should report containsHTJ2KTiles = true")
    }

    func testParsedCodestreamStandardEncodeHasNoHTJ2KTiles() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let result = try await encoder.encode(volume)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(result.data)
        XCTAssertFalse(codestream.containsHTJ2KTiles,
                       "Standard codestream should report containsHTJ2KTiles = false")
    }

    func testIsHybridHTJ2KFalseForPureHTJ2K() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let result = try await encoder.encode(volume)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(result.data)
        // A pure-HTJ2K codestream (all tiles HT) is not hybrid
        XCTAssertFalse(codestream.isHybridHTJ2K,
                       "All-HT codestream should not be considered hybrid")
    }

    // MARK: - JP3DTranscoder tests

    func testTranscoderDefaultConfiguration() {
        let config = JP3DTranscoderConfiguration()
        XCTAssertEqual(config.direction, .standardToHTJ2K)
        XCTAssertFalse(config.verifyRoundTrip)
    }

    func testTranscoderReverseConfiguration() {
        let config = JP3DTranscoderConfiguration.reverseDefault
        XCTAssertEqual(config.direction, .htj2kToStandard)
    }

    func testTranscodeStandardToHTJ2KProducesValidCodingStream() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let standardResult = try await encoder.encode(volume)

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(standardResult.data, configuration: .forwardDefault)

        XCTAssertEqual(result.direction, .standardToHTJ2K)
        XCTAssertGreaterThan(result.tilesTranscoded, 0)
        XCTAssertTrue(result.metadataPreserved)

        // The transcoded codestream should be parsable
        let parser = JP3DCodestreamParser()
        XCTAssertNoThrow(try parser.parse(result.data))
    }

    func testTranscodeHTJ2KToStandardProducesDecodableStream() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let htResult = try await encoder.encode(volume)

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(htResult.data, configuration: .reverseDefault)

        XCTAssertEqual(result.direction, .htj2kToStandard)
        XCTAssertGreaterThan(result.tilesTranscoded, 0)

        // The transcoded codestream should be parsable and decodable
        let decoder = JP3DDecoder()
        let decResult = try await decoder.decode(result.data)
        XCTAssertEqual(decResult.volume.width, volume.width)
        XCTAssertEqual(decResult.volume.height, volume.height)
        XCTAssertEqual(decResult.volume.depth, volume.depth)
    }

    func testTranscodePreservesVolumeDimensions() async throws {
        let volume = makeTestVolume(width: 16, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let standardData = try await encoder.encode(volume).data

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(standardData, configuration: .forwardDefault)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(result.data)
        XCTAssertEqual(codestream.siz.width, volume.width)
        XCTAssertEqual(codestream.siz.height, volume.height)
        XCTAssertEqual(codestream.siz.depth, volume.depth)
    }

    func testTranscodePreservesWaveletLevels() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let encoder = JP3DEncoder(configuration: encConfig)
        let standardData = try await encoder.encode(volume).data

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(standardData, configuration: .forwardDefault)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(result.data)
        XCTAssertEqual(codestream.cod.levelsX, 2)
        XCTAssertEqual(codestream.cod.levelsY, 2)
    }

    func testTranscodeTileCount() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: JP3DTilingConfiguration(tileSizeX: 4, tileSizeY: 4, tileSizeZ: 2)
        )
        let encoder = JP3DEncoder(configuration: encConfig)
        let standardData = try await encoder.encode(volume).data

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(standardData, configuration: .forwardDefault)

        XCTAssertGreaterThan(result.tilesTranscoded, 1,
                             "Multi-tile volume should transcode multiple tiles")
    }

    // MARK: - Edge cases

    func testCodecEncodeDecodeSingleVoxel() throws {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let single: [Int32] = [127]
        let encoded = codec.encodeTile(coefficients: single, voxelCount: single.count)
        let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: single.count)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0], 127.0)
    }

    func testCodecEncodeDecodeLargeVolumeTile() throws {
        let codec = JP3DHTJ2KCodec(configuration: .default)
        let size = 64 * 64 * 8
        let coefficients = (0..<size).map { Int32($0 % 512 - 256) }
        let encoded = codec.encodeTile(coefficients: coefficients, voxelCount: size)
        let decoded = try codec.decodeTile(tileData: encoded, expectedVoxels: size)
        XCTAssertEqual(decoded.count, size)
        for i in 0..<min(10, size) {
            XCTAssertEqual(decoded[i], Float(coefficients[i]),
                           "Large tile coefficient \(i) mismatch")
        }
    }

    func testTranscodeEmptyWarningsForValidInput() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let standardData = try await encoder.encode(volume).data

        let transcoder = JP3DTranscoder()
        let result = try await transcoder.transcode(standardData, configuration: .forwardDefault)
        XCTAssertTrue(result.warnings.isEmpty,
                      "Transcoding a valid codestream should produce no warnings")
    }

    func testHTJ2KEncodeProducesNonEmptyCAPHeader() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let encoder = JP3DEncoder(configuration: .htj2kLossless)
        let result = try await encoder.encode(volume)
        // Codestream must contain CAP marker (0xFF50)
        XCTAssertTrue(findMarker(in: result.data, high: 0xFF, low: 0x50),
                      "HTJ2K encode result must include CAP marker in codestream header")
    }

    // MARK: - Private helpers

    private func findMarker(in data: Data, high: UInt8, low: UInt8) -> Bool {
        for i in 0..<(data.count - 1) {
            if data[i] == high && data[i + 1] == low { return true }
        }
        return false
    }
}
