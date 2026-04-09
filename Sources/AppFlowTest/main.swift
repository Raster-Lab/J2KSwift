//
// main.swift
// AppFlowTest
//
// End-to-end validation of the J2KTestApp encode→decode→preview flow.
// Exercises the exact code paths used by EncodeView and DecodeView.
//
// Run with: swift run AppFlowTest
//

#if canImport(AppKit)
import Foundation
import AppKit
import J2KCore
import J2KCodec

// MARK: - Test infrastructure

nonisolated(unsafe) var passCount = 0
nonisolated(unsafe) var failCount = 0

func test(_ name: String, _ body: () throws -> Void) {
    print("\nTest: \(name)")
    do {
        try body()
        passCount += 1
        print("  ✅ PASS")
    } catch {
        failCount += 1
        print("  ❌ FAIL: \(error)")
    }
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}

// MARK: - Helper: same as DecodeViewModel.rawPixelsToPNGData

func rawPixelsToPNGData(_ pixelData: Data, width: Int, height: Int, components: Int) -> Data? {
    let pixelCount = width * height
    guard pixelData.count >= pixelCount * components else { return nil }

    var rgbaData = Data(count: pixelCount * 4)
    rgbaData.withUnsafeMutableBytes { outBuf in
        let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        pixelData.withUnsafeBytes { inBuf in
            let inp = inBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<pixelCount {
                if components >= 3 {
                    out[i * 4] = inp[i]
                    out[i * 4 + 1] = inp[pixelCount + i]
                    out[i * 4 + 2] = inp[pixelCount * 2 + i]
                } else {
                    let g = inp[i]
                    out[i * 4] = g; out[i * 4 + 1] = g; out[i * 4 + 2] = g
                }
                out[i * 4 + 3] = 255
            }
        }
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let provider = CGDataProvider(data: rgbaData as CFData),
          let cgImg = CGImage(
              width: width, height: height,
              bitsPerComponent: 8, bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: cs, bitmapInfo: bi,
              provider: provider, decode: nil,
              shouldInterpolate: false, intent: .defaultIntent
          ) else { return nil }

    let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: width, height: height))
    return nsImg.tiffRepresentation.flatMap {
        NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
    }
}

// MARK: - Helper: same as EncodeViewModel.encode CGImage parsing

func parseCGImageToPlanar(from imageData: Data) -> (Data, Int, Int, Int)? {
    guard let nsImage = NSImage(data: imageData),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    let w = cgImage.width
    let h = cgImage.height
    let bytesPerRow = w * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

    guard let context = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace, bitmapInfo: bitmapInfo
    ), let pixelData = context.data else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    let pixelCount = w * h
    let comps = 3
    var planar = Data(count: pixelCount * comps)
    planar.withUnsafeMutableBytes { outBuf in
        let outPtr = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        let inPtr = pixelData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<pixelCount {
            outPtr[i] = inPtr[i * 4]
            outPtr[pixelCount + i] = inPtr[i * 4 + 1]
            outPtr[pixelCount * 2 + i] = inPtr[i * 4 + 2]
        }
    }
    return (planar, w, h, comps)
}

// MARK: - Helper: same as CodecService

func encodeImage(pixelData: Data, width: Int, height: Int, componentCount: Int,
                 quality: Double = 0.9, lossless: Bool = false) throws -> Data {
    var comps: [J2KComponent] = []
    let pixelCount = width * height
    for c in 0..<componentCount {
        let start = c * pixelCount
        let end = min(start + pixelCount, pixelData.count)
        comps.append(J2KComponent(
            index: c, bitDepth: 8, signed: false,
            width: width, height: height,
            data: pixelData.subdata(in: start..<end)
        ))
    }
    let image = J2KImage(width: width, height: height, components: comps)
    let config = J2KEncodingConfiguration(
        quality: quality, lossless: lossless, decompositionLevels: 5,
        codeBlockSize: (width: 32, height: 32), qualityLayers: 5,
        progressionOrder: .lrcp
    )
    let encoder = J2KEncoder(encodingConfiguration: config)
    return try encoder.encode(image)
}

