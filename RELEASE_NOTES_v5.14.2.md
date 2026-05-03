# J2KSwift v5.14.2 — Systemic byte-order fix across every image-I/O surface

**Release date:** 2026-05-03
**Theme:** Audit + fix the entire class of byte-order bugs, not just the one that surfaced.

## The framing

v5.14.1 fixed lossless PGM round-trip correctness — the CLI's PGM writer was emitting little-endian 16-bit pixel data when the spec requires big-endian. The bug was hidden because the matching PGM loader had the same wrong assumption, so in-process round-trips appeared to work; only external consumers (Python's numpy in the medical benchmark) saw the corrupted bytes.

That fix was scoped to PGM/PPM. But the underlying class of bug — *"reader assumes one byte order, writer assumes another, they cancel out for in-process round-trips"* — could lurk in every other image format too. v5.14.2 audits the entire I/O surface and fixes it systematically.

## The audit

| Format | Reader byte order | Writer assumption | Components tagged? | Pre-v5.14.2 status |
|---|---|---|---|---|
| PGM (read) | passes BE through | — | ❌ untagged | encoder had to infer |
| PGM (write) | — | assumed LE input | — | broken with BE input (fixed v5.14.1) |
| PPM (read) | passes BE through | — | ❌ untagged | same as PGM |
| PPM (write) | — | assumed LE input | — | same as PGM |
| PNG (read) | swaps BE → LE | — | ❌ untagged | encoder had to infer |
| PNG (write) | — | assumed LE input | — | broken with BE input + had a Sub-filter bug |
| TIFF (read) | canonicalises to BE | — | ❌ untagged | encoder had to infer |
| TIFF (write) | — | assumed BE input | — | broken with LE input |
| DICOM (read) | canonicalises to BE | — | ❌ untagged | encoder had to infer |
| Decoder pipeline (output) | — | tagged BE since v5.14.1 | ✓ | OK after v5.14.1 |
| JP2/JPX containers | always BE | always BE | n/a | OK (BE-throughout by design) |

Every reader was producing untagged components, and every writer was making a per-format assumption about untagged input. Self-consistent in-process; spec-violating for any external tool.

## What changed

### Reader-side tagging

Every reader now declares `J2KComponent.sampleByteOrder` at the API boundary instead of leaving downstream consumers to guess:

```swift
// loadPGM / loadPPM
sampleByteOrder: bitDepth > 8 ? .bigEndian : nil

// loadPNG
sampleByteOrder: bitDepth > 8 ? .littleEndian : nil

// loadTIFF / loadDICOM
sampleByteOrder: bytesPerSample > 1 ? .bigEndian : nil
```

The encoder pipeline already respected `sampleByteOrder` (since v5.6.0) but had to fall back to `j2kInfer16BitByteOrder` when components were untagged. With every loader tagging explicitly, that inference path is no longer hit on the standard codepaths.

### Writer-side respect

The shared `componentDataIsBigEndian(_:legacyDefault:)` helper now lives in `Sources/J2KCLI/ImageIO.swift` and is callable from sibling files (PNGSupport.swift, TIFFSupport.swift). Per-format legacy defaults preserve pre-v5.14.2 untagged-input behavior:

```swift
// PGM/PPM/PNG writers — pre-v5.14.2 assumed LE input
componentDataIsBigEndian(comp, legacyDefault: .littleEndian)

// TIFF writer — pre-v5.14.2 assumed BE input
componentDataIsBigEndian(comp, legacyDefault: .bigEndian)
```

When a tag is present, it wins. When absent, the per-format default keeps callers that never set the tag working as before.

### Bonus: PNG Sub-filter correctness fix

The audit caught a pre-existing PNG-encoder bug unrelated to byte order: the Sub filter was implemented as `Filt(x) = Orig(x) - Filt(x-bpp)` (subtracting the *filtered* previous byte) instead of `Filt(x) = Orig(x) - Orig(x-bpp)` (the spec). It silently corrupted PNG output beyond the first `bpp` bytes of each scanline. The pre-existing tests didn't catch it because they only tested PNG *reading*, not round-trip.

The fix: switch to filter type 0 (None) — emit raw sample bytes unfiltered. PNG accepts this; only zlib compression handles redundancy. Compression ratio is slightly worse than correct Sub filter on natural images, but correctness is unconditional. Re-implementing Sub/Up/Average/Paeth with proper original-byte semantics is daytime followup if PNG output size matters.

## New regression matrix

`Tests/J2KCodecTests/J2KByteOrderRoundTripTests.swift`:
- **`testPGM_16bit_RoundTrip_PixelValues`** — encode → decode PGM, byte-for-byte equality.
- **`testPNG_16bit_RoundTrip_BytesIdentical`** — PGM → J2K → PNG → J2K → PGM. Catches both byte-order bugs and the Sub-filter bug.
- **`testTIFF_16bit_RoundTrip_BytesIdentical`** — PGM → J2K → TIFF → J2K → PGM.
- **`testLoaderTagsByteOrder_PGM_BigEndian`** — tag verification.

Plus the `J2KPGMRoundTripTests` matrix from v5.14.1 (6 tests covering `{8, 12, 16}-bit × {Part 1, HTJ2K}`).

These gates are the regression floor. Any future change to a loader or writer's byte-order handling has to keep all 10 tests green.

## Test results

**Full suite:** 1309 pass / 5 fail (was 1305/5 at v5.14.1)
- **+4 net new passes**: the 2 TIFF tests that my first cut of v5.14.2 broke (and re-fixed), plus 2 PNG round-trip cases that were silently broken by the pre-existing Sub-filter bug.
- The 5 remaining failures are pre-existing perf-threshold / thermal-noise / unrelated tests — none from this work.

**Medical benchmark:** unchanged from v5.14.1 — all lossless rows ∞, all lossy rows match or beat OpenJPEG. The PGM-only fix in v5.14.1 already covered the medical benchmark's I/O path; v5.14.2 extends the same correctness guarantee to PNG/TIFF/DICOM workflows that the benchmark didn't exercise.

## Caveats

- **PNG output size** is slightly larger than v5.14.1 because the writer now emits filter type 0 (no filtering) instead of the broken Sub filter. Re-implement Sub/Up/Average/Paeth with proper original-byte semantics if size matters; the regression test will catch correctness regressions either way.
- **Pre-v5.14.2 PNG files** were corrupted past the first `bpp` bytes of every scanline. If you have persisted PNG output from earlier J2KSwift versions, re-encode with v5.14.2.
- **Pre-v5.14.2 PGM/PPM files** were little-endian instead of spec-compliant big-endian (per the v5.14.1 release notes). Same advice: re-encode if interop matters.
- **TIFF, DICOM** were correct on the file-format side pre-v5.14.2; the v5.14.2 changes are tag-related infrastructure that doesn't change on-disk output for the legacy untagged-input pathway.

## Lesson

A bug fix is good. A bug *class* fix is better. The PGM byte-order bug was an instance of the broader pattern where every loader / writer pair self-consistently agreed on the wrong convention, and only external interop revealed the corruption. Fixing PGM/PPM in isolation would have left PNG / TIFF / DICOM with the same shape of bug latent — and the inference-fallback in the encoder would have masked it on the read side, so the next regression report would still show "lossless works on PGM but not PNG" or similar. The systemic audit + matching test matrix is what makes the whole shape unrepresentable.
