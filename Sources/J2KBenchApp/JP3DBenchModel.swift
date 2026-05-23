//
// JP3DBenchModel.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// 3D analogue of `BenchModel`: corpus, value types for per-fixture
// timings, persisted runs, and the observable state of one *live* JP3D
// run session. Persistence + canonical JSON export live in
// `JP3DBenchStore`.
//
// The 3D bench measures four decode lanes against one canonical
// lossless HT-J2K encode:
//   • encode               — JP3DEncoder.encode (lossless HT)
//   • decode (full)        — JP3DDecoder.decode  (current production)
//   • decode (res-1)       — JP3DDecoder with configuration.resolutionLevel = 1
//                            (today: stub; v10.18 Phase 2 fix: true partial-res)
//   • decode (ROI 1/4)     — JP3DROIDecoder.decode(region:) over centre 1/4
//                            volume (today: decode-then-crop; v10.18 Phase 3
//                            fix: true ROI footprint-skip)
//
// The same per-lane shape lets the UI A/B today's behaviour against
// the v10.18 ports in-place once Phases 2-4 land.

import Foundation
import J2KCore

/// One fixture in the synthetic JP3D bench corpus.
struct JP3DFixture: Identifiable, Hashable, Sendable {
    let id: String
    let modality: String
    let width: Int
    let height: Int
    let depth: Int
    let bitDepth: Int
    let seed: UInt64

    var voxels: Int { width * height * depth }
    var label: String { "\(modality) \(width)\u{00d7}\(height)\u{00d7}\(depth)" }

    /// Centre 1/4 volume (centre half on each axis) for the ROI decode
    /// lane. Even-aligned to the nearest multiple of 2 so encoder tile
    /// grids don't fight the region edges.
    var centreQuarterROI: (x: Range<Int>, y: Range<Int>, z: Range<Int>) {
        func centred(_ n: Int) -> Range<Int> {
            let half = n / 2
            let origin = (n - half) / 2
            let aligned = (origin / 2) * 2
            return aligned..<(aligned + half)
        }
        return (centred(width), centred(height), centred(depth))
    }
}

/// Per-run timing samples reused from `BenchModel` (`TimingSamples` is
/// declared there) — same Codable shape so existing JSON-export
/// helpers work uniformly.

/// All measurements for one JP3D fixture.
struct JP3DFixtureResult: Codable, Hashable, Sendable, Identifiable {
    var fixture: String
    var modality: String
    var width: Int
    var height: Int
    var depth: Int
    var bitDepth: Int
    var codestreamBytes: Int = 0
    var rawBytes: Int = 0          // uncompressed voxel byte count
    var encode: TimingSamples = TimingSamples()
    var decodeFull: TimingSamples = TimingSamples()
    var decodeRes1: TimingSamples = TimingSamples()
    var decodeROIQuarter: TimingSamples = TimingSamples()
    var error: String?

    var id: String { fixture }
    var label: String { "\(modality) \(width)\u{00d7}\(height)\u{00d7}\(depth)" }

    /// Compression ratio = raw / codestream.
    var compressionRatio: Double? {
        guard codestreamBytes > 0 else { return nil }
        return Double(rawBytes) / Double(codestreamBytes)
    }
}

/// Coarse run-state for the Volumes tab UI. `encoding`/`decoding`
/// carry the fixture **id** so a view can match a phase to a corpus
/// row exactly.
enum JP3DBenchPhase: Equatable, Sendable {
    case idle
    case warming(String)
    case encoding(id: String)
    case decoding(id: String, mode: String)
    case done
    case failed(String)
}

/// Per-fixture lifecycle state, drives the UI badge in the corpus list.
enum JP3DFixtureStatus: Sendable {
    case notSelected
    case notRun
    case running
    case done
    case failed
}

// MARK: - Persisted run

/// One completed (or partially completed) JP3D benchmark session,
/// persisted to disk by `JP3DBenchStore`.
struct JP3DBenchRun: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var host: HostSnapshot         // reused from BenchModel
    var j2kVersion: String
    var runs: Int
    var warmups: Int
    var results: [JP3DFixtureResult]

    var title: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
    var fixtureCount: Int { results.count }
    var hasFailures: Bool { results.contains { $0.error != nil } }
}

// MARK: - Live JP3D run session

@MainActor
final class JP3DBenchModel: ObservableObject {

    /// 6 synthetic JP3D fixtures spanning ~250 K → ~16 M voxels across
    /// CT (16-bit grayscale), MR (16-bit grayscale), and US (8-bit
    /// grayscale). Sized so the full 4-lane bench (encode + 3 decode
    /// lanes) at the default 2 warmups + 7 timed runs completes in
    /// ~1–2 minutes on M-series silicon.
    static let corpus: [JP3DFixture] = [
        .init(id: "mr_3d_small",  modality: "MR", width: 128,  height: 128,  depth: 16,  bitDepth: 16, seed: 1001),
        .init(id: "ct_3d_small",  modality: "CT", width: 256,  height: 256,  depth: 16,  bitDepth: 16, seed: 2001),
        .init(id: "us_3d_small",  modality: "US", width: 320,  height: 240,  depth: 24,  bitDepth: 8,  seed: 3001),
        .init(id: "mr_3d_mid",    modality: "MR", width: 256,  height: 256,  depth: 32,  bitDepth: 16, seed: 4001),
        .init(id: "ct_3d_mid",    modality: "CT", width: 512,  height: 512,  depth: 32,  bitDepth: 16, seed: 5001),
        .init(id: "ct_3d_large",  modality: "CT", width: 512,  height: 512,  depth: 64,  bitDepth: 16, seed: 6001),
    ]

    static func fixture(id: String) -> JP3DFixture? {
        corpus.first { $0.id == id }
    }

    @Published var phase: JP3DBenchPhase = .idle
    @Published var results: [String: JP3DFixtureResult] = [:]
    @Published var progressCompleted: Int = 0
    @Published var progressTotal: Int = 0
    @Published var lastError: String?

    /// Ticked fixture ids — drives both *which fixtures run* and
    /// *which fixtures export*. One selection, both actions.
    @Published var selectedFixtures: Set<String> = Set(corpus.map(\.id))

    @Published var runs: Int = 7
    @Published var warmups: Int = 2

    /// `true` once `run(fixtures:)` has finished and a `JP3DBenchRun`
    /// has been persisted — gates the "Share Selected" affordance.
    @Published var completed: Bool = false

    var allSelected: Bool {
        selectedFixtures.count == JP3DBenchModel.corpus.count
    }
    func toggle(_ id: String) {
        if selectedFixtures.contains(id) { selectedFixtures.remove(id) }
        else { selectedFixtures.insert(id) }
    }
    func selectAll() { selectedFixtures = Set(JP3DBenchModel.corpus.map(\.id)) }
    func selectNone() { selectedFixtures.removeAll() }

    func status(for fixture: JP3DFixture) -> JP3DFixtureStatus {
        if let r = results[fixture.id], r.error != nil { return .failed }
        switch phase {
        case .encoding(let id) where id == fixture.id:        return .running
        case .decoding(let id, _) where id == fixture.id:     return .running
        default: break
        }
        if results[fixture.id] != nil { return .done }
        return selectedFixtures.contains(fixture.id) ? .notRun : .notSelected
    }

    var j2kVersionString: String { HostInfo.j2kSwiftVersion }
}
