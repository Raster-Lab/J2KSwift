//
// J2KQualityMetrics.swift
// J2KSwift
//
/// Quality metrics computation for image comparison.
///
/// Provides deterministic, reproducible quality measurements including
/// PSNR, SSIM, MAE, and maximum absolute error. All computations use
/// only Foundation types — no external image libraries.

import Foundation

/// Per-component quality metrics.
public struct J2KComponentQualityMetrics: Sendable {
    /// Component index (0-based).
    public let component: Int

    /// Peak Signal-to-Noise Ratio in decibels.
    public let psnr: Double

    /// Mean Squared Error.
    public let mse: Double

    /// Mean Absolute Error.
    public let mae: Double

    /// Maximum absolute error across all pixels.
    public let maxAbsoluteError: Int

    /// Structural Similarity Index (0–1, higher is better).
    public let ssim: Double

    /// Whether the component is bit-exact with the reference.
    public let bitExact: Bool
}

/// Aggregated quality metrics for a full image comparison.
public struct J2KQualityReport: Sendable {
    /// Path or label of the original (reference) image.
    public let originalLabel: String

    /// Path or label of the compared image.
    public let comparedLabel: String

    /// Width of the images in pixels.
    public let width: Int

    /// Height of the images in pixels.
    public let height: Int

    /// Number of components (colour channels).
    public let componentCount: Int

    /// File size of the original in bytes.
    public let originalFileSize: Int64

    /// File size of the compared file in bytes.
    public let comparedFileSize: Int64

    /// Compression ratio (original raw size / compared file size).
    public let compressionRatio: Double

    /// Global PSNR across all components (dB).
    public let globalPSNR: Double

    /// Global MSE across all components.
    public let globalMSE: Double

    /// Global MAE across all components.
    public let globalMAE: Double

    /// Global maximum absolute error.
    public let globalMaxAbsoluteError: Int

    /// Global SSIM across all components.
    public let globalSSIM: Double

    /// Whether all components are bit-exact.
    public let bitExact: Bool

    /// Per-component metrics.
    public let perComponent: [J2KComponentQualityMetrics]

    /// Location (x, y) of the worst-error pixel.
    public let worstErrorLocation: (x: Int, y: Int)

    /// Component index where the worst error occurs.
    public let worstErrorComponent: Int
}

/// Deterministic quality metrics computation engine.
///
/// All methods are pure functions with no randomness or non-deterministic behaviour.
public enum J2KQualityMetricsEngine {

    // MARK: - Public API

    /// Compute full quality metrics between an original and compared image.
    ///
    /// - Parameters:
    ///   - original: The reference image.
    ///   - compared: The image to evaluate.
    ///   - originalLabel: Display label for the original.
    ///   - comparedLabel: Display label for the compared image.
    ///   - originalFileSize: File size of the original in bytes.
    ///   - comparedFileSize: File size of the compared file in bytes.
    /// - Returns: A complete quality report.
    /// - Throws: ``J2KError`` if images have mismatched dimensions.
    public static func computeReport(
        original: J2KImage,
        compared: J2KImage,
        originalLabel: String,
        comparedLabel: String,
        originalFileSize: Int64,
        comparedFileSize: Int64
    ) throws -> J2KQualityReport {
        guard original.width == compared.width,
              original.height == compared.height,
              original.componentCount == compared.componentCount else {
            throw J2KError.invalidParameter(
                "Dimension mismatch: original \(original.width)×\(original.height)×\(original.componentCount) " +
                "vs compared \(compared.width)×\(compared.height)×\(compared.componentCount)")
        }

        var perComponent: [J2KComponentQualityMetrics] = []
        var totalMSE: Double = 0
        var totalMAE: Double = 0
        var totalSSIM: Double = 0
        var globalMaxErr = 0
        var allBitExact = true
        var worstX = 0, worstY = 0, worstComp = 0

        for ci in 0..<original.componentCount {
            let origComp = original.components[ci]
            let compComp = compared.components[ci]

            let metrics = computeComponentMetrics(
                original: origComp,
                compared: compComp,
                width: original.width,
                height: original.height
            )

            perComponent.append(metrics.metrics)
            totalMSE += metrics.metrics.mse
            totalMAE += metrics.metrics.mae
            totalSSIM += metrics.metrics.ssim
            if !metrics.metrics.bitExact { allBitExact = false }
            if metrics.metrics.maxAbsoluteError > globalMaxErr {
                globalMaxErr = metrics.metrics.maxAbsoluteError
                worstX = metrics.worstX
                worstY = metrics.worstY
                worstComp = ci
            }
        }

        let nc = Double(original.componentCount)
        let avgMSE = totalMSE / nc
        let avgMAE = totalMAE / nc
        let avgSSIM = totalSSIM / nc

        let maxVal = Double((1 << original.components[0].bitDepth) - 1)
        let globalPSNR = avgMSE > 0 ? 10.0 * log10(maxVal * maxVal / avgMSE) : Double.infinity

        let rawSize = Int64(original.width * original.height * original.componentCount *
                            (original.components[0].bitDepth <= 8 ? 1 : 2))
        let ratio = comparedFileSize > 0 ? Double(rawSize) / Double(comparedFileSize) : 0

        return J2KQualityReport(
            originalLabel: originalLabel,
            comparedLabel: comparedLabel,
            width: original.width,
            height: original.height,
            componentCount: original.componentCount,
            originalFileSize: originalFileSize,
            comparedFileSize: comparedFileSize,
            compressionRatio: ratio,
            globalPSNR: globalPSNR,
            globalMSE: avgMSE,
            globalMAE: avgMAE,
            globalMaxAbsoluteError: globalMaxErr,
            globalSSIM: avgSSIM,
            bitExact: allBitExact,
            perComponent: perComponent,
            worstErrorLocation: (x: worstX, y: worstY),
            worstErrorComponent: worstComp
        )
    }

