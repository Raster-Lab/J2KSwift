// J2KWindowsPlatformTests.swift
// J2KSwift
//
// Tests for Windows platform validation ensuring correct behavior
// of platform utilities, file I/O, memory measurement, and
// Foundation compatibility on Windows systems.

import XCTest
@testable import J2KCore

final class J2KWindowsPlatformTests: XCTestCase {
    // MARK: - Platform Detection Tests

    func testJ2KPlatformCurrentIsNotUnknown() {
        XCTAssertNotEqual(J2KPlatform.current, .unknown,
                          "Current platform should be detected")
    }

    func testJ2KPlatformWindowsDetection() {
        #if os(Windows)
        XCTAssertTrue(J2KPlatform.isWindows)
        XCTAssertFalse(J2KPlatform.isLinux)
        XCTAssertFalse(J2KPlatform.isApple)
        XCTAssertEqual(J2KPlatform.current, .windows)
        #else
        XCTAssertFalse(J2KPlatform.isWindows)
        #endif
    }

    func testJ2KPlatformMutualExclusivity() {
        // At most one platform family should be true
        let flags = [J2KPlatform.isWindows, J2KPlatform.isLinux, J2KPlatform.isApple]
        let trueCount = flags.filter { $0 }.count
        XCTAssertEqual(trueCount, 1,
                       "Exactly one platform family should be detected")
    }

    // MARK: - Path Utilities Tests

    func testPathSeparator() {
        #if os(Windows)
        XCTAssertEqual(J2KPathUtilities.pathSeparator, "\\")
        #else
        XCTAssertEqual(J2KPathUtilities.pathSeparator, "/")
        #endif
    }

    func testNormalizePath() {
        let unixPath = "/usr/local/bin/file.txt"

        #if os(Windows)
        let normalized = J2KPathUtilities.normalizePath(unixPath)
        XCTAssertTrue(normalized.contains("\\"),
                      "Windows should convert forward slashes to backslashes")
        XCTAssertFalse(normalized.contains("/"),
                       "Windows normalized path should not contain forward slashes")
        #else
        let normalized = J2KPathUtilities.normalizePath(unixPath)
        XCTAssertEqual(normalized, unixPath,
                       "Unix path should remain unchanged on non-Windows")
        #endif
    }

    func testNormalizePathPreservesEmptyString() {
        let empty = ""
        XCTAssertEqual(J2KPathUtilities.normalizePath(empty), "")
    }

    func testTemporaryDirectory() {
        let tmpDir = J2KPathUtilities.temporaryDirectory()
        XCTAssertFalse(tmpDir.path.isEmpty, "Temporary directory should not be empty")
    }

    func testTemporaryFileURL() {
        let tmpFile = J2KPathUtilities.temporaryFileURL(named: "test.j2k")
        XCTAssertTrue(tmpFile.lastPathComponent == "test.j2k")
    }

    // MARK: - Memory Info Tests

    func testMemoryInfoReturnsNonNegative() {
        let memory = J2KMemoryInfo.currentResidentMemory()
        XCTAssertGreaterThanOrEqual(memory, 0,
                                    "Memory usage should be non-negative")
    }

    func testMemoryInfoOnCurrentPlatform() {
        let memory = J2KMemoryInfo.currentResidentMemory()
        #if os(Linux)
        // On Linux, we should get a positive value in test environment
        XCTAssertGreaterThan(memory, 0,
                             "Linux should report positive memory usage")
        #else
        // On other platforms, may return 0 (not implemented)
        XCTAssertGreaterThanOrEqual(memory, 0)
        #endif
    }

    // MARK: - Foundation Compatibility Tests

    func testFileExistsAtURL() throws {
        // Create a temporary file and verify existence check
        let tmpURL = J2KPathUtilities.temporaryFileURL(named: "j2k_test_exists_\(UUID().uuidString).tmp")
        let testData = Data("J2KSwift Windows test".utf8)

        // File should not exist yet
        XCTAssertFalse(J2KFoundationCompat.fileExists(at: tmpURL))

        // Write and verify
        try testData.write(to: tmpURL)
        XCTAssertTrue(J2KFoundationCompat.fileExists(at: tmpURL))

        // Cleanup
        try FileManager.default.removeItem(at: tmpURL)
        XCTAssertFalse(J2KFoundationCompat.fileExists(at: tmpURL))
    }

    func testCreateDirectoryAndRemove() throws {
        let tmpDir = J2KPathUtilities.temporaryDirectory()
            .appendingPathComponent("j2k_test_dir_\(UUID().uuidString)")

        // Create directory
        try J2KFoundationCompat.createDirectory(at: tmpDir)
        XCTAssertTrue(J2KFoundationCompat.fileExists(at: tmpDir))

        // Clean up
        try J2KFoundationCompat.removeItem(at: tmpDir)
        XCTAssertFalse(J2KFoundationCompat.fileExists(at: tmpDir))
    }

