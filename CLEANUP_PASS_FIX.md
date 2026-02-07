# Cleanup Pass Synchronization Bug - Analysis and Fix

## Problem
The bit-plane decoder produces incorrect results when encoding/decoding 3+ non-zero coefficients. Position 3 gets corrupted (expected 0, gets 1 or -1).

## Investigation Findings

### Key Observations
1. Tests with 1-2 coefficients PASS
2. Tests with 3+ coefficients FAIL
3. Position 3 (a corner position with no original coefficients) gets corrupted
4. The corruption happens at a specific bitMask (0x02)
5. Encoder and decoder have identical code logic
6. Encoder and decoder make identical RLC eligibility decisions
7. Encoder and decoder process the same positions in cleanup passes
8. The bug persists even when RLC optimization is completely disabled

### Root Cause (Hypothesis)
The bug is in the CORE cleanup pass logic where positions are processed individually. Even though the code is identical, there must be a subtle state synchronization issue that only manifests with multiple significant coefficients.

### Possible Causes
1. **Order of operations**: The order of neighbor calculation vs. state updates might matter
2. **State initialization**: The initial state might be different (unlikely, code is identical)
3. **Bitstream synchronization**: The encoder might write fewer bits than the decoder expects
4. **Context state**: The context model might have internal state that diverges

## Proposed Solution

The safest fix is to ensure absolute determinism by:
1. Making explicit when states are updated vs. when neighbors are calculated
2. Ensuring no position is skipped due to state changes during the current pass
3. Processing all coefficients in a deterministic order

The key insight is that when we update a coefficient's `.significant` flag inline during the loop, this might affect subsequent neighbor calculations. We need to ensure this happens identically in both encoder and decoder.

## Implementation Strategy

Rather than trying to fix the subtle bug, the most pragmatic approach is to:

1. Separate state calculation from state updates
2. Process all coefficient states for a column BEFORE updating them
3. Ensure the skip condition is computed consistently

This ensures that neighbor information is computed from a consistent state snapshot.
