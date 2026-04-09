//
// DiagTest — Diagnose lossy encode/decode issue
//

import Foundation
import J2KCore
import J2KCodec

// Test 1: Step size encode/decode round-trip
print("=== Test 1: Step Size Encode/Decode ===")
do {
    let quality = 0.9
    let qualityClamped = max(0.0, min(1.0, quality))
    let baseStep = 16.0 * pow(0.1 / 16.0, qualityClamped)

    for (name, sub, level) in [("LL_0", J2KSubband.ll, 0), ("HL_1", J2KSubband.hl, 1),
                                ("HL_2", J2KSubband.hl, 2), ("HH_1", J2KSubband.hh, 1)] as [(String, J2KSubband, Int)] {
        let step = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: baseStep, subband: sub,
            decompositionLevel: level, totalLevels: 2, reversible: false)
        let (exp, mant) = J2KStepSizeCalculator.encodeStepSize(step)
        let decoded = pow(2.0, Double(exp) - 16.0) * (1.0 + Double(mant) / 2048.0)
        print("  \(name): step=\(String(format: "%.6f", step)) encoded=(\(exp),\(mant)) decoded=\(String(format: "%.6f", decoded))")
    }
}
print()

// Test 2: Constant image — should have near-zero error
print("=== Test 2: 4x4 Solid 128 (lossy, q=0.9, 1 level) ===")
do {
    let width = 4, height = 4
    let pixels = [UInt8](repeating: 128, count: width * height)
    let data = Data(pixels)

    let component = J2KComponent(
        index: 0, bitDepth: 8, signed: false,
        width: width, height: height,
        subsamplingX: 1, subsamplingY: 1, data: data)
    let image = J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)

    let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 1)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(image)
    print("  Encoded: \(encoded.count) bytes")

    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)

    let origData = Array(image.components[0].data)
    let decData = Array(decoded.components[0].data)
    print("  Original: \(origData.map { Int($0) })")
    print("  Decoded:  \(decData.map { Int($0) })")

    let mae = zip(origData, decData).map { abs(Int($0) - Int($1)) }.reduce(0, +)
    print("  MAE: \(Double(mae) / Double(origData.count))")
}
print()

// Test 3: Gradient image
print("=== Test 3: 8x8 Gradient (lossy, q=0.9, 2 levels) ===")
do {
    let width = 8, height = 8
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels[y * width + x] = UInt8((x * 255) / max(1, width - 1))
        }
    }
    let data = Data(pixels)

    let component = J2KComponent(
        index: 0, bitDepth: 8, signed: false,
        width: width, height: height,
        subsamplingX: 1, subsamplingY: 1, data: data)
    let image = J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)

    let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(image)
    print("  Encoded: \(encoded.count) bytes")

    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)

    let origData = Array(image.components[0].data)
    let decData = Array(decoded.components[0].data)
    print("  Original: \(origData.map { Int($0) })")
    print("  Decoded:  \(decData.map { Int($0) })")

    var totalErr = 0
    for i in 0..<origData.count {
        totalErr += abs(Int(origData[i]) - Int(decData[i]))
    }
    print("  MAE: \(Double(totalErr) / Double(origData.count))")
}
print()

// Test 4: Same gradient but LOSSLESS — verify it's perfect
print("=== Test 4: 8x8 Gradient (lossless, 2 levels) ===")
do {
    let width = 8, height = 8
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels[y * width + x] = UInt8((x * 255) / max(1, width - 1))
        }
    }
    let data = Data(pixels)

    let component = J2KComponent(
        index: 0, bitDepth: 8, signed: false,
        width: width, height: height,
        subsamplingX: 1, subsamplingY: 1, data: data)
    let image = J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)

    let config = J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: 2)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(image)
    print("  Encoded: \(encoded.count) bytes")

    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)

    let origData = Array(image.components[0].data)
    let decData = Array(decoded.components[0].data)
    print("  Original: \(origData.map { Int($0) })")
    print("  Decoded:  \(decData.map { Int($0) })")

    var totalErr = 0
    for i in 0..<origData.count {
        totalErr += abs(Int(origData[i]) - Int(decData[i]))
    }
    print("  MAE: \(Double(totalErr) / Double(origData.count))")
}
print()

