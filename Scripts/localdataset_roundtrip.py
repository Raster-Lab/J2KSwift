#!/usr/bin/env python3
"""
localdataset_roundtrip.py — exhaustive encode/decode harness for LocalDatasets.

Drives the `j2k` CLI over every DICOM image in a dataset tree and records,
per file, whether it:

  1. ENCODES   (DICOM  -> lossless JPEG 2000 codestream)
  2. DECODES   (codestream -> PGM/PPM raster)
  3. VERIFIES  (optional: decoded pixels are bit-identical to the source
                DICOM pixels read via pydicom — true lossless round-trip)

Outputs a per-file CSV and a human-readable Markdown report grouped by
modality and failure class.

Why the CLI and not an in-process harness: testers exercise the shipped
`j2k` binary, so this reproduces exactly what they see. Each file is an
independent process, so one bad image can never abort the whole run.

Usage:
  python3 Scripts/localdataset_roundtrip.py \
      --dataset LocalDatasets/medical-dicom-organized \
      --bin .build/release/j2k \
      --workers 8 \
      --out results/localdataset_roundtrip \
      [--verify] [--verify-sample 200] [--modality ct,mr] [--limit N]

Environment:
  J2K_DICOM_PYTHON is set automatically to --python so the CLI can
  decompress JPEG/JPEG-LS/J2K-encapsulated DICOM (e.g. the `px` set).
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import random
import struct
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict, field
from pathlib import Path

# ----------------------------------------------------------------------------
# Module-level config. We use a ThreadPoolExecutor (not ProcessPoolExecutor):
# every unit of work is a `subprocess.run()` call which releases the GIL while
# the j2k child runs, so threads give full parallelism with none of the
# ProcessPoolExecutor+subprocess+macOS-spawn deadlock (forking a pool worker to
# launch a subprocess while it holds multiprocessing semaphore/pipe FDs wedges
# the task queues — observed first-hand). Threads share these globals directly.
# ----------------------------------------------------------------------------
_BIN = ""
_PYTHON = ""
_ENCODE_TIMEOUT = 120
_DECODE_TIMEOUT = 120


def configure(binary: str, python: str, enc_to: int, dec_to: int):
    global _BIN, _PYTHON, _ENCODE_TIMEOUT, _DECODE_TIMEOUT
    _BIN = binary
    _PYTHON = python
    _ENCODE_TIMEOUT = enc_to
    _DECODE_TIMEOUT = dec_to
    # Let the CLI shell out to this interpreter for compressed DICOM.
    os.environ["J2K_DICOM_PYTHON"] = python


@dataclass
class Result:
    path: str
    modality: str               # top-level folder (CT, MR, US, ...)
    study: str
    status: str = "OK"          # OK | ENCODE_FAIL | DECODE_FAIL | VERIFY_MISMATCH | VERIFY_SKIP
    # --- DICOM "type" fields (what kind of data was tested) ---
    sop_class: str = ""         # e.g. "CT Image Storage", "Raw Data Storage"
    dicom_modality: str = ""    # (0008,0060) Modality
    transfer_syntax: str = ""
    photometric: str = ""       # MONOCHROME2, YBR_FULL_422, RGB, ...
    samples_per_pixel: int = 1
    bits_allocated: int = 0
    bits_stored: int = 0
    signed: int = 0             # PixelRepresentation (1 = signed)
    is_image: int = 1           # 0 if no pixel data (report/raw object)
    compressed: int = 0         # 1 if encapsulated/compressed transfer syntax
    # --- geometry / round-trip ---
    width: int = 0
    height: int = 0
    components: int = 0
    frames: int = 1
    src_bytes: int = 0
    j2k_bytes: int = 0
    enc_seconds: float = 0.0
    dec_seconds: float = 0.0
    detail: str = ""            # error/mismatch detail (first stderr line, etc.)


# ----------------------------------------------------------------------------
# Lightweight DICOM header sniff — transfer syntax + a couple of tags — done
# in pure Python so we can label every file even when encode fails.
# ----------------------------------------------------------------------------
def sniff_dicom(path: str) -> dict:
    info = {"transfer_syntax": "", "frames": 1}
    try:
        with open(path, "rb") as fh:
            head = fh.read(2048)
        if len(head) < 132 or head[128:132] != b"DICM":
            info["transfer_syntax"] = "NOT_DICOM"
            return info
        # Scan group-0002 explicit-VR-LE for TransferSyntaxUID (0002,0010).
        off = 132
        while off + 8 <= len(head):
            group = struct.unpack_from("<H", head, off)[0]
            element = struct.unpack_from("<H", head, off + 2)[0]
            if group != 0x0002:
                break
            vr = head[off + 4:off + 6]
            if vr in (b"OB", b"OW", b"OF", b"SQ", b"UT", b"UN"):
                vlen = struct.unpack_from("<I", head, off + 8)[0]
                vstart = off + 12
            else:
                vlen = struct.unpack_from("<H", head, off + 6)[0]
                vstart = off + 8
            if element == 0x0010 and vstart + vlen <= len(head):
                info["transfer_syntax"] = head[vstart:vstart + vlen].decode(
                    "ascii", "ignore").strip("\x00 ")
            off = vstart + vlen
    except Exception:
        pass
    return info


_COMPRESSED_TS = {
    # Encapsulated / compressed transfer syntaxes (decoded via pydicom helper).
    "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51",   # JPEG Baseline / Extended
    "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.70",   # JPEG Lossless
    "1.2.840.10008.1.2.4.80", "1.2.840.10008.1.2.4.81",   # JPEG-LS
    "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91",   # JPEG 2000
    "1.2.840.10008.1.2.5",                                  # RLE
}


def dicom_meta(path: str) -> dict:
    """Read DICOM type metadata (SOP class, modality, photometric, bit depth,
    samples, signedness, frames, transfer syntax, pixel-data presence). Uses
    pydicom (header-only, stop_before_pixels) for accuracy; falls back to the
    pure-Python transfer-syntax sniff if pydicom is unavailable."""
    meta = {
        "sop_class": "", "dicom_modality": "", "transfer_syntax": "",
        "photometric": "", "samples_per_pixel": 1, "bits_allocated": 0,
        "bits_stored": 0, "signed": 0, "is_image": 1, "compressed": 0, "frames": 1,
    }
    try:
        import pydicom
        ds = pydicom.dcmread(path, force=True, stop_before_pixels=True)
        scn = getattr(ds, "SOPClassUID", None)
        meta["sop_class"] = str(getattr(scn, "name", scn) or "")
        meta["dicom_modality"] = str(getattr(ds, "Modality", "") or "")
        ts = str(getattr(getattr(ds, "file_meta", None), "TransferSyntaxUID", "") or "")
        meta["transfer_syntax"] = ts
        meta["compressed"] = 1 if ts in _COMPRESSED_TS else 0
        meta["photometric"] = str(getattr(ds, "PhotometricInterpretation", "") or "")
        meta["samples_per_pixel"] = int(getattr(ds, "SamplesPerPixel", 1) or 1)
        meta["bits_allocated"] = int(getattr(ds, "BitsAllocated", 0) or 0)
        meta["bits_stored"] = int(getattr(ds, "BitsStored", 0) or 0)
        meta["signed"] = int(getattr(ds, "PixelRepresentation", 0) or 0)
        meta["frames"] = int(getattr(ds, "NumberOfFrames", 1) or 1)
        # No Rows/Columns and a report/raw SOP class => not an image.
        has_geom = (getattr(ds, "Rows", 0) and getattr(ds, "Columns", 0))
        meta["is_image"] = 1 if has_geom else 0
        return meta
    except Exception:
        # Fallback: at least the transfer syntax.
        s = sniff_dicom(path)
        meta["transfer_syntax"] = s.get("transfer_syntax", "")
        meta["compressed"] = 1 if meta["transfer_syntax"] in _COMPRESSED_TS else 0
        return meta


def _read_pgm_pixels(path: str):
    """Parse a binary PGM (P5) / PPM (P6) into a flat list of ints. Returns
    (width, height, maxval, channels, bytes-per-sample, raw-bytes)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] not in (b"P5", b"P6"):
        raise ValueError(f"not a binary PGM/PPM: {data[:2]!r}")
    channels = 1 if data[:2] == b"P5" else 3
    # Read three whitespace-separated header ints, skipping comments.
    idx = 2
    fields = []
    while len(fields) < 3:
        while idx < len(data) and data[idx:idx + 1].isspace():
            idx += 1
        if data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx:idx + 1] != b"\n":
                idx += 1
            continue
        start = idx
        while idx < len(data) and not data[idx:idx + 1].isspace():
            idx += 1
        fields.append(int(data[start:idx]))
    width, height, maxval = fields
    idx += 1  # single whitespace after maxval
    bps = 2 if maxval > 255 else 1
    return width, height, maxval, channels, bps, data[idx:]


