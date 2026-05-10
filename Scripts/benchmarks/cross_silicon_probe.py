#!/usr/bin/env python3
"""
v9.0 Path C — cross-silicon performance probe.

Reproducible benchmark for running the full J2KSwift cross-codec
performance test on different Apple Silicon chips (M2 / M3 / M3 Pro /
M3 Max / M4 / M4 Pro / M4 Max / M4 Ultra / iPhone A-series).

Usage:
    # Run on the current machine; captures system identifier
    # automatically and writes structured JSON output.
    python3 Scripts/benchmarks/cross_silicon_probe.py

    # Compare two prior runs:
    python3 Scripts/benchmarks/cross_silicon_probe.py compare \
        results-M2.json results-M4.json

What it measures:
    - Encode wall (HT-conformant lossless) for J2KSwift in-proc,
      J2KSwift --daemon auto, OpenJPH, Grok, Kakadu — full medical corpus
    - Decode wall for all four codecs — same corpus
    - Cross-codec parity check (J2KSwift codestream MD5 vs prior version)
    - System metadata: silicon model, OS version, J2KSwift version

Output:
    JSON file at:
        ./benchmark-results-{silicon}-{j2kswift_version}-{date}.json

    Structured for easy diffing across silicon generations to identify
    where each chip's curve falls relative to M2 (the v8.x reference).

Methodology note:
    The probe captures system state (vm.compressor_bytes_used, pages_free,
    load_1min) at startup. On a memory-pressured M2 with 9+ GB in the
    compressor, every CLI subprocess invocation pays ~30 ms of extra
    exec/page-swap tax — so absolute numbers reflect stressed-state
    measurement, not idle-system best-case. For cross-silicon
    comparability, run on a fresh-rebooted system with <2 GB compressor
    usage and >500 MB free pages.
"""
from __future__ import annotations
import subprocess, time, statistics, os, sys, json, hashlib, platform
import shutil
from pathlib import Path
from datetime import datetime

# ---- Codec discovery ----

def which_codec(*names: str) -> str | None:
    """Find first available codec binary."""
    for n in names:
        p = shutil.which(n)
        if p:
            return p
    return None

J2K_BUILD_DIR = Path(__file__).resolve().parents[2] / ".build" / "release"
J2K = str(J2K_BUILD_DIR / "j2k")
OJPH_E = which_codec("ojph_compress")
OJPH_D = which_codec("ojph_expand")
GROK_E = which_codec("grk_compress")
GROK_D = which_codec("grk_decompress")
KDU_E = which_codec("kdu_compress")
KDU_D = which_codec("kdu_expand")

FIXTURE_DIR = str(Path(__file__).resolve().parents[2] / "Tests" / "Fixtures" / "CrossCodec")

FIXTURES = [
    ("mr_study_002_instance_000100", "MR-small 180²"),
    ("ct_study_001_instance_000001", "CT 512²"),
    ("mr_study_001_instance_000001", "MR 886²"),
    ("xa_study_001_instance_000001", "XA 1024²"),
    ("px_study_001_instance_000001", "PX 2459×1316"),
    ("dx_study_002_instance_000001", "DX 2800×2288"),
]


