//
// J2KVulkanBackend.swift
// J2KSwift
//
// Protocol-based GPU backend selection for Vulkan and Metal compute paths.
//

import Foundation
import J2KCore

// MARK: - GPU Backend Type

/// Identifies the GPU compute backend in use.
///
/// Used by the protocol-based backend selection system to determine
/// which GPU API is active and available.
public enum J2KGPUBackendType: String, Sendable, CaseIterable {
    /// Apple Metal GPU compute (macOS, iOS, tvOS, visionOS).
    case metal = "Metal"
    /// Vulkan GPU compute (Linux, Windows).
    case vulkan = "Vulkan"
    /// CPU-only fallback (no GPU available).
    case cpu = "CPU"

    /// Human-readable description of the backend.
    public var displayName: String {
        rawValue
    }
}

// MARK: - GPU Backend Capabilities

/// Describes the capabilities of a GPU compute backend.
///
/// Used to query what operations a backend supports, enabling
/// the runtime to select the most appropriate backend or fall
/// back gracefully.
public struct J2KGPUBackendCapabilities: Sendable {
    /// The backend type.
    public let backendType: J2KGPUBackendType
    /// Whether the backend is currently available and initialised.
    public let isAvailable: Bool
    /// Whether the backend supports DWT compute.
    public let supportsDWT: Bool
    /// Whether the backend supports colour transforms.
    public let supportsColourTransform: Bool
    /// Whether the backend supports quantisation.
    public let supportsQuantisation: Bool
    /// Maximum supported buffer size in bytes.
    public let maxBufferSize: UInt64
    /// Maximum compute workgroup/threadgroup size.
    public let maxWorkGroupSize: UInt32
    /// Device name for diagnostics.
    public let deviceName: String

    /// Creates backend capabilities.
    public init(
        backendType: J2KGPUBackendType,
        isAvailable: Bool,
        supportsDWT: Bool = true,
        supportsColourTransform: Bool = true,
        supportsQuantisation: Bool = true,
        maxBufferSize: UInt64 = 256 * 1024 * 1024,
        maxWorkGroupSize: UInt32 = 256,
        deviceName: String = "unknown"
    ) {
        self.backendType = backendType
        self.isAvailable = isAvailable
        self.supportsDWT = supportsDWT
        self.supportsColourTransform = supportsColourTransform
        self.supportsQuantisation = supportsQuantisation
        self.maxBufferSize = maxBufferSize
        self.maxWorkGroupSize = maxWorkGroupSize
        self.deviceName = deviceName
    }

    /// CPU-only capabilities (always available).
    public static let cpuOnly = J2KGPUBackendCapabilities(
        backendType: .cpu,
        isAvailable: true,
        maxBufferSize: UInt64.max,
        maxWorkGroupSize: 1,
        deviceName: "CPU"
    )
}

// MARK: - GPU Backend Selector

/// Selects the best available GPU compute backend at runtime.
///
/// `J2KGPUBackendSelector` queries platform capabilities and selects
/// the most appropriate GPU backend: Metal on Apple platforms, Vulkan
/// on Linux/Windows, or CPU fallback when no GPU is available.
///
/// ## Usage
///
/// ```swift
/// let selector = J2KGPUBackendSelector()
/// let backend = selector.selectedBackend()
///
/// switch backend {
/// case .metal:
///     // Use Metal compute path
/// case .vulkan:
///     // Use Vulkan compute path
/// case .cpu:
///     // Use CPU fallback
/// }
/// ```
///
/// ## Architecture Isolation
///
/// The Vulkan backend is fully contained in the `J2KVulkan` module.
/// To remove Vulkan support entirely:
/// 1. Delete the `J2KVulkan` target from `Package.swift`
/// 2. Delete the `Sources/J2KVulkan/` directory
/// 3. Remove any `J2KVulkan` imports from consuming code
///
/// No other modules depend on `J2KVulkan`; the dependency is optional
/// and resolved at the application level.
public struct J2KGPUBackendSelector: Sendable {

    /// Creates a new backend selector.
    public init() {}

    /// Returns the best available GPU backend type.
    ///
    /// Selection priority:
    /// 1. Metal (if available on Apple platforms)
    /// 2. Vulkan (if available on Linux/Windows)
    /// 3. CPU fallback
    ///
    /// - Returns: The selected backend type.
    public func selectedBackend() -> J2KGPUBackendType {
        if isMetalAvailable() {
            return .metal
        } else if isVulkanAvailable() {
            return .vulkan
        } else {
            return .cpu
        }
    }

    /// Returns capabilities for the currently selected backend.
    ///
    /// - Returns: The capabilities of the selected backend.
    public func selectedCapabilities() -> J2KGPUBackendCapabilities {
        let backend = selectedBackend()
        return capabilities(for: backend)
    }

    /// Returns capabilities for a specific backend type.
    ///
    /// - Parameter backend: The backend type to query.
    /// - Returns: The capabilities of the specified backend.
    public func capabilities(for backend: J2KGPUBackendType) -> J2KGPUBackendCapabilities {
        switch backend {
        case .metal:
            return metalCapabilities()
        case .vulkan:
            return vulkanCapabilities()
        case .cpu:
            return .cpuOnly
        }
    }

    /// Returns all available backend types, ordered by preference.
    ///
    /// - Returns: Array of available backend types.
    public func availableBackends() -> [J2KGPUBackendType] {
        var backends: [J2KGPUBackendType] = []
        if isMetalAvailable() {
            backends.append(.metal)
        }
        if isVulkanAvailable() {
            backends.append(.vulkan)
        }
        backends.append(.cpu)
        return backends
    }

    // MARK: - Private Helpers

    private func isMetalAvailable() -> Bool {
        #if canImport(Metal)
        return true
        #else
        return false
        #endif
    }

    private func isVulkanAvailable() -> Bool {
        J2KVulkanDevice.isAvailable
    }

    private func metalCapabilities() -> J2KGPUBackendCapabilities {
        #if canImport(Metal)
        return J2KGPUBackendCapabilities(
            backendType: .metal,
            isAvailable: true,
            maxBufferSize: 256 * 1024 * 1024,
            maxWorkGroupSize: 1024,
            deviceName: "Metal GPU"
        )
        #else
        return J2KGPUBackendCapabilities(
            backendType: .metal,
            isAvailable: false,
            deviceName: "unavailable"
        )
        #endif
    }

    private func vulkanCapabilities() -> J2KGPUBackendCapabilities {
        J2KGPUBackendCapabilities(
            backendType: .vulkan,
            isAvailable: J2KVulkanDevice.isAvailable,
            maxBufferSize: 256 * 1024 * 1024,
            maxWorkGroupSize: 256,
            deviceName: J2KVulkanDevice.isAvailable ? "Vulkan GPU" : "unavailable"
        )
    }
}
