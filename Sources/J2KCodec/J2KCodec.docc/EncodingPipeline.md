# Encoding Pipeline

@Metadata {
    @PageKind(article)
}

A detailed look at the JPEG 2000 encoding pipeline in J2KCodec, from raw pixel
data to a fully-formed codestream.

## Overview

The ``J2KEncoder`` drives a multi-stage pipeline that transforms an input
``J2KImage`` into a JPEG 2000 codestream. Each stage is configurable through
``J2KEncodingConfiguration`` and can be hardware-accelerated when a suitable
GPU back-end is available.

## Pipeline Stages

### 1. Preprocessing

The encoder validates the input image dimensions, bit depth, and component
count. If tiling is enabled, the image is partitioned into ``J2KTile``
instances that are processed independently. DC-level offset removal
(``J2KDCOffset``) may be applied at this stage.

### 2. Colour Transform

Intercomponent decorrelation reduces redundancy across colour channels.

- **Irreversible Colour Transform (ICT)** — floating-point RGB → YCbCr,
  used for lossy compression.
- **Reversible Colour Transform (RCT)** — integer-based transform used for
  lossless compression.

Configure the mode with ``J2KColorTransformMode``. For images with more than
three components, the Multi-Component Transform (``J2KMCT``) generalises this
step.

### 3. Wavelet Transform

The Discrete Wavelet Transform (``J2KDWT2D``) decomposes each tile-component
into subbands (``J2KSubband``).

- **CDF 9/7** — used with lossy compression.
- **Le Gall 5/3** — used with lossless compression.

Custom wavelet kernels can be registered through
``J2KWaveletKernelLibrary``. The number of decomposition levels and the
kernel selection are controlled by ``J2KEncodingConfiguration``.

### 4. Quantisation

Subband coefficients are quantised to reduce precision.

- **Scalar dead-zone quantisation** — standard JPEG 2000 method.
- **Trellis-coded quantisation (TCQ)** — via ``J2KTrellisQuantizer`` for
  improved rate-distortion performance.

``J2KQuantizationParameters`` specifies step sizes and guard bits.
``J2KQuantizationMode`` selects between reversible (no quantisation) and
irreversible modes.

### 5. Entropy Coding

Quantised coefficients are entropy-coded at the code-block level
(``J2KCodeBlock``).

- **EBCOT (Embedded Block Coding with Optimised Truncation)** — the
  traditional Part 1 block coder producing multiple coding passes per code
  block.
- **HTJ2K (High Throughput JPEG 2000)** — the Part 15 block coder, offering
  significantly faster encoding at a modest compression efficiency trade-off.

### 6. Rate Control

``J2KRateControl`` selects the optimal truncation points across all code
blocks to meet a target bitrate or quality.

- ``RateControlMode`` provides fixed-rate, fixed-quality, and visual-quality
  modes.
- ``J2KBitrateMode`` distinguishes variable bitrate (VBR) from constant
  bitrate (CBR) targets.

Post-compression rate-distortion optimisation (PCRD-opt) assigns coding passes
to quality layers.

### 7. Codestream Generation

Packets are formed from the selected coding passes and arranged according to
the chosen ``J2KProgressionOrder``. Marker segments (``J2KMarker``) are
emitted and the final JPEG 2000 codestream is assembled.

## Configuration

``J2KEncodingConfiguration`` centralises every tuneable parameter:

| Property              | Purpose                                |
|-----------------------|----------------------------------------|
| `waveletLevels`       | Number of DWT decomposition levels     |
| `codeBlockSize`       | Code-block dimensions (e.g. 64 × 64)  |
| `progressionOrder`    | Packet ordering strategy               |
| `qualityLayers`       | Number of quality layers               |
| `targetBitrate`       | Desired output bitrate                 |
| `isLossless`          | Enable reversible transforms           |

### Presets

``J2KEncodingPreset`` provides ready-made configurations for common use cases
such as archival lossless, visually lossless, high-quality lossy, and
low-bandwidth streaming.

## Progressive Encoding

``J2KProgressiveMode`` controls how the codestream is organised for
progressive transmission:

- **Layer progression** — quality improves with each additional layer.
- **Resolution progression** — a low-resolution preview is delivered first.
- **Position progression** — spatial regions arrive in scan order.

``J2KProgressiveEncodingStrategy`` combines progression order, layer count,
and component interleaving into a single reusable strategy.

## Usage Example

```swift
import J2KCodec

// Configure the encoder
var config = J2KEncodingConfiguration()
config.isLossless = false
config.targetBitrate = 1.0          // 1 bit per pixel
config.waveletLevels = 5
config.progressionOrder = .layerResolutionComponentPosition

// Create the encoder and encode
let encoder = J2KEncoder(configuration: config)
let codestream = try encoder.encode(image)
```

For common scenarios, use a preset instead:

```swift
let encoder = J2KEncoder(preset: .highQuality)
let codestream = try encoder.encode(image)
```

## See Also

- ``J2KEncoder``
- ``J2KEncodingConfiguration``
- ``J2KEncodingPreset``
- <doc:DecodingPipeline>
