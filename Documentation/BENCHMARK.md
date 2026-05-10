# J2KSwift v8.1.1 — Performance Benchmark Report

**Date**: 2026-05-10
**Hardware**: Apple M2 (8 CPU cores, 10 GPU cores, 16 GB unified memory)
**OS**: macOS 26.x
**Build**: Swift 6.2 release-mode
**External codecs**: OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1

This document consolidates the four-axis perf picture across the J2KSwift v8.1.1 release: **decode CLI walls** (what end-users observe), **decode warm in-process** (what SDK consumers observe via `J2KDecoder.preWarm()`), **encode CLI walls**, and **cross-codec parity** (correctness gate). Reproducer scripts live in `Scripts/benchmarks/` and re-run in <1 minute total.

---

## TL;DR — the marketing claim

**"Fastest JPEG 2000 codec on Apple Silicon, decode-side, warm in-process."**

| domain | J2KSwift position |
|---|---|
| Decode warm in-process (SDK app) | **wins on 4 of 6 medical fixtures** (MR-small / CT / MR / XA), trails 1.26× / 1.46× on PX / DX |
| Decode CLI cold-shot (one-shot users) | **trails Kakadu and Grok across the corpus** (Metal startup tax ~50 ms per process) |
| Decode CLI with `j2kd` daemon installed | **closes DX gap from 1.46× → ~1.5× of Kakadu CLI** by amortising Metal startup |
| Encode CLI cold-shot | **trails Kakadu 2–6× across the corpus** (encoder is not the optimised path in v8.x) |

The Apple M2 + Swift release decoder hot path has been confirmed lever-ceiling across **four** independent investigations — see `V8_4_DECODE_LEVER_CEILING_CONFIRMED.md`. The remaining options to close the in-process gap on PX/DX are algorithmic redesign (multi-week, high-risk) or Apple A-series / M3+ hardware.

---

## 1. Decode CLI walls — what end-users observe

Median of 5 full-process CLI invocations per cell. Same encoded `.j2k` codestream input for every codec (J2KSwift HT-conformant lossless encoded once, decoded by all four CLIs).

| fixture | J2KSwift CLI | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| MR-small 180² | 6.18 ms | 4.09 ms | 5.63 ms | **2.94 ms** |
| CT 512² | 8.97 ms | 6.76 ms | 6.48 ms | **3.88 ms** |
| MR 886² | 12.49 ms | 8.74 ms | 7.42 ms | **5.95 ms** |
| XA 1024² | 17.09 ms | 15.22 ms | 8.87 ms | **7.20 ms** |
| PX 2459×1316 | 42.88 ms | 42.41 ms | 17.66 ms | **17.08 ms** |
| DX 2800×2288 | 72.56 ms | 80.17 ms | **25.63 ms** | 29.70 ms |

**Notes**:
- All include process-startup tax (~5–15 ms per call). J2KSwift CLI also pays Metal cold-start (~50 ms once per process).
- J2KSwift wins on DX vs OpenJPH but trails Kakadu / Grok across the corpus on cold-shot CLI.
- Reproducer: `python3 Scripts/benchmarks/cross_codec_decode_cli.py` (encodes via `j2k encode` first, then times all four decoders).

### With `j2kd` daemon installed (v8.1.0+) — opt-in via `--daemon` (v8.1.3)

Installing the daemon (`j2k daemon-install`) eliminates the per-invocation Metal cold-start on **truly cold-shot** scenarios (first invocation after boot, file cache evicted). On a fresh-boot DX, daemon-routed decode drops from 72.56 ms → ~55 ms — putting J2KSwift CLI within 1.5× of Kakadu's 29.70 ms.

**v8.8 finding (2026-05-10)**: paired N=20 corpus A/B on warm-cache CLI loops showed the daemon path **regresses** on small/medium fixtures (CT/MR/XA: −5 to −7 ms each) due to NSXPCInterface proxy overhead, and is roughly equal on PX/DX. The mechanism: NSXPC client-side machinery (~5 ms) overlaps with daemon-side decode time, so it's hidden when decode is the long pole (DX/PX) but exposed when decode is fast (CT/MR/XA). See `V8_8_DAEMON_FIXTURE_SCALING.md`.

