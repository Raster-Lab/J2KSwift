// v8 Phase 6.2 — gated to macOS: invokes external CLIs via Process() (unavailable on iOS).
#if os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLI

/// Real-data lossless stress tests driven by the staged local DICOM corpus.
///
/// These tests intentionally exercise multiple medical modalities through the
/// native CLI encode/decode path and verify exact reconstruction against the
/// DICOM pixel data extracted by the workspace loader.
final class J2KRealMedicalDICOMStressTests: XCTestCase {
    private let modalitySampleLimits: [String: Int] = [
        "ct": 6,
        "mr": 6,
        "dx": 8,
        "mg": 8,
        "px": 6,
        "xa": 8,
    ]

    private var cliPath: String {
        if let envPath = ProcessInfo.processInfo.environment["J2K_CLI_PATH"] {
            return envPath
        }

        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let possiblePaths = [
            "\(currentDir)/.build/debug/j2k",
            "\(currentDir)/.build/release/j2k",
            "\(currentDir)/J2KSwift/.build/debug/j2k",
            "\(currentDir)/J2KSwift/.build/release/j2k",
        ]

        for path in possiblePaths where fileManager.fileExists(atPath: path) {
            return path
        }

        return "\(currentDir)/.build/debug/j2k"
    }

    private func datasetRootURL() -> URL? {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let candidates = [
            URL(fileURLWithPath: currentDir).appendingPathComponent("LocalDatasets/medical-dicom-organized", isDirectory: true),
            URL(fileURLWithPath: currentDir).appendingPathComponent("J2KSwift/LocalDatasets/medical-dicom-organized", isDirectory: true),
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func evenlySpaced<T>(_ items: [T], limit: Int) -> [T] {
        guard limit > 0, items.count > limit else { return items }
        guard limit > 1 else { return [items[items.count / 2]] }

        var indices: [Int] = []
        indices.reserveCapacity(limit)
        for i in 0..<limit {
            let idx = Int(round(Double(i) * Double(items.count - 1) / Double(limit - 1)))
            if indices.last != idx {
                indices.append(idx)
            }
        }
        return indices.map { items[$0] }
    }

    private func candidateFiles(in modalityRoot: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: modalityRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "dcm" || ext == "dicom" {
                urls.append(url)
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    private func selectedSamples() throws -> [(modality: String, url: URL)] {
        guard let datasetRoot = datasetRootURL() else {
            throw XCTSkip("Local staged DICOM corpus not available")
        }

        var selected: [(modality: String, url: URL)] = []

        for (modality, limit) in modalitySampleLimits.sorted(by: { $0.key < $1.key }) {
            let modalityRoot = datasetRoot.appendingPathComponent(modality, isDirectory: true)
            let candidates = evenlySpaced(candidateFiles(in: modalityRoot), limit: max(limit * 3, limit))

            var accepted = 0
            for url in candidates {
                do {
                    let data = try Data(contentsOf: url)
                    let image = try J2KCLI.loadDICOM(data)
                    guard image.width > 0, image.height > 0, image.componentCount > 0 else {
                        continue
                    }
                    selected.append((modality: modality, url: url))
                    accepted += 1
                    if accepted == limit {
                        break
                    }
                } catch {
                    continue
                }
            }
        }

        if selected.isEmpty {
            throw XCTSkip("No decodable local DICOM files found in staged corpus")
        }

        return selected
    }

    @discardableResult
    private func runCLI(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        XCTAssertEqual(
            process.terminationStatus,
            0,
            "CLI failed for arguments \(arguments.joined(separator: " "))\nSTDOUT:\n\(stdout)\nSTDERR:\n\(stderr)",
            file: file,
            line: line
        )

        return stdout
    }

    private func assertLosslessRoundTrip(for sample: URL, modality: String, useHTJ2K: Bool) throws {
        let originalData = try Data(contentsOf: sample)
        let original = try J2KCLI.loadDICOM(originalData)

        let workRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workRoot) }

        let encodedURL = workRoot
            .appendingPathComponent(sample.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(useHTJ2K ? "jph" : "j2k")
        let reconstructedURL = workRoot.appendingPathComponent("reconstructed.tiff")

        var encodeArguments = ["encode", "-i", sample.path, "-o", encodedURL.path, "--lossless", "--quiet"]
        if useHTJ2K {
            encodeArguments.append("--htj2k")
        }

        try runCLI(encodeArguments)
        try runCLI(["decode", "-i", encodedURL.path, "-o", reconstructedURL.path, "--quiet"])

        let reconstructedData = try Data(contentsOf: reconstructedURL)
        let reconstructed = try J2KCLI.loadTIFF(reconstructedData)

        XCTAssertEqual(reconstructed.width, original.width, "Width mismatch for \(modality) sample \(sample.lastPathComponent)")
        XCTAssertEqual(reconstructed.height, original.height, "Height mismatch for \(modality) sample \(sample.lastPathComponent)")
        XCTAssertEqual(reconstructed.componentCount, original.componentCount, "Component count mismatch for \(modality) sample \(sample.lastPathComponent)")

        for (originalComponent, reconstructedComponent) in zip(original.components, reconstructed.components) {
            XCTAssertEqual(reconstructedComponent.bitDepth, originalComponent.bitDepth, "Bit depth mismatch for \(modality) sample \(sample.lastPathComponent)")
            XCTAssertEqual(reconstructedComponent.signed, originalComponent.signed, "Signedness mismatch for \(modality) sample \(sample.lastPathComponent)")
            XCTAssertEqual(reconstructedComponent.data, originalComponent.data, "Lossless medical roundtrip must remain bit-exact for \(modality) sample \(sample.lastPathComponent)")
        }
    }

    func testRealMedicalDICOMLosslessLegacyRoundTripsAcrossModalities() throws {
        // Arrange
        let samples = try selectedSamples()

        // Act / Assert
        XCTAssertGreaterThanOrEqual(samples.count, 30, "Expected broad real-medical sample coverage")
        for (modality, url) in samples {
            try assertLosslessRoundTrip(for: url, modality: modality, useHTJ2K: false)
        }
    }

    func testRealMedicalDICOMLosslessHTJ2KRoundTripsAcrossModalities() throws {
        // Arrange
        let samples = try selectedSamples()

        // Act / Assert
        XCTAssertGreaterThanOrEqual(samples.count, 30, "Expected broad real-medical sample coverage")
        for (modality, url) in samples {
            try assertLosslessRoundTrip(for: url, modality: modality, useHTJ2K: true)
        }
    }
}

#endif // os(macOS)
