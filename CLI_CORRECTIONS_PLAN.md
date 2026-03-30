# J2KSwift CLI Corrections Plan

Corrections to the `j2k` CLI addressing optional output file names and additional
file format support (TIFF, PNG, DICOM).

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

| Command     | Condition                          | Default Extension |
|-------------|------------------------------------|-------------------|
| `encode`    | `--format jp2`                     | `.jp2`            |
| `encode`    | `--format jpx`                     | `.jpx`            |
| `encode`    | `--htj2k` (no explicit `--format`) | `.jph`            |
| `encode`    | default (no `--format`, no `--htj2k`) | `.j2k`         |
| `decode`    | greyscale, 1 component             | `.pgm`            |
| `decode`    | colour, ≥ 3 components            | `.ppm`            |
| `decode`    | explicit `--output-format tiff`    | `.tiff`           |
| `decode`    | explicit `--output-format png`     | `.png`            |
| `transcode` | determined by target `--format`    | `.j2k` / `.jph` / `.jp2` |
| `convert`   | determined by `--output-format`    | matches format    |

#### Algorithm

```
1. If -o / --output is supplied → use it as-is (no change).
2. Otherwise:
   a. Take the input file path.
   b. Strip the existing extension.
   c. Append the default extension from the table above.
   d. Place the output in the same directory as the input.
```

#### Files to Modify

| File | Change |
|------|--------|
| `Commands.swift` | Replace the `guard let outputPath` blocks in `encodeCommand` and `decodeCommand` with fallback logic that derives the output path using the helper below. |
| `Transcode.swift` | Same change in `transcodeCommand`. |
| `Convert.swift` | Same change in `convertCommand`. |
| `MultiFileProcessor.swift` | Extract a shared `deriveOutputPath(input:format:componentCount:)` helper used by all commands and the existing `resolveOutputPath` batch helper. |
| `Batch.swift` | No change required — batch mode already uses `--output-suffix` and `resolveOutputPath`. |

#### Help Text Updates

Update the `--output` description in every help printer to indicate the flag is
optional, for example:

```
-o, --output PATH   Output file (optional; derived from input name if omitted)
```

---

## 2. Additional File Format Support

### 2.1 TIFF (Input and Output)

#### Scope

- Read **uncompressed** TIFF files (little-endian and big-endian byte order).
- Support 8-bit, 16-bit, and 32-bit samples — preserving the full bit depth
  through the encode/decode pipeline ("high bit rate").
- Write TIFF files with the same bit depth as the decoded image.
- Greyscale (1 component), RGB (3 components), and RGBA (4 components).

#### Design

Implement a minimal TIFF reader/writer inside the CLI (`ImageIO.swift` or a new
`TIFFSupport.swift` file). The implementation should:

1. Parse the 8-byte TIFF header (`II` / `MM` byte-order mark, magic `42`,
   offset to first IFD).
2. Walk the IFD entries to extract the tags required for raw pixel access:
   - `ImageWidth` (256), `ImageLength` (257)
   - `BitsPerSample` (258), `SamplesPerPixel` (277)
   - `PhotometricInterpretation` (262)
   - `StripOffsets` (273), `RowsPerStrip` (278), `StripByteCounts` (279)
   - `SampleFormat` (339) — to distinguish unsigned / signed / float
3. Read the pixel strips into a contiguous buffer, de-interleave into separate
   `J2KComponent` planes exactly as `loadPPM` does today.
4. For writing, emit a minimal single-strip TIFF with interleaved samples.

**No dependency on libtiff or any external library** — the parser handles only
the uncompressed baseline subset that medical and scientific imaging commonly
uses.

#### Files to Create / Modify

| File | Change |
|------|--------|
| `ImageIO.swift` | Add `.tiff` / `.tif` cases to `loadImage(from:)` and `saveImage(_:to:)` switch statements. |
| `TIFFSupport.swift` *(new)* | `loadTIFF(_ data: Data) throws -> J2KImage` and `saveTIFF(_ image: J2KImage, to url: URL) throws`. |
| `Convert.swift` | Add `tiff` / `tif` to the `printConvertHelp` supported-formats list. |
| `Commands.swift` | Add `tiff` to decode `--output-format` help text. |

---

### 2.2 PNG (Input and Output)

#### Scope

- Read PNG files: 8-bit greyscale, 8-bit RGB (24-bit), and 8-bit RGBA (32-bit).
- Write PNG files under the same bit-depth constraints.
- Higher bit depths (16-bit PNG) are outside scope for now because the
  requirement limits PNG to 8-bit (greyscale) and 24/32-bit (colour).

#### Design

Implement a minimal PNG reader/writer, or use the system-provided facilities:

- **macOS / iOS**: Use `CGImage` via `ImageIO.framework` (`CGImageSource` /
  `CGImageDestination`) behind `#if canImport(CoreGraphics)`.
- **Linux / cross-platform fallback**: Implement a minimal PNG decoder/encoder
  using the zlib `compress` / `uncompress` functions available through
  `import Foundation` (or `Glibc`). The subset required is small:
  1. Parse the PNG signature, IHDR, IDAT, and IEND chunks.
  2. Decompress the IDAT payload with zlib inflate.
  3. Reverse the per-row filter (Sub, Up, Average, Paeth).
  4. De-interleave into `J2KComponent` planes.
  5. For writing, apply Sub filter, compress with zlib deflate, emit chunks.

#### Bit-Depth / Component Validation

When **saving** to PNG, validate the image before writing:

| Components | Bit Depth | PNG Colour Type | Allowed |
|------------|-----------|-----------------|---------|
| 1          | 8         | Greyscale (0)   | ✅       |
| 3          | 8         | RGB (2)         | ✅       |
| 4          | 8         | RGBA (6)        | ✅       |
| Any other combination | — | —         | ❌ Error: "PNG output requires 8-bit greyscale (1 component), 24-bit RGB (3 components), or 32-bit RGBA (4 components)." |

