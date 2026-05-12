#!/usr/bin/env python3
"""Generate the J2KSwift synthetic medical corpus.

Produces deterministic LCG-seeded 16-bit PGM fixtures + matching DICOM
files (uncompressed Explicit VR Little Endian) covering 8 modalities
× multiple sizes. Combined with the 7 real PGMs already at
`Tests/Fixtures/CrossCodec/`, the corpus has 20 PGM fixtures + 13 DICOM
fixtures — the minimum the user requires for cross-codec benchmark
claims.

The pixel data is **clearly synthetic** (NO real medical content,
NO patient information). Structural features are added to make each
modality plausibly distinct from a codec-stress perspective:
  - MR: bright cortex + dark CSF + Gaussian-like noise
  - CT: concentric soft-tissue rings + bone-density ring (high-contrast)
  - XA: vascular tree (thin high-contrast filaments)
  - DX: bilateral symmetric soft tissue + bone shadows
  - PX: dental arch (curved bone shadow + air pockets)
  - MG: gradient + speckle + microcalcification specks
  - NM: low-resolution noisy spot pattern (8-bit)
  - CR: chest-like bilateral soft regions

Deterministic: every host produces byte-identical output from the same
seed. The benchmark script `cross_codec_warm_bench.py` verifies an MD5
against a manifest CSV to catch any platform drift.

Usage:
  python3 Scripts/benchmarks/generate_synthetic_corpus.py
  # Writes to Tests/Fixtures/CrossCodec/synthetic/ (created if missing)
  # Generates 26 files (13 PGM + 13 DCM) + manifest.csv
"""
import os
import sys
import csv
import hashlib
from dataclasses import dataclass
from typing import Tuple

import numpy as np
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid
import datetime


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO_ROOT, "Tests/Fixtures/CrossCodec/synthetic")
MANIFEST_PATH = os.path.join(OUT_DIR, "manifest.csv")


@dataclass
class FixtureSpec:
    name: str
    modality: str
    width: int
    height: int
    bit_depth: int      # 8 or 16
    seed: int

    @property
    def n_pixels(self) -> int:
        return self.width * self.height


# ------------------------------------------------------------------------
# 13 synthetic fixtures spanning 8 modalities + 4 size tiers.
# Seeds are arbitrary but FIXED — changing them invalidates the manifest.
# ------------------------------------------------------------------------
SPECS = [
    FixtureSpec("mr_synth_small",  "MR", 256,  256,  16, 1001),
    FixtureSpec("mr_synth_mid",    "MR", 512,  512,  16, 1002),
    FixtureSpec("mr_synth_large",  "MR", 1024, 1024, 16, 1003),
    FixtureSpec("ct_synth_small",  "CT", 384,  384,  16, 2001),
    FixtureSpec("ct_synth_mid",    "CT", 768,  768,  16, 2002),
    FixtureSpec("ct_synth_large",  "CT", 1024, 1024, 16, 2003),
    FixtureSpec("xa_synth_small",  "XA", 800,  800,  16, 3001),
    FixtureSpec("xa_synth_mid",    "XA", 1280, 1280, 16, 3002),
    FixtureSpec("dx_synth_mid",    "DX", 1024, 1024, 16, 4001),
    FixtureSpec("px_synth_mid",    "PX", 1024, 800,  16, 5001),
    FixtureSpec("mg_synth_mid",    "MG", 1024, 1280, 16, 6001),
    FixtureSpec("nm_synth_small",  "NM", 256,  256,  8,  7001),
    FixtureSpec("cr_synth_mid",    "CR", 1024, 1024, 16, 8001),
]


