#!/usr/bin/env python3
"""Cold cross-codec CLI benchmark — fresh-process invocations, no daemon.

The COLD counterpart of `cross_codec_warm_bench.py`: identical corpus,
identical per-codec command lines, identical median-of-N protocol — except
the J2KSwift column runs `j2k` WITHOUT `--daemon`, so every invocation pays
the full Swift-runtime + Metal cold-start tax exactly as a one-shot CLI
user would. The external codecs are unchanged (their CLIs are always
fresh-process). OS file caches stay warm (we measure process-cold, not
boot-cold — the comparison every codec column shares).

Usage:
    python3 Scripts/benchmarks/cross_codec_cold_cli_bench.py [--runs N] [--output PATH]
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cross_codec_warm_bench as warm


def cmd_j2kswift_encode_cold(src: str):
    def make(out: str):
        return [warm.J2K_BIN, "encode", "-i", src, "-o", out,
                "--htj2k", "--lossless", "--quiet"]
    return make


def cmd_j2kswift_decode_cold(src: str):
    def make(out: str):
        return [warm.J2K_BIN, "decode", "-i", src, "-o", out, "--quiet"]
    return make


def main():
    warm.cmd_j2kswift_encode = cmd_j2kswift_encode_cold
    warm.cmd_j2kswift_decode = cmd_j2kswift_decode_cold

    import argparse
    import json
    ap = argparse.ArgumentParser(description="J2KSwift COLD cross-codec CLI benchmark")
    ap.add_argument("--runs", type=int, default=7)
    ap.add_argument("--warmups", type=int, default=2,
                    help="Discarded fresh-process invocations (file-cache settling)")
    ap.add_argument("--output", type=str, default=None)
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()
    # Inject the attributes run_benchmark reads but our parser doesn't define.
    args.isolated = False
    args.in_proc = False

    print("=== COLD MODE: J2KSwift column is one-shot `j2k` (NO daemon) — "
          "every invocation pays full process cold-start ===")
    results = warm.run_benchmark(args)
    if results is not None:
        results["mode"] = "cold-cli"
    if args.output and results is not None:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults written to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
