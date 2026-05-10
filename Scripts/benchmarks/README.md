# Cross-codec benchmark scripts

Shell-driven cross-codec performance benchmarks that complement the in-process Swift XCTest benchmarks. These run external CLI tools (OpenJPH, Grok, Kakadu) directly via `subprocess.run`, eliminating a class of `swift test` runner instabilities observed when many `Process()` invocations stack up in a single test method.

| script | what it measures |
|---|---|
| `cross_codec_decode_cli.py` | Decode wall (full-process) for J2KSwift CLI / OpenJPH / Grok / Kakadu on the medical corpus |
| `cross_codec_encode_cli.py` | Encode wall (full-process), HT-conformant lossless, on the same corpus |

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
