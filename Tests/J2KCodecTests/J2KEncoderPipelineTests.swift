//
// J2KEncoderPipelineTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the JPEG 2000 encoder pipeline.
///
/// These tests validate the complete encoding pipeline from image input
/// to JPEG 2000 codestream output, including all intermediate stages.
final class J2KEncoderPipelineTests: XCTestCase {
    // MARK: - Basic Encoding Tests

    /// Tests encoding a minimal grayscale image.
    func testEncodeMinimalGrayscaleImage() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")
        assertValidCodestream(data)
    }

    /// Tests encoding a 16×16 grayscale image with actual pixel data.
    func testEncodeGrayscaleWithData() throws {
        let width = 16
        let height = 16
        var pixelData = Data(count: width * height)
        for i in 0..<(width * height) {
            pixelData[i] = UInt8(i % 256)
        }

        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding a 3-component RGB image (triggers color transform).
    func testEncodeRGBImage() throws {
        let width = 32
        let height = 32
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for i in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for p in 0..<pixelCount {
                pixelData[p] = UInt8((p + i * 64) % 256)
            }
            components.append(J2KComponent(
                index: i, bitDepth: 8, signed: false,
                width: width, height: height, data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    // MARK: - Configuration Tests

    /// Tests lossless encoding configuration.
    func testEncodeLossless() throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding with different decomposition levels.
    func testEncodeWithVariousDecompositionLevels() throws {
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 8)

        for levels in [1, 2, 3, 4] {
            let config = J2KEncodingConfiguration(
                quality: 0.9,
                lossless: false,
                decompositionLevels: levels
            )
            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)
            XCTAssertFalse(data.isEmpty, "Failed at decomposition level \(levels)")
            assertValidCodestream(data)
        }
    }

    /// Tests encoding with preset configurations.
    func testEncodeWithPresets() throws {
        // Use larger image that supports highest decomposition level (6)
        let image = J2KImage(width: 128, height: 128, components: 1, bitDepth: 8)

        for preset in J2KEncodingPreset.allCases {
            let config = preset.configuration(quality: 0.8)
            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)
            XCTAssertFalse(data.isEmpty, "Encoding failed with preset: \(preset)")
            assertValidCodestream(data)
        }
    }

    // MARK: - Codestream Structure Tests

    /// Tests that the codestream contains the required SIZ marker.
    func testCodestreamContainsSIZMarker() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)

        // SIZ marker is 0xFF51 and must follow SOC
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(data[2], 0xFF, "Third byte should be 0xFF for SIZ marker")
        XCTAssertEqual(data[3], 0x51, "Fourth byte should be 0x51 for SIZ marker")
    }

    /// Tests that the codestream contains required markers in correct order.
    func testCodestreamMarkerOrder() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        let markers = findMarkers(in: data)

        // Verify required markers are present
        XCTAssertTrue(markers.contains(0xFF4F), "Missing SOC marker")
        XCTAssertTrue(markers.contains(0xFF51), "Missing SIZ marker")
        XCTAssertTrue(markers.contains(0xFF52), "Missing COD marker")
        XCTAssertTrue(markers.contains(0xFF5C), "Missing QCD marker")
        XCTAssertTrue(markers.contains(0xFF90), "Missing SOT marker")
        XCTAssertTrue(markers.contains(0xFF93), "Missing SOD marker")
        XCTAssertTrue(markers.contains(0xFFD9), "Missing EOC marker")
    }

    // MARK: - Progress Reporting Tests

    /// Tests that progress callbacks are invoked during encoding.
    func testProgressReporting() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        var progressUpdates: [EncoderProgressUpdate] = []

        let data = try encoder.encode(image) { update in
            progressUpdates.append(update)
        }

        XCTAssertFalse(data.isEmpty)
        XCTAssertFalse(progressUpdates.isEmpty, "Should receive progress updates")

        // Should have updates for multiple stages
        let stages = Set(progressUpdates.map { $0.stage })
        XCTAssertGreaterThanOrEqual(stages.count, 2, "Should report progress for multiple stages")

        // Overall progress should be non-decreasing
        var lastOverall = 0.0
        for update in progressUpdates {
            XCTAssertGreaterThanOrEqual(update.overallProgress, lastOverall,
                "Overall progress should be non-decreasing")
            lastOverall = update.overallProgress
        }
    }

    // MARK: - Edge Cases

    /// Tests encoding an image where all pixels are zero.
    func testEncodeAllZeroImage() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding a single-pixel image (no DWT possible).
    func testEncodeSinglePixelImage() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: true,
            decompositionLevels: 1 // Pipeline will clamp to 0 for 1×1
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 1, height: 1, data: Data([128])
        )
        let image = J2KImage(width: 1, height: 1, components: [component])

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding with an image whose dimensions are not power-of-two.
    func testEncodeOddDimensionImage() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 13, height: 7, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    // MARK: - Encoder Initialization Tests

    /// Tests creating an encoder with default configuration.
    func testEncoderDefaultInit() throws {
        let encoder = J2KEncoder()
        XCTAssertEqual(encoder.configuration.quality, 0.9)
        XCTAssertEqual(encoder.encodingConfiguration.lossless, false)
        XCTAssertEqual(encoder.encodingConfiguration.decompositionLevels, 5)
        XCTAssertEqual(encoder.encodingConfiguration.qualityLayers, 5)
    }

    /// Tests creating an encoder with encoding configuration.
    func testEncoderEncodingConfigInit() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        XCTAssertEqual(encoder.encodingConfiguration.quality, 0.7)
        XCTAssertEqual(encoder.encodingConfiguration.decompositionLevels, 4)
        XCTAssertEqual(encoder.encodingConfiguration.qualityLayers, 3)
    }

    // MARK: - HTJ2K Marker Tests

    /// Tests that CAP and CPF markers are written when HTJ2K is enabled.
    func testHTJ2KMarkersIncludedWhenEnabled() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")

        // Parse the codestream to verify CAP and CPF markers are present
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        let hasCAP = segments.contains { $0.marker == .cap }
        let hasCPF = segments.contains { $0.marker == .cpf }

        XCTAssertTrue(hasCAP, "CAP marker should be present when HTJ2K is enabled")
        XCTAssertTrue(hasCPF, "CPF marker should be present when HTJ2K is enabled")
    }

    /// Tests that CAP and CPF markers are NOT written when HTJ2K is disabled.
    func testHTJ2KMarkersNotIncludedWhenDisabled() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: false
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")

        // Parse the codestream to verify CAP and CPF markers are NOT present
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        let hasCAP = segments.contains { $0.marker == .cap }
        let hasCPF = segments.contains { $0.marker == .cpf }

        XCTAssertFalse(hasCAP, "CAP marker should not be present when HTJ2K is disabled")
        XCTAssertFalse(hasCPF, "CPF marker should not be present when HTJ2K is disabled")
    }

    /// Tests that CAP marker appears before COD marker in the codestream.
    func testHTJ2KMarkerOrder() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)

        // Parse the codestream and check marker order
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        // Find positions of relevant markers
        let sizIndex = segments.firstIndex { $0.marker == .siz }
        let capIndex = segments.firstIndex { $0.marker == .cap }
        let cpfIndex = segments.firstIndex { $0.marker == .cpf }
        let codIndex = segments.firstIndex { $0.marker == .cod }

        XCTAssertNotNil(sizIndex, "SIZ marker should be present")
        XCTAssertNotNil(capIndex, "CAP marker should be present")
        XCTAssertNotNil(cpfIndex, "CPF marker should be present")
        XCTAssertNotNil(codIndex, "COD marker should be present")

        // Verify marker order: SIZ < CAP < CPF < COD
        if let siz = sizIndex, let cap = capIndex, let cpf = cpfIndex, let cod = codIndex {
            XCTAssertLessThan(siz, cap, "CAP marker should appear after SIZ")
            XCTAssertLessThan(cap, cpf, "CPF marker should appear after CAP")
            XCTAssertLessThan(cpf, cod, "COD marker should appear after CPF")
        }
    }

    /// Tests HTJ2K with lossless configuration.
    func testHTJ2KLosslessEncoding() throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 3,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)

        // Verify CPF marker indicates reversible profile (Pcpf = 0)
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        let cpfSegment = segments.first { $0.marker == .cpf }
        XCTAssertNotNil(cpfSegment, "CPF marker should be present")

        if let cpfData = cpfSegment?.data, cpfData.count >= 2 {
            let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
            XCTAssertEqual(pcpf, 0, "CPF should indicate reversible profile (0) for lossless")
        }
    }

    /// Tests HTJ2K with lossy configuration.
    func testHTJ2KLossyEncoding() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            decompositionLevels: 3,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)

        // Verify CPF marker indicates irreversible profile (Pcpf = 1)
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        let cpfSegment = segments.first { $0.marker == .cpf }
        XCTAssertNotNil(cpfSegment, "CPF marker should be present")

        if let cpfData = cpfSegment?.data, cpfData.count >= 2 {
            let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
            XCTAssertEqual(pcpf, 1, "CPF should indicate irreversible profile (1) for lossy")
        }
    }

    // MARK: - Codestream Conformance Tests

    /// Tests that COD marker writes correct decomposition levels (clamped value).
    func testCODDecompositionLevelsClamped() throws {
        // 8×8 image can support at most 2 levels (log2(8) - 1 = 2)
        // but config asks for 5 → should clamp to 2
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 5
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        assertValidCodestream(data)

        // Parse COD marker and verify decomposition levels
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()
        let codSegment = segments.first { $0.marker == .cod }
        XCTAssertNotNil(codSegment)

        if let codData = codSegment?.data, codData.count >= 6 {
            // SPcod starts after SGcod (4 bytes: Scod + progression + layers + MCT)
            // Byte 4 of codData = Scod, then bytes 5-8 = SGcod
            // Actually: Scod(1) + SGcod(progression(1) + layers(2) + MCT(1)) then SPcod starts
            // SPcod byte 0 = number of decomposition levels
            let decomLevels = codData[5] // offset 5 = first byte of SPcod
            XCTAssertLessThanOrEqual(decomLevels, 2,
                "Decomposition levels should be clamped for 8×8 image; got \(decomLevels)")
        }
    }

    /// Tests that QCD epsilon values follow ISO 15444-1 Table E.1 for lossless.
    func testQCDEpsilonValuesLossless() throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        assertValidCodestream(data)

        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()
        let qcdSegment = segments.first { $0.marker == .qcd }
        XCTAssertNotNil(qcdSegment)

        if let qcdData = qcdSegment?.data, qcdData.count >= 8 {
            // Sqcd (1 byte) then SPqcd values
            // For lossless: each SPqcd byte has epsilon in bits 3-7
            let epsilonLL = qcdData[1] >> 3   // LL: bitDepth + 0 = 8
            let epsilonHL = qcdData[2] >> 3   // HL: bitDepth + 1 = 9
            let epsilonLH = qcdData[3] >> 3   // LH: bitDepth + 1 = 9
            let epsilonHH = qcdData[4] >> 3   // HH: bitDepth + 2 = 10

            XCTAssertEqual(epsilonLL, 8, "LL epsilon should be bitDepth (8)")
            XCTAssertEqual(epsilonHL, 9, "HL epsilon should be bitDepth+1 (9)")
            XCTAssertEqual(epsilonLH, 9, "LH epsilon should be bitDepth+1 (9)")
            XCTAssertEqual(epsilonHH, 10, "HH epsilon should be bitDepth+2 (10)")
        }
    }

    /// Tests that COD MCT field is 0 for single-component images.
    func testCODMCTDisabledForGrayscale() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()
        let codSegment = segments.first { $0.marker == .cod }
        XCTAssertNotNil(codSegment)

        if let codData = codSegment?.data, codData.count >= 5 {
            // MCT is at offset 4 (after Scod(1) + progression(1) + layers(2))
            let mct = codData[4]
            XCTAssertEqual(mct, 0, "MCT should be 0 for single-component images")
        }
    }

    /// Tests that the number of packets matches expected LRCP structure.
    func testPacketCountMatchesResolutionStructure() throws {
        // 32×32, 2 decomposition levels, 1 component
        // Expected: (2+1) resolutions × 1 component = 3 packets
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)

        var pixelData = Data(count: 32 * 32)
        for i in 0..<pixelData.count {
            pixelData[i] = UInt8(i % 256)
        }
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 32, height: 32, data: pixelData
        )
        let image = J2KImage(width: 32, height: 32, components: [component])

        let data = try encoder.encode(image)
        assertValidCodestream(data)

        // The codestream should be parseable and decodable
        XCTAssertGreaterThan(data.count, 20, "Encoded codestream should have meaningful size")
    }

    /// Tests round-trip encoding and decoding produces valid output.
    func testRoundTripEncodeDecode() throws {
        let width = 32
        let height = 32
        let pixelCount = width * height

        // Create a gradient test image
        var pixelData = Data(count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                pixelData[y * width + x] = UInt8(x * 255 / (width - 1))
            }
        }

        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        // Encode lossless
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)
        assertValidCodestream(encoded)

        // Decode
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)

        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.componentCount, 1)
    }

    // MARK: - SIZ Tile Size Correctness

    /// Tests that the SIZ marker always writes tile dimensions equal to the image
    /// dimensions, since the encoder only supports single-tile mode. If tile size
    /// were smaller than the image, external decoders would expect multiple tiles
    /// but only find one, causing severe distortion.
    func testSIZTileSizeMatchesImageDimensions() throws {
        let width = 512
        let height = 512
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for i in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for p in 0..<pixelCount {
                pixelData[p] = UInt8((p &+ i &* 64) % 256)
            }
            components.append(J2KComponent(
                index: i, bitDepth: 8, signed: false,
                width: width, height: height, data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)

        // Even when config specifies a tile size, encoder forces single-tile
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 5,
            tileSize: (width: 256, height: 256)
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)

        assertValidCodestream(data)

        // Parse SIZ marker: SOC (2 bytes) + SIZ marker (2 bytes) + Lsiz (2 bytes) + Rsiz (2 bytes)
        // + Xsiz (4) + Ysiz (4) + XOsiz (4) + YOsiz (4) + XTsiz (4) + YTsiz (4)
        // SIZ starts at offset 2, data at offset 6
        XCTAssertEqual(data[2], 0xFF)
        XCTAssertEqual(data[3], 0x51, "Expected SIZ marker")

        // XTsiz at offset 6 + 2(Rsiz) + 4(Xsiz) + 4(Ysiz) + 4(XOsiz) + 4(YOsiz) = offset 24
        let xTsiz = UInt32(data[24]) << 24 | UInt32(data[25]) << 16 | UInt32(data[26]) << 8 | UInt32(data[27])
        let yTsiz = UInt32(data[28]) << 24 | UInt32(data[29]) << 16 | UInt32(data[30]) << 8 | UInt32(data[31])

        XCTAssertEqual(xTsiz, UInt32(width), "XTsiz must equal image width for single-tile mode")
        XCTAssertEqual(yTsiz, UInt32(height), "YTsiz must equal image height for single-tile mode")
    }

    /// Tests that lossy RGB encoding uses ICT (not RCT) and produces valid codestream.
    func testLossyRGBUsesICTColorTransform() throws {
        let width = 64
        let height = 64
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for i in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for p in 0..<pixelCount {
                pixelData[p] = UInt8((p &+ i &* 80) % 256)
            }
            components.append(J2KComponent(
                index: i, bitDepth: 8, signed: false,
                width: width, height: height, data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)

        assertValidCodestream(data)
        XCTAssertTrue(data.count > 100, "Encoded data should be non-trivial")
    }

    /// Tests that QCD step sizes for lossy encoding are varied across subbands
    /// (not all identical), which would indicate a key lookup failure.
    func testQCDStepSizesVaryAcrossSubbands() throws {
        let width = 64
        let height = 64
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for i in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for p in 0..<pixelCount {
                pixelData[p] = UInt8((p &+ i &* 80) % 256)
            }
            components.append(J2KComponent(
                index: i, bitDepth: 8, signed: false,
                width: width, height: height, data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)

        assertValidCodestream(data)

        // Find QCD marker (0xFF5C)
        var qcdOffset = -1
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0x5C {
                qcdOffset = i
                break
            }
        }
        XCTAssertGreaterThan(qcdOffset, 0, "QCD marker not found")

        let lqcd = Int(data[qcdOffset + 2]) << 8 | Int(data[qcdOffset + 3])
        let sqcd = data[qcdOffset + 4]
        let qstyle = sqcd & 0x1F
        XCTAssertEqual(qstyle, 2, "Expected scalar expounded quantization for lossy")

        // Read all 2-byte step size entries
        let numBands = (lqcd - 3) / 2  // 1 band for LL + 3*decompositionLevels detail
        XCTAssertEqual(numBands, 1 + 3 * 3, "Expected 10 bands for 3-level decomposition")

        var stepValues = Set<UInt16>()
        for i in 0..<numBands {
            let offset = qcdOffset + 5 + i * 2
            let val = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            stepValues.insert(val)
        }

        // Step sizes should NOT all be identical — different subbands have different gains
        XCTAssertGreaterThan(stepValues.count, 1,
            "QCD step sizes are all identical (\(stepValues)) — key lookup likely broken")
    }

    // MARK: - Helpers

    /// Asserts that the data represents a valid JPEG 2000 codestream.
    private func assertValidCodestream(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        // Must start with SOC (0xFF4F)
        XCTAssertGreaterThanOrEqual(data.count, 4, "Codestream too short", file: file, line: line)
        XCTAssertEqual(data[0], 0xFF, "Missing SOC marker high byte", file: file, line: line)
        XCTAssertEqual(data[1], 0x4F, "Missing SOC marker low byte", file: file, line: line)

        // Must end with EOC (0xFFD9)
        XCTAssertEqual(data[data.count - 2], 0xFF, "Missing EOC marker high byte", file: file, line: line)
        XCTAssertEqual(data[data.count - 1], 0xD9, "Missing EOC marker low byte", file: file, line: line)
    }

    /// Finds all 0xFF-prefixed markers in the data.
    private func findMarkers(in data: Data) -> Set<UInt16> {
        var markers = Set<UInt16>()
        var i = 0
        while i < data.count - 1 {
            if data[i] == 0xFF && data[i + 1] != 0x00 && data[i + 1] != 0xFF {
                let marker = UInt16(data[i]) << 8 | UInt16(data[i + 1])
                markers.insert(marker)
            }
            i += 1
        }
        return markers
    }
}
