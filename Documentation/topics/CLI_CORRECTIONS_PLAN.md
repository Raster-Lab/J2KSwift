# J2KSwift CLI Corrections Plan

Corrections to the `j2k` CLI addressing optional output file names, additional
file format support (TIFF, PNG, DICOM), and piped inter-library format
conversion.

All changes are scoped to the `J2KCLI` target only — no modifications to
`J2KCore`, `J2KCodec`, `J2KFileFormat`, or `Package.swift`.

---

## 1. Optional Output File Names

### Current Behaviour

The `encode`, `decode`, `transcode`, and `convert` commands all **require**
`-o`/`--output`. If the flag is omitted the CLI prints an error and exits:

```
Error: Missing required argument: -o/--output
```

### Proposed Behaviour

Make `-o`/`--output` optional across all single-file commands. When omitted,
derive the output path from the input file name by replacing its extension with
one appropriate to the operation and format requested.

#### Default Extension Rules

| Command     | Condition                             | Default Extension |
|-------------|---------------------------------------|-------------------|
| `encode`    | `--format jp2`                        | `.jp2`            |
| `encode`    | `--format jpx`                        | `.jpx`            |
| `encode`    | `--htj2k` (no explicit `--format`)    | `.jph`            |
| `encode`    | default (no `--format`, no `--htj2k`) | `.j2k`            |
| `decode`    | greyscale, 1 component                | `.pgm`            |
| `decode`    | colour, ≥ 3 components               | `.ppm`            |
| `decode`    | explicit `--output-format tiff`       | `.tiff`           |
| `decode`    | explicit `--output-format png`        | `.png`            |
| `transcode` | determined by target `--format`       | `.j2k` / `.jph` / `.jp2` |
| `convert`   | determined by `--output-format`       | matches format    |

#### Algorithm

```
1. If -o / --output is supplied → use it as-is (no change).
2. Otherwise:
   a. Take the input file path.
   b. Strip the existing extension.
   c. Append the default extension from the table above.
   d. Place the output in the same directory as the input.
```

#### Changes Required

| File | Change |
|------|--------|
| `MultiFileProcessor.swift` | Add a new `deriveOutputPath(inputPath:command:options:componentCount:)` static method. This helper inspects the parsed options dictionary (`--format`, `--htj2k`, `--output-format`, `--to-htj2k`) and the command name to select the correct extension. It sits alongside the existing `resolveOutputPath` used by batch mode. |
| `Commands.swift` | In `encodeCommand`: replace the `guard let outputPath` block with a fallback that calls `deriveOutputPath` when `-o` is absent. The encode path can derive immediately since the format is known before loading. In `decodeCommand`: move the output path resolution to *after* decoding so the component count is available for choosing `.pgm` vs `.ppm`. |
| `Transcode.swift` | In `transcodeCommand` single-file mode: replace the `guard let outputPath` block with a fallback to `deriveOutputPath`. |
| `Convert.swift` | In `convertCommand`: replace the `guard let outputPath` block with a fallback to `deriveOutputPath`. |
| `Batch.swift` | No change — batch mode already uses `--output-suffix` and `resolveOutputPath`. |

#### Help Text Updates

Update the `--output` description in every help printer (`printEncodeHelp`,
`printDecodeHelp`, `printTranscodeHelp`, `printConvertHelp`) and in
`main.swift`'s `printUsage` to indicate the flag is optional:

```
-o, --output PATH   Output file (optional; derived from input name if omitted)
```

---

## 2. Additional File Format Support

### 2.1 TIFF (Input and Output — maintaining high bit depth)

#### Scope

- Read **uncompressed** TIFF files (little-endian `II` and big-endian `MM`
  byte order).
- Support **8-bit, 16-bit, and 32-bit** samples — preserving the full bit
  depth through the encode/decode pipeline so no precision is lost.
- Write TIFF files with the same bit depth as the image being saved.
- Greyscale (1 component), RGB (3 components), and RGBA (4 components).

#### Design

Create a new file `TIFFSupport.swift` in `Sources/J2KCLI/` containing a
minimal TIFF reader/writer with **no dependency on libtiff or any external
library**. The parser handles only the uncompressed baseline subset used in
medical and scientific imaging.

**Reading (`loadTIFF(_ data: Data) throws -> J2KImage`):**

1. Parse the 8-byte TIFF header:
   - Bytes 0–1: byte-order mark (`II` = little-endian, `MM` = big-endian).
   - Bytes 2–3: magic number `42`.
   - Bytes 4–7: offset to first IFD.
