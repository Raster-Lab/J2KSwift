#!/usr/bin/env python3
import subprocess, time, statistics, os, sys

J2K  = "/Users/raster/Documents/raster/J2KSwift/.build/release/j2k"
OJPH = "/opt/homebrew/bin/ojph_expand"
GROK = "/opt/homebrew/bin/grk_decompress"
KDU  = "/usr/local/bin/kdu_expand"

FIXTURES = [
    ("mr_study_002_instance_000100", "MR-small 180²"),
    ("ct_study_001_instance_000001", "CT 512²"),
    ("mr_study_001_instance_000001", "MR 886²"),
    ("xa_study_001_instance_000001", "XA 1024²"),
    ("px_study_001_instance_000001", "PX 2459×1316"),
    ("dx_study_002_instance_000001", "DX 2800×2288"),
]

OUT = "/tmp/v8_0_1_decoded.pgm"
RUNS = 5

def time_one(cmd):
    try:
        if os.path.exists(OUT):
            os.remove(OUT)
        t0 = time.perf_counter()
        r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t1 = time.perf_counter()
        if r.returncode != 0:
            return None
        return (t1 - t0) * 1000.0
    except Exception:
        return None

def bench(cmd):
    samples = []
    for _ in range(RUNS):
        ms = time_one(cmd)
        if ms is None:
            return "(error)"
        samples.append(ms)
    return f"{statistics.median(samples):.2f} ms"

print(f"=== v8.0.1 cross-codec decode wall — median of {RUNS} CLI invocations (Apple M2) ===\n")
print(f"{'fixture':<18} | {'J2KSwift CLI':>14} | {'OpenJPH':>14} | {'Grok':>14} | {'Kakadu':>14}")
print("-" * 84)

for stem, label in FIXTURES:
    src = f"/tmp/v8_0_1_bench/{stem}.j2k"
    if not os.path.exists(src):
        print(f"{label:<18} | {'(missing)':>14} | {'':>14} | {'':>14} | {'':>14}")
        continue
    j2k = bench([J2K, "decode", "-i", src, "-o", OUT, "--quiet"])
    ojph = bench([OJPH, "-i", src, "-o", OUT])
    grok = bench([GROK, "-i", src, "-o", OUT])
    kdu = bench([KDU, "-i", src, "-o", OUT])
    print(f"{label:<18} | {j2k:>14} | {ojph:>14} | {grok:>14} | {kdu:>14}")

print()
print("Notes:")
print("  • All four columns are CLI walls — full-process invocations (codec startup +")
print("    decode + write). Apples-to-apples user-facing comparison.")
print("  • J2KSwift CLI pays Metal cold-start tax (~50 ms once per process). The")
print("    optional `j2kd` XPC daemon eliminates it (see RELEASE_NOTES_v8.0.0.md).")
print("  • Codestream bytes are byte-identical across all four codecs — confirmed")
print("    by HTTileParityMatrixTests (33/33 cross-decode comparisons bit-exact).")
