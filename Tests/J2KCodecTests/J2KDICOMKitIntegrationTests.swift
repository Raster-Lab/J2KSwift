//
// J2KDICOMKitIntegrationTests.swift
// J2KSwift
//
// Reproduces and validates fixes for DICOMKit Phase 1 integration bugs.
// See https://github.com/Raster-Lab/J2KSwift bug report (2026-04-20).
//

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KDICOMKitIntegrationTests: XCTestCase {

    // MARK: - Helpers (mirror DICOMKit adapter exactly)

    private func makeEncoder(quality: Double = 1.0, lossless: Bool = true) -> J2KEncoder {
        J2KEncoder(encodingConfiguration: J2KEncodingConfiguration(
            quality: quality,
            lossless: lossless,
            decompositionLevels: 0,
            qualityLayers: 1,
            progressionOrder: .lrcp
        ))
    }

    private func grayscaleImage(width: Int, height: Int, bitDepth: Int, bytes: Data) -> J2KImage {
        let component = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: width,
            height: height,
            data: bytes
        )
        return J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)
    }

    private func rgbImage(width: Int, height: Int, r: Data, g: Data, b: Data) -> J2KImage {
        let comps = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: r),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: g),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: b)
        ]
        return J2KImage(width: width, height: height, components: comps, colorSpace: .sRGB)
    }

    // MARK: - Bug 1: Lossless 8-bit grayscale round-trip

    func testLossless8BitGrayscaleRoundTripPreservesPayload() async throws {
        let width = 32, height = 32
        var pixels = Data(count: width * height)
        for i in 0..<pixels.count { pixels[i] = UInt8(i & 0xFF) }

        let image = grayscaleImage(width: width, height: height, bitDepth: 8, bytes: pixels)
        let encoded = try await makeEncoder().encode(image)
        let decoded = try await J2KDecoder().decode(encoded)

        XCTAssertEqual(decoded.components.count, 1, "Should have 1 component")
        XCTAssertEqual(decoded.components[0].data.count, pixels.count, "Payload size mismatch")
        XCTAssertEqual(decoded.components[0].data, pixels, "Lossless round-trip must preserve every byte")
    }

    // MARK: - Bug 2: Lossless 12-bit-in-16-bit grayscale round-trip

    func testLossless12BitIn16BitGrayscaleRoundTripPreservesPayload() async throws {
        let width = 32, height = 32
        let bitDepth = 12
        let maxValue: UInt16 = (1 << bitDepth) - 1   // 4095
        var pixels = Data(count: width * height * 2)
        for i in 0..<(width * height) {
            let value = UInt16(i % Int(maxValue + 1))
            // DICOM stream is little-endian
            pixels[i * 2] = UInt8(value & 0xFF)
            pixels[i * 2 + 1] = UInt8(value >> 8)
        }

        let image = grayscaleImage(width: width, height: height, bitDepth: bitDepth, bytes: pixels)
        let encoded = try await makeEncoder().encode(image)
        let decoded = try await J2KDecoder().decode(encoded)

        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(decoded.components[0].data.count, pixels.count)
        XCTAssertEqual(decoded.components[0].bitDepth, bitDepth, "Bit depth must round-trip")

        // The decoder emits 16-bit samples in big-endian byte order (PGM / DICOM
        // Explicit VR BE convention). DICOMKit integration byte-swaps to the
        // LE transfer syntax at its boundary, which is what we emulate here.
        let decodedBytes = decoded.components[0].data
        var expected = Data(count: pixels.count)
        for i in 0..<(width * height) {
            expected[i * 2]     = pixels[i * 2 + 1]
            expected[i * 2 + 1] = pixels[i * 2]
        }
        XCTAssertEqual(decodedBytes, expected, "Lossless 12-in-16 must preserve payload (BE output)")
    }

    // MARK: - Bug 3: Lossless RGB round-trip preserves component count

    func testLosslessRGBRoundTripPreservesComponents() async throws {
        let width = 16, height = 16
        var r = Data(count: width * height)
        var g = Data(count: width * height)
        var b = Data(count: width * height)
        for i in 0..<(width * height) {
            r[i] = UInt8(i & 0xFF)
            g[i] = UInt8((i * 2) & 0xFF)
            b[i] = UInt8((i * 3) & 0xFF)
        }

        let image = rgbImage(width: width, height: height, r: r, g: g, b: b)
        let encoded = try await makeEncoder().encode(image)
        let decoded = try await J2KDecoder().decode(encoded)

        XCTAssertEqual(decoded.components.count, 3, "RGB round-trip must preserve component count")
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
    }

    // MARK: - Bug 4: 16-bit lossless / lossy must not crash

    func testLossless16BitGrayscaleDoesNotCrash() async throws {
        let width = 32, height = 32
        var pixels = Data(count: width * height * 2)
        for i in 0..<(width * height) {
            let value = UInt16((i * 31) % 0x10000)
            pixels[i * 2] = UInt8(value & 0xFF)
            pixels[i * 2 + 1] = UInt8(value >> 8)
        }
        let image = grayscaleImage(width: width, height: height, bitDepth: 16, bytes: pixels)
        let encoded = try await makeEncoder().encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(decoded.components[0].bitDepth, 16)

        // Decoder emits BE; LE input is byte-swapped at integration.
        var expected = Data(count: pixels.count)
        for i in 0..<(width * height) {
            expected[i * 2]     = pixels[i * 2 + 1]
            expected[i * 2 + 1] = pixels[i * 2]
        }
        XCTAssertEqual(decoded.components[0].data, expected, "Lossless 16-bit round-trip must preserve payload (BE output)")
    }

    func testLossyGrayscaleDoesNotCrash() async throws {
        let width = 32, height = 32
        var pixels = Data(count: width * height)
        for i in 0..<pixels.count { pixels[i] = UInt8(i & 0xFF) }
        let image = grayscaleImage(width: width, height: height, bitDepth: 8, bytes: pixels)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 0,
            qualityLayers: 1,
            progressionOrder: .lrcp
        ))
        let encoded = try await encoder.encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.components.count, 1)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
    }

    // MARK: - Helpers

    private func decodeSamples(_ data: Data, bigEndian: Bool) -> [UInt16] {
        var out = [UInt16](); out.reserveCapacity(data.count / 2)
        for i in stride(from: 0, to: data.count - 1, by: 2) {
            let v: UInt16
            if bigEndian {
                v = (UInt16(data[i]) << 8) | UInt16(data[i + 1])
            } else {
                v = (UInt16(data[i + 1]) << 8) | UInt16(data[i])
            }
            out.append(v)
        }
        return out
    }
}
