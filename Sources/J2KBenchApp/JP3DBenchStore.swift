//
// JP3DBenchStore.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// Persistent JP3D run history. Mirrors `BenchStore` exactly (per-run
// JSON files under Application Support) but writes to a separate
// `JP3DRuns/` subdir so 2D and 3D histories never collide.
//
// Two serialisations live here, same pattern as the 2D store:
//   • internal per-run file — plain Codable encoding of `JP3DBenchRun`
//   • export blob          — canonical schema the cross-host harness
//                            ingests, with `encode` and `decode`
//                            top-level direction keys and per-fixture
//                            codec entries for the three decode lanes
//                            (full / res-1 / ROI 1/4).

import Foundation

@MainActor
final class JP3DBenchStore: ObservableObject {

    /// Saved JP3D runs, newest first.
    @Published private(set) var runs: [JP3DBenchRun] = []

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        directory = base.appendingPathComponent("JP3DRuns", isDirectory: true)
        try? fm.createDirectory(at: directory,
                                withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    // MARK: - Run history

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil) else { return }
        var loaded: [JP3DBenchRun] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let run = try? decoder.decode(JP3DBenchRun.self, from: data) {
                loaded.append(run)
            }
        }
        runs = loaded.sorted { $0.date > $1.date }
    }

    func add(_ run: JP3DBenchRun) {
        if let data = try? encoder.encode(run) {
            try? data.write(to: fileURL(for: run), options: .atomic)
        }
        runs.removeAll { $0.id == run.id }
        runs.insert(run, at: 0)
        runs.sort { $0.date > $1.date }
    }

    func delete(_ run: JP3DBenchRun) {
        try? FileManager.default.removeItem(at: fileURL(for: run))
        runs.removeAll { $0.id == run.id }
    }

    private func fileURL(for run: JP3DBenchRun) -> URL {
        directory.appendingPathComponent("\(run.id.uuidString).json")
    }

    // MARK: - Canonical export

    /// Build the canonical warm in-process JP3D bench JSON for a run,
    /// limited to `fixtureIDs`. Shape mirrors the 2D export so a
    /// future `cross_host_jp3d_compare.py` can ingest 2D-style.
    /// Three decode "codecs":
    ///   • J2KSwift+jp3d+full   — full-volume decode
    ///   • J2KSwift+jp3d+res1   — resolutionLevel=1 (today: stub-equal-to-full)
    ///   • J2KSwift+jp3d+roiq   — centre 1/4 ROI (today: decode-then-crop)
    func exportData(run: JP3DBenchRun, fixtureIDs: Set<String>) -> Data? {
        let selected = run.results.filter { fixtureIDs.contains($0.fixture) }
        guard !selected.isEmpty else { return nil }

        func directionMap(
            _ codecs: [(name: String, pick: (JP3DFixtureResult) -> TimingSamples)]
        ) -> [String: [String: Any]] {
            var out: [String: [String: Any]] = [:]
            for r in selected {
                var results: [String: [String: Any]] = [:]
                for codec in codecs {
                    let ts = codec.pick(r)
                    guard !ts.isEmpty else { continue }
                    results[codec.name] = [
                        "samples": ts.samples,
                        "median":  ts.median ?? 0,
                        "min":     ts.min ?? 0,
                        "max":     ts.max ?? 0,
                    ]
                }
                guard !results.isEmpty else { continue }
                out[r.fixture] = [
                    "label":    r.label,
                    "modality": r.modality,
                    "fixture":  r.fixture,
                    "source":   "synth",
                    "width":    r.width,
                    "height":   r.height,
                    "depth":    r.depth,
                    "results":  results,
                ]
            }
            return out
        }

        let payload: [String: Any] = [
            "schema": "warm-inproc-jp3d-v1",
            "j2k_version": run.j2kVersion,
            "runs": run.runs,
            "warmups": run.warmups,
            "host": [
                "brand": run.host.brand,
                "modelIdentifier": run.host.modelIdentifier,
                "systemName": run.host.systemName,
                "systemVersion": run.host.systemVersion,
                "ncpu": run.host.ncpu,
            ],
            "encode": directionMap([
                (name: "J2KSwift+jp3d+inproc", pick: { $0.encode }),
            ]),
            "decode": directionMap([
                (name: "J2KSwift+jp3d+full", pick: { $0.decodeFull }),
                (name: "J2KSwift+jp3d+res1", pick: { $0.decodeRes1 }),
                (name: "J2KSwift+jp3d+roiq", pick: { $0.decodeROIQuarter }),
            ]),
        ]

        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys])
    }

    /// Standard filename, mirrors the 2D bench convention:
    /// `benchmark-results-jp3d-<modelid>-<version>-warm-inproc-<yyyymmdd>.json`
    func exportFilename(for run: JP3DBenchRun) -> String {
        let modelID = run.host.modelIdentifier
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let date = df.string(from: run.date)
        return "benchmark-results-jp3d-\(modelID)-\(run.j2kVersion)-warm-inproc-\(date).json"
    }
}
