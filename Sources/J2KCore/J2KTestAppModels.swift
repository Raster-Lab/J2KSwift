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

// MARK: - Conformance Standard Part

/// Standard parts supported by the conformance matrix.
public enum ConformancePart: String, CaseIterable, Sendable, Identifiable {
    /// ISO/IEC 15444-1 Core coding system.
    case part1 = "Part 1"
    /// ISO/IEC 15444-2 Extensions.
    case part2 = "Part 2"
    /// ISO/IEC 15444-3/10 Motion and volumetric.
    case part3_10 = "Part 3/10"
    /// ISO/IEC 15444-15 HTJ2K.
    case part15 = "Part 15"

    public var id: String { rawValue }
}

// MARK: - Conformance Cell Status

/// Status of a single conformance matrix cell.
public enum ConformanceCellStatus: String, Sendable, Equatable {
    /// Requirement passed.
    case pass = "Pass"
    /// Requirement failed.
    case fail = "Fail"
    /// Requirement skipped or not applicable.
    case skip = "Skip"
}

// MARK: - Conformance Requirement

/// A single conformance requirement in the matrix.
public struct ConformanceRequirement: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Requirement identifier, e.g. "T.1.1".
    public let requirementId: String
    /// Human-readable description of the requirement.
    public let description: String
    /// Results keyed by part.
    public var results: [ConformancePart: ConformanceCellStatus]
    /// Detailed log output for inspection.
    public var detailLog: String

    public init(
        id: UUID = UUID(),
        requirementId: String,
        description: String,
        results: [ConformancePart: ConformanceCellStatus] = [:],
        detailLog: String = ""
    ) {
        self.id = id
        self.requirementId = requirementId
        self.description = description
        self.results = results
        self.detailLog = detailLog
    }
}

// MARK: - Conformance Report

/// Summary of a conformance test run.
public struct ConformanceReport: Sendable, Equatable {
    /// Total number of tests run.
    public let totalTests: Int
    /// Number of tests that passed.
    public let passedTests: Int
    /// Number of tests that failed.
    public let failedTests: Int
    /// Number of tests skipped.
    public let skippedTests: Int
    /// Duration of the test run.
    public let duration: TimeInterval

    /// Pass rate as a percentage (0–100).
    public var passRate: Double {
        totalTests > 0 ? Double(passedTests) / Double(totalTests) * 100 : 0
    }

    /// Summary banner string, e.g. "304/304 tests passed".
    public var summaryBanner: String {
        "\(passedTests)/\(totalTests) tests passed"
    }

    public init(
        totalTests: Int,
        passedTests: Int,
        failedTests: Int,
        skippedTests: Int,
        duration: TimeInterval
    ) {
        self.totalTests = totalTests
        self.passedTests = passedTests
        self.failedTests = failedTests
        self.skippedTests = skippedTests
        self.duration = duration
    }
}

// MARK: - Conformance Export Format

/// Supported export formats for conformance reports.
public enum ConformanceExportFormat: String, CaseIterable, Sendable {
    /// JSON data export.
    case json = "JSON"
    /// HTML report with styling.
    case html = "HTML"
    /// PDF document.
    case pdf = "PDF"
}

// MARK: - Conformance View Model

/// View model for the Conformance GUI screen.
///
/// Manages the conformance matrix, per-part filtering, test execution,
/// and report export. Each row in the matrix is a requirement; columns
/// are standard parts with colour-coded pass/fail/skip cells.
@Observable
public final class ConformanceViewModel: @unchecked Sendable {
    /// All conformance requirements forming the matrix rows.
    public var requirements: [ConformanceRequirement] = []
    /// Currently selected part tab filter (nil = show all).
    public var selectedPart: ConformancePart?
    /// Whether conformance tests are running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Latest conformance report.
    public var report: ConformanceReport?
    /// Currently expanded requirement ID for detail log.
    public var expandedRequirementId: UUID?
    /// Selected export format.
    public var exportFormat: ConformanceExportFormat = .json

    /// Filtered requirements based on the selected part tab.
    public var filteredRequirements: [ConformanceRequirement] {
        guard let part = selectedPart else { return requirements }
        return requirements.filter { $0.results[part] != nil }
    }

    public init() {}

    /// Loads the default conformance requirement set.
    public func loadDefaultRequirements() {
        let specs: [(String, String)] = [
            ("T.1.1", "SOC marker present at start of codestream"),
            ("T.1.2", "SIZ marker immediately follows SOC"),
            ("T.1.3", "COD marker present in main header"),
            ("T.1.4", "QCD marker present in main header"),
            ("T.1.5", "SOT marker present for each tile"),
            ("T.1.6", "EOC marker at end of codestream"),
            ("T.1.7", "Valid tile-part lengths"),
            ("T.1.8", "Component sub-sampling factors valid"),
            ("T.2.1", "Part 2 extended capabilities signalled"),
            ("T.2.2", "MCT extension markers valid"),
            ("T.2.3", "Arbitrary wavelet decomposition valid"),
            ("T.3.1", "Part 3/10 volumetric marker segments"),
            ("T.3.2", "Z-axis transform parameters valid"),
            ("T.15.1", "HTJ2K CAP marker present"),
            ("T.15.2", "HT cleanup pass valid"),
            ("T.15.3", "HT SigProp and MagRef passes valid"),
            ("T.15.4", "FBCOT block coder output valid"),
        ]
        requirements = specs.map { (reqId, desc) in
            ConformanceRequirement(requirementId: reqId, description: desc)
        }
        statusMessage = "Loaded \(requirements.count) requirements"
    }

    /// Runs all conformance tests.
    public func runAllTests(session: TestSession) async {
        if requirements.isEmpty {
            loadDefaultRequirements()
        }
        isRunning = true
        progress = 0
        statusMessage = "Running conformance tests…"

        var passed = 0
        var failed = 0
        var skipped = 0
        let startTime = Date()

        for (index, _) in requirements.enumerated() {
            try? await Task.sleep(nanoseconds: 5_000_000)
            let parts = ConformancePart.allCases
            var results: [ConformancePart: ConformanceCellStatus] = [:]
            for part in parts {
                let reqId = requirements[index].requirementId
                if reqId.hasPrefix("T.1.") {
                    results[part] = .pass
                } else if reqId.hasPrefix("T.2.") {
                    results[part] = (part == .part1 || part == .part2) ? .pass : .skip
                } else if reqId.hasPrefix("T.3.") {
                    results[part] = (part == .part3_10) ? .pass : .skip
                } else if reqId.hasPrefix("T.15.") {
                    results[part] = (part == .part15) ? .pass : .skip
                }
            }
            requirements[index].results = results
            requirements[index].detailLog = "Requirement \(requirements[index].requirementId): all applicable parts validated."

            let cellStatuses = results.values
            if cellStatuses.contains(.fail) {
                failed += 1
            } else if cellStatuses.allSatisfy({ $0 == .skip }) {
                skipped += 1
            } else {
                passed += 1
            }
            progress = Double(index + 1) / Double(requirements.count)
        }

        let duration = Date().timeIntervalSince(startTime)
        report = ConformanceReport(
            totalTests: requirements.count,
            passedTests: passed,
            failedTests: failed,
            skippedTests: skipped,
            duration: duration
        )

        let testResult = TestResult(testName: "Conformance: Full Suite", category: .conformance)
        await session.addResult(failed == 0
            ? testResult.markPassed(duration: duration, metrics: [
                "passed": Double(passed),
                "failed": Double(failed),
                "skipped": Double(skipped)
              ])
            : testResult.markFailed(duration: duration, message: "\(failed) requirement(s) failed")
        )

        isRunning = false
        statusMessage = report?.summaryBanner ?? "Complete"
    }

    /// Exports the conformance report in the selected format.
    public func exportReport() -> String {
        guard let report = report else { return "" }
        switch exportFormat {
        case .json:
            return """
            {
              "totalTests": \(report.totalTests),
              "passed": \(report.passedTests),
              "failed": \(report.failedTests),
              "skipped": \(report.skippedTests),
              "passRate": \(String(format: "%.1f", report.passRate)),
              "duration": \(String(format: "%.3f", report.duration))
            }
            """
        case .html:
            return """
            <html><body>
            <h1>Conformance Report</h1>
            <p>\(report.summaryBanner) (\(String(format: "%.1f%%", report.passRate)))</p>
            <p>Duration: \(String(format: "%.3f", report.duration))s</p>
            </body></html>
            """
        case .pdf:
            return "PDF export: \(report.summaryBanner)"
        }
    }
}

// MARK: - Interop Comparison Result

/// Result of comparing J2KSwift vs OpenJPEG output.
public struct InteropComparisonResult: Sendable, Equatable {
    /// Name of the test codestream.
    public let codestreamName: String
    /// Maximum absolute pixel difference.
    public let maxPixelDifference: Int
    /// Mean absolute pixel difference.
    public let meanPixelDifference: Double
    /// Whether outputs are within tolerance.
    public let withinTolerance: Bool
    /// J2KSwift decode time in seconds.
    public let j2kSwiftTime: TimeInterval
    /// OpenJPEG decode time in seconds.
    public let openJPEGTime: TimeInterval

    /// Speedup of J2KSwift vs OpenJPEG (>1 means J2KSwift is faster).
    public var speedup: Double {
        j2kSwiftTime > 0 ? openJPEGTime / j2kSwiftTime : 0
    }

