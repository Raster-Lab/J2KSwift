//
// J2KLayersPacketsTests.swift
// J2KSwift
//
// Tests for Prompt 06: Layers & Packets — packet formation,
// quality layers, marker validation, and layer configuration benchmarks.
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KLayersPacketsTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a deterministic greyscale test image.
    private func makeGreyscale(width: Int, height: Int) -> J2KImage {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let gradient = (x * 255) / max(width - 1, 1)
                let checker = ((x / 8 + y / 8) % 2 == 0) ? 30 : 0
                pixels[y * width + x] = UInt8(min(255, gradient + checker))
            }
        }
        return J2KImage(width: width, height: height, components: [
            J2KComponent(index: 0, bitDepth: 8, signed: false,
                         width: width, height: height, data: pixels)
        ], colorSpace: .grayscale)
    }

    /// PSNR between two single-component images.
    private func psnr(original: J2KImage, decoded: J2KImage) -> Double {
        let a = original.components[0].data
        let b = decoded.components[0].data
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var mse: Double = 0
        for i in 0..<a.count {
            let d = Double(a[i]) - Double(b[i])
            mse += d * d
        }
        mse /= Double(a.count)
        guard mse > 0 else { return Double.infinity }
        return 10.0 * log10(65025.0 / mse)
    }

    // MARK: - PacketHeaderWriter Tests

    func testEmptyPacketHeaderMinimalSize() throws {
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: true
        )
        let data = try writer.encode(header)

        // Empty packet = 1-bit flag (0) byte-aligned → exactly 1 byte
        XCTAssertEqual(data.count, 1,
            "Empty packet header should be exactly 1 byte")
        XCTAssertEqual(data[0] & 0x80, 0,
            "Empty packet flag (MSB) should be 0")
    }

    func testSingleBlockPacketHeader() throws {
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true],
            codingPasses: [1],
            dataLengths: [64]
        )
        let data = try writer.encode(header)

        XCTAssertGreaterThan(data.count, 0)
        // First bit should be 1 (non-empty)
        XCTAssertEqual(data[0] & 0x80, 0x80,
            "Non-empty packet flag should be 1")
    }

    func testMultiBlockPacketHeader() throws {
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true, false, true, true],
            codingPasses: [3, 2, 5],
            dataLengths: [128, 64, 256]
        )
        let data = try writer.encode(header)

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(data[0] & 0x80, 0x80)
    }

    func testPacketHeaderStateContinuity() throws {
        // First layer includes block 0; second layer adds block 1.
        // The writer must track inclusion state across encode calls.
        var writer = PacketHeaderWriter()

        let h1 = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true, false],
            codingPasses: [1],
            dataLengths: [32]
        )
        let d1 = try writer.encode(h1, blockIndices: [0, 1])
        XCTAssertGreaterThan(d1.count, 0)

        let h2 = PacketHeader(
            layerIndex: 1, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true, true],
            codingPasses: [2, 1],
            dataLengths: [48, 24]
        )
        let d2 = try writer.encode(h2, blockIndices: [0, 1])
        XCTAssertGreaterThan(d2.count, 0)
    }

    func testPacketHeaderWriterReset() throws {
        var writer = PacketHeaderWriter()

        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true],
            codingPasses: [1],
            dataLengths: [16]
        )
        _ = try writer.encode(header, blockIndices: [0])

        writer.reset()

        // After reset, the same block should be treated as first inclusion again
        let d2 = try writer.encode(header, blockIndices: [0])
        XCTAssertGreaterThan(d2.count, 0)
    }

    func testPacketHeaderOversizedPassCountThrows() throws {
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true],
            codingPasses: [200], // > 164, unsupported
            dataLengths: [100]
        )
        XCTAssertThrowsError(try writer.encode(header))
    }

    // MARK: - CodingPasses Prefix Code Coverage

    func testCodingPassesPrefixCodeValues() throws {
        // Verify all prefix code ranges: 1, 2, 3-5, 6-36
        for passes in [1, 2, 3, 4, 5, 6, 10, 36] {
            var writer = PacketHeaderWriter()
            let header = PacketHeader(
                layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
                precinctIndex: 0, isEmpty: false,
                codeBlockInclusions: [true],
                codingPasses: [passes],
                dataLengths: [100]
            )
            let data = try writer.encode(header)
            XCTAssertGreaterThan(data.count, 0,
                "Should encode \(passes) coding passes without error")
        }
    }

    // MARK: - Quality Layer Tests

    func testQualityLayerCreation() throws {
        let layer = QualityLayer(
            index: 0,
            targetRate: 1.5,
            codeBlockContributions: [0: 3, 1: 5, 2: 2]
        )
        XCTAssertEqual(layer.index, 0)
        XCTAssertEqual(layer.targetRate, 1.5)
        XCTAssertEqual(layer.codeBlockContributions.count, 3)
    }

    func testLosslessLayerIncludesAllPasses() throws {
        let blocks = [
            J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32,
                         subband: .ll, data: Data(count: 100),
                         passeCount: 9, zeroBitPlanes: 0),
            J2KCodeBlock(index: 1, x: 32, y: 0, width: 32, height: 32,
                         subband: .hl, data: Data(count: 80),
                         passeCount: 6, zeroBitPlanes: 1)
        ]
        let config = RateControlConfiguration.lossless
        let rc = J2KRateControl(configuration: config)
        let layers = try rc.optimizeLayers(codeBlocks: blocks, totalPixels: 64 * 32)

        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].codeBlockContributions[0], 9)
        XCTAssertEqual(layers[0].codeBlockContributions[1], 6)
    }

    func testMultiLayerCumulativeContributions() throws {
        let blocks = [
            J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32,
                         subband: .ll,
                         data: Data(repeating: 0xAB, count: 200),
                         passeCount: 12, zeroBitPlanes: 0,
                         passSegmentLengths: Array(repeating: 16, count: 12) +
                                             [8]) // 12 passes, ~200 bytes, close enough
        ]
        // Fix: passSegmentLengths must have exactly passeCount entries
        let segLengths12 = [Int](repeating: 16, count: 11) + [24] // sums to 200
        let blocks2 = [
            J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32,
                         subband: .ll,
                         data: Data(repeating: 0xAB, count: 200),
                         passeCount: 12, zeroBitPlanes: 0,
                         passSegmentLengths: segLengths12)
        ]

        let config = RateControlConfiguration.targetBitrate(4.0, layerCount: 3)
        let rc = J2KRateControl(configuration: config)
        let layers = try rc.optimizeLayers(codeBlocks: blocks2,
                                            totalPixels: 32 * 32)

        XCTAssertEqual(layers.count, 3)

        // Layer contributions must be non-decreasing (cumulative)
        for blockIdx in [0] {
            let p0 = layers[0].codeBlockContributions[blockIdx] ?? 0
            let p1 = layers[1].codeBlockContributions[blockIdx] ?? 0
            let p2 = layers[2].codeBlockContributions[blockIdx] ?? 0
            XCTAssertLessThanOrEqual(p0, p1,
                "Layer 0 passes (\(p0)) must be ≤ layer 1 passes (\(p1))")
            XCTAssertLessThanOrEqual(p1, p2,
                "Layer 1 passes (\(p1)) must be ≤ layer 2 passes (\(p2))")
        }
    }

    // MARK: - Layer Formation Simple Strategy Tests

    func testSimpleLayerFormation() throws {
        let formation = LayerFormation(targetRates: [0.5, 1.0])
        let blocks = [
            J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32,
                         subband: .ll, data: Data(count: 128),
                         passeCount: 9, zeroBitPlanes: 0)
        ]
        let layers = try formation.formLayers(codeBlocks: blocks,
                                               totalPixels: 1024)
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[0].index, 0)
        XCTAssertEqual(layers[1].index, 1)
    }

    func testSimpleLosslessLayer() throws {
        let formation = LayerFormation(targetRates: [8.0])
        let blocks = [
            J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32,
                         subband: .ll, data: Data(count: 128),
                         passeCount: 12, zeroBitPlanes: 0),
            J2KCodeBlock(index: 1, x: 32, y: 0, width: 32, height: 32,
                         subband: .hl, data: Data(count: 96),
                         passeCount: 9, zeroBitPlanes: 0)
        ]
        let layer = formation.formLosslessLayer(codeBlocks: blocks)
        XCTAssertEqual(layer.codeBlockContributions[0], 12)
        XCTAssertEqual(layer.codeBlockContributions[1], 9)
    }

    // MARK: - End-to-End Layer Tests

    func testSingleLayerEncodeDecode() throws {
        let image = makeGreyscale(width: 64, height: 64)
        var config = J2KEncodingConfiguration()
        config.quality = 0.7
        config.lossless = false
        config.bitrateMode = .constantQuality
        config.qualityLayers = 1
        config.decompositionLevels = 3

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)
        let decoded = try J2KDecoder().decode(data)

        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
    }

    func testMultiLayerEncodeDecode() throws {
        let image = makeGreyscale(width: 64, height: 64)
        var config = J2KEncodingConfiguration()
        config.quality = 0.8
        config.lossless = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
        config.qualityLayers = 3
        config.decompositionLevels = 3

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)
        let decoded = try J2KDecoder().decode(data)

        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
    }

    func testLosslessEncodeDecode() throws {
        let image = makeGreyscale(width: 32, height: 32)
        var config = J2KEncodingConfiguration()
        config.lossless = true
        config.bitrateMode = .lossless
        config.qualityLayers = 1
        config.decompositionLevels = 2

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)
        let decoded = try J2KDecoder().decode(data)

        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 32)
        // Lossless: output should equal input
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "Lossless decode must exactly match original")
    }

    // MARK: - Marker Validation Tests

    func testCodestreamStartsWithSOC() throws {
        let image = makeGreyscale(width: 32, height: 32)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
        let data = try encoder.encode(image)

        XCTAssertGreaterThanOrEqual(data.count, 4)
        // SOC marker: 0xFF4F
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
    }

    func testCodestreamEndsWithEOC() throws {
        let image = makeGreyscale(width: 32, height: 32)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
        let data = try encoder.encode(image)

        // EOC marker: 0xFFD9
        XCTAssertEqual(data[data.count - 2], 0xFF)
        XCTAssertEqual(data[data.count - 1], 0xD9)
    }

    func testSIZMarkerPresent() throws {
        let image = makeGreyscale(width: 64, height: 64)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
        let data = try encoder.encode(image)

        // SIZ must follow SOC: bytes 2-3 = 0xFF51
        XCTAssertEqual(data[2], 0xFF)
        XCTAssertEqual(data[3], 0x51)
    }

    func testCODMarkerLayerCount() throws {
        // Verify COD encodes correct layer count
        let image = makeGreyscale(width: 32, height: 32)
        var config = J2KEncodingConfiguration()
        config.qualityLayers = 4
        config.lossless = true
        config.bitrateMode = .lossless

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)

        // Find COD marker (0xFF52)
        var codFound = false
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0x52 {
                codFound = true
                // COD segment: [marker(2)][length(2)][Scod(1)][SGcod: progOrder(1), layers(2), mct(1)]
                // layers at offset i+2+2+1+1 = i+6 (2 bytes, big-endian)
                let layersHi = UInt16(data[i + 6])
                let layersLo = UInt16(data[i + 7])
                let layerCount = (layersHi << 8) | layersLo
                XCTAssertEqual(layerCount, 4,
                    "COD marker should encode 4 quality layers")
                break
            }
        }
        XCTAssertTrue(codFound, "COD marker must be present")
    }

    func testSOTMarkerPresent() throws {
        let image = makeGreyscale(width: 32, height: 32)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
        let data = try encoder.encode(image)

        // Find SOT marker (0xFF90) anywhere in codestream
        var sotFound = false
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0x90 {
                sotFound = true
                break
            }
        }
        XCTAssertTrue(sotFound, "SOT marker must be present")
    }

    func testSODMarkerPresent() throws {
        let image = makeGreyscale(width: 32, height: 32)
        let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
        let data = try encoder.encode(image)

        // Find SOD marker (0xFF93) anywhere in codestream
        var sodFound = false
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0x93 {
                sodFound = true
                break
            }
        }
        XCTAssertTrue(sodFound, "SOD marker must be present")
    }

    // MARK: - Packet Overhead Tests

    func testPacketHeaderSmallerThanMQBased() throws {
        // The new bit-packed header should produce smaller output than the
        // old MQ-based approach for a typical packet.
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: false,
            codeBlockInclusions: [true, true, false, true],
            codingPasses: [1, 3, 2],
            dataLengths: [128, 256, 64]
        )
        let data = try writer.encode(header)

        // MQ-based approach typically produced 15-50 bytes for similar headers.
        // Bit-packed should be under 10 bytes.
        // Allow generous but reduced upper bound:
        XCTAssertLessThanOrEqual(data.count, 15,
            "Bit-packed header (\(data.count) bytes) should have low overhead")
    }

    func testEmptyPacketMinimalOverhead() throws {
        var writer = PacketHeaderWriter()
        let header = PacketHeader(
            layerIndex: 0, resolutionLevel: 0, componentIndex: 0,
            precinctIndex: 0, isEmpty: true
        )
        let data = try writer.encode(header)

        XCTAssertEqual(data.count, 1,
            "Empty packet should be exactly 1 byte overhead")
    }

    // MARK: - Progression Order Tests

    func testProgressionOrderEnumValues() throws {
        XCTAssertEqual(J2KProgressionOrder.lrcp.rawValue, "LRCP")
        XCTAssertEqual(J2KProgressionOrder.rlcp.rawValue, "RLCP")
        XCTAssertEqual(J2KProgressionOrder.rpcl.rawValue, "RPCL")
        XCTAssertEqual(J2KProgressionOrder.pcrl.rawValue, "PCRL")
        XCTAssertEqual(J2KProgressionOrder.cprl.rawValue, "CPRL")
    }

    func testAllProgressionOrdersEncode() throws {
        let image = makeGreyscale(width: 32, height: 32)

        for order in J2KProgressionOrder.allCases {
            var config = J2KEncodingConfiguration()
            config.quality = 0.7
            config.lossless = false
            config.bitrateMode = .constantQuality
            config.qualityLayers = 1
            config.decompositionLevels = 2
            config.progressionOrder = order

            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)

            XCTAssertGreaterThan(data.count, 0,
                "Encoding with \(order.rawValue) should produce data")

            // Verify decodable
            let decoded = try J2KDecoder().decode(data)
            XCTAssertEqual(decoded.width, 32)
            XCTAssertEqual(decoded.height, 32)
        }
    }

    // MARK: - Layer Configuration Benchmarks

    func testPrintLayerConfigurationBenchmark() throws {
        let image = makeGreyscale(width: 64, height: 64)
        let totalPixels = 64 * 64

        print("\n--- Layer Configuration Benchmark ---")
        print(String(format: "%-20s %-10s %-10s %-8s",
              "Configuration", "Size(B)", "BPP", "PSNR"))

        // Single layer, various quality
        for quality in [0.5, 0.7, 0.9] {
            var config = J2KEncodingConfiguration()
            config.quality = quality
            config.lossless = false
            config.bitrateMode = .constantQuality
            config.qualityLayers = 1
            config.decompositionLevels = 3

            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)
            let decoded = try J2KDecoder().decode(data)
            let p = psnr(original: image, decoded: decoded)
            let bpp = Double(data.count * 8) / Double(totalPixels)

            print(String(format: "1L q=%.1f            %-10d %-10.2f %-8.2f",
                  quality, data.count, bpp, p))
        }

        // Multi-layer at 2.0 bpp
        for layers in [1, 2, 3, 4] {
            var config = J2KEncodingConfiguration()
            config.quality = 0.8
            config.lossless = false
            config.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
            config.qualityLayers = layers
            config.decompositionLevels = 3

            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)
            let decoded = try J2KDecoder().decode(data)
            let p = psnr(original: image, decoded: decoded)
            let bpp = Double(data.count * 8) / Double(totalPixels)

            print(String(format: "%dL @2.0bpp           %-10d %-10.2f %-8.2f",
                  layers, data.count, bpp, p))
        }

        print("--- End Benchmark ---\n")
    }

    func testMultiLayerDoesNotIncreaseSize() throws {
        // Using more layers should not significantly increase output size
        // at the same target bitrate (modest overhead from extra packet headers)
        let image = makeGreyscale(width: 64, height: 64)

        var config1 = J2KEncodingConfiguration()
        config1.quality = 0.8
        config1.lossless = false
        config1.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
        config1.qualityLayers = 1
        config1.decompositionLevels = 3

        let encoder1 = J2KEncoder(encodingConfiguration: config1)
        let data1 = try encoder1.encode(image)

        var config4 = config1
        config4.qualityLayers = 4

        let encoder4 = J2KEncoder(encodingConfiguration: config4)
        let data4 = try encoder4.encode(image)

        // 4-layer version may be slightly larger due to packet headers
        // but should not be more than 20% larger
        let overhead = Double(data4.count) / Double(max(1, data1.count))
        XCTAssertLessThan(overhead, 1.2,
            "4-layer overhead (\(String(format: "%.1f%%", (overhead - 1) * 100))) " +
            "should be < 20%")
    }

    func testDeterministicLayerOutput() throws {
        let image = makeGreyscale(width: 64, height: 64)
        var config = J2KEncodingConfiguration()
        config.quality = 0.7
        config.lossless = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.0)
        config.qualityLayers = 2
        config.decompositionLevels = 3
        config.enableParallelCodeBlocks = false

        let encoder = J2KEncoder(encodingConfiguration: config)
        let d1 = try encoder.encode(image)
        let d2 = try encoder.encode(image)

        XCTAssertEqual(d1, d2, "Layer output must be deterministic")
    }
}
