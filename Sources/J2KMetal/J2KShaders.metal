#include <metal_stdlib>
using namespace metal;

// MARK: - Forward 9/7 Irreversible DWT (Horizontal)

kernel void j2k_dwt_forward_97_horizontal(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    // CDF 9/7 lifting coefficients
    const float alpha = -1.586134342f;
    const float beta  = -0.052980118f;
    const float gamma =  0.882911075f;
    const float delta =  0.443506852f;
    const float K     =  1.230174105f;

    uint idx = row * width;
    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;

    // Step 1: Split into even and odd samples (no scaling yet)
    for (uint i = 0; i < halfWidth; i++) {
        lowpass[lBase + i] = input[idx + min(2 * i, width - 1)];
    }
    for (uint i = 0; i < halfWidthH; i++) {
        highpass[hBase + i] = input[idx + 2 * i + 1];
    }

    // Step 2: Predict 1 — d[i] += alpha * (s[i] + s[i+1])
    for (uint i = 0; i < halfWidthH; i++) {
        highpass[hBase + i] += alpha * (lowpass[lBase + i] + lowpass[lBase + min(i + 1, halfWidth - 1)]);
    }
    // Step 3: Update 1 — s[i] += beta * (d[i-1] + d[i])
    for (uint i = 0; i < halfWidth; i++) {
        float dLeft  = highpass[hBase + ((i > 0) ? (i - 1) : 0)];
        float dRight = highpass[hBase + min(i, halfWidthH - 1)];
        lowpass[lBase + i] += beta * (dLeft + dRight);
    }
    // Step 4: Predict 2 — d[i] += gamma * (s[i] + s[i+1])
    for (uint i = 0; i < halfWidthH; i++) {
        highpass[hBase + i] += gamma * (lowpass[lBase + i] + lowpass[lBase + min(i + 1, halfWidth - 1)]);
    }
    // Step 5: Update 2 — s[i] += delta * (d[i-1] + d[i])
    for (uint i = 0; i < halfWidth; i++) {
        float dLeft  = highpass[hBase + ((i > 0) ? (i - 1) : 0)];
        float dRight = highpass[hBase + min(i, halfWidthH - 1)];
        lowpass[lBase + i] += delta * (dLeft + dRight);
    }

    // Step 6: Scale (ISO/IEC 15444-1 Annex F.4.1.1)
    // v5.21.0 fix: lowpass /= K, highpass *= K (was inverted pre-v5.21).
    for (uint i = 0; i < halfWidth; i++) { lowpass[lBase + i] /= K; }
    for (uint i = 0; i < halfWidthH; i++) { highpass[hBase + i] *= K; }
}

// MARK: - Forward 9/7 Irreversible DWT (Vertical)

kernel void j2k_dwt_forward_97_vertical(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    const float alpha = -1.586134342f;
    const float beta  = -0.052980118f;
    const float gamma =  0.882911075f;
    const float delta =  0.443506852f;
    const float K     =  1.230174105f;

    // Step 1: Split into even and odd rows
    for (uint i = 0; i < halfHeight; i++) {
        lowpass[i * width + col] = input[min(2 * i, height - 1) * width + col];
    }
    for (uint i = 0; i < halfHeightH; i++) {
        highpass[i * width + col] = input[(2 * i + 1) * width + col];
    }

    // Step 2: Predict 1
    for (uint i = 0; i < halfHeightH; i++) {
        highpass[i * width + col] += alpha * (lowpass[i * width + col] + lowpass[min(i + 1, halfHeight - 1) * width + col]);
    }
    // Step 3: Update 1
    for (uint i = 0; i < halfHeight; i++) {
        float dTop = highpass[((i > 0) ? (i - 1) : 0) * width + col];
        float dBot = highpass[min(i, halfHeightH - 1) * width + col];
        lowpass[i * width + col] += beta * (dTop + dBot);
    }
    // Step 4: Predict 2
    for (uint i = 0; i < halfHeightH; i++) {
        highpass[i * width + col] += gamma * (lowpass[i * width + col] + lowpass[min(i + 1, halfHeight - 1) * width + col]);
    }
    // Step 5: Update 2
    for (uint i = 0; i < halfHeight; i++) {
        float dTop = highpass[((i > 0) ? (i - 1) : 0) * width + col];
        float dBot = highpass[min(i, halfHeightH - 1) * width + col];
        lowpass[i * width + col] += delta * (dTop + dBot);
    }

    // Step 6: Scale (ISO/IEC 15444-1 Annex F.4.1.1)
    // v5.21.0 fix: lowpass /= K, highpass *= K (was inverted pre-v5.21).
    for (uint i = 0; i < halfHeight; i++) { lowpass[i * width + col] /= K; }
    for (uint i = 0; i < halfHeightH; i++) { highpass[i * width + col] *= K; }
}

// MARK: - Inverse 9/7 Irreversible DWT (Horizontal)

