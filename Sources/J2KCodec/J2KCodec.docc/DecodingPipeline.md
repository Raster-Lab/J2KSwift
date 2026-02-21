# Decoding Pipeline

@Metadata {
    @PageKind(article)
}

A detailed look at the JPEG 2000 decoding pipeline in J2KCodec, from
codestream parsing to a fully reconstructed image.

## Overview

The ``J2KDecoder`` reverses every stage of the encoding pipeline. Given a
JPEG 2000 codestream (or a JP2 file via ``J2KFileReader``), the decoder
reconstructs a ``J2KImage`` through codestream parsing, entropy decoding,
dequantisation, inverse wavelet transform, and inverse colour transform.

Partial decoding — by region, resolution, or quality layer — is a first-class
feature, making JPEG 2000 especially suitable for interactive viewing and
bandwidth-constrained delivery.

## Pipeline Stages

### 1. Codestream Parsing

The decoder reads marker segments (``J2KMarker``, ``J2KMarkerSegment``) from
the codestream to recover the image size, component layout, tile grid,
decomposition structure, quantisation parameters, and progression order.
``J2KMarkerParser`` handles validation and extraction of every marker defined
by Part 1 and Part 2.

### 2. Entropy Decoding

Packet data is demultiplexed into individual code-block bitstreams
(``J2KCodeBlock``). Each code block is decoded by the appropriate block coder:

- **EBCOT** — standard Part 1 arithmetic-coded passes.
- **HTJ2K** — Part 15 high-throughput block coder for faster decoding.

The decoder only processes the coding passes required by the requested quality
layer, enabling quality-scalable access.

### 3. Dequantisation

``J2KQuantizer`` restores the magnitude of subband coefficients using the
step sizes recorded in the codestream. In the lossless (reversible) case, this
step is a no-op because quantisation was not applied during encoding.

### 4. Inverse Wavelet Transform

``J2KDWT2D`` performs the inverse discrete wavelet transform to reconstruct
spatial-domain tile-component data from subbands (``J2KSubband``). The kernel
(CDF 9/7 or Le Gall 5/3) matches the one used during encoding.

If only a lower resolution is requested, the decoder skips the highest
decomposition levels, performing fewer inverse transform stages and producing
a smaller output image.

### 5. Inverse Colour Transform

``J2KColorTransform`` reverses the intercomponent decorrelation:

- **Inverse ICT** — YCbCr → RGB (lossy path).
- **Inverse RCT** — integer inverse (lossless path).

For multi-component images, the inverse Multi-Component Transform
(``J2KMCT``) is used instead.

## Partial Decoding

One of the most powerful features of JPEG 2000 is the ability to decode only
the data that is actually needed.

### Region of Interest Decoding

``J2KPartialDecodingOptions`` specifies a spatial region (in image
coordinates) to decode. Only the tiles and precincts (``J2KPrecinct``) that
intersect the region are processed, greatly reducing memory and compute
requirements for large images.

``J2KROIDecodingOptions`` further refines decoding when the encoder has
applied ROI coding, ensuring that the region of interest is reconstructed at
full quality before the background.

### Resolution Scalability

``J2KResolutionDecodingOptions`` allows the caller to request a specific
resolution level. Setting a lower level skips higher-frequency subbands and
produces a proportionally smaller image — ideal for thumbnail generation.

### Quality Layer Selection

Each quality layer adds fidelity. The decoder can stop after a specified
number of layers, trading image quality for reduced processing time and
bandwidth.

## Progressive Decoding

``J2KProgressiveDecodingOptions`` controls how a progressively-ordered
codestream is consumed. The decoder yields intermediate results — improving
in quality, resolution, or spatial coverage — as more data arrives. This is
the foundation of the JPIP streaming workflow where ``JPIPClient`` delivers
data incrementally and the decoder updates the display.

``J2KProgressiveMode`` determines the progression axis:

- `.qualityProgressive` — each pass adds a quality layer.
- `.resolutionProgressive` — each pass doubles the resolution.
- `.positionProgressive` — each pass reveals more spatial area.

## Usage Example

### Basic Full Decoding

```swift
import J2KCodec

let decoder = J2KDecoder()
let image = try decoder.decode(from: codestreamData)

print("Decoded \(image.width)×\(image.height), "
    + "\(image.componentCount) components")
```

### Region-of-Interest Decoding

```swift
import J2KCodec

let options = J2KPartialDecodingOptions(
    region: .init(x: 100, y: 100, width: 256, height: 256)
)
let decoder = J2KDecoder()
let cropped = try decoder.decode(from: codestreamData, options: options)
```

### Reduced-Resolution Decoding

```swift
import J2KCodec

let options = J2KResolutionDecodingOptions(level: 2)  // quarter size
let decoder = J2KDecoder()
let thumbnail = try decoder.decode(from: codestreamData,
                                   resolutionOptions: options)
```

## See Also

- ``J2KDecoder``
- ``J2KPartialDecodingOptions``
- ``J2KResolutionDecodingOptions``
- ``J2KProgressiveDecodingOptions``
- <doc:EncodingPipeline>
