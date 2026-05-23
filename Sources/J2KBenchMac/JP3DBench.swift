//
// JP3DBench.swift
// J2KBenchMac — v10.18-research JP3D arc
//
// 3D analogue of the 2D bench in J2KBenchMac.swift. Same shape: LCG-
// synthesised volume corpus, lossless HT-J2K JP3D encoder, warm
// in-process timing across encode + 3 decode lanes (full / res-1 /
// ROI 1/4), canonical JSON output that mirrors the iOS J2KBenchApp's
// `Volumes` tab Share Selected payload (schema "warm-inproc-jp3d-v1").
//
// Invoked from J2KBenchMac.main via `--jp3d`. Reuses HostSnapshot,
// `eprint`, `sysctlString`, `Samples` from the 2D side of the binary;
// only the corpus / synthesiser / encoder / bench loop are 3D-specific.

import Foundation
import J2KCore
import J2K3D

// MARK: - JP3D fixtures (mirrors iOS JP3DBenchModel.corpus)

struct JP3DBenchFixture: Sendable {
    let id: String
    let modality: String
    let width: Int
    let height: Int
    let depth: Int
    let bitDepth: Int
    let seed: UInt64
    var voxels: Int { width * height * depth }
    var label: String { "\(modality) \(width)\u{00d7}\(height)\u{00d7}\(depth)" }
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

let jp3dCorpus: [JP3DBenchFixture] = [
    .init(id: "mr_3d_small",  modality: "MR", width: 128,  height: 128,  depth: 16, bitDepth: 16, seed: 1001),
    .init(id: "ct_3d_small",  modality: "CT", width: 256,  height: 256,  depth: 16, bitDepth: 16, seed: 2001),
    .init(id: "us_3d_small",  modality: "US", width: 320,  height: 240,  depth: 24, bitDepth: 8,  seed: 3001),
    .init(id: "mr_3d_mid",    modality: "MR", width: 256,  height: 256,  depth: 32, bitDepth: 16, seed: 4001),
    .init(id: "ct_3d_mid",    modality: "CT", width: 512,  height: 512,  depth: 32, bitDepth: 16, seed: 5001),
    .init(id: "ct_3d_large",  modality: "CT", width: 512,  height: 512,  depth: 64, bitDepth: 16, seed: 6001),
]

// MARK: - LCG volume synthesis (mirrors iOS JP3DSampleSource.synthesize)

func synthesize(_ fixture: JP3DBenchFixture) -> J2KVolume {
    let voxelCount = fixture.width * fixture.height * fixture.depth
    let bitDepth = fixture.bitDepth
    let bytesPerSample = (bitDepth + 7) / 8
    precondition(bytesPerSample == 1 || bytesPerSample == 2,
                 "JP3D bench supports 8-bit or 16-bit fixtures only")

    let maxVal = (1 << bitDepth) - 1
    var data = Data(count: voxelCount * bytesPerSample)
    var s: UInt64 = fixture.seed &* 6364136223846793005 &+ 1442695040888963407

    data.withUnsafeMutableBytes { rawPtr in
        if bytesPerSample == 1 {
            let buf = rawPtr.bindMemory(to: UInt8.self)
            for i in 0..<voxelCount {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let sample = Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1)
                buf[i] = UInt8(truncatingIfNeeded: sample)
            }
        } else {
            let buf = rawPtr.bindMemory(to: UInt16.self)
            for i in 0..<voxelCount {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let sample = Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1)
                buf[i] = UInt16(truncatingIfNeeded: sample)
            }
        }
    }

    let comp = J2KVolumeComponent(
        index: 0, bitDepth: bitDepth, signed: false,
        width: fixture.width, height: fixture.height, depth: fixture.depth,
        subsamplingX: 1, subsamplingY: 1, subsamplingZ: 1,
        data: data)
    return J2KVolume(
        width: fixture.width, height: fixture.height, depth: fixture.depth,
        components: [comp],
        spacingX: 1.0, spacingY: 1.0, spacingZ: 1.0)
}