// Test 5: 16x16 gradient — matches PipelineTest config
print("=== Test 5: 16x16 Gradient (lossy, q=0.9, 2 levels) ===")
do {
    let width = 16, height = 16
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels[y * width + x] = UInt8((x * 255) / max(1, width - 1))
        }
    }
    let data = Data(pixels)

    let component = J2KComponent(
        index: 0, bitDepth: 8, signed: false,
        width: width, height: height,
        subsamplingX: 1, subsamplingY: 1, data: data)
    let image = J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)

    let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(image)
    print("  Encoded: \(encoded.count) bytes")

    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)

    let origData = Array(image.components[0].data)
    let decData = Array(decoded.components[0].data)
    print("  Original (first 16): \(origData.prefix(16).map { Int($0) })")
    print("  Decoded  (first 16): \(decData.prefix(16).map { Int($0) })")

    var totalErr = 0
    for i in 0..<origData.count {
        totalErr += abs(Int(origData[i]) - Int(decData[i]))
    }
    print("  MAE: \(Double(totalErr) / Double(origData.count))")
}
print()

// Test 6: Try different sizes with 1 decomposition level
print("=== Test 6: Size sweep with 1 decomp level ===")
for sz in [4, 8, 16, 32, 64] {
    do {
        var pixels = [UInt8](repeating: 0, count: sz * sz)
        for y in 0..<sz {
            for x in 0..<sz {
                pixels[y * sz + x] = UInt8((x * 255) / max(1, sz - 1))
            }
        }
        let data = Data(pixels)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: sz, height: sz,
            subsamplingX: 1, subsamplingY: 1, data: data)
        let image = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)

        let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 1)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)

        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)

        let origData = Array(image.components[0].data)
        let decData = Array(decoded.components[0].data)
        var totalErr = 0
        for i in 0..<origData.count {
            totalErr += abs(Int(origData[i]) - Int(decData[i]))
        }
        let mae = Double(totalErr) / Double(origData.count)
        print("  1-level \(sz)x\(sz): MAE=\(String(format: "%.2f", mae)), encoded=\(encoded.count) bytes")
    } catch {
        print("  1-level \(sz)x\(sz): ERROR: \(error)")
    }
}
print()

// Test 7: Try different sizes with 2 decomp levels, lossless
print("=== Test 7: Size sweep with 2 decomp levels, LOSSLESS ===")
for sz in [4, 8, 12, 16, 32] {
    do {
        var pixels = [UInt8](repeating: 0, count: sz * sz)
        for y in 0..<sz {
            for x in 0..<sz {
                pixels[y * sz + x] = UInt8((x * 255) / max(1, sz - 1))
            }
        }
        let data = Data(pixels)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: sz, height: sz,
            subsamplingX: 1, subsamplingY: 1, data: data)
        let image = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)

        let config = J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: 2)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)

        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)

        let origData = Array(image.components[0].data)
        let decData = Array(decoded.components[0].data)
        var totalErr = 0
        for i in 0..<origData.count {
            totalErr += abs(Int(origData[i]) - Int(decData[i]))
        }
        let mae = Double(totalErr) / Double(origData.count)
        print("  lossless 2-lvl \(sz)x\(sz): MAE=\(String(format: "%.2f", mae))")
    } catch {
        print("  lossless 2-lvl \(sz)x\(sz): ERROR: \(error)")
    }
}
print()

