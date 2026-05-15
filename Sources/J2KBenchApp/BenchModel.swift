//
// BenchModel.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Single source of truth for the corpus, per-fixture state, and host
// identity. Designed to be lightweight enough to JSON-encode straight
// to the share-sheet payload that compare_hosts.py consumes.

import Foundation
import J2KCore

#if canImport(UIKit)
import UIKit
#endif

/// One fixture in the canonical synthetic corpus.
struct BenchFixture: Identifiable, Hashable {
    let id: String
    let modality: String
    let width: Int
    let height: Int
    let bitDepth: Int
    let seed: UInt64

    var pixels: Int { width * height }
    var label: String { "\(modality) \(width)\u{00d7}\(height)" }
}

/// Per-run timing samples (median computed lazily).
struct TimingSamples: Codable, Hashable {
    var samples: [Double] = []  // milliseconds

    var median: Double? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        return s[s.count / 2]
    }
    var min: Double? { samples.min() }
    var max: Double? { samples.max() }
}

/// All measurements for one fixture.
struct FixtureResult: Codable, Hashable {
    var fixture: String
    var modality: String
    var width: Int
    var height: Int
    var bitDepth: Int
    var codestreamBytes: Int = 0
    var encode: TimingSamples = TimingSamples()
    var decodeCPU: TimingSamples = TimingSamples()
    var decodeGPU: TimingSamples = TimingSamples()
    var decodeWithGPUHT: TimingSamples = TimingSamples()
    var error: String?
}

/// Coarse run-state for the UI.
enum BenchPhase: Equatable {
    case idle
    case warming(String)
    case encoding(String)
    case decoding(String, String)  // (fixture, mode)
    case done
    case failed(String)
}

@MainActor
final class BenchModel: ObservableObject {

    /// 7 synthetic-corpus fixtures mirroring `cross_codec_warm_bench.py`
    /// (subset chosen to fit in ~5 min on A-series + cover MR/CT/XA/DX/PX/MG
    /// modality spread) PLUS 3 medical-class large fixtures matching the
    /// J2KMedicalCorpusPerformanceTests dimensions where the M2/M4 baseline
    /// gap is largest (DX 2544x3056, MG 3520x4784). On large fixtures the
    /// run is the only datapoint that actually exposes silicon-class
    /// differences, so they are non-optional.
    static let corpus: [BenchFixture] = [
        // Small/mid — fits the canonical-bench corpus
        .init(id: "mr_synth_small",  modality: "MR", width: 256,  height: 256,  bitDepth: 16, seed: 1001),
        .init(id: "ct_synth_mid",    modality: "CT", width: 768,  height: 768,  bitDepth: 16, seed: 2002),
        .init(id: "xa_synth_small",  modality: "XA", width: 800,  height: 800,  bitDepth: 16, seed: 3001),
        .init(id: "dx_synth_mid",    modality: "DX", width: 1024, height: 1024, bitDepth: 16, seed: 4001),
        .init(id: "px_synth_mid",    modality: "PX", width: 1024, height: 800,  bitDepth: 16, seed: 5001),
        .init(id: "mg_synth_mid",    modality: "MG", width: 1024, height: 1280, bitDepth: 16, seed: 6001),
        .init(id: "cr_synth_mid",    modality: "CR", width: 1024, height: 1024, bitDepth: 16, seed: 8001),
        // Medical-class large — these expose the lever ceiling
        .init(id: "dx_002_class",    modality: "DX", width: 2800, height: 2288, bitDepth: 12, seed: 4002),
        .init(id: "dx_001_class",    modality: "DX", width: 2544, height: 3056, bitDepth: 12, seed: 4003),
        .init(id: "mg_001_class",    modality: "MG", width: 3520, height: 4784, bitDepth: 12, seed: 6002),
    ]

    @Published var phase: BenchPhase = .idle
    @Published var results: [String: FixtureResult] = [:]
    @Published var progressCompleted: Int = 0
    @Published var progressTotal: Int = 0
    @Published var lastError: String?

    /// Configurable so the user can do a quick smoke run (e.g. 3 timed
    /// samples) before committing to the full 7-sample canonical run.
    @Published var runs: Int = 7
    @Published var warmups: Int = 2

