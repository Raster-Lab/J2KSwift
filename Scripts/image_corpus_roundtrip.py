#!/usr/bin/env python3
"""
image_corpus_roundtrip.py — encode/decode validation harness for NON-DICOM
images (PNG/PPM/PGM/TIFF/BMP), e.g. the Cloudinary Image Dataset '22.

For every image it runs, via the shipped `j2k` CLI:

  1. LOSSLESS round-trip   : encode --lossless -> decode -> compare pixels to
                             the source (bit-exact => lossless codec is correct)
  2. LOSSY sweep (optional) : encode at one or more --quality levels -> decode ->
                             PSNR vs source + compression ratio

Two codec variants can be exercised per image: plain J2K and HTJ2K (--htj2k).

Outputs a per-file CSV and a Markdown report (lossless pass-rate, compression
ratios, lossy PSNR table, failures grouped by signature). Uses a
ThreadPoolExecutor (all work is in subprocess.run, which releases the GIL) to
avoid the ProcessPoolExecutor+subprocess+macOS-spawn deadlock.

Usage:
  python3 Scripts/image_corpus_roundtrip.py \
      --dataset Datasets/cid22/CID22_validation_set/original \
      --bin .build/release/j2k --workers 8 \
      --qualities 0.95,0.85,0.70 --htj2k \
      --out results/cid22_roundtrip
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict, field
from pathlib import Path

IMAGE_EXTS = {".png", ".ppm", ".pgm", ".pnm", ".tif", ".tiff", ".bmp"}

_BIN = ""
_ENC_TO = 300
_DEC_TO = 300
_QUALITIES: list[float] = []
_HTJ2K = False


def configure(binary, enc_to, dec_to, qualities, htj2k):
    global _BIN, _ENC_TO, _DEC_TO, _QUALITIES, _HTJ2K
    _BIN, _ENC_TO, _DEC_TO, _QUALITIES, _HTJ2K = binary, enc_to, dec_to, qualities, htj2k


@dataclass
class Result:
    path: str
    name: str
    width: int = 0
    height: int = 0
    components: int = 0
    src_bytes: int = 0
    # lossless round-trip
    ll_status: str = "OK"          # OK | ENCODE_FAIL | DECODE_FAIL | MISMATCH | VERIFY_ERR
    ll_j2k_bytes: int = 0
    ll_ratio: float = 0.0          # src raster bytes / j2k bytes
    ll_detail: str = ""
    # htj2k lossless round-trip (optional)
    ht_status: str = ""            # blank if not run
    ht_j2k_bytes: int = 0
    ht_ratio: float = 0.0
    ht_detail: str = ""
    # lossy sweep: JSON dict {quality: {"bytes":N,"psnr":X,"ratio":R,"status":S}}
    lossy: str = ""
    enc_seconds: float = 0.0
    dec_seconds: float = 0.0


def _run(cmd, timeout):
    t0 = time.perf_counter()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        dt = time.perf_counter() - t0
        combined = ((p.stderr or "") + (p.stdout or "")).strip()
        last = combined.splitlines()[-1] if combined else ""
        return p.returncode, last[:300], (p.stdout or ""), dt
    except subprocess.TimeoutExpired:
        return 124, f"TIMEOUT {timeout}s", "", time.perf_counter() - t0


def _read_pnm(path):
    """Parse binary PGM(P5)/PPM(P6) -> (numpy array HxW or HxWx3, maxval)."""
    import numpy as np
    with open(path, "rb") as fh:
        data = fh.read()
    magic = data[:2]
    if magic not in (b"P5", b"P6"):
        raise ValueError(f"not PGM/PPM: {magic!r}")
    ch = 1 if magic == b"P5" else 3
    idx = 2
    fields = []
    while len(fields) < 3:
        while idx < len(data) and data[idx:idx+1].isspace():
            idx += 1
        if data[idx:idx+1] == b"#":
            while idx < len(data) and data[idx:idx+1] != b"\n":
                idx += 1
            continue
        s = idx
        while idx < len(data) and not data[idx:idx+1].isspace():
            idx += 1
        fields.append(int(data[s:idx]))
    w, h, maxval = fields
    idx += 1
    dt = ">u2" if maxval > 255 else "u1"
    arr = np.frombuffer(data[idx:], dtype=dt)
    arr = arr.reshape((h, w, ch)) if ch > 1 else arr.reshape((h, w))
    return arr, maxval


def _load_source(path):
    """Load source image as a numpy array (HxW or HxWx3) via PIL."""
    import numpy as np
    from PIL import Image
    im = Image.open(path)
    if im.mode in ("L", "I;16", "I"):
        return np.array(im)
    return np.array(im.convert("RGB"))


def _decode_ext(components):
    return "ppm" if components >= 3 else "pgm"


def _psnr(a, b, maxval):
    import numpy as np
    a = a.astype(np.float64); b = b.astype(np.float64)
    mse = float(np.mean((a - b) ** 2))
    if mse == 0:
        return math.inf
    return 10.0 * math.log10((maxval ** 2) / mse)


def _encode_decode(src, td, tag, extra_args, verify_src):
    """Run one encode+decode; return dict(status, j2k_bytes, ratio, psnr, detail)."""
    import numpy as np
    j2k = os.path.join(td, f"{tag}.j2k")
    rc, err, out, _ = _run([_BIN, "encode", "-i", src, "-o", j2k, "--json"] + extra_args, _ENC_TO)
    if rc != 0 or not os.path.exists(j2k):
        return {"status": "ENCODE_FAIL", "detail": err}
    try:
        meta = json.loads(out) if out.strip().startswith("{") else {}
    except Exception:
        meta = {}
    comps = int(meta.get("components", verify_src.shape[2] if verify_src.ndim == 3 else 1))
    jbytes = os.path.getsize(j2k)
    dec = os.path.join(td, f"{tag}.{_decode_ext(comps)}")
    rc, err, _o, _ = _run([_BIN, "decode", "-i", j2k, "-o", dec, "--quiet"], _DEC_TO)
    produced = dec
    if not os.path.exists(produced):
        cand = [p for p in Path(td).iterdir() if p.name.startswith(tag + ".") and not p.name.endswith(".j2k")]
        produced = str(cand[0]) if cand else dec
    if rc != 0 or not os.path.exists(produced):
        return {"status": "DECODE_FAIL", "j2k_bytes": jbytes, "detail": err}
    try:
        dec_arr, maxval = _read_pnm(produced)
        raster_bytes = verify_src.size * (2 if maxval > 255 else 1)
        ratio = raster_bytes / jbytes if jbytes else 0
        # squeeze single-channel
        s = verify_src
        if dec_arr.shape != s.shape and dec_arr.ndim == 3 and dec_arr.shape[2] == 1:
            dec_arr = dec_arr[:, :, 0]
        if dec_arr.shape != s.shape:
            return {"status": "MISMATCH", "j2k_bytes": jbytes, "ratio": round(ratio, 3),
                    "detail": f"shape src{s.shape} dec{dec_arr.shape}"}
        psnr = _psnr(s, dec_arr, maxval)
        return {"status": "OK", "j2k_bytes": jbytes, "ratio": round(ratio, 3),
                "psnr": psnr, "decoded": dec_arr}
    except Exception as exc:
        return {"status": "VERIFY_ERR", "j2k_bytes": jbytes, "detail": f"{type(exc).__name__}: {exc}"}


def process_one(path_name):
    path, name = path_name
    r = Result(path=path, name=name)
    r.src_bytes = os.path.getsize(path)
    try:
        src = _load_source(path)
    except Exception as exc:
        r.ll_status = "VERIFY_ERR"; r.ll_detail = f"load: {type(exc).__name__}: {exc}"
        return asdict(r)
    r.height = src.shape[0]; r.width = src.shape[1]
    r.components = src.shape[2] if src.ndim == 3 else 1

    with tempfile.TemporaryDirectory(prefix="imgrt-") as td:
        t0 = time.perf_counter()
        # 1) Lossless J2K
        res = _encode_decode(path, td, "ll", ["--lossless"], src)
        r.ll_status = res["status"]; r.ll_j2k_bytes = res.get("j2k_bytes", 0)
        r.ll_ratio = res.get("ratio", 0.0); r.ll_detail = res.get("detail", "")
        if res["status"] == "OK":
            # lossless must be bit-exact (psnr inf). If not, mark MISMATCH.
            import numpy as np
            if not np.array_equal(src, res["decoded"]):
                ndiff = int(np.count_nonzero(src.astype(np.int64) - res["decoded"].astype(np.int64)))
                r.ll_status = "MISMATCH"; r.ll_detail = f"not bit-exact: {ndiff}px"
        r.enc_seconds = round(time.perf_counter() - t0, 3)

        # 2) HTJ2K lossless (optional)
        if _HTJ2K:
            res = _encode_decode(path, td, "ht", ["--lossless", "--htj2k"], src)
            r.ht_status = res["status"]; r.ht_j2k_bytes = res.get("j2k_bytes", 0)
            r.ht_ratio = res.get("ratio", 0.0); r.ht_detail = res.get("detail", "")
            if res["status"] == "OK":
                import numpy as np
                if not np.array_equal(src, res["decoded"]):
                    r.ht_status = "MISMATCH"

        # 3) Lossy sweep (optional)
        if _QUALITIES:
            sweep = {}
            for q in _QUALITIES:
                res = _encode_decode(path, td, f"q{int(q*100)}", ["--quality", str(q)], src)
                entry = {"status": res["status"], "bytes": res.get("j2k_bytes", 0),
                         "ratio": res.get("ratio", 0.0)}
                if res["status"] == "OK":
                    p = res.get("psnr", 0.0)
                    entry["psnr"] = round(p, 2) if p != math.inf else "inf"
                else:
                    entry["detail"] = res.get("detail", "")
                sweep[f"q{q}"] = entry
            r.lossy = json.dumps(sweep)
    return asdict(r)


def collect(dataset, limit):
    files = []
    for dp, dn, fn in os.walk(dataset, followlinks=False):
        for n in fn:
            if os.path.splitext(n)[1].lower() in IMAGE_EXTS:
                files.append((os.path.join(dp, n), n))
    files.sort()
    return files[:limit] if limit else files


def write_report(results, outdir, elapsed, args):
    import statistics
    outdir.mkdir(parents=True, exist_ok=True)
    fields = list(Result(path="", name="").__dict__.keys())
    with open(outdir / "results.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields); w.writeheader()
        for r in results:
            w.writerow(r)

    total = len(results)
    ll_ok = [r for r in results if r["ll_status"] == "OK"]
    ll_fail = [r for r in results if r["ll_status"] != "OK"]
    md = outdir / "REPORT.md"
    with open(md, "w") as f:
        f.write("# Image Corpus Encode/Decode Round-Trip Report\n\n")
        f.write(f"- **Dataset:** `{args.dataset}`\n")
        f.write(f"- **Binary:** `{args.bin}`\n")
        f.write(f"- **Images:** {total}\n")
        f.write(f"- **Wall time:** {elapsed/60:.1f} min ({args.workers} workers)\n\n")

        f.write("## Lossless round-trip (correctness)\n\n")
        f.write(f"- **Bit-exact OK: {len(ll_ok)}/{total} "
                f"({100*len(ll_ok)/total:.2f}%)**\n")
        if ll_ok:
            ratios = [r["ll_ratio"] for r in ll_ok if r["ll_ratio"]]
            f.write(f"- Lossless compression ratio (raster/J2K): "
                    f"min {min(ratios):.2f}× · median {statistics.median(ratios):.2f}× "
                    f"· max {max(ratios):.2f}×\n")
        from collections import Counter
        sc = Counter(r["ll_status"] for r in results)
        f.write("\n| Lossless status | Count |\n|---|---:|\n")
        for k, v in sc.most_common():
            f.write(f"| {k} | {v} |\n")

        # HTJ2K
        if any(r["ht_status"] for r in results):
            ht_ok = [r for r in results if r["ht_status"] == "OK"]
            f.write("\n## HTJ2K lossless round-trip\n\n")
            f.write(f"- **Bit-exact OK: {len(ht_ok)}/{total}**\n")
            if ht_ok:
                hr = [r["ht_ratio"] for r in ht_ok if r["ht_ratio"]]
                f.write(f"- HTJ2K compression ratio: median {statistics.median(hr):.2f}×\n")
            hsc = Counter(r["ht_status"] for r in results if r["ht_status"])
            f.write("\n| HTJ2K status | Count |\n|---|---:|\n")
            for k, v in hsc.most_common():
                f.write(f"| {k} | {v} |\n")

        # Lossy sweep
        lossy_rows = [r for r in results if r["lossy"]]
        if lossy_rows:
            f.write("\n## Lossy quality sweep (PSNR + compression)\n\n")
            f.write("Per quality level, averaged over images that encoded successfully.\n\n")
            f.write("| Quality | Images OK | Median PSNR (dB) | Median ratio | Median bpp |\n")
            f.write("|---|---:|---:|---:|---:|\n")
            qkeys = sorted({k for r in lossy_rows for k in json.loads(r["lossy"]).keys()},
                           key=lambda s: -float(s[1:]))
            for qk in qkeys:
                psnrs, ratios, bpps, okn = [], [], [], 0
                for r in lossy_rows:
                    e = json.loads(r["lossy"]).get(qk)
                    if e and e["status"] == "OK":
                        okn += 1
                        if isinstance(e.get("psnr"), (int, float)):
                            psnrs.append(e["psnr"])
                        ratios.append(e["ratio"])
                        px = r["width"] * r["height"]
                        if px:
                            bpps.append(e["bytes"] * 8 / px)
                med = lambda xs: statistics.median(xs) if xs else float("nan")
                f.write(f"| {qk} | {okn} | {med(psnrs):.2f} | {med(ratios):.2f}× | "
                        f"{med(bpps):.2f} |\n")

        f.write("\n## Failures / anomalies\n\n")
        if not ll_fail:
            f.write("None. Every image encoded, decoded, and round-tripped bit-exact losslessly.\n")
        else:
            from collections import defaultdict
            buckets = defaultdict(list)
            for r in ll_fail:
                buckets[(r["ll_status"], r["ll_detail"])].append(r)
            f.write(f"**{len(ll_fail)} image(s)** across **{len(buckets)}** signature(s).\n\n")
            for (st, det), items in sorted(buckets.items(), key=lambda kv: -len(kv[1])):
                f.write(f"### {st} — {len(items)} image(s)\n\n- Detail: `{det or '(none)'}`\n- Examples:\n")
                for r in items[:12]:
                    f.write(f"  - `{r['name']}` ({r['width']}x{r['height']}, {r['components']}c)\n")
                f.write("\n")
    return outdir / "results.csv", md


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--bin", default=".build/release/j2k")
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 4)))
    ap.add_argument("--out", default="results/image_corpus")
    ap.add_argument("--qualities", default="", help="comma list e.g. 0.95,0.85,0.70 (lossy sweep)")
    ap.add_argument("--htj2k", action="store_true", help="also test HTJ2K lossless")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--encode-timeout", type=int, default=300)
    ap.add_argument("--decode-timeout", type=int, default=300)
    args = ap.parse_args()

    if not Path(args.bin).exists():
        sys.exit(f"binary not found: {args.bin}")
    files = collect(args.dataset, args.limit or None)
    if not files:
        sys.exit(f"no images found under {args.dataset}")
    qualities = [float(q) for q in args.qualities.split(",") if q.strip()]
    configure(args.bin, args.encode_timeout, args.decode_timeout, qualities, args.htj2k)
    print(f"[*] {len(files)} images | workers={args.workers} | htj2k={args.htj2k} "
          f"| lossy={qualities or 'off'}", flush=True)

    t0 = time.perf_counter()
    results = []
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(process_one, fn) for fn in files]
        for fut in as_completed(futs):
            results.append(fut.result())
            done += 1
            if done % 25 == 0 or done == len(files):
                el = time.perf_counter() - t0
                print(f"  {done}/{len(files)} ({done/el:.1f}/s)", flush=True)
    elapsed = time.perf_counter() - t0
    csvp, md = write_report(results, Path(args.out), elapsed, args)
    bad = sum(1 for r in results if r["ll_status"] != "OK")
    print(f"\n[*] done in {elapsed/60:.1f} min — {bad} lossless problem image(s)")
    print(f"[*] CSV: {csvp}\n[*] REPORT: {md}")


if __name__ == "__main__":
    main()
