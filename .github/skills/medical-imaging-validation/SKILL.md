---
name: medical-imaging-validation
description: 'Medical imaging validation with DICOM, clinical workflow testing, CT/MRI compression, lossless medical roundtrip, diagnostic quality verification, PSNR/MAE metrics for medical images.'
---

# Medical Imaging Validation

Validate JPEG 2000 compression quality for medical imaging workflows (DICOM, CT, MRI).

## When to Use
- Validating lossless compression for diagnostic-quality medical images
- Testing DICOM integration workflows
- Benchmarking medical image compression ratios
- Verifying compliance with medical imaging standards (DICOM Supplement 106)

## Prerequisites
- J2KSwift CLI built: `swift build`
- OpenJPEG available at `/opt/homebrew/bin/`
- Python 3 with standard library (for metric calculation)

## Procedure

### 1. Create Synthetic Medical Test Data
```bash
# 512x512 16-bit grayscale (simulated CT slice)
python3 -c "
import struct, math
with open('/tmp/ct_slice.pgm', 'wb') as f:
    f.write(b'P5\n512 512\n65535\n')
    for y in range(512):
        for x in range(512):
            # Simulate tissue density gradient with noise
            val = int(32768 + 16384 * math.sin(x/50.0) * math.cos(y/50.0))
            val = max(0, min(65535, val))
            f.write(struct.pack('>H', val))
"
```

### 2. Lossless Medical Roundtrip
Medical images MUST be lossless (MAE = 0):
```bash
# Encode lossless
.build/debug/j2k encode /tmp/ct_slice.pgm /tmp/ct_lossless.j2k

# Decode
.build/debug/j2k decode /tmp/ct_lossless.j2k /tmp/ct_decoded.pgm

# Verify exact match
.build/debug/j2k compare /tmp/ct_slice.pgm /tmp/ct_decoded.pgm
```

### 3. Cross-Codec Medical Validation
```bash
# J2KSwift encode → OpenJPEG decode
.build/debug/j2k encode /tmp/ct_slice.pgm /tmp/ct_j2k.j2k
opj_decompress -i /tmp/ct_j2k.j2k -o /tmp/ct_opj_decoded.pgm

# OpenJPEG encode → J2KSwift decode
opj_compress -i /tmp/ct_slice.pgm -o /tmp/ct_opj.j2k -r 1
.build/debug/j2k decode /tmp/ct_opj.j2k /tmp/ct_j2k_decoded.pgm
```

### 4. Quality Metrics
```bash
python3 -c "
import struct, math, sys
def read_pgm16(path):
    with open(path, 'rb') as f:
        magic = f.readline().strip()
        dims = f.readline().strip().split()
        maxval = int(f.readline().strip())
        w, h = int(dims[0]), int(dims[1])
        data = []
        for _ in range(w * h):
            data.append(struct.unpack('>H', f.read(2))[0])
        return data, w, h, maxval

orig, w, h, m = read_pgm16(sys.argv[1])
dec, _, _, _ = read_pgm16(sys.argv[2])
mae = sum(abs(a-b) for a,b in zip(orig, dec)) / len(orig)
mse = sum((a-b)**2 for a,b in zip(orig, dec)) / len(orig)
psnr = 10 * math.log10(m**2 / mse) if mse > 0 else float('inf')
print(f'MAE:  {mae:.6f}')
print(f'MSE:  {mse:.6f}')
print(f'PSNR: {psnr:.2f} dB')
print(f'Lossless: {\"YES\" if mae == 0 else \"NO\"}')
" /tmp/ct_slice.pgm /tmp/ct_decoded.pgm
```

### 5. Test Suite Validation
```bash
swift test --filter J2KCoreTests
swift test --filter J2KInteroperabilityTests
```

### 6. DICOM Integration Check
- Verify `Sources/J2KCLI/DICOMSupport.swift` handles DICOM encapsulation
- Test with DICOM-wrapped JPEG 2000 data
- Validate transfer syntax UIDs

## Acceptance Criteria
- Lossless: MAE = 0 (mandatory for diagnostic use)
- Lossy (non-diagnostic): PSNR ≥ 40 dB
- Cross-codec roundtrip: lossless match
- 16-bit depth support: verified
- No memory leaks during batch medical processing

## Reference Documentation
- `CLINICAL_VALIDATION_REPORT.md`
- `MEDICAL_BENCHMARK.md`
- `Documentation/DICOM_INTEGRATION.md`
- `Scripts/clinical_validation.py`
- `Scripts/medical_benchmark.py`