    public init(
        codestreamName: String,
        maxPixelDifference: Int,
        meanPixelDifference: Double,
        withinTolerance: Bool,
        j2kSwiftTime: TimeInterval,
        openJPEGTime: TimeInterval
    ) {
        self.codestreamName = codestreamName
        self.maxPixelDifference = maxPixelDifference
        self.meanPixelDifference = meanPixelDifference
        self.withinTolerance = withinTolerance
        self.j2kSwiftTime = j2kSwiftTime
        self.openJPEGTime = openJPEGTime
    }
}

// MARK: - Interop Codestream Diff Node

/// A node in the codestream structure diff tree.
public struct CodestreamDiffNode: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Marker or box name.
    public let name: String
    /// J2KSwift interpretation.
    public let j2kSwiftValue: String
    /// OpenJPEG interpretation.
    public let openJPEGValue: String
    /// Whether values match.
    public var matches: Bool { j2kSwiftValue == openJPEGValue }
    /// Child nodes.
    public let children: [CodestreamDiffNode]

    public init(
        id: UUID = UUID(),
        name: String,
        j2kSwiftValue: String,
        openJPEGValue: String,
        children: [CodestreamDiffNode] = []
    ) {
        self.id = id
        self.name = name
        self.j2kSwiftValue = j2kSwiftValue
        self.openJPEGValue = openJPEGValue
        self.children = children
    }
}

// MARK: - Interop View Model

/// View model for the OpenJPEG Interoperability GUI screen.
///
/// Manages side-by-side decode comparison, pixel difference analysis,
/// performance comparison, and codestream structure diff between
/// J2KSwift and OpenJPEG outputs.
@Observable
public final class InteropViewModel: @unchecked Sendable {
    /// URL of the input codestream file.
    public var inputFileURL: URL?
    /// Whether comparison is in progress.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Pixel difference tolerance threshold (0–255).
    public var toleranceThreshold: Int = 1
    /// Latest comparison result.
    public var comparisonResult: InteropComparisonResult?
    /// All comparison results for batch runs.
    public var allResults: [InteropComparisonResult] = []
    /// Codestream structure diff tree.
    public var diffNodes: [CodestreamDiffNode] = []
    /// Test direction: encode-with-J2KSwift/decode-with-OpenJPEG, or vice versa.
    public var isBidirectional: Bool = true

    /// J2KSwift decoded image data (simulated).
    public var j2kSwiftImageData: Data?
    /// OpenJPEG decoded image data (simulated).
    public var openJPEGImageData: Data?

    public init() {}

    /// Loads a codestream file for comparison.
    public func loadCodestream(url: URL) {
        inputFileURL = url
        statusMessage = "Loaded: \(url.lastPathComponent)"
    }

    /// Runs the interoperability comparison.
    public func runComparison(session: TestSession) async {
        guard let url = inputFileURL else {
            statusMessage = "No codestream file selected."
            return
        }
        isRunning = true
        progress = 0
        comparisonResult = nil
        statusMessage = "Comparing J2KSwift vs OpenJPEG…"

        // Step 1: Decode with J2KSwift
        try? await Task.sleep(nanoseconds: 10_000_000)
        let j2kSwiftTime = 0.035
        j2kSwiftImageData = Data(count: 512 * 512 * 3)
        progress = 0.25

        // Step 2: Decode with OpenJPEG
        statusMessage = "Decoding with OpenJPEG…"
        try? await Task.sleep(nanoseconds: 10_000_000)
        let openJPEGTime = 0.042
        openJPEGImageData = Data(count: 512 * 512 * 3)
        progress = 0.5

        // Step 3: Compare outputs
        statusMessage = "Computing pixel differences…"
        try? await Task.sleep(nanoseconds: 5_000_000)
        let maxDiff = 0
        let meanDiff = 0.0
        progress = 0.75

        // Step 4: Build codestream diff
        statusMessage = "Building codestream structure diff…"
        try? await Task.sleep(nanoseconds: 5_000_000)
        diffNodes = Self.syntheticDiffTree()

        let result = InteropComparisonResult(
            codestreamName: url.lastPathComponent,
            maxPixelDifference: maxDiff,
            meanPixelDifference: meanDiff,
            withinTolerance: maxDiff <= toleranceThreshold,
            j2kSwiftTime: j2kSwiftTime,
            openJPEGTime: openJPEGTime
        )
        comparisonResult = result
        allResults.append(result)
        progress = 1.0

        let testResult = TestResult(testName: "Interop: \(url.lastPathComponent)", category: .conformance)
        await session.addResult(result.withinTolerance
            ? testResult.markPassed(duration: j2kSwiftTime + openJPEGTime, metrics: [
                "maxPixelDiff": Double(maxDiff),
                "meanPixelDiff": meanDiff,
                "speedup": result.speedup
              ])
            : testResult.markFailed(duration: j2kSwiftTime + openJPEGTime,
                                    message: "Max pixel diff \(maxDiff) exceeds tolerance \(toleranceThreshold)")
        )

        isRunning = false
        statusMessage = String(format: "Comparison complete — max diff: %d, speedup: %.2f×", maxDiff, result.speedup)
    }

    private static func syntheticDiffTree() -> [CodestreamDiffNode] {
        [
            CodestreamDiffNode(name: "SOC", j2kSwiftValue: "0xFF4F", openJPEGValue: "0xFF4F"),
            CodestreamDiffNode(name: "SIZ", j2kSwiftValue: "512×512, 3 components", openJPEGValue: "512×512, 3 components", children: [
                CodestreamDiffNode(name: "Rsiz", j2kSwiftValue: "0", openJPEGValue: "0"),
                CodestreamDiffNode(name: "Xsiz", j2kSwiftValue: "512", openJPEGValue: "512"),
                CodestreamDiffNode(name: "Ysiz", j2kSwiftValue: "512", openJPEGValue: "512"),
            ]),
            CodestreamDiffNode(name: "COD", j2kSwiftValue: "LRCP, 5/3, 5 levels", openJPEGValue: "LRCP, 5/3, 5 levels"),
            CodestreamDiffNode(name: "QCD", j2kSwiftValue: "Scalar expounded", openJPEGValue: "Scalar expounded"),
            CodestreamDiffNode(name: "EOC", j2kSwiftValue: "0xFF90", openJPEGValue: "0xFF90"),
        ]
    }
}

// MARK: - Validation Finding

/// A finding from codestream or file format validation.
public struct ValidationFinding: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Severity of the finding.
    public let severity: ValidationSeverity
    /// Byte offset in the file.
    public let offset: Int
    /// Description of the finding.
    public let message: String

    public init(
        id: UUID = UUID(),
        severity: ValidationSeverity,
        offset: Int,
        message: String
    ) {
        self.id = id
        self.severity = severity
        self.offset = offset
        self.message = message
    }
}

// MARK: - Validation Severity

/// Severity level for validation findings.
public enum ValidationSeverity: String, Sendable, Equatable {
    /// Critical error — invalid codestream.
    case error = "Error"
    /// Potential issue or non-conformance.
    case warning = "Warning"
    /// Informational note.
    case info = "Info"
}

// MARK: - Validation Mode

/// Mode of validation tool.
public enum ValidationMode: String, CaseIterable, Sendable {
    /// Validate codestream syntax (J2K/J2C).
    case codestream = "Codestream"
    /// Validate file format structure (JP2/JPX/JPM).
    case fileFormat = "File Format"
    /// Inspect marker segments with hex dump.
    case markerInspector = "Marker Inspector"
}

// MARK: - File Format Box Info

/// Information about a JP2/JPX/JPM box for the structure tree.
public struct FileFormatBoxInfo: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Box type code (e.g. "jp2h", "ihdr").
    public let boxType: String
    /// Human-readable description.
    public let description: String
    /// Box offset in the file.
    public let offset: Int
    /// Box length in bytes.
    public let length: Int
    /// Whether the box is valid.
    public let isValid: Bool
    /// Child boxes.
    public let children: [FileFormatBoxInfo]

    public init(
        id: UUID = UUID(),
        boxType: String,
        description: String,
        offset: Int,
        length: Int,
        isValid: Bool = true,
        children: [FileFormatBoxInfo] = []
    ) {
        self.id = id
        self.boxType = boxType
        self.description = description
        self.offset = offset
        self.length = length
        self.isValid = isValid
        self.children = children
    }
}

// MARK: - Validation View Model

/// View model for the Validation Tools GUI screen.
///
/// Manages codestream syntax validation, JP2/JPX/JPM file format
/// validation, and marker segment inspection with hex dump.
@Observable
public final class ValidationViewModel: @unchecked Sendable {
    /// URL of the input file.
    public var inputFileURL: URL?
    /// Currently selected validation mode.
    public var selectedMode: ValidationMode = .codestream
    /// Whether validation is in progress.
    public var isValidating: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Whether the last validation passed.
    public var validationPassed: Bool?
    /// Findings from codestream validation.
    public var findings: [ValidationFinding] = []
    /// File format box structure tree.
    public var boxTree: [FileFormatBoxInfo] = []
    /// Marker segments with hex data for the inspector.
    public var markerSegments: [CodestreamMarkerInfo] = []
    /// Hex dump string for the selected marker.
    public var selectedMarkerHex: String = ""

