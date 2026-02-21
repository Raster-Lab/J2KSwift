//
// J2KTestAppTests.swift
// J2KSwift
//
// Unit tests for J2KTestApp models, TestSession actor, and view models.
//

import XCTest
@testable import J2KCore

// MARK: - Test Category Tests

final class TestCategoryTests: XCTestCase {

    // MARK: - Category Properties

    func testAllCategoriesExist() {
        let categories = TestCategory.allCases
        XCTAssertEqual(categories.count, 7)
    }

    func testCategoryRawValues() {
        XCTAssertEqual(TestCategory.encode.rawValue, "Encode")
        XCTAssertEqual(TestCategory.decode.rawValue, "Decode")
        XCTAssertEqual(TestCategory.conformance.rawValue, "Conformance")
        XCTAssertEqual(TestCategory.performance.rawValue, "Performance")
        XCTAssertEqual(TestCategory.streaming.rawValue, "Streaming")
        XCTAssertEqual(TestCategory.volumetric.rawValue, "Volumetric")
        XCTAssertEqual(TestCategory.validation.rawValue, "Validation")
    }

    func testCategoryDisplayNames() {
        for category in TestCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertEqual(category.displayName, category.rawValue)
        }
    }

    func testCategorySystemImages() {
        for category in TestCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty)
        }
    }

    func testCategoryDescriptions() {
        for category in TestCategory.allCases {
            XCTAssertFalse(category.categoryDescription.isEmpty)
            XCTAssertGreaterThan(category.categoryDescription.count, 20)
        }
    }

    func testCategoryIdentifiable() {
        for category in TestCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testCategorySendable() {
        // Verify TestCategory is Sendable by passing across concurrency boundaries
        let category: TestCategory = .encode
        let sendable: any Sendable = category
        XCTAssertNotNil(sendable)
    }
}

// MARK: - Test Status Tests

final class TestStatusTests: XCTestCase {

    func testStatusRawValues() {
        XCTAssertEqual(TestStatus.passed.rawValue, "Passed")
        XCTAssertEqual(TestStatus.failed.rawValue, "Failed")
        XCTAssertEqual(TestStatus.skipped.rawValue, "Skipped")
        XCTAssertEqual(TestStatus.error.rawValue, "Error")
        XCTAssertEqual(TestStatus.running.rawValue, "Running")
        XCTAssertEqual(TestStatus.pending.rawValue, "Pending")
    }

    func testStatusIsComplete() {
        XCTAssertTrue(TestStatus.passed.isComplete)
        XCTAssertTrue(TestStatus.failed.isComplete)
        XCTAssertTrue(TestStatus.skipped.isComplete)
        XCTAssertTrue(TestStatus.error.isComplete)
        XCTAssertFalse(TestStatus.running.isComplete)
        XCTAssertFalse(TestStatus.pending.isComplete)
    }

    func testStatusIsSuccess() {
        XCTAssertTrue(TestStatus.passed.isSuccess)
        XCTAssertFalse(TestStatus.failed.isSuccess)
        XCTAssertFalse(TestStatus.skipped.isSuccess)
        XCTAssertFalse(TestStatus.error.isSuccess)
        XCTAssertFalse(TestStatus.running.isSuccess)
        XCTAssertFalse(TestStatus.pending.isSuccess)
    }
}

// MARK: - Test Result Tests

final class TestResultTests: XCTestCase {

