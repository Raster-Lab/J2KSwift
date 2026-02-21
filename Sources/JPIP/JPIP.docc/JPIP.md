# ``JPIP``

JPEG 2000 Interactive Protocol (ISO/IEC 15444-9) client and server implementation for progressive image streaming.

## Overview

JPIP implements the JPEG 2000 Interactive Protocol as defined in ISO/IEC 15444-9. This protocol enables efficient streaming of JPEG 2000 images over networks, allowing clients to request specific regions, resolutions, or quality layers without downloading the entire image.

The ``JPIPClient`` provides a high-level interface for connecting to JPIP servers, managing sessions, and receiving progressive image data. The ``JPIPServer`` actor handles incoming requests, session management, and response generation. Both support HTTP and WebSocket transports via ``JPIPWebSocketTransport``.

The module includes intelligent caching through ``JPIPClientCacheManager``, bandwidth estimation via ``JPIPBandwidthEstimator``, and progressive delivery scheduling with ``JPIPProgressiveStreamingPipeline``. For volumetric data, ``JP3DJPIPClient`` and ``JP3DJPIPServer`` extend the protocol to support JP3D datasets.

## Topics

### Client

- ``JPIPClient``
- ``JPIPRequest``
- ``JPIPResponse``

### Server

- ``JPIPServer``
- ``JPIPWebSocketServer``

### Session Management

- ``JPIPSession``

### Caching

- ``JPIPClientCacheManager``
- ``JPIPPrecinctCache``
- ``JPIPCacheModel``

### Streaming and Delivery

- ``JPIPProgressiveStreamingPipeline``
- ``JPIPBandwidthEstimator``
- ``JPIPProgressiveDeliveryScheduler``

### Transport

- ``JPIPWebSocketTransport``

### Volumetric Streaming (JP3D)

- ``JP3DJPIPClient``
- ``JP3DJPIPServer``
- ``JP3DProgressiveDelivery``
