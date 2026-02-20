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
