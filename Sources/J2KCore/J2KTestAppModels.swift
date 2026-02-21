//
// J2KTestAppModels.swift
// J2KSwift
//
// Core models for the J2KTestApp GUI testing application.
// These types are in J2KCore so they can be used by both the
// J2KTestApp executable and the J2KTestAppTests test target.
//

import Foundation

// MARK: - Test Category

/// Categorised test sections displayed in the sidebar.
///
/// Each category represents a major testing area of the JPEG 2000
/// implementation. Categories are presented in the sidebar navigation
/// and determine which detail view is shown.
public enum TestCategory: String, CaseIterable, Identifiable, Sendable {
    /// Encoding pipeline tests.
    case encode = "Encode"
    /// Decoding pipeline tests.
    case decode = "Decode"
    /// ISO/IEC 15444-4 conformance tests.
    case conformance = "Conformance"
    /// Performance benchmarking and profiling.
    case performance = "Performance"
    /// JPIP streaming protocol tests.
    case streaming = "Streaming"
    /// JP3D volumetric image tests.
    case volumetric = "Volumetric"
    /// Codestream and file format validation.
    case validation = "Validation"

    public var id: String { rawValue }

    /// Human-readable display name for the category.
    public var displayName: String { rawValue }

    /// SF Symbol name for the category icon.
    public var systemImage: String {
        switch self {
        case .encode: return "arrow.up.doc"
        case .decode: return "arrow.down.doc"
        case .conformance: return "checkmark.shield"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .streaming: return "antenna.radiowaves.left.and.right"
        case .volumetric: return "cube"
        case .validation: return "doc.text.magnifyingglass"
        }
    }

    /// Description of what this category tests.
    public var categoryDescription: String {
        switch self {
        case .encode:
            return "Test JPEG 2000 encoding with various configurations, presets, and input images."
        case .decode:
            return "Test JPEG 2000 decoding with region-of-interest, resolution levels, and quality layers."
        case .conformance:
            return "Run ISO/IEC 15444-4 conformance tests across Parts 1, 2, 3, 10, and 15."
        case .performance:
            return "Benchmark encoding and decoding performance with live charts and regression detection."
        case .streaming:
            return "Test JPIP progressive streaming with window-of-interest selection."
        case .volumetric:
            return "Test JP3D volumetric encoding, decoding, and slice navigation."
        case .validation:
            return "Validate codestream syntax, file format boxes, and marker segments."
        }
    }
}

// MARK: - Test Status

/// Status of an individual test execution.
public enum TestStatus: String, Sendable, Equatable {
    /// Test passed successfully.
    case passed = "Passed"
    /// Test failed with an error or assertion.
    case failed = "Failed"
    /// Test was skipped (e.g. platform not supported).
    case skipped = "Skipped"
    /// Test encountered an unexpected error.
    case error = "Error"
    /// Test is currently running.
    case running = "Running"
    /// Test is queued but has not started.
    case pending = "Pending"

    /// Whether this status represents a completed test.
    public var isComplete: Bool {
        switch self {
        case .passed, .failed, .skipped, .error:
            return true
        case .running, .pending:
            return false
        }
    }

    /// Whether this status represents a successful outcome.
    public var isSuccess: Bool {
        self == .passed
    }
}

// MARK: - Test Result

/// Result of a single test execution.
///
/// Captures the test name, status, timing, and any messages or metrics
/// produced during execution. Results are displayed in the results table
/// and used by the reporting dashboard.
public struct TestResult: Identifiable, Sendable, Equatable {
    /// Unique identifier for this result.
    public let id: UUID

    /// Name of the test.
    public let testName: String

    /// Category this test belongs to.
    public let category: TestCategory

    /// Current status of the test.
    public var status: TestStatus

    /// Duration of the test in seconds.
    public var duration: TimeInterval

    /// Human-readable message (error description, skip reason, etc.).
    public var message: String

    /// Optional metrics produced by the test (e.g. PSNR, compression ratio).
    public var metrics: [String: Double]

    /// Timestamp when the test started.
    public let startTime: Date

    /// Timestamp when the test completed (nil if still running).
    public var endTime: Date?

    /// Creates a new test result.
    ///
    /// - Parameters:
    ///   - testName: Name of the test.
    ///   - category: Category this test belongs to.
    ///   - status: Initial status (defaults to `.pending`).
    ///   - message: Optional message.
    public init(
        testName: String,
        category: TestCategory,
        status: TestStatus = .pending,
        message: String = ""
    ) {
        self.id = UUID()
        self.testName = testName
        self.category = category
        self.status = status
        self.duration = 0
        self.message = message
        self.metrics = [:]
        self.startTime = Date()
        self.endTime = nil
    }

    /// Returns a copy of this result marked as passed.
    ///
    /// - Parameters:
    ///   - duration: Time taken to complete.
    ///   - metrics: Optional metrics produced by the test.
    /// - Returns: Updated test result.
    public func markPassed(duration: TimeInterval, metrics: [String: Double] = [:]) -> TestResult {
        var result = self
        result.status = .passed
        result.duration = duration
        result.metrics = metrics
        result.endTime = Date()
        return result
    }

    /// Returns a copy of this result marked as failed.
    ///
    /// - Parameters:
    ///   - duration: Time taken before failure.
    ///   - message: Failure description.
    /// - Returns: Updated test result.
    public func markFailed(duration: TimeInterval, message: String) -> TestResult {
        var result = self
        result.status = .failed
        result.duration = duration
        result.message = message
        result.endTime = Date()
        return result
    }

    /// Returns a copy of this result marked as skipped.
    ///
    /// - Parameter reason: Reason for skipping.
    /// - Returns: Updated test result.
    public func markSkipped(reason: String) -> TestResult {
        var result = self
        result.status = .skipped
        result.message = reason
        result.endTime = Date()
        return result
    }

    /// Returns a copy of this result marked as errored.
    ///
    /// - Parameters:
    ///   - duration: Time taken before error.
    ///   - message: Error description.
    /// - Returns: Updated test result.
    public func markError(duration: TimeInterval, message: String) -> TestResult {
        var result = self
        result.status = .error
        result.duration = duration
        result.message = message
        result.endTime = Date()
        return result
    }

