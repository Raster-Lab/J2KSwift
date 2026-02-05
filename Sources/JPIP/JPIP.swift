/// # JPIP
///
/// JPEG 2000 Interactive Protocol (JPIP) implementation.
///
/// This module provides support for the JPIP protocol, enabling efficient streaming
/// and progressive transmission of JPEG 2000 images over networks.
///
/// ## Topics
///
/// ### Client
/// - ``JPIPClient``
///
/// ### Server
/// - ``JPIPServer``
///
/// ### Session Management
/// - ``JPIPSession``

import Foundation
import J2KCore
import J2KFileFormat

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A JPIP client for requesting and receiving JPEG 2000 data.
public actor JPIPClient {
    /// The server URL to connect to.
    public let serverURL: URL
    
    /// Creates a new JPIP client.
    ///
    /// - Parameter serverURL: The URL of the JPIP server.
    public init(serverURL: URL) {
        self.serverURL = serverURL
    }
    
    /// Requests an image from the server.
    ///
    /// - Parameter imageID: The identifier of the image to request.
    /// - Returns: The requested image.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestImage(imageID: String) async throws -> J2KImage {
        fatalError("Not implemented")
    }
    
    /// Requests a specific region of interest from an image.
    ///
    /// - Parameters:
    ///   - imageID: The identifier of the image.
    ///   - region: The region to request (x, y, width, height).
    /// - Returns: The requested image region.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestRegion(imageID: String, region: (x: Int, y: Int, width: Int, height: Int)) async throws -> J2KImage {
        fatalError("Not implemented")
    }
}

/// A JPIP session for managing image streaming.
public actor JPIPSession {
    /// The session identifier.
    public let sessionID: String
    
    /// Creates a new JPIP session.
    ///
    /// - Parameter sessionID: The session identifier.
    public init(sessionID: String) {
        self.sessionID = sessionID
    }
    
    /// Closes the session.
    ///
    /// - Throws: ``J2KError`` if closing fails.
    public func close() async throws {
        fatalError("Not implemented")
    }
}

/// A JPIP server for serving JPEG 2000 images.
public actor JPIPServer {
    /// The port to listen on.
    public let port: Int
    
    /// Creates a new JPIP server.
    ///
    /// - Parameter port: The port to listen on (default: 8080).
    public init(port: Int = 8080) {
        self.port = port
    }
    
    /// Starts the server.
    ///
    /// - Throws: ``J2KError`` if the server cannot start.
    public func start() async throws {
        fatalError("Not implemented")
    }
    
    /// Stops the server.
    ///
    /// - Throws: ``J2KError`` if stopping fails.
    public func stop() async throws {
        fatalError("Not implemented")
    }
}
