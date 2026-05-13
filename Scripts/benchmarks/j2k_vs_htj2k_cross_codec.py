#!/usr/bin/env python3
"""J2K Part 1 (legacy EBCOT) vs HTJ2K Part 15 cross-codec comparison.

Measures encode wall + decode wall + output bytes (compression ratio)
across the 5 codecs that support these modes:

  | codec      | J2K Part 1 (EBCOT) | HTJ2K Part 15 (HT) |
  |---         |--                  |--                   |
  | J2KSwift   | yes (`j2k encode --lossless`)            | yes (`j2k encode --htj2k --lossless`) |
  | OpenJPEG   | yes (`opj_compress`)                     | (HT support incomplete in OSS build)  |
  | OpenJPH    | (HT-only by design)                      | yes (`ojph_compress -reversible true`) |
  | Grok       | yes (`grk_compress`)                     | yes (`grk_compress -M 64`, .jph)      |
  | Kakadu     | yes (`kdu_compress Creversible=yes`)     | yes (Creversible=yes Cmodes=HT)       |

Methodology: cold CLI per call (no daemon), median of 5 + 1 warmup,
release-mode Apple M2. Uses the 7-fixture real medical corpus (the same
fixtures the canonical warm bench uses). 16-bit lossless throughout.

Why cold CLI: not all codecs have a daemon equivalent. To compare J2K
vs HTJ2K apples-to-apples on the same per-call shape, all codecs run
cold. J2KSwift pays its Swift+Metal init tax each call; that tax is
the same whether the output is J2K or HTJ2K, so the within-J2KSwift
J2K-vs-HTJ2K comparison is still meaningful.

Usage:
    python3 Scripts/benchmarks/j2k_vs_htj2k_cross_codec.py
    python3 Scripts/benchmarks/j2k_vs_htj2k_cross_codec.py --output bench.json
"""
from __future__ import annotations
import argparse
import json
import os
import statistics
import subprocess
import time
from datetime import datetime

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FIXTURE_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec")
J2K_BIN = os.path.join(REPO_ROOT, ".build/release/j2k")

OPJ_C = "/opt/homebrew/bin/opj_compress"
OPJ_D = "/opt/homebrew/bin/opj_decompress"
OJPH_C = "/opt/homebrew/bin/ojph_compress"
OJPH_D = "/opt/homebrew/bin/ojph_expand"
GROK_C = "/opt/homebrew/bin/grk_compress"
GROK_D = "/opt/homebrew/bin/grk_decompress"
KDU_C = "/usr/local/bin/kdu_compress"
KDU_D = "/usr/local/bin/kdu_expand"

FIXTURES = [
    ("MR-small 180²", "mr_study_002_instance_000100.pgm"),
    ("CT 512² (1)",   "ct_study_001_instance_000001.pgm"),
    ("CT 512² (2)",   "ct_study_003_instance_000050.pgm"),
    ("MR 886²",       "mr_study_001_instance_000001.pgm"),
    ("XA 1024²",      "xa_study_001_instance_000001.pgm"),
    ("PX 2459×1316",  "px_study_001_instance_000001.pgm"),
    ("DX 2800×2288",  "dx_study_002_instance_000001.pgm"),
]


def time_one(cmd: list[str], out: str | None = None) -> float | None:
    try:
        if out and os.path.exists(out):
            os.remove(out)
        t0 = time.perf_counter()
        r = subprocess.run(cmd, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=120)
        if r.returncode != 0:
            return None
        if out and not os.path.exists(out):
            return None
        return (time.perf_counter() - t0) * 1000.0
    except Exception:
        return None


