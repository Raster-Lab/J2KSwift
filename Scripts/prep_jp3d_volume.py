#!/usr/bin/env python3
"""
prep_jp3d_volume.py — DICOM → raw-volume exporter for JP3D benchmarks.

Reads a directory of DICOM slices and writes the volume in three forms
so the head-to-head JP3D harness (`Scripts/jp3d_beat_openjpeg.sh` /
`Scripts/jp3d_clinical_validation.py`) can feed both codecs from
identical pixel data:

  <out_base>.bin   raw LE uint16 voxels, slice-major (slice0 then slice1…)
  <out_base>.img   ASCII header for OpenJPEG JP3D (Bpp / Color Map / Dims)
  <out_base>.meta  JSON with width/height/depth/bit-depth/signed for the driver

Robustness notes — this script is the load-bearing prep step that has
to deal with messy real-world DICOM:

  * Skips non-image DICOM (DICOMDIR, presentation states, structured
    reports, RTSTRUCT, GSPS, etc.) — anything missing Rows/Columns/
    BitsStored is filtered before any geometry decision.
  * Multi-geometry studies are normal in clinical PACS exports. We
    bin every readable slice by (rows, cols, bits, signed) and emit
    only the largest homogeneous group (the volumetric series); the
    other groups are reported as `skipped_*` counts in the meta JSON.
  * Sorts the kept slices by `InstanceNumber` when available, falling
    back to filename. Filename sort alone misorders zero-padded
    multi-series exports (instance_000001.dcm in series 2 sorts
    before instance_000050.dcm in series 1).
  * `PixelRepresentation == 1` (signed) is *kept* — the slice-stack
    codec round-trips signed via the `J2KComponent.signed` flag.

Usage:
    prep_jp3d_volume.py --dicom-dir PATH --out PATH-BASE [--max-slices N]
                        [--sample even|head]

Requires: pydicom, numpy (already in .venv).
"""
from __future__ import annotations

import argparse
import glob
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import pydicom


# DICOM SOP class UIDs we know are *not* image data and can be skipped fast.
_NON_IMAGE_SOP_CLASSES = frozenset({
    "1.2.840.10008.1.3.10",        # Media Storage Directory (DICOMDIR)
    "1.2.840.10008.5.1.4.1.1.11.1", # Grayscale Softcopy Presentation State
    "1.2.840.10008.5.1.4.1.1.11.2", # Color Softcopy Presentation State
    "1.2.840.10008.5.1.4.1.1.11.3", # Pseudo-color Softcopy Presentation
    "1.2.840.10008.5.1.4.1.1.11.4", # Blending Softcopy Presentation
    "1.2.840.10008.5.1.4.1.1.88.11", # Basic Text SR
    "1.2.840.10008.5.1.4.1.1.88.22", # Enhanced SR
    "1.2.840.10008.5.1.4.1.1.88.33", # Comprehensive SR
    "1.2.840.10008.5.1.4.1.1.481.3", # RT Structure Set
    "1.2.840.10008.5.1.4.1.1.481.5", # RT Plan
})


@dataclass
class SliceMeta:
    path: Path
    instance_number: int   # missing → 1<<30 + filename hash; sorted last
    geometry: tuple        # (rows, cols, bits, signed)


def scan_dicom_dir(dicom_dir: Path) -> tuple[list[SliceMeta], dict]:
    """Return (kept_slices_in_largest_geometry_group, scan_stats).

    scan_stats records every reason a slice was dropped so the meta
    JSON gives an honest picture of why a study's effective depth is
    smaller than its raw .dcm count.
    """
    files = sorted(glob.glob(str(dicom_dir / "*.dcm")))
    stats = {
        "raw_files": len(files),
        "skipped_non_image": 0,
        "skipped_unreadable": 0,
        "geometry_groups": {},
    }

    by_geometry: dict[tuple, list[SliceMeta]] = {}

    for path_str in files:
        path = Path(path_str)
        try:
            ds = pydicom.dcmread(path, stop_before_pixels=True, force=True)
        except Exception:
            stats["skipped_unreadable"] += 1
            continue

        sop_class = str(getattr(ds, "SOPClassUID", "") or "")
        if sop_class in _NON_IMAGE_SOP_CLASSES:
            stats["skipped_non_image"] += 1
            continue

        # Pixel-data sanity. Many non-image SOP classes still leak
        # through SOPClassUID checks (private vendor classes, partial
        # exports), so the structural check is the real gate.
        if not (hasattr(ds, "Rows") and hasattr(ds, "Columns")
                and hasattr(ds, "BitsStored")):
            stats["skipped_non_image"] += 1
            continue

        rows = int(ds.Rows)
        cols = int(ds.Columns)
        bits = int(ds.BitsStored)
        signed = int(getattr(ds, "PixelRepresentation", 0))
        geom = (rows, cols, bits, signed)

        # InstanceNumber is the canonical slice ordering. Without it,
        # synthesise a sortable fallback that respects filename order
        # so the volumetric Z-axis stays roughly correct.
        inst_attr = getattr(ds, "InstanceNumber", None)
        try:
            inst = int(inst_attr) if inst_attr is not None else (1 << 30) + len(by_geometry.get(geom, []))
        except (TypeError, ValueError):
            inst = (1 << 30) + len(by_geometry.get(geom, []))

        by_geometry.setdefault(geom, []).append(
            SliceMeta(path=path, instance_number=inst, geometry=geom)
        )

    # Pick the geometry group with the most slices. Ties broken by
    # higher resolution (more pixels), then deeper bit depth — the
    # heuristic favours the diagnostic-quality volumetric series over
    # any localiser / scout / overlay frames that may share a geometry.
    if not by_geometry:
        stats["geometry_groups"] = {}
        return [], stats

    stats["geometry_groups"] = {
        f"{g[0]}x{g[1]}x{g[2]}{'s' if g[3] else 'u'}": len(v)
        for g, v in by_geometry.items()
    }

    def _rank(item):
        geom, slices = item
        rows, cols, bits, _ = geom
        return (len(slices), rows * cols, bits)

    chosen_geom, chosen_slices = max(by_geometry.items(), key=_rank)
    chosen_slices.sort(key=lambda s: (s.instance_number, str(s.path)))
    return chosen_slices, stats


