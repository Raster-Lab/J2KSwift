#!/usr/bin/env python3
"""
Medical Imaging Benchmark: J2KSwift vs OpenJPEG
Tests grayscale 12-bit and 16-bit images across CT, MRI, Ultrasound modalities.
Metrics: PSNR, SSIM, MAE at 0.25, 0.5, 0.75 bpp + lossless.
"""

import numpy as np
import struct
import subprocess
import os
import sys
import time

TMPDIR = "/private/tmp/medical_bench"
J2K_CLI = None  # Will be found
OPJ_COMPRESS = "/opt/homebrew/bin/opj_compress"
OPJ_DECOMPRESS = "/opt/homebrew/bin/opj_decompress"

# ============================================================
# PGM I/O (P5 binary, 16-bit big-endian)
# ============================================================

def write_pgm(path, img, maxval):
    """Write a 16-bit big-endian PGM (P5) file."""
    h, w = img.shape
    header = f"P5\n{w} {h}\n{maxval}\n".encode('ascii')
    with open(path, 'wb') as f:
        f.write(header)
        if maxval <= 255:
            f.write(img.astype(np.uint8).tobytes())
        else:
            # PGM 16-bit is big-endian
            f.write(img.astype('>u2').tobytes())


def read_pgm(path):
    """Read a PGM (P5) file, return (image_array, maxval)."""
    with open(path, 'rb') as f:
        # Read magic
        magic = f.readline().strip()
        assert magic == b'P5', f"Not a P5 PGM: {magic}"
        # Skip comments
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


def uniform_filter(img, size):
    """Simple uniform (box) filter using cumsum for speed."""
    # Pad
    r = size // 2
    padded = np.pad(img, r, mode='reflect')
    # Cumsum along rows
    cs = np.cumsum(padded, axis=1)
    cs = cs[:, size:] - np.concatenate([np.zeros((cs.shape[0], 1)), cs[:, :-size]], axis=1)
    # Actually let me just use a simpler convolution approach
    from numpy.lib.stride_tricks import sliding_window_view
    # This won't work well for large images. Use cumsum properly.
    pass


def _box_filter_2d(img, k):
    """2D box filter using cumulative sums. Returns filtered image (same shape)."""
    r = k // 2
    padded = np.pad(img, r, mode='reflect')
    # Prepend a row and column of zeros so S is 1-indexed
    ph, pw = padded.shape
    S = np.zeros((ph + 1, pw + 1), dtype=np.float64)
    S[1:, 1:] = np.cumsum(np.cumsum(padded, axis=0), axis=1)
    h, w = img.shape
    # For output pixel (i, j), window in padded is [i, i+k) × [j, j+k)
    # sum = S[i+k, j+k] - S[i, j+k] - S[i+k, j] + S[i, j]
    rows_b = np.arange(k, h + k)   # i + k
    rows_t = np.arange(0, h)       # i
    cols_r = np.arange(k, w + k)   # j + k
    cols_l = np.arange(0, w)       # j

    result = (S[np.ix_(rows_b, cols_r)]
              - S[np.ix_(rows_t, cols_r)]
              - S[np.ix_(rows_b, cols_l)]
              + S[np.ix_(rows_t, cols_l)])
    return result / (k * k)


def compute_ssim(orig, dec, maxval, k=11):
    """Compute SSIM (Structural Similarity Index) using box filter."""
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
# Synthetic Medical Image Generation
# ============================================================

