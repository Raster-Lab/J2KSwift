# ``J2KCodec``

Encoding and decoding implementation for JPEG 2000 including colour transforms, wavelet transforms, quantisation, entropy coding, rate control, region of interest, and progressive coding.

## Overview

J2KCodec provides the complete JPEG 2000 encoding and decoding pipeline. It implements all stages of the codec process: colour transforms (both irreversible and reversible), discrete wavelet transforms, quantisation, entropy coding via the EBCOT and HTJ2K block coders, rate-distortion optimisation, and progressive quality/resolution/position ordering.

The module supports advanced features such as region-of-interest (ROI) coding, perceptual visual weighting, transcoding between different JPEG 2000 configurations, and Motion JPEG 2000 (MJ2) video encoding and decoding.

All codec types conform to ``Sendable`` for safe use with Swift 6 structured concurrency. Actor-based types manage mutable state for thread-safe operation.

## Topics

### Encoding

- ``J2KEncoder``
- ``J2KEncodingConfiguration``
- ``J2KEncodingPreset``
- ``J2KBitrateMode``

### Decoding

- ``J2KDecoder``
- ``J2KPartialDecodingOptions``
- ``J2KProgressiveMode``

### Colour Transform

- ``J2KColorTransform``
- ``J2KColorTransformMode``
- ``J2KColorTransformConfiguration``
- ``J2KMCT``

### Wavelet Transform

- ``J2KDWT2D``
- ``J2KDWT1D``
- ``J2KWaveletKernel``
- ``J2KWaveletKernelLibrary``

### Quantisation

- ``J2KQuantization``
- ``J2KQuantizationMode``
- ``J2KQuantizationParameters``

### Entropy Coding

- ``HTBlockCoderMemoryTracker``

### Rate Control

- ``J2KRateControl``
- ``RateControlMode``
- ``RateControlConfiguration``

### Region of Interest

- ``J2KExtendedROI``

### Transcoding

- ``J2KTranscoder``

### Motion JPEG 2000 Video

- ``MJ2SoftwareEncoder``
- ``MJ2VideoToolboxEncoder``
- ``MJ2VideoToolboxDecoder``

### Perceptual Coding

- ``J2KVisualMasking``