// Test 8: Staged diagnostics for 12x12 lossy 2-level
print("=== Test 8: Stage-by-stage 12x12 lossy 2-level ===")
do {
    let sz = 12
    // Build gradient image, level-shift to signed
    var image2D = [[Int32]](repeating: [Int32](repeating: 0, count: sz), count: sz)
    var origPixels = [UInt8](repeating: 0, count: sz * sz)
    for y in 0..<sz {
        for x in 0..<sz {
            let val = UInt8((x * 255) / max(1, sz - 1))
            origPixels[y * sz + x] = val
            image2D[y][x] = Int32(val) - 128 // level shift
        }
    }

    // Stage A: DWT round-trip only (no quantization)
    let decomp = try J2KDWT2D.forwardDecomposition(image: image2D, levels: 2, filter: .irreversible97)
    let reconA = try J2KDWT2D.inverseDecomposition(decomposition: decomp, filter: .irreversible97)
    var maeA = 0.0
    var maxErrA = 0
    for y in 0..<sz {
        for x in 0..<sz {
            let err = abs(Int(image2D[y][x]) - Int(reconA[y][x]))
            maeA += Double(err)
            maxErrA = max(maxErrA, err)
        }
    }
    maeA /= Double(sz * sz)
    print("  Stage A (DWT round-trip only): MAE=\(String(format: "%.4f", maeA)), maxErr=\(maxErrA)")

    // Stage B: DWT → quantize → dequantize → IDWT
    let quality = 0.9
    let baseStep = 16.0 * pow(0.1 / 16.0, quality)

    // Quantize each subband
    var quantizedLevels = decomp.levels.enumerated().map { (levelIdx, level) -> (hl: [[Int32]], lh: [[Int32]], hh: [[Int32]]) in
        let decompLevel = levelIdx + 1
        func quantize2D(_ data: [[Int32]], subband: J2KSubband) -> [[Int32]] {
            let step = J2KStepSizeCalculator.calculateStepSize(
                baseStepSize: baseStep, subband: subband,
                decompositionLevel: decompLevel, totalLevels: 2, reversible: false)
            return data.map { row in
                row.map { coeff in
                    let sign: Int32 = coeff >= 0 ? 1 : -1
                    let mag = abs(coeff)
                    let q = Int32(Double(mag) / step)
                    return sign * q
                }
            }
        }
        return (hl: quantize2D(level.hl, subband: .hl),
                lh: quantize2D(level.lh, subband: .lh),
                hh: quantize2D(level.hh, subband: .hh))
    }

    // Quantize LL
    let llStep = J2KStepSizeCalculator.calculateStepSize(
        baseStepSize: baseStep, subband: .ll, decompositionLevel: 0, totalLevels: 2, reversible: false)
    let quantizedLL = decomp.coarsestLL.map { row in
        row.map { coeff -> Int32 in
            let sign: Int32 = coeff >= 0 ? 1 : -1
            let mag = abs(coeff)
            let q = Int32(Double(mag) / llStep)
            return sign * q
        }
    }

    // Dequantize
    func dequantize2D(_ data: [[Int32]], subband: J2KSubband, decompLevel: Int) -> [[Int32]] {
        let step = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: baseStep, subband: subband,
            decompositionLevel: decompLevel, totalLevels: 2, reversible: false)
        return data.map { row in row.map { Int32(Double($0) * step) } }
    }

    let dequantLL = dequantize2D(quantizedLL, subband: .ll, decompLevel: 0)

    // Build a new decomposition with dequantized coefficients for IDWT
    var dequantResults: [J2KDWT2D.DecompositionResult] = []
    for (levelIdx, _) in decomp.levels.enumerated() {
        let decompLevel = levelIdx + 1
        let dqHL = dequantize2D(quantizedLevels[levelIdx].hl, subband: .hl, decompLevel: decompLevel)
        let dqLH = dequantize2D(quantizedLevels[levelIdx].lh, subband: .lh, decompLevel: decompLevel)
        let dqHH = dequantize2D(quantizedLevels[levelIdx].hh, subband: .hh, decompLevel: decompLevel)
        dequantResults.append(J2KDWT2D.DecompositionResult(ll: [[0]], lh: dqLH, hl: dqHL, hh: dqHH))
    }

    // Manual multi-level IDWT from coarsest to finest
    var currentLL = dequantLL
    for levelIdx in (0..<decomp.levels.count).reversed() {
        currentLL = try J2KDWT2D.inverseTransform(
            ll: currentLL,
            lh: dequantResults[levelIdx].lh,
            hl: dequantResults[levelIdx].hl,
            hh: dequantResults[levelIdx].hh,
            filter: .irreversible97
        )
    }

    var maeB = 0.0
    var maxErrB = 0
    for y in 0..<sz {
        for x in 0..<sz {
            let err = abs(Int(image2D[y][x]) - Int(currentLL[y][x]))
            maeB += Double(err)
            maxErrB = max(maxErrB, err)
        }
    }
    maeB /= Double(sz * sz)
    print("  Stage B (DWT+quant+dequant+IDWT): MAE=\(String(format: "%.4f", maeB)), maxErr=\(maxErrB)")

    // Stage C: Full pipeline encode/decode
    let data = Data(origPixels)
    let component = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                  width: sz, height: sz, subsamplingX: 1, subsamplingY: 1, data: data)
    let j2kImage = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)
    let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(j2kImage)
    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)
    let decData = Array(decoded.components[0].data)

    var maeC = 0.0
    var maxErrC = 0
    for i in 0..<origPixels.count {
        let err = abs(Int(origPixels[i]) - Int(decData[i]))
        maeC += Double(err)
        maxErrC = max(maxErrC, err)
    }
    maeC /= Double(origPixels.count)
    print("  Stage C (full pipeline):           MAE=\(String(format: "%.4f", maeC)), maxErr=\(maxErrC)")

    // Print first row comparison
    print("  Original row 0: \(origPixels[0..<sz].map { Int($0) })")
    print("  Decoded  row 0: \(decData[0..<sz].map { Int($0) })")
    print("  StageB   row 0: \(currentLL[0].map { Int($0) + 128 })")
} catch {
    print("  ERROR: \(error)")
}
print()

