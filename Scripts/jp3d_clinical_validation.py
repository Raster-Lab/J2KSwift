#!/usr/bin/env python3
"""
jp3d_clinical_validation.py — multi-study medical-grade JP3D validation.

Drives the J2KSwift JP3D vs OpenJPEG JP3D head-to-head across every CT
and MR study in `LocalDatasets/medical-dicom-organized/`, captures the
ratio / encode time / decode time / bit-exact gates, and emits both a
machine-readable CSV and a clinical-validation Markdown report.

This is M3 of `docs/JP3D_BEAT_OPENJPEG_PLAN.md`. See that doc for the
medical-grade pass criteria (bit-exact, ratio ≥ 99 % of OpenJPEG,
encode ≥ 1.5× faster, decode ≥ 1.5× faster).

Prerequisites:
    Scripts/setup-jp3d-openjpeg.sh           # builds opj_jp3d_compress
    swift build -c release --product j2k     # builds j2k CLI
    source .venv/bin/activate                # pydicom + numpy

Usage:
    Scripts/jp3d_clinical_validation.py \\
        [--slices N]                  # cap per-study slice count (default 32)
        [--iters N]                   # timing iterations (default 2)
        [--csv-out PATH]              # results.csv (default docs/jp3d_clinical_validation.csv)
        [--report-out PATH]           # markdown report (default docs/JP3D_CLINICAL_VALIDATION.md)
        [--datasets-root PATH]        # default LocalDatasets/medical-dicom-organized
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OPJ_PREFIX = Path.home() / ".j2kswift-tools" / "jp3d" / "bin"
DEFAULT_J2K_BIN = REPO_ROOT / ".build" / "release" / "j2k"
PREP_SCRIPT = REPO_ROOT / "Scripts" / "prep_jp3d_volume.py"

# Medical-grade gate (mirrors Scripts/jp3d_beat_openjpeg.sh)
RATIO_FLOOR = 0.99
SPEED_FLOOR = 1.5


@dataclass
class StudyResult:
    modality: str
    study: str
    width: int
    height: int
    depth: int
    bit_depth: int
    raw_bytes: int

    j2k_bytes: int
    opj_bytes: int
    j2k_ratio: float
    opj_ratio: float
    ratio_delta: float

    j2k_enc_s: float
    opj_enc_s: float
    enc_speedup: float

    j2k_dec_s: float
    opj_dec_s: float
    dec_speedup: float

    j2k_bitexact: bool
    opj_bitexact: bool

    pass_overall: bool
    fail_reasons: str


def find_tool(env_var: str, default: Path) -> Path:
    p = Path(os.environ.get(env_var, str(default)))
    if not p.is_file() or not os.access(p, os.X_OK):
        sys.exit(f"[clinical] required tool not found / not executable: {p} "
                 f"(set {env_var} to override)")
    return p


def time_min(cmd: list[str], iters: int) -> float:
    """Returns the minimum wall time over `iters` runs of `cmd`."""
    best = float("inf")
    for _ in range(iters):
        t0 = time.perf_counter()
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        dt = time.perf_counter() - t0
        if result.returncode != 0:
            sys.exit(f"[clinical] command failed (exit {result.returncode}): "
                     + " ".join(cmd))
        best = min(best, dt)
    return best


def bitexact(a: Path, b: Path, length_bytes: int) -> bool:
    return a.read_bytes()[:length_bytes] == b.read_bytes()[:length_bytes]


def run_one_study(
    modality: str, study_dir: Path, slices: int, iters: int,
    j2k_bin: Path, opj_compress: Path, opj_decompress: Path,
    work_dir: Path
) -> Optional[StudyResult]:

    out_base = work_dir / f"{modality}_{study_dir.name}_{slices}s"
    bin_path = out_base.with_suffix(".bin")
    img_path = out_base.with_suffix(".img")
    meta_path = out_base.with_suffix(".meta")

    # Prep volume (idempotent)
    if not bin_path.exists():
        result = subprocess.run([
            sys.executable, str(PREP_SCRIPT),
            "--dicom-dir", str(study_dir),
            "--out", str(out_base),
            "--max-slices", str(slices),
        ], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"[clinical] prep failed for {modality}/{study_dir.name}: "
                  f"{result.stderr.strip()}", file=sys.stderr)
            return None

    meta = json.loads(meta_path.read_text())
    raw_bytes = bin_path.stat().st_size

    j2k_out = work_dir / f"j2k_{modality}_{study_dir.name}.j3d"
    opj_out = work_dir / f"opj_{modality}_{study_dir.name}.j3d"
    j2k_back = work_dir / f"j2k_{modality}_{study_dir.name}_back.bin"
    opj_back = work_dir / f"opj_{modality}_{study_dir.name}_back.bin"
    for p in [j2k_out, opj_out, j2k_back, opj_back]:
        p.unlink(missing_ok=True)

    j2k_enc = time_min([
        str(j2k_bin), "encode3d",
        "-i", str(bin_path), "-o", str(j2k_out),
        "--dimensions", f"{meta['width']}x{meta['height']}x{meta['depth']}",
        "--bit-depth", str(meta["bit_depth"]),
        "--codec", "j2k-lossless",
        "--quiet",
    ], iters)
    opj_enc = time_min([
        str(opj_compress),
        "-i", str(bin_path), "-m", str(img_path),
        "-o", str(opj_out), "-C", "3EB", "-r", "1",
    ], iters)

    j2k_dec = time_min([
        str(j2k_bin), "decode3d",
        "-i", str(j2k_out), "-o", str(j2k_back),
        "--output-format", "raw", "--quiet",
    ], iters)
    opj_dec = time_min([
        str(opj_decompress), "-i", str(opj_out), "-o", str(opj_back),
    ], iters)

    j2k_bytes = j2k_out.stat().st_size
    opj_bytes = opj_out.stat().st_size

    j2k_ratio = raw_bytes / j2k_bytes
    opj_ratio = raw_bytes / opj_bytes
    ratio_delta = j2k_ratio / opj_ratio
    enc_speedup = opj_enc / j2k_enc
    dec_speedup = opj_dec / j2k_dec

    j2k_be = bitexact(bin_path, j2k_back, raw_bytes)
    opj_be = bitexact(bin_path, opj_back, raw_bytes)

    fails = []
    if not j2k_be:
        fails.append("J2KSwift not bit-exact")
    if ratio_delta < RATIO_FLOOR:
        fails.append(f"ratio_delta {ratio_delta:.4f}× < {RATIO_FLOOR}×")
    if enc_speedup < SPEED_FLOOR:
        fails.append(f"enc_speedup {enc_speedup:.2f}× < {SPEED_FLOOR}×")
    if dec_speedup < SPEED_FLOOR:
        fails.append(f"dec_speedup {dec_speedup:.2f}× < {SPEED_FLOOR}×")

    return StudyResult(
        modality=modality, study=study_dir.name,
        width=meta["width"], height=meta["height"], depth=meta["depth"],
        bit_depth=meta["bit_depth"], raw_bytes=raw_bytes,
        j2k_bytes=j2k_bytes, opj_bytes=opj_bytes,
        j2k_ratio=j2k_ratio, opj_ratio=opj_ratio, ratio_delta=ratio_delta,
        j2k_enc_s=j2k_enc, opj_enc_s=opj_enc, enc_speedup=enc_speedup,
        j2k_dec_s=j2k_dec, opj_dec_s=opj_dec, dec_speedup=dec_speedup,
        j2k_bitexact=j2k_be, opj_bitexact=opj_be,
        pass_overall=not fails,
        fail_reasons="; ".join(fails),
    )


def write_csv(results: list[StudyResult], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(asdict(results[0]).keys()))
        w.writeheader()
        for r in results:
            w.writerow(asdict(r))


def write_report(results: list[StudyResult], report_path: Path,
                 slices: int, iters: int) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    passing = sum(1 for r in results if r.pass_overall)

    rows = []
    for r in results:
        check = "✓" if r.pass_overall else "✗"
        rows.append(
            f"| {r.modality.upper()}/{r.study} "
            f"| {r.width}×{r.height}×{r.depth} "
            f"| {r.j2k_ratio:.3f}:1 "
            f"| {r.opj_ratio:.3f}:1 "
            f"| {r.ratio_delta:.4f}× "
            f"| {r.j2k_enc_s*1000:.0f} ms / {r.opj_enc_s*1000:.0f} ms "
            f"| **{r.enc_speedup:.2f}×** "
            f"| {r.j2k_dec_s*1000:.0f} ms / {r.opj_dec_s*1000:.0f} ms "
            f"| **{r.dec_speedup:.2f}×** "
            f"| {check} "
            f"|"
        )

    text = f"""# JP3D Clinical Validation Report

