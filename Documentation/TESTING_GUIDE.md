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
- [How to Test Encoding](#how-to-test-encoding)
  - [Step-by-Step: Encode a Single Image](#step-by-step-encode-a-single-image)
  - [Encoding Presets Reference](#encoding-presets-reference)
  - [Side-by-Side Configuration Comparison](#side-by-side-configuration-comparison)
  - [Batch Encoding](#batch-encoding)
- [How to Test Decoding](#how-to-test-decoding)
  - [Step-by-Step: Decode a File](#step-by-step-decode-a-file)
  - [Using the Region-of-Interest Selector](#using-the-region-of-interest-selector)
  - [Resolution Level Stepper](#resolution-level-stepper)
  - [Quality Layer Slider](#quality-layer-slider)
  - [Component Channel Selector](#component-channel-selector)
  - [Marker Inspector Panel](#marker-inspector-panel)
- [How to Test Round-Trip](#how-to-test-round-trip)
  - [Step-by-Step: One-Click Round-Trip](#step-by-step-one-click-round-trip)
  - [Understanding PSNR, SSIM, and MSE](#understanding-psnr-ssim-and-mse)
  - [Lossless Bit-Exact Badge](#lossless-bit-exact-badge)
  - [Difference Image View](#difference-image-view)
  - [Test Image Generator](#test-image-generator)
- [How to Test Performance](#how-to-test-performance)
  - [Benchmark Tab — Throughput and Latency Profiling](#benchmark-tab--throughput-and-latency-profiling)
  - [GPU Tab — Metal Acceleration Testing](#gpu-tab--metal-acceleration-testing)
  - [SIMD Tab — Vectorisation Testing](#simd-tab--vectorisation-testing)
  - [Performance Targets Reference](#performance-targets-reference)
- [Common GUI Components](#common-gui-components)
  - [Image Preview Panel](#image-preview-panel)
  - [Image Comparison View](#image-comparison-view)
  - [Progress Indicator](#progress-indicator)
  - [Results Table](#results-table)
  - [Log Console](#log-console)
- [Settings](#settings)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Quick Start](#quick-start)
- [Troubleshooting](#troubleshooting)
- [Extending the Test App](#extending-the-test-app)
- [Keyboard Shortcuts Reference](#keyboard-shortcuts-reference)
- [Conformance Matrix Reference](#conformance-matrix-reference)
- [Performance Targets Reference](#performance-targets-reference)
- [Glossary](#glossary)

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

## How to Test Encoding

The **Encode** screen (`EncodeView`) provides a complete workflow for testing JPEG 2000 encoding.
Open it by selecting **Encode** in the sidebar.

### Step-by-Step: Encode a Single Image

1. **Load an input image** — drag and drop a PNG, TIFF, or BMP file onto the drop zone in the
   detail area, or click inside the zone to browse.  The thumbnail preview appears immediately.

2. **Configure encoding** — use the left-hand configuration panel to adjust:
   - **Quality slider** — drag from 0.0 (maximum compression) to 1.0 (lossless).
   - **Wavelet selector** — choose `5/3 (Lossless)`, `9/7 Float`, `9/7 Fixed`, or `Haar`.
   - **Tile Width / Tile Height** — enter pixel dimensions for the tile grid.
   - **Decomp Levels stepper** — number of wavelet decomposition levels (0–10).
   - **Quality Layers stepper** — number of embedded quality layers (1–20).
   - **Progression Order** — select LRCP, RLCP, RPCL, PCRL, or CPRL via the radio group.
   - **MCT toggle** — enable Multi-Component Transform (ICT) for colour images.
   - **HTJ2K toggle** — enable Part 15 high-throughput encoding.

3. **Apply a preset** (optional) — click one of the four preset buttons at the top of the panel
   to populate all settings at once:
   - **Lossless** — quality 1.0, 5/3 wavelet, 1 quality layer.
   - **Lossy High Quality** — quality 0.95, 9/7 Float, 5 layers.
   - **Visually Lossless** — quality 0.85, RLCP progression.
   - **Maximum Compression** — quality 0.5, 512×512 tiles, 10 layers.

4. **Encode** — click the **Encode** button in the toolbar (or press **⌘↵**).  A real-time
   progress bar appears showing overall percentage and a per-stage breakdown:
   - Colour Transform → DWT → Quantise → Entropy Coding → Rate Control → Packaging.

5. **Inspect the output** — when encoding completes the **Encoding Output** box shows:
   - **Encoded Size** — size of the produced codestream (e.g. "12.4 KB").
   - **Compression Ratio** — input bytes ÷ output bytes (e.g. "8.19:1").
   - **Encoding Time** — wall-clock time in milliseconds.
   - **Stage Timing** — per-stage timing breakdown.

6. **Compare** — a side-by-side comparison panel shows the original image alongside the
   encoded-then-decoded output.  Use the segmented control to switch between **Side by Side**,
   **Overlay**, and **Difference** modes.

### Encoding Presets Reference

| Preset | Quality | Wavelet | Tile | Layers | Progression | Typical Ratio |
|--------|---------|---------|------|--------|-------------|---------------|
| **Lossless** | 1.00 | 5/3 | 256×256 | 1 | LRCP | 2:1 – 4:1 |
| **Lossy High Quality** | 0.95 | 9/7 Float | 256×256 | 5 | LRCP | 8:1 – 15:1 |
| **Visually Lossless** | 0.85 | 9/7 Float | 256×256 | 5 | RLCP | 15:1 – 25:1 |
| **Maximum Compression** | 0.50 | 9/7 Float | 512×512 | 10 | CPRL | 40:1 – 80:1 |

### Side-by-Side Configuration Comparison

1. Select the **Compare** tab in the toolbar above the detail area.
2. Adjust the configuration panel to the first configuration and click **Add Current Config**.
3. Change settings in the panel and click **Add Current Config** again.
4. The comparison panel shows each configuration's output side by side.  Click the **×** button
   on any card to remove it from the comparison.

### Batch Encoding

1. Select the **Batch** tab.
2. Click **Select Folder…** to choose a directory of images.  The list of files appears below.
3. Configure encoding settings in the left panel.
4. Click **Encode All**.  A progress bar tracks the overall batch progress.
5. When complete, a summary table shows each file's encoded size, compression ratio, and time.

---

## How to Test Decoding

The **Decode** screen (`DecodeView`) provides an interactive environment for testing JPEG 2000
decoding.  Open it by selecting **Decode** in the sidebar.

### Step-by-Step: Decode a File

1. **Open a file** — click **Open File…** in the toolbar and select a JP2, J2K, or JPX file.
   The codestream header summary appears in the banner at the top of the preview area,
   showing file name, format, dimensions, and component count.

2. **Configure decoding** — use the left-hand control panel to adjust:
   - **Resolution Level slider** — 0 = full resolution; higher values decode at reduced
     resolution (each step halves the width and height).
   - **Quality Layer slider** — 0 = all layers (maximum quality); higher values decode with
     fewer layers (faster, lower quality).
   - **Component selector** — choose **All Components** or select an individual channel
     (Component 0 = Y/R, 1 = Cb/G, 2 = Cr/B).

3. **Decode** — click the **Decode** button (or press **⌘↵**).  A progress bar tracks the
   four internal decode stages.

4. **Inspect the result** — the decoded image appears in the main preview area.  Use the zoom
   (`+`/`−`) and pan controls to examine details.  The **Decode Result** box in the left panel
   shows dimensions, component count, and decoding time.

### Using the Region-of-Interest Selector

1. Click the **ROI** toggle button in the toolbar to activate the selection tool.
2. Draw a rectangle on the preview image to define the region to decode.
3. An indicator at the bottom of the preview shows the selected region dimensions and offset.
4. Click **Decode** — only the selected region is decoded.  This exercises the JPEG 2000
   region-of-interest decoding path.
5. To clear the ROI, click the **×** button next to the indicator, or click the **ROI** toggle
   again and click **Clear** in the status area.

### Resolution Level Stepper

| Level | Effective Resolution | Use Case |
|-------|---------------------|----------|
| 0 | Full (1×) | Complete detail inspection |
| 1 | ½ × ½ | Thumbnail generation |
| 2 | ¼ × ¼ | Fast preview |
| 3 | ⅛ × ⅛ | Overview only |

Drag the **Resolution Level** slider to the desired level and press **Decode** after each change
to compare the decoded output at each level.

### Quality Layer Slider

- Drag the **Quality Layer** slider to 0 for maximum quality (all layers decoded).
- Increase the value to stop decoding after fewer layers — the image will be noisier but
  decoding will be faster.
- This exercises the progressive-quality path defined in ISO/IEC 15444-1 Annex B.

### Component Channel Selector

For multi-component images (YCbCr or RGB):

- **All Components** — decodes all three channels and combines them.
- **Component 0 (Y/R)** — luminance or red channel only.
- **Component 1 (Cb/G)** — blue-difference or green channel.
- **Component 2 (Cr/B)** — red-difference or blue channel.

Inspecting individual components is useful for verifying MCT (Multi-Component Transform)
correctness.

### Marker Inspector Panel

1. Click the **Markers** toggle button in the toolbar to open the inspector panel on the right.
2. The tree view shows all codestream marker segments:
   - **SOC** — Start of Codestream (byte offset 0x0000)
   - **SIZ** — Image and tile size (dimensions, components, bit depth)
   - **COD** — Coding style default (progression order, wavelet, levels)
   - **QCD** — Quantisation default (step sizes)
   - **SOT** — Start of Tile-part (expandable; contains **SOD**)
   - **EOC** — End of Codestream
3. Click the **▶** arrow on any composite marker (e.g. SOT) to expand its children.
4. Each row shows the marker name, byte offset in hexadecimal, and a human-readable summary.

---

## How to Test Round-Trip

The **Round-Trip Validation** screen (`RoundTripView`) performs a complete encode → decode →
compare workflow with automatic quality metrics.  It is accessible via the **Encode** sidebar
entry when using the **Round-Trip** tab, or directly from the main window.

### Step-by-Step: One-Click Round-Trip

1. **Choose or generate an input image**:
   - To use a synthetic image, select a type from the **Test Image Generator** panel
     (Gradient, Checkerboard, Noise, Solid Colour, or Lena-Style) and click **Generate**.
   - To use a real image, drag and drop it onto the encode drop zone first.

2. **Select an encoding preset** from the left panel: Lossless, Lossy High Quality, Visually
   Lossless, or Maximum Compression.

3. **Run** — click **Run Round-Trip** (or press **⌘↵**).  Three steps execute in sequence:
   - **Step 1/3: Encoding** — input image is encoded with the selected configuration.
   - **Step 2/3: Decoding** — encoded codestream is decoded back to pixels.
   - **Step 3/3: Computing metrics** — PSNR, SSIM, and MSE are computed.

4. **Read the results** — the metrics panel at the bottom of the screen shows:
   - **PSNR** — coloured green (≥ 40 dB) or red (< 40 dB).
   - **SSIM** — coloured green (≥ 0.99) or red (< 0.99).
   - **MSE** — coloured green (< 10.0) or red (≥ 10.0).
   - A **Pass** or **Fail** badge appears in the toolbar.

5. **Compare images** — the main area shows original vs. round-tripped in **Side by Side** mode.
   Use the segmented control to switch to **Overlay** or **Difference** modes.

### Understanding PSNR, SSIM, and MSE

| Metric | Full Name | Pass Threshold | Notes |
|--------|-----------|---------------|-------|
| **PSNR** | Peak Signal-to-Noise Ratio | ≥ 40 dB | Higher is better; ∞ for lossless |
| **SSIM** | Structural Similarity Index | ≥ 0.99 | Range 0–1; 1.0 = identical |
| **MSE** | Mean Squared Error | < 10.0 | Lower is better; 0.0 = identical |

Typical values for common presets:

| Preset | PSNR | SSIM | MSE |
|--------|------|------|-----|
| Lossless | ∞ dB | 1.0000 | 0.0 |
| Lossy High Quality | ~49 dB | ~0.995 | ~0.2 |
| Visually Lossless | ~47 dB | ~0.993 | ~0.5 |
| Maximum Compression | ~40 dB | ~0.990 | ~1.0 |

### Lossless Bit-Exact Badge

When the **Lossless** preset is used (5/3 wavelet, quality = 1.0), the round-trip produces
bit-for-bit identical pixels.  The toolbar displays a **Bit-Exact Lossless ✓** badge in green.
The PSNR is shown as **∞ dB** and SSIM as **1.0000**.  MSE is **0.0**.

### Difference Image View

1. After a round-trip completes, click the **Difference** toggle button in the toolbar.
2. The main area switches to a difference image that highlights per-pixel discrepancies:
   - **Black pixels** — identical to the original (no difference).
   - **Bright pixels** — indicate deviations from the original.
3. For a lossless round-trip the difference image will be uniformly black.
4. Toggle the button again to switch back to the comparison view.

### Test Image Generator

The **Test Image Generator** panel creates 64×64 synthetic images for quick testing without
requiring external files.

| Type | Description | Best for |
|------|-------------|---------|
| **Gradient** | Smooth horizontal/vertical colour ramp | Wavelet transform quality |
| **Checkerboard** | High-frequency black/white pattern | Entropy coding efficiency |
| **Noise** | Random per-pixel values | Worst-case compression |
| **Solid Colour** | Uniform grey (128, 128, 128) | Lossless verification |
| **Lena-Style** | Sinusoidal luminance pattern | Natural image approximation |

---

## How to Test Conformance

The **Conformance** screen provides an interactive dashboard for ISO/IEC 15444-4 conformance testing
across Parts 1, 2, 3/10, and 15 of the JPEG 2000 standard.

### Opening the Conformance Screen

1. Select **Conformance** in the sidebar.
2. The conformance matrix loads automatically with the default requirement set.

### Running Conformance Tests

1. Click **Run All Conformance Tests** in the toolbar.
2. A progress bar shows overall completion.
3. As tests complete, cells in the matrix update with colour-coded results:
   - 🟢 **Green** — Pass
   - 🔴 **Red** — Fail
   - ⚪ **Grey** — Skip (requirement not applicable to this part)
4. The **summary banner** at the top left shows e.g. "17/17 tests passed" with a percentage bar.

### Reading the Conformance Matrix

| Column | Description |
|--------|-------------|
| **Requirement** | Requirement identifier (e.g. T.1.1) |
| **Description** | Human-readable description of the requirement |
| **Part 1** | Core coding system result |
| **Part 2** | Extensions result |
| **Part 3/10** | Motion and volumetric result |
| **Part 15** | HTJ2K result |

Click the **chevron** at the end of any row to expand the detailed test log.

### Filtering by Part

Use the **Filter by Part** segmented control in the left panel to show only requirements
relevant to a specific part. Select "All Parts" to see the full matrix.

### Exporting the Conformance Report

1. Select the desired format (JSON, HTML, or PDF) using the segmented control.
2. Click **Export** to generate the report.
3. JSON exports include `totalTests`, `passed`, `failed`, `skipped`, `passRate`, and `duration`.

---

## How to Test OpenJPEG Interoperability

The **Conformance** sidebar category includes interoperability testing. In the current implementation
the interoperability screen is accessible through dedicated views that compare J2KSwift and OpenJPEG
decode outputs side by side.

### Loading a Codestream

1. Drop a J2K or JP2 file into the input area, or use the file picker to select one.
2. The file name appears in the **Input Codestream** section of the left panel.

### Running the Comparison

1. Click **Run Comparison** in the toolbar.
2. The screen performs four steps:
   - Decode the codestream with J2KSwift
   - Decode the codestream with OpenJPEG
   - Compute pixel-level differences
   - Build a codestream structure diff tree
3. Progress is shown via a progress bar.

### Reading the Results

**Side-by-Side Images**: The top area shows J2KSwift output on the left and OpenJPEG output on the right.

**Performance Comparison**: The left panel shows a bar chart comparing J2KSwift and OpenJPEG
decode times with a speedup factor.

**Pixel Difference**: Max pixel difference and tolerance status are shown. Adjust the
**Tolerance Threshold** slider (0–10) to set the acceptable pixel difference.

**Codestream Structure Diff**: The bottom area shows a tree of marker segments with:
- 🟢 **Green equal sign** — Values match between J2KSwift and OpenJPEG
- 🟠 **Orange warning** — Values differ

### Bidirectional Testing

Toggle **Bidirectional** in the toolbar to test both directions:
- Encode with J2KSwift → Decode with OpenJPEG
- Encode with OpenJPEG → Decode with J2KSwift

### Results History

All comparison results are accumulated in the **Results History** section of the left panel,
showing the codestream name, tolerance pass/fail, and speedup factor.

---

## How to Validate a Codestream

The **Validation** screen provides three tools for inspecting JPEG 2000 codestreams and file formats.

### Opening the Validation Screen

1. Select **Validation** in the sidebar.
2. Drop a J2K, JP2, JPX, or JPM file into the input area.

### Codestream Syntax Validation

1. Select **Codestream** mode in the toolbar segmented control.
2. Click **Validate**.
3. The findings list shows each marker found with:
   - Severity icon: 🔵 Info, 🟠 Warning, 🔴 Error
   - Byte offset in hexadecimal
   - Description of the finding
4. The left panel shows a **Valid** or **Invalid** badge.

### File Format Validation

1. Select **File Format** mode.
2. Click **Validate**.
3. The box structure tree shows all JP2/JPX/JPM boxes:
   - ✅ Green checkbox — Valid box
   - ❌ Red checkbox — Invalid box
   - Nested boxes are indented to show hierarchy
4. Each box shows type code, description, and size in bytes.

### Marker Inspector

1. Select **Marker Inspector** mode.
2. Click **Validate**.
3. The marker list shows all codestream markers with:
   - Marker name (SOC, SIZ, COD, etc.)
   - Byte offset
   - Length in bytes
   - Summary description
4. The **Hex Dump** panel below shows raw hex data for the selected marker with highlighted boundaries.

---

## How to Test Performance

The **Performance** screen provides three tabbed sub-screens: **Benchmark**, **GPU**, and **SIMD**. Select the **Performance** category in the sidebar to access them.

### Benchmark Tab — Throughput and Latency Profiling

1. Select the **Benchmark** tab at the top.
2. In the left panel, tick the **Image Sizes** to benchmark (e.g. 512×512, 1024×1024).
3. Tick the **Coding Modes** to test (e.g. Lossless, HTJ2K).
4. Adjust **Iterations** (default: 10) and **Warm-up** rounds (default: 2).
5. Click **Run Benchmark**.
6. The **Throughput chart** shows megapixels per second for each configuration.
7. The **Latency chart** shows milliseconds per encode/decode.
8. The **Regression Badge** indicates:
   - 🟢 **No Regression** — throughput within 5% of historical baseline
   - 🟠 **Possible Regression** — throughput dropped 5–15%
   - 🔴 **Regression Detected** — throughput dropped more than 15%
9. The **Memory Usage** panel shows peak allocation, current usage, and allocation count.
10. Click **Export** to download results as CSV or JSON.

### GPU Tab — Metal Acceleration Testing

1. Select the **GPU** tab.
2. The **Metal availability badge** shows whether Metal is available on the current platform.
3. Select an operation (DWT, Colour Transform, Quantisation, Entropy Coding, Rate Control) from the radio group.
4. Click **Run All GPU Tests** to test all operations, or **Run Selected** for just one.
5. The **GPU vs CPU Comparison** table shows:
   - GPU and CPU timing in milliseconds
   - Speedup factor (green if GPU is faster, red otherwise)
   - Output match indicator (✅ outputs identical, ❌ mismatch)
   - GPU memory usage per operation
6. The **GPU Speedup Factor** chart visualises speedup per operation.
7. The **Shader Status** panel lists all Metal shaders with compile time and status.
8. The **GPU Memory** monitor shows buffer pool utilisation and peak usage.

### SIMD Tab — Vectorisation Testing

1. Select the **SIMD** tab.
2. The **Platform Badge** shows the detected architecture (ARM Neon or x86 SSE/AVX).
3. Click **Run All SIMD Tests** to test all vectorised operations.
4. The **SIMD Utilisation** gauge shows the overall utilisation percentage:
   - Target is **≥85%** — green when met, orange when below
5. The **Operations** list in the left panel shows pass/fail status and speedup for each operation.
6. The **SIMD vs Scalar Speedup** chart visualises the speedup factor per operation.
7. The **Detailed Results** table shows:
   - SIMD and scalar timing in milliseconds
   - Speedup factor
   - Output match indicator
   - Platform identifier

### Performance Targets Reference

| Mode | Expected Speedup vs OpenJPEG | Notes |
|------|------------------------------|-------|
| Lossless | ≥1.0× | Baseline target |
| Lossy | ≥1.2× | With rate control |
| HTJ2K | ≥2.0× | Optimised block coder |
| HTJ2K Lossless | ≥1.8× | FBCOT fast path |
| Tiled Lossless | ≥1.0× | Per-tile overhead |
| Tiled Lossy | ≥1.2× | Parallel tile encoding |

---

## Conformance Matrix Reference

The conformance matrix maps JPEG 2000 standard requirements to test results across parts.

| Requirement | Description | Applicable Parts |
|-------------|-------------|------------------|
| T.1.1 | SOC marker present at start of codestream | All |
| T.1.2 | SIZ marker immediately follows SOC | All |
| T.1.3 | COD marker present in main header | All |
| T.1.4 | QCD marker present in main header | All |
| T.1.5 | SOT marker present for each tile | All |
| T.1.6 | EOC marker at end of codestream | All |
| T.1.7 | Valid tile-part lengths | All |
| T.1.8 | Component sub-sampling factors valid | All |
| T.2.1 | Part 2 extended capabilities signalled | Part 1, Part 2 |
| T.2.2 | MCT extension markers valid | Part 1, Part 2 |
| T.2.3 | Arbitrary wavelet decomposition valid | Part 1, Part 2 |
| T.3.1 | Part 3/10 volumetric marker segments | Part 3/10 |
| T.3.2 | Z-axis transform parameters valid | Part 3/10 |
| T.15.1 | HTJ2K CAP marker present | Part 15 |
| T.15.2 | HT cleanup pass valid | Part 15 |
| T.15.3 | HT SigProp and MagRef passes valid | Part 15 |
| T.15.4 | FBCOT block coder output valid | Part 15 |

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

## How to Test JPIP Streaming

The **Streaming** screen provides two tabbed sub-screens: **JPIP** and **MJ2**. Select the **Streaming** category in the sidebar to access them.

### How to Test JPIP Streaming

1. Open the **Streaming** category and select the **JPIP** tab.
2. In the **Control Panel**, enter the JPIP server URL (e.g. `jpip://localhost:8080/image.jp2`).
3. Click **Connect** in the toolbar.
   - The status badge changes to **On** (green) when connected.
4. Adjust the **Window of Interest** sliders to select a region of the image.
5. Set the desired **Resolution Level** using the stepper.
6. Click **Load Image** to start a progressive load.
   - The **Progressive Image Canvas** displays the image as quality layers arrive.
   - The toolbar progress bar tracks the current quality layer.
7. After loading completes, read the **Network Metrics** panel:
   - **Bytes Received** — total compressed data delivered in this session
   - **Avg Latency** — average round-trip time per JPIP request
   - **Requests** — total number of JPIP data-bin requests sent
   - **Duration** — elapsed session time in seconds
8. Review the **Request Log** table to inspect every individual JPIP request with its status code, byte count, latency, and URL path.
9. Click **Clear Log** to reset metrics and the request log for a fresh test.
10. Click **Disconnect** to close the JPIP session.

### How to Test Motion JPEG 2000

1. Open the **Streaming** category and select the **MJ2** tab.
2. In the **Control Panel**, configure the encoding settings:
   - Toggle **Uniform Settings** to apply one quality value across all frames, or disable to configure per-frame.
   - Adjust the **Quality** slider (0.0–1.0) for uniform encoding.
   - Set the **Frame Rate** field (frames per second).
3. Click **Load Sequence** in the toolbar to load a test frame sequence (60 frames by default).
4. Use the **Playback Controls** to navigate frames:
   - **Play/Pause** — toggle live playback simulation
   - **Stop** — return to frame 1
   - **Step Forward/Backward** — single-frame navigation
   - **Frame Scrubber** — drag to jump directly to any frame
5. Click any bar in the **Frame Timeline** at the bottom to jump to that frame.
   - Bar height indicates PSNR; colour indicates quality tier (green ≥ 45 dB, yellow 40–45 dB, orange < 40 dB).
6. Inspect the selected frame in the **Control Panel**:
   - Timestamp, resolution, compressed size, PSNR, SSIM, and decode time are shown.
7. The **Sequence Summary** panel shows aggregate statistics: frame count, duration, average PSNR, and average SSIM.
8. Click **Clear** to reset and load a new sequence.

---

## How to Test Volumetric (JP3D)

Select the **Volumetric** category in the sidebar to access the `VolumetricTestView`.

1. In the **Control Panel**, choose an anatomical plane: **Axial**, **Coronal**, or **Sagittal**.
2. Set the wavelet parameters:
   - **Z-axis Levels** stepper (1–6 decomposition levels along the z-axis)
   - **Wavelet** radio group: 5/3 (lossless), 9/7 (lossy), or Haar
3. Click **Run Test** in the toolbar.
   - The toolbar progress bar shows per-slice encode/decode progress.
   - The status bar reports the current slice number.
4. When complete, the **Slice Comparison** panel appears:
   - Left placeholder: original slice
   - Right placeholder: decoded slice (or difference image if **Show Difference Overlay** is enabled)
   - PSNR and SSIM badges appear in the header for the current slice.
5. Use the **Slice Navigator** in the Control Panel to scroll through slices:
   - Drag the slider, or use the chevron buttons to step one slice at a time.
6. Review the **Per-Slice Quality Metrics** table at the bottom:
   - Each row shows slice index, plane, PSNR (dB), SSIM, decode time (ms), and resolution.
   - PSNR values below 40 dB are highlighted in orange as a quality warning.
7. Toggle **Show Difference Overlay** to switch the right comparison panel between decoded and difference views.
8. Click **Clear** to reset all results and re-run with different parameters.

---

*J2KTestApp is part of J2KSwift v2.1 — a pure Swift 6 JPEG 2000 implementation.*
*Last updated: 2026-02-21*

---

## How to Read Test Reports

After running tests through **J2KTestApp** or the headless CLI, the **Report** screen provides a visual summary.

### Summary Dashboard

Select **Report** in the sidebar to open the dashboard. The top section shows three summary cards:

- **Total** — number of tests run in the most recent session.
- **Passed** — number of tests that passed.
- **Pass Rate** — overall pass percentage.

### Trend Chart

The **Pass Rate Trend** chart plots pass-rate data points over the last five sessions. Each dot represents a session; the line connecting them shows the trajectory. A flat or rising line indicates stability; a falling line warrants investigation.

### Coverage Heatmap

The **Coverage Heatmap** is a grid of coloured cells mapping JPEG 2000 standard parts (rows) against test sections (columns):

| Colour | Coverage Level |
|--------|---------------|
| 🔴 Red | < 25% |
| 🟠 Orange | 25 – 49% |
| 🟡 Yellow | 50 – 74% |
| 🟢 Light green | 75 – 99% |
| 💚 Dark green | 100% |

Each cell shows the test count. Click **Refresh** (⌘R) to reload data from the current session.

### Exporting Reports

Use the **Export** panel on the left to choose a format and click **Export Report**:

- **HTML** — self-contained HTML file with embedded charts.
- **JSON** — structured data for programmatic processing.
- **CSV** — spreadsheet-friendly tabular output.

The path of the last exported file is shown below the export button.

---

## How to Create Test Playlists

A *playlist* is a named set of test categories that can be saved and re-run as a unit.

### Using Preset Playlists

J2KTestApp ships with four built-in presets (see [Preset Playlists Reference](#preset-playlists-reference)). Select **Playlists** in the sidebar. The **Presets** section of the sidebar lists all four.

### Creating a Custom Playlist

1. Click the **＋ New Playlist** button (toolbar or bottom of the sidebar).
2. Enter a **name** for the playlist.
3. Toggle the **categories** you want to include.
4. Click **Create**.

The new playlist appears in the **Custom** section of the sidebar.

### Reordering and Deleting Custom Playlists

- Drag rows in the **Custom** section to reorder them.
- Swipe left on a row (or right-click and choose **Delete**) to remove it.

### Running a Playlist

Select the playlist and click **Run Playlist** (⌘R) in the detail pane. A progress bar tracks category completion. When finished, the status message confirms the run.

---

## How to Run Tests in CI/CD

J2KTestApp supports a headless mode for automated CI/CD pipelines.

### CLI Usage

```bash
j2k testapp --headless \
  --playlist "Quick Smoke Test" \
  --output report.html \
  --format html
```

**Flags:**

| Flag | Required | Description |
|------|----------|-------------|
| `--headless` | ✅ | Enable headless (non-GUI) mode |
| `--playlist <name>` | ✅ | Name of the playlist to run |
| `--output <path>` | ✅ | Path for the output report file |
| `--format html\|json\|csv` | Optional | Report format (default: `html`) |

**Exit codes:** `0` = all tests passed, `1` = one or more tests failed.

### GitHub Actions

The repository ships a `interactive-testing.yml` workflow:

```yaml
# Trigger manually via GitHub Actions UI
workflow_dispatch:
  inputs:
    playlist:
      description: 'Test playlist to run'
      default: 'Quick Smoke Test'
```

To run it manually: go to **Actions → Interactive Testing (Headless) → Run workflow** and choose a playlist.

The workflow also runs automatically every **Monday at 06:00 UTC** (the `schedule` trigger).

On completion:
- Exit code is checked and the step fails if any tests failed.
- A **test report artifact** is uploaded (HTML/JSON/CSV) and retained for 30 days.

---

## Preset Playlists Reference

| Preset | Categories | Best Used For |
|--------|-----------|---------------|
| **Quick Smoke Test** | Encode, Decode | Fast pre-merge sanity check (< 1 min) |
| **Full Conformance** | Conformance, Validation, Encode, Decode | ISO/IEC 15444 compliance verification |
| **Performance Suite** | Performance | Benchmarking and regression detection |
| **Encode/Decode Only** | Encode, Decode | Pipeline-focused testing without conformance overhead |

### When to Use Each Preset

- **Quick Smoke Test** — Run on every PR to catch regressions quickly.
- **Full Conformance** — Run nightly or before a release to verify standard compliance.
- **Performance Suite** — Run on main branch after performance-related changes to detect regressions.
- **Encode/Decode Only** — Run when working on codec changes and conformance testing is not relevant.

---

---

## Quick Start

This one-page summary gets you from a fresh checkout to a passing smoke test in under five minutes.

| Step | Command / Action | Expected Result |
|------|-----------------|----------------|
| 1. Clone | `git clone https://github.com/Raster-Lab/J2KSwift.git && cd J2KSwift` | Repository cloned |
| 2. Build | `swift build --target J2KTestApp` | `Build complete!` |
| 3. Launch | `swift run J2KTestApp` | Main window opens |
| 4. Select | Click **Encode** in the sidebar | Encode screen appears |
| 5. Run smoke test | Click **Run All** (⌘R) | Progress bar fills; all results green |
| 6. Read results | Click **Report** in the sidebar | Summary dashboard with pass rate |

If any step fails, see [Troubleshooting](#troubleshooting) below.

---

## Troubleshooting

### Build Errors

**Error: `'J2KCore' module not found`**  
Cause: Missing module dependency.  
Fix: Run `swift package resolve` then `swift build --target J2KTestApp` again.

**Error: `cannot find type 'Observable' in scope`**  
Cause: Swift version is older than 5.9.  
Fix: Install Swift 6.2 or later (bundled with Xcode 16.3+).

**Error: `unable to attach DB`** (SwiftData/Core Data)  
Cause: Stale build artefact.  
Fix: Delete `.build/` and retry: `rm -rf .build && swift build --target J2KTestApp`.

### Runtime Issues

**Sidebar shows no items**  
Cause: `TestCategory.allCases` returned empty — usually a Debug build issue.  
Fix: Build with `swift build -c release --target J2KTestApp`.

**All tests show "pending" and never run**  
Cause: The async test runner task may have been cancelled.  
Fix: Click **Stop** (⌘.) then **Run All** (⌘R) again.

**Encode / Decode buttons are greyed out**  
Cause: No image has been loaded yet (the button requires a valid input path).  
Fix: Drag an image file onto the drop zone, or click **Open File…**.

**JPIP screen shows "Network Unavailable"**  
Cause: No JPIP server is running at the configured address.  
Fix: Start a local OpenJPEG JPIP server or change the URL in the JPIP screen to a reachable endpoint.

**GPU screen shows "Metal not available"**  
Cause: Running in a VM or on a machine without Metal support.  
Fix: GPU tests are skipped automatically; results are marked as "skipped" rather than "failed".

**Report export produces an empty file**  
Cause: No test results have been recorded yet.  
Fix: Run at least one test category before exporting.

### macOS Permissions

If macOS shows a security warning when launching J2KTestApp for the first time:  
1. Go to **System Settings → Privacy & Security**.  
2. Scroll to the bottom and click **Open Anyway**.  
3. Confirm in the dialog that appears.

---

## Extending the Test App

This section is for developers who want to add new test scenarios or GUI screens.

### Adding a New Test Runner

1. **Create a type** that conforms to `TestRunnerProtocol` in your module:

```swift
import J2KCore

struct MyCustomTestRunner: TestRunnerProtocol {
    let category: TestCategory = .encode   // choose the appropriate category

    func run(session: TestSession) async {
        let result = TestResult(testName: "My custom test", category: category)
        // Perform your test logic here…
        await session.addResult(result.markPassed(duration: 0.1))
    }
}
```

2. **Register the runner** during app startup:

```swift
TestRunnerRegistry.shared.register(MyCustomTestRunner(), for: .encode)
```

3. **Run it** via the existing Encode screen — your runner will be invoked alongside the built-in ones when the user presses **Run**.

### Adding a New GUI Screen

1. **Create a view model** in `Sources/J2KCore/J2KTestAppModels.swift` (must be in J2KCore because the test target imports J2KCore):

```swift
#if canImport(SwiftUI) && os(macOS)
import SwiftUI

@Observable
public final class MyFeatureViewModel {
    public var isRunning: Bool = false
    public var result: String = ""

    public init() {}

    public func run() async {
        isRunning = true
        // … your logic …
        result = "Done"
        isRunning = false
    }
}
#endif
```

2. **Create a SwiftUI view** in `Sources/J2KTestApp/Views/MyFeatureView.swift`:

```swift
#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

struct MyFeatureView: View {
    @State var viewModel: MyFeatureViewModel
    let session: TestSession

    var body: some View {
        VStack {
            Text(viewModel.result)
            Button("Run") {
                Task { await viewModel.run() }
            }
            .disabled(viewModel.isRunning)
        }
        .padding()
        .navigationTitle("My Feature")
    }
}
#endif
```

3. **Add a `TestCategory` case** (if needed) in `J2KTestAppModels.swift`:

```swift
public enum TestCategory: String, CaseIterable, Identifiable, Codable {
    // … existing cases …
    case myFeature = "myFeature"
}
```

4. **Wire it up** in `CategoryDetailView.body` in `Sources/J2KTestApp/Views/MainWindow.swift`:

```swift
case .myFeature:
    MyFeatureView(viewModel: myFeatureViewModel, session: session)
```

5. **Write tests** in `Tests/J2KTestAppTests/J2KTestAppTests.swift` using `@testable import J2KCore`:

```swift
final class MyFeatureViewModelTests: XCTestCase {
    func testRunSetsResult() async {
        let vm = MyFeatureViewModel()
        await vm.run()
        XCTAssertEqual(vm.result, "Done")
    }
}
```

### Design Guidelines for New Screens

- Use `J2KDesignSystem` tokens for spacing, typography, and corner radius — do not hardcode values.
- Apply `AccessibilityIdentifiers` constants to interactive controls.
- Wrap error states in `ErrorStateModel` and display them with a consistent error view.
- Use British English throughout labels, tooltips, and documentation.
- All view models must be `@Observable` and `public` (so they can be tested via J2KCore).

---

## Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| **⌘R** | Run all tests |
| **⌘.** | Stop all running tests |
| **⌘⇧E** | Export test results |
| **⌘,** | Open Settings |
| **⌘W** | Close window |
| **⌘Q** | Quit J2KTestApp |
| **⌘1** — **⌘7** | Jump to sidebar category 1–7 |
| **↑ / ↓** | Navigate sidebar items |
| **⌘↩** | Run selected category |
| **⌘⇧C** | Copy selected result to clipboard |
| **⌘⇧S** | Save current report |
| **Space** | Preview selected image (Quick Look) |

### Encode Screen

| Shortcut | Action |
|----------|--------|
| **⌘O** | Open image file |
| **⌘↩** | Start encoding |
| **⌘1–5** | Select encoding preset |

### Decode Screen

| Shortcut | Action |
|----------|--------|
| **⌘O** | Open J2K/JP2 file |
| **⌘↩** | Start decoding |
| **⌘+** / **⌘-** | Zoom in / out on preview |
| **⌘⌥R** | Reset ROI to full image |

### Report Screen

| Shortcut | Action |
|----------|--------|
| **⌘⇧E** | Export report |
| **⌘⇧J** | Export as JSON |
| **⌘⇧H** | Export as HTML |

---

## Conformance Matrix Reference

| Part | Standard | Categories Tested | Pass Target |
|------|----------|-------------------|-------------|
| **Part 1** | ISO/IEC 15444-1 | Core encode/decode, lossless, lossy | 100% |
| **Part 2** | ISO/IEC 15444-2 | Extended capabilities, ROI | 100% |
| **Part 3** | ISO/IEC 15444-3 | Motion JPEG 2000 | 100% |
| **Part 10** | ISO/IEC 15444-10 | JP3D volumetric | 100% |
| **Part 15** | ISO/IEC 15444-15 | HTJ2K high-throughput | 100% |

### Reading the Conformance Matrix

The ConformanceView shows a colour-coded grid:

- 🟢 **Green** — all tests for that requirement passed
- 🟡 **Amber** — some tests passed but at least one skipped
- 🔴 **Red** — one or more tests failed
- ⬜ **Grey** — not yet tested

---

## Performance Targets Reference

| Metric | Target | Platform |
|--------|--------|----------|
| Encode throughput | ≥ 500 MP/s | Apple M-series |
| Decode throughput | ≥ 800 MP/s | Apple M-series |
| HTJ2K encode | ≥ 2 GP/s | Apple M-series (Metal) |
| HTJ2K decode | ≥ 3 GP/s | Apple M-series (Metal) |
| SIMD utilisation | ≥ 85% | ARM Neon |
| GPU speedup (encode) | ≥ 4× vs CPU | Metal |
| GPU speedup (decode) | ≥ 6× vs CPU | Metal |
| Memory overhead | < 3× image size | All platforms |

---

## Glossary

| Term | Definition |
|------|-----------|
| **JPEG 2000** | ISO/IEC 15444 image compression standard supporting both lossy and lossless coding. |
| **JP2** | The JPEG 2000 Part 1 file format container (`.jp2`). |
| **JPX** | The JPEG 2000 Part 2 extended file format (`.jpx`). |
| **J2K / JPC** | Raw JPEG 2000 codestream without a file format wrapper (`.j2k`, `.j2c`). |
| **MJ2** | Motion JPEG 2000 — a video container wrapping JPEG 2000 frames (`.mj2`). |
| **JP3D** | JPEG 2000 Part 10 — volumetric 3D image coding. |
| **HTJ2K** | High Throughput JPEG 2000 (ISO/IEC 15444-15) — a block coding variant optimised for speed. |
| **DWT** | Discrete Wavelet Transform — the spatial decorrelation step in JPEG 2000 encoding. |
| **5/3 filter** | Integer reversible wavelet filter used for lossless JPEG 2000 coding. |
| **9/7 filter** | Float irreversible wavelet filter used for lossy JPEG 2000 coding. |
| **MCT** | Multiple Component Transform — converts RGB to YCbCr (or similar) before coding. |
| **RCT** | Reversible Colour Transform — integer MCT for lossless coding. |
| **ICT** | Irreversible Colour Transform — float MCT for lossy coding. |
| **Tile** | A rectangular subdivision of an image that is encoded independently. |
| **Precinct** | A spatial subdivision of a subband; the basic unit for JPIP data packets. |
| **Code block** | The smallest unit of entropy coding in JPEG 2000 (typically 64×64 samples). |
| **MQ coder** | The adaptive binary arithmetic entropy coder used in JPEG 2000. |
| **PCRL** | Progression order: Position–Component–Resolution–Layer. |
| **LRCP** | Progression order: Layer–Resolution–Component–Position (default). |
| **RLCP** | Progression order: Resolution–Layer–Component–Position. |
| **RPCL** | Progression order: Resolution–Position–Component–Layer. |
| **CPRL** | Progression order: Component–Position–Resolution–Layer. |
| **Quality layer** | A set of code-block contributions that collectively improve image quality by a defined amount. |
| **Resolution level** | A level in the DWT hierarchy; level 0 is the full resolution, higher levels are coarser. |
| **ROI** | Region of Interest — a spatial area that is encoded at higher quality than the background. |
| **PSNR** | Peak Signal-to-Noise Ratio — a measure of reconstruction quality in decibels (higher = better). |
| **SSIM** | Structural Similarity Index — a perceptual image quality metric (1.0 = identical). |
| **MSE** | Mean Squared Error — average squared difference between original and reconstructed pixels. |
| **JPIP** | JPEG 2000 Interactive Protocol (ISO/IEC 15444-9) — HTTP-based progressive streaming. |
| **WOI** | Window of Interest — the spatial region requested by a JPIP client. |
| **Metal** | Apple's low-level GPU compute and graphics framework. |
| **SIMD** | Single Instruction, Multiple Data — CPU instruction set for parallel arithmetic. |
| **Neon** | ARM's SIMD instruction set extension. |
| **AVX2** | Intel's Advanced Vector Extensions 2 (256-bit SIMD). |
| **SSE4.2** | Intel's Streaming SIMD Extensions 4.2 (128-bit). |
| **Accelerate** | Apple's framework for high-performance signal processing (vDSP, vImage, BLAS, LAPACK). |
| **OpenJPEG** | The ISO reference open-source JPEG 2000 codec used for interoperability testing. |
| **Codestream** | The raw sequence of bytes produced by JPEG 2000 encoding. |
| **SOC marker** | Start Of Codestream — the first 2 bytes (`0xFF 0x4F`) of every JPEG 2000 codestream. |
| **SOT marker** | Start Of Tile-part. |
| **SIZ marker** | Image and tile size marker segment. |
| **COD marker** | Coding style default marker segment. |
| **QCD marker** | Quantisation default marker segment. |
| **EOC marker** | End Of Codestream (`0xFF 0xD9`). |

---

*J2KTestApp is part of J2KSwift v2.1 — a pure Swift 6 JPEG 2000 implementation.*
*Last updated: 2026-07-15*
