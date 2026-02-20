/// # JPIPSessionPersistence
///
/// Enhanced session persistence and recovery for JPIP protocol.
///
/// Provides serializable session state, persistent storage (file-based and in-memory),
/// session state versioning, and automatic session recovery after disconnection.

import Foundation
import J2KCore

// MARK: - Session State Version

/// Version identifier for session state serialization format.
///
/// Enables forward compatibility by allowing older versions to detect
/// and handle newer serialization formats gracefully.
public enum JPIPSessionStateVersion: Int, Codable, Sendable {
    /// Initial version of session state format.
    case v1 = 1

    /// The current version used for new serializations.
    public static let current: JPIPSessionStateVersion = .v1
}

// MARK: - Serializable Data Bin

/// A Codable representation of a JPIP data bin for serialization.
public struct JPIPSerializableDataBin: Codable, Sendable {
    /// The data bin class raw value.
    public let binClassRawValue: Int

    /// The data bin ID.
    public let binID: Int

    /// The data content.
    public let data: Data

    /// Whether this is the complete bin.
    public let isComplete: Bool

    /// Creates a serializable data bin with explicit values.
    ///
    /// - Parameters:
    ///   - binClassRawValue: The raw integer value of the bin class.
    ///   - binID: The data bin ID.
    ///   - data: The data content.
    ///   - isComplete: Whether this is the complete bin.
    public init(binClassRawValue: Int, binID: Int, data: Data, isComplete: Bool) {
        self.binClassRawValue = binClassRawValue
        self.binID = binID
        self.data = data
        self.isComplete = isComplete
    }

    /// Creates a serializable data bin from a JPIPDataBin.
    ///
    /// - Parameter dataBin: The data bin to serialize.
    public init(from dataBin: JPIPDataBin) {
        self.binClassRawValue = dataBin.binClass.rawValue
        self.binID = dataBin.binID
        self.data = dataBin.data
        self.isComplete = dataBin.isComplete
    }

    /// Converts back to a JPIPDataBin.
    ///
    /// - Returns: The reconstructed data bin, or nil if the bin class is invalid.
    public func toDataBin() -> JPIPDataBin? {
        guard let binClass = JPIPDataBinClass(rawValue: binClassRawValue) else {
            return nil
        }
        return JPIPDataBin(
            binClass: binClass,
            binID: binID,
            data: data,
            isComplete: isComplete
        )
    }
}

// MARK: - Serializable Precinct

/// A Codable representation of a JPIP precinct for serialization.
public struct JPIPSerializablePrecinct: Codable, Sendable {
    /// Precinct identifier components.
    public let tile: Int
    public let component: Int
    public let resolution: Int
    public let precinctX: Int
    public let precinctY: Int

    /// The cached data.
    public let data: Data

    /// Whether this precinct is complete.
    public let isComplete: Bool

    /// Quality layers that have been received.
    public let receivedLayers: [Int]

    /// Creates a serializable precinct from JPIPPrecinctData.
    ///
    /// - Parameter precinctData: The precinct data to serialize.
    public init(from precinctData: JPIPPrecinctData) {
        self.tile = precinctData.precinctID.tile
        self.component = precinctData.precinctID.component
        self.resolution = precinctData.precinctID.resolution
        self.precinctX = precinctData.precinctID.precinctX
        self.precinctY = precinctData.precinctID.precinctY
        self.data = precinctData.data
        self.isComplete = precinctData.isComplete
        self.receivedLayers = Array(precinctData.receivedLayers).sorted()
    }

    /// Converts back to JPIPPrecinctData.
    ///
    /// - Returns: The reconstructed precinct data.
    public func toPrecinctData() -> JPIPPrecinctData {
        let precinctID = JPIPPrecinctID(
            tile: tile,
            component: component,
            resolution: resolution,
            precinctX: precinctX,
            precinctY: precinctY
        )
        return JPIPPrecinctData(
            precinctID: precinctID,
            data: data,
            isComplete: isComplete,
            receivedLayers: Set(receivedLayers)
        )
    }
}

// MARK: - Session State Snapshot

/// A complete serializable snapshot of a JPIP session's state.
///
/// Captures all session state needed for persistence and recovery,
/// including channel information, cache model, and precinct data.
public struct JPIPSessionStateSnapshot: Codable, Sendable {
    /// The serialization format version.
    public let version: JPIPSessionStateVersion

