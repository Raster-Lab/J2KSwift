import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for J2KMetal module - Metal GPU Acceleration Infrastructure.
final class J2KMetalDeviceTests: XCTestCase {

    // MARK: - Platform Availability Tests

    /// Tests that Metal availability can be queried without crashing.
    func testMetalAvailabilityCheck() {
        // Should return true on Apple platforms with Metal, false on Linux
        let available = J2KMetalDevice.isAvailable
        #if canImport(Metal)
        // Metal framework is importable but device may not be available in CI
        _ = available
        #else
        XCTAssertFalse(available)
        #endif
    }

    /// Tests that buffer pool availability matches platform.
    func testBufferPoolAvailabilityCheck() {
        let available = J2KMetalBufferPool.isAvailable
        #if canImport(Metal)
        XCTAssertTrue(available)
        #else
        XCTAssertFalse(available)
        #endif
    }

    /// Tests that shader library availability matches platform.
    func testShaderLibraryAvailabilityCheck() {
        let available = J2KMetalShaderLibrary.isAvailable
        #if canImport(Metal)
        XCTAssertTrue(available)
        #else
        XCTAssertFalse(available)
        #endif
    }

    // MARK: - Feature Tier Tests

    /// Tests feature tier ordering.
    func testFeatureTierOrdering() {
        XCTAssertTrue(J2KMetalFeatureTier.unknown < .intelIntegrated)
        XCTAssertTrue(J2KMetalFeatureTier.intelIntegrated < .intelDiscrete)
        XCTAssertTrue(J2KMetalFeatureTier.intelDiscrete < .appleSilicon)
    }

    /// Tests feature tier raw values.
    func testFeatureTierRawValues() {
        XCTAssertEqual(J2KMetalFeatureTier.unknown.rawValue, 0)
        XCTAssertEqual(J2KMetalFeatureTier.intelIntegrated.rawValue, 1)
        XCTAssertEqual(J2KMetalFeatureTier.intelDiscrete.rawValue, 2)
        XCTAssertEqual(J2KMetalFeatureTier.appleSilicon.rawValue, 3)
    }

    /// Tests feature tier equality.
    func testFeatureTierEquality() {
        XCTAssertEqual(J2KMetalFeatureTier.appleSilicon, .appleSilicon)
        XCTAssertNotEqual(J2KMetalFeatureTier.unknown, .appleSilicon)
    }

    // MARK: - Device Configuration Tests

