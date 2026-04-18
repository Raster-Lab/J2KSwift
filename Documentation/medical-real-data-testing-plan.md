# Medical Real-Data Testing Plan

## Local Dataset Staging

A local organized copy of the radiology DICOM data is staged under the workspace-only folder:

- LocalDatasets/medical-dicom-organized

This location is intentionally git-ignored so the real medical data stays local and is not committed.

## Organization Scheme

The dataset is normalized by modality and study:

- ct/study_001
- dx/study_001
- mg/study_001
- mr/study_001
- px/study_001
- xa/study_001

Within each study, instances are renamed in sequence for stable testing.

## Next Validation Pass

1. Verify DICOM ingestion in the app on representative studies for CT, MR, DX, MG, PX, and XA.
2. Run lossless J2K roundtrip checks and confirm exact reconstruction where expected.
3. Run HTJ2K encode and decode checks on a smaller subset first.
4. Measure output size, decode speed, and visual fidelity for 8-bit and 16-bit cases.
5. Confirm metadata handling and ensure no workflow regressions in the app.

## Safety Notes

- Use the local copy only for testing.
- Keep the cloud source untouched as the source of truth.
- Do not commit, publish, or share the staged dataset.