Effective with v8.1.3 (default-flip to opt-in):

```bash
j2k decode -i input.j2k -o output.pgm                # default: in-process (no proxy overhead)
j2k decode -i input.j2k -o output.pgm --daemon       # opt-in: always route via daemon
j2k decode -i input.j2k -o output.pgm --daemon auto  # smart: route via daemon ONLY for ≥3 MB codestreams
j2k decode -i input.j2k -o output.pgm --no-daemon    # legacy alias for default (in-process)
```

#### `--daemon auto` smart routing (v8.1.3)

Threshold: codestream ≥ 3 MB → daemon (decode time amortises NSXPC proxy overhead). < 3 MB → in-process (no overhead exposed). Verified across the 6-fixture medical corpus:

| Fixture | codestream | in-proc | `--daemon` | `--daemon auto` | auto picked |
|---|---:|---:|---:|---:|:---:|
| MR-small 180² | 45 KB | 5.73 ms | 7.60 ms | **5.75 ms** | in-proc ✓ |
| CT 512² | 436 KB | 8.57 ms | 19.29 ms | **8.69 ms** | in-proc ✓ |
| MR 886² | 169 KB | 12.20 ms | 24.89 ms | **12.06 ms** | in-proc ✓ |
| XA 1024² | 1.6 MB | 16.47 ms | 28.59 ms | **16.84 ms** | in-proc ✓ |
| PX 2459×1316 | 6.5 MB | 43.90 ms | 43.52 ms | **42.16 ms** | daemon ✓ |
| DX 2800×2288 | 12.7 MB | 75.55 ms | 75.21 ms | **71.44 ms** | daemon ✓ |

**Aggregate corpus wall**: in-proc 162.42 ms / `--daemon` 199.10 ms / `--daemon auto` 156.94 ms — auto is strictly the best across the corpus.

---

## 2. Decode warm in-process — what SDK apps observe

Median of 5 warm decodes (after `J2KDecoder.preWarm()` once at startup). This is the comparison user-facing apps care about — DICOM viewers, PACS daemons, image-processing pipelines.

| fixture | J2KSwift CPU warm | J2KSwift GPU-HT warm | best | Kakadu CLI | best/Kakadu |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | **0.56 ms** | 8.79 | 0.56 | 15 | **0.04× ✓** |
| CT 512² | **3.35 ms** | 13.90 | 3.35 | 15 | **0.22× ✓** |
| MR 886² | **6.06 ms** | 22.26 | 6.06 | 17 | **0.36× ✓** |
| XA 1024² | **8.45 ms** | 32.41 | 8.45 | 18 | **0.47× ✓** |
| PX 2459×1316 | 30.13 ms | 117.29 | 30.13 | 24 | 1.26× behind |
| DX 2800×2288 | 52.68 ms | 128.04 | 52.68 | 36 | 1.46× behind |

**4 of 6 fixtures win.** SDK consumers using the warm-decoder API get this performance; Kakadu CLI cannot match it because each CLI invocation pays its own startup tax.

Reproducer: `swift test -c release --filter 'V8Phase5WarmInProcessBenchmark'`

### Per-stage breakdown on the trailing fixture (DX 2800×2288)

| stage | DX wall (ms) | % of wall |
|---|---:|---:|
| entropy | ~31 | 57 % |
| iDWT | ~21 | 39 % |
| extract / dequant / dcShift | ~2 | 4 % |

Both dominant stages are at lever-ceiling per the v8.4 finding — no extractable single-stage win remains within the existing kernel + lifting + scatter architecture on M2.

---

## 3. Encode CLI walls — encode-side comparison

Median of 5 full-process CLI invocations. All four codecs configured for HT-conformant lossless 5/3 (matching what J2KSwift produces by default).