// Test 9: Lossy 2-level size sweep (fine-grained)
print("=== Test 9: 2-level lossy sweep (8..16) ===")
for sz in [8, 9, 10, 11, 12, 13, 14, 15, 16] {
    do {
        var pixels = [UInt8](repeating: 0, count: sz * sz)
        for y in 0..<sz { for x in 0..<sz { pixels[y * sz + x] = UInt8((x * 255) / max(1, sz - 1)) } }
        let data = Data(pixels)
        let component = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                      width: sz, height: sz, subsamplingX: 1, subsamplingY: 1, data: data)
        let image = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)
        let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        let origData = Array(image.components[0].data)
        let decData = Array(decoded.components[0].data)
        var totalErr = 0
        for i in 0..<origData.count { totalErr += abs(Int(origData[i]) - Int(decData[i])) }
        let mae = Double(totalErr) / Double(origData.count)
        print("  2-lvl lossy \(sz)x\(sz): MAE=\(String(format: "%.2f", mae))")
    } catch {
        print("  2-lvl lossy \(sz)x\(sz): ERROR: \(error)")
    }
}
print()

// Test 10: EBCOT encode/decode roundtrip for each subband individually
// This isolates EBCOT from the codestream packet layer
print("=== Test 10: EBCOT roundtrip per-subband (9x9 lossy 2-level) ===")
do {
    let sz = 9
    var image2D = [[Int32]](repeating: [Int32](repeating: 0, count: sz), count: sz)
    for y in 0..<sz {
        for x in 0..<sz {
            let val = UInt8((x * 255) / max(1, sz - 1))
            image2D[y][x] = Int32(val) - 128
        }
    }

    let decomp = try J2KDWT2D.forwardDecomposition(image: image2D, levels: 2, filter: .irreversible97)

    let quality = 0.9
    let baseStep = 16.0 * pow(0.1 / 16.0, quality)
    let params = J2KQuantizationParameters.fromQuality(quality)
    let quantizer = J2KQuantizer(parameters: params)

    // Test each subband's EBCOT encode/decode
    let cbEncoder = CodeBlockEncoder()
    let cbDecoder = CodeBlockDecoder()

    // Helper
    func testSubband(_ label: String, coeffs2D: [[Int32]], subband: J2KSubband, decompLevel: Int) throws {
        let w = coeffs2D[0].count
        let h = coeffs2D.count
        let flat = coeffs2D.flatMap { $0 }

        // Quantize
        let quantized = try quantizer.quantize(
            coefficients: flat, subband: subband,
            decompositionLevel: decompLevel, totalLevels: 2)

        // Compute K_b (same as encoder)
        let stepSize = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: baseStep, subband: subband,
            decompositionLevel: decompLevel, totalLevels: 2, reversible: false)
        let subbandGain: Int
        switch subband {
        case .ll: subbandGain = 0
        case .hl, .lh: subbandGain = 1
        case .hh: subbandGain = 2
        }
        let epsilon = 8 + subbandGain - Int(floor(log2(stepSize)))
        let bitDepth = epsilon + 2 - 1 // guardBits=2

        // EBCOT encode
        let encoded = try cbEncoder.encode(
            coefficients: quantized, width: w, height: h,
            subband: subband, bitDepth: bitDepth)

        // EBCOT decode
        let codeBlock = J2KCodeBlock(
            index: 0, x: 0, y: 0, width: w, height: h,
            subband: subband, data: encoded.data,
            passeCount: encoded.passeCount,
            zeroBitPlanes: encoded.zeroBitPlanes)
        let decoded = try cbDecoder.decode(codeBlock: codeBlock, bitDepth: bitDepth)

        // Compare
        var totalErr = 0
        var maxErr = 0
        for i in 0..<quantized.count {
            let err = abs(Int(quantized[i]) - Int(decoded[i]))
            totalErr += err
            maxErr = max(maxErr, err)
        }
        let mae = quantized.isEmpty ? 0.0 : Double(totalErr) / Double(quantized.count)
        let maxQ = quantized.map { abs(Int($0)) }.max() ?? 0
        print("  \(label) (\(w)x\(h)): MAE=\(String(format: "%.4f", mae)), maxErr=\(maxErr), maxQ=\(maxQ), passes=\(encoded.passeCount), zbp=\(encoded.zeroBitPlanes), K_b=\(bitDepth), bytes=\(encoded.data.count)")
    }

    // LL subband
    try testSubband("LL_0", coeffs2D: decomp.coarsestLL, subband: .ll, decompLevel: 0)

    // Level 2 subbands (coarsest detail) - index 1 in decomp.levels
    try testSubband("HL_2", coeffs2D: decomp.levels[1].hl, subband: .hl, decompLevel: 2)
    try testSubband("LH_2", coeffs2D: decomp.levels[1].lh, subband: .lh, decompLevel: 2)
    try testSubband("HH_2", coeffs2D: decomp.levels[1].hh, subband: .hh, decompLevel: 2)

    // Level 1 subbands (finest detail) - index 0 in decomp.levels
    try testSubband("HL_1", coeffs2D: decomp.levels[0].hl, subband: .hl, decompLevel: 1)
    try testSubband("LH_1", coeffs2D: decomp.levels[0].lh, subband: .lh, decompLevel: 1)
    try testSubband("HH_1", coeffs2D: decomp.levels[0].hh, subband: .hh, decompLevel: 1)
} catch {
    print("  ERROR: \(error)")
}
print()