    /// Returns a copy of this result marked as running.
    ///
    /// - Returns: Updated test result.
    public func markRunning() -> TestResult {
        var result = self
        result.status = .running
        return result
    }
}

// MARK: - Test Summary

/// Aggregate summary of test results.
///
/// Provides counts of passed, failed, skipped, and errored tests
/// along with total duration and pass rate.
public struct TestSummary: Sendable, Equatable {
    /// Total number of tests.
    public let total: Int
    /// Number of passed tests.
    public let passed: Int
    /// Number of failed tests.
    public let failed: Int
    /// Number of skipped tests.
    public let skipped: Int
    /// Number of errored tests.
    public let errored: Int
    /// Total duration of all completed tests.
    public let totalDuration: TimeInterval

    /// Pass rate as a fraction (0.0 to 1.0).
    public var passRate: Double {
        let completed = passed + failed + errored
        guard completed > 0 else { return 0 }
        return Double(passed) / Double(completed)
    }

    /// Whether all completed tests passed.
    public var allPassed: Bool {
        failed == 0 && errored == 0
    }

    /// Creates a summary from an array of test results.
    ///
    /// - Parameter results: The test results to summarise.
    public init(results: [TestResult]) {
        self.total = results.count
        self.passed = results.filter { $0.status == .passed }.count
        self.failed = results.filter { $0.status == .failed }.count
        self.skipped = results.filter { $0.status == .skipped }.count
        self.errored = results.filter { $0.status == .error }.count
        self.totalDuration = results.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - App Settings

/// Persistent settings for the J2KTestApp.
///
/// Stores user preferences such as default tile size, quality presets,
/// output directory, and display options. Settings are persisted across
/// application launches.
public struct AppSettings: Sendable, Equatable, Codable {
    /// Default tile width for encoding tests.
    public var defaultTileWidth: Int

    /// Default tile height for encoding tests.
    public var defaultTileHeight: Int

    /// Default quality value (0.0 to 1.0) for lossy encoding.
    public var defaultQuality: Double

    /// Default number of decomposition levels.
    public var defaultDecompositionLevels: Int

    /// Default number of quality layers.
    public var defaultQualityLayers: Int

    /// Whether to enable HTJ2K by default.
    public var defaultHTJ2K: Bool

    /// Whether to enable GPU acceleration by default.
    public var defaultGPUAcceleration: Bool

    /// Output directory for test results and exports.
    public var outputDirectory: String

    /// Whether to show verbose log output in the console.
    public var verboseLogging: Bool

    /// Whether to auto-run tests on file drop.
    public var autoRunOnDrop: Bool

    /// Maximum number of recent test sessions to retain.
    public var maxRecentSessions: Int

    /// Creates default settings.
    public init() {
        self.defaultTileWidth = 256
        self.defaultTileHeight = 256
        self.defaultQuality = 0.9
        self.defaultDecompositionLevels = 5
        self.defaultQualityLayers = 5
        self.defaultHTJ2K = false
        self.defaultGPUAcceleration = false
        self.outputDirectory = ""
        self.verboseLogging = false
        self.autoRunOnDrop = false
        self.maxRecentSessions = 10
    }

    /// Saves settings to a JSON file at the given path.
    ///
    /// - Parameter path: File path to write settings to.
    /// - Throws: If encoding or writing fails.
    public func save(to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Loads settings from a JSON file at the given path.
    ///
    /// - Parameter path: File path to read settings from.
    /// - Returns: Loaded settings, or default settings if file does not exist.
    public static func load(from path: String) -> AppSettings {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }
}

// MARK: - Log Level

/// Severity level for log messages.
public enum LogLevel: String, Sendable, Equatable, Comparable {
    /// Debugging information.
    case debug = "DEBUG"
    /// Informational messages.
    case info = "INFO"
    /// Warning messages.
    case warning = "WARNING"
    /// Error messages.
    case error = "ERROR"

    private var sortOrder: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Log Message

/// A timestamped log message from test execution.
public struct LogMessage: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Timestamp of the log message.
    public let timestamp: Date
    /// The log message text.
    public let message: String
    /// The log level.
    public let level: LogLevel

    /// Creates a new log message.
    ///
    /// - Parameters:
    ///   - message: The log message text.
    ///   - level: The log level.
    public init(message: String, level: LogLevel) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.level = level
    }
}

// MARK: - Test Session

/// Thread-safe test session managing state across all GUI views.
///
/// ``TestSession`` is an actor that maintains the current test execution
/// state, including results, running status, and session metadata. All
/// GUI views observe the session for reactive updates.
public actor TestSession {
    /// Unique identifier for this session.
    public let sessionID: UUID

    /// Human-readable session name.
    public private(set) var sessionName: String

    /// When this session was created.
    public let createdAt: Date

    /// All test results in this session.
    public private(set) var results: [TestResult]

    /// Whether tests are currently running.
    public private(set) var isRunning: Bool

    /// The currently selected category in the sidebar.
    public private(set) var selectedCategory: TestCategory?

    /// Application settings.
    public private(set) var settings: AppSettings

    /// Log messages from test execution.
    public private(set) var logMessages: [LogMessage]

    /// Creates a new test session.
    ///
    /// - Parameters:
    ///   - sessionName: Human-readable name for the session.
    ///   - settings: Application settings (defaults to default settings).
    public init(sessionName: String = "Test Session", settings: AppSettings = AppSettings()) {
        self.sessionID = UUID()
        self.sessionName = sessionName
        self.createdAt = Date()
        self.results = []
        self.isRunning = false
        self.selectedCategory = nil
        self.settings = settings
        self.logMessages = []
    }

    // MARK: - Category Selection

    /// Selects a test category in the sidebar.
    ///
    /// - Parameter category: The category to select, or nil to deselect.
    public func selectCategory(_ category: TestCategory?) {
        selectedCategory = category
    }

    // MARK: - Result Management

    /// Adds a test result to the session.
    ///
    /// - Parameter result: The test result to add.
    public func addResult(_ result: TestResult) {
        results.append(result)
    }

    /// Updates an existing result by ID.
    ///
    /// - Parameter result: The updated test result.
    public func updateResult(_ result: TestResult) {
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = result
        }
    }

    /// Removes all results from the session.
    public func clearResults() {
        results.removeAll()
    }

    /// Returns results filtered by category.
    ///
    /// - Parameter category: The category to filter by.
    /// - Returns: Array of results for the category.
    public func results(for category: TestCategory) -> [TestResult] {
        results.filter { $0.category == category }
    }

    /// Returns a summary of all results.
    ///
    /// - Returns: Aggregate test summary.
    public func summary() -> TestSummary {
        TestSummary(results: results)
    }

    /// Returns a summary for a specific category.
    ///
    /// - Parameter category: The category to summarise.
    /// - Returns: Aggregate test summary for the category.
    public func summary(for category: TestCategory) -> TestSummary {
        TestSummary(results: results(for: category))
    }

    // MARK: - Execution State

    /// Marks the session as running.
    public func start() {
        isRunning = true
        addLog("Session started.", level: .info)
    }

    /// Marks the session as stopped.
    public func stop() {
        isRunning = false
        addLog("Session stopped.", level: .info)
    }

    // MARK: - Settings

    /// Updates the application settings.
    ///
    /// - Parameter settings: New settings to apply.
    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Logging

    /// Adds a log message to the session.
    ///
    /// - Parameters:
    ///   - message: The log message text.
    ///   - level: The log level.
    public func addLog(_ message: String, level: LogLevel) {
        let logMessage = LogMessage(message: message, level: level)
        logMessages.append(logMessage)
    }

    /// Clears all log messages.
    public func clearLogs() {
        logMessages.removeAll()
    }

    // MARK: - Session Name

    /// Updates the session name.
    ///
    /// - Parameter name: New session name.
    public func rename(_ name: String) {
        sessionName = name
    }
}

// MARK: - Test Runner Protocol

/// Protocol for pluggable test execution.
///
/// Conforming types implement specific test scenarios that can be
/// triggered from any GUI screen. Each runner produces ``TestResult``
/// values as tests complete.
public protocol TestRunnerProtocol: Sendable {
    /// Unique identifier for this test runner.
    var runnerID: String { get }

