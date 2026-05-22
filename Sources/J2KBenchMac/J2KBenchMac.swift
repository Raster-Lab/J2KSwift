//
// J2KBenchMac.swift
// J2KBenchMac — v10.5 cross-silicon arc — macOS counterpart of J2KBenchApp.
//
// Runs the same warm in-process bench the iOS J2KBenchApp does (same
// LCG-synthesised corpus, same lossless HT encoder, same 2 warmup + N
// timed methodology, same canonical JSON schema) so M2 / M4 readings
// drop straight into Documentation/Benchmarks/data/ alongside iPhone /
// iPad readings and feed `Scripts/benchmarks/cross_silicon_compare.py`.
//
// Usage:
//   swift run -c release J2KBenchMac [options]
//
// Options:
//   --runs N           timed runs per fixture (default 7)
//   --warmups N        untimed warmups per fixture (default 2)
//   --quick            small-fixture subset, 3 runs / 1 warmup
//   --output PATH      write the JSON here (default: ./benchmark-results-…)
//   --help, -h         this help
//
// The fixtures + LCG synthesis + encoder config MUST mirror
// `Sources/J2KBenchApp/BenchModel.swift` and `J2KSampleSource.swift`
// — that's what makes the cross-silicon JSONs apples-to-apples.

import Foundation
import J2KCore
import J2KCodec
#if canImport(J2KMetal)
import J2KMetal
#endif

// MARK: - Fixtures (mirrors `BenchModel.corpus`)

struct BenchFixture: Sendable {
    let id: String
    let modality: String
    let width: Int
    let height: Int
    let bitDepth: Int
    let seed: UInt64
    var label: String { "\(modality) \(width)\u{00d7}\(height)" }
}

let corpus: [BenchFixture] = [
    .init(id: "mr_synth_small",  modality: "MR", width: 256,  height: 256,  bitDepth: 16, seed: 1001),
    .init(id: "ct_synth_mid",    modality: "CT", width: 768,  height: 768,  bitDepth: 16, seed: 2002),
    .init(id: "xa_synth_small",  modality: "XA", width: 800,  height: 800,  bitDepth: 16, seed: 3001),
    .init(id: "dx_synth_mid",    modality: "DX", width: 1024, height: 1024, bitDepth: 16, seed: 4001),
    .init(id: "px_synth_mid",    modality: "PX", width: 1024, height: 800,  bitDepth: 16, seed: 5001),
    .init(id: "mg_synth_mid",    modality: "MG", width: 1024, height: 1280, bitDepth: 16, seed: 6001),
    .init(id: "cr_synth_mid",    modality: "CR", width: 1024, height: 1024, bitDepth: 16, seed: 8001),
    .init(id: "dx_002_class",    modality: "DX", width: 2800, height: 2288, bitDepth: 12, seed: 4002),
    .init(id: "dx_001_class",    modality: "DX", width: 2544, height: 3056, bitDepth: 12, seed: 4003),
    .init(id: "mg_001_class",    modality: "MG", width: 3520, height: 4784, bitDepth: 12, seed: 6002),
]

// MARK: - LCG synthesis (mirrors `J2KSampleSource.synthesize`)

func synthesize(_ fixture: BenchFixture) -> J2KImage {
    let n = fixture.width * fixture.height
    let bitDepth = fixture.bitDepth
    let bytesPerSample = (bitDepth + 7) / 8
    precondition(bytesPerSample == 2, "16-bit corpus only")

    let maxVal = (1 << bitDepth) - 1
    var data = Data(count: n * 2)
    var s: UInt64 = fixture.seed &* 6364136223846793005 &+ 1442695040888963407
    data.withUnsafeMutableBytes { rawPtr in
        let buf = rawPtr.bindMemory(to: UInt16.self)
        for i in 0..<n {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let sample = UInt16(Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
            buf[i] = sample.bigEndian
        }
    }
    let comp = J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                            width: fixture.width, height: fixture.height,
                            subsamplingX: 1, subsamplingY: 1,
                            data: data, sampleByteOrder: .bigEndian)
    return J2KImage(width: fixture.width, height: fixture.height,
                    components: [comp])
}

// MARK: - Encoder (mirrors `J2KSampleSource.losslessHTEncoder`)

func losslessHTEncoder() -> J2KEncoder {
    let cfg = J2KEncodingConfiguration(
        quality: 1.0, lossless: true,
        decompositionLevels: 5, qualityLayers: 1,
        progressionOrder: .lrcp, bitrateMode: .lossless,
        maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
        enableParallelCodeBlocks: true,
        htj2kBlockFormat: .conformant)
    return J2KEncoder(encodingConfiguration: cfg)
}

