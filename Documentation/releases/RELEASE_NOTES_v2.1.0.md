# J2KSwift v2.1.0 Release Notes

**Release Date**: 2026-07-15  
**Phase**: Phase 18 — GUI Testing Application (Weeks 296–315)  
**Previous Version**: 2.0.0

---

## Headline Feature: J2KTestApp — Native macOS GUI Testing Application

v2.1.0 delivers a complete native macOS SwiftUI application for testing every feature of J2KSwift interactively. J2KTestApp provides 13 dedicated screens, real-time progress tracking, visual comparison tools, and a headless CLI mode for CI/CD automation.

---

## What's New

### J2KTestApp — GUI Testing Application

A full macOS application built with SwiftUI and `@Observable` view models.

#### Screens

| Screen | Description |
|--------|-------------|
| **Encode** | Drag-and-drop encoding with configuration panel, 5 presets, side-by-side comparison, and batch mode |
| **Decode** | File-based decoding with ROI selector, resolution stepper, quality-layer slider, component selector, and marker inspector |
| **Round-Trip** | One-click encode/decode/compare with PSNR/SSIM/MSE metrics and lossless bit-exact badge |
| **Conformance** | Part 1/2/3/10/15 conformance matrix dashboard with per-requirement status and HTML/JSON/PDF export |
| **Interoperability** | OpenJPEG side-by-side pixel comparison, performance charts, and codestream diff tree |
| **Validation** | Codestream syntax validator, file format box inspector, and marker-level analysis |
| **Performance** | Benchmark runner with live throughput charts, latency histograms, and regression detection |
| **GPU** | Metal pipeline testing with GPU vs CPU speedup comparison and shader compilation info |
| **SIMD** | ARM Neon / Intel SSE/AVX verification with utilisation gauges and platform detection |
| **JPIP** | Progressive streaming canvas with WOI selection, network metrics, and session log |
| **Volumetric** | JP3D slice navigation (XY/XZ/YZ planes) with encode/decode comparison |
| **MJ2** | Motion JPEG 2000 frame playback with frame stepping, quality inspection, and sequence loading |
| **Report** | Summary dashboard, trend charts, coverage heatmap, and export (HTML/JSON/CSV) |

#### Test Playlists

Named, reusable sets of test categories that can be run as a unit:

| Preset | Categories | Purpose |
|--------|-----------|---------|
| **Quick Smoke Test** | Encode, Decode | Fast pre-merge sanity check |
| **Full Conformance** | Conformance, Validation, Encode, Decode | ISO/IEC 15444 compliance verification |
| **Performance Suite** | Performance | Benchmarking and regression detection |
| **Encode/Decode Only** | Encode, Decode | Codec-focused pipeline testing |

Custom playlists can be created in the Playlists screen and persist across launches.

#### Headless CLI Mode

```bash
j2k testapp --headless \
  --playlist "Quick Smoke Test" \
  --output report.html \
  --format html
```

Exit code `0` = all tests passed, `1` = one or more tests failed.

---

### GUI Polish (Week 314–315)

#### Design System (`J2KDesignSystem`)

Consistent design tokens used across all screens:
- **Spacing** — `spacingXS` (4 pt) through `spacingXL` (32 pt)
- **Corner Radius** — `cornerRadiusSM/MD/LG` (6/10/14 pt)
- **Icon Sizes** — `iconSizeSM/MD/LG/XL` (16/24/48/96 pt)
- **Typography** — `headlineFont`, `subheadlineFont`, `bodyFont`, `captionFont`, `monoFont`

#### Dark Mode and Light Mode

J2KTestApp fully supports macOS dark mode and light mode. All screens use semantic SwiftUI colours that adapt automatically.

#### Accessibility

- All interactive controls have `accessibilityIdentifier` constants from `AccessibilityIdentifiers`
- Sidebar items include `accessibilityLabel` (display name) and `accessibilityHint` (description) for VoiceOver
- Toolbar buttons have descriptive labels for screen reader users

#### Window State Persistence (`WindowPreferences`)

- Window size is persisted to `UserDefaults` via `GeometryReader.onChange`
- Last-selected sidebar item is persisted and available for restoration on next launch
- Settings are stored via the existing `AppSettings`/`TestSession` actor

#### About Screen

- `AboutView` displays the application icon, version, copyright, tagline, links, and acknowledgements
- Accessible via **Help → About J2KTestApp** (uses `NSApp.orderFrontStandardAboutPanel`)

#### Error State Handling (`ErrorStateModel`)

Consistent error presentation across all screens:
- `ErrorStateModel` carries a title, message, optional suggested action, and system image
- Factory methods: `.fileNotFound(_:)`, `.encodingFailed(_:)`, `.decodingFailed(_:)`, `.networkUnavailable()`

#### macOS Settings Scene

A native `Settings` scene (⌘,) wraps encoding defaults and application preferences, replacing the sheet-only approach.

---

### Documentation

#### Complete Testing Guide (`Documentation/TESTING_GUIDE.md`)

The testing guide now covers all screens and includes these new sections:

- **Quick Start** — one-page summary: build → launch → smoke test → read results
- **Troubleshooting** — build errors, runtime issues, macOS permissions
- **Extending the Test App** — developer guide for adding new test runners and GUI screens
- **Keyboard Shortcuts Reference** — complete list including encode/decode/report shortcuts
- **Conformance Matrix Reference** — colour key and part-by-part breakdown
- **Performance Targets Reference** — throughput, latency, SIMD utilisation, GPU speedup targets
- **Glossary** — 50+ JPEG 2000 terms (DWT, MCT, HTJ2K, PSNR, SSIM, JPIP, WOI, etc.)

---

## Test Coverage

| Test Suite | New Tests | Total |
|-----------|-----------|-------|
| `J2KDesignSystemTests` | 6 | 6 |
| `WindowPreferencesTests` | 8 | 8 |
| `AboutViewModelTests` | 8 | 8 |
| `AccessibilityIdentifiersTests` | 8 | 8 |
| `ErrorStateModelTests` | 10 | 10 |
| **Total new** | **40** | — |
| **Grand total (J2KTestAppTests)** | — | **309** |

---

## Known Limitations

- **J2KTestApp** requires **macOS 15** (Sequoia) or later and **Swift 6.2**.
- The GPU screen requires Metal support; it gracefully skips tests and shows a "Metal not available" message on unsupported hardware.
- The JPIP screen requires a running JPIP server; it shows `ErrorStateModel.networkUnavailable()` if no server is reachable.
- Window state persistence uses `UserDefaults` (not `NSWindowRestoration`) — the window is restored to its last size but not position.

---

## Upgrade Guide

### From v2.0.0

No API changes. v2.1.0 adds new public types to `J2KCore`:
- `J2KDesignSystem` — design tokens
- `WindowPreferences` — window state persistence
- `AboutViewModel` — about screen data
- `AccessibilityIdentifiers` — accessibility identifier constants
- `ErrorStateModel` — error state presentation

These are additive; no existing code needs to change.

The `getVersion()` function now returns `"2.1.0"`.

---

## Checksums

| File | SHA-256 |
|------|---------|
| J2KSwift-2.1.0-source.zip | *(computed at release time)* |

---

*J2KSwift is a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444).*  
*© 2026 Raster Lab. All rights reserved.*
