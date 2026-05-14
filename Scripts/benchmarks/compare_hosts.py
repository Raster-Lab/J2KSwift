#!/usr/bin/env python3
"""
compare_hosts.py — generate a cross-host markdown comparison report
from two or more canonical warm cross-codec benchmark JSONs.

Produces a per-fixture × per-codec speedup matrix plus aggregate rankings,
suitable for cross-silicon comparison (e.g. M2 vs M4) of J2KSwift and
external codecs (Kakadu, OpenJPH, Grok).

Usage:
    python3 Scripts/benchmarks/compare_hosts.py \\
        path/to/m2.json path/to/m4.json \\
        --output Documentation/Benchmarks/CROSS_HOST_M2_M4.md \\
        [--baseline 0]   # which input is the baseline (default 0 = first)
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
from datetime import datetime


def load_run(path: str) -> dict:
    with open(path) as f:
        d = json.load(f)
    if "host" not in d or "encode" not in d:
        raise ValueError(f"{path} does not look like a canonical bench JSON")
    return d


def host_label(run: dict) -> str:
    h = run["host"]
    return f"{h['brand']} ({h['model']})"


def codec_keys(run: dict) -> list[str]:
    """Discover codec column names from the encode results."""
    keys: list[str] = []
    for entry in run["encode"].values():
        for k in entry["results"].keys():
            if k not in keys:
                keys.append(k)
    return keys


def median(entry: dict | None) -> float | None:
    if not entry:
        return None
    return entry.get("median")


def fmt_ms(v: float | None) -> str:
    return f"{v:.2f}" if v is not None else "—"


def fmt_speedup(baseline: float | None, other: float | None) -> str:
    if baseline is None or other is None or other == 0:
        return "—"
    s = baseline / other
    return f"{s:.2f}×"


def build_per_fixture_table(direction: str,
                            runs: list[dict],
                            host_labels: list[str],
                            baseline_idx: int) -> str:
    """Per-fixture × per-codec ms + speedup vs baseline host.

    Schema: one row per fixture. Columns:
      Fixture | Source | <Codec1> on <H1> | <Codec1> on <H2> | speedup |
                       | <Codec2> on <H1> | <Codec2> on <H2> | speedup | ...
    """
    # Find common codec set across runs
    all_codecs = set()
    for r in runs:
        all_codecs.update(codec_keys(r))
    # Stable order: J2KSwift first (whichever variant), then alphabetical
    codecs = sorted(all_codecs, key=lambda k: (0 if k.startswith("J2KSwift") else 1, k))

    # Find common fixture set across runs (intersection)
    fixture_sets = [set(r[direction].keys()) for r in runs]
    common = set.intersection(*fixture_sets)
    if not common:
        return f"_(no fixtures shared across hosts for {direction})_\n"

    # Order fixtures by appearance in the baseline
    baseline = runs[baseline_idx]
    ordered = [f for f in baseline[direction].keys() if f in common]

    # Build header
    header = ["Fixture", "Source"]
    for c in codecs:
        for h in host_labels:
            header.append(f"{c} {h.split('(')[0].strip()}")
        header.append(f"{c} {host_labels[1 - baseline_idx].split('(')[0].strip()}/"
                      f"{host_labels[baseline_idx].split('(')[0].strip()}")
    sep = ["---"] * len(header)
    lines = ["| " + " | ".join(header) + " |",
             "|" + "|".join(sep) + "|"]

    for fname in ordered:
        bl_entry = baseline[direction][fname]
        row = [bl_entry["label"], bl_entry["source"]]
        for c in codecs:
            cell_medians = []
            for r in runs:
                row_data = r[direction].get(fname, {}).get("results", {})
                cell_medians.append(median(row_data.get(c)))
            for ms in cell_medians:
                row.append(fmt_ms(ms))
            # Speedup = baseline_host_ms / other_host_ms (other faster -> >1×)
            other_idx = 1 - baseline_idx if len(runs) == 2 else None
            if other_idx is not None:
                row.append(fmt_speedup(cell_medians[baseline_idx],
                                       cell_medians[other_idx]))
            else:
                row.append("—")
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines) + "\n"


def aggregate_speedup(direction: str,
                      runs: list[dict],
                      baseline_idx: int) -> dict[str, dict]:
    """Per-codec aggregate: median speedup, geomean speedup, win count delta.
    Returns {codec: {median_speedup, n_fixtures, baseline_wins, other_wins}}.
    """
    out: dict[str, dict] = {}
    if len(runs) != 2:
        return out
    other_idx = 1 - baseline_idx
    baseline = runs[baseline_idx]
    other = runs[other_idx]

    common = set(baseline[direction]) & set(other[direction])
    all_codecs = set()
    for r in runs:
        all_codecs.update(codec_keys(r))

    for c in all_codecs:
        speedups: list[float] = []
        for fname in common:
            bl_ms = median(baseline[direction][fname]["results"].get(c))
            ot_ms = median(other[direction][fname]["results"].get(c))
            if bl_ms and ot_ms:
                speedups.append(bl_ms / ot_ms)
        if not speedups:
            continue
        speedups.sort()
        out[c] = {
            "median_speedup": speedups[len(speedups) // 2],
            "min_speedup": speedups[0],
            "max_speedup": speedups[-1],
            "n_fixtures": len(speedups),
        }
    return out


def build_aggregate_table(agg: dict, direction: str,
                          host_labels: list[str], baseline_idx: int) -> str:
    if not agg:
        return f"_(comparison requires exactly 2 hosts for {direction} aggregate)_\n"
    other_label = host_labels[1 - baseline_idx].split("(")[0].strip()
    base_label = host_labels[baseline_idx].split("(")[0].strip()
    header = ["Codec", "n", f"Median {other_label}/{base_label}",
              f"Min", f"Max"]
    lines = ["| " + " | ".join(header) + " |",
             "|" + "|".join(["---"] * len(header)) + "|"]
    sorted_keys = sorted(agg.keys(),
                         key=lambda k: (0 if k.startswith("J2KSwift") else 1, k))
    for c in sorted_keys:
        d = agg[c]
        lines.append(f"| {c} | {d['n_fixtures']} | "
                     f"**{d['median_speedup']:.2f}×** | "
                     f"{d['min_speedup']:.2f}× | "
                     f"{d['max_speedup']:.2f}× |")
    return "\n".join(lines) + "\n"


def build_winner_delta(direction: str, runs: list[dict],
                       host_labels: list[str]) -> str:
    """Per-host: count fixtures where each codec is the fastest.
    Identifies how the win pattern shifts across silicon."""
    lines = []
    for r, hl in zip(runs, host_labels):
        all_codecs = set()
        for entry in r[direction].values():
            all_codecs.update(entry["results"].keys())
        wins = {c: 0 for c in all_codecs}
        total = 0
        for entry in r[direction].values():
            results = entry["results"]
            valid = {c: m["median"] for c, m in results.items()
                     if m and "median" in m}
            if not valid:
                continue
            total += 1
            wins[min(valid, key=valid.get)] += 1
        sorted_wins = sorted(wins.items(), key=lambda kv: -kv[1])
        line = f"- **{hl}** ({total} fixtures): " + ", ".join(
            f"{c} {n}" for c, n in sorted_wins if n > 0)
        lines.append(line)
    return "\n".join(lines) + "\n"


def build_report(runs: list[dict], paths: list[str],
                 baseline_idx: int) -> str:
    host_labels = [host_label(r) for r in runs]
    versions = [r.get("j2k_version", "?") for r in runs]
    captured = [r.get("captured_at", "?") for r in runs]

    out: list[str] = []
    out.append(f"# Cross-host warm cross-codec benchmark — {' vs '.join(host_labels)}")
    out.append("")
    out.append(f"_Generated {datetime.now().isoformat(timespec='seconds')} from "
               f"`Scripts/benchmarks/compare_hosts.py`._")
    out.append("")
    out.append("## Hosts and runs")
    out.append("")
    out.append("| # | Host | J2KSwift version | Captured | Source JSON |")
    out.append("|---|---|---|---|---|")
    for i, (r, p, hl, v, c) in enumerate(zip(runs, paths, host_labels, versions, captured)):
        marker = " (baseline)" if i == baseline_idx else ""
        out.append(f"| {i}{marker} | {hl} | {v} | {c} | `{p}` |")
    out.append("")

    # Methodology note from runs
    runs_n = runs[0].get("runs", "?")
    warmups = runs[0].get("warmups", "?")
    daemon = runs[0].get("daemon_reachable", "?")
    out.append(f"**Bench parameters:** median of {runs_n} timed runs after "
               f"{warmups} warmups per fixture per codec per direction. "
               f"j2kd daemon reachable: {daemon}.")
    out.append("")
    out.append("---")
    out.append("")

    # AGGREGATE SECTIONS
    base_label = host_labels[baseline_idx].split("(")[0].strip()
    other_label = host_labels[1 - baseline_idx].split("(")[0].strip() \
        if len(runs) == 2 else "(other)"

    for direction in ("encode", "decode"):
        out.append(f"## {direction.upper()} — aggregate {other_label} vs {base_label}")
        out.append("")
        out.append(f"Median speedup ({other_label} ms ÷ {base_label} ms; >1× means "
                   f"{other_label} is faster).")
        out.append("")
        agg = aggregate_speedup(direction, runs, baseline_idx)
        out.append(build_aggregate_table(agg, direction, host_labels, baseline_idx))
        out.append("")

    out.append("## Winner pattern by host (lowest median wins)")
    out.append("")
    for direction in ("encode", "decode"):
        out.append(f"**{direction.upper()}:**")
        out.append("")
        out.append(build_winner_delta(direction, runs, host_labels))
        out.append("")

    out.append("---")
    out.append("")

    # PER-FIXTURE DETAIL
    for direction in ("encode", "decode"):
        out.append(f"## Per-fixture {direction.upper()} — full ms + speedup matrix")
        out.append("")
        out.append(build_per_fixture_table(direction, runs, host_labels, baseline_idx))
        out.append("")

    # ENCODED SIZE PARITY (if both runs were captured under same fixtures)
    out.append("## Encoded-byte parity")
    out.append("")
    out.append(
        "_Cross-codec encoded sizes do not depend on host silicon — bytes are "
        "deterministic per (codec, source, config). To cross-check, compare "
        "the per-fixture .j2k/.jph byte counts in `/tmp/j2kswift_warm_bench/` "
        "from each host's run; differences > 0 indicate a non-deterministic "
        "codec config or version drift._"
    )
    out.append("")

    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Cross-host comparison report for canonical warm bench JSONs.")
    ap.add_argument("inputs", nargs="+",
                    help="Two or more canonical bench JSON files (one per host).")
    ap.add_argument("--output", "-o", required=True,
                    help="Markdown output path.")
    ap.add_argument("--baseline", type=int, default=0,
                    help="Index of baseline host (default 0 = first input).")
    args = ap.parse_args()

    if len(args.inputs) < 2:
        print("Error: need at least 2 input JSONs to compare.", file=sys.stderr)
        return 2

    runs = [load_run(p) for p in args.inputs]
    report = build_report(runs, args.inputs, args.baseline)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        f.write(report)

    print(f"Wrote {args.output} ({len(report.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
