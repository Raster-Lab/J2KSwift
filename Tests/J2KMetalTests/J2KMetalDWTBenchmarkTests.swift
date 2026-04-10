//
// J2KMetalDWTBenchmarkTests.swift
// J2KSwift
//
// Benchmarks comparing Metal GPU vs CPU DWT performance across all modes.
//

import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Benchmarks Metal GPU vs CPU DWT for all filter modes and image sizes.
final class J2KMetalDWTBenchmarkTests: XCTestCase {

    private func makeData(width: Int, height: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let fx = Float(x) / Float(width)
                let fy = Float(y) / Float(height)
                data[y * width + x] = 128.0 + 64.0 * sin(fx * .pi * 8) + 32.0 * cos(fy * .pi * 6)
            }
        }
        return data
    }

    // MARK: - Forward 2D CDF 9/7

    func testBench97_64() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 64, height: 64)
        _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<10 { _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<10 { _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 10_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 10_000_000.0
        print("[9/7 64x64] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench97_128() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 128, height: 128)
        _ = try await dwt.forward2D(data: data, width: 128, height: 128, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 128, height: 128, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<5 { _ = try await dwt.forward2D(data: data, width: 128, height: 128, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<5 { _ = try await dwt.forward2D(data: data, width: 128, height: 128, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 5_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 5_000_000.0
        print("[9/7 128x128] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench97_256() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 256, height: 256)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 3_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 3_000_000.0
        print("[9/7 256x256] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench97_512() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 512, height: 512)
        _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 2_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 2_000_000.0
        print("[9/7 512x512] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench97_1024() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 1024, height: 1024)
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .gpu)
        let cs = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .cpu)
        let cm = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .gpu)
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 1_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 1_000_000.0
        print("[9/7 1024x1024] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench97_2048() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 2048, height: 2048)
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .gpu)
        let cs = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .cpu)
        let cm = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .gpu)
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 1_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 1_000_000.0
        print("[9/7 2048x2048] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    // MARK: - Forward 2D Le Gall 5/3

    func testBench53_64() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 64, height: 64)
        _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<10 { _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<10 { _ = try await dwt.forward2D(data: data, width: 64, height: 64, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 10_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 10_000_000.0
        print("[5/3 64x64] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench53_256() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 256, height: 256)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 3_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 3_000_000.0
        print("[5/3 256x256] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench53_512() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 512, height: 512)
        _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 2_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 2_000_000.0
        print("[5/3 512x512] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench53_1024() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 1024, height: 1024)
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .gpu)
        let cs = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .cpu)
        let cm = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 1024, height: 1024, backend: .gpu)
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 1_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 1_000_000.0
        print("[5/3 1024x1024] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBench53_2048() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 2048, height: 2048)
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .cpu)
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .gpu)
        let cs = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .cpu)
        let cm = DispatchTime.now()
        _ = try await dwt.forward2D(data: data, width: 2048, height: 2048, backend: .gpu)
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 1_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 1_000_000.0
        print("[5/3 2048x2048] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    // MARK: - Multi-Level 9/7

    func testBenchMultiLevel97_256() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, decompositionLevels: 3, gpuThreshold: 0))
        let data = makeData(width: 256, height: 256)
        _ = try await dwt.forwardMultiLevel(data: data, width: 256, height: 256, levels: 3, backend: .cpu)
        _ = try await dwt.forwardMultiLevel(data: data, width: 256, height: 256, levels: 3, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forwardMultiLevel(data: data, width: 256, height: 256, levels: 3, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<3 { _ = try await dwt.forwardMultiLevel(data: data, width: 256, height: 256, levels: 3, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 3_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 3_000_000.0
        print("[ML 9/7 256x256 L3] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBenchMultiLevel97_512() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, decompositionLevels: 5, gpuThreshold: 0))
        let data = makeData(width: 512, height: 512)
        _ = try await dwt.forwardMultiLevel(data: data, width: 512, height: 512, levels: 5, backend: .cpu)
        _ = try await dwt.forwardMultiLevel(data: data, width: 512, height: 512, levels: 5, backend: .gpu)
        let cs = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forwardMultiLevel(data: data, width: 512, height: 512, levels: 5, backend: .cpu) }
        let cm = DispatchTime.now()
        for _ in 0..<2 { _ = try await dwt.forwardMultiLevel(data: data, width: 512, height: 512, levels: 5, backend: .gpu) }
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 2_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 2_000_000.0
        print("[ML 9/7 512x512 L5] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    func testBenchMultiLevel97_1024() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, decompositionLevels: 5, gpuThreshold: 0))
        let data = makeData(width: 1024, height: 1024)
        _ = try await dwt.forwardMultiLevel(data: data, width: 1024, height: 1024, levels: 5, backend: .cpu)
        _ = try await dwt.forwardMultiLevel(data: data, width: 1024, height: 1024, levels: 5, backend: .gpu)
        let cs = DispatchTime.now()
        _ = try await dwt.forwardMultiLevel(data: data, width: 1024, height: 1024, levels: 5, backend: .cpu)
        let cm = DispatchTime.now()
        _ = try await dwt.forwardMultiLevel(data: data, width: 1024, height: 1024, levels: 5, backend: .gpu)
        let gm = DispatchTime.now()
        let cpuMs = Double(cm.uptimeNanoseconds - cs.uptimeNanoseconds) / 1_000_000.0
        let gpuMs = Double(gm.uptimeNanoseconds - cm.uptimeNanoseconds) / 1_000_000.0
        print("[ML 9/7 1024x1024 L5] CPU: \(String(format: "%.3f", cpuMs))ms  GPU: \(String(format: "%.3f", gpuMs))ms  Speedup: \(String(format: "%.2f", cpuMs/gpuMs))x")
    }

    // MARK: - Roundtrip Correctness

    func testCorrectness97() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 512, height: 512)

        let cpuSub = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu)
        let gpuSub = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu)
        let cpuRecon = try await dwt.inverse2D(subbands: cpuSub, backend: .cpu)
        let gpuRecon = try await dwt.inverse2D(subbands: gpuSub, backend: .gpu)

        var maxErr: Float = 0
        for i in 0..<min(cpuSub.ll.count, gpuSub.ll.count) {
            maxErr = max(maxErr, abs(cpuSub.ll[i] - gpuSub.ll[i]))
        }
        var cpuRT: Float = 0
        for i in 0..<data.count { cpuRT = max(cpuRT, abs(data[i] - cpuRecon[i])) }
        var gpuRT: Float = 0
        for i in 0..<data.count { gpuRT = max(gpuRT, abs(data[i] - gpuRecon[i])) }

        print("[9/7 Correctness] CPU-GPU max: \(maxErr), CPU-RT: \(cpuRT), GPU-RT: \(gpuRT)")
        XCTAssertLessThan(maxErr, 1e-3)
    }

    func testCorrectness53() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .reversible53, gpuThreshold: 0))
        let data = makeData(width: 512, height: 512)

        let cpuSub = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu)
        let gpuSub = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu)
        let cpuRecon = try await dwt.inverse2D(subbands: cpuSub, backend: .cpu)
        let gpuRecon = try await dwt.inverse2D(subbands: gpuSub, backend: .gpu)

        var maxErr: Float = 0
        for i in 0..<min(cpuSub.ll.count, gpuSub.ll.count) {
            maxErr = max(maxErr, abs(cpuSub.ll[i] - gpuSub.ll[i]))
        }
        var cpuRT: Float = 0
        for i in 0..<data.count { cpuRT = max(cpuRT, abs(data[i] - cpuRecon[i])) }
        var gpuRT: Float = 0
        for i in 0..<data.count { gpuRT = max(gpuRT, abs(data[i] - gpuRecon[i])) }

        print("[5/3 Correctness] CPU-GPU max: \(maxErr), CPU-RT: \(cpuRT), GPU-RT: \(gpuRT)")
        XCTAssertLessThan(maxErr, 1e-3)
    }

    // MARK: - Statistics

    func testStatistics() async throws {
        guard J2KMetalDWT.isAvailable else { throw XCTSkip("Metal not available") }
        let dwt = J2KMetalDWT(configuration: .init(filter: .irreversible97, gpuThreshold: 0))
        let data = makeData(width: 256, height: 256)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .gpu)
        _ = try await dwt.forward2D(data: data, width: 256, height: 256, backend: .cpu)
        let stats = await dwt.statistics()
        print("[Stats] total=\(stats.totalOperations) gpu=\(stats.gpuOperations) cpu=\(stats.cpuOperations) util=\(String(format: "%.0f%%", stats.gpuUtilization * 100)) mem=\(stats.peakGPUMemory / 1024)KB")
        XCTAssertEqual(stats.totalOperations, 2)
    }
}
