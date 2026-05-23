//
// JP3DBenchRunner.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// 3D analogue of `BenchRunner`. Drives the in-process warm JP3D bench:
// deterministic LCG-seeded volume synthesis, lossless HT-J2K JP3D
// encode (2 warmup + N timed, median reported), then three decode
// lanes against the same codestream:
//
//   • full         — JP3DDecoder.decode (production)
//   • res-1        — JP3DDecoder with resolutionLevel = 1
//                    (today the field is wired but ignored — Phase 2
//                    fixes it to actually drop deep-detail blocks)
//   • ROI quarter  — JP3DROIDecoder over the centre 1/4 volume
//                    (today: decode-then-crop; Phase 3 fixes that to
//                    true footprint-skip)
//
// The bench therefore *establishes the v10.18 baseline today* and
// re-measures the same shape after each Phase port, so wins land as
// per-fixture deltas the UI can show side-by-side.

import Foundation
import J2KCore
import J2K3D

@MainActor
final class JP3DBenchRunner {
    private weak var model: JP3DBenchModel?
    private weak var store: JP3DBenchStore?

    init(model: JP3DBenchModel, store: JP3DBenchStore?) {
        self.model = model
        self.store = store
    }

    /// Run the JP3D bench over the selected fixture ids. Updates
    /// `model.phase` + `model.results` on the MainActor as each fixture
    /// completes, then builds + persists a `JP3DBenchRun` and returns
    /// it.
    @discardableResult
    func run(fixtures: Set<String>) async -> JP3DBenchRun? {
        guard let model else { return nil }
        let toRun = JP3DBenchModel.corpus.filter { fixtures.contains($0.id) }
        guard !toRun.isEmpty else { return nil }

        model.results.removeAll()
        model.completed = false
        model.progressCompleted = 0
        // 4 stages per fixture (encode + 3 decode lanes).
        model.progressTotal = toRun.count * 4
        model.lastError = nil

        // JP3D doesn't have a `preWarm` analogue today — the per-slice
        // decode path inside JP3DSliceStackCodec spins up a J2KDecoder
        // per call. The first fixture's warmup reads absorb whatever
        // cold-start exists.
        model.phase = .warming("JP3D session")

        for fixture in toRun {
            do {
                try await benchOne(
                    fixture: fixture,
                    runs: model.runs,
                    warmups: model.warmups)
            } catch {
                var partial = model.results[fixture.id] ?? JP3DFixtureResult(
                    fixture: fixture.id,
                    modality: fixture.modality,
                    width: fixture.width,
                    height: fixture.height,
                    depth: fixture.depth,
                    bitDepth: fixture.bitDepth)
                partial.error = String(describing: error)
                model.results[fixture.id] = partial
            }
        }

        model.phase = .done
        model.completed = true

        let ordered = JP3DBenchModel.corpus.compactMap { model.results[$0.id] }
        let run = JP3DBenchRun(
            id: UUID(),
            date: Date(),
            host: .capture(),
            j2kVersion: model.j2kVersionString,
            runs: model.runs,
            warmups: model.warmups,
            results: ordered)
        store?.add(run)
        return run
    }

    // MARK: - Per-fixture pipeline

    private func benchOne(
        fixture: JP3DFixture,
        runs: Int,
        warmups: Int
    ) async throws {
        guard let model else { return }

        // 1) Synthesize volume + lossless HT encode --------------------
        let volume = JP3DSampleSource.synthesize(fixture)
        let rawBytes = volume.components.reduce(0) { $0 + $1.data.count }

        model.phase = .encoding(id: fixture.id)
        let encoder = JP3DSampleSource.losslessHTEncoder()
        var encSamples: [Double] = []
        encSamples.reserveCapacity(runs)
        var lastResult: JP3DEncoderResult?

        for _ in 0..<warmups {
            lastResult = try await encoder.encode(volume)
        }
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            lastResult = try await encoder.encode(volume)
            let t1 = DispatchTime.now().uptimeNanoseconds
            encSamples.append(Double(t1 - t0) / 1_000_000.0)
        }
        guard let encResult = lastResult else {
            throw JP3DBenchError.encodeFailed
        }
        let codestream = encResult.data

        var result = JP3DFixtureResult(
            fixture: fixture.id,
            modality: fixture.modality,
            width: fixture.width,
            height: fixture.height,
            depth: fixture.depth,
            bitDepth: fixture.bitDepth,
            codestreamBytes: codestream.count,
            rawBytes: rawBytes,
            encode: TimingSamples(samples: encSamples))
        model.results[fixture.id] = result
        model.progressCompleted += 1

        // 2) Decode lanes ----------------------------------------------
        result.decodeFull = try await timedDecodeFull(
            codestream: codestream,
            fixtureID: fixture.id,
            runs: runs, warmups: warmups)
        model.results[fixture.id] = result
        model.progressCompleted += 1

        result.decodeRes1 = try await timedDecodeResolution(
            codestream: codestream,
            resolutionLevel: 1,
            fixtureID: fixture.id,
            runs: runs, warmups: warmups)
        model.results[fixture.id] = result
        model.progressCompleted += 1

        let roi = fixture.centreQuarterROI
        result.decodeROIQuarter = try await timedDecodeROI(
            codestream: codestream,
            region: JP3DRegion(x: roi.x, y: roi.y, z: roi.z),
            fixtureID: fixture.id,
            runs: runs, warmups: warmups)
        model.results[fixture.id] = result
        model.progressCompleted += 1
    }

    // MARK: - Decode lane helpers

    private func timedDecodeFull(
        codestream: Data,
        fixtureID: String,
        runs: Int, warmups: Int
    ) async throws -> TimingSamples {
        guard let model else { return TimingSamples() }
        model.phase = .decoding(id: fixtureID, mode: "full")
        let decoder = JP3DDecoder()
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decoder.decode(codestream)
            let t1 = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(t1 - t0) / 1_000_000.0)
        }
        return TimingSamples(samples: samples)
    }

    private func timedDecodeResolution(
        codestream: Data,
        resolutionLevel: Int,
        fixtureID: String,
        runs: Int, warmups: Int
    ) async throws -> TimingSamples {
        guard let model else { return TimingSamples() }
        model.phase = .decoding(id: fixtureID, mode: "res-\(resolutionLevel)")
        let cfg = JP3DDecoderConfiguration(resolutionLevel: resolutionLevel)
        let decoder = JP3DDecoder(configuration: cfg)
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decoder.decode(codestream)
            let t1 = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(t1 - t0) / 1_000_000.0)
        }
        return TimingSamples(samples: samples)
    }

    private func timedDecodeROI(
        codestream: Data,
        region: JP3DRegion,
        fixtureID: String,
        runs: Int, warmups: Int
    ) async throws -> TimingSamples {
        guard let model else { return TimingSamples() }
        model.phase = .decoding(id: fixtureID, mode: "ROI 1/4")
        let decoder = JP3DROIDecoder()
        for _ in 0..<warmups { _ = try await decoder.decode(codestream, region: region) }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decoder.decode(codestream, region: region)
            let t1 = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(t1 - t0) / 1_000_000.0)
        }
        return TimingSamples(samples: samples)
    }
}

enum JP3DBenchError: Error, LocalizedError {
    case encodeFailed
    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "JP3D encode produced no codestream"
        }
    }
}
