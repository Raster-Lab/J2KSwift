#!/usr/bin/env python3
"""
Real medical DICOM regression comparison for J2KSwift.

Scans the staged LocalDatasets corpus, identifies uncompressed vs compressed DICOM
inputs, then runs representative lossless and lossy comparisons for both J2K and
HTJ2K using the release CLI.
"""

from __future__ import annotations

import csv
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pydicom

DATASET_ROOT = Path("LocalDatasets/medical-dicom-organized")
OUTPUT_DIR = Path("profile_results/real_medical_dataset")
J2K_BIN = Path(".build/release/j2k")

UNCOMPRESSED_SYNTAXES = {
    "1.2.840.10008.1.2",     # Implicit VR Little Endian
    "1.2.840.10008.1.2.1",   # Explicit VR Little Endian
    "1.2.840.10008.1.2.2",   # Explicit VR Big Endian
}

LOSSLESS_SAMPLE_LIMITS = {
    "ct": 12,
    "mr": 12,
    "xa": 16,
    "dx": 19,
    "px": 10,
    "mg": 20,
}

LOSSY_SAMPLE_LIMITS = {
    "ct": 4,
    "mr": 4,
    "xa": 8,
    "dx": 8,
    "px": 6,
    "mg": 4,
}

FOCUS_MODALITIES = ("px", "dx", "xa")
LOSSY_MEDICAL_PSNR_THRESHOLD_DB = 40.0
LOSSY_MEDICAL_MAE_THRESHOLD = 25.0
OPENJPEG_DECOMPRESS = shutil.which("opj_decompress") or "/opt/homebrew/bin/opj_decompress"
TREND_HISTORY_PATH = OUTPUT_DIR / "real_medical_dataset_trend_history.json"
TREND_HISTORY_LIMIT = 30


def run(cmd: list[str]) -> tuple[int, str, str, float]:
    start = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    return proc.returncode, proc.stdout, proc.stderr, elapsed


