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

// MARK: - Encode Configuration Tests

final class EncodeConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = EncodeConfiguration()
        XCTAssertEqual(config.quality, 0.9)
        XCTAssertEqual(config.tileWidth, 256)
        XCTAssertEqual(config.tileHeight, 256)
        XCTAssertEqual(config.decompositionLevels, 5)
        XCTAssertEqual(config.qualityLayers, 5)
        XCTAssertEqual(config.progressionOrder, .lrcp)
        XCTAssertEqual(config.waveletType, .nineSevenFloat)
        XCTAssertTrue(config.mctEnabled)
        XCTAssertFalse(config.htj2kEnabled)
    }

    func testLosslessPreset() {
        let config = EncodeConfiguration.Preset.lossless.configuration
        XCTAssertEqual(config.quality, 1.0)
        XCTAssertEqual(config.waveletType, .fiveThree)
        XCTAssertEqual(config.qualityLayers, 1)
    }

    func testHighQualityPreset() {
        let config = EncodeConfiguration.Preset.highQuality.configuration
        XCTAssertEqual(config.quality, 0.95)
        XCTAssertEqual(config.waveletType, .nineSevenFloat)
        XCTAssertEqual(config.qualityLayers, 5)
    }

    func testVisuallyLosslessPreset() {
        let config = EncodeConfiguration.Preset.visuallyLossless.configuration
        XCTAssertEqual(config.quality, 0.85)
        XCTAssertEqual(config.progressionOrder, .rlcp)
    }

    func testMaxCompressionPreset() {
        let config = EncodeConfiguration.Preset.maxCompression.configuration
        XCTAssertEqual(config.quality, 0.5)
        XCTAssertEqual(config.tileWidth, 512)
        XCTAssertEqual(config.tileHeight, 512)
        XCTAssertEqual(config.qualityLayers, 10)
    }

    func testAllPresetsHaveUniqueQualities() {
        let qualities = EncodeConfiguration.Preset.allCases.map { $0.configuration.quality }
        let unique = Set(qualities)
        XCTAssertEqual(unique.count, EncodeConfiguration.Preset.allCases.count)
    }

    func testProgressionOrderAllCases() {
        XCTAssertEqual(ProgressionOrderChoice.allCases.count, 5)
        XCTAssertEqual(ProgressionOrderChoice.lrcp.rawValue, "LRCP")
        XCTAssertEqual(ProgressionOrderChoice.cprl.rawValue, "CPRL")
    }

    func testWaveletTypeAllCases() {
        XCTAssertEqual(WaveletTypeChoice.allCases.count, 4)
        XCTAssertEqual(WaveletTypeChoice.fiveThree.rawValue, "5/3 (Lossless)")
        XCTAssertEqual(WaveletTypeChoice.haar.rawValue, "Haar")
    }
}

// MARK: - Encode Operation Result Tests

final class EncodeOperationResultTests: XCTestCase {

    func testCompressionRatio() {
        let result = EncodeOperationResult(
            inputFileName: "test.png",
            inputSize: 1000,
            encodedSize: 200,
            encodingTime: 0.05
        )
        XCTAssertEqual(result.compressionRatio, 5.0, accuracy: 0.001)
    }

    func testCompressionRatioZeroEncodedSize() {
        let result = EncodeOperationResult(
            inputFileName: "test.png",
            inputSize: 1000,
            encodedSize: 0,
            encodingTime: 0.01
        )
        XCTAssertEqual(result.compressionRatio, 0)
    }

    func testSuccessfulResult() {
        let result = EncodeOperationResult(
            inputFileName: "img.png",
            inputSize: 4096,
            encodedSize: 512,
            encodingTime: 0.1,
            succeeded: true
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.errorMessage.isEmpty)
    }

    func testFailedResult() {
        let result = EncodeOperationResult(
            inputFileName: "img.png",
            inputSize: 4096,
            encodedSize: 0,
            encodingTime: 0.01,
            succeeded: false,
            errorMessage: "Invalid input"
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.errorMessage, "Invalid input")
    }
}

// MARK: - Encode View Model Tests

final class EncodeViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = EncodeViewModel()
        XCTAssertNil(vm.inputImageURL)
        XCTAssertNil(vm.inputImageData)
        XCTAssertFalse(vm.isEncoding)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertNil(vm.lastResult)
        XCTAssertNil(vm.outputData)
        XCTAssertTrue(vm.batchResults.isEmpty)
    }

    func testApplyPreset() {
        let vm = EncodeViewModel()
        vm.applyPreset(.lossless)
        XCTAssertEqual(vm.configuration.quality, 1.0)
        XCTAssertEqual(vm.configuration.waveletType, .fiveThree)
    }

    func testApplyAllPresets() {
        let vm = EncodeViewModel()
        for preset in EncodeConfiguration.Preset.allCases {
            vm.applyPreset(preset)
            XCTAssertEqual(vm.configuration, preset.configuration)
        }
    }

    func testSetInputImage() {
        let vm = EncodeViewModel()
        let url = URL(fileURLWithPath: "/tmp/sample.png")
        vm.inputImageURL = url
        vm.statusMessage = "Loaded: sample.png"
        XCTAssertEqual(vm.inputImageURL, url)
        XCTAssertEqual(vm.statusMessage, "Loaded: sample.png")
    }

    func testSetBatchInputURLs() {
        let vm = EncodeViewModel()
        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/img\($0).png") }
        vm.setBatchInputURLs(urls)
        XCTAssertEqual(vm.batchInputURLs.count, 5)
        XCTAssertTrue(vm.statusMessage.contains("5"))
    }

    func testAddAndRemoveComparisonConfiguration() {
        let vm = EncodeViewModel()
        let config = EncodeConfiguration.Preset.highQuality.configuration
        vm.addComparisonConfiguration(config)
        XCTAssertEqual(vm.comparisonConfigurations.count, 1)
        vm.removeComparisonConfiguration(at: 0)
        XCTAssertTrue(vm.comparisonConfigurations.isEmpty)
    }

    func testRemoveComparisonConfigurationOutOfBoundsDoesNotCrash() {
        let vm = EncodeViewModel()
        vm.removeComparisonConfiguration(at: 99) // Should not crash
        XCTAssertTrue(vm.comparisonConfigurations.isEmpty)
    }

    func testEncodedSizeStringBeforeEncoding() {
        let vm = EncodeViewModel()
        XCTAssertEqual(vm.encodedSizeString, "—")
        XCTAssertEqual(vm.compressionRatioString, "—")
        XCTAssertEqual(vm.encodingTimeString, "—")
    }

    func testEncodeWithoutInput() async {
        let vm = EncodeViewModel()
        let session = TestSession()
        await vm.encode(session: session)
        XCTAssertEqual(vm.statusMessage, "No input image selected.")
        XCTAssertFalse(vm.isEncoding)
    }

    func testEncodeWithInput() async {
        let vm = EncodeViewModel()
        vm.inputImageData = Data(repeating: 128, count: 1024)
        vm.inputImageURL = URL(fileURLWithPath: "/tmp/test.png")
        let session = TestSession()
        await vm.encode(session: session)
        XCTAssertFalse(vm.isEncoding)
        XCTAssertNotNil(vm.lastResult)
        XCTAssertNotNil(vm.outputData)
        XCTAssertTrue(vm.lastResult?.succeeded == true)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    func testEncodeSetsMetricsStrings() async {
        let vm = EncodeViewModel()
        vm.inputImageData = Data(repeating: 0, count: 2048)
        vm.inputImageURL = URL(fileURLWithPath: "/tmp/img.png")
        let session = TestSession()
        await vm.encode(session: session)
        XCTAssertNotEqual(vm.encodedSizeString, "—")
        XCTAssertNotEqual(vm.compressionRatioString, "—")
        XCTAssertNotEqual(vm.encodingTimeString, "—")
    }
}

