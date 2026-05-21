//
// J2KImageRenderer.swift
// J2KBenchApp — image viewer
//
// Converts a decoded `J2KImage` into a displayable `CGImage`/`UIImage`.
// Handles the full range J2KSwift can decode: 1–4 planar components,
// 8-bit and >8-bit (12/16-bit medical), signed samples, big/little
// endian 16-bit data, chroma-subsampled components, and YCbCr.
//
// >8-bit grayscale is auto window/level-stretched (min→0, max→255) so
// medical images aren't a near-black frame; >8-bit colour is bit-shift
// reduced to keep the colour balance intact.

import Foundation
import CoreGraphics
import J2KCore

#if canImport(UIKit)
import UIKit
#endif

enum J2KImageRenderer {

    /// Render a decoded image to an 8-bit RGB `CGImage`. Returns `nil`
    /// for an empty image or a component with no sample data.
    static func cgImage(from image: J2KImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, !image.components.isEmpty,
              image.components.allSatisfy({ !$0.data.isEmpty })
        else { return nil }

        let cc = image.components.count
        let isGray = cc < 3
        let yCbCr = (image.colorSpace == .yCbCr) && cc >= 3

        // Normalised 8-bit planes, at each component's own resolution.
        let used = isGray ? 1 : 3
        let planes = (0..<used).map {
            plane(for: image.components[$0],
                  grayscaleWindow: isGray && image.components[$0].bitDepth > 8)
        }
        let dims = (0..<used).map {
            (image.components[$0].width, image.components[$0].height)
        }

        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = (y * w + x) * 4
                func sample(_ c: Int) -> Int {
                    let (cw, ch) = dims[c]
                    let sx = cw == w ? x : min(cw - 1, x * cw / w)
                    let sy = ch == h ? y : min(ch - 1, y * ch / h)
                    return Int(planes[c][sy * cw + sx])
                }
                if isGray {
                    let v = UInt8(sample(0))
                    rgba[o] = v; rgba[o + 1] = v; rgba[o + 2] = v
                } else if yCbCr {
                    let yy = Double(sample(0))
                    let cb = Double(sample(1)) - 128
                    let cr = Double(sample(2)) - 128
                    rgba[o]     = clamp8(yy + 1.402 * cr)
                    rgba[o + 1] = clamp8(yy - 0.344136 * cb - 0.714136 * cr)
                    rgba[o + 2] = clamp8(yy + 1.772 * cb)
                } else {
                    rgba[o]     = UInt8(sample(0))
                    rgba[o + 1] = UInt8(sample(1))
                    rgba[o + 2] = UInt8(sample(2))
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData)
        else { return nil }
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)
    }

    #if canImport(UIKit)
    static func uiImage(from image: J2KImage) -> UIImage? {
        cgImage(from: image).map { UIImage(cgImage: $0) }
    }
    #endif

    // MARK: - Per-component normalisation

    /// Decode one planar component to an 8-bit plane at its own
    /// resolution. `grayscaleWindow` enables the >8-bit min/max stretch.
    private static func plane(for comp: J2KComponent,
                              grayscaleWindow: Bool) -> [UInt8] {
        let count = max(0, comp.width * comp.height)
        let bd = comp.bitDepth
        let bytesPer = (bd + 7) / 8
        let maxVal = (1 << bd) - 1
        let signedOffset = comp.signed ? (1 << (bd - 1)) : 0
        let bigEndian = (comp.sampleByteOrder ?? .bigEndian) == .bigEndian

        var values = [Int](repeating: 0, count: count)
        comp.data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let avail = bytes.count
            for i in 0..<count {
                var v: Int
                if bytesPer <= 1 {
                    guard i < avail else { break }
                    v = comp.signed ? Int(Int8(bitPattern: bytes[i]))
                                     : Int(bytes[i])
                } else {
                    let off = i * 2
                    guard off + 1 < avail else { break }
                    let b0 = bytes[off], b1 = bytes[off + 1]
                    let u: UInt16 = bigEndian
                        ? (UInt16(b0) << 8 | UInt16(b1))
                        : (UInt16(b1) << 8 | UInt16(b0))
                    v = comp.signed ? Int(Int16(bitPattern: u)) : Int(u)
                }
                v += signedOffset
                values[i] = Swift.min(maxVal, Swift.max(0, v))
            }
        }

        var out = [UInt8](repeating: 0, count: count)
        if bd == 8 {
            for i in 0..<count { out[i] = UInt8(values[i]) }
        } else if bd < 8 {
            let denom = Swift.max(maxVal, 1)
            for i in 0..<count { out[i] = UInt8(values[i] * 255 / denom) }
        } else if grayscaleWindow {
            var lo = Int.max, hi = Int.min
            for v in values { lo = Swift.min(lo, v); hi = Swift.max(hi, v) }
            let range = hi - lo
            if range <= 0 {
                for i in 0..<count { out[i] = 128 }
            } else {
                for i in 0..<count {
                    out[i] = UInt8(Swift.min(255, Swift.max(0,
                        (values[i] - lo) * 255 / range)))
                }
            }
        } else {
            let shift = bd - 8
            for i in 0..<count {
                out[i] = UInt8(Swift.min(255, values[i] >> shift))
            }
        }
        return out
    }

    private static func clamp8(_ v: Double) -> UInt8 {
        UInt8(Swift.min(255, Swift.max(0, v.rounded())))
    }
}