// MARK: - Host info

struct HostSnapshot {
    let brand: String
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let ncpu: Int

    static func capture() -> HostSnapshot {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return HostSnapshot(
            brand: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            modelIdentifier: sysctlString("hw.model") ?? "Unknown",
            systemName: "Darwin",
            systemVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            ncpu: Int(sysctlString("hw.ncpu").flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount))
    }
}

private func sysctlString(_ key: String) -> String? {
    var size: size_t = 0
    sysctlbyname(key, nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    sysctlbyname(key, &buf, &size, nil, 0)
    if let nul = buf.firstIndex(of: 0) { buf.removeLast(buf.count - nul) }
    return String(decoding: buf, as: UTF8.self)
}

// MARK: - Timing samples

struct Samples {
    var values: [Double] = []
    var median: Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
    var minV: Double? { values.min() }
    var maxV: Double? { values.max() }
    var isEmpty: Bool { values.isEmpty }
}

struct FixtureResult {
    let fixture: BenchFixture
    var codestreamBytes: Int = 0
    var encode = Samples()
    var decodeCPU = Samples()
    var decodeGPU = Samples()
    var decodeGPUHT = Samples()
    var error: String?
}

// MARK: - Bench loop

func benchOne(_ fixture: BenchFixture, runs: Int, warmups: Int) async -> FixtureResult {
    var result = FixtureResult(fixture: fixture)
    let image = synthesize(fixture)
    let encoder = losslessHTEncoder()
    var codestream: Data?

    // Encode — warm + timed
    do {
        for _ in 0..<warmups { codestream = try await encoder.encode(image) }
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            codestream = try await encoder.encode(image)
            let t1 = DispatchTime.now().uptimeNanoseconds
            result.encode.values.append(Double(t1 - t0) / 1_000_000.0)
        }
    } catch {
        result.error = "encode: \(error)"
        return result
    }
    guard let cs = codestream else {
        result.error = "encode produced no codestream"
        return result
    }
    result.codestreamBytes = cs.count

    // Decode — three modes, each warm + timed
    do {
        result.decodeCPU = try await timedDecode(cs, mode: .cpu, runs: runs, warmups: warmups)
        result.decodeGPU = try await timedDecode(cs, mode: .gpu, runs: runs, warmups: warmups)
        result.decodeGPUHT = try await timedDecode(cs, mode: .gpuht, runs: runs, warmups: warmups)
    } catch {
        result.error = "decode: \(error)"
    }
    return result
}

enum DecodeMode { case cpu, gpu, gpuht }

func timedDecode(_ data: Data, mode: DecodeMode,
                 runs: Int, warmups: Int) async throws -> Samples {
    let decoder = J2KDecoder()
    for _ in 0..<warmups { _ = try await invoke(decoder, mode: mode, data: data) }
    var s = Samples()
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await invoke(decoder, mode: mode, data: data)
        let t1 = DispatchTime.now().uptimeNanoseconds
        s.values.append(Double(t1 - t0) / 1_000_000.0)
    }
    return s
}

func invoke(_ decoder: J2KDecoder, mode: DecodeMode, data: Data) async throws -> J2KImage {
    switch mode {
    case .cpu:   return try await decoder.decode(data)
    case .gpu:   return try await decoder.decodeGPU(data)
    case .gpuht: return try await decoder.decodeWithGPUHT(data)
    }
}

// MARK: - JSON emit (mirrors `BenchStore.exportData`)

func buildJSON(host: HostSnapshot, j2kVersion: String,
               runs: Int, warmups: Int,
               results: [FixtureResult]) -> Data? {
    func timingDict(_ s: Samples) -> [String: Any] {
        ["samples": s.values,
         "median":  s.median ?? 0,
         "min":     s.minV ?? 0,
         "max":     s.maxV ?? 0]
    }
    func directionMap(_ codecs: [(name: String, pick: (FixtureResult) -> Samples)])
        -> [String: Any] {
        var map: [String: Any] = [:]
        for r in results {
            var perCodec: [String: Any] = [:]
            for c in codecs {
                let s = c.pick(r)
                guard !s.isEmpty else { continue }
                perCodec[c.name] = timingDict(s)
            }
            guard !perCodec.isEmpty else { continue }
            map[r.fixture.id] = [
                "label": r.fixture.label,
                "modality": r.fixture.modality,
                "fixture": r.fixture.id,
                "source": "synthetic",
                "results": perCodec
            ] as [String: Any]
        }
        return map
    }
    let payload: [String: Any] = [
        "host": [
            "machine": "arm64",
            "system":  host.systemName,
            "release": host.systemVersion,
            "brand":   host.brand,
            "model":   host.modelIdentifier,
            "ncpu":    host.ncpu
        ],
        "j2k_version": "J2KSwift version \(j2kVersion)",
        "lane": "inproc",
        "runs": runs, "warmups": warmups,
        "encode": directionMap([
            (name: "J2KSwift+inproc", pick: { $0.encode })
        ]),
        "decode": directionMap([
            (name: "J2KSwift+inproc", pick: { $0.decodeCPU }),
            (name: "J2KSwift+gpu",    pick: { $0.decodeGPU }),
            (name: "J2KSwift+gpuht",  pick: { $0.decodeGPUHT })
        ])
    ]
    return try? JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys])
}

