// J2KHTConformantConstantBitrateViaQstepTests.swift
// v5.19.0 R-D regression gate.
//
// v5.19.0 added .constantBitrateViaQstep mode — combines
// .constantBitrate's target-bpp convenience with .fixedQstep's R-D
// quality (no PCRD-opt all-or-nothing block selection). Implemented
// as an outer binary search on qstep that runs full encodes per
// iteration until achieved bpp matches target.
//
// This gate locks in the R-D improvement. Two assertions:
//   1. Achieved bpp within the configured tolerance of target bpp.
//   2. PSNR strictly higher than .constantBitrate at the same target.
// If either ever fails, either the search loop or the underlying
// qstep semantics changed and need re-investigation.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantConstantBitrateViaQstepTests: XCTestCase {

    private func makeSynth8(width: Int, height: Int, seed: UInt64 = 0xfeed_face_dead_beef) -> J2KImage {
        var s = seed &+ UInt64(width) &* 1009 &+ UInt64(height) &* 7919
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<bytes.count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let x = i % width
            let y = i / width
            let gradient = (x * 31 + y * 17) & 255
            let noise = Int(s >> 56) & 255
            bytes[i] = UInt8(gradient ^ noise)
        }
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height,
            data: Data(bytes))
        return J2KImage(width: width, height: height, components: [component])
    }

    private func psnr8(_ a: Data, _ b: Data, peak: Int = 255) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return -.infinity }
        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)
        var sse: Double = 0
        for i in 0..<count {
            let d = Double(Int(aBytes[i]) - Int(bBytes[i]))
            sse += d * d
        }
        if sse == 0 { return .infinity }
        let mse = sse / Double(count)
        return 10.0 * log10(Double(peak * peak) / mse)
    }

    /// At target bpp = 2.0, .constantBitrateViaQstep must:
    ///   1. Hit the target within tolerance (default 5%).
    ///   2. Produce strictly higher PSNR than .constantBitrate at the
    ///      same target (PCRD-opt's all-or-nothing block selection
    ///      loses ~7 dB on HT conformant lossy; this mode recovers
    ///      most of that gap).
    func testConstantBitrateViaQstep_HitsTargetAndBeatsPCRDOpt() async throws {
        let image = makeSynth8(width: 512, height: 512)
        let totalSamples = image.width * image.height * image.componentCount
        let targetBpp = 2.0
        let tolerance = 0.10  // generous on synth content

        // .constantBitrateViaQstep — the v5.19.0 mode.
        var viaQstepCfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        viaQstepCfg.bitrateMode = .constantBitrateViaQstep(
            bitsPerPixel: targetBpp,
            tolerance: tolerance,
            maxIterations: 8)

        let viaQstepEncoded = try await J2KEncoder(encodingConfiguration: viaQstepCfg).encode(image)
        let viaQstepDecoded = try await J2KDecoder().decode(viaQstepEncoded)
        let viaQstepBpp = Double(viaQstepEncoded.count * 8) / Double(totalSamples)
        let viaQstepPSNR = psnr8(image.components[0].data, viaQstepDecoded.components[0].data)

        // .constantBitrate (the existing mode that has the R-D gap).
        var pcrdCfg = viaQstepCfg
        pcrdCfg.bitrateMode = .constantBitrate(bitsPerPixel: targetBpp)
        let pcrdEncoded = try await J2KEncoder(encodingConfiguration: pcrdCfg).encode(image)
        let pcrdDecoded = try await J2KDecoder().decode(pcrdEncoded)
        let pcrdBpp = Double(pcrdEncoded.count * 8) / Double(totalSamples)
        let pcrdPSNR = psnr8(image.components[0].data, pcrdDecoded.components[0].data)

        let delta = viaQstepPSNR - pcrdPSNR
        print("v5.19.0 .constantBitrateViaQstep R-D regression:")
        print("  ViaQstep mode (target=\(targetBpp)): bpp=\(String(format: "%.3f", viaQstepBpp)) PSNR=\(String(format: "%.2f", viaQstepPSNR)) dB")
        print("  PCRD-opt mode (target=\(targetBpp)): bpp=\(String(format: "%.3f", pcrdBpp)) PSNR=\(String(format: "%.2f", pcrdPSNR)) dB")
        print("  Δ (ViaQstep − PCRD-opt) = \(String(format: "%+.2f", delta)) dB")

        // Assertion 1: hit target bpp within tolerance.
        let bppRatio = viaQstepBpp / targetBpp
        XCTAssertLessThan(abs(bppRatio - 1.0), tolerance + 0.05,
                          "ViaQstep mode missed target bpp by more than tolerance + 5% slack")

        // Assertion 2: beat PCRD-opt by at least 3 dB. Pre-v5.19 was 0 (mode didn't exist).
        XCTAssertGreaterThan(delta, 3.0,
                             "v5.19.0 .constantBitrateViaQstep must beat .constantBitrate by ≥3 dB at matched bpp; got \(String(format: "%+.2f", delta)) dB")
    }

    /// Configuration round-trip: setting .constantBitrateViaQstep should
    /// be intercepted by J2KEncoder.encode and produce a valid encoded
    /// bitstream (any tolerance, any maxIterations).
    func testConstantBitrateViaQstepConfigurationPersists() async throws {
        let image = makeSynth8(width: 64, height: 64)
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrateViaQstep(
            bitsPerPixel: 1.0, tolerance: 0.20, maxIterations: 4)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        XCTAssertGreaterThan(encoded.count, 0, "ViaQstep encode produced empty output")

        // Round-trip through the decoder.
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, image.components.count)
    }
}
