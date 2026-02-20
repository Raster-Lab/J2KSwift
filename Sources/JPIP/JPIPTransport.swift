//
// JPIPTransport.swift
// J2KSwift
//
/// # JPIPTransport
///
/// HTTP transport layer for JPIP protocol.

import Foundation
import J2KCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP transport for JPIP requests.
public actor JPIPTransport {
    /// The base server URL.
    private let baseURL: URL

    /// The URL session for network requests.
    private let session: URLSession

    /// Creates a new JPIP transport.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL of the JPIP server.
    ///   - configuration: Optional URL session configuration.
    public init(baseURL: URL, configuration: URLSessionConfiguration? = nil) {
        self.baseURL = baseURL
        let config = configuration ?? URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Sends a JPIP request to the server.
    ///
    /// - Parameter request: The JPIP request to send.
    /// - Returns: The JPIP response.
    /// - Throws: ``J2KError`` if the request fails.
    public func send(_ request: JPIPRequest) async throws -> JPIPResponse {
        let urlRequest = try buildURLRequest(from: request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw J2KError.networkError("Invalid response type")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw J2KError.networkError("HTTP error: \(httpResponse.statusCode)")
        }

        let headers = JPIPResponseParser.parseHeaders(from: httpResponse)
        let channelID = JPIPResponseParser.extractChannelID(from: headers)

        return JPIPResponse(
            channelID: channelID,
            data: data,
            statusCode: httpResponse.statusCode,
            headers: headers
        )
    }

    /// Builds a URLRequest from a JPIP request.
    ///
    /// - Parameter request: The JPIP request.
    /// - Returns: A configured URL request.
    /// - Throws: ``J2KError`` if the URL cannot be built.
    private func buildURLRequest(from request: JPIPRequest) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw J2KError.invalidParameter("Invalid base URL")
        }

        let queryItems = request.buildQueryItems()
        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw J2KError.invalidParameter("Failed to build request URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        return urlRequest
    }

    /// Closes the transport and cleans up resources.
    public func close() {
        session.finishTasksAndInvalidate()
    }
}

extension J2KError {
    /// Creates a network error.
    ///
    /// - Parameter message: The error message.
    /// - Returns: A network error.
    static func networkError(_ message: String) -> J2KError {
        .internalError("Network error: \(message)")
    }
}