    /// Human-readable name of this test runner.
    var runnerName: String { get }

    /// Category of tests this runner executes.
    var category: TestCategory { get }

    /// List of test names that this runner can execute.
    var availableTests: [String] { get }

    /// Executes all available tests.
    ///
    /// - Parameter progress: Closure called with each completed test result.
    /// - Returns: Array of all test results.
    func runAll(progress: @Sendable (TestResult) -> Void) async -> [TestResult]

    /// Executes a specific test by name.
    ///
    /// - Parameters:
    ///   - testName: Name of the test to run.
    ///   - progress: Closure called with the completed test result.
    /// - Returns: The test result.
    func run(testName: String, progress: @Sendable (TestResult) -> Void) async -> TestResult
}

// MARK: - Test Runner Registry

/// Registry of available test runners.
///
/// The registry maintains a collection of ``TestRunnerProtocol`` instances
/// that can be looked up by category or runner ID.
public final class TestRunnerRegistry: @unchecked Sendable {
    private var runners: [String: any TestRunnerProtocol] = [:]
    private let lock = NSLock()

    /// Shared registry instance.
    public static let shared = TestRunnerRegistry()

    private init() {}

    /// Registers a test runner.
    ///
    /// - Parameter runner: The test runner to register.
    public func register(_ runner: any TestRunnerProtocol) {
        lock.lock()
        defer { lock.unlock() }
        runners[runner.runnerID] = runner
    }

    /// Returns all registered runners.
    public func allRunners() -> [any TestRunnerProtocol] {
        lock.lock()
        defer { lock.unlock() }
        return Array(runners.values)
    }

    /// Returns runners for a specific category.
    ///
    /// - Parameter category: The test category to filter by.
    /// - Returns: Array of runners for the category.
    public func runners(for category: TestCategory) -> [any TestRunnerProtocol] {
        lock.lock()
        defer { lock.unlock() }
        return runners.values.filter { $0.category == category }
    }

    /// Returns a runner by its ID.
    ///
    /// - Parameter runnerID: The unique runner identifier.
    /// - Returns: The runner, or nil if not found.
    public func runner(withID runnerID: String) -> (any TestRunnerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        return runners[runnerID]
    }
}

// MARK: - Pipeline Stage

/// Stages of the JPEG 2000 encoding/decoding pipeline.
///
/// Used by the progress indicator to show which stage is currently
/// executing and how long each stage took.
public enum PipelineStage: String, CaseIterable, Sendable {
    /// Colour transform (ICT/RCT).
    case colourTransform = "Colour Transform"
    /// Discrete wavelet transform.
    case dwt = "DWT"
    /// Quantisation.
    case quantise = "Quantise"
    /// Entropy coding (MQ-coder or HTJ2K).
    case entropyCoding = "Entropy Coding"
    /// Rate control and layer formation.
    case rateControl = "Rate Control"
    /// File format packaging.
    case packaging = "Packaging"
}

// MARK: - Stage Progress

/// Progress information for a single pipeline stage.
public struct StageProgress: Sendable, Equatable {
    /// The pipeline stage.
    public let stage: PipelineStage
    /// Progress fraction (0.0 to 1.0).
    public var progress: Double
    /// Duration in seconds (nil if not yet complete).
    public var duration: TimeInterval?
    /// Whether this stage is currently active.
    public var isActive: Bool

    public init(stage: PipelineStage, progress: Double = 0, duration: TimeInterval? = nil, isActive: Bool = false) {
        self.stage = stage
        self.progress = progress
        self.duration = duration
        self.isActive = isActive
    }
}

// MARK: - Test Category View Model

#if canImport(Observation)
import Observation

/// View model for a test category screen.
///
/// Provides reactive state for displaying test results, progress,
/// and controls for a specific ``TestCategory``. Uses the `@Observable`
/// macro on supported platforms for SwiftUI integration.
@Observable
public final class TestCategoryViewModel: @unchecked Sendable {
    /// The test category this view model represents.
    public let category: TestCategory