2. Walk the IFD entries to extract the tags required for pixel access:
   - `ImageWidth` (256), `ImageLength` (257)
   - `BitsPerSample` (258), `SamplesPerPixel` (277)
   - `PhotometricInterpretation` (262) — 0/1 = greyscale, 2 = RGB
   - `StripOffsets` (273), `RowsPerStrip` (278), `StripByteCounts` (279)
   - `Compression` (259) — must be 1 (uncompressed); reject otherwise
   - `SampleFormat` (339) — 1 = unsigned int, 2 = signed int (default 1)
   - `PlanarConfiguration` (284) — 1 = interleaved (default), 2 = planar
3. Read pixel strips into a contiguous buffer. If big-endian and sample size
   > 8 bits, byte-swap to host order.
4. De-interleave multi-sample data into separate `J2KComponent` planes
   (same approach as `loadPPM`).
5. Set `J2KImage.colorSpace` based on `PhotometricInterpretation`.

**Writing (`saveTIFF(_ image: J2KImage, to url: URL) throws`):**

1. Emit a little-endian TIFF header.
2. Write pixel data as a single contiguous strip with interleaved samples.
   For multi-component images, interleave from the separate `J2KComponent`
   planes. Preserve the original bit depth (8/16/32).
3. Write an IFD with the minimal required tags:
   `ImageWidth`, `ImageLength`, `BitsPerSample`, `Compression` (1),
   `PhotometricInterpretation`, `StripOffsets`, `RowsPerStrip`,
   `StripByteCounts`, `SamplesPerPixel`, `SampleFormat`.
4. Update the header's IFD offset to point to the IFD.

**Validation / error handling:**

- Compressed TIFF → error: "Only uncompressed TIFF is supported."
- Tiled TIFF → error: "Tiled TIFF is not supported; use strip-based TIFF."
- Float samples (SampleFormat = 3) → error: "Floating-point TIFF samples are
  not supported."

#### Wiring into the CLI

| File | Change |
|------|--------|
| `TIFFSupport.swift` *(new)* | `loadTIFF` and `saveTIFF` as described above. |
| `ImageIO.swift` | Add `case "tiff", "tif"` to `loadImage(from:)` calling `loadTIFF`, and to `saveImage(_:to:)` calling `saveTIFF`. |
| `Commands.swift` | Update `printEncodeHelp` input format list and `printDecodeHelp` `--output-format` list to include `tiff`. |
| `Convert.swift` | Add `tiff` / `tif` to `printConvertHelp` supported-formats list. |
| `MultiFileProcessor.swift` | Add `"tiff"`, `"tif"` to `supportedExtensions` in `resolveDirectory`. |

### 2.1 (continued) PNG (Input and Output — maintaining high bit depth)

#### Scope

- Read PNG files: **8-bit and 16-bit** greyscale, RGB, and RGBA.
- Write PNG files preserving bit depth: 8-bit and 16-bit per channel.
- This maintains high bit depth through the pipeline — 16-bit PNG is losslessly
  round-tripped.

#### Design

Create a new file `PNGSupport.swift` in `Sources/J2KCLI/`. Use a cross-platform
pure-Swift implementation using zlib (available on all supported platforms via
`import Foundation` or `Glibc`/`Musl`).

**Reading (`loadPNG(_ data: Data) throws -> J2KImage`):**

1. Verify the 8-byte PNG signature (`\x89PNG\r\n\x1a\n`).
2. Parse chunks sequentially:
   - **IHDR**: extract width, height, bit depth (8 or 16), colour type
     (0 = greyscale, 2 = RGB, 4 = greyscale+alpha, 6 = RGBA).
   - **IDAT**: concatenate all IDAT chunk payloads.
   - **IEND**: stop.
3. Decompress the concatenated IDAT payload with zlib inflate.
4. Reverse the per-row filter byte (None, Sub, Up, Average, Paeth).
5. De-interleave into separate `J2KComponent` planes.
6. Set `J2KImage.colorSpace` based on colour type.
7. Reject interlaced PNG (interlace method ≠ 0) with a clear error.

**Writing (`savePNG(_ image: J2KImage, to url: URL) throws`):**

1. Validate: components must be 1, 2 (greyscale+alpha), 3 (RGB), or 4 (RGBA);
   bit depth must be 8 or 16.
2. Write PNG signature.
3. Write IHDR chunk.
4. Interleave component data into scanlines with a filter byte (Sub filter for
   simplicity and reasonable compression).