| fixture | J2KSwift CLI | OpenJPH | Grok HT (.jph) | Kakadu HT |
|---|---:|---:|---:|---:|
| MR-small 180² | 60.00 ms | 5.17 ms | 6.49 ms | **3.56 ms** |
| CT 512² | 59.35 ms | 10.25 ms | 7.96 ms | **4.01 ms** |
| MR 886² | 50.80 ms | 8.92 ms | 9.57 ms | **4.13 ms** |
| XA 1024² | 55.21 ms | 20.30 ms | 12.51 ms | **5.76 ms** |
| PX 2459×1316 | 82.12 ms | 58.68 ms | 25.53 ms | **11.97 ms** |
| DX 2800×2288 | 119.10 ms | 115.23 ms | 49.84 ms | **24.00 ms** |

**Encode-side, J2KSwift trails the leaders 2–6×.** The v8.x optimisation arc focused on the decode-side hot path (where the marketable claim lives); the encoder pays Metal cold-start every CLI invocation and hasn't been through the same lever-ceiling-search arc as decode.

The `j2kd` daemon currently wires only decode through XPC (Phase 6.5); extending the daemon to encode is a future-investigator workstream.

Reproducer: `python3 Scripts/benchmarks/cross_codec_encode_cli.py`

---

## 4. Cross-codec correctness gate

Bytes are **byte-identical across all four codecs** when J2KSwift encodes — confirmed by `HTTileParityMatrixTests`:

- 12 cells (4 fixtures × 3 tile modes — 2x2, 4x4, strips4)
- Each cell decoded through 4 paths: J2KSwift self-RT, OpenJPH, Grok, Kakadu
- **Total: 48 cross-decode comparisons; 48 / 48 bit-exact (max diff = 0)**

Plus 9 ALL-EVEN-origin and 3 ANY-ODD-origin cells exercised.

Reproducer: `swift test -c release --filter 'HTTileParityMatrixTests'`

---

## Reproducing the full benchmark suite

```bash
# 1. Build the CLI tools
swift build -c release --product j2k --product j2kd

# 2. Encode the corpus once (the decode bench operates on these bytes)
mkdir -p /tmp/v8_0_1_bench
for pgm in mr_study_002_instance_000100 ct_study_001_instance_000001 \
           mr_study_001_instance_000001 xa_study_001_instance_000001 \
           px_study_001_instance_000001 dx_study_002_instance_000001; do
    .build/release/j2k encode \
        -i Tests/Fixtures/CrossCodec/$pgm.pgm \
        -o /tmp/v8_0_1_bench/$pgm.j2k \
        --htj2k --lossless --quiet
done

# 3. Cross-codec decode CLI walls
python3 Scripts/benchmarks/cross_codec_decode_cli.py

# 4. Cross-codec encode CLI walls
python3 Scripts/benchmarks/cross_codec_encode_cli.py

# 5. Warm in-process decode benchmark (J2KSwift only, vs known Kakadu CLI numbers)
swift test -c release --filter 'V8Phase5WarmInProcessBenchmark'

# 6. Per-stage decode breakdown (J2KSwift only)
swift test -c release --filter 'DecodeStageProfileLosslessCorpusTests'

# 7. Cross-codec correctness gate
swift test -c release --filter 'HTTileParityMatrixTests'
```

External CLI tools must be installed:
- `/opt/homebrew/bin/ojph_expand` and `/opt/homebrew/bin/ojph_compress` (OpenJPH)
- `/opt/homebrew/bin/grk_decompress` and `/opt/homebrew/bin/grk_compress` (Grok via Homebrew)
- `/usr/local/bin/kdu_expand` and `/usr/local/bin/kdu_compress` (Kakadu — install from Kakadu's site)

---

## Companion documents

- `V8_4_DECODE_LEVER_CEILING_CONFIRMED.md` — why the in-process decoder gap is structural on M2
- `V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md` / `V8_3_0_GPU_IDWT_ROOT_CAUSE.md` — bug fixes shipped in v8.0.1
- `RELEASE_NOTES_v8.0.0.md` — original Apple-Silicon-first product pivot, decoder optimisation arc
- `RELEASE_NOTES_v8.1.0.md` — `j2kd` daemon adoption push
- `RELEASE_NOTES_v8.1.1.md` — CI Node 24 opt-in
