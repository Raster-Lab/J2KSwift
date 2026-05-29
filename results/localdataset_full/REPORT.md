# LocalDataset Encode/Decode Round-Trip Report

- **Dataset:** `LocalDatasets/medical-dicom-organized`
- **Binary:** `.build/release/j2k`
- **Files processed:** 30104
- **Verification:** ON
- **Wall time:** 22.5 min  (8 workers)

## Overall status

| Status | Count | % |
|---|---:|---:|
| OK | 30048 | 99.81% |
| ENCODE_FAIL | 56 | 0.19% |

**30048/30104 (99.81%) clean round-trips.**

## By modality

| Modality | Total | OK | ENCODE_FAIL | DECODE_FAIL | VERIFY_MISMATCH | VERIFY_SKIP |
|---|---:|---:|---:|---:|---:|---:|
| ct | 14021 | 13976 | 45 | 0 | 0 | 0 |
| dx | 19 | 19 | 0 | 0 | 0 | 0 |
| mg | 40 | 40 | 0 | 0 | 0 | 0 |
| mr | 15700 | 15689 | 11 | 0 | 0 | 0 |
| px | 15 | 15 | 0 | 0 | 0 | 0 |
| xa | 309 | 309 | 0 | 0 | 0 | 0 |

## Failures / anomalies

**56 file(s)** across **1** distinct failure signature(s).

### ENCODE_FAIL — 56 file(s)

- **Transfer syntax:** `1.2.840.10008.1.2.1`
- **Detail:** `Error: Invalid parameter: DICOM file missing Pixel Data tag (7FE0,0010)`
- **Examples:**
  - `LocalDatasets/medical-dicom-organized/ct/study_005/instance_002473.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/ct/study_005/instance_002468.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/ct/study_003/instance_003670.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/ct/study_003/instance_003666.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/ct/study_003/instance_003665.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/ct/study_001/instance_001128.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/mr/study_002/instance_001280.dcm` (0x0, mr)
  - `LocalDatasets/medical-dicom-organized/ct/study_005/instance_002472.dcm` (0x0, ct)
  - `LocalDatasets/medical-dicom-organized/mr/study_004/instance_000413.dcm` (0x0, mr)
  - `LocalDatasets/medical-dicom-organized/ct/study_001/instance_001126.dcm` (0x0, ct)
  - … and 46 more (see results.csv)

