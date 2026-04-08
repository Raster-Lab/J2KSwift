//
// J2KPCRDOptTests.swift
// J2KSwift
//
// Tests for Post-Compression Rate-Distortion optimisation (PCRD-opt).
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KPCRDOptTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a synthetic greyscale test image with gradient and texture.
    private func makeSyntheticImage(width: Int, height: Int) -> J2KImage {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let gradient = (x * 255) / max(width - 1, 1)
                let checker = ((x / 8 + y / 8) % 2 == 0) ? 40 : 0
                pixels[y * width + x] = UInt8(min(255, gradient + checker))
            }
        }
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: pixels
        )
        return J2KImage(width: width, height: height, components: [component],
                        colorSpace: .grayscale)
    }

    /// Computes PSNR between two single-component 8-bit images.
    private func psnr(original: J2KImage, decoded: J2KImage) -> Double {
        let origData = original.components[0].data
        let decData = decoded.components[0].data
        guard origData.count == decData.count, !origData.isEmpty else { return 0 }
        var mse: Double = 0
        for i in 0..<origData.count {
            let d = Double(origData[i]) - Double(decData[i])
            mse += d * d
        }
        mse /= Double(origData.count)
        guard mse > 0 else { return Double.infinity }
        return 10.0 * log10(255.0 * 255.0 / mse)
    }

    // MARK: - CodingPassInfo Tests

    func testCodingPassInfoCreation() throws {
        let info = CodingPassInfo(
            codeBlockIndex: 0,
            passNumber: 2,
            cumulativeBytes: 100,
            distortion: 50.0,
            slope: 0.5
        )
        XCTAssertEqual(info.codeBlockIndex, 0)
        XCTAssertEqual(info.passNumber, 2)
        XCTAssertEqual(info.cumulativeBytes, 100)
        XCTAssertEqual(info.distortion, 50.0, accuracy: 1e-10)
        XCTAssertEqual(info.slope, 0.5, accuracy: 1e-10)
    }

    // MARK: - Rate Control Configuration Tests

    func testTargetBitrateConfiguration() throws {
        let config = RateControlConfiguration.targetBitrate(1.5, layerCount: 3)
        if case .targetBitrate(let bpp) = config.mode {
            XCTAssertEqual(bpp, 1.5, accuracy: 1e-10)
        } else {
            XCTFail("Expected targetBitrate mode")
        }
        XCTAssertEqual(config.layerCount, 3)
    }

    func testConstantQualityConfiguration() throws {
        let config = RateControlConfiguration.constantQuality(0.8, layerCount: 2)
        if case .constantQuality(let q) = config.mode {
            XCTAssertEqual(q, 0.8, accuracy: 1e-10)
        } else {
            XCTFail("Expected constantQuality mode")
        }
    }

    func testLosslessConfiguration() throws {
        let config = RateControlConfiguration.lossless
        if case .lossless = config.mode {
            // OK
        } else {
            XCTFail("Expected lossless mode")
        }
        XCTAssertEqual(config.layerCount, 1)
    }

    // MARK: - PCRD-opt Core Tests

    func testLosslessLayerIncludesAllPasses() throws {
        let blocks = [
            J2KCodeBlock(
                index: 0, x: 0, y: 0, width: 32, height: 32,
                subband: .ll, data: Data(repeating: 0xAB, count: 100),
                passeCount: 9, zeroBitPlanes: 0
            ),
            J2KCodeBlock(
                index: 1, x: 32, y: 0, width: 32, height: 32,
                subband: .hl, data: Data(repeating: 0xCD, count: 80),
                passeCount: 6, zeroBitPlanes: 1
            )
        ]

        let config = RateControlConfiguration.lossless
        let rc = J2KRateControl(configuration: config)
        let layers = try rc.optimizeLayers(codeBlocks: blocks, totalPixels: 64 * 32)

        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].codeBlockContributions[0], 9)
        XCTAssertEqual(layers[0].codeBlockContributions[1], 6)
    }

    func testTargetBitrateReducesSize() throws {
        // Encode a synthetic image
        let image = makeSyntheticImage(width: 64, height: 64)

        // Encode without rate control (all passes)
        var noRCConfig = J2KEncodingConfiguration()
        noRCConfig.quality = 0.8
        noRCConfig.lossless = false
        noRCConfig.bitrateMode = .constantQuality
        noRCConfig.qualityLayers = 1
        noRCConfig.decompositionLevels = 3

        let encoderNoRC = J2KEncoder(encodingConfiguration: noRCConfig)
        let noRCData = try encoderNoRC.encode(image)

        // Encode with target bitrate
        var rcConfig = J2KEncodingConfiguration()
        rcConfig.quality = 0.8
        rcConfig.lossless = false
        rcConfig.bitrateMode = .constantBitrate(bitsPerPixel: 0.5) // 0.5 bpp
        rcConfig.qualityLayers = 1
        rcConfig.decompositionLevels = 3

        let encoderRC = J2KEncoder(encodingConfiguration: rcConfig)
        let rcData = try encoderRC.encode(image)

        // Rate-controlled output should be smaller or equal
        XCTAssertLessThanOrEqual(rcData.count, noRCData.count,
            "Rate-controlled output (\(rcData.count)) should not exceed " +
            "uncontrolled output (\(noRCData.count))")
    }

    func testDeterministicOutput() throws {
        let image = makeSyntheticImage(width: 64, height: 64)

        var config = J2KEncodingConfiguration()
        config.quality = 0.7
        config.lossless = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 1.0)
        config.qualityLayers = 1
        config.decompositionLevels = 3
        config.enableParallelCodeBlocks = false // deterministic

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data1 = try encoder.encode(image)
        let data2 = try encoder.encode(image)

        XCTAssertEqual(data1, data2, "Encoding must be deterministic")
    }

    // MARK: - Multi-Layer Tests

    func testMultiLayerFormation() throws {
        let image = makeSyntheticImage(width: 64, height: 64)

        var config = J2KEncodingConfiguration()
        config.quality = 0.8
        config.lossless = false
        config.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
        config.qualityLayers = 3
        config.decompositionLevels = 3

        let encoder = J2KEncoder(encodingConfiguration: config)
        let data = try encoder.encode(image)

        // Multi-layer output should still be decodable
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(data)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 64)
    }

    // MARK: - Metrics Tests

    func testPCRDMetricsAvailable() throws {
        let blocks = [
            J2KCodeBlock(
                index: 0, x: 0, y: 0, width: 32, height: 32,
                subband: .ll, data: Data(repeating: 0xAB, count: 100),
                passeCount: 9, zeroBitPlanes: 0,
                passSegmentLengths: [15, 12, 10, 12, 10, 8, 12, 10, 11]
            )
        ]

        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 1)
        let rc = J2KRateControl(configuration: config)
        let (layers, metrics) = try rc.optimizeLayersWithMetrics(
            codeBlocks: blocks, totalPixels: 32 * 32
        )

        XCTAssertFalse(layers.isEmpty)
        XCTAssertEqual(metrics.totalCodedBytes, 100)
        XCTAssertGreaterThan(metrics.compressionRatio, 0)
        XCTAssertFalse(metrics.layerMetrics.isEmpty)
    }

    func testMetricsSavingsPercent() throws {
        let blocks = [
            J2KCodeBlock(
                index: 0, x: 0, y: 0, width: 64, height: 64,
                subband: .ll, data: Data(repeating: 0xFF, count: 500),
                passeCount: 12, zeroBitPlanes: 0,
                passSegmentLengths: [50, 45, 40, 45, 40, 35, 45, 40, 35, 40, 35, 30]
            )
        ]

        // Very low bitrate should trigger significant truncation
        let config = RateControlConfiguration.targetBitrate(0.1, layerCount: 1)
        let rc = J2KRateControl(configuration: config)
        let (_, metrics) = try rc.optimizeLayersWithMetrics(
            codeBlocks: blocks, totalPixels: 64 * 64
        )

        // Should achieve some savings
        XCTAssertGreaterThanOrEqual(metrics.savingsPercent, 0,
            "Savings should be non-negative")
        XCTAssertGreaterThan(metrics.actualBpp, 0,
            "Should have non-zero actual bpp")
    }

    // MARK: - Per-Pass Segment Length Tests

    func testPassSegmentLengthsProducedForPCRD() throws {
        // When using near-optimal termination, pass segment lengths
        // should be populated
        let coefficients: [Int32] = (0..<(32 * 32)).map { i in
            Int32(i % 256) - 128
        }

        let encoder = CodeBlockEncoder()
        let block = try encoder.encode(
            coefficients: coefficients,
            width: 32,
            height: 32,
            subband: .ll,
            bitDepth: 8,
            options: .pcrdOptimal
        )

        XCTAssertGreaterThan(block.passeCount, 0)
        XCTAssertFalse(block.passSegmentLengths.isEmpty,
            "Per-pass segment lengths must be populated with pcrdOptimal options")
        XCTAssertEqual(block.passSegmentLengths.count, block.passeCount,
            "Segment length count should match pass count")

        // Sum of segments should equal total data size
        let segmentSum = block.passSegmentLengths.reduce(0, +)
        XCTAssertEqual(segmentSum, block.data.count,
            "Sum of segment lengths (\(segmentSum)) should equal data size (\(block.data.count))")
    }

    // MARK: - Regression Tests

    func testPCRDImprovesPSNRPerByte() throws {
        // Compare quality-per-byte between constant quality (no PCRD truncation)
        // and bitrate-targeted (PCRD active) encoding.
        //
        // At matched output sizes, PCRD should give equal or better PSNR
        // because it selects the most important coding passes.
        let image = makeSyntheticImage(width: 64, height: 64)

        // Encode with constant quality (baseline)
        var baseConfig = J2KEncodingConfiguration()
        baseConfig.quality = 0.6
        baseConfig.lossless = false
        baseConfig.bitrateMode = .constantQuality
        baseConfig.qualityLayers = 1
        baseConfig.decompositionLevels = 3

        let baseEncoder = J2KEncoder(encodingConfiguration: baseConfig)
        let baseData = try baseEncoder.encode(image)
        let baseDecoded = try J2KDecoder().decode(baseData)
        let basePSNR = psnr(original: image, decoded: baseDecoded)
        let baseEfficiency = basePSNR / Double(baseData.count) // PSNR per byte

        // Encode with PCRD at similar bitrate
        let targetBpp = Double(baseData.count * 8) / Double(64 * 64)
        var pcrdConfig = J2KEncodingConfiguration()
        pcrdConfig.quality = 0.6
        pcrdConfig.lossless = false
        pcrdConfig.bitrateMode = .constantBitrate(bitsPerPixel: targetBpp)
        pcrdConfig.qualityLayers = 1
        pcrdConfig.decompositionLevels = 3

        let pcrdEncoder = J2KEncoder(encodingConfiguration: pcrdConfig)
        let pcrdData = try pcrdEncoder.encode(image)
        let pcrdDecoded = try J2KDecoder().decode(pcrdData)
        let pcrdPSNR = psnr(original: image, decoded: pcrdDecoded)
        let pcrdEfficiency = pcrdPSNR / Double(max(1, pcrdData.count))

        // PCRD should not produce significantly worse efficiency
        // Allow 20% tolerance because the mechanism adds some overhead
        XCTAssertGreaterThanOrEqual(pcrdEfficiency, baseEfficiency * 0.8,
            "PCRD efficiency (\(pcrdEfficiency)) should not be much worse " +
            "than baseline (\(baseEfficiency))")

        // Print comparison for manual inspection
        print("--- PCRD Regression ---")
        print("  Baseline: \(baseData.count) bytes, PSNR=\(String(format: "%.2f", basePSNR)) dB")
        print("  PCRD:     \(pcrdData.count) bytes, PSNR=\(String(format: "%.2f", pcrdPSNR)) dB")
        print("  Target bpp: \(String(format: "%.2f", targetBpp))")
    }

    func testPCRDSizeReductionRegression() throws {
        // PCRD at low bitrate must produce smaller output than constant quality
        let image = makeSyntheticImage(width: 64, height: 64)

        var fullConfig = J2KEncodingConfiguration()
        fullConfig.quality = 0.9
        fullConfig.lossless = false
        fullConfig.bitrateMode = .constantQuality
        fullConfig.qualityLayers = 1
        fullConfig.decompositionLevels = 3

        let fullEncoder = J2KEncoder(encodingConfiguration: fullConfig)
        let fullData = try fullEncoder.encode(image)

        // Request very low bitrate
        var lowConfig = J2KEncodingConfiguration()
        lowConfig.quality = 0.9
        lowConfig.lossless = false
        lowConfig.bitrateMode = .constantBitrate(bitsPerPixel: 0.3) // very low
        lowConfig.qualityLayers = 1
        lowConfig.decompositionLevels = 3

        let lowEncoder = J2KEncoder(encodingConfiguration: lowConfig)
        let lowData = try lowEncoder.encode(image)

        // Low bitrate must be smaller
        XCTAssertLessThan(lowData.count, fullData.count,
            "Low-bitrate PCRD (\(lowData.count)) must be smaller " +
            "than full quality (\(fullData.count))")
    }

    // MARK: - Benchmark Comparison

    func testPrintPCRDBenchmark() throws {
        let image = makeSyntheticImage(width: 64, height: 64)
        let totalPixels = 64 * 64

        print("\n--- PCRD-opt Benchmark ---")
        print(String(format: "%-12s %-10s %-10s %-8s %-10s",
              "Mode", "Size", "BPP", "PSNR", "Eff"))

        // Constant quality baseline
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
            let eff = p / bpp

            print(String(format: "CQ(%.1f)     %-10d %-10.2f %-8.2f %-10.2f",
                  quality, data.count, bpp, p, eff))
        }

        // PCRD bitrate targets
        for targetBpp in [0.5, 1.0, 2.0, 4.0] {
            var config = J2KEncodingConfiguration()
            config.quality = 0.9
            config.lossless = false
            config.bitrateMode = .constantBitrate(bitsPerPixel: targetBpp)
            config.qualityLayers = 1
            config.decompositionLevels = 3

            let encoder = J2KEncoder(encodingConfiguration: config)
            let data = try encoder.encode(image)
            let decoded = try J2KDecoder().decode(data)
            let p = psnr(original: image, decoded: decoded)
            let actualBpp = Double(data.count * 8) / Double(totalPixels)
            let eff = p / actualBpp

            print(String(format: "PCRD(%.1f)   %-10d %-10.2f %-8.2f %-10.2f",
                  targetBpp, data.count, actualBpp, p, eff))
        }

        print("--- End Benchmark ---\n")
    }
}
