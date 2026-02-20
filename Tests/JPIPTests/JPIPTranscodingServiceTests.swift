//
// JPIPTranscodingServiceTests.swift
// J2KSwift
//
/// # JPIPTranscodingServiceTests
///
/// Tests for JPIP on-the-fly transcoding service and transcoding cache.

import XCTest
@testable import JPIP
@testable import J2KCore
@testable import J2KCodec

/// Tests for JPIPTranscodingService functionality.
final class JPIPTranscodingServiceTests: XCTestCase {
    // MARK: - Initialization Tests

    func testTranscodingServiceInitialization() {
        let service = JPIPTranscodingService()
        XCTAssertNotNil(service)
    }

    func testTranscodingServiceWithCustomConfiguration() {
        let config = TranscodingConfiguration.sequential
        let service = JPIPTranscodingService(configuration: config)
        XCTAssertNotNil(service)
    }

    // MARK: - Direction Determination Tests

    func testDetermineDirectionNoPreference() {
        let service = JPIPTranscodingService()

        let direction = service.determineDirection(preference: .none, sourceIsHTJ2K: true)
        XCTAssertNil(direction)

        let direction2 = service.determineDirection(preference: .none, sourceIsHTJ2K: false)
        XCTAssertNil(direction2)
    }

    func testDetermineDirectionHTJ2KPreferenceWithLegacySource() {
        let service = JPIPTranscodingService()

        let direction = service.determineDirection(preference: .htj2k, sourceIsHTJ2K: false)
        XCTAssertEqual(direction, .legacyToHT)
    }

    func testDetermineDirectionHTJ2KPreferenceWithHTJ2KSource() {
        let service = JPIPTranscodingService()

        let direction = service.determineDirection(preference: .htj2k, sourceIsHTJ2K: true)
        XCTAssertNil(direction) // No transcoding needed
    }

    func testDetermineDirectionLegacyPreferenceWithHTJ2KSource() {
        let service = JPIPTranscodingService()

        let direction = service.determineDirection(preference: .legacy, sourceIsHTJ2K: true)
        XCTAssertEqual(direction, .htToLegacy)
    }

    func testDetermineDirectionLegacyPreferenceWithLegacySource() {
        let service = JPIPTranscodingService()

        let direction = service.determineDirection(preference: .legacy, sourceIsHTJ2K: false)
        XCTAssertNil(direction) // No transcoding needed
    }

    // MARK: - Needs Transcoding Tests

    func testNeedsTranscodingNoPreference() {
        let service = JPIPTranscodingService()

        XCTAssertFalse(service.needsTranscoding(preference: .none, sourceIsHTJ2K: true))
        XCTAssertFalse(service.needsTranscoding(preference: .none, sourceIsHTJ2K: false))
    }

    func testNeedsTranscodingMatchingFormat() {
        let service = JPIPTranscodingService()

        XCTAssertFalse(service.needsTranscoding(preference: .htj2k, sourceIsHTJ2K: true))
        XCTAssertFalse(service.needsTranscoding(preference: .legacy, sourceIsHTJ2K: false))
    }

    func testNeedsTranscodingMismatchedFormat() {
        let service = JPIPTranscodingService()

        XCTAssertTrue(service.needsTranscoding(preference: .htj2k, sourceIsHTJ2K: false))
        XCTAssertTrue(service.needsTranscoding(preference: .legacy, sourceIsHTJ2K: true))
    }

    // MARK: - Transcoding Pass-through Tests