def verify_lossless(src_path: str, decoded_path: str) -> tuple[bool, str]:
    """Bit-exact comparison of the decoded raster against the source DICOM
    pixels (as decoded by pydicom — identical to what the CLI's compressed-DICOM
    helper feeds the encoder). Handles grayscale + RGB, single- + multi-frame.

    For multi-frame, reconstructs the loader's mosaic: cols=ceil(sqrt(n)),
    rows=ceil(n/cols), frame i at tile (i%cols, i//cols) row-major, unused
    tiles zero-filled. Returns (ok, detail); only genuinely incomparable inputs
    (e.g. pydicom can't decode) yield (True, 'skip:<reason>')."""
    try:
        import numpy as np
        import pydicom
    except Exception as exc:  # pragma: no cover
        return True, f"skip:no-pydicom ({exc})"
    import math
    try:
        ds = pydicom.dcmread(src_path)
        frames = int(getattr(ds, "NumberOfFrames", 1) or 1)
        spp = int(getattr(ds, "SamplesPerPixel", 1) or 1)
        arr = np.ascontiguousarray(ds.pixel_array)
        # Source two's-complement signed -> unsigned bit pattern (PGM/PPM unsigned).
        if arr.dtype.kind == "i":
            arr = arr.astype(f"u{arr.dtype.itemsize}")

        # Normalise to (frames, rows, cols[, spp]).
        rows = int(getattr(ds, "Rows", 0)); cols = int(getattr(ds, "Columns", 0))
        if frames == 1 and arr.shape[0] != 1:
            arr = arr[np.newaxis, ...]
        color = spp > 1
        if color and arr.ndim != 4:
            return True, f"skip:unexpected-color-shape({arr.shape})"
        if not color and arr.ndim != 3:
            return True, f"skip:unexpected-gray-shape({arr.shape})"

        # Build the expected mosaic (frames==1 -> trivial 1x1 grid).
        mc = max(1, math.ceil(math.sqrt(frames)))
        mr = max(1, math.ceil(frames / mc))
        if color:
            expected = np.zeros((rows * mr, cols * mc, spp), dtype=arr.dtype)
            for fi in range(frames):
                tc, tr = fi % mc, fi // mc
                expected[tr*rows:(tr+1)*rows, tc*cols:(tc+1)*cols, :] = arr[fi]
        else:
            expected = np.zeros((rows * mr, cols * mc), dtype=arr.dtype)
            for fi in range(frames):
                tc, tr = fi % mc, fi // mc
                expected[tr*rows:(tr+1)*rows, tc*cols:(tc+1)*cols] = arr[fi]

        # Decoded raster (PGM P5 = 1 ch, PPM P6 = 3 ch).
        w, h, maxval, ch, bps, raw = _read_pgm_pixels(decoded_path)
        if ch != spp:
            return False, f"channel-mismatch:src_spp={spp} decoded_ch={ch}"
        dtype = ">u2" if bps == 2 else "u1"
        dec = np.frombuffer(raw, dtype=dtype)
        want = w * h * ch
        if dec.size != want:
            return False, f"size:dec={dec.size} expected={want}"
        dec = dec.reshape((h, w, ch)) if ch > 1 else dec.reshape((h, w))

        if expected.shape != dec.shape:
            return False, f"dims:src={expected.shape} dec={dec.shape}"
        if not np.array_equal(expected.astype(np.int64), dec.astype(np.int64)):
            diff = int(np.count_nonzero(expected.astype(np.int64) - dec.astype(np.int64)))
            return False, f"pixel-mismatch:{diff}/{expected.size}"
        tag = []
        if frames > 1:
            tag.append(f"{frames}f-mosaic")
        if color:
            tag.append(f"rgb-spp{spp}")
        return True, ("ok:" + ",".join(tag)) if tag else ""
    except Exception as exc:
        return True, f"skip:verify-error ({type(exc).__name__}: {exc})"


