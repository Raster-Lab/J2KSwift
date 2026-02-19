# JP3D Test Vectors

This document describes the synthetic test vectors used in the JP3D compliance
test suite (`Tests/J2KComplianceTests/JP3DComplianceTests.swift`).

All test vectors are generated programmatically; no external binary files are
required. Each vector is described by its construction rule and its intended
conformance coverage.

---

## 1. Gradient Volumes

These volumes are used as inputs for round-trip and structural conformance tests.

| ID | Width | Height | Depth | Components | Bit Depth | Construction |
|----|-------|--------|-------|-----------|-----------|--------------|
| GV-01 | 4 | 4 | 2 | 1 | 8 | `(x + y*2 + z*3) % 256` per voxel |
| GV-02 | 8 | 8 | 4 | 1 | 8 | `(x + y*2 + z*3) % 256` per voxel |
| GV-03 | 16 | 16 | 4 | 3 | 8 | `(x + y*2 + z*3 + c*7) % 256` per voxel |
| GV-04 | 32 | 32 | 8 | 1 | 8 | `(x + y*2 + z*3) % 256` per voxel |
| GV-05 | 8 | 8 | 4 | 1 | 12 | `(x + y*2 + z*3) % 4096` per voxel |
| GV-06 | 8 | 8 | 4 | 1 | 16 | `(x + y*2 + z*3) % 65536` per voxel |

---

## 2. Minimal Conformant Codestream

The minimum valid JP3D codestream has the following structure:

```
SOC (0xFF4F)
SIZ (0xFF51) — 1×1×1 volume, 1 component, 8-bit
COD (0xFF52) — 0 decomposition levels, lossless
QCD (0xFF5C) — lossless quantization
SOT (0xFF90) — tile index 0
SOD (0xFF93) — empty tile data
EOC (0xFFD9)
```

This is the smallest codestream accepted by `JP3DCodestreamParser`.

---

## 3. Marker Byte Sequences

### SOC
```
0xFF 0x4F
```

### EOC
```
0xFF 0xD9
```

### SIZ (minimal)
```
0xFF 0x51 <length:2> <Rsiz:2> <Xsiz:4> <Ysiz:4> <Zsiz:4>
          <XTsiz:4> <YTsiz:4> <ZTsiz:4>
          <XOsiz:4> <YOsiz:4> <ZOsiz:4>
          <Csiz:2>
          [per-component: <Ssiz:1> <XRsiz:1> <YRsiz:1> <ZRsiz:1>]
```

### COD (JP3D extension — length 14)
```
0xFF 0x52 0x00 0x0E <Scod:1> <SGcod:4> <SPcod_NL_X:1> <SPcod_NL_Y:1> <SPcod_NL_Z:1>
                    <filter:1>
```

### QCD
```
0xFF 0x5C <length:2> <Sqcd:1> <step_word(s)>
```

### SOT
```
0xFF 0x90 0x00 0x0A <Isot:2> <Psot:4> <TPsot:1> <TNsot:1>
```

### SOD
```
0xFF 0x93
```

### EOC
```
0xFF 0xD9
```

---

## 4. Invalid / Non-conformant Vectors

These vectors are used in error-resilience tests.

| ID | Description | Expected Behaviour |
|----|-------------|-------------------|
| IV-01 | Empty `Data` | `decodingError` (missing SOC) |
| IV-02 | `[0xFF, 0x52, 0x00, 0x00]` (SOT instead of SOC) | `decodingError` (missing SOC) |
| IV-03 | Valid SOC only (2 bytes) | `decodingError` (missing SIZ) |
| IV-04 | Truncated SIZ (length byte is 2, data cut short) | `decodingError` (truncated marker) |
| IV-05 | SOC + 4 random bytes + EOC | `decodingError` (missing SIZ or COD) |
| IV-06 | Valid codestream truncated at 50% | decoder returns partial result or throws |
| IV-07 | Valid codestream with all tile bytes zeroed | decoder succeeds (zero-tile data handled) |
| IV-08 | SOC + SIZ (zero dimensions) | `decodingError` (invalid dimensions) |

---

## 5. Profile Constraint Vectors

| ID | Description | Expected Behaviour |
|----|-------------|-------------------|
| PC-01 | Encoder: `levelsX: 10` on a 4-voxel-wide volume | Error or graceful clamp |
| PC-02 | `tileSizeX: 0` | `invalidTileConfiguration` |
| PC-03 | `tileSizeZ: -1` | `invalidTileConfiguration` |

---

## 6. Round-trip Conformance Vectors

These volumes are encoded losslessly and then decoded. Each reconstructed voxel
must match the original exactly (bit-exact).

| ID | Width | Height | Depth | Bit Depth | Config |
|----|-------|--------|-------|-----------|--------|
| RT-01 | 8 | 8 | 4 | 8 | `.lossless` |
| RT-02 | 16 | 16 | 4 | 8 | `.lossless`, 3 components |
| RT-03 | 8 | 8 | 4 | 12 | `.lossless` |
| RT-04 | 8 | 8 | 4 | 16 | `.lossless` |
| RT-05 | 32 | 32 | 8 | 8 | `.lossless`, tileSize 16×16×4 |
| RT-06 | 4 | 4 | 2 | 8 | `.lossless`, all 5 progression orders |
| RT-07 | 8 | 8 | 4 | 8 | `.lossless` signed volume |

---

## References

- ISO/IEC 15444-10:2011 — JPEG 2000 image coding system: Extensions for three-dimensional data (JP3D)
- ISO/IEC 15444-4:2004 — JPEG 2000 image coding system: Conformance testing
- ISO/IEC 15444-1:2019 — JPEG 2000 image coding system: Core coding system
