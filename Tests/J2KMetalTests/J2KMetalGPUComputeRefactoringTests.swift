//
// J2KMetalGPUComputeRefactoringTests.swift
// J2KSwift
//

import XCTest
import Synchronization
@testable import J2KMetal
@testable import J2KCore

final class J2KMetalGPUComputeRefactoringTests: XCTestCase {

    // MARK: - Bit Depth Tests

    func testBitDepthAllCases() {
        let cases = J2KMetalBitDepth.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertEqual(cases.map(\.rawValue), [8, 12, 16, 32])
    }

    func testBitDepthBytesPerSample() {
        XCTAssertEqual(J2KMetalBitDepth.depth8.bytesPerSample, 1)
        XCTAssertEqual(J2KMetalBitDepth.depth12.bytesPerSample, 2)
        XCTAssertEqual(J2KMetalBitDepth.depth16.bytesPerSample, 2)
        XCTAssertEqual(J2KMetalBitDepth.depth32.bytesPerSample, 4)
    }

    func testBitDepthShaderSuffix() {
        XCTAssertEqual(J2KMetalBitDepth.depth8.shaderSuffix, "_8bit")
        XCTAssertEqual(J2KMetalBitDepth.depth12.shaderSuffix, "_12bit")
        XCTAssertEqual(J2KMetalBitDepth.depth16.shaderSuffix, "_16bit")
        XCTAssertEqual(J2KMetalBitDepth.depth32.shaderSuffix, "_32bit")
    }

    func testBitDepthComparable() {
        XCTAssertTrue(J2KMetalBitDepth.depth8 < .depth12)
        XCTAssertTrue(J2KMetalBitDepth.depth12 < .depth16)
        XCTAssertTrue(J2KMetalBitDepth.depth16 < .depth32)
    }

    // MARK: - Shader Variant Tests

    func testShaderVariantCreation() {
        let variant = J2KMetalShaderVariant(
            baseFunctionName: "j2k_dwt_forward_97_horizontal",
            bitDepth: .depth16
        )
        XCTAssertEqual(variant.baseFunctionName, "j2k_dwt_forward_97_horizontal")
        XCTAssertEqual(variant.bitDepth, .depth16)
        XCTAssertEqual(variant.functionName, "j2k_dwt_forward_97_horizontal_16bit")
    }