    /// JSON written to the share-sheet payload. Naming matches the
    /// compare_hosts.py contract — see `hostJSONFilename`.
    var hostJSONFilename: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        let date = String(format: "%04d%02d%02d",
                          c.year ?? 1970, c.month ?? 1, c.day ?? 1)
        let model = sanitisedModel
        let version = j2kVersionString
        return "benchmark-results-\(model)-\(version)-warm-inproc-\(date).json"
    }

    /// Encode the run as the same shape Mac142/Mac1610 baseline JSONs
    /// already use, so `compare_hosts.py` can ingest A-series hosts
    /// alongside M2/M4.
    func encodeAsJSON() -> Data? {
        let payload: [String: Any] = [
            "host": [
                "machine": "arm64",
                "system": HostInfo.systemName,
                "release": HostInfo.systemVersion,
                "brand": HostInfo.brand,
                "ncpu": HostInfo.ncpu,
                "model": HostInfo.modelIdentifier
            ],
            "j2k_version": "J2KSwift version \(j2kVersionString)",
            "lane": "inproc",  // pure SDK warm in-process (no daemon, no CLI)
            "runs": runs,
            "warmups": warmups,
            "results": results.mapValues { r in
                return [
                    "fixture": r.fixture,
                    "modality": r.modality,
                    "width": r.width,
                    "height": r.height,
                    "bitDepth": r.bitDepth,
                    "codestreamBytes": r.codestreamBytes,
                    "encode_ms":          timingDict(r.encode),
                    "decode_cpu_ms":      timingDict(r.decodeCPU),
                    "decode_gpu_ms":      timingDict(r.decodeGPU),
                    "decode_gpuht_ms":    timingDict(r.decodeWithGPUHT),
                    "error": r.error ?? NSNull()
                ] as [String: Any]
            }
        ]
        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys])
    }

    private func timingDict(_ t: TimingSamples) -> Any {
        guard !t.samples.isEmpty else { return NSNull() }
        return [
            "samples": t.samples,
            "median": t.median ?? 0,
            "min": t.min ?? 0,
            "max": t.max ?? 0
        ] as [String: Any]
    }

    private var sanitisedModel: String {
        HostInfo.modelIdentifier
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Read directly from J2KCore so the JSON always matches the
    /// dylib that produced it.
    var j2kVersionString: String { HostInfo.j2kSwiftVersion }
}

/// Static host facts (no `@MainActor` — read from anywhere).
enum HostInfo {
    static var modelIdentifier: String {
        sysctlString("hw.machine") ?? sysctlString("hw.model") ?? "Unknown"
    }
    static var brand: String {
        // On macOS this gives "Apple M2"/"Apple M4 Pro"; on iOS the key
        // is unavailable. Map model identifier → marketing name where
        // possible so the JSON is human-readable.
        if let b = sysctlString("machdep.cpu.brand_string") { return b }
        return marketingName(forModel: modelIdentifier)
    }
    static var ncpu: Int {
        if let s = sysctlString("hw.ncpu"), let n = Int(s) { return n }
        return ProcessInfo.processInfo.activeProcessorCount
    }
    static var systemName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "Darwin"
        #else
        return "Unknown"
        #endif
    }
    static var systemVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    /// Pulled at runtime from J2KCore.getVersion(); guarded against a
    /// hard dep so this file is self-contained for unit tests.
    /// Pulled at runtime from J2KCore's top-level `getVersion()`; matches
    /// the semver in the `benchmark-results-<host>-<version>-...` file
    /// label convention.
    static var j2kSwiftVersion: String {
        return getVersion()
    }

    private static func sysctlString(_ key: String) -> String? {
        var size: size_t = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        sysctlbyname(key, &buf, &size, nil, 0)
        if let nul = buf.firstIndex(of: 0) { buf.removeLast(buf.count - nul) }
        return String(decoding: buf, as: UTF8.self)
    }

    /// Tiny lookup table for the iPhone/iPad model identifiers we
    /// care about for the v10.5 cross-silicon arc. Not exhaustive —
    /// future devices fall through to the raw identifier.
    private static func marketingName(forModel id: String) -> String {
        switch id {
        // A18 Pro
        case "iPhone17,1", "iPhone17,2": return "Apple A18 Pro"
        // A18
        case "iPhone17,3", "iPhone17,4": return "Apple A18"
        // A17 Pro
        case "iPhone16,1", "iPhone16,2": return "Apple A17 Pro"
        case "iPad14,8", "iPad14,9": return "Apple A17 Pro (iPad mini)"
        // A16
        case "iPhone15,2", "iPhone15,3": return "Apple A16"
        case "iPhone15,4", "iPhone15,5": return "Apple A16"
        // M-series iPad
        case "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6": return "Apple M4 (iPad Pro)"
        case "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6": return "Apple M2 (iPad Pro)"
        default: return id
        }
    }
}

