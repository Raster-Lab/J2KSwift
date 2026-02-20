//
// JPIPSessionPersistenceTests.swift
// J2KSwift
//
/// # JPIPSessionPersistenceTests
///
/// Tests for enhanced session persistence and recovery.

import XCTest
@testable import JPIP
@testable import J2KCore

// MARK: - Session State Serialization Tests

final class JPIPSessionStateSerializationTests: XCTestCase {
    // MARK: - Data Bin Serialization

    func testSerializableDataBinRoundTrip() throws {
        let original = JPIPDataBin(
            binClass: .mainHeader,
            binID: 42,
            data: Data([0x00, 0xFF, 0x90, 0x51]),
            isComplete: true
        )

        let serializable = JPIPSerializableDataBin(from: original)
        let restored = serializable.toDataBin()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.binClass, original.binClass)
        XCTAssertEqual(restored?.binID, original.binID)
        XCTAssertEqual(restored?.data, original.data)
        XCTAssertEqual(restored?.isComplete, original.isComplete)
    }

    func testSerializableDataBinInvalidClass() throws {
        let serializable = JPIPSerializableDataBin(
            from: JPIPDataBin(binClass: .metadata, binID: 0, data: Data(), isComplete: false)
        )
        // Manually create with invalid raw value
        let invalid = JPIPSerializableDataBin(
            binClassRawValue: 99,
            binID: 0,
            data: Data(),
            isComplete: false
        )
        XCTAssertNotNil(serializable.toDataBin())
        XCTAssertNil(invalid.toDataBin())
    }

    func testSerializableDataBinAllClasses() throws {
        let classes: [JPIPDataBinClass] = [
            .mainHeader, .tileHeader, .precinct, .tile, .extendedPrecinct, .metadata
        ]

        for binClass in classes {
            let original = JPIPDataBin(
                binClass: binClass,
                binID: 1,
                data: Data([0x01, 0x02]),
                isComplete: false
            )
            let serializable = JPIPSerializableDataBin(from: original)
            let restored = serializable.toDataBin()

            XCTAssertNotNil(restored, "Failed for class \(binClass)")
            XCTAssertEqual(restored?.binClass, binClass)
        }
    }

    // MARK: - Precinct Serialization

    func testSerializablePrecinctRoundTrip() throws {
        let precinctID = JPIPPrecinctID(
            tile: 1, component: 0, resolution: 3, precinctX: 5, precinctY: 7
        )
        let original = JPIPPrecinctData(
            precinctID: precinctID,
            data: Data([0xAA, 0xBB, 0xCC]),
            isComplete: false,
            receivedLayers: Set([0, 1, 3])
        )

        let serializable = JPIPSerializablePrecinct(from: original)
        let restored = serializable.toPrecinctData()

        XCTAssertEqual(restored.precinctID, precinctID)
        XCTAssertEqual(restored.data, original.data)
        XCTAssertEqual(restored.isComplete, original.isComplete)
        XCTAssertEqual(restored.receivedLayers, original.receivedLayers)
    }

    // MARK: - Session State Snapshot

    func testSessionStateSnapshotCodable() throws {
        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "test-session-1",
            channelID: "ch-42",
            target: "image.jp2",
            wasActive: true,
            dataBins: [
                JPIPSerializableDataBin(from: JPIPDataBin(
                    binClass: .mainHeader, binID: 0, data: Data([0xFF, 0x4F]), isComplete: true
                ))
            ],
            precincts: [
                JPIPSerializablePrecinct(from: JPIPPrecinctData(
                    precinctID: JPIPPrecinctID(
                        tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0
                    ),
                    data: Data([0x01]),
                    isComplete: true,
                    receivedLayers: Set([0])
                ))
            ],
            metadata: ["key": "value"],
            cacheHits: 10,
            cacheMisses: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JPIPSessionStateSnapshot.self, from: data)

        XCTAssertEqual(decoded.sessionID, "test-session-1")
        XCTAssertEqual(decoded.channelID, "ch-42")
        XCTAssertEqual(decoded.target, "image.jp2")
        XCTAssertEqual(decoded.wasActive, true)
        XCTAssertEqual(decoded.version, .v1)
        XCTAssertEqual(decoded.dataBins.count, 1)
        XCTAssertEqual(decoded.precincts.count, 1)
        XCTAssertEqual(decoded.metadata["key"], "value")
        XCTAssertEqual(decoded.cacheHits, 10)
        XCTAssertEqual(decoded.cacheMisses, 5)
    }

    func testServerSessionStateSnapshotCodable() throws {
        let snapshot = JPIPServerSessionStateSnapshot(
            sessionID: "srv-session-1",
            channelID: "srv-ch-1",
            target: "large.jp2",
            wasActive: true,
            lastActivity: Date(),
            sentDataBins: [
                JPIPSerializableDataBin(from: JPIPDataBin(
                    binClass: .tile, binID: 3, data: Data([0xDE, 0xAD]), isComplete: false
                ))
            ],
            metadata: ["client": "test"],
            totalBytesSent: 1024,
            totalRequests: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JPIPServerSessionStateSnapshot.self, from: data)

        XCTAssertEqual(decoded.sessionID, "srv-session-1")
        XCTAssertEqual(decoded.channelID, "srv-ch-1")
        XCTAssertEqual(decoded.target, "large.jp2")
        XCTAssertEqual(decoded.totalBytesSent, 1024)
        XCTAssertEqual(decoded.totalRequests, 5)
        XCTAssertEqual(decoded.sentDataBins.count, 1)
    }

    func testSessionStateVersioning() throws {
        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "test-v1",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )

        XCTAssertEqual(snapshot.version, .v1)
        XCTAssertEqual(JPIPSessionStateVersion.current, .v1)
        XCTAssertEqual(snapshot.version.rawValue, 1)
    }

    func testSnapshotWithNilOptionals() throws {
        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "minimal",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(JPIPSessionStateSnapshot.self, from: data)

        XCTAssertNil(decoded.channelID)
        XCTAssertNil(decoded.target)
        XCTAssertEqual(decoded.dataBins.count, 0)
        XCTAssertEqual(decoded.precincts.count, 0)
    }

    func testSerializableDataBinDirectInit() throws {
        // Test creating JPIPSerializableDataBin directly with invalid raw value
        let bin = JPIPSerializableDataBin(
            binClassRawValue: 999,
            binID: 42,
            data: Data([0x01]),
            isComplete: true
        )
        XCTAssertNil(bin.toDataBin())

        // Test with valid raw value
        let validBin = JPIPSerializableDataBin(
            binClassRawValue: 0,
            binID: 1,
            data: Data([0x02]),
            isComplete: false
        )
        let restored = validBin.toDataBin()
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.binClass, .mainHeader)
    }
}

