//
// BenchRunner.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Drives the in-process warm bench: deterministic LCG-seeded 16-bit
// fixture synthesis, HT-J2K lossless encode (2 warmup + N timed,
// median reported), then decode across .cpu / .decodeGPU /
// .decodeWithGPUHT (same shape).
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

    init(model: BenchModel) {
        self.model = model
    }

    /// Run the full bench. Updates `model.phase` + `model.results`
    /// on the MainActor as each fixture completes.
    func runAll() async {
        guard let model else { return }
        model.results.removeAll()
        model.progressCompleted = 0
        // 4 stages per fixture (encode + 3 decode modes).
        model.progressTotal = BenchModel.corpus.count * 4
        model.lastError = nil

        // Warm the process-shared Metal session once up front so the
        // GPU decode lanes don't pay ~25-30 ms cold-start in the first
        // fixture's "warmup" reads. preWarm includes a small dispatch
        // so the kernel pipeline cache lands too.
        model.phase = .warming("Metal session")
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        for fixture in BenchModel.corpus {
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
        let image = makeJ2KImage(for: fixture)

        // 1) Encode bench --------------------------------------------
        model.phase = .encoding(fixture.label)
        let encoder = makeLosslessHTEncoder()
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
            fixtureLabel: fixture.label,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".cpu")
        model.results[fixture.id] = result
        model.progressCompleted += 1

        result.decodeGPU = try await timedDecode(
            codestream: codestream,
            mode: .decodeGPU,
            fixtureLabel: fixture.label,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".decodeGPU")
        model.results[fixture.id] = result
        model.progressCompleted += 1

        result.decodeWithGPUHT = try await timedDecode(
            codestream: codestream,
            mode: .decodeWithGPUHT,
            fixtureLabel: fixture.label,
            runs: runs, warmups: warmups,
            phaseModeLabel: ".decodeWithGPUHT")
        model.results[fixture.id] = result
        model.progressCompleted += 1
    }

    private func timedDecode(
        codestream: Data,
        mode: DecodeMode,
        fixtureLabel: String,
        runs: Int, warmups: Int,
        phaseModeLabel: String
    ) async throws -> TimingSamples {
        guard let model else { return TimingSamples() }
        model.phase = .decoding(fixtureLabel, phaseModeLabel)

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

    // MARK: - Encoder configuration

    /// Canonical HT-J2K lossless config used by the in-process
    /// performance suite (J2KMedicalCorpusEncodePerformanceTests).
    /// Holding it stable across hosts is what makes the cross-silicon
    /// comparison apples-to-apples.
    private func makeLosslessHTEncoder() -> J2KEncoder {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant
        )
        return J2KEncoder(encodingConfiguration: cfg)
    }

    // MARK: - Deterministic LCG fixture synthesis

    /// Mirrors `Scripts/benchmarks/generate_synthetic_corpus.py`'s LCG
    /// noise field (multiplier `1442695040888963407`) so an A-series
    /// run can be compared byte-equivalent against the canonical
    /// PGM corpus on M-series. We omit the modality-specific
    /// structural overlays — they affect compression ratio but not
    /// the timing rankings the cross-silicon arc cares about.
    private func makeJ2KImage(for fixture: BenchFixture) -> J2KImage {
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
                // Big-endian byte order matches the PGM corpus written
                // by generate_synthetic_corpus.py.
                buf[i] = sample.bigEndian
            }
        }

        let comp = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: fixture.width,
            height: fixture.height,
            subsamplingX: 1, subsamplingY: 1,
            data: data,
            sampleByteOrder: .bigEndian
        )
        return J2KImage(
            width: fixture.width,
            height: fixture.height,
            components: [comp])
    }
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