func losslessHTJP3DEncoder() -> JP3DEncoder {
    let cfg = JP3DEncoderConfiguration(
        compressionMode: .losslessHTJ2K,
        tiling: .default,
        progressionOrder: .lrcps,
        qualityLayers: 1,
        levelsX: 3, levelsY: 3, levelsZ: 1,
        parallelEncoding: true,
        zDeltaMode: .auto)
    return JP3DEncoder(configuration: cfg)
}

// MARK: - JP3D fixture result + bench loop

struct JP3DFixtureResultM {
    let fixture: JP3DBenchFixture
    var codestreamBytes: Int = 0
    var rawBytes: Int = 0
    var encode = Samples()
    var decodeFull = Samples()
    var decodeRes1 = Samples()
    var decodeROIQuarter = Samples()
    var error: String?
}

func jp3dBenchOne(_ fixture: JP3DBenchFixture,
                  runs: Int, warmups: Int) async -> JP3DFixtureResultM {
    var result = JP3DFixtureResultM(fixture: fixture)
    let volume = synthesize(fixture)
    result.rawBytes = volume.components.reduce(0) { $0 + $1.data.count }
    let encoder = losslessHTJP3DEncoder()
    var lastResult: JP3DEncoderResult?

    // Encode — warm + timed
    do {
        for _ in 0..<warmups { lastResult = try await encoder.encode(volume) }
        for _ in 0..<runs {
            let t0 = DispatchTime.now().uptimeNanoseconds
            lastResult = try await encoder.encode(volume)
            let t1 = DispatchTime.now().uptimeNanoseconds
            result.encode.values.append(Double(t1 - t0) / 1_000_000.0)
        }
    } catch {
        result.error = "encode: \(error)"
        return result
    }
    guard let cs = lastResult?.data else {
        result.error = "encode produced no codestream"
        return result
    }
    result.codestreamBytes = cs.count

    do {
        result.decodeFull = try await jp3dTimedDecodeFull(cs, runs: runs, warmups: warmups)
        result.decodeRes1 = try await jp3dTimedDecodeRes(cs, level: 1, runs: runs, warmups: warmups)
        let roi = fixture.centreQuarterROI
        let region = JP3DRegion(x: roi.x, y: roi.y, z: roi.z)
        result.decodeROIQuarter = try await jp3dTimedDecodeROI(cs, region: region,
                                                               runs: runs, warmups: warmups)
    } catch {
        result.error = "decode: \(error)"
    }
    return result
}

func jp3dTimedDecodeFull(_ data: Data, runs: Int, warmups: Int) async throws -> Samples {
    let decoder = JP3DDecoder()
    for _ in 0..<warmups { _ = try await decoder.decode(data) }
    var s = Samples()
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await decoder.decode(data)
        let t1 = DispatchTime.now().uptimeNanoseconds
        s.values.append(Double(t1 - t0) / 1_000_000.0)
    }
    return s
}

func jp3dTimedDecodeRes(_ data: Data, level: Int,
                        runs: Int, warmups: Int) async throws -> Samples {
    let cfg = JP3DDecoderConfiguration(resolutionLevel: level)
    let decoder = JP3DDecoder(configuration: cfg)
    for _ in 0..<warmups { _ = try await decoder.decode(data) }
    var s = Samples()
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await decoder.decode(data)
        let t1 = DispatchTime.now().uptimeNanoseconds
        s.values.append(Double(t1 - t0) / 1_000_000.0)
    }
    return s
}

func jp3dTimedDecodeROI(_ data: Data, region: JP3DRegion,
                        runs: Int, warmups: Int) async throws -> Samples {
    let decoder = JP3DROIDecoder()
    for _ in 0..<warmups { _ = try await decoder.decode(data, region: region) }
    var s = Samples()
    for _ in 0..<runs {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await decoder.decode(data, region: region)
        let t1 = DispatchTime.now().uptimeNanoseconds
        s.values.append(Double(t1 - t0) / 1_000_000.0)
    }
    return s
}

// MARK: - JSON emit (mirrors iOS JP3DBenchStore.exportData schema)