    /// Tests default device configuration.
    func testDefaultDeviceConfiguration() {
        let config = J2KMetalDeviceConfiguration.default
        XCTAssertFalse(config.preferLowPower)
        XCTAssertEqual(config.maxMemoryUsage, 0)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests high performance configuration.
    func testHighPerformanceConfiguration() {
        let config = J2KMetalDeviceConfiguration.highPerformance
        XCTAssertFalse(config.preferLowPower)
        XCTAssertEqual(config.maxMemoryUsage, 0)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests low power configuration.
    func testLowPowerConfiguration() {
        let config = J2KMetalDeviceConfiguration.lowPower
        XCTAssertTrue(config.preferLowPower)
        XCTAssertEqual(config.maxMemoryUsage, 256 * 1024 * 1024)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests custom device configuration.
    func testCustomDeviceConfiguration() {
        let config = J2KMetalDeviceConfiguration(
            preferLowPower: true,
            maxMemoryUsage: 1024 * 1024,
            enableFallback: false
        )
        XCTAssertTrue(config.preferLowPower)
        XCTAssertEqual(config.maxMemoryUsage, 1024 * 1024)
        XCTAssertFalse(config.enableFallback)
    }

    // MARK: - Device Initialization Tests

    /// Tests device creation with default configuration.
    func testDeviceCreation() async {
        let device = J2KMetalDevice()
        let tier = await device.featureTier()
        #if canImport(Metal)
        // Tier depends on available hardware
        _ = tier
        #else
        XCTAssertEqual(tier, .unknown)
        #endif
    }

    /// Tests device creation with custom configuration.
    func testDeviceCreationWithConfiguration() async {
        let config = J2KMetalDeviceConfiguration(
            preferLowPower: true,
            maxMemoryUsage: 128 * 1024 * 1024,
            enableFallback: true
        )
        let device = J2KMetalDevice(configuration: config)
        let deviceConfig = await device.configuration
        XCTAssertTrue(deviceConfig.preferLowPower)
        XCTAssertEqual(deviceConfig.maxMemoryUsage, 128 * 1024 * 1024)
    }

    /// Tests that uninitialized device returns error for command queue.
    func testUninitializedDeviceCommandQueue() async {
        let device = J2KMetalDevice()
        do {
            try await device.validateReady()
            XCTFail("Expected error for uninitialized device")
        } catch {
            // Expected
        }
    }

    /// Tests device initialization on the current platform.
    func testDeviceInitialization() async {
        let device = J2KMetalDevice()
        #if canImport(Metal)
        do {
            try await device.initialize()
            let name = await device.deviceName()
            XCTAssertNotEqual(name, "unavailable")
        } catch {
            // Metal device not available in CI - this is acceptable
        }
        #else
        do {
            try await device.initialize()
            XCTFail("Expected error on non-Metal platform")
        } catch {
            // Expected
        }
        #endif
    }

    /// Tests that double initialization is safe (no-op).
    func testDoubleInitialization() async {
        let device = J2KMetalDevice()
        #if canImport(Metal)
        do {
            try await device.initialize()
            try await device.initialize() // Should be no-op
        } catch {
            // Metal device not available in CI
        }
        #else
        // Not applicable on non-Metal platforms
        #endif
    }

    /// Tests device name retrieval.
    func testDeviceName() async {
        let device = J2KMetalDevice()
        let name = await device.deviceName()
        // Before initialization, should return "unavailable"
        XCTAssertEqual(name, "unavailable")
    }

    // MARK: - Memory Tracking Tests

    /// Tests memory allocation tracking.
    func testMemoryTracking() async {
        let device = J2KMetalDevice(configuration: .init(maxMemoryUsage: 1024))
        let usage = await device.memoryUsage()
        XCTAssertEqual(usage, 0)

        await device.trackAllocation(bytes: 256)
        let usage2 = await device.memoryUsage()
        XCTAssertEqual(usage2, 256)

        await device.trackAllocation(bytes: 512)
        let usage3 = await device.memoryUsage()
        XCTAssertEqual(usage3, 768)

        await device.trackDeallocation(bytes: 256)
        let usage4 = await device.memoryUsage()
        XCTAssertEqual(usage4, 512)
    }

    /// Tests memory allocation limit checking.
    func testMemoryAllocationLimits() async {
        let device = J2KMetalDevice(
            configuration: .init(maxMemoryUsage: 1024)
        )

        let canAlloc1 = await device.canAllocate(bytes: 512)
        XCTAssertTrue(canAlloc1)

        await device.trackAllocation(bytes: 768)

        let canAlloc2 = await device.canAllocate(bytes: 512)
        XCTAssertFalse(canAlloc2)

        let canAlloc3 = await device.canAllocate(bytes: 256)
        XCTAssertTrue(canAlloc3)
    }

    /// Tests unlimited memory mode (maxMemoryUsage = 0).
    func testUnlimitedMemoryMode() async {
        let device = J2KMetalDevice(
            configuration: .init(maxMemoryUsage: 0)
        )

        let canAlloc = await device.canAllocate(bytes: UInt64.max)
        XCTAssertTrue(canAlloc)
    }

    /// Tests deallocation doesn't underflow.
    func testDeallocationUnderflowProtection() async {
        let device = J2KMetalDevice()
        await device.trackAllocation(bytes: 100)
        await device.trackDeallocation(bytes: 200)
        let usage = await device.memoryUsage()
        XCTAssertEqual(usage, 0)
    }

    // MARK: - Buffer Pool Configuration Tests

    /// Tests default buffer pool configuration.
    func testDefaultBufferPoolConfiguration() {
        let config = J2KMetalBufferPoolConfiguration.default
        XCTAssertEqual(config.maxPoolSize, 64)
        XCTAssertEqual(config.maxPoolMemory, 256 * 1024 * 1024)
        XCTAssertTrue(config.enablePooling)
    }

    /// Tests custom buffer pool configuration.
    func testCustomBufferPoolConfiguration() {
        let config = J2KMetalBufferPoolConfiguration(
            maxPoolSize: 32,
            maxPoolMemory: 128 * 1024 * 1024,
            defaultStrategy: .private,
            enablePooling: false
        )
        XCTAssertEqual(config.maxPoolSize, 32)
        XCTAssertEqual(config.maxPoolMemory, 128 * 1024 * 1024)
        XCTAssertFalse(config.enablePooling)
    }

    // MARK: - Buffer Pool Statistics Tests

    /// Tests initial buffer pool statistics.
    func testInitialPoolStatistics() async {
        let pool = J2KMetalBufferPool()
        let stats = await pool.statistics()
        XCTAssertEqual(stats.totalAllocations, 0)
        XCTAssertEqual(stats.poolHits, 0)
        XCTAssertEqual(stats.poolMisses, 0)
        XCTAssertEqual(stats.currentPoolSize, 0)
        XCTAssertEqual(stats.currentPoolMemory, 0)
        XCTAssertEqual(stats.hitRate, 0.0)
    }

    /// Tests buffer pool drain.
    func testBufferPoolDrain() async {
        let pool = J2KMetalBufferPool()
        await pool.drain()
        let count = await pool.count()
        XCTAssertEqual(count, 0)
    }

    /// Tests hit rate calculation.
    func testPoolHitRateCalculation() {
        var stats = J2KMetalBufferPoolStatistics()
        XCTAssertEqual(stats.hitRate, 0.0)

        stats.totalAllocations = 10
        stats.poolHits = 7
        XCTAssertEqual(stats.hitRate, 0.7, accuracy: 0.001)
    }

    // MARK: - Shader Function Tests

    /// Tests shader function enumeration.
    func testShaderFunctionCases() {
        let allCases = J2KMetalShaderFunction.allCases
        // 30 original + 5 ROI + 8 quantization = 43 total
        XCTAssertEqual(allCases.count, 43)
    }

    /// Tests shader function raw values.
    func testShaderFunctionRawValues() {
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtForward97Horizontal.rawValue,
            "j2k_dwt_forward_97_horizontal"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.ictForward.rawValue,
            "j2k_ict_forward"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.rctForward.rawValue,
            "j2k_rct_forward"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.mctMatrixMultiply.rawValue,
            "j2k_mct_matrix_multiply"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.quantize.rawValue,
            "j2k_quantize"
        )
    }

    // MARK: - Shader Library Configuration Tests

    /// Tests default shader library configuration.
    func testDefaultShaderLibraryConfiguration() {
        let config = J2KMetalShaderLibraryConfiguration.default
        XCTAssertTrue(config.enablePipelineCache)
        XCTAssertEqual(config.maxCachedPipelines, 32)
    }

    /// Tests custom shader library configuration.
    func testCustomShaderLibraryConfiguration() {
        let config = J2KMetalShaderLibraryConfiguration(
            enablePipelineCache: false,
            maxCachedPipelines: 16
        )
        XCTAssertFalse(config.enablePipelineCache)
        XCTAssertEqual(config.maxCachedPipelines, 16)
    }

    // MARK: - Shader Library State Tests

    /// Tests shader library creation.
    func testShaderLibraryCreation() async {
        let library = J2KMetalShaderLibrary()
        let count = await library.cachedPipelineCount()
        XCTAssertEqual(count, 0)
    }

    /// Tests available functions before loading.
    func testAvailableFunctionsBeforeLoading() async {
        let library = J2KMetalShaderLibrary()
        let functions = await library.availableFunctions()
        XCTAssertTrue(functions.isEmpty)
    }

    /// Tests hasFunction before loading.
    func testHasFunctionBeforeLoading() async {
        let library = J2KMetalShaderLibrary()
        let has = await library.hasFunction(.dwtForward97Horizontal)
        XCTAssertFalse(has)
    }

    /// Tests compute pipeline before loading shaders.
    func testComputePipelineBeforeLoading() async {
        let library = J2KMetalShaderLibrary()
        do {
            try await library.validateLoaded()
            XCTFail("Expected error for unloaded library")
        } catch {
            // Expected
        }
    }

    /// Tests cache clearing.
    func testCacheClearing() async {
        let library = J2KMetalShaderLibrary()
        await library.clearCache()
        let count = await library.cachedPipelineCount()
        XCTAssertEqual(count, 0)
    }

    /// Tests shader loading on non-Metal platforms throws appropriate error.
    func testShaderLoadingOnUnsupportedPlatform() async {
        #if !canImport(Metal)
        let library = J2KMetalShaderLibrary()
        do {
            try await library.validateLoaded()
            XCTFail("Expected unsupported feature error")
        } catch {
            // Expected
        }
        #endif
    }

    // MARK: - Buffer Allocation Strategy Tests

    /// Tests buffer allocation strategy values.
    func testBufferAllocationStrategies() {
        let strategies: [J2KMetalBufferAllocationStrategy] = [
            .shared, .managed, .private
        ]
        XCTAssertEqual(strategies.count, 3)
    }
}
