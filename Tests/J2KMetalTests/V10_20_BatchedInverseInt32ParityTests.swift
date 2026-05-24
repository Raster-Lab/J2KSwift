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

    // MARK: - Multi-level batched parity (Phase 3a)

    /// Build a multi-level subband chain for testing the multi-level
    /// orchestrator. The level-chain invariant: at level k, ll dim
    /// equals level k-1's original dim. We build innermost-first.
    private func makeMultiLevelChain(
        finalWidth: Int, finalHeight: Int, levels: Int, seed: UInt64
    ) -> [J2KMetalDWTSubbandsInt32] {
        // Compute per-level dims: level (levels-1) has original =
        // finalW × finalH; level 0 (innermost) has original = finalW/2^(levels-1).
        var dims: [(w: Int, h: Int)] = []
        var w = finalWidth
        var h = finalHeight
        var stack: [(Int, Int)] = [(w, h)]
        for _ in 1..<levels {
            w = (w + 1) / 2
            h = (h + 1) / 2
            stack.append((w, h))
        }
        // Innermost first → reverse
        for (lw, lh) in stack.reversed() {
            dims.append((lw, lh))
        }

        var chain: [J2KMetalDWTSubbandsInt32] = []
        var rng = seed
        for k in 0..<levels {
            let (origW, origH) = dims[k]
            let llW: Int
            let llH: Int
            if k == 0 {
                llW = (origW + 1) / 2
                llH = (origH + 1) / 2
            } else {
                // Level k's LL = level k-1's output (full original)
                llW = dims[k - 1].w
                llH = dims[k - 1].h
            }
            // Wait — per JPEG 2000 the level-chain invariant is that
            // level k's `ll` IS the previous level's full output. So
            // level k's `ll` dims = level k-1's `original` dims; and
            // level k's `original` = 2× level k-1's original (roughly).
            // The dims I built starting from finalW/H and halving are
            // backwards relative to that convention. Let me rebuild:
            // level 0 (innermost) has its own original = smallest;
            // level k's ll dims = level k-1's original; level k's
            // original = ll dims doubled to reach next level out.
            _ = llW; _ = llH
            // The simpler test pattern: just construct each level's
            // ll/lh/hl/hh with the standard partition based on its
            // own (original, ll) dim pair, and let the level chain
            // be enforced by the orchestrator's validation.
            let myLLW: Int
            let myLLH: Int
            if k == 0 {
                myLLW = (origW + 1) / 2
                myLLH = (origH + 1) / 2
            } else {
                myLLW = dims[k - 1].w
                myLLH = dims[k - 1].h
            }
            let myHLW = myLLW
            let myHLH = origH - myLLH
            let myLHW = origW - myLLW
            let myLHH = myLLH
            let myHHW = origW - myLLW
            let myHHH = origH - myLLH

            func fill(_ count: Int) -> [Int32] {
                (0..<count).map { _ in
                    rng = rng &* 6364136223846793005 &+ 1442695040888963407
                    return Int32(truncatingIfNeeded: Int((rng >> 16) & 0xFFFF)) - 16384
                }
            }
            let ll = fill(myLLW * myLLH)
            let lh = max(0, myLHW * myLHH) > 0 ? fill(myLHW * myLHH) : []
            let hl = max(0, myHLW * myHLH) > 0 ? fill(myHLW * myHLH) : []
            let hh = max(0, myHHW * myHHH) > 0 ? fill(myHHW * myHHH) : []
            chain.append(J2KMetalDWTSubbandsInt32(
                ll: ll, lh: lh, hl: hl, hh: hh,
                llWidth: myLLW, llHeight: myLLH,
                originalWidth: origW, originalHeight: origH))
        }
        return chain
    }

    /// **Spec**: the multi-level batched orchestrator's per-slice
    /// output equals the per-slice serial multi-level orchestrator's
    /// output, byte-exact, on every slice in the batch.
    func testMultiLevelBatchedOfOneEqualsSerial_256x256_3levels() async throws {
        let dwt = J2KMetalDWT()
        let chain = makeMultiLevelChain(
            finalWidth: 256, finalHeight: 256, levels: 3, seed: 11)

        let serial = try await dwt.inverse2DInt32MultiLevelFused(
            subbandsPerLevel: chain)
        let batched = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: [chain])

        XCTAssertEqual(batched.count, 1)
        XCTAssertEqual(serial, batched[0],
                       "Multi-level batched-of-one diverges from serial")
    }

    func testMultiLevelBatchedOfFourEqualsSerial_256x256_3levels() async throws {
        let dwt = J2KMetalDWT()
        var batch: [[J2KMetalDWTSubbandsInt32]] = []
        var serials: [[Int32]] = []
        for s in 0..<4 {
            let chain = makeMultiLevelChain(
                finalWidth: 256, finalHeight: 256, levels: 3,
                seed: UInt64(0xABCD0000 + s))
            batch.append(chain)
            serials.append(try await dwt.inverse2DInt32MultiLevelFused(
                subbandsPerLevel: chain))
        }
        let batched = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: batch)

        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            XCTAssertEqual(serials[s], batched[s],
                           "Multi-level batched slice \(s) diverges from serial")
        }
    }

    /// Targeted reproducer for the Phase 3b SIGSEGV: 16 slices,
    /// 256×256, 3 levels — exactly matches the bench fixture that
    /// failed. Innermost dim is 64×64 (above the smallDimThreshold).
    func testMultiLevelBatched_16slices_256x256_3levels() async throws {
        let dwt = J2KMetalDWT()
        var batch: [[J2KMetalDWTSubbandsInt32]] = []
        var serials: [[Int32]] = []
        for s in 0..<16 {
            let chain = makeMultiLevelChain(
                finalWidth: 256, finalHeight: 256, levels: 3,
                seed: UInt64(0x12340000 + s))
            batch.append(chain)
            serials.append(try await dwt.inverse2DInt32MultiLevelFused(
                subbandsPerLevel: chain))
        }
        let batched = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: batch)

        XCTAssertEqual(batched.count, 16)
        for s in 0..<16 {
            XCTAssertEqual(serials[s], batched[s],
                           "16-slice batched diverges at slice \(s)")
        }
    }

    /// Single-shot timing comparison (release-mode). Not a regression
    /// gate — just prints timings + asserts bit-exactness. The
    /// looped-bench shape SIGSEGV'd intermittently during Phase 3b
    /// investigation (a Metal-state accumulation under repeated
    /// invocation that needs separate root-causing); a single-shot
    /// measurement avoids the trigger and still gives a directional
    /// signal on whether batched dispatch beats per-slice serial at
    /// JP3D-typical fixture sizes.
    func testMultiLevelBatchedVsSerialSingleShotTiming_16slices_256x256_3levels() async throws {
        let dwt = J2KMetalDWT()
        var batch: [[J2KMetalDWTSubbandsInt32]] = []
        for s in 0..<16 {
            batch.append(makeMultiLevelChain(
                finalWidth: 256, finalHeight: 256, levels: 3,
                seed: UInt64(0xABCD0000 + s)))
        }

        // Warm both paths with a parity check (also acts as warmup).
        var serials: [[Int32]] = []
        for chain in batch {
            serials.append(try await dwt.inverse2DInt32MultiLevelFused(
                subbandsPerLevel: chain))
        }
        let batchedWarmup = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: batch)
        for s in 0..<batch.count {
            XCTAssertEqual(serials[s], batchedWarmup[s],
                           "Parity warmup slice \(s) diverges")
        }

        // Single-shot timing.
        let t0 = DispatchTime.now().uptimeNanoseconds
        for chain in batch {
            _ = try await dwt.inverse2DInt32MultiLevelFused(subbandsPerLevel: chain)
        }
        let t1 = DispatchTime.now().uptimeNanoseconds
        let serialMS = Double(t1 - t0) / 1_000_000.0

        let t2 = DispatchTime.now().uptimeNanoseconds
        _ = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: batch)
        let t3 = DispatchTime.now().uptimeNanoseconds
        let batchedMS = Double(t3 - t2) / 1_000_000.0

        print("\nV10_20 Phase 3 single-shot timing (16 slices × 256×256 × 3 levels):")
        print(String(format: "  serial : %7.2f ms (16 per-slice multi-level dispatches)", serialMS))
        print(String(format: "  batched: %7.2f ms (1 multi-level batched dispatch)", batchedMS))
        print(String(format: "  ratio  : %.2fx (batched / serial — <1.0 means batched wins)",
                     batchedMS / serialMS))
    }

    /// 5 decomposition levels at 512×512 — typical JP3D slice config.
    func testMultiLevelBatchedOfEightEqualsSerial_512x512_5levels() async throws {
        let dwt = J2KMetalDWT()
        var batch: [[J2KMetalDWTSubbandsInt32]] = []
        var serials: [[Int32]] = []
        for s in 0..<8 {
            let chain = makeMultiLevelChain(
                finalWidth: 512, finalHeight: 512, levels: 5,
                seed: UInt64(0xFADE0000 + s))
            batch.append(chain)
            serials.append(try await dwt.inverse2DInt32MultiLevelFused(
                subbandsPerLevel: chain))
        }
        let batched = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: batch)

        XCTAssertEqual(batched.count, 8)
        for s in 0..<8 {
            XCTAssertEqual(serials[s], batched[s],
                           "Multi-level batched 512×512 5L slice \(s) diverges from serial")
        }
    }
}
