//
// J2KQuantizationTuningTests.swift
// J2KSwift
//
// Tuning harness for quantisation: sweeps quality levels and reports
// PSNR vs encoded size so developers can evaluate quantisation quality.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Tuning harness that encodes a synthetic test image at multiple quality
/// levels and verifies PSNR-vs-size behaviour.
final class J2KQuantizationTuningTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a synthetic greyscale test image with a gradient and edges.
    private func makeSyntheticImage(width: Int, height: Int) -> J2KImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                // Smooth gradient + edge pattern
                let gradient = UInt8(clamping: (x * 255) / max(width - 1, 1))
                let edge: UInt8 = ((x / 16 + y / 16) % 2 == 0) ? 32 : 0
                pixels[y * width + x] = gradient &+ edge
            }
        }
        let component = J2KImageComponent(
            data: pixels.map { Int32($0) },
            width: width,
            height: height,
            bitDepth: 8,
            isSigned: false
        )
        return J2KImage(width: width, height: height, components: [component])
    }

    /// Computes PSNR between two 8-bit single-component images.
    private func psnr(original: J2KImage, decoded: J2KImage) -> Double {
        let origData = original.components[0].data
        let decData = decoded.components[0].data
        guard origData.count == decData.count, !origData.isEmpty else { return 0 }

        var mse: Double = 0
        for i in 0..<origData.count {
            let diff = Double(origData[i]) - Double(decData[i])
            mse += diff * diff
        }
        mse /= Double(origData.count)
        guard mse > 0 else { return Double.infinity }
        return 10.0 * log10(255.0 * 255.0 / mse)
    }

    // MARK: - Tuning Tests

    /// Sweeps quality from low to high and asserts monotonic PSNR increase.
    func testPSNRMonotonicallyIncreasesWithQuality() throws {
        let image = makeSyntheticImage(width: 64, height: 64)
        let qualities: [Double] = [0.1, 0.3, 0.5, 0.7, 0.9]

        var prevPSNR: Double = -1
        var prevSize: Int = Int.max

        for quality in qualities {
            var config = J2KEncoderConfiguration()
            config.quality = quality
            config.decompositionLevels = 3
            config.lossless = false

            let encoder = J2KEncoder()
            let encoded = try encoder.encode(image, configuration: config)
            let encodedSize = encoded.count

            let decoder = J2KDecoder()
            let decoded = try decoder.decode(encoded)

            let p = psnr(original: image, decoded: decoded)

            // PSNR should increase (or stay infinite) as quality increases
            XCTAssertGreaterThanOrEqual(p, prevPSNR,
                "PSNR should not decrease when quality increases " +
                "(q=\(quality): \(p) dB < previous \(prevPSNR) dB)")

            prevPSNR = p
            _ = encodedSize
        }
    }

    /// Verifies encoded size generally decreases as quality decreases.
    func testEncodedSizeDecreasesWithLowerQuality() throws {
        let image = makeSyntheticImage(width: 64, height: 64)

        var config = J2KEncoderConfiguration()
        config.decompositionLevels = 3
        config.lossless = false

        config.quality = 0.9
        let encoder = J2KEncoder()
        let highQData = try encoder.encode(image, configuration: config)

        config.quality = 0.1
        let lowQData = try encoder.encode(image, configuration: config)

        // Lower quality should produce smaller (or equal) output
        XCTAssertLessThanOrEqual(lowQData.count, highQData.count,
            "Low quality (\(lowQData.count) bytes) should not be larger than " +
            "high quality (\(highQData.count) bytes)")
    }

    /// Verifies subband step sizes have correct relative ordering in
    /// the quantizer (LL < LH/HL < HH).
    func testSubbandStepSizeRelativeOrdering() throws {
        let qualities: [Double] = [0.1, 0.5, 0.9]

        for quality in qualities {
            let params = J2KQuantizationParameters.fromQuality(quality)
            let totalLevels = 5

            let steps = J2KStepSizeCalculator.calculateAllStepSizes(
                baseStepSize: params.baseStepSize,
                totalLevels: totalLevels,
                reversible: false
            )

            let llStep = steps["LL_0"]!

            // At any given level, HL/LH step < HH step
            for level in 0..<totalLevels {
                let hlStep = steps["HL_\(level + 1)"]!
                let lhStep = steps["LH_\(level + 1)"]!
                let hhStep = steps["HH_\(level + 1)"]!

                XCTAssertEqual(hlStep, lhStep, accuracy: 1e-10,
                    "HL and LH should have equal step sizes at level \(level + 1)")
                XCTAssertLessThan(hlStep, hhStep,
                    "HL step (\(hlStep)) should be less than HH step (\(hhStep)) " +
                    "at level \(level + 1), quality \(quality)")
            }

            // LL step should be smallest overall
            let finestHLStep = steps["HL_1"]!
            XCTAssertLessThan(llStep, finestHLStep,
                "LL step (\(llStep)) should be less than finest HL step (\(finestHLStep)) " +
                "at quality \(quality)")
        }
    }

    /// Prints a summary table (for developer inspection, not assertion-based).
    func testPrintTuningTable() throws {
        let image = makeSyntheticImage(width: 64, height: 64)
        let qualities: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

        print("\n--- Quantisation Tuning Report ---")
        print(String(format: "%-8s %-10s %-12s %-10s %-10s",
              "Quality", "BaseStep", "EncodedSize", "PSNR(dB)", "MAE"))

        for quality in qualities {
            let params = J2KQuantizationParameters.fromQuality(quality)

            var config = J2KEncoderConfiguration()
            config.quality = quality
            config.decompositionLevels = 3
            config.lossless = false

            let encoder = J2KEncoder()
            let encoded = try encoder.encode(image, configuration: config)

            let decoder = J2KDecoder()
            let decoded = try decoder.decode(encoded)

            let p = psnr(original: image, decoded: decoded)

            // Compute MAE
            let origData = image.components[0].data
            let decData = decoded.components[0].data
            var totalError: Int64 = 0
            for i in 0..<origData.count {
                totalError += Int64(abs(origData[i] - decData[i]))
            }
            let mae = Double(totalError) / Double(origData.count)

            print(String(format: "%-8.1f %-10.4f %-12d %-10.2f %-10.4f",
                  quality, params.baseStepSize, encoded.count, p, mae))
        }
        print("--- End Report ---\n")
    }
}
