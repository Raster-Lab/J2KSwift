// GPUvsCPUBenchmark.swift
//
// In-process GPU vs CPU encode/decode wall comparison for the medical
// corpus, run under v7.1.1's default routing on both axes:
//
//   - GPU on  : `_gpuInverse53Enabled = true` + `_gpuHTEntropyEnabled = true`
//                (the production default — what every J2KSwift caller
//                gets out of the box).
//   - CPU only: both flags false (forces every stage onto the CPU
//                path, regardless of fixture size).
//
// Captures encode + decode wall-time (median of N) and prints a
// table that the cross-codec report can quote directly. Used to
// confirm the optimal CLI / library setting for v7.1.1+.
//
// Single-tile codestreams only (matching the CLI default).

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class GPUvsCPUBenchmark: XCTestCase {

    private struct Fixture {
        let label: String
        let path: String
    }

    private func pgmRoot() -> String {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec").path
        return FileManager.default.fileExists(atPath: here)
            ? here : "Tests/Fixtures/CrossCodec"
    }

    private func fixtures() -> [Fixture] {
        let root = pgmRoot()
        return [
            Fixture(label: "MR-small_180x180",   path: "\(root)/mr_study_002_instance_000100.pgm"),
            Fixture(label: "CT_512x512",         path: "\(root)/ct_study_001_instance_000001.pgm"),
            Fixture(label: "MR_886x886",         path: "\(root)/mr_study_001_instance_000001.pgm"),
            Fixture(label: "XA_1024x1024",       path: "\(root)/xa_study_001_instance_000001.pgm"),
            Fixture(label: "PX_2459x1316",       path: "\(root)/px_study_001_instance_000001.pgm"),
            Fixture(label: "DX_2800x2288",       path: "\(root)/dx_study_002_instance_000001.pgm"),
        ]
    }

    private func loadPGM16(_ path: String) throws -> (Int, Int, Data) {
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        var idx = 0
        func token() -> String {
            while idx < raw.count {
                let b = raw[idx]
                if b == 0x23 { while idx < raw.count && raw[idx] != 0x0A { idx += 1 } }
                else if [0x20, 0x09, 0x0A, 0x0D].contains(b) { idx += 1 }
                else { break }
            }
            let s = idx
            while idx < raw.count {
                let b = raw[idx]
                if [0x20, 0x09, 0x0A, 0x0D].contains(b) { break }
                idx += 1
            }
            return String(data: raw.subdata(in: s..<idx), encoding: .ascii) ?? ""
        }
        let _ = token()  // P5
        let w = Int(token())!
        let h = Int(token())!
        let _ = token()  // maxval
        idx += 1
        return (w, h, raw.subdata(in: idx..<(idx + w * h * 2)))
    }

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            tileSize: (0, 0),
            bitrateMode: .lossless,
            maxThreads: 8,
            useHTJ2K: true,
            useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
    }

    private func image(_ w: Int, _ h: Int, _ data: Data) -> J2KImage {
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: w, height: h,
            subsamplingX: 1, subsamplingY: 1,
            data: data,
            sampleByteOrder: .bigEndian)
        return J2KImage(width: w, height: h, components: [comp],
                        tileWidth: 0, tileHeight: 0)
    }

    private struct Sample {
        let encMs: Double
        let decMs: Double
    }

    /// Run encode + decode `runs` times under the supplied flag state
    /// and return the median (encode_ms, decode_ms) in milliseconds.
    private func benchOne(
        _ fix: Fixture,
        gpuEntropy: Bool,
        gpuIDWT: Bool,
        runs: Int
    ) async throws -> Sample {
        // Save + restore the four global routing flags so a failure
        // in this test never bleeds into the rest of the suite.
        let prevEntropy = DecoderPipeline._gpuHTEntropyEnabled
        let prevIDWT = DecoderPipeline._gpuInverse53Enabled
        defer {
            DecoderPipeline._gpuHTEntropyEnabled = prevEntropy
            DecoderPipeline._gpuInverse53Enabled = prevIDWT
        }
        DecoderPipeline._gpuHTEntropyEnabled = gpuEntropy
        DecoderPipeline._gpuInverse53Enabled = gpuIDWT

        let (w, h, samples) = try loadPGM16(fix.path)
        let img = image(w, h, samples)
        let cfg = htConfig()
        let enc = J2KEncoder(encodingConfiguration: cfg)
        let dec = J2KDecoder()

        // Warm-up.
        let warm = try await enc.encode(img)
        _ = try await dec.decode(warm)

        var encMs: [Double] = []
        var decMs: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            let bytes = try await enc.encode(img)
            let t1 = Date().timeIntervalSinceReferenceDate
            encMs.append((t1 - t0) * 1000.0)

            let d0 = Date().timeIntervalSinceReferenceDate
            _ = try await dec.decode(bytes)
            let d1 = Date().timeIntervalSinceReferenceDate
            decMs.append((d1 - d0) * 1000.0)
        }
        encMs.sort(); decMs.sort()
        return Sample(encMs: encMs[runs / 2], decMs: decMs[runs / 2])
    }

    func testGPUvsCPU_SingleTileMedicalCorpus() async throws {
        let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "5") ?? 5
        print("=== v7.1.1 GPU vs CPU in-process benchmark (single-tile, n=\(runs)) ===")
        print("| fixture | shape | px | enc GPU | enc CPU | enc× | dec GPU | dec CPU | dec× | optimal |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|")

        for fix in fixtures() {
            let (w, h, _) = try loadPGM16(fix.path)
            let px = w * h
            let gpu = try await benchOne(fix, gpuEntropy: true, gpuIDWT: true, runs: runs)
            let cpu = try await benchOne(fix, gpuEntropy: false, gpuIDWT: false, runs: runs)

            // Speedup: <1.0 → CPU faster, >1.0 → GPU faster.
            let encX = cpu.encMs / gpu.encMs
            let decX = cpu.decMs / gpu.decMs
            let totalGpu = gpu.encMs + gpu.decMs
            let totalCpu = cpu.encMs + cpu.decMs
            let optimal = totalGpu < totalCpu ? "GPU" : (totalCpu < totalGpu ? "CPU" : "tie")

            print(String(
                format: "| %@ | %dx%d | %d | %.2f | %.2f | %.2f× | %.2f | %.2f | %.2f× | %@ |",
                fix.label, w, h, px,
                gpu.encMs, cpu.encMs, encX,
                gpu.decMs, cpu.decMs, decX,
                optimal))
        }
    }

    /// Multi-tile (2x2) where the v7.1.1 GPU multi-tile-per-tile path
    /// can actually win — DX 2x2 puts ~1.6 MP per tile, well above the
    /// 1 MP per-tile gate. PX 2x2 puts ~810 K per tile (below gate; CPU
    /// fallback). MR 2x2 puts ~200 K per tile (below gate).
    /// Use this to show readers that GPU vs CPU isn't a wash on every
    /// path — there's a real ≥30% decode win on the multi-tile per-tile
    /// path with big enough per-tile sizes.
    func testGPUvsCPU_MultiTile2x2_DX_PX() async throws {
        let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "5") ?? 5
        print("=== v7.1.1 GPU vs CPU multi-tile 2x2 in-process (n=\(runs)) ===")
        print("| fixture | shape | px/tile | enc GPU | enc CPU | enc× | dec GPU | dec CPU | dec× | optimal |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|")

        let dx = Fixture(label: "DX_2800x2288",
                         path: "\(pgmRoot())/dx_study_002_instance_000001.pgm")
        let px = Fixture(label: "PX_2459x1316",
                         path: "\(pgmRoot())/px_study_001_instance_000001.pgm")

        for fix in [dx, px] {
            let (w, h, _) = try loadPGM16(fix.path)
            let tileW = (w + 1) / 2
            let tileH = (h + 1) / 2
            let pxPerTile = tileW * tileH
            let gpu = try await benchMultiTile(
                fix, tileW: tileW, tileH: tileH,
                gpuEntropy: true, gpuIDWT: true, runs: runs)
            let cpu = try await benchMultiTile(
                fix, tileW: tileW, tileH: tileH,
                gpuEntropy: false, gpuIDWT: false, runs: runs)
            let encX = cpu.encMs / gpu.encMs
            let decX = cpu.decMs / gpu.decMs
            let optimal = (gpu.encMs + gpu.decMs) < (cpu.encMs + cpu.decMs) ? "GPU" : "CPU"
            print(String(
                format: "| %@ 2x2 | %dx%d | %d | %.2f | %.2f | %.2f× | %.2f | %.2f | %.2f× | %@ |",
                fix.label, w, h, pxPerTile,
                gpu.encMs, cpu.encMs, encX,
                gpu.decMs, cpu.decMs, decX, optimal))
        }
    }

    private func benchMultiTile(
        _ fix: Fixture,
        tileW: Int, tileH: Int,
        gpuEntropy: Bool,
        gpuIDWT: Bool,
        runs: Int
    ) async throws -> Sample {
        let prevEntropy = DecoderPipeline._gpuHTEntropyEnabled
        let prevIDWT = DecoderPipeline._gpuInverse53Enabled
        defer {
            DecoderPipeline._gpuHTEntropyEnabled = prevEntropy
            DecoderPipeline._gpuInverse53Enabled = prevIDWT
        }
        DecoderPipeline._gpuHTEntropyEnabled = gpuEntropy
        DecoderPipeline._gpuInverse53Enabled = gpuIDWT

        let (w, h, samples) = try loadPGM16(fix.path)
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: w, height: h, subsamplingX: 1, subsamplingY: 1,
            data: samples, sampleByteOrder: .bigEndian)
        let img = J2KImage(width: w, height: h, components: [comp],
                           tileWidth: tileW, tileHeight: tileH)
        var cfg = htConfig()
        cfg.tileSize = (tileW, tileH)
        let enc = J2KEncoder(encodingConfiguration: cfg)
        let dec = J2KDecoder()

        let warm = try await enc.encode(img)
        _ = try await dec.decode(warm)

        var encMs: [Double] = []
        var decMs: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            let bytes = try await enc.encode(img)
            let t1 = Date().timeIntervalSinceReferenceDate
            encMs.append((t1 - t0) * 1000.0)

            let d0 = Date().timeIntervalSinceReferenceDate
            _ = try await dec.decode(bytes)
            let d1 = Date().timeIntervalSinceReferenceDate
            decMs.append((d1 - d0) * 1000.0)
        }
        encMs.sort(); decMs.sort()
        return Sample(encMs: encMs[runs / 2], decMs: decMs[runs / 2])
    }
}
