// v9.8 calibration — gather (pixel stats, converged qstep) pairs for
// the corpus fixtures. Output feeds image-statistics-based initial
// qstep prediction (the v9.7 close-as-research successor).
//
// Methodology:
//   1. Load each PGM fixture.
//   2. Compute pixel statistics on the dc-shifted Int32 component:
//      max_abs, abs_mean, std_dev, sqrt(L2) = energy per pixel.
//   3. Encode at .constantBitrate (auto-promoted strict-bounded). Use
//      a fresh per-call cache to force the search to run from cold.
//   4. Read `J2KEncodeQstepStats` via the public stats-returning API
//      to get the converged qstep.
//   5. Print a single CSV row per fixture so the v9.8 predictor
//      formula can be regressed offline.

import XCTest
import Darwin
@testable import J2KCodec
import J2KCore

final class V98QstepCalibrationTests: XCTestCase {

    private struct Fixture {
        let name: String
        let filename: String
    }

    private static let fixtures: [Fixture] = [
        Fixture(name: "mr_002", filename: "mr_study_002_instance_000100.pgm"),
        Fixture(name: "ct_001", filename: "ct_study_001_instance_000001.pgm"),
        Fixture(name: "ct_003", filename: "ct_study_003_instance_000050.pgm"),
        Fixture(name: "mr_001", filename: "mr_study_001_instance_000001.pgm"),
        Fixture(name: "xa_001", filename: "xa_study_001_instance_000001.pgm"),
        Fixture(name: "px_001", filename: "px_study_001_instance_000001.pgm"),
        Fixture(name: "dx_002", filename: "dx_study_002_instance_000001.pgm"),
    ]

    private static let packageRoot: URL = {
        var url = URL(fileURLWithPath: #file)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }()

    private func loadPGM(_ filename: String) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            print("V98_CAL_SKIP missing fixture: \(fixture.path)")
            return nil
        }
        let data = try Data(contentsOf: fixture)
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])
    }

    /// Compute pixel statistics on the dc-shifted Int32 component.
    /// Includes a "neighbor diff" texture metric that captures
    /// high-frequency content — the dominant driver of post-DWT
    /// coefficient magnitudes, and therefore of the converged qstep.
    private func computeStats(image: J2KImage)
        -> (maxAbs: Int, absMean: Double, stdDev: Double,
            absDiffH: Double, absDiffV: Double)
    {
        guard let comp = image.components.first else {
            return (0, 0, 0, 0, 0)
        }
        let dcOffset = (1 << (comp.bitDepth - 1))
        let w = comp.width
        let h = comp.height
        let count = w * h
        var maxAbs: Int = 0
        var sumAbs: Int64 = 0
        var sumSq: Int64 = 0
        var sumAbsDiffH: Int64 = 0
        var sumAbsDiffV: Int64 = 0
        var hPairs: Int64 = 0
        var vPairs: Int64 = 0
        comp.data.withUnsafeBytes { raw -> Void in
            let bytes = raw.bindMemory(to: UInt8.self)
            func pixel(_ i: Int) -> Int {
                let hi = Int(bytes[i * 2])
                let lo = Int(bytes[i * 2 + 1])
                return ((hi << 8) | lo) - dcOffset
            }
            for y in 0..<h {
                for x in 0..<w {
                    let idx = y * w + x
                    let v = pixel(idx)
                    let av = v < 0 ? -v : v
                    if av > maxAbs { maxAbs = av }
                    sumAbs += Int64(av)
                    sumSq += Int64(v) * Int64(v)
                    if x + 1 < w {
                        let r = pixel(idx + 1)
                        sumAbsDiffH += Int64(abs(r - v))
                        hPairs += 1
                    }
                    if y + 1 < h {
                        let d = pixel(idx + w)
                        sumAbsDiffV += Int64(abs(d - v))
                        vPairs += 1
                    }
                }
            }
        }
        let n = Double(count)
        let absMean = Double(sumAbs) / n
        let variance = Double(sumSq) / n  // mean ≈ 0 after dc-shift
        let stdDev = variance > 0 ? variance.squareRoot() : 0
        let absDiffH = hPairs > 0 ? Double(sumAbsDiffH) / Double(hPairs) : 0
        let absDiffV = vPairs > 0 ? Double(sumAbsDiffV) / Double(vPairs) : 0
        return (maxAbs, absMean, stdDev, absDiffH, absDiffV)
    }

    /// Stats-only calibration — no encoding, just print pixel
    /// statistics. Cheap and avoids any encoder-side instability.
    func testStatsOnly() async throws {
        print("V98_STATS_HEADER name,pixels,width,height,max_abs,abs_mean,std_dev,absDiffH,absDiffV")
        for fx in Self.fixtures {
            guard let img = try loadPGM(fx.filename) else { continue }
            let stats = computeStats(image: img)
            let pixels = img.width * img.height
            print("V98_STATS_ROW \(fx.name),\(pixels),\(img.width),\(img.height),\(stats.maxAbs),\(String(format: "%.2f", stats.absMean)),\(String(format: "%.2f", stats.stdDev)),\(String(format: "%.2f", stats.absDiffH)),\(String(format: "%.2f", stats.absDiffV))")
        }
    }

    /// Calibration sweep — prints (stats, target_bpp, converged_qstep)
    /// per fixture × bpp.  Used to regress the v9.8 initial-qstep
    /// formula offline.
    func testCalibrationSweep() async throws {
        let bpps: [Double] = [0.5, 1.0, 2.0, 4.0]
        print("V98_CAL_HEADER name,pixels,max_abs,abs_mean,std_dev,target_bpp,converged_qstep,achieved_bpp,iterations")
        for fx in Self.fixtures {
            guard let img = try loadPGM(fx.filename) else { continue }
            let stats = computeStats(image: img)
            let pixels = img.width * img.height
            for bpp in bpps {
                var cfg = J2KEncodingConfiguration(
                    quality: 1.0, lossless: false,
                    decompositionLevels: 5, qualityLayers: 1,
                    progressionOrder: .lrcp, useHTJ2K: true,
                    useReversibleFilter: false,
                    htj2kBlockFormat: .conformant)
                cfg.bitrateMode = .constantBitrateViaQstep(
                    bitsPerPixel: bpp, tolerance: 0.05, maxIterations: 8)
                cfg.qstepCache = J2KQstepCache()  // fresh per-call
                let enc = J2KEncoder(encodingConfiguration: cfg)
                do {
                    let r = try await enc.encodeWithQstepStats(img)
                    print("V98_CAL_ROW \(fx.name),\(pixels),\(stats.maxAbs),\(String(format: "%.2f", stats.absMean)),\(String(format: "%.2f", stats.stdDev)),\(bpp),\(String(format: "%.4g", r.stats.convergedQstep)),\(String(format: "%.4f", r.stats.achievedBpp)),\(r.stats.iterations)")
                } catch {
                    print("V98_CAL_ERR \(fx.name),bpp=\(bpp),error=\(error)")
                }
            }
        }
    }
}