    func testResultCreation() {
        let result = TestResult(testName: "testEncode", category: .encode)
        XCTAssertEqual(result.testName, "testEncode")
        XCTAssertEqual(result.category, .encode)
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.duration, 0)
        XCTAssertEqual(result.message, "")
        XCTAssertTrue(result.metrics.isEmpty)
        XCTAssertNil(result.endTime)
    }

    func testResultMarkPassed() {
        let result = TestResult(testName: "test1", category: .decode)
        let passed = result.markPassed(duration: 1.5, metrics: ["psnr": 42.0])
        XCTAssertEqual(passed.status, .passed)
        XCTAssertEqual(passed.duration, 1.5)
        XCTAssertEqual(passed.metrics["psnr"], 42.0)
        XCTAssertNotNil(passed.endTime)
    }

    func testResultMarkFailed() {
        let result = TestResult(testName: "test2", category: .conformance)
        let failed = result.markFailed(duration: 0.3, message: "Assertion failed")
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.duration, 0.3)
        XCTAssertEqual(failed.message, "Assertion failed")
        XCTAssertNotNil(failed.endTime)
    }

    func testResultMarkSkipped() {
        let result = TestResult(testName: "test3", category: .performance)
        let skipped = result.markSkipped(reason: "Metal not available")
        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertEqual(skipped.message, "Metal not available")
        XCTAssertNotNil(skipped.endTime)
    }

    func testResultMarkError() {
        let result = TestResult(testName: "test4", category: .streaming)
        let errored = result.markError(duration: 0.1, message: "Unexpected crash")
        XCTAssertEqual(errored.status, .error)
        XCTAssertEqual(errored.duration, 0.1)
        XCTAssertEqual(errored.message, "Unexpected crash")
        XCTAssertNotNil(errored.endTime)
    }

    func testResultMarkRunning() {
        let result = TestResult(testName: "test5", category: .validation)
        let running = result.markRunning()
        XCTAssertEqual(running.status, .running)
    }

    func testResultIdentifiable() {
        let result1 = TestResult(testName: "test1", category: .encode)
        let result2 = TestResult(testName: "test2", category: .encode)
        XCTAssertNotEqual(result1.id, result2.id)
    }

    func testResultEquatable() {
        let result = TestResult(testName: "test1", category: .encode)
        let same = result
        XCTAssertEqual(result, same)
    }
}

// MARK: - Test Summary Tests

final class TestSummaryTests: XCTestCase {

    func testEmptySummary() {
        let summary = TestSummary(results: [])
        XCTAssertEqual(summary.total, 0)
        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.errored, 0)
        XCTAssertEqual(summary.passRate, 0)
        XCTAssertTrue(summary.allPassed)
    }

    func testSummaryWithResults() {
        let results = [
            TestResult(testName: "t1", category: .encode).markPassed(duration: 0.1),
            TestResult(testName: "t2", category: .encode).markPassed(duration: 0.2),
            TestResult(testName: "t3", category: .encode).markFailed(duration: 0.1, message: "fail"),
            TestResult(testName: "t4", category: .encode).markSkipped(reason: "skip"),
            TestResult(testName: "t5", category: .encode).markError(duration: 0.05, message: "err"),
        ]
        let summary = TestSummary(results: results)
        XCTAssertEqual(summary.total, 5)
        XCTAssertEqual(summary.passed, 2)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.errored, 1)
        XCTAssertEqual(summary.passRate, 0.5, accuracy: 0.01)
        XCTAssertFalse(summary.allPassed)
    }

    func testSummaryAllPassed() {
        let results = [
            TestResult(testName: "t1", category: .decode).markPassed(duration: 0.1),
            TestResult(testName: "t2", category: .decode).markPassed(duration: 0.2),
        ]
        let summary = TestSummary(results: results)
        XCTAssertTrue(summary.allPassed)
        XCTAssertEqual(summary.passRate, 1.0, accuracy: 0.01)
    }

    func testSummaryTotalDuration() {
        let results = [
            TestResult(testName: "t1", category: .encode).markPassed(duration: 0.5),
            TestResult(testName: "t2", category: .encode).markPassed(duration: 1.0),
            TestResult(testName: "t3", category: .encode).markFailed(duration: 0.3, message: "fail"),
        ]
        let summary = TestSummary(results: results)
        XCTAssertEqual(summary.totalDuration, 1.8, accuracy: 0.01)
    }
}

// MARK: - App Settings Tests

final class AppSettingsTests: XCTestCase {

    func testDefaultSettings() {
        let settings = AppSettings()
        XCTAssertEqual(settings.defaultTileWidth, 256)
        XCTAssertEqual(settings.defaultTileHeight, 256)
        XCTAssertEqual(settings.defaultQuality, 0.9, accuracy: 0.01)
        XCTAssertEqual(settings.defaultDecompositionLevels, 5)
        XCTAssertEqual(settings.defaultQualityLayers, 5)
        XCTAssertFalse(settings.defaultHTJ2K)
        XCTAssertFalse(settings.defaultGPUAcceleration)
        XCTAssertFalse(settings.verboseLogging)
        XCTAssertFalse(settings.autoRunOnDrop)
        XCTAssertEqual(settings.maxRecentSessions, 10)
    }