5. Compress with zlib deflate.
6. Write IDAT chunk(s) (split at 32 KB boundaries).
7. Write IEND chunk.

**Validation / error handling:**

- Bit depth not 8 or 16 → error with descriptive message.
- Interlaced PNG → error: "Interlaced PNG is not supported."
- Palette-based PNG (colour type 3) → error: "Indexed-colour PNG is not
  supported; convert to RGB first."

#### Wiring into the CLI

| File | Change |
|------|--------|
| `PNGSupport.swift` *(new)* | `loadPNG` and `savePNG` as described above. |
| `ImageIO.swift` | Add `case "png"` to `loadImage(from:)` calling `loadPNG`, and to `saveImage(_:to:)` calling `savePNG`. |
| `Commands.swift` | Update `printEncodeHelp` input format list and `printDecodeHelp` `--output-format` list to include `png`. |
| `Convert.swift` | Add `png` to `printConvertHelp` supported-formats list. |
| `MultiFileProcessor.swift` | Add `"png"` to `supportedExtensions` in `resolveDirectory`. |

---

### 2.2 DICOM (Input Only — strip metadata)

#### Scope

- Read **uncompressed** DICOM files (both explicit and implicit VR, both
  little-endian and big-endian transfer syntaxes).
- **Strip all DICOM metadata** — extract only the raw pixel data and the
  minimal tags needed to interpret it.
- Output a `J2KImage` ready for encoding.
- **Input only** — writing DICOM files is outside scope.

#### Relationship to ADR-004

ADR-004 states that **J2KSwift (the library)** has no DICOM dependency. This
plan adds DICOM reading **only to the CLI target** (`J2KCLI`). No DICOM code
is added to `J2KCore`, `J2KCodec`, or `J2KFileFormat`. The CLI's DICOM reader
is a thin metadata-stripping parser, not a general-purpose DICOM toolkit.

#### Design

Create a new file `DICOMSupport.swift` in `Sources/J2KCLI/`.

**`loadDICOM(_ data: Data) throws -> J2KImage`:**

1. **Parse the DICOM preamble** — skip the 128-byte preamble and verify the
   `DICM` magic at byte offset 128 (4 bytes).
2. **Read File Meta Information** (group `0002`), always explicit VR
   little-endian:
   - `(0002,0010)` Transfer Syntax UID — determines VR encoding and byte order
     for the rest of the dataset:
     - `1.2.840.10008.1.2` — Implicit VR Little Endian
     - `1.2.840.10008.1.2.1` — Explicit VR Little Endian
     - `1.2.840.10008.1.2.2` — Explicit VR Big Endian
     - Any JPEG 2000 TS (`1.2.840.10008.1.2.4.90` – `.203`) → error:
       "Input is already JPEG 2000 compressed; use `j2k decode` instead."
     - Any other compressed TS → error: "Compressed DICOM transfer syntax
       is not supported."
3. **Walk the dataset** to extract pixel-interpretation tags:
   - `(0028,0010)` Rows
   - `(0028,0011)` Columns
   - `(0028,0100)` Bits Allocated (8 or 16)
   - `(0028,0101)` Bits Stored
   - `(0028,0102)` High Bit
   - `(0028,0103)` Pixel Representation (0 = unsigned, 1 = signed)
   - `(0028,0002)` Samples Per Pixel
   - `(0028,0004)` Photometric Interpretation
   - `(0028,0006)` Planar Configuration (if samples > 1)
   - `(7FE0,0010)` Pixel Data — the raw pixel bytes.
4. **Handle byte ordering** — if the transfer syntax is big-endian and
   Bits Allocated > 8, byte-swap each 16-bit sample to host order.
5. **De-interleave** multi-component data (Planar Configuration = 0, i.e.
   interleaved by pixel) into separate `J2KComponent` planes.
   If Planar Configuration = 1 (interleaved by plane), split the data
   directly into per-component slices.
6. **Map colour space** from `PhotometricInterpretation`:
   - `MONOCHROME1` / `MONOCHROME2` → `.grayscale`
   - `RGB` → `.sRGB`
   - `YBR_FULL` / `YBR_FULL_422` → convert to RGB (`.sRGB`) during loading
     so downstream commands always receive RGB component data.
7. **Return** a `J2KImage` with the correct dimensions, bit depth per
   component (`Bits Stored`), signedness, and colour space.

**Tag parsing helper:**