// Test 11: Hex dump of encoded codestream for 9x9 lossy 2-level
print("=== Test 11: Codestream analysis for 9x9 lossy 2-level ===")
do {
    let sz = 9
    var pixels = [UInt8](repeating: 0, count: sz * sz)
    for y in 0..<sz {
        for x in 0..<sz {
            pixels[y * sz + x] = UInt8((x * 255) / max(1, sz - 1))
        }
    }
    let data = Data(pixels)
    let component = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                  width: sz, height: sz, subsamplingX: 1, subsamplingY: 1, data: data)
    let image = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)
    let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2, enableParallelCodeBlocks: false)
    let encoder = J2KEncoder(encodingConfiguration: config)
    let encoded = try encoder.encode(image)

    print("  Total encoded bytes: \(encoded.count)")

    // Find SOD marker (0xFF93) - marks start of tile data
    var sodPos = -1
    for i in 0..<(encoded.count - 1) {
        if encoded[i] == 0xFF && encoded[i+1] == 0x93 {
            sodPos = i + 2
            break
        }
    }
    print("  SOD data starts at byte \(sodPos)")

    if sodPos >= 0 {
        let tileData = encoded.subdata(in: sodPos..<(encoded.count - 2)) // exclude EOC marker
        print("  Tile data length: \(tileData.count) bytes")
        print("  Tile data hex: \(tileData.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))...")
    }
} catch {
    print("  ERROR: \(error)")
}
print()

// Test 12: Larger image tests
print("=== Test 12: Larger images ===")
for (sz, levels) in [(64, 2), (128, 2), (128, 3), (256, 3)] as [(Int, Int)] {
    do {
        var pixels = [UInt8](repeating: 0, count: sz * sz)
        for y in 0..<sz { for x in 0..<sz {
            pixels[y * sz + x] = UInt8((x * 255) / max(1, sz - 1))
        }}
        let data = Data(pixels)
        let component = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                      width: sz, height: sz, subsamplingX: 1, subsamplingY: 1, data: data)
        let image = J2KImage(width: sz, height: sz, components: [component], colorSpace: .grayscale)
        let config = J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: levels, enableParallelCodeBlocks: false)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        let origData = Array(image.components[0].data)
        let decData = Array(decoded.components[0].data)
        var totalErr = 0
        var maxErr = 0
        for i in 0..<origData.count {
            let err = abs(Int(origData[i]) - Int(decData[i]))
            totalErr += err
            maxErr = max(maxErr, err)
        }
        let mae = Double(totalErr) / Double(origData.count)
        print("  \(sz)x\(sz) \(levels)-level lossy: MAE=\(String(format: "%.2f", mae)), maxErr=\(maxErr)")
    } catch {
        print("  \(sz)x\(sz) \(levels)-level lossy: ERROR: \(error)")
    }
}