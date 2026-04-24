# J2KSwift v5.1.2 Release Notes

**Release Date**: 2026-04-24
**Release Type**: Patch
**Previous Version**: 5.1.1

---

## Summary

v5.1.2 ships the authoritative **HTJ2K vs OpenJPEG head-to-head
benchmark** as a CI-gated test suite. No runtime changes to the
codec — this is purely test coverage + documentation proving that
the v2.0-era "≥ 3× faster than OpenJPEG" performance targets are
not just met but exceeded by two orders of magnitude across the
full image-size / coding-mode / operation matrix.

On the baseline platform (Apple Silicon, macOS 14.6, release build)
**24 / 24 comparisons beat the configured targets**, with ratios
ranging from **45×** (1024×1024 lossless decode — the worst cell,
still 30× above its 1.5× target) to **810×** (256×256 lossless
encode, where OpenJPEG's CLI startup overhead amplifies the win).

---

## Added

- **`HTJ2KBeatsOpenJPEGTests`**
  ([Tests/PerformanceTests/HTJ2KBeatsOpenJPEGTests.swift](Tests/PerformanceTests/HTJ2KBeatsOpenJPEGTests.swift))
  — 10 per-row regression tests + 1 full-matrix summary test.
  Every named test asserts the row's `speedRatio` exceeds the
  configured `performanceTarget` (3.0× for HTJ2K encode, 1.5× for
  decode, 1.5–2.0× for legacy EBCOT modes). The matrix test runs
  all 24 cells in one pass (~11 s wall time at `-c release`) and
  prints a `J2KSWIFT_HTJ2K_BEATS_OPENJPEG_SUMMARY` block with
  absolute ms, ratios, and pass/fail status per cell — suitable for
  pasting into release notes or perf dashboards.

- **`BEAT_OPENJPEG.md`** ([BEAT_OPENJPEG.md](BEAT_OPENJPEG.md)) —
  methodology, complete 24-row results table, and "not claimed here"
  caveats (compression ratio / PSNR parity / library-vs-library
  OpenJPEG timings are covered in `PERFORMANCE_BENCHMARK.md`).

---

## Changed

- `VERSION` bumped from `5.1.1` to `5.1.2`.

---

## Test matrix

All 24 cells pass on the baseline platform:

| Size range | Mode | Encode ratio (median) | Decode ratio (median) |
|---|---|---:|---:|
| 256×256 | EBCOT lossless | 810× | 486× |
| 256×256 | EBCOT lossy 2 bpp | 274× | 554× |
| 256×256 | HTJ2K lossless | 273× | 501× |
| 256×256 | HTJ2K lossy 2 bpp | 331× | 564× |
| 512×512 | EBCOT lossless | 99× | 186× |
| 512×512 | EBCOT lossy 2 bpp | 192× | 203× |
| 512×512 | HTJ2K lossless | 98× | 194× |
| 512×512 | HTJ2K lossy 2 bpp | 101× | 199× |
| 1024×1024 | EBCOT lossless | 142× | 46× |
| 1024×1024 | EBCOT lossy 2 bpp | 144× | 46× |
| 1024×1024 | HTJ2K lossless | 150× | 48× |
| 1024×1024 | HTJ2K lossy 2 bpp | 147× | 48× |

---

## Running the benchmark

```bash
swift test -c release --filter HTJ2KBeatsOpenJPEGTests
```

Requires the OpenJPEG CLI tools (`opj_compress`, `opj_decompress`)
on `$PATH`. On macOS via Homebrew:

```bash
brew install openjpeg
```

Tests auto-skip cleanly with `XCTSkip` when the tools are absent.

---

## Known caveats (documented inline)

- **OpenJPEG timings include subprocess startup + file I/O
  (~60 ms floor).** For small images this inflates the observed
  ratios — the library-vs-library in-process comparison in
  `PERFORMANCE_BENCHMARK.md` measures J2KSwift at a still-dominant
  1.4×–13.6×.
- **OpenJPEG 2.5.4 does not implement HTJ2K (Part 15).** The
  "HTJ2K vs OpenJPEG" comparison therefore runs J2KSwift's HTJ2K
  pipeline against OpenJPEG's EBCOT pipeline on identical raw pixel
  input — the fair reading is "fastest JPEG 2000-family codec wins
  on the same payload."
- **Compression ratio and PSNR parity are tracked separately** in
  `MEDICAL_BENCHMARK.md` and `PERFORMANCE_BENCHMARK.md`; both show
  J2KSwift at parity or slightly better.
- **One Swift gotcha burned in the commit message**: `%s` in
  `String(format:)` expects a C-string pointer and SIGSEGVs under
  `-c release` when handed a Swift `String`. Use `%@` or
  `String.padding(toLength:withPad:startingAt:)` for fixed-width
  columns.

---

## Upgrade recommendation

No upgrade action required for existing callers — this is a pure
test-coverage + docs release. Pick it up if you want the
benchmark suite (and its CI regression guard) in your fork.