- Implement a small `readTag` helper that reads a (group, element) pair,
  determines VR (from the explicit bytes, or from a minimal implicit-VR
  dictionary for the tags listed above), reads the value length, and returns
  the value bytes.
- Skip sequence items (`SQ` VR) by reading their defined or undefined length
  and advancing past them.
- Stop parsing once `(7FE0,0010)` Pixel Data is found (the remaining bytes
  after the value-length header are the pixel data).

**Validation / error handling:**

- Missing `DICM` magic → error: "Not a valid DICOM file (missing DICM
  prefix). Ensure the file includes the 128-byte preamble."
- Encapsulated (compressed) pixel data (undefined length with item
  delimiters) → error: "Encapsulated pixel data is not supported; only
  uncompressed DICOM files can be read."
- Missing required tags → error naming the missing tag.
- Multi-frame: extract only the first frame, warn if `(0028,0008)`
  Number of Frames > 1.

#### Wiring into the CLI

| File | Change |
|------|--------|
| `DICOMSupport.swift` *(new)* | `loadDICOM` as described above. |
| `ImageIO.swift` | Add `case "dcm", "dicom"` to `loadImage(from:)` calling `loadDICOM`. No save case — DICOM is input only. |
| `Commands.swift` | Update `printEncodeHelp` input format list to include `dcm`/`dicom`. |
| `Convert.swift` | Add `dcm` / `dicom` to `printConvertHelp` as an input-only format. |
| `MultiFileProcessor.swift` | Add `"dcm"`, `"dicom"` to `supportedExtensions` in `resolveDirectory`. |

---

## 3. Piped Inter-Library Format Conversion

### Current State

The CLI currently has **no stdin/stdout piping support** for image data. All
encode, decode, transcode, and convert commands require file paths for both
input and output. The only stdin usage is reading a **list of file paths** via
`--input-list -` in batch mode.

However, the underlying library APIs (`J2KEncoder.encode(_:)` and
`J2KDecoder.decode(_:)`) operate entirely on in-memory `Data` objects, making
piping feasible without architectural changes to the library.

### Goal

Enable piping between compression tools so a user can convert from one format
to another **without writing the intermediate uncompressed file to disk**.

Example use cases:
```bash
# Decode a JPEG XS file and pipe the raw image to J2K encoder
jxs decode -i input.jxs -o - | j2k encode -i - -o output.j2k

# Pipe a DICOM file through J2K encoding
j2k encode -i input.dcm -o - | other-tool process -i -

# Chain decode → re-encode without intermediate file
j2k decode -i input.j2k -o - --output-format raw | \
  other-codec encode -i - -o output.ext

# Pipe between two J2KSwift commands (e.g. decode then re-encode as HTJ2K)
j2k decode -i legacy.j2k -o - --output-format raw | \
  j2k encode -i - -o modern.jph --htj2k --lossless
```

### Design

#### Convention: `-` means stdin / stdout

Follow the widespread Unix convention:
- `-i -` or `--input -` → read image data from **stdin**.
- `-o -` or `--output -` → write output data to **stdout**.

When either is used, all informational/diagnostic output (`Encoded:`,
`Decoded:`, timing, etc.) must be redirected to **stderr** so it does not
contaminate the data stream.

#### Wire Format for Piped Image Data

When piping **uncompressed image data** between tools, the CLI needs a
self-describing wire format so the receiving end knows the dimensions, bit
depth, and component count without a separate header file. Two approaches:

**Option A — PNM passthrough (recommended):**

Use the existing PGM (P5) / PPM (P6) format as the wire format:
- Greyscale → PGM (P5) header + pixel data.
- RGB → PPM (P6) header + pixel data.
- Supports 8-bit and 16-bit.
- Any Unix tool that understands PNM can participate in the pipeline.
- The `--output-format` flag on `decode` already implies the format; for
  pipe mode, default to `pgm`/`ppm` based on component count.
- Higher bit depths (> 16-bit) can use the raw format with a minimal header
  (see Option B) or TIFF written to stdout.

**Option B — Raw with J2K header (alternative):**

Define a minimal binary header: `J2KR` magic (4 bytes) + width (4 bytes BE) +
height (4 bytes BE) + component count (2 bytes BE) + bit depth per component
(1 byte each) + signedness flags + pixel data. This is more compact and
supports arbitrary bit depths but requires both ends to understand the header.

**Recommendation:** Use **Option A (PNM passthrough)** as the default piped
format and add `--pipe-format raw` for the custom header as a future
extension. PNM is universally understood, simple, and already implemented.