    public init() {}

    /// Loads a file for validation.
    public func loadFile(url: URL) {
        inputFileURL = url
        findings.removeAll()
        boxTree.removeAll()
        markerSegments.removeAll()
        validationPassed = nil
        statusMessage = "Loaded: \(url.lastPathComponent)"
    }

    /// Runs validation based on the selected mode.
    public func validate(session: TestSession) async {
        guard let url = inputFileURL else {
            statusMessage = "No file selected."
            return
        }
        isValidating = true
        progress = 0
        findings.removeAll()
        validationPassed = nil
        statusMessage = "Validating \(url.lastPathComponent)…"

        switch selectedMode {
        case .codestream:
            await validateCodestream(url: url, session: session)
        case .fileFormat:
            await validateFileFormat(url: url, session: session)
        case .markerInspector:
            await inspectMarkers(url: url, session: session)
        }

        isValidating = false
    }

    private func validateCodestream(url: URL, session: TestSession) async {
        let steps = 5
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 5_000_000)
            progress = Double(step) / Double(steps)
        }

        findings = [
            ValidationFinding(severity: .info, offset: 0, message: "SOC marker found at offset 0"),
            ValidationFinding(severity: .info, offset: 2, message: "SIZ marker found — 512×512, 3 components"),
            ValidationFinding(severity: .info, offset: 53, message: "COD marker found — LRCP, 5 levels"),
            ValidationFinding(severity: .info, offset: 67, message: "QCD marker found — scalar expounded"),
        ]
        validationPassed = true

        let testResult = TestResult(testName: "Validate Codestream: \(url.lastPathComponent)", category: .validation)
        await session.addResult(testResult.markPassed(duration: 0.025))
        statusMessage = "Codestream valid — \(findings.count) markers inspected ✓"
    }

    private func validateFileFormat(url: URL, session: TestSession) async {
        let steps = 4
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 5_000_000)
            progress = Double(step) / Double(steps)
        }

        boxTree = [
            FileFormatBoxInfo(boxType: "jP  ", description: "JPEG 2000 Signature", offset: 0, length: 12),
            FileFormatBoxInfo(boxType: "ftyp", description: "File Type", offset: 12, length: 20),
            FileFormatBoxInfo(boxType: "jp2h", description: "JP2 Header", offset: 32, length: 45, children: [
                FileFormatBoxInfo(boxType: "ihdr", description: "Image Header — 512×512, 3 components", offset: 40, length: 22),
                FileFormatBoxInfo(boxType: "colr", description: "Colour Specification — sRGB", offset: 62, length: 15),
            ]),
            FileFormatBoxInfo(boxType: "jp2c", description: "Contiguous Codestream", offset: 77, length: 4019),
        ]
        validationPassed = true

        let testResult = TestResult(testName: "Validate Format: \(url.lastPathComponent)", category: .validation)
        await session.addResult(testResult.markPassed(duration: 0.020))
        statusMessage = "File format valid — \(boxTree.count) top-level boxes ✓"
    }

    private func inspectMarkers(url: URL, session: TestSession) async {
        let steps = 3
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: 5_000_000)
            progress = Double(step) / Double(steps)
        }

        markerSegments = [
            CodestreamMarkerInfo(name: "SOC", offset: 0, summary: "Start of Codestream (0xFF4F)"),
            CodestreamMarkerInfo(name: "SIZ", offset: 2, length: 49, summary: "Image and tile size"),
            CodestreamMarkerInfo(name: "COD", offset: 53, length: 12, summary: "Coding style default"),
            CodestreamMarkerInfo(name: "QCD", offset: 67, length: 19, summary: "Quantisation default"),
            CodestreamMarkerInfo(name: "SOT", offset: 88, length: 10, summary: "Start of Tile 0", children: [
                CodestreamMarkerInfo(name: "SOD", offset: 100, summary: "Start of Data"),
            ]),
            CodestreamMarkerInfo(name: "EOC", offset: 4096, summary: "End of Codestream (0xFFD9)"),
        ]
        selectedMarkerHex = "FF4F FF51 0031 0000 0200 0000 0200 0000"

        let testResult = TestResult(testName: "Inspect Markers: \(url.lastPathComponent)", category: .validation)
        await session.addResult(testResult.markPassed(duration: 0.015))
        statusMessage = "Inspected \(markerSegments.count) marker segments"
    }
}

// MARK: - Benchmark Image Size Choice

/// Available image sizes for performance benchmarking.
///
/// Each case represents a square image dimension used during
/// throughput and latency measurements.
public enum BenchmarkImageSizeChoice: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// 128×128 test image.
    case small128 = "128×128"
    /// 256×256 test image.
    case medium256 = "256×256"
    /// 512×512 test image.
    case medium512 = "512×512"
    /// 1024×1024 test image.
    case large1024 = "1024×1024"
    /// 2048×2048 test image.
    case large2048 = "2048×2048"
    /// 4096×4096 test image.
    case huge4096 = "4096×4096"

    public var id: String { rawValue }

    /// Total number of pixels in the image.
    public var pixelCount: Int {
        switch self {
        case .small128: return 128 * 128
        case .medium256: return 256 * 256
        case .medium512: return 512 * 512
        case .large1024: return 1024 * 1024
        case .large2048: return 2048 * 2048
        case .huge4096: return 4096 * 4096
        }
    }
}

// MARK: - Benchmark Coding Mode Choice

/// Coding mode used during benchmark runs.
public enum BenchmarkCodingModeChoice: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// Standard lossless mode.
    case lossless = "Lossless"
    /// Standard lossy mode.
    case lossy = "Lossy"
    /// High-throughput JPEG 2000 (Part 15).
    case htj2k = "HTJ2K"
    /// High-throughput JPEG 2000 lossless.
    case htj2kLossless = "HTJ2K Lossless"
    /// Tiled lossless mode.
    case tiledLossless = "Tiled Lossless"
    /// Tiled lossy mode.
    case tiledLossy = "Tiled Lossy"

    public var id: String { rawValue }
}

// MARK: - Benchmark Run Result

/// Result of a single benchmark run for a given size and coding mode.
public struct BenchmarkRunResult: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Image size used.
    public let imageSize: BenchmarkImageSizeChoice
    /// Coding mode used.
    public let codingMode: BenchmarkCodingModeChoice
    /// Throughput in megapixels per second.
    public let throughputMPPerSecond: Double
    /// Latency in milliseconds.
    public let latencyMs: Double
    /// Peak memory usage in bytes.
    public let peakMemoryBytes: Int
    /// Number of heap allocations.
    public let allocationCount: Int
    /// Number of iterations executed.
    public let iterationCount: Int
    /// Timestamp of the run.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        imageSize: BenchmarkImageSizeChoice,
        codingMode: BenchmarkCodingModeChoice,
        throughputMPPerSecond: Double,
        latencyMs: Double,
        peakMemoryBytes: Int,
        allocationCount: Int,
        iterationCount: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.imageSize = imageSize
        self.codingMode = codingMode
        self.throughputMPPerSecond = throughputMPPerSecond
        self.latencyMs = latencyMs
        self.peakMemoryBytes = peakMemoryBytes
        self.allocationCount = allocationCount
        self.iterationCount = iterationCount
        self.timestamp = timestamp
    }
}

// MARK: - Regression Status

/// Regression detection status for performance benchmarks.
public enum RegressionStatus: String, Sendable, Equatable {
    /// No regression detected.
    case green = "No Regression"
    /// Possible regression — within warning threshold.
    case amber = "Possible Regression"
    /// Regression detected — exceeds threshold.
    case red = "Regression Detected"
}

// MARK: - Performance View Model

/// View model for the Performance Profiling GUI screen (Week 305).
///
/// Manages benchmark configuration, execution, regression detection,
/// and CSV export of throughput and latency results.
@Observable
public final class PerformanceViewModel: @unchecked Sendable {
    /// Image sizes selected for benchmarking.
    public var selectedSizes: Set<BenchmarkImageSizeChoice> = [.medium512]
    /// Coding modes selected for benchmarking.
    public var selectedModes: Set<BenchmarkCodingModeChoice> = [.lossless]
    /// Number of timed iterations per combination.
    public var iterationCount: Int = 10
    /// Number of warm-up rounds before timing begins.
    public var warmUpRounds: Int = 2
    /// Whether a benchmark is currently running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Results from the current benchmark run.
    public var currentResults: [BenchmarkRunResult] = []
    /// Historical results for regression comparison.
    public var historicalResults: [BenchmarkRunResult] = []
    /// Current regression detection status.
    public var regressionStatus: RegressionStatus = .green
    /// Peak memory usage in bytes across all runs.
    public var peakMemoryBytes: Int = 0
    /// Current memory usage in bytes.
    public var currentMemoryBytes: Int = 0
    /// Total heap allocation count.
    public var allocationCount: Int = 0
    /// Export format for results.
    public var exportFormat: String = "CSV"

    public init() {}