// MARK: - In-Memory Persistence Store Tests

final class JPIPInMemoryPersistenceStoreTests: XCTestCase {
    func testSaveAndLoadClientSession() async throws {
        let store = JPIPInMemoryPersistenceStore()

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "mem-1",
            channelID: "ch-1",
            target: "test.jp2",
            wasActive: true,
            dataBins: [],
            precincts: [],
            metadata: ["a": "b"],
            cacheHits: 0,
            cacheMisses: 0
        )

        try await store.save(snapshot)

        let loaded = try await store.load(sessionID: "mem-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, "mem-1")
        XCTAssertEqual(loaded?.channelID, "ch-1")
        XCTAssertEqual(loaded?.target, "test.jp2")
        XCTAssertEqual(loaded?.metadata["a"], "b")
    }

    func testLoadNonexistentSession() async throws {
        let store = JPIPInMemoryPersistenceStore()

        let loaded = try await store.load(sessionID: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testRemoveSession() async throws {
        let store = JPIPInMemoryPersistenceStore()

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "remove-me",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )

        try await store.save(snapshot)
        let countBefore = await store.clientSessionCount()
        XCTAssertEqual(countBefore, 1)

        try await store.remove(sessionID: "remove-me")
        let countAfter = await store.clientSessionCount()
        XCTAssertEqual(countAfter, 0)

        let loaded = try await store.load(sessionID: "remove-me")
        XCTAssertNil(loaded)
    }

    func testListSessions() async throws {
        let store = JPIPInMemoryPersistenceStore()

        for i in 0..<3 {
            let snapshot = JPIPSessionStateSnapshot(
                sessionID: "session-\(i)",
                channelID: nil,
                target: nil,
                wasActive: false,
                dataBins: [],
                precincts: [],
                metadata: [:],
                cacheHits: 0,
                cacheMisses: 0
            )
            try await store.save(snapshot)
        }

        let sessions = try await store.listSessions()
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(sessions.contains("session-0"))
        XCTAssertTrue(sessions.contains("session-1"))
        XCTAssertTrue(sessions.contains("session-2"))
    }

    func testSaveAndLoadServerSession() async throws {
        let store = JPIPInMemoryPersistenceStore()

        let snapshot = JPIPServerSessionStateSnapshot(
            sessionID: "srv-1",
            channelID: "srv-ch-1",
            target: "server.jp2",
            wasActive: true,
            lastActivity: Date(),
            sentDataBins: [],
            metadata: ["server": "test"],
            totalBytesSent: 2048,
            totalRequests: 10
        )

        try await store.saveServerSession(snapshot)

        let loaded = try await store.loadServerSession(sessionID: "srv-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, "srv-1")
        XCTAssertEqual(loaded?.totalBytesSent, 2048)
        XCTAssertEqual(loaded?.totalRequests, 10)
    }

    func testOverwriteExistingSession() async throws {
        let store = JPIPInMemoryPersistenceStore()

        let first = JPIPSessionStateSnapshot(
            sessionID: "same-id",
            channelID: "ch-1",
            target: "first.jp2",
            wasActive: true,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(first)

        let second = JPIPSessionStateSnapshot(
            sessionID: "same-id",
            channelID: "ch-2",
            target: "second.jp2",
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 5,
            cacheMisses: 3
        )
        try await store.save(second)

        let loaded = try await store.load(sessionID: "same-id")
        XCTAssertEqual(loaded?.channelID, "ch-2")
        XCTAssertEqual(loaded?.target, "second.jp2")
        XCTAssertEqual(loaded?.cacheHits, 5)
    }
}

// MARK: - File-Based Persistence Store Tests

final class JPIPFilePersistenceStoreTests: XCTestCase {
    var testDirectory: URL!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpip_persistence_test_\(UUID().uuidString)")
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testSaveAndLoadClientSession() async throws {
        let store = try JPIPFilePersistenceStore(directory: testDirectory)

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "file-1",
            channelID: "ch-f1",
            target: "file-test.jp2",
            wasActive: true,
            dataBins: [
                JPIPSerializableDataBin(from: JPIPDataBin(
                    binClass: .mainHeader, binID: 0, data: Data([0xFF]), isComplete: true
                ))
            ],
            precincts: [],
            metadata: ["file": "test"],
            cacheHits: 7,
            cacheMisses: 2
        )

        try await store.save(snapshot)

        let loaded = try await store.load(sessionID: "file-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, "file-1")
        XCTAssertEqual(loaded?.channelID, "ch-f1")
        XCTAssertEqual(loaded?.dataBins.count, 1)
        XCTAssertEqual(loaded?.metadata["file"], "test")
    }

    func testListSessionsFromFiles() async throws {
        let store = try JPIPFilePersistenceStore(directory: testDirectory)

        for i in 0..<3 {
            let snapshot = JPIPSessionStateSnapshot(
                sessionID: "fs-\(i)",
                channelID: nil,
                target: nil,
                wasActive: false,
                dataBins: [],
                precincts: [],
                metadata: [:],
                cacheHits: 0,
                cacheMisses: 0
            )
            try await store.save(snapshot)
        }

        let sessions = try await store.listSessions()
        XCTAssertEqual(sessions.count, 3)
    }

    func testRemoveSessionFiles() async throws {
        let store = try JPIPFilePersistenceStore(directory: testDirectory)

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "removable",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        let before = try await store.load(sessionID: "removable")
        XCTAssertNotNil(before)

        try await store.remove(sessionID: "removable")

        let after = try await store.load(sessionID: "removable")
        XCTAssertNil(after)
    }

    func testSaveAndLoadServerSessionFiles() async throws {
        let store = try JPIPFilePersistenceStore(directory: testDirectory)

        let snapshot = JPIPServerSessionStateSnapshot(
            sessionID: "srv-file-1",
            channelID: "ch-sf1",
            target: "server-file.jp2",
            wasActive: true,
            lastActivity: Date(),
            sentDataBins: [],
            metadata: ["server": "file-test"],
            totalBytesSent: 4096,
            totalRequests: 20
        )

        try await store.saveServerSession(snapshot)

        let loaded = try await store.loadServerSession(sessionID: "srv-file-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, "srv-file-1")
        XCTAssertEqual(loaded?.totalBytesSent, 4096)
    }

    func testLoadNonexistentFile() async throws {
        let store = try JPIPFilePersistenceStore(directory: testDirectory)

        let loaded = try await store.load(sessionID: "nonexistent")
        XCTAssertNil(loaded)
    }
}

// MARK: - Session Recovery Tests

final class JPIPSessionRecoveryTests: XCTestCase {
    func testFullRecoveryWithDataBins() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        // Create and persist a session with data
        let session = JPIPSession(sessionID: "recover-1")
        await session.setChannelID("ch-r1")
        await session.setTarget("recover.jp2")
        await session.activate()

        let dataBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 0,
            data: Data([0xFF, 0x4F, 0xFF, 0x51]),
            isComplete: true
        )
        await session.recordDataBin(dataBin)

        // Manually create and save snapshot for reliable test
        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "recover-1",
            channelID: "ch-r1",
            target: "recover.jp2",
            wasActive: true,
            dataBins: [JPIPSerializableDataBin(from: dataBin)],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        // Recover
        let result = await manager.recoverSession(sessionID: "recover-1")

        XCTAssertTrue(result.status.isRecovered)
        XCTAssertNotNil(result.session)
        XCTAssertEqual(result.dataBinsRestored, 1)
        XCTAssertTrue(result.recoveryDuration >= 0)

        // Verify restored session
        if let recovered = result.session {
            let channelID = await recovered.channelID
            let target = await recovered.target
            let hasMainHeader = await recovered.hasDataBin(binClass: .mainHeader, binID: 0)

            XCTAssertEqual(channelID, "ch-r1")
            XCTAssertEqual(target, "recover.jp2")
            XCTAssertTrue(hasMainHeader)
        }
    }

    func testRecoveryWithPrecincts() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let precinctID = JPIPPrecinctID(
            tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0
        )
        let precinctData = JPIPPrecinctData(
            precinctID: precinctID,
            data: Data([0x01, 0x02, 0x03]),
            isComplete: true,
            receivedLayers: Set([0, 1])
        )

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "precinct-recovery",
            channelID: nil,
            target: "precincts.jp2",
            wasActive: true,
            dataBins: [],
            precincts: [JPIPSerializablePrecinct(from: precinctData)],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        let result = await manager.recoverSession(sessionID: "precinct-recovery")

        XCTAssertTrue(result.status.isRecovered)
        XCTAssertEqual(result.precinctsRestored, 1)

        if let recovered = result.session {
            let hasPrecinct = await recovered.hasPrecinct(precinctID)
            XCTAssertTrue(hasPrecinct)
        }
    }

    func testRecoveryNonexistentSession() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let result = await manager.recoverSession(sessionID: "nonexistent")

        XCTAssertFalse(result.status.isRecovered)
        XCTAssertNil(result.session)
        XCTAssertEqual(result.dataBinsRestored, 0)

        if case .failed(let reason) = result.status {
            XCTAssertTrue(reason.contains("No persisted state"))
        } else {
            XCTFail("Expected failed status")
        }
    }