#### Implementation Details

**Reading from stdin (`-i -`):**

```
1. Read all data from FileHandle.standardInput into a Data buffer.
2. Auto-detect the format from the data content:
   a. PGM/PPM: check for "P5" or "P6" magic at start.
   b. JPEG 2000: check for SOC marker (0xFF4F) or JP2 signature.
   c. TIFF: check for "II" or "MM" byte-order mark + magic 42.
   d. PNG: check for PNG signature (89 50 4E 47).
   e. DICOM: check for DICM magic at offset 128.
   f. If none match, treat as raw data (requires --width, --height,
      --components, --bit-depth flags).
3. Route to the appropriate loader (loadPGM, loadPPM, J2KDecoder, etc.)
```

**Writing to stdout (`-o -`):**

```
1. Determine the output format:
   - encode/transcode: write the encoded J2K/JP2 data directly.
   - decode: write PGM/PPM (or the format specified by --output-format)
     to stdout.
   - convert: write the target format to stdout.
2. Write the data to FileHandle.standardOutput.
3. Redirect all informational output to stderr.
```

**Diagnostic output to stderr:**

When `-o -` is active, all `print()` calls for status messages must go to
stderr. Add a helper:

```swift
static func printInfo(_ message: String) {
    // Write to stderr when stdout is used for data
    if outputIsStdout {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    } else {
        print(message)
    }
}
```

Or more simply, detect at the start of each command whether `-o -` is in use
and set a flag that routes print calls.

#### Changes Required

| File | Change |
|------|--------|
| `Commands.swift` | In `encodeCommand`: detect `-i -` and read from stdin; detect `-o -` and write to stdout; redirect diagnostics to stderr. Same for `decodeCommand`. |
| `Transcode.swift` | Same stdin/stdout support in `transcodeCommand`. |
| `Convert.swift` | Same stdin/stdout support in `convertCommand`. |
| `ImageIO.swift` | Add `loadImageFromStdin() throws -> J2KImage` that reads `FileHandle.standardInput` and auto-detects format. Add `saveImageToStdout(_ image: J2KImage, format: String) throws` that writes to `FileHandle.standardOutput`. |
| `main.swift` | Update `printUsage` examples to show piping. |
| `Batch.swift` | No change — piping does not apply to batch mode. |

#### Help Text Additions

Add to each command's help:

```
PIPING:
    -i -                        Read input from stdin
    -o -                        Write output to stdout
    When piping, diagnostic messages are sent to stderr.

EXAMPLES:
    jxs decode -i input.jxs -o - | j2k encode -i - -o output.j2k
    j2k decode -i input.j2k -o - | j2k encode -i - --htj2k -o output.jph
    cat scan.dcm | j2k encode -i - -o compressed.j2k
```

---

## 4. Summary of All File Changes

| File | Status | Purpose |
|------|--------|---------|
| `MultiFileProcessor.swift` | Modify | Add `deriveOutputPath` helper; add new extensions to `supportedExtensions`. |
| `Commands.swift` | Modify | Optional output path; stdin/stdout piping for encode/decode; help text updates with new formats. |
| `Transcode.swift` | Modify | Optional output path; stdin/stdout piping for transcode; help text updates. |
| `Convert.swift` | Modify | Optional output path; stdin/stdout piping for convert; help text updates with new formats. |
| `ImageIO.swift` | Modify | Route `.tiff`/`.tif`, `.png`, `.dcm`/`.dicom` to new loaders/savers; add `loadImageFromStdin` and `saveImageToStdout`. |
| `main.swift` | Modify | Update `printUsage` to reflect new format support, optional `-o`, and piping examples. |
| `TIFFSupport.swift` | **New** | Minimal uncompressed TIFF reader/writer (8/16/32-bit). |
| `PNGSupport.swift` | **New** | PNG reader/writer using zlib (8/16-bit). |
| `DICOMSupport.swift` | **New** | Minimal DICOM pixel-data extractor (input only, strips metadata). |

No changes to `J2KCore`, `J2KCodec`, `J2KFileFormat`, or `Package.swift` are
required — all new code lives in the `J2KCLI` target.

---

## 5. Testing Strategy

