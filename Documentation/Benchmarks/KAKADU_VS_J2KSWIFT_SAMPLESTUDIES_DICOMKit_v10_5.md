# Kakadu vs J2KSwift — DICOMKit SampleStudies cross-codec (v10.5-research)

- **Source test:** [`KakaduJ2KSwiftSampleStudiesTests.swift`](file:///Users/raster/Documents/raster/DICOMKit/Tests/DICOMCoreTests/KakaduJ2KSwiftSampleStudiesTests.swift)
- **Run:** 2026-05-15, Apple M2; `swift test --filter DICOMCoreTests --no-parallel` (**DEBUG build**)
- **J2KSwift consumed:** local path dep → `v10.5-research` (= v10.1.0 codec bits + iOS bench scaffolding). _The printed header line `J2KSwift: per Package.resolved (URL dep, from: 5.21.0)` is hardcoded in the test source and is stale — ignore._
- **Methodology:** 2 untimed warmups + 7 timed runs, median of 7 (DispatchTime ns clock). J2KSwift encode = CPU, single reused `J2KEncoder` per fixture. Routes: 15×CPU + 7×decodeGPU + 4×decodeWithGPUHT.
- **Wall:** 3 655.8 s (~61 min) for the single test.
- **Parity:** ✅ **26 / 26** fixtures bit-exact (Kakadu ↔ J2KSwift ↔ source).

## Per-fixture (median ms; Kak/J2K = factor Kakadu is faster than J2KSwift on decode)

| Label | Dim | Route | Raw | J2K bytes | Ratio | Enc ms | J2K Dec ms | Kak Dec ms | Kak/J2K |
|---|---|---|---|---|---|---|---|---|---|
| CT-001..010 | 512×512 16-b | CPU | 5.00 MB | 1.43 MB | 3.51–3.55× | 712–745 | 624–661 | 7.73–8.48 | 76–84× |
| MR-001..005 | 128×128 12-b | CPU | 160 KB | 101 KB | 1.56–1.62× | 53–57 | 69–74 | 4.60–4.97 | 14–16× |
| XA-001..002 | 1024×1024 12-b | decodeGPU | 4.00 MB | 1.20 MB | 3.11–3.61× | 3 183–3 716 | 1 994–2 328 | 22.19–24.76 | 90–94× |
| PX-001 | 2793×1316 12-b | decodeGPU | 7.01 MB | 2.81 MB | 2.50× | 7 483 | 6 095 | 79.33 | 77× |
| DX-001..002 | 2544×3056 12-b | decodeGPU | 14.83 MB | 7.34 / 7.39 MB | 2.01–2.02× | 19 459 / 20 013 | 15 312 / 16 337 | 168.03 / 182.06 | 90–91× |
| MG-001..002 | 3520×4784 12-b | decodeGPU | 32.12 / 32.09 MB | 5.19 / 5.89 MB | 5.45–6.19× | 26 178 / 29 388 | 19 261 / 21 285 | 145.95 / 150.51 | 132–141× |
| DX-001..002-HT | 2544×3056 12-b | decodeWithGPUHT | 14.83 MB | 7.34 / 7.39 MB | 2.01–2.02× | 19 888 / 20 000 | 15 627 / 16 087 | 170.31 / 186.36 | 86–92× |
| MG-001..002-HT | 3520×4784 12-b | decodeWithGPUHT | 32.12 / 32.09 MB | 5.19 / 5.89 MB | 5.45–6.19× | 27 591 / 30 350 | 24 109 / 24 446 | 148.92 / 171.34 | 142–162× |
| **Total** | — | mixed | **203.90 MB** | **57.16 MB** | **3.57×** | **214 840** | **169 631** | **1 555** | **109.1×** |

## Read this with care

- **The decode gap is a debug-build artifact.** The canonical release-mode warm-in-process picture is in [`CROSS_HOST_M2_M4_v10_1_0_inproc.md`](CROSS_HOST_M2_M4_v10_1_0_inproc.md): on M2, **J2KSwift+inproc is the lowest-median decoder on 27/38 fixtures** (Kakadu 7, Grok 4); release-warm encode wins 30/38 on M2 (Kakadu 8). The 14–162× factors here come from `swift test` building debug (no `-O`) while Kakadu runs from its release binary. **This run is a parity check, not a perf claim.**
- **`J2KSwiftCodec.preWarm()` is not called here.** The DICOMKit production app calls it at startup ([DICOMStudioApp.swift](file:///Users/raster/Documents/raster/DICOMKit/Sources/DICOMStudio/App/DICOMStudioApp.swift)); this test only warms within the per-fixture loop.
- Per [`DICOM_STUDIO_CLAIM_SCOPE_FINDING.md`](DICOM_STUDIO_CLAIM_SCOPE_FINDING.md), do not lift these numbers into product positioning. They confirm cross-codec correctness on real DICOM payloads. For perf claims, cite `CROSS_HOST_M2_M4_v10_1_0_*.md` and `Scripts/benchmarks/cross_codec_warm_bench.py` output.