// MARK: - Decode Configuration Tests

final class DecodeConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = DecodeConfiguration()
        XCTAssertEqual(config.resolutionLevel, 0)
        XCTAssertEqual(config.qualityLayer, 0)
        XCTAssertNil(config.regionOfInterest)
        XCTAssertNil(config.componentIndex)
    }

    func testCustomConfiguration() {
        let roi = CGRect(x: 10, y: 20, width: 100, height: 80)
        let config = DecodeConfiguration(
            resolutionLevel: 2,
            qualityLayer: 3,
            regionOfInterest: roi,
            componentIndex: 1
        )
        XCTAssertEqual(config.resolutionLevel, 2)
        XCTAssertEqual(config.qualityLayer, 3)
        XCTAssertEqual(config.regionOfInterest, roi)
        XCTAssertEqual(config.componentIndex, 1)
    }
}

// MARK: - Codestream Marker Info Tests

final class CodestreamMarkerInfoTests: XCTestCase {

    func testMarkerCreation() {
        let marker = CodestreamMarkerInfo(name: "SOC", offset: 0)
        XCTAssertEqual(marker.name, "SOC")
        XCTAssertEqual(marker.offset, 0)
        XCTAssertNil(marker.length)
        XCTAssertTrue(marker.summary.isEmpty)
        XCTAssertTrue(marker.children.isEmpty)
    }

    func testMarkerWithChildren() {
        let child = CodestreamMarkerInfo(name: "SOD", offset: 100)
        let parent = CodestreamMarkerInfo(name: "SOT", offset: 88, length: 10, children: [child])
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.children.first?.name, "SOD")
    }

    func testMarkerIdentifiable() {
        let m1 = CodestreamMarkerInfo(name: "SOC", offset: 0)
        let m2 = CodestreamMarkerInfo(name: "SOC", offset: 0)
        // Each marker gets a unique UUID
        XCTAssertNotEqual(m1.id, m2.id)
    }
}

// MARK: - Decode View Model Tests

final class DecodeViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = DecodeViewModel()
        XCTAssertNil(vm.inputFileURL)
        XCTAssertFalse(vm.isDecoding)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertNil(vm.lastResult)
        XCTAssertNil(vm.outputImageData)
        XCTAssertTrue(vm.markers.isEmpty)
        XCTAssertTrue(vm.codestreamHeaderSummary.isEmpty)
        XCTAssertFalse(vm.isROISelectionActive)
        XCTAssertEqual(vm.maxResolutionLevel, 5)
        XCTAssertEqual(vm.maxQualityLayer, 5)
    }

    func testLoadFile() {
        let vm = DecodeViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.jp2")
        vm.loadFile(url: url)
        XCTAssertEqual(vm.inputFileURL, url)
        XCTAssertFalse(vm.markers.isEmpty)
        XCTAssertFalse(vm.codestreamHeaderSummary.isEmpty)
        XCTAssertTrue(vm.statusMessage.contains("test.jp2"))
    }

    func testLoadFileSetsExpectedMarkers() {
        let vm = DecodeViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.jp2"))
        let markerNames = vm.markers.map { $0.name }
        XCTAssertTrue(markerNames.contains("SOC"))
        XCTAssertTrue(markerNames.contains("EOC"))
        XCTAssertTrue(markerNames.contains("SIZ"))
    }

    func testSetRegionOfInterest() {
        let vm = DecodeViewModel()
        let roi = CGRect(x: 0, y: 0, width: 128, height: 128)
        vm.setRegionOfInterest(roi)
        XCTAssertEqual(vm.configuration.regionOfInterest, roi)
        XCTAssertTrue(vm.statusMessage.contains("128"))
    }

    func testClearRegionOfInterest() {
        let vm = DecodeViewModel()
        vm.setRegionOfInterest(CGRect(x: 0, y: 0, width: 64, height: 64))
        vm.clearRegionOfInterest()
        XCTAssertNil(vm.configuration.regionOfInterest)
        XCTAssertTrue(vm.statusMessage.contains("cleared"))
    }

    func testDecodeTimeStringBeforeDecoding() {
        let vm = DecodeViewModel()
        XCTAssertEqual(vm.decodingTimeString, "—")
    }

    func testDecodeWithoutFile() async {
        let vm = DecodeViewModel()
        let session = TestSession()
        await vm.decode(session: session)
        XCTAssertEqual(vm.statusMessage, "No input file selected.")
        XCTAssertFalse(vm.isDecoding)
    }

    func testDecodeWithFile() async {
        let vm = DecodeViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.jp2"))
        let session = TestSession()
        await vm.decode(session: session)
        XCTAssertFalse(vm.isDecoding)
        XCTAssertNotNil(vm.lastResult)
        XCTAssertNotNil(vm.outputImageData)
        XCTAssertTrue(vm.lastResult?.succeeded == true)
        XCTAssertEqual(vm.lastResult?.imageWidth, 512)
        XCTAssertEqual(vm.lastResult?.imageHeight, 512)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }
}

// MARK: - Round-Trip Metrics Tests

final class RoundTripMetricsTests: XCTestCase {

    func testLosslessMetrics() {
        let metrics = RoundTripMetrics(psnr: .infinity, ssim: 1.0, mse: 0.0, isBitExact: true)
        XCTAssertTrue(metrics.isBitExact)
        XCTAssertTrue(metrics.passes)
        XCTAssertEqual(metrics.mse, 0.0)
    }

    func testPassingLossyMetrics() {
        let metrics = RoundTripMetrics(psnr: 45.0, ssim: 0.995, mse: 0.5)
        XCTAssertTrue(metrics.psnrPasses)
        XCTAssertTrue(metrics.ssimPasses)
        XCTAssertTrue(metrics.passes)
    }

    func testFailingPSNR() {
        let metrics = RoundTripMetrics(psnr: 35.0, ssim: 0.995, mse: 2.0)
        XCTAssertFalse(metrics.psnrPasses)
        XCTAssertFalse(metrics.passes)
    }

    func testFailingSSIM() {
        let metrics = RoundTripMetrics(psnr: 50.0, ssim: 0.97, mse: 1.0)
        XCTAssertFalse(metrics.ssimPasses)
        XCTAssertFalse(metrics.passes)
    }

    func testThresholds() {
        XCTAssertEqual(RoundTripMetrics.psnrPassThreshold, 40.0, accuracy: 0.001)
        XCTAssertEqual(RoundTripMetrics.ssimPassThreshold, 0.99, accuracy: 0.001)
    }
}

// MARK: - Round-Trip View Model Tests