    /// The unique session identifier.
    public let sessionID: String

    /// The channel ID assigned by the server.
    public let channelID: String?

    /// The target image being accessed.
    public let target: String?

    /// Whether the session was active when serialized.
    public let wasActive: Bool

    /// Timestamp when the snapshot was created.
    public let snapshotTimestamp: Date

    /// Cached data bins.
    public let dataBins: [JPIPSerializableDataBin]

    /// Cached precincts.
    public let precincts: [JPIPSerializablePrecinct]

    /// Session metadata (key-value pairs).
    public let metadata: [String: String]

    /// Cache statistics at time of snapshot.
    public let cacheHits: Int
    public let cacheMisses: Int

    /// Creates a session state snapshot.
    ///
    /// - Parameters:
    ///   - sessionID: The session identifier.
    ///   - channelID: The channel ID, if any.
    ///   - target: The target image, if any.
    ///   - wasActive: Whether the session was active.
    ///   - dataBins: Cached data bins.
    ///   - precincts: Cached precincts.
    ///   - metadata: Session metadata.
    ///   - cacheHits: Number of cache hits.
    ///   - cacheMisses: Number of cache misses.
    public init(
        sessionID: String,
        channelID: String?,
        target: String?,
        wasActive: Bool,
        dataBins: [JPIPSerializableDataBin],
        precincts: [JPIPSerializablePrecinct],
        metadata: [String: String],
        cacheHits: Int,
        cacheMisses: Int
    ) {
        self.version = .current
        self.sessionID = sessionID
        self.channelID = channelID
        self.target = target
        self.wasActive = wasActive
        self.snapshotTimestamp = Date()
        self.dataBins = dataBins
        self.precincts = precincts
        self.metadata = metadata
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
    }
}

// MARK: - Server Session State Snapshot

/// A complete serializable snapshot of a server-side JPIP session.
public struct JPIPServerSessionStateSnapshot: Codable, Sendable {
    /// The serialization format version.
    public let version: JPIPSessionStateVersion

    /// The unique session identifier.
    public let sessionID: String

    /// The channel ID.
    public let channelID: String

    /// The target image.
    public let target: String

    /// Whether the session was active when serialized.
    public let wasActive: Bool

    /// Timestamp when the snapshot was created.
    public let snapshotTimestamp: Date

    /// Last activity timestamp.
    public let lastActivity: Date

    /// Data bins sent to client.
    public let sentDataBins: [JPIPSerializableDataBin]

    /// Session metadata.
    public let metadata: [String: String]

    /// Total bytes sent.
    public let totalBytesSent: Int

    /// Total requests handled.
    public let totalRequests: Int

    /// Creates a server session state snapshot.
    public init(
        sessionID: String,
        channelID: String,
        target: String,
        wasActive: Bool,
        lastActivity: Date,
        sentDataBins: [JPIPSerializableDataBin],
        metadata: [String: String],
        totalBytesSent: Int,
        totalRequests: Int
    ) {
        self.version = .current
        self.sessionID = sessionID
        self.channelID = channelID
        self.target = target
        self.wasActive = wasActive
        self.snapshotTimestamp = Date()
        self.lastActivity = lastActivity
        self.sentDataBins = sentDataBins
        self.metadata = metadata
        self.totalBytesSent = totalBytesSent
        self.totalRequests = totalRequests
    }
}

// MARK: - Session Persistence Store Protocol

/// Protocol for session state persistence backends.
///
/// Implementations provide storage for serialized session state,
/// supporting both file-based and in-memory backends.
public protocol JPIPSessionPersistenceStore: Sendable {
    /// Saves a client session state snapshot.
    ///
    /// - Parameter snapshot: The session state to save.
    /// - Throws: If the save operation fails.
    func save(_ snapshot: JPIPSessionStateSnapshot) async throws

    /// Loads a client session state snapshot.
    ///
    /// - Parameter sessionID: The session identifier to load.
    /// - Returns: The loaded snapshot, or nil if not found.
    /// - Throws: If the load operation fails.
    func load(sessionID: String) async throws -> JPIPSessionStateSnapshot?

