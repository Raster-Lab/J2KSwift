// J2KXSTests.swift
// J2KSwift
//
// Tests for Phase 20 JPEG XS Core Codec (ISO/IEC 21122).

import XCTest
@testable import J2KXS
@testable import J2KCore

final class J2KXSTests: XCTestCase {

    // MARK: - J2KXSPixelFormat

    func testPixelFormatPlaneCountYUV420() {
        XCTAssertEqual(J2KXSPixelFormat.yuv420.planeCount, 3)
    }

    func testPixelFormatPlaneCountYUV422() {
        XCTAssertEqual(J2KXSPixelFormat.yuv422.planeCount, 3)
    }

    func testPixelFormatPlaneCountYUV444() {
        XCTAssertEqual(J2KXSPixelFormat.yuv444.planeCount, 3)
    }

    func testPixelFormatPlaneCountRGB() {
        XCTAssertEqual(J2KXSPixelFormat.rgb.planeCount, 3)
    }

    func testPixelFormatPlaneCountRGBA() {
        XCTAssertEqual(J2KXSPixelFormat.rgba.planeCount, 4)
    }

    func testPixelFormatCaseIterable() {
        XCTAssertEqual(J2KXSPixelFormat.allCases.count, 5)
    }

    // MARK: - J2KXSImage