def system_info() -> dict:
    """Capture silicon model + OS info for cross-system comparison."""
    info = {"date": datetime.utcnow().isoformat() + "Z", "platform": platform.platform()}
    try:
        # macOS hardware identifier (e.g., "Mac15,7" for M3, "Mac14,2" for M2)
        info["hw_model"] = subprocess.check_output(
            ["sysctl", "-n", "hw.model"], text=True).strip()
    except Exception:
        info["hw_model"] = "unknown"
    try:
        # Marketing name like "Apple M2" / "Apple M3 Pro"
        info["cpu_brand"] = subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    except Exception:
        info["cpu_brand"] = "unknown"
    try:
        info["mem_gb"] = int(subprocess.check_output(
            ["sysctl", "-n", "hw.memsize"], text=True).strip()) // (1024 ** 3)
    except Exception:
        info["mem_gb"] = 0
    try:
        info["cores_perf"] = int(subprocess.check_output(
            ["sysctl", "-n", "hw.perflevel0.physicalcpu"], text=True).strip())
        info["cores_eff"] = int(subprocess.check_output(
            ["sysctl", "-n", "hw.perflevel1.physicalcpu"], text=True).strip())
    except Exception:
        info["cores_perf"] = 0
        info["cores_eff"] = 0
    try:
        info["j2kswift_version"] = subprocess.check_output(
            [J2K, "version"], text=True).strip()
    except Exception:
        info["j2kswift_version"] = "unknown"

    # Memory pressure indicators — large vm.compressor_bytes_used or low free
    # pages slow every CLI invocation by ~30 ms (page-swap on exec). Capture
    # for cross-system comparability — runs under heavy memory pressure are
    # not directly comparable to runs on idle systems.
    try:
        info["vm_compressor_bytes"] = int(subprocess.check_output(
            ["sysctl", "-n", "vm.compressor_bytes_used"], text=True).strip())
    except Exception:
        info["vm_compressor_bytes"] = 0
    try:
        vm_out = subprocess.check_output(["vm_stat"], text=True)
        for line in vm_out.splitlines():
            if "Pages free" in line:
                info["pages_free"] = int(
                    line.split(":")[1].strip().rstrip("."))
            if "page size of" in line:
                info["page_size"] = int(
                    line.split("page size of")[1].split("bytes")[0].strip())
    except Exception:
        pass
    # 1-min load average — indicates system load during the bench
    try:
        info["loadavg_1min"] = float(os.getloadavg()[0])
    except Exception:
        info["loadavg_1min"] = 0.0
    return info