    /// Removes a saved session state.
    ///
    /// - Parameter sessionID: The session identifier to remove.
    /// - Throws: If the removal fails.
    func remove(sessionID: String) async throws

    /// Lists all saved session identifiers.
    ///
    /// - Returns: Array of saved session IDs.
    /// - Throws: If listing fails.
    func listSessions() async throws -> [String]

    /// Saves a server session state snapshot.
    ///
    /// - Parameter snapshot: The server session state to save.
    /// - Throws: If the save operation fails.
    func saveServerSession(_ snapshot: JPIPServerSessionStateSnapshot) async throws

    /// Loads a server session state snapshot.
    ///
    /// - Parameter sessionID: The session identifier to load.
    /// - Returns: The loaded snapshot, or nil if not found.
    /// - Throws: If the load operation fails.
    func loadServerSession(sessionID: String) async throws -> JPIPServerSessionStateSnapshot?
}

// MARK: - In-Memory Persistence Store

/// An in-memory session persistence store for testing and ephemeral use.
///
/// Stores session state in memory without any disk I/O. Data is lost
/// when the store is deallocated.
public actor JPIPInMemoryPersistenceStore: JPIPSessionPersistenceStore {
    /// Stored client session snapshots.
    private var clientSessions: [String: Data] = [:]

    /// Stored server session snapshots.
    private var serverSessions: [String: Data] = [:]

    /// JSON encoder for serialization.
    private let encoder = JSONEncoder()

    /// JSON decoder for deserialization.
    private let decoder = JSONDecoder()

    /// Creates a new in-memory persistence store.
    public init() {}

    public func save(_ snapshot: JPIPSessionStateSnapshot) async throws {
        let data = try encoder.encode(snapshot)
        clientSessions[snapshot.sessionID] = data
    }

    public func load(sessionID: String) async throws -> JPIPSessionStateSnapshot? {
        guard let data = clientSessions[sessionID] else {
            return nil
        }
        return try decoder.decode(JPIPSessionStateSnapshot.self, from: data)
    }

    public func remove(sessionID: String) async throws {
        clientSessions.removeValue(forKey: sessionID)
        serverSessions.removeValue(forKey: sessionID)
    }

    public func listSessions() async throws -> [String] {
        Array(clientSessions.keys)
    }

    public func saveServerSession(_ snapshot: JPIPServerSessionStateSnapshot) async throws {
        let data = try encoder.encode(snapshot)
        serverSessions[snapshot.sessionID] = data
    }

    public func loadServerSession(sessionID: String) async throws -> JPIPServerSessionStateSnapshot? {
        guard let data = serverSessions[sessionID] else {
            return nil
        }
        return try decoder.decode(JPIPServerSessionStateSnapshot.self, from: data)
    }

    /// Returns the number of stored client sessions.
    public func clientSessionCount() -> Int {
        clientSessions.count
    }

    /// Returns the number of stored server sessions.
    public func serverSessionCount() -> Int {
        serverSessions.count
    }
}

// MARK: - File-Based Persistence Store

/// A file-based session persistence store using JSON serialization.
///
/// Stores each session as a separate JSON file in a configurable directory.
/// Provides durable persistence across application restarts.
public actor JPIPFilePersistenceStore: JPIPSessionPersistenceStore {
    /// The directory where session files are stored.
    private let directory: URL

    /// JSON encoder for serialization.
    private let encoder: JSONEncoder

    /// JSON decoder for deserialization.
    private let decoder: JSONDecoder

    /// Creates a new file-based persistence store.
    ///
    /// - Parameter directory: The directory for storing session files.
    ///   The directory will be created if it does not exist.
    /// - Throws: If the directory cannot be created.
    public init(directory: URL) throws {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func save(_ snapshot: JPIPSessionStateSnapshot) async throws {
        let data = try encoder.encode(snapshot)
        let fileURL = clientSessionURL(for: snapshot.sessionID)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(sessionID: String) async throws -> JPIPSessionStateSnapshot? {
        let fileURL = clientSessionURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(JPIPSessionStateSnapshot.self, from: data)
    }

    public func remove(sessionID: String) async throws {
        let clientURL = clientSessionURL(for: sessionID)
        let serverURL = serverSessionURL(for: sessionID)

        if FileManager.default.fileExists(atPath: clientURL.path) {
            try FileManager.default.removeItem(at: clientURL)
        }
        if FileManager.default.fileExists(atPath: serverURL.path) {
            try FileManager.default.removeItem(at: serverURL)
        }
    }

    public func listSessions() async throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return contents
            .filter { $0.pathExtension == "jpipsession" }
            .compactMap { url -> String? in
                let name = url.deletingPathExtension().lastPathComponent
                if name.hasPrefix("client_") {
                    return String(name.dropFirst(7))
                }
                return nil
            }
    }

    public func saveServerSession(_ snapshot: JPIPServerSessionStateSnapshot) async throws {
        let data = try encoder.encode(snapshot)
        let fileURL = serverSessionURL(for: snapshot.sessionID)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadServerSession(sessionID: String) async throws -> JPIPServerSessionStateSnapshot? {
        let fileURL = serverSessionURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(JPIPServerSessionStateSnapshot.self, from: data)
    }

    /// File URL for a client session.
    private func clientSessionURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("client_\(sessionID).jpipsession")
    }

    /// File URL for a server session.
    private func serverSessionURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("server_\(sessionID).jpipsession")
    }
}

