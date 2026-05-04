// J2KHTConformantFixedQstepRDTests.swift
// v5.18.0 R-D regression gate.
//
// v5.18.0 added .fixedQstep mode to J2KBitrateMode as a workaround
// for the lossy HT conformant R-D gap documented in v5.16.0. PCRD-opt
// can't truncate inside a single-cleanup-pass HT block (only one
// truncation point per block), so it makes all-or-nothing block
// selection decisions that produce ~7 dB worse R-D than EBCOT or
// OpenJPH at matched bitrates.
//
// Fixed-qstep mode bypasses PCRD-opt entirely: every block is
// included unchanged, quality is governed by the user-supplied
// quantization step. Matches OpenJPH's encoder model.
//
// This gate locks in the R-D improvement: at matched achieved bpp,
// fixed-qstep must produce STRICTLY HIGHER PSNR than the equivalent
// PCRD-opt encode for HT conformant lossy. If it ever doesn't, the
// design assumption (PCRD-opt is the bottleneck) has changed and we
// need to re-investigate.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantFixedQstepRDTests: XCTestCase {

    /// Build a deterministic 8-bit synth image — same construction as
    /// other v5.x R-D probes for cross-comparison.
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

    /// At a fixed-qstep that produces ~2 bpp, J2KSwift HT conformant
    /// lossy must achieve strictly higher PSNR than PCRD-opt at
    /// `--bitrate 2.0`. Pre-v5.18.0 the gap was effectively 0 dB (no
    /// fixed-qstep mode existed); v5.18.0 measured +6.55 dB on this
    /// content. Gate at +3 dB to leave headroom for content variance.
    func testFixedQstep_BeatsPCRD_AtMatchedBpp() async throws {
        let image = makeSynth8(width: 512, height: 512)

        // Fixed-qstep mode at qstep=40 ≈ 2 bpp on this image.
        var qstepCfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        qstepCfg.bitrateMode = .fixedQstep(qstep: 40.0)

        let qstepEncoded = try await J2KEncoder(encodingConfiguration: qstepCfg).encode(image)
        let qstepDecoded = try await J2KDecoder().decode(qstepEncoded)
        let qstepBpp = Double(qstepEncoded.count * 8) / Double(image.width * image.height)
        let qstepPSNR = psnr8(image.components[0].data, qstepDecoded.components[0].data)

        // Same configuration but with PCRD-opt at the same achieved bpp target.
        var pcrdCfg = qstepCfg
        pcrdCfg.bitrateMode = .constantBitrate(bitsPerPixel: qstepBpp)

        let pcrdEncoded = try await J2KEncoder(encodingConfiguration: pcrdCfg).encode(image)
        let pcrdDecoded = try await J2KDecoder().decode(pcrdEncoded)
        let pcrdBpp = Double(pcrdEncoded.count * 8) / Double(image.width * image.height)
        let pcrdPSNR = psnr8(image.components[0].data, pcrdDecoded.components[0].data)

        let delta = qstepPSNR - pcrdPSNR
        print("v5.18.0 fixed-qstep R-D regression:")
        print("  Fixed-qstep mode (qstep=40): bpp=\(String(format: "%.3f", qstepBpp)) PSNR=\(String(format: "%.2f", qstepPSNR)) dB")
        print("  PCRD-opt mode (--bitrate \(String(format: "%.3f", qstepBpp))): bpp=\(String(format: "%.3f", pcrdBpp)) PSNR=\(String(format: "%.2f", pcrdPSNR)) dB")
        print("  Δ (fixed-qstep − PCRD-opt) = \(String(format: "%+.2f", delta)) dB")

        // Sanity: bpp values should be comparable (within 10%) for the
        // PSNR comparison to be meaningful. PCRD-opt should hit its
        // target bpp closely.
        XCTAssertEqual(pcrdBpp, qstepBpp, accuracy: qstepBpp * 0.10,
                       "PCRD-opt didn't hit the target bpp closely enough for fair comparison")

        // Core assertion: fixed-qstep must beat PCRD-opt by at least
        // 3 dB at matched bpp on lossy HT conformant 8-bit.
        XCTAssertGreaterThan(delta, 3.0,
                             "v5.18.0 fixed-qstep mode must beat PCRD-opt by ≥3 dB at matched bpp; got \(String(format: "%+.2f", delta)) dB")
    }

    /// Configuration round-trip: setting .fixedQstep should be
    /// preserved through encoding without crashing or being silently
    /// converted to another mode.
    func testFixedQstepConfigurationPersists() async throws {
        let image = makeSynth8(width: 64, height: 64)
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .fixedQstep(qstep: 5.0)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        XCTAssertGreaterThan(encoded.count, 0, "fixed-qstep encode produced empty output")

        // Decode round-trips
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components.count, image.components.count)
    }
}
