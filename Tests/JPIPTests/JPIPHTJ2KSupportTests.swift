//
// JPIPHTJ2KSupportTests.swift
// J2KSwift
//
/// # JPIPHTJ2KSupportTests
///
/// Tests for JPIP HTJ2K (High-Throughput JPEG 2000) support.

import XCTest
@testable import JPIP
@testable import J2KCore
@testable import J2KFileFormat

/// Tests for JPIP HTJ2K integration features.
final class JPIPHTJ2KSupportTests: XCTestCase {
    // MARK: - JPIPCodingPreference Tests

    func testCodingPreferenceRawValues() {
        XCTAssertEqual(JPIPCodingPreference.none.rawValue, "none")
        XCTAssertEqual(JPIPCodingPreference.htj2k.rawValue, "htj2k")
        XCTAssertEqual(JPIPCodingPreference.legacy.rawValue, "legacy")
    }

    // MARK: - JPIPImageInfo Tests

    func testImageInfoCreation() {
        let url = URL(fileURLWithPath: "/tmp/test.jph")
        let info = JPIPImageInfo(url: url, format: .jph, isHTJ2K: true)

        XCTAssertEqual(info.url, url)
        XCTAssertEqual(info.format, .jph)
        XCTAssertTrue(info.isHTJ2K)
        XCTAssertEqual(info.mimeType, "image/jph")
    }

    func testImageInfoLegacyFormat() {
        let url = URL(fileURLWithPath: "/tmp/test.jp2")
        let info = JPIPImageInfo(url: url, format: .jp2, isHTJ2K: false)

        XCTAssertEqual(info.format, .jp2)
        XCTAssertFalse(info.isHTJ2K)
        XCTAssertEqual(info.mimeType, "image/jp2")
    }

    func testImageInfoJ2KFormat() {
        let url = URL(fileURLWithPath: "/tmp/test.j2k")
        let info = JPIPImageInfo(url: url, format: .j2k, isHTJ2K: false)

        XCTAssertEqual(info.format, .j2k)
        XCTAssertFalse(info.isHTJ2K)
        XCTAssertEqual(info.mimeType, "image/j2k")
    }

    // MARK: - JPIPHTJ2KSupport Tests

    func testSupportInitialization() {
        let support = JPIPHTJ2KSupport()
        XCTAssertNotNil(support)
    }

    func testCapabilityHeadersForHTJ2K() {
        let support = JPIPHTJ2KSupport()
        let url = URL(fileURLWithPath: "/tmp/test.jph")
        let info = JPIPImageInfo(url: url, format: .jph, isHTJ2K: true)

        let headers = support.capabilityHeaders(for: info)

        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(headers["JPIP-cap"], "htj2k")
        XCTAssertEqual(headers["JPIP-pref"], "htj2k")
        XCTAssertEqual(headers["JPIP-tid"], "test.jph")
    }

    func testCapabilityHeadersForLegacy() {
        let support = JPIPHTJ2KSupport()
        let url = URL(fileURLWithPath: "/tmp/test.jp2")
        let info = JPIPImageInfo(url: url, format: .jp2, isHTJ2K: false)

        let headers = support.capabilityHeaders(for: info)

        XCTAssertEqual(headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(headers["JPIP-cap"], "j2k")
        XCTAssertEqual(headers["JPIP-pref"], "j2k")
        XCTAssertEqual(headers["JPIP-tid"], "test.jp2")
    }

    func testGenerateFormatMetadataHTJ2K() {
        let support = JPIPHTJ2KSupport()
        let url = URL(fileURLWithPath: "/tmp/test.jph")
        let info = JPIPImageInfo(url: url, format: .jph, isHTJ2K: true)

        let metadata = support.generateFormatMetadata(for: info)
        let metadataString = String(data: metadata, encoding: .utf8)!

        XCTAssertTrue(metadataString.contains("format=jph"))
        XCTAssertTrue(metadataString.contains("htj2k=true"))
        XCTAssertTrue(metadataString.contains("mime=image/jph"))
        XCTAssertTrue(metadataString.contains("file=test.jph"))
    }

    func testGenerateFormatMetadataLegacy() {
        let support = JPIPHTJ2KSupport()
        let url = URL(fileURLWithPath: "/tmp/test.jp2")
        let info = JPIPImageInfo(url: url, format: .jp2, isHTJ2K: false)

        let metadata = support.generateFormatMetadata(for: info)
        let metadataString = String(data: metadata, encoding: .utf8)!

        XCTAssertTrue(metadataString.contains("format=jp2"))
        XCTAssertTrue(metadataString.contains("htj2k=false"))
        XCTAssertTrue(metadataString.contains("mime=image/jp2"))
    }

    // MARK: - Preference Compatibility Tests

    func testPreferenceCompatibilityNone() {
        let support = JPIPHTJ2KSupport()
        let htInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.jph"),
            format: .jph,
            isHTJ2K: true
        )
        let legacyInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.jp2"),
            format: .jp2,
            isHTJ2K: false
        )

