#!/usr/bin/env python3
import subprocess, time, statistics, os, tempfile

J2K  = "/Users/raster/Documents/raster/J2KSwift/.build/release/j2k"
OJPH = "/opt/homebrew/bin/ojph_compress"
GROK = "/opt/homebrew/bin/grk_compress"
KDU  = "/usr/local/bin/kdu_compress"

FIXTURES = [
    ("mr_study_002_instance_000100", "MR-small 180²"),
    ("ct_study_001_instance_000001", "CT 512²"),
    ("mr_study_001_instance_000001", "MR 886²"),
    ("xa_study_001_instance_000001", "XA 1024²"),
    ("px_study_001_instance_000001", "PX 2459×1316"),
    ("dx_study_002_instance_000001", "DX 2800×2288"),
]

FIXTURE_DIR = "/Users/raster/Documents/raster/J2KSwift/Tests/Fixtures/CrossCodec"
RUNS = 5

def time_one(cmd, output_path):
    try:
        if os.path.exists(output_path):
            os.remove(output_path)
        t0 = time.perf_counter()
        r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        t1 = time.perf_counter()
        if r.returncode != 0:
            return None
        if not os.path.exists(output_path):
            return None
        return (t1 - t0) * 1000.0
    except Exception:
        return None

def bench(cmd_factory, output_ext):
    samples = []
    out = f"/tmp/v8_perf_encode_out{output_ext}"
    for _ in range(RUNS):
        cmd = cmd_factory(out)
        ms = time_one(cmd, out)
        if ms is None:
            return "(error)"
        samples.append(ms)
    return f"{statistics.median(samples):.2f} ms"

print(f"=== v8.1.1 cross-codec ENCODE wall — HT-conformant lossless, median of {RUNS} CLI invocations (Apple M2) ===\n")
print(f"{'fixture':<18} | {'J2KSwift CLI':>14} | {'OpenJPH':>14} | {'Grok HT (.jph)':>14} | {'Kakadu HT':>14}")
print("-" * 88)

for stem, label in FIXTURES:
    src = f"{FIXTURE_DIR}/{stem}.pgm"
    if not os.path.exists(src):
        print(f"{label:<18} | {'(missing)':>14} | {'':>14} | {'':>14} | {'':>14}")
        continue
    j2k  = bench(lambda o: [J2K, "encode", "-i", src, "-o", o, "--htj2k", "--lossless", "--quiet"], ".j2k")
    ojph = bench(lambda o: [OJPH, "-i", src, "-o", o, "-reversible", "true"], ".j2k")
    grok = bench(lambda o: [GROK, "-i", src, "-o", o, "-M", "64"], ".jph")
    kdu  = bench(lambda o: [KDU, "-i", src, "-o", o, "Creversible=yes", "Cmodes=HT", "-quiet"], ".j2k")
    print(f"{label:<18} | {j2k:>14} | {ojph:>14} | {grok:>14} | {kdu:>14}")

print()
print("Notes:")
print("  • All four columns are CLI walls — full-process invocations (codec startup +")
print("    encode + write). All produce HT-conformant lossless 5/3 codestreams.")
print("  • Output formats: J2KSwift/Kakadu = .j2k; OpenJPH = .j2k; Grok HT = .jph (Grok")
print("    requires the .jph extension to honour -M 64 HT-mode flag).")
print("  • J2KSwift CLI pays Metal cold-start tax (~50 ms once per process). The")
print("    optional `j2kd` daemon doesn't currently wire encode through XPC (decode-")
print("    only in v8.0.x); encode CLI cold is the apples-to-apples row here.")
print("  • Codestream bytes are NOT byte-identical across codecs on encode (same")
print("    pixels round-trip via every external decoder per HTTileParityMatrixTests,")
print("    but each codec packs codeblocks differently within the spec).")
