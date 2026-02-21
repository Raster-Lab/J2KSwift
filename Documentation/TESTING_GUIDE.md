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