        XCTAssertTrue(support.isPreferenceCompatible(.none, with: htInfo))
        XCTAssertTrue(support.isPreferenceCompatible(.none, with: legacyInfo))
    }

    func testPreferenceCompatibilityHTJ2K() {
        let support = JPIPHTJ2KSupport()
        let htInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.jph"),
            format: .jph,
            isHTJ2K: true
        )
        let legacyInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.jp2"),
            format: .jp2,
            isHTJ2K: false
        )

        XCTAssertTrue(support.isPreferenceCompatible(.htj2k, with: htInfo))
        XCTAssertFalse(support.isPreferenceCompatible(.htj2k, with: legacyInfo))
    }

    func testPreferenceCompatibilityLegacy() {
        let support = JPIPHTJ2KSupport()
        let legacyInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.jp2"),
            format: .jp2,
            isHTJ2K: false
        )
        let j2kInfo = JPIPImageInfo(
            url: URL(fileURLWithPath: "/tmp/test.j2k"),
            format: .j2k,
            isHTJ2K: false
        )

        XCTAssertTrue(support.isPreferenceCompatible(.legacy, with: legacyInfo))
        XCTAssertTrue(support.isPreferenceCompatible(.legacy, with: j2kInfo))
    }

    // MARK: - JPIPRequest Coding Preference Tests

    func testRequestWithCodingPreference() {
        var request = JPIPRequest(target: "test.jph")
        request.codingPreference = .htj2k

        let items = request.buildQueryItems()
        XCTAssertEqual(items["pref"], "htj2k")
    }

    func testRequestWithLegacyPreference() {
        var request = JPIPRequest(target: "test.jp2")
        request.codingPreference = .legacy

        let items = request.buildQueryItems()
        XCTAssertEqual(items["pref"], "legacy")
    }

    func testRequestWithNoCodingPreference() {
        var request = JPIPRequest(target: "test.jp2")
        request.codingPreference = JPIPCodingPreference.none

        let items = request.buildQueryItems()
        XCTAssertNil(items["pref"])
    }

    func testRequestWithoutCodingPreference() {
        let request = JPIPRequest(target: "test.jp2")

        let items = request.buildQueryItems()
        XCTAssertNil(items["pref"])
    }

    func testRequestCodingPreferenceDefaultNil() {
        let request = JPIPRequest(target: "test.jp2")
        XCTAssertNil(request.codingPreference)
    }

    // MARK: - Format Detection Tests

    func testDetectFormatWithJ2KCodestream() throws {
        let support = JPIPHTJ2KSupport()

        // Create a minimal J2K codestream (starts with SOC marker 0xFF4F)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-detect-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x00])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let info = try support.detectFormat(at: tempURL)
        XCTAssertEqual(info.format, .j2k)
        XCTAssertFalse(info.isHTJ2K)
    }

    func testDetectFormatWithCAPMarker() throws {
        let support = JPIPHTJ2KSupport()

        // Create a J2K codestream with CAP marker (0xFF50)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-cap-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x29,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00,
                            0xFF, 0x50, 0x00, 0x08, 0x00, 0x02,
                            0x00, 0x00, 0x00, 0x20])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let info = try support.detectFormat(at: tempURL)
        XCTAssertEqual(info.format, .j2k)
        XCTAssertTrue(info.isHTJ2K)
    }

    // MARK: - Server HTJ2K Integration Tests

    func testServerRegisterHTJ2KImage() async throws {
        let server = JPIPServer(port: 9100)

        // Create a minimal J2K file with CAP marker (HTJ2K)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-htj2k-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x50, 0x00, 0x08,
                            0x00, 0x02, 0x00, 0x00, 0x00, 0x20])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "htj2k.j2k", at: tempURL)

        let images = await server.listRegisteredImages()
        XCTAssertTrue(images.contains("htj2k.j2k"))

        // Verify image info was cached
        let info = await server.getImageInfo(name: "htj2k.j2k")
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.isHTJ2K ?? false)
    }

    func testServerRegisterLegacyImage() async throws {
        let server = JPIPServer(port: 9101)

        // Create a minimal J2K file without CAP marker (legacy)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-legacy-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "legacy.j2k", at: tempURL)

        let info = await server.getImageInfo(name: "legacy.j2k")
        XCTAssertNotNil(info)
        XCTAssertFalse(info?.isHTJ2K ?? true)
    }

    func testServerUnregisterClearsImageInfo() async throws {
        let server = JPIPServer(port: 9102)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-unreg-\(UUID().uuidString).j2k")
        try Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.j2k", at: tempURL)
        let infoAfterRegister = await server.getImageInfo(name: "test.j2k")
        XCTAssertNotNil(infoAfterRegister)

        await server.unregisterImage(name: "test.j2k")
        let infoAfterUnregister = await server.getImageInfo(name: "test.j2k")
        XCTAssertNil(infoAfterUnregister)
    }

    func testServerSessionCreationIncludesHTJ2KHeaders() async throws {
        let server = JPIPServer(port: 9103)

        // Create an HTJ2K image (J2K with CAP marker)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-session-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x50, 0x00, 0x08,
                            0x00, 0x02, 0x00, 0x00, 0x00, 0x20])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "htj2k.j2k", at: tempURL)
        try await server.start()

        var request = JPIPRequest(target: "htj2k.j2k")
        request.cnew = .http

        let response = try await server.handleRequest(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["JPIP-cap"], "htj2k")
        XCTAssertEqual(response.headers["JPIP-pref"], "htj2k")

        try await server.stop()
    }

    func testServerSessionCreationLegacyHeaders() async throws {
        let server = JPIPServer(port: 9104)

        // Create a legacy image (J2K without CAP marker)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-session-leg-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "legacy.j2k", at: tempURL)
        try await server.start()

        var request = JPIPRequest(target: "legacy.j2k")
        request.cnew = .http

        let response = try await server.handleRequest(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["JPIP-cap"], "j2k")
        XCTAssertEqual(response.headers["JPIP-pref"], "j2k")

        try await server.stop()
    }

    func testServerMetadataIncludesFormatInfo() async throws {
        let server = JPIPServer(port: 9105)

        // Create an HTJ2K image
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-meta-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x50, 0x00, 0x08,
                            0x00, 0x02, 0x00, 0x00, 0x00, 0x20])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "htj2k-meta.j2k", at: tempURL)
        try await server.start()

        // Create session first
        var sessionRequest = JPIPRequest(target: "htj2k-meta.j2k")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request metadata
        var metadataRequest = JPIPRequest.metadataRequest(target: "htj2k-meta.j2k")
        metadataRequest.cid = sessionResponse.channelID

        let response = try await server.handleRequest(metadataRequest)
        XCTAssertEqual(response.statusCode, 200)

        let metadataString = String(data: response.data, encoding: .utf8)!
        XCTAssertTrue(metadataString.contains("htj2k=true"))
        XCTAssertTrue(metadataString.contains("format=j2k"))

        try await server.stop()
    }

    func testImageInfoReturnedNilForUnregistered() async throws {
        let server = JPIPServer(port: 9106)
        let info = await server.getImageInfo(name: "nonexistent.j2k")
        XCTAssertNil(info)
    }
}
