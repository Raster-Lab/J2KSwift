# v10.15-research — `decodeQuality` / multi-layer decode

**Branch:** `v10.15-research`
**Status:** Phase 0 complete (investigation + plan); Phase 1 in progress
**Date:** 2026-05-20

## Goal

`decodeQuality(_:options:)` — quality-layer progressive decode — is the
last `notImplemented` partial-decode stub of arc C (after
`decodeResolution`, `decodeRegion`, `decodePartial`).
`decodeQuality(layer: L)` should decode a JPEG 2000 codestream up to
quality layer `L`, discarding the refinement carried by layers `> L`.

## Phase 0 — what the investigation found

### J2KSwift silently mis-decodes multi-layer codestreams (conformance bug)

`decodeQuality` is **not** a self-contained API stub — it sits on top of
multi-layer packet decode, which **the decoder does not implement**.
`extractTileData`'s packet loop is hardcoded single-layer
(`// Single layer for now`): it iterates `resolution × component ×
precinct` and reads exactly one packet per precinct. An LRCP codestream
with `Clayers > 1` emits `layer × resolution × component × precinct`
packets — the decoder reads a fraction of them and desynchronises.

Empirically confirmed (M2, Kakadu 8.4.1):

```
kdu_compress … Clayers=1 Creversible=yes  → ml1.j2k
kdu_compress … Clayers=4 Creversible=yes  → ml4.j2k   (genuine 4-layer)

j2k decode ml1.j2k   ≡  kdu_expand ml1.j2k   →  IDENTICAL  (md5 7f7c…)
j2k decode ml4.j2k   ≠  kdu_expand ml4.j2k   →  DIFFER
                          J2KSwift md5 116e04…  vs correct 7f7c…
```

So a multi-layer codestream from *any* encoder decodes to a **wrong
image, with no error raised**. This is a real Part-1 conformance defect,
not just a missing convenience API.

### The encoder cannot produce genuine quality layers

J2KSwift's own encoder does not produce progressive multi-layer
codestreams: `applyLayerTruncation` is a no-op in lossless mode, and the
legacy `layer × …` emission loop writes *identical* packets per layer.
The production encode path is single-layer (the v5.35.0d multi-precinct
design replaced the multi-layer approach). Consequence: `decodeQuality`
is a **decoder conformance feature** — its test surface is external
(Kakadu `kdu_compress Clayers=N`), not a J2KSwift round-trip.

### Scope

`decodeQuality` decomposes into:

- **Phase 1 — multi-layer packet decode** (the substantial part; also a
  conformance bug fix making `decode()` correct on multi-layer input).
- **Phase 2 — `decodeQuality(layer: L)`** — process only layers `0…L`;
  trivial once Phase 1 lands.

## Phase 1 plan — multi-layer packet decode in `extractTileData`

Per ISO/IEC 15444-1 B.10. The single-layer loop today:

```
for resLevel { for comp { for precinct {
    read 1 packet — fresh per-precinct inclusion + zbp tag-trees;
    each included block: inclusion(threshold 1), zbp, passes, length, data
}}}
```

Multi-layer changes:

1. **Layer loop** wrapping `for resLevel` — `for layer in 0..<qualityLayers`.
2. **Persistent per-precinct tag-trees.** `inclusionTree` / `zbpTree` for
   a `(res, comp, py, px)` precinct are created at layer 0 and **reused**
   across every layer's packet for that precinct (today they are fresh
   per packet). Store keyed by precinct.
3. **Per-layer inclusion.** A not-yet-included block: inclusion tag-tree
   decoded with `threshold = layer + 1`. An already-included block: a
   single bit ("contributes to this layer?"). The zbp tag-tree is
   decoded only on a block's *first* inclusion.
4. **Cross-layer accumulation.** A block accumulates passes/data across
   the layers it contributes to — `passCount = Σ passes_ℓ`,
   `data = concat(data_ℓ)`. `CodeBlockInfo` is emitted once per block
   with the totals.
5. **Per-block `LBlock` state** persists across layers (the length-
   signalling state in `decodeDataLength`).

Single-layer codestreams (`qualityLayers == 1`) must stay byte-exact —
the layer loop runs once and reduces to today's behaviour.

## Validation plan

- `decode()` of `kdu_compress Clayers=N` (N = 2,3,4) bit-identical to
  `kdu_expand` full decode, across the medical corpus.
- Single-layer decode unchanged (regression).
- Phase 2: `decodeQuality(layer: L)` consistent with `kdu_expand -layers L`.
- Mandatory commit gate.

## Status

Phase 0 done — bug diagnosed, test surface established, plan written.
Phase 1 (the multi-layer packet-decode rework) is the substantial
implementation and is the active work.
