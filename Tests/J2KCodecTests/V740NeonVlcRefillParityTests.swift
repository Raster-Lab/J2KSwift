// V740NeonVlcRefillParityTests.swift
//
// v7.4 NEON VLC refill — bit-exact parity between scalar and SWAR-
// batched VLC refill. The VLC reverse reader is fileprivate inside
// J2KHTConformantBlockDecoder, so we drive both paths through the
// public block-decode entry point (`HTBlockDecoderConformant.decode`)
// and compare full coefficient outputs. Any divergence in the
// VLC-refill state machine would surface as a wrong-rho or
// wrong-codeword decode and fail at the coefs[] level.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V740NeonVlcRefillParityTests: XCTestCase {

    private func makeBlock(
        width: Int, height: Int,
        sigDensity: Double, missingMSBs: Int,
        seed: UInt64
    ) throws -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        let n = width * height
        var coeffs = [UInt32](repeating: 0, count: n)
        let sigThreshold = UInt64(sigDensity * Double(UInt64.max))
        let p = 30 - missingMSBs
        let minMag: UInt32 = UInt32(1) << p
        let extraBits = min(3, 30 - p)
        let extraMask: UInt32 = extraBits >= 31 ? 0 : ((UInt32(1) << extraBits) - 1)
        for i in 0..<n {
            if rng.next() < sigThreshold {
                let extra = UInt32(rng.next() & UInt64(extraMask))
                let sign: UInt32 = (rng.next() & 1 != 0) ? 0x8000_0000 : 0
                coeffs[i] = sign | (minMag &+ extra)
            }
        }
        let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coeffs, width: width, height: height,
            missingMSBs: missingMSBs)
        return try HTBlockLayoutConformant.assemble(
            magsgn: magsgn, mel: mel, vlc: vlc)
    }

    private func assertParity(
        block: [UInt8], width: Int, height: Int, missingMSBs: Int,
        label: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let prev = VLCReverseReaderTesting.batchedRefillEnabled
        defer { VLCReverseReaderTesting.batchedRefillEnabled = prev }

        VLCReverseReaderTesting.batchedRefillEnabled = false
        let scalar = try HTBlockDecoderConformant.decode(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs)

        VLCReverseReaderTesting.batchedRefillEnabled = true
        let batched = try HTBlockDecoderConformant.decode(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs)

        XCTAssertEqual(scalar.count, batched.count,
            "[\(label)] output length mismatch", file: file, line: line)
        for i in 0..<min(scalar.count, batched.count) {
            if scalar[i] != batched[i] {
                XCTFail("[\(label)] coef[\(i)] differs: " +
                    "scalar=0x\(String(scalar[i], radix: 16)) " +
                    "batched=0x\(String(batched[i], radix: 16))",
                    file: file, line: line)
                return
            }
        }
    }

    func testParity_AcrossBitDepths() throws {
        for missingMSBs in [0, 4, 8, 14, 18, 24, 28] {
            let block = try makeBlock(
                width: 32, height: 32,
                sigDensity: 0.30, missingMSBs: missingMSBs,
                seed: 0xC0FFEE_C0FFEE)
            try assertParity(
                block: block, width: 32, height: 32,
                missingMSBs: missingMSBs,
                label: "missingMSBs=\(missingMSBs)")
        }
    }

    func testParity_AcrossDensities() throws {
        for d in [0.0, 0.05, 0.10, 0.30, 0.50, 0.75, 0.95] {
            let block = try makeBlock(
                width: 64, height: 64,
                sigDensity: d, missingMSBs: 14,
                seed: 0x1234_5678_9ABC_DEF0)
            try assertParity(
                block: block, width: 64, height: 64,
                missingMSBs: 14,
                label: "density=\(d)")
        }
    }

    func testParity_AcrossBlockSizes() throws {
        for (w, h) in [(4, 4), (8, 8), (16, 16), (32, 32), (64, 64),
                       (32, 16), (16, 32), (64, 32), (32, 64)] {
            let block = try makeBlock(
                width: w, height: h,
                sigDensity: 0.30, missingMSBs: 14,
                seed: UInt64(w &* 1_000 &+ h))
            try assertParity(
                block: block, width: w, height: h,
                missingMSBs: 14,
                label: "\(w)×\(h)")
        }
    }

    func testParity_RandomSweep64Seeds() throws {
        for seedIdx in 0..<64 {
            let seed = UInt64(seedIdx) &* 0x9E37_79B9_7F4A_7C15 | 1
            let block = try makeBlock(
                width: 32, height: 32,
                sigDensity: 0.40, missingMSBs: 14,
                seed: seed)
            try assertParity(
                block: block, width: 32, height: 32,
                missingMSBs: 14,
                label: "seed=\(seedIdx)")
        }
    }

    func testParity_FullCorpusEndToEnd() async throws {
        let fixtures: [(label: String, filename: String)] = [
            ("MR-small 180²",  "mr_study_002_instance_000100.pgm"),
            ("CT 512²",        "ct_study_001_instance_000001.pgm"),
            ("MR 886²",        "mr_study_001_instance_000001.pgm"),
            ("XA 1024²",       "xa_study_001_instance_000001.pgm"),
            ("PX 2459×1316",   "px_study_001_instance_000001.pgm"),
            ("DX 2800×2288",   "dx_study_002_instance_000001.pgm"),
        ]
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)

        for fix in fixtures {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await J2KEncoder(encodingConfiguration: cfg)
                .encode(image)

            let prev = VLCReverseReaderTesting.batchedRefillEnabled
            defer { VLCReverseReaderTesting.batchedRefillEnabled = prev }

            VLCReverseReaderTesting.batchedRefillEnabled = false
            let scalarImage = try await J2KDecoder().decode(codestream)
            VLCReverseReaderTesting.batchedRefillEnabled = true
            let batchedImage = try await J2KDecoder().decode(codestream)

            XCTAssertEqual(scalarImage.width, batchedImage.width)
            XCTAssertEqual(scalarImage.height, batchedImage.height)
            for (sc, ne) in zip(scalarImage.components, batchedImage.components) {
                XCTAssertEqual(sc.data, ne.data,
                    "[\(fix.label)] component data differs scalar vs batched")
            }
        }
    }

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 {
                while i < raw.count, raw[i] != 0x0A { i += 1 }
                continue
            }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
