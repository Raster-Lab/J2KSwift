# J2K vs HTJ2K Lossless — size comparison on 10 reference DICOMs (v10.5-research)

- **Source test:** [`J2KvsHTJ2KCompressionReportTests.swift`](file:///Users/raster/Documents/raster/DICOMKit/Tests/DICOMCoreTests/J2KvsHTJ2KCompressionReportTests.swift)
- **Run:** 2026-05-15, Apple M2; `swift test --filter DICOMCoreTests --no-parallel`
- **J2KSwift consumed:** local path dep → `v10.5-research` (= v10.1.0 codec bits)
- **Methodology:** both columns produced by the **same** `J2KSwiftCodec`, varying only the transfer syntax UID (`jpeg2000Lossless` vs `htj2kLossless`). Size-only — no timing.
- **Wall:** 229.2 s
- **Corpus:** 10 single-instance DICOMs from `DICOMKit/LocalDatasets/medical-dicom-organized` covering CT (×2), DX (×2), MG (×2), MR (×2), PX, XA. Most fixtures are 12-bit stored, CT pair is 16-bit.

## Per-fixture

| # | Fixture | Modality | Dim | DICOM (in) | J2K Lossless | HTJ2K Lossless | HTJ2K Δ |
|---|---|---|---|---|---|---|---|
| 1 | ct/study_001/instance_001 | CT | 512×512 | 516.4 KB | 144.3 KB | 158.0 KB | +9.5% |
| 2 | ct/study_003/instance_050 | CT | 512×512 | 516.5 KB | 145.4 KB | 158.2 KB | +8.8% |
| 3 | dx/study_001/instance_001 | DX | 2544×3056 | 14.88 MB | 7.34 MB | 7.63 MB | +4.0% |
| 4 | dx/study_002/instance_001 | DX | 2800×2288 | 12.23 MB | 4.87 MB | 5.13 MB | +5.3% |
| 5 | mg/study_001/instance_001 | MG | 3520×4784 | 32.14 MB | 5.19 MB | 5.37 MB | +3.5% |
| 6 | mg/study_002/instance_001 | MG | 3521×4784 | 32.15 MB | 8.35 MB | 8.60 MB | +3.0% |
| 7 | mr/study_001/instance_001 | MR | 886×886 | 1.60 MB | 66.0 KB | 72.6 KB | +10.0% |
| 8 | mr/study_002/instance_100 | MR | 180×180 | 168.1 KB | 12.4 KB | 13.3 KB | +7.3% |
| 9 | px/study_001/instance_001 | PX | 2459×1316 | 6.21 MB | 2.29 MB | 2.48 MB | +8.3% |
| 10 | xa/study_001/instance_001 | XA | 1024×1024 | 2.03 MB | 658.0 KB | 688.6 KB | +4.6% |
| | **Total** | | | **102.41 MB** | **29.05 MB** | **30.27 MB** | **+4.19%** |

- Aggregate ratio (DICOM ÷ encoded): **J2K = 3.53×, HTJ2K = 3.38×**
- HTJ2K vs J2K size delta (totals): **+4.19%** (HTJ2K is larger)
- Per-fixture range: **+3.0% (MG) to +10.0% (MR)**

## Notes

- HTJ2K is **+4.19% larger** than EBCOT (J2K Part 1) on this corpus in aggregate. Per-fixture spread is **+3.0% (MG, large 12-bit) to +10.0% (MR, small)** — smaller images skew the gap wider.
- Both columns are produced by **J2KSwift's own** EBCOT and HT entropy paths — this is an internal codestream-format comparison, not a cross-codec test.
- Test exited green; the assertion is purely informational (printed report).