| Area | Test Approach |
|------|---------------|
| Optional output names | Unit tests verifying `deriveOutputPath` produces correct extensions for each command × format combination (encode default `.j2k`, encode `--htj2k` → `.jph`, encode `--format jp2` → `.jp2`, decode greyscale → `.pgm`, decode RGB → `.ppm`, decode `--output-format tiff` → `.tiff`, transcode default → `.j2k`, transcode `--to-htj2k` → `.jph`, convert `--output-format png` → `.png`). |
| TIFF round-trip | Create synthetic `J2KImage` instances (8-bit greyscale, 16-bit greyscale, 8-bit RGB, 16-bit RGB, RGBA). Save via `saveTIFF`, reload via `loadTIFF`, compare pixel values are identical. Test both LE and BE TIFF input. |
| PNG round-trip | Create synthetic images (8-bit greyscale, 8-bit RGB, 8-bit RGBA, 16-bit greyscale, 16-bit RGB). Save via `savePNG`, reload via `loadPNG`, compare pixel values. Verify rejection of interlaced and palette-based PNG. |
| DICOM input | Prepare minimal synthetic DICOM test files: LE Explicit VR (8-bit mono, 16-bit mono, 8-bit RGB), BE Explicit VR (16-bit mono), Implicit VR (16-bit mono). Verify pixel data extraction matches expected values. Verify compressed DICOM is rejected. Verify JPEG 2000–compressed DICOM produces guidance message. |
| Piping | Integration tests: (a) `j2k encode -i test.pgm -o -` produces valid J2K on stdout. (b) `cat test.j2k | j2k decode -i - -o output.pgm` decodes correctly. (c) `j2k decode -i test.j2k -o - | j2k encode -i - -o roundtrip.j2k` produces a valid re-encoded file. (d) Verify diagnostics go to stderr, not stdout, when `-o -` is active. |
| Integration | End-to-end: `j2k encode -i test.tiff` (no `-o`) → verify output `test.j2k` created. `j2k decode -i test.j2k` → verify output `test.pgm` or `test.ppm`. `j2k encode -i scan.dcm --lossless` → verify J2K output. |
| Regression | Run existing `swift test` suite to confirm no breakage. Build with `swift build` to verify compilation. |

---

## 6. Implementation Order

1. **`deriveOutputPath` helper + optional output in all commands** — smallest
   change, unblocks other work, no new dependencies.
2. **TIFF support** — straightforward binary format, no compression dependency,
   validates the high-bit-depth pipeline.
3. **PNG support** — requires zlib; slightly more complex but uses
   platform-available zlib.
4. **DICOM support** — most complex parser; benefits from TIFF/PNG work
   stabilising `ImageIO.swift` first.
5. **Stdin/stdout piping** — builds on all the above; requires every command
   to be updated but uses the same loader/saver infrastructure.

---

## 7. Design Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| No external dependencies for TIFF/PNG/DICOM | Keeps the CLI self-contained; avoids pulling in libtiff, libpng, or DICOM libraries. The subset needed is small. |
| DICOM in CLI only, not in library | Respects ADR-004 (no DICOM dependency in J2KSwift library). The CLI parser is a thin pixel-data extractor. |
| PNG supports 16-bit | The requirement says "maintaining high bit rate" — 16-bit PNG is commonly used in medical/scientific imaging and should be preserved. |
| TIFF supports 32-bit | 32-bit integer TIFF samples are used in scientific imaging; JPEG 2000 supports up to 38-bit components. |
| `deriveOutputPath` uses options dict | Avoids a complex parameter list; the helper reads `--format`, `--htj2k`, `--output-format`, `--to-htj2k` directly from the parsed options. |
| Decode derives path after decoding | Component count is only known after decoding, so the default extension (`.pgm` vs `.ppm`) must be chosen post-decode. |
| Little-endian TIFF output | Nearly all modern software reads LE TIFF; no need to add a `--tiff-endian` flag. |
| Sub filter for PNG writing | Simple, effective, and widely compatible. Optimal filtering adds complexity with marginal benefit for a CLI tool. |
| PNM as pipe wire format | PGM/PPM is already implemented, universally understood, and self-describing. Avoids inventing a custom header. Works with any tool that speaks PNM (ImageMagick, NetPBM, etc.). |
| `-` convention for stdin/stdout | Standard Unix convention; used by `tar`, `curl`, `ffmpeg`, `ImageMagick`, `gzip`, etc. Minimal learning curve. |
| Diagnostics to stderr when piping | Prevents status messages from corrupting the binary data stream. Standard practice for Unix tools. |
| Auto-detect format on stdin | Since stdin has no file extension, the CLI inspects magic bytes. All supported formats have distinctive signatures, making auto-detection reliable. |
