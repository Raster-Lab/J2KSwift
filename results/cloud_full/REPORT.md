# DICOM Encode/Decode Round-Trip Report

- **Dataset:** `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data`
- **Binary:** `.build/release/j2k`
- **Files processed:** 30329
- **Verification:** ON
- **Wall time:** 38.4 min  (8 workers)

## Overall status

| Status | Count | % |
|---|---:|---:|
| OK | 30267 | 99.80% |
| ENCODE_FAIL | 62 | 0.20% |

**30267/30329 (99.80%) clean round-trips.**

## By modality

| Modality | Total | OK | ENCODE_FAIL | DECODE_FAIL | VERIFY_MISMATCH | VERIFY_SKIP |
|---|---:|---:|---:|---:|---:|---:|
| CT | 14021 | 13976 | 45 | 0 | 0 | 0 |
| DX | 19 | 19 | 0 | 0 | 0 | 0 |
| MG | 40 | 40 | 0 | 0 | 0 | 0 |
| MR | 15700 | 15689 | 11 | 0 | 0 | 0 |
| PX | 15 | 15 | 0 | 0 | 0 | 0 |
| US | 225 | 219 | 6 | 0 | 0 | 0 |
| XA | 309 | 309 | 0 | 0 | 0 | 0 |

## Types tested

A breakdown of *how many of each DICOM type* were exercised, with the round-trip outcome for each. 'OK' = encoded, decoded, and bit-exact verified. 'Fails' excludes VERIFY_SKIP.

**Corpus mix:** 30267 image objects · 62 non-image objects · 219 colour (multi-sample) · 299 multi-frame · 234 compressed-source · 0 signed-pixel.

### SOP Class

| SOP Class | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| CT Image Storage | 20817 | 20817 | 100.0% | 0 |
| MR Image Storage | 8834 | 8834 | 100.0% | 0 |
| X-Ray Angiographic Image Storage | 309 | 309 | 100.0% | 0 |
| Ultrasound Multi-frame Image Storage | 143 | 143 | 100.0% | 0 |
| Ultrasound Image Storage | 76 | 76 | 100.0% | 0 |
| Computed Radiography Image Storage | 40 | 40 | 100.0% | 0 |
| Raw Data Storage | 39 | 0 | 0.0% | 39 |
| Digital X-Ray Image Storage - For Presentation | 34 | 34 | 100.0% | 0 |
| Secondary Capture Image Storage | 14 | 14 | 100.0% | 0 |
| X-Ray Radiation Dose SR Storage | 9 | 0 | 0.0% | 9 |
| Enhanced SR Storage | 8 | 0 | 0.0% | 8 |
| Comprehensive SR Storage | 6 | 0 | 0.0% | 6 |

### DICOM Modality (0008,0060)

| DICOM Modality (0008,0060) | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| CT | 20868 | 20829 | 99.8% | 39 |
| MR | 8836 | 8836 | 100.0% | 0 |
| XA | 309 | 309 | 100.0% | 0 |
| US | 219 | 219 | 100.0% | 0 |
| CR | 40 | 40 | 100.0% | 0 |
| SR | 23 | 0 | 0.0% | 23 |
| DX | 19 | 19 | 100.0% | 0 |
| PX | 15 | 15 | 100.0% | 0 |

### Transfer Syntax

| Transfer Syntax | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| 1.2.840.10008.1.2.1 | 21141 | 21085 | 99.7% | 56 |
| 1.2.840.10008.1.2 | 8954 | 8948 | 99.9% | 6 |
| 1.2.840.10008.1.2.4.50 | 219 | 219 | 100.0% | 0 |
| 1.2.840.10008.1.2.4.80 | 9 | 9 | 100.0% | 0 |
| 1.2.840.10008.1.2.4.70 | 6 | 6 | 100.0% | 0 |

### Photometric Interpretation

| Photometric Interpretation | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| MONOCHROME2 | 30045 | 30045 | 100.0% | 0 |
| YBR_FULL_422 | 219 | 219 | 100.0% | 0 |
| (none) | 62 | 0 | 0.0% | 62 |
| MONOCHROME1 | 3 | 3 | 100.0% | 0 |

### Samples/pixel

