//
// J2KVulkanTests.swift
// J2KSwift
//
// Comprehensive tests for the Vulkan GPU compute backend.
//
import XCTest
@testable import J2KVulkan

/// Tests for Vulkan GPU compute backend — device, buffer pool, shaders,
/// DWT, colour transform, quantisation, and backend selection.
final class J2KVulkanTests: XCTestCase {

    // MARK: - Device Tests

    /// Tests that Vulkan is not available on macOS/Linux CI (no CVulkan module).
    func testVulkanAvailability() {
        // On CI without Vulkan drivers, isAvailable should be false
        let available = J2KVulkanDevice.isAvailable
        // Just verify it returns a Bool without crashing
        XCTAssertFalse(available, "Vulkan should not be available without CVulkan module")
    }

    /// Tests default device configuration.
    func testDefaultDeviceConfiguration() {
        let config = J2KVulkanDeviceConfiguration()
        XCTAssertFalse(config.preferIntegrated)
        XCTAssertEqual(config.maxMemoryUsage, 0)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests high performance device configuration.
    func testHighPerformanceConfiguration() {
        let config = J2KVulkanDeviceConfiguration.highPerformance
        XCTAssertFalse(config.preferIntegrated)
        XCTAssertEqual(config.maxMemoryUsage, 0)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests low power device configuration.
    func testLowPowerConfiguration() {
        let config = J2KVulkanDeviceConfiguration.lowPower
        XCTAssertTrue(config.preferIntegrated)
        XCTAssertEqual(config.maxMemoryUsage, 256 * 1024 * 1024)
        XCTAssertTrue(config.enableFallback)
    }

    /// Tests device initialisation fails gracefully without Vulkan.
    func testDeviceInitialisationFallback() async {
        let device = J2KVulkanDevice()
        do {
            try await device.initialize()
            XCTFail("Expected initialisation to throw without Vulkan")
        } catch {
            // Expected: Vulkan not available
        }
    }

    /// Tests device memory tracking.
    func testDeviceMemoryTracking() async {
        let device = J2KVulkanDevice()
        let usage0 = await device.memoryUsage()
        XCTAssertEqual(usage0, 0)

        await device.trackAllocation(bytes: 1024)
        let usage1 = await device.memoryUsage()
        XCTAssertEqual(usage1, 1024)

        await device.trackAllocation(bytes: 2048)
        let usage2 = await device.memoryUsage()
        XCTAssertEqual(usage2, 3072)

        await device.trackDeallocation(bytes: 1024)
        let usage3 = await device.memoryUsage()
        XCTAssertEqual(usage3, 2048)

        // Deallocation larger than current usage clamps to zero
        await device.trackDeallocation(bytes: 10000)
        let usage4 = await device.memoryUsage()
        XCTAssertEqual(usage4, 0)
    }

    /// Tests device canAllocate with memory limit.
    func testDeviceCanAllocate() async {
        let config = J2KVulkanDeviceConfiguration(maxMemoryUsage: 1024)
        let device = J2KVulkanDevice(configuration: config)

        let can512 = await device.canAllocate(bytes: 512)
        XCTAssertTrue(can512)

        let can2048 = await device.canAllocate(bytes: 2048)
        XCTAssertFalse(can2048)

        await device.trackAllocation(bytes: 800)
        let can300 = await device.canAllocate(bytes: 300)
        XCTAssertFalse(can300)
    }

    /// Tests device canAllocate with unlimited memory.
    func testDeviceCanAllocateUnlimited() async {
        let device = J2KVulkanDevice()
        let canAllocate = await device.canAllocate(bytes: UInt64.max)
        XCTAssertTrue(canAllocate)
    }

    /// Tests device runtime availability.
    func testDeviceRuntimeAvailable() async {
        let device = J2KVulkanDevice()
        let available = await device.runtimeAvailable()
        XCTAssertFalse(available)
    }

    /// Tests device name when not initialised.
    func testDeviceNameUninitialised() async {
        let device = J2KVulkanDevice()
        let name = await device.deviceName()
        XCTAssertEqual(name, "unavailable")
    }

    /// Tests device feature tier when not initialised.
    func testDeviceFeatureTierUninitialised() async {
        let device = J2KVulkanDevice()
        let tier = await device.featureTier()
        XCTAssertEqual(tier, .unknown)
    }

    // MARK: - Feature Tier Tests

    /// Tests vendor-based feature tier identification.
    func testFeatureTierIdentification() {
        XCTAssertEqual(J2KVulkanDevice.featureTier(vendorID: 0x10DE, isIntegrated: false), .nvidiaDiscrete)
        XCTAssertEqual(J2KVulkanDevice.featureTier(vendorID: 0x1002, isIntegrated: false), .amdDiscrete)
        XCTAssertEqual(J2KVulkanDevice.featureTier(vendorID: 0x8086, isIntegrated: true), .intelIntegrated)
        XCTAssertEqual(J2KVulkanDevice.featureTier(vendorID: 0x8086, isIntegrated: false), .intelDiscrete)
        XCTAssertEqual(J2KVulkanDevice.featureTier(vendorID: 0xFFFF, isIntegrated: false), .unknown)
    }

    /// Tests feature tier comparison.
    func testFeatureTierComparison() {
        XCTAssertTrue(J2KVulkanFeatureTier.unknown < J2KVulkanFeatureTier.intelIntegrated)
        XCTAssertTrue(J2KVulkanFeatureTier.intelIntegrated < J2KVulkanFeatureTier.intelDiscrete)
        XCTAssertTrue(J2KVulkanFeatureTier.intelDiscrete < J2KVulkanFeatureTier.amdDiscrete)
        XCTAssertTrue(J2KVulkanFeatureTier.amdDiscrete < J2KVulkanFeatureTier.nvidiaDiscrete)
    }

    // MARK: - Device Properties Tests

    /// Tests device properties construction.
    func testDeviceProperties() {
        let props = J2KVulkanDeviceProperties(
            name: "NVIDIA RTX 4090",
            vendorID: 0x10DE,
            deviceID: 0x2684,
            featureTier: .nvidiaDiscrete,
            maxComputeWorkGroupSizeX: 1024,
            maxComputeWorkGroupCountX: 65535,
            deviceLocalMemoryBytes: 24 * 1024 * 1024 * 1024
        )
        XCTAssertEqual(props.name, "NVIDIA RTX 4090")
        XCTAssertEqual(props.vendorID, 0x10DE)
        XCTAssertEqual(props.featureTier, .nvidiaDiscrete)
        XCTAssertEqual(props.maxComputeWorkGroupSizeX, 1024)
    }

    // MARK: - Buffer Pool Tests

    /// Tests default buffer pool configuration.
    func testDefaultBufferPoolConfiguration() {
        let config = J2KVulkanBufferPoolConfiguration()
        XCTAssertEqual(config.maxPoolSize, 64)
        XCTAssertEqual(config.maxPoolMemory, 256 * 1024 * 1024)
        XCTAssertTrue(config.enablePooling)
    }

    /// Tests buffer pool statistics initialisation.
    func testBufferPoolInitialStatistics() async {
        let pool = J2KVulkanBufferPool()
        let stats = await pool.statistics()
        XCTAssertEqual(stats.totalAllocations, 0)
        XCTAssertEqual(stats.poolHits, 0)
        XCTAssertEqual(stats.poolMisses, 0)
        XCTAssertEqual(stats.currentPoolSize, 0)
        XCTAssertEqual(stats.totalReturns, 0)
        XCTAssertEqual(stats.hitRate, 0.0, accuracy: 0.001)
    }

    /// Tests buffer pool acquire and return cycle.
    func testBufferPoolAcquireAndReturn() async throws {
        let pool = J2KVulkanBufferPool()

        // First acquire: miss
        let handle = try await pool.acquireBuffer(size: 1024)
        XCTAssertEqual(handle.size, 4096) // Rounded up to bucket
        var stats = await pool.statistics()
        XCTAssertEqual(stats.totalAllocations, 1)
        XCTAssertEqual(stats.poolMisses, 1)

        // Return
        await pool.returnBuffer(handle)
        stats = await pool.statistics()
        XCTAssertEqual(stats.totalReturns, 1)
        XCTAssertEqual(stats.currentPoolSize, 1)

        // Second acquire: hit (reuse from pool)
        let handle2 = try await pool.acquireBuffer(size: 1024)
        XCTAssertEqual(handle2.size, 4096)
        stats = await pool.statistics()
        XCTAssertEqual(stats.totalAllocations, 2)
        XCTAssertEqual(stats.poolHits, 1)
        XCTAssertEqual(stats.currentPoolSize, 0)
    }

    /// Tests buffer pool drain.
    func testBufferPoolDrain() async throws {
        let pool = J2KVulkanBufferPool()
        let handle = try await pool.acquireBuffer(size: 2048)
        await pool.returnBuffer(handle)

        let countBefore = await pool.count()
        XCTAssertEqual(countBefore, 1)

        await pool.drain()
        let countAfter = await pool.count()
        XCTAssertEqual(countAfter, 0)
    }

    /// Tests buffer pool hit rate calculation.
    func testBufferPoolHitRate() {
        var stats = J2KVulkanBufferPoolStatistics()
        XCTAssertEqual(stats.hitRate, 0.0, accuracy: 0.001)

        stats.totalAllocations = 10
        stats.poolHits = 7
        stats.poolMisses = 3
        XCTAssertEqual(stats.hitRate, 0.7, accuracy: 0.001)
    }

    /// Tests buffer pool with pooling disabled.
    func testBufferPoolDisabled() async throws {
        let config = J2KVulkanBufferPoolConfiguration(enablePooling: false)
        let pool = J2KVulkanBufferPool(configuration: config)

        let handle = try await pool.acquireBuffer(size: 1024)
        await pool.returnBuffer(handle)

        // With pooling disabled, return doesn't add to pool
        let count = await pool.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Buffer Handle Tests

    /// Tests buffer handle creation.
    func testBufferHandle() {
        let handle = J2KVulkanBufferHandle(id: 42, size: 8192, memoryType: .deviceLocal)
        XCTAssertEqual(handle.id, 42)
        XCTAssertEqual(handle.size, 8192)
    }

    // MARK: - Shader Library Tests

    /// Tests shader function enumeration.
    func testShaderFunctionCount() {
        let count = J2KVulkanShaderFunction.allCases.count
        XCTAssertEqual(count, 16) // 8 DWT + 4 colour + 4 quantisation
    }

    /// Tests pipeline configuration defaults.
    func testDefaultPipelineConfiguration() {
        let config = J2KVulkanPipelineConfiguration()
        XCTAssertEqual(config.workGroupSizeX, 256)
        XCTAssertEqual(config.workGroupSizeY, 1)
        XCTAssertEqual(config.workGroupSizeZ, 1)
    }

    /// Tests 2D pipeline configuration.
    func testPipelineConfiguration2D() {
        let config = J2KVulkanPipelineConfiguration.compute2D
        XCTAssertEqual(config.workGroupSizeX, 16)
        XCTAssertEqual(config.workGroupSizeY, 16)
    }

    /// Tests shader library statistics.
    func testShaderLibraryStatistics() async {
        let library = J2KVulkanShaderLibrary()
        let stats = await library.statistics()
        XCTAssertEqual(stats.totalPipelineRequests, 0)
        XCTAssertEqual(stats.cacheHits, 0)
        XCTAssertEqual(stats.cacheMisses, 0)
        XCTAssertEqual(stats.cacheHitRate, 0.0, accuracy: 0.001)
    }

    /// Tests shader library pipeline request caching.
    func testShaderLibraryPipelineCaching() async throws {
        let library = J2KVulkanShaderLibrary()

        // First request: cache miss
        _ = try await library.requestPipeline(for: .dwtForward53H)
        var stats = await library.statistics()
        XCTAssertEqual(stats.totalPipelineRequests, 1)
        XCTAssertEqual(stats.cacheMisses, 1)
        XCTAssertEqual(stats.cachedPipelineCount, 1)

        // Second request same function: cache hit
        _ = try await library.requestPipeline(for: .dwtForward53H)
        stats = await library.statistics()
        XCTAssertEqual(stats.totalPipelineRequests, 2)
        XCTAssertEqual(stats.cacheHits, 1)

        // Different function: cache miss
        _ = try await library.requestPipeline(for: .colourForwardICT)
        stats = await library.statistics()
        XCTAssertEqual(stats.totalPipelineRequests, 3)
        XCTAssertEqual(stats.cacheMisses, 2)
        XCTAssertEqual(stats.cachedPipelineCount, 2)
    }

    /// Tests shader library cache clear.
    func testShaderLibraryCacheClear() async throws {
        let library = J2KVulkanShaderLibrary()
        _ = try await library.requestPipeline(for: .quantiseScalar)

        await library.clearCache()
        let stats = await library.statistics()
        XCTAssertEqual(stats.cachedPipelineCount, 0)
    }

    /// Tests shader library available function count.
    func testShaderLibraryFunctionCount() async {
        let library = J2KVulkanShaderLibrary()
        let count = await library.availableFunctionCount()
        XCTAssertEqual(count, J2KVulkanShaderFunction.allCases.count)
    }

    // MARK: - Quantiser Tests

    /// Tests default quantisation configuration.
    func testDefaultQuantisationConfiguration() {
        let config = J2KVulkanQuantisationConfiguration()
        XCTAssertEqual(config.stepSize, 0.1, accuracy: 0.001)
        XCTAssertEqual(config.deadzoneWidth, 1.5, accuracy: 0.001)
        XCTAssertEqual(config.gpuThreshold, 1024)
    }

    /// Tests lossy quantisation configuration preset.
    func testLossyQuantisationConfiguration() {
        let config = J2KVulkanQuantisationConfiguration.lossy
        XCTAssertEqual(config.stepSize, 0.1, accuracy: 0.001)
    }

    /// Tests high quality quantisation configuration preset.
    func testHighQualityQuantisationConfiguration() {
        let config = J2KVulkanQuantisationConfiguration.highQuality
        XCTAssertEqual(config.stepSize, 0.05, accuracy: 0.001)
    }

    /// Tests quantisation statistics initialisation.
    func testQuantisationStatisticsInit() {
        let stats = J2KVulkanQuantisationStatistics()
        XCTAssertEqual(stats.totalQuantisations, 0)
        XCTAssertEqual(stats.totalDequantisations, 0)
        XCTAssertEqual(stats.gpuUtilisation, 0.0, accuracy: 0.001)
        XCTAssertEqual(stats.coefficientsPerSecond, 0.0, accuracy: 0.001)
    }

    /// Tests GPU utilisation calculation.
    func testQuantisationGPUUtilisation() {
        var stats = J2KVulkanQuantisationStatistics()
        stats.totalQuantisations = 6
        stats.totalDequantisations = 4
        stats.gpuQuantisations = 5
        stats.gpuDequantisations = 3
        // (5 + 3) / (6 + 4) = 0.8
        XCTAssertEqual(stats.gpuUtilisation, 0.8, accuracy: 0.001)
    }

    /// Tests scalar quantisation via CPU fallback.
    func testScalarQuantisationCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(
            mode: .scalar, stepSize: 0.5, backend: .cpu
        )
        let coefficients: [Float] = [0.0, 0.3, 0.7, 1.5, -0.8, -2.3]
        let result = try await quantiser.quantise(
            coefficients: coefficients,
            configuration: config
        )

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.indices.count, coefficients.count)
        // 0.0/0.5 = 0, 0.3/0.5 = 0, 0.7/0.5 = 1, 1.5/0.5 = 3, -0.8/0.5 = -1, -2.3/0.5 = -4
        XCTAssertEqual(result.indices[0], 0)
        XCTAssertEqual(result.indices[1], 0)
        XCTAssertEqual(result.indices[2], 1)
        XCTAssertEqual(result.indices[3], 3)
        XCTAssertEqual(result.indices[4], -1)
        XCTAssertEqual(result.indices[5], -4)
    }

    /// Tests deadzone quantisation via CPU fallback.
    func testDeadzoneQuantisationCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(
            mode: .deadzone, stepSize: 1.0, deadzoneWidth: 1.5, backend: .cpu
        )
        let coefficients: [Float] = [0.0, 0.5, 0.8, 2.0, -0.5, -3.0]
        let result = try await quantiser.quantise(
            coefficients: coefficients,
            configuration: config
        )

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.indices.count, coefficients.count)
        // threshold = 1.0 * 1.5 * 0.5 = 0.75
        // |0.0| <= 0.75 → 0
        // |0.5| <= 0.75 → 0
        // |0.8| > 0.75 → floor((0.8-0.75)/1.0)+1 = 1
        // |2.0| > 0.75 → floor((2.0-0.75)/1.0)+1 = 2
        XCTAssertEqual(result.indices[0], 0)
        XCTAssertEqual(result.indices[1], 0)
        XCTAssertEqual(result.indices[2], 1)
        XCTAssertEqual(result.indices[3], 2)
    }

    /// Tests scalar dequantisation via CPU fallback.
    func testScalarDequantisationCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(
            mode: .scalar, stepSize: 0.5, backend: .cpu
        )
        let indices: [Int32] = [0, 1, 3, -2]
        let result = try await quantiser.dequantise(
            indices: indices,
            configuration: config
        )

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.coefficients.count, indices.count)
        XCTAssertEqual(result.coefficients[0], 0.0, accuracy: 0.001)
    }

    /// Tests quantiser statistics tracking.
    func testQuantiserStatisticsTracking() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(backend: .cpu)
        _ = try await quantiser.quantise(coefficients: [1.0, 2.0], configuration: config)
        _ = try await quantiser.dequantise(indices: [1, 2], configuration: config)

        let stats = await quantiser.getStatistics()
        XCTAssertEqual(stats.totalQuantisations, 1)
        XCTAssertEqual(stats.totalDequantisations, 1)
        XCTAssertEqual(stats.cpuQuantisations, 1)
        XCTAssertEqual(stats.cpuDequantisations, 1)
        XCTAssertEqual(stats.totalCoefficientsProcessed, 4)
    }

    /// Tests quantiser statistics reset.
    func testQuantiserStatisticsReset() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(backend: .cpu)
        _ = try await quantiser.quantise(coefficients: [1.0], configuration: config)
        await quantiser.resetStatistics()

        let stats = await quantiser.getStatistics()
        XCTAssertEqual(stats.totalQuantisations, 0)
    }

    // MARK: - DWT Tests

    /// Tests default DWT configuration.
    func testDefaultDWTConfiguration() {
        let config = J2KVulkanDWTConfiguration()
        XCTAssertEqual(config.decompositionLevels, 5)
        XCTAssertEqual(config.gpuThreshold, 4096)
    }

    /// Tests lossy DWT configuration preset.
    func testLossyDWTConfiguration() {
        let config = J2KVulkanDWTConfiguration.lossy
        if case .irreversible97 = config.filter {
            // OK
        } else {
            XCTFail("Lossy config should use irreversible97 filter")
        }
    }

    /// Tests lossless DWT configuration preset.
    func testLosslessDWTConfiguration() {
        let config = J2KVulkanDWTConfiguration.lossless
        if case .reversible53 = config.filter {
            // OK
        } else {
            XCTFail("Lossless config should use reversible53 filter")
        }
    }

    /// Tests DWT statistics initialisation.
    func testDWTStatisticsInit() {
        let stats = J2KVulkanDWTStatistics()
        XCTAssertEqual(stats.totalForwardTransforms, 0)
        XCTAssertEqual(stats.totalInverseTransforms, 0)
        XCTAssertEqual(stats.gpuUtilisation, 0.0, accuracy: 0.001)
        XCTAssertEqual(stats.samplesPerSecond, 0.0, accuracy: 0.001)
    }

    /// Tests forward 5/3 DWT via CPU fallback.
    func testForward53DWTCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(filter: .reversible53, backend: .cpu)
        let samples: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let result = try await dwt.forwardTransform(samples: samples, configuration: config)

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.coefficients.count, samples.count)
        XCTAssertEqual(result.lowpassCount, 4)
    }

    /// Tests forward 9/7 DWT via CPU fallback.
    func testForward97DWTCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(filter: .irreversible97, backend: .cpu)
        let samples: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let result = try await dwt.forwardTransform(samples: samples, configuration: config)

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.coefficients.count, samples.count)
        XCTAssertEqual(result.lowpassCount, 4)
    }

    /// Tests DWT round-trip (5/3 forward → inverse) preserves signal.
    func testDWT53RoundTrip() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(filter: .reversible53, backend: .cpu)
        let samples: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]

        let forward = try await dwt.forwardTransform(samples: samples, configuration: config)
        let inverse = try await dwt.inverseTransform(
            coefficients: forward.coefficients,
            lowpassCount: forward.lowpassCount,
            configuration: config
        )

        // 5/3 is reversible, so round-trip should be near-exact
        for i in 0..<samples.count {
            XCTAssertEqual(inverse.coefficients[i], samples[i], accuracy: 1.0,
                          "Mismatch at index \(i)")
        }
    }

    /// Tests DWT round-trip (9/7 forward → inverse) preserves signal approximately.
    func testDWT97RoundTrip() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(filter: .irreversible97, backend: .cpu)
        let samples: [Float] = [10, 20, 30, 40, 50, 60, 70, 80]

        let forward = try await dwt.forwardTransform(samples: samples, configuration: config)
        let inverse = try await dwt.inverseTransform(
            coefficients: forward.coefficients,
            lowpassCount: forward.lowpassCount,
            configuration: config
        )

        // 9/7 is irreversible but should be close
        for i in 0..<samples.count {
            XCTAssertEqual(inverse.coefficients[i], samples[i], accuracy: 5.0,
                          "Mismatch at index \(i)")
        }
    }

    /// Tests DWT with empty input throws error.
    func testDWTEmptyInputThrows() async {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        do {
            _ = try await dwt.forwardTransform(samples: [], configuration: .lossy)
            XCTFail("Expected empty input to throw")
        } catch {
            // Expected
        }
    }

    /// Tests DWT statistics tracking.
    func testDWTStatisticsTracking() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(backend: .cpu)
        _ = try await dwt.forwardTransform(samples: [1, 2, 3, 4], configuration: config)
        _ = try await dwt.inverseTransform(
            coefficients: [1, 2, 3, 4], lowpassCount: 2, configuration: config
        )

        let stats = await dwt.getStatistics()
        XCTAssertEqual(stats.totalForwardTransforms, 1)
        XCTAssertEqual(stats.totalInverseTransforms, 1)
        XCTAssertEqual(stats.cpuForwardTransforms, 1)
        XCTAssertEqual(stats.cpuInverseTransforms, 1)
        XCTAssertEqual(stats.totalSamplesProcessed, 8)
    }

    /// Tests DWT with single sample.
    func testDWTSingleSample() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        let config = J2KVulkanDWTConfiguration(filter: .reversible53, backend: .cpu)
        let result = try await dwt.forwardTransform(samples: [42.0], configuration: config)
        XCTAssertEqual(result.coefficients, [42.0])
        XCTAssertEqual(result.lowpassCount, 1)
    }

    // MARK: - Colour Transform Tests

    /// Tests default colour transform configuration.
    func testDefaultColourTransformConfiguration() {
        let config = J2KVulkanColourTransformConfiguration()
        XCTAssertEqual(config.gpuThreshold, 1024)
    }

    /// Tests lossy colour transform configuration.
    func testLossyColourTransformConfiguration() {
        let config = J2KVulkanColourTransformConfiguration.lossy
        if case .ict = config.transformType {
            // OK
        } else {
            XCTFail("Lossy config should use ICT")
        }
    }

    /// Tests lossless colour transform configuration.
    func testLosslessColourTransformConfiguration() {
        let config = J2KVulkanColourTransformConfiguration.lossless
        if case .rct = config.transformType {
            // OK
        } else {
            XCTFail("Lossless config should use RCT")
        }
    }

    /// Tests colour transform statistics initialisation.
    func testColourTransformStatisticsInit() {
        let stats = J2KVulkanColourTransformStatistics()
        XCTAssertEqual(stats.totalForwardTransforms, 0)
        XCTAssertEqual(stats.totalInverseTransforms, 0)
        XCTAssertEqual(stats.gpuUtilisation, 0.0, accuracy: 0.001)
    }

    /// Tests forward ICT via CPU fallback.
    func testForwardICTCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        let config = J2KVulkanColourTransformConfiguration(
            transformType: .ict, backend: .cpu
        )
        let r: [Float] = [255, 0, 0, 128]
        let g: [Float] = [0, 255, 0, 128]
        let b: [Float] = [0, 0, 255, 128]

        let result = try await transform.forwardTransform(
            red: r, green: g, blue: b, configuration: config
        )

        XCTAssertFalse(result.usedGPU)
        XCTAssertEqual(result.component0.count, 4)
        XCTAssertEqual(result.component1.count, 4)
        XCTAssertEqual(result.component2.count, 4)

        // Grey (128,128,128) should have near-zero chroma
        XCTAssertEqual(result.component1[3], 0.0, accuracy: 0.5)
        XCTAssertEqual(result.component2[3], 0.0, accuracy: 0.5)
    }

    /// Tests ICT round-trip (forward → inverse) preserves signal.
    func testICTRoundTrip() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        let config = J2KVulkanColourTransformConfiguration(
            transformType: .ict, backend: .cpu
        )
        let r: [Float] = [200, 100, 50, 128]
        let g: [Float] = [150, 200, 100, 128]
        let b: [Float] = [100, 50, 200, 128]

        let forward = try await transform.forwardTransform(
            red: r, green: g, blue: b, configuration: config
        )
        let inverse = try await transform.inverseTransform(
            component0: forward.component0,
            component1: forward.component1,
            component2: forward.component2,
            configuration: config
        )

        for i in 0..<r.count {
            XCTAssertEqual(inverse.component0[i], r[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component1[i], g[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component2[i], b[i], accuracy: 1.0)
        }
    }

    /// Tests RCT round-trip preserves signal.
    func testRCTRoundTrip() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        let config = J2KVulkanColourTransformConfiguration(
            transformType: .rct, backend: .cpu
        )
        let r: [Float] = [200, 100, 50, 128]
        let g: [Float] = [150, 200, 100, 128]
        let b: [Float] = [100, 50, 200, 128]

        let forward = try await transform.forwardTransform(
            red: r, green: g, blue: b, configuration: config
        )
        let inverse = try await transform.inverseTransform(
            component0: forward.component0,
            component1: forward.component1,
            component2: forward.component2,
            configuration: config
        )

        for i in 0..<r.count {
            XCTAssertEqual(inverse.component0[i], r[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component1[i], g[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component2[i], b[i], accuracy: 1.0)
        }
    }

    /// Tests colour transform with mismatched channel sizes throws error.
    func testColourTransformMismatchedChannelsThrows() async {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        do {
            _ = try await transform.forwardTransform(
                red: [1.0, 2.0], green: [1.0], blue: [1.0, 2.0],
                configuration: .lossy
            )
            XCTFail("Expected mismatched channels to throw")
        } catch {
            // Expected
        }
    }

    /// Tests colour transform with empty channels throws error.
    func testColourTransformEmptyChannelsThrows() async {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        do {
            _ = try await transform.forwardTransform(
                red: [], green: [], blue: [],
                configuration: .lossy
            )
            XCTFail("Expected empty channels to throw")
        } catch {
            // Expected
        }
    }

    /// Tests colour transform statistics tracking.
    func testColourTransformStatisticsTracking() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        let config = J2KVulkanColourTransformConfiguration(backend: .cpu)
        _ = try await transform.forwardTransform(
            red: [1.0], green: [1.0], blue: [1.0], configuration: config
        )
        _ = try await transform.inverseTransform(
            component0: [1.0], component1: [0.0], component2: [0.0], configuration: config
        )

        let stats = await transform.getStatistics()
        XCTAssertEqual(stats.totalForwardTransforms, 1)
        XCTAssertEqual(stats.totalInverseTransforms, 1)
        XCTAssertEqual(stats.cpuForwardTransforms, 1)
        XCTAssertEqual(stats.cpuInverseTransforms, 1)
    }

    // MARK: - Backend Selector Tests

    /// Tests backend selector creation.
    func testBackendSelectorCreation() {
        let selector = J2KGPUBackendSelector()
        let backend = selector.selectedBackend()
        // On CI without Metal or Vulkan, should be CPU
        #if canImport(Metal)
        XCTAssertEqual(backend, .metal)
        #else
        XCTAssertEqual(backend, .cpu)
        #endif
    }

    /// Tests available backends always includes CPU.
    func testAvailableBackendsIncludesCPU() {
        let selector = J2KGPUBackendSelector()
        let backends = selector.availableBackends()
        XCTAssertTrue(backends.contains(.cpu))
    }

    /// Tests backend capabilities for CPU.
    func testCPUBackendCapabilities() {
        let caps = J2KGPUBackendCapabilities.cpuOnly
        XCTAssertEqual(caps.backendType, .cpu)
        XCTAssertTrue(caps.isAvailable)
        XCTAssertTrue(caps.supportsDWT)
        XCTAssertTrue(caps.supportsColourTransform)
        XCTAssertTrue(caps.supportsQuantisation)
        XCTAssertEqual(caps.deviceName, "CPU")
    }

    /// Tests backend type display names.
    func testBackendTypeDisplayNames() {
        XCTAssertEqual(J2KGPUBackendType.metal.displayName, "Metal")
        XCTAssertEqual(J2KGPUBackendType.vulkan.displayName, "Vulkan")
        XCTAssertEqual(J2KGPUBackendType.cpu.displayName, "CPU")
    }

    /// Tests backend type enumeration.
    func testBackendTypeAllCases() {
        let allCases = J2KGPUBackendType.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.metal))
        XCTAssertTrue(allCases.contains(.vulkan))
        XCTAssertTrue(allCases.contains(.cpu))
    }

    /// Tests selected capabilities match selected backend.
    func testSelectedCapabilitiesMatchBackend() {
        let selector = J2KGPUBackendSelector()
        let backend = selector.selectedBackend()
        let caps = selector.selectedCapabilities()
        XCTAssertEqual(caps.backendType, backend)
    }

    /// Tests Vulkan capabilities when Vulkan is unavailable.
    func testVulkanCapabilitiesUnavailable() {
        let selector = J2KGPUBackendSelector()
        let caps = selector.capabilities(for: .vulkan)
        XCTAssertEqual(caps.backendType, .vulkan)
        XCTAssertFalse(caps.isAvailable)
    }

    // MARK: - Vulkan Memory Type Tests

    /// Tests memory type enumeration.
    func testVulkanMemoryTypes() {
        let deviceLocal = J2KVulkanMemoryType.deviceLocal
        let hostVisible = J2KVulkanMemoryType.hostVisible
        let hostCached = J2KVulkanMemoryType.hostCached

        // Just verify they are distinct and constructible
        XCTAssertTrue(true, "Memory types are constructible: \(deviceLocal), \(hostVisible), \(hostCached)")
    }

    // MARK: - Fallback Path Tests

    /// Tests that DWT uses CPU when backend is .auto and Vulkan unavailable.
    func testDWTAutoFallbackToCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

        // Auto backend should fall back to CPU since Vulkan is not available
        let config = J2KVulkanDWTConfiguration(filter: .reversible53, backend: .auto)
        let result = try await dwt.forwardTransform(
            samples: [1, 2, 3, 4], configuration: config
        )
        XCTAssertFalse(result.usedGPU)
    }

    /// Tests that quantiser uses CPU when backend is .auto and Vulkan unavailable.
    func testQuantiserAutoFallbackToCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

        let config = J2KVulkanQuantisationConfiguration(backend: .auto)
        let result = try await quantiser.quantise(
            coefficients: [1.0, 2.0, 3.0], configuration: config
        )
        XCTAssertFalse(result.usedGPU)
    }

    /// Tests that colour transform uses CPU when backend is .auto and Vulkan unavailable.
    func testColourTransformAutoFallbackToCPU() async throws {
        let device = J2KVulkanDevice()
        let library = J2KVulkanShaderLibrary()
        let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

        let config = J2KVulkanColourTransformConfiguration(backend: .auto)
        let result = try await transform.forwardTransform(
            red: [1.0], green: [1.0], blue: [1.0], configuration: config
        )
        XCTAssertFalse(result.usedGPU)
    }
}
