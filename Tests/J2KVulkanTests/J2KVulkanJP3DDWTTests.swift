// J2KVulkanJP3DDWTTests.swift
// J2KSwift
//
// Tests for Phase 19 Vulkan-accelerated 3D DWT (JP3D multi-spectral).

import XCTest
@testable import J2KVulkan

final class J2KVulkanJP3DDWTTests: XCTestCase {

    // MARK: - J2KVulkanJP3DDWTConfiguration

    func testDefaultConfiguration() {
        let config = J2KVulkanJP3DDWTConfiguration.default
        XCTAssertEqual(config.decompositionLevels, 3)
        XCTAssertTrue(config.enableSpectralAxis)
        XCTAssertEqual(config.gpuThreshold, 4096)
        if case .irreversible97 = config.filter { } else {
            XCTFail("Default filter should be .irreversible97")
        }
    }

    func testLosslessConfiguration() {
        let config = J2KVulkanJP3DDWTConfiguration.lossless
        if case .reversible53 = config.filter { } else {
            XCTFail("Lossless filter should be .reversible53")
        }
        XCTAssertEqual(config.decompositionLevels, 3)
        XCTAssertTrue(config.enableSpectralAxis)
    }

    func testConfigurationDecompositionLevelsClamped() {
        let config = J2KVulkanJP3DDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 0,
            enableSpectralAxis: false,
            gpuThreshold: 1024
        )
        XCTAssertEqual(config.decompositionLevels, 1)
    }

    func testConfigurationGPUThresholdClamped() {
        let config = J2KVulkanJP3DDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 3,
            enableSpectralAxis: true,
            gpuThreshold: 0
        )
        XCTAssertEqual(config.gpuThreshold, 1)
    }

    // MARK: - J2KVulkanJP3DDWTStatistics

    func testStatisticsGPUUtilisationRatioZeroWhenNoTransforms() {
        let stats = J2KVulkanJP3DDWTStatistics(
            totalTransforms: 0,
            gpuTransforms: 0,
            cpuTransforms: 0,
            averageProcessingTimeMs: 0.0
        )
        XCTAssertEqual(stats.gpuUtilisationRatio, 0.0)
    }

    func testStatisticsGPUUtilisationRatioAllGPU() {
        let stats = J2KVulkanJP3DDWTStatistics(
            totalTransforms: 10,
            gpuTransforms: 10,
            cpuTransforms: 0,
            averageProcessingTimeMs: 5.0
        )
        XCTAssertEqual(stats.gpuUtilisationRatio, 1.0, accuracy: 1e-9)
    }

    func testStatisticsGPUUtilisationRatioMixed() {
        let stats = J2KVulkanJP3DDWTStatistics(
            totalTransforms: 4,
            gpuTransforms: 1,
            cpuTransforms: 3,
            averageProcessingTimeMs: 2.0
        )
        XCTAssertEqual(stats.gpuUtilisationRatio, 0.25, accuracy: 1e-9)
    }

    // MARK: - J2KVulkanJP3DDWT (actor)

    func testActorCreation() async {
        let dwt = J2KVulkanJP3DDWT()
        _ = dwt
    }

    func testForward3DSmallData() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let data = Array(repeating: Float(1.0), count: 2 * 2 * 2 * 1)
        let result = try await dwt.forward3D(
            data, width: 2, height: 2, depth: 2, spectralBands: 1,
            configuration: .default
        )
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.depth, 2)
        XCTAssertEqual(result.spectralBands, 1)
        XCTAssertEqual(result.decompositionLevels, 3)
        XCTAssertFalse(result.subbands3D.isEmpty)
        XCTAssertGreaterThanOrEqual(result.processingTimeMs, 0.0)
    }

    func testForward3DMismatchedDataCountThrows() async {
        let dwt = J2KVulkanJP3DDWT()
        let data = Array(repeating: Float(1.0), count: 5)
        do {
            _ = try await dwt.forward3D(
                data, width: 2, height: 2, depth: 2, spectralBands: 1,
                configuration: .default
            )
            XCTFail("Expected error was not thrown")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testInverse3DRoundTrip() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let original = (0..<8).map { Float($0) / 7.0 }
        let result = try await dwt.forward3D(
            original, width: 2, height: 2, depth: 2, spectralBands: 1,
            configuration: .lossless
        )
        let reconstructed = try await dwt.inverse3D(result)
        XCTAssertFalse(reconstructed.isEmpty)
    }

    func testStatisticsAfterTransform() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let data = Array(repeating: Float(0.5), count: 2 * 2 * 2 * 1)
        _ = try await dwt.forward3D(
            data, width: 2, height: 2, depth: 2, spectralBands: 1,
            configuration: .default
        )
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalTransforms, 1)
        XCTAssertEqual(stats.gpuTransforms + stats.cpuTransforms, 1)
    }

    func testResetStatistics() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let data = Array(repeating: Float(0.5), count: 2 * 2 * 2 * 1)
        _ = try await dwt.forward3D(
            data, width: 2, height: 2, depth: 2, spectralBands: 1,
            configuration: .default
        )
        await dwt.resetStatistics()
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalTransforms, 0)
        XCTAssertEqual(stats.gpuTransforms, 0)
        XCTAssertEqual(stats.cpuTransforms, 0)
        XCTAssertEqual(stats.averageProcessingTimeMs, 0.0)
    }

    func testInverse3DEmptyResultThrows() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let emptyResult = J2KVulkanJP3DDWTResult(
            subbands3D: [],
            width: 2, height: 2, depth: 2, spectralBands: 1,
            decompositionLevels: 3,
            filter: .irreversible97,
            processingTimeMs: 0.0
        )
        do {
            _ = try await dwt.inverse3D(emptyResult)
            XCTFail("Expected error for empty subbands")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testMultipleTransformsAccumulateStatistics() async throws {
        let dwt = J2KVulkanJP3DDWT()
        let data = Array(repeating: Float(0.5), count: 2 * 2 * 2 * 1)
        for _ in 0..<3 {
            _ = try await dwt.forward3D(
                data, width: 2, height: 2, depth: 2, spectralBands: 1,
                configuration: .default
            )
        }
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalTransforms, 3)
    }
}
