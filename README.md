# J2KSwift

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<!-- CI / Code Quality / Documentation badges removed 2026-05-27 along
     with the underlying GitHub Actions workflows (cost-reduction).
     Build + test verification now runs locally via
     `swift test -c release --filter "J2KMedicalCorpus*PerformanceTests|J2KStrictCrossCodecValidationTests"`
     (the mandatory commit gate per feedback_commit_gate.md). The only
     remaining cloud workflows are `release.yml` (auto-creates the
     GitHub Release on tag push) + `create-release-branches.yml`
     (manual-dispatch only). -->


A pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

**Current Version**: 11.0.2
**Status**: Apple Silicon-first JPEG 2000 / HTJ2K (Part-15) implementation. v11.0.2 is a decoder-only DBT performance patch: truncated quality-layer prefixes stop at their exact coding-pass boundary, reusable scratch clears are limited to the logical code-block region, and disabled EBCOT tracing is compiled out. Decoded pixels remain bit-exact with no public API or codestream-format change. See [RELEASE_NOTES_v11.0.2.md](RELEASE_NOTES_v11.0.2.md).
**Previous Release**: 11.0.1 (EBCOT decoder state optimization)
**Release process**: see [RELEASING.md](RELEASING.md). Every release MUST update this README (Current Version line + new Release Status paragraph) — see the Release artefacts checklist for the full requirements.

## 📦 Release Status

**v11.0.2** fixes the DBT bit-plane decoder hot path. Quality-layer prefixes now stop as soon as their requested coding passes are consumed, scratch-state clearing touches only the logical code-block extent, and EBCOT diagnostics impose no cost unless explicitly compiled in. Focused decoder regressions and bounded real-frame DBT verification are bit-exact. See [RELEASE_NOTES_v11.0.2.md](RELEASE_NOTES_v11.0.2.md).

**v11.0.1** is a decoder-only correctness/performance patch. EBCOT decoder scratch now uses the sign bit already carried by `CoefficientState`, avoiding redundant allocation, zeroing, and writes; empty zero-pass blocks return zero coefficients immediately. Real TCIA DBT validation covered all 100 1996×2457 lossless JPEG 2000 frames with bit-identical output. See [RELEASE_NOTES_v11.0.1.md](RELEASE_NOTES_v11.0.1.md).

**v11.0.0** is the **dead-weight + packaging MAJOR** — ~125K deleted lines with **zero codec behaviour change** (codestream bytes and decoded pixels identical to v10.25.0). Removes the production-dead exported products `J2KAccelerate`/`J2KVulkan`/`J2KXS`, the MJ2 container stack, dead pool/concurrency/benchmark/conformance scaffolding (~15K lines out of J2KCore alone — DICOMKit-consumed HT conformance types survive unchanged in `J2KHTConformanceAPI.swift`), orphan source dirs, and ~23 MB of tracked artifacts. Every candidate was verified reference-free by a 25-agent sweep with adversarial re-checks. **Packaging headline: the manifest is unsafeFlags-free, making J2KSwift consumable as a versioned SwiftPM dependency for the first time** (verified end-to-end; the NEON `-O3` removal was A/B-measured as a wash first). Clean debug build −24.6% (52.8→39.8 s); `Sources/` −19%. Deferred: the `.custom` HT format (three live consumer chains). Gate + touched suites 271/271, exit 0. MAJOR per RELEASING.md (products removed). See [RELEASE_NOTES_v11.0.0.md](RELEASE_NOTES_v11.0.0.md).

**v10.25.0** is the **optimization-audit release** — the implementation arc of a full-project, 8-dimension multi-agent audit (60 adversarially-verified findings; `OPTIMIZATION_AUDIT_2026-06-10.md`). Decoder: the multi-level fused GPU iDWT chaining had been **dead-gated since v10.3.0** (coupled to the GPU-HT-*entropy* flag that release turned off), so default DX/MG GPU decodes paid a CPU readback+re-upload of the LL at every decomposition level; the chain is restored, per-tile iDWTs run on fresh command queues, and the buffer pool buckets linearly above 16 MB. **MG decode −8 to −10 ms: J2KSwift now beats both Kakadu and Grok on MG small + mid decode** (large-medical decode geomean gap 1.27×→**1.16×**). Product layer: CLI `--level`/`--region` finally wired to the v10.4–v10.7 partial-decode APIs (DX thumbnail **10 ms vs 57 ms** full), which surfaced and fixed a latent **multi-tile `decodeResolution` corruption** shipping since v10.5.0; stdin/stdout piping (`-i -`/`-o -`) fixed; daemon multi-component silent data-drop fixed; `swift test` exit code fixed via a `J2KCLICore` library split; JP3D per-voxel `Data` subscript hot loops bulk-converted; daemon + encoder + decoder tile tasks at `.high` QoS (completing the v10.24.2 arc). One audit recommendation was **empirically rejected**: excluding MG 2x2 from per-tile GPU forward DWT regressed encode +20–35 ms — the in-code table that justified it predates fresh per-call queues (the v10.7.0 stale-routing lesson, in reverse). Codestream bytes byte-identical to v10.24.2; gate 7/7 + parity matrix 12/12 bit-exact across OpenJPH/Grok/Kakadu. MINOR. See [RELEASE_NOTES_v10.25.0.md](RELEASE_NOTES_v10.25.0.md).

**v10.24.2** is a **decoder-only patch** improving parallel decode throughput. The parallel tier-1 (code-block) entropy **decode** previously split blocks into exactly `coreCount` **contiguous** chunks (`chunkSize = blockCount / coreCount`) with no load-balancing, no oversubscription, and no QoS. Code-block decode cost is highly skewed (dense LL/low-frequency vs near-empty HH) and blocks arrive in resolution/packet order, so expensive blocks clustered into a few chunks — the slowest chunk gated the stage while other cores idled (**~2.9 of 8 cores effective on M2**, measured) and default-priority tasks spilled onto the slower E-cores. **Fix**: distribute blocks across `2 × coreCount` buckets via **LPT** (sort by descending encoded byte length, greedily assign to the least-loaded bucket) and run the decode tasks at **`.high` priority** (P-core bias) — the decode-side analogue of the encoder's `Tier1ChunkPlan`. Output is keyed by block index, so the redistribution is **bit-exact**. **Results (M2, warm)**: SDK/library decode DX 63.9→**48.1 ms (−25%)**, CT 6.2→**2.3 ms**, effective cores 2.9→**4.4**; canonical large-medical decode −3%, multi-tile MG −5–8% (MG-mid now matches/edges Kakadu+Grok). Codestream byte-identical to v10.24.1; OpenJPH/Grok/Kakadu cross-decode of our HTJ2K output unchanged (15/15). Mandatory commit gate **7/7 PASS** release mode; bit-exact round-trip re-verified on DX/PX/MG. This is the shippable win from a "be #1 vs Kakadu" investigation; the encode-entropy rebalance (−0.3%) and the row-band CPU inverse-DWT probe (iDWT moves the wall <1 ms — not the decode bottleneck) were measured as M2 washes and **not** shipped (14th confirmation of the M2 + Swift hot-path lever ceiling). PATCH — decoder-only, no API change. See [RELEASE_NOTES_v10.24.2.md](RELEASE_NOTES_v10.24.2.md).

**v10.24.1** is a **patch** fixing an HTJ2K **lossless** encoder data-loss bug surfaced by testing against the **Cloudinary Image Dataset '22 (CID22)** — a non-DICOM, natural, full-colour corpus. `j2k encode --htj2k --lossless` was not always lossless: on 4 of 49 CID22 reference images the HTJ2K codestream decoded with up to 38,946 wrong pixels (max err 238), while the default Part-1 path was always bit-exact. **Root cause**: the conformant HT encoder converts coefficients to OpenJPH sign-magnitude as `sign | (|v| << (31 - K_max))`, where `K_max` was derived from the single-level subband gain `{LL:0, HL/LH:1, HH:2}`; a multi-level reversible 5/3 transform expands the coefficient range (deep LL band especially), so high-contrast 8-bit content (hard 0↔255 edges) produced coefficients ≥ `2^K_max` whose top bit overflowed bit 31 (the sign bit) and was silently dropped. Confirmed **encoder-side** (OpenJPH reproduces the loss from our codestream; our decoder reconstructs OpenJPH's reversible streams bit-exactly). The 12/16-bit medical corpus never triggered it because that content never approaches full scale. **Fix**: a centralized `htConformantReversibleGain(subband:rctActive:)` sizes the window to OpenJPH's proven-sufficient reversible `K_max` (LL=B+1, detail=B+2, +1 when the reversible colour transform is active), taking `max` with the previous gain so windows only grow; the same gain drives the QCD ε signalling and the per-block shift, scoped to the HT-conformant path so legacy EBCOT / custom-HT codestreams are byte-identical to v10.24.0. Decoder needs no change (derives `K_max` from the QCD ε). **Validation**: CID22 **49/49 bit-exact** in both Part-1 and HTJ2K (was 45/49 HTJ2K); HT-conformant medical sample bit-exact + OpenJPH cross-decode; **cross-codec parity 15/15** (CT/MR/DX/MG/PX × OpenJPH/Grok/Kakadu, all ✓); new regression suite `V10_25_HTConformantReversibleWindowTests` **3/3 PASS** (exact 8×8 reproducer + synthetic high-contrast RGB & greyscale across 1–5 levels); mandatory commit gate **7/7 PASS** release mode. PATCH — default config byte-identical; only opt-in HTJ2K reversible codestream bytes change (the fix). Also bundles the non-DICOM `Scripts/image_corpus_roundtrip.py` test harness. See [RELEASE_NOTES_v10.24.1.md](RELEASE_NOTES_v10.24.1.md).

**v10.24.0** ships **`J2KDICOMHelpers` Phase 3.1 — uncompressed pixel extraction**. Closes the Phase 3.1 candidate explicitly called out in v10.21.0's "Known limitations": v10.21's `J2KDICOMFileParser.parse(_:)` returned pixel data only for J2K-tagged transfer syntaxes (`.j2kCompressed(metadata, pixelDataBytes)`) and metadata-only for the rest (`.uncompressed(metadata)`). On further consideration this asymmetry was awkward — consumers parsing a `.dcm` file got pixel bytes for J2K-tagged files but not for uncompressed ones, so they ended up shipping two parsers (J2KSwift's + their DICOM library's) just to read both kinds uniformly. v10.24.0 ships a SIBLING method `J2KDICOMFileParser.parseExtractingPixelData(_:)` that returns the richer `J2KDICOMFileWithPixelData` type — both cases now carry `pixelDataBytes`. For uncompressed inputs the bytes are sliced from the `(7FE0,0010)` element in SOURCE BYTE ORDER (no endianness conversion to caller's native, no mosaic / planar-config interpretation — caller's DICOM library / image-construction handles those concerns). Explicit truncation detection throws `J2KDICOMFileError.truncatedFile(expectedAtLeast:got:)` when the file's declared Pixel Data length is positive but less than the metadata-derived expected size (`rows × columns × samplesPerPixel × bytesPerSample × numberOfFrames`) — mirrors the CLI's `loadDICOM` truncation check at `J2KCLI/DICOMSupport.swift:187`. The SIBLING-type design (`J2KDICOMFileWithPixelData` alongside `J2KDICOMFile` + `parseExtractingPixelData` alongside `parse`) is intentional non-breakingness — adding a `.uncompressedWithPixelData` case to the existing `J2KDICOMFile` enum would warn on every exhaustive switch in consumer code without an unreachable default. Existing `parse(_:)` + `J2KDICOMFile` API contracts PRESERVED. **Validation**: `V10_36_ParseExtractingPixelDataTests` **5/5 PASS** release mode (J2K-tagged path returns same bytes as `parse(_:)`; uncompressed single-frame returns byte-identical source slice; uncompressed multi-frame returns N × frameSize bytes; truncated source throws `.truncatedFile`; convenience accessors work for both variants). Full `swift test --filter J2KDICOMHelpers` regression **56/56 PASS** (51 pre-existing — 26 V10_29 Phase 1 + 12 V10_31 Phase 2 + 13 V10_33 Phase 3 — + 5 new V10_36 Phase 3.1); `swift test --filter JP3D` regression **539/539 PASS**; mandatory commit gate 7/7 PASS. Fifth release under the post-`bill-reduction` regime: only `release.yml` fires on the tag push (Linux, ~30s, 2 jobs, ~$0.01). Also bumps `getVersion()` 10.23.0 → 10.24.0. Codestream bytes byte-identical to v10.23.0. See [RELEASE_NOTES_v10.24.0.md](RELEASE_NOTES_v10.24.0.md).