// MARK: - Session Recovery Status

/// Describes the outcome of a session recovery attempt.
public enum JPIPSessionRecoveryStatus: Sendable {
    /// Full recovery — all state restored successfully.
    case fullRecovery

    /// Partial recovery — some state could not be restored.
    case partialRecovery(reason: String)

    /// Recovery failed — a new session is needed.
    case failed(reason: String)

    /// Whether recovery succeeded (fully or partially).
    public var isRecovered: Bool {
        switch self {
        case .fullRecovery, .partialRecovery:
            return true
        case .failed:
            return false
        }
    }
}

// MARK: - Session Recovery Configuration

/// Configuration for session recovery behavior.
public struct JPIPSessionRecoveryConfiguration: Sendable {
    /// Maximum age of a snapshot for recovery (in seconds).
    /// Snapshots older than this are considered stale.
    public let maxSnapshotAge: TimeInterval

    /// Whether to attempt cache model synchronization on reconnect.
    public let synchronizeCacheOnReconnect: Bool

    /// Whether to restore precinct cache data.
    public let restorePrecinctCache: Bool

    /// Maximum number of data bins to restore from snapshot.
    /// Limits memory usage during recovery.
    public let maxDataBinsToRestore: Int

    /// Maximum number of precincts to restore from snapshot.
    public let maxPrecinctsToRestore: Int

    /// Whether to automatically retry recovery on failure.
    public let autoRetryOnFailure: Bool

    /// Maximum number of automatic retry attempts.
    public let maxRetryAttempts: Int

    /// Default recovery configuration.
    public static let `default` = JPIPSessionRecoveryConfiguration(
        maxSnapshotAge: 3600,
        synchronizeCacheOnReconnect: true,
        restorePrecinctCache: true,
        maxDataBinsToRestore: 10_000,
        maxPrecinctsToRestore: 5_000,
        autoRetryOnFailure: true,
        maxRetryAttempts: 3
    )

    /// Creates a recovery configuration.
    ///
    /// - Parameters:
    ///   - maxSnapshotAge: Maximum snapshot age in seconds (default: 3600).
    ///   - synchronizeCacheOnReconnect: Whether to sync cache on reconnect (default: true).
    ///   - restorePrecinctCache: Whether to restore precincts (default: true).
    ///   - maxDataBinsToRestore: Maximum data bins to restore (default: 10,000).
    ///   - maxPrecinctsToRestore: Maximum precincts to restore (default: 5,000).
    ///   - autoRetryOnFailure: Whether to auto-retry (default: true).
    ///   - maxRetryAttempts: Max retry attempts (default: 3).
    public init(
        maxSnapshotAge: TimeInterval = 3600,
        synchronizeCacheOnReconnect: Bool = true,
        restorePrecinctCache: Bool = true,
        maxDataBinsToRestore: Int = 10_000,
        maxPrecinctsToRestore: Int = 5_000,
        autoRetryOnFailure: Bool = true,
        maxRetryAttempts: Int = 3
    ) {
        self.maxSnapshotAge = maxSnapshotAge
        self.synchronizeCacheOnReconnect = synchronizeCacheOnReconnect
        self.restorePrecinctCache = restorePrecinctCache
        self.maxDataBinsToRestore = maxDataBinsToRestore
        self.maxPrecinctsToRestore = maxPrecinctsToRestore
        self.autoRetryOnFailure = autoRetryOnFailure
        self.maxRetryAttempts = maxRetryAttempts
    }
}