def _lcg_noise(width: int, height: int, seed: int, bit_depth: int) -> np.ndarray:
    """Deterministic LCG-noise field as an integer array.

    Mirrors the Swift V96DWTMicrobench `makeFloatBuffer` LCG pattern so the
    Python and Swift test paths produce byte-identical noise distributions
    given the same seed. Returns shape (height, width), dtype matches bit
    depth.
    """
    # Use plain Python int arithmetic (auto-bigint), then cast at the end.
    # This sidesteps numpy 2.x's stricter overflow warnings on uint64
    # modular-arithmetic that the LCG depends on.
    n = width * height
    out = np.empty(n, dtype=np.uint32)
    s = int(seed)
    one = 1442695040888963407
    mul = 6364136223846793005
    mask64 = (1 << 64) - 1
    for i in range(n):
        s = (s * mul + one) & mask64
        out[i] = (s >> 32) & 0xFFFFFFFF
    arr = out.reshape((height, width))
    max_val = (1 << bit_depth) - 1
    return (arr & max_val).astype(np.uint16 if bit_depth > 8 else np.uint8)


def _structural_overlay_mr(width: int, height: int, max_val: int) -> np.ndarray:
    """T1-weighted brain-MRI-like overlay: bright cortex + dark CSF."""
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = width / 2.0, height / 2.0
    rx, ry = width * 0.42, height * 0.42
    norm = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    cortex = np.where(norm <= 1.0, max_val * 0.55, max_val * 0.05)
    inner = np.where(norm <= 0.30, max_val * 0.20, 0)
    return (cortex + inner).astype(np.float32)


def _structural_overlay_ct(width: int, height: int, max_val: int) -> np.ndarray:
    """CT-like: concentric tissue rings + bone ring (high contrast)."""
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = width / 2.0, height / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    rmax = min(cx, cy) * 0.95
    field = np.zeros((height, width), dtype=np.float32)
    field += np.where(r < rmax * 0.95, max_val * 0.40, 0)
    field += np.where((r > rmax * 0.85) & (r < rmax * 0.95), max_val * 0.55, 0)  # bone
    field += np.where(r < rmax * 0.30, max_val * 0.50, 0)  # organ
    return field


def _structural_overlay_xa(width: int, height: int, max_val: int) -> np.ndarray:
    """XA-like: high-contrast vascular tree."""
    field = np.full((height, width), max_val * 0.20, dtype=np.float32)
    # Main vessel (vertical sinusoidal)
    yy, xx = np.mgrid[0:height, 0:width]
    cx = width / 2.0
    main = np.abs(xx - (cx + 30 * np.sin(2 * np.pi * yy / max(height, 1)))) < 8
    field[main] = max_val * 0.85
    # Branches (diagonals)
    for sign in (-1, 1):
        for offset in range(int(height * 0.3), int(height * 0.7), max(1, int(height * 0.06))):
            branch = np.abs((xx - cx) - sign * (yy - offset) * 0.6) < 4
            branch &= (yy > offset) & (yy < offset + height * 0.12)
            field[branch] = max_val * 0.80
    return field


def _structural_overlay_dx(width: int, height: int, max_val: int) -> np.ndarray:
    """DX-like: bilateral symmetric soft tissue + ribs."""
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = width / 2.0, height / 2.0
    # Lung field (bilateral dark ovals)
    rx, ry = width * 0.22, height * 0.32
    left = ((xx - (cx - width * 0.18)) / rx) ** 2 + ((yy - cy) / ry) ** 2
    right = ((xx - (cx + width * 0.18)) / rx) ** 2 + ((yy - cy) / ry) ** 2
    field = np.full((height, width), max_val * 0.55, dtype=np.float32)
    field[(left < 1.0) | (right < 1.0)] = max_val * 0.20
    # Rib shadows
    for y_off in range(int(height * 0.20), int(height * 0.70), max(1, int(height * 0.07))):
        rib_mask = np.abs(yy - y_off) < 3
        field[rib_mask] += max_val * 0.10
    return np.clip(field, 0, max_val).astype(np.float32)