func buildJP3DJSON(host: HostSnapshot, j2kVersion: String,
                   runs: Int, warmups: Int,
                   results: [JP3DFixtureResultM]) -> Data? {
    func timingDict(_ s: Samples) -> [String: Any] {
        ["samples": s.values,
         "median":  s.median ?? 0,
         "min":     s.minV ?? 0,
         "max":     s.maxV ?? 0]
    }
    func directionMap(_ codecs: [(name: String,
                                  pick: (JP3DFixtureResultM) -> Samples)])
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
                "label":    r.fixture.label,
                "modality": r.fixture.modality,
                "fixture":  r.fixture.id,
                "source":   "synthetic",
                "width":    r.fixture.width,
                "height":   r.fixture.height,
                "depth":    r.fixture.depth,
                "results":  perCodec
            ] as [String: Any]
        }
        return map
    }
    let payload: [String: Any] = [
        "schema": "warm-inproc-jp3d-v1",
        "host": [
            "machine": "arm64",
            "system":  host.systemName,
            "release": host.systemVersion,
            "brand":   host.brand,
            "model":   host.modelIdentifier,
            "ncpu":    host.ncpu
        ],
        "j2k_version": "J2KSwift version \(j2kVersion)",
        "lane": "inproc-jp3d",
        "runs": runs, "warmups": warmups,
        "encode": directionMap([
            (name: "J2KSwift+jp3d+inproc", pick: { $0.encode })
        ]),
        "decode": directionMap([
            (name: "J2KSwift+jp3d+full", pick: { $0.decodeFull }),
            (name: "J2KSwift+jp3d+res1", pick: { $0.decodeRes1 }),
            (name: "J2KSwift+jp3d+roiq", pick: { $0.decodeROIQuarter })
        ])
    ]
    return try? JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys])
}

func jp3dDefaultOutputName(host: HostSnapshot, version: String) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    let c = cal.dateComponents([.year, .month, .day], from: Date())
    let date = String(format: "%04d%02d%02d",
                      c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    let model = host.modelIdentifier
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: " ", with: "")
    return "benchmark-results-jp3d-\(model)-\(version)-warm-inproc-\(date).json"
}

// MARK: - Entry point (called from J2KBenchMac.main on `--jp3d`)

func runJP3DBench(args: [String]) async {
    var runs = 7
    var warmups = 2
    var quick = false
    var output: String?

    var i = 0
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
        default:
            eprint("JP3D unknown arg: \(a)")
        }
        i += 1
    }

    let host = HostSnapshot.capture()
    let version = getVersion()

    eprint("J2KBenchMac --jp3d · \(host.brand) (\(host.modelIdentifier)) · "
           + "\(host.systemName) \(host.systemVersion) · "
           + "\(host.ncpu) cores · J2KSwift \(version)")
    eprint("runs=\(runs) warmups=\(warmups)\(quick ? " (quick)" : "")")
    eprint("")

    let fixtures = quick
        ? jp3dCorpus.filter { ["mr_3d_small", "ct_3d_small",
                               "mr_3d_mid"].contains($0.id) }
        : jp3dCorpus

    var results: [JP3DFixtureResultM] = []
    for fixture in fixtures {
        eprint("→ \(fixture.id) \(fixture.label) "
               + "(\(fixture.voxels) voxels)…")
        let r = await jp3dBenchOne(fixture, runs: runs, warmups: warmups)
        if let err = r.error {
            eprint("  ! \(err)")
        } else {
            func ms(_ s: Samples) -> String {
                s.median.map { String(format: "%.2f", $0) } ?? "—"
            }
            eprint("  enc \(ms(r.encode)) ms · "
                   + "dec full \(ms(r.decodeFull)) / "
                   + "res1 \(ms(r.decodeRes1)) / "
                   + "roi1/4 \(ms(r.decodeROIQuarter)) ms · "
                   + "cs \(r.codestreamBytes) B (raw \(r.rawBytes))")
        }
        results.append(r)
    }
    eprint("")

    guard let data = buildJP3DJSON(host: host, j2kVersion: version,
                                   runs: runs, warmups: warmups,
                                   results: results) else {
        eprint("JP3D JSON build failed"); exit(1)
    }
    let path = output ?? jp3dDefaultOutputName(host: host, version: version)
    do {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        eprint("wrote \(path) (\(data.count) bytes)")
    } catch {
        eprint("write failed: \(error)"); exit(1)
    }
}