    func testReadWriteFile() throws {
        let tmpURL = J2KPathUtilities.temporaryFileURL(named: "j2k_test_rw_\(UUID().uuidString).bin")
        let testData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x2F]) // SOC + SIZ marker fragment

        // Write
        try J2KFoundationCompat.writeFile(testData, to: tmpURL)

        // Read back
        let readData = try J2KFoundationCompat.readFile(at: tmpURL)
        XCTAssertEqual(readData, testData,
                       "Read data should match written data")

        // Cleanup
        try J2KFoundationCompat.removeItem(at: tmpURL)
    }

    func testContentsOfDirectory() throws {
        let tmpDir = J2KPathUtilities.temporaryDirectory()
            .appendingPathComponent("j2k_test_list_\(UUID().uuidString)")

        try J2KFoundationCompat.createDirectory(at: tmpDir)

        // Create a few test files
        let fileNames = ["test1.j2k", "test2.jp2", "test3.jph"]
        for name in fileNames {
            let fileURL = tmpDir.appendingPathComponent(name)
            try Data("test".utf8).write(to: fileURL)
        }

        // List directory
        let contents = try J2KFoundationCompat.contentsOfDirectory(at: tmpDir)
        XCTAssertEqual(contents.count, fileNames.count)

        let listedNames = Set(contents.map { $0.lastPathComponent })
        for name in fileNames {
            XCTAssertTrue(listedNames.contains(name),
                          "Directory listing should include \(name)")
        }

        // Cleanup
        try J2KFoundationCompat.removeItem(at: tmpDir)
    }

    // MARK: - File Format I/O Validation

    func testBinaryDataRoundTripOnPlatform() throws {
        // Simulate writing and reading a JPEG 2000 codestream header
        let tmpURL = J2KPathUtilities.temporaryFileURL(named: "j2k_test_binary_\(UUID().uuidString).j2k")

        // Build a minimal codestream: SOC (0xFF4F) + EOC (0xFFD9)
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F]) // SOC
        data.append(contentsOf: [0xFF, 0xD9]) // EOC

        try J2KFoundationCompat.writeFile(data, to: tmpURL)
        let readBack = try J2KFoundationCompat.readFile(at: tmpURL)

        // Verify byte-for-byte integrity
        XCTAssertEqual(readBack.count, 4)
        XCTAssertEqual(readBack[0], 0xFF)
        XCTAssertEqual(readBack[1], 0x4F)
        XCTAssertEqual(readBack[2], 0xFF)
        XCTAssertEqual(readBack[3], 0xD9)

        try J2KFoundationCompat.removeItem(at: tmpURL)
    }

    func testLargeFileRoundTrip() throws {
        // Test with a larger file to verify no platform-specific size issues
        let tmpURL = J2KPathUtilities.temporaryFileURL(named: "j2k_test_large_\(UUID().uuidString).bin")

        // Create 64KB of test data
        let size = 64 * 1024
        var data = Data(count: size)
        for i in 0..<size {
            data[i] = UInt8(i & 0xFF)
        }

        try J2KFoundationCompat.writeFile(data, to: tmpURL)
        let readBack = try J2KFoundationCompat.readFile(at: tmpURL)

        XCTAssertEqual(readBack.count, size)
        XCTAssertEqual(readBack, data)

        try J2KFoundationCompat.removeItem(at: tmpURL)
    }

    // MARK: - Platform Info Integration

    func testConformancePlatformInfoWindowsAwareness() {
        let summary = J2KPlatformInfo.platformSummary()
        XCTAssertTrue(summary.contains("Windows Platform:"),
                      "Platform summary should include Windows Platform field")

        #if os(Windows)
        XCTAssertTrue(J2KPlatformInfo.isWindowsPlatform)
        XCTAssertEqual(J2KPlatformInfo.currentOS, .windows)
        #else
        XCTAssertFalse(J2KPlatformInfo.isWindowsPlatform)
        #endif
    }

    func testWindowsSpecificPathHandling() {
        #if os(Windows)
        // On Windows, test UNC path handling
        let uncPath = "\\\\server\\share\\file.j2k"
        let normalized = J2KPathUtilities.normalizePath(uncPath)
        XCTAssertTrue(normalized.hasPrefix("\\\\"),
                      "UNC paths should be preserved on Windows")
        #else
        // On non-Windows, paths with backslashes are left as-is by normalizePath
        let path = "/home/user/file.j2k"
        XCTAssertEqual(J2KPathUtilities.normalizePath(path), path)
        #endif
    }
}