def _run(cmd: list[str], timeout: int) -> tuple[int, str, str, float]:
    """Returns (returncode, last-line-of-output, full-stdout, seconds)."""
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        dt = time.perf_counter() - t0
        combined = ((proc.stderr or "") + (proc.stdout or "")).strip()
        last = combined.splitlines()[-1] if combined else ""
        return proc.returncode, last[:400], (proc.stdout or ""), dt
    except subprocess.TimeoutExpired:
        return 124, f"TIMEOUT after {timeout}s", "", time.perf_counter() - t0


def process_one(args: tuple[str, str, str, bool]) -> dict:
    path, modality, study, verify = args
    r = Result(path=path, modality=modality, study=study)
    r.src_bytes = os.path.getsize(path)
    # Capture DICOM "type" metadata up-front (works even when encode later
    # fails, so non-image objects are still classified in the report).
    m = dicom_meta(path)
    r.sop_class = m["sop_class"]
    r.dicom_modality = m["dicom_modality"]
    r.transfer_syntax = m["transfer_syntax"]
    r.photometric = m["photometric"]
    r.samples_per_pixel = m["samples_per_pixel"]
    r.bits_allocated = m["bits_allocated"]
    r.bits_stored = m["bits_stored"]
    r.signed = m["signed"]
    r.is_image = m["is_image"]
    r.compressed = m["compressed"]
    r.frames = m["frames"]

    with tempfile.TemporaryDirectory(prefix="j2krt-") as td:
        j2k = os.path.join(td, "e.j2k")
        # --- encode ---
        rc, err, out, dt = _run(
            [_BIN, "encode", "-i", path, "-o", j2k, "--lossless", "--json"],
            _ENCODE_TIMEOUT)
        r.enc_seconds = round(dt, 4)
        if rc != 0 or not os.path.exists(j2k):
            r.status = "ENCODE_FAIL"
            r.detail = err
            return asdict(r)
        # Parse the JSON the encoder printed (stdout) for dims/sizes.
        try:
            meta = json.loads(out) if out.strip().startswith("{") else {}
        except Exception:
            meta = {}
        r.width = int(meta.get("width", 0))
        r.height = int(meta.get("height", 0))
        r.components = int(meta.get("components", 0))
        r.j2k_bytes = os.path.getsize(j2k)

        # --- decode ---
        # Pick the raster format that matches the component count: PPM (P6) for
        # colour/multi-sample (the CLI refuses to write >1 component as PGM),
        # PGM (P5) for grayscale. Component count comes from the encoder JSON.
        ext = "ppm" if (r.components or r.samples_per_pixel) >= 3 else "pgm"
        dec = os.path.join(td, f"d.{ext}")
        rc, err, _out, dt = _run(
            [_BIN, "decode", "-i", j2k, "-o", dec, "--quiet"], _DECODE_TIMEOUT)
        r.dec_seconds = round(dt, 4)
        # decode derives extension; find whatever it actually wrote.
        produced = dec
        if not os.path.exists(produced):
            cand = [p for p in Path(td).iterdir() if p.name.startswith("d.")]
            produced = str(cand[0]) if cand else dec
        if rc != 0 or not os.path.exists(produced):
            r.status = "DECODE_FAIL"
            r.detail = err
            return asdict(r)

        # --- verify (optional) ---
        if verify:
            ok, detail = verify_lossless(path, produced)
            if not ok:
                r.status = "VERIFY_MISMATCH"
                r.detail = detail
            elif detail.startswith("skip:"):
                r.status = "VERIFY_SKIP"
                r.detail = detail
    return asdict(r)


