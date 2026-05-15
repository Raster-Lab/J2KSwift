// Pin-down for `J2KDecoder.recommendedDecodeAPI(width:height:)` policy.
//
// Calibrated against the 2026-05-15 DICOM Studio panel substitute corpus
// (DICOMKit/Tests/DICOMCoreTests/DICOMStudioPanelSubstituteTests.swift).
// Each modality's expected route is the empirically fastest decode mode
// from that run on Apple M2 v9.5.2. The old (pre-v9.6) router mis-routed
// CT, PX, DX, and MG; see J2KCodec.swift recommendedDecodeAPI rationale.

import XCTest
@testable import J2KCodec

final class RecommendedDecodeAPIRouterTests: XCTestCase {

    private func route(_ w: Int, _ h: Int) -> J2KRecommendedDecodeAPI {
        // Clear any inherited env override before reading the calibrated
        // policy. The override path is exercised separately below.
        unsetenv("J2K_AUTO_DECODE_API")
        return J2KDecoder.recommendedDecodeAPI(width: w, height: h)
    }

    // MARK: - Calibrated policy

    /// MR 128² (16 384 px) — substitute: `.cpu` 0.53 ms wins by 11.4× vs
    /// `.decodeGPU` 5.22 ms. CPU dispatch wins at sub-megapixel sizes.
    func testRoute_mr_128x128_picksCPU() {
        XCTAssertEqual(route(128, 128), .cpu)
    }

    /// CT 512² (262 144 px) — substitute: `.cpu` 2.37 ms wins by 4.93× vs
    /// `.decodeGPU` 11.56 ms. v5.27 router mis-routed this to `.decodeGPU`.
    func testRoute_ct_512x512_picksCPU() {
        XCTAssertEqual(route(512, 512), .cpu)
    }

    /// XA 1024² (1 048 576 px) — substitute: `.decodeGPU` 9.40 ms ties
    /// `.cpu` 9.56 ms; GPU lift starts to amortise around 1 MP.
    func testRoute_xa_1024x1024_picksDecodeGPU() {
        XCTAssertEqual(route(1024, 1024), .decodeGPU)
    }

    /// PX 2793×1316 (3.67 MP) — substitute: `.decodeGPU` 35.95 ms wins by
    /// 3.29× vs `.decodeWithGPUHT` 118.18 ms. v5.27 router mis-routed
    /// this to `.decodeWithGPUHT`.
    func testRoute_px_2793x1316_picksDecodeGPU() {
        XCTAssertEqual(route(2793, 1316), .decodeGPU)
    }

    /// DX 2544×3056 (7.77 MP) — substitute: `.decodeGPU` 70.01 ms wins
    /// by 1.85× vs `.decodeWithGPUHT` 129.26 ms. v5.27 router mis-routed
    /// this to `.decodeWithGPUHT`.
    func testRoute_dx_2544x3056_picksDecodeGPU() {
        XCTAssertEqual(route(2544, 3056), .decodeGPU)
    }

    /// MG 3520×4784 (16.84 MP) — substitute: `.cpu` 125.93 ms wins over
    /// `.decodeGPU` 132.15 ms and `.decodeWithGPUHT` 127.83 ms. Memory
    /// bandwidth saturates GPU before dispatch overhead pays back.
    /// v5.27 router mis-routed this to `.decodeWithGPUHT`.
    func testRoute_mg_3520x4784_picksCPU() {
        XCTAssertEqual(route(3520, 4784), .cpu)
    }

    // MARK: - Threshold boundaries

    /// Below the small-image threshold (500 K px): always CPU.
    func testRoute_belowSmallThreshold_picksCPU() {
        XCTAssertEqual(route(700, 700), .cpu)         // 490 000 px
        XCTAssertEqual(route(1, 1), .cpu)
        XCTAssertEqual(route(256, 256), .cpu)         // ex-boundary, old router flipped here
    }

    /// At the small-image boundary (500 K px): `.decodeGPU`.
    func testRoute_atSmallThreshold_picksDecodeGPU() {
        XCTAssertEqual(route(708, 707), .decodeGPU)   // 500 556 px
        XCTAssertEqual(route(800, 800), .decodeGPU)   // 640 000 px
    }

    /// At the large-image boundary (15 MP): flips back to CPU.
    func testRoute_atLargeThreshold_picksCPU() {
        XCTAssertEqual(route(4000, 4000), .cpu)       // 16 000 000 px
        XCTAssertEqual(route(5000, 5000), .cpu)       // 25 000 000 px
    }

    /// Just below the large-image threshold: still `.decodeGPU`.
    func testRoute_justBelowLargeThreshold_picksDecodeGPU() {
        XCTAssertEqual(route(3800, 3900), .decodeGPU) // 14 820 000 px
    }

    // MARK: - Env override

    /// `J2K_AUTO_DECODE_API=cpu` forces `.cpu` regardless of size.
    func testEnvOverride_cpu_alwaysCPU() {
        setenv("J2K_AUTO_DECODE_API", "cpu", 1)
        defer { unsetenv("J2K_AUTO_DECODE_API") }
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 2793, height: 1316), .cpu)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .cpu)
    }

    /// `J2K_AUTO_DECODE_API=decodeGPU` forces `.decodeGPU` regardless
    /// of size; alias `gpu` accepted.
    func testEnvOverride_decodeGPU_alwaysGPU() {
        setenv("J2K_AUTO_DECODE_API", "decodeGPU", 1)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .decodeGPU)
        setenv("J2K_AUTO_DECODE_API", "gpu", 1)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .decodeGPU)
        unsetenv("J2K_AUTO_DECODE_API")
    }

    /// `J2K_AUTO_DECODE_API=decodeWithGPUHT` forces full-GPU regardless
    /// of size (provides an escape hatch for future-silicon experiments
    /// where the GPU HT crossover may differ from M2 v9.5.2).
    func testEnvOverride_decodeWithGPUHT_alwaysGPUHT() {
        setenv("J2K_AUTO_DECODE_API", "decodeWithGPUHT", 1)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .decodeWithGPUHT)
        setenv("J2K_AUTO_DECODE_API", "gpuht", 1)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .decodeWithGPUHT)
        unsetenv("J2K_AUTO_DECODE_API")
    }

    /// Unrecognised override values fall through to the calibrated policy.
    func testEnvOverride_unrecognised_fallsThrough() {
        setenv("J2K_AUTO_DECODE_API", "bogus-value", 1)
        defer { unsetenv("J2K_AUTO_DECODE_API") }
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 128, height: 128), .cpu)
        XCTAssertEqual(J2KDecoder.recommendedDecodeAPI(width: 2544, height: 3056), .decodeGPU)
    }

    // MARK: - Anti-regression

    /// `.decodeWithGPUHT` must NOT be auto-recommended on M2 v9.5.2 for
    /// any size in the calibrated substitute corpus. This pin protects
    /// against an accidental re-introduction of the v5.27 router shape.
    func testAutoRouter_neverPicksDecodeWithGPUHT_inSubstituteCorpus() {
        let cases: [(Int, Int)] = [
            (128, 128),
            (512, 512),
            (1024, 1024),
            (2793, 1316),
            (2544, 3056),
            (3520, 4784)
        ]
        for (w, h) in cases {
            XCTAssertNotEqual(
                route(w, h),
                .decodeWithGPUHT,
                "Router must not recommend .decodeWithGPUHT for \(w)x\(h) on M2 v9.5.2 calibration."
            )
        }
    }
}
