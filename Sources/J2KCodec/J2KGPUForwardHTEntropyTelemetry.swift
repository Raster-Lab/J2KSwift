// J2KGPUForwardHTEntropyTelemetry.swift
//
// v6-alpha6 phase 1.2 — observability for the GPU forward HT entropy
// production gate (mirrors `J2KGPUForward53Telemetry` for v6.0.0's
// forward DWT path).
//
// The forward HT entropy path is opt-in via `J2K_GPU_FORWARD_HT_ENTROPY=1`
// (or programmatic `EncoderPipeline._gpuForwardHTEntropyEnabled`) and
// gated on a per-batch codeblock-count threshold. The threshold uses
// codeblock count rather than pixel count (per Phase 0.5 finding —
// dispatch overhead is per-call, not per-pixel; smaller batches see
// dispatch cost dominate).
//
// All telemetry is process-global, lock-protected, intended for tests
// + opt-in instrumentation. Production hot path pays one `NSLock` per
// batch (one batch == one tile's entropy stage).
//

import Foundation

/// Process-global telemetry for the GPU forward HT entropy path.
public enum J2KGPUForwardHTEntropyTelemetry {

    /// Reasons the gate routed to CPU instead of GPU. Tracked as a
    /// per-reason counter so policy tests can assert which branch
    /// fired.
    public enum SkipReason: String, Sendable, CaseIterable {
        /// `J2K_GPU_FORWARD_HT_ENTROPY` env var unset (and
        /// `_gpuForwardHTEntropyEnabled = false` programmatically).
        case envDisabled        = "env-disabled"
        /// Metal not available on this platform / build.
        case metalUnavailable   = "metal-unavailable"
        /// `blockCount < _gpuForwardHTEntropyBlockThreshold`. The
        /// threshold defaults to 256 codeblocks based on Phase 0.5
        /// (DX 1584 blocks → 2.3 µs/block ≈ 11% of CPU entropy
        /// budget; smaller fixtures see dispatch cost dominate).
        /// Re-tune per-device in Phase 5.
        case belowBlockThreshold = "below-block-threshold"
        /// Not in conformant block format. The GPU classifier only
        /// targets the conformant cleanup-pass formula; non-
        /// conformant blocks stay on CPU.
        case nonConformantFormat = "non-conformant-format"
    }

    public struct Snapshot: Sendable {
        /// Number of times the GPU forward HT entropy path fired.
        /// One fire == one batched classifier dispatch.
        public let gpuFireCount: Int
        /// Total codeblocks classified by the GPU across all fires.
        public let gpuBlocksClassified: Int
        /// Number of times the gate routed to CPU, broken down by
        /// reason. The sum equals total batch decisions on the
        /// HT-conformant entropy stage.
        public let cpuFireByReason: [SkipReason: Int]
        /// Cumulative GPU classifier dispatch wall time (upload +
        /// kernel + readback) across every GPU fire.
        public let totalDispatchMs: Double
        /// Cumulative CPU emit wall time across every GPU fire
        /// (the per-block `HTBlockEncoderConformant.encode(...,
        /// preClassifiedTuples:)` calls). Distinguishes GPU work
        /// from CPU work in the GPU-on path.
        public let totalEmitMs: Double

        public var totalCPUFireCount: Int {
            cpuFireByReason.values.reduce(0, +)
        }
    }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var _gpuFireCount: Int = 0
    nonisolated(unsafe) private static var _gpuBlocksClassified: Int = 0
    nonisolated(unsafe) private static var _cpuFireByReason: [SkipReason: Int] = [:]
    nonisolated(unsafe) private static var _totalDispatchMs: Double = 0
    nonisolated(unsafe) private static var _totalEmitMs: Double = 0

    /// `J2K_GPU_FORWARD_HT_ENTROPY_DEBUG=1` (or `true` / `yes`) prints
    /// a one-line decision record per batch decision. Off by default.
    nonisolated(unsafe) public static let debugEnabled: Bool = {
        if let v = ProcessInfo.processInfo.environment["J2K_GPU_FORWARD_HT_ENTROPY_DEBUG"] {
            switch v.lowercased() {
            case "1", "true", "yes": return true
            default: return false
            }
        }
        return false
    }()

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _gpuFireCount = 0
        _gpuBlocksClassified = 0
        _cpuFireByReason = [:]
        _totalDispatchMs = 0
        _totalEmitMs = 0
    }

    public static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            gpuFireCount: _gpuFireCount,
            gpuBlocksClassified: _gpuBlocksClassified,
            cpuFireByReason: _cpuFireByReason,
            totalDispatchMs: _totalDispatchMs,
            totalEmitMs: _totalEmitMs)
    }

    /// Record one batched GPU classify + CPU emit. Called from inside
    /// the gate-positive branch.
    static func recordGPUFire(blockCount: Int,
                              dispatchMs: Double, emitMs: Double) {
        lock.lock()
        _gpuFireCount += 1
        _gpuBlocksClassified += blockCount
        _totalDispatchMs += dispatchMs
        _totalEmitMs += emitMs
        lock.unlock()
        if debugEnabled {
            print("[J2K GPU fwd HT entropy] FIRE  blocks=\(blockCount) dispatch=\(String(format: "%.2f", dispatchMs))ms emit=\(String(format: "%.2f", emitMs))ms")
        }
    }

    static func recordCPUFire(reason: SkipReason, blockCount: Int) {
        lock.lock()
        _cpuFireByReason[reason, default: 0] += 1
        lock.unlock()
        if debugEnabled {
            print("[J2K GPU fwd HT entropy] SKIP  blocks=\(blockCount) reason=\(reason.rawValue)")
        }
    }
}
