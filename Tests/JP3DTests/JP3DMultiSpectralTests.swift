// JP3DMultiSpectralTests.swift
// J2KSwift
//
// Tests for Phase 19 multi-spectral JP3D types, encoder, decoder, and spectral analysis.

import XCTest
@testable import J2K3D
@testable import J2KCore

final class JP3DMultiSpectralTests: XCTestCase {

    // MARK: - JP3DSpectralBand

    func testSpectralBandInitialisation() {
        let band = JP3DSpectralBand(bandIndex: 2, wavelengthNanometres: 842.0, description: "NIR")
        XCTAssertEqual(band.bandIndex, 2)
        XCTAssertEqual(band.wavelengthNanometres, 842.0)
        XCTAssertEqual(band.description, "NIR")
    }

    func testSpectralBandEquality() {
        let a = JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red")
        let b = JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red")
        XCTAssertEqual(a, b)
    }

    func testSpectralBandInequality() {
        let a = JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665.0, description: "Red")
        let b = JP3DSpectralBand(bandIndex: 1, wavelengthNanometres: 560.0, description: "Green")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - JP3DSpectralMapping

    func testSpectralMappingVisible() {
        let mapping = JP3DSpectralMapping.visible
        XCTAssertEqual(mapping.bands.count, 3)
        XCTAssertEqual(mapping.bands[0].description, "Red")
        XCTAssertEqual(mapping.bands[1].description, "Green")
        XCTAssertEqual(mapping.bands[2].description, "Blue")
        XCTAssertEqual(mapping.bands[0].wavelengthNanometres, 665.0)
    }

    func testSpectralMappingNearInfrared() {
        let mapping = JP3DSpectralMapping.nearInfrared
        XCTAssertEqual(mapping.bands.count, 3)
        XCTAssertEqual(mapping.bands[1].description, "NIR")
        XCTAssertEqual(mapping.bands[1].wavelengthNanometres, 842.0)
        XCTAssertEqual(mapping.bands[2].description, "SWIR")
    }

    func testSpectralMappingHyperspectral() {
        let mapping = JP3DSpectralMapping.hyperspectral(bandCount: 10)
        XCTAssertEqual(mapping.bands.count, 10)
        XCTAssertEqual(mapping.bands.first!.wavelengthNanometres, 400.0, accuracy: 0.01)
        XCTAssertEqual(mapping.bands.last!.wavelengthNanometres, 2500.0, accuracy: 0.01)
    }

    func testSpectralMappingHyperspectralSingleBand() {
        let mapping = JP3DSpectralMapping.hyperspectral(bandCount: 1)
        XCTAssertEqual(mapping.bands.count, 1)
        XCTAssertEqual(mapping.bands[0].wavelengthNanometres, 400.0, accuracy: 0.01)
    }

    func testSpectralMappingHyperspectralMinimumClamped() {
        let mapping = JP3DSpectralMapping.hyperspectral(bandCount: 0)
        XCTAssertEqual(mapping.bands.count, 1)
    }

    // MARK: - JP3DMultiSpectralVolume

    func testMultiSpectralVolumeCreation() {
        let samples: [[Float]] = Array(
            repeating: Array(repeating: 0.5, count: 4 * 4 * 2),
            count: 3
        )
        let volume = JP3DMultiSpectralVolume(
            width: 4, height: 4, depth: 2,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: samples
        )
        XCTAssertEqual(volume.width, 4)
        XCTAssertEqual(volume.height, 4)
        XCTAssertEqual(volume.depth, 2)
        XCTAssertEqual(volume.bandCount, 3)
        XCTAssertEqual(volume.voxelCount, 32)
    }

