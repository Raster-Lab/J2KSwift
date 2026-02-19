# Part 2 Conformance Testing Guide

This document describes the conformance testing strategy for ISO/IEC 15444-2 (JPEG 2000 Part 2) features in J2KSwift.

## Overview

Part 2 conformance testing validates that the J2KSwift implementation correctly handles all Part 2 extensions. Testing covers codestream marker generation, file format box round-trip, reader requirements signaling, and decoder capability negotiation.

## Test Categories

### 1. Codestream Marker Conformance

Tests that Part 2 marker segments are correctly generated and parsed.

#### SIZ Marker (Rsiz Extensions)

| Test | Description |
|------|-------------|
| Part 1 baseline | Rsiz = 0x0000 for default config |
| Part 2 flag | Rsiz bit 15 set when Part 2 features enabled |
| HTJ2K flag | Rsiz bit 14 set when HTJ2K enabled |
| MCT bit | Rsiz bit 0 set when MCT configured |
| Arbitrary wavelets bit | Rsiz bit 1 set when arbitrary wavelets used |
| DC offset bit | Rsiz bit 4 set when DC offset enabled |
| Extended precision bit | Rsiz bit 6 set when extended precision used |
| Combined flags | Multiple Part 2 features set correct bits |

#### COD/COC Marker Extensions

| Test | Description |
|------|-------------|
| Coding extensions detection | Part 2 coding features correctly detected |
| Arbitrary decomposition flag | Flagged when arbitrary wavelets are used |
| Multi-component coding flag | Flagged when MCT is configured |
| Extended precinct sizes | Custom precinct sizes encoded correctly |

#### QCD/QCC Marker Extensions

| Test | Description |
|------|-------------|
| Standard guard bits | Default 2 guard bits for Part 1 |
| Extended guard bits | Part 2 supports up to 15 guard bits |
| Sqcd encoding | Guard bits and style correctly combined |
| Trellis quantization flag | TCQ detection in configuration |

### 2. File Format Box Conformance

Tests that Part 2 boxes are correctly written and parsed.

#### Metadata Boxes

| Box Type | Tests |
|----------|-------|
| IPR (`jp2i`) | Write, read, round-trip, empty data |
| Label (`lbl`) | Write, read, round-trip, Unicode support |
| Number List (`nlst`) | Write, read, entity types, round-trip |
| Association (`asoc`) | Container, nested boxes, round-trip |
| Cross-Reference (`cref`) | URL reference, round-trip |
| Digital Signature (`dsig`) | MD5, SHA-1, SHA-256, SHA-512, verification |
| ROI Description (`roid`) | Rectangle, ellipse, polygon shapes |
| Data Entry URL (`url`) | URL encoding, round-trip |

#### Animation Boxes

| Box Type | Tests |
|----------|-------|
| Instruction Set (`inst`) | Compose, animate, transform modes |
| Opacity (`opct`) | Last channel, matte, global value |
| Codestream Registration (`creg`) | Grid mapping, multi-codestream |
| Composition Layer Header (`jplh`) | Layer construction, metadata |

#### Resolution Boxes

| Box Type | Tests |
|----------|-------|
| Resolution (`res`) | Container with capture and display |
| Capture Resolution (`resc`) | DPI encoding, round-trip |
| Display Resolution (`resd`) | DPI encoding, round-trip |

### 3. Reader Requirements Conformance

Tests for the rreq box and feature signaling.

| Test | Description |
|------|-------------|
| Standard features | All 14+ standard feature values |
| Part 2 feature detection | `isPart2Feature` for values >= 18 |
| Mask length | 1, 2, 4, 8 byte masks |
| Fully-understand mask | Correct bits set for required features |
| Display mask | Part 2 features in display mask |
| Vendor features | UUID-based vendor feature entries |
| Round-trip | Write and read back with identical data |
| Feature names | Human-readable names for all features |

### 4. Decoder Capability Conformance

Tests for decoder capability negotiation.

| Test | Description |
|------|-------------|
| Part 1 decoder | Only supports `noExtensions` |
| Part 2 decoder | Supports all standard features |
| Validation results | Compatible, partially compatible, incompatible |
| Missing features | Correctly identifies unsupported features |
| Display capability | Separate check for display requirements |

### 5. Feature Compatibility Conformance

Tests for feature combination validation.

| Test | Description |
|------|-------------|
| Part 2 without JPX | Warning when Part 2 features lack `needsJPXReader` |
| noExtensions conflict | Error when `noExtensions` combined with others |
| Visual masking pairing | Warning when visual masking without perceptual encoding |
| Feature dependencies | All Part 2 features require `needsJPXReader` |
| Suggested requirements | Automatic rreq box generation from feature set |

### 6. Integration Tests

End-to-end tests combining multiple Part 2 features.

| Test | Description |
|------|-------------|
| Metadata preservation | Metadata survives write/read cycle |
| Animation sequence | Multi-frame animation construction |
| Multi-layer composition | Layer blending and compositing |
| Part 2 codestream | SIZ Rsiz reflects configuration |
| Full JPX pipeline | Complete JPX file with all Part 2 boxes |

## Running Conformance Tests

```bash
# Run all Part 2 file format tests
swift test --filter J2KPart2FileFormatTests

# Run Part 2 conformance tests
swift test --filter J2KPart2ConformanceTests

# Run all file format tests
swift test --filter J2KFileFormat

# Run all tests
swift test
```

## Compliance Matrix

### ISO/IEC 15444-2 Annex Coverage

| Annex | Feature | Status |
|-------|---------|--------|
| I.5 | Image Header Box | ✅ Supported |
| I.7 | Reader Requirements Box | ✅ Supported |
| I.7.1 | Standard Features | ✅ 14+ features |
| I.7.2 | Feature Signaling | ✅ Full mask support |
| I.7.3 | Vendor Features | ✅ UUID-based |
| M.1 | Composition Box | ✅ Instruction sets |
| M.2 | Compositing Layer | ✅ Layer headers |
| M.3 | Animation | ✅ Timing, frames |
| M.4 | Fragment Table | ✅ Fragment list |
| M.5 | Cross-Reference | ✅ External refs |
| M.9 | IPR Box | ✅ Arbitrary data |
| M.10 | Digital Signature | ✅ MD5/SHA family |
| M.11 | XML Metadata | ✅ Schema detection |
| M.12 | Label Box | ✅ UTF-8 labels |
| M.13 | Association Box | ✅ Nested grouping |
| M.14 | Number List Box | ✅ Entity types |

### Part 2 Codestream Marker Coverage

| Marker | Feature | Status |
|--------|---------|--------|
| SIZ | Extended Rsiz capabilities | ✅ Part 2/HTJ2K flags |
| COD | Extended coding style | ✅ Part 2 extensions |
| COC | Per-component extensions | ✅ Part 2 extensions |
| QCD | Extended quantization | ✅ Extended guard bits |
| QCC | Per-component quantization | ✅ Extended guard bits |
| DCO | DC offset | ✅ Per-component offsets |
| ADS | Arbitrary decomposition | ✅ Custom kernels |
| MCT | Multi-component transform | ✅ Array-based |
| MCC | Component collection | ✅ Component grouping |
| MCO | Transform ordering | ✅ Transform sequence |

## Version History

| Version | Changes |
|---------|---------|
| v1.6.0 | Initial Part 2 conformance testing framework |