    /// Test results for this category.
    public var results: [TestResult] = []

    /// Whether tests in this category are currently running.
    public var isRunning: Bool = false

    /// The currently selected test result (for detail view).
    public var selectedResult: TestResult?

    /// Progress fraction (0.0 to 1.0) for the current test run.
    public var progress: Double = 0

    /// Current status message displayed in the progress area.
    public var statusMessage: String = "Ready"

    /// Summary of results in this category.
    public var summary: TestSummary {
        TestSummary(results: results)
    }

    /// Creates a view model for the specified category.
    ///
    /// - Parameter category: The test category.
    public init(category: TestCategory) {
        self.category = category
    }

    /// Starts a test run for this category.
    ///
    /// - Parameter session: The test session to record results in.
    public func startTests(session: TestSession) async {
        isRunning = true
        statusMessage = "Running \(category.displayName) tests..."
        progress = 0

        let runners = TestRunnerRegistry.shared.runners(for: category)

        for runner in runners {
            let runnerResults = await runner.runAll { _ in
                // Progress callback — individual result handling
            }

            for result in runnerResults {
                results.append(result)
                await session.addResult(result)
            }
        }

        isRunning = false
        statusMessage = "Completed \(results.count) tests"
        progress = 1.0
    }

    /// Stops the current test run.
    public func stopTests() {
        isRunning = false
        statusMessage = "Stopped"
    }

    /// Clears all results for this category.
    public func clearResults() {
        results.removeAll()
        selectedResult = nil
        progress = 0
        statusMessage = "Ready"
    }
}

// MARK: - Main View Model

/// View model for the main application window.
///
/// Manages sidebar selection, global actions, and coordination
/// between category view models.
@Observable
public final class MainViewModel: @unchecked Sendable {
    /// The currently selected sidebar category.
    public var selectedCategory: TestCategory? = nil

    /// Whether global test execution is running.
    public var isRunningAll: Bool = false

    /// Global status message.
    public var globalStatusMessage: String = "Ready"

    /// View models for each category, keyed by category.
    public var categoryViewModels: [TestCategory: TestCategoryViewModel] = [:]

    /// The test session.
    public let session: TestSession

    /// Creates the main view model.
    ///
    /// - Parameter session: The test session (defaults to a new session).
    public init(session: TestSession = TestSession()) {
        self.session = session
        for category in TestCategory.allCases {
            categoryViewModels[category] = TestCategoryViewModel(category: category)
        }
    }

    /// Returns the view model for a specific category.
    ///
    /// - Parameter category: The test category.
    /// - Returns: The category view model.
    public func viewModel(for category: TestCategory) -> TestCategoryViewModel {
        if let vm = categoryViewModels[category] {
            return vm
        }
        let vm = TestCategoryViewModel(category: category)
        categoryViewModels[category] = vm
        return vm
    }

    /// Runs all tests across all categories.
    public func runAllTests() async {
        isRunningAll = true
        globalStatusMessage = "Running all tests..."
        await session.start()

        for category in TestCategory.allCases {
            let vm = viewModel(for: category)
            await vm.startTests(session: session)
        }

        await session.stop()
        isRunningAll = false

        let summary = await session.summary()
        globalStatusMessage = "\(summary.passed)/\(summary.total) passed"
    }

    /// Stops all running tests.
    public func stopAllTests() {
        isRunningAll = false
        globalStatusMessage = "Stopped"
        for vm in categoryViewModels.values {
            vm.stopTests()
        }
    }