    func testSettingsSaveAndLoad() throws {
        var settings = AppSettings()
        settings.defaultTileWidth = 512
        settings.defaultQuality = 0.75
        settings.defaultHTJ2K = true
        settings.verboseLogging = true

        let path = NSTemporaryDirectory() + "j2k_test_settings_\(UUID().uuidString).json"
        try settings.save(to: path)

        let loaded = AppSettings.load(from: path)
        XCTAssertEqual(loaded.defaultTileWidth, 512)
        XCTAssertEqual(loaded.defaultQuality, 0.75, accuracy: 0.01)
        XCTAssertTrue(loaded.defaultHTJ2K)
        XCTAssertTrue(loaded.verboseLogging)

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }

    func testSettingsLoadNonExistentFile() {
        let loaded = AppSettings.load(from: "/nonexistent/path/settings.json")
        // Should return defaults
        XCTAssertEqual(loaded.defaultTileWidth, 256)
    }

    func testSettingsEquatable() {
        let settings1 = AppSettings()
        let settings2 = AppSettings()
        XCTAssertEqual(settings1, settings2)
    }

    func testSettingsCodable() throws {
        var settings = AppSettings()
        settings.defaultTileWidth = 128
        settings.defaultDecompositionLevels = 3

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.defaultTileWidth, 128)
        XCTAssertEqual(decoded.defaultDecompositionLevels, 3)
    }
}

// MARK: - Test Session Tests

final class TestSessionTests: XCTestCase {

    func testSessionCreation() async {
        let session = TestSession(sessionName: "Unit Test Session")
        let name = await session.sessionName
        let results = await session.results
        let isRunning = await session.isRunning
        let selected = await session.selectedCategory

        XCTAssertEqual(name, "Unit Test Session")
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(isRunning)
        XCTAssertNil(selected)
    }

    func testSessionCategorySelection() async {
        let session = TestSession()
        await session.selectCategory(.encode)
        let selected = await session.selectedCategory
        XCTAssertEqual(selected, .encode)

        await session.selectCategory(nil)
        let deselected = await session.selectedCategory
        XCTAssertNil(deselected)
    }

    func testSessionAddResult() async {
        let session = TestSession()
        let result = TestResult(testName: "test1", category: .encode)
        await session.addResult(result)

        let results = await session.results
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.testName, "test1")
    }

    func testSessionUpdateResult() async {
        let session = TestSession()
        let result = TestResult(testName: "test1", category: .decode)
        await session.addResult(result)

        let updated = result.markPassed(duration: 0.5)
        await session.updateResult(updated)

        let results = await session.results
        XCTAssertEqual(results.first?.status, .passed)
        XCTAssertEqual(results.first?.duration, 0.5)
    }

    func testSessionClearResults() async {
        let session = TestSession()
        await session.addResult(TestResult(testName: "t1", category: .encode))
        await session.addResult(TestResult(testName: "t2", category: .decode))
        await session.clearResults()

        let results = await session.results
        XCTAssertTrue(results.isEmpty)
    }

    func testSessionResultsForCategory() async {
        let session = TestSession()
        await session.addResult(TestResult(testName: "enc1", category: .encode))
        await session.addResult(TestResult(testName: "dec1", category: .decode))
        await session.addResult(TestResult(testName: "enc2", category: .encode))

        let encodeResults = await session.results(for: .encode)
        XCTAssertEqual(encodeResults.count, 2)

        let decodeResults = await session.results(for: .decode)
        XCTAssertEqual(decodeResults.count, 1)
    }

    func testSessionSummary() async {
        let session = TestSession()
        let passed = TestResult(testName: "t1", category: .encode).markPassed(duration: 0.1)
        let failed = TestResult(testName: "t2", category: .encode).markFailed(duration: 0.2, message: "fail")
        await session.addResult(passed)
        await session.addResult(failed)

        let summary = await session.summary()
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 1)
    }

    func testSessionSummaryForCategory() async {
        let session = TestSession()
        let enc = TestResult(testName: "enc1", category: .encode).markPassed(duration: 0.1)
        let dec = TestResult(testName: "dec1", category: .decode).markFailed(duration: 0.1, message: "fail")
        await session.addResult(enc)
        await session.addResult(dec)

        let encodeSummary = await session.summary(for: .encode)
        XCTAssertEqual(encodeSummary.passed, 1)
        XCTAssertEqual(encodeSummary.failed, 0)

        let decodeSummary = await session.summary(for: .decode)
        XCTAssertEqual(decodeSummary.passed, 0)
        XCTAssertEqual(decodeSummary.failed, 1)
    }

    func testSessionStartStop() async {
        let session = TestSession()
        await session.start()
        var isRunning = await session.isRunning
        XCTAssertTrue(isRunning)

        await session.stop()
        isRunning = await session.isRunning
        XCTAssertFalse(isRunning)
    }

    func testSessionSettings() async {
        let session = TestSession()
        var newSettings = AppSettings()
        newSettings.defaultTileWidth = 512
        await session.updateSettings(newSettings)

        let settings = await session.settings
        XCTAssertEqual(settings.defaultTileWidth, 512)
    }

    func testSessionLogging() async {
        let session = TestSession()
        await session.addLog("Test started", level: .info)
        await session.addLog("Warning occurred", level: .warning)

        let logs = await session.logMessages
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].message, "Test started")
        XCTAssertEqual(logs[0].level, .info)
        XCTAssertEqual(logs[1].level, .warning)
    }

    func testSessionClearLogs() async {
        let session = TestSession()
        await session.addLog("Log 1", level: .info)
        await session.clearLogs()

        let logs = await session.logMessages
        XCTAssertTrue(logs.isEmpty)
    }

    func testSessionRename() async {
        let session = TestSession(sessionName: "Original")
        await session.rename("Renamed")
        let name = await session.sessionName
        XCTAssertEqual(name, "Renamed")
    }
}

