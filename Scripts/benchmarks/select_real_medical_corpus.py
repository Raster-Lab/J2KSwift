#!/usr/bin/env python3
"""Select 18 real-medical PGM fixtures from LocalDatasets/.

PHI-safe by structural design: PGM container has NO metadata format, so
patient identifiers / dates / institutions / accession numbers / referring
physicians cannot be carried into the output. Only the pixel data (and a
neutral generator-chosen filename) survives.

Process per modality (CT, DX, MG, MR, PX, XA):
  1. Walk LocalDatasets/medical-dicom-organized/<modality>/ for *.dcm
  2. Read each via pydicom, compute pixel count = Rows × Columns
  3. Sort by pixel count; pick small (10th-pctile), mid (50th), large (90th)
  4. Read pixel data, write as 16-bit big-endian PGM
  5. Compute MD5 of the PGM (anchor for reproducibility checks)
  6. Append to manifest.csv (no PHI: only modality, tier, W, H, bitdepth, MD5)

Output naming: <modality>_real_<tier>_<W>x<H>.pgm
Output dir:    Tests/Fixtures/CrossCodec/medical-real/
"""
import csv
import hashlib
import os
import sys
from typing import Optional

import numpy as np
import pydicom


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC_ROOT = os.path.join(REPO_ROOT, "LocalDatasets/medical-dicom-organized")
OUT_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec/medical-real")
MANIFEST = os.path.join(OUT_DIR, "manifest.csv")

MODALITIES = ["CT", "DX", "MG", "MR", "PX", "XA"]


def safe_read_dimensions(path: str) -> Optional[dict]:
    """Read DICOM header only; return dimensions + bitdepth or None on failure."""
    try:
        ds = pydicom.dcmread(path, stop_before_pixels=True, force=True)
        rows = int(getattr(ds, "Rows", 0))
        cols = int(getattr(ds, "Columns", 0))
        bits = int(getattr(ds, "BitsStored", 0))
        if rows < 16 or cols < 16 or bits not in (8, 12, 14, 16):
            return None
        # Skip multi-frame DICOMs (rare; complicates PGM mapping)
        if int(getattr(ds, "NumberOfFrames", 1)) > 1:
            return None
        # Skip color (multi-sample) DICOMs — out of scope for medical lossless 16-bit testing
        if int(getattr(ds, "SamplesPerPixel", 1)) != 1:
            return None
        return {"rows": rows, "cols": cols, "bits": bits, "pixels": rows * cols}
    except Exception:
        return None


def select_three(modality_dir: str) -> list[tuple[str, dict]]:
    """Pick small/mid/large by pixel count from a modality dir."""
    candidates = []
    for root, _, files in os.walk(modality_dir):
        for f in files:
            if not f.endswith(".dcm"):
                continue
            path = os.path.join(root, f)
            info = safe_read_dimensions(path)
            if info is not None:
                candidates.append((path, info))
    if len(candidates) < 3:
        return candidates
    candidates.sort(key=lambda x: x[1]["pixels"])
    n = len(candidates)
    return [
        ("small", candidates[max(0, n // 10)]),       # 10th percentile
        ("mid",   candidates[n // 2]),                 # 50th percentile
        ("large", candidates[min(n - 1, 9 * n // 10)]),# 90th percentile
    ]


def dicom_to_pgm(src_dcm: str, dst_pgm: str) -> dict:
    """Read DICOM, write 16-bit big-endian PGM. PHI-safe: no metadata copied."""
    ds = pydicom.dcmread(src_dcm, force=True)
    pixels = ds.pixel_array
    if pixels.ndim != 2:
        raise ValueError(f"Expected 2D pixel array, got shape {pixels.shape}")

    bits = int(getattr(ds, "BitsStored", 16))
    rows, cols = pixels.shape
    max_val = (1 << bits) - 1

    # Clip into valid range and cast to uint16 for >8-bit, uint8 for 8-bit
    pixels = np.clip(pixels, 0, max_val)

    if bits > 8:
        body_dtype = ">u2"   # PGM big-endian for max_val > 255
        body = pixels.astype(body_dtype).tobytes()
    else:
        body = pixels.astype(np.uint8).tobytes()

    header = f"P5\n{cols} {rows}\n{max_val}\n".encode("ascii")
    with open(dst_pgm, "wb") as f:
        f.write(header)
        f.write(body)

    return {"rows": rows, "cols": cols, "bits": bits, "size": os.path.getsize(dst_pgm)}


def md5_file(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not os.path.isdir(SRC_ROOT):
        print(f"Error: {SRC_ROOT} not found. Need LocalDatasets/medical-dicom-organized/.")
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    print(f"Output dir: {OUT_DIR}\n")

    for modality in MODALITIES:
        mod_dir = os.path.join(SRC_ROOT, modality.lower())
        if not os.path.isdir(mod_dir):
            print(f"  ⚠️  {modality}: dir missing at {mod_dir}, skipping")
            continue
        print(f"  {modality}: scanning {mod_dir} ...")
        triple = select_three(mod_dir)
        if len(triple) < 3:
            print(f"    only {len(triple)} candidates; skipping modality")
            continue
        for tier, (src_path, info) in triple:
            name = f"{modality.lower()}_real_{tier}_{info['cols']}x{info['rows']}.pgm"
            dst = os.path.join(OUT_DIR, name)
            try:
                meta = dicom_to_pgm(src_path, dst)
            except Exception as e:
                print(f"    ✗ {tier} failed: {e}")
                continue
            md5 = md5_file(dst)
            print(f"    ✓ {tier:5s}  {meta['cols']}×{meta['rows']}  "
                  f"{meta['bits']}b  pgm={meta['size']:>10d}  md5={md5[:12]}…")
            rows.append({
                "filename": name,
                "modality": modality,
                "tier": tier,
                "width": meta["cols"],
                "height": meta["rows"],
                "bit_depth": meta["bits"],
                "pgm_size": meta["size"],
                "pgm_md5": md5,
            })

    if rows:
        with open(MANIFEST, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        total_mb = sum(r["pgm_size"] for r in rows) / 1024 / 1024
        print(f"\nWrote {len(rows)} PGM fixtures ({total_mb:.1f} MB)")
        print(f"Manifest: {MANIFEST}")
        print(f"\nNote: PGM container has no metadata format — patient identifiers,")
        print(f"dates, institutions, accession numbers cannot be present in these")
        print(f"files. Only pixel data + width/height/maxval header.")
    else:
        print("\nNo fixtures written.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
