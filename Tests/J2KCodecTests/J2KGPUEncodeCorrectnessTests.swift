// Regression tests for GPU encoder correctness. These tests deliberately call
// encodeGPU instead of comparing the CPU entry point with itself.
import Foundation
import XCTest
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class J2KGPUEncodeCorrectnessTests: XCTestCase {
    private func image(
        width: Int, height: Int, components: Int
    ) -> J2KImage {
        let count = width * height
        let planes = (0..<components).map { component in
            let values = (0..<count).map { index -> UInt8 in
                UInt8((index * (component + 3) * 29 + component * 17) & 0xFF)
            }
            return J2KComponent(
                index: component, bitDepth: 8, signed: false,
                width: width, height: height,
                data: Data(values), sampleByteOrder: .littleEndian)
        }
        return J2KImage(width: width, height: height, components: planes)
    }

    private func withGPUForward53<T>(
        _ enabled: Bool, operation: () async throws -> T
    ) async rethrows -> T {
        let previous = EncoderPipeline._gpuForward53Enabled
        EncoderPipeline._gpuForward53Enabled = enabled
        defer { EncoderPipeline._gpuForward53Enabled = previous }
        return try await operation()
    }

    func testLosslessRGBEncodeGPUMatchesCPUBytes() async throws {
        try XCTSkipUnless(J2KMetalColorTransform.isAvailable, "Metal not available")
        let source = image(width: 256, height: 256, components: 3)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 3,
            useHTJ2K: false, useReversibleFilter: true)
        let cpu = try await withGPUForward53(false) {
            try await J2KEncoder(encodingConfiguration: config).encode(source)
        }
        let gpu = try await withGPUForward53(true) {
            try await J2KEncoder(encodingConfiguration: config).encodeGPU(source)
        }
        XCTAssertEqual(gpu, cpu,
                       "lossless encodeGPU must be byte-identical to encode")
    }

    func testLosslessGrayscaleEncodeGPUMatchesCPUBytes() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let source = image(width: 256, height: 256, components: 1)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 3,
            useHTJ2K: false, useReversibleFilter: true)
        let previousThreshold = EncoderPipeline._gpuForward53PixelThreshold
        EncoderPipeline._gpuForward53PixelThreshold = 1
        J2KGPUForward53Telemetry.reset()
        defer { EncoderPipeline._gpuForward53PixelThreshold = previousThreshold }
        let cpu = try await withGPUForward53(false) {
            try await J2KEncoder(encodingConfiguration: config).encode(source)
        }
        let gpu = try await withGPUForward53(true) {
            try await J2KEncoder(encodingConfiguration: config).encodeGPU(source)
        }
        XCTAssertGreaterThan(
            J2KGPUForward53Telemetry.snapshot().gpuFireCount, 0,
            "encodeGPU lossless must exercise the integer 5/3 GPU path")
        XCTAssertEqual(gpu, cpu,
                       "lossless grayscale encodeGPU must be byte-identical to encode")
    }

    func testLossyRGBGPURateBudgetIncludesEveryComponent() async throws {
        try XCTSkipUnless(J2KMetalColorTransform.isAvailable, "Metal not available")
        let source = image(width: 128, height: 128, components: 3)
        var config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 2,
            useHTJ2K: false, useReversibleFilter: false)
        config.bitrateMode = .constantBitrate(bitsPerPixel: 0.5)
        let cpu = try await withGPUForward53(false) {
            try await J2KEncoder(encodingConfiguration: config).encode(source)
        }
        let gpu = try await withGPUForward53(true) {
            try await J2KEncoder(encodingConfiguration: config).encodeGPU(source)
        }
        XCTAssertGreaterThan(
            gpu.count, cpu.count * 7 / 10,
            "GPU rate control must not silently budget RGB as one component")
    }
}