func defaultOutputName(host: HostSnapshot, version: String) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    let c = cal.dateComponents([.year, .month, .day], from: Date())
    let date = String(format: "%04d%02d%02d",
                      c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    let model = host.modelIdentifier
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: " ", with: "")
    return "benchmark-results-\(model)-\(version)-warm-inproc-\(date).json"
}

// MARK: - Entry point

func eprint(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8) ?? Data()) }

func usage() -> String {
    """
    J2KBenchMac — macOS counterpart of the J2KBenchApp warm in-process bench.

      swift run -c release J2KBenchMac [--runs N] [--warmups N] [--quick] [--output PATH]

      --runs N        timed runs per fixture per stage (default 7)
      --warmups N     untimed warmups per stage (default 2)
      --quick         small subset, 3 runs / 1 warmup (sanity check)
      --output PATH   JSON output path (default: ./benchmark-results-<model>-<ver>-warm-inproc-<date>.json)
      --help, -h      this message

    JSON shape matches J2KBenchApp's "Share Selected" export so it drops
    into Documentation/Benchmarks/data/ for cross_silicon_compare.py.
    """
}

@main
struct J2KBenchMac {
    static func main() async {
        var runs = 7
        var warmups = 2
        var quick = false
        var output: String?

        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            let a = args[i]
            switch a {
            case "--runs":
                i += 1
                if i < args.count, let v = Int(args[i]) { runs = v }
            case "--warmups":
                i += 1
                if i < args.count, let v = Int(args[i]) { warmups = v }
            case "--quick":
                quick = true; runs = 3; warmups = 1
            case "--output":
                i += 1
                if i < args.count { output = args[i] }
            case "--help", "-h":
                print(usage()); return
            default:
                eprint("Unknown argument: \(a)\n\n\(usage())"); return
            }
            i += 1
        }

        let host = HostSnapshot.capture()
        let version = getVersion()

        eprint("J2KBenchMac · \(host.brand) (\(host.modelIdentifier)) · "
               + "\(host.systemName) \(host.systemVersion) · "
               + "\(host.ncpu) cores · J2KSwift \(version)")
        eprint("runs=\(runs) warmups=\(warmups)\(quick ? " (quick)" : "")")
        eprint("")

        // Warm the process-shared Metal session once up front so GPU
        // decode lanes don't pay cold-start in the first fixture.
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        let fixtures = quick
            ? corpus.filter { ["mr_synth_small", "ct_synth_mid",
                               "dx_synth_mid", "mg_synth_mid"].contains($0.id) }
            : corpus

        var results: [FixtureResult] = []
        for fixture in fixtures {
            eprint("→ \(fixture.id) \(fixture.label) "
                   + "(\(fixture.width)×\(fixture.height))…")
            let r = await benchOne(fixture, runs: runs, warmups: warmups)
            if let err = r.error {
                eprint("  ! \(err)")
            } else {
                func ms(_ s: Samples) -> String {
                    s.median.map { String(format: "%.2f", $0) } ?? "—"
                }
                eprint("  enc \(ms(r.encode)) ms · "
                       + "dec cpu \(ms(r.decodeCPU)) / gpu \(ms(r.decodeGPU)) / "
                       + "gpuht \(ms(r.decodeGPUHT)) ms · "
                       + "cs \(r.codestreamBytes) B")
            }
            results.append(r)
        }
        eprint("")

        guard let data = buildJSON(host: host, j2kVersion: version,
                                   runs: runs, warmups: warmups,
                                   results: results) else {
            eprint("JSON build failed"); exit(1)
        }
        let path = output ?? defaultOutputName(host: host, version: version)
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            eprint("wrote \(path) (\(data.count) bytes)")
        } catch {
            eprint("write failed: \(error)"); exit(1)
        }
    }
}