final class RoundTripViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = RoundTripViewModel()
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertNil(vm.originalImageData)
        XCTAssertNil(vm.roundTrippedImageData)
        XCTAssertNil(vm.metrics)
        XCTAssertFalse(vm.showDifferenceImage)
        XCTAssertEqual(vm.selectedTestImageType, .gradient)
    }

    func testGenerateGradientTestImage() {
        let vm = RoundTripViewModel()
        vm.selectedTestImageType = .gradient
        vm.generateTestImage()
        XCTAssertNotNil(vm.encodeViewModel.inputImageData)
        XCTAssertFalse(vm.encodeViewModel.inputImageData!.isEmpty)
        XCTAssertTrue(vm.statusMessage.contains("Gradient"))
    }

    func testGenerateCheckerboardTestImage() {
        let vm = RoundTripViewModel()
        vm.selectedTestImageType = .checkerboard
        vm.generateTestImage()
        XCTAssertNotNil(vm.encodeViewModel.inputImageData)
        XCTAssertTrue(vm.statusMessage.contains("Checkerboard"))
    }

    func testGenerateAllTestImageTypes() {
        let vm = RoundTripViewModel()
        for imageType in RoundTripViewModel.TestImageType.allCases {
            vm.selectedTestImageType = imageType
            vm.generateTestImage()
            XCTAssertNotNil(vm.encodeViewModel.inputImageData)
            XCTAssertFalse(vm.encodeViewModel.inputImageData!.isEmpty)
        }
    }

    func testRoundTripWithoutInput() async {
        let vm = RoundTripViewModel()
        let session = TestSession()
        await vm.runRoundTrip(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertTrue(vm.statusMessage.contains("No input"))
    }

    func testRoundTripLossless() async {
        let vm = RoundTripViewModel()
        vm.selectedTestImageType = .gradient
        vm.generateTestImage()
        vm.encodeViewModel.applyPreset(.lossless)
        let session = TestSession()
        await vm.runRoundTrip(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNotNil(vm.metrics)
        XCTAssertTrue(vm.metrics?.isBitExact == true)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
        XCTAssertTrue(vm.statusMessage.contains("Bit-exact"))
    }

    func testRoundTripLossy() async {
        let vm = RoundTripViewModel()
        vm.selectedTestImageType = .checkerboard
        vm.generateTestImage()
        vm.encodeViewModel.applyPreset(.highQuality)
        let session = TestSession()
        await vm.runRoundTrip(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNotNil(vm.metrics)
        XCTAssertFalse(vm.metrics?.isBitExact == true)
        XCTAssertNotNil(vm.roundTrippedImageData)
    }

    func testRoundTripRecordsResults() async {
        let vm = RoundTripViewModel()
        vm.generateTestImage()
        let session = TestSession()
        await vm.runRoundTrip(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testTestImageTypeAllCases() {
        XCTAssertEqual(RoundTripViewModel.TestImageType.allCases.count, 5)
    }
}

// MARK: - Conformance Part Tests

final class ConformancePartTests: XCTestCase {

    func testAllPartsExist() {
        XCTAssertEqual(ConformancePart.allCases.count, 4)
    }

    func testPartRawValues() {
        XCTAssertEqual(ConformancePart.part1.rawValue, "Part 1")
        XCTAssertEqual(ConformancePart.part2.rawValue, "Part 2")
        XCTAssertEqual(ConformancePart.part3_10.rawValue, "Part 3/10")
        XCTAssertEqual(ConformancePart.part15.rawValue, "Part 15")
    }

    func testPartIdentifiable() {
        XCTAssertEqual(ConformancePart.part1.id, "Part 1")
    }
}

// MARK: - Conformance Cell Status Tests

final class ConformanceCellStatusTests: XCTestCase {

    func testCellStatusRawValues() {
        XCTAssertEqual(ConformanceCellStatus.pass.rawValue, "Pass")
        XCTAssertEqual(ConformanceCellStatus.fail.rawValue, "Fail")
        XCTAssertEqual(ConformanceCellStatus.skip.rawValue, "Skip")
    }
}

// MARK: - Conformance Requirement Tests

final class ConformanceRequirementTests: XCTestCase {

    func testRequirementCreation() {
        let req = ConformanceRequirement(
            requirementId: "T.1.1",
            description: "SOC marker present"
        )
        XCTAssertEqual(req.requirementId, "T.1.1")
        XCTAssertEqual(req.description, "SOC marker present")
        XCTAssertTrue(req.results.isEmpty)
        XCTAssertTrue(req.detailLog.isEmpty)
    }

    func testRequirementWithResults() {
        let req = ConformanceRequirement(
            requirementId: "T.2.1",
            description: "Part 2 extended capabilities",
            results: [.part1: .pass, .part2: .pass, .part3_10: .skip],
            detailLog: "All applicable parts validated."
        )
        XCTAssertEqual(req.results[.part1], .pass)
        XCTAssertEqual(req.results[.part3_10], .skip)
        XCTAssertFalse(req.detailLog.isEmpty)
    }

    func testRequirementIdentifiable() {
        let req = ConformanceRequirement(requirementId: "T.1.1", description: "Test")
        XCTAssertFalse(req.id.uuidString.isEmpty)
    }

    func testRequirementEquatable() {
        let id = UUID()
        let a = ConformanceRequirement(id: id, requirementId: "T.1.1", description: "Test")
        let b = ConformanceRequirement(id: id, requirementId: "T.1.1", description: "Test")
        XCTAssertEqual(a, b)
    }
}

// MARK: - Conformance Report Tests

final class ConformanceReportTests: XCTestCase {

    func testReportPassRate() {
        let report = ConformanceReport(totalTests: 10, passedTests: 8, failedTests: 1, skippedTests: 1, duration: 1.5)
        XCTAssertEqual(report.passRate, 80.0, accuracy: 0.001)
    }

    func testReportPerfectPassRate() {
        let report = ConformanceReport(totalTests: 100, passedTests: 100, failedTests: 0, skippedTests: 0, duration: 2.0)
        XCTAssertEqual(report.passRate, 100.0, accuracy: 0.001)
    }

    func testReportEmptyPassRate() {
        let report = ConformanceReport(totalTests: 0, passedTests: 0, failedTests: 0, skippedTests: 0, duration: 0)
        XCTAssertEqual(report.passRate, 0.0, accuracy: 0.001)
    }

    func testReportSummaryBanner() {
        let report = ConformanceReport(totalTests: 304, passedTests: 304, failedTests: 0, skippedTests: 0, duration: 1.0)
        XCTAssertEqual(report.summaryBanner, "304/304 tests passed")
    }
}

// MARK: - Conformance Export Format Tests

final class ConformanceExportFormatTests: XCTestCase {

    func testAllFormatsExist() {
        XCTAssertEqual(ConformanceExportFormat.allCases.count, 3)
    }

    func testFormatRawValues() {
        XCTAssertEqual(ConformanceExportFormat.json.rawValue, "JSON")
        XCTAssertEqual(ConformanceExportFormat.html.rawValue, "HTML")
        XCTAssertEqual(ConformanceExportFormat.pdf.rawValue, "PDF")
    }
}

// MARK: - Conformance View Model Tests

final class ConformanceViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = ConformanceViewModel()
        XCTAssertTrue(vm.requirements.isEmpty)
        XCTAssertNil(vm.selectedPart)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertNil(vm.report)
        XCTAssertNil(vm.expandedRequirementId)
        XCTAssertEqual(vm.exportFormat, .json)
    }

    func testLoadDefaultRequirements() {
        let vm = ConformanceViewModel()
        vm.loadDefaultRequirements()
        XCTAssertFalse(vm.requirements.isEmpty)
        XCTAssertEqual(vm.requirements.count, 17)
        XCTAssertTrue(vm.statusMessage.contains("17"))
    }

    func testFilteredRequirementsNoFilter() {
        let vm = ConformanceViewModel()
        vm.loadDefaultRequirements()
        XCTAssertEqual(vm.filteredRequirements.count, vm.requirements.count)
    }

    func testFilteredRequirementsWithPartFilter() {
        let vm = ConformanceViewModel()
        vm.loadDefaultRequirements()
        // Before running tests, results are empty so filtering by part returns nothing
        vm.selectedPart = .part1
        XCTAssertEqual(vm.filteredRequirements.count, 0)
    }

    func testRunAllTests() async {
        let vm = ConformanceViewModel()
        vm.loadDefaultRequirements()
        let session = TestSession()
        await vm.runAllTests(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNotNil(vm.report)
        XCTAssertEqual(vm.report?.totalTests, 17)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    func testRunAllTestsAutoLoads() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        XCTAssertFalse(vm.requirements.isEmpty)
        XCTAssertNotNil(vm.report)
    }

    func testRunAllTestsRecordsResults() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testExportReportJSON() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        vm.exportFormat = .json
        let exported = vm.exportReport()
        XCTAssertTrue(exported.contains("totalTests"))
        XCTAssertTrue(exported.contains("passRate"))
    }

    func testExportReportHTML() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        vm.exportFormat = .html
        let exported = vm.exportReport()
        XCTAssertTrue(exported.contains("<html>"))
        XCTAssertTrue(exported.contains("Conformance Report"))
    }

    func testExportReportPDF() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        vm.exportFormat = .pdf
        let exported = vm.exportReport()
        XCTAssertTrue(exported.contains("PDF export"))
    }

    func testExportReportNoReport() {
        let vm = ConformanceViewModel()
        let exported = vm.exportReport()
        XCTAssertTrue(exported.isEmpty)
    }

    func testFilteredRequirementsAfterRun() async {
        let vm = ConformanceViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        vm.selectedPart = .part1
        // Part 1 requirements (T.1.x) have results for all parts
        XCTAssertFalse(vm.filteredRequirements.isEmpty)
    }
}

