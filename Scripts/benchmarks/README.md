# Cross-codec benchmark scripts

Shell-driven cross-codec performance benchmarks that complement the in-process Swift XCTest benchmarks. These run external CLI tools (OpenJPH, Grok, Kakadu) directly via `subprocess.run`, eliminating a class of `swift test` runner instabilities observed when many `Process()` invocations stack up in a single test method.

## Canonical warm benchmark (v9.6+) — `cross_codec_warm_bench.py`

**The authoritative apples-to-apples cross-codec benchmark for any J2KSwift performance claim.** Required per release per `RELEASING.md`. Measures:

1. **PGM encode** (cross-codec, warm) — J2KSwift `--daemon` vs OpenJPH vs Grok vs Kakadu
2. **PGM decode** (cross-codec, warm) — same four codecs decoding the J2KSwift codestream
3. **DICOM encode** (J2KSwift-only) — DICOM PixelData → HT J2K, no cross-codec comparator since the others' CLIs are J2K-only

Warm = j2kd daemon installed + 2 warmup invocations per cell + 7 timed runs (median). Auto-detects host CPU + codec binary paths + daemon availability. Outputs markdown tables (paste into release notes) + JSON (for cross-host diffing). Runs ~5-10 minutes on M-series. See `Documentation/BENCHMARK.md` "Canonical warm cross-codec benchmark" section for rationale.

## Synthetic corpus generator — `generate_synthetic_corpus.py`

Produces the 13 synthetic medical fixtures (PGM + DICOM) that supplement the 7 real fixtures in `Tests/Fixtures/CrossCodec/`. Deterministic LCG-seeded — byte-identical across hosts. 8 modalities (MR/CT/XA/DX/PX/MG/NM/CR) × 4 size tiers (256² → 1280²). DICOM files are uncompressed Explicit VR Little Endian.

Combined corpus = 20 PGM + 13 DICOM = 33 fixtures, the minimum corpus for marketing-grade cross-codec claims.

## Legacy CLI benchmarks (cold; pre-v9.6)

| script | what it measures |
|---|---|
| `cross_codec_decode_cli.py` | Decode wall, **cold CLI** (full-process) for J2KSwift / OpenJPH / Grok / Kakadu on the 6-real-fixture corpus |
| `cross_codec_encode_cli.py` | Encode wall, **cold CLI**, HT-conformant lossless, same corpus |
| `cross_silicon_probe.py` | M2/M4 in-proc + `--daemon` walls (used for the v9.2 Path B M4 report) |

These are retained for historical reproduction and quick smoke-tests; new release claims should use `cross_codec_warm_bench.py` (warm methodology, 20-fixture corpus).

## Setup

External binaries — install via Homebrew (or Kakadu's site for `kdu_*`):

```bash
brew install openjph grokj2k          # ojph_compress / ojph_expand / grk_compress / grk_decompress
# Kakadu — download from https://kakadusoftware.com/ and install to /usr/local/bin/
```

Encode the corpus once before running the decode bench:

```bash
swift build -c release --product j2k
mkdir -p /tmp/v8_0_1_bench
for pgm in mr_study_002_instance_000100 ct_study_001_instance_000001 \
           mr_study_001_instance_000001 xa_study_001_instance_000001 \
           px_study_001_instance_000001 dx_study_002_instance_000001; do
    .build/release/j2k encode \
        -i Tests/Fixtures/CrossCodec/$pgm.pgm \
        -o /tmp/v8_0_1_bench/$pgm.j2k \
        --htj2k --lossless --quiet
done
```

## Run

```bash
python3 Scripts/benchmarks/cross_codec_decode_cli.py
python3 Scripts/benchmarks/cross_codec_encode_cli.py
```

Each prints a markdown-style table of median-of-5 ms-per-codec-per-fixture. Total runtime ~30 seconds for both.

## Latest results

See [`Documentation/BENCHMARK.md`](../../Documentation/BENCHMARK.md) for the consolidated v8.1.1 numbers and analysis.