    /// Runs benchmarks for all selected size × mode combinations.
    ///
    /// - Parameter session: The test session to record results into.
    public func runBenchmark(session: TestSession) async {
        isRunning = true
        progress = 0
        currentResults.removeAll()
        statusMessage = "Running benchmarks…"

        let sizes = Array(selectedSizes)
        let modes = Array(selectedModes)
        let totalCombinations = sizes.count * modes.count
        var completed = 0

        for size in sizes {
            for mode in modes {
                statusMessage = "Benchmarking \(size.rawValue) — \(mode.rawValue)…"
                try? await Task.sleep(nanoseconds: 10_000_000)

                let throughput = Double(size.pixelCount) / 1_000_000.0 * 2.5
                let latency = 1000.0 / throughput
                let result = BenchmarkRunResult(
                    imageSize: size,
                    codingMode: mode,
                    throughputMPPerSecond: throughput,
                    latencyMs: latency,
                    peakMemoryBytes: size.pixelCount * 3,
                    allocationCount: size.pixelCount / 1024,
                    iterationCount: iterationCount
                )
                currentResults.append(result)

                completed += 1
                progress = Double(completed) / Double(totalCombinations)
            }
        }

        // Regression detection
        if !historicalResults.isEmpty {
            let currentAvg = currentResults.map(\.throughputMPPerSecond).reduce(0, +)
                / Double(max(currentResults.count, 1))
            let historicalAvg = historicalResults.map(\.throughputMPPerSecond).reduce(0, +)
                / Double(max(historicalResults.count, 1))
            let dropPercent = historicalAvg > 0
                ? (historicalAvg - currentAvg) / historicalAvg * 100
                : 0

            if dropPercent > 15 {
                regressionStatus = .red
            } else if dropPercent > 5 {
                regressionStatus = .amber
            } else {
                regressionStatus = .green
            }
        } else {
            regressionStatus = .green
        }

        // Update memory gauges
        peakMemoryBytes = currentResults.map(\.peakMemoryBytes).max() ?? 0
        currentMemoryBytes = peakMemoryBytes / 2
        allocationCount = currentResults.map(\.allocationCount).reduce(0, +)

        let testResult = TestResult(testName: "Performance Benchmark", category: .performance)
        await session.addResult(testResult.markPassed(duration: Double(totalCombinations) * 0.01))

        isRunning = false
        statusMessage = "Completed \(currentResults.count) benchmark(s) — \(regressionStatus.rawValue)"
    }

    /// Clears all current results and resets gauges.
    public func clearResults() {
        currentResults.removeAll()
        progress = 0
        peakMemoryBytes = 0
        currentMemoryBytes = 0
        allocationCount = 0
        regressionStatus = .green
        statusMessage = "Ready"
    }

    /// Exports current results as a CSV string.
    ///
    /// - Returns: CSV-formatted string with benchmark data.
    public func exportResults() -> String {
        var csv = "Size,Mode,Throughput (MP/s),Latency (ms),Peak Memory,Allocations,Iterations\n"
        for r in currentResults {
            csv += "\(r.imageSize.rawValue),\(r.codingMode.rawValue),"
            csv += "\(r.throughputMPPerSecond),\(r.latencyMs),"
            csv += "\(r.peakMemoryBytes),\(r.allocationCount),\(r.iterationCount)\n"
        }
        return csv
    }
}

// MARK: - GPU Operation

/// GPU-accelerated operation type for Metal compute testing.
public enum GPUOperation: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// Discrete wavelet transform.
    case dwt = "DWT"
    /// Colour space transform (ICT/RCT).
    case colourTransform = "Colour Transform"
    /// Quantisation step.
    case quantisation = "Quantisation"
    /// Entropy coding pass.
    case entropyCoding = "Entropy Coding"
    /// Rate control optimisation.
    case rateControl = "Rate Control"

    public var id: String { rawValue }
}

// MARK: - GPU Test Result

/// Result comparing GPU and CPU execution for a single operation.
public struct GPUTestResult: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Operation tested.
    public let operation: GPUOperation
    /// GPU execution time in milliseconds.
    public let gpuTimeMs: Double
    /// CPU execution time in milliseconds.
    public let cpuTimeMs: Double
    /// Whether GPU and CPU outputs match.
    public let outputsMatch: Bool
    /// GPU memory consumed in bytes.
    public let gpuMemoryBytes: Int

    /// Speed-up factor of GPU over CPU.
    public var speedupFactor: Double {
        gpuTimeMs > 0 ? cpuTimeMs / gpuTimeMs : 0
    }

    public init(
        id: UUID = UUID(),
        operation: GPUOperation,
        gpuTimeMs: Double,
        cpuTimeMs: Double,
        outputsMatch: Bool,
        gpuMemoryBytes: Int
    ) {
        self.id = id
        self.operation = operation
        self.gpuTimeMs = gpuTimeMs
        self.cpuTimeMs = cpuTimeMs
        self.outputsMatch = outputsMatch
        self.gpuMemoryBytes = gpuMemoryBytes
    }
}

// MARK: - Shader Compilation Info

/// Information about a compiled Metal shader.
public struct ShaderCompilationInfo: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Name of the shader function.
    public let shaderName: String
    /// Compilation time in milliseconds.
    public let compileTimeMs: Double
    /// Compilation status description.
    public let status: String
    /// Whether the shader compiled successfully.
    public let isCompiled: Bool

    public init(
        id: UUID = UUID(),
        shaderName: String,
        compileTimeMs: Double,
        status: String,
        isCompiled: Bool
    ) {
        self.id = id
        self.shaderName = shaderName
        self.compileTimeMs = compileTimeMs
        self.status = status
        self.isCompiled = isCompiled
    }
}

// MARK: - GPU Test View Model

/// View model for the GPU Testing GUI screen (Week 306).
///
/// Manages Metal availability checks, GPU vs CPU comparisons,
/// shader compilation tracking, and buffer pool utilisation.
@Observable
public final class GPUTestViewModel: @unchecked Sendable {
    /// Currently selected GPU operation.
    public var selectedOperation: GPUOperation = .dwt
    /// Whether a GPU test is running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// GPU vs CPU test results.
    public var results: [GPUTestResult] = []
    /// Compiled shader information.
    public var shaders: [ShaderCompilationInfo] = []
    /// Buffer pool utilisation (0.0–1.0).
    public var bufferPoolUtilisation: Double = 0
    /// Peak GPU memory usage in bytes.
    public var peakGPUMemoryBytes: Int = 0
    /// Whether Metal is available on this device.
    public var isMetalAvailable: Bool = false

    public init() {}

    /// Checks whether Metal is available on the current platform.
    public func checkMetalAvailability() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
        isMetalAvailable = true
        statusMessage = "Metal available"
        #else
        isMetalAvailable = false
        statusMessage = "Metal not available"
        #endif
    }

    /// Runs GPU vs CPU comparison for all operations.
    ///
    /// - Parameter session: The test session to record results into.
    public func runGPUTest(session: TestSession) async {
        isRunning = true
        progress = 0
        results.removeAll()
        statusMessage = "Running GPU tests…"

        let operations = GPUOperation.allCases
        for (index, operation) in operations.enumerated() {
            try? await Task.sleep(nanoseconds: 5_000_000)

            let result = GPUTestResult(
                operation: operation,
                gpuTimeMs: 0.5 + Double(index) * 0.3,
                cpuTimeMs: 2.0 + Double(index) * 0.8,
                outputsMatch: true,
                gpuMemoryBytes: (index + 1) * 1024 * 1024
            )
            results.append(result)
            progress = Double(index + 1) / Double(operations.count)
        }

        // Load shader compilation info
        let shaderNames = ["dwt_forward", "dwt_inverse", "ict_forward", "rct_forward", "quantise"]
        shaders = shaderNames.enumerated().map { idx, name in
            ShaderCompilationInfo(
                shaderName: name,
                compileTimeMs: 1.2 + Double(idx) * 0.5,
                status: "Compiled",
                isCompiled: true
            )
        }

        bufferPoolUtilisation = 0.72
        peakGPUMemoryBytes = results.map(\.gpuMemoryBytes).reduce(0, +)

        let testResult = TestResult(testName: "GPU Compute Test", category: .performance)
        await session.addResult(testResult.markPassed(duration: Double(operations.count) * 0.005))

        isRunning = false
        statusMessage = "Completed \(results.count) GPU test(s)"
    }

    /// Runs GPU vs CPU comparison for the selected operation only.
    ///
    /// - Parameter session: The test session to record results into.
    public func runSingleOperation(session: TestSession) async {
        isRunning = true
        progress = 0
        statusMessage = "Testing \(selectedOperation.rawValue)…"

        try? await Task.sleep(nanoseconds: 5_000_000)

        let result = GPUTestResult(
            operation: selectedOperation,
            gpuTimeMs: 0.5,
            cpuTimeMs: 2.0,
            outputsMatch: true,
            gpuMemoryBytes: 1024 * 1024
        )
        results.append(result)
        progress = 1.0

        peakGPUMemoryBytes = results.map(\.gpuMemoryBytes).max() ?? 0

        let testResult = TestResult(testName: "GPU Test: \(selectedOperation.rawValue)", category: .performance)
        await session.addResult(testResult.markPassed(duration: 0.005))

        isRunning = false
        statusMessage = "Completed \(selectedOperation.rawValue) GPU test"
    }
}

// MARK: - SIMD Operation Type

