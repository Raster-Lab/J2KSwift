#!/usr/bin/env python3
"""J2KSwift canonical warm cross-codec benchmark.

This is THE script for marketing-grade claims about J2KSwift performance
on Apple Silicon. Every release that updates encode/decode performance
numbers in `RELEASE_NOTES_vX.Y.Z.md` MUST cite this script's output
(captured with `--json --output benchmark-results-<host>-<version>-<date>.json`).

What this measures
==================

Three workloads, all WARM start, all median-of-N after W warmups:

1. **PGM encode (cross-codec)** — J2KSwift CLI (with daemon) vs OpenJPH
   vs Grok vs Kakadu. Encode 16-bit medical PGM → HT-conformant lossless
   J2K codestream. Each codec's CLI is invoked once per timed run; each
   pays fork+exec but J2KSwift's library cold-start is amortised via the
   pre-installed j2kd daemon. This is the closest apples-to-apples
   warm-start comparison the CLI shape allows.

2. **PGM decode (cross-codec)** — same four codecs decoding the J2KSwift-
   encoded codestream from step 1 back to 16-bit pixels. Decode is also
   warm via `j2k --daemon` for J2KSwift.

3. **DICOM encode (J2KSwift-only)** — J2KSwift CLI consumes the DICOM
   Part 10 file directly (PixelData tag), produces an HT-conformant J2K
   codestream. The other codecs' CLIs are J2K-only and don't read DICOM
   directly, so this is the marketable-strength workload where J2KSwift's
   integrated DICOM support has no comparable warm-equivalent.

Why warm-only
=============

Cold CLI invocations on Swift binaries pay a Swift-runtime + Metal init
tax (~70 ms on M2) that other codecs don't pay. That tax distorts every
"J2KSwift is slow" claim. The j2kd daemon (v9.5.0) amortises that tax
across calls. Phase 6 of v10.0-research (V10_0_PHASE6_DAEMON_DECOMPOSITION.md)
proves the daemon's net win over warm-in-process is +20 ms XPC overhead
on M2 DX (i.e., daemon is the right CLI-warm baseline, not in-process).

For SDK-shape benchmarking (J2KSwift called from inside a long-lived
process), see `J2KMedicalCorpusEncodePerformanceTests` in the Swift
test suite — that measures direct in-process API calls.

Apples-to-apples
================

Each codec runs:
- 2 warmup invocations (discarded) per fixture per direction
- 7 timed invocations per fixture per direction
- Median across the 7 is reported

The j2kd daemon is verified reachable before the run starts; if it is
not installed, the script aborts with `j2k daemon-install` guidance.
Other codecs run plain CLI — their startup costs are inherent.

Corpus
======

20 PGM fixtures: 7 real medical images + 13 deterministic synthetic
fixtures (8 modalities × 4 sizes — see
`Scripts/benchmarks/generate_synthetic_corpus.py`).

13 DICOM fixtures: same pixel data as the synthetics, wrapped in
DICOM Part 10 (Explicit VR Little Endian, uncompressed).

Output
======

- Markdown tables on stdout (paste-ready for RELEASE_NOTES_vX.Y.Z.md).
- Optional JSON via `--output <path>` for archival + cross-host diffing.

Usage
=====

    python3 Scripts/benchmarks/cross_codec_warm_bench.py
    python3 Scripts/benchmarks/cross_codec_warm_bench.py --output bench.json
    python3 Scripts/benchmarks/cross_codec_warm_bench.py --quick    # 3 runs, small fixtures only

Prerequisites:
    swift build -c release --product j2k --product j2kd
    .build/release/j2k daemon-install --force
    brew install openjph grokj2k                  # OpenJPH + Grok
    # Kakadu: download from kakadusoftware.com to /usr/local/bin/
    python3 Scripts/benchmarks/generate_synthetic_corpus.py
"""
import argparse
import csv
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from datetime import datetime
from typing import Optional


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REAL_FIXTURE_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec")
SYNTH_FIXTURE_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec/synthetic")
MEDICAL_REAL_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec/medical-real")
MEDICAL_REAL_MANIFEST = os.path.join(MEDICAL_REAL_DIR, "manifest.csv")
J2K_BIN = os.path.join(REPO_ROOT, ".build/release/j2k")
SCRATCH_DIR = "/tmp/j2kswift_warm_bench"