def bench(cmd_factory, out_path: str, runs: int = 5, warmups: int = 1) -> dict | None:
    for _ in range(warmups):
        time_one(cmd_factory(out_path), out_path)
    samples = []
    for _ in range(runs):
        ms = time_one(cmd_factory(out_path), out_path)
        if ms is None:
            return None
        samples.append(ms)
    samples.sort()
    return {
        "median": samples[len(samples) // 2],
        "min": samples[0],
        "max": samples[-1],
        "samples": samples,
        "output_bytes": os.path.getsize(out_path) if os.path.exists(out_path) else None,
    }


# Codec factories (encode + decode + output extension per mode)
def make_encoders(src: str):
    return {
        # ----- J2K Part 1 (legacy EBCOT) -----
        ("J2KSwift",  "Part1"): (
            lambda o: [J2K_BIN, "encode", "-i", src, "-o", o,
                       "--lossless", "--no-daemon", "--quiet"],
            ".j2k",
        ),
        ("OpenJPEG",  "Part1"): (
            lambda o: [OPJ_C, "-i", src, "-o", o],
            ".j2k",
        ),
        ("Grok",      "Part1"): (
            lambda o: [GROK_C, "-i", src, "-o", o],
            ".j2k",
        ),
        ("Kakadu",    "Part1"): (
            lambda o: [KDU_C, "-i", src, "-o", o,
                       "Creversible=yes", "-quiet"],
            ".j2k",
        ),
        # ----- HTJ2K Part 15 -----
        ("J2KSwift",  "Part15"): (
            lambda o: [J2K_BIN, "encode", "-i", src, "-o", o,
                       "--htj2k", "--lossless", "--no-daemon", "--quiet"],
            ".j2k",
        ),
        ("OpenJPH",   "Part15"): (
            lambda o: [OJPH_C, "-i", src, "-o", o, "-reversible", "true"],
            ".j2k",
        ),
        ("Grok",      "Part15"): (
            lambda o: [GROK_C, "-i", src, "-o", o, "-M", "64"],
            ".jph",
        ),
        ("Kakadu",    "Part15"): (
            lambda o: [KDU_C, "-i", src, "-o", o,
                       "Creversible=yes", "Cmodes=HT", "-quiet"],
            ".j2k",
        ),
    }


def make_decoders(src: str):
    """Decoder factories. src = a J2K/JPH file already produced."""
    return {
        "J2KSwift": (lambda o: [J2K_BIN, "decode", "-i", src, "-o", o,
                                "--no-daemon", "--quiet"], ".pgm"),
        "OpenJPEG": (lambda o: [OPJ_D, "-i", src, "-o", o], ".pgm"),
        "OpenJPH":  (lambda o: [OJPH_D, "-i", src, "-o", o], ".pgm"),
        "Grok":     (lambda o: [GROK_D, "-i", src, "-o", o], ".pgm"),
        "Kakadu":   (lambda o: [KDU_D, "-i", src, "-o", o], ".pgm"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=str, default=None)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--warmups", type=int, default=1)
    args = ap.parse_args()

    scratch = "/tmp/j2k_vs_htj2k"
    os.makedirs(scratch, exist_ok=True)

    print(f"=== J2K Part 1 (legacy EBCOT) vs HTJ2K Part 15 cross-codec ===")
    print(f"Host: Apple M2 (Mac14_2), release-mode J2KSwift v9.5.2")
    print(f"Cold CLI per call (no daemon); median of {args.runs} after {args.warmups} warmup")
    print(f"Date: {datetime.now().isoformat(timespec='seconds')}")
    print()

    # === Encode pass: every codec × mode × fixture ===
    encode_results: dict = {}  # key: (fixture, codec, mode) → result dict
    print("Encoding (cold CLI; medians):")
    print(f"{'Fixture':<18}  {'Codec':<10}  {'Mode':<7}  {'enc_ms':>8}  {'bytes':>10}  {'bpp':>6}")
    for label, fname in FIXTURES:
        src = os.path.join(FIXTURE_DIR, fname)
        if not os.path.exists(src):
            continue
        # Need pixel count for bpp calc; PGM header parse
        with open(src, "rb") as f:
            hdr = f.read(64)
        # P5\nW H\nMAX\n binary…
        try:
            parts = hdr.decode("ascii", errors="ignore").split()
            w = int(parts[1]); h = int(parts[2])
        except Exception:
            w = h = 0
        pixels = w * h
        for (codec, mode), (factory, ext) in make_encoders(src).items():
            outp = os.path.join(scratch, f"enc_{codec}_{mode}_{fname}{ext}")
            r = bench(factory, outp, args.runs, args.warmups)
            encode_results[(label, codec, mode)] = (r, outp, ext)
            if r is None:
                print(f"  {label:<18}  {codec:<10}  {mode:<7}  {'(err)':>8}  {'-':>10}  {'-':>6}")
            else:
                bpp = (r["output_bytes"] * 8 / pixels) if pixels and r["output_bytes"] else 0
                print(f"  {label:<18}  {codec:<10}  {mode:<7}  {r['median']:>8.2f}  "
                      f"{r['output_bytes']:>10}  {bpp:>6.2f}")
    print()

    # === Decode pass: decode the J2KSwift output of each mode with each decoder ===
    # Why J2KSwift output: it is bit-exact to OpenJPH/Kakadu encoders (parity matrix
    # tests confirm), so using J2KSwift bytes is fair AND lets each decoder be
    # measured against the SAME input.
    print("Decoding (cold CLI; medians; decoder reads J2KSwift-encoded input):")
    print(f"{'Fixture':<18}  {'Codec':<10}  {'Mode':<7}  {'dec_ms':>8}")
    decode_results: dict = {}
    for label, fname in FIXTURES:
        for mode in ("Part1", "Part15"):
            j2k_out_key = ("J2KSwift", mode)
            r_enc_tuple = encode_results.get((label, *j2k_out_key))
            if r_enc_tuple is None or r_enc_tuple[0] is None:
                continue
            j2k_input = r_enc_tuple[1]
            for codec, (factory, dext) in make_decoders(j2k_input).items():
                # OpenJPH can't decode Part1; OpenJPEG limited HT support — skip
                # combinations that don't make sense
                if codec == "OpenJPH" and mode == "Part1":
                    continue
                if codec == "OpenJPEG" and mode == "Part15":
                    # opj_decompress claims HT support in v2.5+, but the OSS
                    # build may not be reliable. Skip for clarity.
                    continue
                outp = os.path.join(scratch, f"dec_{codec}_{mode}_{fname}{dext}")
                rd = bench(factory, outp, args.runs, args.warmups)
                decode_results[(label, codec, mode)] = rd
                if rd is None:
                    print(f"  {label:<18}  {codec:<10}  {mode:<7}  {'(err)':>8}")
                else:
                    print(f"  {label:<18}  {codec:<10}  {mode:<7}  {rd['median']:>8.2f}")
    print()

    # === Compression ratio summary: HTJ2K / J2K Part 1 bytes per codec ===
    print("Compression ratio (HTJ2K bytes / J2K Part 1 bytes) — values >1 mean HTJ2K is larger:")
    print(f"{'Fixture':<18}  {'J2KSwift':>10}  {'Grok':>10}  {'Kakadu':>10}")
    for label, _ in FIXTURES:
        row = [label]
        for codec in ("J2KSwift", "Grok", "Kakadu"):
            r_p1 = encode_results.get((label, codec, "Part1"))
            r_p15 = encode_results.get((label, codec, "Part15"))
            if r_p1 and r_p1[0] and r_p15 and r_p15[0]:
                ratio = r_p15[0]["output_bytes"] / r_p1[0]["output_bytes"]
                row.append(f"{ratio:.3f}×")
            else:
                row.append("-")
        print(f"  {row[0]:<18}  {row[1]:>10}  {row[2]:>10}  {row[3]:>10}")
    print()

    if args.output:
        # Strip non-serializable parts
        encode_serial = {
            f"{k[0]}|{k[1]}|{k[2]}": v[0]
            for k, v in encode_results.items() if v[0]
        }
        decode_serial = {
            f"{k[0]}|{k[1]}|{k[2]}": v
            for k, v in decode_results.items() if v
        }
        with open(args.output, "w") as f:
            json.dump({
                "captured_at": datetime.now().isoformat(timespec="seconds"),
                "host": "Apple M2 Mac14_2",
                "j2kswift_version": "9.5.2",
                "runs": args.runs,
                "warmups": args.warmups,
                "encode": encode_serial,
                "decode": decode_serial,
            }, f, indent=2)
        print(f"Results written to {args.output}")


if __name__ == "__main__":
    main()