    func testRecoveryExpiredSnapshot() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let configuration = JPIPSessionRecoveryConfiguration(
            maxSnapshotAge: 1 // 1 second max age
        )
        let manager = JPIPSessionPersistenceManager(
            store: store,
            configuration: configuration
        )

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "old-session",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        // Wait for snapshot to expire
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let result = await manager.recoverSession(sessionID: "old-session")

        XCTAssertFalse(result.status.isRecovered)
        if case .failed(let reason) = result.status {
            XCTAssertTrue(reason.contains("too old"))
        } else {
            XCTFail("Expected failed status for expired snapshot")
        }
    }

    func testPartialRecoveryWithLimits() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let configuration = JPIPSessionRecoveryConfiguration(
            maxDataBinsToRestore: 2,
            maxPrecinctsToRestore: 1
        )
        let manager = JPIPSessionPersistenceManager(
            store: store,
            configuration: configuration
        )

        // Create snapshot with more data bins than limit
        var dataBins: [JPIPSerializableDataBin] = []
        for i in 0..<5 {
            dataBins.append(JPIPSerializableDataBin(from: JPIPDataBin(
                binClass: .tile, binID: i, data: Data([UInt8(i)]), isComplete: true
            )))
        }

        var precincts: [JPIPSerializablePrecinct] = []
        for i in 0..<3 {
            precincts.append(JPIPSerializablePrecinct(from: JPIPPrecinctData(
                precinctID: JPIPPrecinctID(
                    tile: i, component: 0, resolution: 0, precinctX: 0, precinctY: 0
                ),
                data: Data([UInt8(i)]),
                isComplete: true,
                receivedLayers: Set([0])
            )))
        }

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "partial",
            channelID: nil,
            target: nil,
            wasActive: true,
            dataBins: dataBins,
            precincts: precincts,
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        let result = await manager.recoverSession(sessionID: "partial")

        XCTAssertTrue(result.status.isRecovered)
        XCTAssertEqual(result.dataBinsRestored, 2)
        XCTAssertEqual(result.precinctsRestored, 1)

        if case .partialRecovery(let reason) = result.status {
            XCTAssertTrue(reason.contains("2/5"))
            XCTAssertTrue(reason.contains("1/3"))
        } else {
            XCTFail("Expected partial recovery status")
        }
    }

    func testRecoveryWithoutPrecinctRestore() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let configuration = JPIPSessionRecoveryConfiguration(
            restorePrecinctCache: false
        )
        let manager = JPIPSessionPersistenceManager(
            store: store,
            configuration: configuration
        )

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "no-precincts",
            channelID: nil,
            target: nil,
            wasActive: true,
            dataBins: [],
            precincts: [JPIPSerializablePrecinct(from: JPIPPrecinctData(
                precinctID: JPIPPrecinctID(
                    tile: 0, component: 0, resolution: 0, precinctX: 0, precinctY: 0
                ),
                data: Data([0x01]),
                isComplete: true,
                receivedLayers: Set([0])
            ))],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        let result = await manager.recoverSession(sessionID: "no-precincts")
        XCTAssertEqual(result.precinctsRestored, 0)
    }

    func testServerSessionRecovery() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let serverSnapshot = JPIPServerSessionStateSnapshot(
            sessionID: "srv-recover",
            channelID: "srv-ch-r",
            target: "server-recover.jp2",
            wasActive: true,
            lastActivity: Date(),
            sentDataBins: [
                JPIPSerializableDataBin(from: JPIPDataBin(
                    binClass: .mainHeader, binID: 0, data: Data([0xFF]), isComplete: true
                ))
            ],
            metadata: ["test-key": "test-value"],
            totalBytesSent: 512,
            totalRequests: 3
        )
        try await store.saveServerSession(serverSnapshot)

        let result = await manager.recoverServerSession(sessionID: "srv-recover")

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.status.isRecovered)

        let recoveredSession = result!.session
        let sessionID = recoveredSession.sessionID
        let channelID = recoveredSession.channelID
        let target = recoveredSession.target

        XCTAssertEqual(sessionID, "srv-recover")
        XCTAssertEqual(channelID, "srv-ch-r")
        XCTAssertEqual(target, "server-recover.jp2")

        let metaValue = await recoveredSession.getMetadata("test-key")
        XCTAssertEqual(metaValue, "test-value")

        let hasMainHeader = await recoveredSession.hasDataBin(binClass: .mainHeader, binID: 0)
        XCTAssertTrue(hasMainHeader)
    }

    func testServerSessionRecoveryNonexistent() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let result = await manager.recoverServerSession(sessionID: "nonexistent")
        XCTAssertNil(result)
    }
}

