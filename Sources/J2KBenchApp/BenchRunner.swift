//
// BenchRunner.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Drives the in-process warm bench: deterministic LCG-seeded 16-bit
// fixture synthesis, HT-J2K lossless encode (2 warmup + N timed,
// median reported), then decode across .cpu / .decodeGPU /
// .decodeWithGPUHT (same shape). Runs only the fixtures the user
// selected, then persists the result as a `BenchRun` via `BenchStore`.
//
// This is the same arithmetic the canonical
// `cross_codec_warm_bench.py --in-proc` lane runs — minus the
// subprocess + j2kd daemon shell, since neither is reachable from
// inside an iOS app sandbox.

import Foundation
import J2KCore
import J2KCodec
#if canImport(J2KMetal)
import J2KMetal
#endif

@MainActor
final class BenchRunner {
    private weak var model: BenchModel?
    private weak var store: BenchStore?

    init(model: BenchModel, store: BenchStore?) {
        self.model = model
        self.store = store
    }

    /// Run the bench over the selected fixture ids. Updates
    /// `model.phase` + `model.results` on the MainActor as each fixture
    /// completes, then builds + persists a `BenchRun` and returns it.
    @discardableResult
    func run(fixtures: Set<String>) async -> BenchRun? {
        guard let model else { return nil }
        let toRun = BenchModel.corpus.filter { fixtures.contains($0.id) }
        guard !toRun.isEmpty else { return nil }

        model.results.removeAll()
        model.completed = false
        model.progressCompleted = 0
        // 4 stages per fixture (encode + 3 decode modes).
        model.progressTotal = toRun.count * 4
        model.lastError = nil

        // Warm the process-shared Metal session once up front so the
        // GPU decode lanes don't pay ~25-30 ms cold-start in the first
        // fixture's "warmup" reads. preWarm includes a small dispatch
        // so the kernel pipeline cache lands too.
        model.phase = .warming("Metal session")
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        for fixture in toRun {
            do {
                try await benchOne(fixture: fixture, runs: model.runs, warmups: model.warmups)
            } catch {
                var partial = model.results[fixture.id] ?? FixtureResult(
                    fixture: fixture.id,
                    modality: fixture.modality,
                    width: fixture.width,
                    height: fixture.height,
                    bitDepth: fixture.bitDepth)
                partial.error = String(describing: error)
                model.results[fixture.id] = partial
            }
        }

        model.phase = .done
        model.completed = true

        // Persist — corpus order, only the fixtures actually measured.
        let ordered = BenchModel.corpus.compactMap { model.results[$0.id] }
        let run = BenchRun(
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
        fixture: BenchFixture,
        runs: Int,
        warmups: Int
    ) async throws {
        guard let model else { return }

        // Synthesize once; warm bench reuses the same J2KImage buffer
        // for every run so allocator costs aren't bench-time-dominated.
        let image = J2KSampleSource.synthesize(fixture)

        // 1) Encode bench --------------------------------------------
        model.phase = .encoding(id: fixture.id)
        let encoder = J2KSampleSource.losslessHTEncoder()
        var encSamples: [Double] = []
        encSamples.reserveCapacity(runs)
        var lastCodestream: Data?

        for _ in 0..<warmups {
            lastCodestream = try await encoder.encode(image)
        }
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            lastCodestream = try await encoder.encode(image)
            let t1 = DispatchTime.now().uptimeNanoseconds
            encSamples.append(Double(t1 - t0) / 1_000_000.0)
        }
        guard let codestream = lastCodestream else {
            throw BenchError.encodeFailed
        }

        var result = FixtureResult(
            fixture: fixture.id,
            modality: fixture.modality,
            width: fixture.width,
            height: fixture.height,
            bitDepth: fixture.bitDepth,
            codestreamBytes: codestream.count,
            encode: TimingSamples(samples: encSamples)
        )
        model.results[fixture.id] = result
        model.progressCompleted += 1

        // 2) Decode benches ------------------------------------------
        result.decodeCPU = try await timedDecode(
            codestream: codestream,
            mode: .cpu,
            fixtureID: fixture.id,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".cpu")
        model.results[fixture.id] = result
        model.progressCompleted += 1

        result.decodeGPU = try await timedDecode(
            codestream: codestream,
            mode: .decodeGPU,
            fixtureID: fixture.id,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".decodeGPU")
        model.results[fixture.id] = result
        model.progressCompleted += 1

        result.decodeWithGPUHT = try await timedDecode(
            codestream: codestream,
            mode: .decodeWithGPUHT,
            fixtureID: fixture.id,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".decodeWithGPUHT")
        model.results[fixture.id] = result
        model.progressCompleted += 1
    }

    private func timedDecode(
        codestream: Data,
        mode: DecodeMode,
        fixtureID: String,
        runs: Int, warmups: Int,
        phaseModeLabel: String
    ) async throws -> TimingSamples {
        guard let model else { return TimingSamples() }
        model.phase = .decoding(id: fixtureID, mode: phaseModeLabel)

        let decoder = J2KDecoder()

        for _ in 0..<warmups {
            _ = try await decode(codestream, mode: mode, with: decoder)
        }
        var samples: [Double] = []
        samples.reserveCapacity(runs)
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try await decode(codestream, mode: mode, with: decoder)
            let t1 = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(t1 - t0) / 1_000_000.0)
        }
        return TimingSamples(samples: samples)
    }

    private func decode(
        _ data: Data,
        mode: DecodeMode,
        with decoder: J2KDecoder
    ) async throws -> J2KImage {
        switch mode {
        case .cpu:
            return try await decoder.decode(data)
        case .decodeGPU:
            return try await decoder.decodeGPU(data)
        case .decodeWithGPUHT:
            return try await decoder.decodeWithGPUHT(data)
        }
    }

    // Fixture synthesis and the lossless HT encoder config live in
    // `J2KSampleSource` — shared with the image viewer.
}

enum DecodeMode {
    case cpu, decodeGPU, decodeWithGPUHT
}

enum BenchError: Error, LocalizedError {
    case encodeFailed
    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "Encode produced no codestream"
        }
    }
}