func decodeImage(codestream: Data) throws -> (Data, Int, Int, Int) {
    let decoder = J2KDecoder()
    let image = try decoder.decode(codestream)
    let w = image.width
    let h = image.height
    let c = image.componentCount
    let pixelCount = w * h
    var planar = Data(count: pixelCount * c)
    planar.withUnsafeMutableBytes { outBuf in
        let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        for ci in 0..<min(c, image.components.count) {
            let comp = image.components[ci]
            comp.data.withUnsafeBytes { compBuf in
                let inp = compBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let count = min(pixelCount, comp.data.count)
                for i in 0..<count {
                    out[ci * pixelCount + i] = inp[i]
                }
            }
        }
    }
    return (planar, w, h, c)
}

// MARK: - Tests

print("╔══════════════════════════════════════════════════╗")
print("║  J2KTestApp Flow Validation                     ║")
print("╚══════════════════════════════════════════════════╝")

// --- Test 1: Create a BMP, load it, encode, decode, make PNG preview ---

test("BMP → Encode → Decode → PNG preview") {
    // Create a 64x64 BMP
    let w = 64, h = 64
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: w * 3, bitsPerPixel: 24
    ) else { throw TestError("Cannot create NSBitmapImageRep") }

    for y in 0..<h { for x in 0..<w {
        bitmapRep.setColor(NSColor(
            red: CGFloat(x) / 63, green: CGFloat(y) / 63, blue: 0.5, alpha: 1
        ), atX: x, y: y)
    }}

    guard let bmpData = bitmapRep.representation(using: .bmp, properties: [:]) else {
        throw TestError("Cannot create BMP data")
    }
    print("  BMP created: \(bmpData.count) bytes")

    // Parse BMP → planar pixels (same path as EncodeViewModel.encode)
    guard let (planar, pw, ph, pc) = parseCGImageToPlanar(from: bmpData) else {
        throw TestError("Cannot parse BMP via CGImage")
    }
    print("  Parsed: \(pw)×\(ph), \(pc) components, \(planar.count) bytes")

    // Encode
    let encoded = try encodeImage(pixelData: planar, width: pw, height: ph, componentCount: pc)
    print("  Encoded: \(encoded.count) bytes")

    // Decode
    let (decoded, dw, dh, dc) = try decodeImage(codestream: encoded)
    print("  Decoded: \(dw)×\(dh), \(dc) components")

    guard dw == pw && dh == ph else {
        throw TestError("Dimension mismatch: \(dw)×\(dh) vs \(pw)×\(ph)")
    }

    // Convert to PNG for display
    guard let pngData = rawPixelsToPNGData(decoded, width: dw, height: dh, components: dc) else {
        throw TestError("Cannot convert decoded pixels to PNG")
    }
    print("  PNG preview: \(pngData.count) bytes")

    // Verify NSImage can load it (this is what ImagePreviewView does)
    guard let nsImg = NSImage(data: pngData) else {
        throw TestError("NSImage CANNOT load the PNG preview!")
    }
    print("  NSImage loaded: \(nsImg.size) ← this is what ImagePreviewView displays")
}

// --- Test 2: Lossless round-trip with BMP input ---

test("Lossless BMP round-trip (MAE=0)") {
    let w = 32, h = 32
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: w * 3, bitsPerPixel: 24
    ) else { throw TestError("Cannot create bitmap") }

    for y in 0..<h { for x in 0..<w {
        bitmapRep.setColor(NSColor(
            red: CGFloat(x) / 31, green: CGFloat(y) / 31, blue: 0.3, alpha: 1
        ), atX: x, y: y)
    }}

    guard let bmpData = bitmapRep.representation(using: .bmp, properties: [:]),
          let (planar, pw, ph, pc) = parseCGImageToPlanar(from: bmpData) else {
        throw TestError("BMP creation/parse failed")
    }

    let encoded = try encodeImage(pixelData: planar, width: pw, height: ph,
                                   componentCount: pc, quality: 1.0, lossless: true)
    let (decoded, _, _, _) = try decodeImage(codestream: encoded)

    var totalError: Int64 = 0
    let count = min(planar.count, decoded.count)
    for i in 0..<count {
        totalError += Int64(abs(Int(planar[i]) - Int(decoded[i])))
    }
    let mae = Double(totalError) / Double(count)
    print("  MAE: \(mae)")
    guard mae == 0 else {
        throw TestError("Lossless round-trip NOT bit-exact! MAE=\(mae)")
    }
    print("  Bit-exact lossless ✓")
}