// MARK: - Recovery Manager Tests

final class JPIPSessionRecoveryManagerTests: XCTestCase {
    func testRecoveryWithRetryLimit() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let persistenceManager = JPIPSessionPersistenceManager(store: store)
        let configuration = JPIPSessionRecoveryConfiguration(
            maxRetryAttempts: 2
        )
        let recoveryManager = JPIPSessionRecoveryManager(
            persistenceManager: persistenceManager,
            configuration: configuration
        )

        // No persisted state, so recovery will fail
        let result1 = await recoveryManager.recoverAfterDisconnect(sessionID: "retry-test")
        XCTAssertFalse(result1.status.isRecovered)

        let result2 = await recoveryManager.recoverAfterDisconnect(sessionID: "retry-test")
        XCTAssertFalse(result2.status.isRecovered)

        // Third attempt exceeds max (2 attempts)
        let result3 = await recoveryManager.recoverAfterDisconnect(sessionID: "retry-test")
        XCTAssertFalse(result3.status.isRecovered)

        if case .failed(let reason) = result3.status {
            XCTAssertTrue(reason.contains("retry"))
        }
    }

    func testRecoveryResetsOnSuccess() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let persistenceManager = JPIPSessionPersistenceManager(store: store)
        let configuration = JPIPSessionRecoveryConfiguration(
            maxRetryAttempts: 3
        )
        let recoveryManager = JPIPSessionRecoveryManager(
            persistenceManager: persistenceManager,
            configuration: configuration
        )

        // First attempt fails (no data)
        let result1 = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-test")
        XCTAssertFalse(result1.status.isRecovered)

        // Save some state
        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "reset-test",
            channelID: nil,
            target: nil,
            wasActive: true,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        // Second attempt succeeds
        let result2 = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-test")
        XCTAssertTrue(result2.status.isRecovered)

        // Remove state again
        try await store.remove(sessionID: "reset-test")

        // After success, retry counter is reset, so should allow fresh attempts
        let result3 = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-test")
        XCTAssertFalse(result3.status.isRecovered)
        // Not "exceeded retries" but "no data found"
        if case .failed(let reason) = result3.status {
            XCTAssertTrue(reason.contains("No persisted state"))
        }
    }

    func testRecoveryHistory() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let persistenceManager = JPIPSessionPersistenceManager(store: store)
        let recoveryManager = JPIPSessionRecoveryManager(
            persistenceManager: persistenceManager
        )

        _ = await recoveryManager.recoverAfterDisconnect(sessionID: "history-1")
        _ = await recoveryManager.recoverAfterDisconnect(sessionID: "history-2")

        let history = await recoveryManager.getRecoveryHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].sessionID, "history-1")
        XCTAssertEqual(history[1].sessionID, "history-2")

        let filtered = await recoveryManager.getRecoveryHistory(sessionID: "history-1")
        XCTAssertEqual(filtered.count, 1)
    }

    func testClearHistory() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let persistenceManager = JPIPSessionPersistenceManager(store: store)
        let recoveryManager = JPIPSessionRecoveryManager(
            persistenceManager: persistenceManager
        )

        _ = await recoveryManager.recoverAfterDisconnect(sessionID: "clear-test")

        let before = await recoveryManager.getRecoveryHistory()
        XCTAssertEqual(before.count, 1)

        await recoveryManager.clearHistory()

        let after = await recoveryManager.getRecoveryHistory()
        XCTAssertEqual(after.count, 0)
    }

    func testResetRecoveryAttempts() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let persistenceManager = JPIPSessionPersistenceManager(store: store)
        let configuration = JPIPSessionRecoveryConfiguration(
            maxRetryAttempts: 1
        )
        let recoveryManager = JPIPSessionRecoveryManager(
            persistenceManager: persistenceManager,
            configuration: configuration
        )

        // First attempt fails
        _ = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-attempts")
        // Second attempt would exceed limit
        let result = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-attempts")
        if case .failed(let reason) = result.status {
            XCTAssertTrue(reason.contains("retry"))
        }

        // Reset attempts
        await recoveryManager.resetRecoveryAttempts(sessionID: "reset-attempts")

        // Should be able to try again (fails because no data, not because of limit)
        let afterReset = await recoveryManager.recoverAfterDisconnect(sessionID: "reset-attempts")
        if case .failed(let reason) = afterReset.status {
            XCTAssertTrue(reason.contains("No persisted state"))
        }
    }
}