// MARK: - Session Recovery Result

/// The result of a session recovery operation.
public struct JPIPSessionRecoveryResult: Sendable {
    /// The recovery status.
    public let status: JPIPSessionRecoveryStatus

    /// The recovered session, if recovery succeeded.
    public let session: JPIPSession?

    /// Number of data bins restored.
    public let dataBinsRestored: Int

    /// Number of precincts restored.
    public let precinctsRestored: Int

    /// Time taken for recovery.
    public let recoveryDuration: TimeInterval

    /// Creates a recovery result.
    public init(
        status: JPIPSessionRecoveryStatus,
        session: JPIPSession?,
        dataBinsRestored: Int,
        precinctsRestored: Int,
        recoveryDuration: TimeInterval
    ) {
        self.status = status
        self.session = session
        self.dataBinsRestored = dataBinsRestored
        self.precinctsRestored = precinctsRestored
        self.recoveryDuration = recoveryDuration
    }
}

// MARK: - Session Persistence Manager

/// Manages session persistence and recovery for JPIP sessions.
///
/// Coordinates serialization, storage, and recovery of both client
/// and server session state. Supports automatic persistence on
/// session events and recovery after disconnection.
public actor JPIPSessionPersistenceManager {
    /// The persistence store backend.
    private let store: JPIPSessionPersistenceStore

    /// Recovery configuration.
    private let recoveryConfiguration: JPIPSessionRecoveryConfiguration

    /// Tracks active persistence subscriptions.
    private var persistedSessions: Set<String> = []

    /// Performance metrics.
    public private(set) var metrics: JPIPPersistenceMetrics

    /// Creates a session persistence manager.
    ///
    /// - Parameters:
    ///   - store: The persistence store to use.
    ///   - configuration: Recovery configuration (default: `.default`).
    public init(
        store: JPIPSessionPersistenceStore,
        configuration: JPIPSessionRecoveryConfiguration = .default
    ) {
        self.store = store
        self.recoveryConfiguration = configuration
        self.metrics = JPIPPersistenceMetrics()
    }

    // MARK: - Client Session Persistence

    /// Persists the current state of a client session.
    ///
    /// Creates a snapshot of the session's state and saves it to the store.
    ///
    /// - Parameter session: The session to persist.
    /// - Throws: If serialization or saving fails.
    public func persistSession(_ session: JPIPSession) async throws {
        let startTime = Date()

        let snapshot = await createClientSnapshot(session)
        try await store.save(snapshot)

        persistedSessions.insert(snapshot.sessionID)
        metrics.totalSaves += 1
        metrics.lastSaveDuration = Date().timeIntervalSince(startTime)
    }

    /// Recovers a client session from persisted state.
    ///
    /// Loads the session snapshot and restores the session state,
    /// including cache model and precinct data.
    ///
    /// - Parameter sessionID: The session identifier to recover.
    /// - Returns: The recovery result containing status and recovered session.
    public func recoverSession(sessionID: String) async -> JPIPSessionRecoveryResult {
        let startTime = Date()

        // Load the snapshot
        guard let snapshot = try? await store.load(sessionID: sessionID) else {
            metrics.totalRecoveryFailures += 1
            return JPIPSessionRecoveryResult(
                status: .failed(reason: "No persisted state found for session \(sessionID)"),
                session: nil,
                dataBinsRestored: 0,
                precinctsRestored: 0,
                recoveryDuration: Date().timeIntervalSince(startTime)
            )
        }

        // Check snapshot age
        let snapshotAge = Date().timeIntervalSince(snapshot.snapshotTimestamp)
        if snapshotAge > recoveryConfiguration.maxSnapshotAge {
            metrics.totalRecoveryFailures += 1
            return JPIPSessionRecoveryResult(
                status: .failed(reason: "Snapshot is too old (\(Int(snapshotAge))s > \(Int(recoveryConfiguration.maxSnapshotAge))s)"),
                session: nil,
                dataBinsRestored: 0,
                precinctsRestored: 0,
                recoveryDuration: Date().timeIntervalSince(startTime)
            )
        }

        // Check version compatibility
        guard snapshot.version == .current else {
            metrics.totalRecoveryFailures += 1
            return JPIPSessionRecoveryResult(
                status: .failed(reason: "Incompatible snapshot version: \(snapshot.version.rawValue)"),
                session: nil,
                dataBinsRestored: 0,
                precinctsRestored: 0,
                recoveryDuration: Date().timeIntervalSince(startTime)
            )
        }

        // Create a new session and restore state
        let session = JPIPSession(sessionID: snapshot.sessionID)

        if let channelID = snapshot.channelID {
            await session.setChannelID(channelID)
        }
        if let target = snapshot.target {
            await session.setTarget(target)
        }

        // Restore data bins (up to configured limit)
        var dataBinsRestored = 0
        let dataBinsToRestore = Array(
            snapshot.dataBins.prefix(recoveryConfiguration.maxDataBinsToRestore)
        )
        for serializedBin in dataBinsToRestore {
            if let dataBin = serializedBin.toDataBin() {
                await session.recordDataBin(dataBin)
                dataBinsRestored += 1
            }
        }

        // Restore precincts if configured
        var precinctsRestored = 0
        if recoveryConfiguration.restorePrecinctCache {
            let precinctsToRestore = Array(
                snapshot.precincts.prefix(recoveryConfiguration.maxPrecinctsToRestore)
            )
            for serializedPrecinct in precinctsToRestore {
                let precinctData = serializedPrecinct.toPrecinctData()
                await session.addPrecinct(precinctData)
                precinctsRestored += 1
            }
        }

        // Determine recovery status
        let isPartial = dataBinsRestored < snapshot.dataBins.count ||
            precinctsRestored < snapshot.precincts.count
        let status: JPIPSessionRecoveryStatus
        if isPartial {
            let reason = "Restored \(dataBinsRestored)/\(snapshot.dataBins.count) data bins, " +
                "\(precinctsRestored)/\(snapshot.precincts.count) precincts"
            status = .partialRecovery(reason: reason)
        } else {
            status = .fullRecovery
        }

        let duration = Date().timeIntervalSince(startTime)
        metrics.totalRecoveries += 1
        metrics.lastRecoveryDuration = duration

        return JPIPSessionRecoveryResult(
            status: status,
            session: session,
            dataBinsRestored: dataBinsRestored,
            precinctsRestored: precinctsRestored,
            recoveryDuration: duration
        )
    }

    // MARK: - Server Session Persistence

    /// Persists the current state of a server session.
    ///
    /// - Parameter session: The server session to persist.
    /// - Throws: If serialization or saving fails.
    public func persistServerSession(_ session: JPIPServerSession) async throws {
        let startTime = Date()

        let snapshot = await createServerSnapshot(session)
        try await store.saveServerSession(snapshot)

        persistedSessions.insert(snapshot.sessionID)
        metrics.totalSaves += 1
        metrics.lastSaveDuration = Date().timeIntervalSince(startTime)
    }

    /// Recovers a server session from persisted state.
    ///
    /// - Parameter sessionID: The session identifier to recover.
    /// - Returns: The recovered server session, or nil if recovery fails.
    public func recoverServerSession(
        sessionID: String
    ) async -> (session: JPIPServerSession, status: JPIPSessionRecoveryStatus)? {
        guard let snapshot = try? await store.loadServerSession(sessionID: sessionID) else {
            metrics.totalRecoveryFailures += 1
            return nil
        }

        let snapshotAge = Date().timeIntervalSince(snapshot.snapshotTimestamp)
        if snapshotAge > recoveryConfiguration.maxSnapshotAge {
            metrics.totalRecoveryFailures += 1
            return nil
        }

        let session = JPIPServerSession(
            sessionID: snapshot.sessionID,
            channelID: snapshot.channelID,
            target: snapshot.target
        )

        // Restore sent data bins
        var dataBinsRestored = 0
        for serializedBin in snapshot.sentDataBins.prefix(recoveryConfiguration.maxDataBinsToRestore) {
            if let dataBin = serializedBin.toDataBin() {
                await session.recordSentDataBin(dataBin)
                dataBinsRestored += 1
            }
        }

        // Restore metadata
        for (key, value) in snapshot.metadata {
            await session.setMetadata(key, value: value)
        }

        let isPartial = dataBinsRestored < snapshot.sentDataBins.count
        let status: JPIPSessionRecoveryStatus = isPartial
            ? .partialRecovery(reason: "Restored \(dataBinsRestored)/\(snapshot.sentDataBins.count) data bins")
            : .fullRecovery

        metrics.totalRecoveries += 1
        return (session: session, status: status)
    }

    // MARK: - Session Management

    /// Removes persisted state for a session.
    ///
    /// - Parameter sessionID: The session identifier to remove.
    public func removePersisted(sessionID: String) async throws {
        try await store.remove(sessionID: sessionID)
        persistedSessions.remove(sessionID)
    }

    /// Lists all persisted session identifiers.
    ///
    /// - Returns: Array of session IDs that have been persisted.
    public func listPersistedSessions() async throws -> [String] {
        try await store.listSessions()
    }

    /// Checks if a session has persisted state.
    ///
    /// - Parameter sessionID: The session identifier to check.
    /// - Returns: True if persisted state exists.
    public func hasPersistedState(sessionID: String) async -> Bool {
        (try? await store.load(sessionID: sessionID)) != nil
    }

    // MARK: - Snapshot Creation

    /// Creates a client session snapshot from the current session state.
    private func createClientSnapshot(_ session: JPIPSession) async -> JPIPSessionStateSnapshot {
        let sessionID = session.sessionID
        let channelID = await session.channelID
        let target = await session.target
        let isActive = await session.isActive
        let cacheStats = await session.getCacheStatistics()

        // Collect data bins from cache
        var dataBins: [JPIPSerializableDataBin] = []
        for binClass in JPIPDataBinClass.allCases {
            for binID in 0..<100 {
                if let dataBin = await session.getDataBin(binClass: binClass, binID: binID) {
                    dataBins.append(JPIPSerializableDataBin(from: dataBin))
                }
            }
        }

        return JPIPSessionStateSnapshot(
            sessionID: sessionID,
            channelID: channelID,
            target: target,
            wasActive: isActive,
            dataBins: dataBins,
            precincts: [],
            metadata: [:],
            cacheHits: cacheStats.hits,
            cacheMisses: cacheStats.misses
        )
    }

    /// Creates a server session snapshot from the current session state.
    private func createServerSnapshot(
        _ session: JPIPServerSession
    ) async -> JPIPServerSessionStateSnapshot {
        let info = await session.getInfo()

        // Collect data bins that were sent
        var sentBins: [JPIPSerializableDataBin] = []
        for binClass in JPIPDataBinClass.allCases {
            for binID in 0..<100 {
                if await session.hasDataBin(binClass: binClass, binID: binID) {
                    let dataBin = JPIPDataBin(
                        binClass: binClass,
                        binID: binID,
                        data: Data(),
                        isComplete: true
                    )
                    sentBins.append(JPIPSerializableDataBin(from: dataBin))
                }
            }
        }

        return JPIPServerSessionStateSnapshot(
            sessionID: info.sessionID,
            channelID: info.channelID,
            target: info.target,
            wasActive: info.isActive,
            lastActivity: info.lastActivity,
            sentDataBins: sentBins,
            metadata: [:],
            totalBytesSent: info.totalBytesSent,
            totalRequests: info.totalRequests
        )
    }
}

