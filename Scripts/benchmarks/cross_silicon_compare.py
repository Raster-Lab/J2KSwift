#!/usr/bin/env python3
"""
cross_silicon_compare.py — cross-Apple-silicon J2KSwift wall comparison.

Built for the v10.17-research cross-silicon arc. Once the J2KBenchApp
Ad Hoc build (distributed via Diawi) is run on M3 / M4 / A-series
devices and the resulting JSONs land in `Documentation/Benchmarks/data/`,
this produces a per-fixture decode/encode-wall table across every host,
anchored on an M2 baseline — the data that answers whether the CPU/GPU
crossover shifts on newer Apple silicon.

Each input JSON is a warm in-process bench file in the canonical
`compare_hosts.py` schema (top-level `host` / `encode` / `decode`, with
a `J2KSwift+inproc` codec entry per fixture) — the shape J2KBenchApp's
"Share Selected" export and `cross_codec_warm_bench.py --in-proc` both
emit.

Usage:
    python3 Scripts/benchmarks/cross_silicon_compare.py \\
        [HOST.json ...] [--baseline SUBSTR] [--output REPORT.md]

With no JSON arguments it globs `Documentation/Benchmarks/data/` for
`*warm-inproc*.json`. `--baseline` (default `Mac142`, the M2 host) is a
filename substring selecting which host is the speedup denominator.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_hosts import load_run, host_label  # noqa: E402


def j2kswift_codec(run: dict) -> str | None:
    """The J2KSwift codec key used in this run's encode results."""
    for entry in run.get("encode", {}).values():
        for key in entry.get("results", {}):
            if key.startswith("J2KSwift"):
                return key
    return None


def medians(run: dict, direction: str, codec: str) -> dict[str, float]:
    """{fixture: median ms} for `codec` in `direction`."""
    out: dict[str, float] = {}
    for fixture, entry in run.get(direction, {}).items():
        result = entry.get("results", {}).get(codec)
        if result and result.get("median") is not None:
            out[fixture] = result["median"]
    return out


def short(label: str) -> str:
    """`Apple M2 (Mac14,2)` -> `Apple M2`."""
    return label.split("(")[0].strip()


def direction_table(direction: str, runs: list[tuple[str, dict]]) -> list[str]:
    per_host = []
    for _, run in runs:
        codec = j2kswift_codec(run)
        per_host.append(medians(run, direction, codec) if codec else {})

    common = set(per_host[0])
    for m in per_host[1:]:
        common &= set(m)
    if not common:
        return [f"## {direction.upper()}", "",
                "_(no fixtures shared across all hosts)_", ""]

    # Preserve the baseline run's fixture order.
    ordered = [f for f in runs[0][1].get(direction, {}) if f in common]

    hosts = [short(host_label(r)) for _, r in runs]
    header = ["Fixture"] + [f"{h} ms" for h in hosts]
    header += [f"{h}/base" for h in hosts[1:]]
    lines = [f"## {direction.upper()} — J2KSwift wall (ms), median of N",
             "",
             "| " + " | ".join(header) + " |",
             "|" + "|".join(["---"] * len(header)) + "|"]
    for fixture in ordered:
        base = per_host[0][fixture]
        row = [fixture] + [f"{m[fixture]:.2f}" for m in per_host]
        for m in per_host[1:]:
            row.append(f"{base / m[fixture]:.2f}×" if m[fixture] else "—")
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json", nargs="*", help="host JSON files")
    parser.add_argument("--baseline", default="Mac142",
                        help="filename substring of the baseline (M2) host")
    parser.add_argument("--output", default=None, help="write Markdown here")
    args = parser.parse_args()

    paths = args.json
    if not paths:
        data_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..", "Documentation", "Benchmarks", "data")
        paths = sorted(glob.glob(os.path.join(data_dir, "*warm-inproc*.json")))
    if not paths:
        sys.exit("no JSON args and none found under Documentation/Benchmarks/data/")

    runs: list[tuple[str, dict]] = []
    for path in paths:
        try:
            runs.append((path, load_run(path)))
        except Exception as exc:  # noqa: BLE001
            print(f"skip {path}: {exc}", file=sys.stderr)
    if not runs:
        sys.exit("no usable host JSONs")

    # Baseline host first.
    runs.sort(key=lambda pr: (0 if args.baseline in os.path.basename(pr[0]) else 1,
                              pr[0]))

    lines = ["# Cross-silicon J2KSwift wall comparison", "",
             f"_{len(runs)} hosts; baseline (speedup denominator) = first row._",
             "", "## Hosts", "",
             "| # | Host | J2KSwift version | JSON |",
             "|---|---|---|---|"]
    for i, (path, run) in enumerate(runs):
        version = run.get("j2k_version", "?")
        lines.append(f"| {i} | {host_label(run)} | {version} "
                     f"| `{os.path.basename(path)}` |")
    lines.append("")

    for direction in ("decode", "encode"):
        lines += direction_table(direction, runs)

    report = "\n".join(lines)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(report + "\n")
        print(f"wrote {args.output}")
    else:
        print(report)


if __name__ == "__main__":
    main()
