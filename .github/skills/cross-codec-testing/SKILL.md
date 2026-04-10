---
name: cross-codec-testing
description: 'Cross-codec interoperability testing between J2KSwift and OpenJPEG. Use for validating encode/decode compatibility, verifying lossless roundtrip, comparing outputs between codecs, testing multi-tile images, medical imaging interop.'
---

# Cross-Codec Interoperability Testing

Test JPEG 2000 encode/decode compatibility between J2KSwift and OpenJPEG.

## When to Use
- Verifying J2KSwift output can be decoded by OpenJPEG (and vice versa)
- Testing lossless roundtrip: encode → decode → compare
- Validating multi-tile, multi-component, or medical images
- Debugging interoperability failures

## Prerequisites
- J2KSwift CLI built: `swift build` (produces `.build/debug/j2k`)
- OpenJPEG v2.5.4 at `/opt/homebrew/bin/` (`opj_compress`, `opj_decompress`, `opj_dump`)
- Test images (create synthetic PGM/PPM if none available)

## Procedure

### 1. Build J2KSwift CLI
```bash
swift build
```

### 2. Create Test Images (if needed)
Generate synthetic PGM (grayscale) or PPM (color) test images:
```bash
# 256x256 grayscale gradient
python3 -c "
import struct
with open('/tmp/test_gray.pgm', 'wb') as f:
    f.write(b'P5\n256 256\n255\n')
    for y in range(256):
        for x in range(256):
            f.write(struct.pack('B', (x + y) % 256))
"
```

### 3. Test Matrix

Run each combination:

| Encode With | Decode With | Mode | Expected |
|------------|-------------|------|----------|
| J2KSwift | OpenJPEG | Lossless | MAE = 0 |
| OpenJPEG | J2KSwift | Lossless | MAE = 0 |
| J2KSwift | J2KSwift | Lossless | MAE = 0 |
| J2KSwift | OpenJPEG | Lossy | MAE < threshold |
| OpenJPEG | J2KSwift | Lossy | MAE < threshold |

### 4. Encode/Decode Commands

**J2KSwift encode (lossless):**
```bash
.build/debug/j2k encode /tmp/test_gray.pgm /tmp/j2k_lossless.j2k
```

**J2KSwift encode (lossy):**
```bash
.build/debug/j2k encode /tmp/test_gray.pgm /tmp/j2k_lossy.j2k --quality 0.5
```

**OpenJPEG encode (lossless):**
```bash
opj_compress -i /tmp/test_gray.pgm -o /tmp/opj_lossless.j2k -r 1
```

**OpenJPEG decode:**
```bash
opj_decompress -i /tmp/j2k_lossless.j2k -o /tmp/decoded.pgm
```

**J2KSwift decode:**
```bash
.build/debug/j2k decode /tmp/opj_lossless.j2k /tmp/decoded.pgm
```

### 5. Compare Results
```bash
.build/debug/j2k compare /tmp/test_gray.pgm /tmp/decoded.pgm
```

Or use Python for MAE calculation:
```bash
python3 -c "
import sys
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
# Skip PGM header (find data after third newline)
def skip_header(d):
    pos = 0
    for _ in range(3):
        pos = d.index(ord('\n'), pos) + 1
    return d[pos:]
da, db = skip_header(a), skip_header(b)
mae = sum(abs(x-y) for x,y in zip(da,db)) / len(da)
print(f'MAE: {mae:.4f}')
" /tmp/test_gray.pgm /tmp/decoded.pgm
```

### 6. Test Edge Cases
- 1x1 pixel image
- Non-power-of-2 dimensions (e.g., 253x127)
- Multi-tile (large images with small tile size)
- 16-bit depth images
- Multi-component (RGB) images

## Troubleshooting
- If J2KSwift output fails in OpenJPEG: use `opj_dump` to inspect codestream markers
- If lossless MAE > 0: check DWT mode (must be 5/3 reversible) and quantization step sizes
- If multi-tile fails: verify tile boundaries match between encoder/decoder