// MARK: - Multi-Session Concurrent Persistence Tests

final class JPIPConcurrentPersistenceTests: XCTestCase {
    func testConcurrentSessionPersistence() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        // Persist multiple sessions concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let snapshot = JPIPSessionStateSnapshot(
                        sessionID: "concurrent-\(i)",
                        channelID: "ch-\(i)",
                        target: "image-\(i).jp2",
                        wasActive: true,
                        dataBins: [
                            JPIPSerializableDataBin(from: JPIPDataBin(
                                binClass: .mainHeader,
                                binID: 0,
                                data: Data([UInt8(i)]),
                                isComplete: true
                            ))
                        ],
                        precincts: [],
                        metadata: [:],
                        cacheHits: i,
                        cacheMisses: 0
                    )
                    try await store.save(snapshot)
                }
            }
            try await group.waitForAll()
        }

        // Verify all sessions were saved
        let sessions = try await store.listSessions()
        XCTAssertEqual(sessions.count, 10)

        // Recover all concurrently
        let results = await withTaskGroup(of: JPIPSessionRecoveryResult.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await manager.recoverSession(sessionID: "concurrent-\(i)")
                }
            }

            var results: [JPIPSessionRecoveryResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let recovered = results.filter { $0.status.isRecovered }
        XCTAssertEqual(recovered.count, 10)
    }

    func testConcurrentSaveAndRemove() async throws {
        let store = JPIPInMemoryPersistenceStore()

        // Save sessions
        for i in 0..<5 {
            let snapshot = JPIPSessionStateSnapshot(
                sessionID: "sr-\(i)",
                channelID: nil,
                target: nil,
                wasActive: false,
                dataBins: [],
                precincts: [],
                metadata: [:],
                cacheHits: 0,
                cacheMisses: 0
            )
            try await store.save(snapshot)
        }

        // Concurrently remove and save new ones
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await store.remove(sessionID: "sr-\(i)")
                }
                group.addTask {
                    let snapshot = JPIPSessionStateSnapshot(
                        sessionID: "new-\(i)",
                        channelID: nil,
                        target: nil,
                        wasActive: false,
                        dataBins: [],
                        precincts: [],
                        metadata: [:],
                        cacheHits: 0,
                        cacheMisses: 0
                    )
                    try await store.save(snapshot)
                }
            }
            try await group.waitForAll()
        }

        // Verify old sessions are removed and new ones exist
        for i in 0..<5 {
            let old = try await store.load(sessionID: "sr-\(i)")
            XCTAssertNil(old)

            let new = try await store.load(sessionID: "new-\(i)")
            XCTAssertNotNil(new)
        }
    }
}