def collect_files(dataset: Path, modalities: set[str] | None, limit: int | None):
    # os.walk with followlinks=False so a self-referential symlink (e.g. the
    # Google Drive "Radiology DICOM Data" shortcut that points back at the
    # dataset root) cannot cause infinite recursion.
    files = []
    root = str(dataset)
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in filenames:
            if not name.lower().endswith(".dcm"):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).split(os.sep)
            modality = rel[0] if rel else "?"
            study = rel[1] if len(rel) > 1 else "?"
            if modalities and modality not in modalities:
                continue
            files.append((full, modality, study))
    files.sort()
    if limit:
        files = files[:limit]
    return files


def write_reports(results: list[dict], outdir: Path, elapsed: float, args):
    outdir.mkdir(parents=True, exist_ok=True)
    csv_path = outdir / "results.csv"
    fields = list(Result(path="", modality="", study="").__dict__.keys())
    with open(csv_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for row in results:
            w.writerow(row)

    # Aggregate.
    from collections import Counter, defaultdict
    by_mod = defaultdict(Counter)
    status_total = Counter()
    failures = []
    for r in results:
        by_mod[r["modality"]][r["status"]] += 1
        status_total[r["status"]] += 1
        if r["status"] not in ("OK", "VERIFY_SKIP"):
            failures.append(r)

    md = outdir / "REPORT.md"
    total = len(results)
    ok = status_total.get("OK", 0)
    with open(md, "w") as f:
        f.write("# DICOM Encode/Decode Round-Trip Report\n\n")
        f.write(f"- **Dataset:** `{args.dataset}`\n")
        f.write(f"- **Binary:** `{args.bin}`\n")
        f.write(f"- **Files processed:** {total}\n")
        f.write(f"- **Verification:** {'ON' if args.verify else 'OFF'}\n")
        f.write(f"- **Wall time:** {elapsed/60:.1f} min  ({args.workers} workers)\n\n")
        f.write("## Overall status\n\n")
        f.write("| Status | Count | % |\n|---|---:|---:|\n")
        for st, c in status_total.most_common():
            f.write(f"| {st} | {c} | {100*c/total:.2f}% |\n")
        f.write(f"\n**{ok}/{total} ({100*ok/total:.2f}%) clean round-trips.**\n\n")

        f.write("## By modality\n\n")
        cols = ["OK", "ENCODE_FAIL", "DECODE_FAIL", "VERIFY_MISMATCH", "VERIFY_SKIP"]
        f.write("| Modality | Total | " + " | ".join(cols) + " |\n")
        f.write("|---|---:|" + "|".join(["---:"] * len(cols)) + "|\n")
        for mod in sorted(by_mod):
            row = by_mod[mod]
            tot = sum(row.values())
            f.write(f"| {mod} | {tot} | " +
                    " | ".join(str(row.get(c, 0)) for c in cols) + " |\n")

        # ---- Types tested: break the corpus down by DICOM characteristic ----
        def type_table(title, keyfn, note=""):
            agg = defaultdict(Counter)
            for r in results:
                agg[keyfn(r)][r["status"]] += 1
            f.write(f"\n### {title}\n\n")
            if note:
                f.write(note + "\n\n")
            f.write("| " + title + " | Total | OK | Pass% | Fails |\n")
            f.write("|---|---:|---:|---:|---:|\n")
            for k in sorted(agg, key=lambda k: -sum(agg[k].values())):
                c = agg[k]; tot = sum(c.values())
                okc = c.get("OK", 0)
                fails = tot - okc - c.get("VERIFY_SKIP", 0)
                f.write(f"| {k or '(none)'} | {tot} | {okc} | "
                        f"{100*okc/tot:.1f}% | {fails} |\n")

        f.write("\n## Types tested\n\n")
        f.write("A breakdown of *how many of each DICOM type* were exercised, with the "
                "round-trip outcome for each. 'OK' = encoded, decoded, and bit-exact "
                "verified. 'Fails' excludes VERIFY_SKIP.\n")
        n_image = sum(1 for r in results if r.get("is_image", 1))
        n_nonimg = len(results) - n_image
        n_color = sum(1 for r in results if (r.get("samples_per_pixel", 1) or 1) > 1)
        n_mf = sum(1 for r in results if (r.get("frames", 1) or 1) > 1)
        n_comp = sum(1 for r in results if r.get("compressed", 0))
        n_signed = sum(1 for r in results if r.get("signed", 0))
        f.write(f"\n**Corpus mix:** {n_image} image objects · {n_nonimg} non-image objects "
                f"· {n_color} colour (multi-sample) · {n_mf} multi-frame "
                f"· {n_comp} compressed-source · {n_signed} signed-pixel.\n")
        type_table("SOP Class", lambda r: r.get("sop_class", ""))
        type_table("DICOM Modality (0008,0060)", lambda r: r.get("dicom_modality", ""))
        type_table("Transfer Syntax", lambda r: r.get("transfer_syntax", ""))
        type_table("Photometric Interpretation", lambda r: r.get("photometric", ""))
        type_table("Samples/pixel", lambda r: f"spp={r.get('samples_per_pixel',1)}")
        type_table("Bit depth (allocated/stored)",
                   lambda r: f"{r.get('bits_allocated',0)}/{r.get('bits_stored',0)}")
        type_table("Pixel representation", lambda r: "signed" if r.get("signed", 0) else "unsigned")
        type_table("Frame count", lambda r: "multi-frame" if (r.get("frames",1) or 1) > 1 else "single-frame")

        f.write("\n## Failures / anomalies\n\n")
        if not failures:
            f.write("None. Every image encoded and decoded successfully.\n")
        else:
            # Group identical detail messages.
            buckets = defaultdict(list)
            for r in failures:
                key = (r["status"], r["transfer_syntax"], r["detail"])
                buckets[key].append(r)
            f.write(f"**{len(failures)} file(s)** across "
                    f"**{len(buckets)}** distinct failure signature(s).\n\n")
            for (status, ts, detail), items in sorted(
                    buckets.items(), key=lambda kv: -len(kv[1])):
                f.write(f"### {status} — {len(items)} file(s)\n\n")
                f.write(f"- **Transfer syntax:** `{ts or 'unknown'}`\n")
                f.write(f"- **Detail:** `{detail or '(none)'}`\n")
                sopset = sorted({r.get("sop_class", "") for r in items})
                f.write(f"- **SOP class(es):** {', '.join('`'+s+'`' for s in sopset if s) or '(unknown)'}\n")
                n_nonimg = sum(1 for r in items if not r.get('is_image', 1))
                f.write(f"- **Non-image objects (no pixel data):** {n_nonimg}/{len(items)}\n")
                f.write("- **Examples:**\n")
                for r in items[:10]:
                    f.write(f"  - `{r['path']}` "
                            f"[{r.get('sop_class','?')}, {r['modality']}]\n")
                if len(items) > 10:
                    f.write(f"  - … and {len(items)-10} more "
                            f"(see results.csv)\n")
                f.write("\n")
    return csv_path, md


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dataset", default="LocalDatasets/medical-dicom-organized")
    ap.add_argument("--bin", default=".build/release/j2k")
    ap.add_argument("--python", default=sys.executable,
                    help="interpreter for compressed-DICOM helper (J2K_DICOM_PYTHON)")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 4)))
    ap.add_argument("--out", default="results/localdataset_roundtrip")
    ap.add_argument("--modality", default="", help="comma list, e.g. ct,mr")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--verify", action="store_true",
                    help="bit-exact lossless verification against pydicom pixels")
    ap.add_argument("--verify-sample", type=int, default=0,
                    help="verify only a random N (implies --verify); 0 = all")
    ap.add_argument("--encode-timeout", type=int, default=300)
    ap.add_argument("--decode-timeout", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1234)
    args = ap.parse_args()

    dataset = Path(args.dataset)
    if not dataset.exists():
        sys.exit(f"dataset not found: {dataset}")
    if not Path(args.bin).exists():
        sys.exit(f"binary not found: {args.bin} (build with: swift build -c release --product j2k)")

    mods = set(m.strip() for m in args.modality.split(",") if m.strip()) or None
    files = collect_files(dataset, mods, args.limit or None)
    if not files:
        sys.exit("no .dcm files found")

    verify = args.verify or args.verify_sample > 0
    if args.verify_sample > 0 and args.verify_sample < len(files):
        random.seed(args.seed)
        # Encode/decode runs on all files; verification only on the sampled
        # subset (a per-task flag — threads share globals, no pool split).
        sample = set(random.sample(range(len(files)), args.verify_sample))
    else:
        sample = None

    # Build the per-task worklist: (path, modality, study, verify_flag).
    worklist = []
    for i, (path, modality, study) in enumerate(files):
        vflag = verify if sample is None else (i in sample)
        worklist.append((path, modality, study, vflag))
    # Shuffle (seeded) so modalities interleave: smoother throughput (large mg
    # files don't all land on the pool at once) and any modality-specific
    # failure surfaces early instead of after the whole ct/mr block.
    random.seed(args.seed)
    random.shuffle(worklist)

    configure(args.bin, args.python, args.encode_timeout, args.decode_timeout)
    print(f"[*] {len(files)} files | workers={args.workers} | verify={verify}"
          f"{f' (sample {args.verify_sample})' if sample else ''}", flush=True)
    t0 = time.perf_counter()
    results = []
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(process_one, w) for w in worklist]
        for fut in as_completed(futs):
            results.append(fut.result())
            done += 1
            if done % 250 == 0 or done == len(files):
                el = time.perf_counter() - t0
                rate = done / el if el else 0
                eta = (len(files) - done) / rate if rate else 0
                print(f"  {done}/{len(files)}  "
                      f"({rate:.1f}/s, ETA {eta/60:.1f}m)", flush=True)

    elapsed = time.perf_counter() - t0
    csv_path, md = write_reports(results, Path(args.out), elapsed, args)
    bad = sum(1 for r in results if r["status"] not in ("OK", "VERIFY_SKIP"))
    print(f"\n[*] done in {elapsed/60:.1f} min — {bad} problem file(s)")
    print(f"[*] CSV:    {csv_path}")
    print(f"[*] REPORT: {md}")


if __name__ == "__main__":
    main()