// MARK: - Log Message Tests

final class LogMessageTests: XCTestCase {

    func testLogMessageCreation() {
        let message = LogMessage(message: "Test log", level: .info)
        XCTAssertEqual(message.message, "Test log")
        XCTAssertEqual(message.level, .info)
        XCTAssertNotNil(message.timestamp)
    }

    func testLogLevelOrdering() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, "DEBUG")
        XCTAssertEqual(LogLevel.info.rawValue, "INFO")
        XCTAssertEqual(LogLevel.warning.rawValue, "WARNING")
        XCTAssertEqual(LogLevel.error.rawValue, "ERROR")
    }
}

// MARK: - Test Runner Registry Tests

final class TestRunnerRegistryTests: XCTestCase {

    /// A mock test runner for testing the registry.
    struct MockTestRunner: TestRunnerProtocol {
        let runnerID: String
        let runnerName: String
        let category: TestCategory
        let availableTests: [String]

        func runAll(progress: @Sendable (TestResult) -> Void) async -> [TestResult] {
            availableTests.map { name in
                TestResult(testName: name, category: category).markPassed(duration: 0.01)
            }
        }

        func run(testName: String, progress: @Sendable (TestResult) -> Void) async -> TestResult {
            TestResult(testName: testName, category: category).markPassed(duration: 0.01)
        }
    }

    func testRegistryRegisterAndRetrieve() {
        let registry = TestRunnerRegistry.shared
        let runner = MockTestRunner(
            runnerID: "mock-encode",
            runnerName: "Mock Encoder",
            category: .encode,
            availableTests: ["test1", "test2"]
        )
        registry.register(runner)

        let retrieved = registry.runner(withID: "mock-encode")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.runnerID, "mock-encode")
    }

    func testRegistryRunnersByCategory() {
        let registry = TestRunnerRegistry.shared
        let runner1 = MockTestRunner(
            runnerID: "mock-decode-1",
            runnerName: "Mock Decoder 1",
            category: .decode,
            availableTests: ["d1"]
        )
        let runner2 = MockTestRunner(
            runnerID: "mock-decode-2",
            runnerName: "Mock Decoder 2",
            category: .decode,
            availableTests: ["d2"]
        )
        registry.register(runner1)
        registry.register(runner2)

        let decodeRunners = registry.runners(for: .decode)
        XCTAssertGreaterThanOrEqual(decodeRunners.count, 2)
    }

    func testRegistryAllRunners() {
        let registry = TestRunnerRegistry.shared
        // Register a runner to ensure there's at least one
        let runner = MockTestRunner(
            runnerID: "mock-all-test",
            runnerName: "Mock All Test",
            category: .validation,
            availableTests: ["v1"]
        )
        registry.register(runner)
        let runners = registry.allRunners()
        XCTAssertGreaterThan(runners.count, 0)
    }
}