def _structural_overlay_px(width: int, height: int, max_val: int) -> np.ndarray:
    """PX-like: dental arch (curved bone shadow + air pockets)."""
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = width / 2.0, height * 0.6
    # Parabolic arch
    arch = ((xx - cx) ** 2) / (width * 0.4) ** 2 + (yy - cy) / (height * 0.4) - 0.3
    field = np.full((height, width), max_val * 0.25, dtype=np.float32)
    field[(arch > -0.05) & (arch < 0.05)] = max_val * 0.80
    # Teeth (regular spaced rectangles)
    for i in range(-7, 8):
        tooth_x = int(cx + i * width * 0.05)
        if 0 <= tooth_x < width:
            field[int(cy - height * 0.08):int(cy + height * 0.04),
                  max(0, tooth_x - 3):min(width, tooth_x + 3)] = max_val * 0.90
    return field


def _structural_overlay_mg(width: int, height: int, max_val: int) -> np.ndarray:
    """MG-like: gradient + speckle + microcalcifications."""
    yy, xx = np.mgrid[0:height, 0:width]
    # Gradient (top-brighter, bottom-darker for breast tissue)
    field = max_val * 0.30 + max_val * 0.20 * (yy / max(height, 1))
    # Microcalcifications (sparse bright dots)
    rng = np.random.default_rng(6001)
    for _ in range(50):
        x = rng.integers(int(width * 0.2), int(width * 0.8))
        y = rng.integers(int(height * 0.2), int(height * 0.8))
        field[max(0, y - 1):min(height, y + 2),
              max(0, x - 1):min(width, x + 2)] = max_val * 0.95
    return field.astype(np.float32)


def _structural_overlay_nm(width: int, height: int, max_val: int) -> np.ndarray:
    """NM-like: low-resolution noisy spot pattern."""
    yy, xx = np.mgrid[0:height, 0:width]
    cx, cy = width / 2.0, height / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return (max_val * 0.5 * np.exp(-(r / (width * 0.25)) ** 2)).astype(np.float32)


def _structural_overlay_cr(width: int, height: int, max_val: int) -> np.ndarray:
    """CR-like (chest radiography): bilateral structure + texture."""
    # Reuse DX-like with slightly different parameters
    return _structural_overlay_dx(width, height, max_val) * 0.9


_OVERLAY = {
    "MR": _structural_overlay_mr,
    "CT": _structural_overlay_ct,
    "XA": _structural_overlay_xa,
    "DX": _structural_overlay_dx,
    "PX": _structural_overlay_px,
    "MG": _structural_overlay_mg,
    "NM": _structural_overlay_nm,
    "CR": _structural_overlay_cr,
}


def generate_pixel_array(spec: FixtureSpec) -> np.ndarray:
    """Deterministic 2D pixel array for the given fixture spec."""
    max_val = (1 << spec.bit_depth) - 1
    overlay = _OVERLAY[spec.modality](spec.width, spec.height, max_val)
    noise = _lcg_noise(spec.width, spec.height, spec.seed, spec.bit_depth).astype(np.float32)
    # 70% structure + 30% noise — keeps noise contribution real (codec
    # stress) without burying the structure.
    mixed = (0.70 * overlay + 0.30 * (noise * (max_val / max(noise.max(), 1))))
    mixed = np.clip(mixed, 0, max_val)
    return mixed.astype(np.uint16 if spec.bit_depth > 8 else np.uint8)


def write_pgm(path: str, pixels: np.ndarray, bit_depth: int) -> None:
    height, width = pixels.shape
    max_val = (1 << bit_depth) - 1
    header = f"P5\n{width} {height}\n{max_val}\n".encode("ascii")
    if bit_depth > 8:
        # Big-endian per PGM spec for max_val > 255.
        body = pixels.astype(">u2").tobytes()
    else:
        body = pixels.astype(np.uint8).tobytes()
    with open(path, "wb") as f:
        f.write(header)
        f.write(body)