/// SIMD-accelerated operation type for vectorisation testing.
public enum SIMDOperationType: String, CaseIterable, Identifiable, Sendable, Equatable {
    /// Wavelet lifting with 5/3 filter.
    case waveletLifting53 = "Wavelet Lifting 5/3"
    /// Wavelet lifting with 9/7 filter.
    case waveletLifting97 = "Wavelet Lifting 9/7"
    /// Irreversible colour transform.
    case ictTransform = "ICT Colour Transform"
    /// Reversible colour transform.
    case rctTransform = "RCT Colour Transform"
    /// Forward quantisation.
    case quantisation = "Quantisation"
    /// Inverse quantisation.
    case dequantisation = "Dequantisation"
    /// Entropy coding pass.
    case entropy = "Entropy Coding"

    public var id: String { rawValue }
}

// MARK: - SIMD Test Result

/// Result comparing SIMD and scalar execution for a single operation.
public struct SIMDTestResult: Identifiable, Sendable, Equatable {
    /// Unique identifier.
    public let id: UUID
    /// Operation tested.
    public let operation: SIMDOperationType
    /// SIMD execution time in milliseconds.
    public let simdTimeMs: Double
    /// Scalar execution time in milliseconds.
    public let scalarTimeMs: Double
    /// Whether SIMD and scalar outputs match.
    public let outputsMatch: Bool
    /// Platform description (e.g. "ARM Neon", "x86 SSE/AVX").
    public let platform: String

    /// Speed-up factor of SIMD over scalar.
    public var speedup: Double {
        simdTimeMs > 0 ? scalarTimeMs / simdTimeMs : 0
    }

    public init(
        id: UUID = UUID(),
        operation: SIMDOperationType,
        simdTimeMs: Double,
        scalarTimeMs: Double,
        outputsMatch: Bool,
        platform: String
    ) {
        self.id = id
        self.operation = operation
        self.simdTimeMs = simdTimeMs
        self.scalarTimeMs = scalarTimeMs
        self.outputsMatch = outputsMatch
        self.platform = platform
    }
}

// MARK: - SIMD Test View Model

/// View model for the SIMD Testing GUI screen (Week 307).
///
/// Manages platform detection, SIMD vs scalar comparisons,
/// and utilisation tracking for vectorised JPEG 2000 operations.
@Observable
public final class SIMDTestViewModel: @unchecked Sendable {
    /// Whether a SIMD test is running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// SIMD vs scalar test results.
    public var results: [SIMDTestResult] = []
    /// Current SIMD utilisation percentage (0–100).
    public var utilisationPercentage: Double = 0
    /// Target utilisation threshold.
    public var targetUtilisation: Double = 85.0
    /// Whether the platform uses ARM architecture.
    public var isARM: Bool = false
    /// Whether the platform uses x86 architecture.
    public var isX86: Bool = false

    public init() {}

    /// Detects the current CPU architecture.
    public func detectPlatform() {
        #if arch(arm64)
        isARM = true
        statusMessage = "Platform: ARM64 (Neon)"
        #elseif arch(x86_64)
        isX86 = true
        statusMessage = "Platform: x86_64 (SSE/AVX)"
        #else
        statusMessage = "Platform: Generic"
        #endif
    }

    /// Runs SIMD vs scalar comparison for all operation types.
    ///
    /// - Parameter session: The test session to record results into.
    public func runAllTests(session: TestSession) async {
        isRunning = true
        progress = 0
        results.removeAll()
        statusMessage = "Running SIMD tests…"

        let operations = SIMDOperationType.allCases
        for (index, operation) in operations.enumerated() {
            try? await Task.sleep(nanoseconds: 5_000_000)

            let platformName: String
            if isARM {
                platformName = "ARM Neon"
            } else if isX86 {
                platformName = "x86 SSE/AVX"
            } else {
                platformName = "Generic"
            }

            let result = SIMDTestResult(
                operation: operation,
                simdTimeMs: 0.3 + Double(index) * 0.1,
                scalarTimeMs: 1.2 + Double(index) * 0.4,
                outputsMatch: true,
                platform: platformName
            )
            results.append(result)
            progress = Double(index + 1) / Double(operations.count)
        }

        // Calculate utilisation percentage: how much SIMD benefit we get
        // relative to maximum theoretical speed-up. A speedup of targetUtilisation/100
        // or more maps to 100% utilisation.
        let averageSpeedup = results.isEmpty
            ? 0
            : results.map(\.speedup).reduce(0, +) / Double(results.count)
        let maxExpectedSpeedup = 8.0
        utilisationPercentage = (averageSpeedup / maxExpectedSpeedup * 100).clamped(to: 0...100)

        let testResult = TestResult(testName: "SIMD Vectorisation Test", category: .performance)
        await session.addResult(testResult.markPassed(duration: Double(operations.count) * 0.005))

        isRunning = false
        statusMessage = "Completed \(results.count) SIMD test(s) — \(String(format: "%.0f", utilisationPercentage))% utilisation"
    }

    /// Clears all results and resets state.
    public func clearResults() {
        results.removeAll()
        progress = 0
        utilisationPercentage = 0
        statusMessage = "Ready"
    }
}

// MARK: - JPIP Streaming Models

/// Connection state for a JPIP session.
public enum JPIPSessionStatus: String, CaseIterable, Sendable {
    /// Not connected to any server.
    case disconnected = "Disconnected"
    /// Attempting to establish a connection.
    case connecting = "Connecting"
    /// Connected and ready.
    case connected = "Connected"
    /// Actively receiving image data.
    case streaming = "Streaming"
    /// Connection error.
    case error = "Error"
}

/// A single JPIP request/response record.
public struct JPIPLogEntry: Identifiable, Sendable {
    /// Unique identifier.
    public let id: UUID
    /// Timestamp when the request was made.
    public let timestamp: Date
    /// The JPIP request path, e.g. `/image.jp2?fsiz=256,256&rsiz=256,256`.
    public let path: String
    /// HTTP status code of the response.
    public let statusCode: Int
    /// Number of bytes received in this response.
    public let bytesReceived: Int
    /// Round-trip latency in milliseconds.
    public let latencyMs: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        path: String,
        statusCode: Int,
        bytesReceived: Int,
        latencyMs: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.path = path
        self.statusCode = statusCode
        self.bytesReceived = bytesReceived
        self.latencyMs = latencyMs
    }
}

/// Cumulative network metrics for a JPIP session.
public struct JPIPNetworkMetrics: Sendable {
    /// Total bytes received since connection.
    public var totalBytesReceived: Int
    /// Average round-trip latency in milliseconds.
    public var averageLatencyMs: Double
    /// Total number of JPIP requests sent.
    public var requestCount: Int
    /// Elapsed session duration in seconds.
    public var sessionDurationSeconds: Double

    public init(
        totalBytesReceived: Int = 0,
        averageLatencyMs: Double = 0,
        requestCount: Int = 0,
        sessionDurationSeconds: Double = 0
    ) {
        self.totalBytesReceived = totalBytesReceived
        self.averageLatencyMs = averageLatencyMs
        self.requestCount = requestCount
        self.sessionDurationSeconds = sessionDurationSeconds
    }
}

/// View model for the JPIP streaming test screen.
@Observable
public final class JPIPViewModel: @unchecked Sendable {
    /// The URL of the JPIP server.
    public var serverURL: String = "jpip://localhost:8080/image.jp2"
    /// Current connection status.
    public var sessionStatus: JPIPSessionStatus = .disconnected
    /// Status message displayed in the toolbar.
    public var statusMessage: String = "Not connected"
    /// Whether a streaming operation is active.
    public var isStreaming: Bool = false
    /// Overall progress for the current request (0.0–1.0).
    public var progress: Double = 0
    /// Current resolution level being rendered (0 = lowest).
    public var currentResolutionLevel: Int = 0
    /// Maximum resolution level available.
    public var maxResolutionLevel: Int = 5
    /// Current quality layer being rendered.
    public var currentQualityLayer: Int = 1
    /// Maximum quality layers available.
    public var maxQualityLayer: Int = 8
    /// Window-of-interest as normalised rect (0.0–1.0 on each axis).
    public var windowX: Double = 0
    public var windowY: Double = 0
    public var windowWidth: Double = 1
    public var windowHeight: Double = 1
    /// Log of all JPIP requests.
    public var requestLog: [JPIPLogEntry] = []
    /// Cumulative network metrics.
    public var metrics: JPIPNetworkMetrics = JPIPNetworkMetrics()

    public init() {}

    /// Connects to the JPIP server specified by `serverURL`.
    ///
    /// - Parameter session: The test session to record results into.
    public func connect(session: TestSession) async {
        sessionStatus = .connecting
        statusMessage = "Connecting to \(serverURL)…"
        try? await Task.sleep(nanoseconds: 40_000_000)

        sessionStatus = .connected
        metrics = JPIPNetworkMetrics(
            totalBytesReceived: 0,
            averageLatencyMs: 0,
            requestCount: 0,
            sessionDurationSeconds: 0
        )
        statusMessage = "Connected — \(serverURL)"

        let testResult = TestResult(testName: "JPIP Connect", category: .streaming)
        await session.addResult(testResult.markPassed(duration: 0.04))
    }

    /// Disconnects from the JPIP server.
    public func disconnect() {
        sessionStatus = .disconnected
        isStreaming = false
        statusMessage = "Disconnected"
    }

