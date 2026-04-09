//
// main.swift
// PipelineTest
//
// Standalone test for the JPEG 2000 encode/decode pipeline.
// Run with: swift run PipelineTest [--save <path>]
//

import Foundation
import J2KCore
import J2KCodec

// MARK: - Test Helpers

func makeGrayscaleImage(width: Int, height: Int, pattern: String = "gradient") -> J2KImage {
    var data = Data(count: width * height)
    data.withUnsafeMutableBytes { buffer in
        let ptr = buffer.bindMemory(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                switch pattern {
                case "gradient":
                    ptr[idx] = UInt8((x * 255) / max(1, width - 1))
                case "checkerboard":
                    ptr[idx] = ((x / 8 + y / 8) % 2 == 0) ? UInt8(200) : UInt8(50)
                case "solid":
                    ptr[idx] = 128
                default:
                    ptr[idx] = UInt8((x + y) % 256)
                }
            }
        }
    }

    let component = J2KComponent(
        index: 0, bitDepth: 8, signed: false,
        width: width, height: height,
        subsamplingX: 1, subsamplingY: 1, data: data
    )
    return J2KImage(width: width, height: height, components: [component],
                    colorSpace: .grayscale)
}

func makeRGBImage(width: Int, height: Int) -> J2KImage {
    func componentData(channel: Int) -> Data {
        var data = Data(count: width * height)
        data.withUnsafeMutableBytes { buffer in
            let ptr = buffer.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * width + x
                    switch channel {
                    case 0: // Red: horizontal gradient
                        ptr[idx] = UInt8((x * 255) / max(1, width - 1))
                    case 1: // Green: vertical gradient
                        ptr[idx] = UInt8((y * 255) / max(1, height - 1))
                    case 2: // Blue: diagonal
                        ptr[idx] = UInt8(((x + y) * 255) / max(1, width + height - 2))
                    default:
                        ptr[idx] = 128
                    }
                }
            }
        }
        return data
    }

    let components = (0..<3).map { ch in
        J2KComponent(
            index: ch, bitDepth: 8, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: componentData(channel: ch)
        )
    }
    return J2KImage(width: width, height: height, components: components, colorSpace: .sRGB)
}

func computeMAE(original: Data, decoded: Data) -> Double {
    let count = min(original.count, decoded.count)
    guard count > 0 else { return Double.infinity }
    var totalError: Int = 0
    original.withUnsafeBytes { origBuf in
        decoded.withUnsafeBytes { decBuf in
            let op = origBuf.bindMemory(to: UInt8.self)
            let dp = decBuf.bindMemory(to: UInt8.self)
            for i in 0..<count {
                totalError += abs(Int(op[i]) - Int(dp[i]))
            }
        }
    }
    return Double(totalError) / Double(count)
}

func computePSNR(original: Data, decoded: Data, maxVal: Int = 255) -> Double {
    let count = min(original.count, decoded.count)
    guard count > 0 else { return 0 }
    var mse: Double = 0
    original.withUnsafeBytes { origBuf in
        decoded.withUnsafeBytes { decBuf in
            let op = origBuf.bindMemory(to: UInt8.self)
            let dp = decBuf.bindMemory(to: UInt8.self)
            for i in 0..<count {
                let diff = Double(Int(op[i]) - Int(dp[i]))
                mse += diff * diff
            }
        }
    }
    mse /= Double(count)
    if mse == 0 { return Double.infinity }
    return 10.0 * log10(Double(maxVal * maxVal) / mse)
}

// MARK: - Test Runner

struct TestResult {
    let name: String
    let passed: Bool
    let error: String?
    let encodedSize: Int?
    let mae: Double?
    let psnr: Double?
    let encodeTime: TimeInterval?
    let decodeTime: TimeInterval?
}

