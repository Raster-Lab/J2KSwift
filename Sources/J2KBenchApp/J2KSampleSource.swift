//
// J2KSampleSource.swift
// J2KBenchApp — shared codec helpers
//
// Fixture synthesis, encoder configurations, photo → J2KImage
// conversion, and PSNR. Shared by the benchmark runner (BenchRunner)
// and the image viewer (ViewerModel) so the two never drift apart.

import Foundation
import J2KCore
import J2KCodec

#if canImport(UIKit)
import UIKit
import CoreGraphics
#endif

enum J2KSampleSource {

    // MARK: - Encoder configurations

    /// Canonical HT-J2K conformant lossless config — the exact encode
    /// configuration the in-process performance suite uses, so the
    /// benchmark stays apples-to-apples across hosts.
    static func losslessHTEncoder() -> J2KEncoder {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
        return J2KEncoder(encodingConfiguration: cfg)
    }

    /// Irreversible (9/7) HT-J2K lossy config used by the viewer's
    /// photo round-trip so PSNR is a meaningful finite number.
    static func lossyHTEncoder(quality: Double) -> J2KEncoder {
        let cfg = J2KEncodingConfiguration(
            quality: quality, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .constantQuality,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: false,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
        return J2KEncoder(encodingConfiguration: cfg)
    }

    // MARK: - Deterministic fixture synthesis

    /// Mirrors `Scripts/benchmarks/generate_synthetic_corpus.py`'s LCG
    /// noise field (multiplier `1442695040888963407`) so an A-series
    /// run is comparable byte-equivalent against the canonical PGM
    /// corpus on M-series. Modality-specific structural overlays are
    /// omitted — they affect compression ratio, not timing rankings.
    static func synthesize(_ fixture: BenchFixture) -> J2KImage {
        let n = fixture.width * fixture.height
        let bitDepth = fixture.bitDepth
        let bytesPerSample = (bitDepth + 7) / 8
        precondition(bytesPerSample == 2, "16-bit corpus only")

        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: n * 2)
        var s: UInt64 = fixture.seed &* 6364136223846793005 &+ 1442695040888963407

        data.withUnsafeMutableBytes { rawPtr in
            let buf = rawPtr.bindMemory(to: UInt16.self)
            for i in 0..<n {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let sample = UInt16(Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                // Big-endian byte order matches the PGM corpus written
                // by generate_synthetic_corpus.py.
                buf[i] = sample.bigEndian
            }
        }

        let comp = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: fixture.width,
            height: fixture.height,
            subsamplingX: 1, subsamplingY: 1,
            data: data,
            sampleByteOrder: .bigEndian)
        return J2KImage(
            width: fixture.width,
            height: fixture.height,
            components: [comp])
    }

    // MARK: - PGM decoding

    /// Parse a binary PGM (P5) into a single-component `J2KImage`. Used
    /// for the bundled real medical images, which are 16-bit / 12-bit
    /// grayscale graymaps. 16-bit PGM rasters are big-endian per spec.
    static func j2kImage(fromPGM data: Data) -> J2KImage? {
        let bytes = [UInt8](data)
        guard bytes.count > 2, bytes[0] == 0x50, bytes[1] == 0x35 else { return nil }
        var i = 2

        func skipBlanksAndComments() {
            while i < bytes.count {
                let c = bytes[i]
                if c == 0x23 {                       // '#' — comment to end of line
                    while i < bytes.count && bytes[i] != 0x0A { i += 1 }
                } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    i += 1
                } else { break }
            }
        }
        func readInt() -> Int? {
            skipBlanksAndComments()
            var value = 0, any = false
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                value = value * 10 + Int(bytes[i] - 0x30)
                i += 1
                any = true
            }
            return any ? value : nil
        }

        guard let width = readInt(), let height = readInt(),
              let maxValue = readInt(),
              width > 0, height > 0, maxValue > 0 else { return nil }
        guard i < bytes.count else { return nil }
        i += 1                                       // single whitespace before raster

        let bytesPerSample = maxValue > 255 ? 2 : 1
        let needed = width * height * bytesPerSample
        guard i + needed <= bytes.count else { return nil }

        let raster = Data(bytes[i..<(i + needed)])
        let bitDepth = max(1, Int(ceil(log2(Double(maxValue + 1)))))
        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: raster,
            sampleByteOrder: bytesPerSample == 2 ? .bigEndian : nil)
        return J2KImage(width: width, height: height, components: [comp])
    }

    // MARK: - Photo → J2KImage

    #if canImport(UIKit)
    /// Render an arbitrary `CGImage` into a known RGBA8 bitmap and
    /// split it into three planar 8-bit components — the J2KImage the
    /// viewer's photo round-trip feeds to the encoder.
    static func j2kImage(from cgImage: CGImage) -> J2KImage? {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        let count = w * h

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return nil }

        let stride = ctx.bytesPerRow
        let px = base.bindMemory(to: UInt8.self, capacity: stride * h)

        var r = Data(count: count)
        var g = Data(count: count)
        var b = Data(count: count)
        r.withUnsafeMutableBytes { rp in
            g.withUnsafeMutableBytes { gp in
                b.withUnsafeMutableBytes { bp in
                    let rb = rp.bindMemory(to: UInt8.self)
                    let gb = gp.bindMemory(to: UInt8.self)
                    let bb = bp.bindMemory(to: UInt8.self)
                    for y in 0..<h {
                        let row = y * stride
                        for x in 0..<w {
                            let s = row + x * 4
                            let i = y * w + x
                            rb[i] = px[s]
                            gb[i] = px[s + 1]
                            bb[i] = px[s + 2]
                        }
                    }
                }
            }
        }

        func comp(_ idx: Int, _ d: Data) -> J2KComponent {
            J2KComponent(index: idx, bitDepth: 8, signed: false,
                         width: w, height: h,
                         subsamplingX: 1, subsamplingY: 1,
                         data: d, sampleByteOrder: nil)
        }
        return J2KImage(width: w, height: h,
                        components: [comp(0, r), comp(1, g), comp(2, b)])
    }
    #endif

    // MARK: - PSNR

    /// Peak signal-to-noise ratio (dB) between two 8-bit images.
    /// Returns `nil` for an exact (lossless) match or for shapes that
    /// don't line up — the viewer shows "exact" in that case.
    static func psnr(_ a: J2KImage, _ b: J2KImage) -> Double? {
        guard a.width == b.width, a.height == b.height,
              a.components.count == b.components.count else { return nil }
        var sumSq: Double = 0
        var n = 0
        for (ca, cb) in zip(a.components, b.components) {
            guard ca.bitDepth <= 8, cb.bitDepth <= 8 else { return nil }
            let len = min(ca.data.count, cb.data.count)
            ca.data.withUnsafeBytes { pa in
                cb.data.withUnsafeBytes { pb in
                    let ba = pa.bindMemory(to: UInt8.self)
                    let bb = pb.bindMemory(to: UInt8.self)
                    for i in 0..<len {
                        let d = Double(Int(ba[i]) - Int(bb[i]))
                        sumSq += d * d
                    }
                }
            }
            n += len
        }
        guard n > 0 else { return nil }
        let mse = sumSq / Double(n)
        guard mse > 0 else { return nil }   // bit-exact reconstruction
        return 10.0 * log10(255.0 * 255.0 / mse)
    }
}