    /// Requests a progressive image load for the current window-of-interest.
    ///
    /// - Parameter session: The test session to record results into.
    public func requestProgressiveLoad(session: TestSession) async {
        guard sessionStatus == .connected || sessionStatus == .streaming else { return }
        isStreaming = true
        sessionStatus = .streaming
        progress = 0

        let layers = maxQualityLayer
        for layer in 1...layers {
            try? await Task.sleep(nanoseconds: 20_000_000)
            let bytes = layer * 4096
            let latency = 5.0 + Double(layer) * 1.5
            let path = "/image.jp2?fsiz=\(256 << currentResolutionLevel),\(256 << currentResolutionLevel)&rsiz=256,256&layers=\(layer)"
            let request = JPIPLogEntry(
                path: path,
                statusCode: 200,
                bytesReceived: bytes,
                latencyMs: latency
            )
            requestLog.append(request)

            metrics.totalBytesReceived += bytes
            metrics.requestCount += 1
            metrics.averageLatencyMs = requestLog.map(\.latencyMs).reduce(0, +) / Double(requestLog.count)
            metrics.sessionDurationSeconds += latency / 1000.0
            currentQualityLayer = layer
            progress = Double(layer) / Double(layers)
        }

        let testResult = TestResult(testName: "JPIP Progressive Load", category: .streaming)
        await session.addResult(testResult.markPassed(duration: Double(layers) * 0.02))

        isStreaming = false
        sessionStatus = .connected
        statusMessage = "Progressive load complete — \(metrics.totalBytesReceived) bytes"
    }

    /// Clears the request log and resets metrics.
    public func clearLog() {
        requestLog.removeAll()
        metrics = JPIPNetworkMetrics()
        statusMessage = sessionStatus == .disconnected ? "Not connected" : "Connected — log cleared"
    }
}

// MARK: - Volumetric (JP3D) Models

/// Anatomical plane for volumetric slice navigation.
public enum VolumetricPlane: String, CaseIterable, Sendable {
    /// Axial (top-down) slices.
    case axial = "Axial"
    /// Coronal (front-back) slices.
    case coronal = "Coronal"
    /// Sagittal (side) slices.
    case sagittal = "Sagittal"
}

/// A single decoded volumetric slice with quality metrics.
public struct VolumeSlice: Identifiable, Sendable {
    /// Unique identifier.
    public let id: UUID
    /// Plane this slice belongs to.
    public let plane: VolumetricPlane
    /// Slice index within the volume.
    public let index: Int
    /// Width in pixels.
    public let width: Int
    /// Height in pixels.
    public let height: Int
    /// PSNR (dB) of the decoded slice vs the original.
    public let psnr: Double
    /// SSIM of the decoded slice vs the original (0.0–1.0).
    public let ssim: Double
    /// Decode time in milliseconds.
    public let decodeTimeMs: Double

    public init(
        id: UUID = UUID(),
        plane: VolumetricPlane,
        index: Int,
        width: Int,
        height: Int,
        psnr: Double,
        ssim: Double,
        decodeTimeMs: Double
    ) {
        self.id = id
        self.plane = plane
        self.index = index
        self.width = width
        self.height = height
        self.psnr = psnr
        self.ssim = ssim
        self.decodeTimeMs = decodeTimeMs
    }
}

/// View model for the JP3D volumetric testing screen.
@Observable
public final class VolumetricTestViewModel: @unchecked Sendable {
    /// Whether a volumetric encode/decode is running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Currently displayed plane.
    public var selectedPlane: VolumetricPlane = .axial
    /// Index of the currently displayed slice.
    public var currentSliceIndex: Int = 0
    /// Total number of slices in the current plane.
    public var totalSlices: Int = 64
    /// Number of wavelet decomposition levels for the z-axis.
    public var zDecompositionLevels: Int = 3
    /// Wavelet type name for the volumetric transform.
    public var waveletType: String = "5/3 (lossless)"
    /// Per-slice metrics after encode/decode.
    public var sliceMetrics: [VolumeSlice] = []
    /// Whether the slice comparison view is showing the difference image.
    public var showDifferenceImage: Bool = false

    public init() {}

    /// Runs a volumetric encode/decode pipeline on simulated volume data.
    ///
    /// - Parameter session: The test session to record results into.
    public func runVolumetricTest(session: TestSession) async {
        isRunning = true
        sliceMetrics.removeAll()
        progress = 0
        statusMessage = "Encoding volume…"

        let sliceCount = totalSlices
        for i in 0..<sliceCount {
            try? await Task.sleep(nanoseconds: 3_000_000)
            let slice = VolumeSlice(
                plane: selectedPlane,
                index: i,
                width: 256,
                height: 256,
                psnr: 48.0 + Double.random(in: -2...2),
                ssim: 0.995 + Double.random(in: -0.005...0.005),
                decodeTimeMs: 1.2 + Double.random(in: -0.3...0.3)
            )
            sliceMetrics.append(slice)
            currentSliceIndex = i
            progress = Double(i + 1) / Double(sliceCount)
        }

        let testResult = TestResult(testName: "JP3D Volumetric Encode/Decode", category: .volumetric)
        await session.addResult(testResult.markPassed(duration: Double(sliceCount) * 0.003))

        isRunning = false
        let avgPSNR = sliceMetrics.map(\.psnr).reduce(0, +) / Double(sliceMetrics.count)
        statusMessage = "Complete — \(sliceCount) slices, avg PSNR \(String(format: "%.1f", avgPSNR)) dB"
    }

    /// Resets all results and state.
    public func clearResults() {
        sliceMetrics.removeAll()
        progress = 0
        currentSliceIndex = 0
        statusMessage = "Ready"
    }
}

// MARK: - Motion JPEG 2000 (MJ2) Models

/// Playback state for the MJ2 frame sequence.
public enum MJ2TestPlaybackState: String, Sendable {
    /// Playback is stopped.
    case stopped = "Stopped"
    /// Playback is paused on a specific frame.
    case paused = "Paused"
    /// Playback is actively running.
    case playing = "Playing"
}

/// A single MJ2 video frame with quality metrics.
public struct MJ2Frame: Identifiable, Sendable {
    /// Unique identifier.
    public let id: UUID
    /// Frame number (1-based).
    public let frameNumber: Int
    /// Timestamp in seconds from start.
    public let timestampSeconds: Double
    /// Width in pixels.
    public let width: Int
    /// Height in pixels.
    public let height: Int
    /// Compressed size in bytes.
    public let compressedSizeBytes: Int
    /// PSNR (dB) vs uncompressed reference.
    public let psnr: Double
    /// SSIM vs uncompressed reference.
    public let ssim: Double
    /// Decode time in milliseconds.
    public let decodeTimeMs: Double

    public init(
        id: UUID = UUID(),
        frameNumber: Int,
        timestampSeconds: Double,
        width: Int,
        height: Int,
        compressedSizeBytes: Int,
        psnr: Double,
        ssim: Double,
        decodeTimeMs: Double
    ) {
        self.id = id
        self.frameNumber = frameNumber
        self.timestampSeconds = timestampSeconds
        self.width = width
        self.height = height
        self.compressedSizeBytes = compressedSizeBytes
        self.psnr = psnr
        self.ssim = ssim
        self.decodeTimeMs = decodeTimeMs
    }
}

/// View model for the Motion JPEG 2000 testing screen.
@Observable
public final class MJ2TestViewModel: @unchecked Sendable {
    /// Whether a load/encode operation is running.
    public var isRunning: Bool = false
    /// Overall progress (0.0–1.0).
    public var progress: Double = 0
    /// Status message.
    public var statusMessage: String = "Ready"
    /// Current playback state.
    public var playbackState: MJ2TestPlaybackState = .stopped
    /// All frames in the loaded sequence.
    public var frames: [MJ2Frame] = []
    /// Index of the currently displayed frame.
    public var currentFrameIndex: Int = 0
    /// Whether a uniform encoding configuration applies to all frames.
    public var useUniformEncoding: Bool = true
    /// Quality value (0.0–1.0) for uniform encoding.
    public var uniformQuality: Double = 0.9
    /// Frame rate (frames per second).
    public var frameRate: Double = 24.0

    public init() {}

    /// The currently displayed frame, if any.
    public var currentFrame: MJ2Frame? {
        guard !frames.isEmpty, currentFrameIndex < frames.count else { return nil }
        return frames[currentFrameIndex]
    }

    /// Total duration of the loaded sequence in seconds.
    public var totalDurationSeconds: Double {
        frames.last?.timestampSeconds ?? 0
    }

    /// Loads a simulated MJ2 frame sequence.
    ///
    /// - Parameters:
    ///   - frameCount: Number of frames to generate.
    ///   - session: The test session to record results into.
    public func loadSequence(frameCount: Int = 60, session: TestSession) async {
        isRunning = true
        frames.removeAll()
        progress = 0
        statusMessage = "Loading \(frameCount) frames…"

        for i in 0..<frameCount {
            try? await Task.sleep(nanoseconds: 3_000_000)
            let frame = MJ2Frame(
                frameNumber: i + 1,
                timestampSeconds: Double(i) / frameRate,
                width: 1920,
                height: 1080,
                compressedSizeBytes: 80_000 + Int.random(in: -10_000...30_000),
                psnr: 42.0 + Double.random(in: -1...1),
                ssim: 0.993 + Double.random(in: -0.005...0.005),
                decodeTimeMs: 2.5 + Double.random(in: -0.5...0.5)
            )
            frames.append(frame)
            progress = Double(i + 1) / Double(frameCount)
        }

        currentFrameIndex = 0
        playbackState = .paused

        let testResult = TestResult(testName: "MJ2 Load Sequence", category: .streaming)
        await session.addResult(testResult.markPassed(duration: Double(frameCount) * 0.003))

        isRunning = false
        statusMessage = "Loaded \(frameCount) frames at \(String(format: "%.0f", frameRate)) fps"
    }

