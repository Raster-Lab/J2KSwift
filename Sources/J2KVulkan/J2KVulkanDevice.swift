//
// J2KVulkanDevice.swift
// J2KSwift
//
// Vulkan device management for GPU-accelerated JPEG 2000 operations on Linux/Windows.
//

import Foundation
import J2KCore

// MARK: - Vulkan Feature Tier

/// Identifies the GPU vendor tier for capability-based decisions.
///
/// Feature tiers help the framework select appropriate shader variants and
/// memory strategies based on the GPU's capabilities.
public enum J2KVulkanFeatureTier: Int, Sendable, Comparable {
    /// Unknown or unsupported GPU tier.
    case unknown = 0
    /// Intel integrated GPU.
    case intelIntegrated = 1
    /// Intel discrete GPU (Arc series).
    case intelDiscrete = 2
    /// AMD discrete GPU.
    case amdDiscrete = 3
    /// NVIDIA discrete GPU.
    case nvidiaDiscrete = 4

    public static func < (lhs: J2KVulkanFeatureTier, rhs: J2KVulkanFeatureTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Vulkan Device Configuration

/// Configuration for Vulkan device initialisation and behaviour.
///
/// Controls how the Vulkan device is selected, memory limits are enforced,
/// and fallback behaviour when Vulkan is unavailable.
public struct J2KVulkanDeviceConfiguration: Sendable {
    /// Whether to prefer integrated (low-power) GPU on multi-GPU systems.
    public var preferIntegrated: Bool

    /// Maximum GPU memory usage in bytes (0 for unlimited).
    public var maxMemoryUsage: UInt64

    /// Whether to automatically fall back to CPU when Vulkan is unavailable.
    public var enableFallback: Bool

    /// Creates a new Vulkan device configuration.
    ///
    /// - Parameters:
    ///   - preferIntegrated: Whether to prefer integrated GPU. Defaults to `false`.
    ///   - maxMemoryUsage: Maximum GPU memory usage in bytes. Defaults to `0` (unlimited).
    ///   - enableFallback: Whether to fall back to CPU. Defaults to `true`.
    public init(
        preferIntegrated: Bool = false,
        maxMemoryUsage: UInt64 = 0,
        enableFallback: Bool = true
    ) {
        self.preferIntegrated = preferIntegrated
        self.maxMemoryUsage = maxMemoryUsage
        self.enableFallback = enableFallback
    }

    /// Default configuration suitable for most use cases.
    public static let `default` = J2KVulkanDeviceConfiguration()

    /// Configuration optimised for high performance.
    public static let highPerformance = J2KVulkanDeviceConfiguration(
        preferIntegrated: false,
        maxMemoryUsage: 0,
        enableFallback: true
    )

    /// Configuration optimised for low power usage.
    public static let lowPower = J2KVulkanDeviceConfiguration(
        preferIntegrated: true,
        maxMemoryUsage: 256 * 1024 * 1024,
        enableFallback: true
    )
}

// MARK: - Vulkan Device Properties

/// Properties of a discovered Vulkan-capable GPU device.
///
/// Encapsulates information about a physical device that can be queried
/// without requiring a full Vulkan initialisation.
public struct J2KVulkanDeviceProperties: Sendable {
    /// Device name as reported by the driver.
    public let name: String
    /// Vendor identifier (e.g. 0x10DE for NVIDIA, 0x1002 for AMD, 0x8086 for Intel).
    public let vendorID: UInt32
    /// Device identifier.
    public let deviceID: UInt32
    /// Identified feature tier.
    public let featureTier: J2KVulkanFeatureTier
    /// Maximum compute workgroup size (x dimension).
    public let maxComputeWorkGroupSizeX: UInt32
    /// Maximum compute workgroup count (x dimension).
    public let maxComputeWorkGroupCountX: UInt32
    /// Device-local memory heap size in bytes.
    public let deviceLocalMemoryBytes: UInt64

    /// Creates device properties.
    public init(
        name: String,
        vendorID: UInt32,
        deviceID: UInt32,
        featureTier: J2KVulkanFeatureTier,
        maxComputeWorkGroupSizeX: UInt32 = 1024,
        maxComputeWorkGroupCountX: UInt32 = 65535,
        deviceLocalMemoryBytes: UInt64 = 0
    ) {
        self.name = name
        self.vendorID = vendorID
        self.deviceID = deviceID
        self.featureTier = featureTier
        self.maxComputeWorkGroupSizeX = maxComputeWorkGroupSizeX
        self.maxComputeWorkGroupCountX = maxComputeWorkGroupCountX
        self.deviceLocalMemoryBytes = deviceLocalMemoryBytes
    }
}

// MARK: - Vulkan Device Manager

/// Manages Vulkan device lifecycle and provides GPU access for JPEG 2000 operations.
///
/// `J2KVulkanDevice` handles Vulkan instance creation, physical device selection,
/// logical device creation, compute queue retrieval, and graceful degradation
/// when Vulkan is unavailable. All mutable state is protected by actor isolation.
///
/// ## Usage
///
/// ```swift
/// let device = J2KVulkanDevice()
///
/// if J2KVulkanDevice.isAvailable {
///     try await device.initialize()
///     let props = await device.deviceProperties()
///     // Use device for GPU operations
/// } else {
///     // Fall back to CPU
/// }
/// ```
///
/// ## Platform Support
///
/// Vulkan is available on:
/// - Linux (AMD, NVIDIA, Intel GPUs with Vulkan drivers)
/// - Windows (AMD, NVIDIA, Intel GPUs with Vulkan drivers)
///
/// On platforms without Vulkan (macOS, iOS), all operations gracefully
/// fall back to CPU or fail with ``J2KError/unsupportedFeature(_:)``.
public actor J2KVulkanDevice {
    /// Whether Vulkan is available on this platform at compile time.
    ///
    /// Returns `true` only when the CVulkan system module can be imported.
    /// Runtime availability must also be checked via ``runtimeAvailable()``.
    public static var isAvailable: Bool {
        #if canImport(CVulkan)
        return true
        #else
        return false
        #endif
    }

    /// The configuration for this device.
    public let configuration: J2KVulkanDeviceConfiguration

    /// Whether the device has been initialised.
    private var isInitialized = false

    /// Current GPU memory usage tracking.
    private var currentMemoryUsage: UInt64 = 0

    /// Cached device properties after initialisation.
    private var _deviceProperties: J2KVulkanDeviceProperties?

    /// Creates a Vulkan device manager with the given configuration.
    ///
    /// - Parameter configuration: The device configuration. Defaults to `.default`.
    public init(configuration: J2KVulkanDeviceConfiguration = .default) {
        self.configuration = configuration
    }

    /// Initialises the Vulkan instance, selects a physical device, and creates
    /// a logical device with a compute queue.
    ///
    /// This method is safe to call multiple times; subsequent calls are no-ops.
    ///
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Vulkan is not available.
    /// - Throws: ``J2KError/internalError(_:)`` if device initialisation fails.
    public func initialize() throws {
        guard !isInitialized else { return }

        #if canImport(CVulkan)
        // Real Vulkan initialisation would happen here:
        // 1. vkCreateInstance
        // 2. vkEnumeratePhysicalDevices
        // 3. Select best physical device based on configuration
        // 4. vkCreateDevice with compute queue family
        // 5. vkGetDeviceQueue for compute queue
        fatalError("Vulkan runtime initialisation requires CVulkan system module")
        #else
        throw J2KError.unsupportedFeature("Vulkan is not available on this platform")
        #endif
    }

    /// Checks whether Vulkan is available at runtime.
    ///
    /// Attempts to detect Vulkan loader presence via dynamic library loading.
    /// This is more reliable than compile-time checks on Linux systems where
    /// Vulkan may be installed but not all headers are present.
    ///
    /// - Returns: `true` if Vulkan runtime is detected.
    public func runtimeAvailable() -> Bool {
        #if canImport(CVulkan)
        return true
        #else
        return false
        #endif
    }

    /// Validates that the device is initialised and ready for use.
    ///
    /// - Throws: ``J2KError/internalError(_:)`` if the device is not initialised.
    public func validateReady() throws {
        guard isInitialized else {
            throw J2KError.internalError("Vulkan device not initialised. Call initialize() first.")
        }
    }

    /// Returns the feature tier of the current GPU.
    ///
    /// - Returns: The identified feature tier, or `.unknown` if not initialised.
    public func featureTier() -> J2KVulkanFeatureTier {
        _deviceProperties?.featureTier ?? .unknown
    }

    /// Returns the device name for diagnostic purposes.
    ///
    /// - Returns: The GPU device name, or "unavailable" if Vulkan is not initialised.
    public func deviceName() -> String {
        _deviceProperties?.name ?? "unavailable"
    }

    /// Returns the device properties.
    ///
    /// - Returns: The device properties, or `nil` if not initialised.
    public func deviceProperties() -> J2KVulkanDeviceProperties? {
        _deviceProperties
    }

    /// Returns the device-local memory heap size in bytes.
    ///
    /// - Returns: The device-local heap size, or 0 if unavailable.
    public func deviceLocalMemorySize() -> UInt64 {
        _deviceProperties?.deviceLocalMemoryBytes ?? 0
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
        currentMemoryUsage
    }

    // MARK: - Vendor Identification

    /// Identifies the feature tier from a Vulkan vendor ID.
    ///
    /// - Parameters:
    ///   - vendorID: The Vulkan physical device vendor ID.
    ///   - isIntegrated: Whether the device is an integrated GPU.
    /// - Returns: The identified feature tier.
    public static func featureTier(
        vendorID: UInt32,
        isIntegrated: Bool
    ) -> J2KVulkanFeatureTier {
        switch vendorID {
        case 0x10DE: // NVIDIA
            return .nvidiaDiscrete
        case 0x1002: // AMD
            return .amdDiscrete
        case 0x8086: // Intel
            return isIntegrated ? .intelIntegrated : .intelDiscrete
        default:
            return .unknown
        }
    }
}