    /// Extract per-pixel signed differences for a single component.
    ///
    /// - Parameters:
    ///   - original: Reference component.
    ///   - compared: Component under test.
    /// - Returns: Array of signed differences (original − compared), row-major order.
    public static func pixelDifferences(
        original: J2KComponent,
        compared: J2KComponent
    ) -> [Int] {
        let count = original.width * original.height
        let bps = original.bitDepth <= 8 ? 1 : 2
        var diffs = [Int](repeating: 0, count: count)
        for i in 0..<count {
            let o = readSample(original.data, index: i, bytesPerSample: bps)
            let c = readSample(compared.data, index: i, bytesPerSample: bps)
            diffs[i] = o - c
        }
        return diffs
    }

    // MARK: - Internal

    private struct ComponentResult {
        let metrics: J2KComponentQualityMetrics
        let worstX: Int
        let worstY: Int
    }

    private static func computeComponentMetrics(
        original: J2KComponent,
        compared: J2KComponent,
        width: Int,
        height: Int
    ) -> ComponentResult {
        let pixelCount = original.width * original.height
        guard pixelCount > 0 else {
            let m = J2KComponentQualityMetrics(
                component: original.index,
                psnr: .infinity, mse: 0, mae: 0,
                maxAbsoluteError: 0, ssim: 1.0, bitExact: true)
            return ComponentResult(metrics: m, worstX: 0, worstY: 0)
        }

        let bps = original.bitDepth <= 8 ? 1 : 2
        var sumSq: Double = 0
        var sumAbs: Double = 0
        var maxErr = 0
        var exact = true
        var worstIdx = 0

        for i in 0..<pixelCount {
            let o = readSample(original.data, index: i, bytesPerSample: bps)
            let c = readSample(compared.data, index: i, bytesPerSample: bps)
            let diff = o - c
            let ad = abs(diff)
            sumSq += Double(diff * diff)
            sumAbs += Double(ad)
            if ad > maxErr {
                maxErr = ad
                worstIdx = i
            }
            if diff != 0 { exact = false }
        }

        let mse = sumSq / Double(pixelCount)
        let mae = sumAbs / Double(pixelCount)
        let maxVal = Double((1 << original.bitDepth) - 1)
        let psnr = mse > 0 ? 10.0 * log10(maxVal * maxVal / mse) : Double.infinity

        let ssim = computeSSIM(
            original: original, compared: compared,
            width: width, height: height, bytesPerSample: bps)

        let worstX = worstIdx % width
        let worstY = worstIdx / width

        let m = J2KComponentQualityMetrics(
            component: original.index,
            psnr: psnr, mse: mse, mae: mae,
            maxAbsoluteError: maxErr, ssim: ssim, bitExact: exact)
        return ComponentResult(metrics: m, worstX: worstX, worstY: worstY)
    }

    // MARK: - SSIM

    /// Compute SSIM using 8×8 non-overlapping windows.
    ///
    /// Uses the standard SSIM formula with K1=0.01, K2=0.03.
    /// Windows that extend beyond the image boundary are excluded.
    private static func computeSSIM(
        original: J2KComponent,
        compared: J2KComponent,
        width: Int,
        height: Int,
        bytesPerSample: Int
    ) -> Double {
        let windowSize = 8
        let L = Double((1 << original.bitDepth) - 1)
        let k1 = 0.01
        let k2 = 0.03
        let c1 = (k1 * L) * (k1 * L)
        let c2 = (k2 * L) * (k2 * L)

        let wCountX = width / windowSize
        let wCountY = height / windowSize
        guard wCountX > 0 && wCountY > 0 else { return 1.0 }

        var ssimSum: Double = 0
        var windowCount = 0

        for wy in 0..<wCountY {
            for wx in 0..<wCountX {
                let startX = wx * windowSize
                let startY = wy * windowSize

                var sumO: Double = 0
                var sumC: Double = 0
                var sumO2: Double = 0
                var sumC2: Double = 0
                var sumOC: Double = 0
                let n = Double(windowSize * windowSize)

                for dy in 0..<windowSize {
                    for dx in 0..<windowSize {
                        let idx = (startY + dy) * width + (startX + dx)
                        let o = Double(readSample(original.data, index: idx, bytesPerSample: bytesPerSample))
                        let c = Double(readSample(compared.data, index: idx, bytesPerSample: bytesPerSample))
                        sumO += o
                        sumC += c
                        sumO2 += o * o
                        sumC2 += c * c
                        sumOC += o * c
                    }
                }

                let muO = sumO / n
                let muC = sumC / n
                let sigO2 = sumO2 / n - muO * muO
                let sigC2 = sumC2 / n - muC * muC
                let sigOC = sumOC / n - muO * muC

                let num = (2.0 * muO * muC + c1) * (2.0 * sigOC + c2)
                let den = (muO * muO + muC * muC + c1) * (sigO2 + sigC2 + c2)
                ssimSum += num / den
                windowCount += 1
            }
        }

        return windowCount > 0 ? ssimSum / Double(windowCount) : 1.0
    }

    // MARK: - Sample Access

    @inline(__always)
    private static func readSample(_ data: Data, index: Int, bytesPerSample: Int) -> Int {
        if bytesPerSample == 1 {
            return index < data.count ? Int(data[index]) : 0
        } else {
            let idx = index * 2
            if idx + 1 < data.count {
                return Int(data[idx]) | (Int(data[idx + 1]) << 8)
            }
            return 0
        }
    }
}