def write_dicom(path: str, pixels: np.ndarray, spec: FixtureSpec) -> None:
    """Write a minimal DICOM Part 10 file with Explicit VR Little Endian
    uncompressed pixel data. Sufficient for DCMTK / pydicom / Swift
    DICOM parsers to round-trip pixel data.
    """
    height, width = pixels.shape

    file_meta = FileMetaDataset()
    file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.1.1.7"  # Secondary Capture
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    # OID-style UID under the 1.2.826.0.1 (Apple) branch. Must be <=64
    # chars of digits+dots per DICOM PS3.5 §9.1.
    file_meta.ImplementationClassUID = "1.2.826.0.1.3680043.10.511.1"
    file_meta.ImplementationVersionName = "J2KSwiftCorpus"

    ds = FileDataset(path, {}, file_meta=file_meta, preamble=b"\0" * 128)
    ds.PatientName = "SYNTHETIC^J2KSwift"
    ds.PatientID = "J2KSwift-synth"
    ds.StudyInstanceUID = generate_uid()
    ds.SeriesInstanceUID = generate_uid()
    ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
    ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
    ds.Modality = spec.modality
    ds.StudyDate = "20260512"
    ds.ContentDate = "20260512"
    ds.ContentTime = "000000"
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    ds.Rows = height
    ds.Columns = width
    ds.BitsAllocated = 16 if spec.bit_depth > 8 else 8
    ds.BitsStored = spec.bit_depth
    ds.HighBit = spec.bit_depth - 1
    ds.PixelRepresentation = 0  # unsigned
    if spec.bit_depth > 8:
        ds.PixelData = pixels.astype("<u2").tobytes()
    else:
        ds.PixelData = pixels.astype("<u1").tobytes()
    ds.is_little_endian = True
    ds.is_implicit_VR = False
    ds.save_as(path, write_like_original=False)


def md5_file(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    print(f"Generating {len(SPECS) * 2} synthetic fixtures to {OUT_DIR}")
    for spec in SPECS:
        pixels = generate_pixel_array(spec)
        pgm = os.path.join(OUT_DIR, f"{spec.name}.pgm")
        dcm = os.path.join(OUT_DIR, f"{spec.name}.dcm")
        write_pgm(pgm, pixels, spec.bit_depth)
        write_dicom(dcm, pixels, spec)
        rows.append((
            spec.name, spec.modality, spec.width, spec.height,
            spec.bit_depth, spec.seed,
            os.path.getsize(pgm), md5_file(pgm),
            os.path.getsize(dcm),
        ))
        print(f"  ✓ {spec.name:18s}  {spec.modality}  {spec.width}×{spec.height}  "
              f"{spec.bit_depth}b  pgm={os.path.getsize(pgm):>10d}  dcm={os.path.getsize(dcm):>10d}")

    with open(MANIFEST_PATH, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["name", "modality", "width", "height", "bit_depth", "seed",
                    "pgm_size", "pgm_md5", "dcm_size"])
        for row in rows:
            w.writerow(row)

    pgm_total = sum(r[6] for r in rows)
    dcm_total = sum(r[8] for r in rows)
    print(f"\nWrote {len(SPECS)} PGMs ({pgm_total / 1024 / 1024:.1f} MB) + "
          f"{len(SPECS)} DCMs ({dcm_total / 1024 / 1024:.1f} MB)")
    print(f"Manifest: {MANIFEST_PATH}")
    print()
    print("Note: DICOM files use Explicit VR Little Endian (uncompressed). The")
    print("DICOM 'PixelData' tag contains raw pixels — codecs that consume")
    print("DICOM as input (J2KSwift CLI, DCMTK, dcmcjpls, gdcm) will read this.")
    print("Apples-to-apples cross-codec on DICOM requires extracting the")
    print("PixelData tag first, since OpenJPH/Grok/Kakadu CLIs are J2K-only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
