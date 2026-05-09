// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
// J2KHTConformantMedicalRoundTripTests.swift
// Downstream bug report reproduction: v5.1.0 `.conformant` HTJ2K
// lossless round-trip mismatches pixel values on real DICOM
// payloads through J2KSwift's own decode API. Tracked for v5.1.1.
//
// These tests walk the staged DICOM corpus (local-only, skipped in CI)
// and bisect the failure across modalities + decomposition levels.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLI
@testable import J2KCodec

final class J2KHTConformantMedicalRoundTripTests: XCTestCase {

    private func datasetRootURL() -> URL? {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: cwd).appendingPathComponent("LocalDatasets/medical-dicom-organized", isDirectory: true),
            URL(fileURLWithPath: cwd).appendingPathComponent("J2KSwift/LocalDatasets/medical-dicom-organized", isDirectory: true),
        ]
        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func firstDICOM(modality: String) throws -> J2KImage {
        guard let root = datasetRootURL() else {
            throw XCTSkip("Local DICOM corpus not available")
        }
        let modalityRoot = root.appendingPathComponent(modality, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: modalityRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            throw XCTSkip("No modality directory for \(modality)")
        }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "dcm" else { continue }
            let data = try Data(contentsOf: url)
            let image = try J2KCLI.loadDICOM(data)
            if image.width > 0, image.height > 0 {
                return image
            }
        }
        throw XCTSkip("No decodable DICOM under \(modalityRoot.path)")
    }

    private func conformantLosslessConfig(decompositionLevels: Int) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true
        )
        cfg.useReversibleFilter = true
        cfg.htj2kBlockFormat = .conformant
        cfg.bitrateMode = .lossless
        return cfg
    }

    private func assertLosslessRoundTrip(
        _ image: J2KImage,
        decompositionLevels: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let cfg = conformantLosslessConfig(decompositionLevels: decompositionLevels)
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(decoded.width, image.width, "\(label) width mismatch", file: file, line: line)
        XCTAssertEqual(decoded.height, image.height, "\(label) height mismatch", file: file, line: line)
        XCTAssertEqual(decoded.components.count, image.components.count, "\(label) component count mismatch", file: file, line: line)

        for (i, (orig, rec)) in zip(image.components, decoded.components).enumerated() {
            XCTAssertEqual(rec.bitDepth, orig.bitDepth, "\(label) component \(i) bit depth", file: file, line: line)
            if rec.data != orig.data {
                let origBytes = [UInt8](orig.data)
                let recBytes = [UInt8](rec.data)
                let bytesPerSample = (orig.bitDepth + 7) / 8
                let sampleCount = min(origBytes.count, recBytes.count) / max(1, bytesPerSample)
                var mismatchCount = 0
                var zeroPixelMismatches = 0
                var nonZeroPixelMismatches = 0
                for s in 0..<sampleCount {
                    let base = s * bytesPerSample
                    var origIsZero = true
                    var mismatched = false
                    for b in 0..<bytesPerSample {
                        if origBytes[base + b] != 0 { origIsZero = false }
                        if origBytes[base + b] != recBytes[base + b] { mismatched = true }
                    }
                    if mismatched {
                        mismatchCount += 1
                        if origIsZero { zeroPixelMismatches += 1 }
                        else { nonZeroPixelMismatches += 1 }
                    }
                }
                XCTFail(
                    "\(label) lossless mismatch: \(mismatchCount)/\(sampleCount) samples; " +
                    "zero-pixel=\(zeroPixelMismatches), non-zero=\(nonZeroPixelMismatches)",
                    file: file, line: line
                )
                return
            }
        }
    }

    // Downstream's exact repro: decomp=0.
    func testMRFirstSample_decomp0() async throws {
        let image = try firstDICOM(modality: "mr")
        try await assertLosslessRoundTrip(image, decompositionLevels: 0,
            label: "MR \(image.width)×\(image.height) bd=\(image.components[0].bitDepth) decomp=0")
    }

    // Sanity: non-zero decomposition reproduces or not?
    func testMRFirstSample_decomp3() async throws {
        let image = try firstDICOM(modality: "mr")
        try await assertLosslessRoundTrip(image, decompositionLevels: 3,
            label: "MR \(image.width)×\(image.height) bd=\(image.components[0].bitDepth) decomp=3")
    }

    // CT sibling case.
    func testCTFirstSample_decomp0() async throws {
        let image = try firstDICOM(modality: "ct")
        try await assertLosslessRoundTrip(image, decompositionLevels: 0,
            label: "CT \(image.width)×\(image.height) bd=\(image.components[0].bitDepth) decomp=0")
    }
}

#endif // os(macOS)