def time_cmd(cmd: list[str], output_path: str, timeout: float = 30) -> float | None:
    """Run a command, return wall ms or None on failure."""
    if output_path and os.path.exists(output_path):
        os.remove(output_path)
    t0 = time.perf_counter()
    try:
        r = subprocess.run(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    dt = (time.perf_counter() - t0) * 1000.0
    if r.returncode != 0:
        return None
    if output_path and not os.path.exists(output_path):
        return None
    return dt


def median_run(make_cmd, output_path: str, runs: int = 8, warmups: int = 2) -> float | None:
    samples = []
    for _ in range(warmups):
        time_cmd(make_cmd(), output_path)
    for _ in range(runs):
        ms = time_cmd(make_cmd(), output_path)
        if ms is None:
            return None
        samples.append(ms)
    return statistics.median(samples) if samples else None


def encode_corpus(out_dir: str) -> dict[str, str]:
    """Encode each fixture once with J2KSwift; return MD5s for parity check."""
    os.makedirs(out_dir, exist_ok=True)
    md5s = {}
    for stem, label in FIXTURES:
        src = f"{FIXTURE_DIR}/{stem}.pgm"
        if not os.path.exists(src):
            md5s[stem] = "missing"
            continue
        dst = f"{out_dir}/{stem}.j2k"
        subprocess.run(
            [J2K, "encode", "-i", src, "-o", dst,
             "--htj2k", "--lossless", "--quiet", "--no-daemon"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(dst, "rb") as f:
            md5s[stem] = hashlib.md5(f.read()).hexdigest()
    return md5s


def bench_encode(runs: int = 8) -> list[dict]:
    """Encode wall measurement: J2KSwift in-proc + --daemon auto + OpenJPH + Grok + Kakadu."""
    cells = []
    for stem, label in FIXTURES:
        src = f"{FIXTURE_DIR}/{stem}.pgm"
        if not os.path.exists(src):
            continue
        ts = lambda x: f"/tmp/v9_silicon_enc_{x}.j2k"
        cell = {"fixture": label, "stem": stem}
        cell["j2kswift_inproc"] = median_run(
            lambda: [J2K, "encode", "-i", src, "-o", ts("j_in"),
                     "--htj2k", "--lossless", "--quiet", "--no-daemon"],
            ts("j_in"), runs=runs)
        cell["j2kswift_daemon_auto"] = median_run(
            lambda: [J2K, "encode", "-i", src, "-o", ts("j_dae"),
                     "--htj2k", "--lossless", "--quiet", "--daemon", "auto"],
            ts("j_dae"), runs=runs)
        if OJPH_E:
            cell["openjph"] = median_run(
                lambda: [OJPH_E, "-i", src, "-o", ts("o"), "-reversible", "true"],
                ts("o"), runs=runs)
        if GROK_E:
            cell["grok"] = median_run(
                lambda: [GROK_E, "-i", src, "-o", f"/tmp/v9_silicon_enc_g.jph", "-M", "64"],
                "/tmp/v9_silicon_enc_g.jph", runs=runs)
        if KDU_E:
            cell["kakadu"] = median_run(
                lambda: [KDU_E, "-i", src, "-o", ts("k"),
                         "Creversible=yes", "Cmodes=HT", "-quiet"],
                ts("k"), runs=runs)
        cells.append(cell)
    return cells


def bench_decode(j2k_dir: str, runs: int = 8) -> list[dict]:
    """Decode wall measurement: same 4 codecs."""
    cells = []
    out = "/tmp/v9_silicon_decoded.pgm"
    for stem, label in FIXTURES:
        src = f"{j2k_dir}/{stem}.j2k"
        if not os.path.exists(src):
            continue
        cell = {"fixture": label, "stem": stem}
        cell["j2kswift_inproc"] = median_run(
            lambda: [J2K, "decode", "-i", src, "-o", out, "--quiet", "--no-daemon"],
            out, runs=runs)
        cell["j2kswift_daemon_auto"] = median_run(
            lambda: [J2K, "decode", "-i", src, "-o", out, "--quiet", "--daemon", "auto"],
            out, runs=runs)
        if OJPH_D:
            cell["openjph"] = median_run(
                lambda: [OJPH_D, "-i", src, "-o", out], out, runs=runs)
        if GROK_D:
            cell["grok"] = median_run(
                lambda: [GROK_D, "-i", src, "-o", out], out, runs=runs)
        if KDU_D:
            cell["kakadu"] = median_run(
                lambda: [KDU_D, "-i", src, "-o", out], out, runs=runs)
        cells.append(cell)
    return cells


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "compare":
        if len(sys.argv) < 4:
            print("Usage: cross_silicon_probe.py compare <result1.json> <result2.json>")
            sys.exit(1)
        return compare_runs(sys.argv[2], sys.argv[3])

    if not os.path.exists(J2K):
        print(f"ERROR: j2k binary not found at {J2K}")
        print("Run: swift build -c release --product j2k")
        sys.exit(1)

    info = system_info()
    print(f"=== v9.0 cross-silicon probe ===")
    print(f"  hw_model:    {info['hw_model']}")
    print(f"  cpu_brand:   {info['cpu_brand']}")
    print(f"  mem_gb:      {info['mem_gb']}")
    print(f"  cores:       {info['cores_perf']}P + {info['cores_eff']}E")
    print(f"  J2KSwift:    {info['j2kswift_version']}")
    compressor_gb = info.get("vm_compressor_bytes", 0) / (1024 ** 3)
    free_mb = (info.get("pages_free", 0) * info.get("page_size", 0)) / (1024 ** 2)
    print(f"  compressor:  {compressor_gb:.2f} GB used (>2 GB = pressure)")
    print(f"  free pages:  {free_mb:.0f} MB (<500 MB = memory pressure)")
    print(f"  load 1min:   {info.get('loadavg_1min', 0):.2f}")
    if compressor_gb > 2.0 or free_mb < 500:
        print("  ⚠ system is memory-pressured — every CLI invocation pays an")
        print("    extra ~30 ms exec/page-swap tax. Numbers below reflect")
        print("    stressed-state baseline, not idle-system best-case.")
    print()
    print("Encoding corpus...")
    enc_dir = f"/tmp/v9_silicon_bench"
    md5s = encode_corpus(enc_dir)
    for stem, md5 in md5s.items():
        print(f"  {stem}: {md5[:12]}...")

    print()
    print("Encode benchmark (median of 8)...")
    enc_cells = bench_encode()
    for c in enc_cells:
        print(f"  {c['fixture']:<18} | "
              f"j2k_inproc={c.get('j2kswift_inproc', 0):.2f} ms | "
              f"j2k_daemon={c.get('j2kswift_daemon_auto', 0):.2f} ms | "
              f"ojph={c.get('openjph', 0):.2f} ms | "
              f"grok={c.get('grok', 0):.2f} ms | "
              f"kakadu={c.get('kakadu', 0):.2f} ms")

    print()
    print("Decode benchmark (median of 8)...")
    dec_cells = bench_decode(enc_dir)
    for c in dec_cells:
        print(f"  {c['fixture']:<18} | "
              f"j2k_inproc={c.get('j2kswift_inproc', 0):.2f} ms | "
              f"j2k_daemon={c.get('j2kswift_daemon_auto', 0):.2f} ms | "
              f"ojph={c.get('openjph', 0):.2f} ms | "
              f"grok={c.get('grok', 0):.2f} ms | "
              f"kakadu={c.get('kakadu', 0):.2f} ms")

    out = {
        "system": info,
        "codestream_md5s": md5s,
        "encode": enc_cells,
        "decode": dec_cells,
    }
    silicon = info["hw_model"].replace(",", "_")
    version = info["j2kswift_version"].split()[-1]
    date = datetime.utcnow().strftime("%Y%m%d")
    fname = f"benchmark-results-{silicon}-{version}-{date}.json"
    with open(fname, "w") as f:
        json.dump(out, f, indent=2)
    print(f"\nSaved: {fname}")


def compare_runs(path_a: str, path_b: str):
    """Diff two cross-silicon probe results."""
    with open(path_a) as f: a = json.load(f)
    with open(path_b) as f: b = json.load(f)

    print(f"=== Cross-silicon comparison ===")
    print(f"A: {a['system']['hw_model']} / {a['system']['cpu_brand']} / {a['system']['j2kswift_version']}")
    print(f"B: {b['system']['hw_model']} / {b['system']['cpu_brand']} / {b['system']['j2kswift_version']}")
    print()

    # Verify codestream parity (J2KSwift output should be byte-identical
    # across silicon if encoder is deterministic).
    print("Codestream MD5 parity (A vs B):")
    for stem in a["codestream_md5s"]:
        am = a["codestream_md5s"][stem]
        bm = b["codestream_md5s"].get(stem, "missing")
        match = "✓" if am == bm else "✗"
        print(f"  {match} {stem}: A={am[:12]}... B={bm[:12]}...")
    print()

    # Encode comparison.
    print("Encode wall comparison (ms, A → B):")
    print(f"{'fixture':<18} | {'codec':<22} | {'A':>9} | {'B':>9} | {'Δ':>9} | {'%':>7}")
    print("-" * 85)
    for ca in a["encode"]:
        cb = next((c for c in b["encode"] if c["stem"] == ca["stem"]), None)
        if not cb: continue
        for codec in ["j2kswift_inproc", "j2kswift_daemon_auto", "openjph", "grok", "kakadu"]:
            va = ca.get(codec)
            vb = cb.get(codec)
            if va is None or vb is None: continue
            delta = vb - va
            pct = 100 * delta / va if va else 0
            print(f"{ca['fixture']:<18} | {codec:<22} | {va:>9.2f} | {vb:>9.2f} | {delta:+9.2f} | {pct:+7.1f}%")
    print()
    print("Decode wall comparison (ms, A → B):")
    print(f"{'fixture':<18} | {'codec':<22} | {'A':>9} | {'B':>9} | {'Δ':>9} | {'%':>7}")
    print("-" * 85)
    for ca in a["decode"]:
        cb = next((c for c in b["decode"] if c["stem"] == ca["stem"]), None)
        if not cb: continue
        for codec in ["j2kswift_inproc", "j2kswift_daemon_auto", "openjph", "grok", "kakadu"]:
            va = ca.get(codec)
            vb = cb.get(codec)
            if va is None or vb is None: continue
            delta = vb - va
            pct = 100 * delta / va if va else 0
            print(f"{ca['fixture']:<18} | {codec:<22} | {va:>9.2f} | {vb:>9.2f} | {delta:+9.2f} | {pct:+7.1f}%")


if __name__ == "__main__":
    main()
