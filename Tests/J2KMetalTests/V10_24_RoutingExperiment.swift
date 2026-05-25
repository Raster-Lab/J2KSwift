// V10_24_RoutingExperiment.swift
//
// v10.24-research — quick routing experiment before committing to the
// multi-day windowed-iDWT implementation. Hypothesis: routing single-
// tile ROI through pipeline.decodeGPU(data) (GPU iDWT) instead of
// pipeline.decode(data) (CPU iDWT) saves ~6-9 ms on the iDWT stage,
// closing most of the gap the windowed iDWT was targeting — but with
// a one-line implementation change.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_24_RoutingExperiment: XCTestCase {

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Quick A/B: CPU-iDWT-routed decodeRegion(.direct) vs
    /// GPU-iDWT-routed (using pipeline.decodeGPU instead of
    /// pipeline.decode). Same regionOfInterest, same entropy-skip,
    /// only the iDWT backend differs.
    func testRoutingExperiment_DX2800_256region() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()
        let region = J2KRegion(x: image.width / 2 - 128,
                               y: image.height / 2 - 128,
                               width: 256, height: 256)
        let options = J2KROIDecodingOptions(region: region, strategy: .direct)

        // Warm-up.
        _ = try await decoder.decodeRegion(codestream, options: options)

        let trials = 7
        var directWall = 0.0
        for _ in 0..<trials {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decoder.decodeRegion(codestream, options: options)
            directWall += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        }
        let directAvg = directWall / Double(trials)

        // GPU iDWT routing via decodeRegionDirect rewritten to use
        // pipeline.decodeGPU(data). Mirror it here with a private
        // DecoderPipeline + decodeGPU call.
        var pipeline = DecoderPipeline()
        pipeline.metalSession = J2KMetalSession.processShared
        pipeline.regionOfInterest = region
        // Warm.
        _ = try await pipeline.decodeGPU(codestream)
        var gpuRouteWall = 0.0
        for _ in 0..<trials {
            var pipe2 = DecoderPipeline()
            pipe2.metalSession = J2KMetalSession.processShared
            pipe2.regionOfInterest = region
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await pipe2.decodeGPU(codestream)
            gpuRouteWall += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        }
        let gpuAvg = gpuRouteWall / Double(trials)

        // Crop output dim check (the GPU path returns full-tile image;
        // decodeRegion in J2KAdvancedDecoding crops to region size).
        // For the experiment we just compare WALL TIME; bytes-parity
        // is validated by V10_24_BitExactRoutingTest below.
        print(String(format: """

        V10_24 routing experiment: DX 2800×2288, 256² centre ROI, n=%d trials, release
          .direct (current, CPU iDWT)        : %.2f ms
          .direct via pipeline.decodeGPU     : %.2f ms (full-image return; no crop yet)
          Δ %.2f ms (%.2fx faster if routed to GPU)
        """,
            trials, directAvg, gpuAvg,
            directAvg - gpuAvg,
            directAvg > 0 ? directAvg / gpuAvg : 0))
    }

    /// Bit-exactness gate: pipeline.decodeGPU(data) with regionOfInterest
    /// set produces the same full-image output as pipeline.decode(data)
    /// with the same regionOfInterest. Both then crop to region for the
    /// ROI return value.
    func testBitExactRoutingTest_DX2800_centreRegion() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let region = J2KRegion(x: image.width / 2 - 128,
                               y: image.height / 2 - 128,
                               width: 256, height: 256)

        // Path A: CPU iDWT route (current decodeRegionDirect)
        var pipeA = DecoderPipeline()
        pipeA.metalSession = J2KMetalSession.processShared
        pipeA.regionOfInterest = region
        let imageA = try await pipeA.decode(codestream)

        // Path B: GPU iDWT route
        var pipeB = DecoderPipeline()
        pipeB.metalSession = J2KMetalSession.processShared
        pipeB.regionOfInterest = region
        let imageB = try await pipeB.decodeGPU(codestream)

        XCTAssertEqual(imageA.width, imageB.width, "Routing-experiment widths must match")
        XCTAssertEqual(imageA.height, imageB.height, "Routing-experiment heights must match")
        XCTAssertEqual(imageA.components[0].data, imageB.components[0].data,
                       "Routing-experiment full-image output must be bit-identical (5/3 reversible)")
    }
}
#endif