    func testShaderVariantEquality() {
        let a = J2KMetalShaderVariant(baseFunctionName: "test", bitDepth: .depth8)
        let b = J2KMetalShaderVariant(baseFunctionName: "test", bitDepth: .depth8)
        let c = J2KMetalShaderVariant(baseFunctionName: "test", bitDepth: .depth16)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Tile Dispatch Configuration Tests

    func testTileDispatchDefaults() {
        let config = J2KMetalTileDispatchConfiguration.default
        XCTAssertEqual(config.tileWidth, 256)
        XCTAssertEqual(config.tileHeight, 256)
        XCTAssertEqual(config.overlap, 8)
        XCTAssertTrue(config.doubleBuffered)
        XCTAssertEqual(config.maxConcurrentTiles, 4)
    }

    func testTileDispatchLargeImage() {
        let config = J2KMetalTileDispatchConfiguration.largeImage
        XCTAssertEqual(config.tileWidth, 512)
        XCTAssertEqual(config.tileHeight, 512)
        XCTAssertEqual(config.overlap, 16)
        XCTAssertTrue(config.doubleBuffered)
        XCTAssertEqual(config.maxConcurrentTiles, 8)
    }

    func testTileDispatchSmallImage() {
        let config = J2KMetalTileDispatchConfiguration.smallImage
        XCTAssertEqual(config.tileWidth, 1024)
        XCTAssertFalse(config.doubleBuffered)
        XCTAssertEqual(config.maxConcurrentTiles, 1)
    }

    func testTileDispatchMinimumClamp() {
        let config = J2KMetalTileDispatchConfiguration(
            tileWidth: 1, tileHeight: 1, overlap: -5,
            doubleBuffered: false, maxConcurrentTiles: 0
        )
        XCTAssertEqual(config.tileWidth, 16)
        XCTAssertEqual(config.tileHeight, 16)
        XCTAssertEqual(config.overlap, 0)
        XCTAssertEqual(config.maxConcurrentTiles, 1)
    }

    // MARK: - Tile Descriptor Tests

    func testTileDescriptorCreation() {
        let tile = J2KMetalTileDescriptor(
            tileX: 2, tileY: 3, originX: 512, originY: 768,
            width: 256, height: 256
        )
        XCTAssertEqual(tile.tileX, 2)
        XCTAssertEqual(tile.tileY, 3)
        XCTAssertEqual(tile.originX, 512)
        XCTAssertEqual(tile.originY, 768)
        XCTAssertEqual(tile.width, 256)
        XCTAssertEqual(tile.height, 256)
    }

    // MARK: - Indirect Command Configuration Tests

    func testIndirectCommandDefaults() {
        let config = J2KMetalIndirectCommandConfiguration.default
        XCTAssertEqual(config.maxCommandCount, 256)
        XCTAssertTrue(config.inheritPipelineState)
        XCTAssertTrue(config.inheritBuffers)
    }

    func testIndirectCommandMinClamp() {
        let config = J2KMetalIndirectCommandConfiguration(maxCommandCount: 0)
        XCTAssertEqual(config.maxCommandCount, 1)
    }

    // MARK: - Async Compute Configuration Tests

    func testAsyncComputeDefaults() {
        let config = J2KMetalAsyncComputeConfiguration.default
        XCTAssertEqual(config.inflightBufferCount, 2)
        XCTAssertTrue(config.enableMultiQueue)
        XCTAssertTrue(config.enableTimelineSync)
        XCTAssertEqual(config.computePriority, .normal)
    }

    func testAsyncComputeHighThroughput() {
        let config = J2KMetalAsyncComputeConfiguration.highThroughput
        XCTAssertEqual(config.inflightBufferCount, 3)
        XCTAssertEqual(config.computePriority, .high)
    }

    func testAsyncComputeInflightClamp() {
        let low = J2KMetalAsyncComputeConfiguration(inflightBufferCount: 0)
        XCTAssertEqual(low.inflightBufferCount, 1)
        let high = J2KMetalAsyncComputeConfiguration(inflightBufferCount: 10)
        XCTAssertEqual(high.inflightBufferCount, 3)
    }

    // MARK: - Compute Priority Tests

    func testComputePriorityComparable() {
        XCTAssertTrue(J2KMetalComputePriority.low < .normal)
        XCTAssertTrue(J2KMetalComputePriority.normal < .high)
    }

    // MARK: - Profiling Event Tests

    func testProfilingEventCreation() {
        let event = J2KMetalProfilingEvent(
            name: "dwt_forward", startTime: 100, endTime: 200,
            duration: 0.001, threadgroupSize: 256, gridSize: 4096,
            isAsync: true
        )
        XCTAssertEqual(event.name, "dwt_forward")
        XCTAssertEqual(event.startTime, 100)
        XCTAssertEqual(event.endTime, 200)
        XCTAssertEqual(event.duration, 0.001, accuracy: 1e-9)
        XCTAssertEqual(event.threadgroupSize, 256)
        XCTAssertEqual(event.gridSize, 4096)
        XCTAssertTrue(event.isAsync)
    }

    // MARK: - Occupancy Analysis Tests

    func testOccupancyAnalysisCreation() {
        let analysis = J2KMetalOccupancyAnalysis(
            shaderName: "test_shader",
            optimalThreadgroupSize: 256,
            estimatedOccupancy: 0.75,
            registerPressure: 48,
            threadgroupMemoryUsed: 4096,
            recommendedMaxThreads: 512
        )
        XCTAssertEqual(analysis.shaderName, "test_shader")
        XCTAssertEqual(analysis.optimalThreadgroupSize, 256)
        XCTAssertEqual(analysis.estimatedOccupancy, 0.75, accuracy: 1e-6)
        XCTAssertEqual(analysis.registerPressure, 48)
        XCTAssertEqual(analysis.threadgroupMemoryUsed, 4096)
        XCTAssertEqual(analysis.recommendedMaxThreads, 512)
    }

    // MARK: - Threadgroup Memory Layout Tests

    func testThreadgroupMemoryLayoutCreation() {
        let layout = J2KMetalThreadgroupMemoryLayout(
            size: 2048, alignment: 16, avoidBankConflicts: true, rowPadding: 4
        )
        XCTAssertEqual(layout.size, 2048)
        XCTAssertEqual(layout.alignment, 16)
        XCTAssertTrue(layout.avoidBankConflicts)
        XCTAssertEqual(layout.rowPadding, 4)
    }

    // MARK: - Bottleneck Analysis Tests

    func testBottleneckTypes() {
        XCTAssertEqual(J2KMetalBottleneck.aluBound.rawValue, "ALU-bound")
        XCTAssertEqual(J2KMetalBottleneck.bandwidthBound.rawValue, "bandwidth-bound")
        XCTAssertEqual(J2KMetalBottleneck.latencyBound.rawValue, "latency-bound")
        XCTAssertEqual(J2KMetalBottleneck.balanced.rawValue, "balanced")
    }

    func testBottleneckAnalysisCreation() {
        let analysis = J2KMetalBottleneckAnalysis(
            bottleneck: .bandwidthBound,
            aluUtilisation: 0.3,
            bandwidthUtilisation: 0.9,
            recommendations: ["Reduce memory traffic"]
        )
        XCTAssertEqual(analysis.bottleneck, .bandwidthBound)
        XCTAssertEqual(analysis.aluUtilisation, 0.3, accuracy: 1e-6)
        XCTAssertEqual(analysis.bandwidthUtilisation, 0.9, accuracy: 1e-6)
        XCTAssertEqual(analysis.recommendations.count, 1)
    }

    // MARK: - Metal 3 Features Tests

    func testMetal3FeaturesDetect() {
        let features = J2KMetal3Features.detect()
        #if canImport(Metal)
        _ = features.anyAvailable
        #else
        XCTAssertFalse(features.meshShaders)
        XCTAssertFalse(features.raytracingAcceleration)
        XCTAssertFalse(features.residencySets)
        XCTAssertFalse(features.functionPointers)
        XCTAssertFalse(features.anyAvailable)
        #endif
    }

    func testMetal3FeaturesAnyAvailable() {
        let allFalse = J2KMetal3Features(
            meshShaders: false, raytracingAcceleration: false,
            residencySets: false, functionPointers: false
        )
        XCTAssertFalse(allFalse.anyAvailable)

        let onTrue = J2KMetal3Features(
            meshShaders: true, raytracingAcceleration: false,
            residencySets: false, functionPointers: false
        )
        XCTAssertTrue(onTrue.anyAvailable)
    }

    // MARK: - Pipeline Manager Tests

    func testPipelineManagerAvailability() {
        let available = J2KMetalShaderPipelineManager.isAvailable
        #if canImport(Metal)
        _ = available
        #else
        XCTAssertFalse(available)
        #endif
    }

    func testPipelineManagerInitialisation() async throws {
        let pipeline = J2KMetalShaderPipelineManager()
        let ready = await pipeline.isReady()
        XCTAssertFalse(ready)

        #if canImport(Metal)
        // Initialisation may fail in CI without GPU
        do {
            try await pipeline.initialize()
            let readyAfter = await pipeline.isReady()
            XCTAssertTrue(readyAfter)
        } catch {
            // Expected on non-GPU CI
        }
        #endif
    }

    func testPipelineManagerIdempotentInit() async throws {
        let pipeline = J2KMetalShaderPipelineManager()
        #if canImport(Metal)
        do {
            try await pipeline.initialize()
            try await pipeline.initialize() // Second call should be no-op
            let ready = await pipeline.isReady()
            XCTAssertTrue(ready)
        } catch {
            // Expected on non-GPU CI
        }
        #endif
    }

    // MARK: - Shader Variant Selection Tests

    func testShaderVariantSelection() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let variant = await pipeline.shaderVariant(
            baseName: "j2k_dwt_forward_97_horizontal",
            bitDepth: .depth12
        )
        XCTAssertEqual(variant.functionName, "j2k_dwt_forward_97_horizontal_12bit")
    }

