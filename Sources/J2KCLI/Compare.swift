//
// Compare.swift
// J2KSwift
//
/// Compare command — compute image quality metrics between original and reconstructed images.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Compare command: compute quality metrics between two images.
    static func compareCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printCompareHelp()
            return
        }

        guard let originalPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input (original image)")
            exit(1)
        }

        guard let reconstructedPath = options["r"] ?? options["reference"] else {
            print("Error: Missing required argument: -r/--reference (reconstructed image)")
            exit(1)
        }

        let jsonOutput = options["json"] != nil
        let quiet = options["quiet"] != nil
        let bitExact = options["bit-exact"] != nil
        let mode = options["mode"] ?? "2d"

        // Load images
        let originalImage: J2KImage
        let reconstructedImage: J2KImage

        // Check if input is a J2K file — decode it first
        let origExt = URL(fileURLWithPath: originalPath).pathExtension.lowercased()
        let recoExt = URL(fileURLWithPath: reconstructedPath).pathExtension.lowercased()
        let j2kExts = Set(["j2k", "jp2", "jpx", "jph", "j2c", "jpc"])

        if j2kExts.contains(origExt) {
            let data = try Data(contentsOf: URL(fileURLWithPath: originalPath))
            let decoder = J2KDecoder()
            originalImage = try decoder.decode(data)
        } else {
            originalImage = try loadImage(from: originalPath)
        }

        if j2kExts.contains(recoExt) {
            let data = try Data(contentsOf: URL(fileURLWithPath: reconstructedPath))
            let decoder = J2KDecoder()
            reconstructedImage = try decoder.decode(data)
        } else {
            reconstructedImage = try loadImage(from: reconstructedPath)
        }

        // Validate dimensions
        guard originalImage.width == reconstructedImage.width &&
              originalImage.height == reconstructedImage.height &&
              originalImage.componentCount == reconstructedImage.componentCount else {
            print("Error: Image dimensions do not match")
            print("  Original:      \(originalImage.width)×\(originalImage.height), \(originalImage.componentCount) component(s)")
            print("  Reconstructed: \(reconstructedImage.width)×\(reconstructedImage.height), \(reconstructedImage.componentCount) component(s)")
            exit(1)
        }

        // Compute metrics per component
        var componentMetrics: [[String: Any]] = []
        var overallMSE: Double = 0
        var overallMAE: Double = 0
        var overallMaxError: Int = 0
        var isBitExact = true

        for ci in 0..<originalImage.componentCount {
            let origComp = originalImage.components[ci]
            let recoComp = reconstructedImage.components[ci]
            let metrics = computeComponentMetrics(original: origComp, reconstructed: recoComp)

            componentMetrics.append([
                "component": ci,
                "psnr": metrics.psnr,
                "mse": metrics.mse,
                "mae": metrics.mae,
                "maxError": metrics.maxError,
                "bitExact": metrics.bitExact
            ])

            overallMSE += metrics.mse
            overallMAE += metrics.mae
            overallMaxError = max(overallMaxError, metrics.maxError)
            if !metrics.bitExact { isBitExact = false }
        }

        overallMSE /= Double(originalImage.componentCount)
        overallMAE /= Double(originalImage.componentCount)

        let maxVal = Double((1 << originalImage.components[0].bitDepth) - 1)
        let overallPSNR = overallMSE > 0 ? 10.0 * log10(maxVal * maxVal / overallMSE) : Double.infinity

        // Output results
        if jsonOutput {
            let result: [String: Any] = [
                "original": originalPath,
                "reconstructed": reconstructedPath,
                "width": originalImage.width,
                "height": originalImage.height,
                "components": originalImage.componentCount,
                "overall": [
                    "psnr": overallPSNR.isInfinite ? "Inf" : String(format: "%.4f", overallPSNR),
                    "mse": overallMSE,
                    "mae": overallMAE,
                    "maxError": overallMaxError,
                    "bitExact": isBitExact
                ],
                "perComponent": componentMetrics
            ]
            printJSON(result)
        } else if !quiet {
            print("Image Comparison:")
            print("  Original:      \(originalPath)")
            print("  Reconstructed: \(reconstructedPath)")
            print("  Dimensions:    \(originalImage.width)×\(originalImage.height), \(originalImage.componentCount) component(s)")
            print("")

            if bitExact {
                print("  Bit-exact:     \(isBitExact ? "YES ✓" : "NO ✗")")
            }

            print("  Overall:")
            if overallPSNR.isInfinite {
                print("    PSNR:        Inf (lossless)")
            } else {
                print("    PSNR:        \(String(format: "%.4f", overallPSNR)) dB")
            }
            print("    MSE:         \(String(format: "%.6f", overallMSE))")
            print("    MAE:         \(String(format: "%.6f", overallMAE))")
            print("    Max Error:   \(overallMaxError)")

            if originalImage.componentCount > 1 {
                print("")
                print("  Per-Component:")
                for ci in 0..<originalImage.componentCount {
                    let m = componentMetrics[ci]
                    let psnr = m["psnr"] as? Double ?? 0
                    let mse = m["mse"] as? Double ?? 0
                    let mae = m["mae"] as? Double ?? 0
                    let maxErr = m["maxError"] as? Int ?? 0
                    let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.4f", psnr)
                    print("    [\(ci)] PSNR: \(psnrStr) dB, MSE: \(String(format: "%.6f", mse)), MAE: \(String(format: "%.6f", mae)), MaxErr: \(maxErr)")
                }
            }
        }
    }

    // MARK: - Metrics Computation

    struct ComponentMetrics {
        let psnr: Double
        let mse: Double
        let mae: Double
        let maxError: Int
        let bitExact: Bool
    }

    static func computeComponentMetrics(original: J2KComponent, reconstructed: J2KComponent) -> ComponentMetrics {
        let pixelCount = original.width * original.height
        guard pixelCount > 0 else {
            return ComponentMetrics(psnr: .infinity, mse: 0, mae: 0, maxError: 0, bitExact: true)
        }

        let bytesPerSample = original.bitDepth <= 8 ? 1 : 2
        var sumSqError: Double = 0
        var sumAbsError: Double = 0
        var maxErr = 0
        var exact = true

        for i in 0..<pixelCount {
            let origVal: Int
            let recoVal: Int

            if bytesPerSample == 1 {
                let idx = i
                origVal = idx < original.data.count ? Int(original.data[idx]) : 0
                recoVal = idx < reconstructed.data.count ? Int(reconstructed.data[idx]) : 0
            } else {
                let idx = i * 2
                if idx + 1 < original.data.count {
                    origVal = Int(original.data[idx]) | (Int(original.data[idx + 1]) << 8)
                } else {
                    origVal = 0
                }
                if idx + 1 < reconstructed.data.count {
                    recoVal = Int(reconstructed.data[idx]) | (Int(reconstructed.data[idx + 1]) << 8)
                } else {
                    recoVal = 0
                }
            }

            let diff = origVal - recoVal
            let absDiff = abs(diff)
            sumSqError += Double(diff * diff)
            sumAbsError += Double(absDiff)
            if absDiff > maxErr { maxErr = absDiff }
            if diff != 0 { exact = false }
        }

        let mse = sumSqError / Double(pixelCount)
        let mae = sumAbsError / Double(pixelCount)
        let maxVal = Double((1 << original.bitDepth) - 1)
        let psnr = mse > 0 ? 10.0 * log10(maxVal * maxVal / mse) : Double.infinity

        return ComponentMetrics(psnr: psnr, mse: mse, mae: mae, maxError: maxErr, bitExact: exact)
    }

    // MARK: - Help

    private static func printCompareHelp() {
        print("""
        j2k compare - Compare two images (quality metrics)

        USAGE:
            j2k compare -i <original> -r <reconstructed> [options]

        OPTIONS:
            -i, --input PATH            Original image
            -r, --reference PATH        Reconstructed image
            --mode 2d|3d                Comparison mode (default: 2d)
            --bit-exact                 Verify bit-exact match
            --json                      JSON output
            --quiet                     Suppress output

        METRICS:
            PSNR    Peak Signal-to-Noise Ratio (dB)
            MSE     Mean Squared Error
            MAE     Mean Absolute Error
            MaxErr  Maximum Absolute Error

        EXAMPLES:
            j2k compare -i original.pgm -r decoded.pgm
            j2k compare -i original.ppm -r decoded.ppm --bit-exact --json
        """)
    }
}
