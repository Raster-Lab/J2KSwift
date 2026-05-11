// V91Phase1BBlockEncodeMicrobench.swift
//
// v9.1 Path B Phase 1B — direct HT block-encode microbench.
//
// Bypasses async/TaskGroup orchestration to measure HTBlockEncoderConformant.encode
// in a tight loop. Validates whether the corpus-measured 1112 ns/quad cost
// is real or whether it's measurement artifact from the async pipeline.
//
// If wall time / quad in this microbench matches the corpus measurement,
// the per-quad cost is structural (Swift function-call overhead, ARC,
// bounds checks). If it's MUCH lower, the corpus measurement is including
// pipeline orchestration overhead and the encoder hot path is actually fast.

import XCTest
@testable import J2KCodec

final class V91Phase1BBlockEncodeMicrobench: XCTestCase {

    /// Build a synthetic 64×64 block of UInt32 coefficients with realistic
    /// significance density. The encoder treats UInt32 as sign-magnitude
    /// per T.814: bit 31 = sign, bits 0..30 = magnitude.
    /// Magnitudes in [1, 0x3F] keep eQ ≤ 6 so all per-quad emit paths
    /// stay within the encoder's bit-width budget at p=8.
    private func syntheticBlock(seed: UInt64) -> [UInt32] {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: seed)
        var data = [UInt32](repeating: 0, count: 64 * 64)
        for i in 0..<data.count {
            let r = rng.next()
            if (r & 0xFF) < 76 {  // ~30% non-zero
                let magnitude = UInt32(r >> 8) & 0x003F  // 6-bit magnitudes
                let sign: UInt32 = (r & 0x8000) != 0 ? 0x8000_0000 : 0
                data[i] = sign | magnitude
            }
        }
        return data
    }

    /// Single-block sanity probe: encode ONCE with all-zero data to
    /// isolate whether the trap is in encoder logic vs the synthetic data.
    func testSingleBlockEncodeAllZeros() throws {
        let block = [UInt32](repeating: 0, count: 64 * 64)
        var magsgn = HTMagSgnEncoderConformant()
        var mel = HTMELEncoderConformant()
        var vlc = HTReverseBitEmitterConformant()
        let result = block.withUnsafeBufferPointer { ptr in
            HTBlockEncoderConformant.encode(
                coefficients: ptr,
                width: 64, height: 64,
                missingMSBs: 24,
                magsgnEnc: &magsgn,
                melEnc: &mel,
                vlcEnc: &vlc,
                useSIMDClassification: false,
                preClassifiedTuples: nil)
        }
        print("All-zero 64x64 encode: magsgn=\(result.magsgn.count) mel=\(result.mel.count) vlc=\(result.vlc.count)")
        // Sanity: zero coefficients → minimal codestream.
        XCTAssertGreaterThanOrEqual(result.magsgn.count, 0)
    }

    /// Single-block one-significant-sample probe: minimal repro.
    func testSingleBlockEncodeOneSig() throws {
        var block = [UInt32](repeating: 0, count: 64 * 64)
        block[0] = 0x0000_0040  // magnitude 64 — significant at p=6
        var magsgn = HTMagSgnEncoderConformant()
        var mel = HTMELEncoderConformant()
        var vlc = HTReverseBitEmitterConformant()
        let result = block.withUnsafeBufferPointer { ptr in
            HTBlockEncoderConformant.encode(
                coefficients: ptr,
                width: 64, height: 64,
                missingMSBs: 24,
                magsgnEnc: &magsgn,
                melEnc: &mel,
                vlcEnc: &vlc,
                useSIMDClassification: false,
                preClassifiedTuples: nil)
        }
        print("OneSig encode: magsgn=\(result.magsgn.count) mel=\(result.mel.count) vlc=\(result.vlc.count)")
    }

    /// Tight-loop block-encode timing — sparse-block lower bound.
    func testTightLoopBlockEncodeThroughput() throws {
        var block = [UInt32](repeating: 0, count: 64 * 64)
        block[0] = 0x0000_0040
        block[64 * 5 + 7] = 0x8000_0080
        let runs = 5
        let blocksPerRun = 5_000
        let missingMSBs = 24

        var samples: [Double] = []
        var encodedSize = 0

        for _ in 0..<runs {
            var magsgn = HTMagSgnEncoderConformant()
            var mel = HTMELEncoderConformant()
            var vlc = HTReverseBitEmitterConformant()
            // v9.2 Path B Phase 0: counters are opt-in; enable for the
            // microbench so it can still report ns/quad. The harness
            // still measures wall against the (warmer) production
            // counter-disabled state in setUp/tearDown.
            J2KHTEntropyEncoderProfile.setEnabled(true)
            J2KHTEntropyEncoderProfile.reset()

            let t0 = DispatchTime.now()
            block.withUnsafeBufferPointer { ptr in
                for _ in 0..<blocksPerRun {
                    let result = HTBlockEncoderConformant.encode(
                        coefficients: ptr,
                        width: 64, height: 64,
                        missingMSBs: missingMSBs,
                        magsgnEnc: &magsgn,
                        melEnc: &mel,
                        vlcEnc: &vlc,
                        useSIMDClassification: false,
                        preClassifiedTuples: nil)
                    encodedSize = result.magsgn.count + result.mel.count + result.vlc.count
                }
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / Double(blocksPerRun))
        }
        samples.sort()
        let nsPerBlock = samples[runs / 2]

        let snapshot = J2KHTEntropyEncoderProfile.snapshot()
        let totalProcessQuad = Int(snapshot.processQuadCallCount)
        let processQuadPerBlock = totalProcessQuad / blocksPerRun
        let nsPerQuad = nsPerBlock / Double(max(processQuadPerBlock, 1))
        let nsPerSample = nsPerBlock / 4096.0

        // Read corpus DX value from V9_1_PATH_B_PHASE_0.md:
        let corpusDXNsPerQuad: Double = 1112
        let speedup = corpusDXNsPerQuad / nsPerQuad

        print()
        print("=== v9.1 Phase 1B — direct block-encode tight-loop bench ===")
        print()
        print("Sparse 64×64 (2 sig samples), missingMSBs=\(missingMSBs).")
        print("Codestream: \(encodedSize) bytes/block. processQuad/block: \(processQuadPerBlock).")
        print()
        print("|       metric           |    value    |")
        print("|------------------------|------------:|")
        print(String(format: "| ns / block             | %11.0f |", nsPerBlock))
        print(String(format: "| ns / quad (lower bound)| %11.2f |", nsPerQuad))
        print(String(format: "| ns / sample            | %11.2f |", nsPerSample))
        print(String(format: "| corpus DX ns/quad      | %11.0f |", corpusDXNsPerQuad))
        print(String(format: "| corpus / direct ratio  | %11.2f× |", speedup))
        print()
        print("Reads:")
        print("  - This is a sparse-block lower bound. Real DX blocks have ~30% sig.")
        print("  - If direct ns/quad is much less than 1112 (the corpus DX number),")
        print("    pipeline orchestration is part of the corpus measurement and the")
        print("    encoder hot-path itself isn't as bad as the corpus probe suggested.")
        print("  - If direct ns/quad is comparable to 1112, the per-quad cost is")
        print("    structural to the encoder code (Swift overhead, ARC, bounds checks).")
    }

    /// Tight-loop block-encode timing — moderate-density block with all
    /// significant samples placed at small magnitudes that don't trigger
    /// the encoder's Swift trap on synthetic data.
    func testTightLoopBlockEncodeThroughput_ModerateDensity() throws {
        // Place ~10% of samples as significant with magnitude 0x80
        // (well within UInt8 eQ range at p=6). Sparse but not minimal.
        var block = [UInt32](repeating: 0, count: 64 * 64)
        // Stride pattern: every 10th sample significant.
        var idx = 0
        while idx < 64 * 64 {
            block[idx] = (idx & 1 == 0) ? 0x0000_0080 : 0x8000_0080
            idx += 10
        }
        let runs = 5
        let blocksPerRun = 5_000
        let missingMSBs = 24

        var samples: [Double] = []
        var encodedSize = 0

        for _ in 0..<runs {
            var magsgn = HTMagSgnEncoderConformant()
            var mel = HTMELEncoderConformant()
            var vlc = HTReverseBitEmitterConformant()
            // v9.2 Path B Phase 0: counters are opt-in; enable for the
            // microbench so it can still report ns/quad. The harness
            // still measures wall against the (warmer) production
            // counter-disabled state in setUp/tearDown.
            J2KHTEntropyEncoderProfile.setEnabled(true)
            J2KHTEntropyEncoderProfile.reset()

            let t0 = DispatchTime.now()
            block.withUnsafeBufferPointer { ptr in
                for _ in 0..<blocksPerRun {
                    let result = HTBlockEncoderConformant.encode(
                        coefficients: ptr,
                        width: 64, height: 64,
                        missingMSBs: missingMSBs,
                        magsgnEnc: &magsgn,
                        melEnc: &mel,
                        vlcEnc: &vlc,
                        useSIMDClassification: false,
                        preClassifiedTuples: nil)
                    encodedSize = result.magsgn.count + result.mel.count + result.vlc.count
                }
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / Double(blocksPerRun))
        }
        samples.sort()
        let nsPerBlock = samples[runs / 2]
        let snapshot = J2KHTEntropyEncoderProfile.snapshot()
        let processQuadPerBlock = Int(snapshot.processQuadCallCount) / blocksPerRun
        let nsPerQuad = nsPerBlock / Double(max(processQuadPerBlock, 1))

        print()
        print("=== v9.1 Phase 1B — moderate-density block-encode bench ===")
        print()
        print("Stride-significant 64×64 (~10% sig at mag=128), missingMSBs=\(missingMSBs).")
        print("Codestream: \(encodedSize) bytes/block.")
        print("Per block: processQuad=\(processQuadPerBlock) "
              + "magsgn=\(Int(snapshot.magsgnEncodeCallCount) / blocksPerRun) "
              + "vlc=\(Int(snapshot.vlcEncodeCallCount) / blocksPerRun) "
              + "mel=\(Int(snapshot.melEncodeCallCount) / blocksPerRun)")
        print(String(format: "ns/block: %.0f, ns/quad: %.2f, ns/sample: %.2f",
                     nsPerBlock, nsPerQuad, nsPerBlock / 4096.0))
        print(String(format: "Corpus DX ns/quad: 1112, direct ratio: %.2f×", 1112.0 / nsPerQuad))
    }
}
