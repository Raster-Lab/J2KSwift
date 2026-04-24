// J2KHTStandaloneBench.swift
// Isolated J2KSwift HTJ2K encode/decode timing. Designed to run
// separately from the external-codec comparison so any crash in the
// J2KSwift pipeline doesn't affect the OpenJPH / OpenJPEG numbers.

import XCTest
import Foundation
import J2KCore
@testable import J2KCodec

final class HTStandaloneBench: XCTestCase {

    private func syntheticPixels(width: Int, height: Int, seed: UInt64)
        -> [UInt8]
    {
        var pixels = [UInt8](repeating: 0, count: width * height)
        var state = seed | 1
        for y in 0..<height {
            for x in 0..<width {
                state &*= 6364136223846793005
                state &+= 1442695040888963407
                let noise = Int((state >> 56) & 0x1F) - 16
                let gradient = (x * 128 / width) + (y * 128 / height)
                pixels[y * width + x] = UInt8(max(0, min(255, gradient + noise)))
            }
        }
        return pixels
    }

    private func image(w: Int, h: Int, pixels: [UInt8]) -> J2KImage {
        let c = J2KComponent(
            index: 0, bitDepth: 8, width: w, height: h, data: Data(pixels))
        return J2KImage(width: w, height: h, components: [c])
    }

    private func bench(
        label: String, width: Int, height: Int, pixels: [UInt8],
        format: HTBlockFormat, iterations: Int = 3
    ) async throws {
        let img = image(w: width, h: height, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = format
        cfg.decompositionLevels = 5

        let encoder = J2KEncoder(encodingConfiguration: cfg)
        // Warmup.
        _ = try await encoder.encode(img)

        var encoded = Data()
        var totalE: Double = 0
        for _ in 0..<iterations {
            let t0 = CFAbsoluteTimeGetCurrent()
            encoded = try await encoder.encode(img)
            totalE += CFAbsoluteTimeGetCurrent() - t0
        }
        let encMS = (totalE / Double(iterations)) * 1000

        // Decode only through J2KSwift for custom format; the
        // conformant pipeline decode is v5.1.
        var decMS: Double? = nil
        var decoded: [UInt8]? = nil
        if format == .custom {
            let decoder = J2KDecoder()
            var totalD: Double = 0
            for _ in 0..<iterations {
                let t0 = CFAbsoluteTimeGetCurrent()
                let out = try await decoder.decode(encoded)
                totalD += CFAbsoluteTimeGetCurrent() - t0
                decoded = [UInt8](out.components[0].data)
            }
            decMS = (totalD / Double(iterations)) * 1000
        }

        let bpp = Double(encoded.count * 8) / Double(width * height)
        let losslessNote = (decoded == pixels) ? "✓"
            : (decoded == nil ? "(n/a pipeline)" : "✗")
        let decStr = decMS.map { String(format: "%.2f", $0) } ?? "  —  "
        print(String(format: "%-30s  %5dx%5d  enc %.2f ms  dec %@ ms   %d bytes   %.3f bpp   %@",
              label, width, height, encMS, decStr,
              encoded.count, bpp, losslessNote))
    }

    func testBenchJ2KSwiftHT256Custom() async throws {
        let w = 256, h = 256
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1001)
        try await bench(label: "J2KSwift HT custom", width: w, height: h,
                       pixels: pixels, format: .custom)
    }

    func testBenchJ2KSwiftHT512Custom() async throws {
        let w = 512, h = 512
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1002)
        try await bench(label: "J2KSwift HT custom", width: w, height: h,
                       pixels: pixels, format: .custom)
    }

    func testBenchJ2KSwiftHT1024Custom() async throws {
        let w = 1024, h = 1024
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1003)
        try await bench(label: "J2KSwift HT custom", width: w, height: h,
                       pixels: pixels, format: .custom)
    }

    func testBenchJ2KSwiftHT256Conformant() async throws {
        let w = 256, h = 256
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1001)
        try await bench(label: "J2KSwift HT conformant", width: w, height: h,
                       pixels: pixels, format: .conformant)
    }

    func testBenchJ2KSwiftHT512Conformant() async throws {
        let w = 512, h = 512
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1002)
        try await bench(label: "J2KSwift HT conformant", width: w, height: h,
                       pixels: pixels, format: .conformant)
    }

    func testBenchJ2KSwiftHT1024Conformant() async throws {
        let w = 1024, h = 1024
        let pixels = syntheticPixels(width: w, height: h, seed: 0x1003)
        try await bench(label: "J2KSwift HT conformant", width: w, height: h,
                       pixels: pixels, format: .conformant)
    }
}
