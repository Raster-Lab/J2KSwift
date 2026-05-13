# V8.8 — AMX feasibility study for HT classifier: not viable

**Status**: NOT VIABLE. Apple Matrix Extensions (AMX) is structurally inapplicable to the JPEG 2000 HT entropy classifier.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)
**Method**: API surface review of corsix/dougallj reverse-engineered AMX documentation.

## Goal

Workstream 4 of the overnight research: determine whether Apple's undocumented AMX coprocessor (used internally by Accelerate.framework's BLAS/BNNS) can accelerate the per-quad HT entropy classifier. This is the encoder's only remaining structural lever after v6.1.0 PR #306 / v8.6 closed the SIMD4 classifier as wash.

## Verdict

**Not viable.** AMX is an outer-product matrix-multiply coprocessor with no count-leading-zeros, no per-element variable shift, and no general bit-manipulation primitives — exactly the operations that dominate the HT per-quad classifier.

## AMX instruction surface (from corsix.org reverse-engineering)

| Family       | Instructions | What they do |
|--------------|--------------|--------------|
| Load/store   | `ldx`/`ldy`/`ldz`, `stx`/`sty`/`stz`, `ldzi`/`stzi` | Move 64-byte registers between memory and the AMX register pool |
| Float MAC    | `fma16/32/64`, `fms16/32/64` | Float FMA over X×Y → Z, broadcast or strided |
| Integer MAC  | `mac16` | INT8/INT16 multiplicands, INT16/INT32 accumulators; `z ± ((x*y) >> s)` with **immediate** shift `s` |
| Integer mat  | `matint`, `vecint` | Integer matrix/vector arith (add, sub, mul, sqrdmlah). Same right-shift slot, same outer-product shape |
| Float mat    | `matfp`, `vecfp` | Float counterparts |
| Auxiliary    | `extr`, `set`, `clr`, `genlut` | Lane extract, zero, **table lookup capped at 32-entry / 5-bit index** |

**Hard absences**: no CLZ (count-leading-zeros), no `__builtin_ctz/clz`, no AND/OR/XOR, no per-lane variable shift, no compare→mask, no sign extraction primitive. The architecture is "32×32 grid of MAC units fed by X/Y register pools, accumulating into Z" — fundamentally `z[j][i] ± f(x[i], y[j])`.

## Mapping the classifier to AMX

The HT per-quad classifier computes `(sig: Bool, eQ: Int8, payload: UInt32)` from a UInt32 sample with sign-magnitude encoding:

```
sig     = (sample != 0)                 // compare→mask, AMX cannot
eQ      = MSB_position(magnitude)       // count-leading-zeros, AMX cannot
payload = 2*(magnitude - 1) + sign_bit  // shift+add, AMX *could* via mac16
                                        //   but this is 1 NEON cycle anyway
```

The **load-bearing** operation is `eQ = MSB_position(mag)` — for 25-bit medical magnitudes this is `clz(mag) - shift_offset`. AMX has no CLZ. `genlut` is capped at 32-entry tables (5-bit indices), so even a "log2 LUT trick" is impossible without 5+ chained lookups plus arithmetic to combine them — at which point you've spent more issue slots than the scalar `clz` instruction (1 cycle, fully pipelined on M2).

The classifier is structurally a **bit-manipulation kernel**. AMX is a **matrix-multiply kernel**. The primitives don't intersect.

## Risk assessment

Even if the math fit, AMX is **undocumented private ABI**:
- Opcodes use the reserved `0x00201000`-prefixed space, gated by a per-process enable.
- Can `SIGILL` on any future silicon Apple decides to remove it from. AMX has shipped on M1→M4 (2020-2024) but Apple has committed to **SME (Scalable Matrix Extension)** as the public successor on M4+.
- corsix/dougallj note `matint` mode tweaks at every M-generation transition; even using AMX correctly requires per-chip testing.
- Inline assembly + per-cluster latch state means thread-pinning quirks.
- AMX-context save/restore on kernel context switch adds ~hundreds of cycles.
- Zero compiler support.

For a workload measured **WASH at SIMD4 in v6.1.0 PR #306** and again in **v8.6 PR #407**, the engineering cost is multi-week vs. an upper-bound speedup that doesn't exist because the dominant op (CLZ) isn't in the ISA.

## Recommendation

**Close as wash — do not pursue Phase 1A AMX prototype.** Same conclusion class as v8.8 Accelerate sweep and v8.6 encoder arc.

The lever-ceiling on M2 + Swift release is structural for bit-manipulation hot paths regardless of which Apple-private accelerator is tried — vDSP / NEON / SIMD4 / AMX all converge on the same answer because the underlying ISA-level primitive (`clz`) is already optimally expressed by a single ARM64 instruction.

## Sources

- [corsix/amx — Apple AMX Instruction Set (GitHub)](https://github.com/corsix/amx)
- [corsix/amx — Instructions.md (full opcode list)](https://github.com/corsix/amx/blob/main/Instructions.md)
- [corsix/amx — mac16.md (INT16 MAC + post-shift)](https://github.com/corsix/amx/blob/main/mac16.md)
- [corsix/amx — genlut.md (32-entry LUT)](https://github.com/corsix/amx/blob/main/genlut.md)
- [dougallj — aarch64_amx.py reverse-engineering notes](https://gist.github.com/dougallj/7a75a3be1ec69ca550e7c36dc75e0d6f)
- [Eclectic Light Co — AMX co-processors across Apple silicon](https://eclecticlight.co/2023/12/13/finding-and-evaluating-amx-co-processors-in-apple-silicon-chips/)
- [PQC-AMX paper — AMX integer-mode usage on M1/M3](https://eprint.iacr.org/2024/195.pdf)
- [Jonathan Zhou MIT thesis — AMX Performance Analysis (2025)](https://commit.csail.mit.edu/papers/2025/Jonathan_Zhou_SB_Thesis.pdf)

## What stays in tree

- `V8_8_AMX_FEASIBILITY_FINDING.md` — this document.

No code change. No microbench (the API surface review is the deliverable).
