# Bypass Mode Issue - RESOLVED

## Status: Fixed in v1.1.1

The bypass mode synchronization bug has been fixed. The root cause was the MQ
coder's C register being shared between MQ arithmetic coding and raw bypass
bit packing, which caused bit-positioning mismatches for larger blocks.

## Solution

The fix implements separate `RawBypassEncoder` and `RawBypassDecoder` types
that pack/unpack raw bits independently using simple MSB-first byte packing
with 0xFF stuffing. When bypass mode is enabled, per-pass segmentation is
automatically used to cleanly separate MQ-coded and raw-coded data, following
the JPEG 2000 standard requirement for pass termination before bypass passes.

## Test Status

- `testMinimalBlock32x32` - **PASSING** (was failing with 95.70% error rate)
- `testCodeBlockBypassLargeBlock` - **PASSING** (was skipped)
- `testProgressiveBlockSizes` - **PASSING** (4x4 through 32x32)
- `testMinimalBlock64x64` - Skipped (pre-existing 64x64 dense data MQ issue, not bypass-related)
- `test64x64WithoutBypass` - Skipped (same pre-existing 64x64 issue)

The 64x64 dense data issue affects all coding options (including default/no bypass)
and is a separate MQ coder issue to be addressed in a future release.

## References

- [BYPASS_MODE.md](BYPASS_MODE.md) - Feature documentation
- OpenJPEG source: `src/lib/openjp2/mqc.c` and `mqc_inl.h`
- ISO/IEC 15444-1 Annex C - MQ-coder specification