// MARK: - Pipeline Stage Tests

final class PipelineStageTests: XCTestCase {

    func testAllPipelineStages() {
        let stages = PipelineStage.allCases
        XCTAssertEqual(stages.count, 6)
    }

    func testStageRawValues() {
        XCTAssertEqual(PipelineStage.colourTransform.rawValue, "Colour Transform")
        XCTAssertEqual(PipelineStage.dwt.rawValue, "DWT")
        XCTAssertEqual(PipelineStage.quantise.rawValue, "Quantise")
        XCTAssertEqual(PipelineStage.entropyCoding.rawValue, "Entropy Coding")
        XCTAssertEqual(PipelineStage.rateControl.rawValue, "Rate Control")
        XCTAssertEqual(PipelineStage.packaging.rawValue, "Packaging")
    }

    func testStageProgressCreation() {
        let progress = StageProgress(stage: .dwt, progress: 0.5, duration: 0.1, isActive: true)
        XCTAssertEqual(progress.stage, .dwt)
        XCTAssertEqual(progress.progress, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.duration, 0.1)
        XCTAssertTrue(progress.isActive)
    }

    func testStageProgressDefaults() {
        let progress = StageProgress(stage: .quantise)
        XCTAssertEqual(progress.progress, 0)
        XCTAssertNil(progress.duration)
        XCTAssertFalse(progress.isActive)
    }
}

#if canImport(Observation)
// MARK: - View Model Tests

final class TestCategoryViewModelTests: XCTestCase {

    func testViewModelCreation() {
        let vm = TestCategoryViewModel(category: .encode)
        XCTAssertEqual(vm.category, .encode)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNil(vm.selectedResult)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
    }

    func testViewModelClearResults() {
        let vm = TestCategoryViewModel(category: .decode)
        vm.results.append(TestResult(testName: "t1", category: .decode))
        vm.clearResults()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.selectedResult)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
    }

    func testViewModelStopTests() {
        let vm = TestCategoryViewModel(category: .performance)
        vm.isRunning = true
        vm.stopTests()
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.statusMessage, "Stopped")
    }

    func testViewModelSummary() {
        let vm = TestCategoryViewModel(category: .conformance)
        vm.results.append(TestResult(testName: "t1", category: .conformance).markPassed(duration: 0.1))
        vm.results.append(TestResult(testName: "t2", category: .conformance).markFailed(duration: 0.2, message: "fail"))
        let summary = vm.summary
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 1)
    }
}

final class MainViewModelTests: XCTestCase {

    func testMainViewModelCreation() {
        let vm = MainViewModel()
        XCTAssertNil(vm.selectedCategory)
        XCTAssertFalse(vm.isRunningAll)
        XCTAssertEqual(vm.globalStatusMessage, "Ready")
        XCTAssertEqual(vm.categoryViewModels.count, TestCategory.allCases.count)
    }

    func testMainViewModelCategorySelection() {
        let vm = MainViewModel()
        vm.selectedCategory = .encode
        XCTAssertEqual(vm.selectedCategory, .encode)
    }

    func testMainViewModelGetViewModelForCategory() {
        let vm = MainViewModel()
        let encodeVM = vm.viewModel(for: .encode)
        XCTAssertEqual(encodeVM.category, .encode)
    }

    func testMainViewModelStopAllTests() {
        let vm = MainViewModel()
        vm.isRunningAll = true
        vm.stopAllTests()
        XCTAssertFalse(vm.isRunningAll)
        XCTAssertEqual(vm.globalStatusMessage, "Stopped")
    }

    func testMainViewModelExportResults() async {
        let vm = MainViewModel()
        let path = NSTemporaryDirectory() + "j2k_export_test_\(UUID().uuidString).json"
        let success = await vm.exportResults(to: path)
        XCTAssertTrue(success)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        try? FileManager.default.removeItem(atPath: path)
    }
}
#endif
