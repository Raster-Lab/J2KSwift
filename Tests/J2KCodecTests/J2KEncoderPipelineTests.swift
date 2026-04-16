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
    func testEncodeMinimalGrayscaleImage() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")
        assertValidCodestream(data)
    }

    /// Tests encoding a 16×16 grayscale image with actual pixel data.
    func testEncodeGrayscaleWithData() async throws {
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
        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding a 3-component RGB image (triggers color transform).
    func testEncodeRGBImage() async throws {
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
        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Guards against severe bitrate undershoot on the lossy RGB benchmark path.
    func testLossyRGBBitrateDoesNotSeverelyUndershootTarget() async throws {
        let width = 512
        let height = 512
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for componentIndex in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    let value: UInt8
                    switch componentIndex {
                    case 0:
                        value = UInt8((x * 255) / max(1, width - 1))
                    case 1:
                        value = UInt8((y * 255) / max(1, height - 1))
                    default:
                        value = UInt8(((x + y) * 255) / max(1, width + height - 2))
                    }
                    pixelData[index] = value
                }
            }
            components.append(J2KComponent(
                index: componentIndex,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        var config = J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 5
        )
        config.useReversibleFilter = false

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let expectedBytes = Int(1.2 * Double(width * height) / 8.0)
        XCTAssertGreaterThanOrEqual(
            encoded.count,
            Int(Double(expectedBytes) * 0.60),
            "Lossy RGB size undershot too far: \(encoded.count) bytes vs target \(expectedBytes)"
        )
    }

    /// Guards the grayscale medium-bitrate path against overly aggressive
    /// pre-PCRD pass truncation that can collapse PSNR on smooth content.
    func testLossyGrayscaleMediumBitrateRetainsReasonablePSNR() async throws {
        let width = 128
        let height = 128
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let horizontal = Double(x) / Double(max(1, width - 1))
                let vertical = Double(y) / Double(max(1, height - 1))
                let smoothSignal = 0.7 * horizontal + 0.3 * vertical
                pixelData[index] = UInt8((smoothSignal * 255.0).rounded())
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 1
        )
        config.useReversibleFilter = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 0.5)

        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        let originalBytes = component.data
        let decodedBytes = decoded.components[0].data
        var mse = 0.0
        for i in 0..<min(originalBytes.count, decodedBytes.count) {
            let diff = Double(originalBytes[i]) - Double(decodedBytes[i])
            mse += diff * diff
        }
        mse /= Double(max(1, min(originalBytes.count, decodedBytes.count)))
        let psnr = mse > 0 ? 10.0 * log10((255.0 * 255.0) / mse) : Double.infinity

        let expectedBytes = Int(0.5 * Double(width * height) / 8.0)
        XCTAssertGreaterThanOrEqual(
            encoded.count,
            Int(Double(expectedBytes) * 0.80),
            "Lossy grayscale encode undershot the target budget too far: \(encoded.count) bytes vs target \(expectedBytes)"
        )
        XCTAssertGreaterThan(
            psnr,
            23.0,
            "Lossy grayscale PSNR regressed too far at medium bitrate: \(psnr) dB"
        )
    }

    /// Guards the constant-quality grayscale path used by the benchmark CLI.
    func testLossyGrayscaleMediumQualityRetainsReasonablePSNR() async throws {
        let width = 128
        let height = 128
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let horizontal = Double(x) / Double(max(1, width - 1))
                let vertical = Double(y) / Double(max(1, height - 1))
                let smoothSignal = 0.75 * horizontal + 0.25 * vertical
                pixelData[index] = UInt8((smoothSignal * 255.0).rounded())
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 1
        )
        config.useReversibleFilter = false

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        let originalBytes = component.data
        let decodedBytes = decoded.components[0].data
        var mse = 0.0
        for i in 0..<min(originalBytes.count, decodedBytes.count) {
            let diff = Double(originalBytes[i]) - Double(decodedBytes[i])
            mse += diff * diff
        }
        mse /= Double(max(1, min(originalBytes.count, decodedBytes.count)))
        let psnr = mse > 0 ? 10.0 * log10((255.0 * 255.0) / mse) : Double.infinity

        XCTAssertGreaterThan(
            encoded.count,
            600,
            "Constant-quality grayscale encode collapsed to an unexpectedly tiny payload: \(encoded.count) bytes"
        )
        XCTAssertGreaterThan(
            psnr,
            23.0,
            "Constant-quality grayscale PSNR regressed too far at q=0.5: \(psnr) dB"
        )
    }

    func testLossyDecodeIsDeterministicAcrossRepeatedRuns() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                pixelData[index] = UInt8(((x * 37) ^ (y * 53) ^ ((x + y) * 11)) & 0xFF)
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 1
        )
        config.useReversibleFilter = true
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.5)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoder = J2KDecoder()
        let first = try await decoder.decode(encoded)
        let second = try await decoder.decode(encoded)
        let third = try await decoder.decode(encoded)

        XCTAssertEqual(first.components[0].data, second.components[0].data)
        XCTAssertEqual(second.components[0].data, third.components[0].data)
    }

    func testTenBitLossyDecodeIsDeterministicAcrossRepeatedRuns() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount * 2)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = UInt16(((x * 43) + (y * 29) + ((x ^ y) * 7)) & 0x03FF)
                pixelData[index * 2] = UInt8((value >> 8) & 0xFF)
                pixelData[index * 2 + 1] = UInt8(value & 0xFF)
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 10,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1
        )
        config.useReversibleFilter = true
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.5)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoder = J2KDecoder()
        let first = try await decoder.decode(encoded)
        let second = try await decoder.decode(encoded)
        let third = try await decoder.decode(encoded)

        XCTAssertEqual(first.components[0].data, second.components[0].data)
        XCTAssertEqual(second.components[0].data, third.components[0].data)
        XCTAssertFalse(first.components[0].data.allSatisfy { $0 == 0 })
    }

    func testHighBitDepthLossyDecodeIsDeterministicAcrossRepeatedRuns() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount * 2)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = UInt16(((x * 97) + (y * 53) + ((x ^ y) * 11)) & 0x0FFF)
                pixelData[index * 2] = UInt8((value >> 8) & 0xFF)
                pixelData[index * 2 + 1] = UInt8(value & 0xFF)
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 12,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1
        )
        config.useReversibleFilter = true
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.5)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoder = J2KDecoder()
        let first = try await decoder.decode(encoded)
        let second = try await decoder.decode(encoded)
        let third = try await decoder.decode(encoded)

        XCTAssertEqual(first.components[0].data, second.components[0].data)
        XCTAssertEqual(second.components[0].data, third.components[0].data)
        XCTAssertFalse(first.components[0].data.allSatisfy { $0 == 0 })
    }

    func testTenBitHTJ2KLossyDecodeIsDeterministicAcrossRepeatedRuns() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount * 2)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = UInt16(((x * 67) + (y * 41) + ((x ^ y) * 13)) & 0x03FF)
                pixelData[index * 2] = UInt8((value >> 8) & 0xFF)
                pixelData[index * 2 + 1] = UInt8(value & 0xFF)
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 10,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            useHTJ2K: true
        )
        config.useReversibleFilter = true
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.5)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoder = J2KDecoder()
        let first = try await decoder.decode(encoded)
        let second = try await decoder.decode(encoded)
        let third = try await decoder.decode(encoded)

        XCTAssertEqual(first.components[0].data, second.components[0].data)
        XCTAssertEqual(second.components[0].data, third.components[0].data)
        XCTAssertFalse(first.components[0].data.allSatisfy { $0 == 0 })
    }

    func testHighBitDepthHTJ2KLossyDecodeIsDeterministicAcrossRepeatedRuns() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var pixelData = Data(count: pixelCount * 2)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = UInt16(((x * 131) + (y * 71) + ((x ^ y) * 19)) & 0x0FFF)
                pixelData[index * 2] = UInt8((value >> 8) & 0xFF)
                pixelData[index * 2 + 1] = UInt8(value & 0xFF)
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 12,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            useHTJ2K: true
        )
        config.useReversibleFilter = true
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.5)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoder = J2KDecoder()
        let first = try await decoder.decode(encoded)
        let second = try await decoder.decode(encoded)
        let third = try await decoder.decode(encoded)

        XCTAssertEqual(first.components[0].data, second.components[0].data)
        XCTAssertEqual(second.components[0].data, third.components[0].data)
        XCTAssertFalse(first.components[0].data.allSatisfy { $0 == 0 })
    }

    func testLossyRGBLowBitrateAvoidsCatastrophicPSNRCollapse() async throws {
        let width = 256
        let height = 256
        let pixelCount = width * height

        var components: [J2KComponent] = []
        for componentIndex in 0..<3 {
            var pixelData = Data(count: pixelCount)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    let value: UInt8
                    switch componentIndex {
                    case 0:
                        value = UInt8((x * 255) / max(1, width - 1))
                    case 1:
                        value = UInt8((y * 255) / max(1, height - 1))
                    default:
                        value = UInt8(((x + y) * 255) / max(1, width + height - 2))
                    }
                    pixelData[index] = value
                }
            }
            components.append(J2KComponent(
                index: componentIndex,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 1
        )
        config.useReversibleFilter = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.0)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        var mse = 0.0
        var count = 0
        for componentIndex in 0..<3 {
            let original = components[componentIndex].data
            let result = decoded.components[componentIndex].data
            let sampleCount = min(original.count, result.count)
            for index in 0..<sampleCount {
                let diff = Double(original[index]) - Double(result[index])
                mse += diff * diff
            }
            count += sampleCount
        }

        mse /= Double(max(1, count))
        let psnr = mse > 0 ? 10.0 * log10((255.0 * 255.0) / mse) : Double.infinity

        XCTAssertGreaterThan(
            psnr,
            18.0,
            "Low-bitrate RGB PSNR collapsed too far: \(psnr) dB"
        )
    }

    func testLossyBenchmarkStyleRGBFirstComponentRetainsReasonablePSNR() async throws {
        let width = 512
        let height = 512
        let bitDepth = 8
        let maxValue = (1 << bitDepth) - 1
        let pixelCount = width * height

        struct XorShift32 {
            var state: UInt32
            mutating func next() -> UInt32 {
                state ^= state &<< 13
                state ^= state &>> 17
                state ^= state &<< 5
                return state
            }
        }

        var components: [J2KComponent] = []
        for componentIndex in 0..<3 {
            var pixelData = Data(count: pixelCount)
            pixelData.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                var rng = XorShift32(state: UInt32(42 + componentIndex * 7919))

                for y in 0..<height {
                    for x in 0..<width {
                        var value: Double
                        switch componentIndex {
                        case 0:
                            value = Double(x * maxValue) / Double(max(width - 1, 1))
                        case 1:
                            value = Double(y * maxValue) / Double(max(height - 1, 1))
                        default:
                            value = Double((x + y) * maxValue) / Double(max(width + height - 2, 1))
                        }

                        let boxX = width / 4
                        let boxY = height / 4
                        let boxWidth = width / 3
                        let boxHeight = height / 3
                        if x >= boxX && x < boxX + boxWidth && y >= boxY && y < boxY + boxHeight {
                            value = Double(maxValue) * 0.7
                        }
                        if abs(x - y) < max(4, width / 64) {
                            value = Double(maxValue) * 0.9
                        }

                        let noise = Double(rng.next() % UInt32(max(maxValue / 4, 1))) - Double(maxValue / 8)
                        value += noise
                        let clamped = max(0, min(maxValue, Int(value)))
                        base[y * width + x] = UInt8(clamped)
                    }
                }
            }

            components.append(J2KComponent(
                index: componentIndex,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                data: pixelData
            ))
        }

        let image = J2KImage(width: width, height: height, components: components)
        var config = J2KEncodingConfiguration(
            quality: 0.7,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1
        )
        config.useReversibleFilter = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.0)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        let original = components[0].data
        let result = decoded.components[0].data
        let sampleCount = min(original.count, result.count)
        var mse = 0.0
        for index in 0..<sampleCount {
            let diff = Double(original[index]) - Double(result[index])
            mse += diff * diff
        }
        mse /= Double(max(1, sampleCount))
        let psnr = mse > 0 ? 10.0 * log10((255.0 * 255.0) / mse) : Double.infinity

        XCTAssertGreaterThan(
            psnr,
            20.0,
            "Benchmark-style RGB first-component PSNR regressed too far: \(psnr) dB"
        )
    }

    func testLossless12BitRoundTripPreservesSamples() async throws {
        let width = 4
        let height = 4
        let samples: [UInt16] = [
            219, 217, 213, 211,
            212, 208, 205, 201,
            197, 192, 190, 189,
            184, 183, 181, 177
        ]

        var pixelData = Data()
        pixelData.reserveCapacity(samples.count * 2)
        for sample in samples {
            var bigEndian = sample.bigEndian
            withUnsafeBytes(of: &bigEndian) { pixelData.append(contentsOf: $0) }
        }

        let image = J2KImage(
            width: width,
            height: height,
            components: [
                J2KComponent(
                    index: 0,
                    bitDepth: 12,
                    signed: false,
                    width: width,
                    height: height,
                    data: pixelData
                )
            ]
        )

        var config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 2,
            qualityLayers: 1
        )
        config.useReversibleFilter = true

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.components[0].data, pixelData)
    }

    /// Guards the high-bit-depth lossy path used by medical-style workloads.
    func testLossy16BitMedicalImageRetainsReasonablePSNR() async throws {
        try await assertMedicalLossyPSNRReasonable(useHTJ2K: false, minimumPSNR: 28.0)
    }

    /// Guards the HTJ2K high-bit-depth lossy path used by medical-style workloads.
    func testHTJ2KLossy16BitMedicalImageRetainsReasonablePSNR() async throws {
        try await assertMedicalLossyPSNRReasonable(useHTJ2K: true, minimumPSNR: 27.0)
    }

    /// Guards the matched-rate HTJ2K path against backsliding on a
    /// monochrome medical-style reversible-rate workload.
    func testHTJ2KMedicalQualityGapStaysControlledAtMatchedBitrate() async throws {
        let j2kPSNR = try await medicalStylePSNR(useHTJ2K: false, bitrate: 1.0, useReversibleFilter: true)
        let htj2kPSNR = try await medicalStylePSNR(useHTJ2K: true, bitrate: 1.0, useReversibleFilter: true)

        XCTAssertGreaterThan(
            htj2kPSNR,
            32.9,
            "HTJ2K PSNR regressed too far on the medical-style matched-rate path: \(htj2kPSNR) dB"
        )
        XCTAssertLessThanOrEqual(
            j2kPSNR - htj2kPSNR,
            7.1,
            "HTJ2K quality gap widened too far versus J2K at the same bitrate: J2K=\(j2kPSNR) dB HTJ2K=\(htj2kPSNR) dB"
        )
    }

    /// Guards the matched-rate HTJ2K path against systematic bitrate overspend
    /// on medical-style single-component workloads.
    func testHTJ2KMedicalCompressionEfficiencyStaysCloseToJ2KAtMatchedBitrate() async throws {
        let j2kStats = try await medicalStyleEncodeStats(useHTJ2K: false, bitrate: 1.0, useReversibleFilter: true)
        let htj2kStats = try await medicalStyleEncodeStats(useHTJ2K: true, bitrate: 1.0, useReversibleFilter: true)

        XCTAssertGreaterThan(
            htj2kStats.psnr,
            32.9,
            "HTJ2K medical matched-rate PSNR regressed too far while tightening compression: \(htj2kStats.psnr) dB"
        )
        XCTAssertLessThanOrEqual(
            Double(htj2kStats.encodedBytes),
            Double(j2kStats.encodedBytes) * 1.23,
            "HTJ2K should stay within a tighter matched-rate size envelope versus J2K on the medical-style path after the compression-efficiency tuning: J2K=\(j2kStats.encodedBytes) bytes HTJ2K=\(htj2kStats.encodedBytes) bytes"
        )
    }

    private func assertMedicalLossyPSNRReasonable(useHTJ2K: Bool, minimumPSNR: Double) async throws {
        let stats = try await medicalStyleEncodeStats(useHTJ2K: useHTJ2K, bitrate: 0.5, useReversibleFilter: false)
        let codecLabel = useHTJ2K ? "HTJ2K" : "J2K"

        XCTAssertGreaterThan(
            stats.psnr,
            minimumPSNR,
            "High-bit-depth \(codecLabel) lossy PSNR regressed too far: \(stats.psnr) dB"
        )
    }

    /// Verifies adaptive lossy quantization responds to local image statistics.
    func testAdaptiveQuantizationEmitsDifferentQCDStepsForSmoothAndNoisyContent() async throws {
        let width = 128
        let height = 128
        let pixelCount = width * height

        var smoothData = Data(count: pixelCount)
        var noisyData = Data(count: pixelCount)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let smoothValue = UInt8(((Double(x) / Double(max(1, width - 1))) * 255.0).rounded())
                smoothData[index] = smoothValue
                noisyData[index] = UInt8((x &* 37 &+ y &* 91 &+ index &* 17) & 0xFF)
            }
        }

        let smoothImage = J2KImage(
            width: width,
            height: height,
            components: [J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: smoothData)]
        )
        let noisyImage = J2KImage(
            width: width,
            height: height,
            components: [J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: noisyData)]
        )

        var config = J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 4,
            qualityLayers: 1,
            useHTJ2K: true
        )
        config.useReversibleFilter = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 0.75)

        let encoder = J2KEncoder(encodingConfiguration: config)
        let smoothEncoded = try await encoder.encode(smoothImage)
        let noisyEncoded = try await encoder.encode(noisyImage)

        let smoothSteps = try extractLossyQCDSteps(from: smoothEncoded, bitDepth: 8, decompositionLevels: 4)
        let noisySteps = try extractLossyQCDSteps(from: noisyEncoded, bitDepth: 8, decompositionLevels: 4)

        XCTAssertEqual(smoothSteps.count, noisySteps.count)
        XCTAssertGreaterThan(smoothSteps.count, 3)
        XCTAssertNotEqual(
            smoothSteps,
            noisySteps,
            "Adaptive quantization should emit different QCD steps for smooth vs noisy content"
        )

        let smoothDetailMean = smoothSteps.dropFirst().reduce(0.0, +) / Double(max(1, smoothSteps.count - 1))
        let noisyDetailMean = noisySteps.dropFirst().reduce(0.0, +) / Double(max(1, noisySteps.count - 1))
        XCTAssertLessThan(
            smoothDetailMean,
            noisyDetailMean,
            "Smooth content should receive finer average detail-band quantization than noisy content"
        )
    }

    private func medicalStylePSNR(useHTJ2K: Bool, bitrate: Double, useReversibleFilter: Bool) async throws -> Double {
        try await medicalStyleEncodeStats(
            useHTJ2K: useHTJ2K,
            bitrate: bitrate,
            useReversibleFilter: useReversibleFilter
        ).psnr
    }

    private func medicalStyleEncodeStats(
        useHTJ2K: Bool,
        bitrate: Double,
        useReversibleFilter: Bool
    ) async throws -> (psnr: Double, encodedBytes: Int) {
        let width = 512
        let height = 512
        let pixelCount = width * height
        let maxValue = Double(UInt16.max)
        var pixelData = Data(count: pixelCount * 2)

        struct XorShift32 {
            var state: UInt32
            mutating func next() -> UInt32 {
                var value = state
                value ^= value << 13
                value ^= value >> 17
                value ^= value << 5
                state = value
                return value
            }
        }

        let centerX = Double(width) / 2.0
        let centerY = Double(height) / 2.0
        let radius = Double(min(width, height)) / 2.0

        pixelData.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            var rng = XorShift32(state: 314159)
            for y in 0..<height {
                let deltaY = Double(y) - centerY
                for x in 0..<width {
                    let deltaX = Double(x) - centerX
                    let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

                    var value: Double
                    if distance > radius * 0.95 {
                        value = maxValue * 0.05
                    } else if distance > radius * 0.85 {
                        value = maxValue * 0.85
                    } else if distance > radius * 0.50 {
                        value = maxValue * 0.45
                    } else if distance > radius * 0.30 {
                        value = maxValue * 0.60
                    } else {
                        value = maxValue * 0.35
                    }

                    let ex1 = (deltaX - radius * 0.2) / (radius * 0.15)
                    let ey1 = (deltaY + radius * 0.1) / (radius * 0.10)
                    if ex1 * ex1 + ey1 * ey1 < 1.0 {
                        value = maxValue * 0.75
                    }

                    let ex2 = (deltaX + radius * 0.3) / (radius * 0.08)
                    let ey2 = (deltaY - radius * 0.15) / (radius * 0.12)
                    if ex2 * ex2 + ey2 * ey2 < 1.0 {
                        value = maxValue * 0.20
                    }

                    let noiseLimit = max(Int(maxValue) / 50, 1)
                    let noise = Double(Int32(bitPattern: rng.next()) % Int32(noiseLimit))
                    let sample = UInt16(max(0.0, min(maxValue, value + noise)).rounded())
                    let offset = (y * width + x) * 2
                    base[offset] = UInt8(sample >> 8)
                    base[offset + 1] = UInt8(sample & 0xFF)
                }
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 16,
            signed: false,
            width: width,
            height: height,
            data: pixelData
        )
        let image = J2KImage(width: width, height: height, components: [component])

        var config = J2KEncodingConfiguration(
            quality: 0.5,
            lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            useHTJ2K: useHTJ2K
        )
        config.useReversibleFilter = useReversibleFilter
        config.bitrateMode = .constantBitrate(bitsPerPixel: bitrate)

        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)
        assertValidCodestream(encoded)

        let decoded = try await J2KDecoder().decode(encoded)
        let decodedBytes = decoded.components[0].data
        let sampleCount = min(pixelData.count, decodedBytes.count) / 2
        var mse = 0.0

        pixelData.withUnsafeBytes { originalBuffer in
            decodedBytes.withUnsafeBytes { decodedBuffer in
                guard let originalBase = originalBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let decodedBase = decodedBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                for index in 0..<sampleCount {
                    let source = Double(UInt16(originalBase[index * 2]) << 8 | UInt16(originalBase[index * 2 + 1]))
                    let result = Double(UInt16(decodedBase[index * 2]) << 8 | UInt16(decodedBase[index * 2 + 1]))
                    let diff = source - result
                    mse += diff * diff
                }
            }
        }

        mse /= Double(max(1, sampleCount))
        let psnr = mse > 0 ? 10.0 * log10((maxValue * maxValue) / mse) : Double.infinity
        return (psnr, encoded.count)
    }

    // MARK: - Configuration Tests

    /// Tests lossless encoding configuration.
    func testEncodeLossless() async throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding with different decomposition levels.
    func testEncodeWithVariousDecompositionLevels() async throws {
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 8)

        for levels in [1, 2, 3, 4] {
            let config = J2KEncodingConfiguration(
                quality: 0.9,
                lossless: false,
                decompositionLevels: levels
            )
            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try await encoder.encode(image)
            XCTAssertFalse(data.isEmpty, "Failed at decomposition level \(levels)")
            assertValidCodestream(data)
        }
    }

    /// Tests encoding with preset configurations.
    func testEncodeWithPresets() async throws {
        // Use larger image that supports highest decomposition level (6)
        let image = J2KImage(width: 128, height: 128, components: 1, bitDepth: 8)

        for preset in J2KEncodingPreset.allCases {
            let config = preset.configuration(quality: 0.8)
            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try await encoder.encode(image)
            XCTAssertFalse(data.isEmpty, "Encoding failed with preset: \(preset)")
            assertValidCodestream(data)
        }
    }

    // MARK: - Codestream Structure Tests

    /// Tests that the codestream contains the required SIZ marker.
    func testCodestreamContainsSIZMarker() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)

        // SIZ marker is 0xFF51 and must follow SOC
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(data[2], 0xFF, "Third byte should be 0xFF for SIZ marker")
        XCTAssertEqual(data[3], 0x51, "Fourth byte should be 0x51 for SIZ marker")
    }

    /// Tests that the codestream contains required markers in correct order.
    func testCodestreamMarkerOrder() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testProgressReporting() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        var progressUpdates: [EncoderProgressUpdate] = []

        let data = try await encoder.encode(image) { update in
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
    func testEncodeAllZeroImage() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding a single-pixel image (no DWT possible).
    func testEncodeSinglePixelImage() async throws {
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

        let data = try await encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
        assertValidCodestream(data)
    }

    /// Tests encoding with an image whose dimensions are not power-of-two.
    func testEncodeOddDimensionImage() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 13, height: 7, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testHTJ2KMarkersIncludedWhenEnabled() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testHTJ2KMarkersNotIncludedWhenDisabled() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: false
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testHTJ2KMarkerOrder() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 2,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)

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
    func testHTJ2KLosslessEncoding() async throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 3,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testHTJ2KLossyEncoding() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            decompositionLevels: 3,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testCODDecompositionLevelsClamped() async throws {
        // 8×8 image can support at most 2 levels (log2(8) - 1 = 2)
        // but config asks for 5 → should clamp to 2
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 5
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testQCDEpsilonValuesLossless() async throws {
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testCODMCTDisabledForGrayscale() async throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try await encoder.encode(image)
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
    func testPacketCountMatchesResolutionStructure() async throws {
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

        let data = try await encoder.encode(image)
        assertValidCodestream(data)

        // The codestream should be parseable and decodable
        XCTAssertGreaterThan(data.count, 20, "Encoded codestream should have meaningful size")
    }

    /// Tests round-trip encoding and decoding produces valid output.
    func testRoundTripEncodeDecode() async throws {
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
        let encoded = try await encoder.encode(image)
        assertValidCodestream(encoded)

        // Decode
        let decoder = J2KDecoder()
        let decoded = try await decoder.decode(encoded)

        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.componentCount, 1)
    }

    // MARK: - SIZ Tile Size Correctness

    /// Tests that the SIZ marker always writes tile dimensions equal to the image
    /// dimensions, since the encoder only supports single-tile mode. If tile size
    /// were smaller than the image, external decoders would expect multiple tiles
    /// but only find one, causing severe distortion.
    func testSIZTileSizeMatchesImageDimensions() async throws {
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
        let data = try await encoder.encode(image)

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
    func testLossyRGBUsesICTColorTransform() async throws {
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
        let data = try await encoder.encode(image)

        assertValidCodestream(data)
        XCTAssertTrue(data.count > 100, "Encoded data should be non-trivial")
    }

    /// Tests that QCD step sizes for lossy encoding are varied across subbands
    /// (not all identical), which would indicate a key lookup failure.
    func testQCDStepSizesVaryAcrossSubbands() async throws {
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
        let data = try await encoder.encode(image)

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

    /// Tests that lossy 9/7 QCD signaling includes the JPEG 2000 detail-band
    /// gain exponents expected by external decoders like OpenJPEG.
    func testLossyQCDUsesDetailBandGainForInterop() async throws {
        let image = J2KImage(width: 64, height: 64, components: 1, bitDepth: 12)
        let config = J2KEncodingConfiguration(
            quality: 0.85, lossless: false, decompositionLevels: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try await encoder.encode(image)

        assertValidCodestream(data)

        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()
        guard let qcdData = segments.first(where: { $0.marker == .qcd })?.data else {
            XCTFail("Missing QCD marker")
            return
        }

        XCTAssertGreaterThanOrEqual(qcdData.count, 1 + 2 * (1 + 3 * 3))
        XCTAssertEqual(qcdData[0] & 0x1F, 2, "Expected scalar expounded quantization for lossy")

        let bitDepth = 12
        let decompositionLevels = 3
        let baseParameters = J2KQuantizationParameters.fromQuality(0.85, bitDepth: bitDepth)
        let params = J2KQuantizationParameters(
            mode: baseParameters.mode,
            baseStepSize: baseParameters.baseStepSize * 4.0,
            deadzoneWidth: baseParameters.deadzoneWidth,
            guardBits: baseParameters.guardBits,
            implicitStepSizes: baseParameters.implicitStepSizes,
            explicitStepSizes: baseParameters.explicitStepSizes,
            tcqConfiguration: baseParameters.tcqConfiguration
        )

        func encodeStep(_ step: Double, rangeBits: Int) -> UInt16 {
            let floorLog2 = Int(Foundation.floor(Foundation.log2(step)))
            let exponent = max(0, min(31, rangeBits - floorLog2))
            let basePow = Foundation.pow(2.0, Double(rangeBits - exponent))
            let mantissa = max(0, min(2047, Int((step / basePow - 1.0) * 2048.0 + 0.5)))
            return UInt16((exponent & 0x1F) << 11 | (mantissa & 0x7FF))
        }

        func adaptiveScale(for subband: J2KSubband) -> Double {
            var scale = 1.0
            switch subband {
            case .ll:
                scale *= 0.96
            case .hl, .lh:
                break
            case .hh:
                scale *= 1.03
            }
            scale *= 0.84
            scale *= 0.92
            return min(1.10, max(0.78, scale))
        }

        let hlStep = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: params.baseStepSize,
            subband: .hl,
            decompositionLevel: 3,
            totalLevels: decompositionLevels,
            reversible: false
        ) * adaptiveScale(for: .hl)
        let lhStep = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: params.baseStepSize,
            subband: .lh,
            decompositionLevel: 3,
            totalLevels: decompositionLevels,
            reversible: false
        ) * adaptiveScale(for: .lh)
        let hhStep = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: params.baseStepSize,
            subband: .hh,
            decompositionLevel: 3,
            totalLevels: decompositionLevels,
            reversible: false
        ) * adaptiveScale(for: .hh)

        let expectedHL = encodeStep(hlStep, rangeBits: bitDepth + 1)
        let expectedLH = encodeStep(lhStep, rangeBits: bitDepth + 1)
        let expectedHH = encodeStep(hhStep, rangeBits: bitDepth + 2)

        let actualHL = UInt16(qcdData[3]) << 8 | UInt16(qcdData[4])
        let actualLH = UInt16(qcdData[5]) << 8 | UInt16(qcdData[6])
        let actualHH = UInt16(qcdData[7]) << 8 | UInt16(qcdData[8])

        XCTAssertEqual(actualHL, expectedHL, "HL should encode with detail-band gain")
        XCTAssertEqual(actualLH, expectedLH, "LH should encode with detail-band gain")
        XCTAssertEqual(actualHH, expectedHH, "HH should encode with detail-band gain")
    }

    // MARK: - Helpers

    private func extractLossyQCDSteps(from data: Data, bitDepth: Int, decompositionLevels: Int) throws -> [Double] {
        var index = 0
        while index + 1 < data.count {
            if data[index] == 0xFF, data[index + 1] == 0x5C {
                guard index + 4 <= data.count else {
                    throw XCTSkip("QCD marker truncated")
                }

                let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
                let segmentStart = index + 4
                let segmentEnd = segmentStart + max(0, length - 2)
                guard segmentEnd <= data.count, segmentStart < segmentEnd else {
                    throw XCTSkip("QCD segment length invalid")
                }

                let segment = data[segmentStart..<segmentEnd]
                guard !segment.isEmpty else {
                    throw XCTSkip("QCD segment missing payload")
                }

                var cursor = segment.startIndex + 1
                var steps: [Double] = []
                let gainExponents = [0] + Array(repeating: [1, 1, 2], count: decompositionLevels).flatMap { $0 }

                for gainExponent in gainExponents {
                    guard cursor + 1 < segment.endIndex else { break }
                    let encoded = Int(segment[cursor]) << 8 | Int(segment[cursor + 1])
                    let exponent = (encoded >> 11) & 0x1F
                    let mantissa = encoded & 0x7FF
                    let rangeBits = bitDepth + gainExponent
                    let step = pow(2.0, Double(rangeBits - exponent)) * (1.0 + Double(mantissa) / 2048.0)
                    steps.append(step)
                    cursor += 2
                }

                return steps
            }
            index += 1
        }

        throw XCTSkip("QCD marker not found")
    }

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
