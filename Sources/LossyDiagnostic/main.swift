import Foundation
import J2KCore
import J2KCodec
#if canImport(AppKit)
import AppKit
#endif

func diagnoseAppFlow() throws {
    #if canImport(AppKit)
    let candidates = [
        "/Users/raster/Downloads/blackbuck.bmp",
        "/Users/raster/Downloads/blackbuck-1.bmp"
    ]
    var bmpData: Data?
    var usedPath = ""
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            bmpData = try Data(contentsOf: URL(fileURLWithPath: path))
            usedPath = path
            break
        }
    }

    guard let imageData = bmpData else {
        print("No BMP found")
        return
    }

    guard let nsImage = NSImage(data: imageData),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("ERROR: Can't load BMP")
        return
    }

    let imgWidth = cgImage.width
    let imgHeight = cgImage.height
    print("Loaded \(usedPath): \(imgWidth)x\(imgHeight)")

    // Same as EncodeViewModel
    let bytesPerRow = imgWidth * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
    guard let context = CGContext(data: nil, width: imgWidth, height: imgHeight,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
    guard let pixelPtr = context.data else { return }

    let pixelCount = imgWidth * imgHeight
    var planarData = Data(count: pixelCount * 3)
    planarData.withUnsafeMutableBytes { outBuf in
        let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        let inp = pixelPtr.assumingMemoryBound(to: UInt8.self)
        for i in 0..<pixelCount {
            out[i] = inp[i * 4]
            out[pixelCount + i] = inp[i * 4 + 1]
            out[pixelCount * 2 + i] = inp[i * 4 + 2]
        }
    }

    // === TEST 1: Exact app settings from screenshot ===
    print("\n=== Test 1: App settings (q=0.9, decomp=5, tiles=256x256) ===")
    let components1 = (0..<3).map { c -> J2KComponent in
        let start = c * pixelCount
        return J2KComponent(index: c, bitDepth: 8, signed: false,
                           width: imgWidth, height: imgHeight,
                           data: planarData.subdata(in: start..<start+pixelCount))
    }
    let j2kImage1 = J2KImage(width: imgWidth, height: imgHeight, components: components1,
                              tileWidth: 256, tileHeight: 256)

    let encConfig1 = J2KEncodingConfiguration(
        quality: 0.9, lossless: false, decompositionLevels: 5,
        codeBlockSize: (width: 32, height: 32), qualityLayers: 5,
        progressionOrder: .lrcp,
        tileSize: (width: 256, height: 256), useHTJ2K: false
    )
    let encoder1 = J2KEncoder(encodingConfiguration: encConfig1)
    let encoded1 = try encoder1.encode(j2kImage1)
    print("Encoded: \(encoded1.count) bytes (\(String(format: "%.1f", Double(encoded1.count)/1024)) KB)")

    // Save the raw J2K codestream for external decoder testing
    try encoded1.write(to: URL(fileURLWithPath: "/tmp/j2k_test_output.j2k"))
    print("Saved codestream: /tmp/j2k_test_output.j2k")

    // Hex dump the header (first 80 bytes) for conformance inspection
    print("\nCodestream header hex dump:")
    let headerBytes = min(80, encoded1.count)
    let hexLine = encoded1.prefix(headerBytes).map { String(format: "%02X", $0) }
    for i in stride(from: 0, to: hexLine.count, by: 16) {
        let end = min(i + 16, hexLine.count)
        let offset = String(format: "%04X", i)
        print("  \(offset): \(hexLine[i..<end].joined(separator: " "))")
    }

    // Parse and print QCD step sizes from codestream
    print("\nQCD step sizes (from codestream):")
    // Find QCD marker (FF 5C)
    for i in 0..<(encoded1.count - 3) {
        if encoded1[i] == 0xFF && encoded1[i+1] == 0x5C {
            let sqcd = encoded1[i+4]
            let guardBits = Int(sqcd >> 5) & 7
            let quantStyle = Int(sqcd & 0x1F)
            print("  Guard bits: \(guardBits), Quant style: \(quantStyle)")
            if quantStyle == 2 {
                var pos = i + 5
                let bitDepth = 8
                // LL
                let llWord = UInt16(encoded1[pos]) << 8 | UInt16(encoded1[pos+1])
                let llEps = Int(llWord >> 11) & 0x1F
                let llMant = Int(llWord & 0x7FF)
                let llStep = pow(2.0, Double(bitDepth - llEps)) * (1.0 + Double(llMant) / 2048.0)
                print("  LL_0: eps=\(llEps) mant=\(llMant) step=\(String(format: "%.6f", llStep))")
                pos += 2
                for level in 1...5 {
                    for sb in ["HL", "LH", "HH"] {
                        let w = UInt16(encoded1[pos]) << 8 | UInt16(encoded1[pos+1])
                        let eps = Int(w >> 11) & 0x1F
                        let mant = Int(w & 0x7FF)
                        let step = pow(2.0, Double(bitDepth - eps)) * (1.0 + Double(mant) / 2048.0)
                        print("  \(sb)_\(level): eps=\(eps) mant=\(mant) step=\(String(format: "%.6f", step))")
                        pos += 2
                    }
                }
            }
            break
        }
    }

    let decoder1 = J2KDecoder()
    let decoded1 = try decoder1.decode(encoded1)
    print("Decoded: \(decoded1.width)x\(decoded1.height), \(decoded1.components.count) comp")

    // Build planar from decoded
    let dw1 = decoded1.width, dh1 = decoded1.height, dc1 = decoded1.componentCount
    let dpx1 = dw1 * dh1
    var decodedPlanar1 = Data(count: dpx1 * dc1)
    decodedPlanar1.withUnsafeMutableBytes { outBuf in
        let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        for c in 0..<min(dc1, decoded1.components.count) {
            let comp = decoded1.components[c]
            comp.data.withUnsafeBytes { compBuf in
                let inp = compBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let count = min(dpx1, comp.data.count)
                for i in 0..<count { out[c * dpx1 + i] = inp[i] }
            }
        }
    }

    for c in 0..<3 {
        var err: Int64 = 0
        let n = min(pixelCount, dpx1)
        for i in 0..<n {
            err += Int64(abs(Int(planarData[c * pixelCount + i]) - Int(decodedPlanar1[c * dpx1 + i])))
        }
        print("Component \(c) MAE: \(String(format: "%.2f", Double(err)/Double(n)))")
    }

    // Save as PNG
    var rgbaData = Data(count: dpx1 * 4)
    rgbaData.withUnsafeMutableBytes { outBuf in
        let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
        decodedPlanar1.withUnsafeBytes { inBuf in
            let inp = inBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<dpx1 {
                out[i * 4] = inp[i]
                out[i * 4 + 1] = inp[dpx1 + i]
                out[i * 4 + 2] = inp[dpx1 * 2 + i]
                out[i * 4 + 3] = 255
            }
        }
    }

    let outCS = CGColorSpaceCreateDeviceRGB()
    let outBI = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    if let prov = CGDataProvider(data: rgbaData as CFData),
       let outCG = CGImage(width: dw1, height: dh1, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: dw1 * 4, space: outCS, bitmapInfo: outBI,
                           provider: prov, decode: nil, shouldInterpolate: false,
                           intent: .defaultIntent) {
        let outNS = NSImage(cgImage: outCG, size: NSSize(width: dw1, height: dh1))
        if let tiff = outNS.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/j2k_tiled_output.png"))
            print("Saved: /tmp/j2k_tiled_output.png")
        }
    }

    // === TEST 2: No tiling (same quality/decomp) ===
    print("\n=== Test 2: No tiling (q=0.9, decomp=5) ===")
    let j2kImage2 = J2KImage(width: imgWidth, height: imgHeight, components: components1)
    let encConfig2 = J2KEncodingConfiguration(
        quality: 0.9, lossless: false, decompositionLevels: 5
    )
    let encoded2 = try J2KEncoder(encodingConfiguration: encConfig2).encode(j2kImage2)
    let decoded2 = try J2KDecoder().decode(encoded2)
    print("Encoded: \(encoded2.count) bytes, Decoded: \(decoded2.width)x\(decoded2.height)")
    for c in 0..<3 {
        var err: Int64 = 0
        let n = min(pixelCount, decoded2.components[c].data.count)
        for i in 0..<n {
            err += Int64(abs(Int(planarData[c * pixelCount + i]) - Int(decoded2.components[c].data[i])))
        }
        print("Component \(c) MAE: \(String(format: "%.2f", Double(err)/Double(n)))")
    }

    // === TEST 3: Lossless ===
    print("\n=== Test 3: Lossless (5/3, decomp=5) ===")
    let encConfig3 = J2KEncodingConfiguration(
        quality: 1.0, lossless: true, decompositionLevels: 5
    )
    let encoded3 = try J2KEncoder(encodingConfiguration: encConfig3).encode(j2kImage2)
    let decoded3 = try J2KDecoder().decode(encoded3)
    print("Encoded: \(encoded3.count) bytes, Decoded: \(decoded3.width)x\(decoded3.height)")
    for c in 0..<3 {
        var err: Int64 = 0
        let n = min(pixelCount, decoded3.components[c].data.count)
        for i in 0..<n {
            err += Int64(abs(Int(planarData[c * pixelCount + i]) - Int(decoded3.components[c].data[i])))
        }
        print("Component \(c) MAE: \(String(format: "%.2f", Double(err)/Double(n)))")
    }

    #else
    print("AppKit not available")
    #endif
}

do {
    try diagnoseAppFlow()
} catch {
    print("ERROR: \(error)")
}
