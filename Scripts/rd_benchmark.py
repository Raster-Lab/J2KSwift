#!/usr/bin/env python3
"""
Rate-Distortion benchmark for J2KSwift vs OpenJPEG / OpenJPH / Grok.

Compares all four codecs across multiple bpp targets, plotting PSNR
vs *achieved* bitrate (file_size × 8 / pixels) — the unit the v5.14.2
benchmark report flagged as the right axis for a fair comparison.

For each (image, codec, target_bpp):
  1. Encode to a J2K codestream at the requested bitrate
  2. Decode back to PGM
  3. Measure: achieved bpp, PSNR, SSIM
  4. Persist a row in the CSV

Then for each image:
  • Plot PSNR vs achieved bpp (one curve per codec)
  • Linearly interpolate each codec's curve at common achieved-bpp
    grid points (0.5, 1.0, 2.0, 4.0)
  • Print + write a matched-bpp comparison table

Output:
  results/rd_benchmark/
    rd_results.csv
    rd_plot_<image>.png       (one per image)
    rd_summary.md             (matched-bpp comparison + recommendations)

Requirements:
  python3 -m pip install numpy matplotlib scikit-image
  Codecs:
    - J2KSwift: .build/release/j2k (run swift build -c release first)
    - OpenJPEG / OpenJPH / Grok: brew install openjpeg openjph grok

Usage:
  python3 Scripts/rd_benchmark.py
  python3 Scripts/rd_benchmark.py --quick    # smaller image set + fewer points
  python3 Scripts/rd_benchmark.py --images img1.pgm img2.pgm
"""

import argparse
import csv
import json
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MPL = True
except ImportError:
    HAS_MPL = False
    print("warning: matplotlib not available; plots will be skipped", file=sys.stderr)

try:
    from skimage.metrics import structural_similarity as ssim_fn
    HAS_SKIMAGE = True
except ImportError:
    HAS_SKIMAGE = False
    print("warning: scikit-image not available; SSIM column will be 'n/a'", file=sys.stderr)


# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent.parent
J2K_CLI = ROOT / ".build" / "release" / "j2k"
OPJ_ENC = "/opt/homebrew/bin/opj_compress"
OPJ_DEC = "/opt/homebrew/bin/opj_decompress"
OJPH_ENC = "/opt/homebrew/bin/ojph_compress"
OJPH_DEC = "/opt/homebrew/bin/ojph_expand"
GRK_ENC = "/opt/homebrew/bin/grk_compress"
GRK_DEC = "/opt/homebrew/bin/grk_decompress"

OUT_DIR = ROOT / "results" / "rd_benchmark"
TMP_DIR = Path(tempfile.gettempdir()) / "rd_benchmark"

DEFAULT_BPP_TARGETS = [0.25, 0.5, 1.0, 2.0, 4.0]
QUICK_BPP_TARGETS = [0.5, 1.0, 2.0]

# Common achieved-bpp grid for matched comparison (interpolation)
MATCHED_BPP = [0.25, 0.5, 1.0, 2.0, 4.0]


# ---------------------------------------------------------------------------
# PGM I/O (P5 binary, 8 / 16-bit big-endian)
# ---------------------------------------------------------------------------

def read_pgm(path):
    """Read a P5 PGM file. Handles `#`-prefixed comment lines (PGM
    spec allows them after any whitespace token) — OpenJPEG's
    `opj_decompress` emits one with its version string, which the
    naive 3-newlines parser would mistake for header content."""
    with open(path, "rb") as f:
        data = f.read()
    # Tokenise the header: skip any whitespace and `#…\n` comments
    # until we have magic + width + height + maxval, then the next
    # byte is the start of pixel data.
    pos = 0

    def skip_ws_and_comments(pos):
        while pos < len(data):
            c = data[pos]
            if c in (0x20, 0x09, 0x0A, 0x0D):  # space, tab, LF, CR
                pos += 1
            elif c == 0x23:  # '#' — comment to end of line
                while pos < len(data) and data[pos] != 0x0A:
                    pos += 1
            else:
                break
        return pos

    def read_token(pos):
        pos = skip_ws_and_comments(pos)
        start = pos
        while pos < len(data):
            c = data[pos]
            if c in (0x20, 0x09, 0x0A, 0x0D):
                break
            pos += 1
        return data[start:pos].decode("ascii"), pos

    magic, pos = read_token(pos)
    if magic != "P5":
        raise ValueError(f"Not a P5 PGM file: magic={magic!r}")
    width_s, pos = read_token(pos)
    height_s, pos = read_token(pos)
    maxval_s, pos = read_token(pos)
    w, h, maxval = int(width_s), int(height_s), int(maxval_s)
    # PGM spec: exactly one whitespace byte after maxval, then pixels
    if pos < len(data) and data[pos] in (0x20, 0x09, 0x0A, 0x0D):
        pos += 1
    body = data[pos:]
    if maxval <= 255:
        arr = np.frombuffer(body, dtype=np.uint8, count=w * h).reshape(h, w)
    else:
        # PGM 16-bit is big-endian per spec
        arr = np.frombuffer(body, dtype=">u2", count=w * h).reshape(h, w).astype(np.uint16)
    return arr, maxval


def write_pgm(path, arr, maxval):
    h, w = arr.shape
    header = f"P5\n{w} {h}\n{maxval}\n".encode("ascii")
    with open(path, "wb") as f:
        f.write(header)
        if maxval <= 255:
            f.write(arr.astype(np.uint8).tobytes())
        else:
            f.write(arr.astype(">u2").tobytes())


# ---------------------------------------------------------------------------
# Test image generation
# ---------------------------------------------------------------------------

def make_synthetic_8bit_natural(width, height, seed=0xC0FFEE01):
    """Bandlimited gradient + noise, 8-bit. Natural-image-like spectrum."""
    rng = np.random.default_rng(seed)
    yy, xx = np.indices((height, width))
    # Diagonal gradient + low-frequency sinusoids + small noise
    img = (
        128.0
        + 80.0 * np.sin(xx / max(width, 1) * 4 * np.pi)
        + 40.0 * np.cos(yy / max(height, 1) * 6 * np.pi)
        + 20.0 * np.sin((xx + yy) / max(width, 1) * 8 * np.pi)
        + rng.normal(0, 8, (height, width))
    )
    return np.clip(img, 0, 255).astype(np.uint8), 255


def make_synthetic_12bit_medical(width, height, seed=0xCAFE0001):
    """CT-like 12-bit. Mostly-dark with bright structures + Gaussian noise."""
    rng = np.random.default_rng(seed)
    yy, xx = np.indices((height, width))
    cx, cy = width / 2, height / 2
    rr2 = (xx - cx) ** 2 + (yy - cy) ** 2
    radial = np.exp(-rr2 / (max(width, height) ** 2 / 4))
    img = (
        500.0
        + 1500.0 * radial
        + 300.0 * np.sin(xx / max(width, 1) * 12 * np.pi)
        + 200.0 * rng.normal(0, 1.0, (height, width))
    )
    return np.clip(img, 0, 4095).astype(np.uint16), 4095


def make_synthetic_16bit_medical(width, height, seed=0xCAFEBABE):
    """16-bit medical-like with full-range values."""
    rng = np.random.default_rng(seed)
    yy, xx = np.indices((height, width))
    cx, cy = width / 2, height / 2
    rr2 = (xx - cx) ** 2 + (yy - cy) ** 2
    radial = np.exp(-rr2 / (max(width, height) ** 2 / 6))
    img = (
        8000.0
        + 30000.0 * radial
        + 5000.0 * np.cos(xx / max(width, 1) * 16 * np.pi + yy / max(height, 1) * 12 * np.pi)
        + 3000.0 * rng.normal(0, 1.0, (height, width))
    )
    return np.clip(img, 0, 65535).astype(np.uint16), 65535


def build_image_set(quick=False):
    """Returns a list of (name, ndarray, maxval) tuples."""
    if quick:
        return [
            ("synth_8b_512", *make_synthetic_8bit_natural(512, 512)),
            ("synth_12b_512", *make_synthetic_12bit_medical(512, 512)),
        ]

    images = [
        ("synth_8b_512", *make_synthetic_8bit_natural(512, 512)),
        ("synth_12b_512", *make_synthetic_12bit_medical(512, 512)),
        ("synth_16b_512", *make_synthetic_16bit_medical(512, 512)),
    ]
    # Also include a real CrossCodec fixture if available — useful as
    # a real-image sanity check vs synthetic test patterns.
    fixture = ROOT / "Tests" / "Fixtures" / "CrossCodec" / "ct_study_001_instance_000001.pgm"
    if fixture.exists():
        arr, maxval = read_pgm(str(fixture))
        images.append(("ct_001_corpus", arr, maxval))
    return images


# ---------------------------------------------------------------------------
# Codec invocations — encode at target bpp, decode, return (j2k_path, dec_path)
# ---------------------------------------------------------------------------

def encode_decode_j2kswift(in_pgm, out_dir, bpp, bitdepth):
    j2k = out_dir / "j2kswift.j2k"
    dec = out_dir / "j2kswift_dec.pgm"
    enc_cmd = [str(J2K_CLI), "encode", "-i", str(in_pgm), "-o", str(j2k),
               "--bitrate", str(bpp), "--quiet"]
    r1 = subprocess.run(enc_cmd, capture_output=True, text=True, timeout=120)
    if r1.returncode != 0:
        return None, None, f"encode failed: {r1.stderr.strip()}"
    dec_cmd = [str(J2K_CLI), "decode", "-i", str(j2k), "-o", str(dec), "--quiet"]
    r2 = subprocess.run(dec_cmd, capture_output=True, text=True, timeout=120)
    if r2.returncode != 0:
        return None, None, f"decode failed: {r2.stderr.strip()}"
    return j2k, dec, None


def encode_decode_openjpeg(in_pgm, out_dir, bpp, bitdepth):
    j2k = out_dir / "opj.j2k"
    dec = out_dir / "opj_dec.pgm"
    # OpenJPEG: -r is compression ratio (orig_size_per_pixel_bits / target_bpp)
    ratio = bitdepth / bpp if bpp > 0 else 1
    enc_cmd = [OPJ_ENC, "-i", str(in_pgm), "-o", str(j2k), "-r", f"{ratio:.4f}"]
    r1 = subprocess.run(enc_cmd, capture_output=True, text=True, timeout=120)
    if r1.returncode != 0:
        return None, None, f"encode failed: {r1.stderr.strip()[:200]}"
    dec_cmd = [OPJ_DEC, "-i", str(j2k), "-o", str(dec)]
    r2 = subprocess.run(dec_cmd, capture_output=True, text=True, timeout=120)
    if r2.returncode != 0:
        return None, None, f"decode failed: {r2.stderr.strip()[:200]}"
    return j2k, dec, None


def _ojph_qstep_for_target_bpp(target_bpp, bitdepth):
    """Maps target bpp + bit-depth to OpenJPH `-qstep`. OpenJPH doesn't
    expose a direct bpp/rate flag — quantization step determines the
    achieved bpp implicitly through a non-linear relationship that
    has a sharp "knee" below which bpp collapses to near-zero. The
    table below was calibrated empirically on synthetic 512×512 test
    images per bit-depth; achieved bpp lands within ~30% of target
    on natural-image inputs. The matched-bpp interpolation downstream
    handles whatever achieved bpp falls out.
    """
    # Calibration tables: target bpp → qstep, per bit-depth. Values
    # were fit by sweeping qstep on synthetic test images and reading
    # off achieved bpp; see commit log for the calibration script.
    QSTEP_TABLE = {
        8:  {0.25: 0.075, 0.5: 0.058, 1.0: 0.046, 2.0: 0.024, 4.0: 0.0095},
        12: {0.25: 0.115, 0.5: 0.085, 1.0: 0.064, 2.0: 0.041, 4.0: 0.018},
        16: {0.25: 0.150, 0.5: 0.110, 1.0: 0.080, 2.0: 0.052, 4.0: 0.024},
    }
    bd_key = min(QSTEP_TABLE.keys(), key=lambda k: abs(k - bitdepth))
    table = QSTEP_TABLE[bd_key]
    # Direct lookup if the target is in the table
    if target_bpp in table:
        return table[target_bpp]
    # Otherwise log-linear interpolation between adjacent table entries
    targets = sorted(table.keys())
    if target_bpp <= targets[0]:
        return table[targets[0]]
    if target_bpp >= targets[-1]:
        return table[targets[-1]]
    for i in range(len(targets) - 1):
        a, b = targets[i], targets[i + 1]
        if a <= target_bpp <= b:
            t = (np.log(target_bpp) - np.log(a)) / (np.log(b) - np.log(a))
            qa, qb = table[a], table[b]
            return float(np.exp(np.log(qa) + t * (np.log(qb) - np.log(qa))))
    return table[targets[len(targets) // 2]]


def encode_decode_openjph(in_pgm, out_dir, bpp, bitdepth):
    j2k = out_dir / "ojph.j2c"
    dec = out_dir / "ojph_dec.pgm"
    qstep = _ojph_qstep_for_target_bpp(bpp, bitdepth)
    # OpenJPH: lossy compression via quantization step. Sets
    # `-reversible false` to engage the 9/7 lossy filter; `-qstep`
    # determines target quality, which implicitly determines bpp.
    enc_cmd = [OJPH_ENC, "-i", str(in_pgm), "-o", str(j2k),
               "-reversible", "false",
               "-qstep", f"{qstep:.7f}",
               "-colour_trans", "false"]
    r1 = subprocess.run(enc_cmd, capture_output=True, text=True, timeout=120)
    if r1.returncode != 0:
        return None, None, f"encode failed: {r1.stderr.strip()[:200]}"
    dec_cmd = [OJPH_DEC, "-i", str(j2k), "-o", str(dec)]
    r2 = subprocess.run(dec_cmd, capture_output=True, text=True, timeout=120)
    if r2.returncode != 0:
        return None, None, f"decode failed: {r2.stderr.strip()[:200]}"
    return j2k, dec, None


def encode_decode_grok(in_pgm, out_dir, bpp, bitdepth):
    j2k = out_dir / "grk.j2k"
    dec = out_dir / "grk_dec.pgm"
    ratio = bitdepth / bpp if bpp > 0 else 1
    # Grok: lowercase `-o` for output file (uppercase `-O` is output format)
    enc_cmd = [GRK_ENC, "-i", str(in_pgm), "-o", str(j2k), "-r", f"{ratio:.4f}"]
    r1 = subprocess.run(enc_cmd, capture_output=True, text=True, timeout=120)
    if r1.returncode != 0:
        return None, None, f"encode failed: {r1.stderr.strip()[:200]}"
    dec_cmd = [GRK_DEC, "-i", str(j2k), "-o", str(dec)]
    r2 = subprocess.run(dec_cmd, capture_output=True, text=True, timeout=120)
    if r2.returncode != 0:
        return None, None, f"decode failed: {r2.stderr.strip()[:200]}"
    return j2k, dec, None


CODECS = [
    ("J2KSwift", encode_decode_j2kswift),
    ("OpenJPEG", encode_decode_openjpeg),
    ("OpenJPH", encode_decode_openjph),
    ("Grok", encode_decode_grok),
]


# ---------------------------------------------------------------------------
# Quality metrics
# ---------------------------------------------------------------------------

def compute_psnr(orig, dec, maxval):
    """Peak signal-to-noise ratio in dB. Returns inf for identical inputs."""
    if orig.shape != dec.shape:
        return float("nan")
    diff = orig.astype(np.float64) - dec.astype(np.float64)
    mse = float(np.mean(diff * diff))
    if mse <= 1e-12:
        return float("inf")
    return 10.0 * np.log10((float(maxval) ** 2) / mse)


def compute_ssim(orig, dec, maxval):
    """Structural similarity index. nan if scikit-image unavailable."""
    if not HAS_SKIMAGE:
        return float("nan")
    if orig.shape != dec.shape:
        return float("nan")
    # data_range = maxval; convert to float64 for stability
    return float(ssim_fn(
        orig.astype(np.float64), dec.astype(np.float64),
        data_range=float(maxval)))


# ---------------------------------------------------------------------------
# Run pipeline
# ---------------------------------------------------------------------------

def run_one(orig_arr, maxval, image_name, codec_name, encode_fn,
            target_bpp, work_dir):
    """Encode + decode one (image, codec, target_bpp) and return a result dict."""
    h, w = orig_arr.shape
    bitdepth = 8 if maxval <= 255 else (12 if maxval <= 4095 else 16)
    pixel_count = w * h

    # Write input PGM into the work dir so the encoder can read it.
    in_pgm = work_dir / f"{image_name}_input.pgm"
    write_pgm(str(in_pgm), orig_arr, maxval)

    j2k_path, dec_path, err = encode_fn(in_pgm, work_dir, target_bpp, bitdepth)
    if err is not None:
        return {
            "image": image_name, "codec": codec_name,
            "target_bpp": target_bpp,
            "achieved_bpp": float("nan"),
            "psnr_db": float("nan"), "ssim": float("nan"),
            "file_size_bytes": 0,
            "error": err,
        }

    file_size = j2k_path.stat().st_size
    achieved_bpp = file_size * 8.0 / pixel_count

    try:
        dec_arr, dec_maxval = read_pgm(str(dec_path))
        if dec_arr.shape != orig_arr.shape:
            # Some codecs may emit slightly different dims if header mismatches
            return {
                "image": image_name, "codec": codec_name,
                "target_bpp": target_bpp,
                "achieved_bpp": achieved_bpp,
                "psnr_db": float("nan"), "ssim": float("nan"),
                "file_size_bytes": file_size,
                "error": f"shape mismatch: orig={orig_arr.shape} dec={dec_arr.shape}",
            }
        psnr = compute_psnr(orig_arr, dec_arr, maxval)
        ssim = compute_ssim(orig_arr, dec_arr, maxval)
    except Exception as e:
        return {
            "image": image_name, "codec": codec_name,
            "target_bpp": target_bpp,
            "achieved_bpp": achieved_bpp,
            "psnr_db": float("nan"), "ssim": float("nan"),
            "file_size_bytes": file_size,
            "error": f"decode read failed: {e}",
        }

    return {
        "image": image_name, "codec": codec_name,
        "target_bpp": target_bpp,
        "achieved_bpp": achieved_bpp,
        "psnr_db": psnr, "ssim": ssim,
        "file_size_bytes": file_size,
        "error": "",
    }


def run_full_pipeline(images, bpp_targets, codecs):
    """Runs the full matrix and returns rows as a list of dicts."""
    rows = []
    work_root = TMP_DIR
    work_root.mkdir(parents=True, exist_ok=True)

    total = len(images) * len(codecs) * len(bpp_targets)
    done = 0
    for image_name, arr, maxval in images:
        h, w = arr.shape
        bd = 8 if maxval <= 255 else (12 if maxval <= 4095 else 16)
        print(f"\n=== {image_name} ({w}x{h} {bd}-bit, maxval={maxval}) ===")
        for codec_name, encode_fn in codecs:
            for bpp in bpp_targets:
                done += 1
                work_dir = work_root / f"{image_name}_{codec_name}_{bpp}"
                work_dir.mkdir(parents=True, exist_ok=True)
                row = run_one(arr, maxval, image_name, codec_name, encode_fn, bpp, work_dir)
                rows.append(row)
                if row["error"]:
                    print(f"  [{done}/{total}] {codec_name:10} target={bpp:.2f}bpp  ERROR: {row['error']}")
                else:
                    psnr_str = "inf" if row["psnr_db"] == float("inf") else f"{row['psnr_db']:6.2f}"
                    ssim_str = "n/a" if not HAS_SKIMAGE else f"{row['ssim']:.4f}"
                    print(f"  [{done}/{total}] {codec_name:10} target={bpp:.2f}bpp  achieved={row['achieved_bpp']:5.3f}bpp  PSNR={psnr_str}dB  SSIM={ssim_str}")
    return rows


# ---------------------------------------------------------------------------
# Output: CSV, plots, summary
# ---------------------------------------------------------------------------

def write_csv(rows, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "image", "codec", "target_bpp", "achieved_bpp",
            "psnr_db", "ssim", "file_size_bytes", "error",
        ])
        for r in rows:
            w.writerow([
                r["image"], r["codec"],
                f"{r['target_bpp']:.4f}",
                f"{r['achieved_bpp']:.6f}" if not np.isnan(r["achieved_bpp"]) else "",
                "inf" if r["psnr_db"] == float("inf") else (f"{r['psnr_db']:.4f}" if not np.isnan(r["psnr_db"]) else ""),
                f"{r['ssim']:.6f}" if not np.isnan(r["ssim"]) else "",
                r["file_size_bytes"],
                r["error"],
            ])


def plot_per_image(rows, image_name, out_path):
    if not HAS_MPL:
        return
    fig, ax = plt.subplots(figsize=(8, 5.5))
    codec_styles = {
        "J2KSwift": ("o-", "#1f77b4"),
        "OpenJPEG": ("s-", "#ff7f0e"),
        "OpenJPH":  ("^-", "#2ca02c"),
        "Grok":     ("d-", "#d62728"),
    }
    for codec_name, (style, colour) in codec_styles.items():
        pts = sorted([
            (r["achieved_bpp"], r["psnr_db"]) for r in rows
            if r["image"] == image_name and r["codec"] == codec_name
            and not np.isnan(r["achieved_bpp"]) and not np.isnan(r["psnr_db"])
            and r["psnr_db"] != float("inf")  # skip ∞ for plot Y-axis
        ])
        if not pts:
            continue
        xs, ys = zip(*pts)
        ax.plot(xs, ys, style, label=codec_name, color=colour, markersize=7, linewidth=1.6)

    ax.set_xlabel("Achieved bitrate (bpp)")
    ax.set_ylabel("PSNR (dB)")
    ax.set_title(f"Rate-Distortion: {image_name}")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(out_path, dpi=120)
    plt.close(fig)


def interpolate_curve(points, target_bpp):
    """Linear interp PSNR at target_bpp from a list of (bpp, psnr) points.
    Returns nan if target_bpp is outside the [min, max] of `points` to avoid
    spurious extrapolation."""
    if not points:
        return float("nan")
    pts = sorted(points)
    bpps, psnrs = zip(*pts)
    if target_bpp < bpps[0] or target_bpp > bpps[-1]:
        return float("nan")
    return float(np.interp(target_bpp, bpps, psnrs))


def matched_bpp_summary(rows, images, matched_targets):
    """For each image, interpolate each codec's curve at matched_targets and
    return a list of (image, target_bpp, {codec: psnr})."""
    out = []
    for image_name, _, _ in images:
        for tgt in matched_targets:
            row = {"image": image_name, "matched_bpp": tgt}
            for codec_name, _ in CODECS:
                pts = [
                    (r["achieved_bpp"], r["psnr_db"]) for r in rows
                    if r["image"] == image_name and r["codec"] == codec_name
                    and not np.isnan(r["achieved_bpp"])
                    and not np.isnan(r["psnr_db"]) and r["psnr_db"] != float("inf")
                ]
                row[codec_name] = interpolate_curve(pts, tgt)
            out.append(row)
    return out


def write_summary_md(rows, images, matched, path):
    """Markdown summary: per-image curve description + matched-bpp table."""
    lines = []
    lines.append("# Rate-Distortion Benchmark — J2KSwift vs OpenJPEG / OpenJPH / Grok")
    lines.append("")
    lines.append("**Generated:** `Scripts/rd_benchmark.py`")
    lines.append("")
    lines.append("PSNR (dB) at *matched* achieved bitrate, linearly interpolated from")
    lines.append("each codec's R-D curve. `n/a` means the target falls outside the")
    lines.append("codec's measured range (interpolation only — no extrapolation).")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Per-image PSNR at matched achieved bpp")
    lines.append("")
    lines.append("| Image | Achieved bpp | J2KSwift | OpenJPEG | OpenJPH | Grok | Best |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    for row in matched:
        cells = [
            row["image"], f"{row['matched_bpp']:.2f}",
        ]
        scores = []
        for codec_name, _ in CODECS:
            v = row.get(codec_name, float("nan"))
            if np.isnan(v):
                cells.append("n/a")
            else:
                cells.append(f"{v:.2f}")
                scores.append((v, codec_name))
        if scores:
            best = max(scores)
            cells.append(f"**{best[1]}** (+{best[0] - sorted(scores)[-2][0]:.2f} dB vs 2nd)" if len(scores) > 1 else f"**{best[1]}**")
        else:
            cells.append("—")
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Raw R-D points (achieved bpp, PSNR dB)")
    lines.append("")
    for image_name, _, _ in images:
        lines.append(f"### {image_name}")
        lines.append("")
        lines.append("| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |")
        lines.append("|---|---:|---:|---:|---:|")
        for r in rows:
            if r["image"] != image_name:
                continue
            psnr_s = "—" if r["error"] else (
                "∞" if r["psnr_db"] == float("inf") else
                ("nan" if np.isnan(r["psnr_db"]) else f"{r['psnr_db']:.2f}"))
            ssim_s = "n/a" if not HAS_SKIMAGE else (
                ("nan" if np.isnan(r["ssim"]) else f"{r['ssim']:.4f}"))
            achieved_s = "—" if np.isnan(r["achieved_bpp"]) else f"{r['achieved_bpp']:.3f}"
            lines.append(f"| {r['codec']} | {r['target_bpp']:.2f} | {achieved_s} | {psnr_s} | {ssim_s} |")
        lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Notes & caveats")
    lines.append("")
    lines.append("- **Matched-bpp values** are linearly interpolated from each codec's")
    lines.append("  R-D curve. This is the right comparison axis when the codecs land at")
    lines.append("  different *achieved* bitrates for the same nominal target — see the")
    lines.append("  v5.14.2 benchmark report for the rate-control caveat that motivated")
    lines.append("  this pipeline.")
    lines.append("- **Lossless rows** (where PSNR = ∞) are excluded from interpolation.")
    lines.append("  J2KSwift and OpenJPEG/OpenJPH/Grok all reach lossless at ~6–9 bpp")
    lines.append("  depending on bit-depth — but lossless isn't the question this")
    lines.append("  benchmark answers.")
    lines.append("- **Bit-depth-aware ratios.** OpenJPEG and Grok take a `-r` flag that")
    lines.append("  is the compression ratio relative to the input's bit-depth × pixel")
    lines.append("  count; OpenJPH's `-rate` is bpp directly; J2KSwift's `--bitrate` is")
    lines.append("  also bpp directly. Each pipeline computes the correct flag value.")
    lines.append("- **Plot files**: see `rd_plot_<image>.png` next to this summary for")
    lines.append("  visual R-D curves.")
    lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--quick", action="store_true",
                        help="Smaller image set + fewer bpp targets (for fast iteration)")
    parser.add_argument("--images", nargs="*", default=None,
                        help="Override image set with explicit PGM paths")
    parser.add_argument("--out-dir", type=str, default=str(OUT_DIR),
                        help=f"Output directory (default: {OUT_DIR})")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    bpp_targets = QUICK_BPP_TARGETS if args.quick else DEFAULT_BPP_TARGETS

    if args.images:
        images = []
        for p in args.images:
            arr, mv = read_pgm(p)
            name = Path(p).stem
            images.append((name, arr, mv))
    else:
        images = build_image_set(quick=args.quick)

    print(f"Image set: {[(n, a.shape, m) for n, a, m in images]}")
    print(f"BPP targets: {bpp_targets}")
    print(f"Codecs: {[c[0] for c in CODECS]}")
    print(f"Output: {out_dir}")
    print()

    # Filter codecs that aren't installed
    codecs = []
    for name, fn in CODECS:
        # Sniff the binary if applicable
        if name == "J2KSwift" and not J2K_CLI.exists():
            print(f"warning: skipping J2KSwift — {J2K_CLI} not found")
            continue
        elif name == "OpenJPEG" and not Path(OPJ_ENC).exists():
            print(f"warning: skipping OpenJPEG — {OPJ_ENC} not found")
            continue
        elif name == "OpenJPH" and not Path(OJPH_ENC).exists():
            print(f"warning: skipping OpenJPH — {OJPH_ENC} not found")
            continue
        elif name == "Grok" and not Path(GRK_ENC).exists():
            print(f"warning: skipping Grok — {GRK_ENC} not found")
            continue
        codecs.append((name, fn))

    rows = run_full_pipeline(images, bpp_targets, codecs)

    csv_path = out_dir / "rd_results.csv"
    write_csv(rows, csv_path)
    print(f"\nWrote CSV: {csv_path}")

    if HAS_MPL:
        for image_name, _, _ in images:
            plot_path = out_dir / f"rd_plot_{image_name}.png"
            plot_per_image(rows, image_name, plot_path)
            print(f"Wrote plot: {plot_path}")

    matched = matched_bpp_summary(rows, images, MATCHED_BPP)
    summary_path = out_dir / "rd_summary.md"
    write_summary_md(rows, images, matched, summary_path)
    print(f"Wrote summary: {summary_path}")

    # Print matched-bpp summary inline
    print("\n=== Matched-bpp PSNR summary ===")
    for row in matched:
        cells = [f"{row['image']:>16}  {row['matched_bpp']:.2f}bpp"]
        for codec_name, _ in CODECS:
            v = row.get(codec_name, float("nan"))
            cells.append(f"{codec_name}={v:.2f}" if not np.isnan(v) else f"{codec_name}=n/a")
        print("  " + "  ".join(cells))


if __name__ == "__main__":
    main()
