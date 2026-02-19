// J2KMetalDevice.swift
// J2KSwift
//
// Metal device management for GPU-accelerated JPEG 2000 operations.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - Metal Feature Tier

/// Identifies the GPU feature tier for capability-based decisions.
///
/// Feature tiers help the framework select appropriate shader variants and
/// memory strategies based on the GPU's capabilities.
public enum J2KMetalFeatureTier: Int, Sendable, Comparable {
    /// Unknown or unsupported GPU tier.
    case unknown = 0
    /// Intel integrated GPU (macOS only).
    case intelIntegrated = 1
    /// Intel discrete GPU (macOS only).
    case intelDiscrete = 2
    /// Apple Silicon GPU (M1 and later).
    case appleSilicon = 3

    public static func < (lhs: J2KMetalFeatureTier, rhs: J2KMetalFeatureTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Metal Device Configuration

/// Configuration for Metal device initialization and behavior.
///
/// Controls how the Metal device is selected, memory limits are enforced,
/// and fallback behavior when Metal is unavailable.
public struct J2KMetalDeviceConfiguration: Sendable {
    /// Whether to prefer low-power GPU on multi-GPU systems.
    public var preferLowPower: Bool

    /// Maximum GPU memory usage in bytes (0 for unlimited).
    public var maxMemoryUsage: UInt64

    /// Whether to automatically fall back to CPU when Metal is unavailable.
    public var enableFallback: Bool

    /// Creates a new Metal device configuration.
    ///
    /// - Parameters:
    ///   - preferLowPower: Whether to prefer low-power GPU. Defaults to `false`.
    ///   - maxMemoryUsage: Maximum GPU memory usage in bytes. Defaults to `0` (unlimited).
    ///   - enableFallback: Whether to fall back to CPU. Defaults to `true`.
    public init(
        preferLowPower: Bool = false,
        maxMemoryUsage: UInt64 = 0,
        enableFallback: Bool = true
    ) {
        self.preferLowPower = preferLowPower
        self.maxMemoryUsage = maxMemoryUsage
        self.enableFallback = enableFallback
    }

    /// Default configuration suitable for most use cases.
    public static let `default` = J2KMetalDeviceConfiguration()

    /// Configuration optimized for high performance.
    public static let highPerformance = J2KMetalDeviceConfiguration(
        preferLowPower: false,
        maxMemoryUsage: 0,
        enableFallback: true
    )

    /// Configuration optimized for low power usage.
    public static let lowPower = J2KMetalDeviceConfiguration(
        preferLowPower: true,
        maxMemoryUsage: 256 * 1024 * 1024,
        enableFallback: true
    )
}

// MARK: - Metal Device Manager

/// Manages Metal device lifecycle and provides GPU access for JPEG 2000 operations.
///
/// `J2KMetalDevice` handles Metal device initialization, command queue creation,
/// feature tier identification, and graceful degradation when Metal is unavailable.
/// All mutable state is protected by the actor isolation model for thread safety.
///
/// ## Usage
///
/// ```swift
/// let device = J2KMetalDevice()
///
/// if J2KMetalDevice.isAvailable {
///     try await device.initialize()
///     let queue = try await device.commandQueue()
///     // Use queue for GPU operations
/// }
/// ```
///
/// ## Platform Support
///
/// Metal is available on:
/// - macOS 10.13+ (Intel and Apple Silicon)
/// - iOS 11+ (A7 and later)
/// - tvOS 11+
///
/// On unsupported platforms (Linux, Windows), all operations gracefully
/// fail with ``J2KError/unsupportedFeature(_:)``.
public actor J2KMetalDevice {
    /// Whether Metal is available on this platform.
    public static var isAvailable: Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    /// The configuration for this device.
    public let configuration: J2KMetalDeviceConfiguration

    #if canImport(Metal)
    /// The underlying Metal device.
    private var device: (any MTLDevice)?

    /// The command queue for submitting work.
    private var _commandQueue: (any MTLCommandQueue)?

    /// The identified feature tier for this GPU.
    private var _featureTier: J2KMetalFeatureTier = .unknown
    #endif

    /// Whether the device has been initialized.
    private var isInitialized = false

    /// Current GPU memory usage tracking.
    private var currentMemoryUsage: UInt64 = 0

    /// Creates a Metal device manager with the given configuration.
    ///
    /// - Parameter configuration: The device configuration. Defaults to `.default`.
    public init(configuration: J2KMetalDeviceConfiguration = .default) {
        self.configuration = configuration
    }

    /// Initializes the Metal device and command queue.
    ///
    /// This method selects the appropriate GPU, creates the command queue,
    /// and identifies the feature tier. It is safe to call multiple times;
    /// subsequent calls are no-ops.
    ///
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Metal is not available.
    /// - Throws: ``J2KError/internalError(_:)`` if device initialization fails.
    public func initialize() throws {
        guard !isInitialized else { return }

        #if canImport(Metal)
        let selectedDevice = selectDevice()
        guard let selectedDevice else {
            throw J2KError.unsupportedFeature("Metal device not available")
        }

        guard let queue = selectedDevice.makeCommandQueue() else {
            throw J2KError.internalError("Failed to create Metal command queue")
        }

        self.device = selectedDevice
        self._commandQueue = queue
        self._featureTier = identifyFeatureTier(selectedDevice)
        self.isInitialized = true
        #else
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
        #endif
    }

    /// Validates that the device is initialized and ready for use.
    ///
    /// - Throws: ``J2KError/internalError(_:)`` if the device is not initialized.
    public func validateReady() throws {
        guard isInitialized else {
            throw J2KError.internalError("Metal device not initialized. Call initialize() first.")
        }

        #if canImport(Metal)
        guard _commandQueue != nil else {
            throw J2KError.internalError("Metal command queue is nil")
        }
        #else
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
        #endif
    }

    #if canImport(Metal)
    /// Returns the Metal command queue for submitting work.
    ///
    /// - Returns: The Metal command queue.
    /// - Throws: ``J2KError/internalError(_:)`` if the device is not initialized.
    public func commandQueue() throws -> any MTLCommandQueue {
        try validateReady()
        return _commandQueue!
    }
    #endif

    /// Returns the feature tier of the current GPU.
    ///
    /// - Returns: The identified feature tier.
    public func featureTier() -> J2KMetalFeatureTier {
        #if canImport(Metal)
        return _featureTier
        #else
        return .unknown
        #endif
    }

    /// Returns the device name for diagnostic purposes.
    ///
    /// - Returns: The GPU device name, or "unavailable" if Metal is not initialized.
    public func deviceName() -> String {
        #if canImport(Metal)
        return device?.name ?? "unavailable"
        #else
        return "unavailable"
        #endif
    }

    /// Returns the maximum recommended working set size in bytes.
    ///
    /// - Returns: The recommended maximum working set size, or 0 if unavailable.
    public func maxWorkingSetSize() -> UInt64 {
        #if canImport(Metal)
        guard let device else { return 0 }
        #if os(macOS)
        return UInt64(device.recommendedMaxWorkingSetSize)
        #else
        return 0
        #endif
        #else
        return 0
        #endif
    }

    /// Checks whether the requested memory allocation can be satisfied.
    ///
    /// - Parameter bytes: The number of bytes to allocate.
    /// - Returns: `true` if the allocation is within configured limits.
    public func canAllocate(bytes: UInt64) -> Bool {
        guard configuration.maxMemoryUsage > 0 else { return true }
        return currentMemoryUsage + bytes <= configuration.maxMemoryUsage
    }

    /// Tracks a memory allocation.
    ///
    /// - Parameter bytes: The number of bytes allocated.
    public func trackAllocation(bytes: UInt64) {
        currentMemoryUsage += bytes
    }

    /// Tracks a memory deallocation.
    ///
    /// - Parameter bytes: The number of bytes deallocated.
    public func trackDeallocation(bytes: UInt64) {
        if bytes > currentMemoryUsage {
            currentMemoryUsage = 0
        } else {
            currentMemoryUsage -= bytes
        }
    }

    /// Returns the current tracked memory usage.
    ///
    /// - Returns: The current memory usage in bytes.
    public func memoryUsage() -> UInt64 {
        return currentMemoryUsage
    }

    // MARK: - Private Helpers

    #if canImport(Metal)
    /// Selects the best available Metal device based on configuration.
    private func selectDevice() -> (any MTLDevice)? {
        #if os(macOS)
        let devices = MTLCopyAllDevices()
        if configuration.preferLowPower {
            if let lowPower = devices.first(where: { $0.isLowPower }) {
                return lowPower
            }
        }
        // Prefer non-low-power (discrete/Apple Silicon) device
        if let highPerf = devices.first(where: { !$0.isLowPower }) {
            return highPerf
        }
        return devices.first ?? MTLCreateSystemDefaultDevice()
        #else
        return MTLCreateSystemDefaultDevice()
        #endif
    }

    /// Identifies the feature tier of a Metal device.
    private func identifyFeatureTier(_ device: any MTLDevice) -> J2KMetalFeatureTier {
        let name = device.name.lowercased()

        // Check for Apple Silicon first
        if name.contains("apple") {
            return .appleSilicon
        }

        #if os(macOS)
        // On macOS, check for Intel GPUs
        if name.contains("intel") {
            if device.isLowPower {
                return .intelIntegrated
            }
            return .intelDiscrete
        }
        // AMD or other discrete GPUs
        if !device.isLowPower {
            return .intelDiscrete
        }
        #endif

        // iOS/tvOS devices with Metal support are at least Apple GPU
        #if os(iOS) || os(tvOS)
        return .appleSilicon
        #else
        return .unknown
        #endif
    }
    #endif
}