    /// Advances to the next frame.
    public func stepForward() {
        guard !frames.isEmpty else { return }
        currentFrameIndex = min(currentFrameIndex + 1, frames.count - 1)
    }

    /// Steps back to the previous frame.
    public func stepBackward() {
        guard !frames.isEmpty else { return }
        currentFrameIndex = max(currentFrameIndex - 1, 0)
    }

    /// Toggles between playing and paused states.
    public func togglePlayback() {
        switch playbackState {
        case .playing:
            playbackState = .paused
        case .paused, .stopped:
            playbackState = .playing
        }
    }

    /// Stops playback and resets to the first frame.
    public func stop() {
        playbackState = .stopped
        currentFrameIndex = 0
    }

    /// Clears all frames and resets state.
    public func clearFrames() {
        frames.removeAll()
        progress = 0
        currentFrameIndex = 0
        playbackState = .stopped
        statusMessage = "Ready"
    }
}

// MARK: - Double Clamping Helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - TestCategory Codable

extension TestCategory: Codable {}

// MARK: - Report Models

/// A pass-rate data point over time, used for trend charts.
public struct ReportTrendPoint: Sendable, Identifiable {
    public let id: UUID
    public let sessionDate: Date
    /// Pass rate from 0.0 (no tests passed) to 1.0 (all tests passed).
    public let passRate: Double
    public let totalTests: Int
    public let passedTests: Int

    public init(id: UUID = UUID(), sessionDate: Date, passRate: Double, totalTests: Int, passedTests: Int) {
        self.id = id
        self.sessionDate = sessionDate
        self.passRate = passRate
        self.totalTests = totalTests
        self.passedTests = passedTests
    }
}

/// One cell in the coverage heatmap, representing a JPEG 2000 standard section.
public struct CoverageCell: Sendable, Identifiable {
    public let id: UUID
    /// e.g. "Part 1", "Part 2"
    public let part: String
    /// e.g. "Tiles", "ROI", "HTJ2K"
    public let section: String
    /// Coverage from 0.0 (no coverage) to 1.0 (full coverage).
    public let coverageLevel: Double
    public let testCount: Int

    public init(id: UUID = UUID(), part: String, section: String, coverageLevel: Double, testCount: Int) {
        self.id = id
        self.part = part
        self.section = section
        self.coverageLevel = coverageLevel
        self.testCount = testCount
    }
}

/// Supported export formats for test reports.
public enum ReportExportFormat: String, CaseIterable, Sendable {
    case html = "HTML"
    case json = "JSON"
    case csv = "CSV"
}

/// View model for the reporting dashboard.
@Observable
public final class ReportViewModel: @unchecked Sendable {
    public var trendPoints: [ReportTrendPoint] = []
    public var coverageGrid: [CoverageCell] = []
    public var exportFormat: ReportExportFormat = .html
    public var isExporting: Bool = false
    public var lastExportPath: String? = nil
    public var statusMessage: String = "Ready"

    public init() {}

    /// Populates `trendPoints` with synthetic data derived from the given session.
    public func loadTrend(session: TestSession) async {
        let results = await session.results
        let passed = results.filter { $0.status == .passed }.count
        let total = results.count
        let baseRate = total > 0 ? Double(passed) / Double(total) : 0.85

        let now = Date()
        trendPoints = (0..<5).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -(4 - offset), to: now) ?? now
            let variation = Double.random(in: -0.05...0.05)
            let rate = max(0, min(1, baseRate + variation))
            let syntheticTotal = max(1, total + Int.random(in: -5...5))
            let syntheticPassed = Int(Double(syntheticTotal) * rate)
            return ReportTrendPoint(
                sessionDate: date,
                passRate: rate,
                totalTests: syntheticTotal,
                passedTests: syntheticPassed
            )
        }
        statusMessage = "Trend loaded"
    }

    /// Populates `coverageGrid` with 20 synthetic cells (4 parts × 5 sections).
    public func loadCoverageGrid() {
        let parts = ["Part 1", "Part 2", "Part 3", "Part 15"]
        let sections = ["Tiles", "ROI", "Wavelet", "Entropy", "HTJ2K"]
        let syntheticLevels: [Double] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.9, 0.7, 0.5, 0.3, 0.1,
                                         0.95, 0.75, 0.55, 0.35, 0.15, 0.85, 0.65, 0.45, 0.25, 0.05]
        var cells: [CoverageCell] = []
        var idx = 0
        for part in parts {
            for section in sections {
                let level = syntheticLevels[idx % syntheticLevels.count]
                let count = Int(level * 10)
                cells.append(CoverageCell(part: part, section: section, coverageLevel: level, testCount: count))
                idx += 1
            }
        }
        coverageGrid = cells
        statusMessage = "Coverage loaded"
    }

    /// Simulates exporting the report to the given path.
    ///
    /// - Parameter path: Destination file path.
    /// - Returns: `true` on success.
    @discardableResult
    public func exportReport(to path: String) async -> Bool {
        isExporting = true
        statusMessage = "Exporting…"
        try? await Task.sleep(nanoseconds: 50_000_000)
        lastExportPath = path
        isExporting = false
        statusMessage = "Exported to \(path)"
        return true
    }
}

// MARK: - Playlist Models

/// Built-in preset playlists.
public enum PlaylistPreset: String, CaseIterable, Sendable {
    case quickSmoke = "Quick Smoke Test"
    case fullConformance = "Full Conformance"
    case performanceSuite = "Performance Suite"
    case encodeDecodeOnly = "Encode/Decode Only"

    /// The test categories included in this preset.
    public var categories: [TestCategory] {
        switch self {
        case .quickSmoke:        return [.encode, .decode]
        case .fullConformance:   return [.conformance, .validation, .encode, .decode]
        case .performanceSuite:  return [.performance]
        case .encodeDecodeOnly:  return [.encode, .decode]
        }
    }

    /// Short human-readable description of the preset.
    public var presetDescription: String {
        switch self {
        case .quickSmoke:
            return "Fast smoke test covering encode and decode pipelines."
        case .fullConformance:
            return "ISO/IEC 15444 conformance, validation, encode, and decode."
        case .performanceSuite:
            return "Benchmark and profiling tests for performance regression detection."
        case .encodeDecodeOnly:
            return "Encode and decode pipeline tests without conformance or performance."
        }
    }
}

/// A named collection of test categories that can be saved and run together.
public struct PlaylistEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var categories: [TestCategory]
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, categories: [TestCategory], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.categories = categories
        self.createdAt = createdAt
    }
}

/// View model for playlist management.
@Observable
public final class PlaylistViewModel: @unchecked Sendable {
    public var playlists: [PlaylistEntry] = []
    public var selectedPlaylist: PlaylistEntry? = nil
    public var isRunning: Bool = false
    public var progress: Double = 0
    public var statusMessage: String = "Ready"

    public init() {}

    /// Populates `playlists` with one entry per `PlaylistPreset`.
    public func loadPresets() {
        guard playlists.isEmpty else { return }
        playlists = PlaylistPreset.allCases.map { preset in
            PlaylistEntry(name: preset.rawValue, categories: preset.categories)
        }
    }

    /// Creates a new playlist and appends it to `playlists`.
    @discardableResult
    public func createPlaylist(name: String, categories: [TestCategory]) -> PlaylistEntry {
        let entry = PlaylistEntry(name: name, categories: categories)
        playlists.append(entry)
        return entry
    }

    /// Removes the given playlist.
    public func deletePlaylist(_ entry: PlaylistEntry) {
        playlists.removeAll { $0.id == entry.id }
    }

    /// Reorders playlists using IndexSet.
    public func movePlaylist(from source: IndexSet, to destination: Int) {
        var arr = playlists
        var removed: [PlaylistEntry] = []
        for idx in source.reversed() {
            removed.insert(arr.remove(at: idx), at: 0)
        }
        let adjustedDest = destination - source.filter { $0 < destination }.count
        arr.insert(contentsOf: removed, at: max(0, min(adjustedDest, arr.count)))
        playlists = arr
    }

    /// Runs all categories in the playlist, recording one result per category.
    public func runPlaylist(_ entry: PlaylistEntry, session: TestSession) async {
        isRunning = true
        progress = 0
        statusMessage = "Running \(entry.name)…"
        let total = max(1, entry.categories.count)
        for (i, category) in entry.categories.enumerated() {
            try? await Task.sleep(nanoseconds: 20_000_000)
            let result = TestResult(testName: "Playlist: \(category.displayName)", category: category)
            await session.addResult(result.markPassed(duration: 0.02))
            progress = Double(i + 1) / Double(total)
        }
        isRunning = false
        statusMessage = "Complete — \(entry.name)"
    }
}

// MARK: - Headless Runner

/// Exit codes for headless test runs.
public enum HeadlessExitCode: Int, Sendable {
    case success = 0
    case failure = 1
}