kernel void j2k_dwt_inverse_97_horizontal(
    device const float* lowpassIn [[buffer(0)]],
    device const float* highpassIn [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    const float alpha = -1.586134342f;
    const float beta  = -0.052980118f;
    const float gamma =  0.882911075f;
    const float delta =  0.443506852f;
    const float K     =  1.230174105f;

    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;

    // Use output buffer as scratch for even/odd reconstruction
    // Undo scaling — inverse of forward step 6 (which divides
    // lowpass by K and multiplies highpass by K per ISO/IEC
    // 15444-1 Annex F.4.1.1). v5.21.0 fix: pre-v5.21 the GPU had
    // both forward and inverse scaling inverted vs spec — self-
    // consistent but incompatible with CPU-encoded codestreams.
    // Now spec-compliant: undo by `lowpass *= K`, `highpass /= K`.
    for (uint i = 0; i < halfWidth; i++) {
        output[row * width + 2 * i] = lowpassIn[lBase + i] * K;
    }
    for (uint i = 0; i < halfWidthH; i++) {
        output[row * width + 2 * i + 1] = highpassIn[hBase + i] / K;
    }

    // We need even/odd arrays for lifting; re-extract them from output
    // Use local-scope arrays via output reinterpretation
    // For correctness, work with even[] and odd[] in output positions
    // even = output[2*i], odd = output[2*i+1]

    // Undo update 2: s[i] -= delta * (d[i-1] + d[i])
    for (uint i = 0; i < halfWidth; i++) {
        float dLeft  = output[row * width + 2 * ((i > 0) ? (i - 1) : 0) + 1];
        float dRight = (i < halfWidthH) ? output[row * width + 2 * i + 1]
                       : output[row * width + 2 * max(int(halfWidthH) - 1, 0) + 1];
        output[row * width + 2 * i] -= delta * (dLeft + dRight);
    }
    // Undo predict 2: d[i] -= gamma * (s[i] + s[i+1])
    for (uint i = 0; i < halfWidthH; i++) {
        float sLeft  = output[row * width + 2 * i];
        float sRight = output[row * width + 2 * min(i + 1, halfWidth - 1)];
        output[row * width + 2 * i + 1] -= gamma * (sLeft + sRight);
    }
    // Undo update 1: s[i] -= beta * (d[i-1] + d[i])
    for (uint i = 0; i < halfWidth; i++) {
        float dLeft  = output[row * width + 2 * ((i > 0) ? (i - 1) : 0) + 1];
        float dRight = (i < halfWidthH) ? output[row * width + 2 * i + 1]
                       : output[row * width + 2 * max(int(halfWidthH) - 1, 0) + 1];
        output[row * width + 2 * i] -= beta * (dLeft + dRight);
    }
    // Undo predict 1: d[i] -= alpha * (s[i] + s[i+1])
    for (uint i = 0; i < halfWidthH; i++) {
        float sLeft  = output[row * width + 2 * i];
        float sRight = output[row * width + 2 * min(i + 1, halfWidth - 1)];
        output[row * width + 2 * i + 1] -= alpha * (sLeft + sRight);
    }
}

// MARK: - Inverse 9/7 Irreversible DWT (Vertical)

kernel void j2k_dwt_inverse_97_vertical(
    device const float* lowpassIn [[buffer(0)]],
    device const float* highpassIn [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    const float alpha = -1.586134342f;
    const float beta  = -0.052980118f;
    const float gamma =  0.882911075f;
    const float delta =  0.443506852f;
    const float K     =  1.230174105f;

    // Undo scaling and interleave into output. v5.21.0 fix: see
    // horizontal-inverse comment above; pre-v5.21 had both forward
    // and inverse scaling inverted vs ISO/IEC 15444-1.
    for (uint i = 0; i < halfHeight; i++) {
        output[(2 * i) * width + col] = lowpassIn[i * width + col] * K;
    }
    for (uint i = 0; i < halfHeightH; i++) {
        output[(2 * i + 1) * width + col] = highpassIn[i * width + col] / K;
    }

    // Undo update 2
    for (uint i = 0; i < halfHeight; i++) {
        float dTop = output[(2 * ((i > 0) ? (i - 1) : 0) + 1) * width + col];
        float dBot = (i < halfHeightH) ? output[(2 * i + 1) * width + col]
                     : output[(2 * max(int(halfHeightH) - 1, 0) + 1) * width + col];
        output[(2 * i) * width + col] -= delta * (dTop + dBot);
    }
    // Undo predict 2
    for (uint i = 0; i < halfHeightH; i++) {
        float sTop = output[(2 * i) * width + col];
        float sBot = output[(2 * min(i + 1, halfHeight - 1)) * width + col];
        output[(2 * i + 1) * width + col] -= gamma * (sTop + sBot);
    }
    // Undo update 1
    for (uint i = 0; i < halfHeight; i++) {
        float dTop = output[(2 * ((i > 0) ? (i - 1) : 0) + 1) * width + col];
        float dBot = (i < halfHeightH) ? output[(2 * i + 1) * width + col]
                     : output[(2 * max(int(halfHeightH) - 1, 0) + 1) * width + col];
        output[(2 * i) * width + col] -= beta * (dTop + dBot);
    }
    // Undo predict 1
    for (uint i = 0; i < halfHeightH; i++) {
        float sTop = output[(2 * i) * width + col];
        float sBot = output[(2 * min(i + 1, halfHeight - 1)) * width + col];
        output[(2 * i + 1) * width + col] -= alpha * (sTop + sBot);
    }
}

// MARK: - Forward 5/3 Reversible DWT (Horizontal)

kernel void j2k_dwt_forward_53_horizontal(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    uint idx = row * width;
    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;

    // Predict step: d[n] = x[2n+1] - (x[2n] + x[2n+2]) / 2
    for (uint i = 0; i < halfWidthH; i++) {
        float left = input[idx + 2 * i];
        float right = (2 * i + 2 < width) ? input[idx + 2 * i + 2] : input[idx + 2 * i];
        highpass[hBase + i] = input[idx + 2 * i + 1] - (left + right) / 2.0f;
    }

    // Update step: s[n] = x[2n] + (d[n-1] + d[n] + 2) / 4
    for (uint i = 0; i < halfWidth; i++) {
        float d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
        float d_right = (i < halfWidthH) ? highpass[hBase + i] : highpass[hBase + max(int(halfWidthH) - 1, 0)];
        lowpass[lBase + i] = input[idx + 2 * i] + (d_left + d_right + 2.0f) / 4.0f;
    }
}

// MARK: - Forward 5/3 Reversible DWT (Vertical)

kernel void j2k_dwt_forward_53_vertical(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    // Predict step
    for (uint i = 0; i < halfHeightH; i++) {
        float top = input[(2 * i) * width + col];
        float bottom = (2 * i + 2 < height) ? input[(2 * i + 2) * width + col] : input[(2 * i) * width + col];
        highpass[i * width + col] = input[(2 * i + 1) * width + col] - (top + bottom) / 2.0f;
    }
    // Update step
    for (uint i = 0; i < halfHeight; i++) {
        float d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
        float d_bot = (i < halfHeightH) ? highpass[i * width + col] : highpass[max(int(halfHeightH) - 1, 0) * width + col];
        lowpass[i * width + col] = input[(2 * i) * width + col] + (d_top + d_bot + 2.0f) / 4.0f;
    }
}

// MARK: - Inverse 5/3 Reversible DWT (Horizontal)

kernel void j2k_dwt_inverse_53_horizontal(
    device const float* lowpass [[buffer(0)]],
    device const float* highpass [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;
    uint oBase = row * width;

    // Undo update: x[2n] = s[n] - (d[n-1] + d[n] + 2) / 4
    for (uint i = 0; i < halfWidth; i++) {
        float d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
        float d_right = (i < halfWidthH) ? highpass[hBase + i] : highpass[hBase + max(int(halfWidthH) - 1, 0)];
        output[oBase + 2 * i] = lowpass[lBase + i] - (d_left + d_right + 2.0f) / 4.0f;
    }
    // Undo predict: x[2n+1] = d[n] + (x[2n] + x[2n+2]) / 2
    for (uint i = 0; i < halfWidthH; i++) {
        float left = output[oBase + 2 * i];
        float right = (2 * i + 2 < width) ? output[oBase + 2 * i + 2] : output[oBase + 2 * i];
        output[oBase + 2 * i + 1] = highpass[hBase + i] + (left + right) / 2.0f;
    }
}

// MARK: - Inverse 5/3 Reversible DWT (Vertical)

kernel void j2k_dwt_inverse_53_vertical(
    device const float* lowpass [[buffer(0)]],
    device const float* highpass [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    // Undo update
    for (uint i = 0; i < halfHeight; i++) {
        float d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
        float d_bot = (i < halfHeightH) ? highpass[i * width + col] : highpass[max(int(halfHeightH) - 1, 0) * width + col];
        output[(2 * i) * width + col] = lowpass[i * width + col] - (d_top + d_bot + 2.0f) / 4.0f;
    }
    // Undo predict
    for (uint i = 0; i < halfHeightH; i++) {
        float top = output[(2 * i) * width + col];
        float bottom = (2 * i + 2 < height) ? output[(2 * i + 2) * width + col] : output[(2 * i) * width + col];
        output[(2 * i + 1) * width + col] = highpass[i * width + col] + (top + bottom) / 2.0f;
    }
}

// MARK: - Forward 5/3 Reversible DWT (Horizontal, integer / bit-exact)
//
// Lossless-only pivot — Phase 0. Bit-exact match for the CPU reference
// `AcceleratedDWT2D.forward53_1D(_:_:count:workspace:)` in
// `J2KAcceleratedEncoder.swift`:
//   highpass[i] = X[2i+1] - ((X[2i] + X[2i+2]) >> 1)        // predict
//   lowpass[i]  = X[2i]  + ((H[i-1] + H[i] + 2) >> 2)       // update
// with whole-sample symmetric mirror at both boundaries (right edge of
// predict when n is even; both edges of update). Floor-divide via
// arithmetic right shift on signed int matches Swift's `&-`/`&+` and
// `>> n` on Int32 (sign-preserving shift). Kernel does the predict pass
// fully before the update pass (per-row read-after-write within one
// thread) so no thread-level synchronisation is needed.

kernel void j2k_dwt_forward_53_horizontal_int(
    device const int* input [[buffer(0)]],
    device int* lowpass [[buffer(1)]],
    device int* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth  = (width + 1) / 2;   // lowCount  = ceil(n/2)
    uint halfWidthH = width / 2;         // highCount = floor(n/2)

    uint idx   = row * width;
    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;

    // Edge tile (width = 1 → only one even sample, no highpass).
    if (halfWidthH == 0) {
        if (halfWidth > 0) {
            lowpass[lBase] = input[idx];
        }
        return;
    }

    // Predict: H[i] = X[2i+1] - ((X[2i] + X[2i+2]) >> 1).
    // Right boundary (n even, last i): mirror X[2i+2] = X[2i].
    for (uint i = 0; i < halfWidthH; i++) {
        int xLeft  = input[idx + 2 * i];
        int xRight = (2 * i + 2 < width)
            ? input[idx + 2 * i + 2]
            : input[idx + 2 * i];
        highpass[hBase + i] =
            input[idx + 2 * i + 1] - ((xLeft + xRight) >> 1);
    }

    // Update: L[i] = X[2i] + ((H[i-1] + H[i] + 2) >> 2).
    // Left boundary (i = 0): mirror H[-1] = H[0].
    // Right boundary (n odd, i = halfWidth-1 ≥ halfWidthH):
    //   mirror H[halfWidthH] = H[halfWidthH-1].
    for (uint i = 0; i < halfWidth; i++) {
        int dLeft  = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
        int dRight = (i < halfWidthH)
            ? highpass[hBase + i]
            : highpass[hBase + halfWidthH - 1];
        lowpass[lBase + i] =
            input[idx + 2 * i] + ((dLeft + dRight + 2) >> 2);
    }
}

// MARK: - Forward 5/3 Reversible DWT (Vertical, integer / bit-exact)

kernel void j2k_dwt_forward_53_vertical_int(
    device const int* input [[buffer(0)]],
    device int* lowpass [[buffer(1)]],
    device int* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight  = (height + 1) / 2;  // lowCount
    uint halfHeightH = height / 2;        // highCount

    // Edge tile (height = 1 → one even row, no highpass).
    if (halfHeightH == 0) {
        if (halfHeight > 0) {
            lowpass[col] = input[col];
        }
        return;
    }

    // Predict (column): H[i] = X[2i+1] - ((X[2i] + X[2i+2]) >> 1).
    for (uint i = 0; i < halfHeightH; i++) {
        int xTop = input[(2 * i) * width + col];
        int xBot = (2 * i + 2 < height)
            ? input[(2 * i + 2) * width + col]
            : input[(2 * i) * width + col];
        highpass[i * width + col] =
            input[(2 * i + 1) * width + col] - ((xTop + xBot) >> 1);
    }

    // Update (column): L[i] = X[2i] + ((H[i-1] + H[i] + 2) >> 2).
    for (uint i = 0; i < halfHeight; i++) {
        int dTop = (i > 0)
            ? highpass[(i - 1) * width + col]
            : highpass[col];
        int dBot = (i < halfHeightH)
            ? highpass[i * width + col]
            : highpass[(halfHeightH - 1) * width + col];
        lowpass[i * width + col] =
            input[(2 * i) * width + col] + ((dTop + dBot + 2) >> 2);
    }
}

// MARK: - Forward 5/3 Reversible DWT (Horizontal, integer / odd origin)
//
// v6-alpha5 phase 4 — odd-origin parity-aware forward 5/3 INT.
// Bit-exact match for the CPU reference
// `AcceleratedDWT2D.forward53_1D(...uOrigin:workspace:)` when uOrigin
// is odd. Image-coord parity flips local-vs-band mapping:
//   local even index → image-odd position → H band source
//   local odd index  → image-even position → L band source
// and the band counts swap:
//   lowCount  = floor(n/2)   (was ceil(n/2) for even origin)
//   highCount = ceil(n/2)    (was floor(n/2))
// The predict pass has a left-mirror at H[0] (= L[0] for both
// neighbours, so H[0] -= L[0]). The update pass has *no* left
// mirror — for odd origin, L[0] is at image position u+1 and its
// left H neighbour is H[0], its right is H[1].
//
// Forward kernel has no read-after-write across the split: predict
// only reads input + writes highpass; update only reads input +
// highpass + writes lowpass. Single-thread per row, sequential.

kernel void j2k_dwt_forward_53_horizontal_int_odd(
    device const int* input [[buffer(0)]],
    device int* lowpass [[buffer(1)]],
    device int* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint lowCount  = width / 2;            // floor(n/2)
    uint highCount = width - lowCount;     // ceil(n/2)

    uint idx   = row * width;
    uint lBase = row * lowCount;
    uint hBase = row * highCount;

    // Edge tile (width = 1 → only one image-even sample, no L band).
    if (lowCount == 0) {
        if (highCount > 0) {
            highpass[hBase] = input[idx];
        }
        return;
    }

    // Predict: H[i] is computed from local-even input X[2i] minus
    // (L_left + L_right) >> 1 where L_left, L_right are the two
    // image-even neighbours bracketing the image-odd position.
    // For odd origin the gather flips: L stores input[2i+1] etc.
    //
    // H[0]: left mirror — both neighbours collapse to L[0].
    // Interior 1 ≤ i < min(highCount, lowCount): H[i] uses L[i-1] and L[i].
    // H[lowCount] when n odd (highCount > lowCount): right mirror,
    //   both neighbours collapse to L[lowCount-1].
    if (highCount > 0) {
        // H[0] = input[0] - ((L[0] + L[0]) >> 1) = input[0] - L[0]
        // L[0] = input[1] (local-odd gather).
        highpass[hBase] = input[idx] - input[idx + 1];
    }
    uint predictInteriorEnd = min(highCount, lowCount);
    for (uint i = 1; i < predictInteriorEnd; i++) {
        // L[i-1] = input[idx + 2*(i-1) + 1], L[i] = input[idx + 2*i + 1]
        int lLeft  = input[idx + 2 * (i - 1) + 1];
        int lRight = input[idx + 2 * i + 1];
        highpass[hBase + i] = input[idx + 2 * i] - ((lLeft + lRight) >> 1);
    }
    if (highCount > lowCount) {
        // H[lowCount]: right mirror at tile edge (n odd).
        // Both neighbours collapse to L[lowCount-1] = input[2*(lowCount-1) + 1].
        int lLast = input[idx + 2 * (lowCount - 1) + 1];
        highpass[hBase + lowCount] = input[idx + 2 * lowCount] - lLast;
    }

    // Update: L[i] is computed from input[2i+1] (the local-odd
    // gather, image-even position) plus (H_left + H_right + 2) >> 2.
    // No left mirror for odd origin — L[0]'s left H is H[0].
    // Right mirror when i+1 >= highCount.
    for (uint i = 0; i < lowCount; i++) {
        int hLeft  = highpass[hBase + i];
        int hRight = (i + 1 < highCount)
            ? highpass[hBase + i + 1]
            : highpass[hBase + highCount - 1];
        lowpass[lBase + i] = input[idx + 2 * i + 1] + ((hLeft + hRight + 2) >> 2);
    }
}

// MARK: - Forward 5/3 Reversible DWT (Vertical, integer / odd origin)

kernel void j2k_dwt_forward_53_vertical_int_odd(
    device const int* input [[buffer(0)]],
    device int* lowpass [[buffer(1)]],
    device int* highpass [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint lowCount  = height / 2;
    uint highCount = height - lowCount;

    if (lowCount == 0) {
        if (highCount > 0) {
            highpass[col] = input[col];
        }
        return;
    }

    // Predict (column): H[i] = X[2i] - ((L[i-1] + L[i]) >> 1)
    // where L[i] = X[2i+1] (image-odd gather flips for odd uY).
    if (highCount > 0) {
        highpass[col] = input[col] - input[width + col];
    }
    uint predictInteriorEnd = min(highCount, lowCount);
    for (uint i = 1; i < predictInteriorEnd; i++) {
        int lTop = input[(2 * (i - 1) + 1) * width + col];
        int lBot = input[(2 * i + 1) * width + col];
        highpass[i * width + col] =
            input[(2 * i) * width + col] - ((lTop + lBot) >> 1);
    }
    if (highCount > lowCount) {
        int lLast = input[(2 * (lowCount - 1) + 1) * width + col];
        highpass[lowCount * width + col] =
            input[(2 * lowCount) * width + col] - lLast;
    }

    // Update (column): L[i] = X[2i+1] + ((H[i] + H[i+1 or mirror] + 2) >> 2)
    for (uint i = 0; i < lowCount; i++) {
        int hTop = highpass[i * width + col];
        int hBot = (i + 1 < highCount)
            ? highpass[(i + 1) * width + col]
            : highpass[(highCount - 1) * width + col];
        lowpass[i * width + col] =
            input[(2 * i + 1) * width + col] + ((hTop + hBot + 2) >> 2);
    }
}

// MARK: - Inverse 5/3 Reversible DWT (Horizontal, integer / bit-exact)
//
// Bit-exact match for J2KDWT1D.inverseTransform53 (symmetric extension):
//   even[i] = lowpass[i] - ((hp[i-1] + hp[i] + 2) >> 2)
//   odd[i]  = highpass[i] + ((even[i] + even[i+1]) >> 1)
// Floor-divide via arithmetic right shift on signed int matches Swift's
// `>> 2` / `>> 1` on Int32 (both perform sign-preserving shift).

kernel void j2k_dwt_inverse_53_horizontal_int(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;
    uint oBase = row * width;

    // Edge tile with no highpass samples → output equals lowpass.
    if (halfWidthH == 0) {
        for (uint i = 0; i < halfWidth; i++) {
            output[oBase + 2 * i] = lowpass[lBase + i];
        }
        return;
    }

    // Step 1 (undo update). Symmetric: hp[-1] = hp[0], hp[halfWidthH] = hp[halfWidthH-1].
    for (uint i = 0; i < halfWidth; i++) {
        int dLeft  = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
        int dRight = (i < halfWidthH)
            ? highpass[hBase + i]
            : highpass[hBase + halfWidthH - 1];
        output[oBase + 2 * i] = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
    }

    // Step 2 (undo predict). Symmetric: even[halfWidth] = even[halfWidth-1].
    for (uint i = 0; i < halfWidthH; i++) {
        int eLeft  = output[oBase + 2 * i];
        int eRight = (2 * i + 2 < width)
            ? output[oBase + 2 * i + 2]
            : output[oBase + 2 * i];
        output[oBase + 2 * i + 1] = highpass[hBase + i] + ((eLeft + eRight) >> 1);
    }
}

// MARK: - Inverse 5/3 Reversible DWT (Vertical, integer / bit-exact)

kernel void j2k_dwt_inverse_53_vertical_int(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    // Edge tile with no highpass rows → copy lowpass rows into even slots.
    if (halfHeightH == 0) {
        for (uint i = 0; i < halfHeight; i++) {
            output[(2 * i) * width + col] = lowpass[i * width + col];
        }
        return;
    }

    // Step 1 (undo update). Symmetric column boundaries.
    for (uint i = 0; i < halfHeight; i++) {
        int dTop = (i > 0)
            ? highpass[(i - 1) * width + col]
            : highpass[col];
        int dBot = (i < halfHeightH)
            ? highpass[i * width + col]
            : highpass[(halfHeightH - 1) * width + col];
        output[(2 * i) * width + col] = lowpass[i * width + col] - ((dTop + dBot + 2) >> 2);
    }

    // Step 2 (undo predict).
    for (uint i = 0; i < halfHeightH; i++) {
        int eTop = output[(2 * i) * width + col];
        int eBot = (2 * i + 2 < height)
            ? output[(2 * i + 2) * width + col]
            : output[(2 * i) * width + col];
        output[(2 * i + 1) * width + col] = highpass[i * width + col] + ((eTop + eBot) >> 1);
    }
}

// MARK: - v10.3 Phase 2-1 — 2D-layout Inverse 5/3 integer kernels (split steps)
//
// The scalar `j2k_dwt_inverse_53_*_int` kernels above dispatch ONE
// thread per row (or column) and loop internally over the other axis.
// On MG (3520×4784) that's only ~2400 threads in flight, severely
// under-utilising the M2 GPU (~100K-thread sweet spot).
//
// The 2D-layout variants split the work:
//   • Step 1 (undo update) — one thread per output even-position
//     (gid.x = i ∈ [0, halfWidth), gid.y = row).
//   • Step 2 (undo predict) — one thread per output odd-position
//     (gid.x = i ∈ [0, halfWidthH), gid.y = row), dispatched in
//     a SEPARATE encoder so step-1 writes are visible globally
//     before step-2 reads them.
//
// Bit-exact equivalent of the scalar kernel by construction: same
// arithmetic, same boundary conditions, just executed in a parallel
// thread layout. The edge case (halfWidthH == 0 for horizontal,
// halfHeight == 0 for vertical) is handled in step 1; caller must
// skip step-2 dispatch when the corresponding half-dimension is 0.

kernel void j2k_dwt_inverse_53_horizontal_int_2d_step1(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint row = gid.y;
    uint i = gid.x;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    if (row >= height || i >= halfWidth) return;

    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;
    uint oBase = row * width;

    if (halfWidthH == 0) {
        output[oBase + 2 * i] = lowpass[lBase + i];
        return;
    }

    int dLeft = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
    int dRight = (i < halfWidthH)
        ? highpass[hBase + i]
        : highpass[hBase + halfWidthH - 1];
    output[oBase + 2 * i] = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
}

kernel void j2k_dwt_inverse_53_horizontal_int_2d_step2(
    device const int* highpass [[buffer(0)]],
    device int* output [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint row = gid.y;
    uint i = gid.x;
    uint halfWidthH = width / 2;

    if (row >= height || i >= halfWidthH) return;

    uint hBase = row * halfWidthH;
    uint oBase = row * width;

    int eLeft = output[oBase + 2 * i];
    int eRight = (2 * i + 2 < width)
        ? output[oBase + 2 * i + 2]
        : output[oBase + 2 * i];
    output[oBase + 2 * i + 1] = highpass[hBase + i] + ((eLeft + eRight) >> 1);
}

kernel void j2k_dwt_inverse_53_vertical_int_2d_step1(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint col = gid.x;
    uint i = gid.y;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    if (col >= width || i >= halfHeight) return;

    if (halfHeightH == 0) {
        output[(2 * i) * width + col] = lowpass[i * width + col];
        return;
    }

    int dTop = (i > 0)
        ? highpass[(i - 1) * width + col]
        : highpass[col];
    int dBot = (i < halfHeightH)
        ? highpass[i * width + col]
        : highpass[(halfHeightH - 1) * width + col];
    output[(2 * i) * width + col] = lowpass[i * width + col] - ((dTop + dBot + 2) >> 2);
}

kernel void j2k_dwt_inverse_53_vertical_int_2d_step2(
    device const int* highpass [[buffer(0)]],
    device int* output [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint col = gid.x;
    uint i = gid.y;
    uint halfHeightH = height / 2;

    if (col >= width || i >= halfHeightH) return;

    int eTop = output[(2 * i) * width + col];
    int eBot = (2 * i + 2 < height)
        ? output[(2 * i + 2) * width + col]
        : output[(2 * i) * width + col];
    output[(2 * i + 1) * width + col] = highpass[i * width + col] + ((eTop + eBot) >> 1);
}

// MARK: - v10.3 Phase 2-2-tiled — Inverse 5/3 Int with threadgroup-memory tiling
//
// The Phase 2-1 split-step kernels (`*_2d_step1` + `*_2d_step2`) exposed
// per-sample parallelism but required TWO encoder dispatches per pass.
// On large fixtures (≥ 7 MP) the extra encoder overhead (~50 µs ×
// 2 extra encoders per pass = 200-300 µs/decode) plus the cross-step
// device-memory RAW dependency eats the parallelism gains: DX 2544×3056
// regressed +1-8 ms end-to-end despite a 1.13× microbench speedup.
//
// The tiled variants do BOTH steps in a single kernel dispatch using
// threadgroup memory to stage step-1's even-output between the steps.
// Eliminates the cross-step kernel boundary AND keeps step-1 → step-2
// data on-chip (no device-memory round-trip).
//
// Threadgroup geometry (horizontal):
//   tg = (32 cols, 8 rows). Each thread computes one (even, odd) output
//   pair → 32×2 = 64 outputs per row × 8 rows = 512 outputs per tg.
//   Threadgroup memory: 8 rows × 33 evens × 4 bytes = 1056 B (right-halo
//   even computed by thread 31 to give thread 31's odd its eRight).
//
// Bit-exact equivalent of the scalar kernel by construction (same
// arithmetic, same symmetric boundary handling).

kernel void j2k_dwt_inverse_53_horizontal_int_tiled(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    // tg shape: 32 cols × 8 rows. Each thread computes 1 even + 1 odd
    // (2 output samples). Right-halo even per row (the 33rd) is computed
    // by thread.x == 31 so thread.x == 31's odd has its eRight on-chip.
    threadgroup int tg_even[8][33];

    uint row = gid.y;
    if (row >= height) return;

    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;
    uint lBase = row * halfWidth;
    uint hBase = row * halfWidthH;
    uint oBase = row * width;

    uint t = lid.x;                 // 0..31 within threadgroup row
    uint r = lid.y;                 // 0..7 within threadgroup
    uint tile_base_i = tgid.x * 32; // first even index in this tile

    // Edge case: halfWidthH == 0 → no step 2, just copy lowpass to evens.
    if (halfWidthH == 0) {
        uint i = tile_base_i + t;
        if (i < halfWidth) output[oBase + 2 * i] = lowpass[lBase + i];
        return;
    }

    // ----- Step 1 — compute thread t's even at i = tile_base_i + t -----
    {
        uint i = tile_base_i + t;
        if (i < halfWidth) {
            int dLeft = (i > 0)
                ? highpass[hBase + i - 1]
                : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            int e = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
            tg_even[r][t] = e;
            output[oBase + 2 * i] = e;
        }
    }

    // ----- Step 1 boundary — thread.x == 31 also computes the 33rd
    // even (i = tile_base_i + 32) so its step-2 has eRight on-chip.
    if (t == 31) {
        uint i = tile_base_i + 32;
        if (i < halfWidth) {
            int dLeft = (i > 0)
                ? highpass[hBase + i - 1]
                : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            int e = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
            tg_even[r][32] = e;
            // Don't write to device — the next tile's thread.x == 0
            // also computes it and writes (idempotent same value).
        } else {
            // Past the right edge: symmetric-boundary fallback used by
            // thread 31's step 2 when 2*(tile_base_i+31)+2 >= width.
            tg_even[r][32] = tg_even[r][31];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // ----- Step 2 — compute thread t's odd at i = tile_base_i + t -----
    uint i = tile_base_i + t;
    if (i < halfWidthH) {
        int eLeft = tg_even[r][t];
        int eRight = (2 * i + 2 < width)
            ? tg_even[r][t + 1]
            : tg_even[r][t];   // symmetric boundary
        output[oBase + 2 * i + 1] = highpass[hBase + i] + ((eLeft + eRight) >> 1);
    }
}

// MARK: - v10.3 Phase 2-2-tiled — Inverse 5/3 Int vertical, tiled
//
// Threadgroup geometry: 32 cols × 8 row-pairs. Each thread computes
// one (even-row, odd-row) output pair → 32 × 2 = 64 output rows per
// column × 8-tg-rows × tg.x columns. tg_even[8][33] holds the row-axis
// halo evens; thread (x, 7) computes the boundary 33rd even.
//
// Memory access pattern is strided (stride = width × 4 bytes). The
// 2D thread layout puts adjacent threads on adjacent columns → row-
// pass writes coalesce naturally; column reads have one cache line
// per thread but at least the SIMD group's 32 threads hit 32
// consecutive columns of the same row.
//
// Bit-exact equivalent of `j2k_dwt_inverse_53_vertical_int` by
// construction.

kernel void j2k_dwt_inverse_53_vertical_int_tiled(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    // tg shape: 32 cols × 8 row-pairs. Each thread computes 1 even-
    // row output + 1 odd-row output for its column. The +1 halo even
    // is computed by lid.y == 7 so lid.y == 7's odd has its eBot
    // on-chip.
    threadgroup int tg_even[33][32];

    uint col = gid.x;
    if (col >= width) return;

    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    uint t = lid.x;                 // 0..31 within tg's column dim
    uint r = lid.y;                 // 0..7 within tg's row-pair dim
    uint tile_base_i = tgid.y * 8;  // first even-row index in this tile

    // Edge case: halfHeightH == 0 → no step 2; copy lowpass rows.
    if (halfHeightH == 0) {
        uint i = tile_base_i + r;
        if (i < halfHeight) {
            output[(2 * i) * width + col] = lowpass[i * width + col];
        }
        return;
    }

    // ----- Step 1 — compute even-row output for (i = tile_base_i + r, col)
    {
        uint i = tile_base_i + r;
        if (i < halfHeight) {
            int dTop = (i > 0)
                ? highpass[(i - 1) * width + col]
                : highpass[col];
            int dBot = (i < halfHeightH)
                ? highpass[i * width + col]
                : highpass[(halfHeightH - 1) * width + col];
            int e = lowpass[i * width + col] - ((dTop + dBot + 2) >> 2);
            tg_even[r][t] = e;
            output[(2 * i) * width + col] = e;
        }
    }

    // Boundary even: lid.y == 7 also computes the 9th even (r = 8)
    // for the same column so r==7's odd has its eBot on-chip.
    if (r == 7) {
        uint i = tile_base_i + 8;
        if (i < halfHeight) {
            int dTop = (i > 0)
                ? highpass[(i - 1) * width + col]
                : highpass[col];
            int dBot = (i < halfHeightH)
                ? highpass[i * width + col]
                : highpass[(halfHeightH - 1) * width + col];
            int e = lowpass[i * width + col] - ((dTop + dBot + 2) >> 2);
            tg_even[8][t] = e;
        } else {
            tg_even[8][t] = tg_even[7][t];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // ----- Step 2 — compute odd-row output for (i = tile_base_i + r, col)
    uint i = tile_base_i + r;
    if (i < halfHeightH) {
        int eTop = tg_even[r][t];
        int eBot = (2 * i + 2 < height)
            ? tg_even[r + 1][t]
            : tg_even[r][t];   // symmetric boundary
        output[(2 * i + 1) * width + col] = highpass[i * width + col]
            + ((eTop + eBot) >> 1);
    }
}

// MARK: - v10.20-research Phase 2 — Inverse 5/3 Int tiled BATCHED kernels
//
// Bit-exact equivalent of `j2k_dwt_inverse_53_{horizontal,vertical}_int_tiled`
// extended along a third grid dimension (Z = slice index). One dispatch
// runs N parallel iDWTs — one threadgroup per (xTile, yTile, sliceIndex).
//
// Why: JP3D's slice-stack codec decodes N similar 2D slices in a row.
// Per-slice dispatch overhead × N slices > CPU iDWT total
// (V10_19_JP3D_GPU_IDWT_CLOSED.md). A batched dispatch amortises the
// overhead across the volume — one kernel launch for the whole tile's
// horizontal pass, one for the vertical pass.
//
// Buffer layout: each band (lowpass / highpass / output) is laid out
// linearly per slice. Slice `s`'s lowpass band starts at
// `lowpass[s * sliceStrideLowpass]` etc. Strides are passed as
// constants so the kernel doesn't need to recompute them.
//
// Threadgroup geometry is unchanged (32 × 8 for horizontal, 32 × 8
// for vertical). The Z dimension of the dispatch grid is N_slices;
// each threadgroup processes its (xTile, yTile, sliceIndex) tile.
// Threadgroup memory is per-threadgroup — no cross-slice contamination.
//
// Per-slice dimensions (width / height / lowpass-band-dim / highpass-
// band-dim) MUST be uniform across all N slices in a batch. JP3D
// slice-stack guarantees this — every slice in a JP3D tile shares
// `header.tileWidth × header.tileHeight`.

kernel void j2k_dwt_inverse_53_horizontal_int_tiled_batched(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    constant uint& sliceStrideLowpass [[buffer(5)]],
    constant uint& sliceStrideHighpass [[buffer(6)]],
    constant uint& sliceStrideOutput [[buffer(7)]],
    uint3 gid [[thread_position_in_grid]],
    uint3 lid [[thread_position_in_threadgroup]],
    uint3 tgid [[threadgroup_position_in_grid]]
) {
    threadgroup int tg_even[8][33];

    uint row = gid.y;
    if (row >= height) return;

    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;
    uint slice = tgid.z;

    // Per-slice band base offsets — point into this slice's portion
    // of each batched buffer.
    uint lSliceBase = slice * sliceStrideLowpass;
    uint hSliceBase = slice * sliceStrideHighpass;
    uint oSliceBase = slice * sliceStrideOutput;

    uint lBase = lSliceBase + row * halfWidth;
    uint hBase = hSliceBase + row * halfWidthH;
    uint oBase = oSliceBase + row * width;

    uint t = lid.x;
    uint r = lid.y;
    uint tile_base_i = tgid.x * 32;

    if (halfWidthH == 0) {
        uint i = tile_base_i + t;
        if (i < halfWidth) output[oBase + 2 * i] = lowpass[lBase + i];
        return;
    }

    // Step 1 — thread t's even
    {
        uint i = tile_base_i + t;
        if (i < halfWidth) {
            int dLeft = (i > 0)
                ? highpass[hBase + i - 1]
                : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            int e = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
            tg_even[r][t] = e;
            output[oBase + 2 * i] = e;
        }
    }

    // Step 1 boundary — t == 31 also computes the 33rd even
    if (t == 31) {
        uint i = tile_base_i + 32;
        if (i < halfWidth) {
            int dLeft = (i > 0)
                ? highpass[hBase + i - 1]
                : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            int e = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
            tg_even[r][32] = e;
        } else {
            tg_even[r][32] = tg_even[r][31];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Step 2 — thread t's odd
    uint i = tile_base_i + t;
    if (i < halfWidthH) {
        int eLeft = tg_even[r][t];
        int eRight = (2 * i + 2 < width)
            ? tg_even[r][t + 1]
            : tg_even[r][t];
        output[oBase + 2 * i + 1] = highpass[hBase + i] + ((eLeft + eRight) >> 1);
    }
}

kernel void j2k_dwt_inverse_53_vertical_int_tiled_batched(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    constant uint& sliceStrideLowpass [[buffer(5)]],
    constant uint& sliceStrideHighpass [[buffer(6)]],
    constant uint& sliceStrideOutput [[buffer(7)]],
    uint3 gid [[thread_position_in_grid]],
    uint3 lid [[thread_position_in_threadgroup]],
    uint3 tgid [[threadgroup_position_in_grid]]
) {
    threadgroup int tg_even[33][32];

    uint col = gid.x;
    if (col >= width) return;

    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;
    uint slice = tgid.z;

    uint lSliceBase = slice * sliceStrideLowpass;
    uint hSliceBase = slice * sliceStrideHighpass;
    uint oSliceBase = slice * sliceStrideOutput;

    uint t = lid.x;
    uint r = lid.y;
    uint tile_base_i = tgid.y * 8;

    if (halfHeightH == 0) {
        uint i = tile_base_i + r;
        if (i < halfHeight) {
            output[oSliceBase + (2 * i) * width + col] =
                lowpass[lSliceBase + i * width + col];
        }
        return;
    }

    // Step 1 — even-row output for (i = tile_base_i + r, col)
    {
        uint i = tile_base_i + r;
        if (i < halfHeight) {
            int dTop = (i > 0)
                ? highpass[hSliceBase + (i - 1) * width + col]
                : highpass[hSliceBase + col];
            int dBot = (i < halfHeightH)
                ? highpass[hSliceBase + i * width + col]
                : highpass[hSliceBase + (halfHeightH - 1) * width + col];
            int e = lowpass[lSliceBase + i * width + col] - ((dTop + dBot + 2) >> 2);
            tg_even[r][t] = e;
            output[oSliceBase + (2 * i) * width + col] = e;
        }
    }

    // Boundary — r == 7 also computes the 9th even
    if (r == 7) {
        uint i = tile_base_i + 8;
        if (i < halfHeight) {
            int dTop = (i > 0)
                ? highpass[hSliceBase + (i - 1) * width + col]
                : highpass[hSliceBase + col];
            int dBot = (i < halfHeightH)
                ? highpass[hSliceBase + i * width + col]
                : highpass[hSliceBase + (halfHeightH - 1) * width + col];
            int e = lowpass[lSliceBase + i * width + col] - ((dTop + dBot + 2) >> 2);
            tg_even[8][t] = e;
        } else {
            tg_even[8][t] = tg_even[7][t];
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Step 2 — odd-row output
    uint i = tile_base_i + r;
    if (i < halfHeightH) {
        int eTop = tg_even[r][t];
        int eBot = (2 * i + 2 < height)
            ? tg_even[r + 1][t]
            : tg_even[r][t];
        output[oSliceBase + (2 * i + 1) * width + col] =
            highpass[hSliceBase + i * width + col] + ((eTop + eBot) >> 1);
    }
}

// MARK: - v10.5 Phase 2-3-fused — Inverse 5/3 Int H+V fused-tile kernel
//
// The v10.3 Phase 2-2-tiled pair (`*_horizontal_int_tiled` +
// `*_vertical_int_tiled`) shipped default-on in v10.1.0 and already
// fuses step 1 + step 2 within each pass via threadgroup memory.
// But the H pass still writes its colLow/colHigh outputs to device
// memory, and the V pass reads them back — 2× full-image DRAM round-
// trip per IDWT level (134 MB at MG L1).
//
// This v10.5 probe collapses both passes into one kernel by holding
// the H-pass output in threadgroup memory across the V pass's lift.
// Bandwidth math:
//   - Current pair (per level at MG L1):
//       LL+HL read → colLow write     = 67 MB
//       LH+HH read → colHigh write    = 67 MB
//       colLow+colHigh read → output  = 134 MB
//                                Total ≈ 268 MB
//   - Fused (per level at MG L1):
//       LL+HL+LH+HH read → output     = 134 MB total
//   2× less DRAM traffic per level. Plus 3 → 1 kernel dispatch
//   reduction per level (saves 2 × ~80 µs = 160 µs encoder overhead
//   per level × 5 levels = 0.8 ms).
//
// Threadgroup geometry: (32, 10). Each tg covers 32 output cols ×
// 16 output rows = 512 output samples. The 10 lid.y dimension splits
// into:
//   r = 0       — top halo (H-pass only, no output written)
//   r ∈ [1..9)  — body row-pair (1 even-row output + 1 odd-row output)
//   r = 9       — bottom halo (H-pass only, no output written)
//
// Threadgroup memory: tg_lo[10][32] + tg_hi[10][32] = 2560 bytes (Int32),
// well under Apple Silicon's 32 KB / 64 KB tg memory budget.
//
// Halo handling:
//   - V-pass halo (top/bottom row): r=0 and r=9 compute one extra H row each.
//   - H-pass halo (left/right col): each H lift reads col t-1 or t+1
//     directly from device when at tile edge (uncoalesced cost is small —
//     2 cells × 32 rows per tg = 64 extra device reads).
//
// Bit-exact equivalent of the v10.3 Phase 2-2-tiled pair by construction
// — same arithmetic, same symmetric boundary handling. Verified by
// `V10_5_MetalIDWTInverse53FusedParityTests`.

kernel void j2k_dwt_inverse_53_fused_int_tiled(
    device const int* ll [[buffer(0)]],
    device const int* hl [[buffer(1)]],
    device const int* lh [[buffer(2)]],
    device const int* hh [[buffer(3)]],
    device int* output [[buffer(4)]],
    constant uint& width [[buffer(5)]],
    constant uint& height [[buffer(6)]],
    constant uint& llW [[buffer(7)]],
    constant uint& llH [[buffer(8)]],
    constant uint& halfHH [[buffer(9)]],
    uint2 lid [[thread_position_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]])
{
    threadgroup int tg_lo[10][32];  // H-pass output for LL+HL band, 10 input rows
    threadgroup int tg_hi[10][32];  // H-pass output for LH+HH band, 10 input rows

    uint t = lid.x;          // 0..31 — output col within tile
    uint r = lid.y;          // 0..9  — input row within tile (incl. halo at r=0, r=9)

    uint tile_col = tgid.x * 32;
    uint tile_row_lo = tgid.y * 8;   // first low-band input row in tile body

    // The 10 thread rows map to input rows [tile_row_lo - 1, tile_row_lo + 9):
    //   lid.y = 0     → halo row  (tile_row_lo - 1)
    //   lid.y = 1..8  → body rows (tile_row_lo .. tile_row_lo + 8)
    //   lid.y = 9     → halo row  (tile_row_lo + 8) (== "even[r+1]" for V step 2)
    int ir_signed = int(tile_row_lo) + int(r) - 1;

    uint out_col = tile_col + t;
    // NB: do NOT early-return at out_col >= width. Threads past the image
    // right edge must still populate their tg_lo / tg_hi cells (they may
    // be read by in-bounds neighbour threads in Stage B for the symmetric-
    // extension halo). Bound-check happens only at the output-write step.

    uint hlW = width - llW;       // = width / 2

    // ----- Phase 1: H lift for both bands ------------------------------------
    //
    // For each thread (t, r), compute one H-output cell in EACH of tg_lo / tg_hi.
    // The H lift on a row produces:
    //   even col output at t=0,2,4,...   from LL band lift
    //   odd col output at  t=1,3,5,...   from HL band lift (depends on even col)
    //
    // To respect data dependency (odd needs adjacent evens), we do:
    //   Stage A: each thread with t%2==0 computes its even cell
    //   threadgroup_barrier
    //   Stage B: each thread with t%2==1 computes its odd cell

    // Stage A — even cols (t == 0,2,4,...,30): compute LL-band lift
    if ((t & 1u) == 0u) {
        uint icol = (tile_col + t) >> 1;   // input col in LL/LH band space

        // Low band (LL+HL → tg_lo)
        if (ir_signed >= 0 && uint(ir_signed) < llH && icol < llW) {
            int dLeft, dRight;
            if (hlW == 0u) {
                dLeft = 0; dRight = 0;
            } else {
                uint il_left  = (icol > 0u) ? (icol - 1u) : 0u;
                uint il_right = (icol < hlW) ? icol : (hlW - 1u);
                dLeft  = hl[uint(ir_signed) * hlW + il_left];
                dRight = hl[uint(ir_signed) * hlW + il_right];
            }
            tg_lo[r][t] = (hlW == 0u)
                ? ll[uint(ir_signed) * llW + icol]
                : ll[uint(ir_signed) * llW + icol] - ((dLeft + dRight + 2) >> 2);
        } else {
            tg_lo[r][t] = 0;
        }

        // High band (LH+HH → tg_hi). LH/HH have halfHH rows.
        // The "high-band input row index" = ir_signed (same row index as low band).
        if (ir_signed >= 0 && uint(ir_signed) < halfHH && icol < llW) {
            int dLeft, dRight;
            if (hlW == 0u) {
                dLeft = 0; dRight = 0;
            } else {
                uint il_left  = (icol > 0u) ? (icol - 1u) : 0u;
                uint il_right = (icol < hlW) ? icol : (hlW - 1u);
                dLeft  = hh[uint(ir_signed) * hlW + il_left];
                dRight = hh[uint(ir_signed) * hlW + il_right];
            }
            tg_hi[r][t] = (hlW == 0u)
                ? lh[uint(ir_signed) * llW + icol]
                : lh[uint(ir_signed) * llW + icol] - ((dLeft + dRight + 2) >> 2);
        } else {
            tg_hi[r][t] = 0;
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Stage B — odd cols (t == 1,3,5,...,31): compute HL-band lift
    if ((t & 1u) == 1u) {
        uint icol = (tile_col + t) >> 1;   // input col in HL/HH band space

        // eRight selection (shared between low and high band):
        //   - If next output col (out_col + 1) is past image right edge:
        //         symmetric ext → eRight = eLeft
        //   - Else if next output col is within this tile (t < 31u, t+1 even
        //     col already computed in Stage A):
        //         eRight = tg_{lo,hi}[r][t + 1]
        //   - Else (t == 31u, next col is in the next tile):
        //         recompute the next tile's first even directly from device
        //         (cross-tile read — small extra cost at tile boundary)
        uint next_out_col = tile_col + t + 1u;

        // Low band (HL → tg_lo)
        if (ir_signed >= 0 && uint(ir_signed) < llH && icol < hlW) {
            int eLeft  = tg_lo[r][t - 1];
            int eRight;
            if (next_out_col >= width) {
                eRight = eLeft;   // symmetric ext past image right
            } else if (t < 31u) {
                eRight = tg_lo[r][t + 1];
            } else {
                // Cross-tile: recompute next tile's t=0 even.
                uint icol_n = icol + 1u;
                if (icol_n < llW) {
                    int dL, dR;
                    if (hlW == 0u) {
                        dL = 0; dR = 0;
                    } else {
                        uint il_left  = (icol_n > 0u) ? (icol_n - 1u) : 0u;
                        uint il_right = (icol_n < hlW) ? icol_n : (hlW - 1u);
                        dL = hl[uint(ir_signed) * hlW + il_left];
                        dR = hl[uint(ir_signed) * hlW + il_right];
                    }
                    eRight = (hlW == 0u)
                        ? ll[uint(ir_signed) * llW + icol_n]
                        : ll[uint(ir_signed) * llW + icol_n] - ((dL + dR + 2) >> 2);
                } else {
                    eRight = eLeft;
                }
            }
            tg_lo[r][t] = hl[uint(ir_signed) * hlW + icol] + ((eLeft + eRight) >> 1);
        } else {
            tg_lo[r][t] = 0;
        }

        // High band (HH → tg_hi)
        if (ir_signed >= 0 && uint(ir_signed) < halfHH && icol < hlW) {
            int eLeft  = tg_hi[r][t - 1];
            int eRight;
            if (next_out_col >= width) {
                eRight = eLeft;
            } else if (t < 31u) {
                eRight = tg_hi[r][t + 1];
            } else {
                uint icol_n = icol + 1u;
                if (icol_n < llW) {
                    int dL, dR;
                    if (hlW == 0u) {
                        dL = 0; dR = 0;
                    } else {
                        uint il_left  = (icol_n > 0u) ? (icol_n - 1u) : 0u;
                        uint il_right = (icol_n < hlW) ? icol_n : (hlW - 1u);
                        dL = hh[uint(ir_signed) * hlW + il_left];
                        dR = hh[uint(ir_signed) * hlW + il_right];
                    }
                    eRight = (hlW == 0u)
                        ? lh[uint(ir_signed) * llW + icol_n]
                        : lh[uint(ir_signed) * llW + icol_n] - ((dL + dR + 2) >> 2);
                } else {
                    eRight = eLeft;
                }
            }
            tg_hi[r][t] = hh[uint(ir_signed) * hlW + icol] + ((eLeft + eRight) >> 1);
        } else {
            tg_hi[r][t] = 0;
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // ----- Phase 2: V lift across rows for output col `out_col` --------------
    //
    // After Phase 1, tg_lo[r][t] holds the H-output of LL+HL band at
    // input row (tile_row_lo + r - 1) and output col (tile_col + t).
    // tg_hi[r][t] holds the H-output of LH+HH band at the same row+col.
    //
    // V lift step 1 — compute even output row at output index 2*input_row_idx:
    //   even_out[2*i] = tg_lo[i] - ((tg_hi[i-1] + tg_hi[i] + 2) >> 2)
    //
    // V lift step 2 — compute odd output row at output index 2*input_row_idx + 1:
    //   odd_out[2*i+1] = tg_hi[i] + ((even_out[2*i] + even_out[2*(i+1)]) >> 1)

    // Each thread with r in [1..9) emits one even output row.
    // Each thread with r in [1..9) also emits one odd output row.
    if (r >= 1u && r <= 8u && out_col < width) {
        // input row index in low band = tile_row_lo + r - 1
        uint i_lo = tile_row_lo + r - 1u;
        uint even_out_row = 2u * i_lo;

        if (even_out_row < height && uint(ir_signed) < llH) {
            // V step 1 — even row
            int dTop, dBot;
            int hp_top_row_idx = int(r) - 1;  // tg row index for prev odd in high band
            int hp_cur_row_idx = int(r);

            // If we're at the global top (i_lo == 0), dTop uses hp at row 0
            // (symmetric: hp[-1] = hp[0]).
            if (i_lo == 0u) {
                dTop = tg_hi[1][t];    // tg_hi[r=1] corresponds to i=0 (since r=0 is i=-1 halo)
            } else {
                dTop = tg_hi[hp_top_row_idx][t];
            }

            // If high-band row index >= halfHH, fall back to symmetric (hp[halfHH] = hp[halfHH-1])
            if (i_lo < halfHH) {
                dBot = tg_hi[hp_cur_row_idx][t];
            } else if (halfHH > 0u) {
                // i_lo == halfHH (== llH - 1 typically for odd height): use last hp row
                dBot = tg_hi[hp_top_row_idx][t];
            } else {
                dBot = 0;
            }

            int even_val = (halfHH == 0u)
                ? tg_lo[r][t]
                : tg_lo[r][t] - ((dTop + dBot + 2) >> 2);

            output[even_out_row * width + out_col] = even_val;

            // Stash even_val back into tg_lo for step 2's read by another thread.
            // (tg_lo[r][t] is no longer needed in the original form after this write.)
            tg_lo[r][t] = even_val;
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (r >= 1u && r <= 8u && out_col < width) {
        uint i_lo = tile_row_lo + r - 1u;
        uint odd_out_row = 2u * i_lo + 1u;
        // i_hi (high-band input row idx) = i_lo when both bands sized the same
        // Odd output exists only for i_lo < halfHH

        if (odd_out_row < height && i_lo < halfHH) {
            // V step 2 — odd row
            int eTop = tg_lo[r][t];               // even output at row 2*i_lo
            int eBot;

            uint i_next = i_lo + 1u;
            uint even_next_row = 2u * i_next;
            if (even_next_row < height && i_next < llH) {
                // Need the next even output (which is tg_lo[r+1][t] OR for
                // r==8, the halo row r=9 — but r=9 only computed its H-pass,
                // not its V-step-1 even output). Special-case r==8: compute
                // the next even output inline using tg_lo[9][t] and tg_hi.
                if (r < 8u) {
                    eBot = tg_lo[r + 1u][t];   // already-computed even at next input row
                } else {
                    // r == 8 → next is r=9 (halo). Compute the even output
                    // for input row i_next = tile_row_lo + 8 = i_lo + 1.
                    // halo row tg_hi[9][t] holds hp at i_next, tg_hi[r=8][t] = hp at i_lo.
                    int dT = tg_hi[8][t];   // hp at i_lo
                    int dB;
                    if (i_next < halfHH) {
                        dB = tg_hi[9][t];   // hp at i_next
                    } else if (halfHH > 0u) {
                        dB = tg_hi[8][t];
                    } else {
                        dB = 0;
                    }
                    eBot = (halfHH == 0u)
                        ? tg_lo[9][t]
                        : tg_lo[9][t] - ((dT + dB + 2) >> 2);
                }
            } else {
                // Past the bottom: symmetric extension → eBot = eTop.
                eBot = eTop;
            }

            int odd_val = tg_hi[r][t] + ((eTop + eBot) >> 1);
            output[odd_out_row * width + out_col] = odd_val;
        }
    }
}

// MARK: - Forward ICT (Irreversible Colour Transform)

kernel void j2k_ict_forward(
    device const float* r [[buffer(0)]],
    device const float* g [[buffer(1)]],
    device const float* b [[buffer(2)]],
    device float* y [[buffer(3)]],
    device float* cb [[buffer(4)]],
    device float* cr [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float rv = r[gid];
    float gv = g[gid];
    float bv = b[gid];

    y[gid]  =  0.299f   * rv + 0.587f   * gv + 0.114f   * bv;
    cb[gid] = -0.16875f * rv - 0.33126f * gv + 0.5f     * bv;
    cr[gid] =  0.5f     * rv - 0.41869f * gv - 0.08131f * bv;
}

// MARK: - Inverse ICT (Irreversible Colour Transform)

kernel void j2k_ict_inverse(
    device const float* y [[buffer(0)]],
    device const float* cb [[buffer(1)]],
    device const float* cr [[buffer(2)]],
    device float* r [[buffer(3)]],
    device float* g [[buffer(4)]],
    device float* b [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float yv  = y[gid];
    float cbv = cb[gid];
    float crv = cr[gid];

    r[gid] = yv + 1.402f   * crv;
    g[gid] = yv - 0.34413f * cbv - 0.71414f * crv;
    b[gid] = yv + 1.772f   * cbv;
}

// MARK: - Forward RCT (Reversible Colour Transform)

kernel void j2k_rct_forward(
    device const int* r [[buffer(0)]],
    device const int* g [[buffer(1)]],
    device const int* b [[buffer(2)]],
    device int* y [[buffer(3)]],
    device int* u [[buffer(4)]],
    device int* v [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    int rv = r[gid];
    int gv = g[gid];
    int bv = b[gid];

    y[gid] = (rv + 2 * gv + bv) >> 2;
    u[gid] = bv - gv;
    v[gid] = rv - gv;
}

// MARK: - Inverse RCT (Reversible Colour Transform)

kernel void j2k_rct_inverse(
    device const int* y [[buffer(0)]],
    device const int* u [[buffer(1)]],
    device const int* v [[buffer(2)]],
    device int* r [[buffer(3)]],
    device int* g [[buffer(4)]],
    device int* b [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    int yv = y[gid];
    int uv = u[gid];
    int vv = v[gid];

    g[gid] = yv - ((uv + vv) >> 2);
    r[gid] = vv + g[gid];
    b[gid] = uv + g[gid];
}

// MARK: - MCT Matrix Multiply

kernel void j2k_mct_matrix_multiply(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    device const float* matrix [[buffer(2)]],
    constant uint& componentCount [[buffer(3)]],
    constant uint& sampleCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= sampleCount) return;

    for (uint c = 0; c < componentCount; c++) {
        float sum = 0.0f;
        for (uint k = 0; k < componentCount; k++) {
            sum += matrix[c * componentCount + k] * input[k * sampleCount + gid];
        }
        output[c * sampleCount + gid] = sum;
    }
}

// MARK: - Scalar Quantization

kernel void j2k_quantize(
    device const float* input [[buffer(0)]],
    device int* output [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant float& deadzone [[buffer(3)]],
    constant uint& count [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float val = input[gid];
    float sign = (val >= 0.0f) ? 1.0f : -1.0f;
    float absVal = abs(val);

    if (absVal < deadzone * stepSize) {
        output[gid] = 0;
    } else {
        output[gid] = int(sign * floor(absVal / stepSize));
    }
}

// MARK: - Scalar Dequantization

kernel void j2k_dequantize(
    device const int* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    int val = input[gid];
    if (val == 0) {
        output[gid] = 0.0f;
    } else {
        float sign = (val > 0) ? 1.0f : -1.0f;
        output[gid] = sign * (float(abs(val)) + 0.5f) * stepSize;
    }
}

// MARK: - Forward Arbitrary Wavelet (Horizontal) - Generic Convolution

kernel void j2k_dwt_forward_arbitrary_horizontal(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    device const float* analysisLow [[buffer(3)]],
    device const float* analysisHigh [[buffer(4)]],
    constant uint& width [[buffer(5)]],
    constant uint& height [[buffer(6)]],
    constant uint& filterLowLen [[buffer(7)]],
    constant uint& filterHighLen [[buffer(8)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfLow = filterLowLen / 2;
    uint halfHigh = filterHighLen / 2;

    // Lowpass: downsample by 2, convolve with analysis lowpass filter
    for (uint i = 0; i < halfWidth; i++) {
        float sum = 0.0f;
        int center = int(2 * i);
        for (uint k = 0; k < filterLowLen; k++) {
            int srcIdx = center + int(k) - int(halfLow);
            // Symmetric boundary extension
            if (srcIdx < 0) srcIdx = -srcIdx;
            if (srcIdx >= int(width)) srcIdx = 2 * int(width) - srcIdx - 2;
            sum += input[row * width + uint(srcIdx)] * analysisLow[k];
        }
        lowpass[row * halfWidth + i] = sum;
    }

    // Highpass: downsample by 2, convolve with analysis highpass filter
    uint halfWidthH = width / 2;
    for (uint i = 0; i < halfWidthH; i++) {
        float sum = 0.0f;
        int center = int(2 * i + 1);
        for (uint k = 0; k < filterHighLen; k++) {
            int srcIdx = center + int(k) - int(halfHigh);
            if (srcIdx < 0) srcIdx = -srcIdx;
            if (srcIdx >= int(width)) srcIdx = 2 * int(width) - srcIdx - 2;
            sum += input[row * width + uint(srcIdx)] * analysisHigh[k];
        }
        highpass[row * halfWidthH + i] = sum;
    }
}

// MARK: - Inverse Arbitrary Wavelet (Horizontal) - Generic Convolution

kernel void j2k_dwt_inverse_arbitrary_horizontal(
    device const float* lowpass [[buffer(0)]],
    device const float* highpass [[buffer(1)]],
    device float* output [[buffer(2)]],
    device const float* synthesisLow [[buffer(3)]],
    device const float* synthesisHigh [[buffer(4)]],
    constant uint& width [[buffer(5)]],
    constant uint& height [[buffer(6)]],
    constant uint& filterLowLen [[buffer(7)]],
    constant uint& filterHighLen [[buffer(8)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;
    uint halfWidthH = width / 2;

    // Upsample and convolve: interleave lowpass and highpass contributions
    for (uint n = 0; n < width; n++) {
        float sum = 0.0f;
        // Lowpass contribution (upsampled at even positions)
        for (uint k = 0; k < filterLowLen; k++) {
            int idx = int(n) - int(k);
            if (idx >= 0 && idx % 2 == 0) {
                uint j = uint(idx) / 2;
                if (j < halfWidth) {
                    sum += lowpass[row * halfWidth + j] * synthesisLow[k];
                }
            }
        }
        // Highpass contribution (upsampled at odd positions)
        for (uint k = 0; k < filterHighLen; k++) {
            int idx = int(n) - int(k);
            if (idx >= 0 && (idx % 2 == 1)) {
                uint j = uint(idx) / 2;
                if (j < halfWidthH) {
                    sum += highpass[row * halfWidthH + j] * synthesisHigh[k];
                }
            }
        }
        output[row * width + n] = sum;
    }
}

// MARK: - Forward Arbitrary Wavelet (Vertical) - Generic Convolution

kernel void j2k_dwt_forward_arbitrary_vertical(
    device const float* input [[buffer(0)]],
    device float* lowpass [[buffer(1)]],
    device float* highpass [[buffer(2)]],
    device const float* analysisLow [[buffer(3)]],
    device const float* analysisHigh [[buffer(4)]],
    constant uint& width [[buffer(5)]],
    constant uint& height [[buffer(6)]],
    constant uint& filterLowLen [[buffer(7)]],
    constant uint& filterHighLen [[buffer(8)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfLow = filterLowLen / 2;
    uint halfHigh = filterHighLen / 2;

    // Lowpass: downsample by 2, convolve vertically
    for (uint i = 0; i < halfHeight; i++) {
        float sum = 0.0f;
        int center = int(2 * i);
        for (uint k = 0; k < filterLowLen; k++) {
            int srcRow = center + int(k) - int(halfLow);
            if (srcRow < 0) srcRow = -srcRow;
            if (srcRow >= int(height)) srcRow = 2 * int(height) - srcRow - 2;
            sum += input[uint(srcRow) * width + col] * analysisLow[k];
        }
        lowpass[i * width + col] = sum;
    }

    // Highpass
    uint halfHeightH = height / 2;
    for (uint i = 0; i < halfHeightH; i++) {
        float sum = 0.0f;
        int center = int(2 * i + 1);
        for (uint k = 0; k < filterHighLen; k++) {
            int srcRow = center + int(k) - int(halfHigh);
            if (srcRow < 0) srcRow = -srcRow;
            if (srcRow >= int(height)) srcRow = 2 * int(height) - srcRow - 2;
            sum += input[uint(srcRow) * width + col] * analysisHigh[k];
        }
        highpass[i * width + col] = sum;
    }
}

// MARK: - Inverse Arbitrary Wavelet (Vertical) - Generic Convolution

kernel void j2k_dwt_inverse_arbitrary_vertical(
    device const float* lowpass [[buffer(0)]],
    device const float* highpass [[buffer(1)]],
    device float* output [[buffer(2)]],
    device const float* synthesisLow [[buffer(3)]],
    device const float* synthesisHigh [[buffer(4)]],
    constant uint& width [[buffer(5)]],
    constant uint& height [[buffer(6)]],
    constant uint& filterLowLen [[buffer(7)]],
    constant uint& filterHighLen [[buffer(8)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;
    uint halfHeightH = height / 2;

    for (uint n = 0; n < height; n++) {
        float sum = 0.0f;
        for (uint k = 0; k < filterLowLen; k++) {
            int idx = int(n) - int(k);
            if (idx >= 0 && idx % 2 == 0) {
                uint j = uint(idx) / 2;
                if (j < halfHeight) {
                    sum += lowpass[j * width + col] * synthesisLow[k];
                }
            }
        }
        for (uint k = 0; k < filterHighLen; k++) {
            int idx = int(n) - int(k);
            if (idx >= 0 && (idx % 2 == 1)) {
                uint j = uint(idx) / 2;
                if (j < halfHeightH) {
                    sum += highpass[j * width + col] * synthesisHigh[k];
                }
            }
        }
        output[n * width + col] = sum;
    }
}

// MARK: - Forward Lifting Scheme DWT (Horizontal)

kernel void j2k_dwt_forward_lifting_horizontal(
    device float* data [[buffer(0)]],
    device const float* liftingCoeffs [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant uint& numSteps [[buffer(4)]],
    constant float& finalScaleL [[buffer(5)]],
    constant float& finalScaleH [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;

    // Apply lifting steps in-place
    // Even indices = lowpass, Odd indices = highpass
    for (uint step = 0; step < numSteps; step++) {
        float coeff = liftingCoeffs[step];
        bool updateOdd = (step % 2 == 0); // Predict then Update alternation

        if (updateOdd) {
            // Update odd (highpass) samples using even (lowpass) neighbors
            for (uint i = 0; i < width / 2; i++) {
                uint oddIdx = row * width + 2 * i + 1;
                uint leftEven = row * width + 2 * i;
                uint rightEven = (2 * i + 2 < width)
                    ? row * width + 2 * i + 2
                    : row * width + 2 * i;
                data[oddIdx] += coeff * (data[leftEven] + data[rightEven]);
            }
        } else {
            // Update even (lowpass) samples using odd (highpass) neighbors
            for (uint i = 0; i < halfWidth; i++) {
                uint evenIdx = row * width + 2 * i;
                uint leftOdd = (i > 0)
                    ? row * width + 2 * i - 1
                    : row * width + 1;
                uint rightOdd = (2 * i + 1 < width)
                    ? row * width + 2 * i + 1
                    : row * width + width - 2;
                data[evenIdx] += coeff * (data[leftOdd] + data[rightOdd]);
            }
        }
    }

    // Apply final scaling
    for (uint i = 0; i < halfWidth; i++) {
        data[row * width + 2 * i] *= finalScaleL;
    }
    for (uint i = 0; i < width / 2; i++) {
        data[row * width + 2 * i + 1] *= finalScaleH;
    }
}

// MARK: - Inverse Lifting Scheme DWT (Horizontal)

kernel void j2k_dwt_inverse_lifting_horizontal(
    device float* data [[buffer(0)]],
    device const float* liftingCoeffs [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant uint& numSteps [[buffer(4)]],
    constant float& finalScaleL [[buffer(5)]],
    constant float& finalScaleH [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    uint halfWidth = (width + 1) / 2;

    // Undo final scaling
    for (uint i = 0; i < halfWidth; i++) {
        data[row * width + 2 * i] /= finalScaleL;
    }
    for (uint i = 0; i < width / 2; i++) {
        data[row * width + 2 * i + 1] /= finalScaleH;
    }

    // Apply lifting steps in reverse order with negated coefficients
    for (int step = int(numSteps) - 1; step >= 0; step--) {
        float coeff = -liftingCoeffs[step];
        bool updateOdd = (step % 2 == 0);

        if (updateOdd) {
            for (uint i = 0; i < width / 2; i++) {
                uint oddIdx = row * width + 2 * i + 1;
                uint leftEven = row * width + 2 * i;
                uint rightEven = (2 * i + 2 < width)
                    ? row * width + 2 * i + 2
                    : row * width + 2 * i;
                data[oddIdx] += coeff * (data[leftEven] + data[rightEven]);
            }
        } else {
            for (uint i = 0; i < halfWidth; i++) {
                uint evenIdx = row * width + 2 * i;
                uint leftOdd = (i > 0)
                    ? row * width + 2 * i - 1
                    : row * width + 1;
                uint rightOdd = (2 * i + 1 < width)
                    ? row * width + 2 * i + 1
                    : row * width + width - 2;
                data[evenIdx] += coeff * (data[leftOdd] + data[rightOdd]);
            }
        }
    }
}

// MARK: - Forward Lifting Scheme DWT (Vertical)

kernel void j2k_dwt_forward_lifting_vertical(
    device float* data [[buffer(0)]],
    device const float* liftingCoeffs [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant uint& numSteps [[buffer(4)]],
    constant float& finalScaleL [[buffer(5)]],
    constant float& finalScaleH [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;

    for (uint step = 0; step < numSteps; step++) {
        float coeff = liftingCoeffs[step];
        bool updateOdd = (step % 2 == 0);

        if (updateOdd) {
            for (uint i = 0; i < height / 2; i++) {
                uint oddIdx = (2 * i + 1) * width + col;
                uint topEven = (2 * i) * width + col;
                uint botEven = (2 * i + 2 < height)
                    ? (2 * i + 2) * width + col
                    : (2 * i) * width + col;
                data[oddIdx] += coeff * (data[topEven] + data[botEven]);
            }
        } else {
            for (uint i = 0; i < halfHeight; i++) {
                uint evenIdx = (2 * i) * width + col;
                uint topOdd = (i > 0)
                    ? (2 * i - 1) * width + col
                    : width + col;
                uint botOdd = (2 * i + 1 < height)
                    ? (2 * i + 1) * width + col
                    : (height - 2) * width + col;
                data[evenIdx] += coeff * (data[topOdd] + data[botOdd]);
            }
        }
    }

    for (uint i = 0; i < halfHeight; i++) {
        data[(2 * i) * width + col] *= finalScaleL;
    }
    for (uint i = 0; i < height / 2; i++) {
        data[(2 * i + 1) * width + col] *= finalScaleH;
    }
}

// MARK: - Inverse Lifting Scheme DWT (Vertical)

kernel void j2k_dwt_inverse_lifting_vertical(
    device float* data [[buffer(0)]],
    device const float* liftingCoeffs [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant uint& numSteps [[buffer(4)]],
    constant float& finalScaleL [[buffer(5)]],
    constant float& finalScaleH [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    uint halfHeight = (height + 1) / 2;

    // Undo final scaling
    for (uint i = 0; i < halfHeight; i++) {
        data[(2 * i) * width + col] /= finalScaleL;
    }
    for (uint i = 0; i < height / 2; i++) {
        data[(2 * i + 1) * width + col] /= finalScaleH;
    }

    for (int step = int(numSteps) - 1; step >= 0; step--) {
        float coeff = -liftingCoeffs[step];
        bool updateOdd = (step % 2 == 0);

        if (updateOdd) {
            for (uint i = 0; i < height / 2; i++) {
                uint oddIdx = (2 * i + 1) * width + col;
                uint topEven = (2 * i) * width + col;
                uint botEven = (2 * i + 2 < height)
                    ? (2 * i + 2) * width + col
                    : (2 * i) * width + col;
                data[oddIdx] += coeff * (data[topEven] + data[botEven]);
            }
        } else {
            for (uint i = 0; i < halfHeight; i++) {
                uint evenIdx = (2 * i) * width + col;
                uint topOdd = (i > 0)
                    ? (2 * i - 1) * width + col
                    : width + col;
                uint botOdd = (2 * i + 1 < height)
                    ? (2 * i + 1) * width + col
                    : (height - 2) * width + col;
                data[evenIdx] += coeff * (data[topOdd] + data[botOdd]);
            }
        }
    }
}

// MARK: - Parametric Non-Linear Transform

kernel void j2k_nlt_parametric(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    constant uint& transformType [[buffer(3)]],
    constant float& param1 [[buffer(4)]],
    constant float& param2 [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float val = input[gid];

    // transformType: 0=gamma, 1=log, 2=exp
    if (transformType == 0) {
        // Gamma correction: output = sign(val) * |val|^param1
        float sign = (val >= 0.0f) ? 1.0f : -1.0f;
        output[gid] = sign * pow(abs(val), param1);
    } else if (transformType == 1) {
        // Logarithmic: output = param1 * log(1 + param2 * |val|) * sign(val)
        float sign = (val >= 0.0f) ? 1.0f : -1.0f;
        output[gid] = sign * param1 * log(1.0f + param2 * abs(val));
    } else {
        // Exponential: output = param1 * (exp(param2 * |val|) - 1) * sign(val)
        float sign = (val >= 0.0f) ? 1.0f : -1.0f;
        output[gid] = sign * param1 * (exp(param2 * abs(val)) - 1.0f);
    }
}

// MARK: - LUT-Based Non-Linear Transform

kernel void j2k_nlt_lut(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    device const float* lut [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    constant uint& lutSize [[buffer(4)]],
    constant float& inputMin [[buffer(5)]],
    constant float& inputMax [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float val = input[gid];
    float range = inputMax - inputMin;
    if (range <= 0.0f) {
        output[gid] = lut[0];
        return;
    }

    // Normalise to [0, lutSize-1]
    float normalized = (val - inputMin) / range * float(lutSize - 1);
    normalized = clamp(normalized, 0.0f, float(lutSize - 1));

    // Linear interpolation
    uint idx0 = uint(normalized);
    uint idx1 = min(idx0 + 1, lutSize - 1);
    float frac = normalized - float(idx0);

    output[gid] = lut[idx0] * (1.0f - frac) + lut[idx1] * frac;
}

// MARK: - Optimised 3×3 MCT Matrix Multiply

kernel void j2k_mct_matrix_multiply_3x3(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant float* matrix [[buffer(2)]],
    constant uint& sampleCount [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= sampleCount) return;

    float c0 = input[gid];
    float c1 = input[sampleCount + gid];
    float c2 = input[2 * sampleCount + gid];

    output[gid]                  = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2;
    output[sampleCount + gid]    = matrix[3] * c0 + matrix[4] * c1 + matrix[5] * c2;
    output[2 * sampleCount + gid] = matrix[6] * c0 + matrix[7] * c1 + matrix[8] * c2;
}

// MARK: - Optimised 4×4 MCT Matrix Multiply

kernel void j2k_mct_matrix_multiply_4x4(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant float* matrix [[buffer(2)]],
    constant uint& sampleCount [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= sampleCount) return;

    float c0 = input[gid];
    float c1 = input[sampleCount + gid];
    float c2 = input[2 * sampleCount + gid];
    float c3 = input[3 * sampleCount + gid];

    output[gid]                  = matrix[0]  * c0 + matrix[1]  * c1 + matrix[2]  * c2 + matrix[3]  * c3;
    output[sampleCount + gid]    = matrix[4]  * c0 + matrix[5]  * c1 + matrix[6]  * c2 + matrix[7]  * c3;
    output[2 * sampleCount + gid] = matrix[8]  * c0 + matrix[9]  * c1 + matrix[10] * c2 + matrix[11] * c3;
    output[3 * sampleCount + gid] = matrix[12] * c0 + matrix[13] * c1 + matrix[14] * c2 + matrix[15] * c3;
}

// MARK: - Fused Colour Transform + MCT

kernel void j2k_color_mct_fused(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant float* colorMatrix [[buffer(2)]],
    constant float* mctMatrix [[buffer(3)]],
    constant uint& componentCount [[buffer(4)]],
    constant uint& sampleCount [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= sampleCount) return;

    // Apply colour transform then MCT in a single pass
    // First: colour transform
    float temp[16]; // Max 16 components
    for (uint c = 0; c < componentCount && c < 16; c++) {
        float sum = 0.0f;
        for (uint k = 0; k < componentCount; k++) {
            sum += colorMatrix[c * componentCount + k] * input[k * sampleCount + gid];
        }
        temp[c] = sum;
    }

    // Second: MCT
    for (uint c = 0; c < componentCount && c < 16; c++) {
        float sum = 0.0f;
        for (uint k = 0; k < componentCount; k++) {
            sum += mctMatrix[c * componentCount + k] * temp[k];
        }
        output[c * sampleCount + gid] = sum;
    }
}

// MARK: - Perceptual Quantizer (PQ) - SMPTE ST 2084

kernel void j2k_nlt_pq(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    constant uint& inverse [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    // PQ constants (SMPTE ST 2084)
    const float m1 = 0.1593017578125f;
    const float m2 = 78.84375f;
    const float c1 = 0.8359375f;
    const float c2 = 18.8515625f;
    const float c3 = 18.6875f;

    float val = input[gid];

    if (inverse == 0) {
        // Forward PQ: linear to PQ
        float y = clamp(val, 0.0f, 1.0f);
        float ym1 = pow(y, m1);
        output[gid] = pow((c1 + c2 * ym1) / (1.0f + c3 * ym1), m2);
    } else {
        // Inverse PQ: PQ to linear
        float n = clamp(val, 0.0f, 1.0f);
        float nm2 = pow(n, 1.0f / m2);
        float num = max(nm2 - c1, 0.0f);
        float den = c2 - c3 * nm2;
        output[gid] = pow(num / max(den, 1e-10f), 1.0f / m1);
    }
}

// MARK: - Hybrid Log-Gamma (HLG) - ITU-R BT.2100

kernel void j2k_nlt_hlg(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    constant uint& inverse [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    // HLG constants
    const float a = 0.17883277f;
    const float b = 0.28466892f;  // 1 - 4*a
    const float c = 0.55991073f;  // 0.5 - a*ln(4*a)

    float val = input[gid];

    if (inverse == 0) {
        // Forward HLG: linear to HLG
        float e = clamp(val, 0.0f, 1.0f);
        if (e <= 1.0f / 12.0f) {
            output[gid] = sqrt(3.0f * e);
        } else {
            output[gid] = a * log(12.0f * e - b) + c;
        }
    } else {
        // Inverse HLG: HLG to linear
        float ep = clamp(val, 0.0f, 1.0f);
        if (ep <= 0.5f) {
            output[gid] = ep * ep / 3.0f;
        } else {
            output[gid] = (exp((ep - c) / a) + b) / 12.0f;
        }
    }
}

// MARK: - Region of Interest (ROI) Shaders

// Generate ROI mask from rectangular bounds
kernel void j2k_roi_mask_generate(
    device bool* mask [[buffer(0)]],
    constant uint& width [[buffer(1)]],
    constant uint& height [[buffer(2)]],
    constant uint& roiX [[buffer(3)]],
    constant uint& roiY [[buffer(4)]],
    constant uint& roiWidth [[buffer(5)]],
    constant uint& roiHeight [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width || gid.y >= height) return;

    uint x = gid.x;
    uint y = gid.y;

    // Check if pixel is inside ROI rectangle
    bool insideX = (x >= roiX) && (x < roiX + roiWidth);
    bool insideY = (y >= roiY) && (y < roiY + roiHeight);

    mask[y * width + x] = insideX && insideY;
}

// Apply MaxShift coefficient scaling for ROI
kernel void j2k_roi_coefficient_scale(
    device const int* input [[buffer(0)]],
    device const bool* mask [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    constant uint& shift [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width || gid.y >= height) return;

    uint idx = gid.y * width + gid.x;
    int coeff = input[idx];

    // Apply bit-shift only if mask is set
    if (mask[idx]) {
        // Preserve sign and shift magnitude
        if (coeff >= 0) {
            output[idx] = coeff << shift;
        } else {
            output[idx] = -((-coeff) << shift);
        }
    } else {
        output[idx] = coeff;
    }
}

// Blend multiple ROI masks with priority
kernel void j2k_roi_mask_blend(
    device const bool* mask1 [[buffer(0)]],
    device const bool* mask2 [[buffer(1)]],
    device const uint* priority1 [[buffer(2)]],
    device const uint* priority2 [[buffer(3)]],
    device bool* output [[buffer(4)]],
    device uint* outputPriority [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    bool m1 = mask1[gid];
    bool m2 = mask2[gid];
    uint p1 = priority1[0];
    uint p2 = priority2[0];

    // Higher priority wins, or combine if equal
    if (m1 && m2) {
        if (p1 >= p2) {
            output[gid] = true;
            outputPriority[gid] = p1;
        } else {
            output[gid] = true;
            outputPriority[gid] = p2;
        }
    } else if (m1) {
        output[gid] = true;
        outputPriority[gid] = p1;
    } else if (m2) {
        output[gid] = true;
        outputPriority[gid] = p2;
    } else {
        output[gid] = false;
        outputPriority[gid] = 0;
    }
}

// Apply feathering/smooth transitions to ROI boundaries
kernel void j2k_roi_feathering(
    device const bool* mask [[buffer(0)]],
    device float* scalingMap [[buffer(1)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant float& featherWidth [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width || gid.y >= height) return;

    uint idx = gid.y * width + gid.x;

    // If inside ROI, full scaling
    if (mask[idx]) {
        scalingMap[idx] = 1.0f;
        return;
    }

    // Find minimum distance to ROI boundary
    float minDist = featherWidth + 1.0f;
    int searchRadius = (int)ceil(featherWidth);

    for (int dy = -searchRadius; dy <= searchRadius; dy++) {
        for (int dx = -searchRadius; dx <= searchRadius; dx++) {
            int nx = (int)gid.x + dx;
            int ny = (int)gid.y + dy;

            if (nx >= 0 && nx < (int)width && ny >= 0 && ny < (int)height) {
                if (mask[ny * width + nx]) {
                    float dist = sqrt((float)(dx * dx + dy * dy));
                    minDist = min(minDist, dist);
                }
            }
        }
    }

    // Apply smooth falloff based on distance
    if (minDist <= featherWidth) {
        scalingMap[idx] = 1.0f - (minDist / featherWidth);
    } else {
        scalingMap[idx] = 0.0f;
    }
}

// Map spatial ROI to wavelet domain coefficients
kernel void j2k_roi_wavelet_mapping(
    device const bool* spatialMask [[buffer(0)]],
    device bool* waveletMask [[buffer(1)]],
    constant uint& spatialWidth [[buffer(2)]],
    constant uint& spatialHeight [[buffer(3)]],
    constant uint& waveletWidth [[buffer(4)]],
    constant uint& waveletHeight [[buffer(5)]],
    constant uint& decompositionLevel [[buffer(6)]],
    constant uint& subbandType [[buffer(7)]],  // 0=LL, 1=LH, 2=HL, 3=HH
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= waveletWidth || gid.y >= waveletHeight) return;

    uint waveletIdx = gid.y * waveletWidth + gid.x;

    // Scale factor for this decomposition level
    uint scaleFactor = 1u << decompositionLevel;

    // Map wavelet coefficient to spatial region
    uint spatialX = gid.x * scaleFactor;
    uint spatialY = gid.y * scaleFactor;

    // Apply subband offset (for LH, HL, HH subbands)
    if (subbandType == 1 || subbandType == 3) {  // LH or HH
        spatialX += scaleFactor / 2;
    }
    if (subbandType == 2 || subbandType == 3) {  // HL or HH
        spatialY += scaleFactor / 2;
    }

    // Check if any pixel in the corresponding spatial region is in ROI
    bool inROI = false;
    for (uint dy = 0; dy < scaleFactor && !inROI; dy++) {
        for (uint dx = 0; dx < scaleFactor && !inROI; dx++) {
            uint sx = spatialX + dx;
            uint sy = spatialY + dy;
            if (sx < spatialWidth && sy < spatialHeight) {
                if (spatialMask[sy * spatialWidth + sx]) {
                    inROI = true;
                }
            }
        }
    }

    waveletMask[waveletIdx] = inROI;
}

// MARK: - Quantization Shaders

// Scalar quantization with uniform step size
kernel void j2k_quantize_scalar(
    device const float* coefficients [[buffer(0)]],
    device int* indices [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float c = coefficients[gid];
    float absC = fabs(c);
    int sign = (c >= 0.0f) ? 1 : -1;

    // q = sign(c) × floor(|c| / Δ)
    int q = (int)floor(absC / stepSize);
    indices[gid] = sign * q;
}

// Dead-zone quantization with enlarged zero bin
kernel void j2k_quantize_deadzone(
    device const float* coefficients [[buffer(0)]],
    device int* indices [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant float& deadzoneWidth [[buffer(3)]],
    constant uint& count [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float c = coefficients[gid];
    float absC = fabs(c);
    float threshold = stepSize * deadzoneWidth * 0.5f;

    if (absC <= threshold) {
        indices[gid] = 0;
    } else {
        int sign = (c >= 0.0f) ? 1 : -1;
        // q = sign(c) × floor((|c| - t) / Δ) + 1
        int q = (int)floor((absC - threshold) / stepSize) + 1;
        indices[gid] = sign * q;
    }
}

// Dequantization (scalar mode)
kernel void j2k_dequantize_scalar(
    device const int* indices [[buffer(0)]],
    device float* coefficients [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    int q = indices[gid];
    if (q == 0) {
        coefficients[gid] = 0.0f;
    } else {
        int sign = (q >= 0) ? 1 : -1;
        int absQ = abs(q);
        // c' = (q + 0.5 × sign(q)) × Δ (midpoint reconstruction)
        coefficients[gid] = (float)(sign * absQ + 0.5f * sign) * stepSize;
    }
}

// Dequantization (dead-zone mode)
kernel void j2k_dequantize_deadzone(
    device const int* indices [[buffer(0)]],
    device float* coefficients [[buffer(1)]],
    constant float& stepSize [[buffer(2)]],
    constant float& deadzoneWidth [[buffer(3)]],
    constant uint& count [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    int q = indices[gid];
    float threshold = stepSize * deadzoneWidth * 0.5f;

    if (q == 0) {
        coefficients[gid] = 0.0f;
    } else {
        int sign = (q >= 0) ? 1 : -1;
        int absQ = abs(q);
        // c' = sign(q) × ((|q| - 0.5) × Δ + threshold)
        coefficients[gid] = (float)sign * ((float)(absQ - 0.5f) * stepSize + threshold);
    }
}

// Apply visual frequency weighting to quantization step sizes
kernel void j2k_quantize_visual_weighting(
    device const float* baseStepSizes [[buffer(0)]],
    device const float* visualWeights [[buffer(1)]],
    device float* adjustedStepSizes [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    // Apply perceptual weighting: Δ' = Δ × W
    // Lower weight = higher quality (smaller step size)
    float weight = max(visualWeights[gid], 0.1f);  // Clamp minimum weight
    adjustedStepSizes[gid] = baseStepSizes[gid] * weight;
}

// Perceptual quantization based on quality metrics
kernel void j2k_quantize_perceptual(
    device const float* coefficients [[buffer(0)]],
    device const float* perceptualWeights [[buffer(1)]],
    device int* indices [[buffer(2)]],
    constant float& baseStepSize [[buffer(3)]],
    constant uint& count [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float c = coefficients[gid];
    float weight = perceptualWeights[gid];
    float stepSize = baseStepSize * weight;

    float absC = fabs(c);
    int sign = (c >= 0.0f) ? 1 : -1;
    int q = (int)floor(absC / stepSize);
    indices[gid] = sign * q;
}

// Parallel trellis state evaluation for TCQ
kernel void j2k_quantize_trellis_evaluate(
    device const float* coefficients [[buffer(0)]],
    device const float* pathMetrics [[buffer(1)]],
    device float* newMetrics [[buffer(2)]],
    device int* decisions [[buffer(3)]],
    constant float& stepSize [[buffer(4)]],
    constant uint& numStates [[buffer(5)]],
    constant uint& coeffIndex [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= numStates) return;

    // Each thread evaluates one state transition
    float coeff = coefficients[coeffIndex];
    float bestMetric = INFINITY;
    int bestDecision = 0;

    // Evaluate all possible transitions to this state
    for (uint prevState = 0; prevState < numStates; prevState++) {
        // Compute reconstruction value for this transition
        float reconstruction = (float)((int)prevState - (int)numStates / 2) * stepSize;

        // Compute distortion
        float distortion = (coeff - reconstruction) * (coeff - reconstruction);

        // Compute accumulated metric
        float metric = pathMetrics[prevState] + distortion;

        if (metric < bestMetric) {
            bestMetric = metric;
            bestDecision = (int)prevState;
        }
    }

    newMetrics[gid] = bestMetric;
    decisions[gid * 256 + coeffIndex] = bestDecision;  // Store decision path
}

// Compute distortion metrics for R-D optimisation
kernel void j2k_quantize_distortion_metric(
    device const float* original [[buffer(0)]],
    device const float* reconstructed [[buffer(1)]],
    device float* distortions [[buffer(2)]],
    constant uint& count [[buffer(3)]],
    constant uint& metric [[buffer(4)]],  // 0=MSE, 1=MAE, 2=PSNR
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) return;

    float orig = original[gid];
    float recon = reconstructed[gid];
    float diff = orig - recon;

    switch (metric) {
        case 0:  // MSE (Mean Squared Error)
            distortions[gid] = diff * diff;
            break;
        case 1:  // MAE (Mean Absolute Error)
            distortions[gid] = fabs(diff);
            break;
        case 2:  // Squared difference for PSNR calculation
            distortions[gid] = diff * diff;
            break;
        default:
            distortions[gid] = diff * diff;
    }
}

// MARK: - HTJ2K Decode Prototype: dispatch-cost probe
//
// Layout the eventual real decoder will use, exercised here with
// trivial work so we can measure the actual GPU launch + memory
// marshaling overhead at varying codeblock counts. Each thread
// handles one codeblock — the same architecture a full HT decoder
// would use (per-codeblock state is independent, the parallelism
// unit is the codeblock).
//
// Inputs:
//   blocks       — array of CodeBlockDescriptor, one per codeblock
//   codestream   — single concatenated byte pool covering all blocks
//   output       — single Int32 pool covering all decoded samples
//   blockCount   — number of codeblocks to process
//
// Per-block work: walk the codeblock's bytes once, sum into a
// checksum, and write `width × height` Int32 values to the output
// region. Substitutes for the eventual MQ-free HT decode workload.

struct GPUHTBlockDescriptor {
    uint dataOffset;    // byte offset into codestream pool
    uint dataLength;
    uint outputOffset;  // sample offset into output pool
    ushort width;
    ushort height;
};

kernel void j2k_ht_dispatch_probe(
    device const GPUHTBlockDescriptor* blocks  [[buffer(0)]],
    device const uchar*                codestream [[buffer(1)]],
    device int*                        output  [[buffer(2)]],
    constant uint&                     blockCount [[buffer(3)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUHTBlockDescriptor desc = blocks[tid];

    // Touch every input byte once — models the per-block bit-stream
    // walk an HT decoder would do. The accumulator stays in a
    // register so the optimizer cannot eliminate the loop.
    uint checksum = 0;
    for (uint i = 0; i < desc.dataLength; i++) {
        checksum = checksum * 1103515245u + uint(codestream[desc.dataOffset + i]);
    }

    // Write width × height Int32 outputs — models the eventual
    // coefficient write traffic.
    uint sampleCount = uint(desc.width) * uint(desc.height);
    device int* myOut = output + desc.outputOffset;
    int v = int(checksum & 0x0FFFu);   // bounded magnitude
    for (uint i = 0; i < sampleCount; i++) {
        myOut[i] = ((i & 1u) == 0u) ? v : -v;
    }
}

// MARK: - HTJ2K Forward Encode Prototype: dispatch-cost probe (v6-alpha6 phase 0.5)
//
// Symmetric to `j2k_ht_dispatch_probe` (decoder side) but for the
// **encode** direction. Models the traffic shape an eventual GPU
// HT-conformant forward entropy encoder will see:
//
//   reads:  W*H UInt32 coefficients (sign-magnitude, same convention
//           as HTBlockEncoderConformant.encode input)
//   writes: ~half the coefficient count's worth of bytes (rough
//           steady-state ratio for lossless 16-bit medical inputs)
//
// Per-thread work mimics the per-sample classification cost of
// HTBlockEncoderConformant.sampleInfo: significance test + leading-
// zero count + sign extraction. Light enough that the dispatch
// overhead dominates, heavy enough that the optimizer cannot skip
// the loop — the same balance the decoder dispatch probe strikes.
//
// Inputs:
//   blocks       — array of GPUHTForwardBlockDescriptor, one per block
//   coefficients — concatenated UInt32 coefficient pool (sign-magnitude)
//   output       — concatenated UInt8 byte pool for synthetic writes
//   blockCount   — number of codeblocks to process
//
// NOT a real encoder. Used to answer the v6-alpha6 Phase 0.5 question:
// "does the per-block GPU dispatch + memory-traffic floor leave room
// for the actual entropy work to win against CPU's parallel
// codeblock encode?" If the floor exceeds CPU's per-block wall time,
// the v6-alpha6 plan pivots to approach E (CPU-SIMD only).

struct GPUHTForwardBlockDescriptor {
    uint coeffOffset;     // sample offset into coefficient pool
    uint outputOffset;    // byte offset into output byte pool
    uint outputCapacity;  // upper bound on bytes this block may write
    ushort width;
    ushort height;
};

kernel void j2k_ht_forward_dispatch_probe(
    device const GPUHTForwardBlockDescriptor* blocks       [[buffer(0)]],
    device const uint*                        coefficients [[buffer(1)]],
    device uchar*                             output       [[buffer(2)]],
    constant uint&                            blockCount   [[buffer(3)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUHTForwardBlockDescriptor desc = blocks[tid];

    uint sampleCount = uint(desc.width) * uint(desc.height);

    // Walk every coefficient once — models per-sample classification
    // + payload extraction cost. The accumulator stays in a register
    // so the optimizer cannot eliminate the loop.
    uint accumulator = 0u;
    device const uint* myCoeffs = coefficients + desc.coeffOffset;
    for (uint i = 0; i < sampleCount; i++) {
        uint v = myCoeffs[i];
        // Light synthetic work matching sampleInfo shape:
        //   - significance test (top-bit == 0 means insignificant)
        //   - magnitude extraction (low 31 bits)
        //   - leading-zero count = bit-width (used for VLC/MagSgn
        //     codeword length in the real encoder)
        uint mag = v & 0x7FFFFFFFu;
        uint isSig = (mag != 0u) ? 1u : 0u;
        uint leadingZeros = (mag == 0u) ? 32u : clz(mag);
        accumulator = accumulator * 31u + isSig + (leadingZeros << 1);
    }

    // Write output bytes proportional to coefficient count — models
    // per-block byte-stream emission cost. Real codeblocks emit
    // closer to 0.5–1.5 bytes per significant sample on lossless;
    // half the sample count is a defensible synthetic upper bound
    // that fits within outputCapacity.
    uint outBytes = sampleCount >> 1;
    if (outBytes > desc.outputCapacity) {
        outBytes = desc.outputCapacity;
    }
    device uchar* myOut = output + desc.outputOffset;
    uchar payload = uchar(accumulator & 0xFFu);
    for (uint i = 0; i < outBytes; i++) {
        myOut[i] = payload;
    }
}

// MARK: - HTJ2K Forward Encode: per-sample classifier (v6-alpha6 phase 1)
//
// Per-sample classification kernel — the parallelizable half of
// HT-conformant forward entropy. Mirrors the CPU `sampleInfo`
// function in `J2KHTConformantBlockEncoder.swift` line by line:
//
//   val = (t * 2) >> p & ~1;
//   if val == 0  -> (sig=false, eQ=0, payload=0)
//   val -= 1
//   eQ = 32 - clz(val)
//   sign = (t >> 31) & 1
//   payload = (val - 1) + sign
//   return (sig=true, eQ, payload)
//
// Output tuple — one UInt64 per sample:
//   bit  63    : sig
//   bits 56-62 : eQ    (7 bits — 0..32 fits)
//   bits  0-31 : payload (32 bits, full precision)
//   bits 32-55 : reserved (zero)
//
// Each thread handles one codeblock, looping over its W*H samples
// serially within the thread. The Phase 0.5 dispatch probe showed
// per-block threads scale well (2300 ns/block on M2 for the DX
// fixture); the per-sample compute is simpler than the probe's
// synthetic work, so steady-state should be similar or better.

struct GPUHTForwardClassifyDescriptor {
    uint coeffOffset;     // sample offset into coefficient pool
    uint tupleOffset;     // tuple offset into output pool (UInt64s)
    uint sampleCount;     // width * height
    uint p;               // bit-depth shift parameter (Kmsbs-style)
};

kernel void j2k_ht_forward_classify_samples(
    device const GPUHTForwardClassifyDescriptor* blocks       [[buffer(0)]],
    device const uint*                           coefficients [[buffer(1)]],
    device ulong*                                tuples       [[buffer(2)]],
    constant uint&                               blockCount   [[buffer(3)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUHTForwardClassifyDescriptor desc = blocks[tid];

    device const uint*  myCoeffs = coefficients + desc.coeffOffset;
    device ulong*       myTuples = tuples       + desc.tupleOffset;
    uint p = desc.p;

    for (uint i = 0; i < desc.sampleCount; i++) {
        uint t = myCoeffs[i];

        // val = (t * 2) >> p & ~1;
        uint val = ((t << 1) >> p) & ~1u;

        ulong tuple;
        if (val == 0u) {
            tuple = 0;  // sig=0, eQ=0, payload=0
        } else {
            // val -= 1; eQ = 32 - clz(val); sign = (t >> 31) & 1;
            // payload = (val - 1) + sign;
            uint valM1 = val - 1u;
            // clz on a non-zero uint always returns 0..31, so eQ ∈ [1, 32].
            uint eQ = 32u - clz(valM1);
            uint sign = (t >> 31) & 1u;
            uint payload = (valM1 - 1u) + sign;

            // Pack: bit 63 = sig, bits 56-62 = eQ, bits 0-31 = payload.
            tuple = (1uL << 63)
                  | ((ulong(eQ) & 0x7Fu) << 56)
                  | ulong(payload);
        }
        myTuples[i] = tuple;
    }
}

// MARK: - HTJ2K MagSgn forward bit reader (Phase 1)
//
// Per-codeblock MagSgn descriptor: layout matches the Swift
// `J2KMetalHTMagSgnBlockDescriptor` struct field-for-field.
struct GPUHTMagSgnDescriptor {
    uint dataOffset;     // byte offset into codestream pool
    uint dataLength;     // bytes available in this block
    uint widthsOffset;   // sample offset into widths pool (1 byte/sample)
    uint outputOffset;   // sample offset into output pool (1 uint/sample)
    uint sampleCount;    // number of samples to decode for this block
};

// MagSgn reader state — kept in registers for the duration of one
// codeblock decode. Mirrors `HTMagSgnDecoderConformant`'s fields:
//   - tmp:        bit buffer (LSB-first consumption)
//   - bits:       valid bits in tmp
//   - readIndex:  byte position relative to dataOffset
//   - unstuff:    next byte's high bit is reserved (because previous == 0xFF)
struct HTMagSgnState {
    ulong tmp;
    int   bits;
    int   readIndex;
    bool  unstuff;
};

// Refill the bit buffer so at least 32 bits are available, with
// FF-stuff handling. `byteCount` is dataLength; reads past the end
// synthesise 0xFF (matches CPU's post-EOF padding convention).
inline void htMagSgnRefill(thread HTMagSgnState* s,
                           device const uchar* bytes,
                           uint byteCount)
{
    while (s->bits <= 32) {
        uchar b;
        if ((uint)s->readIndex < byteCount) {
            b = bytes[s->readIndex];
            s->readIndex += 1;
        } else {
            b = 0xFF;
        }
        int  dBits = s->unstuff ? 7 : 8;
        uchar mask = s->unstuff ? (uchar)0x7F : (uchar)0xFF;
        ulong value = (ulong)(b & mask);
        s->tmp |= value << s->bits;
        s->bits += dBits;
        s->unstuff = (b == 0xFF);
    }
}

// Read `count` bits LSB-first. Mirrors `HTMagSgnDecoderConformant.read`.
inline uint htMagSgnRead(thread HTMagSgnState* s,
                         device const uchar* bytes,
                         uint byteCount,
                         int count)
{
    if (s->bits < count) {
        htMagSgnRefill(s, bytes, byteCount);
    }
    ulong mask = (count >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << count) - 1);
    uint v = (uint)(s->tmp & mask);
    s->tmp >>= count;
    s->bits -= count;
    return v;
}

// Decode `desc.sampleCount` MagSgn samples for a single codeblock.
// The widths array stores one byte per sample — the bit width to
// consume from the MagSgn stream for that sample's reconstruction.
// Output is one uint per sample (matches CPU's `[UInt32]` output).
kernel void j2k_ht_magsgn_decode(
    device const GPUHTMagSgnDescriptor* blocks  [[buffer(0)]],
    device const uchar*                  codestream [[buffer(1)]],
    device const uchar*                  widths     [[buffer(2)]],
    device uint*                         output     [[buffer(3)]],
    constant uint&                       blockCount [[buffer(4)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUHTMagSgnDescriptor desc = blocks[tid];
    device const uchar* myBytes  = codestream + desc.dataOffset;
    device const uchar* myWidths = widths + desc.widthsOffset;
    device       uint*  myOut    = output + desc.outputOffset;

    HTMagSgnState s;
    s.tmp = 0;
    s.bits = 0;
    s.readIndex = 0;
    s.unstuff = false;

    for (uint i = 0; i < desc.sampleCount; i++) {
        int w = int(myWidths[i]);
        myOut[i] = htMagSgnRead(&s, myBytes, desc.dataLength, w);
    }
}

// MARK: - HTJ2K Cleanup-pass decoder (Phase 2)
//
// Per-codeblock descriptor for the full cleanup-pass kernel.
// Field layout matches `J2KMetalHTCleanupBlockDescriptor` in
// Swift exactly. All UInt32 fields → unambiguous 4-byte
// alignment, stride 32 bytes.
struct GPUHTCleanupDescriptor {
    uint magsgnOffset;
    uint magsgnLength;
    uint melVlcOffset;
    uint melVlcLength;       // == scup
    uint outputOffset;       // sample offset (uint per sample)
    uint width;
    uint height;
    uint missingMSBs;
};

// MEL state. Mirrors HTMELDecoderConformant — MSB-first bit buffer
// top-aligned, `bits` is the number of valid bits, `state` indexes
// the MEL exponent table.
struct HTMELState {
    ulong tmp;
    int   bits;
    int   readIndex;
    bool  unstuff;
    int   state;
};

constant int melExp[13] = {0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5};

inline void htMELRefill(thread HTMELState* s,
                        device const uchar* bytes, uint byteCount)
{
    while (s->bits <= 32) {
        uchar b;
        if ((uint)s->readIndex < byteCount) {
            b = bytes[s->readIndex];
            s->readIndex += 1;
        } else {
            b = 0xFF;
        }
        int  dBits = s->unstuff ? 7 : 8;
        ulong value = (ulong)b & (((ulong)1 << dBits) - 1);
        s->tmp |= value << (64 - s->bits - dBits);
        s->bits += dBits;
        s->unstuff = (b == 0xFF);
    }
}

inline int htMELNextRun(thread HTMELState* s,
                        device const uchar* bytes, uint byteCount)
{
    if (s->bits < 6) htMELRefill(s, bytes, byteCount);
    int eval = melExp[s->state];
    int run;
    if ((s->tmp & ((ulong)1 << 63)) != 0) {
        run = (1 << eval) - 1;
        s->state = min(12, s->state + 1);
        s->tmp <<= 1;
        s->bits -= 1;
        run <<= 1;             // low bit 0 → no terminator
    } else {
        int r = 0;
        if (eval > 0) {
            r = (int)((s->tmp >> (63 - eval)) & (ulong)((1 << eval) - 1));
        }
        s->state = max(0, s->state - 1);
        s->tmp <<= (eval + 1);
        s->bits -= (eval + 1);
        run = (r << 1) + 1;    // low bit 1 → terminator
    }
    return run;
}

inline bool htMELNextEvent(thread int* run,
                           thread HTMELState* s,
                           device const uchar* bytes, uint byteCount)
{
    *run -= 2;
    bool isOne = (*run == -1);
    if (*run < 0) *run = htMELNextRun(s, bytes, byteCount);
    return isOne;
}

// VLC reverse reader. Reads from the END of the mel/vlc segment
// backwards, LSB-first into `tmp`. Mirrors `VLCReverseReader`.
struct VLCReverseState {
    ulong tmp;
    int   bits;
    int   byteIdx;        // counts down toward -1
    bool  unstuff;
};

inline void vlcReverseInit(thread VLCReverseState* s,
                           device const uchar* bytes, int scup)
{
    s->tmp = 0;
    s->bits = 0;
    s->byteIdx = scup - 2;
    s->unstuff = false;
    if (s->byteIdx >= 0) {
        uchar b = bytes[s->byteIdx];
        ulong highNibble = (ulong)(b >> 4);
        ulong t = ((highNibble & 0x7) == 0x7) ? (ulong)1 : (ulong)0;
        ulong val = highNibble & ((ulong)0xF >> t);
        s->tmp = val;
        s->bits = (int)(4 - t);
        s->unstuff = val > 0x8;
        s->byteIdx -= 1;
    }
}

inline void vlcReverseRefill(thread VLCReverseState* s,
                             device const uchar* bytes)
{
    while (s->bits <= 32) {
        uchar b;
        if (s->byteIdx >= 0) {
            b = bytes[s->byteIdx];
            s->byteIdx -= 1;
        } else {
            b = 0;
        }
        int t = (s->unstuff && (((int)b) & 0x7F) == 0x7F) ? 1 : 0;
        int dBits = 8 - t;
        uchar mask = (t == 1) ? (uchar)0x7F : (uchar)0xFF;
        ulong value = (ulong)(b & mask);
        s->tmp |= value << s->bits;
        s->bits += dBits;
        s->unstuff = (b > 0x8F);
    }
}

inline ulong vlcReversePeek(thread VLCReverseState* s,
                            device const uchar* bytes,
                            int maxBits)
{
    if (s->bits < maxBits) vlcReverseRefill(s, bytes);
    ulong m = (maxBits >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << maxBits) - 1);
    return s->tmp & m;
}

inline ulong vlcReverseRead(thread VLCReverseState* s,
                            device const uchar* bytes,
                            int count)
{
    if (s->bits < count) vlcReverseRefill(s, bytes);
    ulong m = (count >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << count) - 1);
    ulong v = s->tmp & m;
    s->tmp >>= count;
    s->bits -= count;
    return v;
}

// VLC table lookup — same packed layout as the CPU side:
//   bits  0-2: cwd_len
//   bit   3:   u_off
//   bits  4-7: rho
//   bits  8-11: e_1
//   bits 12-15: e_k
inline void htLookupVLC(constant ushort* tbl, int c_q, int bits,
                        thread int* rho, thread int* u_off,
                        thread int* cwd_len, thread int* e_k,
                        thread int* e_1)
{
    int idx = (c_q << 7) | (bits & 0x7F);
    int entry = (int)tbl[idx];
    *cwd_len = entry & 0x7;
    *u_off   = (entry >> 3) & 0x1;
    *rho     = (entry >> 4) & 0xF;
    *e_1     = (entry >> 8) & 0xF;
    *e_k     = (entry >> 12) & 0xF;
}

// Unary prefix: 1→1, 01→2, 001→3, 000→4.
inline int htReadPrefix(thread VLCReverseState* s, device const uchar* bytes)
{
    int b0 = (int)vlcReverseRead(s, bytes, 1);
    if (b0 == 1) return 1;
    int b1 = (int)vlcReverseRead(s, bytes, 1);
    if (b1 == 1) return 2;
    int b2 = (int)vlcReverseRead(s, bytes, 1);
    if (b2 == 1) return 3;
    return 4;
}

inline int htDecodeFromPrefix(int len,
                              thread VLCReverseState* s,
                              device const uchar* bytes)
{
    if (len == 3) {
        int suf = (int)vlcReverseRead(s, bytes, 1);
        return 3 + suf;
    }
    if (len == 4) {
        int suf = (int)vlcReverseRead(s, bytes, 5);
        if (suf < 28) return 5 + suf;
        int ext = (int)vlcReverseRead(s, bytes, 4);
        return 33 + (suf - 28) + 4 * ext;
    }
    return len;
}

// Initial-row UVLC pair — mirrors decodeUVLCPairInitial.
inline void htDecodeUVLCPairInitial(int u_off0, int u_off1,
                                    thread int* u0_out, thread int* u1_out,
                                    thread VLCReverseState* vs,
                                    device const uchar* mvBytes,
                                    thread int* melRun,
                                    thread HTMELState* ms,
                                    device const uchar* mvBytesForMEL,
                                    uint mvByteCount)
{
    if (u_off0 == 0 && u_off1 == 0) { *u0_out = 0; *u1_out = 0; return; }
    if (u_off0 == 1 && u_off1 == 1) {
        bool melEvent = htMELNextEvent(melRun, ms, mvBytesForMEL, mvByteCount);
        if (melEvent) {
            int p0 = htReadPrefix(vs, mvBytes);
            int p1 = htReadPrefix(vs, mvBytes);
            int s0 = htDecodeFromPrefix(p0, vs, mvBytes);
            int s1 = htDecodeFromPrefix(p1, vs, mvBytes);
            *u0_out = s0 + 2; *u1_out = s1 + 2; return;
        }
        int p0 = htReadPrefix(vs, mvBytes);
        if (p0 >= 3) {
            int bit = (int)vlcReverseRead(vs, mvBytes, 1);
            int u0v = htDecodeFromPrefix(p0, vs, mvBytes);
            *u0_out = u0v; *u1_out = bit + 1; return;
        }
        int p1 = htReadPrefix(vs, mvBytes);
        int u0v = htDecodeFromPrefix(p0, vs, mvBytes);
        int u1v = htDecodeFromPrefix(p1, vs, mvBytes);
        *u0_out = u0v; *u1_out = u1v; return;
    }
    *u0_out = (u_off0 != 0) ? htDecodeFromPrefix(htReadPrefix(vs, mvBytes), vs, mvBytes) : 0;
    *u1_out = (u_off1 != 0) ? htDecodeFromPrefix(htReadPrefix(vs, mvBytes), vs, mvBytes) : 0;
}

// Subsequent-row UVLC: encoder writes pre0, pre1, suf0, suf1 in
// that order unconditionally — read both prefixes first.
inline void htDecodeUVLCPairSubsequent(int u_off0, int u_off1,
                                       thread int* u0_out, thread int* u1_out,
                                       thread VLCReverseState* vs,
                                       device const uchar* mvBytes)
{
    int len0 = (u_off0 != 0) ? htReadPrefix(vs, mvBytes) : 0;
    int len1 = (u_off1 != 0) ? htReadPrefix(vs, mvBytes) : 0;
    *u0_out = (u_off0 != 0) ? htDecodeFromPrefix(len0, vs, mvBytes) : 0;
    *u1_out = (u_off1 != 0) ? htDecodeFromPrefix(len1, vs, mvBytes) : 0;
}

// Read MagSgn bits per significant sample of the quad and place
// reconstructed sign-magnitude UInt32 coefficients into `coefs`.
inline void htReadQuadSamples(int baseX, int baseY,
                              int rho, int Uq, int e_k, int e_1, uint p,
                              uint width, uint height,
                              thread HTMagSgnState* ms,
                              device const uchar* msBytes,
                              uint msByteCount,
                              device uint* coefs)
{
    // (col, row) = [(0,0), (0,1), (1,0), (1,1)] indexed by i = 2*col+row.
    for (int i = 0; i < 4; i++) {
        int bit = (rho >> i) & 1;
        if (bit == 0) continue;
        int eBit = (e_k >> i) & 1;
        int e1Bit = (e_1 >> i) & 1;
        int m = Uq - eBit;
        uint payload = htMagSgnRead(ms, msBytes, msByteCount, m);
        uint sign = payload & 1;
        uint mask = (m >= 32) ? (uint)~(uint)0 : (((uint)1 << m) - 1);
        uint v_n = payload & mask;
        v_n |= ((uint)e1Bit) << m;
        v_n |= 1;
        int dx = (i >> 1) & 1;     // (i / 2) % 2
        int dy = i & 1;            // i % 2
        int xi = baseX + dx;
        int yi = baseY + dy;
        if ((uint)xi >= width || (uint)yi >= height) continue;
        uint coef = (v_n + 2) << (p - 1);
        if (sign != 0) coef |= 0x80000000u;
        coefs[yi * width + xi] = coef;
    }
}

// Recover the per-quad e_q values from the reconstructed coefs.
// Returns 4 ints packed (eQ0, eQ1, eQ2, eQ3).
inline void htRecoverEQ(int rho, int baseX, int baseY,
                        uint p, uint width, uint height,
                        device const uint* coefs,
                        thread int* outEQ0, thread int* outEQ1,
                        thread int* outEQ2, thread int* outEQ3)
{
    *outEQ0 = 0; *outEQ1 = 0; *outEQ2 = 0; *outEQ3 = 0;
    for (int i = 0; i < 4; i++) {
        if (((rho >> i) & 1) == 0) continue;
        int dx = (i >> 1) & 1;
        int dy = i & 1;
        int xi = baseX + dx;
        int yi = baseY + dy;
        if ((uint)xi >= width || (uint)yi >= height) continue;
        uint mag = coefs[yi * width + xi] & 0x7FFFFFFFu;
        uint v_n = (mag >> (p - 1)) - 2u;
        uint twoMuMinusOne = v_n | 1u;
        int eQ = 32 - clz(twoMuMinusOne);
        if (i == 0) *outEQ0 = eQ;
        else if (i == 1) *outEQ1 = eQ;
        else if (i == 2) *outEQ2 = eQ;
        else *outEQ3 = eQ;
    }
}

// Initial row decoder — uses VLC table 0 with implicit kappa=1.
inline void htDecodeInitialRow(uint width, uint height, uint p,
                               thread HTMagSgnState* ms,
                               device const uchar* msBytes, uint msByteCount,
                               thread VLCReverseState* vs,
                               device const uchar* mvBytes,
                               uint mvByteCount,
                               thread HTMELState* mel,
                               thread int* melRun,
                               thread uchar* eVal, thread uchar* cxVal,
                               constant ushort* vlcTbl0,
                               device uint* coefs)
{
    int lep = 0;
    int lcxp = 0;
    int c_q0 = 0;
    int x = 0;
    while ((uint)x < width) {
        int rho0 = 0;
        int u_off0 = 0; int cwd_len0 = 0; int e_k0 = 0; int e_1_0 = 0;
        if (c_q0 == 0) {
            if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl0, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                (void)vlcReverseRead(vs, mvBytes, cwd_len0);
            }
        } else {
            int head = (int)vlcReversePeek(vs, mvBytes, 7);
            htLookupVLC(vlcTbl0, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
            (void)vlcReverseRead(vs, mvBytes, cwd_len0);
        }

        int rho1 = 0;
        int u_off1 = 0; int cwd_len1 = 0; int e_k1 = 0; int e_1_1 = 0;
        if ((uint)(x + 2) < width) {
            int c_q1 = (rho0 >> 1) | (rho0 & 1);
            if (c_q1 == 0) {
                if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl0, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                }
            } else {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl0, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                (void)vlcReverseRead(vs, mvBytes, cwd_len1);
            }
        }

        int u0 = 0, u1 = 0;
        htDecodeUVLCPairInitial(rho0 != 0 ? u_off0 : 0,
                                rho1 != 0 ? u_off1 : 0,
                                &u0, &u1,
                                vs, mvBytes,
                                melRun, mel, mvBytes, mvByteCount);
        int Uq0 = u0 + 1, Uq1 = u1 + 1;

        htReadQuadSamples(x, 0, rho0, Uq0, e_k0, e_1_0, p, width, height, ms, msBytes, msByteCount, coefs);
        if ((uint)(x + 2) < width) {
            htReadQuadSamples(x + 2, 0, rho1, Uq1, e_k1, e_1_1, p, width, height, ms, msBytes, msByteCount, coefs);
        }

        int eQ0_0, eQ0_1, eQ0_2, eQ0_3;
        htRecoverEQ(rho0, x, 0, p, width, height, coefs, &eQ0_0, &eQ0_1, &eQ0_2, &eQ0_3);
        eVal[lep] = max(eVal[lep], (uchar)eQ0_1); lep += 1;
        eVal[lep] = (uchar)eQ0_3;
        cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho0 & 2) >> 1)); lcxp += 1;
        cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);
        if ((uint)(x + 2) < width) {
            int eQ1_0, eQ1_1, eQ1_2, eQ1_3;
            htRecoverEQ(rho1, x + 2, 0, p, width, height, coefs, &eQ1_0, &eQ1_1, &eQ1_2, &eQ1_3);
            eVal[lep] = max(eVal[lep], (uchar)eQ1_1); lep += 1;
            eVal[lep] = (uchar)eQ1_3;
            cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho1 & 2) >> 1)); lcxp += 1;
            cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);
        }

        c_q0 = (rho1 >> 1) | (rho1 & 1);
        x += 4;
    }
    // Sentinel — eVal capacity is at least lep + 2 by construction.
    eVal[lep + 1] = 0;
}

// Subsequent row decoder — uses VLC table 1 with kappa from maxE.
inline void htDecodeSubsequentRow(int y, uint width, uint height, uint p,
                                  thread HTMagSgnState* ms,
                                  device const uchar* msBytes, uint msByteCount,
                                  thread VLCReverseState* vs,
                                  device const uchar* mvBytes,
                                  uint mvByteCount,
                                  thread HTMELState* mel,
                                  thread int* melRun,
                                  thread uchar* eVal, thread uchar* cxVal,
                                  constant ushort* vlcTbl1,
                                  device uint* coefs)
{
    int lep = 0;
    int lcxp = 0;
    int maxE = max((int)eVal[0], (int)eVal[1]) - 1;
    eVal[0] = 0;
    int c_q0 = (int)cxVal[0] + ((int)cxVal[1] << 2);
    cxVal[0] = 0;
    int x = 0;
    while ((uint)x < width) {
        int rho0 = 0;
        int u_off0 = 0; int cwd_len0 = 0; int e_k0 = 0; int e_1_0 = 0;
        if (c_q0 == 0) {
            if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl1, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                (void)vlcReverseRead(vs, mvBytes, cwd_len0);
            }
        } else {
            int head = (int)vlcReversePeek(vs, mvBytes, 7);
            htLookupVLC(vlcTbl1, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
            (void)vlcReverseRead(vs, mvBytes, cwd_len0);
        }
        int kappaA = ((rho0 & (rho0 - 1)) != 0) ? max(1, maxE) : 1;

        // Advance lcxp partially to discover c_q1's source slot.
        cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho0 & 2) >> 1)); lcxp += 1;
        int c_q1 = (int)cxVal[lcxp] + ((int)cxVal[lcxp + 1] << 2);
        cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);

        int rho1 = 0;
        int u_off1 = 0; int cwd_len1 = 0; int e_k1 = 0; int e_1_1 = 0;
        if ((uint)(x + 2) < width) {
            c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2);
            if (c_q1 == 0) {
                if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl1, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                }
            } else {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl1, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                (void)vlcReverseRead(vs, mvBytes, cwd_len1);
            }
            cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho1 & 2) >> 1)); lcxp += 1;
            c_q0 = (int)cxVal[lcxp] + ((int)cxVal[lcxp + 1] << 2);
            cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);
        }

        int u0 = 0, u1 = 0;
        htDecodeUVLCPairSubsequent(rho0 != 0 ? u_off0 : 0,
                                   rho1 != 0 ? u_off1 : 0,
                                   &u0, &u1, vs, mvBytes);

        int Uq0 = u0 + kappaA;
        htReadQuadSamples(x, y, rho0, Uq0, e_k0, e_1_0, p, width, height, ms, msBytes, msByteCount, coefs);

        int eQ0_0, eQ0_1, eQ0_2, eQ0_3;
        htRecoverEQ(rho0, x, y, p, width, height, coefs, &eQ0_0, &eQ0_1, &eQ0_2, &eQ0_3);
        eVal[lep] = max(eVal[lep], (uchar)eQ0_1); lep += 1;
        int maxEAfterQ0 = max((int)eVal[lep], (int)eVal[lep + 1]) - 1;
        eVal[lep] = (uchar)eQ0_3;

        int kappaB = 1;
        if ((uint)(x + 2) < width) {
            kappaB = ((rho1 & (rho1 - 1)) != 0) ? max(1, maxEAfterQ0) : 1;
            int Uq1 = u1 + kappaB;
            htReadQuadSamples(x + 2, y, rho1, Uq1, e_k1, e_1_1, p, width, height, ms, msBytes, msByteCount, coefs);

            int eQ1_0, eQ1_1, eQ1_2, eQ1_3;
            htRecoverEQ(rho1, x + 2, y, p, width, height, coefs, &eQ1_0, &eQ1_1, &eQ1_2, &eQ1_3);
            eVal[lep] = max(eVal[lep], (uchar)eQ1_1); lep += 1;
            maxE = max((int)eVal[lep], (int)eVal[lep + 1]) - 1;
            eVal[lep] = (uchar)eQ1_3;
        } else {
            maxE = maxEAfterQ0;
        }

        c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2);
        x += 4;
    }
}

// Top-level cleanup-pass kernel. One thread per codeblock.
// VLC tables are passed in `[[buffer(N)]]`; on Apple GPUs they
// land in unified memory but get cached aggressively after the
// first lookup.
kernel void j2k_ht_cleanup_decode(
    device const GPUHTCleanupDescriptor* blocks      [[buffer(0)]],
    device const uchar*                  codestream  [[buffer(1)]],
    constant ushort*                     vlcTbl0     [[buffer(2)]],
    constant ushort*                     vlcTbl1     [[buffer(3)]],
    device uint*                         output      [[buffer(4)]],
    constant uint&                       blockCount  [[buffer(5)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUHTCleanupDescriptor desc = blocks[tid];

    uint width  = desc.width;
    uint height = desc.height;
    uint p      = (uint)(30 - (int)desc.missingMSBs);

    device const uchar* msBytes = codestream + desc.magsgnOffset;
    device const uchar* mvBytes = codestream + desc.melVlcOffset;
    device       uint*  myCoefs = output + desc.outputOffset;

    // Zero the output region — readQuadSamples only writes
    // significant samples; insignificant ones stay 0.
    uint sampleCount = width * height;
    for (uint i = 0; i < sampleCount; i++) myCoefs[i] = 0;

    // State init.
    HTMagSgnState ms; ms.tmp = 0; ms.bits = 0; ms.readIndex = 0; ms.unstuff = false;
    HTMELState mel; mel.tmp = 0; mel.bits = 0; mel.readIndex = 0; mel.unstuff = false; mel.state = 0;
    VLCReverseState vs; vlcReverseInit(&vs, mvBytes, (int)desc.melVlcLength);
    int melRun = htMELNextRun(&mel, mvBytes, desc.melVlcLength);

    // Per-row scratch — at most ((width + 3)/4)*2 + 2 entries.
    // For width <= 64 (typical codeblock max), 34 fits.
    uchar eVal[34];
    uchar cxVal[34];
    for (int i = 0; i < 34; i++) { eVal[i] = 0; cxVal[i] = 0; }

    htDecodeInitialRow(width, height, p, &ms, msBytes, desc.magsgnLength,
                       &vs, mvBytes, desc.melVlcLength,
                       &mel, &melRun, eVal, cxVal, vlcTbl0, myCoefs);

    for (int y = 2; (uint)y < height; y += 2) {
        htDecodeSubsequentRow(y, width, height, p, &ms, msBytes, desc.magsgnLength,
                              &vs, mvBytes, desc.melVlcLength,
                              &mel, &melRun, eVal, cxVal, vlcTbl1, myCoefs);
    }
}

// MARK: - HT dequantisation (v5.6.0)

kernel void j2k_ht_dequant(
    device const GPUHTCleanupDescriptor* blocks      [[buffer(0)]],
    device const uint*                   sgnMag      [[buffer(1)]],
    device int*                          output      [[buffer(2)]],
    constant uint&                       blockCount  [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint blockIdx = gid.y;
    if (blockIdx >= blockCount) return;
    GPUHTCleanupDescriptor desc = blocks[blockIdx];
    uint sampleCount = desc.width * desc.height;
    uint sampleIdx = gid.x;
    if (sampleIdx >= sampleCount) return;

    uint outOffset = desc.outputOffset + sampleIdx;
    uint val = sgnMag[outOffset];
    uint shift = (uint)(30 - (int)desc.missingMSBs);
    bool isNeg = (val & 0x80000000u) != 0;
    int mag = (int)((val & 0x7FFFFFFFu) >> shift);
    output[outOffset] = isNeg ? -mag : mag;
}

// MARK: - Subband scatter (v5.7.0)

struct GPUScatterDescriptor {
    uint codeblockOffset;
    uint blockWidth;
    uint blockHeight;
    uint subbandX;
    uint subbandY;
    uint subbandStride;
    uint targetSubband;
    uint _pad;
};

kernel void j2k_subband_scatter(
    device const GPUScatterDescriptor* descs        [[buffer(0)]],
    device const int*                  codeblocks   [[buffer(1)]],
    device int*                        llOut        [[buffer(2)]],
    device int*                        lhOut        [[buffer(3)]],
    device int*                        hlOut        [[buffer(4)]],
    device int*                        hhOut        [[buffer(5)]],
    constant uint&                     descCount    [[buffer(6)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint blockIdx = gid.z;
    if (blockIdx >= descCount) return;
    GPUScatterDescriptor d = descs[blockIdx];
    uint col = gid.x;
    uint row = gid.y;
    if (col >= d.blockWidth || row >= d.blockHeight) return;

    uint srcIdx = d.codeblockOffset + row * d.blockWidth + col;
    uint dstX = d.subbandX + col;
    uint dstY = d.subbandY + row;
    uint dstIdx = dstY * d.subbandStride + dstX;
    int value = codeblocks[srcIdx];

    if (d.targetSubband == 0) llOut[dstIdx] = value;
    else if (d.targetSubband == 1) lhOut[dstIdx] = value;
    else if (d.targetSubband == 2) hlOut[dstIdx] = value;
    else hhOut[dstIdx] = value;
}

// MARK: - Subband scatter + dequant (Float, v5.26.0)
//
// Mirror of j2k_subband_scatter for the 9/7 lossy fused-from-
// codeblocks path: reads Int32 codeblock samples, applies HTJ2K
// conformant cleanup-only dequantisation, writes Float to the
// per-subband 2D buffers. Closes the CPU dequant + per-level
// upload of LH/HL/HH that the v5.25.0 multi-level fused IDWT
// still paid.
//
// Dequant formula (HTJ2K conformant cleanup-only):
//   coeff == 0 → 0
//   coeff > 0  → (coeff + 0.5) * stepSize
//   coeff < 0  → (coeff - 0.5) * stepSize
//
// Matches `applyDequantization`'s irreversible-9/7 + useHTJ2K +
// !hasHTMask branch; conformant blocks never carry partial
// refinement (htPartiallyRefined is always empty on the Part-15
// cleanup-only path), so the per-coefficient mask check from CPU
// dequant is unnecessary here.

struct GPUScatterDescriptorFloat {
    uint  codeblockOffset;
    uint  blockWidth;
    uint  blockHeight;
    uint  subbandX;
    uint  subbandY;
    uint  subbandStride;
    uint  targetSubband;
    float stepSize;
};

kernel void j2k_subband_scatter_float_dequant(
    device const GPUScatterDescriptorFloat* descs        [[buffer(0)]],
    device const int*                       codeblocks   [[buffer(1)]],
    device float*                           llOut        [[buffer(2)]],
    device float*                           lhOut        [[buffer(3)]],
    device float*                           hlOut        [[buffer(4)]],
    device float*                           hhOut        [[buffer(5)]],
    constant uint&                          descCount    [[buffer(6)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint blockIdx = gid.z;
    if (blockIdx >= descCount) return;
    GPUScatterDescriptorFloat d = descs[blockIdx];
    uint col = gid.x;
    uint row = gid.y;
    if (col >= d.blockWidth || row >= d.blockHeight) return;

    uint srcIdx = d.codeblockOffset + row * d.blockWidth + col;
    uint dstX = d.subbandX + col;
    uint dstY = d.subbandY + row;
    uint dstIdx = dstY * d.subbandStride + dstX;
    int coeff = codeblocks[srcIdx];

    float value;
    if (coeff == 0) {
        value = 0.0f;
    } else if (coeff > 0) {
        value = (float(coeff) + 0.5f) * d.stepSize;
    } else {
        value = (float(coeff) - 0.5f) * d.stepSize;
    }

    if (d.targetSubband == 0) llOut[dstIdx] = value;
    else if (d.targetSubband == 1) lhOut[dstIdx] = value;
    else if (d.targetSubband == 2) hlOut[dstIdx] = value;
    else hhOut[dstIdx] = value;
}

// MARK: - v7.1.0 I1.1 — inclusive prefix-sum (Pass 2 of approach C)
//
// Single-threadgroup inclusive scan over a UInt32 array. Used by
// approach C's Pass 2 to convert per-block byte counts into per-block
// byte offsets in the concatenated output buffer.
//
// Two-level scan within the threadgroup:
//   1. Each thread loads its element (0 if past end).
//   2. simd_prefix_inclusive_sum within each simdgroup → per-warp
//      inclusive prefix-sum.
//   3. Each warp's last thread writes its total to threadgroup memory.
//   4. First simdgroup runs simd_prefix_exclusive_sum over the warp
//      totals → per-warp prefix offsets.
//   5. Each thread adds its warp's prefix to its local prefix-sum.
//
// Threadgroup size must be a multiple of `threads_per_simdgroup`
// (32 on Apple Silicon). For DX 2x2 multi-tile fixtures we typically
// have ~2,300 blocks per tile; this kernel handles N up to
// `threadgroup_size` per dispatch (1024 on M2 → 1024 elements). For
// larger N use multiple dispatches with a propagation pass; not
// required for v7.1.0 corpus (we'll add multi-dispatch in I1.2 if
// the byte-write step's per-block count exceeds 1024 per dispatch).
kernel void j2k_prefix_sum_inclusive_uint32(
    device const uint* input          [[buffer(0)]],
    device       uint* output         [[buffer(1)]],
    constant     uint& n              [[buffer(2)]],
    uint tid          [[thread_position_in_threadgroup]],
    uint sg_id        [[simdgroup_index_in_threadgroup]],
    uint sg_lane      [[thread_index_in_simdgroup]],
    uint sg_size      [[threads_per_simdgroup]],
    uint tg_size      [[threads_per_threadgroup]]
) {
    // Phase 1: load this thread's element (or 0 if past end).
    uint v = (tid < n) ? input[tid] : 0u;

    // Phase 2: simd inclusive prefix-sum within the warp.
    uint psum = simd_prefix_inclusive_sum(v);

    // Phase 3: each warp's last lane stores its total in threadgroup mem.
    threadgroup uint sg_totals[32]; // up to 32 simdgroups (32 × 32 = 1024 threads)
    if (sg_lane == sg_size - 1u) {
        sg_totals[sg_id] = psum;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Phase 4: first simdgroup runs an exclusive prefix-sum over warp totals.
    uint num_warps = (tg_size + sg_size - 1u) / sg_size;
    if (sg_id == 0u) {
        uint t = (sg_lane < num_warps) ? sg_totals[sg_lane] : 0u;
        uint pt = simd_prefix_exclusive_sum(t);
        if (sg_lane < num_warps) {
            sg_totals[sg_lane] = pt;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Phase 5: add the warp's prefix to this thread's local prefix-sum.
    psum += sg_totals[sg_id];

    if (tid < n) {
        output[tid] = psum;
    }
}

// ---------------------------------------------------------------------------
// v7.1.0 I1.2 — Pass 3 byte-write kernel (MagSgn-only spike)
// ---------------------------------------------------------------------------
//
// Per-block serial bit-emitter for the HT-conformant MagSgn stream.
// One threadgroup per block; a single thread does the inherently-
// serial bit-write while the rest of the warp idles. Block-level
// parallelism (one threadgroup per block) is what keeps the GPU busy
// — Apple M2 schedules ~320 simultaneous threadgroups; DX 2x2 emits
// ~2,300 blocks per tile, so each core sees ~7 in-flight threadgroups.
//
// Direct port of `HTMagSgnEncoderConformant.encode + finish` from
// `Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift`. FF-stuffing
// is applied inline (the next byte's high bit is reserved as a
// 0 stuff-bit after every 0xFF). The terminate edge-cases match
// the CPU reference 1:1 — the bit-exact regression tests in
// `MetalHTForwardMagSgnEmitTests.swift` are the gate.
//
// Inputs (per block):
//   - `items[]` — packed (codeword, count) pairs, uint2.
//   - `itemCount` — how many items to consume.
//   - `outputOffset` — starting byte index in `output[]` for this
//     block's stream (computed by the I1.1 prefix-sum kernel; for
//     the I1.2 spike's single-block tests it's just 0).
//   - `output[]` — `device` byte buffer, written sequentially.
//   - `byteCountOut` — written with the number of bytes the block
//     emitted (post-finish, post-FF-trim).
//
// I1.2 scope is intentionally MagSgn-only single-block. Multi-block
// dispatch + MEL/VLC + integration with classifier + prefix-sum
// land in subsequent I1.2 / I1.3 PRs.

kernel void j2k_ht_magsgn_emit_block(
    device const uint2* items         [[buffer(0)]],
    constant     uint&  itemCount     [[buffer(1)]],
    device       uchar* output        [[buffer(2)]],
    constant     uint&  outputOffset  [[buffer(3)]],
    device       uint*  byteCountOut  [[buffer(4)]],
    uint tid                          [[thread_position_in_threadgroup]]
) {
    if (tid != 0u) return;

    uint tmp = 0u;
    uint usedBits = 0u;
    uint maxBits = 8u;
    uint byteIdx = 0u;

    for (uint i = 0u; i < itemCount; ++i) {
        uint cwd = items[i].x;
        uint len = items[i].y;
        while (len > 0u) {
            uint take = min(maxBits - usedBits, len);
            uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
            tmp |= (cwd & mask) << usedBits;
            usedBits += take;
            cwd >>= take;
            len -= take;
            if (usedBits >= maxBits) {
                uint b = tmp & 0xFFu;
                output[outputOffset + byteIdx] = (uchar)b;
                byteIdx += 1u;
                maxBits = (b == 0xFFu) ? 7u : 8u;
                tmp = 0u;
                usedBits = 0u;
            }
        }
    }

    // finish() — pad with 1-bits, drop the padded byte if it's 0xFF,
    // roll back the over-committed reserved-stuff slot if maxBits==7.
    if (usedBits != 0u) {
        uint padBits = maxBits - usedBits;
        uint padMask = (padBits >= 32u) ? 0xFFFFFFFFu : ((1u << padBits) - 1u);
        tmp |= padMask << usedBits;
        uint b = tmp & 0xFFu;
        if (b != 0xFFu) {
            output[outputOffset + byteIdx] = (uchar)b;
            byteIdx += 1u;
        }
    } else if (maxBits == 7u) {
        // ms_terminate rollback — un-emit the byte that reserved a
        // stuff-bit slot we never filled.
        byteIdx -= 1u;
    }

    *byteCountOut = byteIdx;
}

// ---------------------------------------------------------------------------
// v7.1.0 I1.2b — Pass 3 MagSgn batched byte-write (multi-block dispatch)
// ---------------------------------------------------------------------------
//
// Same per-block bit-emit logic as `j2k_ht_magsgn_emit_block`, but
// dispatched as one threadgroup per block. This is the production
// shape of Pass 3: ~2,300 blocks per DX 2x2 tile each get their own
// threadgroup. Apple M2's ~320 simultaneous threadgroups means each
// of the 10 GPU cores sees ~7 in-flight threadgroups, which is what
// the I1.0 design relies on to amortise the 31-idle-thread cost of
// the per-block-serial bit-write.
//
// Per-block descriptor (uint2):
//   .x = itemStart  — index into the flat items[] buffer
//   .y = itemCount  — how many (codeword, count) pairs belong to this block
//
// Per-block output offset:
//   offsets[blockIdx] — start byte index into output[] for this block.
//   **MUST be 4-byte aligned**, and the gap between consecutive
//   offsets must be ≥ the aligned-up byte budget for the block.
//   Apple Silicon implements `device uchar*` stores as 32-bit RMW,
//   so two threadgroups sharing a 4-byte word race — one wins, the
//   other's byte gets clobbered. Aligning each block's region to a
//   word boundary eliminates the race. The Swift wrapper helper
//   `J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets:)` computes
//   the canonical aligned offsets.
//
// Per-block byte count out:
//   byteCountsOut[blockIdx] — emitted byte count, written by thread 0
//   (raw count, not aligned-up).
//
// Bit-exactness: each block produces a stream byte-identical to
// `HTMagSgnEncoderConformant` — same FF-stuffing, same terminate
// rollback. Validated by `MetalHTForwardMagSgnEmitBatchedTests`'s
// per-block-vs-CPU sweep + the alignment regression-guard test.

kernel void j2k_ht_magsgn_emit_blocks_batched(
    device const uint2* items                [[buffer(0)]],
    device const uint2* blockDescriptors     [[buffer(1)]], // (itemStart, itemCount) per block
    device const uint*  outputOffsets        [[buffer(2)]],
    device       uchar* output               [[buffer(3)]],
    device       uint*  byteCountsOut        [[buffer(4)]],
    constant     uint&  blockCount           [[buffer(5)]],
    uint tid                                 [[thread_position_in_threadgroup]],
    uint tgIdx                               [[threadgroup_position_in_grid]]
) {
    if (tgIdx >= blockCount) return;
    if (tid != 0u) return;

    const uint2 desc = blockDescriptors[tgIdx];
    const uint  itemStart    = desc.x;
    const uint  itemCount    = desc.y;
    const uint  outputOffset = outputOffsets[tgIdx];

    uint tmp = 0u;
    uint usedBits = 0u;
    uint maxBits = 8u;
    uint byteIdx = 0u;

    for (uint i = 0u; i < itemCount; ++i) {
        uint cwd = items[itemStart + i].x;
        uint len = items[itemStart + i].y;
        while (len > 0u) {
            uint take = min(maxBits - usedBits, len);
            uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
            tmp |= (cwd & mask) << usedBits;
            usedBits += take;
            cwd >>= take;
            len -= take;
            if (usedBits >= maxBits) {
                uint b = tmp & 0xFFu;
                output[outputOffset + byteIdx] = (uchar)b;
                byteIdx += 1u;
                maxBits = (b == 0xFFu) ? 7u : 8u;
                tmp = 0u;
                usedBits = 0u;
            }
        }
    }

    if (usedBits != 0u) {
        uint padBits = maxBits - usedBits;
        uint padMask = (padBits >= 32u) ? 0xFFFFFFFFu : ((1u << padBits) - 1u);
        tmp |= padMask << usedBits;
        uint b = tmp & 0xFFu;
        if (b != 0xFFu) {
            output[outputOffset + byteIdx] = (uchar)b;
            byteIdx += 1u;
        }
    } else if (maxBits == 7u) {
        byteIdx -= 1u;
    }

    byteCountsOut[tgIdx] = byteIdx;
}

// ---------------------------------------------------------------------------
// v7.1.0 I1.2c — Pass 3 MEL batched byte-write (multi-block dispatch)
// ---------------------------------------------------------------------------
//
// Direct port of `HTForwardBitEmitterConformant.emit(bits:count:) +
// finish()` from `Sources/J2KCodec/J2KHTConformantBitStream.swift`.
//
// Differences vs the I1.2b MagSgn kernel:
//   - **MSB-first** bit packing (each emitted bit shifts tmp left by 1
//     and ORs the bit into the LSB; finish() left-shifts the partial
//     byte by `remainingBits` to position bits in the high half).
//     MagSgn is LSB-first.
//   - **No rollback** on terminate. If a 0xFF byte was just emitted
//     (so remainingBits == 7), finish() pads the next byte's low 7
//     bits with zeros and appends — even though the byte is just
//     stuff-bit padding. MagSgn rolls back the over-committed byte.
//   - **No pad-drops-FF** terminate rule. The padded byte is always
//     appended even if it's 0xFF (which can't happen here since
//     padding is zeros and high bits are real data).
//
// FF-stuffing rule is identical to MagSgn: after a 0xFF byte is
// emitted, the next byte's high bit is reserved as a 0 stuff bit
// (so `remainingBits` goes to 7 instead of 8).
//
// Same alignment requirement as I1.2b: per-block output regions
// must be 4-byte aligned to avoid Apple Silicon byte-store RMW
// races between concurrent threadgroups.

kernel void j2k_ht_mel_emit_blocks_batched(
    device const uint2* items                [[buffer(0)]],   // (codeword, count) per emit
    device const uint2* blockDescriptors     [[buffer(1)]],   // (itemStart, itemCount) per block
    device const uint*  outputOffsets        [[buffer(2)]],   // 4-byte-aligned per-block start
    device       uchar* output               [[buffer(3)]],
    device       uint*  byteCountsOut        [[buffer(4)]],
    constant     uint&  blockCount           [[buffer(5)]],
    uint tid                                 [[thread_position_in_threadgroup]],
    uint tgIdx                               [[threadgroup_position_in_grid]]
) {
    if (tgIdx >= blockCount) return;
    if (tid != 0u) return;

    const uint2 desc = blockDescriptors[tgIdx];
    const uint  itemStart    = desc.x;
    const uint  itemCount    = desc.y;
    const uint  outputOffset = outputOffsets[tgIdx];

    uint tmp = 0u;
    uint remainingBits = 8u;
    uint byteIdx = 0u;

    for (uint i = 0u; i < itemCount; ++i) {
        uint cwd = items[itemStart + i].x;
        uint c   = items[itemStart + i].y;
        // emit(bits: cwd, count: c) — MSB-first, one bit at a time.
        while (c > 0u) {
            c -= 1u;
            uint bit = (cwd >> c) & 1u;
            tmp = (tmp << 1) | bit;
            remainingBits -= 1u;
            if (remainingBits == 0u) {
                uint b = tmp & 0xFFu;
                output[outputOffset + byteIdx] = (uchar)b;
                byteIdx += 1u;
                remainingBits = (b == 0xFFu) ? 7u : 8u;
                tmp = 0u;
            }
        }
    }

    // finish(): if anything is in tmp, left-shift to position bits in
    // the high half of the byte (zero-pad the LSB side) and emit.
    if (remainingBits != 8u) {
        tmp <<= remainingBits;
        output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
        byteIdx += 1u;
    }

    byteCountsOut[tgIdx] = byteIdx;
}

// ---------------------------------------------------------------------------
// v7.1.0 I1.2d — Pass 3 VLC batched byte-write (reverse bit-stream)
// ---------------------------------------------------------------------------
//
// Direct port of `HTReverseBitEmitterConformant.encode + finish` from
// `Sources/J2KCodec/J2KHTConformantBitStream.swift`.
//
// The VLC stream is the trickiest of the three Pass 3 emit kernels:
//
//   - Bytes are packed **LSB-first** within each byte but the byte
//     SEQUENCE itself is built in REVERSE: the first emitted byte
//     ends up at the **end** of the on-wire stream, the last emitted
//     byte ends up at the start.
//   - The first byte of the on-wire stream is always `0xFF` (sentinel,
//     adjacent to the MagSgn region; ISO 15444-15).
//   - Reverse FF-stuffing: when the previous emitted byte was
//     `> 0x8F`, the next byte's **low** bit is reserved as a stuff
//     bit (0). There's a deferred-emit optimization: if the byte
//     after stuff would have low 7 bits != 0x7F, the stuff
//     reservation is "released" and the high bit becomes a real
//     data bit instead.
//   - Initial state: `tmp = 0x0F`, `usedBits = 4`,
//     `lastGreaterThan8F = true` — the 4 already-used bits represent
//     the initial 0xFF sentinel's downstream adjacency.
//
// Strategy: emit bytes forward into the per-block region (the
// sentinel goes at byteIdx=0, then each new emitted byte at
// byteIdx=1, 2, …). After all bits have been packed and any partial
// byte flushed by `finish()`, reverse the region in-place so the
// on-wire forward order matches the CPU reference's
// `emittedReversed.reversed()` return value.
//
// Same Apple-Silicon byte-store RMW alignment requirement as
// I1.2b/I1.2c: per-block output offsets MUST be 4-byte aligned.

kernel void j2k_ht_vlc_emit_blocks_batched(
    device const uint2* items                [[buffer(0)]],
    device const uint2* blockDescriptors     [[buffer(1)]],
    device const uint*  outputOffsets        [[buffer(2)]],
    device       uchar* output               [[buffer(3)]],
    device       uint*  byteCountsOut        [[buffer(4)]],
    constant     uint&  blockCount           [[buffer(5)]],
    uint tid                                 [[thread_position_in_threadgroup]],
    uint tgIdx                               [[threadgroup_position_in_grid]]
) {
    if (tgIdx >= blockCount) return;
    if (tid != 0u) return;

    const uint2 desc = blockDescriptors[tgIdx];
    const uint  itemStart    = desc.x;
    const uint  itemCount    = desc.y;
    const uint  outputOffset = outputOffsets[tgIdx];

    // Initial state: emittedReversed = [0xFF], tmp = 0x0F, usedBits = 4.
    output[outputOffset + 0u] = (uchar)0xFFu;
    uint byteIdx = 1u;

    uint tmp = 0x0Fu;
    uint usedBits = 4u;
    bool lastGreaterThan8F = true;

    for (uint i = 0u; i < itemCount; ++i) {
        uint cwd = items[itemStart + i].x;
        uint len = items[itemStart + i].y;
        while (len > 0u) {
            uint stuffPenalty = lastGreaterThan8F ? 1u : 0u;
            uint availBits = 8u - stuffPenalty - usedBits;
            uint take = min(availBits, len);
            if (take > 0u) {
                uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
                tmp |= (cwd & mask) << usedBits;
                usedBits += take;
                cwd >>= take;
                len -= take;
            }
            uint remainingAfter = availBits - take;
            if (remainingAfter == 0u) {
                if (lastGreaterThan8F && tmp != 0x7Fu) {
                    // Deferred stuff release: the "would-be" stuff
                    // byte has only 7 real bits and tmp != 0x7F, so
                    // we can sneak one more real bit into the high
                    // position by dropping the stuff reservation.
                    lastGreaterThan8F = false;
                    continue;
                }
                output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
                byteIdx += 1u;
                lastGreaterThan8F = (tmp > 0x8Fu);
                tmp = 0u;
                usedBits = 0u;
            }
        }
    }

    // finish(): flush any partial byte (no padding adjustment — the
    // CPU reference appends `tmp` directly).
    if (usedBits > 0u) {
        output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
        byteIdx += 1u;
    }

    // Reverse the per-block region in-place. CPU returns
    // `emittedReversed.reversed()`; we wrote the bytes forward into
    // the region in emit order, so flipping produces the on-wire
    // forward order.
    for (uint i = 0u; i < byteIdx / 2u; ++i) {
        uchar a = output[outputOffset + i];
        uchar b = output[outputOffset + byteIdx - 1u - i];
        output[outputOffset + i] = b;
        output[outputOffset + byteIdx - 1u - i] = a;
    }

    byteCountsOut[tgIdx] = byteIdx;
}

// ===========================================================================
// v7.1.0 I1.3b — unified Pass 3 cleanup-pass + 3-stream emit kernel
// ===========================================================================
//
// Direct port of `HTBlockEncoderConformant.encode(preClassifiedTuples:)`
// from `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` (lines
// 162-628) to MSL. One threadgroup per block; thread 0 of each group
// runs the entire cleanup-pass + 3-stream emit serially. Block-level
// parallelism (one threadgroup per block) is what fills the GPU.
//
// **Why one big kernel** — the per-block byte budgets cannot be
// derived from per-sample classification alone; the cleanup-pass
// state machine (MEL run-length, VLC Huffman, U-value derivation)
// determines them. Bit-packing primitives proven in I1.2 / I1.2b /
// I1.2c / I1.2d are inlined here (MSL forbids kernel-from-kernel
// calls). See `docs/V7_1_0_I1_3_DESIGN.md`.
//
// **Inputs**
//   tuples[]            — UInt64 per sample, packed as
//                         `sig:1 | eQ:7 | (24 unused) | payload:32`
//                         in row-major (y * width + x) order. Same
//                         format as `J2KMetalHTForwardClassifier`'s
//                         output and `processQuadFromTuples`'s input.
//   width, height       — block dimensions
//   missingMSBs         — coefficient bit-budget reduction; p = 30 - missingMSBs
//   vlcTable0, vlcTable1 — 2048-entry UInt16 lookup tables (initial
//                         row + subsequent rows)
//   uvlcTable           — 75-entry packed UVLCEntry table
//                         (uint2: .x = pre|preLen|suf|sufLen,
//                                 .y = ext|extLen)
//   melExp              — 13-entry MEL exponent table
//   outputMagSgnCap     — per-block upper-bound capacity for MagSgn region
//   outputMelCap        — per-block upper-bound capacity for MEL region
//   outputVlcCap        — per-block upper-bound capacity for VLC region
//
// **Outputs** (one block at offset blockIdx * cap_perStream)
//   magsgnOut, melOut, vlcOut — emitted bytes (with FF-stuff applied
//                              inline, matching CPU byte-for-byte)
//   magsgnByteCount, melByteCount, vlcByteCount — actual emitted
//                                                  byte counts (caller
//                                                  uses to compact)

// MARK: - cleanup-pass kernel state machine helpers (inline)

// MagSgn LSB-first bit packer with FF-stuff + ms_terminate semantics
// (mirrors `HTMagSgnEncoderConformant`). Used inline by the
// cleanup-pass kernel below.
inline void htclnp_magsgn_emit_bits(
    thread uint& tmp,
    thread uint& usedBits,
    thread uint& maxBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase,
    uint cwd,
    uint count
) {
    uint c = count;
    while (c > 0u) {
        uint take = min(maxBits - usedBits, c);
        uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
        tmp |= (cwd & mask) << usedBits;
        usedBits += take;
        cwd >>= take;
        c -= take;
        if (usedBits >= maxBits) {
            uint b = tmp & 0xFFu;
            output[outputBase + byteIdx] = (uchar)b;
            byteIdx += 1u;
            maxBits = (b == 0xFFu) ? 7u : 8u;
            tmp = 0u;
            usedBits = 0u;
        }
    }
}

inline void htclnp_magsgn_finish(
    thread uint& tmp,
    thread uint& usedBits,
    thread uint& maxBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase
) {
    if (usedBits != 0u) {
        uint padBits = maxBits - usedBits;
        uint padMask = (padBits >= 32u) ? 0xFFFFFFFFu : ((1u << padBits) - 1u);
        tmp |= padMask << usedBits;
        uint b = tmp & 0xFFu;
        if (b != 0xFFu) {
            output[outputBase + byteIdx] = (uchar)b;
            byteIdx += 1u;
        }
    } else if (maxBits == 7u) {
        byteIdx -= 1u;
    }
}

// MEL forward MSB-first bit emitter — used by the MEL coder below
// for both the threshold-emit-1 path and the event-emit-0-then-bits
// path. Mirrors `HTForwardBitEmitterConformant.emit(bit:)`.
inline void htclnp_mel_emit_bit(
    thread uint& tmp,
    thread uint& remainingBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase,
    uint bit
) {
    tmp = (tmp << 1) | (bit & 1u);
    remainingBits -= 1u;
    if (remainingBits == 0u) {
        uint b = tmp & 0xFFu;
        output[outputBase + byteIdx] = (uchar)b;
        byteIdx += 1u;
        remainingBits = (b == 0xFFu) ? 7u : 8u;
        tmp = 0u;
    }
}

inline void htclnp_mel_finish(
    thread uint& tmp,
    thread uint& remainingBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase
) {
    if (remainingBits != 8u) {
        tmp <<= remainingBits;
        output[outputBase + byteIdx] = (uchar)(tmp & 0xFFu);
        byteIdx += 1u;
    }
}

// MEL state machine — encodes one binary event. Mirrors
// `HTMELEncoderConformant.encode(eventIsOne:)`.
inline void htclnp_mel_encode_event(
    thread int& state,
    thread int& run,
    thread int& threshold,
    thread uint& tmp,
    thread uint& remainingBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase,
    constant uchar* melExp,
    bool eventIsOne
) {
    if (!eventIsOne) {
        run += 1;
        if (run >= threshold) {
            htclnp_mel_emit_bit(tmp, remainingBits, byteIdx, output, outputBase, 1u);
            run = 0;
            state = min(12, state + 1);
            threshold = 1 << int(melExp[state]);
        }
    } else {
        htclnp_mel_emit_bit(tmp, remainingBits, byteIdx, output, outputBase, 0u);
        int t = int(melExp[state]);
        while (t > 0) {
            t -= 1;
            htclnp_mel_emit_bit(tmp, remainingBits, byteIdx, output, outputBase,
                                uint((run >> t) & 1));
        }
        run = 0;
        state = max(0, state - 1);
        threshold = 1 << int(melExp[state]);
    }
}

inline void htclnp_mel_flush(
    thread int& state,
    thread int& run,
    thread int& threshold,
    thread uint& tmp,
    thread uint& remainingBits,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase
) {
    // If a non-terminated zero run is open, emit a final 1 bit to
    // close it (mirrors CPU `HTMELEncoderConformant.finish`).
    if (run > 0) {
        htclnp_mel_emit_bit(tmp, remainingBits, byteIdx, output, outputBase, 1u);
    }
    htclnp_mel_finish(tmp, remainingBits, byteIdx, output, outputBase);
}

// VLC reverse-bit emit — LSB-first within byte, byte SEQUENCE built
// in REVERSE then flipped at terminate. Mirrors
// `HTReverseBitEmitterConformant.encode(codeword:count:)`.
inline void htclnp_vlc_emit_bits(
    thread uint& tmp,
    thread uint& usedBits,
    thread bool& lastGreaterThan8F,
    thread uint& byteIdx,
    device uchar* output,
    uint outputBase,
    uint cwd,
    uint count
) {
    uint c = count;
    while (c > 0u) {
        uint stuffPenalty = lastGreaterThan8F ? 1u : 0u;
        uint availBits = 8u - stuffPenalty - usedBits;
        uint take = min(availBits, c);
        if (take > 0u) {
            uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
            tmp |= (cwd & mask) << usedBits;
            usedBits += take;
            cwd >>= take;
            c -= take;
        }
        uint remainingAfter = availBits - take;
        if (remainingAfter == 0u) {
            if (lastGreaterThan8F && tmp != 0x7Fu) {
                lastGreaterThan8F = false;
                continue;
            }
            output[outputBase + byteIdx] = (uchar)(tmp & 0xFFu);
            byteIdx += 1u;
            lastGreaterThan8F = (tmp > 0x8Fu);
            tmp = 0u;
            usedBits = 0u;
        }
    }
}

// MARK: - cleanup-pass kernel (single-block; one threadgroup per block)
//
// I1.3b-spike: dispatched as one threadgroup; thread 0 does the
// whole serial cleanup-pass. blockIdx (threadgroup_position_in_grid)
// is unused for now (single-block) — I1.3c will add multi-block.

// v7.1.0 I1.3c — batched (multi-block) cleanup-pass kernel. One
// threadgroup per block; per-block dimensions, tuple-stream offset,
// and per-stream output offsets come from arrays indexed by
// `threadgroup_position_in_grid`. blockCount=1 collapses this to
// the I1.3b single-block path; the canonical kernel for both cases.
//
// **Output offset alignment**: per-stream output offsets MUST be
// 4-byte aligned (Apple Silicon `device uchar*` stores RMW on the
// containing 32-bit word; concurrent threadgroups sharing a word
// race — see I1.2b). Use the Swift wrapper's helpers to compute
// aligned offsets from per-block byte budgets.
kernel void j2k_ht_cleanup_pass_emit_blocks_batched(
    device const ulong*  tuples              [[buffer(0)]],
    device const uint4*  blockDims           [[buffer(1)]],   // (width, height, missingMSBs, tupleStart) per block
    device const ushort* vlcTable0           [[buffer(2)]],
    device const ushort* vlcTable1           [[buffer(3)]],
    device const uint2*  uvlcTable           [[buffer(4)]],   // (.x = pre|preLen|suf|sufLen, .y = ext|extLen)
    constant     uchar*  melExp              [[buffer(5)]],   // 13 entries
    device       uchar*  magsgnOut           [[buffer(6)]],
    device const uint*   magsgnOffsets       [[buffer(7)]],   // 4-byte-aligned per-block start
    device       uchar*  melOut              [[buffer(8)]],
    device const uint*   melOffsets          [[buffer(9)]],
    device       uchar*  vlcOut              [[buffer(10)]],
    device const uint*   vlcOffsets          [[buffer(11)]],
    device       uint3*  byteCountsOut       [[buffer(12)]],  // (magsgn, mel, vlc) per block
    constant     uint&   blockCount          [[buffer(13)]],
    uint tid                                 [[thread_position_in_threadgroup]],
    uint tgIdx                               [[threadgroup_position_in_grid]]
) {
    if (tgIdx >= blockCount) return;
    if (tid != 0u) return;

    // Per-block descriptor + per-stream output bases.
    const uint4 dims = blockDims[tgIdx];
    const uint  width        = dims.x;
    const uint  height       = dims.y;
    // dims.z is missingMSBs; not needed (p is implicit in tuple payloads).
    const uint  tupleStart   = dims.w;
    const uint  magsgnBase   = magsgnOffsets[tgIdx];
    const uint  melBase      = melOffsets[tgIdx];
    const uint  vlcBase      = vlcOffsets[tgIdx];

    // Block-level state: per-stream emit accumulators + cleanup-pass
    // bookkeeping. All in registers (or LLVM's spill if too many).

    // MagSgn emit state
    uint ms_tmp = 0u;
    uint ms_usedBits = 0u;
    uint ms_maxBits = 8u;
    uint ms_byteIdx = 0u;

    // MEL coder state (state machine + bit emitter)
    int  mel_state = 0;
    int  mel_run = 0;
    int  mel_threshold = 1 << int(melExp[0]);
    uint mel_tmp = 0u;
    uint mel_remainingBits = 8u;
    uint mel_byteIdx = 0u;

    // VLC reverse-bit emitter
    uint vlc_tmp = 0x0Fu;
    uint vlc_usedBits = 4u;
    bool vlc_lastGreaterThan8F = true;
    uint vlc_byteIdx = 1u;
    vlcOut[vlcBase + 0u] = (uchar)0xFFu;   // sentinel at emit-order index 0

    // dims.z (missingMSBs) is implicit in pre-classified tuple payloads,
    // so the kernel doesn't need to read it. We retain it in the
    // descriptor for parity with the CPU `encode(preClassifiedTuples:)`
    // signature so the wrapper can pass through any future tuple format
    // changes without breaking the layout.

    // Per-row context state. Sized to support up to 64-wide blocks
    // (J2K HT codeblock max). guardedWidth ≤ ((64+3)/4)*2 + 2 = 34.
    threadgroup uchar eVal[64];
    threadgroup uchar cxVal[64];
    for (uint i = 0u; i < 64u; ++i) {
        eVal[i] = 0;
        cxVal[i] = 0;
    }

    int c_q0 = 0;
    int lep = 0;
    int lcxp = 0;

    // ----- helper inline lambda equivalents (Metal has no closures)
    // We unpack tuples and build per-quad state inline below.

    if (height > 0u) {
        // --- Initial row of quads (y = 0..1) — uses vlcTable0 ---
        uint spX = 0u;
        while (spX < width) {
            // q0 = processQuadFromTuples(spX, 0)
            int rho0 = 0, eQMax0 = 0;
            int eQ0_0 = 0, eQ0_1 = 0, eQ0_2 = 0, eQ0_3 = 0;
            uint s0_0 = 0, s0_1 = 0, s0_2 = 0, s0_3 = 0;
            // (col, row) layout: (0,0), (0,1), (1,0), (1,1)
            // out-of-bounds → zero tuple
            #define UNPACK_TUPLE(_X, _Y, _RHO_BIT, _SET_E, _SET_S) \
                if ((_X) < width && (_Y) < height) { \
                    ulong raw = tuples[tupleStart + ((_Y) * width) + (_X)]; \
                    bool sig = ((raw >> 63) & 1ul) != 0ul; \
                    int eQ = int((raw >> 56) & 0x7Ful); \
                    uint payload = uint(raw & 0xFFFFFFFFul); \
                    if (sig) { rho0 |= _RHO_BIT; _SET_E = eQ; _SET_S = payload; if (eQ > eQMax0) eQMax0 = eQ; } \
                }
            UNPACK_TUPLE(spX,     0u, 1, eQ0_0, s0_0)
            UNPACK_TUPLE(spX,     1u, 2, eQ0_1, s0_1)
            UNPACK_TUPLE(spX + 1u,0u, 4, eQ0_2, s0_2)
            UNPACK_TUPLE(spX + 1u,1u, 8, eQ0_3, s0_3)
            #undef UNPACK_TUPLE

            int Uq0 = max(eQMax0, 1);
            int u_q0 = Uq0 - 1;
            int eps0 = 0;
            if (u_q0 > 0) {
                if (eQ0_0 == eQMax0) eps0 |= 1;
                if (eQ0_1 == eQMax0) eps0 |= 2;
                if (eQ0_2 == eQMax0) eps0 |= 4;
                if (eQ0_3 == eQMax0) eps0 |= 8;
            }

            eVal[lep] = (uchar)max((int)eVal[lep], eQ0_1); lep += 1;
            eVal[lep] = (uchar)eQ0_3;
            cxVal[lcxp] = cxVal[lcxp] | (uchar)((rho0 & 2) >> 1); lcxp += 1;
            cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);

            uint t0idx = (uint(c_q0) << 8) | (uint(rho0) << 4) | uint(eps0);
            uint tuple0 = uint(vlcTable0[t0idx]);
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 tuple0 >> 8u, (tuple0 >> 4u) & 0x7u);

            if (c_q0 == 0) {
                htclnp_mel_encode_event(mel_state, mel_run, mel_threshold,
                                        mel_tmp, mel_remainingBits, mel_byteIdx,
                                        melOut, melBase, melExp, rho0 != 0);
            }

            // emitQuadMagSgn for q0
            // emit each significant sample: m = Uq - eBit; sample & ((1<<m)-1)
            #define MS_EMIT(_BIT, _SAMPLE, _EBIT) \
                if ((rho0 & _BIT) != 0) { \
                    int m = Uq0 - (_EBIT); \
                    uint mask = (m >= 32) ? 0xFFFFFFFFu : ((1u << uint(m)) - 1u); \
                    htclnp_magsgn_emit_bits(ms_tmp, ms_usedBits, ms_maxBits, \
                                            ms_byteIdx, magsgnOut, magsgnBase, \
                                            (_SAMPLE) & mask, uint(m)); \
                }
            MS_EMIT(1, s0_0, int(tuple0) & 1)
            MS_EMIT(2, s0_1, (int(tuple0) >> 1) & 1)
            MS_EMIT(4, s0_2, (int(tuple0) >> 2) & 1)
            MS_EMIT(8, s0_3, (int(tuple0) >> 3) & 1)
            #undef MS_EMIT

            // Second quad of pair (might be out of bounds)
            int rho1 = 0;
            int u_q1 = 0;
            uint tuple1 = 0u;
            int Uq1 = 0;
            uint s1_0 = 0, s1_1 = 0, s1_2 = 0, s1_3 = 0;
            if (spX + 2u < width) {
                int eQMax1 = 0;
                int eQ1_0 = 0, eQ1_1 = 0, eQ1_2 = 0, eQ1_3 = 0;
                #define UNPACK_TUPLE1(_X, _Y, _RHO_BIT, _SET_E, _SET_S) \
                    if ((_X) < width && (_Y) < height) { \
                        ulong raw = tuples[tupleStart + ((_Y) * width) + (_X)]; \
                        bool sig = ((raw >> 63) & 1ul) != 0ul; \
                        int eQ = int((raw >> 56) & 0x7Ful); \
                        uint payload = uint(raw & 0xFFFFFFFFul); \
                        if (sig) { rho1 |= _RHO_BIT; _SET_E = eQ; _SET_S = payload; if (eQ > eQMax1) eQMax1 = eQ; } \
                    }
                UNPACK_TUPLE1(spX + 2u, 0u, 1, eQ1_0, s1_0)
                UNPACK_TUPLE1(spX + 2u, 1u, 2, eQ1_1, s1_1)
                UNPACK_TUPLE1(spX + 3u, 0u, 4, eQ1_2, s1_2)
                UNPACK_TUPLE1(spX + 3u, 1u, 8, eQ1_3, s1_3)
                #undef UNPACK_TUPLE1

                int c_q1 = (rho0 >> 1) | (rho0 & 1);
                Uq1 = max(eQMax1, 1);
                u_q1 = Uq1 - 1;
                int eps1 = 0;
                if (u_q1 > 0) {
                    if (eQ1_0 == eQMax1) eps1 |= 1;
                    if (eQ1_1 == eQMax1) eps1 |= 2;
                    if (eQ1_2 == eQMax1) eps1 |= 4;
                    if (eQ1_3 == eQMax1) eps1 |= 8;
                }
                eVal[lep] = (uchar)max((int)eVal[lep], eQ1_1); lep += 1;
                eVal[lep] = (uchar)eQ1_3;
                cxVal[lcxp] = cxVal[lcxp] | (uchar)((rho1 & 2) >> 1); lcxp += 1;
                cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);

                uint t1idx = (uint(c_q1) << 8) | (uint(rho1) << 4) | uint(eps1);
                tuple1 = uint(vlcTable0[t1idx]);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     tuple1 >> 8u, (tuple1 >> 4u) & 0x7u);
                if (c_q1 == 0) {
                    htclnp_mel_encode_event(mel_state, mel_run, mel_threshold,
                                            mel_tmp, mel_remainingBits, mel_byteIdx,
                                            melOut, melBase, melExp, rho1 != 0);
                }
                #define MS_EMIT1(_BIT, _SAMPLE, _EBIT) \
                    if ((rho1 & _BIT) != 0) { \
                        int m = Uq1 - (_EBIT); \
                        uint mask = (m >= 32) ? 0xFFFFFFFFu : ((1u << uint(m)) - 1u); \
                        htclnp_magsgn_emit_bits(ms_tmp, ms_usedBits, ms_maxBits, \
                                                ms_byteIdx, magsgnOut, magsgnBase, \
                                                (_SAMPLE) & mask, uint(m)); \
                    }
                MS_EMIT1(1, s1_0, int(tuple1) & 1)
                MS_EMIT1(2, s1_1, (int(tuple1) >> 1) & 1)
                MS_EMIT1(4, s1_2, (int(tuple1) >> 2) & 1)
                MS_EMIT1(8, s1_3, (int(tuple1) >> 3) & 1)
                #undef MS_EMIT1
            }

            // u-value encoding
            #define UVLC_EMIT(_IDX) { \
                uint2 e = uvlcTable[_IDX]; \
                uint pre = e.x & 0xFFu; \
                uint preLen = (e.x >> 8u) & 0xFFu; \
                uint suf = (e.x >> 16u) & 0xFFu; \
                uint sufLen = (e.x >> 24u) & 0xFFu; \
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F, \
                                     vlc_byteIdx, vlcOut, vlcBase, pre, preLen); \
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F, \
                                     vlc_byteIdx, vlcOut, vlcBase, suf, sufLen); \
            }
            // Initial row uses 4 different code paths depending on u_q0/u_q1.
            if (u_q0 > 0 && u_q1 > 0) {
                htclnp_mel_encode_event(mel_state, mel_run, mel_threshold,
                                        mel_tmp, mel_remainingBits, mel_byteIdx,
                                        melOut, melBase, melExp, min(u_q0, u_q1) > 2);
            }
            if (u_q0 > 2 && u_q1 > 2) {
                uint2 e0 = uvlcTable[u_q0 - 2];
                uint2 e1 = uvlcTable[u_q1 - 2];
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     e0.x & 0xFFu, (e0.x >> 8u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     e1.x & 0xFFu, (e1.x >> 8u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     (e0.x >> 16u) & 0xFFu, (e0.x >> 24u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     (e1.x >> 16u) & 0xFFu, (e1.x >> 24u) & 0xFFu);
            } else if (u_q0 > 2 && u_q1 > 0) {
                uint2 e0 = uvlcTable[u_q0];
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     e0.x & 0xFFu, (e0.x >> 8u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     uint(u_q1 - 1), 1u);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     (e0.x >> 16u) & 0xFFu, (e0.x >> 24u) & 0xFFu);
            } else {
                uint2 e0 = uvlcTable[u_q0];
                uint2 e1 = uvlcTable[u_q1];
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     e0.x & 0xFFu, (e0.x >> 8u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     e1.x & 0xFFu, (e1.x >> 8u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     (e0.x >> 16u) & 0xFFu, (e0.x >> 24u) & 0xFFu);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     (e1.x >> 16u) & 0xFFu, (e1.x >> 24u) & 0xFFu);
            }
            #undef UVLC_EMIT

            c_q0 = (rho1 >> 1) | (rho1 & 1);
            spX += 4u;
        }
    }
    if (lep + 1 < 64) eVal[lep + 1] = 0;

    // --- Subsequent quad rows (y = 2, 4, ...) — uses vlcTable1 ---
    uint y = 2u;
    while (y < height) {
        lep = 0;
        int maxE = max(int(eVal[0]), int(eVal[1])) - 1;
        eVal[0] = 0;
        lcxp = 0;
        c_q0 = int(cxVal[0]) + (int(cxVal[1]) << 2);
        cxVal[0] = 0;

        uint spX = 0u;
        while (spX < width) {
            int rho0 = 0, eQMax0 = 0;
            int eQ0_0 = 0, eQ0_1 = 0, eQ0_2 = 0, eQ0_3 = 0;
            uint s0_0 = 0, s0_1 = 0, s0_2 = 0, s0_3 = 0;
            #define UNPACK_TUPLE_R(_X, _Y, _RHO_BIT, _SET_E, _SET_S) \
                if ((_X) < width && (_Y) < height) { \
                    ulong raw = tuples[tupleStart + ((_Y) * width) + (_X)]; \
                    bool sig = ((raw >> 63) & 1ul) != 0ul; \
                    int eQ = int((raw >> 56) & 0x7Ful); \
                    uint payload = uint(raw & 0xFFFFFFFFul); \
                    if (sig) { rho0 |= _RHO_BIT; _SET_E = eQ; _SET_S = payload; if (eQ > eQMax0) eQMax0 = eQ; } \
                }
            UNPACK_TUPLE_R(spX,      y,      1, eQ0_0, s0_0)
            UNPACK_TUPLE_R(spX,      y + 1u, 2, eQ0_1, s0_1)
            UNPACK_TUPLE_R(spX + 1u, y,      4, eQ0_2, s0_2)
            UNPACK_TUPLE_R(spX + 1u, y + 1u, 8, eQ0_3, s0_3)
            #undef UNPACK_TUPLE_R

            int kappaA = ((rho0 & (rho0 - 1)) != 0) ? max(1, maxE) : 1;
            int Uq0 = max(eQMax0, kappaA);
            int u_q0 = Uq0 - kappaA;
            int eps0 = 0;
            if (u_q0 > 0) {
                if (eQ0_0 == eQMax0) eps0 |= 1;
                if (eQ0_1 == eQMax0) eps0 |= 2;
                if (eQ0_2 == eQMax0) eps0 |= 4;
                if (eQ0_3 == eQMax0) eps0 |= 8;
            }
            eVal[lep] = (uchar)max((int)eVal[lep], eQ0_1); lep += 1;
            maxE = max(int(eVal[lep]), int(eVal[lep + 1])) - 1;
            eVal[lep] = (uchar)eQ0_3;
            cxVal[lcxp] = cxVal[lcxp] | (uchar)((rho0 & 2) >> 1); lcxp += 1;
            int c_q1 = int(cxVal[lcxp]) + (int(cxVal[lcxp + 1]) << 2);
            cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);

            uint t0idx = (uint(c_q0) << 8) | (uint(rho0) << 4) | uint(eps0);
            uint tuple0 = uint(vlcTable1[t0idx]);
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 tuple0 >> 8u, (tuple0 >> 4u) & 0x7u);
            if (c_q0 == 0) {
                htclnp_mel_encode_event(mel_state, mel_run, mel_threshold,
                                        mel_tmp, mel_remainingBits, mel_byteIdx,
                                        melOut, melBase, melExp, rho0 != 0);
            }
            #define MS_EMIT_R(_BIT, _SAMPLE, _EBIT) \
                if ((rho0 & _BIT) != 0) { \
                    int m = Uq0 - (_EBIT); \
                    uint mask = (m >= 32) ? 0xFFFFFFFFu : ((1u << uint(m)) - 1u); \
                    htclnp_magsgn_emit_bits(ms_tmp, ms_usedBits, ms_maxBits, \
                                            ms_byteIdx, magsgnOut, magsgnBase, \
                                            (_SAMPLE) & mask, uint(m)); \
                }
            MS_EMIT_R(1, s0_0, int(tuple0) & 1)
            MS_EMIT_R(2, s0_1, (int(tuple0) >> 1) & 1)
            MS_EMIT_R(4, s0_2, (int(tuple0) >> 2) & 1)
            MS_EMIT_R(8, s0_3, (int(tuple0) >> 3) & 1)
            #undef MS_EMIT_R

            int rho1 = 0;
            int u_q1 = 0;
            uint tuple1 = 0u;
            int Uq1 = 0;
            uint s1_0 = 0, s1_1 = 0, s1_2 = 0, s1_3 = 0;
            if (spX + 2u < width) {
                int eQMax1 = 0;
                int eQ1_0 = 0, eQ1_1 = 0, eQ1_2 = 0, eQ1_3 = 0;
                #define UNPACK_TUPLE_R1(_X, _Y, _RHO_BIT, _SET_E, _SET_S) \
                    if ((_X) < width && (_Y) < height) { \
                        ulong raw = tuples[tupleStart + ((_Y) * width) + (_X)]; \
                        bool sig = ((raw >> 63) & 1ul) != 0ul; \
                        int eQ = int((raw >> 56) & 0x7Ful); \
                        uint payload = uint(raw & 0xFFFFFFFFul); \
                        if (sig) { rho1 |= _RHO_BIT; _SET_E = eQ; _SET_S = payload; if (eQ > eQMax1) eQMax1 = eQ; } \
                    }
                UNPACK_TUPLE_R1(spX + 2u, y,      1, eQ1_0, s1_0)
                UNPACK_TUPLE_R1(spX + 2u, y + 1u, 2, eQ1_1, s1_1)
                UNPACK_TUPLE_R1(spX + 3u, y,      4, eQ1_2, s1_2)
                UNPACK_TUPLE_R1(spX + 3u, y + 1u, 8, eQ1_3, s1_3)
                #undef UNPACK_TUPLE_R1

                int kappaB = ((rho1 & (rho1 - 1)) != 0) ? max(1, maxE) : 1;
                c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2);
                Uq1 = max(eQMax1, kappaB);
                u_q1 = Uq1 - kappaB;
                int eps1 = 0;
                if (u_q1 > 0) {
                    if (eQ1_0 == eQMax1) eps1 |= 1;
                    if (eQ1_1 == eQMax1) eps1 |= 2;
                    if (eQ1_2 == eQMax1) eps1 |= 4;
                    if (eQ1_3 == eQMax1) eps1 |= 8;
                }
                eVal[lep] = (uchar)max((int)eVal[lep], eQ1_1); lep += 1;
                maxE = max(int(eVal[lep]), int(eVal[lep + 1])) - 1;
                eVal[lep] = (uchar)eQ1_3;
                cxVal[lcxp] = cxVal[lcxp] | (uchar)((rho1 & 2) >> 1); lcxp += 1;
                c_q0 = int(cxVal[lcxp]) + (int(cxVal[lcxp + 1]) << 2);
                cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);

                uint t1idx = (uint(c_q1) << 8) | (uint(rho1) << 4) | uint(eps1);
                tuple1 = uint(vlcTable1[t1idx]);
                htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                     vlc_byteIdx, vlcOut, vlcBase,
                                     tuple1 >> 8u, (tuple1 >> 4u) & 0x7u);
                if (c_q1 == 0) {
                    htclnp_mel_encode_event(mel_state, mel_run, mel_threshold,
                                            mel_tmp, mel_remainingBits, mel_byteIdx,
                                            melOut, melBase, melExp, rho1 != 0);
                }
                #define MS_EMIT_R1(_BIT, _SAMPLE, _EBIT) \
                    if ((rho1 & _BIT) != 0) { \
                        int m = Uq1 - (_EBIT); \
                        uint mask = (m >= 32) ? 0xFFFFFFFFu : ((1u << uint(m)) - 1u); \
                        htclnp_magsgn_emit_bits(ms_tmp, ms_usedBits, ms_maxBits, \
                                                ms_byteIdx, magsgnOut, magsgnBase, \
                                                (_SAMPLE) & mask, uint(m)); \
                    }
                MS_EMIT_R1(1, s1_0, int(tuple1) & 1)
                MS_EMIT_R1(2, s1_1, (int(tuple1) >> 1) & 1)
                MS_EMIT_R1(4, s1_2, (int(tuple1) >> 2) & 1)
                MS_EMIT_R1(8, s1_3, (int(tuple1) >> 3) & 1)
                #undef MS_EMIT_R1
            }

            // Subsequent rows: unconditional UVLC per quad pair.
            uint2 e0u = uvlcTable[u_q0];
            uint2 e1u = uvlcTable[u_q1];
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 e0u.x & 0xFFu, (e0u.x >> 8u) & 0xFFu);
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 e1u.x & 0xFFu, (e1u.x >> 8u) & 0xFFu);
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 (e0u.x >> 16u) & 0xFFu, (e0u.x >> 24u) & 0xFFu);
            htclnp_vlc_emit_bits(vlc_tmp, vlc_usedBits, vlc_lastGreaterThan8F,
                                 vlc_byteIdx, vlcOut, vlcBase,
                                 (e1u.x >> 16u) & 0xFFu, (e1u.x >> 24u) & 0xFFu);

            c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2);
            spX += 4u;
        }
        y += 2u;
    }

    // ----- finish steps (per CPU encoder) -----
    htclnp_magsgn_finish(ms_tmp, ms_usedBits, ms_maxBits, ms_byteIdx, magsgnOut, magsgnBase);
    htclnp_mel_flush(mel_state, mel_run, mel_threshold,
                     mel_tmp, mel_remainingBits, mel_byteIdx, melOut, melBase);
    // VLC: flush any partial byte (CPU `HTReverseBitEmitterConformant.finish`).
    if (vlc_usedBits > 0u) {
        vlcOut[vlcBase + vlc_byteIdx] = (uchar)(vlc_tmp & 0xFFu);
        vlc_byteIdx += 1u;
    }
    // Reverse the VLC region in-place to produce on-wire forward order.
    for (uint i = 0u; i < vlc_byteIdx / 2u; ++i) {
        uchar a = vlcOut[vlcBase + i];
        uchar b = vlcOut[vlcBase + vlc_byteIdx - 1u - i];
        vlcOut[vlcBase + i] = b;
        vlcOut[vlcBase + vlc_byteIdx - 1u - i] = a;
    }

    byteCountsOut[tgIdx] = uint3(ms_byteIdx, mel_byteIdx, vlc_byteIdx);
}

// ---------------------------------------------------------------------------
// v7.1.0 H2 — Inverse 5/3 Reversible DWT (parity-aware, odd-origin)
// ---------------------------------------------------------------------------
//
// Direct port of `inverseTransform53OddOriginSymmetric` from
// `Sources/J2KCodec/J2KDWT1DOptimized.swift` to MSL. The even-origin
// inverse kernels above always assumed canvas origin (0, 0); for
// multi-tile per-tile decode where the band's canvas origin is odd
// at a given decomposition level, we need the parity-aware lifting
// equations. ISO/IEC 15444-1 Annex F.4.1.1.
//
// **Differences vs even-origin inverse**:
//   1. Step 1 (undo update on L) — for odd origin, only RIGHT mirror
//      (`H[i+1] → H[highCount-1]` when `i+1 >= highCount`). NO left
//      mirror — the lifting starts from `H[i]` itself (not `H[i-1]`).
//   2. Step 2 (undo predict on H) — three regions:
//        * H[0]   += L[0]                     (no left mirror)
//        * H[i]   += ((L[i-1] + L[i]) >> 1)   for 1 ≤ i < min(highCount, lowCount)
//        * H[lowCount] += L[lowCount-1]       (right tail when n odd)
//   3. Interleave is **flipped**:
//        * even origin: x[2i] = L, x[2i+1] = H
//        * odd  origin: x[2i] = H, x[2i+1] = L
//
// This kernel writes directly to the output buffer at the final
// interleaved positions. Step 1's L-update goes to output[2i+1];
// step 2 reads those positions back as L_updated when computing
// H_updated, which lands at output[2i]. The intra-row dependency
// is sequential within the lifting steps but read-write doesn't
// race because step 1 fills only odd-indexed slots and step 2
// fills only even-indexed slots.
//
// Bit-exact with `J2KDWT1DOptimized.inverseTransform53OddOriginSymmetric`;
// validated by `J2KMetalDWT53IntOddOriginBitExactTests`.

kernel void j2k_dwt_inverse_53_horizontal_int_odd(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.y >= height) return;

    uint row = gid.y;
    // Odd origin: highCount = ceil(n/2), lowCount = floor(n/2).
    uint lowCount  = width / 2;
    uint highCount = width - lowCount;

    uint lBase = row * lowCount;
    uint hBase = row * highCount;
    uint oBase = row * width;

    // Edge case: lowCount == 0 (width = 1, n odd) — only H sample,
    // goes to output[0] under odd interleave.
    if (lowCount == 0) {
        if (highCount > 0) {
            output[oBase] = highpass[hBase];
        }
        return;
    }

    // Step 1: undo update on L.
    //   L[i] -= ((H[i] + H[i+1] + 2) >> 2)
    // Right mirror: H[i+1] → H[highCount - 1] when i+1 >= highCount.
    // L_updated lands at output[2i + 1] (odd-origin interleave).
    for (uint i = 0; i < lowCount; i++) {
        int hLeft  = highpass[hBase + i];
        int hRight = (i + 1 < highCount)
            ? highpass[hBase + i + 1]
            : highpass[hBase + highCount - 1];
        output[oBase + 2 * i + 1] = lowpass[lBase + i] - ((hLeft + hRight + 2) >> 2);
    }

    // Step 2: undo predict on H.
    //   H[0]   += L[0]                                  (left)
    //   H[i]   += ((L[i-1] + L[i]) >> 1)                (interior, 1 ≤ i < min(highCount, lowCount))
    //   H[lowCount] += L[lowCount-1]                    (right tail, n odd)
    // H_updated lands at output[2i] (odd-origin interleave).
    if (highCount > 0) {
        // L[0] is at output[1] (already written in Step 1).
        output[oBase] = highpass[hBase] + output[oBase + 1];
    }
    uint interiorEnd = min(highCount, lowCount);
    for (uint i = 1; i < interiorEnd; i++) {
        int lLeft  = output[oBase + 2 * (i - 1) + 1];
        int lRight = output[oBase + 2 * i + 1];
        output[oBase + 2 * i] = highpass[hBase + i] + ((lLeft + lRight) >> 1);
    }
    if (highCount > lowCount) {
        // H[lowCount] += L[lowCount - 1]; output position 2 * lowCount.
        int lLast = output[oBase + 2 * (lowCount - 1) + 1];
        output[oBase + 2 * lowCount] = highpass[hBase + lowCount] + lLast;
    }
}

// MARK: - Inverse 5/3 Reversible DWT (Vertical, integer / odd origin)

kernel void j2k_dwt_inverse_53_vertical_int_odd(
    device const int* lowpass [[buffer(0)]],
    device const int* highpass [[buffer(1)]],
    device int* output [[buffer(2)]],
    constant uint& width [[buffer(3)]],
    constant uint& height [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= width) return;

    uint col = gid.x;
    // Odd origin (vertical): high → ceil, low → floor of height.
    uint lowCount  = height / 2;
    uint highCount = height - lowCount;

    if (lowCount == 0) {
        if (highCount > 0) {
            output[col] = highpass[col];   // H → row 0 in odd interleave
        }
        return;
    }

    // Step 1: undo update on L (per-column lift). L_updated lands at
    // output row (2 * i + 1), column `col`.
    for (uint i = 0; i < lowCount; i++) {
        int hTop = highpass[i * width + col];
        int hBot = (i + 1 < highCount)
            ? highpass[(i + 1) * width + col]
            : highpass[(highCount - 1) * width + col];
        output[(2 * i + 1) * width + col] = lowpass[i * width + col]
                                          - ((hTop + hBot + 2) >> 2);
    }

    // Step 2: undo predict on H. H_updated lands at row (2 * i).
    if (highCount > 0) {
        output[col] = highpass[col] + output[width + col];   // H[0] += L[0]
    }
    uint interiorEnd = min(highCount, lowCount);
    for (uint i = 1; i < interiorEnd; i++) {
        int lTop = output[(2 * (i - 1) + 1) * width + col];
        int lBot = output[(2 * i + 1) * width + col];
        output[(2 * i) * width + col] = highpass[i * width + col]
                                      + ((lTop + lBot) >> 1);
    }
    if (highCount > lowCount) {
        int lLast = output[(2 * (lowCount - 1) + 1) * width + col];
        output[(2 * lowCount) * width + col] = highpass[lowCount * width + col]
                                              + lLast;
    }
}