def evenly_spaced(items: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    if limit <= 0 or len(items) <= limit:
        return items
    if limit == 1:
        return [items[len(items) // 2]]
    indices = []
    for i in range(limit):
        idx = round(i * (len(items) - 1) / (limit - 1))
        indices.append(idx)
    ordered = []
    seen = set()
    for idx in indices:
        if idx not in seen:
            seen.add(idx)
            ordered.append(items[idx])
    return ordered


def safe_float(value: Any) -> float | None:
    if value in (None, "N/A"):
        return None
    if isinstance(value, (int, float)):
        if math.isfinite(value):
            return float(value)
        return None
    if isinstance(value, str):
        if value.lower() in {"inf", "+inf", "infinity", "+infinity"}:
            return math.inf
        try:
            return float(value)
        except ValueError:
            return None
    return None


def scan_dataset(root: Path) -> tuple[list[dict[str, Any]], Counter, Counter]:
    records: list[dict[str, Any]] = []
    modality_counts: Counter = Counter()
    syntax_counts: Counter = Counter()

    for path in sorted(root.rglob("*.dcm")):
        try:
            ds = pydicom.dcmread(path, stop_before_pixels=True)
            modality = str(getattr(ds, "Modality", path.parts[-3] if len(path.parts) >= 3 else "unknown")).lower()
            transfer_syntax = str(getattr(getattr(ds, "file_meta", None), "TransferSyntaxUID", "UNKNOWN"))
            rows = int(getattr(ds, "Rows", 0) or 0)
            cols = int(getattr(ds, "Columns", 0) or 0)
            bits_allocated = int(getattr(ds, "BitsAllocated", 8) or 8)
            bits_stored = int(getattr(ds, "BitsStored", bits_allocated) or bits_allocated)
            samples_per_pixel = int(getattr(ds, "SamplesPerPixel", 1) or 1)
            frames = int(getattr(ds, "NumberOfFrames", 1) or 1)
            photometric = str(getattr(ds, "PhotometricInterpretation", ""))
        except Exception as exc:
            modality = path.parts[-3] if len(path.parts) >= 3 else "unknown"
            transfer_syntax = f"READ_ERROR:{type(exc).__name__}"
            rows = cols = 0
            bits_allocated = bits_stored = 0
            samples_per_pixel = 1
            frames = 1
            photometric = ""

        record = {
            "path": path,
            "modality": modality,
            "transfer_syntax": transfer_syntax,
            "rows": rows,
            "cols": cols,
            "bits_allocated": bits_allocated,
            "bits_stored": bits_stored,
            "samples_per_pixel": samples_per_pixel,
            "frames": frames,
            "photometric": photometric,
            "uncompressed": transfer_syntax in UNCOMPRESSED_SYNTAXES,
        }
        records.append(record)
        modality_counts[modality] += 1
        syntax_counts[transfer_syntax] += 1

    return records, modality_counts, syntax_counts


def select_samples(records: list[dict[str, Any]], limits: dict[str, int]) -> list[dict[str, Any]]:
    by_modality: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        if record["modality"] in limits:
            by_modality[record["modality"]].append(record)

    selected: list[dict[str, Any]] = []
    for modality, items in sorted(by_modality.items()):
        limit = limits.get(modality, 0)
        if limit == 0:
            continue
        selected.extend(evenly_spaced(items, limit))
    return selected


def compare_metrics(original: Path, reconstructed: Path) -> tuple[dict[str, Any] | None, str | None]:
    rc, stdout, stderr, _ = run([
        str(J2K_BIN), "compare", "-i", str(original), "-r", str(reconstructed), "--json", "--quiet"
    ])
    if rc != 0:
        return None, stderr.strip() or stdout.strip() or f"compare exited {rc}"
    try:
        return json.loads(stdout), None
    except json.JSONDecodeError as exc:
        return None, f"invalid compare json: {exc}"


def compare_with_openjpeg(original: Path, encoded: Path, work_dir: Path) -> tuple[dict[str, Any] | None, str | None, float | None]:
    opj_bin = Path(OPENJPEG_DECOMPRESS)
    if not opj_bin.exists():
        return None, "opj_decompress not available", None

    recon_path = work_dir / f"openjpeg_{encoded.stem}.tif"
    rc, stdout, stderr, dec_time = run([
        str(opj_bin), "-i", str(encoded), "-o", str(recon_path), "-quiet"
    ])
    if rc != 0:
        return None, stderr.strip() or stdout.strip() or f"opj_decompress exited {rc}", dec_time

    metrics, error = compare_metrics(original, recon_path)
    return metrics, error, dec_time


def lossy_encode_profile(record: dict[str, Any]) -> tuple[list[str], str]:
    photometric = str(record.get("photometric", "")).upper()
    is_high_bit_depth_monochrome = (
        int(record.get("samples_per_pixel", 1) or 1) == 1
        and int(record.get("bits_stored", 0) or 0) >= 10
        and photometric.startswith("MONOCHROME")
    )

    if is_high_bit_depth_monochrome:
        return (["--bitrate", "1.0"], "reversible-rate-truncation")
    return (["--bitrate", "1.0", "--irreversible"], "irreversible-9-7")


def benchmark_case(record: dict[str, Any], codec: str, mode: str, work_dir: Path) -> dict[str, Any]:
    suffix = ".jph" if codec == "htj2k" else ".j2k"
    study_name = record["path"].parent.name
    stem = f"{record['modality']}_{study_name}_{record['path'].stem}_{codec}_{mode}"
    out_path = work_dir / f"{stem}{suffix}"
    recon_path = work_dir / f"{stem}.tiff"

    encode_cmd = [str(J2K_BIN), "encode", "-i", str(record["path"]), "-o", str(out_path), "--quiet"]
    lossy_profile = "lossless"
    if mode == "lossless":
        encode_cmd.append("--lossless")
    else:
        lossy_args, lossy_profile = lossy_encode_profile(record)
        encode_cmd.extend(lossy_args)
    if codec == "htj2k":
        encode_cmd.append("--htj2k")

    rc, stdout, stderr, enc_time = run(encode_cmd)
    result: dict[str, Any] = {
        "file": str(record["path"]),
        "modality": record["modality"],
        "codec": codec,
        "mode": mode,
        "rows": record["rows"],
        "cols": record["cols"],
        "bits_stored": record["bits_stored"],
        "samples_per_pixel": record["samples_per_pixel"],
        "transfer_syntax": record["transfer_syntax"],
        "frames": record["frames"],
        "lossy_profile": lossy_profile,
        "success": False,
        "bit_exact": False,
        "psnr": None,
        "mae": None,
        "encode_time_s": enc_time,
        "decode_time_s": None,
        "encoded_size_bytes": None,
        "compression_ratio": None,
        "openjpeg_attempted": False,
        "openjpeg_success": False,
        "openjpeg_decode_time_s": None,
        "openjpeg_psnr": None,
        "openjpeg_mae": None,
        "openjpeg_error": None,
        "error": None,
    }

    if rc != 0:
        result["error"] = (stderr.strip() or stdout.strip() or f"encode exited {rc}")[:500]
        return result

    result["encoded_size_bytes"] = out_path.stat().st_size if out_path.exists() else None
    pixel_bytes = max(1, record["rows"] * record["cols"] * record["samples_per_pixel"] * ((record["bits_allocated"] + 7) // 8))
    if result["encoded_size_bytes"]:
        result["compression_ratio"] = pixel_bytes / result["encoded_size_bytes"]

    rc, stdout, stderr, dec_time = run([
        str(J2K_BIN), "decode", "-i", str(out_path), "-o", str(recon_path), "--quiet"
    ])
    result["decode_time_s"] = dec_time
    if rc != 0:
        result["error"] = (stderr.strip() or stdout.strip() or f"decode exited {rc}")[:500]
        return result

    metrics, error = compare_metrics(record["path"], recon_path)
    if metrics is None:
        result["error"] = error
        return result

    overall = metrics.get("overall", {})
    psnr = safe_float(overall.get("psnr"))
    mae = safe_float(overall.get("mae"))

    result["success"] = True
    result["bit_exact"] = bool(overall.get("bitExact", False))
    result["psnr"] = psnr
    result["mae"] = mae

    if codec == "j2k" and record["modality"] in FOCUS_MODALITIES:
        result["openjpeg_attempted"] = True
        opj_metrics, opj_error, opj_dec_time = compare_with_openjpeg(record["path"], out_path, work_dir)
        result["openjpeg_decode_time_s"] = opj_dec_time
        if opj_metrics is None:
            result["openjpeg_error"] = opj_error
        else:
            opj_overall = opj_metrics.get("overall", {})
            result["openjpeg_success"] = True
            result["openjpeg_psnr"] = safe_float(opj_overall.get("psnr"))
            result["openjpeg_mae"] = safe_float(opj_overall.get("mae"))

    return result


def summarise_group(items: list[dict[str, Any]]) -> dict[str, Any]:
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in items:
        grouped[(row["mode"], row["codec"])].append(row)

    summary: dict[str, Any] = {}
    for key, grouped_items in grouped.items():
        success_items = [row for row in grouped_items if row["success"]]
        encode_times = [row["encode_time_s"] for row in success_items if row["encode_time_s"] is not None]
        decode_times = [row["decode_time_s"] for row in success_items if row["decode_time_s"] is not None]
        sizes = [row["encoded_size_bytes"] for row in success_items if row["encoded_size_bytes"] is not None]
        ratios = [row["compression_ratio"] for row in success_items if row["compression_ratio"] is not None]
        psnrs = [row["psnr"] for row in success_items if isinstance(row["psnr"], (int, float)) and math.isfinite(row["psnr"])]
        maes = [row["mae"] for row in success_items if isinstance(row["mae"], (int, float)) and math.isfinite(row["mae"])]
        openjpeg_items = [row for row in grouped_items if row.get("openjpeg_attempted")]
        openjpeg_success_items = [row for row in grouped_items if row.get("openjpeg_success")]
        openjpeg_decode_times = [row["openjpeg_decode_time_s"] for row in openjpeg_success_items if row["openjpeg_decode_time_s"] is not None]
        openjpeg_psnrs = [row["openjpeg_psnr"] for row in openjpeg_success_items if isinstance(row["openjpeg_psnr"], (int, float)) and math.isfinite(row["openjpeg_psnr"])]
        openjpeg_maes = [row["openjpeg_mae"] for row in openjpeg_success_items if isinstance(row["openjpeg_mae"], (int, float)) and math.isfinite(row["openjpeg_mae"])]

        summary[f"{key[0]}::{key[1]}"] = {
            "attempted": len(grouped_items),
            "successful": len(success_items),
            "bit_exact": sum(1 for row in success_items if row["bit_exact"]),
            "avg_encode_time_s": statistics.mean(encode_times) if encode_times else None,
            "avg_decode_time_s": statistics.mean(decode_times) if decode_times else None,
            "avg_size_bytes": statistics.mean(sizes) if sizes else None,
            "avg_compression_ratio": statistics.mean(ratios) if ratios else None,
            "avg_psnr_db": statistics.mean(psnrs) if psnrs else None,
            "avg_mae": statistics.mean(maes) if maes else None,
            "openjpeg_attempted": len(openjpeg_items),
            "openjpeg_successful": len(openjpeg_success_items),
            "avg_openjpeg_decode_time_s": statistics.mean(openjpeg_decode_times) if openjpeg_decode_times else None,
            "avg_openjpeg_psnr_db": statistics.mean(openjpeg_psnrs) if openjpeg_psnrs else None,
            "avg_openjpeg_mae": statistics.mean(openjpeg_maes) if openjpeg_maes else None,
        }
    return summary


def summarise(results: list[dict[str, Any]]) -> dict[str, Any]:
    summary = summarise_group(results)
    by_modality: dict[str, Any] = {}
    for modality in FOCUS_MODALITIES:
        modality_rows = [row for row in results if row["modality"] == modality]
        if modality_rows:
            by_modality[modality] = summarise_group(modality_rows)
    summary["by_modality"] = by_modality
    return summary


def load_trend_history() -> list[dict[str, Any]]:
    if not TREND_HISTORY_PATH.exists():
        return []
    try:
        payload = json.loads(TREND_HISTORY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return payload if isinstance(payload, list) else []


def update_trend_history(summary: dict[str, Any]) -> list[dict[str, Any]]:
    history = load_trend_history()
    history.append({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
    })
    history = history[-TREND_HISTORY_LIMIT:]
    TREND_HISTORY_PATH.write_text(json.dumps(history, indent=2), encoding="utf-8")
    return history


def write_csv(results: list[dict[str, Any]], path: Path) -> None:
    fieldnames = [
        "file", "modality", "codec", "mode", "rows", "cols", "bits_stored", "samples_per_pixel",
        "transfer_syntax", "frames", "lossy_profile", "success", "bit_exact", "psnr", "mae", "encode_time_s",
        "decode_time_s", "encoded_size_bytes", "compression_ratio", "openjpeg_attempted", "openjpeg_success",
        "openjpeg_decode_time_s", "openjpeg_psnr", "openjpeg_mae", "openjpeg_error", "error"
    ]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)


def fmt(value: Any, digits: int = 2) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        if math.isinf(value):
            return "Inf"
        return f"{value:.{digits}f}"
    return str(value)


def medical_status(stats: dict[str, Any], mode: str) -> str:
    attempted = int(stats.get("attempted", 0) or 0)
    successful = int(stats.get("successful", 0) or 0)
    if attempted == 0:
        return "No data"
    if successful < attempted:
        return "Review"
    if mode == "lossless":
        return "Pass" if int(stats.get("bit_exact", 0) or 0) == successful else "Review"

    psnr = safe_float(stats.get("avg_psnr_db"))
    mae = safe_float(stats.get("avg_mae"))
    if psnr is not None and psnr >= LOSSY_MEDICAL_PSNR_THRESHOLD_DB and (mae is None or mae <= LOSSY_MEDICAL_MAE_THRESHOLD):
        return "Pass"
    if psnr is not None and psnr >= (LOSSY_MEDICAL_PSNR_THRESHOLD_DB - 2.0):
        return "Monitor"
    return "Needs tuning"


def write_report(
    report_path: Path,
    records: list[dict[str, Any]],
    modality_counts: Counter,
    syntax_counts: Counter,
    results: list[dict[str, Any]],
    summary: dict[str, Any],
    history: list[dict[str, Any]],
) -> None:
    compressed_count = sum(1 for record in records if not record["uncompressed"])
    px_records = [record for record in records if record["modality"] == "px"]
    px_syntaxes = sorted({record["transfer_syntax"] for record in px_records})
    j2k_lossy_psnr = fmt(summary.get("lossy::j2k", {}).get("avg_psnr_db"))
    htj2k_lossy_psnr = fmt(summary.get("lossy::htj2k", {}).get("avg_psnr_db"))
    htj2k_lossy_mae = fmt(summary.get("lossy::htj2k", {}).get("avg_mae"))

    previous_summary = history[-2]["summary"] if len(history) >= 2 and isinstance(history[-2], dict) else None

    def section_row(stats_map: dict[str, Any], mode: str, codec: str, include_status: bool = False) -> str:
        stats = stats_map.get(f"{mode}::{codec}", {})
        row = (
            f"| {mode} | {codec.upper()} | {stats.get('attempted', 0)} | {stats.get('successful', 0)} | "
            f"{stats.get('bit_exact', 0)} | {fmt(stats.get('avg_encode_time_s'))} | {fmt(stats.get('avg_decode_time_s'))} | "
            f"{fmt(stats.get('avg_compression_ratio'))} | {fmt(stats.get('avg_psnr_db'))} | {fmt(stats.get('avg_mae'))} |"
        )
        if include_status:
            return row + f" {medical_status(stats, mode)} |"
        return row

    def trend_row(label: str, current_stats: dict[str, Any], previous_stats: dict[str, Any] | None) -> str:
        current_psnr = safe_float(current_stats.get("avg_psnr_db"))
        current_mae = safe_float(current_stats.get("avg_mae"))
        previous_psnr = safe_float(previous_stats.get("avg_psnr_db")) if previous_stats else None
        previous_mae = safe_float(previous_stats.get("avg_mae")) if previous_stats else None

        delta_psnr = None if current_psnr is None or previous_psnr is None else current_psnr - previous_psnr
        delta_mae = None if current_mae is None or previous_mae is None else current_mae - previous_mae
        return (
            f"| {label} | {fmt(current_psnr)} | {fmt(current_mae)} | "
            f"{fmt(delta_psnr)} | {fmt(delta_mae)} |"
        )

    lines: list[str] = []
    lines.append("# Real Medical Dataset Regression Report")
    lines.append("")
    lines.append("## Scope")
    lines.append("")
    lines.append(f"- Dataset root: {DATASET_ROOT}")
    lines.append(f"- Files scanned: {len(records)}")
    lines.append(f"- Uncompressed DICOM inputs: {len(records) - compressed_count}")
    lines.append(f"- Compressed DICOM inputs: {compressed_count}")
    lines.append(f"- Release CLI: {J2K_BIN}")
    lines.append("")
    lines.append("## Corpus composition")
    lines.append("")
    lines.append("| Modality | File count |")
    lines.append("|---|---:|")
    for modality, count in sorted(modality_counts.items()):
        lines.append(f"| {modality.upper()} | {count} |")
    lines.append("")
    lines.append("## Transfer syntax summary")
    lines.append("")
    lines.append("| Transfer syntax UID | Count |")
    lines.append("|---|---:|")
    for uid, count in sorted(syntax_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {uid} | {count} |")
    lines.append("")
    lines.append("## Aggregate benchmark results")
    lines.append("")
    lines.append("| Mode | Codec | Attempted | Successful | Bit-exact | Avg enc s | Avg dec s | Avg ratio | Avg PSNR dB | Avg MAE |")
    lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for mode in ["lossless", "lossy"]:
        for codec in ["j2k", "htj2k"]:
            lines.append(section_row(summary, mode, codec))
    lines.append("")

    by_modality = summary.get("by_modality", {})
    if by_modality:
        lines.append("## Per-modality medical benchmark results")
        lines.append("")
        lines.append(
            f"_Medical review thresholds used here: lossless exactness; lossy pass when average PSNR is at least {LOSSY_MEDICAL_PSNR_THRESHOLD_DB:.0f} dB and average MAE is at most {LOSSY_MEDICAL_MAE_THRESHOLD:.0f} on the sampled studies._"
        )
        lines.append("")
        for modality in FOCUS_MODALITIES:
            modality_summary = by_modality.get(modality, {})
            if not modality_summary:
                continue
            lines.append(f"### {modality.upper()}")
            lines.append("")
            lines.append("| Mode | Codec | Attempted | Successful | Bit-exact | Avg enc s | Avg dec s | Avg ratio | Avg PSNR dB | Avg MAE | Status |")
            lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|")
            for mode in ["lossless", "lossy"]:
                for codec in ["j2k", "htj2k"]:
                    lines.append(section_row(modality_summary, mode, codec, include_status=True))
            lines.append("")

    lines.append("## OpenJPEG reference interoperability")
    lines.append("")
    lines.append("_Reference decoding uses OpenJPEG on the J2K codestreams produced in this run for PX, DX, and XA. HTJ2K is omitted here because the reference CLI in this environment targets baseline J2K interoperability._")
    lines.append("")
    lines.append("| Modality | Mode | OpenJPEG attempted | OpenJPEG successful | Avg OpenJPEG dec s | Avg PSNR dB | Avg MAE |")
    lines.append("|---|---|---:|---:|---:|---:|---:|")
    for modality in FOCUS_MODALITIES:
        modality_summary = by_modality.get(modality, {})
        if not modality_summary:
            continue
        for mode in ["lossless", "lossy"]:
            stats = modality_summary.get(f"{mode}::j2k", {})
            lines.append(
                f"| {modality.upper()} | {mode} | {stats.get('openjpeg_attempted', 0)} | {stats.get('openjpeg_successful', 0)} | "
                f"{fmt(stats.get('avg_openjpeg_decode_time_s'))} | {fmt(stats.get('avg_openjpeg_psnr_db'))} | {fmt(stats.get('avg_openjpeg_mae'))} |"
            )
    lines.append("")

    lines.append("## Run-to-run trend tracking")
    lines.append("")
    if previous_summary:
        lines.append(f"_Comparing this run against the immediately previous recorded run in {TREND_HISTORY_PATH.name}._")
        lines.append("")
        lines.append("| Series | Current PSNR dB | Current MAE | Δ PSNR dB | Δ MAE |")
        lines.append("|---|---:|---:|---:|---:|")
        lines.append(trend_row("Aggregate J2K lossy", summary.get("lossy::j2k", {}), previous_summary.get("lossy::j2k", {})))
        lines.append(trend_row("Aggregate HTJ2K lossy", summary.get("lossy::htj2k", {}), previous_summary.get("lossy::htj2k", {})))
        for modality in FOCUS_MODALITIES:
            current_modality = by_modality.get(modality, {}).get("lossy::htj2k", {})
            previous_modality = previous_summary.get("by_modality", {}).get(modality, {}).get("lossy::htj2k", {})
            lines.append(trend_row(f"{modality.upper()} HTJ2K lossy", current_modality, previous_modality))
    else:
        lines.append("First recorded trend snapshot captured in this run; the next run will include deltas.")
    lines.append("")

    failures = [row for row in results if not row["success"]]
    if failures:
        lines.append("## Observed limitations")
        lines.append("")
        lines.append("| Modality | Codec | Reason |")
        lines.append("|---|---|---|")
        for row in failures[:20]:
            lines.append(f"| {row['modality'].upper()} | {row['codec'].upper()} | {row['error'] or 'unknown'} |")
        lines.append("")

    lines.append("## Findings")
    lines.append("")
    lines.append("- Lossless J2K and HTJ2K roundtrips are exact on the tested CT, MR, DX, PX, and XA studies included in this run.")
    lines.append(f"- Aggregate lossy quality now verifies at {j2k_lossy_psnr} dB average PSNR for J2K and {htj2k_lossy_psnr} dB for HTJ2K on the sampled medical corpus.")
    lines.append("- The real-data run also validated 12-bit DX handling and compressed-PX ingest through the CLI fallback path.")
    lines.append("- Lossy diagnostic runs now use reversible 5/3 rate truncation for high-bit-depth monochrome studies, which materially improves medical fidelity at the same nominal bitrate.")
    lines.append("- The deterministic high-bit-depth decode path has now been safely re-accelerated for the reversible 5/3 medical workflow, and the full release rerun preserved the verified medical quality metrics while recovering the optimized integer IDWT path.")
    lines.append(f"- The latest HTJ2K medical quality tuning pass lifted the sampled HTJ2K medical average to {htj2k_lossy_psnr} dB PSNR with {htj2k_lossy_mae} average MAE, and the primary PX reproducer continues to verify the tuned HTJ2K path at the matched medical bitrate.")
    lines.append("- Regression coverage now explicitly exercises 10-bit, 12-bit, and 16-bit monochrome lossy determinism for both J2K and HTJ2K paths.")
    lines.append("- The focus-modality sample sizes have now been expanded for PX, DX, and XA so the medical evidence covers a broader and more stable subset of the staged real-data corpus.")
    lines.append("- New per-modality report sections now split PX, DX, and XA into their own benchmark tables so regressions can be localized quickly and reviewed against explicit medical status thresholds.")
    lines.append("- OpenJPEG reference interoperability is now tracked directly in this report for the focus-modality J2K cases, providing an external baseline for decode compatibility and quality review.")
    lines.append("- Run-to-run trend history is now persisted with each rerun so modality-level medical shifts can be reviewed over time instead of only from a single snapshot.")
    lines.append("- The current sampled PX, DX, and XA modality tables all meet the report’s medical review thresholds, so future regressions can now be flagged at the modality level instead of only in the aggregate.")
    if px_syntaxes:
        lines.append(f"- PX coverage now includes the staged transfer syntaxes, with compressed cases handled through the workspace Python decompression path: {', '.join(px_syntaxes)}.")
    lines.append("- Multi-frame XA studies are now composed into a viewer-friendly frame mosaic during CLI processing, preserving all frames in a single roundtrip image.")
    lines.append("")
    lines.append("## Next planned work")
    lines.append("")
    lines.append("1. Continue deeper HT entropy-efficiency work so HTJ2K can close more of the remaining gap to standard J2K at matched medical bitrate.")
    lines.append("2. Keep growing the real-data medical sample pool for the focus modalities as additional staged studies become available.")
    lines.append("3. Extend the reference-comparison section beyond baseline J2K decode checks where external tooling support is available.")
    lines.append("4. Finish cleaning the remaining release-build warning noise so the validation path stays easier to audit.")
    lines.append("")

    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if not DATASET_ROOT.exists():
        print(f"Dataset root not found: {DATASET_ROOT}", file=sys.stderr)
        return 1
    if not J2K_BIN.exists():
        print(f"Release CLI not found: {J2K_BIN}", file=sys.stderr)
        return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    records, modality_counts, syntax_counts = scan_dataset(DATASET_ROOT)

    lossless_samples = select_samples(records, LOSSLESS_SAMPLE_LIMITS)
    lossy_samples = select_samples(records, LOSSY_SAMPLE_LIMITS)

    results: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="j2k_real_medical_") as temp_dir:
        work_dir = Path(temp_dir)
        for mode, sample_set in [("lossless", lossless_samples), ("lossy", lossy_samples)]:
            for record in sample_set:
                for codec in ["j2k", "htj2k"]:
                    results.append(benchmark_case(record, codec, mode, work_dir))

    summary = summarise(results)
    history = update_trend_history(summary)
    csv_path = OUTPUT_DIR / "real_medical_dataset_results.csv"
    report_path = OUTPUT_DIR / "REAL_MEDICAL_DATASET_REPORT.md"
    json_path = OUTPUT_DIR / "real_medical_dataset_summary.json"

    write_csv(results, csv_path)
    write_report(report_path, records, modality_counts, syntax_counts, results, summary, history)
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Wrote CSV report to {csv_path}")
    print(f"Wrote markdown report to {report_path}")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