    func testImageCreation() {
        let plane = Data(repeating: 128, count: 4 * 4)
        let image = J2KXSImage(width: 4, height: 4, pixelFormat: .rgb, planes: [plane, plane, plane])
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 4)
        XCTAssertEqual(image.pixelFormat, .rgb)
        XCTAssertEqual(image.planes.count, 3)
    }

    func testImagePixelCount() {
        let plane = Data(repeating: 0, count: 8 * 6)
        let image = J2KXSImage(width: 8, height: 6, pixelFormat: .rgb, planes: [plane, plane, plane])
        XCTAssertEqual(image.pixelCount, 48)
    }

    func testImageDimensionClamping() {
        let image = J2KXSImage(width: 0, height: -1, pixelFormat: .rgb, planes: [])
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }

    func testImageEquality() {
        let plane = Data(repeating: 200, count: 4)
        let a = J2KXSImage(width: 2, height: 2, pixelFormat: .rgb, planes: [plane, plane, plane])
        let b = J2KXSImage(width: 2, height: 2, pixelFormat: .rgb, planes: [plane, plane, plane])
        XCTAssertEqual(a, b)
    }

    // MARK: - J2KXSError

    func testErrorEquality() {
        let e1 = J2KXSError.invalidConfiguration("bad")
        let e2 = J2KXSError.invalidConfiguration("bad")
        XCTAssertEqual(e1, e2)
    }

    func testUnsupportedProfileError() {
        let err = J2KXSError.unsupportedProfile(.light)
        if case .unsupportedProfile(let p) = err {
            XCTAssertEqual(p, .light)
        } else {
            XCTFail("Wrong error case")
        }
    }

    func testPlaneMismatchError() {
        let err = J2KXSError.planeMismatch(expected: 3, got: 4)
        if case .planeMismatch(let e, let g) = err {
            XCTAssertEqual(e, 3)
            XCTAssertEqual(g, 4)
        } else {
            XCTFail("Wrong error case")
        }
    }

    // MARK: - J2KXSEncodeResult

    func testEncodeResultProperties() {
        let data = Data(repeating: 0xAB, count: 100)
        let result = J2KXSEncodeResult(
            encodedData: data,
            profile: .main,
            level: .sublevel1,
            sliceCount: 4,
            encodingTimeMs: 12.5
        )
        XCTAssertEqual(result.encodedBytes, 100)
        XCTAssertEqual(result.profile, .main)
        XCTAssertEqual(result.level, .sublevel1)
        XCTAssertEqual(result.sliceCount, 4)
        XCTAssertEqual(result.encodingTimeMs, 12.5, accuracy: 0.01)
    }

    func testEncodeResultSliceCountClamped() {
        let result = J2KXSEncodeResult(
            encodedData: Data(),
            profile: .light,
            level: .sublevel0,
            sliceCount: 0,
            encodingTimeMs: 0
        )
        XCTAssertEqual(result.sliceCount, 1)
    }

    // MARK: - J2KXSDecodeResult

    func testDecodeResultProperties() {
        let plane = Data(repeating: 100, count: 16)
        let image = J2KXSImage(width: 4, height: 4, pixelFormat: .rgb, planes: [plane, plane, plane])
        let result = J2KXSDecodeResult(
            image: image,
            profile: .high,
            level: .sublevel2,
            decodingTimeMs: 8.0
        )
        XCTAssertEqual(result.profile, .high)
        XCTAssertEqual(result.level, .sublevel2)
        XCTAssertGreaterThanOrEqual(result.decodingTimeMs, 0)
    }

    // MARK: - J2KXSDWTOrientation

    func testDWTOrientationLabels() {
        XCTAssertEqual(J2KXSDWTOrientation.ll.label, "LL")
        XCTAssertEqual(J2KXSDWTOrientation.lh.label, "LH")
        XCTAssertEqual(J2KXSDWTOrientation.hl.label, "HL")
        XCTAssertEqual(J2KXSDWTOrientation.hh.label, "HH")
    }

    func testDWTOrientationIsApproximation() {
        XCTAssertTrue(J2KXSDWTOrientation.ll.isApproximation)
        XCTAssertFalse(J2KXSDWTOrientation.lh.isApproximation)
        XCTAssertFalse(J2KXSDWTOrientation.hl.isApproximation)
        XCTAssertFalse(J2KXSDWTOrientation.hh.isApproximation)
    }

    func testDWTOrientationAllCases() {
        XCTAssertEqual(J2KXSDWTOrientation.allCases.count, 4)
    }

    // MARK: - J2KXSSubband

    func testSubbandCreation() {
        let sb = J2KXSSubband(orientation: .lh, level: 1,
                               coefficients: [1.0, 2.0, 3.0, 4.0],
                               width: 2, height: 2)
        XCTAssertEqual(sb.orientation, .lh)
        XCTAssertEqual(sb.level, 1)
        XCTAssertEqual(sb.count, 4)
        XCTAssertEqual(sb.width, 2)
        XCTAssertEqual(sb.height, 2)
    }

    func testSubbandLevelClamped() {
        let sb = J2KXSSubband(orientation: .ll, level: 0,
                               coefficients: [], width: 1, height: 1)
        XCTAssertEqual(sb.level, 1)
    }

    // MARK: - J2KXSDWTEngine

    func testDWTEngineForwardSmallSlice() async throws {
        let engine = J2KXSDWTEngine()
        let samples = (0..<16).map { Float($0) }
        let result = try await engine.forward(slice: samples, width: 4, height: 4, levels: 1)
        XCTAssertEqual(result.decompositionLevels, 1)
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 4)
        // 1 level produces 3 detail subbands + 1 LL = 4 subbands
        XCTAssertEqual(result.subbands.count, 4)
        XCTAssertNotNil(result.approximation)
        let forwardCount = await engine.forwardTransformCount
        XCTAssertEqual(forwardCount, 1)
    }

    func testDWTEngineTooSmallForLevels() async throws {
        let engine = J2KXSDWTEngine()
        let samples = [Float](repeating: 1.0, count: 4)
        do {
            _ = try await engine.forward(slice: samples, width: 2, height: 2, levels: 3)
            XCTFail("Expected invalidConfiguration error")
        } catch J2KXSError.invalidConfiguration {
            // Expected
        }
    }

    func testDWTEngineSampleCountMismatch() async throws {
        let engine = J2KXSDWTEngine()
        let samples = [Float](repeating: 1.0, count: 3)  // Should be 4
        do {
            _ = try await engine.forward(slice: samples, width: 2, height: 2, levels: 1)
            XCTFail("Expected invalidConfiguration error")
        } catch J2KXSError.invalidConfiguration {
            // Expected
        }
    }

    func testDWTEngineInverseRoundTrip() async throws {
        let engine = J2KXSDWTEngine()
        let original = (0..<16).map { Float($0) }
        let decomp = try await engine.forward(slice: original, width: 4, height: 4, levels: 1)
        let reconstructed = try await engine.inverse(decomp)
        XCTAssertEqual(reconstructed.count, original.count)
        // Check approximate reconstruction (Haar scaffold has some loss at boundaries).
        for (orig, recon) in zip(original, reconstructed) {
            XCTAssertEqual(orig, recon, accuracy: 1.0,
                           "Reconstruction deviation too large: expected ~\(orig), got \(recon)")
        }
    }

    func testDWTEngineResetStatistics() async throws {
        let engine = J2KXSDWTEngine()
        let samples = (0..<16).map { Float($0) }
        _ = try await engine.forward(slice: samples, width: 4, height: 4, levels: 1)
        await engine.resetStatistics()
        let count = await engine.forwardTransformCount
        XCTAssertEqual(count, 0)
    }

    func testDWTEngineDecompositionResultApproximation() async throws {
        let engine = J2KXSDWTEngine()
        let samples = [Float](repeating: 0.5, count: 64)
        let decomp = try await engine.forward(slice: samples, width: 8, height: 8, levels: 2)
        XCTAssertNotNil(decomp.approximation)
        XCTAssertEqual(decomp.approximation?.orientation, .ll)
        XCTAssertEqual(decomp.approximation?.level, 2)
    }

    // MARK: - J2KXSQuantisationParameters

    func testQuantisationParametersDefault() {
        let params = J2KXSQuantisationParameters.default
        XCTAssertEqual(params.stepSize, 1.0)
        XCTAssertEqual(params.deadZoneOffset, 0.0)
    }

    func testQuantisationParametersFine() {
        let params = J2KXSQuantisationParameters.fine
        XCTAssertLessThan(params.stepSize, 1.0)
    }

    func testQuantisationParametersCoarse() {
        let params = J2KXSQuantisationParameters.coarse
        XCTAssertGreaterThan(params.stepSize, 1.0)
    }

    func testQuantisationStepSizeClamped() {
        let params = J2KXSQuantisationParameters(stepSize: -5.0)
        XCTAssertGreaterThan(params.stepSize, 0)
    }

    func testQuantisationDeadZoneClamped() {
        let params = J2KXSQuantisationParameters(stepSize: 1.0, deadZoneOffset: 2.0)
        XCTAssertLessThanOrEqual(params.deadZoneOffset, 1.0)
    }

    // MARK: - J2KXSQuantiser

    func testQuantiserQuantiseProducesIntValues() async {
        let q = J2KXSQuantiser()
        let sb = J2KXSSubband(orientation: .hh, level: 1,
                               coefficients: [0.0, 4.0, -4.0, 8.0],
                               width: 2, height: 2)
        let result = await q.quantise(subband: sb, parameters: .default)
        XCTAssertEqual(result.orientation, .hh)
        XCTAssertEqual(result.values.count, 4)
    }

    func testQuantiserZeroCoefficientsQuantiseToZero() async {
        let q = J2KXSQuantiser()
        let sb = J2KXSSubband(orientation: .ll, level: 1,
                               coefficients: [0.0, 0.0, 0.0],
                               width: 3, height: 1)
        let result = await q.quantise(subband: sb, parameters: .default)
        XCTAssertTrue(result.values.allSatisfy { $0 == 0 })
    }

    func testQuantiserDequantiseReconstructsSign() async {
        let q = J2KXSQuantiser()
        let qCoeffs = J2KXSQuantisedCoefficients(
            orientation: .lh, level: 1,
            values: [3, -3, 0],
            stepIndex: 128,
            stepSize: 1.0,
            width: 3, height: 1
        )
        let sb = await q.dequantise(qCoeffs)
        XCTAssertGreaterThan(sb.coefficients[0], 0)
        XCTAssertLessThan(sb.coefficients[1], 0)
        XCTAssertEqual(sb.coefficients[2], 0)
    }

    func testQuantiserStatisticsReset() async {
        let q = J2KXSQuantiser()
        let sb = J2KXSSubband(orientation: .ll, level: 1,
                               coefficients: [1.0], width: 1, height: 1)
        _ = await q.quantise(subband: sb, parameters: .default)
        await q.resetStatistics()
        let count = await q.processedCoefficientCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - J2KXSEntropyMode

    func testEntropyModePacketHeaderIDs() {
        XCTAssertEqual(J2KXSEntropyMode.significanceRange.packetHeaderID, 0x00)
        XCTAssertEqual(J2KXSEntropyMode.varianceAdaptive.packetHeaderID, 0x01)
    }

    func testEntropyModeAllCases() {
        XCTAssertEqual(J2KXSEntropyMode.allCases.count, 2)
    }

    // MARK: - J2KXSEncodedSlice

    func testEncodedSliceProperties() {
        let data = Data(repeating: 0xFF, count: 50)
        let slice = J2KXSEncodedSlice(data: data, lineOffset: 16, lineCount: 8, componentIndex: 1)
        XCTAssertEqual(slice.byteCount, 50)
        XCTAssertEqual(slice.lineOffset, 16)
        XCTAssertEqual(slice.lineCount, 8)
        XCTAssertEqual(slice.componentIndex, 1)
    }

    func testEncodedSliceLineCountClamped() {
        let slice = J2KXSEncodedSlice(data: Data(), lineOffset: 0, lineCount: 0, componentIndex: 0)
        XCTAssertEqual(slice.lineCount, 1)
    }

    // MARK: - J2KXSPacketiser

    func testPacketiserPackAndUnpack() async throws {
        let p = J2KXSPacketiser()
        let slices = [
            J2KXSEncodedSlice(data: Data(repeating: 0x01, count: 8),
                               lineOffset: 0, lineCount: 16, componentIndex: 0),
            J2KXSEncodedSlice(data: Data(repeating: 0x02, count: 8),
                               lineOffset: 16, lineCount: 16, componentIndex: 0),
        ]
        let codestream = try await p.pack(slices: slices, mode: .significanceRange)
        let recovered = try await p.unpack(codestream)
        XCTAssertEqual(recovered.count, 2)
        XCTAssertEqual(recovered[0].lineOffset, 0)
        XCTAssertEqual(recovered[1].lineOffset, 16)
        XCTAssertEqual(recovered[0].data, slices[0].data)
        XCTAssertEqual(recovered[1].data, slices[1].data)
    }

    func testPacketiserEmptySlicesThrows() async {
        let p = J2KXSPacketiser()
        do {
            _ = try await p.pack(slices: [], mode: .significanceRange)
            XCTFail("Expected encodingFailed error")
        } catch J2KXSError.encodingFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPacketiserInvalidMagicThrows() async {
        let p = J2KXSPacketiser()
        let bad = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        do {
            _ = try await p.unpack(bad)
            XCTFail("Expected decodingFailed error")
        } catch J2KXSError.decodingFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPacketiserStatisticsReset() async throws {
        let p = J2KXSPacketiser()
        let slice = J2KXSEncodedSlice(data: Data(repeating: 0x01, count: 4),
                                       lineOffset: 0, lineCount: 8, componentIndex: 0)
        _ = try await p.pack(slices: [slice], mode: .significanceRange)
        await p.resetStatistics()
        let count = await p.packedSliceCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - J2KXSEncoder

    func testEncoderEncodeSmallRGBImage() async throws {
        let encoder = J2KXSEncoder()
        let planeSize = 8 * 8
        let plane = Data((0..<planeSize).map { UInt8($0 % 256) })
        let image = J2KXSImage(width: 8, height: 8, pixelFormat: .rgb,
                                planes: [plane, plane, plane])
        let result = try await encoder.encode(image, configuration: .preview)
        XCTAssertGreaterThan(result.encodedBytes, 0)
        XCTAssertEqual(result.profile, .main)
        XCTAssertGreaterThan(result.sliceCount, 0)
        let count = await encoder.encodedImageCount
        XCTAssertEqual(count, 1)
    }

    func testEncoderPlaneMismatchThrows() async throws {
        let encoder = J2KXSEncoder()
        let plane = Data(repeating: 100, count: 64)
        // rgb format requires 3 planes, but we give 4
        let image = J2KXSImage(width: 8, height: 8, pixelFormat: .rgb,
                                planes: [plane, plane, plane, plane])
        do {
            _ = try await encoder.encode(image, configuration: .preview)
            XCTFail("Expected planeMismatch error")
        } catch J2KXSError.planeMismatch {
            // Expected
        }
    }

    func testEncoderUnsupportedProfileThrows() async throws {
        let encoder = J2KXSEncoder()
        let plane = Data(repeating: 100, count: 64)
        // Light profile allows only 1 component, but we provide 3 (RGB)
        let image = J2KXSImage(width: 8, height: 8, pixelFormat: .rgb,
                                planes: [plane, plane, plane])
        let config = J2KXSConfiguration(
            profile: .light,
            level: .sublevel0,
            sliceHeight: .height16,
            targetBitsPerPixel: 3.0
        )
        do {
            _ = try await encoder.encode(image, configuration: config)
            XCTFail("Expected unsupportedProfile error")
        } catch J2KXSError.unsupportedProfile {
            // Expected
        }
    }

    // MARK: - J2KXSDecoder

    func testDecoderDecodeSmallImage() async throws {
        let encoder = J2KXSEncoder()
        let decoder = J2KXSDecoder()
        let planeSize = 8 * 8
        let plane = Data((0..<planeSize).map { UInt8($0 % 200) })
        let image = J2KXSImage(width: 8, height: 8, pixelFormat: .rgb,
                                planes: [plane, plane, plane])
        let encResult = try await encoder.encode(image, configuration: .preview)
        let decResult = try await decoder.decode(
            encResult, pixelFormat: .rgb, width: 8, height: 8
        )
        XCTAssertEqual(decResult.image.width, 8)
        XCTAssertEqual(decResult.image.height, 8)
        XCTAssertEqual(decResult.image.pixelFormat, .rgb)
        XCTAssertEqual(decResult.image.planes.count, 3)
        XCTAssertEqual(decResult.profile, .main)
        let count = await decoder.decodedImageCount
        XCTAssertEqual(count, 1)
    }

    func testDecoderEmptyCodestreamThrows() async throws {
        let decoder = J2KXSDecoder()
        let emptyResult = J2KXSEncodeResult(
            encodedData: Data(),
            profile: .main,
            level: .sublevel0,
            sliceCount: 0,
            encodingTimeMs: 0
        )
        do {
            _ = try await decoder.decode(emptyResult, pixelFormat: .rgb, width: 4, height: 4)
            XCTFail("Expected decodingFailed or encodingFailed error")
        } catch is J2KXSError {
            // Expected — either decodingFailed or encodingFailed from the packetiser
        }
    }

    // MARK: - J2KXSCapabilities (updated in Phase 20)

    func testCapabilitiesIsAvailableTrue() {
        XCTAssertTrue(J2KXSCapabilities.current.isAvailable)
    }

    func testCapabilitiesVersion() {
        XCTAssertEqual(J2KXSCapabilities.current.version, "2.3.0")
    }

    func testCapabilitiesSupportedProfiles() {
        XCTAssertTrue(J2KXSCapabilities.current.supportedProfiles.contains(.high))
        XCTAssertTrue(J2KXSCapabilities.current.supportedProfiles.contains(.main))
        XCTAssertTrue(J2KXSCapabilities.current.supportedProfiles.contains(.light))
    }
}