    func testMultiSpectralVolumeSpectralRange() {
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: [0.5, 0.5, 0.5, 0.5], count: 3)
        )
        let range = volume.spectralRange
        XCTAssertNotNil(range)
        XCTAssertEqual(range!.min, 490.0, accuracy: 0.1)
        XCTAssertEqual(range!.max, 665.0, accuracy: 0.1)
    }

    func testMultiSpectralVolumeSpectralRangeNoBands() {
        let volume = JP3DMultiSpectralVolume(
            width: 1, height: 1, depth: 1, bands: [], samplesPerBand: []
        )
        XCTAssertNil(volume.spectralRange)
    }

    func testMultiSpectralVolumeDimensionClamping() {
        let volume = JP3DMultiSpectralVolume(
            width: 0, height: -1, depth: 0, bands: [], samplesPerBand: []
        )
        XCTAssertEqual(volume.width, 1)
        XCTAssertEqual(volume.height, 1)
        XCTAssertEqual(volume.depth, 1)
    }

    // MARK: - JP3DSpectralClassification

    func testSpectralClassificationAllCases() {
        let all = JP3DSpectralClassification.allCases
        XCTAssertTrue(all.contains(.unclassified))
        XCTAssertTrue(all.contains(.vegetation))
        XCTAssertTrue(all.contains(.water))
        XCTAssertTrue(all.contains(.urban))
        XCTAssertTrue(all.contains(.bareSoil))
        XCTAssertTrue(all.contains(.cloud))
        XCTAssertEqual(all.count, 6)
    }

    // MARK: - JP3DSpectralConfiguration

    func testSpectralConfigurationDefault() {
        let config = JP3DSpectralConfiguration.default
        XCTAssertEqual(config.spectralMapping.bands.count, 3)
        XCTAssertEqual(config.normalisationRange, 0.0...1.0)
        XCTAssertFalse(config.enableInterBandPrediction)
    }

    // MARK: - JP3DMultiSpectralEncoderConfiguration

    func testEncoderConfigurationDefault() {
        let config = JP3DMultiSpectralEncoderConfiguration.default
        XCTAssertEqual(config.qualityLayersPerBand, 1)
        XCTAssertFalse(config.enableSpectralDecorelation)
        XCTAssertFalse(config.spectralConfig.enableInterBandPrediction)
    }

    func testEncoderConfigurationQualityLayersClamping() {
        let config = JP3DMultiSpectralEncoderConfiguration(
            baseConfiguration: .lossless,
            spectralConfig: .default,
            qualityLayersPerBand: 0,
            enableSpectralDecorelation: false
        )
        XCTAssertEqual(config.qualityLayersPerBand, 1)
    }

    // MARK: - JP3DMultiSpectralDecodeOptions

    func testDecodeOptionsFull() {
        let options = JP3DMultiSpectralDecodeOptions.full
        XCTAssertNil(options.targetBands)
        XCTAssertEqual(options.resolutionLevel, 0)
    }

    func testDecodeOptionsCustom() {
        let options = JP3DMultiSpectralDecodeOptions(targetBands: [0, 2], resolutionLevel: 1)
        XCTAssertEqual(options.targetBands, [0, 2])
        XCTAssertEqual(options.resolutionLevel, 1)
    }

    func testDecodeOptionsResolutionLevelClamping() {
        let options = JP3DMultiSpectralDecodeOptions(targetBands: nil, resolutionLevel: -5)
        XCTAssertEqual(options.resolutionLevel, 0)
    }

    // MARK: - JP3DMultiSpectralEncoder (actor)

    func testEncoderActorCreation() async {
        let encoder = JP3DMultiSpectralEncoder()
        // Verify actor initialises without crashing.
        _ = encoder
    }

    func testEncoderEncodeSmallVolume() async throws {
        let encoder = JP3DMultiSpectralEncoder()
        let samples = Array(repeating: Float(0.5), count: 2 * 2 * 1)
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: samples, count: 3)
        )
        let result = try await encoder.encode(volume, configuration: .default)
        XCTAssertEqual(result.encodedBands.count, 3)
        XCTAssertGreaterThan(result.totalBytes, 0)
        XCTAssertEqual(result.spectralMapping.bands.count, 3)
    }

    func testEncoderMismatchedBandCountThrows() async {
        let encoder = JP3DMultiSpectralEncoder()
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,  // 3 bands
            samplesPerBand: [[0.5, 0.5, 0.5, 0.5]]    // only 1 array
        )
        do {
            _ = try await encoder.encode(volume, configuration: .default)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssertTrue(error is J2KError)
        }
    }

    func testEncoderComputeStatistics() async {
        let encoder = JP3DMultiSpectralEncoder()
        let samples: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let volume = JP3DMultiSpectralVolume(
            width: 5, height: 1, depth: 1,
            bands: [JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665, description: "Red")],
            samplesPerBand: [samples]
        )
        let stats = await encoder.computeStatistics(volume)
        XCTAssertEqual(stats.meanPerBand.count, 1)
        XCTAssertEqual(stats.meanPerBand[0], 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(stats.stdDevPerBand[0], 0)
        XCTAssertEqual(stats.minPerBand[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(stats.maxPerBand[0], 1.0, accuracy: 0.001)
    }

    func testEncoderWithInterBandPrediction() async throws {
        let encoder = JP3DMultiSpectralEncoder()
        let samples = Array(repeating: Float(0.5), count: 4)
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: samples, count: 3)
        )
        var config = JP3DMultiSpectralEncoderConfiguration.default
        config.spectralConfig.enableInterBandPrediction = true
        let result = try await encoder.encode(volume, configuration: config)
        XCTAssertEqual(result.encodedBands.count, 3)
    }

    // MARK: - JP3DMultiSpectralDecoder (actor)

    func testDecoderActorCreation() async {
        let decoder = JP3DMultiSpectralDecoder()
        _ = decoder
    }

    func testDecoderRoundTrip() async throws {
        let encoder = JP3DMultiSpectralEncoder()
        let decoder = JP3DMultiSpectralDecoder()
        let originalSamples = (0..<4).map { Float($0) / 3.0 }
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: originalSamples, count: 3)
        )
        let encoded = try await encoder.encode(volume, configuration: .default)
        let decoded = try await decoder.decode(encoded, options: .full)
        XCTAssertEqual(decoded.bandCount, 3)
        XCTAssertEqual(decoded.samplesPerBand.count, 3)
    }

    func testDecoderInvalidBandIndexThrows() async throws {
        let encoder = JP3DMultiSpectralEncoder()
        let decoder = JP3DMultiSpectralDecoder()
        let samples = Array(repeating: Float(0.5), count: 4)
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: samples, count: 3)
        )
        let encoded = try await encoder.encode(volume, configuration: .default)
        let options = JP3DMultiSpectralDecodeOptions(targetBands: [99], resolutionLevel: 0)
        do {
            _ = try await decoder.decode(encoded, options: options)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssertTrue(error is J2KError)
        }
    }

    func testDecoderClassifyPixels() async throws {
        let encoder = JP3DMultiSpectralEncoder()
        let decoder = JP3DMultiSpectralDecoder()
        let samples = Array(repeating: Float(0.9), count: 4)
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: JP3DSpectralMapping.visible.bands,
            samplesPerBand: Array(repeating: samples, count: 3)
        )
        let encoded = try await encoder.encode(volume, configuration: .default)
        let decoded = try await decoder.decode(encoded, options: .full)
        let classification = await decoder.classifyPixels(decoded)
        XCTAssertFalse(classification.isEmpty)
    }

    // MARK: - JP3DSpectralIndex

    func testSpectralIndexAllCases() {
        let all = JP3DSpectralIndex.allCases
        XCTAssertTrue(all.contains(.ndvi))
        XCTAssertTrue(all.contains(.ndwi))
        XCTAssertTrue(all.contains(.ndbi))
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - JP3DSpectralAnalyser (actor)

    func testSpectralAnalyserActorCreation() async {
        let analyser = JP3DSpectralAnalyser()
        _ = analyser
    }

    func testSpectralAnalyserComputeCorrelationMatrix() async {
        let analyser = JP3DSpectralAnalyser()
        let samples: [[Float]] = [
            [0.1, 0.2, 0.3, 0.4],
            [0.4, 0.3, 0.2, 0.1],
        ]
        let volume = JP3DMultiSpectralVolume(
            width: 4, height: 1, depth: 1,
            bands: JP3DSpectralMapping.nearInfrared.bands.prefix(2).map { $0 },
            samplesPerBand: samples
        )
        let matrix = await analyser.computeCorrelationMatrix(volume)
        XCTAssertEqual(matrix.count, 2)
        XCTAssertEqual(matrix[0].count, 2)
        // Diagonal must be 1.0
        XCTAssertEqual(matrix[0][0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(matrix[1][1], 1.0, accuracy: 1e-9)
        // Perfectly anti-correlated bands → r ≈ −1
        XCTAssertEqual(matrix[0][1], matrix[1][0], accuracy: 1e-9)
        XCTAssertEqual(matrix[0][1], -1.0, accuracy: 1e-6)
    }

    func testSpectralAnalyserComputeNDVIIndex() async throws {
        let analyser = JP3DSpectralAnalyser()
        let nirSamples: [Float] = [0.6, 0.6, 0.6, 0.6]
        let redSamples: [Float] = [0.2, 0.2, 0.2, 0.2]
        // Place Red at 665 nm, NIR at 842 nm
        let bands: [JP3DSpectralBand] = [
            JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665, description: "Red"),
            JP3DSpectralBand(bandIndex: 1, wavelengthNanometres: 842, description: "NIR"),
        ]
        let volume = JP3DMultiSpectralVolume(
            width: 4, height: 1, depth: 1,
            bands: bands,
            samplesPerBand: [redSamples, nirSamples]
        )
        let result = try await analyser.computeIndex(volume, index: .ndvi)
        XCTAssertEqual(result.index, .ndvi)
        XCTAssertEqual(result.values.count, 1)
        // NDVI = (NIR − Red)/(NIR + Red) = (0.6−0.2)/(0.6+0.2) = 0.5
        XCTAssertEqual(Double(result.values[0][0]), 0.5, accuracy: 1e-5)
    }

    func testSpectralAnalyserThrowsWithTooFewBands() async {
        let analyser = JP3DSpectralAnalyser()
        let volume = JP3DMultiSpectralVolume(
            width: 2, height: 2, depth: 1,
            bands: [JP3DSpectralBand(bandIndex: 0, wavelengthNanometres: 665, description: "Red")],
            samplesPerBand: [[0.5, 0.5, 0.5, 0.5]]
        )
        do {
            _ = try await analyser.computeIndex(volume, index: .ndvi)
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssertTrue(error is J2KError)
        }
    }
}