// MARK: - Interop Comparison Result Tests

final class InteropComparisonResultTests: XCTestCase {

    func testComparisonResultCreation() {
        let result = InteropComparisonResult(
            codestreamName: "test.j2k",
            maxPixelDifference: 0,
            meanPixelDifference: 0.0,
            withinTolerance: true,
            j2kSwiftTime: 0.035,
            openJPEGTime: 0.042
        )
        XCTAssertEqual(result.codestreamName, "test.j2k")
        XCTAssertEqual(result.maxPixelDifference, 0)
        XCTAssertTrue(result.withinTolerance)
    }

    func testSpeedupCalculation() {
        let result = InteropComparisonResult(
            codestreamName: "test.j2k",
            maxPixelDifference: 0,
            meanPixelDifference: 0.0,
            withinTolerance: true,
            j2kSwiftTime: 0.035,
            openJPEGTime: 0.042
        )
        XCTAssertEqual(result.speedup, 0.042 / 0.035, accuracy: 0.001)
    }

    func testSpeedupZeroDivision() {
        let result = InteropComparisonResult(
            codestreamName: "test.j2k",
            maxPixelDifference: 0,
            meanPixelDifference: 0.0,
            withinTolerance: true,
            j2kSwiftTime: 0.0,
            openJPEGTime: 0.042
        )
        XCTAssertEqual(result.speedup, 0.0)
    }

    func testSpeedupZeroOpenJPEGTime() {
        let result = InteropComparisonResult(
            codestreamName: "test.j2k",
            maxPixelDifference: 0,
            meanPixelDifference: 0.0,
            withinTolerance: true,
            j2kSwiftTime: 0.035,
            openJPEGTime: 0.0
        )
        XCTAssertEqual(result.speedup, 0.0, accuracy: 0.001)
    }
}

// MARK: - Codestream Diff Node Tests

final class CodestreamDiffNodeTests: XCTestCase {

    func testDiffNodeMatching() {
        let node = CodestreamDiffNode(name: "SOC", j2kSwiftValue: "0xFF4F", openJPEGValue: "0xFF4F")
        XCTAssertTrue(node.matches)
    }

    func testDiffNodeMismatch() {
        let node = CodestreamDiffNode(name: "SIZ", j2kSwiftValue: "512×512", openJPEGValue: "256×256")
        XCTAssertFalse(node.matches)
    }

    func testDiffNodeWithChildren() {
        let child = CodestreamDiffNode(name: "Rsiz", j2kSwiftValue: "0", openJPEGValue: "0")
        let parent = CodestreamDiffNode(name: "SIZ", j2kSwiftValue: "512", openJPEGValue: "512", children: [child])
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertTrue(parent.children[0].matches)
    }
}

// MARK: - Interop View Model Tests

