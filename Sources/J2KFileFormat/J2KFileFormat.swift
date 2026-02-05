/// # J2KFileFormat
///
/// File format support for JPEG 2000 and related formats.
///
/// This module handles reading and writing JPEG 2000 files in various formats,
/// including JP2, J2K, JPX, and related container formats.
///
/// ## Topics
///
/// ### File Reading
/// - ``J2KFileReader``
///
/// ### File Writing
/// - ``J2KFileWriter``
///
/// ### Format Detection
/// - ``J2KFormat``

import Foundation
import J2KCore

/// Supported JPEG 2000 file formats.
public enum J2KFormat: String, Sendable {
    /// JP2 format (JPEG 2000 Part 1)
    case jp2
    
    /// J2K codestream format
    case j2k
    
    /// JPX format (JPEG 2000 Part 2)
    case jpx
    
    /// JPM format (JPEG 2000 Part 6)
    case jpm
}

/// Reads JPEG 2000 files from disk.
public struct J2KFileReader: Sendable {
    /// Creates a new file reader.
    public init() {}
    
    /// Reads a JPEG 2000 file from the specified URL.
    ///
    /// - Parameter url: The URL of the file to read.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if reading or decoding fails.
    public func read(from url: URL) throws -> J2KImage {
        fatalError("Not implemented")
    }
    
    /// Detects the format of a JPEG 2000 file.
    ///
    /// - Parameter url: The URL of the file to examine.
    /// - Returns: The detected format.
    /// - Throws: ``J2KError`` if format detection fails.
    public func detectFormat(at url: URL) throws -> J2KFormat {
        fatalError("Not implemented")
    }
}

/// Writes JPEG 2000 files to disk.
public struct J2KFileWriter: Sendable {
    /// The format to use for writing.
    public let format: J2KFormat
    
    /// Creates a new file writer with the specified format.
    ///
    /// - Parameter format: The format to use (default: .jp2).
    public init(format: J2KFormat = .jp2) {
        self.format = format
    }
    
    /// Writes an image to a JPEG 2000 file.
    ///
    /// - Parameters:
    ///   - image: The image to write.
    ///   - url: The destination URL.
    ///   - configuration: The encoding configuration.
    /// - Throws: ``J2KError`` if encoding or writing fails.
    public func write(_ image: J2KImage, to url: URL, configuration: J2KConfiguration = J2KConfiguration()) throws {
        fatalError("Not implemented")
    }
}