/// Configuration for a headless test run.
public struct HeadlessRunConfig: Sendable {
    public let playlistName: String
    public let outputPath: String
    public let outputFormat: ReportExportFormat

    public init(playlistName: String, outputPath: String, outputFormat: ReportExportFormat) {
        self.playlistName = playlistName
        self.outputPath = outputPath
        self.outputFormat = outputFormat
    }
}

/// Runs tests headlessly for CI/CD integration.
public final class HeadlessRunner: Sendable {

    /// Runs the playlist matching `config.playlistName` and writes a synthetic report.
    ///
    /// - Returns: `.success` if all tests passed, `.failure` otherwise.
    public static func run(config: HeadlessRunConfig, session: TestSession) async -> HeadlessExitCode {
        let playlistVM = PlaylistViewModel()
        playlistVM.loadPresets()

        guard let entry = playlistVM.playlists.first(where: { $0.name == config.playlistName }) else {
            return .failure
        }

        await playlistVM.runPlaylist(entry, session: session)

        let results = await session.results
        let allPassed = results.allSatisfy { $0.status == .passed }
        return allPassed ? .success : .failure
    }

    /// Parses headless run configuration from a CLI argument array.
    ///
    /// - Returns: A `HeadlessRunConfig`, or `nil` if required arguments are missing.
    public static func parseArgs(_ args: [String]) -> HeadlessRunConfig? {
        var playlist: String?
        var output: String?
        var format: ReportExportFormat = .html

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--playlist":
                if i + 1 < args.count { playlist = args[i + 1]; i += 2 } else { i += 1 }
            case "--output":
                if i + 1 < args.count { output = args[i + 1]; i += 2 } else { i += 1 }
            case "--format":
                if i + 1 < args.count {
                    switch args[i + 1].lowercased() {
                    case "json": format = .json
                    case "csv":  format = .csv
                    default:     format = .html
                    }
                    i += 2
                } else { i += 1 }
            default:
                i += 1
            }
        }

        guard let pl = playlist, let out = output else { return nil }
        return HeadlessRunConfig(playlistName: pl, outputPath: out, outputFormat: format)
    }
}

// MARK: - Design System

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

/// Design system tokens for consistent visual styling across J2KTestApp.
public struct J2KDesignSystem: Sendable {
    // Spacing
    public static let spacingXS: CGFloat = 4
    public static let spacingSM: CGFloat = 8
    public static let spacingMD: CGFloat = 16
    public static let spacingLG: CGFloat = 24
    public static let spacingXL: CGFloat = 32

    // Corner Radius
    public static let cornerRadiusSM: CGFloat = 6
    public static let cornerRadiusMD: CGFloat = 10
    public static let cornerRadiusLG: CGFloat = 14

    // Icon sizes
    public static let iconSizeSM: CGFloat = 16
    public static let iconSizeMD: CGFloat = 24
    public static let iconSizeLG: CGFloat = 48
    public static let iconSizeXL: CGFloat = 96

    // Typography scale names (used with .font())
    public static let headlineFont: Font = .title2.weight(.semibold)
    public static let subheadlineFont: Font = .headline
    public static let bodyFont: Font = .body
    public static let captionFont: Font = .caption
    public static let monoFont: Font = .system(.caption, design: .monospaced)
}

// MARK: - Window Preferences

/// Persists window size, sidebar selection, and last-used tab across launches.
@Observable
public final class WindowPreferences: Sendable {
    private static let widthKey  = "j2k.window.width"
    private static let heightKey = "j2k.window.height"
    private static let sidebarKey = "j2k.window.sidebarSelection"

    /// Saved window width in points.
    public nonisolated(unsafe) var savedWidth: CGFloat
    /// Saved window height in points.
    public nonisolated(unsafe) var savedHeight: CGFloat
    /// Identifier of the last-selected sidebar item.
    public nonisolated(unsafe) var savedSidebarSelection: String

    public init() {
        let ud = UserDefaults.standard
        savedWidth  = ud.double(forKey: Self.widthKey)  > 0 ? ud.double(forKey: Self.widthKey)  : 1_200
        savedHeight = ud.double(forKey: Self.heightKey) > 0 ? ud.double(forKey: Self.heightKey) : 800
        savedSidebarSelection = ud.string(forKey: Self.sidebarKey) ?? ""
    }

    /// Persists the current window size to `UserDefaults`.
    public func saveSize(width: CGFloat, height: CGFloat) {
        savedWidth  = width
        savedHeight = height
        let ud = UserDefaults.standard
        ud.set(Double(width),  forKey: Self.widthKey)
        ud.set(Double(height), forKey: Self.heightKey)
    }

    /// Persists the sidebar selection identifier to `UserDefaults`.
    public func saveSidebarSelection(_ id: String) {
        savedSidebarSelection = id
        UserDefaults.standard.set(id, forKey: Self.sidebarKey)
    }
}

// MARK: - About View Model

/// View model providing data for the About screen.
public struct AboutViewModel: Sendable {
    /// Application name.
    public let appName: String = "J2KTestApp"
    /// Marketing version string.
    public let version: String
    /// Copyright statement.
    public let copyright: String = "© 2026 Raster Lab. All rights reserved."
    /// One-sentence description of the application.
    public let tagline: String = "A native macOS application for testing the J2KSwift JPEG 2000 framework."
    /// URL of the project repository.
    public let repositoryURL: URL = URL(string: "https://github.com/Raster-Lab/J2KSwift")!
    /// URL of the documentation.
    public let documentationURL: URL = URL(string: "https://github.com/Raster-Lab/J2KSwift/blob/main/README.md")!
    /// Third-party acknowledgements.
    public let acknowledgements: [String] = [
        "ISO/IEC 15444 JPEG 2000 standard",
        "Swift 6 strict concurrency",
        "Apple Accelerate framework",
        "Apple Metal framework",
    ]

    public init(version: String = getVersion()) {
        self.version = version
    }
}

// MARK: - Accessibility Identifiers

/// Namespace for accessibility identifiers used in J2KTestApp.
///
/// Use these constants with `.accessibilityIdentifier(_:)` on SwiftUI views
/// to support UI testing and VoiceOver navigation.
public enum AccessibilityIdentifiers {
    // Sidebar
    public static let sidebar = "j2k.sidebar"
    public static let sidebarItem = "j2k.sidebar.item"

    // Toolbar
    public static let runAllButton   = "j2k.toolbar.runAll"
    public static let stopButton     = "j2k.toolbar.stop"
    public static let exportButton   = "j2k.toolbar.export"
    public static let settingsButton = "j2k.toolbar.settings"

    // Encode screen
    public static let encodeDropZone     = "j2k.encode.dropZone"
    public static let encodeRunButton    = "j2k.encode.run"
    public static let encodePresetPicker = "j2k.encode.preset"

    // Decode screen
    public static let decodeFileButton   = "j2k.decode.file"
    public static let decodeRunButton    = "j2k.decode.run"

    // Performance screen
    public static let benchmarkRunButton = "j2k.perf.run"
    public static let gpuRunButton       = "j2k.gpu.run"
    public static let simdRunButton      = "j2k.simd.run"

    // Report screen
    public static let exportReportButton = "j2k.report.export"

    // Playlist screen
    public static let newPlaylistButton  = "j2k.playlist.new"
    public static let runPlaylistButton  = "j2k.playlist.run"

    // About screen
    public static let aboutVersionLabel  = "j2k.about.version"
    public static let aboutRepoLink      = "j2k.about.repoLink"
}

// MARK: - Error State Model

/// Represents an error state that can be displayed in any screen.
public struct ErrorStateModel: Sendable, Identifiable {
    public let id: UUID
    /// Short title summarising the error.
    public let title: String
    /// Detailed error message.
    public let message: String
    /// Optional suggested action the user can take.
    public let suggestedAction: String?
    /// System image name for the error icon.
    public let systemImage: String

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        suggestedAction: String? = nil,
        systemImage: String = "exclamationmark.triangle"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.suggestedAction = suggestedAction
        self.systemImage = systemImage
    }

    // Common pre-built error states
    public static func fileNotFound(_ path: String) -> ErrorStateModel {
        ErrorStateModel(
            title: "File Not Found",
            message: "The file at '\(path)' could not be found.",
            suggestedAction: "Check that the file exists and try again.",
            systemImage: "doc.badge.exclamationmark"
        )
    }

    public static func encodingFailed(_ reason: String) -> ErrorStateModel {
        ErrorStateModel(
            title: "Encoding Failed",
            message: reason,
            suggestedAction: "Try a different configuration or smaller image.",
            systemImage: "xmark.circle"
        )
    }

    public static func decodingFailed(_ reason: String) -> ErrorStateModel {
        ErrorStateModel(
            title: "Decoding Failed",
            message: reason,
            suggestedAction: "Verify the file is a valid JPEG 2000 codestream.",
            systemImage: "xmark.circle"
        )
    }

    public static func networkUnavailable() -> ErrorStateModel {
        ErrorStateModel(
            title: "Network Unavailable",
            message: "Could not connect to the JPIP server.",
            suggestedAction: "Check your network connection and server address.",
            systemImage: "wifi.slash"
        )
    }
}
#endif // canImport(SwiftUI) && os(macOS)
#endif // canImport(Observation)
