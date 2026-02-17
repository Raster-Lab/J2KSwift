/// # JPIPServer
///
/// Server implementation for the JPIP protocol.

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A JPIP server for serving JPEG 2000 images over HTTP.
///
/// The server handles multiple concurrent clients, manages request queues,
/// implements bandwidth throttling, and serves image data progressively.
/// Supports HTJ2K format detection, data bin streaming, and on-the-fly
/// transcoding between legacy JPEG 2000 and HTJ2K formats.
///
/// Example usage:
/// ```swift
/// let server = JPIPServer(port: 8080)
/// 
/// // Register images
/// try await server.registerImage(name: "sample.jp2", at: imageURL)
/// 
/// // Start serving
/// try await server.start()
/// 
/// // Server is now accepting requests...
/// 
/// // Stop when done
/// try await server.stop()
/// ```
public actor JPIPServer {
    /// The port to listen on.
    nonisolated public let port: Int
    
    /// Registered images available for serving.
    private var registeredImages: [String: URL]
    
    /// Cached image format information for registered images.
    private var imageInfoCache: [String: JPIPImageInfo]
    
    /// HTJ2K support helper.
    private let htj2kSupport: JPIPHTJ2KSupport
    
    /// Data bin generator for codestream extraction.
    private let dataBinGenerator: JPIPDataBinGenerator
    
    /// Transcoding service for on-the-fly format conversion.
    private let transcodingService: JPIPTranscodingService
    
    /// Cache for transcoded data.
    private let transcodingCache: JPIPTranscodingCache
    
    /// Active client sessions.
    private var sessions: [String: JPIPServerSession]
    
    /// Request queue for managing incoming requests.
    private var requestQueue: JPIPRequestQueue
    
    /// Bandwidth throttle for controlling data rates.
    private var bandwidthThrottle: JPIPBandwidthThrottle
    
    /// Whether the server is currently running.
    private var isRunning: Bool
    
    /// Configuration for the server.
    nonisolated public let configuration: Configuration
    
    /// Server statistics.
    private var stats: Statistics
    
    /// Configuration for the JPIP server.
    public struct Configuration: Sendable {
        /// Maximum number of concurrent clients.
        public let maxClients: Int
        
        /// Maximum queue size for pending requests.
        public let maxQueueSize: Int
        
        /// Global bandwidth limit in bytes per second (nil = unlimited).
        public let globalBandwidthLimit: Int?
        
        /// Per-client bandwidth limit in bytes per second (nil = unlimited).
        public let perClientBandwidthLimit: Int?
        
        /// Session timeout in seconds.
        public let sessionTimeout: TimeInterval
        
        /// Creates a new server configuration.
        ///
        /// - Parameters:
        ///   - maxClients: Maximum concurrent clients (default: 100).
        ///   - maxQueueSize: Maximum queue size (default: 1000).
        ///   - globalBandwidthLimit: Global bandwidth limit in bytes/sec (default: nil).
        ///   - perClientBandwidthLimit: Per-client bandwidth limit in bytes/sec (default: nil).
        ///   - sessionTimeout: Session timeout in seconds (default: 300).
        public init(
            maxClients: Int = 100,
            maxQueueSize: Int = 1000,
            globalBandwidthLimit: Int? = nil,
            perClientBandwidthLimit: Int? = nil,
            sessionTimeout: TimeInterval = 300
        ) {
            self.maxClients = maxClients
            self.maxQueueSize = maxQueueSize
            self.globalBandwidthLimit = globalBandwidthLimit
            self.perClientBandwidthLimit = perClientBandwidthLimit
            self.sessionTimeout = sessionTimeout
        }
    }
    
    /// Server statistics.
    public struct Statistics: Sendable {
        /// Total requests received.
        public var totalRequests: Int
        
        /// Active client count.
        public var activeClients: Int
        
        /// Total bytes sent.
        public var totalBytesSent: Int
        
        /// Requests in queue.
        public var queuedRequests: Int
        
        /// Creates empty statistics.
        public init() {
            self.totalRequests = 0
            self.activeClients = 0
            self.totalBytesSent = 0
            self.queuedRequests = 0
        }
    }
    
    /// Creates a new JPIP server.
    ///
    /// - Parameters:
    ///   - port: The port to listen on (default: 8080).
    ///   - configuration: Server configuration.
    public init(port: Int = 8080, configuration: Configuration = Configuration()) {
        self.port = port
        self.configuration = configuration
        self.registeredImages = [:]
        self.imageInfoCache = [:]
        self.htj2kSupport = JPIPHTJ2KSupport()
        self.dataBinGenerator = JPIPDataBinGenerator()
        self.transcodingService = JPIPTranscodingService()
        self.transcodingCache = JPIPTranscodingCache()
        self.sessions = [:]
        self.requestQueue = JPIPRequestQueue(maxSize: configuration.maxQueueSize)
        self.bandwidthThrottle = JPIPBandwidthThrottle(
            globalLimit: configuration.globalBandwidthLimit,
            perClientLimit: configuration.perClientBandwidthLimit
        )
        self.isRunning = false
        self.stats = Statistics()
    }
    
    /// Registers an image for serving.
    ///
    /// - Parameters:
    ///   - name: The image name (used as target in requests).
    ///   - url: The file URL of the JPEG 2000 image.
    /// - Throws: ``J2KError`` if the image cannot be accessed.
    public func registerImage(name: String, at url: URL) throws {
        // Verify the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw J2KError.fileNotFound("Image file not found: \(url.path)")
        }
        
        registeredImages[name] = url
        
        // Detect format and cache image info
        if let info = try? htj2kSupport.detectFormat(at: url) {
            imageInfoCache[name] = info
        }
    }
    
    /// Unregisters an image from serving.
    ///
    /// - Parameter name: The image name to unregister.
    public func unregisterImage(name: String) {
        registeredImages.removeValue(forKey: name)
        imageInfoCache.removeValue(forKey: name)
    }
    
    /// Gets the list of registered image names.
    ///
    /// - Returns: Array of registered image names.
    public func listRegisteredImages() async -> [String] {
        return Array(registeredImages.keys)
    }
    
    /// Starts the server.
    ///
    /// This is a placeholder implementation. In a real server, this would
    /// start an HTTP server (using SwiftNIO, Vapor, or similar framework).
    ///
    /// - Throws: ``J2KError`` if the server cannot start.
    public func start() async throws {
        guard !isRunning else {
            throw J2KError.invalidState("Server is already running")
        }
        
        isRunning = true
        
        // In a real implementation, we would:
        // 1. Bind to the port
        // 2. Start accepting connections
        // 3. Spawn request handlers
        // 4. Monitor for shutdown
        
        // For now, just mark as running
        // Real implementation would require a web framework
    }
    
    /// Stops the server.
    ///
    /// - Throws: ``J2KError`` if stopping fails.
    public func stop() async throws {
        guard isRunning else {
            throw J2KError.invalidState("Server is not running")
        }
        
        isRunning = false
        
        // Close all active sessions
        for (_, session) in sessions {
            await session.close()
        }
        sessions.removeAll()
        
        // Clear the request queue
        await requestQueue.clear()
    }
    
    /// Handles an incoming JPIP request.
    ///
    /// This method processes JPIP requests and generates appropriate responses.
    ///
    /// - Parameter request: The JPIP request to handle.
    /// - Returns: A JPIP response.
    /// - Throws: ``J2KError`` if the request cannot be handled.
    public func handleRequest(_ request: JPIPRequest) async throws -> JPIPResponse {
        guard isRunning else {
            throw J2KError.invalidState("Server is not running")
        }
        
        stats.totalRequests += 1
        
        // Enqueue the request
        try await requestQueue.enqueue(request, priority: determinePriority(request))
        stats.queuedRequests = await requestQueue.size
        
        // Get or create session
        let session = try await getOrCreateSession(for: request)
        
        // Check bandwidth limits
        let canSend = await bandwidthThrottle.canSend(
            clientID: session.sessionID,
            bytes: 1024 // Estimated response size
        )
        
        guard canSend else {
            // Return throttled response
            return JPIPResponse(
                channelID: session.channelID,
                data: Data(),
                statusCode: 503, // Service Unavailable
                headers: ["Retry-After": "1"]
            )
        }
        
        // Process the request
        let response = try await processRequest(request, session: session)
        
        // Record bandwidth usage
        await bandwidthThrottle.recordSent(
            clientID: session.sessionID,
            bytes: response.data.count
        )
        
        stats.totalBytesSent += response.data.count
        stats.queuedRequests = await requestQueue.size
        
        return response
    }
    
    /// Determines the priority for a request.
    private func determinePriority(_ request: JPIPRequest) -> Int {
        // Higher priority for:
        // - Session creation requests (cnew)
        // - Metadata requests
        // - Small region requests
        
        if request.cnew != nil {
            return 100 // Highest priority for new sessions
        }
        
        if request.metadata == true {
            return 90 // High priority for metadata
        }
        
        if let rsiz = request.rsiz, rsiz.width * rsiz.height < 10000 {
            return 80 // High priority for small regions
        }
        
        return 50 // Normal priority
    }
    
    /// Gets an existing session or creates a new one.
    private func getOrCreateSession(for request: JPIPRequest) async throws -> JPIPServerSession {
        // Check if request has existing channel ID
        if let cid = request.cid, let existingSession = sessions[cid] {
            return existingSession
        }
        
        // Create new session if cnew is specified
        if request.cnew != nil {
            let sessionID = UUID().uuidString
            let channelID = "cid-\(sessionID)"
            
            let newSession = JPIPServerSession(
                sessionID: sessionID,
                channelID: channelID,
                target: request.target
            )
            
            sessions[channelID] = newSession
            stats.activeClients = sessions.count
            
            return newSession
        }
        
        throw J2KError.invalidParameter("No session ID and no cnew specified")
    }
    
    /// Processes a request and generates a response.
    private func processRequest(
        _ request: JPIPRequest,
        session: JPIPServerSession
    ) async throws -> JPIPResponse {
        // Verify the target image is registered
        guard let imageURL = registeredImages[request.target] else {
            throw J2KError.fileNotFound("Image not found: \(request.target)")
        }
        
        // For session creation, return minimal response with channel ID
        if request.cnew != nil {
            var headers = [
                "JPIP-cnew": "cid=\(session.channelID),path=/jpip,transport=http",
                "Content-Type": "application/octet-stream"
            ]
            
            // Add HTJ2K capability headers if the image supports it
            if let info = imageInfoCache[request.target] {
                let capHeaders = htj2kSupport.capabilityHeaders(for: info)
                for (key, value) in capHeaders {
                    if key != "Content-Type" { // Don't override Content-Type
                        headers[key] = value
                    }
                }
            }
            
            return JPIPResponse(
                channelID: session.channelID,
                data: Data(),
                statusCode: 200,
                headers: headers
            )
        }
        
        // For metadata requests, return basic metadata
        if request.metadata == true {
            let metadataData = try await generateMetadata(for: imageURL)
            return JPIPResponse(
                channelID: session.channelID,
                data: metadataData,
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"]
            )
        }
        
        // For image data requests, generate response data
        let imageData = try await generateImageData(
            for: imageURL,
            request: request,
            session: session
        )
        
        return JPIPResponse(
            channelID: session.channelID,
            data: imageData,
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"]
        )
    }
    
    /// Generates metadata for an image.
    private func generateMetadata(for imageURL: URL) async throws -> Data {
        // Check if we have cached image info for format-aware metadata
        for (name, url) in registeredImages where url == imageURL {
            if let info = imageInfoCache[name] {
                return htj2kSupport.generateFormatMetadata(for: info)
            }
        }
        
        // Fallback: return basic metadata
        return Data("metadata".utf8)
    }
    
    /// Generates image data for a request.
    private func generateImageData(
        for imageURL: URL,
        request: JPIPRequest,
        session: JPIPServerSession
    ) async throws -> Data {
        // Read the source codestream data
        let sourceData = try Data(contentsOf: imageURL, options: .mappedIfSafe)
        
        // Determine if on-the-fly transcoding is needed
        let preference = request.codingPreference ?? .none
        let imageName = registeredImages.first(where: { $0.value == imageURL })?.key
        let sourceIsHTJ2K = imageName.flatMap { imageInfoCache[$0]?.isHTJ2K } ?? false
        
        var dataToServe = sourceData
        
        // Apply on-the-fly transcoding if client prefers a different format
        if transcodingService.needsTranscoding(preference: preference, sourceIsHTJ2K: sourceIsHTJ2K) {
            let sourceHash = stableHash(for: sourceData)
            if let direction = transcodingService.determineDirection(
                preference: preference, sourceIsHTJ2K: sourceIsHTJ2K
            ) {
                if let cached = await transcodingCache.get(sourceHash: sourceHash, direction: direction) {
                    dataToServe = cached
                } else if let result = try? transcodingService.transcode(
                    data: sourceData,
                    preference: preference,
                    sourceIsHTJ2K: sourceIsHTJ2K
                ), result.wasTranscoded {
                    // Transcoding succeeded; use transcoded data
                    dataToServe = result.data
                    await transcodingCache.put(
                        data: result.data,
                        sourceHash: sourceHash,
                        direction: direction
                    )
                }
                // If transcoding fails, gracefully fall back to serving original data.
                // This ensures clients always receive valid image data even if
                // the source codestream cannot be transcoded to the preferred format.
            }
        }
        
        // Try to generate data bins from the codestream for progressive streaming
        if let dataBins = try? dataBinGenerator.generateDataBins(from: dataToServe), !dataBins.isEmpty {
            var responseData = Data()
            for bin in dataBins {
                let alreadySent = await session.hasDataBin(binClass: bin.binClass, binID: bin.binID)
                if alreadySent {
                    continue
                }
                responseData.append(bin.data)
                await session.recordSentDataBin(bin)
            }
            
            // If all bins were already sent, re-serve the full data
            if responseData.isEmpty {
                responseData = dataToServe
            }
            
            // Apply response length limit if specified
            if let maxLen = request.len, responseData.count > maxLen {
                responseData = responseData.prefix(maxLen)
            }
            
            return responseData
        }
        
        // Fallback: serve raw data when codestream parsing is not applicable
        var responseData = dataToServe
        if let maxLen = request.len, responseData.count > maxLen {
            responseData = responseData.prefix(maxLen)
        }
        return responseData
    }
    
    /// Gets the current server statistics.
    ///
    /// - Returns: Current server statistics.
    public func getStatistics() async -> Statistics {
        var currentStats = stats
        currentStats.activeClients = sessions.count
        currentStats.queuedRequests = await requestQueue.size
        return currentStats
    }
    
    /// Closes a client session.
    ///
    /// - Parameter sessionID: The session ID to close.
    public func closeSession(_ sessionID: String) async {
        if let session = sessions.removeValue(forKey: sessionID) {
            await session.close()
            stats.activeClients = sessions.count
        }
    }
    
    /// Gets the number of active sessions.
    ///
    /// - Returns: Number of active sessions.
    public func getActiveSessionCount() async -> Int {
        return sessions.count
    }
    
    /// Gets the format information for a registered image.
    ///
    /// - Parameter name: The registered image name.
    /// - Returns: The image info if available, nil otherwise.
    public func getImageInfo(name: String) -> JPIPImageInfo? {
        return imageInfoCache[name]
    }
    
    /// Computes a stable hash string for data, suitable for cache keys.
    ///
    /// Uses a simple FNV-1a-like hash that is stable across executions.
    ///
    /// - Parameter data: The data to hash.
    /// - Returns: A hex string hash.
    private func stableHash(for data: Data) -> String {
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        return String(hash, radix: 16)
    }
}

extension J2KError {
    /// Creates a file not found error.
    static func fileNotFound(_ message: String) -> J2KError {
        return .internalError("File not found: \(message)")
    }
    
    /// Creates an invalid state error.
    static func invalidState(_ message: String) -> J2KError {
        return .internalError("Invalid state: \(message)")
    }
}
