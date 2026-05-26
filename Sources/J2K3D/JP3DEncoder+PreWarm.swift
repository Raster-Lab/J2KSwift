// JP3DEncoder+PreWarm.swift
//
// v10.20.0 — JP3D preWarm symmetric completion.
//
// v10.15.0 shipped `JP3DDecoder.preWarm` + `JP3DROIDecoder.preWarm` as
// discoverable wrappers around `J2KDecoder.preWarm` (v5.28.0). Sibling
// JP3D types (encoder, multi-spectral, progressive, stream writer,
// transcoder) lacked equivalent wrappers, so consumers using those
// types alone had to import the decoder module to find preWarm.
// v10.20.0 closes that gap with thin static wrappers — same idempotent
// semantics, same failure handling, same shared `J2KMetalSession.processShared`.
//
// V10_27 (v10.16-research probe) established that the encoder-specific
// cold cost beyond what `JP3DDecoder.preWarm(includeWarmupDispatch: true)`
// already amortises is below the 3 ms gate (+0.10 / −1.25 ms on the
// 128/256-cube fixtures), so these wrappers are PURELY discoverability —
// they delegate to the same underlying `J2KDecoder.preWarm` that warms
// the shared Metal session that all JP3D types share.

import Foundation
@preconcurrency import J2KCodec

extension JP3DEncoder {
    /// v10.20.0 — warms the shared Metal session before the first
    /// JP3D encode in a process. Thin wrapper around
    /// `J2KDecoder.preWarm(includeWarmupDispatch:)`; JP3D encoders
    /// share the process-wide Metal session via per-slice
    /// `J2KDecoder` / `J2KEncoder` delegation through
    /// `J2KMetalSession.processShared`. The warm-up dispatch
    /// (default off; pass `true` for a real synthetic 256² encode +
    /// decode round-trip) covers the encoder Metal init too.
    public static func preWarm(includeWarmupDispatch: Bool = false) async {
        await J2KDecoder.preWarm(includeWarmupDispatch: includeWarmupDispatch)
    }
}
