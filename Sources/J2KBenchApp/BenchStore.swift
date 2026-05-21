//
// BenchStore.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Persistent run history. Every completed (or partial) `BenchRun` is
// written as one JSON file under Application Support, so a tester runs
// the bench once and can browse / re-share it forever without paying
// the 3–7 min wall again.
//
// Two serialisations live here, deliberately separate:
//   • the *internal* per-run file — a plain `Codable` encoding of
//     `BenchRun`, only ever read back by this app;
//   • the *export* blob — the canonical schema that
//     `Scripts/benchmarks/compare_hosts.py` ingests (top-level
//     `encode`/`decode` direction keys), built by `exportData`.

import Foundation

@MainActor
final class BenchStore: ObservableObject {

    /// Saved runs, newest first.
    @Published private(set) var runs: [BenchRun] = []

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        directory = base.appendingPathComponent("BenchRuns", isDirectory: true)
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
        var loaded: [BenchRun] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let run = try? decoder.decode(BenchRun.self, from: data) {
                loaded.append(run)
            }
        }
        runs = loaded.sorted { $0.date > $1.date }
    }

    /// Persist a freshly completed run and surface it at the top of the
    /// history list.
    func add(_ run: BenchRun) {
        if let data = try? encoder.encode(run) {
            try? data.write(to: fileURL(for: run), options: .atomic)
        }
        runs.removeAll { $0.id == run.id }
        runs.insert(run, at: 0)
        runs.sort { $0.date > $1.date }
    }

    func delete(_ run: BenchRun) {
        try? FileManager.default.removeItem(at: fileURL(for: run))
        runs.removeAll { $0.id == run.id }
    }

    private func fileURL(for run: BenchRun) -> URL {
        directory.appendingPathComponent("\(run.id.uuidString).json")
    }

    // MARK: - Canonical export (compare_hosts.py contract)

    /// Build the canonical warm in-process bench JSON for a run, limited
    /// to `fixtureIDs`. Shape matches the M2/M4 baseline JSONs in
    /// `Documentation/Benchmarks/data/` so `compare_hosts.py` ingests it
    /// unmodified.
    func exportData(run: BenchRun, fixtureIDs: Set<String>) -> Data? {
        let selected = run.results.filter { fixtureIDs.contains($0.fixture) }
        guard !selected.isEmpty else { return nil }

        // Per-direction fixture map: { id: { label, modality, fixture,
        // source, results: { codec: timing } } }.
        func directionMap(_ pick: (FixtureResult) -> TimingSamples) -> [String: Any] {
            var map: [String: Any] = [:]
            for r in selected {
                let timing = pick(r)
                guard !timing.isEmpty else { continue }
                map[r.fixture] = [
                    "label": r.label,
                    "modality": r.modality,
                    "fixture": r.fixture,
                    "source": "synthetic",
                    "results": ["J2KSwift+inproc": timingDict(timing)]
                ] as [String: Any]
            }
            return map
        }

        let payload: [String: Any] = [
            "host": [
                "machine": "arm64",
                "system": run.host.systemName,
                "release": run.host.systemVersion,
                "brand": run.host.brand,
                "model": run.host.modelIdentifier,
                "ncpu": run.host.ncpu
            ],
            "j2k_version": "J2KSwift version \(run.j2kVersion)",
            "lane": "inproc",
            "runs": run.runs,
            "warmups": run.warmups,
            "encode": directionMap { $0.encode },
            // Decode column = `.cpu` lane, i.e. `J2KDecoder.decode()` —
            // the production router path the macOS `--in-proc` lane also
            // measures, keeping the cross-host comparison apples-to-apples.
            "decode": directionMap { $0.decodeCPU }
        ]
        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys])
    }

    private func timingDict(_ t: TimingSamples) -> [String: Any] {
        [
            "samples": t.samples,
            "median": t.median ?? 0,
            "min": t.min ?? 0,
            "max": t.max ?? 0
        ]
    }

    /// `benchmark-results-<model>-<version>-warm-inproc-<YYYYMMDD>.json`
    /// — the filename convention that buckets the file correctly on the
    /// compare side.
    func exportFilename(for run: BenchRun) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: run.date)
        let date = String(format: "%04d%02d%02d",
                          c.year ?? 1970, c.month ?? 1, c.day ?? 1)
        let model = run.host.modelIdentifier
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return "benchmark-results-\(model)-\(run.j2kVersion)-warm-inproc-\(date).json"
    }
}