# Codec binary candidates — first existing path is used.
CODEC_CANDIDATES = {
    "OpenJPH": {
        "encode": ["/opt/homebrew/bin/ojph_compress", "/usr/local/bin/ojph_compress"],
        "decode": ["/opt/homebrew/bin/ojph_expand",   "/usr/local/bin/ojph_expand"],
    },
    "Grok": {
        "encode": ["/opt/homebrew/bin/grk_compress", "/usr/local/bin/grk_compress"],
        "decode": ["/opt/homebrew/bin/grk_decompress", "/usr/local/bin/grk_decompress"],
    },
    "Kakadu": {
        "encode": ["/usr/local/bin/kdu_compress", "/opt/homebrew/bin/kdu_compress"],
        "decode": ["/usr/local/bin/kdu_expand",   "/opt/homebrew/bin/kdu_expand"],
    },
}


# 20 PGM fixtures: 7 real + 13 synthetic. Order is small → large so the
# table reads progressively.
REAL_PGM = [
    ("MR-small 180²",   "mr_study_002_instance_000100.pgm",   "real",  "MR"),
    ("MR 886²",         "mr_study_001_instance_000001.pgm",   "real",  "MR"),
    ("CT 512² (1)",     "ct_study_001_instance_000001.pgm",   "real",  "CT"),
    ("CT 512² (2)",     "ct_study_003_instance_000050.pgm",   "real",  "CT"),
    ("XA 1024²",        "xa_study_001_instance_000001.pgm",   "real",  "XA"),
    ("PX 2459×1316",    "px_study_001_instance_000001.pgm",   "real",  "PX"),
    ("DX 2800×2288",    "dx_study_002_instance_000001.pgm",   "real",  "DX"),
]
SYNTH_PGM = [
    ("NM 256² (synth)",       "nm_synth_small.pgm",   "synth", "NM"),
    ("MR 256² (synth)",       "mr_synth_small.pgm",   "synth", "MR"),
    ("CT 384² (synth)",       "ct_synth_small.pgm",   "synth", "CT"),
    ("MR 512² (synth)",       "mr_synth_mid.pgm",     "synth", "MR"),
    ("CT 768² (synth)",       "ct_synth_mid.pgm",     "synth", "CT"),
    ("XA 800² (synth)",       "xa_synth_small.pgm",   "synth", "XA"),
    ("PX 1024×800 (synth)",   "px_synth_mid.pgm",     "synth", "PX"),
    ("CT 1024² (synth)",      "ct_synth_large.pgm",   "synth", "CT"),
    ("MR 1024² (synth)",      "mr_synth_large.pgm",   "synth", "MR"),
    ("DX 1024² (synth)",      "dx_synth_mid.pgm",     "synth", "DX"),
    ("CR 1024² (synth)",      "cr_synth_mid.pgm",     "synth", "CR"),
    ("MG 1024×1280 (synth)",  "mg_synth_mid.pgm",     "synth", "MG"),
    ("XA 1280² (synth)",      "xa_synth_mid.pgm",     "synth", "XA"),
]

# 13 DICOM fixtures (same names as synth PGMs, .dcm extension).
DCM_FIXTURES = [
    (f"{label} (DCM)", filename.replace(".pgm", ".dcm"), source, modality)
    for label, filename, source, modality in SYNTH_PGM
]


