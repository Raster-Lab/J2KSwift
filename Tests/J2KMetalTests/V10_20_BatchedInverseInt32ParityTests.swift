//
// V10_20_BatchedInverseInt32ParityTests.swift
// J2KSwift
//
// v10.20-research Phase 2 — bit-exact parity oracle for the new
// `J2KMetalDWT.inverseBatched2DInt32` API.
//
// Specification (bit-exact):
//     inverseBatched2DInt32(subbandsBatch: [a, b, c])[i] ≡
//        inverse2DInt32(subbands: subbandsBatch[i], backend: .gpu)
// for every i, on every subband shape the JP3D slice-stack codec
// emits.
//
// The batched dispatch must produce per-slice output byte-identical
// to the existing tiled single-image dispatch — Phase 2's claim
// rests entirely on this property. If parity ever fails, JP3D's
// Phase 3 wiring will produce wrong voxels, so we gate hard.

import XCTest
@testable import J2KCore
@testable import J2KMetal

@MainActor
final class V10_20_BatchedInverseInt32ParityTests: XCTestCase {

    // MARK: - Subband builder

    /// Build a J2KMetalDWTSubbandsInt32 from a deterministic per-slice
    /// seed. Layout mirrors the post-dequant shape the v10.20 bridge
    /// SPI hands off: LL/HL/LH/HH split into the standard band
    /// dimensions, originalWidth × originalHeight final iDWT output.
    private func makeSubbands(
        originalWidth: Int, originalHeight: Int, seed: UInt64
    ) -> J2KMetalDWTSubbandsInt32 {
        let llW = (originalWidth + 1) / 2
        let llH = (originalHeight + 1) / 2
        let hlW = llW
        let hlH = originalHeight / 2
        let lhW = originalWidth / 2
        let lhH = llH
        let hhW = originalWidth / 2
        let hhH = originalHeight / 2

        var rng = seed &* 6364136223846793005 &+ 1442695040888963407
        func fill(_ w: Int, _ h: Int) -> [Int32] {
            (0..<(w * h)).map { _ in
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                let v = Int32(truncatingIfNeeded: Int((rng >> 16) & 0xFFFF)) - 16384
                return v
            }
        }

        return J2KMetalDWTSubbandsInt32(
            ll: fill(llW, llH),
            lh: fill(lhW, lhH),
            hl: fill(hlW, hlH),
            hh: fill(hhW, hhH),
            llWidth: llW, llHeight: llH,
            originalWidth: originalWidth, originalHeight: originalHeight)
    }

    // MARK: - Tests

    /// Single-slice batch — must be byte-identical to the serial path.
    /// Establishes the baseline before testing multi-slice.
    func testBatchedOfOneEqualsSerial_256x256() async throws {
        let dwt = J2KMetalDWT()
        let sub = makeSubbands(originalWidth: 256, originalHeight: 256, seed: 7)

        let serial = try await dwt.inverse2DInt32(subbands: sub, backend: .gpu)
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: [sub])

        XCTAssertEqual(batched.count, 1)
        XCTAssertEqual(serial, batched[0],
                       "Single-slice batched output diverges from serial")
    }

    /// 2-slice batch — each slice's output must match its serial decode.
    func testBatchedOfTwoEqualsSerial_256x256() async throws {
        let dwt = J2KMetalDWT()
        let subA = makeSubbands(originalWidth: 256, originalHeight: 256, seed: 1)
        let subB = makeSubbands(originalWidth: 256, originalHeight: 256, seed: 2)

        let serialA = try await dwt.inverse2DInt32(subbands: subA, backend: .gpu)
        let serialB = try await dwt.inverse2DInt32(subbands: subB, backend: .gpu)
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: [subA, subB])

        XCTAssertEqual(batched.count, 2)
        XCTAssertEqual(serialA, batched[0], "Slice 0 batched diverges from serial")
        XCTAssertEqual(serialB, batched[1], "Slice 1 batched diverges from serial")
    }

    /// 16-slice batch — typical JP3D mid-volume slice count. Confirms
    /// the Z grid dimension scales correctly without aliasing across
    /// slices.
    func testBatchedOfSixteenEqualsSerial_256x256() async throws {
        let dwt = J2KMetalDWT()
        var subs: [J2KMetalDWTSubbandsInt32] = []
        var serials: [[Int32]] = []
        for s in 0..<16 {
            let sub = makeSubbands(originalWidth: 256, originalHeight: 256,
                                    seed: UInt64(0xDEAD0000 + s))
            subs.append(sub)
            serials.append(try await dwt.inverse2DInt32(subbands: sub, backend: .gpu))
        }
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: subs)

        XCTAssertEqual(batched.count, 16)
        for s in 0..<16 {
            XCTAssertEqual(serials[s], batched[s],
                           "Slice \(s) batched diverges from serial")
        }
    }

    /// Larger dim (typical JP3D thorax CT slice) — sanity that the
    /// batched dispatch handles realistic medical-scan sizes.
    func testBatchedOfFourEqualsSerial_512x512() async throws {
        let dwt = J2KMetalDWT()
        var subs: [J2KMetalDWTSubbandsInt32] = []
        var serials: [[Int32]] = []
        for s in 0..<4 {
            let sub = makeSubbands(originalWidth: 512, originalHeight: 512,
                                    seed: UInt64(0xBEEF0000 + s))
            subs.append(sub)
            serials.append(try await dwt.inverse2DInt32(subbands: sub, backend: .gpu))
        }
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: subs)

        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            XCTAssertEqual(serials[s], batched[s],
                           "Slice \(s) batched 512×512 diverges from serial")
        }
    }

    /// Non-square dims — verifies the batched dispatch doesn't assume
    /// square slices.
    func testBatchedNonSquareEqualsSerial_128x320() async throws {
        let dwt = J2KMetalDWT()
        var subs: [J2KMetalDWTSubbandsInt32] = []
        var serials: [[Int32]] = []
        for s in 0..<3 {
            let sub = makeSubbands(originalWidth: 128, originalHeight: 320,
                                    seed: UInt64(0xCAFE0000 + s))
            subs.append(sub)
            serials.append(try await dwt.inverse2DInt32(subbands: sub, backend: .gpu))
        }
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: subs)

        for s in 0..<3 {
            XCTAssertEqual(serials[s], batched[s],
                           "Slice \(s) batched 128×320 diverges from serial")
        }
    }

    /// Mixed-dimension batch throws — JP3D slices share dimensions
    /// per JP3DSliceStackCodec wire format; mixed dims through the SPI
    /// is rejected so the caller can't silently produce wrong output.
    func testMixedDimensionBatchThrows() async throws {
        let dwt = J2KMetalDWT()
        let subA = makeSubbands(originalWidth: 256, originalHeight: 256, seed: 1)
        let subB = makeSubbands(originalWidth: 128, originalHeight: 128, seed: 2)

        do {
            _ = try await dwt.inverseBatched2DInt32(subbandsBatch: [subA, subB])
            XCTFail("Mixed-dimension batch should have thrown invalidParameter")
        } catch J2KError.invalidParameter {
            // Expected
        } catch {
            XCTFail("Wrong error type for mixed dims: \(error)")
        }
    }

    /// Empty batch returns empty result without crashing.
    func testEmptyBatchReturnsEmpty() async throws {
        let dwt = J2KMetalDWT()
        let batched = try await dwt.inverseBatched2DInt32(subbandsBatch: [])
        XCTAssertEqual(batched.count, 0)
    }
}
