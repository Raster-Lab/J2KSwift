//
// BenchModel.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Value types for the corpus, per-fixture timings, persisted runs, and
// host identity, plus `BenchModel` — the observable state of one *live*
// run session (a fresh instance is created per New-Benchmark screen).
//
// Persistence and JSON export live in `BenchStore`; this file is just
// the data model.

import Foundation
import J2KCore

#if canImport(UIKit)
import UIKit
#endif

/// One fixture in the canonical synthetic corpus.
struct BenchFixture: Identifiable, Hashable, Sendable {
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
struct TimingSamples: Codable, Hashable, Sendable {
    var samples: [Double] = []  // milliseconds

    var median: Double? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        return s[s.count / 2]
    }
    var min: Double? { samples.min() }
    var max: Double? { samples.max() }
    var isEmpty: Bool { samples.isEmpty }
}

/// All measurements for one fixture.
struct FixtureResult: Codable, Hashable, Sendable, Identifiable {
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

    var id: String { fixture }
    var label: String { "\(modality) \(width)\u{00d7}\(height)" }

    /// Median of the three decode lanes that produced samples — the
    /// headline "fastest decode" figure shown in compact rows.
    var fastestDecodeMedian: Double? {
        [decodeCPU.median, decodeGPU.median, decodeWithGPUHT.median]
            .compactMap { $0 }
            .min()
    }
}

/// Coarse run-state for the UI. `encoding`/`decoding` carry the
/// fixture **id** so a view can match a phase to a corpus row exactly.
enum BenchPhase: Equatable, Sendable {
    case idle
    case warming(String)
    case encoding(id: String)
    case decoding(id: String, mode: String)
    case done
    case failed(String)
}

/// Per-fixture lifecycle state, derived for the UI badge.
enum FixtureStatus: Sendable {
    case notSelected   // excluded from this run
    case notRun        // selected, not yet measured
    case running       // currently encoding/decoding
    case done          // all stages complete
    case failed        // produced an error
}

// MARK: - Persisted run

/// Host facts snapshotted at run time so a saved run keeps its identity
/// even though `HostInfo` reads live `sysctl` values.
struct HostSnapshot: Codable, Hashable, Sendable {
    var brand: String
    var modelIdentifier: String
    var systemName: String
    var systemVersion: String
    var ncpu: Int

    static func capture() -> HostSnapshot {
        HostSnapshot(
            brand: HostInfo.brand,
            modelIdentifier: HostInfo.modelIdentifier,
            systemName: HostInfo.systemName,
            systemVersion: HostInfo.systemVersion,
            ncpu: HostInfo.ncpu)
    }
}

/// One completed (or partially completed) benchmark session, persisted
/// to disk by `BenchStore` so the user never has to re-run to view it.
struct BenchRun: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var host: HostSnapshot
    var j2kVersion: String
    var runs: Int
    var warmups: Int
    var results: [FixtureResult]   // ordered by corpus appearance

    /// Short human title for the history list.
    var title: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
    var fixtureCount: Int { results.count }
    var hasFailures: Bool { results.contains { $0.error != nil } }
}

// MARK: - Live run session

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

    static func fixture(id: String) -> BenchFixture? {
        corpus.first { $0.id == id }
    }

    @Published var phase: BenchPhase = .idle
    @Published var results: [String: FixtureResult] = [:]
    @Published var progressCompleted: Int = 0
    @Published var progressTotal: Int = 0
    @Published var lastError: String?

    /// Fixture ids the user has ticked. Drives both *which fixtures run*
    /// and *which fixtures export* — one selection, both actions.
    @Published var selectedFixtures: Set<String> = Set(corpus.map(\.id))

    /// Configurable so the user can do a quick smoke run (e.g. 3 timed
    /// samples) before committing to the full 7-sample canonical run.
    @Published var runs: Int = 7
    @Published var warmups: Int = 2

    /// `true` once `runAll`/`run(fixtures:)` has finished and a `BenchRun`
    /// has been persisted — gates the "Share Selected" affordance.
    @Published var completed: Bool = false

    // MARK: Selection helpers

    var allSelected: Bool {
        selectedFixtures.count == BenchModel.corpus.count
    }
    func toggle(_ id: String) {
        if selectedFixtures.contains(id) { selectedFixtures.remove(id) }
        else { selectedFixtures.insert(id) }
    }
    func selectAll() { selectedFixtures = Set(BenchModel.corpus.map(\.id)) }
    func selectNone() { selectedFixtures.removeAll() }

    // MARK: Per-fixture status (drives the UI badge)

    func status(for fixture: BenchFixture) -> FixtureStatus {
        if let r = results[fixture.id], r.error != nil { return .failed }
        switch phase {
        case .encoding(let id) where id == fixture.id:        return .running
        case .decoding(let id, _) where id == fixture.id:     return .running
        default: break
        }
        if results[fixture.id] != nil { return .done }
        return selectedFixtures.contains(fixture.id) ? .notRun : .notSelected
    }

    /// Read directly from J2KCore so any displayed version always
    /// matches the dylib that produced it.
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
        // A15 (iPhone 13 family + iPhone 14 / 14 Plus)
        case "iPhone14,2", "iPhone14,3", "iPhone14,4", "iPhone14,5",
             "iPhone14,7", "iPhone14,8": return "Apple A15"
        // M-series iPad
        case "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6": return "Apple M4 (iPad Pro)"
        case "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6": return "Apple M2 (iPad Pro)"
        default: return id
        }
    }
}
