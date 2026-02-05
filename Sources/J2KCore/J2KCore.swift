/// # J2KCore
///
/// Core module for JPEG 2000 encoding and decoding functionality.
///
/// This module provides the foundational types, protocols, and utilities for JPEG 2000 image
/// processing. It defines the basic building blocks used by other modules in the J2KCore framework.
///
/// ## Topics
///
/// ### Core Types
/// - ``J2KImage``
/// - ``J2KError``
///
/// ### Configuration
/// - ``J2KConfiguration``

import Foundation

/// Represents a JPEG 2000 image with metadata and pixel data.
public struct J2KImage: Sendable {
    /// The width of the image in pixels.
    public let width: Int
    
    /// The height of the image in pixels.
    public let height: Int
    
    /// The number of color components (e.g., 3 for RGB, 4 for RGBA).
    public let components: Int
    
    /// Creates a new J2KImage with the specified dimensions.
    ///
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - components: The number of color components.
    public init(width: Int, height: Int, components: Int) {
        self.width = width
        self.height = height
        self.components = components
    }
}

/// Errors that can occur during JPEG 2000 operations.
public enum J2KError: Error, Sendable {
    /// An invalid parameter was provided.
    case invalidParameter(String)
    
    /// The operation is not yet implemented.
    case notImplemented
    
    /// An internal error occurred.
    case internalError(String)
}

/// Configuration options for JPEG 2000 operations.
public struct J2KConfiguration: Sendable {
    /// The quality factor for encoding (0.0 to 1.0).
    public let quality: Double
    
    /// Whether to use lossless compression.
    public let lossless: Bool
    
    /// Creates a new configuration with the specified options.
    ///
    /// - Parameters:
    ///   - quality: The quality factor (default: 0.9).
    ///   - lossless: Whether to use lossless compression (default: false).
    public init(quality: Double = 0.9, lossless: Bool = false) {
        self.quality = quality
        self.lossless = lossless
    }
}

/// Returns the version of the J2KCore framework.
///
/// - Returns: A string representing the current version.
public func getVersion() -> String {
    fatalError("Not implemented")
}