When **loading** a PNG with bit depth > 8, either:
- Down-convert to 8-bit and warn, or
- Reject with a clear error message.

#### Files to Create / Modify

| File | Change |
|------|--------|
| `ImageIO.swift` | Add `.png` case to `loadImage(from:)` and `saveImage(_:to:)`. |
| `PNGSupport.swift` *(new)* | `loadPNG(_ data: Data) throws -> J2KImage` and `savePNG(_ image: J2KImage, to url: URL) throws`. |
| `Convert.swift` | Add `png` to the help text. |
| `Commands.swift` | Add `png` to decode `--output-format` help text. |

---

### 2.3 DICOM (Input Only)

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

Implement a minimal DICOM pixel-data extractor:

1. **Parse the DICOM preamble** — skip the 128-byte preamble and verify the
   `DICM` magic at offset 132.
2. **Determine the transfer syntax** by reading the File Meta Information group
   (`0002,0010` Transfer Syntax UID):
   - `1.2.840.10008.1.2` — Implicit VR Little Endian
   - `1.2.840.10008.1.2.1` — Explicit VR Little Endian
   - `1.2.840.10008.1.2.2` — Explicit VR Big Endian
   - Any JPEG 2000 transfer syntax → error: "Input is already JPEG 2000
     compressed; use `j2k decode` instead."
3. **Walk the dataset** to extract the tags needed for pixel interpretation:
   - `(0028,0010)` Rows
   - `(0028,0011)` Columns
   - `(0028,0100)` Bits Allocated
   - `(0028,0101)` Bits Stored
   - `(0028,0102)` High Bit
   - `(0028,0103)` Pixel Representation (0 = unsigned, 1 = signed)
   - `(0028,0002)` Samples Per Pixel
   - `(0028,0004)` Photometric Interpretation
   - `(0028,0006)` Planar Configuration (if samples > 1)
   - `(7FE0,0010)` Pixel Data
4. **Handle byte ordering** — if the transfer syntax is big-endian, byte-swap
   16-bit samples to the host order after extraction.
5. **De-interleave** multi-component data (if Planar Configuration = 0) into
   separate `J2KComponent` planes.
6. **Return** a `J2KImage` with the correct dimensions, bit depth, signedness,
   and colour space inferred from `PhotometricInterpretation`:
   - `MONOCHROME1` / `MONOCHROME2` → `.grayscale`
   - `RGB` → `.sRGB`
   - `YBR_FULL` / `YBR_FULL_422` → `.YCbCr` (or convert to RGB)

#### Unsupported / Out of Scope

- Encapsulated (compressed) pixel data — reject with a descriptive error.
- Multi-frame DICOM — extract only the first frame (or all frames as separate
  images if `--all-frames` is passed; optional stretch goal).
- Sequence items (SQ VR) — skip without error.
- DICOM-dir, network (DIMSE), or any non-file-based DICOM source.

#### Files to Create / Modify

| File | Change |
|------|--------|
| `ImageIO.swift` | Add `.dcm` / `.dicom` case to `loadImage(from:)` (input only). |
| `DICOMSupport.swift` *(new)* | `loadDICOM(_ data: Data) throws -> J2KImage` — the minimal parser described above. |
| `Commands.swift` | Add `dcm` / `dicom` to encode `--input` help text. |
| `Convert.swift` | Add `dcm` / `dicom` to the help text as an input format. |

---

## 3. Summary of New and Modified Files

| File | Status | Purpose |
|------|--------|---------|
| `Commands.swift` | Modify | Optional output path logic for encode/decode; help text updates. |
| `Transcode.swift` | Modify | Optional output path logic for transcode. |
| `Convert.swift` | Modify | Optional output path logic for convert; help text updates. |
| `MultiFileProcessor.swift` | Modify | Shared `deriveOutputPath` helper function. |
| `ImageIO.swift` | Modify | Route new extensions (`.tiff`, `.tif`, `.png`, `.dcm`, `.dicom`) to loaders/savers. |
| `TIFFSupport.swift` | **New** | Minimal uncompressed TIFF reader/writer. |
| `PNGSupport.swift` | **New** | Minimal 8-bit PNG reader/writer. |
| `DICOMSupport.swift` | **New** | Minimal DICOM pixel-data extractor (input only). |

No changes to `J2KCore`, `J2KCodec`, `J2KFileFormat`, or `Package.swift` are
required — all new code lives in the `J2KCLI` target.

---

## 4. Testing Strategy

| Area | Test Approach |
|------|---------------|
| Optional output names | Unit tests verifying `deriveOutputPath` produces correct extensions for each command and format combination. |
| TIFF round-trip | Encode a synthetic `J2KImage` to TIFF, reload, and compare pixel values. Test 8-bit, 16-bit, greyscale, and RGB. Test both little-endian and big-endian TIFF. |
| PNG round-trip | Encode/decode 8-bit greyscale, RGB, and RGBA. Verify rejection of unsupported bit depths. |
| DICOM input | Prepare minimal DICOM test files (little-endian explicit VR, big-endian explicit VR, implicit VR). Verify pixel data extraction matches expected values. Verify compressed DICOM is rejected with a clear message. |
| Regression | Run existing `swift test` suite to confirm no breakage. |

---

## 5. Implementation Order

1. **`deriveOutputPath` helper + optional output in all commands** — smallest
   change, unblocks other work.
2. **TIFF support** — straightforward binary format, no compression dependency.
3. **PNG support** — requires zlib; slightly more complex.
4. **DICOM support** — most complex parser; benefits from TIFF/PNG work
   stabilising `ImageIO.swift` first.