**v10.23.0** ships **encoder format-flexibility** — write-side symmetry with v10.22.0's decoder ship. Before v10.23.0 the encode-then-write story was forked: consumers wanting rich `J2KEncoder` configuration (HTJ2K, multi-tile, custom decomposition levels, etc.) had to encode + hand-roll JP2 box bytes themselves, OR write via `J2KFileWriter.write` which re-encodes through the simpler `J2KConfiguration` (quality + lossless only) — discarding the rich encoding choices. v10.23.0 closes this gap. New public APIs: **`J2KEncoder.encodeToFormat(_:format:)`** (extension in `J2KFileFormat` module) — encodes via `self.encode(image)` (preserving the encoder's full `J2KEncodingConfiguration`) and wraps via `J2KFileWriter.wrap(codestream:headerForImage:)` (also new); returns the file bytes for any target format (`.j2k`/`.jp2`/`.jph`/`.jpx`/`.jpm`). **`J2KEncoder.encodeFile(_:to:format:)`** — thin `encodeToFormat` + `Data.write(to:options:.atomic)` wrapper for file-on-disk consumers. **`J2KFileWriter.wrap(codestream:headerForImage:)`** — wraps a pre-encoded J2K codestream into the writer's configured box format WITHOUT re-encoding; useful when consumers want to encode once and target multiple wrappers (DICOM Pixel Data via v10.19's encapsulator + JP2 file + JPX file from a single codestream). The wrap method delegates to the existing `buildJP2File` / `buildJPHFile` / `buildJPXFile` / `buildJPMFile` private helpers (now reachable via the public `wrap` entry point) — same box layouts that `J2KFileWriter.write` has been producing since v8. Extensions live in `J2KFileFormat` (not `J2KCodec`) for the same reason as v10.22's decoder extensions — J2KFileFormat already depends on J2KCodec; the reverse would create a cycle. Consumers add `J2KFileFormat` to their target's product list to gain the methods. Existing `J2KFileWriter.write(_:to:configuration:)` semantics PRESERVED — still re-encodes via `J2KConfiguration`; the new `wrap` + `J2KEncoder` extensions are the opt-in additive paths for richer control. **Validation**: `V10_35_EncoderFileFormatTests` **11/11 PASS** release mode (wrap for `.j2k` returns codestream unchanged; for `.jp2`/`.jph` prepends correct signature box; rejects invalid zero-dim image; wrap → `extractCodestream` round-trip; `encodeToFormat(.j2k)` matches `encode(_:)`; `.jp2` + `.jph` `encodeToFormat` round-trips bit-exact through v10.22's `decodeAnyFormat`; `encodeFile` writes to temp disk + `decodeFile` reads back bit-exact; default format is `.jp2`; unwritable path throws I/O error). Full `swift test --filter J2KFileFormatTests` regression **376/376 PASS** (365 pre-existing + 11 new V10_35 + 10 pre-existing skips); `swift test --filter JP3D` regression **539/539 PASS**; mandatory commit gate 7/7 PASS. Fourth release under the post-`bill-reduction` regime: only `release.yml` fires on the tag push (Linux, ~30s, 2 jobs, ~$0.01). Also bumps `getVersion()` 10.22.0 → 10.23.0. Codestream bytes byte-identical to v10.22.0. See [RELEASE_NOTES_v10.23.0.md](RELEASE_NOTES_v10.23.0.md).

**v10.22.0** ships **decoder format-flexibility** — closes the long-standing "I have a `.jp2` file, how do I decode it?" friction. Before v10.22.0, `J2KDecoder.decode(_:Data)` accepted only raw J2K codestream bytes; consumers loading `.jp2` / `.jph` / `.jpx` files (the typical on-disk format, where the codestream lives inside a `jp2c` Contiguous Codestream box surrounded by signature + filetype + JP2 header boxes per ISO/IEC 15444-1 §I.4) had to roll their own box walker or use `J2KFileReader.read(from:)` (which only returns header-parsed metadata, not actual pixel data). v10.22.0 closes both gaps with three additive APIs: **`J2KDecoder.decodeAnyFormat(_:Data)`** — auto-detects format via `J2KFormatDetector` and decodes (for `.j2k` raw codestream, passes through to existing `decode(_:)`; for `.jp2`/`.jpx`/`.jpm`/`.jph` box formats, extracts the `jp2c` codestream first via `J2KFileReader.extractCodestream(from:)` then decodes); **`J2KDecoder.decodeFile(at:URL)`** — thin `Data(contentsOf:)` + `decodeAnyFormat` wrapper for file-on-disk consumers; **`J2KFileReader.extractCodestream(from:Data)`** — formerly `private`, now `public` so consumers can extract raw codestream bytes from JP2-wrapped data for downstream use (DICOM re-wrap via v10.19's `J2KDICOMPixelDataEncapsulator`, JPIP transport, `decodeRegion(_:options:)` partial decode, etc.). The new methods live as extensions in the `J2KFileFormat` module rather than `J2KCodec` to avoid creating a J2KCodec→J2KFileFormat dependency cycle (J2KFileFormat already depends on J2KCodec); consumers add `J2KFileFormat` to their target's product list to gain the methods. Existing `J2KDecoder.decode(_:Data)` semantics PRESERVED — it still throws on JP2-boxed bytes (strict raw-codestream-only); the new `decodeAnyFormat(_:)` is the opt-in flexible path. **Validation**: `V10_34_DecoderFormatFlexibilityTests` **8/8 PASS** release mode — `extractCodestream` correctly extracts from synthetic JP2 + JPH (both yield bytes starting with SOC `0xFF 0x4F`), rejects raw codestream (no `jp2c` box); `decodeAnyFormat` accepts raw + JP2 + JPH bytes with bit-exact lossless HTJ2K round-trip; `decodeFile` reads from a temp-file URL; missing-file throws I/O error. Synthetic JP2/JPH fixtures generated at test time via `J2KFileWriter.write(image, to:url, configuration: J2KConfiguration.lossless)` — no new binary fixtures committed. Full `swift test --filter J2KFileFormatTests` regression **365/365 PASS** (357 pre-existing + 8 new V10_34 + 10 pre-existing skips); `swift test --filter JP3D` regression **539/539 PASS**; mandatory commit gate 7/7 PASS. Third release under the post-`bill-reduction` regime (after v10.20.0 + v10.21.0): only `release.yml` fires on the tag push (Linux, ~30s, 2 jobs, ~$0.01). Also bumps `getVersion()` 10.21.0 → 10.22.0. Codestream bytes byte-identical to v10.21.0. See [RELEASE_NOTES_v10.22.0.md](RELEASE_NOTES_v10.22.0.md).

**v10.21.0** ships **`J2KDICOMHelpers` Phase 3 — DICOM file parser** — completes the DICOM read-side story for library consumers. Before v10.21.0, consumers parsing `.dcm` files had to use their own DICOM library (pydicom, DICOMKit, dcm4che) to extract J2K codestream bytes out of the DICOM container before feeding them to `J2KDecoder` — even though J2KSwift's CLI has had file-parsing logic since v8 (CLI-private). v10.21.0 lifts the J2K-relevant subset of that parser into the `J2KDICOMHelpers` library product. New public API: **`J2KDICOMFileParser.parse(_:)`** — given complete `.dcm` file bytes, returns a `J2KDICOMFile` enum that branches on Transfer Syntax UID; **`J2KDICOMFile.j2kCompressed(metadata, pixelDataBytes)`** — Transfer Syntax UID is one of the seven JPEG 2000 / HTJ2K variants (`1.2.840.10008.1.2.4.90/91/92/93/201/202/203`); `pixelDataBytes` is the complete Pixel Data Item sequence (BOT + per-frame Items + Sequence Delimitation Item per PS3.5 §A.4) ready to feed to v10.19's `J2KDICOMPixelDataDecapsulator.extractFrames(_:)`; **`J2KDICOMFile.uncompressed(metadata)`** — non-J2K transfer syntax (uncompressed or non-J2K compressed); only metadata returned, consumers use their own DICOM library for pixel data; **`J2KDICOMFileMetadata`** — Image Pixel Module value type (rows, columns, bitsAllocated, bitsStored, pixelRepresentation, samplesPerPixel, photometricInterpretation, numberOfFrames, planarConfiguration) + derived properties (effectiveBitsStored, bytesPerSample, frameSizeInBytes); **`J2KDICOMFileError`** — `Sendable, Equatable` typed errors (`.invalidPreamble`, `.missingDICMMagic`, `.missingPixelDataTag`, `.truncatedFile`, `.invalidTransferSyntax`, `.sequenceParsingFailed`). The parser handles all three transfer-syntax-determined endianness variants (Explicit VR Little Endian, Implicit VR Little Endian, Explicit VR Big Endian retired UID `1.2.840.10008.1.2.2`), correctly skips undefined-length sequences per PS3.5 §7.5, and reuses the v10.17.0 `J2KDICOMTransferSyntax` enum for UID classification. ADR-004 compliant: **no DICOM library dependency added anywhere** — pure byte-level parsing per DICOM PS3.5 §7 (File Meta Information) + §6 (Data Element Structure) + PS3.3 §C.7.6.3.1 (Image Pixel Module). Phase 3 scope deliberately excludes uncompressed pixel-data extraction (Phase 3.1 / v10.22 candidate), compressed-non-J2K transfer syntaxes (stays CLI-only via Python subprocess), DICOM file writing, and tag-dictionary / IOD validation. **Validation**: `V10_33_*` test suites **13/13 PASS** release mode (5 preamble + 3 uncompressed-fixture + 5 J2K-synthesis: end-to-end round-trip from `J2KEncoder` → `J2KDICOMPixelDataEncapsulator` → hand-built DICOM header → parser → decapsulator → byte-identical codestream recovery for HTJ2K Lossless single-frame, HTJ2K Lossless multi-frame with BOT, J2K Lossless, non-J2K UID classification, missing-Pixel-Data error path). Full `swift test --filter J2KDICOMHelpers` regression **51/51 PASS** (26 V10_29 Phase 1 + 12 V10_31 Phase 2 + 13 V10_33 Phase 3); `swift test --filter JP3D` regression **539/539 PASS**; mandatory commit gate 7/7 PASS. Second release under the post-`bill-reduction` regime (after v10.20.0): only `release.yml` fires on the tag push (Linux, ~30s, 2 jobs, ~$0.01). Also bumps `getVersion()` 10.20.0 → 10.21.0. Codestream bytes byte-identical to v10.20.0. See [RELEASE_NOTES_v10.21.0.md](RELEASE_NOTES_v10.21.0.md).

**v10.20.0** ships **JP3D `preWarm()` symmetric completion** — six new public `static func preWarm(includeWarmupDispatch: Bool = false) async` extensions on the JP3D actor types that v10.15.0's `preWarm` discoverability ship missed: `JP3DEncoder`, `JP3DMultiSpectralDecoder`, `JP3DMultiSpectralEncoder`, `JP3DProgressiveDecoder`, `JP3DStreamWriter`, `JP3DTranscoder`. Each wrapper is a 2-line static function that delegates to `J2KDecoder.preWarm(includeWarmupDispatch:)` — the canonical entry point that warms the process-wide `J2KMetalSession.processShared`. Per JP3D type sharing the session via per-slice 2D delegation, warming once via any one of the eight wrappers (the six new + the two existing on `JP3DDecoder`/`JP3DROIDecoder`) covers every subsequent JP3D operation in the process. Per the V10_27 cold-start probe shipped alongside v10.16.0, the encoder-side leftover cost beyond what `JP3DDecoder.preWarm(includeWarmupDispatch: true)` already amortises is +0.10/-1.25 ms on 128/256-cube fixtures — below the 3 ms gate — so v10.20.0 is honest discoverability + symmetric API completion, not a new perf claim on warm paths. Consumers using e.g. `JP3DMultiSpectralEncoder` alone no longer have to know to `import J2KCodec` separately or to find the `JP3DDecoder.preWarm` entry point from a sibling actor. **Validation**: `V10_32_PreWarmSymmetricCompletionTests` **7/7 PASS** release mode (6 per-type surface-availability tests + 1 cross-type shared-session verification covering a real encode-then-decode after `JP3DEncoder.preWarm(includeWarmupDispatch: true)`); full `swift test --filter JP3D` regression sweep **539/539 PASS** (532 pre-existing + 7 new V10_32 + 1 pre-existing skip); mandatory commit gate 7/7 PASS. First release after the 2026-05-27 cloud-cost reduction (`bill-reduction` merge): only `release.yml` (Linux, ~30s) fires on the tag push; previous per-release ~14 macOS jobs eliminated. Also bumps `getVersion()` 10.19.0 → 10.20.0. Codestream bytes byte-identical to v10.19.0. See [RELEASE_NOTES_v10.20.0.md](RELEASE_NOTES_v10.20.0.md).

**v10.19.0** ships **`J2KDICOMHelpers` Phase 2 — DICOM Pixel Data encapsulation helpers**. Builds directly on v10.17.0's Phase 1 product (UID-and-config bridge) with the wire-format layer that lets consumers turn J2K codestreams into DICOM Pixel Data bytes and back. New public API on the `J2KDICOMHelpers` library: **`J2KDICOMPixelDataEncapsulator.encapsulateItem(_:)`** wraps one J2K codestream into a single DICOM Pixel Data Item (8-byte header `FFFE,E000` + LE u32 length + payload + optional 0x00 pad to maintain even Item length per PS3.5 §6.4); **`J2KDICOMPixelDataEncapsulator.encapsulateFrames(_:includeBOT:)`** wraps multiple frames into a complete Item sequence with optional Basic Offset Table prefix + Sequence Delimitation Item suffix (BOT entries are little-endian u32 offsets measured from the start of the first frame Item, per current DICOM Standard); **`J2KDICOMPixelDataDecapsulator.extractFrames(_:)`** parses an encapsulated sequence back into per-frame J2K codestreams, stripping trailing 0x00 pad bytes when detected via the EOC-then-pad pattern (`0xFF 0xD9 0x00`); **`J2KDICOMPixelDataError`** `Sendable, Equatable` error type with cases for `truncated`, `itemTagExpected`, `itemLengthOverrun`, `malformedSequenceDelimitation`. Write-side use case: encode an image via `J2KSwift`, wrap as Pixel Data, hand off to your DICOM writer for insertion at `(7FE0,0010)` with VR `OB` and undefined length. Read-side: extract codestreams from your DICOM library's Pixel Data bytes, decode via `J2KDecoder`. Phase 2 scope is **narrower than the original v10.17 plan** (which contemplated full DICOM file parsing extraction); refined to the wire-format layer specifically because (a) consumers should use their own DICOM library for file parsing (pydicom, DICOMKit, dcm4che), (b) the J2K-specific wire format wasn't previously available — consumers had to hand-roll the byte layout (the pattern was test-scaffolding in `J2KStrictCrossCodecValidationTests.swift:170-194`). ADR-004 compliant: no DICOM library dependency added anywhere; rules codified directly from PS3.5 §A.4 / §6.4. **Validation**: `V10_31_PixelDataEncapsulationTests` **12/12 PASS** release mode (encapsulateItem even+odd length + padding correctness; encapsulateFrames single+multi frame with empty and populated BOT; round-trip byte-exact single + multi frame; pad stripping via EOC-then-pad detection; truncated/invalid input rejection; error type Equatable); full `swift test --filter J2KDICOMHelpers` regression **38/38 PASS** (26 V10_29 Phase 1 + 12 V10_31 Phase 2); `swift test --filter JP3D` regression **532/532 PASS**; mandatory commit gate 7/7 PASS. Also bumps `getVersion()` 10.18.0 → 10.19.0. Codestream bytes byte-identical to v10.18.0. See [RELEASE_NOTES_v10.19.0.md](RELEASE_NOTES_v10.19.0.md).

**v10.18.0** ships **JP3D AsyncSequence progress reporting** — `progressStream()` extensions on `JP3DDecoder`, `JP3DROIDecoder`, `JP3DEncoder`, and `JP3DStreamWriter`. Modern Swift concurrency progress API alongside the existing `setProgressCallback(_:)` closure surface (both remain supported indefinitely). Consumers using structured concurrency previously had to hand-roll a `setProgressCallback` → `AsyncStream.makeStream` adapter themselves; v10.18.0 ships that adapter inside the JP3D module so it composes cleanly with the existing async-await encode/decode methods. The `progressStream()` method is `async` so the relay closure is installed on the actor BEFORE the stream is returned — no race window where early progress events get missed. Lifecycle behaviour is explicitly codified: calling `progressStream()` twice overwrites the first stream's writer (the first stream's continuation receives no further events but isn't explicitly finished); the stream doesn't auto-finish at operation completion (consumers `break` based on observed progress or rely on `Task` cancellation); `setProgressCallback(_:)` after `progressStream()` overwrites the relay (use one or the other, not both). **Validation**: `V10_30_ProgressStreamParityTests` **4/4 PASS** release mode — JP3DDecoder + JP3DEncoder both deliver progress events during real operations; JP3DROIDecoder stream surface is available + safe to consume (its decoder body doesn't currently fire `progressCallback` events — pre-existing upstream gap, documented in the test header); `setProgressCallback` overwrites of `progressStream`'s relay still fire correctly. Full `swift test --filter JP3D` regression sweep **532/532 PASS** (528 pre-existing + 4 new V10_30 + 1 pre-existing skip); mandatory commit gate 7/7 PASS. Closes the deferred Phase 3 from v10.17.0's plan with focused MINOR scope. Also bumps `getVersion()` 10.17.0 → 10.18.0. Codestream bytes byte-identical to v10.17.0. See [RELEASE_NOTES_v10.18.0.md](RELEASE_NOTES_v10.18.0.md).

**v10.17.0** ships **`J2KDICOMHelpers` (Phase 1)** — a new public SwiftPM library closing a long-standing product-layer gap. Per [ADR-004](Documentation/ADR/ADR-004-no-dicom-dependency.md), J2KSwift core libraries don't depend on any DICOM library. The CLI ships a `DICOMSupport.swift` for `.dcm` file loading (uses a Python fallback for compressed transfer syntaxes), but the `DICOMTransferSyntax` / `DICOMTransferSyntaxInfo` types there are CLI-private — not surfaced to library consumers. Library consumers using their own DICOM parser (DICOMKit, pydicom-via-XPC, etc.) extract `(Transfer Syntax UID, Pixel Data bytes)` and previously had to hand-roll the UID-to-`J2KEncodingConfiguration` mapping. v10.17.0 lifts the UID-bridge layer into a new public `J2KDICOMHelpers` SwiftPM library: **`J2KDICOMTransferSyntax`** enum (`CaseIterable` over all seven DICOM Part 5 Annex A JPEG 2000 / HTJ2K UIDs — `j2kLossless`, `j2kLossy`, `j2kPart2MulticompLossless`, `j2kPart2Multicomp`, `htj2kLossless`, `htj2kLossyConstant`, `htj2kLossy`) with `init?(uid:)` / `var uid` round-trip (whitespace + trailing-NUL tolerant per PS3.5 §6.2), `isLossless` / `isHTJ2K` / `isPart2` classification flags, and `encodingConfiguration(bitDepth:psnrTarget:)` returning a matching `J2KEncodingConfiguration` (with `htj2kBlockFormat: .conformant` for DICOM interop); **`J2KDICOMCodestreamDetector.detect(_:)`** sniffs SOC + (optional) CAP markers in the first ~256 bytes to classify raw codestreams as `.j2kLossless` (Part 1, no CAP) or `.htj2kLossless` (Part 15, CAP present), returning nil for non-J2K bytes (JPEG SOI, PNG signature, random bytes all correctly reject); and **`J2KDICOMPhotometricInterpretation`** enum mirror (`MONOCHROME1/2`, `RGB`, `YBR_FULL/422`, `YBR_RCT/ICT`) with bidirectional `J2KColorSpace` mapping (greyscale ↔ MONOCHROME2, sRGB ↔ RGB, yCbCr ↔ YBR_FULL; `hdr`/`hdrLinear`/`iccProfile`/`unknown` return nil reverse). ADR-004 compliant: **no DICOM library dependency anywhere in J2KSwift** — the new product depends only on J2KCore + J2KCodec; consumers not importing `J2KDICOMHelpers` are completely unaffected. **Validation**: `V10_29_*` test suites **26/26 PASS** release mode (9 TransferSyntaxRoundTrip + 5 EncodingConfigurationParity + 6 CodestreamDetection + 6 PhotometricInterpretation); end-to-end bit-exact lossless round-trip confirmed for `.j2kLossless` + `.htj2kLossless` via the helpers-built configurations. Full `swift test --filter JP3D` regression sweep **528/528 PASS**; mandatory commit gate 7/7 PASS. Also bumps `getVersion()` 10.16.0 → 10.17.0. Phase 1 deliberately ships the smallest viable shape — UID-and-config bridge only, no DICOM file parsing (Phase 2 territory: extract more of `J2KCLI/DICOMSupport.swift` or ship a DICOMKit adapter as a sibling opt-in product). AsyncSequence progress streams (originally Phase 3) deferred to a dedicated MINOR. See [RELEASE_NOTES_v10.17.0.md](RELEASE_NOTES_v10.17.0.md).

**v10.16.0** adds three **convenience overloads on `JP3DDecoder`** that surface the JP3D partial-decode capabilities behind the canonical type. The underlying pipelines have been production-default since v10.10.0 (true partial-resolution from v10.18-research, K+ROI composition from v10.13.0), but the only way to reach them from `import J2K3D` was to either construct `JP3DDecoderConfiguration(resolutionLevel: K)` (discoverable only by reading docs) or switch to `JP3DROIDecoder` (a separate actor type). v10.16.0 closes the gap with `decode(_:resolutionLevel:)`, `decode(_:region:)`, and `decode(_:region:resolutionLevel:)` overloads — all thin wrappers that construct a transient inner decoder/ROI-decoder with the requested options and delegate. The actor's `configuration` (`tolerateErrors`, `maxQualityLayers`) propagates to the transient inner instances; negative levels are clamped to 0; level 0 is bit-exact equivalent to `decode(_:)`. **Speedups surfaced (existing pipelines, v10.18-research bench)**: level-1 thumbnail decode **2.2-3.1× faster** than full decode on small-mid JP3D fixtures (mr_3d_small 2.22×, ct_3d_small 3.05×, mr_3d_mid 3.01×); ROI ~1/4-extent decode **3.4-4.1× faster** (mr_3d_small 3.37×, ct_3d_small 4.14×, mr_3d_mid 3.96×); K+ROI composition stacks both savings. Decoder-only, codestream bytes byte-identical to v10.15.0, encoder unchanged. **Validation**: `V10_28_JP3DDecoderPartialOverloadsParityTests` **6/6 PASS** (all three overloads byte-identical to existing JP3DDecoderConfiguration + JP3DROIDecoder usage; no-op level (0) bit-exact to `decode(_:)`; negative level clamped; outer-configuration propagation verified); full `swift test --filter JP3D` regression sweep **528/528 PASS** (519 pre-existing + 9 new = 2 V10_27 probe + 6 V10_28 parity + 1 pre-existing skip); mandatory commit gate 7/7 PASS. The natural symmetric ship to v10.15.0 would have been `JP3DEncoder.preWarm`; the V10_27 cold-start probe killed that candidate (leftover encoder-specific cold cost +0.10 / −1.25 ms on 128/256-cube fixtures — `JP3DDecoder.preWarm(includeWarmupDispatch: true)` already amortises encoder Metal init via `J2KMetalSession.processShared`). Also bumps the stale `getVersion()` constant `10.9.2 → 10.16.0` (drifted across 8 releases). See [RELEASE_NOTES_v10.16.0.md](RELEASE_NOTES_v10.16.0.md).

**v10.15.0** adds **`JP3DDecoder.preWarm()`** (and `JP3DROIDecoder.preWarm()`) as discoverable convenience wrappers around the existing `J2KDecoder.preWarm()` (v5.28.0). JP3D consumers inherit the one-shot Metal session init amortisation automatically (per-slice `J2KMetalSession.processShared`), but the canonical preWarm entry point lived only in `J2KCodec` — consumers using the JP3D module surface alone had to import `J2KCodec` separately. v10.15.0 closes this discoverability gap with 2-line static wrappers in `Sources/J2K3D/JP3DDecoder.swift` + `JP3DROIDecoder.swift` that delegate to `J2KDecoder.preWarm(includeWarmupDispatch:)`. Same idempotent semantics, same failure handling (silently caught on Linux where Metal is unavailable). **M2 release, mr_3d_small 128×128×16 LCG JP3D fixture**: first decode in process **28.26 ms** (cold; includes Metal init), first after `JP3DDecoder.preWarm()` **14.60 ms**, warm median **14.33 ms** — **−13.93 ms cold-start savings** that clears the 3 ms acceptance threshold. Savings are constant per process (one-shot init cost) so they're most visible on small-volume JP3D decodes; for consumers doing one-shot decodes (e.g., a DICOM viewer opening one study), this is a real-world latency win delivered through a discoverable API. No perf change on warm paths; codestream bytes byte-identical to v10.14.0; decoder-only. Validation: `V10_26_JP3DPreWarmProfile` 1/1 PASS confirms `JP3DDecoder.preWarm` wires through correctly; full `swift test --filter JP3D` regression sweep **520/520 PASS** (519 pre-existing + 1 new V10_26); mandatory commit gate 7/7 PASS. Two preceding research arcs (v10.24 + v10.25) confirmed M2 + Swift release lever-ceiling on the ROI iDWT optimization space — v10.15.0 pivots to additive discoverability and ships honestly. See [RELEASE_NOTES_v10.15.0.md](RELEASE_NOTES_v10.15.0.md).

**v10.14.0** is the first **JP3D encoder** speedup of the v10 arc. The per-slice 2D encode loop in `JP3DSliceStackCodec.encode` was sequential since shipping — each Z-slice's 2D J2K encode ran one after another even though encodes are independent across slices (Z-delta residual depends on the previous slice's INPUT bytes, not its codestream). v10.14.0 splits the loop: sequential slices 0-1 commit the M6/M7 Z-delta tile-mode decision (`tileSignedOnlyActive` / `tileTryBothActive`), and slices 2..N run in parallel via `withThrowingTaskGroup`. The per-slice body is extracted into `encodeOneSlice(...)` so both phases share the same logic (raw encode + optional signed encode + best-of-two pick). M2 release JP3D encode A/B (`J2KBenchMac --jp3d`, in-process, 7 runs / 2 warmups, median): mr_3d_small (262K vox) 11.84→7.58 ms (**1.56×**), ct_3d_small (1.05M) 33.92→26.17 ms (**1.30×**), us_3d_small (1.84M) 58.58→40.73 ms (**1.44×**), mr_3d_mid (2.10M) 71.59→65.68 ms (**1.09×**), ct_3d_mid (8.39M) 295.58→246.98 ms (**1.20×**), ct_3d_large (16.78M) 615.94→539.95 ms (**1.14×** = **−76 ms absolute on the radiologist-relevant 16M-voxel CT**). All 6/6 fixtures clear the 3 ms acceptance threshold; smallest fixture shows the largest relative speedup (1.56× — per-slice fixed cost amortises better). Sub-linear vs N=8 M2 cores because Z-delta probe is serialized + slices 0-1 sequential + memory contention on the 33 MB output. Codestream bytes byte-identical to v10.13.0 (round-trip 519/519 JP3D tests PASS). Combined with the v10.11–v10.13 decode wins: round-trip on 16M-voxel CT is ~3.5× faster vs v10.10.0. Opt-out via `J2K_JP3D_PARALLEL_ENCODE=0`. Mandatory commit gate 7/7 PASS. See [RELEASE_NOTES_v10.14.0.md](RELEASE_NOTES_v10.14.0.md) and the bench JSONs at [`Documentation/Benchmarks/data/jp3d-bench-arm64-v10_23-{parallel,serial}-encode-20260524.json`](Documentation/Benchmarks/data/).

**v10.13.0** closes the last open cell of the JP3D **{K, ROI}** decode matrix. v10.11.0 shipped the K=0+nil (full-volume) batched bridge; v10.12.0 added K=0+ROI and K>0+nil; v10.13.0 ships K>0+ROI. Both the per-tile throw in `JP3DSliceStackCodec.decode` and the upstream throw in `JP3DROIDecoder.decode` (both fail-loud guards introduced in v10.18 as Phase 5 wiring tripwires) are removed. **`JP3DROIDecoder(cfg).decode(data, region:)`** with `cfg.resolutionLevel > 0` now returns a sub-volume sized `ceil(region.width / 2^K) × ceil(region.height / 2^K) × region.depth`, with voxels bit-identical to `JP3DDecoder(cfg).decode(data)` cropped to the downsampled-mapped region. `JP3DBridgeOptions.regionOfInterest` is standardised on **full-image coordinates** (matching the 2D codec's `decodeRegion` / `decodePartial` convention); the bridge maps the region onto the reduced grid for the crop step via `region / 2^(N − partialResolutionLevel)` (mirrors `decodePartial`'s `J2KAdvancedDecoding.swift:528-543` logic). `JP3DROIDecoder` is now K-aware end-to-end: the output `roiBuffers` is sized for the downsampled output dims when K>0, and the per-tile composite uses downsampled stride for both src (the slice-stack returns downsampled per-slice buffers) and dst (the roiBuffers). Z stays full — JP3D's K is a 2D-only halving; the Z-delta residual chain is per-slice. **`V10_18_TrueSelectiveParityTests.testCombinedResolutionLevelAndROI`** is the new K+ROI parity oracle (was the v10.18 fail-loud tripwire, inverted to a success-branch check); **9/9 PASS**. `V10_21_BatchedBridgeOptionsParityTests` updated to use full-coords ROI for the K=4+ROI composition test — **7/7 PASS**. `V10_20_BatchedBridgeParityTests` 5/5, `V10_20_BatchedInverseInt32ParityTests` 12/12, `V10_20_JP3DBridgeParityTests` 5/5 — all unchanged. Full `swift test --filter JP3D` regression sweep **519/519 PASS**, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.12.0; encoder unchanged. The full {K, ROI} matrix — (K=0, no ROI), (K=0, ROI), (K>0, no ROI), (K>0, ROI) — is now batched. See [RELEASE_NOTES_v10.13.0.md](RELEASE_NOTES_v10.13.0.md).

**v10.12.0** extends v10.11.0's JP3D batched bridge SPI to the **partial-resolution and ROI lanes** — closes the explicit "Partial-resolution + ROI paths not yet batched" known limitation. A new public `JP3DBridgeOptions(partialResolutionLevel:, regionOfInterest:)` struct + `J2KDecoder._jp3dDecodeToCoefficients(_:options:)` overload thread the options into the bridge SPI; the batched orchestrator truncates the chain to `effectiveLevels = N − K` for partial-res (output dims = `levelSizes[K]`), runs the full chain for ROI and crops the per-slice output via `cropImage`, and composes both (`K>0 + ROI` inside the reduced grid). The eligibility gate now requires uniform options across the batch (which JP3D's per-volume options trivially satisfy). `JP3DSliceStackCodec` removes the per-slice fallback on both branches and now builds a `JP3DBridgeOptions` from `K` + `regionOfInterest`, decodes all slices to coefficients in parallel via the new overload, then runs ONE batched iDWT + finalize. **M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups, median**: `full` lane ct_3d_large **−82.89 ms** (1.13×), `res1` lane ct_3d_large **−25.82 ms** (1.12×), `ROIq` lane ct_3d_large **−47.53 ms** (1.33×); ct_3d_mid full **−38.85 / res1 −10.44 / ROIq −21.18**. Per acceptance discipline (≥3 ms wins): full 4/6, res1 2/6, ROIq 3/6 fixtures clear; smaller fixtures wash on the lighter lanes (reduced workload leaves less to amortise). K=0 thumbnail (no iDWT chain) falls back to per-slice serial. The only `K > 0 AND ROI` composition still throws (the 2D codec doesn't compose those — separate arc). Opt-out via `J2K_JP3D_BATCHED_BRIDGE=0` (introduced v10.11.0; still works for all three lanes). **`V10_21_BatchedBridgeOptionsParityTests` 7/7 PASS** (K=0/2/4/N, ROI 128² and 64², ROI+K composition), `V10_20_BatchedBridgeParityTests` 5/5 PASS, `V10_20_BatchedInverseInt32ParityTests` 12/12 PASS, `V10_20_JP3DBridgeParityTests` 5/5 PASS, full `swift test --filter JP3D` regression sweep **519/519 PASS**, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.11.0; encoder unchanged. See [RELEASE_NOTES_v10.12.0.md](RELEASE_NOTES_v10.12.0.md) and the bench JSONs at [`Documentation/Benchmarks/data/jp3d-bench-arm64-v10_21-{batched,serial}-20260524.json`](Documentation/Benchmarks/data/).

**v10.11.0** ships **JP3D batched GPU iDWT** — the production landing of a multi-week research arc that splits the JP3D per-tile decode pipeline at the dequant↔iDWT boundary and submits one batched Metal dispatch across the whole z-range instead of N per-slice dispatches. A new opaque-payload bridge SPI on `J2KDecoder` (`_jp3dDecodeToCoefficients` / `_jp3dIDWTAndFinalize` / `_jp3dIDWTAndFinalizeBatched`) is the architectural surface; two new Metal kernels (`j2k_dwt_inverse_53_horizontal_int_tiled_batched`, `..._vertical_..._batched`) extend the v10.3 tiled threadgroup-memory kernels with a Z-dim grid axis, processing N slices in one dispatch. `JP3DSliceStackCodec` now runs **parallel `_jp3dDecodeToCoefficients` across `[zStart, zUpper)` via a TaskGroup, then ONE batched iDWT call** before the existing sequential Z-delta residual chain. Per-slice GPU dispatch overhead amortises across the volume; the gain scales with slice count × per-slice work. **M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups**: ct_3d_small **−5.12 ms** (1.13×), us_3d_small −4.15 ms (1.07×), mr_3d_mid **−9.50 ms** (1.12×), ct_3d_mid **−53.25 ms** (1.17×), **ct_3d_large 16M-voxel CT −114.57 ms** (1.17×). 5/6 fixtures clear the 3 ms acceptance threshold; the wash (mr_3d_small @ 13 ms wall) is the smallest fixture where per-slice overhead dominates anyway. Kernel-level bench (16 slices × 256×256 × 3 levels): **5.93 → 2.06 ms = 2.4× faster GPU dispatch**. Eligibility gate: only `K=0 + no ROI` routes through the batched path; `K>0` keeps the per-slice `decodeResolution` loop and ROI keeps `decodeRegion` (bridging those is future work). Opt-out via `J2K_JP3D_BATCHED_BRIDGE=0`. **`V10_20_BatchedBridgeParityTests` 5/5 PASS, `V10_20_BatchedInverseInt32ParityTests` 12/12 PASS, `V10_20_JP3DBridgeParityTests` 5/5 PASS, full `swift test --filter JP3D` regression sweep 519/519 PASS, mandatory commit gate 7/7 PASS**. Codestream bytes byte-identical to v10.10.0; encoder unchanged. See [RELEASE_NOTES_v10.11.0.md](RELEASE_NOTES_v10.11.0.md) and the bench JSONs in [Documentation/Benchmarks/data/](Documentation/Benchmarks/data/).

**v10.10.0** ships **JP3D true partial-resolution + ROI footprint-skip + Z-narrow ROI skip** — three coordinated decoder-side changes inside `Sources/J2K3D/` that close the long-standing follow-up on JP3D's selective-decode story. **`JP3DDecoderConfiguration.resolutionLevel`** has been wired into the struct since v5.x but the decoder ignored it (silently returned full resolution); v10.10.0 routes each per-slice 2D codestream inside `JP3DSliceStackCodec` through the existing v10.5.0 `J2KDecoder.decodeResolution(_:options:)`, producing a volume sized `⌈W / 2^K⌉ × ⌈H / 2^K⌉ × D` as documented. **`JP3DROIDecoder`** swaps decode-then-crop for true ROI footprint-skip — the per-tile in-tile XY sub-region is passed through to the slice-stack codec, which routes the per-slice 2D decode through v10.6.0 `decodeRegion(_:options:)` with `.direct` strategy (code-blocks whose inverse-DWT cone-of-influence misses the region skip entropy decode entirely). **Z-narrow ROI skip** pre-scans slice headers (no decode), finds the latest non-residual slice ≤ `zRange.lowerBound`, and starts decoding from there — completely skipping the unused Z-prefix while keeping Z-delta residual chain integrity via the restart anchor. M2 release: **`resolutionLevel = 1` is 2.2–3.1× faster than full decode** (mr_3d_small 2.22×, ct_3d_small 3.05×, mr_3d_mid 3.01×); **ROI 1/4 is 3.4–4.1× faster than full decode** (mr_3d_small 3.37×, ct_3d_small 4.14×, mr_3d_mid 3.96×). Combined `resolutionLevel + ROI` throws loud (was silently ignored previously). `V10_18_TrueSelectiveParityTests` 9/9 PASS, existing `JP3DDecoderTests` 61/61 PASS, mandatory commit gate clean. Encoder unchanged. Codestream bytes byte-identical to v10.9.3. See [RELEASE_NOTES_v10.10.0.md](RELEASE_NOTES_v10.10.0.md) and [V10_18_JP3D_TRUE_SELECTIVE_DECODE.md](Documentation/research/V10_18_JP3D_TRUE_SELECTIVE_DECODE.md).

**v10.9.3** is a packaging hotfix that makes J2KSwift unconditionally URL-consumable. v10.9.2 attempted CWD-conditional dependency resolution (sibling path if present, else URL) but `FileManager.fileExists` is evaluated with CWD set to the consuming root package — any consumer with a `CompressionFamily` directory beside its own root caused J2KSwift to fall back to the path form, and stable-version consumers may not transitively depend on path/branch packages ("unstable-version package" error). v10.9.3 drops the probe and always uses the public Git URL; local co-development uses `swift package edit CompressionFamily --path ../CompressionFamily`. Single-file Package.swift change; no codec change, codestream bytes byte-identical to v10.9.2.

**v10.9.2** is a stability + packaging patch. It fixes two latent `SIGSEGV` crashes and a packaging defect. **HTJ2K encoder crash (#439):** the fused HT entropy path force-unwrapped an empty buffer's `baseAddress` and trapped on degenerate / zero-coefficient code-blocks — observed crashing parallel code-block workers during the DICOMKit v1.1.0 integration; the five force-unwraps across the three coefficient-extraction sites are now `guard let` (an empty buffer falls through to the existing zero-block path). **Report-generator crash:** `ValidationReportGenerator.textReport` passed Swift `String` values to `String(format:)` `%s` specifiers — `%s` requires a C string, so the argument was `strlen`'d as a bogus tagged pointer; the 14 `%s` sites are replaced with Swift column padding + interpolation (this defect had also been silently aborting full `swift test` runs). **SwiftPM URL consumption (#438):** `Package.swift`'s `CompressionFamily` dependency is now conditional — local path for co-development, public Git URL otherwise — making J2KSwift resolvable via `.package(url:)` once the public `CompressionFamily` repo is published. Also: CI restructured Apple-only, the SwiftLint gate fixed (288 error-level findings → 0, kept as warnings), and the `J2KMetalDWT` band geometry consolidated into one `BandGeometry` helper (output-identical). Codestream bytes byte-identical to v10.9.1 — the encoder fix only alters the previously-crashing path. Validated: mandatory commit gate + HT cross-codec suites 22/22, 0 failures; a full `swift test` (6148 tests) now runs to completion where the report crash previously aborted it. See [RELEASE_NOTES_v10.9.2.md](Documentation/releases/RELEASE_NOTES_v10.9.2.md).

**v10.9.1** is a decoder correctness hotfix. The GPU multi-tile per-tile inverse 5/3 DWT corrupted the bottom edge of decoded images for sub-3-megapixel tiles at an odd tile-component canvas origin — e.g. a DX 2800×2288 image decoded as 2×2 tiles (observed max abs diff ≈ 9823). Root cause: `inverse2DGPUInt32` and `inverse2DCPUInt32` sized the LH/HH high-band as `height/2` (and `width/2`) instead of the canvas-anchored `height − llH` / `width − llW` — at an odd canvas origin the ISO/IEC 15444-1 band partition is uneven. The v8.3 fix corrected the multi-level-fused path but missed these two per-level functions; v10.3.0's `_gpuHTEntropyEnabled` routing change then made them reachable. Pure Swift host-code fix — the Metal kernels were never wrong; `default.metallib` is unchanged. Validated: `V8_3_GPUIDWTRootCauseDiagnostic` 3/3, all IDWT parity/bit-exact suites, the 5 multi-tile self-roundtrips, mandatory commit gate 7/7, cross-codec parity 14/14 (OpenJPEG/OpenJPH/Grok/Kakadu), and the warm cross-codec benchmark within run-to-run noise of v10.9.0 (J2KSwift wins 28/38 encode, 31/38 decode). Encoder and codestream bytes byte-identical to v10.9.0; decoder-only. Also bundles test maintenance — 8 stale-constant test updates and 19 dead-test deletions for de-scoped/parked features (test-only). See [RELEASE_NOTES_v10.9.1.md](Documentation/releases/RELEASE_NOTES_v10.9.1.md).

**v10.9.0** closes the partial-decode arc and fixes a conformance defect. `decodeQuality` was the last of four `notImplemented` partial-decode stubs (after `decodeResolution` v10.4/v10.5, `decodeRegion` v10.6/v10.7, `decodePartial` v10.8). Implementing it uncovered — and fixes — a real bug: `extractTileData`'s packet loop was hardcoded single-layer, so J2KSwift **silently mis-decoded any multi-layer codestream** (confirmed with Kakadu 8.4.1: a 4-layer lossless codestream decoded to wrong pixels, no error raised). v10.9.0 adds `extractTileDataMultiLayer` — the layer-aware packet decode per ISO/IEC 15444-1 B.10 (layer loop, persistent per-precinct inclusion/zero-bit-plane tag-trees, per-block `Lblock`+pass+data accumulation across layers); `extractTileData` routes to it when `qualityLayers > 1`, the single-layer path a separate byte-exact-unchanged branch. **`decodeQuality(layer:L)`** decodes quality layers `0...L` (a lower-bitrate preview); `layer == last` equals `decode()`; `cumulative:false` throws `notImplemented`. `V10_15_MultiLayerDecodeTests` 3/3 PASS: `decode()` of Kakadu 2/3/4-layer lossless codestreams **bit-identical to the original** (the conformance fix); `decodeQuality(layer:L)` **bit-identical to `kdu_expand -layers(L+1)`** for every layer — full cross-codec conformance including lossy truncated reconstructions. Single-layer regression: gate 7/7 + the v10.5–v10.8 partial-decode suites 16/16 PASS — single-layer decode untouched. Codestream bytes byte-identical to v10.8.0; encoder unchanged. `decodeResolution` + `decodeRegion` + `decodePartial` + `decodeQuality` — all four partial-decode APIs now implemented. See [RELEASE_NOTES_v10.9.0.md](Documentation/releases/RELEASE_NOTES_v10.9.0.md) and [V10_15_QUALITY_LAYER_DECODE.md](Documentation/research/V10_15_QUALITY_LAYER_DECODE.md).

**v10.8.0** ships the **`decodePartial` umbrella API**. Arc C exposed four public partial-decode entry points; `decodeResolution` shipped in v10.4.0/v10.5.0 and `decodeRegion` in v10.6.0/v10.7.0, but `decodePartial` was still a `notImplemented` stub. v10.8.0 implements it as the umbrella: one `decodePartial(_:options:)` call taking `J2KPartialDecodingOptions` that composes — `maxResolutionLevel` → true partial-resolution decode (code-block filter + inverse-DWT truncation, 3-8×); `region` → ROI decode (entropy-skip + tile-skip); `components` → component-subset selection (genuinely new — `decodeResolution`/`decodeRegion` never honoured their `components` field); and `maxResolutionLevel` + `region` together → decode at the level, crop the region mapped onto the reduced grid. `maxLayer` is guarded (the decoder packet loop is single-layer — a `maxLayer` that would exclude layers throws `notImplemented`); `earlyStop` is advisory; `decodePartial()` with default options equals `decode()`. Signature changed `throws` → `async throws` (the method was a stub — no real callers). `V10_14_DecodePartialTests` 7/7 PASS — `decodePartial` byte-identical to the single-axis API it delegates to (resolution-only ≡ `decodeResolution`, region-only ≡ `decodeRegion(.direct)`, empty ≡ `decode()`), resolution+region dims/data correct, component selection picks exactly the requested components in order. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.7.0; decoder-only, no codec hot-path change. `decodeQuality` stays `notImplemented` (single-layer decoder — separate arc). See [RELEASE_NOTES_v10.8.0.md](Documentation/releases/RELEASE_NOTES_v10.8.0.md) and [V10_14_DECODE_PARTIAL.md](Documentation/research/V10_14_DECODE_PARTIAL.md).

**v10.7.0** ships **ROI decode Stage 2 — tile-granular skip**. v10.6.0 Stage 1 skipped the entropy stage for off-region code-blocks but still ran the inverse DWT full-tile. Stage 2: JPEG 2000 tiles decode independently (no inverse-DWT halo crosses a tile boundary), so `decodeRegion(.direct)` now short-circuits any tile whose image rectangle does not overlap the region — `decodeTilePayload` / `decodeTilePayloadGPU` return a zero `DecodedTile`, skipping that tile's entropy, dequant, inverse DWT, colour transform and DC shift entirely. The marquee case is the 16.8 MP MG fixture (encoded as 2×2 tiles): a viewport-zoom ROI within one quadrant skips the other three tiles wholesale. **A/B (M2 release, MG 3518×4784, 256² corner region, 3 of 4 tiles skipped, 7 trials): `.fullImageExtraction` 84.70 ms → `.direct` 49.32 ms (Δ 35.38 ms, 1.72×)** — 1.72× rather than ~4× because the four tiles already decode concurrently, so the win is removed CPU work + reduced core contention. Single-tile fixtures (CT / DX / PX / MR) keep the v10.6.0 Stage 1 entropy-skip win unchanged; sub-tile windowed inverse DWT for them is Stage 3 (future work). `V10_12_ROITileSkipTests` 2/2 PASS (bit-exact across MG at 6 quadrant-placed regions, 1/2/4-tile coverage) + `V10_11_DecodeRegionDirectTests` 4/4 PASS re-run. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.6.0; decoder-only change, no public signature change. See [RELEASE_NOTES_v10.7.0.md](Documentation/releases/RELEASE_NOTES_v10.7.0.md) and [V10_12_ROI_TILE_SKIP.md](Documentation/research/V10_12_ROI_TILE_SKIP.md).

**v10.6.0** delivers the **ROI half** of the partial-decode arc (v10.4.0 + v10.5.0 shipped the *resolution* half). `J2KDecoder.decodeRegion(_:options:)` with the `.direct` strategy — previously a `notImplemented` stub — now does **true ROI decode**: `DecoderPipeline` gains a `regionOfInterest` and `extractTileData` drops every code-block whose inverse-DWT spatial footprint (band rect scaled by 2^depth + a conservative `8·2^depth` synthesis-filter halo) cannot influence an in-region pixel, skipping the dominant entropy decode stage for them. Mirrors the v10.5.0 Stage B.1 resolution filter with a spatial keep predicate. The inverse DWT still runs full-tile (off-region coefficients stay zero, cropped away); in-region pixels are exact because every block influencing them is retained. **A/B (M2 release, DX 2800×2288, 256² centre region, 7 trials): `.fullImageExtraction` 46.05 ms → `.direct` 33.21 ms (Δ 12.83 ms, 1.39×)**. Also fixes `extractRegion`, which was 8-bit-only — `decodeRegion(.fullImageExtraction)` had been silently corrupting output for every 16-bit medical image. `V10_11_DecodeRegionDirectTests` 4/4 PASS — `.direct` bit-identical to full-decode-then-crop across CT 512² / DX 2800×2288 / MG 3518×4784 (2×2 multi-tile), 7 region positions each (21 ROI decodes). Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. `decodeQuality` stays `notImplemented` (the decoder packet loop is single-layer — a separate arc). Codestream bytes byte-identical to v10.5.0; decoder-only change, no public signature change. See [RELEASE_NOTES_v10.6.0.md](Documentation/releases/RELEASE_NOTES_v10.6.0.md) and [V10_11_ROI_DECODE.md](Documentation/research/V10_11_ROI_DECODE.md).

**v10.5.0** completes the partial-resolution decode arc that v10.4.0 (Phase 1) started. `J2KDecoder.decodeResolution(_:options:)` now does **true partial-resolution decode**: Stage B.1 filters code-blocks by decomposition level before entropy decode (`extractTileData` gains a `maxResolutionLevel` parameter; a level-0 thumbnail of a 16.8 MP MG fixture drops ~99 % of code-blocks); Stage B.2 truncates the inverse DWT at the target level (`levelSubbands53` truncated to the deepest `r` decomposition levels, producing reduced-dimension LL output directly — no downsample step). **Thumbnail decode is 3-8× faster than full decode** (M2 release, 7-trial bench): CT 512² 2.55 → 0.33 ms (7.69×), PX 2459×1316 26.62 → 5.12 ms (5.20×), DX 2800×2288 47.08 → 9.59 ms (4.91×), MG mid 3518×4784 82.48 → 26.81 ms (3.08×). Clean resolution gradient across all 6 levels. Partial decode forces the CPU iDWT path (GPU iDWT truncation is future work); `decode()` / `decodeGPU()` / `decodeWithGPUHT()` unchanged. `decodeResolution(level: 5)` byte-identical to `decode()`. Partial output at level r is the mathematically exact LL band at decomposition level (N − r) per ISO/IEC 15444-1 §F. Smoke tests 3/3 PASS, cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.4.0. See [RELEASE_NOTES_v10.5.0.md](Documentation/releases/RELEASE_NOTES_v10.5.0.md).

**v10.4.0** lands **Phase 1 of partial-resolution decode**: `J2KDecoder.decodeResolution(_:options:)` (previously a `notImplemented` stub since v6.x) now returns a correctly-dimensioned `J2KImage` at the requested resolution level. Phase 1 implementation is decode-then-downsample — runs the full decode pipeline and power-of-2 block-averages the output to the target resolution. Provides a working API surface for downstream consumers (DICOM thumbnail / viewport-zoom workflows) without yet realising the perf upgrade (thumbnail decode still pays full-decode time). The method signature changed from `throws` to `async throws` — existing callers (test-only, since the stub always threw) need to add `await`. **Phase 2** (true partial decode with code-block filter + iDWT truncation, ~13× projected thumbnail speedup) is the next multi-session investment; the API contract stays stable across the Phase 1 → Phase 2 transition. Smoke tests 3/3 PASS (dimensions correct at all 6 levels, `level=5` byte-identical to `decode()`, `upscale: true` reconstructs original dims). Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.3.0; decoder-only API addition. See [RELEASE_NOTES_v10.4.0.md](Documentation/releases/RELEASE_NOTES_v10.4.0.md) and [V10_10_PARTIAL_RESOLUTION_PHASE1.md](Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE1.md).

**v10.3.0** closes the M2 MG mammography decode gap to Kakadu via two coordinated default-flips, both backed by 10-trial variance benches showing reliable wins on MG and pure wash elsewhere. **(1) `DecoderPipeline._gpuHTEntropyEnabled`** flipped ON → OFF — `V10_7_GPUHTEntropyFlagFlipVarianceTests`: **100% of 10 MG trials show flag-OFF winning by +19-27 ms median**, with DX/PX/XA/CT sitting inside ±0.06 ms median (single-tile decode never engages this multi-tile code path). The v6.2.0 D4 default-on was correct at the time but the CPU+NEON HT entropy path got significantly faster post-v10.0.0 D1.5-D — the GPU HT entropy multi-tile path is now slower on MG-class workloads. Opt-in via `J2K_GPU_HT_ENTROPY_DECODE=1` preserved. **(2) `J2KMetalDWT.inverse53IntFusedEnabled`** flipped OFF → ON with the v10.2.0 `inverse53IntFusedPixelThreshold = 12_000_000` retained — only MG-class (≥12 MP per-level) takes the fused single-dispatch H+V IDWT path. Combined v10.3.0 production impact on MG decode: MG small ~76 ms vs Kakadu ~73 ms (**1.04× — tied**), MG mid ~76 ms vs Kakadu ~75 ms (**1.01× — tied**), MG large ~82 ms vs Kakadu ~76 ms (1.08×). Codestream bytes byte-identical to v10.2.0. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS, `GPUHTEntropyDecodeDefaultOnTests` 2/2 PASS (bit-exact across flag toggle). Full migration notes in [RELEASE_NOTES_v10.3.0.md](Documentation/releases/RELEASE_NOTES_v10.3.0.md).

**v10.2.0** ships an **opt-in fused H+V inverse 5/3 Int Metal kernel** (`j2k_dwt_inverse_53_fused_int_tiled`) gated behind `J2K_METAL_IDWT_FUSED=1` and pixel-threshold `inverse53IntFusedPixelThreshold = 12_000_000`. The kernel collapses the v10.1.0 Phase 2-2-tiled pair (2 horizontal + 1 vertical dispatches per IDWT level) into a single dispatch by holding the H-pass output in threadgroup memory across the V lift — eliminates the colLow/colHigh device-memory round-trip (~2× DRAM saving per level at MG L1). Bit-exact equivalent of the tiled pair (`V10_5_MetalIDWTInverse53FusedParityTests`: 3/3 PASS across small / odd / medical-corpus dimensions including MG 3520×4784). 10-trial interleaved variance bench on M2: MG small +4.68 ms median (70% positive — RELIABLE WIN), MG mid +2.64 ms median (70% positive), MG large +7.67 ms median (50% positive — high std, coin flip per trial). Smaller fixtures (DX/PX/XA/CT) are wash; the 12 MP threshold routes them back through the tiled pair, so the opt-in is safe for production trials. **Default decode behavior unchanged from v10.1.0** — production code path uses the tiled pair unless the env var is set. Codestream bytes byte-identical to v10.1.0. Future v10.3.0 may flip the default to ON pending cross-silicon (M3/M4) variance validation. Cross-codec parity (OpenJPH/Grok/Kakadu) preserved with `J2K_METAL_IDWT_FUSED=1` set (`J2KStrictCrossCodecValidationTests`: 3/3 PASS). Full data set in [V10_5_METAL_IDWT_FUSED_FINDING.md](Documentation/research/V10_5_METAL_IDWT_FUSED_FINDING.md).

**v10.1.0** ships **tiled Metal inverse 5/3 DWT kernels** as the production default — closes the iDWT bottleneck Phase 0 of v10.3-research identified (iDWT became 63% DX / 78% MG of decode wall after v10.0.0's NEON HT entropy default-on). Two new Metal kernels (`j2k_dwt_inverse_53_{horizontal,vertical}_int_tiled`) fuse step 1 + step 2 of the 5/3 lifting in one dispatch per pass via threadgroup memory + barrier, closing the kernel-boundary cost the prior split-step prototype regressed on. Bit-exact equivalent of the scalar kernel by construction. Warm cross-codec bench A/B (M2): every fixture clears v7.4's ≥3 ms acceptance threshold; **MG 3521×4784 large drops 138.91 → 109.58 ms (−21 %)**, **DX 2544×3056 large drops 64.53 → 56.78 ms (−12 %)**, all PX/DX/MG fixtures 7-25% faster. Cross-codec parity (OpenJPH/Grok/Kakadu) preserved. Codestream bytes byte-identical to v10.0.0 (decoder-only optimisation). Opt-out via `J2K_METAL_IDWT_TILED=0`. Full migration notes in [RELEASE_NOTES_v10.1.0.md](RELEASE_NOTES_v10.1.0.md).

**v10.0.0** ships three coordinated wins on Apple M2: (1) **`recommendedDecodeAPI` recalibrated for v9.5.2 post-NEON** — `<500K → .cpu, 500K-15M → .decodeGPU, ≥15M → .cpu`; `.decodeWithGPUHT` removed from auto-routing; substitute-corpus `.auto` row drops 75-80 % on CT/PX/DX; (2) **MG-only 2x2 tile override in `J2KEncodeTilePlanner.auto`** — gate on `(pixels ≥ 12 MP AND min(w, h) ≥ 2400)`; MG encode wall drops 12-25 %; **MG codestream bytes change (MAJOR bump trigger)**; (3) **C+NEON HT decoder default-on** — new `j2knhd_decode_block_ht32` C entry; SWAR-4 MagSgn refill; per-block 1.61× single-thread / 1.55× 12-worker; cross-codec parity preserved; opt-out via `J2K_NEON_HT_DECODE=0`. Full bench numbers and migration notes in [RELEASE_NOTES_v10.0.0.md](RELEASE_NOTES_v10.0.0.md).

**v9.5.2** is a doc-only patch correcting misleading `j2k daemon-install --help` text. The previous help implied the j2kd daemon is the right path for any consumer wanting warm-process speed; v10.0-research Phase 6 measurement on Apple M2 shows that's only true for CLI consumers. SDK consumers calling `J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)` directly already pay zero cold-start after the first call, while the daemon adds avoidable IPC and result-transfer overhead: about 2-9 ms in isolated measurements and 8-50 ms under sustained batch load. The help text spells out **when to use the daemon (CLI / scripts / PACS tooling)** and **when not to (SDK / in-process consumers)**. Zero codec-core changes; codestream bytes byte-identical to v9.5.1. See [RELEASE_NOTES_v9.5.2.md](RELEASE_NOTES_v9.5.2.md).

**v9.5.1** hotfixes two pre-existing production runtime crashes: (1) `vImage_Buffer.data` dangling-pointer write in `J2KAccelerateDeepIntegration.scale16Bit` + `J2KVImageIntegration.resample` (silent corruption + occasional crash on thumbnail/preview paths); (2) SIGSEGV in `J2KConcurrencyTuning.ScalabilityReport.description` (`%s` + Swift String CVarArg UB under Swift 6.x). Codestream bytes byte-identical to v9.5.0 on every default configuration. See [RELEASE_NOTES_v9.5.1.md](RELEASE_NOTES_v9.5.1.md).

**v9.5.0** closes the v9.5–v9.8 research arc with three production wins: (1) daemon-encode large-fixture closure (DX warm via `j2k --daemon` 146 → 57 ms on M2 — 2.5× vs v9.4.0 warm, 1.8× vs cold same-binary); (2) process-default `J2KQstepCache.shared` for lossy 9/7 batches (M4 DX 99 → 29 ms, –71 %); (3) SIGTRAP fix in `encodeViaQstepSearch` refinement loop. Cross-codec parity matrix all-pass vs OpenJPH 0.27.0 / OpenJPEG / Kakadu HT. See [RELEASE_NOTES_v9.5.0.md](RELEASE_NOTES_v9.5.0.md).

**v9.4.0** ships the first **custom C+NEON HT block encoder** as the production default on Apple Silicon — `J2KCodecNEON` SwiftPM C target, 4-sample-per-quad NEON classifier, batched MagSgn emit. DX warm in-proc 104.5 → 94.9 ms on M4 (–9 %); per-block 20,584 → 7,083 ns (2.91× single-thread). 548+ bit-exact assertions PASS including codestream byte-identity vs OpenJPH/OpenJPEG/Kakadu reference encoders. See [RELEASE_NOTES_v9.4.0.md](RELEASE_NOTES_v9.4.0.md).

**v9.3.0** lands Path B encoder closure on Apple Silicon — 4 production wins (counter false-sharing removal, stack-resident scratch, Data-direct emit, MagSgn batched 4-sample emit). DX warm in-proc 124 → 104.5 ms on M4; Kakadu gap on daemon DX 4.39× → 3.69×. See [RELEASE_NOTES_v9.3.0.md](RELEASE_NOTES_v9.3.0.md).

**v8.1.0** turns the v8.0.0 manual 5-step `j2kd` daemon install into a single command (`j2k daemon-install`). End-to-end CLI gap on DX 2800×2288 closes from 72 ms cold-shot → ~55 ms with the daemon installed (–24 % wall). Codestream bytes byte-identical to v8.0.1; no decoder change. See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the full deployment-push details.

**v8.0.1** was a silent-corruption hotfix + GPU multi-tile-per-tile 5/3 IDWT root cause. Fixes the v7.5.1 mg silent-corruption (cross-tile batched HT entropy decode on 16+ MP mammography DICOM fixtures) AND root-causes / fixes the underlying GPU IDWT defect that produced the corruption — two distinct bugs in the GPU multi-tile-per-tile path, both surfacing only on tiles with non-zero canvas origin. `_multiTileBatchedEntropyEnabled` is back default-on; the v7.2.0 cross-tile entropy CB amortisation is restored. **Codestream bytes byte-identical to v8.0.0.** See [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the full root-cause analysis and the per-tile mismatch progression table.

**v8.0.0** was a major-version product pivot. v7.x targeted cross-platform performance and got within 25 % of OpenJPH and 2× of Kakadu globally. v8.0.0 narrows the product to **Apple Silicon (M-series macOS + A-series iOS/iPadOS)** and uses platform-native primitives (Metal, NSXPCConnection, launchd) to make the Swift SDK path fast for warm-process Apple applications. This is not a universal Kakadu-beating claim: Kakadu still leads sustained CLI runs, decode, and large-image batch workloads.

### Benchmark position — SDK encode vs Kakadu CLI (Apple M2/M4, release mode)

J2KSwift has two different performance shapes:

- **SDK / in-process**: app code calls `J2KEncoder.encode(_:)` or `J2KDecoder.decode(_:)` directly after process warmup. This is the shape DICOMKit and DICOM Studio use for their native codec path.
- **CLI / daemon**: scripts invoke `j2k` once per file. This shape includes process, daemon IPC, and file I/O overhead.

The focused M2 report shows J2KSwift in-process HT-conformant-lossless **encode** beating Kakadu CLI on 4 of 7 medical-corpus fixtures, mostly at <= 1 MP. The sustained cross-host CLI report shows J2KSwift+daemon winning **0 of 38** encode fixtures on both M2 and M4. Decode remains weaker: Kakadu leads the focused decode comparison by about 1.9-4.5x. See [J2KSWIFT_OPTIMAL_VS_KAKADU.md](Documentation/Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md), [CROSS_HOST_M2_M4_inproc.md](Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md), [CROSS_HOST_M2_M4_sustained.md](Documentation/Benchmarks/CROSS_HOST_M2_M4_sustained.md), and [DICOM_STUDIO_CLAIM_SCOPE_FINDING.md](Documentation/Benchmarks/DICOM_STUDIO_CLAIM_SCOPE_FINDING.md).

### CLI cold-shot progression — DX 2800×2288 (ms, median of 5)

| version | DX CLI cold | Kakadu gap |
|---|---:|---:|
| v7.5.1 baseline | 134 ms | 4.0× |
| v8 Phase 1 (cold-start elimination) | 91 ms | 2.7× |
| v8 Phase 2 (default-CPU routing) | 103 ms | 2.8× |
| v8 Phase 3 (SIMD CPU IDWT) | 91 ms | 2.7× |
| **v8 Phase 4 (NEON reconstruction default ON)** | **89 ms** | **2.47×** |
| **v8 with `j2kd` XPC daemon installed** | **~55 ms** | **~1.5×** |

The Phase 1-4 CPU optimisations cumulatively close the CLI gap from 4.0× to 2.47×. Installing the optional `j2kd` daemon (Phases 6.3-6.6) closes it further to ~1.5× by amortising Metal cold-start across CLI invocations.

### `j2kd` XPC daemon — warm-CLI single-shot (one-command install)

```bash
swift build -c release --product j2k --product j2kd
.build/release/j2k daemon-install      # one shot: copies binary, writes plist, loads launchd
.build/release/j2k daemon-status       # verify everything is ✓
```

To remove later: `j2k daemon-uninstall`. The install layout is per-user (no sudo) — binary at `~/Library/Application Support/J2KSwift/j2kd`, plist at `~/Library/LaunchAgents/com.raster.j2kd.plist`.

Idle timeout default 10 min; SIGTERM/SIGINT handled cleanly; launchd re-spawns on next client connection. Opt-out per call via `j2k decode --no-daemon`.

See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the daemon adoption push details. [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the silent-corruption hotfix. [RELEASE_NOTES_v8.0.0.md](RELEASE_NOTES_v8.0.0.md) covers the v8.0.0 major-version pivot and the 14 phase-finding documents (`V8_0_0_PHASE_0_BASELINE.md` through `V8_0_0_PHASE_6_6_FINDING.md`). Prior release notes: [v7.5.0](RELEASE_NOTES_v7.5.0.md), [v7.4.0](RELEASE_NOTES_v7.4.0.md), [v7.3.0](RELEASE_NOTES_v7.3.0.md).

## 🖥️ J2KTestApp — GUI Testing Application

J2KTestApp is a native macOS SwiftUI application that provides a complete graphical environment for testing every feature of J2KSwift.

### Building and Running J2KTestApp

```bash
# Build J2KTestApp
swift build --target J2KTestApp

# Run J2KTestApp
swift run J2KTestApp
```

Or open `Package.swift` in Xcode, select the **J2KTestApp** scheme, and press **⌘R**.

### GUI Screens

| Screen | Description |
|--------|-------------|
| **Encode** | Drag-and-drop encoding with configuration panel, presets, and DICOM support |
| **Decode** | File-based decoding with ROI selector, resolution stepper, marker inspector |
| **Round-Trip** | One-click encode/decode/compare with real PSNR/SSIM/MSE metrics |
| **Conformance** | Part 1/2/3/10/15 conformance matrix dashboard |
| **Validation** | Codestream syntax and file format validators |
| **Performance** | Benchmark runner with live charts and regression detection |
| **GPU** | Metal pipeline testing with GPU vs CPU comparison |
| **SIMD** | ARM Neon/Intel SSE verification with utilisation gauges |
| **JPIP** | Progressive streaming canvas with network metrics |
| **Volumetric** | JP3D slice navigation with encode/decode comparison |
| **Report** | Summary dashboard, trend charts, heatmap, and export |

See [Documentation/TESTING_GUIDE.md](Documentation/TESTING_GUIDE.md) for a complete guide to using J2KTestApp.

## 🎯 Project Goals

J2KSwift provides a modern, safe, and performant JPEG 2000 implementation for Swift applications:

- **Swift 6.2 Native**: Built with Swift 6.2's strict concurrency model — zero data races
- **Fully Functional**: Complete encoder and decoder pipelines with JP3D and HTJ2K
- **Apple-Silicon-First (v8.0.0+)**: macOS 15+ (M-series), iOS 18+ / iPadOS 18+ (A-series). Cross-platform builds (tvOS, watchOS, visionOS, Linux, Windows) still compile but performance is no longer a measurement criterion.
- **Standards Compliant**: Full ISO/IEC 15444-4 conformance across Parts 1, 2, 3, 10, and 15
- **Hardware Accelerated**: ARM Neon SIMD, Metal GPU, and Accelerate framework paths where the workload benefits
- **Network Streaming**: JPIP protocol support for efficient 2D and 3D image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: DocC catalogues for 6 modules, 50+ guides, tutorials, and API documentation
- **High Quality**: broad conformance, interoperability, regression, and GUI test coverage; release claims should cite the exact suite and host that were run
- **CLI Toolset**: Complete command-line tools for encoding, decoding, transcoding, 3D volumetric, JPIP streaming, batch processing, image comparison, format conversion, validation, and benchmarking

## 🚀 Quick Start

### Requirements

- Swift 6.2 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+

### Installation

Add J2KSwift to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.1.0")
]
```

Then add the specific modules you need to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
        // Optional: add J2K3D for volumetric JP3D support
        .product(name: "J2K3D", package: "J2KSwift"),
    ]
)
```

### Basic Usage

#### Simple Encoding (v1.2.0)

```swift
import J2KCodec

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// Encode with default settings
let encoder = J2KEncoder()
let j2kData = try encoder.encode(image)

// Or use a preset
let encoder = J2KEncoder(encodingConfiguration: .lossless)
let losslessData = try encoder.encode(image)
```

#### Simple Decoding (v1.2.0)

```swift
import J2KCodec

// Decode a JPEG 2000 file
let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)

// Access decoded data
print("Decoded image: \(image.width)×\(image.height)")
print("Components: \(image.componentCount)")
```

#### Advanced Encoding with Progress (v1.2.0)

```swift
import J2KCodec

let config = J2KEncodingConfiguration.quality
let encoder = J2KEncoder(encodingConfiguration: config)

let data = try encoder.encode(image) { progress in
    print("\(progress.stage): \(progress.percentage)% complete")
}
```

#### Progressive Decoding (v1.2.0)

```swift
import J2KCodec

// Decode progressively to target quality
let options = J2KProgressiveDecodingOptions(
    mode: .quality,
    targetQuality: 0.8
)
let image = try decoder.decode(j2kData, options: options)

// Or decode a region of interest
let roiOptions = J2KROIDecodingOptions(
    region: CGRect(x: 100, y: 100, width: 200, height: 200),
    strategy: .fullQuality
)
let roiImage = try decoder.decode(j2kData, options: roiOptions)
```

#### HTJ2K Encoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Create encoder with HTJ2K configuration
let config = EncodingConfiguration(
    codingStyle: .htj2k,  // Use High Throughput JPEG 2000
    quality: .highQuality
)

let encoder = J2KEncoder(configuration: config)
let htj2kData = try encoder.encode(image)

// HTJ2K is 57-70× faster than legacy JPEG 2000!
```

#### JP3D Volumetric Encoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

// Build a J2KVolume from component data
let component = J2KVolumeComponent(
    index: 0, bitDepth: 16, signed: false,
    width: 256, height: 256, depth: 128,
    data: rawVoxelData
)
let volume = J2KVolume(width: 256, height: 256, depth: 128, components: [component])

// Encode losslessly
let encoder = JP3DEncoder(configuration: .lossless)
let result = try await encoder.encode(volume)
print("Encoded \(result.data.count) bytes, \(result.tileCount) tiles")

// Or use HTJ2K for high throughput
let htConfig = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
let htEncoder = JP3DEncoder(configuration: htConfig)
let htResult = try await htEncoder.encode(volume)
// ~5-10× faster than standard JP3D
```

#### JP3D Volumetric Decoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

let decoder = JP3DDecoder(configuration: .default)
let decoded = try await decoder.decode(encodedData)
let volume = decoded.volume
print("Decoded volume: \(volume.width)×\(volume.height)×\(volume.depth)")
print("Components: \(volume.components.count), voxels: \(volume.voxelCount)")
```

#### Lossless Transcoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Transcode legacy JPEG 2000 to HTJ2K (bit-exact, zero quality loss)
let transcoder = J2KTranscoder()

let legacyCodestream = try Data(contentsOf: legacyFileURL)
let htj2kCodestream = try transcoder.transcode(
    legacyCodestream,
    from: .legacy,
    to: .htj2k
)

// Convert back to verify bit-exact round-trip
let roundTrip = try transcoder.transcode(
    htj2kCodestream,
    from: .htj2k,
    to: .legacy
)
// roundTrip == legacyCodestream (bit-exact!)

// Parallel transcoding for multi-tile images (1.05-2× speedup)
let config = TranscodingConfiguration.default  // Parallel enabled
let parallelTranscoder = J2KTranscoder(configuration: config)
let fastResult = try parallelTranscoder.transcode(multiTileData, from: .legacy, to: .htj2k)
```

#### Writing to JP2 File (v1.2.0)

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
// ... fill with image data ...

// Write as JP2 file (recommended - includes metadata)
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: outputURL, configuration: .init(quality: 0.95))

// Or write as raw J2K codestream
let j2kWriter = J2KFileWriter(format: .j2k)
try j2kWriter.write(image, to: codestreamURL)
```

#### Decoding (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KCodec

// Decode from codestream data
let decoder = J2KDecoder()
let decodedImage = try decoder.decode(codestreamData)
```

#### Reading from File (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KFileFormat

// Read any JPEG 2000 format (JP2, J2K, JPX, JPM)
let reader = J2KFileReader()
let image = try reader.read(from: fileURL)

// Access image data
print("Image: \(image.width)x\(image.height), \(image.components.count) components")
```

#### Using Component APIs (Advanced)

For advanced use cases, you can also use individual components directly:

```swift
import J2KCore
import J2KCodec

// 1. Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// 2. Apply wavelet transform
let dwt = J2KDWT2D()
let transformed = try dwt.forwardDecomposition(
    image.data,
    width: image.width,
    height: image.height,
    levels: 5
)

// 3. Quantization
let quantizer = J2KQuantizer()
let quantized = try quantizer.quantize(transformed, stepSize: 0.05)

// 4. Entropy coding
let mqCoder = J2KMQCoder()
let encoded = try mqCoder.encode(quantized)

// Result: encoded JPEG 2000 coefficient data
```

## 🔧 Command-Line Interface (CLI)

J2KSwift includes a comprehensive CLI tool (`j2k`) for encoding, decoding, transcoding, and analysing JPEG 2000 images. It also provides OpenJPEG-compatible commands for drop-in replacement.

### Installation

```bash
swift build -c release
# Binary at .build/release/j2k
```

### Command Reference

| Command | Description |
|---------|-------------|
| `encode` | Compress image(s) to JPEG 2000 / HTJ2K |
| `decode` | Decompress JPEG 2000 / HTJ2K image(s) |
| `transcode` | Lossless transcoding between J2K ↔ HTJ2K |
| `info` | Display codestream / file-format metadata |
| `validate` | ISO/IEC 15444-4 conformance validation |
| `benchmark` | Performance benchmarking |
| `encode3d` | Compress volumetric / 3D data (JP3D) |
| `decode3d` | Decompress volumetric / 3D data (JP3D) |
| `jpip server` | Start a JPIP streaming server |
| `jpip client` | Start a JPIP streaming client |
| `batch` | Batch-process files in a directory |
| `compare` | Compare two images (PSNR, MSE, MAE) |
| `convert` | Convert between image formats |
| `compress` | OpenJPEG-compatible compress (opj_compress) |
| `decompress` | OpenJPEG-compatible decompress (opj_decompress) |
| `dump` | OpenJPEG-compatible info/dump (opj_dump) |
| `completions` | Generate shell completions (bash/zsh/fish) |
| `version` | Print version information |

### Encoding

```bash
# Lossless encoding with 5/3 wavelet
j2k encode -i input.png -o output.j2k --lossless

# Lossy encoding with quality factor
j2k encode -i input.png -o output.j2k -q 0.85

# HTJ2K encoding for fast decoding
j2k encode -i input.png -o output.jph --htj2k

# Tiled encoding with custom parameters
j2k encode -i input.tif -o output.j2k --tile-size 512x512 --levels 6 --layers 5

# Encode from DICOM
j2k encode -i scan.dcm -o scan.j2k -q 0.95
```

### Decoding

```bash
# Decode to PNG
j2k decode -i input.j2k -o output.png

# Decode at reduced resolution (half size)
j2k decode -i input.j2k -o output.png --reduce 1

# Decode a specific region
j2k decode -i input.j2k -o region.png --region 100,100,400,400

# Decode specific quality layers
j2k decode -i input.j2k -o output.png --layers 3
```

### Transcoding

```bash
# Transcode J2K to HTJ2K (lossless)
j2k transcode -i input.j2k -o output.jph

# Transcode HTJ2K back to J2K
j2k transcode -i input.jph -o output.j2k
```

### Inspection and Validation

```bash
# Show codestream metadata
j2k info -i image.j2k

# Validate conformance
j2k validate -i image.j2k --profile baseline

# Compare two images
j2k compare -a original.png -b decoded.png

# Run benchmarks
j2k benchmark -i image.png --iterations 10
```

### 3D Volumetric (JP3D)

```bash
# Encode a volume from slice directory
j2k encode3d -i slices/ -o volume.jp3d --slices 128

# Decode and extract specific slices
j2k decode3d -i volume.jp3d -o output_dir/ --slice-range 10-20
```

### JPIP Streaming

```bash
# Start a JPIP server
j2k jpip server --port 8080 --image-dir ./images

# Connect with JPIP client
j2k jpip client --url http://localhost:8080/image.jp2
```

### Batch Processing

```bash
# Batch encode all images in a directory
j2k batch -i ./images/ -o ./encoded/ --mode encode -q 0.9

# Batch decode with parallel processing
j2k batch -i ./encoded/ -o ./decoded/ --mode decode --threads 8
```

### OpenJPEG-Compatible Commands

For users migrating from OpenJPEG, J2KSwift provides drop-in replacements:

```bash
# Compress (same flags as opj_compress)
j2k compress -i input.png -o output.j2k -r 20,10,1 -n 6 -b 64,64

# Decompress (same flags as opj_decompress)
j2k decompress -i input.j2k -o output.png -r 1 -l 3

# Dump codestream info (same flags as opj_dump)
j2k dump -i input.j2k -v
```

#### Compress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (PNG, TIFF, BMP, PGM, PPM, RAW, DICOM) |
| `-o` | Output file (J2K, JP2, JPH) |
| `-r` | Compression ratios (e.g., `20,10,1`) |
| `-q` | PSNR values per layer |
| `-n` | Number of resolution levels (default: 6) |
| `-b` | Code-block size (default: 64,64) |
| `-c` | Precinct size |
| `-t` | Tile size |
| `-p` | Progression order (LRCP, RLCP, RPCL, PCRL, CPRL) |
| `-I` | Use irreversible 9/7 wavelet |
| `--htj2k` | Use HTJ2K (Part 15) encoding |
| `-SOP` | Insert SOP markers |
| `-EPH` | Insert EPH markers |
| `-PLT` | Insert PLT markers |
| `-TLM` | Insert TLM markers |

#### Decompress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (J2K, JP2, JPH) |
| `-o` | Output file (PNG, TIFF, PGM, PPM, BMP, RAW) |
| `-r` | Reduce factor (0 = full, 1 = half, etc.) |
| `-l` | Number of quality layers to decode |
| `-d` | Decode area (x0,y0,x1,y1) |
| `-t` | Tile index to decode |
| `-force-rgb` | Force output to RGB |
| `-threads` | Number of threads |

### Piping and Stdin/Stdout

```bash
# Pipe from stdin to stdout
cat image.png | j2k encode -i - -o - --format j2k > encoded.j2k

# Chain encode and decode
j2k encode -i image.png -o - | j2k decode -i - -o decoded.png
```

### Shell Completions

```bash
# Generate Bash completions
j2k completions bash > /usr/local/etc/bash_completion.d/j2k

# Generate Zsh completions
j2k completions zsh > ~/.zfunc/_j2k

# Generate Fish completions
j2k completions fish > ~/.config/fish/completions/j2k.fish
```

## 🖥️ J2KTestApp User Manual

J2KTestApp is a native macOS SwiftUI application for testing, validating, and inspecting JPEG 2000 encoding/decoding.

### Running

```bash
swift run J2KTestApp
```

Or open `Package.swift` in Xcode → select the **J2KTestApp** scheme → **⌘R**.

### Encode Screen

1. **Select Input** — drag-and-drop an image (PNG, TIFF, BMP, DICOM) or click **Browse**.
2. **Choose Preset** — select Lossless, Lossy High Quality, Visually Lossless, or Maximum Compression.
3. **Configure** — adjust quality, wavelet type, tile size, decomposition levels, quality layers, progression order, MCT, and HTJ2K toggles.
4. **Encode** — click the **Encode** button (⌘↵). Progress is shown per-stage.
5. **Inspect Results** — view encoded size, compression ratio, encoding time, and per-stage timing.
6. **Compare** — see original vs. encoded side-by-side, overlay, or difference views.
7. **Save** — export the encoded J2K/JP2 file.

Tabs:
- **Single** — encode one image at a time.
- **Compare** — add multiple configurations and compare outputs side-by-side.
- **Batch** — select a folder and encode all images with the current configuration.

### Decode Screen

1. **Open File** — click **Open File…** and select a JP2, J2K, JPX, JPH, or JHC file.
2. **Configure** — set resolution level, quality layer, component channel, and optional ROI.
3. **Decode** — click **Decode** (⌘↵). The decoded image is displayed with actual dimensions.
4. **Inspect Markers** — toggle the **Markers** panel to see all parsed codestream markers (SOC, SIZ, COD, QCD, SOT, etc.) with offsets and descriptions.

### Round-Trip Validation

1. **Generate Test Image** — choose from Gradient, Checkerboard, Noise, Solid Colour, or Lena-Style patterns.
2. **Or Drop Image** — drag-and-drop a real image onto the encode input.
3. **Run Round-Trip** — click **Run Round-Trip** (⌘↵). The pipeline:
   - Encodes the image using the current configuration.
   - Decodes the encoded output back to pixels.
   - Computes PSNR, SSIM, and MSE metrics.
   - Shows pass/fail badges based on quality thresholds.
4. **Compare** — toggle Difference view to see pixel-level discrepancies.
5. **Bit-Exact Badge** — for lossless configurations, verifies exact reconstruction.

### DICOM Support

J2KTestApp can directly load uncompressed DICOM (.dcm) files for encoding to JPEG 2000. This is useful for medical imaging workflows:

1. Drop a DICOM file onto the Encode input area, or use **Browse**.
2. The app extracts pixel data from the DICOM file (supports 8-bit and 16-bit, grayscale and RGB).
3. 16-bit data is automatically windowed and scaled to 8-bit for encoding.
4. Encode as usual — the output J2K/JP2 file is suitable for PACS and DICOM systems.


## ✨ Features

### Implemented in v1.0.0 ✅

#### Core Components
- **Image Representation**: Multi-component images with arbitrary bit depths (1-38 bits)
- **Tiling**: Configurable tile dimensions with boundary handling
- **Memory Management**: Zero-copy buffers, memory pools, optimized allocators
- **I/O Infrastructure**: Bit-level reading/writing, marker parsing, format detection

#### Wavelet Transform (Phase 2 Complete)
- **Filters**: 5/3 reversible (lossless), 9/7 irreversible (lossy)
- **Decomposition**: 1D and 2D transforms, multi-level (up to 32 levels)
- **Tiling Support**: Tile-by-tile processing with proper boundary handling
- **Test Coverage**: 96.1% pass rate (32 known issues in bit-plane decoder)

#### Entropy Coding (Phase 1 Complete)
- **EBCOT**: Embedded Block Coding with Optimized Truncation
- **MQ-Coder**: Arithmetic entropy coding (18,800+ ops/sec)
- **Bit-Plane Coding**: Three coding passes with context modeling
- **Bypass Mode**: Selective arithmetic coding bypass
- **Performance**: Optimized hot paths with inline hints

#### Quantization & Rate Control (Phase 3 Complete)
- **Quantization**: Scalar and deadzone quantization
- **Rate Control**: PCRD-opt algorithm for optimal rate-distortion
- **ROI**: MaxShift method with arbitrary shapes (rectangle, ellipse, polygon)
- **Quality Layers**: Multi-layer generation for progressive decoding

#### Color Transforms (Phase 4 Complete)
- **RCT**: Reversible Color Transform for lossless compression
- **ICT**: Irreversible Color Transform for lossy compression
- **Color Spaces**: RGB, YCbCr, Greyscale, CMYK support
- **Subsampling**: Component-level subsampling

#### File Format (Phase 5 Complete)
- **Formats**: JP2, J2K, JPX, JPM file formats
- **Boxes**: 15+ box types including header, color, palette, resolution
- **Metadata**: ICC profiles, XML, UUID boxes
- **Composition**: Multi-page and animation support (JPX/JPM)
- **Test Coverage**: 100% pass rate for file format operations

#### JPIP Protocol (Phase 6 Complete - Infrastructure)
- **Session Management**: HTTP transport, session lifecycle
- **Request/Response**: Protocol messaging framework
- **Caching**: Client-side precinct-based caching
- **Server**: Multi-client support with bandwidth throttling
- **Note**: Streaming operations await codec integration (v1.1)

#### Advanced Features (Phase 7 Complete)
- **Visual Weighting**: CSF-based perceptual modeling
- **Quality Metrics**: PSNR, SSIM, MS-SSIM
- **Encoding Presets**: Fast, balanced, quality presets
- **Progressive Modes**: SNR, spatial, layer-progressive
- **Extended Formats**: 16-bit images, HDR support, alpha channels

#### Codec Integration (v1.0 Complete ✅)
- **Encoding**: Full `J2KEncoder.encode()` pipeline
- **Decoding**: Full `J2KDecoder.decode()` pipeline
- **File I/O**: `J2KFileReader.read()` and `J2KFileWriter.write()`
- **Round-Trip**: Complete encode→decode workflows
- **Test Coverage**: 1,498 tests, 98.3% passing (25 skipped)

### Future Releases
- **v2.2**: Multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS exploration (complete)
- **v2.3**: JPEG XS full implementation, DICOM metadata enhancements
- **v3.0**: x86-64 SIMD code removal (Apple-first architecture), JPEG XS support

## 📚 Documentation

### Getting Started
- **[README.md](README.md)**: This file — quick start and overview
- **[CHANGELOG.md](CHANGELOG.md)**: Complete version history
- **[RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)**: Complete v2.1.0 release notes
- **[RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md)**: Complete v2.0.0 release notes
- **[GETTING_STARTED.md](GETTING_STARTED.md)**: Comprehensive introduction
- **[TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md)**: Step-by-step encoding guide
- **[TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)**: Step-by-step decoding guide
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)**: Migrating from OpenJPEG
- **[MIGRATION_GUIDE_v2.0.md](MIGRATION_GUIDE_v2.0.md)**: Migrating from v1.9.0 to v2.0.0

### API Reference
- **[API_REFERENCE.md](API_REFERENCE.md)**: Complete API documentation
- **[API_ERGONOMICS.md](API_ERGONOMICS.md)**: API design principles
- **Swift-DocC**: Generated documentation (see [DOCUMENTATION_GUIDE.md](DOCUMENTATION_GUIDE.md))

### Technical Documentation
- **[WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md)**: DWT implementation details
- **[ENTROPY_CODING.md](ENTROPY_CODING.md)**: EBCOT and MQ-coder
- **[QUANTIZATION.md](QUANTIZATION.md)**: Quantization strategies
- **[RATE_CONTROL.md](RATE_CONTROL.md)**: PCRD-opt algorithm
- **[COLOR_TRANSFORM.md](COLOR_TRANSFORM.md)**: Color space conversions
- **[JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md)**: File format specification
- **[HTJ2K.md](HTJ2K.md)**: High-Throughput JPEG 2000 (ISO/IEC 15444-15)
- **[JPIP_PROTOCOL.md](JPIP_PROTOCOL.md)**: Streaming protocol
- **[EXTENDED_FORMATS.md](EXTENDED_FORMATS.md)**: JPX, JPM support
- **[BYPASS_MODE_ISSUE.md](BYPASS_MODE_ISSUE.md)**: Known bypass mode limitation and workarounds

### JP3D Volumetric JPEG 2000 (v1.9.0)
- **[Documentation/JP3D_GETTING_STARTED.md](Documentation/JP3D_GETTING_STARTED.md)**: Quick start guide for JP3D
- **[Documentation/JP3D_ARCHITECTURE.md](Documentation/JP3D_ARCHITECTURE.md)**: Architecture overview (J2K3D, JPIP, Metal, Accelerate)
- **[Documentation/JP3D_API_REFERENCE.md](Documentation/JP3D_API_REFERENCE.md)**: Complete API reference for all JP3D public types
- **[Documentation/JP3D_STREAMING_GUIDE.md](Documentation/JP3D_STREAMING_GUIDE.md)**: JPIP 3D streaming guide
- **[Documentation/JP3D_PERFORMANCE.md](Documentation/JP3D_PERFORMANCE.md)**: Performance tuning guide with benchmark tables
- **[Documentation/JP3D_HTJ2K_INTEGRATION.md](Documentation/JP3D_HTJ2K_INTEGRATION.md)**: HTJ2K usage guide for volumetric encoding
- **[Documentation/JP3D_MIGRATION.md](Documentation/JP3D_MIGRATION.md)**: Migration from 2D JPEG 2000 to JP3D
- **[Documentation/JP3D_TROUBLESHOOTING.md](Documentation/JP3D_TROUBLESHOOTING.md)**: Common issues and solutions
- **[Documentation/JP3D_EXAMPLES.md](Documentation/JP3D_EXAMPLES.md)**: Comprehensive usage examples

### Advanced Topics
- **[ADVANCED_ENCODING.md](ADVANCED_ENCODING.md)**: Encoding techniques
- **[ADVANCED_DECODING.md](ADVANCED_DECODING.md)**: Decoding optimizations
- **[HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md)**: Performance optimization
- **[PARALLELIZATION.md](PARALLELIZATION.md)**: Multi-threading strategy
- **[PERFORMANCE.md](PERFORMANCE.md)**: Benchmarking and profiling

### Development & Testing
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Development guidelines
- **[CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md)**: Standards compliance
- **[REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md)**: Performance baselines
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions

### Project Management
- **[DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md)**: Current development status with visual progress
- **[NEXT_PHASE.md](NEXT_PHASE.md)**: Next phase development roadmap (HTJ2K codec & transcoding)
- **[MILESTONES.md](MILESTONES.md)**: 100-week development roadmap (complete!)
- **[ROADMAP_v1.1.md](ROADMAP_v1.1.md)**: Next version plans
- **[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)**: Release process

## 🗺️ Development Roadmap

### Completed: 100-Week Milestone
        print("Cache hit rate: \(cacheStats.hitRate * 100)%")
        print("Cache size: \(cacheStats.totalSize) bytes, entries: \(cacheStats.entryCount)")
        
        // Check if data is cached
        if await session.hasDataBin(binClass: .mainHeader, binID: 1) {
            let dataBin = await session.getDataBin(binClass: .mainHeader, binID: 1)
            print("Retrieved from cache: \(dataBin?.data.count ?? 0) bytes")
        }
        
        // Get precinct cache statistics
        let precinctStats = await session.getPrecinctStatistics()
        print("Precincts: \(precinctStats.totalPrecincts) total")
        print("Completion rate: \(precinctStats.completionRate * 100)%")
        
        // Invalidate cache by bin class
        await session.invalidateCache(binClass: .precinct)
        
        print("Received image: \(image.width)x\(image.height)")
    } catch {
        print("Request failed: \(error)")
    }
}
```

## 📦 Modules

### J2KCore
Core types, protocols, and utilities used by all other modules.

### J2KCodec
Encoding and decoding functionality for JPEG 2000 images.

### J2KFileFormat
File format support for JP2, J2K, JPX, and other JPEG 2000 container formats.

### J2KMetal
Metal GPU acceleration for Apple Silicon processors, providing 10–40× performance improvements for wavelet transforms, colour transforms, ROI processing, and quantisation.

### JPIP
JPEG 2000 Interactive Protocol implementation for efficient network streaming, including JP3D 3D streaming with view-dependent progressive delivery.

### J2K3D
JP3D volumetric JPEG 2000 (ISO/IEC 15444-10) encoding, decoding, and streaming. Provides `JP3DEncoder`, `JP3DDecoder`, 3D wavelet transforms, HTJ2K integration, and JPIP 3D streaming. This is an optional module — existing 2D workflows are unaffected.

## 🗓️ Development Roadmap

See [MILESTONES.md](MILESTONES.md) for the detailed 100-week development roadmap tracking all features and implementation phases.

### Current Status: v2.2.0 — Production Ready

> **Encoder Status**: The high-level `J2KEncoder.encode()` API is **fully functional** with ARM Neon SIMD, Intel SSE/AVX, and Metal GPU acceleration.
> 
> **Decoder Status**: The high-level `J2KDecoder.decode()` API is **fully functional** with full ISO/IEC 15444-4 conformance and verified OpenJPEG interoperability.
> 
> **Phase 19 Status**: Multi-spectral JP3D encoding/decoding, Vulkan 3D DWT, and JPEG XS exploration types are **complete**.


**All Phases Complete** (325 weeks):
- ✅ Phase 0–8: Foundation through Production Ready (Weeks 1–100)
- ✅ Phase 9–12: vDSP, JPIP, HTJ2K, Extended Formats (Weeks 101–154)
- ✅ Phase 13–14: Part 2 Extensions, Motion JPEG 2000 (Weeks 155–210)
- ✅ Phase 15–16: JP3D Volumetric Support (Weeks 211–235)
- ✅ Phase 17: Performance Refactoring & Conformance (Weeks 236–295)
- ✅ Phase 18: GUI Testing Application (Weeks 296–315)
- ✅ Phase 19: Multi-Spectral JP3D and Vulkan JP3D Acceleration (Weeks 316–325)

**Current**: v2.2.0 — see [CHANGELOG.md](CHANGELOG.md) for details

## 🧪 Testing

### Test Statistics
- **Total Tests**: 3,100+ across the current project history
- **Passing**: use the latest CI or local run for an exact pass rate; do not treat older README counts as a release guarantee
- **Conformance Tests**: 304 (ISO/IEC 15444-4, Parts 1, 2, 3, 10, 15)
- **Interoperability Tests**: 165 (OpenJPEG bidirectional)
- **Integration Tests**: 200+ (end-to-end, stress, regression)
- **GUI Tests**: 309 (J2KTestApp models and view models)
- **Phase 19 Tests**: 55+ (multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS types)

### Test Coverage by Module
- **J2KCore**: public API and conformance coverage
- **J2KCodec**: codec, ARM Neon, Intel SSE/AVX, and interoperability coverage
- **J2KFileFormat**: JP2/JPH/JHC file-format coverage
- **J2KMetal**: GPU compute regression coverage
- **JPIP**: 2D and 3D streaming coverage
- **J2K3D**: JP3D volumetric coverage

### Running Tests
```bash
# Run all tests
swift test

# Run specific module tests
swift test --filter J2KCoreTests
swift test --filter J2KCodecTests
swift test --filter J2KFileFormatTests
swift test --filter J2KTestAppTests

# Run with coverage
swift test --enable-code-coverage

# Performance tests
swift test --filter J2KBenchmarkTests
```

### J2KTestApp GUI Testing
```bash
# Build and run the GUI testing application (macOS only)
swift run J2KTestApp

# Headless CI mode
j2k testapp --headless --playlist "Quick Smoke Test" --output report.html --format html
```

See [CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md) for details on testing strategy.

## 🚀 Performance

### Performance vs OpenJPEG (v2.0.0)

| Metric | Apple Silicon | Intel x86-64 |
|--------|--------------|--------------|
| Lossless encode | ≥1.5× faster | ≥1.0× (parity) |
| Lossy encode | ≥2.0× faster | ≥1.2× faster |
| HTJ2K encode | ≥3.0× faster | N/A |
| Decode (all modes) | ≥1.5× faster | ≥1.0× (parity) |
| GPU-accelerated (Metal) | ≥10× faster | N/A |

### Hardware Acceleration
- **ARM Neon SIMD**: Vectorised entropy coding, wavelet lifting, colour transforms
- **Metal GPU**: Optimised DWT shaders, tile-based dispatch, async compute
- **Accelerate Framework**: vDSP and vImage integration in the codec hot paths

See [PERFORMANCE.md](PERFORMANCE.md), [Documentation/PERFORMANCE_COMPARISON.md](Documentation/PERFORMANCE_COMPARISON.md), and [Documentation/PERFORMANCE_VALIDATION.md](Documentation/PERFORMANCE_VALIDATION.md) for detailed metrics.

## 🤝 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For information about our CI/CD workflows and automated testing, see [CI_CD_GUIDE.md](CI_CD_GUIDE.md).

### Areas Needing Help
1. **JPEG XS full implementation** (v2.3 target)
2. **DICOM metadata enhancements** (v2.3 target)
3. **Cross-platform testing** (Windows, Linux ARM64)
4. **Community feedback and real-world usage reports**
5. **Hyperspectral remote-sensing datasets for JP3D validation**

### Development Process
```bash
# Clone the repository
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift

# Build the project
swift build

# Run tests
swift test

# Run SwiftLint
swiftlint

# Format code (if swift-format installed)
swift format --in-place --recursive Sources Tests
```

## 📄 License

J2KSwift is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

This project represents a 295-week development effort following a comprehensive milestone-based roadmap. Special thanks to:

- The JPEG committee for the JPEG 2000 standard (ISO/IEC 15444)
- Apple's Swift team for Swift 6.2 and the concurrency model
- The open-source community for testing and feedback

## 📞 Support

### Getting Help
- 📖 **Documentation**: Start with [GETTING_STARTED.md](GETTING_STARTED.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/Raster-Lab/J2KSwift/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Raster-Lab/J2KSwift/discussions)
- 📧 **Security**: Contact maintainers for security issues

### Project Links
- **Repository**: https://github.com/Raster-Lab/J2KSwift
- **Releases**: https://github.com/Raster-Lab/J2KSwift/releases
- **Milestones**: [MILESTONES.md](MILESTONES.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Release Notes**: [RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)

## 📊 Project Status

| Component | Status | Test Coverage | Notes |
|-----------|--------|---------------|-------|
| Core Types | ✅ Complete | 100% | Production ready |
| Wavelet Transform | ✅ Complete | 100% | ARM Neon + Intel SSE/AVX SIMD |
| Entropy Coding | ✅ Complete | 100% | SIMD-accelerated MQ-coder |
| Quantisation | ✅ Complete | 100% | Vectorised quantise/dequantise |
| Colour Transforms | ✅ Complete | 100% | ICT/RCT with SIMD acceleration |
| File Format | ✅ Complete | 100% | JP2/JPX/JPM/J2K/JPH support |
| JPIP Protocol | ✅ Complete | 100% | 2D and 3D streaming |
| Encoder API | ✅ Complete | 100% | ≥1.5–3× faster than OpenJPEG |
| Decoder API | ✅ Complete | 100% | Full Part 4 conformance |
| Hardware Accel | ✅ Complete | 100% | Metal, Accelerate, Neon |
| HTJ2K Codec | ✅ Complete | 100% | ≥3× faster on Apple Silicon |
| JP3D Volumetric | ✅ Complete | 100% | ISO/IEC 15444-10 compliant |
| Motion JPEG 2000 | ❌ Removed in v11.0.0 | — | MJ2 file-format stack deleted (dead weight) |
| CLI Tools | ✅ Complete | 100% | Dual British/American spelling |
| **CLI Enhancement** | ✅ Complete | 193 tests | 8 new commands, 3D/JPIP/batch (Phase 21) |
| Conformance | ✅ Complete | 304 tests | Parts 1, 2, 3, 10, 15 |
| **J2KTestApp** | ✅ Complete | 309 tests | GUI testing application (Phase 18) |
| **Multi-Spectral JP3D** | ✅ Complete | 30+ tests | Spectral bands, encoder, decoder (Phase 19) |
| **Vulkan JP3D DWT** | ✅ Complete | 15+ tests | 3D DWT with spectral axis (Phase 19) |
| **JPEG XS Exploration** | ✅ Scaffolded | 10+ tests | ISO/IEC 21122 exploration types (Phase 19) |
| **JPEG XS Codec** | ❌ Removed in v11.0.0 | — | J2KXS module deleted (dead weight) |

---

**J2KSwift** — A standards-focused Swift implementation of JPEG 2000 / HTJ2K
**Status**: See the current-version and benchmark-position sections at the top of this README for the active performance and interoperability claims.
**Next Release**: See [MILESTONES.md](MILESTONES.md) for roadmap

For detailed information, see [CHANGELOG.md](CHANGELOG.md)