def sample_slices(slices: list[SliceMeta], cap: Optional[int],
                  strategy: str) -> list[SliceMeta]:
    """Per-file sampling. For single-frame DICOM `cap == frame count`.
    Multi-frame DICOM uses `sample_frames` instead — see `load_volume`."""
    if cap is None or cap >= len(slices):
        return slices
    if strategy == "head":
        return slices[:cap]
    indices = np.linspace(0, len(slices) - 1, cap).round().astype(int)
    return [slices[i] for i in indices]


def count_frames_per_file(slices: list[SliceMeta]) -> list[int]:
    """Cheap header-only scan for `NumberOfFrames` on every kept file.
    Defaults to 1 when the tag is absent — single-frame DICOM."""
    counts: list[int] = []
    for sm in slices:
        try:
            ds = pydicom.dcmread(sm.path, stop_before_pixels=True, force=True)
            n = int(getattr(ds, "NumberOfFrames", 1) or 1)
        except Exception:
            n = 1
        counts.append(max(1, n))
    return counts


def sample_total_frames(
    slices: list[SliceMeta], frames_per_file: list[int],
    cap: Optional[int], strategy: str
) -> list[tuple[SliceMeta, int]]:
    """Returns the (file, frame_idx) pairs to load.

    A 58-file XA series where each file holds 60 frames has 3 480 total
    frames. `--max-slices 32` should pick 32 of those 3 480, *not* 32
    files (which silently expands to 32 × 60 = 1 920 frames and OOMs
    OpenJPEG's 3D-EBCOT). This function builds a flat virtual list of
    every frame, then samples it.
    """
    flat: list[tuple[SliceMeta, int]] = []
    for sm, n in zip(slices, frames_per_file):
        flat.extend((sm, f) for f in range(n))

    if cap is None or cap >= len(flat):
        return flat
    if strategy == "head":
        return flat[:cap]
    indices = np.linspace(0, len(flat) - 1, cap).round().astype(int)
    return [flat[i] for i in indices]


def load_volume_from_pairs(pairs: list[tuple[SliceMeta, int]]) -> np.ndarray:
    """Loads only the requested (file, frame_idx) pairs.

    Caches each file's decoded pixel_array so multi-frame DICOM does
    not pay the codec-decode cost N times for N requested frames out
    of the same file.
    """
    if not pairs:
        sys.exit("[prep_jp3d_volume] no frames to load")

    rows, cols, _bits, _signed = pairs[0][0].geometry
    cache: dict[Path, np.ndarray] = {}
    out: list[np.ndarray] = []

    for sm, frame_idx in pairs:
        if sm.path not in cache:
            ds = pydicom.dcmread(sm.path, force=True)
            try:
                arr = ds.pixel_array
            except Exception as e:
                sys.exit(f"[prep_jp3d_volume] could not read pixels from {sm.path}: {e}")
            # Normalise to (N, rows, cols).
            if arr.ndim == 2 and arr.shape == (rows, cols):
                arr = arr[np.newaxis]
            elif arr.ndim == 3 and arr.shape[1:] == (rows, cols):
                pass
            elif arr.ndim == 3 and arr.shape == (rows, cols, 3):
                grey = (0.299 * arr[..., 0] + 0.587 * arr[..., 1]
                        + 0.114 * arr[..., 2]).astype(arr.dtype)
                arr = grey[np.newaxis]
            else:
                sys.exit(f"[prep_jp3d_volume] unexpected pixel_array shape "
                         f"{arr.shape} for {sm.path}")
            if arr.dtype == np.int16:
                arr = arr.view(np.uint16)
            elif arr.dtype != np.uint16:
                arr = arr.astype(np.uint16)
            cache[sm.path] = arr

        frames_arr = cache[sm.path]
        if frame_idx >= frames_arr.shape[0]:
            sys.exit(f"[prep_jp3d_volume] frame index {frame_idx} out of range "
                     f"for {sm.path} (has {frames_arr.shape[0]} frames)")
        out.append(frames_arr[frame_idx])

    return np.stack(out, axis=0)