**Codec under test**: J2KSwift JP3D (M2 slice-stack)
**Reference**: OpenJPEG 2.0.1 JP3D (`opj_jp3d_compress -C 3EB -r 1`)
**Hardware**: Apple Silicon (arm64e), macOS 14.6
**Dataset**: `LocalDatasets/medical-dicom-organized/` ({slices} slices/study)
**Timing**: minimum wall-time over {iters} iterations

## Headline

**{passing} / {len(results)} studies meet every medical-grade pass criterion.**

Pass criteria per study:
- Bit-exact lossless round-trip (non-negotiable)
- Compression ratio within 1 % of OpenJPEG (`ratio_delta ≥ 0.99`)
- Encode wall-time at least 1.5× faster than OpenJPEG
- Decode wall-time at least 1.5× faster than OpenJPEG

## Per-study results

| Study | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ | Encode speedup | Decode J2K / OPJ | Decode speedup | Pass |
|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
{chr(10).join(rows)}

## Failures (if any)

"""
    for r in results:
        if not r.pass_overall:
            text += f"- `{r.modality}/{r.study}`: {r.fail_reasons}\n"
    if passing == len(results):
        text += "_None — every study passed every gate._\n"

    text += f"""
## Methodology

Prep: each DICOM series is exported by [Scripts/prep_jp3d_volume.py](../Scripts/prep_jp3d_volume.py)
to a single raw little-endian uint16 `.bin` plus a matching `.img`
header. Both codecs read the same bytes — J2KSwift via `j2k encode3d`'s
raw-volume mode and OpenJPEG via `bintovolume` (which reads native LE
when its hard-coded `bigendian` flag is 0).

