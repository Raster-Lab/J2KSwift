# J2KSwift v10.24.1

**HTJ2K lossless data-loss fix — reversible 5/3 magnitude-window sizing.**

This is a **patch** release. It fixes a correctness defect in the HTJ2K
(Part-15) **lossless** encoder that could silently lose pixel data on
high-contrast content. The default Part-1 (EBCOT) encoder is unaffected and
its codestreams are byte-identical to v10.24.0.

---

## Summary

Testing J2KSwift against the **Cloudinary Image Dataset '22 (CID22)** — a
non-DICOM, natural, full-colour corpus — exposed a latent bug that the medical
(DICOM) corpus never triggered: **`j2k encode --htj2k --lossless` was not
always lossless.** On 4 of 49 CID22 reference images the HTJ2K codestream
decoded with up to 38,946 wrong pixels (max error 238), while the default
Part-1 lossless path was always bit-exact on the same images.

The defect was confirmed to be in the **encoder**, not the decoder: the
reference HTJ2K codec **OpenJPH** reproduced the loss from J2KSwift's
codestream, and J2KSwift's decoder reconstructs OpenJPH's reversible
codestreams bit-exactly. The 12/16-bit medical corpus was immune because that
content never approaches full scale; CID22's full-range 8-bit colour content
drives the reversible 5/3 transform to produce coefficients large enough to
overflow the encoder's magnitude window.

v10.24.1 sizes that window correctly. After the fix, all 49 CID22 images and
the medical corpus round-trip bit-exact in both Part-1 and HTJ2K, and OpenJPH,
Grok, and Kakadu all decode J2KSwift's HTJ2K output bit-exactly.

---

## What's Fixed

**HTJ2K conformant reversible encoder dropped the top magnitude bitplane of
any code-block whose coefficients exceeded an under-sized magnitude window.**

The conformant HT encoder converts coefficients to OpenJPH sign-magnitude as
`sign | (|v| << (31 - K_max))`. `K_max` was derived from the **single-level**
subband gain `{LL:0, HL/LH:1, HH:2}`. A multi-level reversible 5/3 transform
expands the coefficient range — the deep **LL** band especially — so
high-contrast 8-bit content (hard 0↔255 edges) produced coefficients with
magnitude ≥ `2^K_max`. `|v| << shift` then overflowed **bit 31 (the sign
bit)**, silently corrupting magnitude and sign and dropping the top bitplane.

Instrumentation on the minimal reproducer: `comp=1 sub=LL res=0 K_max=8
window=256 maxAbs=259 → OVERFLOW`. Minimal reproducer: an 8×8 RGB tile
(`Documentation/Benchmarks/data/htj2k_bug_repro/`).

**Fix:** a centralized `htConformantReversibleGain(subband:rctActive:)` sizes
the window to match OpenJPH's proven-sufficient reversible `K_max`
(LL = B+1, detail = B+2, plus one bit when the reversible colour transform is
active, which widens the U/V components), taking `max` with the previous gain
so windows can only **grow, never shrink**. The same gain drives the QCD ε
signalling and the per-block shift, so encoder and decoder stay consistent;
the decoder needs no change (it derives `K_max` from the QCD ε it reads). The
change is **scoped to the HT-conformant path** — legacy EBCOT and custom-HT
codestreams are byte-identical to v10.24.0.

---

## Backward compatibility

| Path | vs v10.24.0 |
|---|---|
| Part-1 / EBCOT (default; `useHTJ2K = false`) | **codestream byte-identical** |
| Custom HTJ2K block format | byte-identical |
| **HTJ2K conformant reversible (`--htj2k --lossless`)** | **codestream bytes change** (the fix) — now correct & OpenJPH/Grok/Kakadu-conformant |

Old v10.24.0 HTJ2K codestreams remain decodable (the decoder reads `K_max`
from each codestream's QCD). No public API was removed or changed.

---

## Cross-codec parity matrix (fresh, HTJ2K lossless)

Encoded with `j2k --htj2k --lossless`, decoded by three external reference
codecs, compared bit-exact to source pixels:

| Fixture | bits | self | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4 |
|---|---:|:--:|:--:|:--:|:--:|
| CT | 16 | ✓ | ✓ | ✓ | ✓ |
| MR | 12 | ✓ | ✓ | ✓ | ✓ |
| DX | 12 | ✓ | ✓ | ✓ | ✓ |
| MG | 12 | ✓ | ✓ | ✓ | ✓ |
| PX | 12 | ✓ | ✓ | ✓ | ✓ |

**External cross-codec cells bit-exact: 15/15.** Plus all 4 previously-failing
CID22 RGB images now bit-exact under OpenJPH cross-decode (was max err 238).

---

## Test Suite Results

Mandatory commit gate (release mode):

| Suite | Result |
|---|---|
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 pass |
| `J2KMedicalCorpusPerformanceTests` | 2/2 pass |
| `J2KStrictCrossCodecValidationTests` | 3/3 pass |

New regression suite:

| Suite | Result |
|---|---|
| `V10_25_HTConformantReversibleWindowTests` | 3/3 pass (exact 8×8 reproducer + synthetic high-contrast RGB & greyscale across 1–5 decomposition levels) |

Corpus validation:
- **CID22 (49 RGB references): 49/49 bit-exact** in both Part-1 and HTJ2K (was 45/49 HTJ2K).
- HT-conformant medical sample (CT/MR/DX/MG/PX, 8/12/16-bit): bit-exact + OpenJPH cross-decode clean.

---

## API surface

No public additions, removals, or signature changes. One internal helper
(`htConformantReversibleGain`) added in `J2KEncoderPipeline`.

New developer tooling (not library API):
- `Scripts/image_corpus_roundtrip.py` — non-DICOM (PNG/PPM/TIFF) encode/decode/
  bit-exact-verify harness with lossless, HTJ2K, and lossy PSNR-sweep modes.

---

## Known limitations

- The fix adds modest magnitude-window headroom, so HTJ2K lossless files are
  marginally larger than v10.24.0 (median CID22 ratio 2.65× → 2.55×). This is
  the cost of correctness and stays well within the normal HT-vs-EBCOT range.
- CID22 coverage used the official 49-image validation reference set (512×512
  RGB 8-bit); the full 250-image set sits behind a 7.2 GB archive whose CDN
  truncated repeatedly. The 49 images were sufficient to expose and fix the bug.

---

## Reproducing

```bash
swift build -c release --product j2k
# CID22 (non-DICOM) round-trip + lossy sweep
python3 Scripts/image_corpus_roundtrip.py \
  --dataset Datasets/cid22/CID22_validation_set/original \
  --bin .build/release/j2k --workers 8 --htj2k --qualities 0.95,0.85,0.50

# Mandatory gate
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Regression
swift test --filter V10_25_HTConformantReversibleWindowTests
```

---

## Companion documents

- [`CID22_COMPRESSION_TEST_REPORT.md`](CID22_COMPRESSION_TEST_REPORT.md) — full test report, root-cause analysis, and fix verification.
