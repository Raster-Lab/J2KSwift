import XCTest
@testable import J2KCodec
@testable import J2KCore
import Foundation

/// Validates that the encoder produces a valid J2K codestream that the decoder
/// can parse without errors.
final class J2KRoundTripValidationTest: XCTestCase {

    func testDecodeOpenJPEGRef() throws {
        let url = URL(fileURLWithPath: "/tmp/ref_gradient8_lossless.j2k")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("SKIP: no ref file")
            return
        }
        let data = try Data(contentsOf: url)
        let decoded = try DecoderPipeline().decode(data)
        let decData = decoded.components[0].data
        print("OPJ ref decoded: \(Array(decData))")
    }

    func testEBCOTDirectRoundTrip() throws {
        // Test BitPlaneCoder directly — bypass the full pipeline
        let w = 4, h = 4
        let coefficients: [Int32] = [
            -118, -108, -98, -88,
            -78, -68, -58, -48,
            -118, -108, -98, -88,
            -78, -68, -58, -48
        ]
        let bitDepth = 10 // Kb = epsilon(8) + guard(2)

        let options = CodingOptions()
        let encoder = BitPlaneCoder(width: w, height: h, subband: .ll, options: options)
        let (data, passCount, zeroBitPlanes, segLengths, _, _) = try encoder.encode(
            coefficients: coefficients, bitDepth: bitDepth)
        print("[EBCOT_RT] encoded: \(data.count) bytes, passes=\(passCount), zbp=\(zeroBitPlanes)")

        let decoder = BitPlaneDecoder(width: w, height: h, subband: .ll, options: options)
        let decoded = try decoder.decode(
            data: data, passCount: passCount, bitDepth: bitDepth,
            zeroBitPlanes: zeroBitPlanes, passSegmentLengths: segLengths)
        print("[EBCOT_RT] decoded: \(decoded)")
        XCTAssertEqual(decoded, coefficients, "Direct EBCOT round-trip failed")
    }

    func testConstantImageOpenJPEG() throws {
        // Test: all pixels = 128 → level shift = 0 → trivial encoding
        let width = 8, height = 8
        var bytes = Data(repeating: 128, count: width * height)
        let comp = J2KComponent(index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: bytes)
        let image = J2KImage(width: width, height: height, components: [comp])
        let config = J2KEncodingConfiguration(quality: 1.0, lossless: true,
            decompositionLevels: 0, codeBlockSize: (width: 32, height: 32))
        let encoded = try EncoderPipeline(config: config).encode(image)
        try encoded.write(to: URL(fileURLWithPath: "/tmp/test_const128.j2k"))
        print("Const128: \(encoded.count) bytes")
        
        // Also test with value 200
        bytes = Data(repeating: 200, count: width * height)
        let comp2 = J2KComponent(index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: bytes)
        let image2 = J2KImage(width: width, height: height, components: [comp2])
        let encoded2 = try EncoderPipeline(config: config).encode(image2)
        try encoded2.write(to: URL(fileURLWithPath: "/tmp/test_const200.j2k"))
        print("Const200: \(encoded2.count) bytes")
    }

    private func makeTestImage(width: Int, height: Int, components: Int) -> J2KImage {
        var comps: [J2KComponent] = []
        for c in 0..<components {
            var bytes = Data(count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    bytes[y * width + x] = UInt8((x * 4 + c * 80 + y * 3) & 0xFF)
                }
            }
            comps.append(J2KComponent(
                index: c, bitDepth: 8, signed: false,
                width: width, height: height, data: bytes
            ))
        }
        return J2KImage(width: width, height: height, components: comps)
    }

    func testLossyRoundTrip64x64() throws {
        let image = makeTestImage(width: 64, height: 64, components: 3)

        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false,
            decompositionLevels: 3,
            codeBlockSize: (width: 32, height: 32)
        )
        let encoded = try EncoderPipeline(config: config).encode(image)

        XCTAssertEqual(encoded[0], 0xFF)
        XCTAssertEqual(encoded[1], 0x4F)
        XCTAssertEqual(encoded[encoded.count - 2], 0xFF)
        XCTAssertEqual(encoded[encoded.count - 1], 0xD9)

        let decoded = try DecoderPipeline().decode(encoded)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
        XCTAssertEqual(decoded.components.count, 3)
    }

    func testLosslessRoundTrip32x32() throws {
        let width = 8, height = 8
        // Simple gradient to test MQ coding: values 10, 20, ..., 80, 10, 20, ...
        var bytes = Data(count: width * height)
        for i in 0..<(width * height) {
            bytes[i] = UInt8(10 + (i % 8) * 10)
        }
        let comp = J2KComponent(index: 0, bitDepth: 8, signed: false,
            width: width, height: height, data: bytes)
        let image = J2KImage(width: width, height: height, components: [comp])
        let config = J2KEncodingConfiguration(quality: 1.0, lossless: true,
            decompositionLevels: 0, codeBlockSize: (width: 32, height: 32))
        let encoded = try EncoderPipeline(config: config).encode(image)
        print("Encoded size: \(encoded.count) bytes (0-level DWT)")
        // Write to file for OpenJPEG testing
        try encoded.write(to: URL(fileURLWithPath: "/tmp/test_gradient8.j2k"))
        let decoded = try DecoderPipeline().decode(encoded)
        let decData = decoded.components[0].data
        print("Orig first 8: \(Array(bytes.prefix(8)))")
        print("Dec  first 8: \(Array(decData.prefix(8)))")
        print("Dec all: \(Array(decData))")
        XCTAssertEqual(decData.count, width * height)
        var maxErr = 0
        for i in 0..<min(bytes.count, decData.count) {
            maxErr = max(maxErr, abs(Int(bytes[i]) - Int(decData[i])))
        }
        XCTAssertEqual(maxErr, 0, "Lossless 0-level DWT: max error \(maxErr)")
    }

    func testLossyRoundTrip512x512() throws {
        let image = makeTestImage(width: 512, height: 512, components: 3)

        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false,
            decompositionLevels: 5,
            codeBlockSize: (width: 32, height: 32)
        )
        let encoded = try EncoderPipeline(config: config).encode(image)
        XCTAssertEqual(encoded[0], 0xFF)
        XCTAssertEqual(encoded[1], 0x4F)

        let decoded = try DecoderPipeline().decode(encoded)
        XCTAssertEqual(decoded.width, 512)
        XCTAssertEqual(decoded.height, 512)
        XCTAssertEqual(decoded.components.count, 3)
    }
}
