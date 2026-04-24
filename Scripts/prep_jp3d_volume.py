#!/usr/bin/env python3
"""
prep_jp3d_volume.py — DICOM → raw-volume exporter for JP3D benchmarks.

Reads a directory of DICOM slices (sorted by filename — relies on the
LocalDatasets/medical-dicom-organized layout) and writes the volume in
three forms so the head-to-head JP3D harness (`Scripts/jp3d_beat_openjpeg.sh`)
can feed both codecs from identical pixel data:

  <out_base>.bin   raw LE uint16 voxels, slice-major (i.e. slice0 then slice1…)
  <out_base>.img   ASCII header for OpenJPEG JP3D (Bpp / Color Map / Dimensions / Resolution)
  <out_base>.meta  JSON with width/height/depth/bit-depth/signed for the benchmark driver

OpenJPEG's `opj_jp3d_compress` reads the .bin as native uint16 with no
byte-swap when `bigendian` is 0 inside the tool (see convert.c). J2KSwift's
`j2k encode3d` raw mode reads the same bytes verbatim. Both codecs thus
receive the exact same logical volume.

Usage:
    prep_jp3d_volume.py --dicom-dir PATH --out PATH-BASE [--max-slices N]

Requires: pydicom, numpy (already in .venv).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path

import numpy as np
import pydicom


def load_dicom_volume(dicom_dir: Path, max_slices: int | None) -> tuple[np.ndarray, dict]:
    files = sorted(glob.glob(str(dicom_dir / "*.dcm")))
    if not files:
        sys.exit(f"[prep_jp3d_volume] no .dcm files in {dicom_dir}")
    if max_slices is not None:
        files = files[:max_slices]

    first = pydicom.dcmread(files[0])
    rows = int(first.Rows)
    cols = int(first.Columns)
    bits_stored = int(first.BitsStored)
    signed = bool(getattr(first, "PixelRepresentation", 0))
    pixel_spacing = [float(x) for x in getattr(first, "PixelSpacing", [1.0, 1.0])]
    slice_thickness = float(getattr(first, "SliceThickness", 1.0))

    if bits_stored > 16:
        sys.exit(f"[prep_jp3d_volume] bits_stored={bits_stored} not supported")
    if signed:
        sys.exit("[prep_jp3d_volume] signed DICOM pixel data not supported yet")

    depth = len(files)
    vol = np.empty((depth, rows, cols), dtype=np.uint16)
    for z, path in enumerate(files):
        ds = pydicom.dcmread(path)
        arr = ds.pixel_array
        if arr.dtype != np.uint16:
            arr = arr.astype(np.uint16)
        if arr.shape != (rows, cols):
            sys.exit(f"[prep_jp3d_volume] slice {z} shape {arr.shape} != expected ({rows},{cols})")
        vol[z] = arr

    meta = {
        "width": cols,
        "height": rows,
        "depth": depth,
        "bit_depth": bits_stored,
        "signed": signed,
        "pixel_spacing_xy": pixel_spacing,
        "slice_thickness": slice_thickness,
        "source_dir": str(dicom_dir),
        "source_slice_count": depth,
    }
    return vol, meta


def write_outputs(vol: np.ndarray, out_base: Path, meta: dict) -> None:
    bin_path = out_base.with_suffix(".bin")
    img_path = out_base.with_suffix(".img")
    meta_path = out_base.with_suffix(".meta")

    # Raw little-endian uint16, slice-major (z, y, x → flat) matches both
    # OpenJPEG's readushort(bigendian=0) and J2KSwift raw-mode layout.
    vol.astype("<u2").tofile(bin_path)

    # OpenJPEG JP3D .img expects tab-separated integer fields.
    # Color Map 1 = grayscale (CLRSPC_GRAY) per openjp3d enum.
    with open(img_path, "w") as fh:
        fh.write(f"Bpp\t{meta['bit_depth']}\n")
        fh.write("Color Map\t1\n")
        fh.write(f"Dimensions\t{meta['width']}\t{meta['height']}\t{meta['depth']}\n")
        fh.write("Resolution(mm)\t1\t1\t1\n")

    with open(meta_path, "w") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")

    bin_bytes = bin_path.stat().st_size
    print(f"[prep_jp3d_volume] {bin_path}  ({bin_bytes} bytes, "
          f"{meta['width']}x{meta['height']}x{meta['depth']} @ {meta['bit_depth']}bpv)")
    print(f"[prep_jp3d_volume] {img_path}")
    print(f"[prep_jp3d_volume] {meta_path}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dicom-dir", required=True, type=Path,
                    help="DICOM series directory (all .dcm files sorted by filename)")
    ap.add_argument("--out", required=True, type=Path,
                    help="Output base path (no extension); writes .bin .img .meta")
    ap.add_argument("--max-slices", type=int, default=None,
                    help="Cap on slices (useful for faster benchmark iterations)")
    args = ap.parse_args()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    vol, meta = load_dicom_volume(args.dicom_dir, args.max_slices)
    write_outputs(vol, args.out, meta)


if __name__ == "__main__":
    main()
