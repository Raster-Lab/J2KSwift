// JP3DTranscoder+PreWarm.swift
//
// v10.20.0 — JP3D preWarm symmetric completion. See
// JP3DEncoder+PreWarm.swift for the design rationale.

import Foundation
@preconcurrency import J2KCodec

extension JP3DTranscoder {
    /// v10.20.0 — warms the shared Metal session before the first
    /// JP3D transcode in a process. Same idempotent semantics + same
    /// `J2KMetalSession.processShared` as `JP3DDecoder.preWarm`.
    /// Transcoding internally decodes + re-encodes per slice through
    /// `J2KDecoder` + `J2KEncoder`, both of which share the
    /// process-wide Metal session.
    public static func preWarm(includeWarmupDispatch: Bool = false) async {
        await J2KDecoder.preWarm(includeWarmupDispatch: includeWarmupDispatch)
    }
}
