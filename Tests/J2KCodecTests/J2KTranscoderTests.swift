import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the J2K Transcoder (Phase 10: Lossless Transcoding).
///
/// Validates coefficient extraction, re-encoding, round-trip integrity,
/// metadata preservation, and format detection.
final class J2KTranscoderTests: XCTestCase {
    // MARK: - Transcoding Direction Tests

    func testTranscodingDirectionRawValues() throws {
        XCTAssertEqual(TranscodingDirection.legacyToHT.rawValue, "JPEG 2000 → HTJ2K")
        XCTAssertEqual(TranscodingDirection.htToLegacy.rawValue, "HTJ2K → JPEG 2000")
    }

    // MARK: - Transcoding Stage Tests

    func testTranscodingStageAllCases() throws {
        let stages = TranscodingStage.allCases
        XCTAssertEqual(stages.count, 5)
        XCTAssertTrue(stages.contains(.parsing))
        XCTAssertTrue(stages.contains(.coefficientExtraction))
        XCTAssertTrue(stages.contains(.validation))
        XCTAssertTrue(stages.contains(.reEncoding))
        XCTAssertTrue(stages.contains(.codestreamGeneration))
    }

    // MARK: - TranscodingCodeBlockCoefficients Tests

    func testCodeBlockCoefficientsCreation() throws {
        let coefficients = [Int](repeating: 42, count: 16)
        let cb = TranscodingCodeBlockCoefficients(
            index: 0,
            x: 0, y: 0,
            width: 4, height: 4,
            subband: .hh,
            coefficients: coefficients,
            zeroBitPlanes: 2,
            codingPasses: 3
        )

        XCTAssertEqual(cb.index, 0)
        XCTAssertEqual(cb.width, 4)
        XCTAssertEqual(cb.height, 4)
        XCTAssertEqual(cb.subband, .hh)
        XCTAssertEqual(cb.coefficients.count, 16)
        XCTAssertEqual(cb.zeroBitPlanes, 2)
        XCTAssertEqual(cb.codingPasses, 3)
    }

    // MARK: - TranscodingTileCoefficients Tests

    func testTileCoefficientsCreation() throws {
        let cb = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0,
            width: 4, height: 4,
            subband: .ll,
            coefficients: [Int](repeating: 10, count: 16),
            zeroBitPlanes: 0,
            codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0,
            width: 64,
            height: 64,
            components: [[.ll: [cb]]]
        )

