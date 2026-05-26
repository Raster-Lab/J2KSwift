// JP3DStreamWriter+PreWarm.swift
//
// v10.20.0 — JP3D preWarm symmetric completion. See
// JP3DEncoder+PreWarm.swift for the design rationale.

import Foundation
@preconcurrency import J2KCodec

extension JP3DStreamWriter {
    /// v10.20.0 — warms the shared Metal session before the first
    /// streaming JP3D encode in a process. Same idempotent
    /// semantics + same `J2KMetalSession.processShared` as
    /// `JP3DDecoder.preWarm`.
    public static func preWarm(includeWarmupDispatch: Bool = false) async {
        await J2KDecoder.preWarm(includeWarmupDispatch: includeWarmupDispatch)
    }
}