def generate_ct_image(w=512, h=512, bit_depth=16):
    """
    Synthetic CT-like image (16-bit unsigned).
    Simulates HU range with body/organ structures + noise.
    """
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(42)
    img = np.zeros((h, w), dtype=np.float64)

    # Background (air) ~ low values
    img[:] = 100

    # Body ellipse
    cy, cx = h // 2, w // 2
    ry, rx = int(h * 0.4), int(w * 0.35)
    Y, X = np.ogrid[:h, :w]
    body_mask = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1.0
    img[body_mask] = 30000  # soft tissue

    # Spine (dense bone)
    spine_mask = ((X - cx) / 25) ** 2 + ((Y - cy) / 40) ** 2 <= 1.0
    img[spine_mask] = 55000  # bone

    # Lungs (dark)
    lung_l = ((X - (cx - rx // 2)) / (rx // 3)) ** 2 + ((Y - (cy - ry // 6)) / (ry // 2)) ** 2 <= 1.0
    lung_r = ((X - (cx + rx // 2)) / (rx // 3)) ** 2 + ((Y - (cy - ry // 6)) / (ry // 2)) ** 2 <= 1.0
    img[lung_l] = 5000
    img[lung_r] = 5000

    # Heart (medium density)
    heart = ((X - (cx + 10)) / 50) ** 2 + ((Y - (cy + 20)) / 45) ** 2 <= 1.0
    img[heart] = 35000

    # Add noise
    noise = rng.normal(0, 500, (h, w))
    img += noise

    # Smooth slightly
    # Simple 3x3 averaging
    kernel = np.ones((3, 3)) / 9.0
    from numpy.lib.stride_tricks import sliding_window_view
    padded = np.pad(img, 1, mode='reflect')
    windows = sliding_window_view(padded, (3, 3))
    img = np.mean(windows, axis=(2, 3))

    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_mri_image(w=256, h=256, bit_depth=12):
    """
    Synthetic MRI-like brain image (12-bit unsigned).
    Simulates T1-weighted contrast.
    """
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(123)
    img = np.zeros((h, w), dtype=np.float64)

    # Background
    img[:] = 50

    cy, cx = h // 2, w // 2
    Y, X = np.ogrid[:h, :w]

    # Skull (bright ring)
    skull_outer = ((X - cx) / (w * 0.42)) ** 2 + ((Y - cy) / (h * 0.45)) ** 2 <= 1.0
    skull_inner = ((X - cx) / (w * 0.38)) ** 2 + ((Y - cy) / (h * 0.41)) ** 2 <= 1.0
    img[skull_outer & ~skull_inner] = 3500  # bone/fat bright on T1

    # Brain parenchyma (gray matter)
    brain_mask = skull_inner
    img[brain_mask] = 2200

    # White matter (brighter)
    wm_mask = ((X - cx) / (w * 0.28)) ** 2 + ((Y - cy) / (h * 0.30)) ** 2 <= 1.0
    img[wm_mask] = 3000

    # Ventricles (dark on T1)
    vent_l = ((X - (cx - 15)) / 12) ** 2 + ((Y - (cy - 10)) / 30) ** 2 <= 1.0
    vent_r = ((X - (cx + 15)) / 12) ** 2 + ((Y - (cy - 10)) / 30) ** 2 <= 1.0
    img[vent_l] = 500
    img[vent_r] = 500

    # Caudate nuclei (medium)
    cn_l = ((X - (cx - 25)) / 10) ** 2 + ((Y - (cy - 5)) / 15) ** 2 <= 1.0
    cn_r = ((X - (cx + 25)) / 10) ** 2 + ((Y - (cy - 5)) / 15) ** 2 <= 1.0
    img[cn_l] = 2500
    img[cn_r] = 2500

    # Noise (Rician-like approximation)
    noise = rng.normal(0, 80, (h, w))
    img += noise

    # Smooth
    padded = np.pad(img, 1, mode='reflect')
    from numpy.lib.stride_tricks import sliding_window_view
    windows = sliding_window_view(padded, (3, 3))
    img = np.mean(windows, axis=(2, 3))

    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


def generate_ultrasound_image(w=640, h=480, bit_depth=12):
    """
    Synthetic ultrasound-like image (12-bit unsigned).
    Simulates speckle pattern with anatomical structures.
    """
    maxval = (1 << bit_depth) - 1
    rng = np.random.default_rng(789)

    # Base: speckle noise (multiplicative)
    base = rng.rayleigh(scale=800, size=(h, w))

    Y, X = np.ogrid[:h, :w]
    cy, cx = h // 2, w // 2

    # Sector shape (fan beam)
    angle = np.arctan2(X - cx, Y - 20)
    dist = np.sqrt((X - cx) ** 2 + (Y - 20) ** 2)
    sector = (np.abs(angle) < 0.6) & (dist > 50) & (dist < h * 0.9)

    img = np.zeros((h, w), dtype=np.float64)
    img[sector] = base[sector]

    # Add some structures
    # Cyst (dark, anechoic)
    cyst = ((X - (cx + 40)) / 30) ** 2 + ((Y - (cy + 50)) / 25) ** 2 <= 1.0
    img[cyst & sector] = rng.rayleigh(scale=100, size=(h, w))[cyst & sector]

    # Dense tissue (bright)
    tissue = ((X - (cx - 30)) / 50) ** 2 + ((Y - (cy + 20)) / 35) ** 2 <= 1.0
    img[tissue & sector] = rng.rayleigh(scale=1500, size=(h, w))[tissue & sector]

    # Depth-dependent attenuation
    depth_atten = np.exp(-0.002 * np.maximum(0, Y - 20))
    img *= depth_atten

    img = np.clip(img, 0, maxval).astype(np.uint16)
    return img, maxval


# ============================================================
# Encode / Decode helpers
# ============================================================

def j2k_encode(input_pgm, output_j2k, bpp=None, lossless=False):
    """Encode using J2KSwift CLI."""
    cmd = [J2K_CLI, "encode", "-i", input_pgm, "-o", output_j2k, "--quiet"]
    if lossless:
        cmd.extend(["--lossless"])
    elif bpp is not None:
        cmd.extend(["--bitrate", str(bpp)])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(f"  J2K encode error: {result.stderr.strip()}")
        return False
    return True


def j2k_decode(input_j2k, output_pgm):
    """Decode using J2KSwift CLI."""
    cmd = [J2K_CLI, "decode", "-i", input_j2k, "-o", output_pgm, "--quiet"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(f"  J2K decode error: {result.stderr.strip()}")
        return False
    return True


def opj_encode(input_pgm, output_j2k, bpp=None, lossless=False):
    """Encode using OpenJPEG."""
    cmd = [OPJ_COMPRESS, "-i", input_pgm, "-o", output_j2k]
    if lossless:
        pass  # Default is lossless for OPJ without -r
    elif bpp is not None:
        # OPJ uses compression ratio: ratio = bitDepth / bpp
        # Or we use -r for rate (compression ratio)
        # Actually -r is compression ratio = uncompressed/compressed
        # For grayscale 16-bit at bpp target:
        #   ratio = bitDepth / bpp
        # But OPJ also accepts -q for quality... 
        # Safest: compute target bytes and use file size... but OPJ takes -r ratio
        # ratio = original_bpp / target_bpp for grayscale
        # For grayscale bitDepth-bit image, uncompressed bpp = bitDepth
        # So ratio = bitDepth / target_bpp
        ratio = 16.0 / bpp  # Using 16 since PGM stores as 16-bit even for 12-bit
        cmd.extend(["-r", str(ratio)])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(f"  OPJ encode error: {result.stderr.strip()}")
        return False
    return True


def opj_decode(input_j2k, output_pgm):
    """Decode using OpenJPEG."""
    cmd = [OPJ_DECOMPRESS, "-i", input_j2k, "-o", output_pgm]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(f"  OPJ decode error: {result.stderr.strip()}")
        return False
    return True


# ============================================================
# Benchmark runner
# ============================================================

def benchmark_image(name, orig_img, maxval, bit_depth, bitrates):
    """Run full benchmark for one image."""
    input_pgm = os.path.join(TMPDIR, f"{name}.pgm")
    write_pgm(input_pgm, orig_img, maxval)

    orig_f = orig_img.astype(np.float64)
    results = []

    for bpp_label, bpp, is_lossless in bitrates:
        row = {"modality": name, "bit_depth": bit_depth, "bitrate": bpp_label}

        for codec_name, encode_fn, decode_fn, suffix in [
            ("J2K", j2k_encode, j2k_decode, "j2k"),
            ("OPJ", opj_encode, opj_decode, "opj"),
        ]:
            j2k_file = os.path.join(TMPDIR, f"{name}_{bpp_label}_{codec_name}.j2k")
            dec_file = os.path.join(TMPDIR, f"{name}_{bpp_label}_{codec_name}_dec.pgm")

            # Encode
            t0 = time.time()
            ok = encode_fn(input_pgm, j2k_file, bpp=bpp, lossless=is_lossless)
            enc_time = time.time() - t0

            if not ok or not os.path.exists(j2k_file):
                row[f"{codec_name}_psnr"] = "FAIL"
                row[f"{codec_name}_ssim"] = "FAIL"
                row[f"{codec_name}_mae"] = "FAIL"
                row[f"{codec_name}_size"] = "FAIL"
                continue

            file_size = os.path.getsize(j2k_file)
            actual_bpp = (file_size * 8) / (orig_img.shape[0] * orig_img.shape[1])

            # Decode
            t0 = time.time()
            ok = decode_fn(j2k_file, dec_file)
            dec_time = time.time() - t0

            if not ok or not os.path.exists(dec_file):
                row[f"{codec_name}_psnr"] = "DEC_FAIL"
                row[f"{codec_name}_ssim"] = "DEC_FAIL"
                row[f"{codec_name}_mae"] = "DEC_FAIL"
                row[f"{codec_name}_size"] = str(file_size)
                continue

            # Read decoded
            dec_f, dec_maxval = read_pgm(dec_file)

            # Ensure same shape
            if dec_f.shape != orig_f.shape:
                row[f"{codec_name}_psnr"] = f"SHAPE({dec_f.shape})"
                row[f"{codec_name}_ssim"] = "SHAPE"
                row[f"{codec_name}_mae"] = "SHAPE"
                row[f"{codec_name}_size"] = str(file_size)
                continue

            # Compute metrics
            psnr = compute_psnr(orig_f, dec_f, maxval)
            mae = compute_mae(orig_f, dec_f)
            ssim = compute_ssim(orig_f, dec_f, maxval)

            row[f"{codec_name}_psnr"] = psnr
            row[f"{codec_name}_ssim"] = ssim
            row[f"{codec_name}_mae"] = mae
            row[f"{codec_name}_size"] = file_size
            row[f"{codec_name}_bpp"] = actual_bpp
            row[f"{codec_name}_enc_ms"] = enc_time * 1000
            row[f"{codec_name}_dec_ms"] = dec_time * 1000

        results.append(row)

    return results


def format_val(v, fmt=".2f"):
    if isinstance(v, str):
        return v
    if isinstance(v, float) and v == float('inf'):
        return "∞"
    return f"{v:{fmt}}"


def print_results(all_results):
    print("\n" + "=" * 120)
    print("MEDICAL IMAGING BENCHMARK: J2KSwift vs OpenJPEG")
    print("=" * 120)

    header = (
        f"{'Modality':<15} {'Bits':>4} {'Rate':>8} │"
        f" {'J2K PSNR':>10} {'J2K SSIM':>9} {'J2K MAE':>9} {'J2K bpp':>8} │"
        f" {'OPJ PSNR':>10} {'OPJ SSIM':>9} {'OPJ MAE':>9} {'OPJ bpp':>8} │"
        f" {'ΔPSNR':>7}"
    )
    print(header)
    print("─" * 120)

    for row in all_results:
        j_psnr = row.get("J2K_psnr", "N/A")
        j_ssim = row.get("J2K_ssim", "N/A")
        j_mae = row.get("J2K_mae", "N/A")
        j_bpp = row.get("J2K_bpp", "N/A")
        o_psnr = row.get("OPJ_psnr", "N/A")
        o_ssim = row.get("OPJ_ssim", "N/A")
        o_mae = row.get("OPJ_mae", "N/A")
        o_bpp = row.get("OPJ_bpp", "N/A")

        # Compute gap
        if isinstance(j_psnr, (int, float)) and isinstance(o_psnr, (int, float)):
            if j_psnr == float('inf') and o_psnr == float('inf'):
                gap = "0.00"
            elif j_psnr == float('inf'):
                gap = "+∞"
            elif o_psnr == float('inf'):
                gap = "-∞"
            else:
                gap = f"{j_psnr - o_psnr:+.2f}"
        else:
            gap = "N/A"

        line = (
            f"{row['modality']:<15} {row['bit_depth']:>4} {row['bitrate']:>8} │"
            f" {format_val(j_psnr):>10} {format_val(j_ssim, '.4f'):>9} {format_val(j_mae):>9} {format_val(j_bpp, '.3f'):>8} │"
            f" {format_val(o_psnr):>10} {format_val(o_ssim, '.4f'):>9} {format_val(o_mae):>9} {format_val(o_bpp, '.3f'):>8} │"
            f" {gap:>7}"
        )
        print(line)

    print("─" * 120)
    print()


def save_markdown_report(all_results, filepath):
    """Save results as a markdown table."""
    lines = []
    lines.append("# Medical Imaging Benchmark: J2KSwift vs OpenJPEG")
    lines.append("")
    lines.append(f"**Date:** {time.strftime('%Y-%m-%d %H:%M')}")
    lines.append("")
    lines.append("## Test Images")
    lines.append("")
    lines.append("| Modality | Dimensions | Bit Depth | Description |")
    lines.append("|----------|-----------|-----------|-------------|")
    lines.append("| CT | 512×512 | 16-bit | Synthetic chest CT (HU range simulation) |")
    lines.append("| MRI | 256×256 | 12-bit | Synthetic T1-weighted brain MRI |")
    lines.append("| Ultrasound | 640×480 | 12-bit | Synthetic sector ultrasound with speckle |")
    lines.append("")
    lines.append("## Results")
    lines.append("")
    lines.append("| Modality | Bits | Bitrate | J2K PSNR | J2K SSIM | J2K MAE | OPJ PSNR | OPJ SSIM | OPJ MAE | ΔPSNR |")
    lines.append("|----------|------|---------|----------|----------|---------|----------|----------|---------|-------|")

    for row in all_results:
        j_psnr = row.get("J2K_psnr", "N/A")
        j_ssim = row.get("J2K_ssim", "N/A")
        j_mae = row.get("J2K_mae", "N/A")
        o_psnr = row.get("OPJ_psnr", "N/A")
        o_ssim = row.get("OPJ_ssim", "N/A")
        o_mae = row.get("OPJ_mae", "N/A")

        if isinstance(j_psnr, (int, float)) and isinstance(o_psnr, (int, float)):
            if j_psnr == float('inf') and o_psnr == float('inf'):
                gap = "0.00"
            elif j_psnr == float('inf'):
                gap = "+∞"
            elif o_psnr == float('inf'):
                gap = "-∞"
            else:
                gap = f"{j_psnr - o_psnr:+.2f}"
        else:
            gap = "N/A"

        lines.append(
            f"| {row['modality']} | {row['bit_depth']} | {row['bitrate']} "
            f"| {format_val(j_psnr)} | {format_val(j_ssim, '.4f')} | {format_val(j_mae)} "
            f"| {format_val(o_psnr)} | {format_val(o_ssim, '.4f')} | {format_val(o_mae)} "
            f"| {gap} |"
        )

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- PSNR: Peak Signal-to-Noise Ratio (dB) — higher is better")
    lines.append("- SSIM: Structural Similarity Index — closer to 1.0 is better")
    lines.append("- MAE: Mean Absolute Error — lower is better")
    lines.append("- ΔPSNR: J2K PSNR minus OPJ PSNR (positive = J2K better)")
    lines.append("- Lossless: exact reconstruction (PSNR = ∞, MAE = 0)")
    lines.append("")

    with open(filepath, 'w') as f:
        f.write('\n'.join(lines))
    print(f"Report saved to: {filepath}")


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
        # Try debug
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

    # Check OPJ
    if not os.path.exists(OPJ_COMPRESS):
        print(f"WARNING: OpenJPEG not found at {OPJ_COMPRESS}")

    os.makedirs(TMPDIR, exist_ok=True)

    bitrates = [
        ("0.25bpp", 0.25, False),
        ("0.50bpp", 0.50, False),
        ("0.75bpp", 0.75, False),
        ("lossless", None, True),
    ]

    all_results = []

    # CT 16-bit
    print("\n>>> Generating CT image (512×512, 16-bit)...")
    ct_img, ct_maxval = generate_ct_image(512, 512, 16)
    print(f"    Range: [{ct_img.min()}, {ct_img.max()}], maxval={ct_maxval}")
    print(">>> Benchmarking CT...")
    all_results.extend(benchmark_image("CT", ct_img, ct_maxval, 16, bitrates))

    # MRI 12-bit
    print("\n>>> Generating MRI image (256×256, 12-bit)...")
    mri_img, mri_maxval = generate_mri_image(256, 256, 12)
    print(f"    Range: [{mri_img.min()}, {mri_img.max()}], maxval={mri_maxval}")
    print(">>> Benchmarking MRI...")
    all_results.extend(benchmark_image("MRI", mri_img, mri_maxval, 12, bitrates))

    # Ultrasound 12-bit
    print("\n>>> Generating Ultrasound image (640×480, 12-bit)...")
    us_img, us_maxval = generate_ultrasound_image(640, 480, 12)
    print(f"    Range: [{us_img.min()}, {us_img.max()}], maxval={us_maxval}")
    print(">>> Benchmarking Ultrasound...")
    all_results.extend(benchmark_image("Ultrasound", us_img, us_maxval, 12, bitrates))

    # Print results
    print_results(all_results)

    # Save report
    report_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                "MEDICAL_BENCHMARK.md")
    save_markdown_report(all_results, report_path)


if __name__ == "__main__":
    main()