// --- Test 3: Input display data (NSImage can show original BMP) ---

test("NSImage can display input BMP directly") {
    let w = 16, h = 16
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: w * 3, bitsPerPixel: 24
    ) else { throw TestError("Cannot create bitmap") }
    for y in 0..<h { for x in 0..<w {
        bitmapRep.setColor(.gray, atX: x, y: y)
    }}
    guard let bmpData = bitmapRep.representation(using: .bmp, properties: [:]) else {
        throw TestError("BMP creation failed")
    }

    // ImagePreviewView does: NSImage(data: imageData)
    guard let img = NSImage(data: bmpData) else {
        throw TestError("NSImage cannot load BMP! ImagePreviewView will show 'No Image'")
    }
    print("  Input BMP displayable: \(img.size)")
}

// --- Test 4: Synthetic planar pixels → PNG display ---

test("Planar test image → PNG display (RoundTripView flow)") {
    let size = 64
    let pixelCount = size * size
    var data = Data(count: pixelCount * 3)
    data.withUnsafeMutableBytes { buffer in
        let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<size { for x in 0..<size {
            let i = y * size + x
            ptr[i] = UInt8(x * 255 / 63)
            ptr[pixelCount + i] = UInt8(y * 255 / 63)
            ptr[pixelCount * 2 + i] = 128
        }}
    }

    guard let pngData = rawPixelsToPNGData(data, width: size, height: size, components: 3) else {
        throw TestError("Cannot convert planar pixels to PNG")
    }
    guard let img = NSImage(data: pngData) else {
        throw TestError("NSImage cannot load synthetic PNG!")
    }
    print("  Synthetic image displayable: \(img.size), PNG size: \(pngData.count) bytes")
}

// --- Test 5: Save J2K, reload, decode, display ---

test("Save J2K → Load → Decode → Display") {
    let w = 32, h = 32, pixelCount = w * h
    var planar = Data(count: pixelCount * 3)
    planar.withUnsafeMutableBytes { buf in
        let p = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<pixelCount {
            p[i] = UInt8(i % 256)
            p[pixelCount + i] = UInt8((i * 2) % 256)
            p[pixelCount * 2 + i] = 128
        }
    }

    let encoded = try encodeImage(pixelData: planar, width: w, height: h, componentCount: 3)

    // Save and reload (simulates Save... dialog + Open File... in DecodeView)
    let tmpPath = "/tmp/j2k_appflow_test.j2k"
    try encoded.write(to: URL(fileURLWithPath: tmpPath))
    let reloaded = try Data(contentsOf: URL(fileURLWithPath: tmpPath))

    let (decoded, dw, dh, dc) = try decodeImage(codestream: reloaded)
    print("  Decoded saved file: \(dw)×\(dh), \(dc) comps")

    guard let pngData = rawPixelsToPNGData(decoded, width: dw, height: dh, components: dc) else {
        throw TestError("Cannot create PNG from decoded J2K")
    }
    guard let _ = NSImage(data: pngData) else {
        throw TestError("NSImage cannot display decoded J2K!")
    }
    print("  Decoded J2K → PNG display ✓")

    try? FileManager.default.removeItem(atPath: tmpPath)
}

// MARK: - Summary

print("\n╔══════════════════════════════════════════════════╗")
print("║  Results                                        ║")
print("╚══════════════════════════════════════════════════╝")
print("  \(passCount) passed, \(failCount) failed")
if failCount == 0 {
    print("\n✅ All app flow tests passed!")
} else {
    print("\n❌ Some tests failed!")
}

#else
print("AppFlowTest requires macOS with AppKit")
#endif