    func testAllVariants() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let variants = await pipeline.allVariants(baseName: "j2k_quantize")
        XCTAssertEqual(variants.count, 4)
        XCTAssertEqual(variants[0].functionName, "j2k_quantize_8bit")
        XCTAssertEqual(variants[1].functionName, "j2k_quantize_12bit")
        XCTAssertEqual(variants[2].functionName, "j2k_quantize_16bit")
        XCTAssertEqual(variants[3].functionName, "j2k_quantize_32bit")
    }

    func testOptimalBitDepthSelection() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let d8 = await pipeline.optimalBitDepth(for: 8)
        XCTAssertEqual(d8, .depth8)
        let d10 = await pipeline.optimalBitDepth(for: 10)
        XCTAssertEqual(d10, .depth12)
        let d12 = await pipeline.optimalBitDepth(for: 12)
        XCTAssertEqual(d12, .depth12)
        let d14 = await pipeline.optimalBitDepth(for: 14)
        XCTAssertEqual(d14, .depth16)
        let d16 = await pipeline.optimalBitDepth(for: 16)
        XCTAssertEqual(d16, .depth16)
        let d24 = await pipeline.optimalBitDepth(for: 24)
        XCTAssertEqual(d24, .depth32)
    }

    // MARK: - Tile Grid Tests

    func testTileGridBasic() async throws {
        let pipeline = J2KMetalShaderPipelineManager(
            tileConfig: J2KMetalTileDispatchConfiguration(
                tileWidth: 256, tileHeight: 256, overlap: 0
            )
        )
        let tiles = try await pipeline.computeTileGrid(
            imageWidth: 512, imageHeight: 512
        )
        XCTAssertEqual(tiles.count, 4) // 2×2 grid
        XCTAssertEqual(tiles[0].originX, 0)
        XCTAssertEqual(tiles[0].originY, 0)
        XCTAssertEqual(tiles[0].width, 256)
        XCTAssertEqual(tiles[1].originX, 256)
    }

    func testTileGridWithOverlap() async throws {
        let pipeline = J2KMetalShaderPipelineManager(
            tileConfig: J2KMetalTileDispatchConfiguration(
                tileWidth: 256, tileHeight: 256, overlap: 8
            )
        )
        let tiles = try await pipeline.computeTileGrid(
            imageWidth: 512, imageHeight: 256
        )
        // With overlap of 8, step = 248. Two tiles fit in 512 width.
        XCTAssertGreaterThanOrEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].originX, 0)
    }

    func testTileGridEdgeTiles() async throws {
        let pipeline = J2KMetalShaderPipelineManager(
            tileConfig: J2KMetalTileDispatchConfiguration(
                tileWidth: 256, tileHeight: 256, overlap: 0
            )
        )
        let tiles = try await pipeline.computeTileGrid(
            imageWidth: 300, imageHeight: 300
        )
        // 300 / 256 rounds up to 2×2
        XCTAssertEqual(tiles.count, 4)
        // Last column tile should have reduced width
        let lastCol = tiles.first(where: { $0.tileX == 1 })
        XCTAssertNotNil(lastCol)
        XCTAssertEqual(lastCol!.width, 44)
    }

    func testTileGridInvalidDimensions() async {
        let pipeline = J2KMetalShaderPipelineManager()
        do {
            _ = try await pipeline.computeTileGrid(imageWidth: 0, imageHeight: 100)
            XCTFail("Expected invalidParameter error")
        } catch {
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter, got \(error)")
                return
            }
        }
    }

    func testTileGridLargeImage() async throws {
        let pipeline = J2KMetalShaderPipelineManager(
            tileConfig: J2KMetalTileDispatchConfiguration.largeImage
        )
        let tiles = try await pipeline.computeTileGrid(
            imageWidth: 4096, imageHeight: 4096
        )
        XCTAssertGreaterThan(tiles.count, 1)
        // All tiles should cover the image
        let maxRight = tiles.map { $0.originX + $0.width }.max()!
        let maxBottom = tiles.map { $0.originY + $0.height }.max()!
        XCTAssertGreaterThanOrEqual(maxRight, 4096)
        XCTAssertGreaterThanOrEqual(maxBottom, 4096)
    }

    func testMaxConcurrentDispatches() async throws {
        let pipeline = J2KMetalShaderPipelineManager(
            tileConfig: J2KMetalTileDispatchConfiguration(maxConcurrentTiles: 4)
        )
        let tiles = try await pipeline.computeTileGrid(
            imageWidth: 1024, imageHeight: 1024,
            config: J2KMetalTileDispatchConfiguration(
                tileWidth: 256, tileHeight: 256, overlap: 0
            )
        )
        let maxConc = await pipeline.maxConcurrentDispatches(for: tiles)
        XCTAssertEqual(maxConc, 4)

        // With fewer tiles than max concurrent
        let fewTiles = [J2KMetalTileDescriptor(
            tileX: 0, tileY: 0, originX: 0, originY: 0, width: 256, height: 256
        )]
        let maxConc2 = await pipeline.maxConcurrentDispatches(for: fewTiles)
        XCTAssertEqual(maxConc2, 1)
    }

    // MARK: - Indirect Command Buffer Tests

    func testSupportsIndirectCommandBuffers() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let supported = await pipeline.supportsIndirectCommandBuffers()
        #if canImport(Metal)
        _ = supported // May or may not be supported depending on hardware
        #else
        XCTAssertFalse(supported)
        #endif
    }

    func testIndirectCommandCount() async {
        let pipeline = J2KMetalShaderPipelineManager(
            indirectConfig: J2KMetalIndirectCommandConfiguration(maxCommandCount: 100)
        )
        let count = await pipeline.indirectCommandCount(for: 50)
        XCTAssertEqual(count, 50)
        let countClamped = await pipeline.indirectCommandCount(for: 200)
        XCTAssertEqual(countClamped, 100)
    }

    // MARK: - Async Pipeline Tests

    func testInflightBufferCount() async {
        let pipeline = J2KMetalShaderPipelineManager(
            asyncConfig: J2KMetalAsyncComputeConfiguration(inflightBufferCount: 3)
        )
        let count = await pipeline.inflightBufferCount()
        XCTAssertEqual(count, 3)
    }

    func testMultiQueueAvailability() async {
        let pipeline = J2KMetalShaderPipelineManager(
            asyncConfig: J2KMetalAsyncComputeConfiguration(enableMultiQueue: false)
        )
        let available = await pipeline.isMultiQueueAvailable()
        XCTAssertFalse(available)
    }

    func testTimelineSyncNotAvailableBeforeInit() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let available = await pipeline.isTimelineSyncAvailable()
        #if canImport(Metal)
        XCTAssertFalse(available) // Not initialised yet
        #else
        XCTAssertFalse(available)
        #endif
    }

    func testTimelineSignalling() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let v0 = await pipeline.currentTimelineValue()
        let v1 = await pipeline.signalTimeline()
        let v2 = await pipeline.signalTimeline()
        #if canImport(Metal)
        XCTAssertEqual(v0, 0)
        XCTAssertEqual(v1, 1)
        XCTAssertEqual(v2, 2)
        #else
        XCTAssertEqual(v0, 0)
        XCTAssertEqual(v1, 0)
        XCTAssertEqual(v2, 0)
        #endif
    }

    // MARK: - Profiling Tests

    func testProfilingEventRecording() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let initial = await pipeline.allProfilingEvents()
        XCTAssertTrue(initial.isEmpty)

        let event = J2KMetalProfilingEvent(
            name: "test_kernel", startTime: 0, endTime: 100,
            duration: 0.001, threadgroupSize: 256, gridSize: 1024,
            isAsync: false
        )
        await pipeline.recordEvent(event)
        let events = await pipeline.allProfilingEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "test_kernel")
    }

    func testProfilingEventClear() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let event = J2KMetalProfilingEvent(
            name: "a", startTime: 0, endTime: 1,
            duration: 0.001, threadgroupSize: 64, gridSize: 256,
            isAsync: false
        )
        await pipeline.recordEvent(event)
        await pipeline.clearProfilingEvents()
        let remaining = await pipeline.allProfilingEvents()
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Occupancy Analysis Tests

    func testOccupancyAnalysis() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let analysis = await pipeline.analyseOccupancy(
            shaderName: "dwt_forward",
            threadgroupSize: 256,
            registersPerThread: 32,
            threadgroupMemory: 4096
        )
        XCTAssertEqual(analysis.shaderName, "dwt_forward")
        XCTAssertGreaterThan(analysis.estimatedOccupancy, 0)
        XCTAssertLessThanOrEqual(analysis.estimatedOccupancy, 1.0)
        XCTAssertGreaterThan(analysis.recommendedMaxThreads, 0)
    }

    func testOccupancyAnalysisCaching() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let a1 = await pipeline.analyseOccupancy(
            shaderName: "cached_shader", threadgroupSize: 256
        )
        let a2 = await pipeline.analyseOccupancy(
            shaderName: "cached_shader", threadgroupSize: 512
        )
        // Second call should return cached result
        XCTAssertEqual(a1.optimalThreadgroupSize, a2.optimalThreadgroupSize)
    }

    func testOccupancyCacheClear() async {
        let pipeline = J2KMetalShaderPipelineManager()
        _ = await pipeline.analyseOccupancy(
            shaderName: "test", threadgroupSize: 256
        )
        await pipeline.clearOccupancyCache()
        // Should compute fresh analysis after clear
        let fresh = await pipeline.analyseOccupancy(
            shaderName: "test", threadgroupSize: 256
        )
        XCTAssertEqual(fresh.shaderName, "test")
    }

    func testOccupancyHighRegisterPressure() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let analysis = await pipeline.analyseOccupancy(
            shaderName: "heavy_shader",
            threadgroupSize: 512,
            registersPerThread: 128
        )
        // High register pressure → smaller recommended threadgroup
        XCTAssertLessThanOrEqual(analysis.recommendedMaxThreads, 256)
    }

    // MARK: - Threadgroup Memory Layout Tests

    func testThreadgroupMemoryLayout() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let layout = await pipeline.optimalThreadgroupMemoryLayout(
            tileWidth: 256, bitDepth: .depth32
        )
        XCTAssertGreaterThan(layout.size, 0)
        XCTAssertEqual(layout.alignment, 16)
        XCTAssertGreaterThanOrEqual(layout.rowPadding, 0)
    }

    func testThreadgroupMemoryLayoutSmall() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let layout = await pipeline.optimalThreadgroupMemoryLayout(
            tileWidth: 32, bitDepth: .depth8
        )
        XCTAssertGreaterThanOrEqual(layout.size, 32)
    }

    // MARK: - Bottleneck Analysis Tests

    func testBottleneckAnalysisBandwidthBound() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let analysis = await pipeline.analyseBottleneck(
            bytesRead: 400_000_000_000, // 400 GB
            bytesWritten: 400_000_000_000,
            operations: 1000,
            duration: 1.0
        )
        XCTAssertEqual(analysis.bottleneck, .bandwidthBound)
        XCTAssertGreaterThan(analysis.bandwidthUtilisation, 0)
    }

    func testBottleneckAnalysisALUBound() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let analysis = await pipeline.analyseBottleneck(
            bytesRead: 1000,
            bytesWritten: 1000,
            operations: 10_000_000_000_000, // 10 TFLOPS
            duration: 1.0
        )
        XCTAssertEqual(analysis.bottleneck, .aluBound)
        XCTAssertGreaterThan(analysis.aluUtilisation, 0)
    }

    func testBottleneckAnalysisZeroDuration() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let analysis = await pipeline.analyseBottleneck(
            bytesRead: 1000, bytesWritten: 1000,
            operations: 1000, duration: 0
        )
        XCTAssertEqual(analysis.bottleneck, .latencyBound)
    }

    func testBottleneckAnalysisBalanced() async {
        let pipeline = J2KMetalShaderPipelineManager()
        // Moderate both ALU and bandwidth
        let analysis = await pipeline.analyseBottleneck(
            bytesRead: 100_000_000_000,
            bytesWritten: 100_000_000_000,
            operations: 5_000_000_000_000,
            duration: 1.0
        )
        XCTAssertFalse(analysis.recommendations.isEmpty)
    }

    // MARK: - Multi-GPU Tests

    func testAvailableDevices() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let devices = await pipeline.availableDevices()
        #if canImport(Metal)
        _ = devices // May or may not have GPUs in CI
        #else
        XCTAssertTrue(devices.isEmpty)
        #endif
    }

    func testCurrentDeviceNameBeforeInit() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let name = await pipeline.currentDeviceName()
        #if canImport(Metal)
        XCTAssertEqual(name, "unavailable") // Not initialised
        #else
        XCTAssertEqual(name, "unavailable")
        #endif
    }

    // MARK: - Metal 3 Feature Detection Tests

    func testMetal3FeatureDetection() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let features = await pipeline.detectMetal3Features()
        #if canImport(Metal)
        _ = features.anyAvailable
        #else
        XCTAssertFalse(features.anyAvailable)
        #endif
    }

    // MARK: - Tile-Pipelined Encode Tests

    func testTilePipelinedEncodeEmpty() async throws {
        let pipeline = J2KMetalShaderPipelineManager()
        let count = try await pipeline.tilePipelinedEncode(
            tiles: [],
            prepareTile: { _ in [] },
            processTile: { _, _ in }
        )
        XCTAssertEqual(count, 0)
    }

    func testTilePipelinedEncode() async throws {
        let pipeline = J2KMetalShaderPipelineManager()
        let tiles = [
            J2KMetalTileDescriptor(tileX: 0, tileY: 0, originX: 0, originY: 0, width: 64, height: 64),
            J2KMetalTileDescriptor(tileX: 1, tileY: 0, originX: 64, originY: 0, width: 64, height: 64),
            J2KMetalTileDescriptor(tileX: 0, tileY: 1, originX: 0, originY: 64, width: 64, height: 64),
        ]

        let processedCount = Mutex<Int>(0)
        let count = try await pipeline.tilePipelinedEncode(
            tiles: tiles,
            prepareTile: { tile in
                [Float](repeating: Float(tile.tileX), count: tile.width * tile.height)
            },
            processTile: { tile, data in
                processedCount.withLock { $0 += 1 }
            }
        )
        XCTAssertEqual(count, 3)
        XCTAssertEqual(processedCount.withLock { $0 }, 3)
    }

    // MARK: - Benchmark Tests

    func testBenchmarkDWT() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let result = await pipeline.benchmarkDWT(dataSize: 10000)
        XCTAssertGreaterThan(result.cpuTime, 0)
        XCTAssertGreaterThan(result.gpuEstimate, 0)
        XCTAssertGreaterThan(result.speedup, 0)
    }

    func testEstimateBandwidth() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let bw = await pipeline.estimateBandwidth(
            tileCount: 16, tileSize: 1_000_000, duration: 0.001
        )
        XCTAssertGreaterThan(bw, 0)
    }

    func testEstimateBandwidthZeroDuration() async {
        let pipeline = J2KMetalShaderPipelineManager()
        let bw = await pipeline.estimateBandwidth(
            tileCount: 16, tileSize: 1_000_000, duration: 0
        )
        XCTAssertEqual(bw, 0)
    }
}
