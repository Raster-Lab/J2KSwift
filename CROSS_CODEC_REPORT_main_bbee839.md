# Cross-Codec Benchmark — main @ bbee839 (post-v9.4.0)

**Date:** 2026-05-12
**Host:** Apple M2, macOS, Swift release build
**Branch:** `main` @ `bbee839` (Merge v9.5-research → main: v9.6 qstep cache + v9.8 SIGTRAP fix)
**Reference tag:** v9.4.0 (`5c90704`) — 14 files / +2,548 lines ahead on encoder pipeline + qstep cache
**Codecs compared:** J2KSwift (CLI cold + `--daemon` warm), OpenJPH 0.27.0, Grok, Kakadu HT
**Runners:**
- `Scripts/benchmarks/cross_codec_encode_cli.py` / `cross_codec_decode_cli.py` (cold, median-of-5)
- warm variants with `j2k --daemon` (median-of-7 after 3 warmups)

## Headline

**Daemon-encode large-fixture regression observed in v9.4.0 is gone.** Encoding DX (2800×2288) via `j2k --daemon`:

| Codec / mode                  | DX encode (ms) |
|-------------------------------|---------------:|
| v9.4.0 J2KSwift `--daemon`    |          146.0 |
| v9.4.0 J2KSwift CLI cold      |          108.1 |
| **main `bbee839` `--daemon`** |       **57.5** |
| main `bbee839` CLI cold       |          104.4 |
| OpenJPH                       |          110.3 |
| Grok HT                       |           44.3 |
| Kakadu HT                     |           19.5 |

Warm-encode DX is now **2.5× faster than v9.4.0 warm**, **1.8× faster than cold same-binary**, and beats OpenJPH by ~2×. Kakadu still leads encode by 2.9× on DX.

## Encode wall — CLI cold, median of 5

| fixture          | J2KSwift cold | OpenJPH | Grok HT | Kakadu HT |
|------------------|--------------:|--------:|--------:|----------:|
| MR-small 180²    |         38.31 |    4.67 |    6.10 |      3.06 |
| CT 512²          |         44.74 |    8.47 |    7.65 |      3.69 |
| MR 886²          |         43.93 |    8.54 |    9.31 |      4.04 |
| XA 1024²         |         52.36 |   19.66 |   12.20 |      5.40 |
| PX 2459×1316     |         72.18 |   56.57 |   25.81 |     12.24 |
| **DX 2800×2288** |    **104.40** |  110.34 |   44.27 |     19.50 |

## Encode wall — WARM via `j2k --daemon`, median of 7 after 3 warmups

| fixture          | J2KSwift `--daemon` | OpenJPH | Grok HT | Kakadu HT | vs cold |
|------------------|--------------------:|--------:|--------:|----------:|--------:|
| MR-small 180²    |                7.41 |    4.38 |    5.85 |      2.93 |   5.2×  |
| CT 512²          |               11.66 |    8.06 |    7.26 |      3.60 |   3.8×  |
| MR 886²          |               12.20 |    8.33 |    9.21 |      3.85 |   3.6×  |
| XA 1024²         |               16.28 |   19.48 |   12.26 |      5.46 |   3.2×  |
| PX 2459×1316     |               29.73 |   58.30 |   26.17 |     12.06 |   2.4×  |
| **DX 2800×2288** |           **57.46** |  113.82 |   45.50 |     20.28 |   1.8×  |

**Warm-encode beats OpenJPH on every fixture ≥ XA (4 of 6 fixtures).** Crossover with Kakadu remains pending — Kakadu still leads on every fixture, narrowest at PX (2.5×) and DX (2.8×).

## Decode wall — CLI cold, median of 5

| fixture          | J2KSwift cold | OpenJPH | Grok  | Kakadu |
|------------------|--------------:|--------:|------:|-------:|
| MR-small 180²    |          5.91 |    4.11 |  5.68 |   2.99 |
| CT 512²          |          9.17 |    6.88 |  6.73 |   4.13 |
| MR 886²          |         13.80 |    9.91 |  7.69 |   5.71 |
| XA 1024²         |         16.23 |   15.28 |  8.86 |   7.00 |
| PX 2459×1316     |         41.85 |   42.74 | 16.85 |  17.35 |
| **DX 2800×2288** |     **71.84** |   80.86 | 26.38 |  29.67 |

## Decode wall — WARM via `j2k --daemon`, median of 7 after 3 warmups

| fixture          | J2KSwift `--daemon` | OpenJPH | Grok  | Kakadu | vs cold |
|------------------|--------------------:|--------:|------:|-------:|--------:|
| MR-small 180²    |                8.81 |    4.67 |  5.62 |   2.97 |   0.67× |
| CT 512²          |               11.85 |    6.73 |  6.37 |   3.84 |   0.77× |
| MR 886²          |               17.13 |    8.96 |  7.40 |   5.70 |   0.81× |
| XA 1024²         |               21.07 |   15.36 |  8.91 |   7.20 |   0.77× |
| PX 2459×1316     |               45.27 |   42.68 | 16.26 |  17.24 |   0.92× |
| **DX 2800×2288** |           **75.16** |   81.68 | 26.26 |  29.04 |   0.96× |

**Decode is broadly flat between cold and warm.** XPC pixel-marshalling cost roughly cancels the cold-start savings on decode (raw output is larger than encoded input, so the daemon round-trip is expensive in the direction that matters). Cold decode is actually slightly faster on small fixtures.

This contrasts with encode, where warm wins everywhere — encode marshals raw pixels *in* (one direction) and gets compressed bytes *out* (small), so XPC cost is bounded by the input size only.

## Cold vs warm summary on DX

| stage  | cold (ms) | warm (ms) | warm/cold |
|--------|----------:|----------:|----------:|
| encode |    104.40 |     57.46 |     0.55× |
| decode |     71.84 |     75.16 |     1.05× |

## Notes

- J2KSwift CLI cold pays a ~30+ ms cold-start tax (Metal init, HT tables, MCT scratch pools). `--daemon` routes the call through the resident `j2kd` XPC service so the cold-start happens once at daemon launch, not per CLI invocation.
- The encode-warm DX win at `bbee839` is a genuine codepath change vs v9.4.0 — same daemon, same fixtures, same external codec versions; only the J2KSwift encoder pipeline differs. Likely candidates from `git diff v9.4.0..bbee839 -- Sources/J2KCodec/J2KEncoderPipeline.swift` (qstep cache integration, pipeline reshape).
- HT codestream bytes from J2KSwift round-trip bit-exactly through OpenJPH / Grok / Kakadu decoders per `HTTileParityMatrixTests` — performance differences here are speed-only.
- All numbers are full-process CLI walls (codec startup + work + write). Apples-to-apples user-facing wall clock.