final class InteropViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = InteropViewModel()
        XCTAssertNil(vm.inputFileURL)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertEqual(vm.toleranceThreshold, 1)
        XCTAssertNil(vm.comparisonResult)
        XCTAssertTrue(vm.allResults.isEmpty)
        XCTAssertTrue(vm.diffNodes.isEmpty)
        XCTAssertTrue(vm.isBidirectional)
    }

    func testLoadCodestream() {
        let vm = InteropViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.j2k")
        vm.loadCodestream(url: url)
        XCTAssertEqual(vm.inputFileURL, url)
        XCTAssertTrue(vm.statusMessage.contains("test.j2k"))
    }

    func testRunComparisonWithoutFile() async {
        let vm = InteropViewModel()
        let session = TestSession()
        await vm.runComparison(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertTrue(vm.statusMessage.contains("No codestream"))
    }

    func testRunComparison() async {
        let vm = InteropViewModel()
        vm.loadCodestream(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        let session = TestSession()
        await vm.runComparison(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNotNil(vm.comparisonResult)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
        XCTAssertTrue(vm.comparisonResult?.withinTolerance == true)
    }

    func testRunComparisonRecordsResults() async {
        let vm = InteropViewModel()
        vm.loadCodestream(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        let session = TestSession()
        await vm.runComparison(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testRunComparisonBuildsDiffTree() async {
        let vm = InteropViewModel()
        vm.loadCodestream(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        let session = TestSession()
        await vm.runComparison(session: session)
        XCTAssertFalse(vm.diffNodes.isEmpty)
    }

    func testAllResultsAccumulate() async {
        let vm = InteropViewModel()
        let session = TestSession()
        vm.loadCodestream(url: URL(fileURLWithPath: "/tmp/a.j2k"))
        await vm.runComparison(session: session)
        vm.loadCodestream(url: URL(fileURLWithPath: "/tmp/b.j2k"))
        await vm.runComparison(session: session)
        XCTAssertEqual(vm.allResults.count, 2)
    }
}

// MARK: - Validation Finding Tests

final class ValidationFindingTests: XCTestCase {

    func testFindingCreation() {
        let finding = ValidationFinding(severity: .error, offset: 0, message: "Missing SOC marker")
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.offset, 0)
        XCTAssertEqual(finding.message, "Missing SOC marker")
    }

    func testFindingSeverityValues() {
        XCTAssertEqual(ValidationSeverity.error.rawValue, "Error")
        XCTAssertEqual(ValidationSeverity.warning.rawValue, "Warning")
        XCTAssertEqual(ValidationSeverity.info.rawValue, "Info")
    }
}

// MARK: - Validation Mode Tests

final class ValidationModeTests: XCTestCase {

    func testAllModesExist() {
        XCTAssertEqual(ValidationMode.allCases.count, 3)
    }

    func testModeRawValues() {
        XCTAssertEqual(ValidationMode.codestream.rawValue, "Codestream")
        XCTAssertEqual(ValidationMode.fileFormat.rawValue, "File Format")
        XCTAssertEqual(ValidationMode.markerInspector.rawValue, "Marker Inspector")
    }
}

// MARK: - File Format Box Info Tests

final class FileFormatBoxInfoTests: XCTestCase {

    func testBoxInfoCreation() {
        let box = FileFormatBoxInfo(boxType: "jp2h", description: "JP2 Header", offset: 32, length: 45)
        XCTAssertEqual(box.boxType, "jp2h")
        XCTAssertEqual(box.description, "JP2 Header")
        XCTAssertEqual(box.offset, 32)
        XCTAssertEqual(box.length, 45)
        XCTAssertTrue(box.isValid)
        XCTAssertTrue(box.children.isEmpty)
    }

    func testBoxInfoWithChildren() {
        let child = FileFormatBoxInfo(boxType: "ihdr", description: "Image Header", offset: 40, length: 22)
        let parent = FileFormatBoxInfo(boxType: "jp2h", description: "JP2 Header", offset: 32, length: 45, children: [child])
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.children[0].boxType, "ihdr")
    }

    func testBoxInfoInvalid() {
        let box = FileFormatBoxInfo(boxType: "bad!", description: "Corrupt box", offset: 0, length: 0, isValid: false)
        XCTAssertFalse(box.isValid)
    }
}

// MARK: - Validation View Model Tests

final class ValidationViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = ValidationViewModel()
        XCTAssertNil(vm.inputFileURL)
        XCTAssertEqual(vm.selectedMode, .codestream)
        XCTAssertFalse(vm.isValidating)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertNil(vm.validationPassed)
        XCTAssertTrue(vm.findings.isEmpty)
        XCTAssertTrue(vm.boxTree.isEmpty)
        XCTAssertTrue(vm.markerSegments.isEmpty)
        XCTAssertTrue(vm.selectedMarkerHex.isEmpty)
    }

    func testLoadFile() {
        let vm = ValidationViewModel()
        let url = URL(fileURLWithPath: "/tmp/test.j2k")
        vm.loadFile(url: url)
        XCTAssertEqual(vm.inputFileURL, url)
        XCTAssertTrue(vm.statusMessage.contains("test.j2k"))
    }

    func testLoadFileClearsPrevious() {
        let vm = ValidationViewModel()
        vm.findings = [ValidationFinding(severity: .info, offset: 0, message: "Old")]
        vm.validationPassed = true
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/new.j2k"))
        XCTAssertTrue(vm.findings.isEmpty)
        XCTAssertNil(vm.validationPassed)
    }

    func testValidateWithoutFile() async {
        let vm = ValidationViewModel()
        let session = TestSession()
        await vm.validate(session: session)
        XCTAssertFalse(vm.isValidating)
        XCTAssertTrue(vm.statusMessage.contains("No file"))
    }

    func testValidateCodestream() async {
        let vm = ValidationViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        vm.selectedMode = .codestream
        let session = TestSession()
        await vm.validate(session: session)
        XCTAssertFalse(vm.isValidating)
        XCTAssertTrue(vm.validationPassed == true)
        XCTAssertFalse(vm.findings.isEmpty)
        XCTAssertTrue(vm.statusMessage.contains("valid"))
    }

    func testValidateFileFormat() async {
        let vm = ValidationViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.jp2"))
        vm.selectedMode = .fileFormat
        let session = TestSession()
        await vm.validate(session: session)
        XCTAssertFalse(vm.isValidating)
        XCTAssertTrue(vm.validationPassed == true)
        XCTAssertFalse(vm.boxTree.isEmpty)
        XCTAssertTrue(vm.statusMessage.contains("valid"))
    }

    func testValidateMarkerInspector() async {
        let vm = ValidationViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        vm.selectedMode = .markerInspector
        let session = TestSession()
        await vm.validate(session: session)
        XCTAssertFalse(vm.isValidating)
        XCTAssertFalse(vm.markerSegments.isEmpty)
        XCTAssertFalse(vm.selectedMarkerHex.isEmpty)
    }

    func testValidateRecordsResults() async {
        let vm = ValidationViewModel()
        vm.loadFile(url: URL(fileURLWithPath: "/tmp/test.j2k"))
        let session = TestSession()
        await vm.validate(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }
}

// MARK: - Benchmark Image Size Choice Tests

final class BenchmarkImageSizeChoiceTests: XCTestCase {

    func testAllSizesExist() {
        let sizes = BenchmarkImageSizeChoice.allCases
        XCTAssertEqual(sizes.count, 6)
    }

    func testSizeRawValues() {
        XCTAssertEqual(BenchmarkImageSizeChoice.small128.rawValue, "128×128")
        XCTAssertEqual(BenchmarkImageSizeChoice.medium256.rawValue, "256×256")
        XCTAssertEqual(BenchmarkImageSizeChoice.medium512.rawValue, "512×512")
        XCTAssertEqual(BenchmarkImageSizeChoice.large1024.rawValue, "1024×1024")
        XCTAssertEqual(BenchmarkImageSizeChoice.large2048.rawValue, "2048×2048")
        XCTAssertEqual(BenchmarkImageSizeChoice.huge4096.rawValue, "4096×4096")
    }

    func testPixelCount() {
        XCTAssertEqual(BenchmarkImageSizeChoice.small128.pixelCount, 16384)
        XCTAssertEqual(BenchmarkImageSizeChoice.medium256.pixelCount, 65536)
        XCTAssertEqual(BenchmarkImageSizeChoice.medium512.pixelCount, 262144)
        XCTAssertEqual(BenchmarkImageSizeChoice.large1024.pixelCount, 1048576)
        XCTAssertEqual(BenchmarkImageSizeChoice.large2048.pixelCount, 4194304)
        XCTAssertEqual(BenchmarkImageSizeChoice.huge4096.pixelCount, 16777216)
    }
}

// MARK: - Benchmark Coding Mode Choice Tests

final class BenchmarkCodingModeChoiceTests: XCTestCase {

    func testAllModesExist() {
        let modes = BenchmarkCodingModeChoice.allCases
        XCTAssertEqual(modes.count, 6)
    }

    func testModeRawValues() {
        XCTAssertEqual(BenchmarkCodingModeChoice.lossless.rawValue, "Lossless")
        XCTAssertEqual(BenchmarkCodingModeChoice.lossy.rawValue, "Lossy")
        XCTAssertEqual(BenchmarkCodingModeChoice.htj2k.rawValue, "HTJ2K")
        XCTAssertEqual(BenchmarkCodingModeChoice.htj2kLossless.rawValue, "HTJ2K Lossless")
        XCTAssertEqual(BenchmarkCodingModeChoice.tiledLossless.rawValue, "Tiled Lossless")
        XCTAssertEqual(BenchmarkCodingModeChoice.tiledLossy.rawValue, "Tiled Lossy")
    }
}

// MARK: - Benchmark Run Result Tests

final class BenchmarkRunResultTests: XCTestCase {

    func testResultCreation() {
        let result = BenchmarkRunResult(
            imageSize: .medium512,
            codingMode: .lossless,
            throughputMPPerSecond: 5.0,
            latencyMs: 200.0,
            peakMemoryBytes: 1024,
            allocationCount: 10,
            iterationCount: 10
        )
        XCTAssertEqual(result.imageSize, .medium512)
        XCTAssertEqual(result.codingMode, .lossless)
        XCTAssertEqual(result.throughputMPPerSecond, 5.0, accuracy: 0.001)
        XCTAssertEqual(result.latencyMs, 200.0, accuracy: 0.001)
        XCTAssertEqual(result.peakMemoryBytes, 1024)
        XCTAssertEqual(result.allocationCount, 10)
        XCTAssertEqual(result.iterationCount, 10)
    }

    func testResultEquality() {
        let id = UUID()
        let a = BenchmarkRunResult(
            id: id,
            imageSize: .medium512,
            codingMode: .lossless,
            throughputMPPerSecond: 5.0,
            latencyMs: 200.0,
            peakMemoryBytes: 1024,
            allocationCount: 10,
            iterationCount: 10
        )
        let b = BenchmarkRunResult(
            id: id,
            imageSize: .medium512,
            codingMode: .lossless,
            throughputMPPerSecond: 5.0,
            latencyMs: 200.0,
            peakMemoryBytes: 1024,
            allocationCount: 10,
            iterationCount: 10
        )
        XCTAssertEqual(a.id, b.id)
    }
}

// MARK: - Regression Status Tests

final class RegressionStatusTests: XCTestCase {

    func testRegressionRawValues() {
        XCTAssertEqual(RegressionStatus.green.rawValue, "No Regression")
        XCTAssertEqual(RegressionStatus.amber.rawValue, "Possible Regression")
        XCTAssertEqual(RegressionStatus.red.rawValue, "Regression Detected")
    }
}

// MARK: - Performance View Model Tests

final class PerformanceViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = PerformanceViewModel()
        XCTAssertTrue(vm.selectedSizes.contains(.medium512))
        XCTAssertTrue(vm.selectedModes.contains(.lossless))
        XCTAssertEqual(vm.iterationCount, 10)
        XCTAssertEqual(vm.warmUpRounds, 2)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertTrue(vm.currentResults.isEmpty)
        XCTAssertEqual(vm.regressionStatus, .green)
        XCTAssertEqual(vm.peakMemoryBytes, 0)
        XCTAssertEqual(vm.currentMemoryBytes, 0)
        XCTAssertEqual(vm.allocationCount, 0)
        XCTAssertEqual(vm.exportFormat, "CSV")
    }

    func testClearResults() {
        let vm = PerformanceViewModel()
        vm.peakMemoryBytes = 999
        vm.allocationCount = 42
        vm.progress = 0.5
        vm.statusMessage = "Done"
        vm.clearResults()
        XCTAssertTrue(vm.currentResults.isEmpty)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertEqual(vm.peakMemoryBytes, 0)
        XCTAssertEqual(vm.allocationCount, 0)
    }

    func testRunBenchmark() async {
        let vm = PerformanceViewModel()
        vm.selectedSizes = [.small128]
        vm.selectedModes = [.lossless]
        let session = TestSession()
        await vm.runBenchmark(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.currentResults.isEmpty)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(vm.peakMemoryBytes, 0)
    }

    func testRunBenchmarkRecordsSession() async {
        let vm = PerformanceViewModel()
        vm.selectedSizes = [.small128]
        vm.selectedModes = [.lossless]
        let session = TestSession()
        await vm.runBenchmark(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testExportResultsEmpty() {
        let vm = PerformanceViewModel()
        let csv = vm.exportResults()
        XCTAssertTrue(csv.contains("Size"))
    }

    func testExportResultsWithData() async {
        let vm = PerformanceViewModel()
        vm.selectedSizes = [.small128]
        vm.selectedModes = [.lossless]
        let session = TestSession()
        await vm.runBenchmark(session: session)
        let csv = vm.exportResults()
        XCTAssertFalse(csv.isEmpty)
        XCTAssertTrue(csv.contains("Size"))
    }

    func testMultipleSizesAndModes() async {
        let vm = PerformanceViewModel()
        vm.selectedSizes = [.small128, .medium256]
        vm.selectedModes = [.lossless, .lossy]
        let session = TestSession()
        await vm.runBenchmark(session: session)
        XCTAssertEqual(vm.currentResults.count, 4)
    }
}

// MARK: - GPU Operation Tests

final class GPUOperationTests: XCTestCase {

    func testAllOperationsExist() {
        let operations = GPUOperation.allCases
        XCTAssertEqual(operations.count, 5)
    }

    func testOperationRawValues() {
        XCTAssertEqual(GPUOperation.dwt.rawValue, "DWT")
        XCTAssertEqual(GPUOperation.colourTransform.rawValue, "Colour Transform")
        XCTAssertEqual(GPUOperation.quantisation.rawValue, "Quantisation")
        XCTAssertEqual(GPUOperation.entropyCoding.rawValue, "Entropy Coding")
        XCTAssertEqual(GPUOperation.rateControl.rawValue, "Rate Control")
    }
}

// MARK: - GPU Test Result Tests

final class GPUTestResultTests: XCTestCase {

    func testResultCreation() {
        let result = GPUTestResult(
            operation: .dwt,
            gpuTimeMs: 0.5,
            cpuTimeMs: 2.0,
            outputsMatch: true,
            gpuMemoryBytes: 1024
        )
        XCTAssertEqual(result.operation, .dwt)
        XCTAssertEqual(result.gpuTimeMs, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.cpuTimeMs, 2.0, accuracy: 0.001)
        XCTAssertTrue(result.outputsMatch)
        XCTAssertEqual(result.gpuMemoryBytes, 1024)
    }

    func testSpeedupFactor() {
        let result = GPUTestResult(
            operation: .dwt,
            gpuTimeMs: 0.5,
            cpuTimeMs: 2.0,
            outputsMatch: true,
            gpuMemoryBytes: 1024
        )
        XCTAssertEqual(result.speedupFactor, 4.0, accuracy: 0.001)
    }

    func testSpeedupFactorZeroGPU() {
        let result = GPUTestResult(
            operation: .dwt,
            gpuTimeMs: 0,
            cpuTimeMs: 2.0,
            outputsMatch: true,
            gpuMemoryBytes: 1024
        )
        XCTAssertEqual(result.speedupFactor, 0)
    }
}

// MARK: - Shader Compilation Info Tests

final class ShaderCompilationInfoTests: XCTestCase {

    func testShaderCreation() {
        let shader = ShaderCompilationInfo(
            shaderName: "dwt_forward",
            compileTimeMs: 1.5,
            status: "Compiled",
            isCompiled: true
        )
        XCTAssertEqual(shader.shaderName, "dwt_forward")
        XCTAssertEqual(shader.compileTimeMs, 1.5, accuracy: 0.001)
        XCTAssertEqual(shader.status, "Compiled")
        XCTAssertTrue(shader.isCompiled)
    }

    func testShaderNotCompiled() {
        let shader = ShaderCompilationInfo(
            shaderName: "test_shader",
            compileTimeMs: 0,
            status: "Failed",
            isCompiled: false
        )
        XCTAssertFalse(shader.isCompiled)
    }
}

// MARK: - GPU Test View Model Tests

final class GPUTestViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = GPUTestViewModel()
        XCTAssertEqual(vm.selectedOperation, .dwt)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertTrue(vm.shaders.isEmpty)
        XCTAssertEqual(vm.bufferPoolUtilisation, 0)
        XCTAssertEqual(vm.peakGPUMemoryBytes, 0)
        XCTAssertFalse(vm.isMetalAvailable)
    }

    func testCheckMetalAvailability() {
        let vm = GPUTestViewModel()
        vm.checkMetalAvailability()
        XCTAssertNotEqual(vm.statusMessage, "Ready")
    }

    func testRunGPUTest() async {
        let vm = GPUTestViewModel()
        let session = TestSession()
        await vm.runGPUTest(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.results.isEmpty)
        XCTAssertFalse(vm.shaders.isEmpty)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    func testRunGPUTestRecordsSession() async {
        let vm = GPUTestViewModel()
        let session = TestSession()
        await vm.runGPUTest(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testRunSingleOperation() async {
        let vm = GPUTestViewModel()
        let session = TestSession()
        await vm.runSingleOperation(session: session)
        XCTAssertEqual(vm.results.count, 1)
    }

    func testBufferPoolUtilisation() async {
        let vm = GPUTestViewModel()
        let session = TestSession()
        await vm.runGPUTest(session: session)
        XCTAssertGreaterThan(vm.bufferPoolUtilisation, 0)
    }

    func testPeakGPUMemory() async {
        let vm = GPUTestViewModel()
        let session = TestSession()
        await vm.runGPUTest(session: session)
        XCTAssertGreaterThan(vm.peakGPUMemoryBytes, 0)
    }
}

// MARK: - SIMD Operation Type Tests

final class SIMDOperationTypeTests: XCTestCase {

    func testAllOperationsExist() {
        let operations = SIMDOperationType.allCases
        XCTAssertEqual(operations.count, 7)
    }

    func testOperationRawValues() {
        XCTAssertEqual(SIMDOperationType.waveletLifting53.rawValue, "Wavelet Lifting 5/3")
        XCTAssertEqual(SIMDOperationType.waveletLifting97.rawValue, "Wavelet Lifting 9/7")
        XCTAssertEqual(SIMDOperationType.ictTransform.rawValue, "ICT Colour Transform")
        XCTAssertEqual(SIMDOperationType.rctTransform.rawValue, "RCT Colour Transform")
        XCTAssertEqual(SIMDOperationType.quantisation.rawValue, "Quantisation")
        XCTAssertEqual(SIMDOperationType.dequantisation.rawValue, "Dequantisation")
        XCTAssertEqual(SIMDOperationType.entropy.rawValue, "Entropy Coding")
    }
}

// MARK: - SIMD Test Result Tests

final class SIMDTestResultTests: XCTestCase {

    func testResultCreation() {
        let result = SIMDTestResult(
            operation: .waveletLifting53,
            simdTimeMs: 0.3,
            scalarTimeMs: 1.2,
            outputsMatch: true,
            platform: "ARM Neon"
        )
        XCTAssertEqual(result.operation, .waveletLifting53)
        XCTAssertEqual(result.simdTimeMs, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.scalarTimeMs, 1.2, accuracy: 0.001)
        XCTAssertTrue(result.outputsMatch)
        XCTAssertEqual(result.platform, "ARM Neon")
    }

    func testSpeedup() {
        let result = SIMDTestResult(
            operation: .waveletLifting53,
            simdTimeMs: 0.3,
            scalarTimeMs: 1.2,
            outputsMatch: true,
            platform: "ARM Neon"
        )
        XCTAssertEqual(result.speedup, 4.0, accuracy: 0.001)
    }

    func testSpeedupZeroSIMD() {
        let result = SIMDTestResult(
            operation: .waveletLifting53,
            simdTimeMs: 0,
            scalarTimeMs: 1.2,
            outputsMatch: true,
            platform: "ARM Neon"
        )
        XCTAssertEqual(result.speedup, 0)
    }
}

// MARK: - SIMD Test View Model Tests

final class SIMDTestViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = SIMDTestViewModel()
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(vm.utilisationPercentage, 0)
        XCTAssertEqual(vm.targetUtilisation, 85.0, accuracy: 0.001)
    }

    func testDetectPlatform() {
        let vm = SIMDTestViewModel()
        vm.detectPlatform()
        XCTAssertTrue(vm.isARM || vm.isX86 || vm.statusMessage != "Ready")
    }

    func testRunAllTests() async {
        let vm = SIMDTestViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.results.isEmpty)
        XCTAssertEqual(vm.results.count, 7)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(vm.utilisationPercentage, 0)
    }

    func testRunAllTestsRecordsSession() async {
        let vm = SIMDTestViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testClearResults() {
        let vm = SIMDTestViewModel()
        vm.progress = 0.5
        vm.statusMessage = "Done"
        vm.clearResults()
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertEqual(vm.utilisationPercentage, 0)
    }

    func testUtilisationCalculation() async {
        let vm = SIMDTestViewModel()
        let session = TestSession()
        await vm.runAllTests(session: session)
        XCTAssertGreaterThanOrEqual(vm.utilisationPercentage, 0)
        XCTAssertLessThanOrEqual(vm.utilisationPercentage, 100)
    }
}

// MARK: - JPIP Request Tests

final class JPIPLogEntryTests: XCTestCase {

    func testRequestCreation() {
        let request = JPIPLogEntry(
            path: "/image.jp2?layers=3",
            statusCode: 200,
            bytesReceived: 4096,
            latencyMs: 12.5
        )
        XCTAssertEqual(request.path, "/image.jp2?layers=3")
        XCTAssertEqual(request.statusCode, 200)
        XCTAssertEqual(request.bytesReceived, 4096)
        XCTAssertEqual(request.latencyMs, 12.5, accuracy: 0.001)
    }

    func testRequestHasUniqueID() {
        let r1 = JPIPLogEntry(path: "/a", statusCode: 200, bytesReceived: 100, latencyMs: 5)
        let r2 = JPIPLogEntry(path: "/b", statusCode: 200, bytesReceived: 100, latencyMs: 5)
        XCTAssertNotEqual(r1.id, r2.id)
    }
}

// MARK: - JPIP Network Metrics Tests

final class JPIPNetworkMetricsTests: XCTestCase {

    func testDefaultInit() {
        let metrics = JPIPNetworkMetrics()
        XCTAssertEqual(metrics.totalBytesReceived, 0)
        XCTAssertEqual(metrics.averageLatencyMs, 0)
        XCTAssertEqual(metrics.requestCount, 0)
        XCTAssertEqual(metrics.sessionDurationSeconds, 0)
    }

    func testCustomInit() {
        let metrics = JPIPNetworkMetrics(
            totalBytesReceived: 1024,
            averageLatencyMs: 8.0,
            requestCount: 4,
            sessionDurationSeconds: 2.5
        )
        XCTAssertEqual(metrics.totalBytesReceived, 1024)
        XCTAssertEqual(metrics.averageLatencyMs, 8.0, accuracy: 0.001)
        XCTAssertEqual(metrics.requestCount, 4)
        XCTAssertEqual(metrics.sessionDurationSeconds, 2.5, accuracy: 0.001)
    }
}

// MARK: - JPIP View Model Tests

final class JPIPViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = JPIPViewModel()
        XCTAssertEqual(vm.sessionStatus, .disconnected)
        XCTAssertFalse(vm.isStreaming)
        XCTAssertTrue(vm.requestLog.isEmpty)
        XCTAssertEqual(vm.metrics.requestCount, 0)
        XCTAssertEqual(vm.windowX, 0)
        XCTAssertEqual(vm.windowY, 0)
        XCTAssertEqual(vm.windowWidth, 1)
        XCTAssertEqual(vm.windowHeight, 1)
    }

    func testConnect() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        XCTAssertEqual(vm.sessionStatus, .connected)
        XCTAssertFalse(vm.isStreaming)
    }

    func testConnectRecordsTestResult() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testDisconnect() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        vm.disconnect()
        XCTAssertEqual(vm.sessionStatus, .disconnected)
        XCTAssertFalse(vm.isStreaming)
    }

    func testProgressiveLoad() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        await vm.requestProgressiveLoad(session: session)
        XCTAssertFalse(vm.isStreaming)
        XCTAssertEqual(vm.sessionStatus, .connected)
        XCTAssertFalse(vm.requestLog.isEmpty)
        XCTAssertGreaterThan(vm.metrics.totalBytesReceived, 0)
        XCTAssertGreaterThan(vm.metrics.requestCount, 0)
    }

    func testProgressiveLoadRequestCount() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        await vm.requestProgressiveLoad(session: session)
        XCTAssertEqual(vm.requestLog.count, vm.maxQualityLayer)
    }

    func testClearLog() async {
        let vm = JPIPViewModel()
        let session = TestSession()
        await vm.connect(session: session)
        await vm.requestProgressiveLoad(session: session)
        XCTAssertFalse(vm.requestLog.isEmpty)
        vm.clearLog()
        XCTAssertTrue(vm.requestLog.isEmpty)
        XCTAssertEqual(vm.metrics.requestCount, 0)
    }
}

