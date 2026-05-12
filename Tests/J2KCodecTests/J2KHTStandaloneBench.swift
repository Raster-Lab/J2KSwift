// J2KHTStandaloneBench.swift
// Isolated J2KSwift HTJ2K encode/decode timing. Designed to run
// separately from the external-codec comparison so any crash in the
// J2KSwift pipeline doesn't affect the OpenJPH / OpenJPEG numbers.

import XCTest
import Foundation
import J2KCore
@testable import J2KCodec

final class HTStandaloneBench: XCTestCase {

    // v9.9 — pin planner envMode = .single so this isolated bench
    // tests the single-tile encode path on each fixture size. Under
    // the v7.0.0 .auto default, the 1024² test crashes inside the
    // multi-tile encoder (SIGSEGV during a per-tile encode for some
    // size/synthetic-content combination). The bench's intent is
    // single-tile timing, so pinning to .single both isolates the
    // measurement and avoids the multi-tile crash. The multi-tile
    // crash itself is a separate latent bug — tracked by the
    // failing testBenchJ2KSwiftHT1024Conformant SIGSEGV before
    // v9.9 — and should be investigated independently.
    private var _savedEnvMode: J2KHTTileMode!

    override func setUp() {
        super.setUp()
        _savedEnvMode = J2KEncodeTilePlanner.envMode
        J2KEncodeTilePlanner.envMode = .single
    }

    override func tearDown() {
        J2KEncodeTilePlanner.envMode = _savedEnvMode
        super.tearDown()
    }

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

        // v9.9 — explicit reversible filter for lossless. The test
        // previously relied on `J2KEncodingConfiguration()`'s default
        // `useReversibleFilter: false` (9/7 irreversible), which is
        // not the typical lossless config. The reversible 5/3 filter
        // is what production lossless callers use.
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useReversibleFilter = true
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
        // v9.9 — use Swift string interpolation instead of
        // `String(format:)` with `%@`/`%s` specifiers. The previous
        // String(format:) call SIGSEGV'd at runtime: `%@` expects an
        // ObjC-bridgeable type but receives Swift `String` directly
        // via the varargs CVarArg conversion, and `%s` expects
        // `CChar*` not Swift String. Either combination crashes
        // (manifested as signal 11 in the bench loop, present on
        // main pre-v9.5 and reproducing across all bench sizes for
        // .conformant format). Interpolation is type-safe and matches
        // the same human-readable output.
        let encMSStr = String(format: "%.2f", encMS)
        let labelPad = label.padding(toLength: 30, withPad: " ", startingAt: 0)
        let widthStr = String(format: "%5d", width)
        let heightStr = String(format: "%5d", height)
        let bytesStr = String(format: "%d", encoded.count)
        let bppStr = String(format: "%.3f", bpp)
        print("\(labelPad)  \(widthStr)x\(heightStr)  enc \(encMSStr) ms  dec \(decStr) ms   \(bytesStr) bytes   \(bppStr) bpp   \(losslessNote)")
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