def write_outputs(vol: np.ndarray, out_base: Path, meta: dict) -> None:
    bin_path = out_base.with_suffix(".bin")
    img_path = out_base.with_suffix(".img")
    meta_path = out_base.with_suffix(".meta")

    # Match the byte width to the bit depth so both codecs read the
    # right voxel count from the same .bin: J2KSwift's raw-mode and
    # OpenJPEG's `bintovolume` both treat the file as a flat sequence
    # of (bit_depth+7)/8-byte samples. Storing 8-bit data as uint16
    # quietly halves the addressed depth and breaks bit-exact.
    if meta["bit_depth"] <= 8:
        vol.astype("<u1").tofile(bin_path)
    else:
        vol.astype("<u2").tofile(bin_path)

    # Color Map 1 = grayscale (CLRSPC_GRAY) per OpenJPEG's openjp3d enum.
    with open(img_path, "w") as fh:
        fh.write(f"Bpp\t{meta['bit_depth']}\n")
        fh.write("Color Map\t1\n")
        fh.write(f"Dimensions\t{meta['width']}\t{meta['height']}\t{meta['depth']}\n")
        fh.write("Resolution(mm)\t1\t1\t1\n")

    with open(meta_path, "w") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
        fh.write("\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dicom-dir", required=True, type=Path,
                    help="DICOM series directory (all .dcm files)")
    ap.add_argument("--out", required=True, type=Path,
                    help="Output base path (no extension); writes .bin .img .meta")
    ap.add_argument("--max-slices", type=int, default=None,
                    help="Cap on slices in the largest geometry group "
                         "(omit to use every slice in the group)")
    ap.add_argument("--sample", choices=("head", "even"), default="even",
                    help="When --max-slices applies, take the first N "
                         "(`head`) or N evenly-spaced through the volume "
                         "(`even`, default — gives representative anatomy)")
    args = ap.parse_args()

    args.out.parent.mkdir(parents=True, exist_ok=True)

    chosen, stats = scan_dicom_dir(args.dicom_dir)
    if not chosen:
        # Honest exit: a DX folder with one frame is not a JP3D candidate.
        sys.exit(f"[prep_jp3d_volume] no usable image slices in {args.dicom_dir} "
                 f"(scanned {stats['raw_files']}, "
                 f"non_image={stats['skipped_non_image']}, "
                 f"unreadable={stats['skipped_unreadable']}, "
                 f"groups={stats['geometry_groups']})")

    # Multi-frame-aware sampling: count frames per file (cheap, header
    # only), build a flat list of (file, frame) pairs, then sample.
    # Single-frame DICOM short-circuits with frames_per_file == [1, 1, …].
    frames_per_file = count_frames_per_file(chosen)
    total_frames = sum(frames_per_file)

    pairs = sample_total_frames(chosen, frames_per_file,
                                args.max_slices, args.sample)
    vol = load_volume_from_pairs(pairs)

    meta = {
        "width": int(vol.shape[2]),
        "height": int(vol.shape[1]),
        "depth": int(vol.shape[0]),
        "bit_depth": int(chosen[0].geometry[2]),
        "signed": bool(chosen[0].geometry[3]),
        "source_dir": str(args.dicom_dir),
        "scan_stats": stats,
        "kept_geometry_files": len(chosen),
        "kept_geometry_total_frames": total_frames,
        "sampled_count": len(pairs),
        "sampling": args.sample,
    }
    write_outputs(vol, args.out, meta)

    bytes_per_voxel = 1 if meta["bit_depth"] <= 8 else 2
    on_disk = vol.size * bytes_per_voxel
    print(f"[prep_jp3d_volume] {args.out.with_suffix('.bin')}  "
          f"({on_disk} bytes on disk, "
          f"{meta['width']}x{meta['height']}x{meta['depth']} @ {meta['bit_depth']}bpv"
          f"{'s' if meta['signed'] else 'u'})")
    if stats["skipped_non_image"] or stats["skipped_unreadable"]:
        print(f"[prep_jp3d_volume]   skipped: {stats['skipped_non_image']} non-image, "
              f"{stats['skipped_unreadable']} unreadable")
    if len(stats["geometry_groups"]) > 1:
        print(f"[prep_jp3d_volume]   geometry groups: {stats['geometry_groups']} "
              f"-> kept largest ({len(chosen)} files)")
    if total_frames != len(chosen):
        print(f"[prep_jp3d_volume]   multi-frame: {len(chosen)} files → {total_frames} total frames")
    if args.max_slices and args.max_slices < total_frames:
        print(f"[prep_jp3d_volume]   sampled {len(pairs)} of {total_frames} frames "
              f"({args.sample})")


if __name__ == "__main__":
    main()
