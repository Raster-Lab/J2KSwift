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
#endif
