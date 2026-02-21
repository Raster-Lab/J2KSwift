# J2KTestApp — Testing Guide

A comprehensive guide to testing every feature of J2KSwift using the native macOS GUI application.

## Table of Contents

- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Building the Application](#building-the-application)
  - [Launching J2KTestApp](#launching-j2ktestapp)
- [Main Window Overview](#main-window-overview)
  - [Sidebar Navigation](#sidebar-navigation)
  - [Detail Area](#detail-area)
  - [Toolbar](#toolbar)
  - [Status Bar](#status-bar)
- [Navigation](#navigation)
  - [Encode](#encode)
  - [Decode](#decode)
  - [Conformance](#conformance)
  - [Performance](#performance)
  - [Streaming](#streaming)
  - [Volumetric](#volumetric)
  - [Validation](#validation)
- [Common GUI Components](#common-gui-components)
  - [Image Preview Panel](#image-preview-panel)
  - [Image Comparison View](#image-comparison-view)
  - [Progress Indicator](#progress-indicator)
  - [Results Table](#results-table)
  - [Log Console](#log-console)
- [Settings](#settings)
- [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Getting Started

### Prerequisites

- **macOS 15** (Sequoia) or later
- **Xcode 16.3** or later (for building from source)
- **Swift 6.2** or later
- J2KSwift repository cloned locally

### Building the Application

Build J2KTestApp from the command line:

```bash
# Clone the repository
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift

# Build J2KTestApp
swift build --target J2KTestApp

# Or build in release mode for better performance
swift build -c release --target J2KTestApp
```

Alternatively, open the project in Xcode:

```bash
open Package.swift
```

Select the **J2KTestApp** scheme and build with **⌘B**.

### Launching J2KTestApp

From the command line:

```bash
swift run J2KTestApp
```

Or launch from Xcode by selecting the **J2KTestApp** scheme and pressing **⌘R**.

The application opens with the main window showing the sidebar navigation on the left and a welcome screen on the right.

---

## Main Window Overview

J2KTestApp uses a `NavigationSplitView` layout with three main areas:

```
┌─────────────────────────────────────────────────────────────────┐
│  [Run All]  [Stop]  [Export Results]  [Settings]  Ready         │
├──────────────────┬──────────────────────────────────────────────┤
│                  │                                              │
│  ▶ Encode        │                                              │
│  ▶ Decode        │          Detail Area                         │
│  ▶ Conformance   │                                              │
│  ▶ Performance   │    Select a category from the sidebar        │
│  ▶ Streaming     │    to begin testing.                         │
│  ▶ Volumetric    │                                              │
│  ▶ Validation    │                                              │
│                  │                                              │
│                  ├──────────────────────────────────────────────┤
│                  │  Console Output                              │
│                  │  09:15:30 INFO  Session started.              │
│                  │  09:15:31 INFO  Running Encode tests...       │
└──────────────────┴──────────────────────────────────────────────┘
```

### Sidebar Navigation

The left sidebar lists seven test categories, each represented by an icon and a brief description:

| Icon | Category | Description |
|------|----------|-------------|
| ↑📄 | **Encode** | Test JPEG 2000 encoding with various configurations, presets, and input images |
| ↓📄 | **Decode** | Test JPEG 2000 decoding with region-of-interest, resolution levels, and quality layers |
| ✓🛡 | **Conformance** | Run ISO/IEC 15444-4 conformance tests across Parts 1, 2, 3, 10, and 15 |
| 📊 | **Performance** | Benchmark encoding and decoding performance with live charts and regression detection |
| 📡 | **Streaming** | Test JPIP progressive streaming with window-of-interest selection |
| 🧊 | **Volumetric** | Test JP3D volumetric encoding, decoding, and slice navigation |
| 🔍 | **Validation** | Validate codestream syntax, file format boxes, and marker segments |

Click any category to display its testing interface in the detail area.

### Detail Area

The detail area shows the testing interface for the selected category. Each category screen includes:

1. **Header** — Category name, description, and action buttons (Run, Clear)
2. **Progress** — Progress bar with status message (visible when tests are running)
3. **Results Table** — Sortable table of test results with status, duration, and metrics
4. **Log Console** — Real-time log output from test execution

### Toolbar

The toolbar at the top of the window provides global actions:

| Button | Shortcut | Description |
|--------|----------|-------------|
| **Run All** | ⌘R | Run all tests across all categories |
| **Stop** | ⌘. | Stop all running tests |
| **Export Results** | ⇧⌘E | Export test results as JSON |
| **Settings** | ⌘, | Open application settings |

### Status Bar

The right side of the toolbar shows a status message indicating the current state:
- **Ready** — No tests running
- **Running all tests...** — Global test execution in progress
- **42/50 passed** — Summary after test completion
- **Stopped** — Tests were manually stopped

---

## Navigation

### Encode

Test JPEG 2000 encoding with various configurations:

- **Drag-and-drop** input images (PNG, TIFF, BMP) for encoding
- **Configuration panel** with controls for quality, tile size, progression order, wavelet type, MCT, and HTJ2K
- **Preset buttons** for common configurations: Lossless, Lossy High Quality, Visually Lossless, Maximum Compression
- **Real-time progress** with per-stage timing breakdown (colour transform → DWT → quantise → entropy coding)
- **Output inspection** showing encoded file size, compression ratio, and encoding time
- **Batch encoding** for processing multiple images with the same settings

### Decode

Test JPEG 2000 decoding with interactive features:

- **File picker** for JP2/J2K/JPX input files with codestream header summary
- **Region-of-interest selector** to decode specific image regions
- **Resolution level stepper** for multi-resolution decode comparison
- **Quality layer slider** for progressive quality improvement
- **Component channel selector** for multi-component images
- **Marker inspector** showing all codestream markers in a tree view

### Conformance

Run ISO/IEC 15444-4 conformance tests:

- **Conformance matrix** — colour-coded grid showing pass/fail status for each requirement
- **Per-part tabs** — Part 1, Part 2, Part 3/10, Part 15
- **Run All Conformance Tests** button with aggregate progress
- **Exportable reports** in JSON, HTML, or PDF format
- **Summary banner** showing total pass count and percentage

### Performance

Benchmark encoding and decoding performance:

- **Benchmark configuration** — image sizes, coding modes, iterations, warm-up rounds
- **Live charts** — real-time bar graphs of throughput and latency
- **Memory usage** — peak allocation, current usage, allocation count
- **Regression detection** — green/amber/red badge based on 5% threshold
- **Export** — CSV, JSON, or screenshot

### Streaming

Test JPIP progressive streaming:

- **Server connection** — enter JPIP URL, connect/disconnect
- **Progressive image canvas** — image renders as data arrives
- **Window-of-interest selector** — draw a rectangle to request a specific region
- **Network metrics** — bytes received, latency, request count
- **Request log** — all JPIP requests and responses with timing

### Volumetric

Test JP3D volumetric image processing:

- **Volume loader** — open multi-slice datasets
- **Slice navigator** — scroll through axial/coronal/sagittal slices
- **3D wavelet parameters** — decomposition levels, wavelet type, z-axis options
- **Encode/decode comparison** — per-slice quality metrics
- **Difference overlay** — original vs decoded slice comparison

### Validation

Validate codestream and file format correctness:

- **Syntax validator** — drag-and-drop J2K file validation
- **File format validator** — JP2/JPX/JPM box structure tree
- **Marker inspector** — hex dump with highlighted boundaries and decoded fields

---

## Common GUI Components

### Image Preview Panel

The image preview panel provides interactive image viewing:

- **Zoom controls** — `+` and `−` buttons with percentage display
- **Pan** — click and drag to move the image
- **Reset** — button to reset zoom and position to defaults
- **Pixel inspection** — view coordinates and colour values at cursor position

### Image Comparison View

Three comparison modes for side-by-side image analysis:

| Mode | Description |
|------|-------------|
| **Side by Side** | Original and processed images shown side-by-side |
| **Overlay** | Images overlaid with adjustable opacity slider |
| **Difference** | Pixel-level difference visualisation |

Switch between modes using the segmented control above the images.

### Progress Indicator

Shows encoding/decoding progress with per-stage breakdown:

- **Overall progress bar** with percentage
- **Per-stage indicators** for each pipeline stage:
  - Colour Transform (ICT/RCT)
  - DWT (Discrete Wavelet Transform)
  - Quantise
  - Entropy Coding (MQ-coder or HTJ2K)
  - Rate Control
  - Packaging

Each stage shows a progress bar, active/complete status indicator, and timing.

### Results Table

Sortable table displaying test outcomes:

| Column | Description |
|--------|-------------|
| **Test Name** | Name of the test |
| **Status** | Colour-coded badge: 🟢 Passed, 🔴 Failed, ⚪ Skipped, 🟠 Error |
| **Duration** | Execution time in milliseconds |

Click any column header to sort. Click a row to select it and view details.

### Log Console

Real-time log output with severity filtering:

- **Level filter** — Debug, Info, Warning, Error (segmented control)
- **Auto-scroll** — automatically scroll to latest messages
- **Timestamps** — each message shows time (HH:mm:ss)
- **Colour coding** — messages coloured by severity level

---

## Settings

Access settings via **⌘,** or the Settings toolbar button.

### Encoding Defaults

| Setting | Default | Description |
|---------|---------|-------------|
| Tile Size | 256 × 256 | Default tile dimensions |
| Quality | 0.90 | Default quality for lossy encoding (0.0–1.0) |
| Decomposition Levels | 5 | Default wavelet decomposition levels (0–10) |
| Quality Layers | 5 | Default number of quality layers (1–20) |
| HTJ2K | Off | Enable HTJ2K (Part 15) encoding by default |
| GPU Acceleration | Off | Enable GPU acceleration by default |

### Application

| Setting | Default | Description |
|---------|---------|-------------|
| Verbose Logging | Off | Show detailed log output in the console |
| Auto-Run on Drop | Off | Automatically run tests when files are dropped |
| Recent Sessions | 10 | Maximum number of recent sessions to retain |

Settings are saved as JSON and persist across application launches.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘R | Run All Tests |
| ⌘. | Stop All Tests |
| ⇧⌘E | Export Results |
| ⌘, | Open Settings |
| ⌘↵ | Run tests for selected category |

---

*J2KTestApp is part of J2KSwift v2.1 — a pure Swift 6 JPEG 2000 implementation.*
*Last updated: 2026-02-21*