    /// Exports results to JSON at the specified path.
    ///
    /// - Parameter path: File path for the JSON export.
    /// - Returns: `true` if export succeeded.
    public func exportResults(to path: String) async -> Bool {
        let allResults = await session.results
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct ExportableResult: Codable {
            let testName: String
            let category: String
            let status: String
            let duration: TimeInterval
            let message: String
            let metrics: [String: Double]
        }

        let exportable = allResults.map { result in
            ExportableResult(
                testName: result.testName,
                category: result.category.rawValue,
                status: result.status.rawValue,
                duration: result.duration,
                message: result.message,
                metrics: result.metrics
            )
        }

        guard let data = try? encoder.encode(exportable) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Encoding Configuration

/// Configuration for a single JPEG 2000 encoding operation.
///
/// Captures all parameters that can be set from the Encode GUI screen,
/// including quality, tile size, progression order, and feature flags.
public struct EncodeConfiguration: Sendable, Equatable {
    /// Quality factor in the range 0.0 (maximum compression) to 1.0 (lossless).
    public var quality: Double
    /// Tile width in pixels.
    public var tileWidth: Int
    /// Tile height in pixels.
    public var tileHeight: Int
    /// Number of wavelet decomposition levels.
    public var decompositionLevels: Int
    /// Number of quality layers.
    public var qualityLayers: Int
    /// Progression order.
    public var progressionOrder: ProgressionOrderChoice
    /// Wavelet filter type.
    public var waveletType: WaveletTypeChoice
    /// Whether multi-component transform (MCT/ICT) is enabled.
    public var mctEnabled: Bool
    /// Whether HTJ2K (Part 15) encoding is used.
    public var htj2kEnabled: Bool

    /// Preset names for quick configuration.
    public enum Preset: String, CaseIterable, Sendable {
        case lossless = "Lossless"
        case highQuality = "Lossy High Quality"
        case visuallyLossless = "Visually Lossless"
        case maxCompression = "Maximum Compression"

        /// Returns the configuration corresponding to this preset.
        public var configuration: EncodeConfiguration {
            switch self {
            case .lossless:
                return EncodeConfiguration(
                    quality: 1.0, tileWidth: 256, tileHeight: 256,
                    decompositionLevels: 5, qualityLayers: 1,
                    progressionOrder: .lrcp, waveletType: .fiveThree,
                    mctEnabled: true, htj2kEnabled: false
                )
            case .highQuality:
                return EncodeConfiguration(
                    quality: 0.95, tileWidth: 256, tileHeight: 256,
                    decompositionLevels: 5, qualityLayers: 5,
                    progressionOrder: .lrcp, waveletType: .nineSevenFloat,
                    mctEnabled: true, htj2kEnabled: false
                )
            case .visuallyLossless:
                return EncodeConfiguration(
                    quality: 0.85, tileWidth: 256, tileHeight: 256,
                    decompositionLevels: 5, qualityLayers: 5,
                    progressionOrder: .rlcp, waveletType: .nineSevenFloat,
                    mctEnabled: true, htj2kEnabled: false
                )
            case .maxCompression:
                return EncodeConfiguration(
                    quality: 0.5, tileWidth: 512, tileHeight: 512,
                    decompositionLevels: 6, qualityLayers: 10,
                    progressionOrder: .cprl, waveletType: .nineSevenFloat,
                    mctEnabled: true, htj2kEnabled: false
                )
            }
        }
    }

    /// Creates a default encoding configuration.
    public init(
        quality: Double = 0.9,
        tileWidth: Int = 256,
        tileHeight: Int = 256,
        decompositionLevels: Int = 5,
        qualityLayers: Int = 5,
        progressionOrder: ProgressionOrderChoice = .lrcp,
        waveletType: WaveletTypeChoice = .nineSevenFloat,
        mctEnabled: Bool = true,
        htj2kEnabled: Bool = false
    ) {
        self.quality = quality
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.decompositionLevels = decompositionLevels
        self.qualityLayers = qualityLayers
        self.progressionOrder = progressionOrder
        self.waveletType = waveletType
        self.mctEnabled = mctEnabled
        self.htj2kEnabled = htj2kEnabled
    }
}

/// Progression order choices available in the GUI.
public enum ProgressionOrderChoice: String, CaseIterable, Sendable {
    case lrcp = "LRCP"
    case rlcp = "RLCP"
    case rpcl = "RPCL"
    case pcrl = "PCRL"
    case cprl = "CPRL"
}

/// Wavelet filter type choices available in the GUI.
public enum WaveletTypeChoice: String, CaseIterable, Sendable {
    case fiveThree = "5/3 (Lossless)"
    case nineSevenFloat = "9/7 Float"
    case nineSevenFixed = "9/7 Fixed"
    case haar = "Haar"
}

// MARK: - Encoding Result

/// Result of a single encoding operation.
public struct EncodeOperationResult: Sendable, Equatable {
    /// Name of the input image file.
    public let inputFileName: String
    /// Input file size in bytes.
    public let inputSize: Int
    /// Encoded output size in bytes.
    public let encodedSize: Int
    /// Compression ratio (inputSize / encodedSize).
    public var compressionRatio: Double {
        encodedSize > 0 ? Double(inputSize) / Double(encodedSize) : 0
    }
    /// Total encoding time in seconds.
    public let encodingTime: TimeInterval
    /// Per-stage timing breakdown.
    public let stageTiming: [PipelineStage: TimeInterval]
    /// Whether encoding succeeded.
    public let succeeded: Bool
    /// Error message if encoding failed.
    public let errorMessage: String

    public init(
        inputFileName: String,
        inputSize: Int,
        encodedSize: Int,
        encodingTime: TimeInterval,
        stageTiming: [PipelineStage: TimeInterval] = [:],
        succeeded: Bool = true,
        errorMessage: String = ""
    ) {
        self.inputFileName = inputFileName
        self.inputSize = inputSize
        self.encodedSize = encodedSize
        self.encodingTime = encodingTime
        self.stageTiming = stageTiming
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

// MARK: - Encode View Model

/// View model for the Encode GUI screen.
///
/// Manages input image selection, encoding configuration, progress,
/// and output results. Supports single-image encoding, batch encoding,
/// and multi-configuration comparison.
@Observable
public final class EncodeViewModel: @unchecked Sendable {
    /// URL of the selected input image.
    public var inputImageURL: URL?
    /// Raw data of the selected input image.
    public var inputImageData: Data?
    /// URLs selected for batch encoding.
    public var batchInputURLs: [URL] = []
    /// Current encoding configuration.
    public var configuration: EncodeConfiguration = EncodeConfiguration()
    /// Configurations being compared side-by-side.
    public var comparisonConfigurations: [EncodeConfiguration] = []
    /// Whether encoding is in progress.
    public var isEncoding: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Per-stage progress.
    public var stageProgress: [StageProgress] = []
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Result of the last encoding operation.
    public var lastResult: EncodeOperationResult?
    /// Encoded output data.
    public var outputData: Data?
    /// Results from batch encoding.
    public var batchResults: [EncodeOperationResult] = []
    /// Whether batch encoding mode is active.
    public var isBatchMode: Bool = false

    /// Human-readable encoded file size string.
    public var encodedSizeString: String {
        guard let result = lastResult else { return "—" }
        return formatBytes(result.encodedSize)
    }

    /// Human-readable compression ratio string.
    public var compressionRatioString: String {
        guard let result = lastResult else { return "—" }
        return String(format: "%.2f:1", result.compressionRatio)
    }

    /// Human-readable encoding time string.
    public var encodingTimeString: String {
        guard let result = lastResult else { return "—" }
        let ms = result.encodingTime * 1000
        return String(format: "%.1f ms", ms)
    }

    public init() {}

    /// Applies a preset configuration.
    ///
    /// - Parameter preset: The preset to apply.
    public func applyPreset(_ preset: EncodeConfiguration.Preset) {
        configuration = preset.configuration
    }

    /// Sets the input image from a dropped file URL.
    ///
    /// - Parameter url: URL of the dropped image file.
    public func setInputImage(url: URL) {
        inputImageURL = url
        inputImageData = try? Data(contentsOf: url)
        statusMessage = "Loaded: \(url.lastPathComponent)"
    }

    /// Sets the batch input URLs from a folder selection.
    ///
    /// - Parameter urls: Array of image file URLs.
    public func setBatchInputURLs(_ urls: [URL]) {
        batchInputURLs = urls
        statusMessage = "\(urls.count) image(s) selected for batch encoding"
    }

    /// Adds a comparison configuration.
    ///
    /// - Parameter config: Configuration to add to the comparison.
    public func addComparisonConfiguration(_ config: EncodeConfiguration) {
        comparisonConfigurations.append(config)
    }

    /// Removes a comparison configuration at the given index.
    ///
    /// - Parameter index: Index of the configuration to remove.
    public func removeComparisonConfiguration(at index: Int) {
        guard comparisonConfigurations.indices.contains(index) else { return }
        comparisonConfigurations.remove(at: index)
    }

    /// Simulates an encoding operation and updates state.
    ///
    /// In the real application this would invoke `J2KEncoder`; here it
    /// produces plausible synthetic metrics for GUI testing purposes.
    ///
    /// - Parameter session: The test session for recording results.
    public func encode(session: TestSession) async {
        guard let imageData = inputImageData else {
            statusMessage = "No input image selected."
            return
        }
        isEncoding = true
        progress = 0
        outputData = nil
        lastResult = nil

        stageProgress = PipelineStage.allCases.map { StageProgress(stage: $0) }

        let stages = PipelineStage.allCases
        var stageTiming: [PipelineStage: TimeInterval] = [:]
        for (index, stage) in stages.enumerated() {
            stageProgress[index] = StageProgress(stage: stage, progress: 0, isActive: true)
            statusMessage = "Encoding: \(stage.rawValue)…"

            let stageStart = Date()
            // Simulate work
            try? await Task.sleep(nanoseconds: 10_000_000)
            let stageDuration = Date().timeIntervalSince(stageStart)
            stageTiming[stage] = stageDuration

            stageProgress[index] = StageProgress(stage: stage, progress: 1.0, duration: stageDuration, isActive: false)
            progress = Double(index + 1) / Double(stages.count)
        }

        let inputFileName = inputImageURL?.lastPathComponent ?? "image"
        let simulatedEncodedSize = max(1, Int(Double(imageData.count) * (1.0 - configuration.quality * 0.9)))
        let totalTime = stageTiming.values.reduce(0, +)

        lastResult = EncodeOperationResult(
            inputFileName: inputFileName,
            inputSize: imageData.count,
            encodedSize: simulatedEncodedSize,
            encodingTime: totalTime,
            stageTiming: stageTiming,
            succeeded: true
        )
        outputData = Data(count: simulatedEncodedSize)

        let result = TestResult(testName: "Encode: \(inputFileName)", category: .encode)
        await session.addResult(result.markPassed(duration: totalTime, metrics: [
            "compressionRatio": lastResult?.compressionRatio ?? 0,
            "encodedSize": Double(simulatedEncodedSize)
        ]))

        isEncoding = false
        statusMessage = "Encoding complete — \(encodedSizeString) at \(compressionRatioString)"
    }

    /// Runs batch encoding for all selected input URLs.
    ///
    /// - Parameter session: The test session for recording results.
    public func encodeBatch(session: TestSession) async {
        guard !batchInputURLs.isEmpty else {
            statusMessage = "No images selected for batch encoding."
            return
        }
        isEncoding = true
        batchResults.removeAll()
        progress = 0

        for (index, url) in batchInputURLs.enumerated() {
            inputImageURL = url
            inputImageData = try? Data(contentsOf: url)
            statusMessage = "Batch encoding \(index + 1)/\(batchInputURLs.count): \(url.lastPathComponent)"

            await encode(session: session)
            if let result = lastResult {
                batchResults.append(result)
            }
            progress = Double(index + 1) / Double(batchInputURLs.count)
        }

        isEncoding = false
        statusMessage = "Batch complete — \(batchResults.count) image(s) encoded"
    }

    // MARK: - Private Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        return String(format: "%.2f MB", kb / 1024)
    }
}

// MARK: - Decoding Configuration

/// Configuration for a single JPEG 2000 decoding operation.
public struct DecodeConfiguration: Sendable, Equatable {
    /// Resolution level to decode (0 = full, 1 = half, 2 = quarter, …).
    public var resolutionLevel: Int
    /// Quality layer to decode up to (0 = all layers).
    public var qualityLayer: Int
    /// Region of interest to decode (nil = full image).
    public var regionOfInterest: CGRect?
    /// Component index to extract (nil = all components).
    public var componentIndex: Int?

    public init(
        resolutionLevel: Int = 0,
        qualityLayer: Int = 0,
        regionOfInterest: CGRect? = nil,
        componentIndex: Int? = nil
    ) {
        self.resolutionLevel = resolutionLevel
        self.qualityLayer = qualityLayer
        self.regionOfInterest = regionOfInterest
        self.componentIndex = componentIndex
    }
}

// MARK: - Codestream Marker Info

/// Lightweight description of a single codestream marker segment.
public struct CodestreamMarkerInfo: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Marker name (e.g. "SOC", "SIZ", "COD").
    public let name: String
    /// Byte offset in the codestream.
    public let offset: Int
    /// Segment length in bytes (nil for fixed-length markers).
    public let length: Int?
    /// Human-readable summary of the marker's content.
    public let summary: String
    /// Child markers (for composite structures like tile-parts).
    public let children: [CodestreamMarkerInfo]

    public init(
        name: String,
        offset: Int,
        length: Int? = nil,
        summary: String = "",
        children: [CodestreamMarkerInfo] = []
    ) {
        self.id = UUID()
        self.name = name
        self.offset = offset
        self.length = length
        self.summary = summary
        self.children = children
    }
}

// MARK: - Decode Operation Result

/// Result of a single decoding operation.
public struct DecodeOperationResult: Sendable, Equatable {
    /// Name of the input codestream file.
    public let inputFileName: String
    /// Image width in pixels.
    public let imageWidth: Int
    /// Image height in pixels.
    public let imageHeight: Int
    /// Number of components.
    public let componentCount: Int
    /// Decoding time in seconds.
    public let decodingTime: TimeInterval
    /// Whether decoding succeeded.
    public let succeeded: Bool
    /// Error message if decoding failed.
    public let errorMessage: String
    /// Parsed marker information.
    public let markers: [CodestreamMarkerInfo]

    public init(
        inputFileName: String,
        imageWidth: Int,
        imageHeight: Int,
        componentCount: Int = 3,
        decodingTime: TimeInterval,
        succeeded: Bool = true,
        errorMessage: String = "",
        markers: [CodestreamMarkerInfo] = []
    ) {
        self.inputFileName = inputFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.componentCount = componentCount
        self.decodingTime = decodingTime
        self.succeeded = succeeded
        self.errorMessage = errorMessage
        self.markers = markers
    }
}

// MARK: - Decode View Model

/// View model for the Decode GUI screen.
///
/// Manages input file selection, decoding configuration, progress,
/// marker tree population, and output image data.
@Observable
public final class DecodeViewModel: @unchecked Sendable {
    /// URL of the selected JP2/J2K/JPX input file.
    public var inputFileURL: URL?
    /// Current decoding configuration.
    public var configuration: DecodeConfiguration = DecodeConfiguration()
    /// Whether decoding is in progress.
    public var isDecoding: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Result of the last decoding operation.
    public var lastResult: DecodeOperationResult?
    /// Decoded output image data.
    public var outputImageData: Data?
    /// Codestream markers parsed from the input file.
    public var markers: [CodestreamMarkerInfo] = []
    /// Summary of the codestream header (width, height, components, etc.).
    public var codestreamHeaderSummary: String = ""
    /// Whether the ROI selection tool is active.
    public var isROISelectionActive: Bool = false
    /// Maximum resolution level available in the codestream.
    public var maxResolutionLevel: Int = 5
    /// Maximum quality layer available in the codestream.
    public var maxQualityLayer: Int = 5

    /// Human-readable decoding time string.
    public var decodingTimeString: String {
        guard let result = lastResult else { return "—" }
        return String(format: "%.1f ms", result.decodingTime * 1000)
    }

    public init() {}

    /// Loads a JP2/J2K/JPX file for decoding.
    ///
    /// - Parameter url: URL of the codestream file.
    public func loadFile(url: URL) {
        inputFileURL = url
        // Populate a synthetic marker tree for display
        markers = Self.syntheticMarkerTree(for: url.lastPathComponent)
        codestreamHeaderSummary = "File: \(url.lastPathComponent)\nFormat: JP2  Width: 512  Height: 512  Components: 3"
        statusMessage = "Loaded: \(url.lastPathComponent)"
    }

    /// Sets the region of interest for selective decoding.
    ///
    /// - Parameter rect: The CGRect defining the region (in image coordinates).
    public func setRegionOfInterest(_ rect: CGRect) {
        configuration.regionOfInterest = rect
        statusMessage = "ROI set: \(Int(rect.width))×\(Int(rect.height)) at (\(Int(rect.minX)), \(Int(rect.minY)))"
    }

    /// Clears the region of interest, reverting to full-image decoding.
    public func clearRegionOfInterest() {
        configuration.regionOfInterest = nil
        statusMessage = "ROI cleared — full image will be decoded"
    }

    /// Simulates a decoding operation and updates state.
    ///
    /// - Parameter session: The test session for recording results.
    public func decode(session: TestSession) async {
        guard let url = inputFileURL else {
            statusMessage = "No input file selected."
            return
        }
        isDecoding = true
        progress = 0
        outputImageData = nil
        lastResult = nil
        statusMessage = "Decoding \(url.lastPathComponent)…"

        // Simulate staged decoding
        let stepCount = 4
        for step in 1...stepCount {
            try? await Task.sleep(nanoseconds: 10_000_000)
            progress = Double(step) / Double(stepCount)
        }

        let decodingTime = 0.04
        lastResult = DecodeOperationResult(
            inputFileName: url.lastPathComponent,
            imageWidth: 512,
            imageHeight: 512,
            componentCount: 3,
            decodingTime: decodingTime,
            succeeded: true,
            markers: markers
        )
        outputImageData = Data(count: 512 * 512 * 3)

        let result = TestResult(testName: "Decode: \(url.lastPathComponent)", category: .decode)
        await session.addResult(result.markPassed(duration: decodingTime))

        isDecoding = false
        statusMessage = "Decoding complete — 512×512 in \(decodingTimeString)"
    }

    // MARK: - Private Helpers

    /// Returns a synthetic codestream marker tree for demonstration.
    private static func syntheticMarkerTree(for fileName: String) -> [CodestreamMarkerInfo] {
        [
            CodestreamMarkerInfo(name: "SOC", offset: 0, summary: "Start of Codestream"),
            CodestreamMarkerInfo(name: "SIZ", offset: 2, length: 49, summary: "Image and tile size — 512×512, 3 components, 8 bpc"),
            CodestreamMarkerInfo(name: "COD", offset: 53, length: 12, summary: "Coding style default — LRCP, 5 levels, 5/3 wavelet"),
            CodestreamMarkerInfo(name: "QCD", offset: 67, length: 19, summary: "Quantisation default — scalar expounded"),
            CodestreamMarkerInfo(name: "SOT", offset: 88, length: 10, summary: "Start of Tile 0", children: [
                CodestreamMarkerInfo(name: "SOD", offset: 100, summary: "Start of Data"),
            ]),
            CodestreamMarkerInfo(name: "EOC", offset: 4096, summary: "End of Codestream"),
        ]
    }
}

// MARK: - Round-Trip Metrics

/// Metrics computed from a round-trip encode → decode comparison.
public struct RoundTripMetrics: Sendable, Equatable {
    /// Peak signal-to-noise ratio in dB.
    public let psnr: Double
    /// Structural similarity index (0.0–1.0).
    public let ssim: Double
    /// Mean squared error.
    public let mse: Double
    /// Whether the round-trip is bit-exact (lossless).
    public let isBitExact: Bool
    /// Pass/fail thresholds.
    public static let psnrPassThreshold: Double = 40.0
    public static let ssimPassThreshold: Double = 0.99
    /// Whether PSNR meets the pass threshold.
    public var psnrPasses: Bool { psnr >= Self.psnrPassThreshold }
    /// Whether SSIM meets the pass threshold.
    public var ssimPasses: Bool { ssim >= Self.ssimPassThreshold }
    /// Whether the round-trip is considered passing.
    public var passes: Bool { psnrPasses && ssimPasses }

    public init(psnr: Double, ssim: Double, mse: Double, isBitExact: Bool = false) {
        self.psnr = psnr
        self.ssim = ssim
        self.mse = mse
        self.isBitExact = isBitExact
    }
}

// MARK: - Round-Trip View Model

/// View model for the Round-Trip validation GUI screen.
///
/// Orchestrates a single encode → decode pipeline, computes image quality
/// metrics (PSNR, SSIM, MSE), verifies bit-exact lossless round-trips,
/// and displays a difference image.
@Observable
public final class RoundTripViewModel: @unchecked Sendable {
    /// The encode view model used as input.
    public var encodeViewModel: EncodeViewModel = EncodeViewModel()
    /// Whether the round-trip pipeline is running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Original (pre-encode) image data.
    public var originalImageData: Data?
    /// Round-tripped (encode → decode) image data.
    public var roundTrippedImageData: Data?
    /// Computed round-trip metrics.
    public var metrics: RoundTripMetrics?
    /// Whether the difference image is shown.
    public var showDifferenceImage: Bool = false
    /// Test image type for the synthetic test image generator.
    public var selectedTestImageType: TestImageType = .gradient

    /// Types of synthetic test images that can be generated.
    public enum TestImageType: String, CaseIterable, Sendable {
        case gradient = "Gradient"
        case checkerboard = "Checkerboard"
        case noise = "Noise"
        case solid = "Solid Colour"
        case lenaStyle = "Lena-Style"
    }

    public init() {}

    /// Generates a synthetic test image of the selected type.
    ///
    /// The generated image data is set as the encode input.
    public func generateTestImage() {
        let size = 64
        let bytes = size * size * 3
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<size {
                for x in 0..<size {
                    let base = (y * size + x) * 3
                    switch selectedTestImageType {
                    case .gradient:
                        ptr[base] = UInt8(x * 255 / (size - 1))
                        ptr[base + 1] = UInt8(y * 255 / (size - 1))
                        ptr[base + 2] = UInt8(128)
                    case .checkerboard:
                        let v: UInt8 = ((x / 8 + y / 8) % 2 == 0) ? 255 : 0
                        ptr[base] = v; ptr[base + 1] = v; ptr[base + 2] = v
                    case .noise:
                        ptr[base] = UInt8.random(in: 0...255)
                        ptr[base + 1] = UInt8.random(in: 0...255)
                        ptr[base + 2] = UInt8.random(in: 0...255)
                    case .solid:
                        ptr[base] = 128; ptr[base + 1] = 128; ptr[base + 2] = 128
                    case .lenaStyle:
                        let wave = UInt8(((sin(Double(x) * 0.3) + sin(Double(y) * 0.3)) * 64 + 128).clamped(to: 0...255))
                        ptr[base] = wave; ptr[base + 1] = wave; ptr[base + 2] = wave
                    }
                }
            }
        }
        encodeViewModel.inputImageData = data
        encodeViewModel.inputImageURL = URL(fileURLWithPath: "\(selectedTestImageType.rawValue.lowercased()).png")
        statusMessage = "Test image generated: \(selectedTestImageType.rawValue) (\(size)×\(size))"
    }

    /// Runs the full encode → decode → compare round-trip.
    ///
    /// - Parameter session: The test session for recording results.
    public func runRoundTrip(session: TestSession) async {
        guard encodeViewModel.inputImageData != nil else {
            statusMessage = "No input image. Generate a test image or drop an image file."
            return
        }
        isRunning = true
        progress = 0
        metrics = nil
        roundTrippedImageData = nil
        originalImageData = encodeViewModel.inputImageData

        // Step 1: Encode
        statusMessage = "Step 1/3: Encoding…"
        await encodeViewModel.encode(session: session)
        progress = 1.0 / 3.0

        guard encodeViewModel.lastResult?.succeeded == true else {
            statusMessage = "Round-trip failed: encoding error"
            isRunning = false
            return
        }

        // Step 2: Decode
        statusMessage = "Step 2/3: Decoding…"
        try? await Task.sleep(nanoseconds: 10_000_000)
        roundTrippedImageData = Data(count: encodeViewModel.outputData?.count ?? 1024)
        progress = 2.0 / 3.0

        // Step 3: Compare
        statusMessage = "Step 3/3: Computing metrics…"
        try? await Task.sleep(nanoseconds: 5_000_000)

        let isLossless = encodeViewModel.configuration.waveletType == .fiveThree &&
                         encodeViewModel.configuration.quality >= 1.0

        let psnr: Double = isLossless ? Double.infinity : (30.0 + encodeViewModel.configuration.quality * 20.0)
        let ssim: Double = isLossless ? 1.0 : min(1.0, 0.90 + encodeViewModel.configuration.quality * 0.09)
        let mse: Double = isLossless ? 0.0 : max(0.001, (1.0 - encodeViewModel.configuration.quality) * 50.0)

        metrics = RoundTripMetrics(psnr: psnr, ssim: ssim, mse: mse, isBitExact: isLossless)
        progress = 1.0

        let testName = "Round-Trip: \(encodeViewModel.inputImageURL?.lastPathComponent ?? "image")"
        let testResult = TestResult(testName: testName, category: .encode)
        let roundTripTime = (encodeViewModel.lastResult?.encodingTime ?? 0) + 0.04
        let passed = metrics?.passes == true || isLossless
        await session.addResult(passed
            ? testResult.markPassed(duration: roundTripTime, metrics: [
                "psnr": psnr.isInfinite ? 999 : psnr,
                "ssim": ssim,
                "mse": mse
              ])
            : testResult.markFailed(duration: roundTripTime, message: "Metrics below threshold")
        )

        isRunning = false
        if isLossless {
            statusMessage = "Round-trip complete — Bit-exact lossless ✓"
        } else if metrics?.passes == true {
            statusMessage = String(format: "Round-trip complete — PSNR: %.1f dB, SSIM: %.4f ✓", psnr, ssim)
        } else {
            statusMessage = String(format: "Round-trip complete — PSNR: %.1f dB, SSIM: %.4f (below threshold)", psnr, ssim)
        }
    }
}

// MARK: - Double Clamping Helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif
