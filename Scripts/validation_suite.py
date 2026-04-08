#!/usr/bin/env python3
"""
Extended Validation Suite for J2KSwift
- Cross-decoder validation (J2KSwift ↔ OpenJPEG interop)
- Stress & edge case testing (uniform, low contrast, high noise, checkerboard)
- Higher resolution testing (2048×2048, 4096×4096)
- Exports results as Markdown + CSV
"""

import numpy as np
import struct
import subprocess
import os
import sys
import time
import csv

TMPDIR = "/private/tmp/validation_suite"
J2K_CLI = None
OPJ_COMPRESS = "/opt/homebrew/bin/opj_compress"
OPJ_DECOMPRESS = "/opt/homebrew/bin/opj_decompress"

# ============================================================
# PGM I/O (P5 binary, 16-bit big-endian)
# ============================================================

def write_pgm(path, img, maxval):
    h, w = img.shape
    header = f"P5\n{w} {h}\n{maxval}\n".encode('ascii')
    with open(path, 'wb') as f:
        f.write(header)
        if maxval <= 255:
            f.write(img.astype(np.uint8).tobytes())
        else:
            f.write(img.astype('>u2').tobytes())


def read_pgm(path):
    with open(path, 'rb') as f:
        magic = f.readline().strip()
        assert magic == b'P5', f"Not a P5 PGM: {magic}"
        while True:
            line = f.readline()
            if not line.startswith(b'#'):
                break
        parts = line.split()
        if len(parts) < 2:
            parts.extend(f.readline().split())
        w, h = int(parts[0]), int(parts[1])
        maxval = int(f.readline().strip())
        data = f.read()
    if maxval <= 255:
        img = np.frombuffer(data, dtype=np.uint8).reshape(h, w)
    else:
        img = np.frombuffer(data, dtype='>u2').reshape(h, w)
    return img.astype(np.float64), maxval


# ============================================================
# Metrics
# ============================================================

def compute_psnr(orig, dec, maxval):
    mse = np.mean((orig - dec) ** 2)
    if mse == 0:
        return float('inf')
    return 10.0 * np.log10(maxval ** 2 / mse)


def compute_mae(orig, dec):
    return np.mean(np.abs(orig - dec))


def _box_filter_2d(img, k):
    r = k // 2
    padded = np.pad(img, r, mode='reflect')
    ph, pw = padded.shape
    S = np.zeros((ph + 1, pw + 1), dtype=np.float64)
    S[1:, 1:] = np.cumsum(np.cumsum(padded, axis=0), axis=1)
    h, w = img.shape
    rows_b = np.arange(k, h + k)
    rows_t = np.arange(0, h)
    cols_r = np.arange(k, w + k)
    cols_l = np.arange(0, w)
    result = (S[np.ix_(rows_b, cols_r)]
              - S[np.ix_(rows_t, cols_r)]
              - S[np.ix_(rows_b, cols_l)]
              + S[np.ix_(rows_t, cols_l)])
    return result / (k * k)


def compute_ssim(orig, dec, maxval, k=11):
    C1 = (0.01 * maxval) ** 2
    C2 = (0.03 * maxval) ** 2
    mu_x = _box_filter_2d(orig, k)
    mu_y = _box_filter_2d(dec, k)
    mu_x2 = mu_x ** 2
    mu_y2 = mu_y ** 2
    mu_xy = mu_x * mu_y
    sigma_x2 = _box_filter_2d(orig ** 2, k) - mu_x2
    sigma_y2 = _box_filter_2d(dec ** 2, k) - mu_y2
    sigma_xy = _box_filter_2d(orig * dec, k) - mu_xy
    ssim_map = ((2 * mu_xy + C1) * (2 * sigma_xy + C2)) / \
               ((mu_x2 + mu_y2 + C1) * (sigma_x2 + sigma_y2 + C2))
    return np.mean(ssim_map)


# ============================================================
# Encode / Decode helpers
# ============================================================

def j2k_encode(input_pgm, output_j2k, bpp=None, lossless=False):
    cmd = [J2K_CLI, "encode", "-i", input_pgm, "-o", output_j2k, "--quiet"]
    if lossless:
        cmd.extend(["--lossless"])
    elif bpp is not None:
        cmd.extend(["--bitrate", str(bpp)])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"  J2K encode error: {result.stderr.strip()}")
        return False
    return True


def j2k_decode(input_j2k, output_pgm):
    cmd = [J2K_CLI, "decode", "-i", input_j2k, "-o", output_pgm, "--quiet"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"  J2K decode error: {result.stderr.strip()}")
        return False
    return True


def opj_encode(input_pgm, output_j2k, bpp=None, lossless=False, bit_depth=16):
    cmd = [OPJ_COMPRESS, "-i", input_pgm, "-o", output_j2k]
    if not lossless and bpp is not None:
        ratio = bit_depth / bpp
        cmd.extend(["-r", str(ratio)])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"  OPJ encode error: {result.stderr.strip()}")
        return False
    return True


def opj_decode(input_j2k, output_pgm):
    cmd = [OPJ_DECOMPRESS, "-i", input_j2k, "-o", output_pgm]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"  OPJ decode error: {result.stderr.strip()}")
        return False
    return True


# ============================================================
# Synthetic Image Generators
# ============================================================

def generate_ct_image(w=512, h=512, bit_depth=16):
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(42)
    img = np.zeros((h, w), dtype=np.float64)
    img[:] = 100
    cy, cx = h // 2, w // 2
    ry, rx = int(h * 0.4), int(w * 0.35)
    Y, X = np.ogrid[:h, :w]
    body_mask = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1.0
    img[body_mask] = 30000
    spine_mask = ((X - cx) / 25) ** 2 + ((Y - cy) / 40) ** 2 <= 1.0
    img[spine_mask] = 55000
    lung_l = ((X - (cx - rx // 2)) / (rx // 3)) ** 2 + ((Y - (cy - ry // 6)) / (ry // 2)) ** 2 <= 1.0
    lung_r = ((X - (cx + rx // 2)) / (rx // 3)) ** 2 + ((Y - (cy - ry // 6)) / (ry // 2)) ** 2 <= 1.0
    img[lung_l] = 5000
    img[lung_r] = 5000
    heart = ((X - (cx + 10)) / 50) ** 2 + ((Y - (cy + 20)) / 45) ** 2 <= 1.0
    img[heart] = 35000
    noise = rng.normal(0, 500, (h, w))
    img += noise
    padded = np.pad(img, 1, mode='reflect')
    from numpy.lib.stride_tricks import sliding_window_view
    windows = sliding_window_view(padded, (3, 3))
    img = np.mean(windows, axis=(2, 3))
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_mri_image(w=256, h=256, bit_depth=12):
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(123)
    img = np.zeros((h, w), dtype=np.float64)
    img[:] = 50
    cy, cx = h // 2, w // 2
    Y, X = np.ogrid[:h, :w]
    skull_outer = ((X - cx) / (w * 0.42)) ** 2 + ((Y - cy) / (h * 0.45)) ** 2 <= 1.0
    skull_inner = ((X - cx) / (w * 0.38)) ** 2 + ((Y - cy) / (h * 0.41)) ** 2 <= 1.0
    img[skull_outer & ~skull_inner] = 3500
    brain_mask = skull_inner
    img[brain_mask] = 2200
    wm_mask = ((X - cx) / (w * 0.28)) ** 2 + ((Y - cy) / (h * 0.30)) ** 2 <= 1.0
    img[wm_mask] = 3000
    vent_l = ((X - (cx - 15)) / 12) ** 2 + ((Y - (cy - 10)) / 30) ** 2 <= 1.0
    vent_r = ((X - (cx + 15)) / 12) ** 2 + ((Y - (cy - 10)) / 30) ** 2 <= 1.0
    img[vent_l] = 500
    img[vent_r] = 500
    cn_l = ((X - (cx - 25)) / 10) ** 2 + ((Y - (cy - 5)) / 15) ** 2 <= 1.0
    cn_r = ((X - (cx + 25)) / 10) ** 2 + ((Y - (cy - 5)) / 15) ** 2 <= 1.0
    img[cn_l] = 2500
    img[cn_r] = 2500
    noise = rng.normal(0, 80, (h, w))
    img += noise
    padded = np.pad(img, 1, mode='reflect')
    from numpy.lib.stride_tricks import sliding_window_view
    windows = sliding_window_view(padded, (3, 3))
    img = np.mean(windows, axis=(2, 3))
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_ultrasound_image(w=640, h=480, bit_depth=12):
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(789)
    base = rng.rayleigh(scale=800, size=(h, w))
    Y, X = np.ogrid[:h, :w]
    cy, cx = h // 2, w // 2
    angle = np.arctan2(X - cx, Y - 20)
    dist = np.sqrt((X - cx) ** 2 + (Y - 20) ** 2)
    sector = (np.abs(angle) < 0.6) & (dist > 50) & (dist < h * 0.9)
    img = np.zeros((h, w), dtype=np.float64)
    img[sector] = base[sector]
    cyst = ((X - (cx + 40)) / 30) ** 2 + ((Y - (cy + 50)) / 25) ** 2 <= 1.0
    img[cyst & sector] = rng.rayleigh(scale=100, size=(h, w))[cyst & sector]
    tissue = ((X - (cx - 30)) / 50) ** 2 + ((Y - (cy + 20)) / 35) ** 2 <= 1.0
    img[tissue & sector] = rng.rayleigh(scale=1500, size=(h, w))[tissue & sector]
    depth_atten = np.exp(-0.002 * np.maximum(0, Y - 20))
    img *= depth_atten
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


# ============================================================
# Stress / Edge-Case Image Generators
# ============================================================

def generate_uniform_image(w, h, bit_depth, value_fraction=0.5):
    """Flat-field image at a constant value. Tests DC-only content."""
    maxval = (1 << bit_depth) - 1
    val = int(maxval * value_fraction)
    img = np.full((h, w), val, dtype=np.uint16)
    return img, maxval


def generate_low_contrast_gradient(w, h, bit_depth):
    """Gentle horizontal gradient spanning only 2% of the dynamic range."""
    maxval = (1 << bit_depth) - 1
    center = maxval // 2
    span = int(maxval * 0.02)  # 2% of range
    row = np.linspace(center - span // 2, center + span // 2, w)
    img = np.tile(row, (h, 1))
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_high_noise_image(w, h, bit_depth):
    """High-variance Gaussian noise (like a noisy acquisition)."""
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(555)
    sigma = maxval * 0.25  # 25% of dynamic range
    img = rng.normal(maxval / 2, sigma, (h, w))
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_checkerboard(w, h, bit_depth, block_size=8):
    """Alternating black/white blocks — worst-case for wavelet transforms."""
    maxval = (1 << bit_depth) - 1
    rows = np.arange(h) // block_size
    cols = np.arange(w) // block_size
    grid = (rows[:, None] + cols[None, :]) % 2
    img = (grid * maxval).astype(np.uint16)
    return img, maxval


def generate_dead_pixel_image(w, h, bit_depth):
    """Smooth gradient with random dead/hot pixels — tests robustness."""
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(321)
    # Vertical gradient
    grad = np.linspace(0.1 * maxval, 0.9 * maxval, h)
    img = np.tile(grad[:, None], (1, w)).astype(np.float64)
    # Add dead pixels (stuck at 0)
    n_dead = max(1, (w * h) // 500)
    dead_y = rng.integers(0, h, n_dead)
    dead_x = rng.integers(0, w, n_dead)
    img[dead_y, dead_x] = 0
    # Add hot pixels (stuck at maxval)
    hot_y = rng.integers(0, h, n_dead)
    hot_x = rng.integers(0, w, n_dead)
    img[hot_y, hot_x] = maxval
    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


# ============================================================
# Cross-Decoder Validation
# ============================================================

def cross_decode_test(name, orig_img, maxval, bit_depth, bitrates):
    """
    Test interoperability:
      Path A: J2KSwift encode → OPJ decode
      Path B: OPJ encode → J2KSwift decode
    Compare decoded output against original.
    """
    input_pgm = os.path.join(TMPDIR, f"xdec_{name}.pgm")
    write_pgm(input_pgm, orig_img, maxval)
    orig_f = orig_img.astype(np.float64)
    results = []

    for bpp_label, bpp, is_lossless in bitrates:
        # --- Path A: J2K encode → OPJ decode ---
        j2k_file_a = os.path.join(TMPDIR, f"xdec_{name}_{bpp_label}_j2k_enc.j2k")
        dec_file_a = os.path.join(TMPDIR, f"xdec_{name}_{bpp_label}_opj_dec.pgm")

        row_a = {"test": f"{name}", "bit_depth": bit_depth, "bitrate": bpp_label,
                 "path": "J2K→OPJ"}

        ok = j2k_encode(input_pgm, j2k_file_a, bpp=bpp, lossless=is_lossless)
        if ok and os.path.exists(j2k_file_a):
            ok = opj_decode(j2k_file_a, dec_file_a)
            if ok and os.path.exists(dec_file_a):
                dec_f, _ = read_pgm(dec_file_a)
                if dec_f.shape == orig_f.shape:
                    row_a["psnr"] = compute_psnr(orig_f, dec_f, maxval)
                    row_a["ssim"] = compute_ssim(orig_f, dec_f, maxval)
                    row_a["mae"] = compute_mae(orig_f, dec_f)
                    row_a["size"] = os.path.getsize(j2k_file_a)
                    row_a["status"] = "OK"
                else:
                    row_a["status"] = f"SHAPE({dec_f.shape})"
            else:
                row_a["status"] = "DEC_FAIL"
        else:
            row_a["status"] = "ENC_FAIL"

        results.append(row_a)

        # --- Path B: OPJ encode → J2K decode ---
        j2k_file_b = os.path.join(TMPDIR, f"xdec_{name}_{bpp_label}_opj_enc.j2k")
        dec_file_b = os.path.join(TMPDIR, f"xdec_{name}_{bpp_label}_j2k_dec.pgm")

        row_b = {"test": f"{name}", "bit_depth": bit_depth, "bitrate": bpp_label,
                 "path": "OPJ→J2K"}

        ok = opj_encode(input_pgm, j2k_file_b, bpp=bpp, lossless=is_lossless,
                        bit_depth=bit_depth if bit_depth > 8 else 16)
        if ok and os.path.exists(j2k_file_b):
            ok = j2k_decode(j2k_file_b, dec_file_b)
            if ok and os.path.exists(dec_file_b):
                dec_f, _ = read_pgm(dec_file_b)
                if dec_f.shape == orig_f.shape:
                    row_b["psnr"] = compute_psnr(orig_f, dec_f, maxval)
                    row_b["ssim"] = compute_ssim(orig_f, dec_f, maxval)
                    row_b["mae"] = compute_mae(orig_f, dec_f)
                    row_b["size"] = os.path.getsize(j2k_file_b)
                    row_b["status"] = "OK"
                else:
                    row_b["status"] = f"SHAPE({dec_f.shape})"
            else:
                row_b["status"] = "DEC_FAIL"
        else:
            row_b["status"] = "ENC_FAIL"

        results.append(row_b)

    return results


# ============================================================
# Same-codec self-test (encode→decode with same codec)
# ============================================================

def self_test(name, orig_img, maxval, bit_depth, bitrates):
    """Standard benchmark: each codec encodes and decodes its own files."""
    input_pgm = os.path.join(TMPDIR, f"self_{name}.pgm")
    write_pgm(input_pgm, orig_img, maxval)
    orig_f = orig_img.astype(np.float64)
    results = []

    for bpp_label, bpp, is_lossless in bitrates:
        for codec_name, enc_fn, dec_fn in [
            ("J2K", j2k_encode, j2k_decode),
            ("OPJ", opj_encode, opj_decode),
        ]:
            j2k_file = os.path.join(TMPDIR, f"self_{name}_{bpp_label}_{codec_name}.j2k")
            dec_file = os.path.join(TMPDIR, f"self_{name}_{bpp_label}_{codec_name}_dec.pgm")

            row = {"test": name, "bit_depth": bit_depth, "bitrate": bpp_label,
                   "path": f"{codec_name}→{codec_name}"}

            enc_kw = {"bpp": bpp, "lossless": is_lossless}
            if codec_name == "OPJ":
                enc_kw["bit_depth"] = bit_depth if bit_depth > 8 else 16
            ok = enc_fn(input_pgm, j2k_file, **enc_kw)
            if ok and os.path.exists(j2k_file):
                ok = dec_fn(j2k_file, dec_file)
                if ok and os.path.exists(dec_file):
                    dec_f, _ = read_pgm(dec_file)
                    if dec_f.shape == orig_f.shape:
                        row["psnr"] = compute_psnr(orig_f, dec_f, maxval)
                        row["ssim"] = compute_ssim(orig_f, dec_f, maxval)
                        row["mae"] = compute_mae(orig_f, dec_f)
                        row["size"] = os.path.getsize(j2k_file)
                        row["status"] = "OK"
                    else:
                        row["status"] = f"SHAPE({dec_f.shape})"
                else:
                    row["status"] = "DEC_FAIL"
            else:
                row["status"] = "ENC_FAIL"

            results.append(row)

    return results


# ============================================================
# Formatting / Reporting
# ============================================================

def format_val(v, fmt=".2f"):
    if v is None:
        return "N/A"
    if isinstance(v, str):
        return v
    if isinstance(v, float) and v == float('inf'):
        return "∞"
    return f"{v:{fmt}}"


def print_section(title, results):
    print(f"\n{'=' * 110}")
    print(f"  {title}")
    print(f"{'=' * 110}")
    header = (
        f"{'Test':<22} {'Bits':>4} {'Rate':>8} {'Path':<12} │"
        f" {'PSNR':>10} {'SSIM':>9} {'MAE':>9} {'Size':>10} {'Status':>10}"
    )
    print(header)
    print("─" * 110)
    for row in results:
        psnr = row.get("psnr")
        ssim = row.get("ssim")
        mae = row.get("mae")
        size = row.get("size", "")
        status = row.get("status", "?")
        size_str = str(size) if size else ""
        print(
            f"{row['test']:<22} {row['bit_depth']:>4} {row['bitrate']:>8} {row['path']:<12} │"
            f" {format_val(psnr):>10} {format_val(ssim, '.4f'):>9} {format_val(mae):>9}"
            f" {size_str:>10} {status:>10}"
        )
    print("─" * 110)


def save_csv(all_results, filepath):
    """Save all results to a CSV file."""
    if not all_results:
        return
    fieldnames = ["section", "test", "bit_depth", "bitrate", "path",
                  "psnr", "ssim", "mae", "size", "status"]
    with open(filepath, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for row in all_results:
            out = dict(row)
            psnr = out.get("psnr")
            if isinstance(psnr, float) and psnr == float('inf'):
                out["psnr"] = "inf"
            writer.writerow(out)
    print(f"\nCSV saved to: {filepath}")


def save_markdown_report(sections, filepath):
    """Save a multi-section Markdown report."""
    lines = []
    lines.append("# Validation Suite Report: J2KSwift")
    lines.append("")
    lines.append(f"**Date:** {time.strftime('%Y-%m-%d %H:%M')}")
    lines.append("")

    for title, results in sections:
        lines.append(f"## {title}")
        lines.append("")
        lines.append("| Test | Bits | Bitrate | Path | PSNR | SSIM | MAE | Size | Status |")
        lines.append("|------|------|---------|------|------|------|-----|------|--------|")
        for row in results:
            psnr = format_val(row.get("psnr"))
            ssim = format_val(row.get("ssim"), ".4f")
            mae = format_val(row.get("mae"))
            size = row.get("size", "")
            status = row.get("status", "?")
            lines.append(
                f"| {row['test']} | {row['bit_depth']} | {row['bitrate']} "
                f"| {row['path']} | {psnr} | {ssim} | {mae} "
                f"| {size} | {status} |"
            )
        lines.append("")

    # Summary statistics
    lines.append("## Summary")
    lines.append("")
    for title, results in sections:
        ok_results = [r for r in results if r.get("status") == "OK"]
        fail_results = [r for r in results if r.get("status") != "OK"]
        lines.append(f"### {title}")
        lines.append(f"- **Total tests:** {len(results)}")
        lines.append(f"- **Passed:** {len(ok_results)}")
        lines.append(f"- **Failed:** {len(fail_results)}")
        if ok_results:
            psnrs = [r["psnr"] for r in ok_results if isinstance(r.get("psnr"), (int, float)) and r["psnr"] != float('inf')]
            if psnrs:
                lines.append(f"- **PSNR range:** {min(psnrs):.2f} – {max(psnrs):.2f} dB")
            lossless = [r for r in ok_results if isinstance(r.get("psnr"), float) and r["psnr"] == float('inf')]
            if lossless:
                lines.append(f"- **Lossless perfect:** {len(lossless)} tests")
        if fail_results:
            lines.append(f"- **Failures:** " + ", ".join(
                f"{r['test']}/{r['bitrate']}/{r['path']}={r['status']}" for r in fail_results))
        lines.append("")

    lines.append("## Notes")
    lines.append("")
    lines.append("- PSNR: Peak Signal-to-Noise Ratio (dB) — higher is better")
    lines.append("- SSIM: Structural Similarity Index — closer to 1.0 is better")
    lines.append("- MAE: Mean Absolute Error — lower is better")
    lines.append("- J2K→OPJ: encoded with J2KSwift, decoded with OpenJPEG")
    lines.append("- OPJ→J2K: encoded with OpenJPEG, decoded with J2KSwift")
    lines.append("- Lossless: exact reconstruction (PSNR = ∞, MAE = 0)")
    lines.append("")

    with open(filepath, 'w') as f:
        f.write('\n'.join(lines))
    print(f"Markdown report saved to: {filepath}")


# ============================================================
# Main
# ============================================================

def main():
    global J2K_CLI

    # Find J2K CLI
    build_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               ".build", "release", "j2k")
    if os.path.exists(build_path):
        J2K_CLI = build_path
    else:
        debug_path = build_path.replace("release", "debug")
        if os.path.exists(debug_path):
            J2K_CLI = debug_path
        else:
            print(f"ERROR: j2k CLI not found at {build_path}")
            print("Run: swift build -c release")
            sys.exit(1)

    print(f"J2K CLI: {J2K_CLI}")
    print(f"OPJ compress: {OPJ_COMPRESS}")
    print(f"OPJ decompress: {OPJ_DECOMPRESS}")

    if not os.path.exists(OPJ_COMPRESS):
        print(f"WARNING: OpenJPEG not found at {OPJ_COMPRESS}")

    os.makedirs(TMPDIR, exist_ok=True)

    bitrates = [
        ("0.25bpp", 0.25, False),
        ("0.50bpp", 0.50, False),
        ("0.75bpp", 0.75, False),
        ("lossless", None, True),
    ]

    # Fewer bitrates for large images to save time
    bitrates_fast = [
        ("0.50bpp", 0.50, False),
        ("lossless", None, True),
    ]

    all_csv_rows = []
    report_sections = []

    # ----------------------------------------------------------
    # Section 1: Cross-Decoder Validation (medical images)
    # ----------------------------------------------------------
    print("\n" + "#" * 60)
    print("  SECTION 1: CROSS-DECODER VALIDATION")
    print("#" * 60)

    xdec_results = []

    print("\n>>> CT 512×512 16-bit cross-decoder test...")
    ct_img, ct_max = generate_ct_image(512, 512, 16)
    xdec_results.extend(cross_decode_test("CT-16bit", ct_img, ct_max, 16, bitrates))

    print("\n>>> MRI 256×256 12-bit cross-decoder test...")
    mri_img, mri_max = generate_mri_image(256, 256, 12)
    xdec_results.extend(cross_decode_test("MRI-12bit", mri_img, mri_max, 12, bitrates))

    print("\n>>> Ultrasound 640×480 12-bit cross-decoder test...")
    us_img, us_max = generate_ultrasound_image(640, 480, 12)
    xdec_results.extend(cross_decode_test("US-12bit", us_img, us_max, 12, bitrates))

    print_section("Cross-Decoder Validation", xdec_results)
    for r in xdec_results:
        r["section"] = "cross-decoder"
    all_csv_rows.extend(xdec_results)
    report_sections.append(("Cross-Decoder Validation", xdec_results))

    # ----------------------------------------------------------
    # Section 2: Stress & Edge-Case Images
    # ----------------------------------------------------------
    print("\n" + "#" * 60)
    print("  SECTION 2: STRESS & EDGE-CASE IMAGES")
    print("#" * 60)

    stress_results = []

    stress_images = [
        ("Uniform-50%", generate_uniform_image, {"w": 256, "h": 256, "bit_depth": 16, "value_fraction": 0.5}),
        ("Uniform-0%",  generate_uniform_image, {"w": 256, "h": 256, "bit_depth": 16, "value_fraction": 0.0}),
        ("Uniform-100%", generate_uniform_image, {"w": 256, "h": 256, "bit_depth": 16, "value_fraction": 1.0}),
        ("LowContrast",  generate_low_contrast_gradient, {"w": 512, "h": 512, "bit_depth": 16}),
        ("HighNoise",    generate_high_noise_image, {"w": 512, "h": 512, "bit_depth": 16}),
        ("Checker-8",    generate_checkerboard, {"w": 256, "h": 256, "bit_depth": 16, "block_size": 8}),
        ("Checker-1",    generate_checkerboard, {"w": 256, "h": 256, "bit_depth": 16, "block_size": 1}),
        ("DeadPixels",   generate_dead_pixel_image, {"w": 512, "h": 512, "bit_depth": 16}),
        # 12-bit variants
        ("LowContrast-12", generate_low_contrast_gradient, {"w": 256, "h": 256, "bit_depth": 12}),
        ("HighNoise-12", generate_high_noise_image, {"w": 256, "h": 256, "bit_depth": 12}),
    ]

    for img_name, gen_fn, kwargs in stress_images:
        bit_depth = kwargs["bit_depth"]
        print(f"\n>>> {img_name} ({kwargs['w']}×{kwargs['h']}, {bit_depth}-bit)...")
        img, maxval = gen_fn(**kwargs)
        print(f"    Range: [{img.min()}, {img.max()}], maxval={maxval}")
        # Self-test (each codec round-trips its own)
        stress_results.extend(self_test(img_name, img, maxval, bit_depth, bitrates))
        # Cross-decoder
        stress_results.extend(cross_decode_test(img_name, img, maxval, bit_depth, bitrates))

    print_section("Stress & Edge-Case Tests", stress_results)
    for r in stress_results:
        r["section"] = "stress"
    all_csv_rows.extend(stress_results)
    report_sections.append(("Stress & Edge-Case Tests", stress_results))

    # ----------------------------------------------------------
    # Section 3: Higher Resolution
    # ----------------------------------------------------------
    print("\n" + "#" * 60)
    print("  SECTION 3: HIGHER RESOLUTION IMAGES")
    print("#" * 60)

    hires_results = []

    print("\n>>> CT 2048×2048 16-bit...")
    ct_2k, ct_2k_max = generate_ct_image(2048, 2048, 16)
    print(f"    Range: [{ct_2k.min()}, {ct_2k.max()}]")
    hires_results.extend(self_test("CT-2k", ct_2k, ct_2k_max, 16, bitrates_fast))
    hires_results.extend(cross_decode_test("CT-2k", ct_2k, ct_2k_max, 16, bitrates_fast))

    print("\n>>> MRI 2048×2048 12-bit...")
    mri_2k, mri_2k_max = generate_mri_image(2048, 2048, 12)
    print(f"    Range: [{mri_2k.min()}, {mri_2k.max()}]")
    hires_results.extend(self_test("MRI-2k", mri_2k, mri_2k_max, 12, bitrates_fast))
    hires_results.extend(cross_decode_test("MRI-2k", mri_2k, mri_2k_max, 12, bitrates_fast))

    print("\n>>> CT 4096×4096 16-bit...")
    ct_4k, ct_4k_max = generate_ct_image(4096, 4096, 16)
    print(f"    Range: [{ct_4k.min()}, {ct_4k.max()}]")
    hires_results.extend(self_test("CT-4k", ct_4k, ct_4k_max, 16, bitrates_fast))
    hires_results.extend(cross_decode_test("CT-4k", ct_4k, ct_4k_max, 16, bitrates_fast))

    print_section("Higher Resolution Tests", hires_results)
    for r in hires_results:
        r["section"] = "hires"
    all_csv_rows.extend(hires_results)
    report_sections.append(("Higher Resolution Tests", hires_results))

    # ----------------------------------------------------------
    # Save reports
    # ----------------------------------------------------------
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    md_path = os.path.join(base_dir, "VALIDATION_REPORT.md")
    csv_path = os.path.join(base_dir, "validation_results.csv")

    save_markdown_report(report_sections, md_path)
    save_csv(all_csv_rows, csv_path)

    # ----------------------------------------------------------
    # Final summary
    # ----------------------------------------------------------
    print("\n" + "=" * 60)
    print("  FINAL SUMMARY")
    print("=" * 60)
    total = len(all_csv_rows)
    ok = sum(1 for r in all_csv_rows if r.get("status") == "OK")
    fail = total - ok
    print(f"  Total tests:  {total}")
    print(f"  Passed:       {ok}")
    print(f"  Failed:       {fail}")
    if fail > 0:
        print("\n  FAILURES:")
        for r in all_csv_rows:
            if r.get("status") != "OK":
                print(f"    {r.get('section','?')}/{r['test']}/{r['bitrate']}/{r['path']}: {r['status']}")
    print()


if __name__ == "__main__":
    main()
