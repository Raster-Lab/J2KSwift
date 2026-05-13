# J2KSwift v2.2.0 Release Notes

**Release Date**: 2026-10-01  
**Phase**: Phase 19 — Multi-Spectral JP3D and Vulkan JP3D Acceleration (Weeks 316–325)  
**Previous Version**: 2.1.0

---

## Headline Feature: Multi-Spectral JP3D Volumetric Imaging

v2.2.0 extends the JP3D volumetric codec with multi-spectral and hyperspectral support, adds Vulkan-accelerated 3D wavelet transforms for spectral volumes, and introduces spectral analysis tools for remote-sensing workflows.

---

## What's New

### Multi-Spectral JP3D Types

New types in `J2K3D` for representing multi-spectral volumetric data:

| Type | Description |
|------|-------------|
| `JP3DSpectralBand` | A single spectral band with zero-based index, centre wavelength (nm), and human-readable label |
| `JP3DSpectralMapping` | Ordered mapping from band indices to wavelengths; factory presets for `.visible` (RGB), `.nearInfrared` (Red/NIR/SWIR), and `.hyperspectral(bandCount:)` |
| `JP3DMultiSpectralVolume` | Width × height × depth volume with per-band `[Float]` samples; computed properties for `bandCount`, `voxelCount`, and `spectralRange` |
| `JP3DSpectralClassification` | Coarse land-cover labels: `.vegetation`, `.water`, `.urban`, `.bareSoil`, `.cloud`, `.unclassified` |
| `JP3DMultiSpectralStatistics` | Per-band descriptive statistics: mean, standard deviation, min, max |
| `JP3DSpectralConfiguration` | Spectral encoding settings: mapping, normalisation range, inter-band prediction flag; `.default` preset available |

### Multi-Spectral Encoder

`JP3DMultiSpectralEncoder` — actor-based encoder for multi-spectral volumetric data.

- Wraps a base `JP3DEncoderConfiguration` with spectral-specific settings
- Per-band quality layers with configurable `qualityLayersPerBand`
- Optional spectral decorrelation transform (principal component approximation)
- Inter-band prediction to exploit correlations between adjacent spectral bands
- Validates band count against sample data at encode time

### Multi-Spectral Decoder

`JP3DMultiSpectralDecoder` — actor-based decoder with selective band loading.

- Decode all bands or a targeted subset via `JP3DMultiSpectralDecodeOptions.targetBands`
- Resolution-level selection for reduced-resolution decoding
- Per-voxel spectral classification using NDVI-based thresholds
- `.full` preset for all-band, full-resolution decoding

### Spectral Analysis

`JP3DSpectralAnalyser` — spectral index computation and inter-band correlation.

| Feature | Description |
|---------|-------------|
| **Spectral indices** | NDVI (vegetation), NDWI (water), NDBI (urban) — normalised difference indices per Z-slice |
| **Correlation matrix** | Inter-band Pearson correlation coefficient matrix across all band pairs |
| **JP3DSpectralIndexResult** | Per-Z-slice `[Float]` values in row-major order for each computed index |

### Vulkan-Accelerated 3D DWT

`J2KVulkanJP3DDWT` — Vulkan-accelerated 3D discrete wavelet transform with spectral-axis support.

| Feature | Description |
|---------|-------------|
| **GPU/CPU auto-selection** | Automatically selects GPU when total element count exceeds `gpuThreshold` (default 4 096) |
| **Spectral-axis DWT** | Optional DWT along the spectral/band axis for inter-band decorrelation |
| **Wavelet filters** | CDF 9/7 (irreversible) and Le Gall 5/3 (reversible) |
| **Configurable decomposition** | 1+ decomposition levels; default 3 |
| **Transform statistics** | `J2KVulkanJP3DDWTStatistics` with element count, timing, subbands produced, and GPU/CPU indicator |
| **Presets** | `.default` (CDF 9/7, GPU), `.lossless` (Le Gall 5/3, GPU) |

### JPEG XS Exploration Types

> **⚠️ Note**: JPEG XS (ISO/IEC 21122) is a separate compression standard from JPEG 2000 (ISO/IEC 15444). These types were added as exploratory scaffolding in Phase 19 and are **not part of the JPEG 2000 standard**. They may be moved to a separate package in a future release.

`J2KXSTypes` in `J2KCore` provides initial type definitions for JPEG XS:

| Type | Description |
|------|-------------|
| `J2KXSProfile` | `.light`, `.main`, `.high` — component capacity profiles |
| `J2KXSLevel` | `.sublevel0` … `.sublevel3` — pixel throughput levels (1–8 Gpixel/s) |
| `J2KXSSliceHeight` | `.height16`, `.height32`, `.height64` — vertical slice granularity |
| `J2KXSConfiguration` | Combined profile/level/slice/bpp settings; `.preview` and `.production` presets |
| `J2KXSCapabilities` | Runtime capability query; `isAvailable: false` in v2.2.0 (exploration only) |

---

## Source Files

### New Files

| File | Module | Lines | Description |
|------|--------|-------|-------------|
| `JP3DMultiSpectralTypes.swift` | J2K3D | 276 | Spectral band, mapping, volume, classification, and configuration types |
| `JP3DMultiSpectralEncoder.swift` | J2K3D | 235 | Actor-based multi-spectral encoder |
| `JP3DMultiSpectralDecoder.swift` | J2K3D | 165 | Actor-based multi-spectral decoder with selective band loading |
| `JP3DSpectralAnalysis.swift` | J2K3D | ~200 | Spectral index computation and correlation analysis |
| `J2KVulkanJP3DDWT.swift` | J2KVulkan | 328 | Vulkan-accelerated 3D DWT with spectral-axis support |
| `J2KXSTypes.swift` | J2KCore | 195 | JPEG XS exploration types (profiles, levels, configuration) |

---

## Testing

### New Tests: 69 tests, 0 failures

| Test Suite | Tests | Description |
|-----------|-------|-------------|
| `JP3DMultiSpectralTests` | 33 | Multi-spectral volume types, encoder, decoder, and spectral analysis |
| `J2KVulkanJP3DDWTTests` | 15 | Vulkan 3D DWT configuration, GPU/CPU path selection, spectral axis |
| `J2KXSTypesTests` | 21 | JPEG XS exploration type validation, presets, capabilities |

---

## Documentation

### Updated Documentation

- `CHANGELOG.md` — v2.2.0 entry (Phase 19)
- `MILESTONES.md` — Phase 19 marked complete
- `README.md` — Updated with Phase 19 features and v2.2.0 status

---

## Breaking Changes

None. v2.2.0 is fully backward compatible with v2.1.0.

---

## Migration

No migration required. All existing APIs remain unchanged. The new multi-spectral types and Vulkan JP3D DWT are additive.

The `getVersion()` function now returns `"2.2.0"`.

---

## Known Limitations

- The Vulkan JP3D DWT requires a Vulkan-capable GPU; the CPU fallback is always available but does not benefit from GPU acceleration.
- Multi-spectral encoding with spectral decorrelation is a scaffold; the principal component transform is an approximation.
- **JPEG XS types are exploration-only** (`J2KXSCapabilities.current.isAvailable == false`). No encode/decode functionality is available in v2.2.0.

---

## Requirements

- Swift 6.2 or later
- macOS 15+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+ / Linux / Windows

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.2.0")
]
```

---

## What's Next

Phase 20 continues JPEG XS development with a full codec implementation. See `MILESTONES.md` for details.

---

*J2KSwift is a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444).*  
*© 2026 Raster Lab. All rights reserved.*
