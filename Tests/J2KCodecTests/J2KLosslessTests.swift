//
// J2KLosslessTests.swift
// J2KSwift
//
/// Comprehensive lossless roundtrip validation suite.
///
/// Each test encodes an image with lossless settings, decodes it,
/// and verifies bit-exact equality. Tests are fully deterministic.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class J2KLosslessTests: XCTestCase {

    // MARK: - Configuration

    /// Standard lossless encoding configuration.
    private func losslessConfig(
        decompositionLevels: Int = 5,
        codeBlockSize: (width: Int, height: Int) = (32, 32),
        tileSize: (width: Int, height: Int) = (0, 0)
    ) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: decompositionLevels,
            codeBlockSize: codeBlockSize,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            enableVisualWeighting: false,
            tileSize: tileSize,
            bitrateMode: .constantQuality,
            maxThreads: 1
        )
    }

    // MARK: - Image Generators

    /// Build an 8-bit greyscale image with a deterministic gradient.
    private func makeGreyscale8(width: Int, height: Int) -> J2KImage {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                pixels[idx] = UInt8((x + y * 3) & 0xFF)
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixels)
        return J2KImage(width: width, height: height, components: [comp],
                        colorSpace: .grayscale)
    }

    /// Build a constant-value 8-bit greyscale image.
    private func makeGreyscaleConstant8(width: Int, height: Int, value: UInt8) -> J2KImage {
        let pixels = Data(repeating: value, count: width * height)
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixels)
        return J2KImage(width: width, height: height, components: [comp],
                        colorSpace: .grayscale)
    }

    /// Build an 8-bit RGB image with deterministic per-channel patterns.
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
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false,
                         width: width, height: height, data: rData),
            J2KComponent(index: 1, bitDepth: 8, signed: false,
                         width: width, height: height, data: gData),
            J2KComponent(index: 2, bitDepth: 8, signed: false,
                         width: width, height: height, data: bData),
        ]
        return J2KImage(width: width, height: height, components: components,
                        colorSpace: .sRGB)
    }

    /// Build a 16-bit greyscale image with deterministic values.
    ///
    /// Pixel data is stored big-endian (matching J2K encoder/decoder convention).
    private func makeGreyscale16(width: Int, height: Int) -> J2KImage {
        let count = width * height
        var pixels = Data(count: count * 2)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let val = UInt16((x * 257 + y * 131) & 0xFFFF)
                // Big-endian storage
                pixels[idx * 2] = UInt8(val >> 8)
                pixels[idx * 2 + 1] = UInt8(val & 0xFF)
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height, data: pixels)
        return J2KImage(width: width, height: height, components: [comp],
                        colorSpace: .grayscale)
    }

    /// Build an image with extreme values (0 and max for each bit depth).
    private func makeExtremeValues8(width: Int, height: Int) -> J2KImage {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                // Alternate between 0 and 255
                pixels[idx] = (x + y).isMultiple(of: 2) ? 0 : 255
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: pixels)
        return J2KImage(width: width, height: height, components: [comp],
                        colorSpace: .grayscale)
    }

    // MARK: - Roundtrip Helper

    /// Encode then decode an image with the given config and return the decoded result.
    private func roundtrip(
        _ image: J2KImage,
        config: J2KEncodingConfiguration
    ) throws -> J2KImage {
        let encoder = J2KEncoder(encodingConfiguration: config)
        let codestream = try encoder.encode(image)

        let decoder = J2KDecoder()
        return try decoder.decode(codestream)
    }

    /// Encode→decode→validate and generate a diagnostic on failure.
    private func assertLossless(
        _ image: J2KImage,
        config: J2KEncodingConfiguration? = nil,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let cfg = config ?? losslessConfig()
        let decoded = try roundtrip(image, config: cfg)
        let result = try J2KLosslessValidator.validate(original: image, decoded: decoded)

        switch result {
        case .bitExact:
            break  // Pass
        case .mismatch(let first, let total, let maxErr):
            let diag = J2KLosslessValidator.diagnosticString(result, label: label)
            XCTFail(diag, file: file, line: line)
        }
    }

    // MARK: - 8-bit Greyscale Tests

    func testLosslessGreyscale8_16x16() throws {
        let image = makeGreyscale8(width: 16, height: 16)
        try assertLossless(image, label: "Grey8 16×16")
    }

    func testLosslessGreyscale8_64x64() throws {
        let image = makeGreyscale8(width: 64, height: 64)
        try assertLossless(image, label: "Grey8 64×64")
    }

    func testLosslessGreyscale8_256x256() throws {
        let image = makeGreyscale8(width: 256, height: 256)
        try assertLossless(image, label: "Grey8 256×256")
    }

    func testLosslessGreyscale8_ConstantBlack() throws {
        let image = makeGreyscaleConstant8(width: 32, height: 32, value: 0)
        try assertLossless(image, label: "Grey8 constant 0")
    }

    func testLosslessGreyscale8_ConstantWhite() throws {
        let image = makeGreyscaleConstant8(width: 32, height: 32, value: 255)
        try assertLossless(image, label: "Grey8 constant 255")
    }

    func testLosslessGreyscale8_ConstantMid() throws {
        let image = makeGreyscaleConstant8(width: 32, height: 32, value: 128)
        try assertLossless(image, label: "Grey8 constant 128")
    }

    func testLosslessGreyscale8_ExtremeValues() throws {
        let image = makeExtremeValues8(width: 32, height: 32)
        try assertLossless(image, label: "Grey8 extreme values")
    }

    // MARK: - 8-bit RGB Tests

    func testLosslessRGB8_16x16() throws {
        let image = makeRGB8(width: 16, height: 16)
        try assertLossless(image, label: "RGB8 16×16")
    }

    func testLosslessRGB8_64x64() throws {
        let image = makeRGB8(width: 64, height: 64)
        try assertLossless(image, label: "RGB8 64×64")
    }

    func testLosslessRGB8_256x256() throws {
        let image = makeRGB8(width: 256, height: 256)
        try assertLossless(image, label: "RGB8 256×256")
    }

    func testLosslessRGB8_ConstantRed() throws {
        let count = 32 * 32
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false,
                         width: 32, height: 32, data: Data(repeating: 255, count: count)),
            J2KComponent(index: 1, bitDepth: 8, signed: false,
                         width: 32, height: 32, data: Data(repeating: 0, count: count)),
            J2KComponent(index: 2, bitDepth: 8, signed: false,
                         width: 32, height: 32, data: Data(repeating: 0, count: count)),
        ]
        let image = J2KImage(width: 32, height: 32, components: components, colorSpace: .sRGB)
        try assertLossless(image, label: "RGB8 constant red")
    }

    // MARK: - 16-bit Greyscale Tests

    func testLosslessGreyscale16_16x16() throws {
        let image = makeGreyscale16(width: 16, height: 16)
        try assertLossless(image, label: "Grey16 16×16")
    }

    func testLosslessGreyscale16_64x64() throws {
        let image = makeGreyscale16(width: 64, height: 64)
        try assertLossless(image, label: "Grey16 64×64")
    }

    // MARK: - Odd Dimension Tests

    func testLosslessGreyscale8_OddWidth() throws {
        let image = makeGreyscale8(width: 17, height: 16)
        try assertLossless(image, label: "Grey8 17×16 (odd width)")
    }

    func testLosslessGreyscale8_OddHeight() throws {
        let image = makeGreyscale8(width: 16, height: 17)
        try assertLossless(image, label: "Grey8 16×17 (odd height)")
    }

    func testLosslessGreyscale8_OddBoth() throws {
        let image = makeGreyscale8(width: 17, height: 19)
        try assertLossless(image, label: "Grey8 17×19 (odd both)")
    }

    func testLosslessGreyscale8_PrimeDimensions() throws {
        let image = makeGreyscale8(width: 13, height: 11)
        try assertLossless(image, label: "Grey8 13×11 (prime dims)")
    }

    func testLosslessRGB8_OddDimensions() throws {
        let image = makeRGB8(width: 23, height: 31)
        try assertLossless(image, label: "RGB8 23×31 (odd dims)")
    }

    func testLosslessGreyscale8_3x3() throws {
        let image = makeGreyscale8(width: 3, height: 3)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 1),
            label: "Grey8 3×3 (minimum)")
    }

    func testLosslessGreyscale8_1x1() throws {
        let pixels = Data([42])
        let comp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 1, height: 1, data: pixels)
        let image = J2KImage(width: 1, height: 1, components: [comp],
                            colorSpace: .grayscale)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 0),
            label: "Grey8 1×1 (single pixel)")
    }

    // MARK: - Multi-Tile Tests

    func testLosslessGreyscale8_Tiled64x64() throws {
        let image = makeGreyscale8(width: 128, height: 128)
        try assertLossless(
            image,
            config: losslessConfig(tileSize: (width: 64, height: 64)),
            label: "Grey8 128×128 tiled 64×64")
    }

    func testLosslessRGB8_Tiled32x32() throws {
        let image = makeRGB8(width: 64, height: 64)
        try assertLossless(
            image,
            config: losslessConfig(tileSize: (width: 32, height: 32)),
            label: "RGB8 64×64 tiled 32×32")
    }

    func testLosslessGreyscale8_TiledOddDimensions() throws {
        // Image not evenly divisible by tile size
        let image = makeGreyscale8(width: 100, height: 100)
        try assertLossless(
            image,
            config: losslessConfig(tileSize: (width: 64, height: 64)),
            label: "Grey8 100×100 tiled 64×64 (non-aligned)")
    }

    // MARK: - Decomposition Level Variants

    func testLosslessGreyscale8_0Levels() throws {
        let image = makeGreyscale8(width: 32, height: 32)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 0),
            label: "Grey8 32×32 0 decomp levels")
    }

    func testLosslessGreyscale8_1Level() throws {
        let image = makeGreyscale8(width: 32, height: 32)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 1),
            label: "Grey8 32×32 1 decomp level")
    }

    func testLosslessGreyscale8_3Levels() throws {
        let image = makeGreyscale8(width: 64, height: 64)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 3),
            label: "Grey8 64×64 3 decomp levels")
    }

    func testLosslessRGB8_3Levels() throws {
        let image = makeRGB8(width: 64, height: 64)
        try assertLossless(
            image,
            config: losslessConfig(decompositionLevels: 3),
            label: "RGB8 64×64 3 decomp levels")
    }

    // MARK: - Code Block Size Variants

    func testLosslessGreyscale8_CodeBlock64() throws {
        let image = makeGreyscale8(width: 128, height: 128)
        try assertLossless(
            image,
            config: losslessConfig(codeBlockSize: (width: 64, height: 64)),
            label: "Grey8 128×128 codeblock 64×64")
    }

    func testLosslessGreyscale8_CodeBlock16() throws {
        let image = makeGreyscale8(width: 64, height: 64)
        try assertLossless(
            image,
            config: losslessConfig(codeBlockSize: (width: 16, height: 16)),
            label: "Grey8 64×64 codeblock 16×16")
    }

    // MARK: - Determinism

    func testLosslessResultsAreDeterministic() throws {
        let image = makeRGB8(width: 64, height: 64)
        let config = losslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: config)

        let codestream1 = try encoder.encode(image)
        let codestream2 = try encoder.encode(image)

        XCTAssertEqual(codestream1, codestream2,
                       "Encoding the same image twice must produce identical codestreams")
    }

    // MARK: - Diagnostic Output

    func testMismatchDiagnosticProvided() throws {
        // Construct two slightly different images and validate diagnostics
        let origPixels = Data([10, 20, 30, 40])
        let decoPixels = Data([10, 21, 30, 40])

        let origComp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 2, height: 2, data: origPixels)
        let decoComp = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 2, height: 2, data: decoPixels)

        let original = J2KImage(width: 2, height: 2, components: [origComp],
                                colorSpace: .grayscale)
        let decoded = J2KImage(width: 2, height: 2, components: [decoComp],
                               colorSpace: .grayscale)

        let result = try J2KLosslessValidator.validate(original: original, decoded: decoded)
        switch result {
        case .bitExact:
            XCTFail("Should have found a mismatch")
        case .mismatch(let first, let total, let maxErr):
            XCTAssertEqual(first.component, 0)
            XCTAssertEqual(first.x, 1)
            XCTAssertEqual(first.y, 0)
            XCTAssertEqual(first.expected, 20)
            XCTAssertEqual(first.actual, 21)
            XCTAssertEqual(first.difference, -1)
            XCTAssertEqual(total, 1)
            XCTAssertEqual(maxErr, 1)
        }

        let diag = J2KLosslessValidator.diagnosticString(result, label: "test")
        XCTAssertTrue(diag.contains("FAIL"))
        XCTAssertTrue(diag.contains("component 0"))
        XCTAssertTrue(diag.contains("(1, 0)"))
    }
}
