// Smoke test: encodeWithPacketIndex must produce byte-identical output
// to encode() for the same configuration.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KEncodeWithPacketIndexParityTests: XCTestCase {

    private func makeSyntheticImage(width: Int = 64, height: Int = 64) -> J2KImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt16((x * 251 + y * 17) & 0xFFFF)
                bytes.append(UInt8((v >> 8) & 0xFF))
                bytes.append(UInt8(v & 0xFF))
            }
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: Data(bytes), sampleByteOrder: .bigEndian)])
    }

    /// Sweep qstep values on a real fixture to find which qstep
    /// regimes produce decodable output.
    func testQstepSweep_PX001_DecodeSurvives() async throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/px_study_001_instance_000001.pgm")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("px_001 fixture not found")
        }
        let data = try Data(contentsOf: fixture)
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        let img = J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])

        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)

        for q in [60.0, 30.0, 14.6, 5.04, 2.52, 1.0, 0.5, 0.1] {
            cfg.bitrateMode = .fixedQstep(qstep: q)
            let pipeline = EncoderPipeline(config: cfg)
            let indexed = try await pipeline.encodeWithPacketIndex(img)
            do {
                let decoded = try await J2KDecoder().decode(indexed.data)
                print("qstep=\(q): \(indexed.data.count) bytes, decoded \(decoded.width)×\(decoded.height) OK")
            } catch {
                print("qstep=\(q): \(indexed.data.count) bytes, DECODE FAILED: \(error)")
            }
        }
    }

    func testParity_FixedQstepHTConformant() async throws {
        let img = makeSyntheticImage()
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .fixedQstep(qstep: 1.0)

        let pipeline = EncoderPipeline(config: cfg)
        let regular = try await pipeline.encode(img)
        let indexed = try await pipeline.encodeWithPacketIndex(img)

        XCTAssertEqual(regular.count, indexed.data.count,
            "encodeWithPacketIndex must produce same length as encode")
        XCTAssertEqual(regular, indexed.data,
            "encodeWithPacketIndex must produce byte-identical output to encode")

        // Both must decode
        let decoded = try await J2KDecoder().decode(indexed.data)
        XCTAssertEqual(decoded.width, img.width)
        XCTAssertEqual(decoded.height, img.height)

        // Packet index sanity
        XCTAssertEqual(indexed.packetEndOffsets.count,
            6,  // 5 decomposition levels + 1 LL → 6 packets per component
            "expected 6 packets for 1-component 5-level decomposition")
        XCTAssertGreaterThan(indexed.tileDataOffset, 0)
        XCTAssertLessThan(indexed.tileDataOffset, indexed.data.count)
        // Last packet end should be just before EOC
        XCTAssertEqual(
            indexed.packetEndOffsets.last!,
            indexed.data.count - 2,  // -2 for EOC marker
            "last packet should end at EOC start")
    }
}
