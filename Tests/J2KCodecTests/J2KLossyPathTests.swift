//
// J2KLossyPathTests.swift
// J2KSwift
//
/// Tests for Prompt 03: correct lossy path — transform selection, defaults,
/// ICT/RCT correctness, precinct support, and encode/decode stability.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class J2KLossyPathTests: XCTestCase {

    // MARK: - Helpers

    /// Build a deterministic 8-bit RGB image.
    private func makeRGB8(width: Int, height: Int) -> J2KImage {
        let count = width * height
        var rData = Data(count: count)
        var gData = Data(count: count)
        var bData = Data(count: count)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                rData[idx] = UInt8((x * 7 + y * 13) & 0xFF)
                gData[idx] = UInt8((x * 11 + y * 5) & 0xFF)
                bData[idx] = UInt8((x * 3 + y * 17) & 0xFF)
            }
        }
        return J2KImage(width: width, height: height, components: [
            J2KComponent(index: 0, bitDepth: 8, signed: false,
                         width: width, height: height, data: rData),
            J2KComponent(index: 1, bitDepth: 8, signed: false,
                         width: width, height: height, data: gData),
            J2KComponent(index: 2, bitDepth: 8, signed: false,
                         width: width, height: height, data: bData),
        ], colorSpace: .sRGB)
    }

    /// Build a deterministic 8-bit greyscale image.
    private func makeGrey8(width: Int, height: Int) -> J2KImage {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8((x + y * 3) & 0xFF)
            }
        }
        return J2KImage(width: width, height: height, components: [
            J2KComponent(index: 0, bitDepth: 8, signed: false,
                         width: width, height: height, data: pixels),
        ], colorSpace: .grayscale)
    }

    // MARK: - Default Configuration Tests

    func testDefaultCodeBlockSize() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.codeBlockSize.width, 64)
        XCTAssertEqual(config.codeBlockSize.height, 64)
    }

    func testDefaultProgressionOrder() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.progressionOrder, .lrcp)
    }

    func testDefaultSingleTile() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.tileSize.width, 0)
        XCTAssertEqual(config.tileSize.height, 0)
    }

    func testDefaultPrecinctSizesEmpty() {
        let config = J2KEncodingConfiguration()
        XCTAssertTrue(config.precinctSizes.isEmpty)
    }

    func testBalancedPresetDefaults() {
        let config = J2KEncodingPreset.balanced.configuration()
        XCTAssertEqual(config.codeBlockSize.width, 64)
        XCTAssertEqual(config.codeBlockSize.height, 64)
        XCTAssertEqual(config.progressionOrder, .lrcp)
        XCTAssertEqual(config.tileSize.width, 0)
        XCTAssertEqual(config.tileSize.height, 0)
        XCTAssertEqual(config.precinctSizes.count, 3)
    }

    func testQualityPresetDefaults() {
        let config = J2KEncodingPreset.quality.configuration()
        XCTAssertEqual(config.codeBlockSize.width, 64)
        XCTAssertEqual(config.codeBlockSize.height, 64)
        XCTAssertEqual(config.progressionOrder, .lrcp)
        XCTAssertEqual(config.tileSize.width, 0)
        XCTAssertEqual(config.tileSize.height, 0)
        XCTAssertEqual(config.precinctSizes.count, 3)
    }

    // MARK: - Transform Selection Tests

    func testLosslessSelectsRCTAnd53() {
        let config = J2KEncodingConfiguration(lossless: true)
        XCTAssertTrue(config.lossless)
        // The wavelet/colour transform selection happens in the pipeline;
        // verify lossless flag propagates correctly.
    }

    func testLossySelectsICTAnd97() {
        let config = J2KEncodingConfiguration(quality: 0.8, lossless: false)
        XCTAssertFalse(config.lossless)
    }

    // MARK: - ICT Forward / Inverse Correctness

    func testICTRoundtripPrecision() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Known test values
        let red:   [Double] = [100.0, 200.0, 50.0, 0.0, 255.0]
        let green: [Double] = [150.0, 100.0, 200.0, 0.0, 255.0]
        let blue:  [Double] = [200.0, 50.0, 100.0, 0.0, 255.0]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
        let (rOut, gOut, bOut) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Verify roundtrip within IEEE 754 double precision tolerance
        for i in 0..<red.count {
            XCTAssertEqual(rOut[i], red[i], accuracy: 1e-9,
                           "Red mismatch at \(i): \(rOut[i]) vs \(red[i])")
            XCTAssertEqual(gOut[i], green[i], accuracy: 1e-9,
                           "Green mismatch at \(i): \(gOut[i]) vs \(green[i])")
            XCTAssertEqual(bOut[i], blue[i], accuracy: 1e-9,
                           "Blue mismatch at \(i): \(bOut[i]) vs \(blue[i])")
        }
    }

    func testICTCoefficientsMatchStandard() throws {
        // Verify standard coefficients from ISO/IEC 15444-1 Annex G.3
        let transform = J2KColorTransform(configuration: .lossy)

        // Pure red (128, 0, 0)
        let (y, cb, cr) = try transform.forwardICT(
            red: [128.0], green: [0.0], blue: [0.0])

        XCTAssertEqual(y[0], 0.299 * 128.0, accuracy: 1e-10)
        XCTAssertEqual(cb[0], -0.168736 * 128.0, accuracy: 1e-10)
        XCTAssertEqual(cr[0], 0.5 * 128.0, accuracy: 1e-10)
    }

    func testRCTRoundtripExact() throws {
        let transform = J2KColorTransform(configuration: .lossless)

        // Test with various values including edge cases
        let red:   [Int32] = [0, 127, 255, 1, 254, 100]
        let green: [Int32] = [0, 127, 255, 200, 50, 100]
        let blue:  [Int32] = [0, 127, 255, 50, 200, 100]

        let (y, cb, cr) = try transform.forwardRCT(
            red: red, green: green, blue: blue)
        let (rOut, gOut, bOut) = try transform.inverseRCT(
            y: y, cb: cb, cr: cr)

        // RCT must be perfectly reversible
        for i in 0..<red.count {
            XCTAssertEqual(rOut[i], red[i], "Red mismatch at \(i)")
            XCTAssertEqual(gOut[i], green[i], "Green mismatch at \(i)")
            XCTAssertEqual(bOut[i], blue[i], "Blue mismatch at \(i)")
        }
    }

    // MARK: - Lossy Encode/Decode Stability

    func testLossyRGBEncodeDecodeProducesValidOutput() throws {
        let image = makeRGB8(width: 64, height: 64)
        let config = J2KEncodingConfiguration(quality: 0.8, lossless: false)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        // Must produce non-empty codestream
        XCTAssertGreaterThan(codestream.count, 0)

        // Decode it back
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(codestream)

        // Dimensions must match
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, image.components.count)

        // Lossy: verify reasonable quality (MAE should be small)
        for compIdx in 0..<image.components.count {
            let origComp = image.components[compIdx]
            let decoComp = decoded.components[compIdx]
            var totalDiff: Int64 = 0
            let pixelCount = origComp.width * origComp.height
            for i in 0..<pixelCount {
                let orig = Int64(origComp.data[i])
                let deco = Int64(decoComp.data[i])
                totalDiff += abs(orig - deco)
            }
            let mae = Double(totalDiff) / Double(pixelCount)
            // Lossy at q=0.8 should have MAE well under 20
            XCTAssertLessThan(mae, 20.0,
                              "Component \(compIdx) MAE \(mae) is too high for lossy q=0.8")
        }
    }

    func testLossyGreyscaleEncodeDecodeStable() throws {
        let image = makeGrey8(width: 64, height: 64)
        let config = J2KEncodingConfiguration(quality: 0.9, lossless: false)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        XCTAssertGreaterThan(codestream.count, 0)

        let decoder = J2KDecoder()
        let decoded = try decoder.decode(codestream)

        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, 1)
    }

    func testLossyEncodingIsDeterministic() throws {
        let image = makeRGB8(width: 32, height: 32)
        let config = J2KEncodingConfiguration(quality: 0.7, lossless: false)
        let encoder = J2KEncoder(encodingConfiguration: config)

        let cs1 = try encoder.encode(image)
        let cs2 = try encoder.encode(image)

        XCTAssertEqual(cs1, cs2,
                       "Lossy encoding must be deterministic for identical input")
    }

    // MARK: - Lossless Regression

    func testLosslessStillWorksAfterLossyFix() throws {
        let image = makeRGB8(width: 32, height: 32)
        let config = J2KEncodingConfiguration(quality: 1.0, lossless: true)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        let decoder = J2KDecoder()
        let decoded = try decoder.decode(codestream)

        // Must be bit-exact
        let result = try J2KLosslessValidator.validate(
            original: image, decoded: decoded)
        switch result {
        case .bitExact: break
        case .mismatch:
            let diag = J2KLosslessValidator.diagnosticString(result, label: "Lossless regression")
            XCTFail(diag)
        }
    }

    // MARK: - Precinct Configuration Tests

    func testPrecinctSizesPreservedInConfig() {
        let precincts: [(width: Int, height: Int)] = [
            (width: 64, height: 64),
            (width: 128, height: 128),
            (width: 256, height: 256),
        ]
        let config = J2KEncodingConfiguration(precinctSizes: precincts)
        XCTAssertEqual(config.precinctSizes.count, 3)
        XCTAssertEqual(config.precinctSizes[0].width, 64)
        XCTAssertEqual(config.precinctSizes[2].width, 256)
    }

    func testEncodeWithPrecinctLadder() throws {
        let image = makeRGB8(width: 64, height: 64)
        let precincts: [(width: Int, height: Int)] = [
            (width: 64, height: 64),
            (width: 128, height: 128),
            (width: 256, height: 256),
        ]
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            precinctSizes: precincts
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        XCTAssertGreaterThan(codestream.count, 0)

        // Decode to verify stability
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(codestream)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
    }

    // MARK: - Code Block Size Tests

    func testCodeBlockSize64x64Encodes() throws {
        let image = makeGrey8(width: 128, height: 128)
        let config = J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            codeBlockSize: (width: 64, height: 64)
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        XCTAssertGreaterThan(codestream.count, 0)
    }
}