| Samples/pixel | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| spp=1 | 30110 | 30048 | 99.8% | 62 |
| spp=3 | 219 | 219 | 100.0% | 0 |

### Bit depth (allocated/stored)

| Bit depth (allocated/stored) | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| 16/16 | 20820 | 20820 | 100.0% | 0 |
| 16/12 | 9073 | 9073 | 100.0% | 0 |
| 8/8 | 374 | 374 | 100.0% | 0 |
| 0/0 | 62 | 0 | 0.0% | 62 |

### Pixel representation

| Pixel representation | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| unsigned | 30329 | 30267 | 99.8% | 62 |

### Frame count

| Frame count | Total | OK | Pass% | Fails |
|---|---:|---:|---:|---:|
| single-frame | 30030 | 29968 | 99.8% | 62 |
| multi-frame | 299 | 299 | 100.0% | 0 |

## Failures / anomalies

**62 file(s)** across **2** distinct failure signature(s).

### ENCODE_FAIL — 56 file(s)

- **Transfer syntax:** `1.2.840.10008.1.2.1`
- **Detail:** `Error: Invalid parameter: DICOM file missing Pixel Data tag (7FE0,0010)`
- **SOP class(es):** `Enhanced SR Storage`, `Raw Data Storage`, `X-Ray Radiation Dose SR Storage`
- **Non-image objects (no pixel data):** 56/56
- **Examples:**
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/MR/MRI_Study2/Head_Dot - MR68/CT_Raw_data_601/IM-0086-0003.dcm` [Raw Data Storage, MR]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/MR/MRI_Study2/Head_Dot - MR68/CT_Raw_data_601/IM-0086-0002.dcm` [Raw Data Storage, MR]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study5/Abd_Triple_Phae(Adult) - CT32/CT_Raw_data_602/IM-0023-0003.dcm` [Raw Data Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study3/Abd_Triple_Phae(Adult) - CT204/CT_Raw_data_601/IM-0020-0007.dcm` [Raw Data Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/MR/MRI_Study4/Head_Dot - MR47/CT_Raw_data_601/IM-0196-0002.dcm` [Raw Data Storage, MR]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study3/Abd_Triple_Phae(Adult) - CT204/Examination_Report_503/IM-0024-0009.dcm` [Enhanced SR Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study5/Abd_Triple_Phae(Adult) - CT32/Examination_Report_509/IM-0032-0003.dcm` [Enhanced SR Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study3/Abd_Triple_Phae(Adult) - CT204/CT_Raw_data_601/IM-0020-0003.dcm` [Raw Data Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study5/Abd_Triple_Phae(Adult) - CT32/Examination_Report_503/IM-0028-0003.dcm` [Enhanced SR Storage, CT]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/CT/CT_Study3/Abd_Triple_Phae(Adult) - CT204/CT_Raw_data_601/IM-0020-0006.dcm` [Raw Data Storage, CT]
  - … and 46 more (see results.csv)

### ENCODE_FAIL — 6 file(s)

- **Transfer syntax:** `1.2.840.10008.1.2`
- **Detail:** `Error: Invalid parameter: DICOM file missing Pixel Data tag (7FE0,0010)`
- **SOP class(es):** `Comprehensive SR Storage`
- **Non-image objects (no pixel data):** 6/6
- **Examples:**
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study1/Unnamed - 0/unnamed_2/IM-0002-0015.dcm` [Comprehensive SR Storage, US]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study5/Unnamed - 0/unnamed_2/IM-0010-0011.dcm` [Comprehensive SR Storage, US]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study4/Unnamed - 0/unnamed_2/IM-0008-0011.dcm` [Comprehensive SR Storage, US]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study1/Unnamed - 0/unnamed_2/IM-0002-0012.dcm` [Comprehensive SR Storage, US]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study2/Unnamed - 0/unnamed_2/IM-0004-0011.dcm` [Comprehensive SR Storage, US]
  - `/Users/raster/Library/CloudStorage/GoogleDrive-ranjithkumar.k@raster.sksh.ac.in/.shortcut-targets-by-id/1yz_KcLqa6FDdNQzWgvHjaKvzwyvFxtf4/Radiology DICOM Data/US/US_Study3/Unnamed - 0/unnamed_2/IM-0006-0023.dcm` [Comprehensive SR Storage, US]

