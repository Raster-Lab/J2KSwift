//
// J2KApplePlatformTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for Apple platform-specific features.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
final class J2KApplePlatformTests: XCTestCase {
    // MARK: - GCD Dispatcher Tests

    func testGCDDispatcherParallelProcessing() async throws {
        let dispatcher = J2KGCDDispatcher()

        let items = Array(0..<100)
        let results = try await dispatcher.parallelProcess(items: items) { item in
            item * 2
        }

        XCTAssertEqual(results.count, 100)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result, index * 2)
        }
    }

    func testGCDDispatcherWithConfiguration() async throws {
        let config = J2KGCDDispatcher.Configuration(
            qos: .userInitiated,
            maxConcurrency: 4,
            adaptiveConcurrency: false
        )
        let dispatcher = J2KGCDDispatcher(configuration: config)

        let items = Array(0..<50)
        let results = try await dispatcher.parallelProcess(items: items) { item in
            item + 1
        }

        XCTAssertEqual(results.count, 50)
    }

    func testGCDDispatcherAdaptiveConcurrency() async throws {
        let config = J2KGCDDispatcher.Configuration(
            qos: .utility,
            adaptiveConcurrency: true
        )
        let dispatcher = J2KGCDDispatcher(configuration: config)

        let items = Array(0..<20)
        let results = try await dispatcher.parallelProcess(items: items) { item in
            // Simulate work
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return item * 3
        }

        XCTAssertEqual(results.count, 20)
    }

    func testGCDDispatcherErrorHandling() async throws {
        let dispatcher = J2KGCDDispatcher()

        let items = Array(0..<10)

        do {
            _ = try await dispatcher.parallelProcess(items: items) { item in
                if item == 5 {
                    throw J2KError.internalError("Test error")
                }
                return item
            }
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }

    // MARK: - Quality of Service Tests

    func testQualityOfServiceMapping() {
        let userInteractive = J2KQualityOfService.userInteractive
        XCTAssertEqual(userInteractive.dispatchQoS, .userInteractive)
        XCTAssertEqual(userInteractive.taskPriority, .high)

        let background = J2KQualityOfService.background
        XCTAssertEqual(background.dispatchQoS, .background)
        XCTAssertEqual(background.taskPriority, .low)

        let utility = J2KQualityOfService.utility
        XCTAssertEqual(utility.dispatchQoS, .utility)
        XCTAssertEqual(utility.taskPriority, .medium)
    }

    // MARK: - Power Efficiency Manager Tests

    func testPowerEfficiencyManagerInitialization() async throws {
        let manager = J2KPowerEfficiencyManager()

        await manager.startMonitoring()

        let mode = await manager.recommendedMode()
        XCTAssertTrue([
            J2KPowerEfficiencyManager.PowerMode.performance,
            .balanced,
            .powerSaver
        ].contains(mode))

        await manager.stopMonitoring()
    }

    func testPowerEfficiencyManagerState() async throws {
        let manager = J2KPowerEfficiencyManager()

        await manager.startMonitoring()

        let state = await manager.powerState()

        #if os(iOS) || os(tvOS) || os(macOS)
        // On Apple platforms, state should be available
        XCTAssertNotNil(state)

        if let state = state {
            // Verify state properties are reasonable
            XCTAssertNotNil(state.thermalState)
        }
        #else
        // On other platforms, state may be nil
        _ = state
        #endif

        await manager.stopMonitoring()
    }

    func testPowerEfficiencyManagerRecommendations() async throws {
        let manager = J2KPowerEfficiencyManager()

        await manager.startMonitoring()

        let mode = await manager.recommendedMode()

        // Should return a valid mode
        XCTAssertTrue([
            J2KPowerEfficiencyManager.PowerMode.performance,
            .balanced,
            .powerSaver
        ].contains(mode))

        await manager.stopMonitoring()
    }

    // MARK: - Thermal State Tests

    func testThermalStateConversion() {
        let processInfo = ProcessInfo.processInfo
        let thermalState = J2KThermalState.from(processInfo: processInfo)

        // Should be a valid thermal state
        XCTAssertTrue([
            J2KThermalState.nominal,
            .fair,
            .serious,
            .critical
        ].contains(thermalState))
    }

    func testThermalStateMonitorInitialization() async throws {
        let monitor = J2KThermalStateMonitor()

        await monitor.startMonitoring()

        let state = await monitor.currentState()
        XCTAssertTrue([
            J2KThermalState.nominal,
            .fair,
            .serious,
            .critical
        ].contains(state))

        await monitor.stopMonitoring()
    }

    func testThermalStateMonitorThrottling() async throws {
        let monitor = J2KThermalStateMonitor()

        await monitor.startMonitoring()

        let shouldThrottle = await monitor.shouldThrottleProcessing()
        // Should be a boolean
        XCTAssertNotNil(shouldThrottle)

        await monitor.stopMonitoring()
    }

    func testThermalStateMonitorRecommendation() async throws {
        let monitor = J2KThermalStateMonitor()

        await monitor.startMonitoring()

        let recommendation = await monitor.throttlingRecommendation()

        // Verify recommendation structure
        XCTAssertGreaterThanOrEqual(recommendation.reductionFactor, 0.0)
        XCTAssertLessThanOrEqual(recommendation.reductionFactor, 1.0)

        // Reduction factor should match thermal state
        switch recommendation.thermalState {
        case .nominal:
            XCTAssertEqual(recommendation.reductionFactor, 1.0)
        case .fair:
            XCTAssertEqual(recommendation.reductionFactor, 0.8)
        case .serious:
            XCTAssertEqual(recommendation.reductionFactor, 0.5)
        case .critical:
            XCTAssertEqual(recommendation.reductionFactor, 0.25)
        }

        await monitor.stopMonitoring()
    }

    // MARK: - Async File I/O Tests

    func testAsyncFileIORead() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_read_\(UUID().uuidString).dat")

        // Create test file
        let testData = Data((0..<1024).map { UInt8($0 % 256) })
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileIO = J2KAsyncFileIO()
        let readData = try await fileIO.read(from: tempURL, offset: 0, length: 1024)

        XCTAssertEqual(readData, testData)
    }

    func testAsyncFileIOPartialRead() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_partial_\(UUID().uuidString).dat")

        let testData = Data((0..<2048).map { UInt8($0 % 256) })
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileIO = J2KAsyncFileIO()
        let readData = try await fileIO.read(from: tempURL, offset: 512, length: 512)

        XCTAssertEqual(readData.count, 512)
        XCTAssertEqual(readData, testData.subdata(in: 512..<1024))
    }

    func testAsyncFileIOWrite() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_write_\(UUID().uuidString).dat")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let testData = Data((0..<2048).map { UInt8($0 % 256) })

        let fileIO = J2KAsyncFileIO()
        try await fileIO.write(testData, to: tempURL)

        // Verify by reading back
        let readData = try Data(contentsOf: tempURL)
        XCTAssertEqual(readData, testData)
    }

    func testAsyncFileIOWithQoS() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_qos_\(UUID().uuidString).dat")

        let testData = Data(repeating: 42, count: 4096)
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let options = J2KAsyncFileIO.ReadOptions(
            qos: .utility,
            bufferSize: 1024
        )

        let fileIO = J2KAsyncFileIO()
        let readData = try await fileIO.read(
            from: tempURL,
            offset: 0,
            length: 4096,
            options: options
        )

        XCTAssertEqual(readData.count, 4096)
    }

    func testAsyncFileIOPerformance() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_perf_\(UUID().uuidString).dat")

        // Create 1MB file
        let testData = Data(repeating: 0xAB, count: 1024 * 1024)
        try testData.write(to: tempURL)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileIO = J2KAsyncFileIO()

        measure {
            let expectation = XCTestExpectation(description: "Async read complete")

            Task {
                do {
                    _ = try await fileIO.read(
                        from: tempURL,
                        offset: 0,
                        length: 1024 * 1024
                    )
                    expectation.fulfill()
                } catch {
                    XCTFail("Read failed: \(error)")
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }
}