def load_medical_real_fixtures() -> list[tuple[str, str, str, str]]:
    """Load the 18 real medical PGM fixtures from manifest.csv.

    Returns [] if the manifest is absent (graceful fallback for repos
    that haven't yet generated the medical-real corpus).
    """
    if not os.path.isfile(MEDICAL_REAL_MANIFEST):
        return []
    out: list[tuple[str, str, str, str]] = []
    import csv as _csv
    with open(MEDICAL_REAL_MANIFEST) as f:
        for row in _csv.DictReader(f):
            label = (
                f"{row['modality']} {row['width']}×{row['height']} "
                f"({row['tier']}, real)"
            )
            out.append((label, row["filename"], "medical-real", row["modality"]))
    # Sort by pixel count so the table reads small → large.
    return sorted(out, key=lambda x: int(x[1].split("_")[3].split("x")[0]) *
                                       int(x[1].split("_")[3].split("x")[1].split(".")[0]))


MEDICAL_REAL_PGM = load_medical_real_fixtures()


# -----------------------------------------------------------------------
# CPU / host probe
# -----------------------------------------------------------------------

def detect_cpu() -> dict:
    """Return host CPU descriptor (M1/M2/.../A-series)."""
    info = {
        "machine": platform.machine(),
        "system": platform.system(),
        "release": platform.release(),
    }
    try:
        brand = subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        info["brand"] = brand
    except Exception:
        info["brand"] = "(sysctl unavailable)"
    try:
        cores = subprocess.run(
            ["sysctl", "-n", "hw.ncpu"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        info["ncpu"] = int(cores) if cores.isdigit() else None
    except Exception:
        info["ncpu"] = None
    try:
        model = subprocess.run(
            ["sysctl", "-n", "hw.model"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        info["model"] = model
    except Exception:
        info["model"] = None
    return info


def resolve_codec_path(candidates: list[str]) -> Optional[str]:
    for p in candidates:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def verify_daemon() -> bool:
    if not os.path.isfile(J2K_BIN):
        return False
    try:
        r = subprocess.run([J2K_BIN, "daemon-ping"], capture_output=True, text=True, timeout=5)
        return r.returncode == 0 and "available" in r.stdout.lower()
    except Exception:
        return False


# -----------------------------------------------------------------------
# Timing helpers
# -----------------------------------------------------------------------

def time_subprocess(cmd: list[str], output_path: Optional[str] = None) -> Optional[float]:
    """Run a subprocess and time it. Returns wall ms, or None on failure
    (non-zero exit code OR missing output_path)."""
    if output_path and os.path.exists(output_path):
        try:
            os.remove(output_path)
        except Exception:
            pass
    t0 = time.perf_counter()
    try:
        r = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        return None
    elapsed = (time.perf_counter() - t0) * 1000.0
    if r.returncode != 0:
        return None
    if output_path and not os.path.exists(output_path):
        return None
    return elapsed


def bench(cmd_factory, output_path: str, runs: int, warmups: int,
          isolated: bool = False) -> Optional[dict]:
    """Run `cmd_factory(output_path)` `warmups + runs` times. Return
    {median, min, max, samples} for the timed runs, or None on failure.

    When `isolated` is True: bumps warmups (5 instead of caller-supplied
    1-2) so the cell's daemon + cores are fully warm before timing
    begins; runs timed calls BACK-TO-BACK (no within-cell sleep — that
    would let the daemon idle and the cores power-gate down, inflating
    per-call timing). Inter-cell + inter-fixture cool-down is handled
    by the run_benchmark caller.

    See DAEMON_OVERHEAD_METHODOLOGY_FINDING.md: isolated DX = ~57 ms
    (this mode), sustained DX = ~77 ms (default mode); the gap is
    accumulated scheduler/cache pressure across the full corpus.
    """
    effective_warmups = max(warmups, 5) if isolated else warmups
    for _ in range(effective_warmups):
        time_subprocess(cmd_factory(output_path), output_path)
    samples = []
    for _ in range(runs):
        ms = time_subprocess(cmd_factory(output_path), output_path)
        if ms is None:
            return None
        samples.append(ms)
    samples.sort()
    return {
        "median": samples[len(samples) // 2],
        "min": samples[0],
        "max": samples[-1],
        "samples": samples,
    }


# -----------------------------------------------------------------------
# Per-codec command factories
# -----------------------------------------------------------------------

def cmd_j2kswift_encode(src: str):
    def make(out: str):
        return [J2K_BIN, "encode", "-i", src, "-o", out,
                "--htj2k", "--lossless", "--daemon", "--quiet"]
    return make


def cmd_openjph_encode(src: str, bin_path: str):
    def make(out: str):
        return [bin_path, "-i", src, "-o", out, "-reversible", "true"]
    return make


def cmd_grok_encode(src: str, bin_path: str):
    def make(out: str):
        # Grok HT mode requires .jph extension on output.
        out_jph = out + ".jph" if not out.endswith(".jph") else out
        return [bin_path, "-i", src, "-o", out_jph, "-M", "64"]
    return make


def cmd_kakadu_encode(src: str, bin_path: str):
    def make(out: str):
        return [bin_path, "-i", src, "-o", out,
                "Creversible=yes", "Cmodes=HT", "-quiet"]
    return make


def cmd_j2kswift_decode(src: str):
    def make(out: str):
        return [J2K_BIN, "decode", "-i", src, "-o", out, "--daemon", "--quiet"]
    return make


def cmd_openjph_decode(src: str, bin_path: str):
    def make(out: str):
        return [bin_path, "-i", src, "-o", out]
    return make


def cmd_grok_decode(src: str, bin_path: str):
    def make(out: str):
        return [bin_path, "-i", src, "-o", out]
    return make


def cmd_kakadu_decode(src: str, bin_path: str):
    def make(out: str):
        return [bin_path, "-i", src, "-o", out]
    return make


# -----------------------------------------------------------------------
# Main benchmark driver
# -----------------------------------------------------------------------

def run_benchmark(args) -> dict:
    runs = args.runs
    warmups = args.warmups

    cpu = detect_cpu()
    print(f"=== J2KSwift canonical warm cross-codec benchmark ===")
    print(f"Host: {cpu.get('brand', '(unknown)')} ({cpu.get('model', '?')}, "
          f"{cpu.get('ncpu', '?')} CPUs), {cpu['system']} {cpu['release']}")
    print(f"Date: {datetime.now().isoformat(timespec='seconds')}")

    # j2k binary version
    j2k_version = "?"
    if os.path.isfile(J2K_BIN):
        try:
            j2k_version = subprocess.run([J2K_BIN, "version"], capture_output=True,
                                          text=True, timeout=5).stdout.strip()
        except Exception:
            pass
    print(f"J2KSwift: {j2k_version}")

    # Codec paths
    codec_paths = {}
    for name, paths in CODEC_CANDIDATES.items():
        codec_paths[name] = {
            "encode": resolve_codec_path(paths["encode"]),
            "decode": resolve_codec_path(paths["decode"]),
        }
    for name, p in codec_paths.items():
        print(f"  {name}: encode={p['encode'] or '(missing)'}  decode={p['decode'] or '(missing)'}")

    # Daemon check
    daemon_ok = verify_daemon()
    print(f"j2kd daemon reachable: {daemon_ok}")
    if not daemon_ok:
        print("\nError: j2kd daemon not reachable. Install with:")
        print(f"  {J2K_BIN} daemon-install --force")
        sys.exit(1)

    os.makedirs(SCRATCH_DIR, exist_ok=True)
    isolated = bool(getattr(args, "isolated", False))
    in_proc = bool(getattr(args, "in_proc", False))
    j2k_col = "J2KSwift+inproc" if in_proc else "J2KSwift+daemon"
    print(f"Runs: median of {runs} after {warmups} warmups (per fixture per codec per direction)")
    if in_proc:
        print(f"Mode: IN-PROC (J2KSwift via `j2k inproc-bench`; one Swift launch per fixture, "
              f"both encode+decode timed in-process — measures pure SDK wall, no CLI subprocess "
              f"or XPC overhead)")
    else:
        print(f"Mode: {'ISOLATED (cool-down between cells; per-call SDK-design measurement)' if isolated else 'SUSTAINED (back-to-back; batch-pipeline-realism measurement)'}")
    print()

    # Pre-encode the corpus once with J2KSwift so other codecs have
    # a J2K input for the decode benchmark. Use --daemon so this is fast.
    encoded_inputs = {}
    print("Pre-encoding corpus (one warm encode per fixture, --daemon)...")
    if args.quick:
        pgm_fixtures = REAL_PGM[:2] + SYNTH_PGM[:3] + MEDICAL_REAL_PGM[:3]
    else:
        pgm_fixtures = REAL_PGM + SYNTH_PGM + MEDICAL_REAL_PGM
    for label, filename, source, modality in pgm_fixtures:
        if source == "real":
            src_dir = REAL_FIXTURE_DIR
        elif source == "medical-real":
            src_dir = MEDICAL_REAL_DIR
        else:
            src_dir = SYNTH_FIXTURE_DIR
        src = os.path.join(src_dir, filename)
        if not os.path.exists(src):
            print(f"  ✗ missing: {src}")
            continue
        encoded = os.path.join(SCRATCH_DIR, filename.replace(".pgm", ".j2k"))
        cmd = [J2K_BIN, "encode", "-i", src, "-o", encoded,
               "--htj2k", "--lossless", "--daemon", "--quiet"]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        if os.path.exists(encoded):
            encoded_inputs[filename] = (encoded, src, label, source, modality)
    print(f"  {len(encoded_inputs)}/{len(pgm_fixtures)} pre-encoded.")
    print()

    # In-proc bench cache: when --in-proc, pre-run `j2k inproc-bench` once
    # per fixture (does both encode and decode in the same Swift process).
    # Cached results substitute for the per-cell `bench()` call below so
    # the J2KSwift column reflects pure in-process SDK timing rather than
    # CLI subprocess + daemon-XPC overhead.
    inproc_cache: dict = {}
    if in_proc:
        print("Pre-running in-proc bench (one Swift launch per fixture)...")
        for filename, (j2k_path, src, label, source, modality) in encoded_inputs.items():
            cmd = [J2K_BIN, "inproc-bench", src,
                   "--runs", str(runs), "--warmups", str(warmups)]
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
                if r.returncode == 0:
                    inproc_cache[filename] = json.loads(r.stdout)
                else:
                    print(f"  ✗ inproc-bench failed for {filename}: {r.stderr.strip()[:120]}")
            except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
                print(f"  ✗ inproc-bench error for {filename}: {e}")
        print(f"  {len(inproc_cache)}/{len(encoded_inputs)} in-proc benched.")
        print()

    # ============== WORKLOAD 1: PGM ENCODE (cross-codec) ==============
    print("## PGM encode wall — warm (median ms)")
    print()
    header = ["Fixture", "Source", j2k_col]
    for name in CODEC_CANDIDATES:
        if codec_paths[name]["encode"]:
            header.append(name)
    print("| " + " | ".join(header) + " |")
    print("|" + "|".join(["---"] * len(header)) + "|")

    encode_results = {}
    for filename, (j2k_path, src, label, source, modality) in encoded_inputs.items():
        row = {"label": label, "source": source, "modality": modality,
               "fixture": filename, "results": {}}
        # J2KSwift: in-proc cache or daemon CLI
        if in_proc:
            r = inproc_cache.get(filename, {}).get("encode")
        else:
            out = os.path.join(SCRATCH_DIR, f"warm_enc_{filename}.j2k")
            r = bench(cmd_j2kswift_encode(src), out, runs, warmups, isolated=isolated)
        row["results"][j2k_col] = r
        row_cells = [label, source, f"{r['median']:.2f}" if r else "(err)"]
        # Other codecs
        for name in CODEC_CANDIDATES:
            ep = codec_paths[name]["encode"]
            if not ep:
                continue
            out_ext = ".jph" if name == "Grok" else ".j2k"
            out = os.path.join(SCRATCH_DIR, f"warm_enc_{name}_{filename}{out_ext}")
            if name == "OpenJPH":
                factory = cmd_openjph_encode(src, ep)
            elif name == "Grok":
                factory = cmd_grok_encode(src, ep)
            elif name == "Kakadu":
                factory = cmd_kakadu_encode(src, ep)
            else:
                continue
            r = bench(factory, out, runs, warmups, isolated=isolated)
            row["results"][name] = r
            row_cells.append(f"{r['median']:.2f}" if r else "(err)")
        print("| " + " | ".join(row_cells) + " |")
        encode_results[filename] = row
        if isolated:
            time.sleep(1.0)   # per-fixture cool-down — drains pressure
                              # accumulated across all codecs on this fixture

    if isolated:
        print()
        print("(2 s cool-down before decode pass for cleaner isolation)")
        time.sleep(2.0)

    # ============== WORKLOAD 2: PGM DECODE (cross-codec) ==============
    print()
    print("## PGM decode wall — warm (median ms)")
    print()
    header = ["Fixture", "Source", j2k_col]
    for name in CODEC_CANDIDATES:
        if codec_paths[name]["decode"]:
            header.append(name)
    print("| " + " | ".join(header) + " |")
    print("|" + "|".join(["---"] * len(header)) + "|")

    decode_results = {}
    for filename, (j2k_path, src, label, source, modality) in encoded_inputs.items():
        row = {"label": label, "source": source, "modality": modality,
               "fixture": filename, "results": {}}
        if in_proc:
            r = inproc_cache.get(filename, {}).get("decode")
        else:
            out = os.path.join(SCRATCH_DIR, f"warm_dec_{filename}.pgm")
            r = bench(cmd_j2kswift_decode(j2k_path), out, runs, warmups, isolated=isolated)
        row["results"][j2k_col] = r
        row_cells = [label, source, f"{r['median']:.2f}" if r else "(err)"]
        for name in CODEC_CANDIDATES:
            dp = codec_paths[name]["decode"]
            if not dp:
                continue
            out = os.path.join(SCRATCH_DIR, f"warm_dec_{name}_{filename}.pgm")
            if name == "OpenJPH":
                factory = cmd_openjph_decode(j2k_path, dp)
            elif name == "Grok":
                factory = cmd_grok_decode(j2k_path, dp)
            elif name == "Kakadu":
                factory = cmd_kakadu_decode(j2k_path, dp)
            else:
                continue
            r = bench(factory, out, runs, warmups, isolated=isolated)
            row["results"][name] = r
            row_cells.append(f"{r['median']:.2f}" if r else "(err)")
        print("| " + " | ".join(row_cells) + " |")
        decode_results[filename] = row
        if isolated:
            time.sleep(1.0)   # per-fixture cool-down

    # ============== WORKLOAD 3: DICOM ENCODE (J2KSwift-only) ==============
    print()
    print("## DICOM encode wall — warm, J2KSwift only (median ms)")
    print("(External codecs' CLIs are J2K-only; DICOM PixelData extraction")
    print("must be done separately for cross-codec DICOM comparison.)")
    print()
    print(f"| Fixture | Modality | {j2k_col} (DICOM→J2K) |")
    print("|---|---|---:|")

    dicom_fixtures = DCM_FIXTURES if not args.quick else DCM_FIXTURES[:3]
    dicom_results = {}
    for label, filename, source, modality in dicom_fixtures:
        src = os.path.join(SYNTH_FIXTURE_DIR, filename)
        if not os.path.exists(src):
            continue
        if in_proc:
            cmd = [J2K_BIN, "inproc-bench", src,
                   "--runs", str(runs), "--warmups", str(warmups),
                   "--mode", "encode"]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
                r = json.loads(proc.stdout).get("encode") if proc.returncode == 0 else None
            except (subprocess.TimeoutExpired, json.JSONDecodeError):
                r = None
        else:
            out = os.path.join(SCRATCH_DIR, f"warm_dcm_{filename}.j2k")
            r = bench(cmd_j2kswift_encode(src), out, runs, warmups, isolated=isolated)
        if r:
            dicom_results[filename] = {"label": label, "modality": modality, "results": r}
            print(f"| {label} | {modality} | {r['median']:.2f} |")
        else:
            print(f"| {label} | {modality} | (err) |")

    # ============== SUMMARY ==============
    print()
    print(f"## Summary — fixtures where {j2k_col} WINS (median ≤ all measured codecs)")
    print()

    def count_wins(direction_results):
        wins = 0
        total = 0
        for fixture, row in direction_results.items():
            results = row["results"]
            ours = results.get(j2k_col)
            if not ours:
                continue
            total += 1
            other_medians = [r["median"] for k, r in results.items()
                             if k != j2k_col and r]
            if other_medians and ours["median"] <= min(other_medians):
                wins += 1
        return wins, total

    enc_wins, enc_total = count_wins(encode_results)
    dec_wins, dec_total = count_wins(decode_results)
    print(f"- PGM encode: {j2k_col} wins on **{enc_wins}/{enc_total}** fixtures")
    print(f"- PGM decode: {j2k_col} wins on **{dec_wins}/{dec_total}** fixtures")
    print(f"- DICOM encode: {j2k_col} measured on **{len(dicom_results)}/{len(dicom_fixtures)}** fixtures (no cross-codec comparator — see note above)")

    return {
        "host": cpu,
        "j2k_version": j2k_version,
        "codec_paths": codec_paths,
        "daemon_reachable": daemon_ok,
        "runs": runs,
        "warmups": warmups,
        "encode": encode_results,
        "decode": decode_results,
        "dicom_encode": dicom_results,
        "summary": {
            "encode_wins": enc_wins,
            "encode_total": enc_total,
            "decode_wins": dec_wins,
            "decode_total": dec_total,
            "dicom_fixtures_measured": len(dicom_results),
        },
        "captured_at": datetime.now().isoformat(timespec="seconds"),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="J2KSwift warm cross-codec benchmark")
    ap.add_argument("--runs", type=int, default=7, help="Timed runs per cell (default 7)")
    ap.add_argument("--warmups", type=int, default=2, help="Discarded warmups per cell (default 2)")
    ap.add_argument("--output", type=str, default=None, help="Write full results JSON to PATH")
    ap.add_argument("--quick", action="store_true", help="Subset corpus for fast smoke run")
    ap.add_argument("--isolated", action="store_true",
                    help="Add cool-down sleeps between calls + between cells. "
                         "Produces per-call SDK-design measurements (~57 ms DX "
                         "vs ~77 ms in default sustained mode). Run-time ~3x "
                         "longer. See Documentation/Benchmarks/"
                         "DAEMON_OVERHEAD_METHODOLOGY_FINDING.md.")
    ap.add_argument("--in-proc", dest="in_proc", action="store_true",
                    help="Measure J2KSwift via in-process `j2k inproc-bench` "
                         "(one Swift launch per fixture, both encode+decode "
                         "timed in-process). Removes CLI subprocess + XPC "
                         "overhead — reflects real SDK consumer wall. "
                         "External codecs (Kakadu/OpenJPH/Grok) remain CLI "
                         "since they have no in-process binding here.")
    args = ap.parse_args()

    results = run_benchmark(args)

    if args.output:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults written to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