        XCTAssertEqual(tile.tileIndex, 0)
        XCTAssertEqual(tile.width, 64)
        XCTAssertEqual(tile.height, 64)
        XCTAssertEqual(tile.components.count, 1)
    }

    // MARK: - TranscodingCoefficients Validation Tests

    func testTranscodingCoefficientsValidation() throws {
        let cb = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0,
            width: 4, height: 4,
            subband: .ll,
            coefficients: [Int](repeating: 10, count: 16),
            zeroBitPlanes: 0,
            codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0, width: 64, height: 64,
            components: [[.ll: [cb]]]
        )

        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: [tile]
        )

        // Should not throw
        XCTAssertNoThrow(try coeffs.validate())
    }

    func testTranscodingCoefficientsValidationInvalidDimensions() throws {
        let coeffs = TranscodingCoefficients(
            width: 0, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: []
        )

        XCTAssertThrowsError(try coeffs.validate()) { error in
            if case J2KError.invalidData(let msg) = error {
                XCTAssertTrue(msg.contains("dimensions"))
            } else {
                XCTFail("Expected invalidData error")
            }
        }
    }

    func testTranscodingCoefficientsValidationMismatchedBitDepths() throws {
        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 3,
            bitDepths: [8], // Only 1 bit depth for 3 components
            signedComponents: [false, false, false],
            colorSpace: .sRGB,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: []
        )

        XCTAssertThrowsError(try coeffs.validate()) { error in
            if case J2KError.invalidData(let msg) = error {
                XCTAssertTrue(msg.contains("Bit depth count"))
            } else {
                XCTFail("Expected invalidData error")
            }
        }
    }

    func testTranscodingCoefficientsValidationBadCodeBlockSize() throws {
        // Code-block with wrong coefficient count
        let cb = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0,
            width: 4, height: 4,
            subband: .ll,
            coefficients: [Int](repeating: 10, count: 8), // 8 != 4*4=16
            zeroBitPlanes: 0,
            codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0, width: 64, height: 64,
            components: [[.ll: [cb]]]
        )

        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: [tile]
        )

        XCTAssertThrowsError(try coeffs.validate()) { error in
            if case J2KError.invalidData(let msg) = error {
                XCTAssertTrue(msg.contains("coefficients"))
            } else {
                XCTFail("Expected invalidData error")
            }
        }
    }

    func testTranscodingCoefficientsTotalCodeBlocks() throws {
        let cb1 = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0, width: 4, height: 4,
            subband: .ll,
            coefficients: [Int](repeating: 0, count: 16),
            zeroBitPlanes: 0, codingPasses: 1
        )
        let cb2 = TranscodingCodeBlockCoefficients(
            index: 1, x: 4, y: 0, width: 4, height: 4,
            subband: .hh,
            coefficients: [Int](repeating: 0, count: 16),
            zeroBitPlanes: 0, codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0, width: 64, height: 64,
            components: [[.ll: [cb1], .hh: [cb2]]]
        )

        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: [tile]
        )

        XCTAssertEqual(coeffs.totalCodeBlocks, 2)
    }

    // MARK: - J2KTranscoder Creation Tests

    func testTranscoderCreation() throws {
        let transcoder = J2KTranscoder()
        XCTAssertNotNil(transcoder)
    }

    // MARK: - Format Detection Tests

    func testDetectCodingModeLegacy() throws {
        let transcoder = J2KTranscoder()

        // Build a minimal legacy JPEG 2000 codestream (no CAP marker)
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F]) // SOC
        data.append(contentsOf: [0xFF, 0x51]) // SIZ marker
        data.append(contentsOf: [0x00, 0x29]) // Length = 41
        data.append(contentsOf: buildMinimalSIZ(width: 64, height: 64, components: 1))
        data.append(contentsOf: [0xFF, 0x52]) // COD marker
        data.append(contentsOf: [0x00, 0x0C]) // Length = 12
        data.append(contentsOf: buildMinimalCOD(htj2k: false))
        data.append(contentsOf: [0xFF, 0x90]) // SOT marker (stops header scan)
        data.append(contentsOf: [0x00, 0x0A])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x00, 0x01])

        let isHT = try transcoder.isHTJ2K(data)
        XCTAssertFalse(isHT)
    }

    func testDetectCodingModeHTJ2K() throws {
        let transcoder = J2KTranscoder()

        // Build a minimal HTJ2K codestream (with CAP marker)
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F]) // SOC
        data.append(contentsOf: [0xFF, 0x50]) // CAP marker
        data.append(contentsOf: [0x00, 0x08]) // Length = 8
        data.append(contentsOf: [0x00, 0x02, 0x00, 0x00, 0x00, 0x01]) // CAP data
        data.append(contentsOf: [0xFF, 0x51]) // SIZ marker
        data.append(contentsOf: [0x00, 0x29]) // Length = 41
        data.append(contentsOf: buildMinimalSIZ(width: 64, height: 64, components: 1))
        data.append(contentsOf: [0xFF, 0x90]) // SOT (stops header scan)
        data.append(contentsOf: [0x00, 0x0A])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x00, 0x01])

        let isHT = try transcoder.isHTJ2K(data)
        XCTAssertTrue(isHT)
    }

    func testDetectCodingModeInvalidData() throws {
        let transcoder = J2KTranscoder()

        // Too short
        XCTAssertThrowsError(try transcoder.isHTJ2K(Data([0xFF])))

        // Wrong SOC marker
        XCTAssertThrowsError(try transcoder.isHTJ2K(Data([0x00, 0x00, 0x00, 0x00])))
    }

    // MARK: - Transcoding Result Tests

    func testTranscodingResultProperties() throws {
        let result = TranscodingResult(
            data: Data([0xFF, 0x4F, 0xFF, 0xD9]),
            direction: .legacyToHT,
            codeBlocksTranscoded: 10,
            tilesProcessed: 1,
            transcodingTime: 0.5,
            metadataPreserved: true
        )

        XCTAssertEqual(result.data.count, 4)
        XCTAssertEqual(result.direction, .legacyToHT)
        XCTAssertEqual(result.codeBlocksTranscoded, 10)
        XCTAssertEqual(result.tilesProcessed, 1)
        XCTAssertEqual(result.transcodingTime, 0.5, accuracy: 0.001)
        XCTAssertTrue(result.metadataPreserved)
    }

    // MARK: - Progress Reporting Tests

    func testTranscodingProgressUpdate() throws {
        let update = TranscodingProgressUpdate(
            stage: .parsing,
            progress: 0.5,
            overallProgress: 0.1,
            direction: .legacyToHT
        )

        XCTAssertEqual(update.stage, .parsing)
        XCTAssertEqual(update.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(update.overallProgress, 0.1, accuracy: 0.001)
        XCTAssertEqual(update.direction, .legacyToHT)
    }

    // MARK: - Coefficient Round-Trip Tests

    func testCoefficientRoundTripLegacyToHT() throws {
        // Create a valid encoded JPEG 2000 codestream using the encoder
        let encoder = J2KEncoder()
        let image = createTestImage(width: 32, height: 32, components: 1, bitDepth: 8)
        let codestreamData = try encoder.encode(image)

        // Extract coefficients
        let transcoder = J2KTranscoder()
        let coefficients = try transcoder.extractCoefficients(from: codestreamData)

        // Validate coefficient structure
        XCTAssertGreaterThan(coefficients.width, 0)
        XCTAssertGreaterThan(coefficients.height, 0)
        XCTAssertGreaterThan(coefficients.componentCount, 0)
        XCTAssertEqual(coefficients.bitDepths.count, coefficients.componentCount)
        XCTAssertFalse(coefficients.tiles.isEmpty)

        // Validate
        XCTAssertNoThrow(try coefficients.validate())
    }

    func testCoefficientRoundTripHTToLegacy() throws {
        // Create an HTJ2K encoded codestream
        let config = J2KEncodingConfiguration(useHTJ2K: true)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = createTestImage(width: 32, height: 32, components: 1, bitDepth: 8)
        let codestreamData = try encoder.encode(image)

        // Extract coefficients
        let transcoder = J2KTranscoder()
        let coefficients = try transcoder.extractCoefficients(from: codestreamData)

        // Validate
        XCTAssertGreaterThan(coefficients.width, 0)
        XCTAssertGreaterThan(coefficients.componentCount, 0)
        XCTAssertNoThrow(try coefficients.validate())
    }

    // MARK: - Encode from Coefficients Tests

    func testEncodeFromCoefficientsLegacy() throws {
        let cb = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0,
            width: 4, height: 4,
            subband: .ll,
            coefficients: Array(1...16),
            zeroBitPlanes: 0,
            codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0, width: 32, height: 32,
            components: [[.ll: [cb]]]
        )

        let coeffs = TranscodingCoefficients(
            width: 32, height: 32,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: [tile]
        )

        let transcoder = J2KTranscoder()
        let result = try transcoder.encodeFromCoefficients(coeffs, useHTJ2K: false)

        // Verify codestream starts with SOC marker
        XCTAssertGreaterThan(result.count, 4)
        XCTAssertEqual(result[0], 0xFF)
        XCTAssertEqual(result[1], 0x4F) // SOC

        // Verify codestream ends with EOC marker
        XCTAssertEqual(result[result.count - 2], 0xFF)
        XCTAssertEqual(result[result.count - 1], 0xD9) // EOC
    }

    func testEncodeFromCoefficientsHTJ2K() throws {
        let cb = TranscodingCodeBlockCoefficients(
            index: 0, x: 0, y: 0,
            width: 4, height: 4,
            subband: .ll,
            coefficients: Array(1...16),
            zeroBitPlanes: 0,
            codingPasses: 1
        )

        let tile = TranscodingTileCoefficients(
            tileIndex: 0, width: 32, height: 32,
            components: [[.ll: [cb]]]
        )

        let coeffs = TranscodingCoefficients(
            width: 32, height: 32,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: [tile]
        )

        let transcoder = J2KTranscoder()
        let result = try transcoder.encodeFromCoefficients(coeffs, useHTJ2K: true)

        // Verify codestream structure
        XCTAssertGreaterThan(result.count, 4)
        XCTAssertEqual(result[0], 0xFF)
        XCTAssertEqual(result[1], 0x4F) // SOC

        // Verify CAP marker is present (HTJ2K)
        var hasCAP = false
        var offset = 2
        while offset < result.count - 1 {
            let marker = UInt16(result[offset]) << 8 | UInt16(result[offset + 1])
            if marker == 0xFF50 { // CAP marker
                hasCAP = true
                break
            }
            if marker == 0xFF90 { break } // SOT - stop scanning
            offset += 2
            if offset + 1 < result.count && marker != 0xFF4F && marker != 0xFFD9 {
                let len = Int(result[offset]) << 8 | Int(result[offset + 1])
                offset += len
            }
        }
        XCTAssertTrue(hasCAP, "HTJ2K codestream should contain CAP marker")
    }

    // MARK: - Full Transcoding Pipeline Tests

    func testTranscodeLegacyToHT() throws {
        // Create a legacy JPEG 2000 codestream
        let encoder = J2KEncoder()
        let image = createTestImage(width: 32, height: 32, components: 1, bitDepth: 8)
        let legacyData = try encoder.encode(image)

        // Transcode to HTJ2K
        let transcoder = J2KTranscoder()
        let result = try transcoder.transcode(legacyData, direction: .legacyToHT)

        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertEqual(result.direction, .legacyToHT)
        XCTAssertGreaterThan(result.codeBlocksTranscoded, 0)
        XCTAssertGreaterThan(result.tilesProcessed, 0)
        XCTAssertGreaterThan(result.transcodingTime, 0)
        XCTAssertTrue(result.metadataPreserved)
    }

    func testTranscodeHTToLegacy() throws {
        // Create an HTJ2K codestream
        let config = J2KEncodingConfiguration(useHTJ2K: true)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = createTestImage(width: 32, height: 32, components: 1, bitDepth: 8)
        let htData = try encoder.encode(image)

        // Transcode to legacy
        let transcoder = J2KTranscoder()
        let result = try transcoder.transcode(htData, direction: .htToLegacy)

        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertEqual(result.direction, .htToLegacy)
        XCTAssertGreaterThan(result.tilesProcessed, 0)
        XCTAssertTrue(result.metadataPreserved)
    }

    func testTranscodeWithProgressReporting() throws {
        let encoder = J2KEncoder()
        let image = createTestImage(width: 32, height: 32, components: 1, bitDepth: 8)
        let codestreamData = try encoder.encode(image)

        let transcoder = J2KTranscoder()

        // Use atomic counter instead of array to avoid Swift 6 concurrency issues
        nonisolated(unsafe) var progressCallCount = 0
        let result = try transcoder.transcode(
            codestreamData,
            direction: .legacyToHT
        ) { update in
            progressCallCount += 1
        }

        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertGreaterThan(progressCallCount, 0, "Should receive progress updates")
    }

    // MARK: - Metadata Preservation Tests

    func testMetadataPreservationDimensions() throws {
        let encoder = J2KEncoder()
        let image = createTestImage(width: 48, height: 32, components: 1, bitDepth: 8)
        let codestreamData = try encoder.encode(image)

        let transcoder = J2KTranscoder()
        let coefficients = try transcoder.extractCoefficients(from: codestreamData)

        XCTAssertEqual(coefficients.width, 48)
        XCTAssertEqual(coefficients.height, 32)
        XCTAssertEqual(coefficients.componentCount, 1)
    }

    func testMetadataPreservationMultiComponent() throws {
        let encoder = J2KEncoder()
        let image = createTestImage(width: 32, height: 32, components: 3, bitDepth: 8)
        let codestreamData = try encoder.encode(image)

        let transcoder = J2KTranscoder()
        let coefficients = try transcoder.extractCoefficients(from: codestreamData)

        XCTAssertEqual(coefficients.componentCount, 3)
        XCTAssertEqual(coefficients.bitDepths.count, 3)
        XCTAssertEqual(coefficients.signedComponents.count, 3)
    }

    // MARK: - Edge Cases

    func testTranscodeEmptyInput() throws {
        let transcoder = J2KTranscoder()
        XCTAssertThrowsError(try transcoder.transcode(Data(), direction: .legacyToHT))
    }

    func testTranscodeInvalidInput() throws {
        let transcoder = J2KTranscoder()
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try transcoder.transcode(invalidData, direction: .legacyToHT))
    }

    func testTranscodingCoefficientsNoComponents() throws {
        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 0,
            bitDepths: [],
            signedComponents: [],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: []
        )

        XCTAssertThrowsError(try coeffs.validate())
    }

    func testTranscodingCoefficientsInvalidBitDepth() throws {
        let coeffs = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [50], // Invalid: exceeds 38
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: []
        )

        XCTAssertThrowsError(try coeffs.validate())
    }

    // MARK: - Source Coding Mode Tests

    func testSourceIsHTJ2KProperty() throws {
        let coeffsLegacy = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: false,
            tiles: []
        )

        XCTAssertFalse(coeffsLegacy.sourceIsHTJ2K)

        let coeffsHT = TranscodingCoefficients(
            width: 64, height: 64,
            componentCount: 1,
            bitDepths: [8],
            signedComponents: [false],
            colorSpace: .grayscale,
            decompositionLevels: 3,
            progressionOrder: .lrcp,
            qualityLayers: 1,
            isLossless: true,
            sourceIsHTJ2K: true,
            tiles: []
        )

        XCTAssertTrue(coeffsHT.sourceIsHTJ2K)
    }

    // MARK: - Helper Methods

    /// Creates a test image with the specified parameters.
    private func createTestImage(
        width: Int,
        height: Int,
        components: Int,
        bitDepth: Int
    ) -> J2KImage {
        let imageComponents = (0..<components).map { index in
            var comp = J2KComponent(
                index: index,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height
            )
            // Fill with simple gradient data
            var data = Data(count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    let value = UInt8((x + y * width) % 256)
                    data[y * width + x] = value
                }
            }
            comp.data = data
            return comp
        }

        return J2KImage(
            width: width,
            height: height,
            components: imageComponents,
            colorSpace: components >= 3 ? .sRGB : .grayscale
        )
    }

    /// Builds a minimal SIZ marker segment body for testing.
    private func buildMinimalSIZ(width: Int, height: Int, components: Int) -> [UInt8] {
        var data: [UInt8] = []

        // Rsiz (2 bytes)
        data.append(contentsOf: [0x00, 0x00])

        // Xsiz (4 bytes) - image width
        data.append(UInt8((width >> 24) & 0xFF))
        data.append(UInt8((width >> 16) & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))

        // Ysiz (4 bytes) - image height
        data.append(UInt8((height >> 24) & 0xFF))
        data.append(UInt8((height >> 16) & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))

        // XOsiz, YOsiz (8 bytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // XTsiz (4 bytes) - tile width = image width (single tile)
        data.append(UInt8((width >> 24) & 0xFF))
        data.append(UInt8((width >> 16) & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))

        // YTsiz (4 bytes) - tile height = image height
        data.append(UInt8((height >> 24) & 0xFF))
        data.append(UInt8((height >> 16) & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))

        // XTOsiz, YTOsiz (8 bytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Csiz (2 bytes) - number of components
        data.append(UInt8((components >> 8) & 0xFF))
        data.append(UInt8(components & 0xFF))

        // Per-component: Ssiz, XRsiz, YRsiz
        for _ in 0..<components {
            data.append(0x07) // 8-bit unsigned (7 + 1 = 8)
            data.append(0x01) // XRsiz
            data.append(0x01) // YRsiz
        }

        return data
    }

    /// Builds a minimal COD marker segment body for testing.
    private func buildMinimalCOD(htj2k: Bool) -> [UInt8] {
        var data: [UInt8] = []

        // Scod (1 byte)
        data.append(htj2k ? 0x40 : 0x00)

        // SGcod - progression order (1 byte)
        data.append(0x00) // LRCP

        // SGcod - number of layers (2 bytes)
        data.append(contentsOf: [0x00, 0x01])

        // SGcod - MCT (1 byte)
        data.append(0x00)

        // SPcod - decomposition levels (1 byte)
        data.append(0x05) // 5 levels

        // SPcod - code-block width (1 byte) exponent - 2
        data.append(0x03) // exponent 3 → 2^(3+2) = 32

        // SPcod - code-block height (1 byte) exponent - 2
        data.append(0x03) // exponent 3 → 2^(3+2) = 32

        // SPcod - code-block style (1 byte)
        data.append(0x00)

        // SPcod - transform (1 byte)
        data.append(0x01) // 5/3 reversible

        return data
    }

    // MARK: - Parallel Transcoding Tests

    func testParallelTranscodingConfiguration() throws {
        // Test default configuration
        let defaultConfig = TranscodingConfiguration.default
        XCTAssertTrue(defaultConfig.enableParallelProcessing)
        XCTAssertGreaterThan(defaultConfig.maxConcurrency, 0)

        // Test sequential configuration
        let sequentialConfig = TranscodingConfiguration.sequential
        XCTAssertFalse(sequentialConfig.enableParallelProcessing)

        // Test custom configuration
        let customConfig = TranscodingConfiguration(
            enableParallelProcessing: true,
            maxConcurrency: 4
        )
        XCTAssertTrue(customConfig.enableParallelProcessing)
        XCTAssertEqual(customConfig.maxConcurrency, 4)
    }

    func testParallelTranscoderCreation() throws {
        // Test default transcoder
        let defaultTranscoder = J2KTranscoder()
        XCTAssertTrue(defaultTranscoder.configuration.enableParallelProcessing)

        // Test transcoder with sequential processing
        let sequentialTranscoder = J2KTranscoder(configuration: .sequential)
        XCTAssertFalse(sequentialTranscoder.configuration.enableParallelProcessing)

        // Test transcoder with custom configuration
        let customConfig = TranscodingConfiguration(
            enableParallelProcessing: true,
            maxConcurrency: 2
        )
        let customTranscoder = J2KTranscoder(configuration: customConfig)
        XCTAssertTrue(customTranscoder.configuration.enableParallelProcessing)
        XCTAssertEqual(customTranscoder.configuration.maxConcurrency, 2)
    }

    func testAsyncTranscodeMethod() async throws {
        let transcoder = J2KTranscoder()
        // Use a simple legacy codestream for testing
        let data = buildMinimalLegacyCodestream()

        // Test async transcoding
        let result = try await transcoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )

        XCTAssertEqual(result.direction, TranscodingDirection.legacyToHT)
        XCTAssertGreaterThan(result.data.count, 0)
        XCTAssertTrue(result.metadataPreserved)
    }

    func testParallelVsSequentialTranscodingComparison() async throws {
        // Create a simple codestream for testing
        let data = buildMinimalLegacyCodestream()

        // Test with parallel processing
        let parallelTranscoder = J2KTranscoder(configuration: .default)
        let parallelResult = try await parallelTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )

        // Test with sequential processing
        let sequentialTranscoder = J2KTranscoder(configuration: .sequential)
        let sequentialResult = try await sequentialTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )

        // Results should be functionally equivalent
        XCTAssertEqual(parallelResult.direction, sequentialResult.direction)
        XCTAssertEqual(parallelResult.tilesProcessed, sequentialResult.tilesProcessed)
        XCTAssertTrue(parallelResult.metadataPreserved)
        XCTAssertTrue(sequentialResult.metadataPreserved)
    }

    private func buildMinimalLegacyCodestream() -> Data {
        var data = Data()

        // SOC marker
        data.append(contentsOf: [0xFF, 0x4F])

        // SIZ marker
        data.append(contentsOf: [0xFF, 0x51])
        data.append(contentsOf: buildMinimalSIZ(width: 128, height: 128, components: 1))

        // COD marker
        data.append(contentsOf: [0xFF, 0x52])
        data.append(contentsOf: buildMinimalCOD(htj2k: false))

        // QCD marker (minimal)
        data.append(contentsOf: [0xFF, 0x5C])
        let qcdData: [UInt8] = [0x00, 0x07, 0x00, 0x88, 0x88, 0x88, 0x88]
        data.append(UInt8((qcdData.count >> 8) & 0xFF))
        data.append(UInt8(qcdData.count & 0xFF))
        data.append(contentsOf: qcdData)

        // SOT marker (tile 0)
        data.append(contentsOf: [0xFF, 0x90, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x14, 0x00, 0x01])

        // SOD marker
        data.append(contentsOf: [0xFF, 0x93])

        // Minimal tile data (8 zero bytes)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        // EOC marker
        data.append(contentsOf: [0xFF, 0xD9])

        return data
    }

    /// Builds a multi-tile legacy JPEG 2000 codestream for parallel transcoding tests.
    ///
    /// - Parameters:
    ///   - imageWidth: Total image width
    ///   - imageHeight: Total image height
    ///   - tileWidth: Width of each tile
    ///   - tileHeight: Height of each tile
    ///   - components: Number of image components
    /// - Returns: A minimal valid multi-tile JPEG 2000 codestream
    private func buildMultiTileLegacyCodestream(
        imageWidth: Int = 512,
        imageHeight: Int = 512,
        tileWidth: Int = 256,
        tileHeight: Int = 256,
        components: Int = 1
    ) -> Data {
        var data = Data()

        // SOC marker
        data.append(contentsOf: [0xFF, 0x4F])

        // SIZ marker with tiling parameters
        data.append(contentsOf: [0xFF, 0x51])
        var sizData = Data()

        // Rsiz (2 bytes) - capabilities
        sizData.append(contentsOf: [0x00, 0x00])

        // Xsiz (4 bytes) - image width
        sizData.append(UInt8((imageWidth >> 24) & 0xFF))
        sizData.append(UInt8((imageWidth >> 16) & 0xFF))
        sizData.append(UInt8((imageWidth >> 8) & 0xFF))
        sizData.append(UInt8(imageWidth & 0xFF))

        // Ysiz (4 bytes) - image height
        sizData.append(UInt8((imageHeight >> 24) & 0xFF))
        sizData.append(UInt8((imageHeight >> 16) & 0xFF))
        sizData.append(UInt8((imageHeight >> 8) & 0xFF))
        sizData.append(UInt8(imageHeight & 0xFF))

        // XOsiz, YOsiz (8 bytes) - image offset
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // XTsiz (4 bytes) - tile width
        sizData.append(UInt8((tileWidth >> 24) & 0xFF))
        sizData.append(UInt8((tileWidth >> 16) & 0xFF))
        sizData.append(UInt8((tileWidth >> 8) & 0xFF))
        sizData.append(UInt8(tileWidth & 0xFF))

        // YTsiz (4 bytes) - tile height
        sizData.append(UInt8((tileHeight >> 24) & 0xFF))
        sizData.append(UInt8((tileHeight >> 16) & 0xFF))
        sizData.append(UInt8((tileHeight >> 8) & 0xFF))
        sizData.append(UInt8(tileHeight & 0xFF))

        // XTOsiz, YTOsiz (8 bytes) - tile offset
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Csiz (2 bytes) - number of components
        sizData.append(UInt8((components >> 8) & 0xFF))
        sizData.append(UInt8(components & 0xFF))

        // Per-component: Ssiz, XRsiz, YRsiz
        for _ in 0..<components {
            sizData.append(0x07) // 8-bit unsigned
            sizData.append(0x01) // XRsiz
            sizData.append(0x01) // YRsiz
        }

        let sizLength = UInt16(sizData.count + 2)
        data.append(UInt8((sizLength >> 8) & 0xFF))
        data.append(UInt8(sizLength & 0xFF))
        data.append(sizData)

        // COD marker
        data.append(contentsOf: [0xFF, 0x52])
        let codData = buildMinimalCOD(htj2k: false)
        let codLength = UInt16(codData.count + 2)
        data.append(UInt8((codLength >> 8) & 0xFF))
        data.append(UInt8(codLength & 0xFF))
        data.append(contentsOf: codData)

        // QCD marker
        data.append(contentsOf: [0xFF, 0x5C])
        let qcdData: [UInt8] = [0x00, 0x07, 0x00, 0x88, 0x88, 0x88, 0x88]
        data.append(UInt8((qcdData.count >> 8) & 0xFF))
        data.append(UInt8(qcdData.count & 0xFF))
        data.append(contentsOf: qcdData)

        // Calculate number of tiles
        let tilesX = (imageWidth + tileWidth - 1) / tileWidth
        let tilesY = (imageHeight + tileHeight - 1) / tileHeight
        let totalTiles = tilesX * tilesY

        // Write tile data for each tile
        for tileIdx in 0..<totalTiles {
            // SOT marker
            data.append(contentsOf: [0xFF, 0x90])
            let sotLength: UInt16 = 10
            data.append(UInt8((sotLength >> 8) & 0xFF))
            data.append(UInt8(sotLength & 0xFF))

            // Isot (tile index)
            data.append(UInt8((UInt16(tileIdx) >> 8) & 0xFF))
            data.append(UInt8(UInt16(tileIdx) & 0xFF))

            // Psot (tile-part length)
            let tileDataSize = 8 // Minimal tile data
            let psot = UInt32(12 + tileDataSize)
            data.append(UInt8((psot >> 24) & 0xFF))
            data.append(UInt8((psot >> 16) & 0xFF))
            data.append(UInt8((psot >> 8) & 0xFF))
            data.append(UInt8(psot & 0xFF))

            // TPsot (tile-part index)
            data.append(0x00)

            // TNsot (number of tile-parts)
            data.append(0x01)

            // SOD marker
            data.append(contentsOf: [0xFF, 0x93])

            // Minimal tile data (8 zero bytes)
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }

        // EOC marker
        data.append(contentsOf: [0xFF, 0xD9])

        return data
    }

    // MARK: - Multi-Tile Parallel Transcoding Tests

    func testMultiTileParallelTranscoding() async throws {
        // Create a 4-tile codestream (2x2 grid, 512x512 image with 256x256 tiles)
        let data = buildMultiTileLegacyCodestream(
            imageWidth: 512,
            imageHeight: 512,
            tileWidth: 256,
            tileHeight: 256,
            components: 1
        )

        // Test with parallel processing
        let parallelTranscoder = J2KTranscoder(configuration: .default)
        let parallelResult = try await parallelTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )

        // Verify results
        XCTAssertEqual(parallelResult.direction, .legacyToHT)
        XCTAssertEqual(parallelResult.tilesProcessed, 4, "Should process all 4 tiles")
        XCTAssertGreaterThan(parallelResult.data.count, 0)
        XCTAssertTrue(parallelResult.metadataPreserved)

        // Test with sequential processing for comparison
        let sequentialTranscoder = J2KTranscoder(configuration: .sequential)
        let sequentialResult = try await sequentialTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )

        // Verify sequential results
        XCTAssertEqual(sequentialResult.direction, .legacyToHT)
        XCTAssertEqual(sequentialResult.tilesProcessed, 4)
        XCTAssertTrue(sequentialResult.metadataPreserved)

        // Results should produce valid codestreams
        XCTAssertGreaterThan(parallelResult.data.count, 100)
        XCTAssertGreaterThan(sequentialResult.data.count, 100)
    }

    func testParallelTranscodingPerformanceBenchmark() async throws {
        // Create an 8-tile codestream (2x4 grid for better parallelization)
        let data = buildMultiTileLegacyCodestream(
            imageWidth: 1024,
            imageHeight: 512,
            tileWidth: 512,
            tileHeight: 128,
            components: 1
        )

        // Benchmark parallel processing
        let parallelTranscoder = J2KTranscoder(configuration: .default)
        let parallelStart = DispatchTime.now()
        let parallelResult = try await parallelTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )
        let parallelEnd = DispatchTime.now()
        let parallelTime = Double(parallelEnd.uptimeNanoseconds - parallelStart.uptimeNanoseconds) / 1_000_000_000.0

        // Benchmark sequential processing
        let sequentialTranscoder = J2KTranscoder(configuration: .sequential)
        let sequentialStart = DispatchTime.now()
        let sequentialResult = try await sequentialTranscoder.transcodeAsync(
            data,
            direction: .legacyToHT
        )
        let sequentialEnd = DispatchTime.now()
        let sequentialTime = Double(sequentialEnd.uptimeNanoseconds - sequentialStart.uptimeNanoseconds) / 1_000_000_000.0

        // Log performance metrics
        print("Multi-tile Transcoding Performance:")
        print("  Tiles: \(parallelResult.tilesProcessed)")
        print("  Parallel time: \(String(format: "%.4f", parallelTime))s")
        print("  Sequential time: \(String(format: "%.4f", sequentialTime))s")

        if sequentialTime > 0 {
            let speedup = sequentialTime / parallelTime
            print("  Speedup: \(String(format: "%.2f", speedup))x")

            // For multi-tile images, parallel should be at least as fast
            // (on multi-core systems, it should be faster)
            XCTAssertLessThanOrEqual(parallelTime, sequentialTime * 1.5,
                "Parallel processing should not be significantly slower than sequential")
        }

        // Verify both produced valid results
        XCTAssertEqual(parallelResult.tilesProcessed, 8)
        XCTAssertEqual(sequentialResult.tilesProcessed, 8)
        XCTAssertTrue(parallelResult.metadataPreserved)
        XCTAssertTrue(sequentialResult.metadataPreserved)
    }
}