func runTest(
    name: String,
    image: J2KImage,
    config: J2KEncodingConfiguration,
    savePath: String? = nil,
    expectLossless: Bool = false
) -> TestResult {
    print("  [\(name)] Encoding \(image.width)x\(image.height) "
          + "(\(image.components.count) comp, \(config.lossless ? "lossless" : "lossy q=\(config.quality)"))...")

    do {
        // Encode
        let encodeStart = Date()
        let encoder = J2KEncoder(encodingConfiguration: config)
        var stageTimings: [(String, TimeInterval)] = []
        let encoded = try encoder.encode(image) { update in
            // Track stage progress
        }
        let encodeTime = Date().timeIntervalSince(encodeStart)

        print("    Encoded: \(encoded.count) bytes (\(String(format: "%.1f", Double(encoded.count) / 1024.0)) KB) "
              + "in \(String(format: "%.1f", encodeTime * 1000)) ms")

        // Validate codestream structure
        if encoded.count < 4 {
            return TestResult(name: name, passed: false, error: "Encoded data too small (\(encoded.count) bytes)",
                              encodedSize: encoded.count, mae: nil, psnr: nil, encodeTime: encodeTime, decodeTime: nil)
        }

        // Check SOC marker (0xFF4F)
        let soc = UInt16(encoded[0]) << 8 | UInt16(encoded[1])
        if soc != 0xFF4F {
            return TestResult(name: name, passed: false,
                              error: "Invalid SOC marker: 0x\(String(format: "%04X", soc)) (expected 0xFF4F)",
                              encodedSize: encoded.count, mae: nil, psnr: nil, encodeTime: encodeTime, decodeTime: nil)
        }

        // Check EOC marker at end (0xFFD9)
        let eoc = UInt16(encoded[encoded.count - 2]) << 8 | UInt16(encoded[encoded.count - 1])
        if eoc != 0xFFD9 {
            return TestResult(name: name, passed: false,
                              error: "Invalid EOC marker: 0x\(String(format: "%04X", eoc)) (expected 0xFFD9)",
                              encodedSize: encoded.count, mae: nil, psnr: nil, encodeTime: encodeTime, decodeTime: nil)
        }
        print("    Codestream: SOC ✓  EOC ✓")

        // Save encoded data if requested
        if let path = savePath {
            let url = URL(fileURLWithPath: path)
            try encoded.write(to: url)
            print("    Saved to: \(path)")
        }

        // Decode
        let decodeStart = Date()
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        let decodeTime = Date().timeIntervalSince(decodeStart)

        print("    Decoded: \(decoded.width)x\(decoded.height) "
              + "(\(decoded.components.count) comp) "
              + "in \(String(format: "%.1f", decodeTime * 1000)) ms")

        // Verify dimensions
        guard decoded.width == image.width && decoded.height == image.height else {
            return TestResult(name: name, passed: false,
                              error: "Dimension mismatch: expected \(image.width)x\(image.height), "
                              + "got \(decoded.width)x\(decoded.height)",
                              encodedSize: encoded.count, mae: nil, psnr: nil,
                              encodeTime: encodeTime, decodeTime: decodeTime)
        }

        // Verify component count
        guard decoded.components.count == image.components.count else {
            return TestResult(name: name, passed: false,
                              error: "Component count mismatch: expected \(image.components.count), "
                              + "got \(decoded.components.count)",
                              encodedSize: encoded.count, mae: nil, psnr: nil,
                              encodeTime: encodeTime, decodeTime: decodeTime)
        }

        // Compute quality metrics for each component
        var totalMAE: Double = 0
        var totalPSNR: Double = 0
        for (i, origComp) in image.components.enumerated() {
            let decComp = decoded.components[i]
            let mae = computeMAE(original: origComp.data, decoded: decComp.data)
            let psnr = computePSNR(original: origComp.data, decoded: decComp.data)
            totalMAE += mae
            totalPSNR += psnr
            print("    Component \(i): MAE=\(String(format: "%.2f", mae))  "
                  + "PSNR=\(psnr.isInfinite ? "∞" : String(format: "%.1f", psnr)) dB")
        }
        let avgMAE = totalMAE / Double(image.components.count)
        let avgPSNR = totalPSNR / Double(image.components.count)

        // Check quality
        if expectLossless && avgMAE > 0 {
            return TestResult(name: name, passed: false,
                              error: "Lossless round-trip failed: MAE=\(String(format: "%.2f", avgMAE)) (expected 0)",
                              encodedSize: encoded.count, mae: avgMAE, psnr: avgPSNR,
                              encodeTime: encodeTime, decodeTime: decodeTime)
        }

        let compressionRatio = Double(image.components.reduce(0) { $0 + $1.data.count }) / Double(encoded.count)
        print("    Compression ratio: \(String(format: "%.2f", compressionRatio)):1")

        return TestResult(name: name, passed: true, error: nil,
                          encodedSize: encoded.count, mae: avgMAE, psnr: avgPSNR,
                          encodeTime: encodeTime, decodeTime: decodeTime)

    } catch {
        print("    ERROR: \(error)")
        return TestResult(name: name, passed: false, error: "\(error)",
                          encodedSize: nil, mae: nil, psnr: nil, encodeTime: nil, decodeTime: nil)
    }
}