// MARK: - Persistence Metrics

/// Performance metrics for session persistence operations.
public struct JPIPPersistenceMetrics: Sendable {
    /// Total number of save operations.
    public var totalSaves: Int = 0

    /// Total number of recovery operations.
    public var totalRecoveries: Int = 0

    /// Total number of failed recovery attempts.
    public var totalRecoveryFailures: Int = 0

    /// Duration of the last save operation.
    public var lastSaveDuration: TimeInterval = 0

    /// Duration of the last recovery operation.
    public var lastRecoveryDuration: TimeInterval = 0

    /// Creates default metrics.
    public init() {}
}

// MARK: - JPIPDataBinClass CaseIterable

extension JPIPDataBinClass: CaseIterable {
    /// All data bin class cases.
    public static var allCases: [JPIPDataBinClass] {
        [.mainHeader, .tileHeader, .precinct, .tile, .extendedPrecinct, .metadata]
    }
}

// MARK: - Session Recovery Manager

/// Manages automatic session recovery after disconnection.
///
/// Monitors session health and performs automatic recovery when
/// a disconnect is detected, with configurable retry behavior.
public actor JPIPSessionRecoveryManager {
    /// The persistence manager for loading/saving state.
    private let persistenceManager: JPIPSessionPersistenceManager

    /// Recovery configuration.
    private let configuration: JPIPSessionRecoveryConfiguration

    /// Active recovery attempts per session.
    private var recoveryAttempts: [String: Int] = [:]

    /// Recovery history for diagnostics.
    private var recoveryHistory: [JPIPRecoveryEvent] = []

    /// Creates a session recovery manager.
    ///
    /// - Parameters:
    ///   - persistenceManager: The persistence manager to use.
    ///   - configuration: Recovery configuration.
    public init(
        persistenceManager: JPIPSessionPersistenceManager,
        configuration: JPIPSessionRecoveryConfiguration = .default
    ) {
        self.persistenceManager = persistenceManager
        self.configuration = configuration
    }

    /// Attempts to recover a session after disconnection.
    ///
    /// Implements retry logic with graceful degradation when full
    /// recovery is not possible.
    ///
    /// - Parameter sessionID: The session to recover.
    /// - Returns: The recovery result.
    public func recoverAfterDisconnect(
        sessionID: String
    ) async -> JPIPSessionRecoveryResult {
        let attempt = (recoveryAttempts[sessionID] ?? 0) + 1
        recoveryAttempts[sessionID] = attempt

        // Check if we've exceeded retry limit
        if attempt > configuration.maxRetryAttempts {
            let event = JPIPRecoveryEvent(
                sessionID: sessionID,
                timestamp: Date(),
                status: .failed(reason: "Exceeded maximum retry attempts (\(configuration.maxRetryAttempts))"),
                attempt: attempt
            )
            recoveryHistory.append(event)

            return JPIPSessionRecoveryResult(
                status: .failed(reason: "Exceeded maximum retry attempts"),
                session: nil,
                dataBinsRestored: 0,
                precinctsRestored: 0,
                recoveryDuration: 0
            )
        }

        // Attempt recovery
        let result = await persistenceManager.recoverSession(sessionID: sessionID)

        let event = JPIPRecoveryEvent(
            sessionID: sessionID,
            timestamp: Date(),
            status: result.status,
            attempt: attempt
        )
        recoveryHistory.append(event)

        // Reset attempts on success
        if result.status.isRecovered {
            recoveryAttempts[sessionID] = 0
        }

        return result
    }

    /// Resets recovery attempts for a session.
    ///
    /// Call this when a session successfully reconnects.
    ///
    /// - Parameter sessionID: The session identifier.
    public func resetRecoveryAttempts(sessionID: String) {
        recoveryAttempts[sessionID] = 0
    }

    /// Gets recovery history for diagnostics.
    ///
    /// - Returns: Array of recovery events.
    public func getRecoveryHistory() -> [JPIPRecoveryEvent] {
        recoveryHistory
    }

    /// Gets recovery history for a specific session.
    ///
    /// - Parameter sessionID: The session identifier.
    /// - Returns: Array of recovery events for the session.
    public func getRecoveryHistory(sessionID: String) -> [JPIPRecoveryEvent] {
        recoveryHistory.filter { $0.sessionID == sessionID }
    }

    /// Clears recovery history.
    public func clearHistory() {
        recoveryHistory.removeAll()
        recoveryAttempts.removeAll()
    }
}

// MARK: - Recovery Event

/// Records a session recovery attempt for diagnostics.
public struct JPIPRecoveryEvent: Sendable {
    /// The session that was being recovered.
    public let sessionID: String

    /// When the recovery was attempted.
    public let timestamp: Date

    /// The outcome of the recovery.
    public let status: JPIPSessionRecoveryStatus

    /// The attempt number.
    public let attempt: Int

    /// Creates a recovery event.
    public init(
        sessionID: String,
        timestamp: Date,
        status: JPIPSessionRecoveryStatus,
        attempt: Int
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.status = status
        self.attempt = attempt
    }
}
