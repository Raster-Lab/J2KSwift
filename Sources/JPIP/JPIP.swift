/// # JPIP
///
/// JPEG 2000 Interactive Protocol (JPIP) implementation.
///
/// This module provides support for the JPIP protocol, enabling efficient streaming
/// and progressive transmission of JPEG 2000 images over networks.
///
/// ## Overview
///
/// JPIP (ISO/IEC 15444-9) enables interactive access to JPEG 2000 images over HTTP.
/// Clients can request specific regions, resolutions, or quality layers without
/// downloading entire images.
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
///
/// ### Requests and Responses
/// - ``JPIPRequest``
/// - ``JPIPResponse``
///
/// ### Transport
/// - ``JPIPTransport``

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
    
    /// The HTTP transport layer.
    private let transport: JPIPTransport
    
    /// Active session, if any.
    private var session: JPIPSession?
    
    /// Creates a new JPIP client.
    ///
    /// - Parameter serverURL: The URL of the JPIP server.
    public init(serverURL: URL) {
        self.serverURL = serverURL
        self.transport = JPIPTransport(baseURL: serverURL)
    }
    
    /// Creates a new session for an image.
    ///
    /// - Parameter target: The target image identifier.
    /// - Returns: A JPIP session.
    /// - Throws: ``J2KError`` if session creation fails.
    public func createSession(target: String) async throws -> JPIPSession {
        // Create a new session ID
        let sessionID = UUID().uuidString
        let newSession = JPIPSession(sessionID: sessionID)
        await newSession.setTarget(target)
        
        // Make initial request to establish channel
        var request = JPIPRequest(target: target)
        request.cnew = .http
        
        let response = try await transport.send(request)
        
        // Extract and set channel ID
        if let channelID = response.channelID {
            await newSession.setChannelID(channelID)
            await newSession.activate()
        }
        
        self.session = newSession
        return newSession
    }
    
    /// Requests an image from the server.
    ///
    /// - Parameter imageID: The identifier of the image to request.
    /// - Returns: The requested image.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestImage(imageID: String) async throws -> J2KImage {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build request
        var request = JPIPRequest(target: imageID)
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        _ = try await transport.send(request)
        
        // For now, return a placeholder image
        // TODO (v1.1 Phase 5): Parse response data and construct J2KImage
        throw J2KError.notImplemented("Image parsing from JPIP response not yet implemented")
    }
    
    /// Requests a specific region of interest from an image.
    ///
    /// - Parameters:
    ///   - imageID: The identifier of the image.
    ///   - region: The region to request (x, y, width, height).
    /// - Returns: The requested image region.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestRegion(imageID: String, region: (x: Int, y: Int, width: Int, height: Int)) async throws -> J2KImage {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build region request
        var request = JPIPRequest.regionRequest(
            target: imageID,
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        )
        
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        _ = try await transport.send(request)
        
        // For now, return a placeholder
        // TODO (v1.1 Phase 5): Parse response data and construct J2KImage
        throw J2KError.notImplemented("Region parsing from JPIP response not yet implemented")
    }
    
    /// Gets the current session or creates a new one.
    private func getOrCreateSession(target: String) async throws -> JPIPSession {
        if let existing = self.session, await existing.target == target {
            return existing
        }
        return try await createSession(target: target)
    }
    
    /// Requests progressive quality layers for an image.
    ///
    /// - Parameters:
    ///   - imageID: The identifier of the image.
    ///   - upToLayers: The maximum number of quality layers to request.
    /// - Returns: The image with progressive quality.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestProgressiveQuality(imageID: String, upToLayers: Int) async throws -> J2KImage {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build progressive quality request
        var request = JPIPRequest.progressiveQualityRequest(target: imageID, upToLayers: upToLayers)
        
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        _ = try await transport.send(request)
        
        // TODO (v1.1 Phase 5): Parse response data and construct J2KImage with progressive quality
        throw J2KError.notImplemented("Progressive quality parsing from JPIP response not yet implemented")
    }
    
    /// Requests a specific resolution level of an image.
    ///
    /// - Parameters:
    ///   - imageID: The identifier of the image.
    ///   - level: The resolution level (0 = full resolution, higher values = lower resolution).
    ///   - layers: Optional number of quality layers.
    /// - Returns: The image at the specified resolution level.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestResolutionLevel(imageID: String, level: Int, layers: Int? = nil) async throws -> J2KImage {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build resolution level request
        var request = JPIPRequest.resolutionLevelRequest(target: imageID, level: level, layers: layers)
        
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        _ = try await transport.send(request)
        
        // TODO (v1.1 Phase 5): Parse response data and construct J2KImage at specified resolution
        throw J2KError.notImplemented("Resolution level parsing from JPIP response not yet implemented")
    }
    
    /// Requests specific components of an image.
    ///
    /// - Parameters:
    ///   - imageID: The identifier of the image.
    ///   - components: Array of component indices to request (e.g., [0, 1] for R and G channels).
    ///   - layers: Optional number of quality layers.
    /// - Returns: The image with only the specified components.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestComponents(imageID: String, components: [Int], layers: Int? = nil) async throws -> J2KImage {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build component request
        var request = JPIPRequest.componentRequest(target: imageID, components: components, layers: layers)
        
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        _ = try await transport.send(request)
        
        // TODO (v1.1 Phase 5): Parse response data and construct J2KImage with specified components
        throw J2KError.notImplemented("Component selection parsing from JPIP response not yet implemented")
    }
    
    /// Requests metadata for an image without transferring image data.
    ///
    /// - Parameter imageID: The identifier of the image.
    /// - Returns: A dictionary containing the image metadata.
    /// - Throws: ``J2KError`` if the request fails.
    public func requestMetadata(imageID: String) async throws -> [String: Any] {
        // Get or create session
        let currentSession = try await getOrCreateSession(target: imageID)
        
        // Build metadata request
        var request = JPIPRequest.metadataRequest(target: imageID)
        
        if let channelID = await currentSession.channelID {
            request.cid = channelID
        }
        
        // Send request
        let response = try await transport.send(request)
        
        // TODO (v1.1 Phase 5): Parse metadata from response
        // For now, return basic info from headers
        var metadata: [String: Any] = [:]
        metadata["channelID"] = response.channelID ?? "none"
        metadata["statusCode"] = response.statusCode
        metadata["dataSize"] = response.data.count
        
        return metadata
    }
    
    /// Closes the client and any active sessions.
    public func close() async throws {
        if let currentSession = self.session {
            try await currentSession.close()
        }
        await transport.close()
    }
}

// Server is now implemented in JPIPServer.swift