// MARK: - Main

// Parse args
var savePath: String? = nil
var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    if arg == "--save" || arg == "-o" {
        savePath = args.first.map { String($0) }
        args = args.dropFirst()
    }
}

print("╔══════════════════════════════════════════════════╗")
print("║  J2KSwift Encode/Decode Pipeline Test           ║")
print("╚══════════════════════════════════════════════════╝")
print()

var results: [TestResult] = []

// Test 1: Small grayscale, lossless
print("Test 1: Small Grayscale Lossless (16x16)")
results.append(runTest(
    name: "Gray16x16-lossless",
    image: makeGrayscaleImage(width: 16, height: 16, pattern: "gradient"),
    config: J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: 2),
    expectLossless: true
))
print()

// Test 2: Small grayscale, lossy
print("Test 2: Small Grayscale Lossy (16x16, q=0.9)")
results.append(runTest(
    name: "Gray16x16-lossy",
    image: makeGrayscaleImage(width: 16, height: 16, pattern: "gradient"),
    config: J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
))
print()

// Test 3: Solid grayscale (all same value)
print("Test 3: Solid Grayscale (16x16)")
results.append(runTest(
    name: "Gray16x16-solid",
    image: makeGrayscaleImage(width: 16, height: 16, pattern: "solid"),
    config: J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: 2),
    expectLossless: true
))
print()

// Test 4: Checkerboard grayscale
print("Test 4: Checkerboard Grayscale (32x32)")
results.append(runTest(
    name: "Gray32x32-checker",
    image: makeGrayscaleImage(width: 32, height: 32, pattern: "checkerboard"),
    config: J2KEncodingConfiguration(quality: 0.95, lossless: false, decompositionLevels: 3)
))
print()

// Test 5: RGB image, lossy
print("Test 5: RGB Lossy (32x32, q=0.9)")
results.append(runTest(
    name: "RGB32x32-lossy",
    image: makeRGBImage(width: 32, height: 32),
    config: J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 2)
))
print()

// Test 6: RGB image, lossless
print("Test 6: RGB Lossless (32x32)")
results.append(runTest(
    name: "RGB32x32-lossless",
    image: makeRGBImage(width: 32, height: 32),
    config: J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: 2),
    expectLossless: true
))
print()

// Test 7: Larger image
print("Test 7: Larger Grayscale (128x128, lossy)")
let saveFile = savePath ?? "/tmp/j2ktest_128x128.j2k"
results.append(runTest(
    name: "Gray128x128-lossy",
    image: makeGrayscaleImage(width: 128, height: 128, pattern: "gradient"),
    config: J2KEncodingConfiguration(quality: 0.85, lossless: false, decompositionLevels: 4),
    savePath: saveFile
))
print()

// Test 8: Larger RGB image
print("Test 8: Larger RGB (64x64, lossy)")
results.append(runTest(
    name: "RGB64x64-lossy",
    image: makeRGBImage(width: 64, height: 64),
    config: J2KEncodingConfiguration(quality: 0.9, lossless: false, decompositionLevels: 3),
    savePath: savePath != nil ? savePath!.replacingOccurrences(of: ".j2k", with: "_rgb.j2k") : "/tmp/j2ktest_64x64_rgb.j2k"
))
print()

// Summary
print("╔══════════════════════════════════════════════════╗")
print("║  Results Summary                                ║")
print("╚══════════════════════════════════════════════════╝")
let passed = results.filter { $0.passed }.count
let total = results.count
for r in results {
    let status = r.passed ? "✅ PASS" : "❌ FAIL"
    var detail = ""
    if let err = r.error {
        detail = " — \(err)"
    } else if let mae = r.mae, let psnr = r.psnr {
        detail = " — MAE=\(String(format: "%.2f", mae)) PSNR=\(psnr.isInfinite ? "∞" : String(format: "%.1f", psnr))dB"
    }
    print("  \(status) \(r.name)\(detail)")
}
print()
print("  \(passed)/\(total) tests passed")

if passed < total {
    print()
    print("⚠️  Some tests failed. See details above.")
    exit(1)
}

print()
print("✅ All tests passed!")