// MARK: - Volume Slice Tests

final class VolumeSliceTests: XCTestCase {

    func testSliceCreation() {
        let slice = VolumeSlice(
            plane: .axial,
            index: 5,
            width: 256,
            height: 256,
            psnr: 48.0,
            ssim: 0.997,
            decodeTimeMs: 1.1
        )
        XCTAssertEqual(slice.plane, .axial)
        XCTAssertEqual(slice.index, 5)
        XCTAssertEqual(slice.width, 256)
        XCTAssertEqual(slice.height, 256)
        XCTAssertEqual(slice.psnr, 48.0, accuracy: 0.001)
        XCTAssertEqual(slice.ssim, 0.997, accuracy: 0.0001)
        XCTAssertEqual(slice.decodeTimeMs, 1.1, accuracy: 0.001)
    }

    func testAllPlanesAvailable() {
        let planes = VolumetricPlane.allCases
        XCTAssertEqual(planes.count, 3)
        XCTAssertTrue(planes.contains(.axial))
        XCTAssertTrue(planes.contains(.coronal))
        XCTAssertTrue(planes.contains(.sagittal))
    }
}

// MARK: - Volumetric Test View Model Tests

final class VolumetricTestViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = VolumetricTestViewModel()
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertTrue(vm.sliceMetrics.isEmpty)
        XCTAssertEqual(vm.selectedPlane, .axial)
        XCTAssertEqual(vm.currentSliceIndex, 0)
        XCTAssertFalse(vm.showDifferenceImage)
    }

    func testRunVolumetricTest() async {
        let vm = VolumetricTestViewModel()
        vm.totalSlices = 4  // Use a small count for speed
        let session = TestSession()
        await vm.runVolumetricTest(session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.sliceMetrics.count, 4)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    func testRunVolumetricTestRecordsResult() async {
        let vm = VolumetricTestViewModel()
        vm.totalSlices = 2
        let session = TestSession()
        await vm.runVolumetricTest(session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testSlicePSNRAboveThreshold() async {
        let vm = VolumetricTestViewModel()
        vm.totalSlices = 4
        let session = TestSession()
        await vm.runVolumetricTest(session: session)
        for slice in vm.sliceMetrics {
            XCTAssertGreaterThan(slice.psnr, 30.0)
        }
    }

    func testClearResults() async {
        let vm = VolumetricTestViewModel()
        vm.totalSlices = 2
        let session = TestSession()
        await vm.runVolumetricTest(session: session)
        XCTAssertFalse(vm.sliceMetrics.isEmpty)
        vm.clearResults()
        XCTAssertTrue(vm.sliceMetrics.isEmpty)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.currentSliceIndex, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
    }
}

// MARK: - MJ2 Frame Tests

final class MJ2FrameTests: XCTestCase {

    func testFrameCreation() {
        let frame = MJ2Frame(
            frameNumber: 1,
            timestampSeconds: 0.0,
            width: 1920,
            height: 1080,
            compressedSizeBytes: 80_000,
            psnr: 42.0,
            ssim: 0.993,
            decodeTimeMs: 2.5
        )
        XCTAssertEqual(frame.frameNumber, 1)
        XCTAssertEqual(frame.timestampSeconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1920)
        XCTAssertEqual(frame.height, 1080)
        XCTAssertEqual(frame.compressedSizeBytes, 80_000)
        XCTAssertEqual(frame.psnr, 42.0, accuracy: 0.001)
        XCTAssertEqual(frame.ssim, 0.993, accuracy: 0.0001)
    }

    func testFrameHasUniqueID() {
        let f1 = MJ2Frame(frameNumber: 1, timestampSeconds: 0, width: 1920, height: 1080,
                          compressedSizeBytes: 80_000, psnr: 42, ssim: 0.99, decodeTimeMs: 2.5)
        let f2 = MJ2Frame(frameNumber: 2, timestampSeconds: 1, width: 1920, height: 1080,
                          compressedSizeBytes: 80_000, psnr: 42, ssim: 0.99, decodeTimeMs: 2.5)
        XCTAssertNotEqual(f1.id, f2.id)
    }
}

// MARK: - MJ2 Test View Model Tests

final class MJ2TestViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = MJ2TestViewModel()
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.statusMessage, "Ready")
        XCTAssertTrue(vm.frames.isEmpty)
        XCTAssertEqual(vm.playbackState, .stopped)
        XCTAssertEqual(vm.currentFrameIndex, 0)
        XCTAssertTrue(vm.useUniformEncoding)
        XCTAssertEqual(vm.frameRate, 24.0, accuracy: 0.001)
    }

    func testLoadSequence() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.frames.count, 5)
        XCTAssertEqual(vm.playbackState, .paused)
        XCTAssertEqual(vm.progress, 1.0, accuracy: 0.001)
    }

    func testLoadSequenceRecordsResult() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 3, session: session)
        let results = await session.results
        XCTAssertFalse(results.isEmpty)
    }

    func testCurrentFrame() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        let frame = vm.currentFrame
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.frameNumber, 1)
    }

    func testTotalDuration() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        XCTAssertGreaterThan(vm.totalDurationSeconds, 0)
    }

    func testStepForward() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        vm.stepForward()
        XCTAssertEqual(vm.currentFrameIndex, 1)
    }

    func testStepBackward() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        vm.currentFrameIndex = 3
        vm.stepBackward()
        XCTAssertEqual(vm.currentFrameIndex, 2)
    }

    func testStepBackwardAtStart() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        vm.currentFrameIndex = 0
        vm.stepBackward()
        XCTAssertEqual(vm.currentFrameIndex, 0)
    }

    func testStepForwardAtEnd() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        vm.currentFrameIndex = 4
        vm.stepForward()
        XCTAssertEqual(vm.currentFrameIndex, 4)
    }

    func testTogglePlayback() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 3, session: session)
        XCTAssertEqual(vm.playbackState, .paused)
        vm.togglePlayback()
        XCTAssertEqual(vm.playbackState, .playing)
        vm.togglePlayback()
        XCTAssertEqual(vm.playbackState, .paused)
    }

    func testStop() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 3, session: session)
        vm.currentFrameIndex = 2
        vm.togglePlayback()
        vm.stop()
        XCTAssertEqual(vm.playbackState, .stopped)
        XCTAssertEqual(vm.currentFrameIndex, 0)
    }

    func testClearFrames() async {
        let vm = MJ2TestViewModel()
        let session = TestSession()
        await vm.loadSequence(frameCount: 5, session: session)
        XCTAssertFalse(vm.frames.isEmpty)
        vm.clearFrames()
        XCTAssertTrue(vm.frames.isEmpty)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.currentFrameIndex, 0)
        XCTAssertEqual(vm.playbackState, .stopped)
        XCTAssertEqual(vm.statusMessage, "Ready")
    }

    func testCurrentFrameNilWhenEmpty() {
        let vm = MJ2TestViewModel()
        XCTAssertNil(vm.currentFrame)
    }
}
#endif