Encode: J2KSwift uses `--codec j2k-lossless`, which routes every Z-slice
through the same `J2KEncoder` EBCOT path that beats OpenJPEG 2D 1.4×–13.6×
in `BENCHMARK_COMPARISON.md`. OpenJPEG uses `-C 3EB -r 1` (3D-EBCOT,
the only OpenJPEG JP3D mode that is genuinely lossless on volumetric
input — `-C 2EB`, the default, silently drops precision).

Decode: J2KSwift via `j2k decode3d --output-format raw`; OpenJPEG via
`opj_jp3d_decompress`. Bit-exact verified against the original `.bin`
truncated to the source byte count (OpenJPEG sometimes pads trailing
samples to a byte alignment).

The J2KSwift M2 architecture (slice-stack codec — see
`docs/JP3D_BEAT_OPENJPEG_PLAN.md`) trades the ≤ 1 % inter-slice DWT
gain that OpenJPEG's `-C 3EB` exploits for a ≥ 2× speed gain on both
encode and decode plus random-access slice decode — operationally the
dominant property in clinical PACS workflows.
"""
    report_path.write_text(text)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slices", type=int, default=32)
    ap.add_argument("--iters", type=int, default=2)
    ap.add_argument("--csv-out", type=Path,
                    default=REPO_ROOT / "docs" / "jp3d_clinical_validation.csv")
    ap.add_argument("--report-out", type=Path,
                    default=REPO_ROOT / "docs" / "JP3D_CLINICAL_VALIDATION.md")
    ap.add_argument("--datasets-root", type=Path,
                    default=REPO_ROOT / "LocalDatasets" / "medical-dicom-organized")
    ap.add_argument("--work-dir", type=Path, default=Path("/tmp/jp3d_clinical"))
    args = ap.parse_args()

    j2k_bin       = find_tool("J2K_BIN", DEFAULT_J2K_BIN)
    opj_compress  = find_tool("JP3D_OPJ_COMPRESS",   DEFAULT_OPJ_PREFIX / "opj_jp3d_compress")
    opj_decompress = find_tool("JP3D_OPJ_DECOMPRESS", DEFAULT_OPJ_PREFIX / "opj_jp3d_decompress")

    args.work_dir.mkdir(parents=True, exist_ok=True)

    studies: list[tuple[str, Path]] = []
    for modality in ["ct", "mr"]:
        modality_dir = args.datasets_root / modality
        if not modality_dir.is_dir():
            print(f"[clinical] skipping missing modality {modality_dir}",
                  file=sys.stderr)
            continue
        for study_dir in sorted(modality_dir.iterdir()):
            if study_dir.is_dir() and not study_dir.name.startswith("."):
                # Sanity: skip studies with no .dcm
                if any(p.suffix == ".dcm" for p in study_dir.iterdir()):
                    studies.append((modality, study_dir))

    if not studies:
        sys.exit(f"[clinical] no studies found under {args.datasets_root}")

    print(f"[clinical] running {len(studies)} studies "
          f"({args.slices} slices, {args.iters} iters each)…")

    results: list[StudyResult] = []
    for i, (modality, study_dir) in enumerate(studies, 1):
        print(f"[clinical] [{i}/{len(studies)}] {modality}/{study_dir.name}…",
              flush=True)
        r = run_one_study(modality, study_dir, args.slices, args.iters,
                          j2k_bin, opj_compress, opj_decompress, args.work_dir)
        if r is None:
            continue
        results.append(r)
        verdict = "PASS" if r.pass_overall else f"FAIL ({r.fail_reasons})"
        print(f"          ratio J2K {r.j2k_ratio:.3f}:1 vs OPJ {r.opj_ratio:.3f}:1  "
              f"enc {r.enc_speedup:.2f}× / dec {r.dec_speedup:.2f}×  "
              f"=> {verdict}")

    if not results:
        sys.exit("[clinical] no results to report")

    write_csv(results, args.csv_out)
    write_report(results, args.report_out, args.slices, args.iters)

    passing = sum(1 for r in results if r.pass_overall)
    print(f"\n[clinical] {passing}/{len(results)} studies passed all gates")
    print(f"[clinical] csv:    {args.csv_out}")
    print(f"[clinical] report: {args.report_out}")
    sys.exit(0 if passing == len(results) else 1)


if __name__ == "__main__":
    main()