    func testTranscodeNoPreferenceReturnsOriginal() throws {
        let service = JPIPTranscodingService()
        let testData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04])

        let result = try service.transcode(
            data: testData,
            preference: .none,
            sourceIsHTJ2K: false
        )

        XCTAssertFalse(result.wasTranscoded)
        XCTAssertEqual(result.data, testData)
        XCTAssertNil(result.direction)
        XCTAssertEqual(result.transcodingTime, 0)
    }

    func testTranscodeMatchingFormatReturnsOriginal() throws {
        let service = JPIPTranscodingService()
        let testData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04])

        let result = try service.transcode(
            data: testData,
            preference: .legacy,
            sourceIsHTJ2K: false
        )

        XCTAssertFalse(result.wasTranscoded)
        XCTAssertEqual(result.data, testData)
    }

    // MARK: - JPIPTranscodingResult Tests

    func testTranscodingResultCreation() {
        let data = Data([0x01, 0x02, 0x03])
        let result = JPIPTranscodingResult(
            data: data,
            wasTranscoded: true,
            direction: .legacyToHT,
            transcodingTime: 0.5
        )

        XCTAssertEqual(result.data, data)
        XCTAssertTrue(result.wasTranscoded)
        XCTAssertEqual(result.direction, .legacyToHT)
        XCTAssertEqual(result.transcodingTime, 0.5)
    }

    func testTranscodingResultNotTranscoded() {
        let data = Data([0x01, 0x02])
        let result = JPIPTranscodingResult(
            data: data,
            wasTranscoded: false,
            direction: nil,
            transcodingTime: 0
        )

        XCTAssertEqual(result.data, data)
        XCTAssertFalse(result.wasTranscoded)
        XCTAssertNil(result.direction)
        XCTAssertEqual(result.transcodingTime, 0)
    }

    // MARK: - Transcoding Cache Tests

    func testTranscodingCacheInitialization() async {
        let cache = JPIPTranscodingCache()
        let count = await cache.count
        let size = await cache.size
        XCTAssertEqual(count, 0)
        XCTAssertEqual(size, 0)
    }

    func testTranscodingCachePutAndGet() async {
        let cache = JPIPTranscodingCache()
        let data = Data([0x01, 0x02, 0x03, 0x04])

        await cache.put(data: data, sourceHash: "hash1", direction: .legacyToHT)

        let retrieved = await cache.get(sourceHash: "hash1", direction: .legacyToHT)
        XCTAssertEqual(retrieved, data)
    }

    func testTranscodingCacheMiss() async {
        let cache = JPIPTranscodingCache()

        let retrieved = await cache.get(sourceHash: "nonexistent", direction: .legacyToHT)
        XCTAssertNil(retrieved)
    }

    func testTranscodingCacheDifferentDirections() async {
        let cache = JPIPTranscodingCache()
        let data1 = Data([0x01, 0x02])
        let data2 = Data([0x03, 0x04])

        await cache.put(data: data1, sourceHash: "hash1", direction: .legacyToHT)
        await cache.put(data: data2, sourceHash: "hash1", direction: .htToLegacy)

        let retrieved1 = await cache.get(sourceHash: "hash1", direction: .legacyToHT)
        let retrieved2 = await cache.get(sourceHash: "hash1", direction: .htToLegacy)

        XCTAssertEqual(retrieved1, data1)
        XCTAssertEqual(retrieved2, data2)
    }

    func testTranscodingCacheClear() async {
        let cache = JPIPTranscodingCache()
        await cache.put(data: Data([0x01]), sourceHash: "hash1", direction: .legacyToHT)
        await cache.put(data: Data([0x02]), sourceHash: "hash2", direction: .htToLegacy)

        let countBefore = await cache.count
        XCTAssertEqual(countBefore, 2)

        await cache.clear()

        let countAfter = await cache.count
        XCTAssertEqual(countAfter, 0)
    }

    func testTranscodingCacheEviction() async {
        // Small cache that can only hold 10 bytes
        let cache = JPIPTranscodingCache(maxCacheSize: 10)

        // Add entries that exceed cache size
        await cache.put(data: Data(repeating: 0x01, count: 5), sourceHash: "h1", direction: .legacyToHT)
        await cache.put(data: Data(repeating: 0x02, count: 5), sourceHash: "h2", direction: .legacyToHT)

        // Adding a third should evict the oldest
        await cache.put(data: Data(repeating: 0x03, count: 5), sourceHash: "h3", direction: .legacyToHT)

        let size = await cache.size
        XCTAssertLessThanOrEqual(size, 10)
    }

    func testTranscodingCacheHitMissCounters() async {
        let cache = JPIPTranscodingCache()
        await cache.put(data: Data([0x01]), sourceHash: "hash1", direction: .legacyToHT)

        // Hit
        _ = await cache.get(sourceHash: "hash1", direction: .legacyToHT)
        let hits = await cache.hits
        XCTAssertEqual(hits, 1)

        // Miss
        _ = await cache.get(sourceHash: "nonexistent", direction: .legacyToHT)
        let misses = await cache.misses
        XCTAssertEqual(misses, 1)
    }

    // MARK: - Server Integration with Transcoding Tests

    func testServerWithCodingPreferenceNone() async throws {
        let server = JPIPServer(port: 9200)

        // Create a minimal J2K file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-pref-none-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04, 0x00, 0x00])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.j2k", at: tempURL)
        try await server.start()

        // Create session
        var sessionRequest = JPIPRequest(target: "test.j2k")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request data with no preference
        var dataRequest = JPIPRequest(target: "test.j2k")
        dataRequest.cid = sessionResponse.channelID
        dataRequest.codingPreference = .none

        let response = try await server.handleRequest(dataRequest)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThan(response.data.count, 0)

        try await server.stop()
    }

    func testServerWithCodingPreferenceLegacyForLegacyImage() async throws {
        let server = JPIPServer(port: 9201)

        // Create a legacy J2K file (no CAP marker)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-pref-legacy-\(UUID().uuidString).j2k")
        let j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04, 0x00, 0x00])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "legacy.j2k", at: tempURL)
        try await server.start()

        // Create session
        var sessionRequest = JPIPRequest(target: "legacy.j2k")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request data with legacy preference (should be no-op since source is legacy)
        var dataRequest = JPIPRequest(target: "legacy.j2k")
        dataRequest.cid = sessionResponse.channelID
        dataRequest.codingPreference = .legacy

        let response = try await server.handleRequest(dataRequest)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThan(response.data.count, 0)

        try await server.stop()
    }

    func testServerDataBinStreamingWithJ2KCodestream() async throws {
        let server = JPIPServer(port: 9202)

        // Create a minimal J2K codestream with tile
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-databin-\(UUID().uuidString).j2k")
        let j2kData = Data([
            0xFF, 0x4F,                         // SOC
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00, // SIZ
            0xFF, 0x90, 0x00, 0x0A,             // SOT
            0x00, 0x00,                          // Tile 0
            0x00, 0x00, 0x00, 0x18,             // Length
            0x00, 0x01,
            0xFF, 0x93,                          // SOD
            0x01, 0x02, 0x03, 0x04,             // Data
            0xFF, 0xD9                           // EOC
        ])
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "stream.j2k", at: tempURL)
        try await server.start()

        // Create session
        var sessionRequest = JPIPRequest(target: "stream.j2k")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request image data - should use data bin generation
        var dataRequest = JPIPRequest(target: "stream.j2k")
        dataRequest.cid = sessionResponse.channelID

        let response = try await server.handleRequest(dataRequest)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThan(response.data.count, 0)

        try await server.stop()
    }

    func testServerResponseLengthLimit() async throws {
        let server = JPIPServer(port: 9203)

        // Create a larger J2K codestream
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-len-\(UUID().uuidString).j2k")
        var j2kData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x04, 0x00, 0x00])
        j2kData.append(Data(repeating: 0xAA, count: 1000))
        try j2kData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "large.j2k", at: tempURL)
        try await server.start()

        // Create session
        var sessionRequest = JPIPRequest(target: "large.j2k")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request with length limit
        var dataRequest = JPIPRequest(target: "large.j2k")
        dataRequest.cid = sessionResponse.channelID
        dataRequest.len = 100

        let response = try await server.handleRequest(dataRequest)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertLessThanOrEqual(response.data.count, 100)

        try await server.stop()
    }
}
