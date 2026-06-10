// J2KGPUForward53Telemetry.swift
//
// v6-alpha5 Phase 9 — observability for the GPU forward 5/3 INT
// production gate.
//
// Phases 0–8 shipped a working, byte-identical GPU forward 5/3 INT
// path with an env-var-cached opt-in flag and a 4 MP pixel-count
// threshold. Phase 9 adds the missing observability layer so:
//
//   1. **Policy tests** can deterministically assert which path
//      fired (without race conditions on the static flag) — the
//      telemetry counter is the load-bearing signal.
//   2. **Cross-device tuning** has a per-encode breakdown of
//      setup vs dispatch time, so future Apple Silicon
//      generations (M4 / M4 Pro / M4 Max) can have the threshold
//      empirically re-validated by harness re-run.
//   3. **Production debugging** can opt into per-call diagnostic
//      lines via `J2K_GPU_FORWARD_53_DEBUG=1`, off by default.
//
// All telemetry is process-global, lock-protected, and intended
// for tests + opt-in instrumentation. Production hot path pays
// one `NSLock` per encode (negligible vs encode wall ~ms).
//

import Foundation

/// Process-global telemetry for the GPU forward 5/3 INT path.
/// Counters and timings are zero by default; `reset()` to clear
/// before a measurement window.
public enum J2KGPUForward53Telemetry {

    /// Reasons the gate routed to CPU instead of GPU. Tracked as
    /// a per-reason counter so policy tests can assert which
    /// branch fired.
    public enum SkipReason: String, Sendable, CaseIterable {
        /// `J2K_GPU_FORWARD_53` env var unset (and
        /// `_gpuForward53Enabled = false` programmatically).
        case envDisabled        = "env-disabled"
        /// Metal not available on this platform / build.
        case metalUnavailable   = "metal-unavailable"
        /// `width * height < _gpuForward53PixelThreshold` (4 MP
        /// production default).
        case belowThreshold     = "below-threshold"
        /// v10.25: multi-tile per-tile dispatch excluded —
        /// `isMultiTilePerTile` and the tile is below
        /// `_gpuForward53MultiTilePerTilePixelThreshold` while
        /// above the single-tile threshold.
        case multiTilePerTile   = "multi-tile-per-tile"
    }

    public struct Snapshot: Sendable {
        /// Number of times the GPU forward path actually fired.
        public let gpuFireCount: Int
        /// Number of times the gate routed to CPU, broken down
        /// by reason. The sum equals total `applyWaveletTransform`
        /// invocations on the 5/3 reversible non-Float branch.
        public let cpuFireByReason: [SkipReason: Int]
        /// Cumulative `J2KMetalDWT.initialize()` wall time across
        /// every GPU fire. Phase 3 made this near-zero after the
        /// first encode (process-shared session); telemetry
        /// confirms the warm-call latency in tests.
        public let totalSetupMs: Double
        /// Cumulative `forward2DInt32MultiLevelFused(...)` wall
        /// time across every GPU fire. Includes upload, kernel
        /// dispatch, GPU completion wait, and readback.
        public let totalDispatchMs: Double

        public var totalCPUFireCount: Int {
            cpuFireByReason.values.reduce(0, +)
        }
    }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var _gpuFireCount: Int = 0
    nonisolated(unsafe) private static var _cpuFireByReason: [SkipReason: Int] = [:]
    nonisolated(unsafe) private static var _totalSetupMs: Double = 0
    nonisolated(unsafe) private static var _totalDispatchMs: Double = 0

    /// `J2K_GPU_FORWARD_53_DEBUG=1` (or `true` / `yes`) prints a
    /// one-line decision record per `applyWaveletTransform` call
    /// on the 5/3 reversible non-Float branch. Off by default.
    /// Production logs are unaffected.
    nonisolated(unsafe) public static let debugEnabled: Bool = {
        if let v = ProcessInfo.processInfo.environment["J2K_GPU_FORWARD_53_DEBUG"] {
            switch v.lowercased() {
            case "1", "true", "yes": return true
            default: return false
            }
        }
        return false
    }()

    /// Resets all counters and accumulators. Call at the start of
    /// a measurement window in tests.
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _gpuFireCount = 0
        _cpuFireByReason = [:]
        _totalSetupMs = 0
        _totalDispatchMs = 0
    }

    public static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            gpuFireCount: _gpuFireCount,
            cpuFireByReason: _cpuFireByReason,
            totalSetupMs: _totalSetupMs,
            totalDispatchMs: _totalDispatchMs)
    }

    /// Record one GPU-forward dispatch. Called from inside the
    /// encoder pipeline's gate-positive branch.
    static func recordGPUFire(setupMs: Double, dispatchMs: Double,
                              width: Int, height: Int, levels: Int,
                              tileOriginX: Int, tileOriginY: Int) {
        lock.lock()
        _gpuFireCount += 1
        _totalSetupMs += setupMs
        _totalDispatchMs += dispatchMs
        lock.unlock()
        if debugEnabled {
            print("[J2K GPU fwd 5/3 INT] FIRE  size=\(width)×\(height)=\(width * height) levels=\(levels) origin=(\(tileOriginX),\(tileOriginY)) setup=\(String(format: "%.2f", setupMs))ms dispatch=\(String(format: "%.2f", dispatchMs))ms")
        }
    }

    /// Record one CPU-forward dispatch with the reason GPU was
    /// not selected. Called from inside the encoder pipeline's
    /// gate-negative branch.
    static func recordCPUFire(reason: SkipReason,
                              width: Int, height: Int,
                              tileOriginX: Int, tileOriginY: Int) {
        lock.lock()
        _cpuFireByReason[reason, default: 0] += 1
        lock.unlock()
        if debugEnabled {
            print("[J2K GPU fwd 5/3 INT] SKIP  size=\(width)×\(height)=\(width * height) origin=(\(tileOriginX),\(tileOriginY)) reason=\(reason.rawValue)")
        }
    }
}