// MARK: - Backward Compatibility Tests

final class JPIPBackwardCompatibilityTests: XCTestCase {
    func testNonPersistentSessionUnaffected() async throws {
        // A session created without persistence should work identically
        let session = JPIPSession(sessionID: "no-persist")
        await session.setChannelID("ch-np")
        await session.setTarget("normal.jp2")
        await session.activate()

        let dataBin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 0,
            data: Data([0xFF, 0x4F]),
            isComplete: true
        )
        await session.recordDataBin(dataBin)

        let isActive = await session.isActive
        let channelID = await session.channelID
        let target = await session.target
        let hasData = await session.hasDataBin(binClass: .mainHeader, binID: 0)

        XCTAssertTrue(isActive)
        XCTAssertEqual(channelID, "ch-np")
        XCTAssertEqual(target, "normal.jp2")
        XCTAssertTrue(hasData)

        // Close works as before
        try await session.close()

        let afterClose = await session.isActive
        XCTAssertFalse(afterClose)
    }

    func testNonPersistentServerSessionUnaffected() async throws {
        let session = JPIPServerSession(
            sessionID: "srv-no-persist",
            channelID: "srv-ch-np",
            target: "server-normal.jp2"
        )

        await session.recordRequest(bytesSent: 100)

        let info = await session.getInfo()
        XCTAssertEqual(info.sessionID, "srv-no-persist")
        XCTAssertEqual(info.totalBytesSent, 100)
        XCTAssertEqual(info.totalRequests, 1)
        XCTAssertTrue(info.isActive)
    }

    func testRecoveryStatusProperties() {
        let full = JPIPSessionRecoveryStatus.fullRecovery
        XCTAssertTrue(full.isRecovered)

        let partial = JPIPSessionRecoveryStatus.partialRecovery(reason: "test")
        XCTAssertTrue(partial.isRecovered)

        let failed = JPIPSessionRecoveryStatus.failed(reason: "test")
        XCTAssertFalse(failed.isRecovered)
    }

    func testRecoveryConfigurationDefaults() {
        let config = JPIPSessionRecoveryConfiguration.default

        XCTAssertEqual(config.maxSnapshotAge, 3600)
        XCTAssertTrue(config.synchronizeCacheOnReconnect)
        XCTAssertTrue(config.restorePrecinctCache)
        XCTAssertEqual(config.maxDataBinsToRestore, 10_000)
        XCTAssertEqual(config.maxPrecinctsToRestore, 5_000)
        XCTAssertTrue(config.autoRetryOnFailure)
        XCTAssertEqual(config.maxRetryAttempts, 3)
    }

    func testPersistenceMetricsDefaults() {
        let metrics = JPIPPersistenceMetrics()

        XCTAssertEqual(metrics.totalSaves, 0)
        XCTAssertEqual(metrics.totalRecoveries, 0)
        XCTAssertEqual(metrics.totalRecoveryFailures, 0)
        XCTAssertEqual(metrics.lastSaveDuration, 0)
        XCTAssertEqual(metrics.lastRecoveryDuration, 0)
    }

    func testPersistenceManagerMetrics() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "metrics-test",
            channelID: nil,
            target: nil,
            wasActive: true,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        // Save via manager
        let session = JPIPSession(sessionID: "metrics-session")
        try await manager.persistSession(session)

        let metrics = await manager.metrics
        XCTAssertEqual(metrics.totalSaves, 1)

        // Recovery
        _ = await manager.recoverSession(sessionID: "metrics-test")
        let updatedMetrics = await manager.metrics
        XCTAssertEqual(updatedMetrics.totalRecoveries, 1)
    }

    func testListAndRemovePersistedSessions() async throws {
        let store = JPIPInMemoryPersistenceStore()
        let manager = JPIPSessionPersistenceManager(store: store)

        let snapshot = JPIPSessionStateSnapshot(
            sessionID: "list-test",
            channelID: nil,
            target: nil,
            wasActive: false,
            dataBins: [],
            precincts: [],
            metadata: [:],
            cacheHits: 0,
            cacheMisses: 0
        )
        try await store.save(snapshot)

        let hasPersisted = await manager.hasPersistedState(sessionID: "list-test")
        XCTAssertTrue(hasPersisted)

        let sessions = try await manager.listPersistedSessions()
        XCTAssertTrue(sessions.contains("list-test"))

        try await manager.removePersisted(sessionID: "list-test")

        let afterRemove = await manager.hasPersistedState(sessionID: "list-test")
        XCTAssertFalse(afterRemove)
    }

    func testDataBinClassAllCases() {
        let allCases = JPIPDataBinClass.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.mainHeader))
        XCTAssertTrue(allCases.contains(.tileHeader))
        XCTAssertTrue(allCases.contains(.precinct))
        XCTAssertTrue(allCases.contains(.tile))
        XCTAssertTrue(allCases.contains(.extendedPrecinct))
        XCTAssertTrue(allCases.contains(.metadata))
    }
}

// MARK: - Recovery Event Tests

final class JPIPRecoveryEventTests: XCTestCase {
    func testRecoveryEventCreation() {
        let event = JPIPRecoveryEvent(
            sessionID: "event-test",
            timestamp: Date(),
            status: .fullRecovery,
            attempt: 1
        )

        XCTAssertEqual(event.sessionID, "event-test")
        XCTAssertEqual(event.attempt, 1)
        XCTAssertTrue(event.status.isRecovered)
    }

    func testRecoveryEventFailedStatus() {
        let event = JPIPRecoveryEvent(
            sessionID: "failed-event",
            timestamp: Date(),
            status: .failed(reason: "test failure"),
            attempt: 3
        )

        XCTAssertEqual(event.sessionID, "failed-event")
        XCTAssertEqual(event.attempt, 3)
        XCTAssertFalse(event.status.isRecovered)
    }
}
