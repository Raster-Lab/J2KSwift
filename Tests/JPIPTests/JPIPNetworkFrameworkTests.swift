import XCTest
@testable import JPIP
@testable import J2KCore

/// Tests for Network.framework integration.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
final class JPIPNetworkFrameworkTests: XCTestCase {
    // MARK: - Network Transport Tests
    
    func testNetworkTransportInitialization() async throws {
        let baseURL = URL(string: "https://example.com")!
        let transport = JPIPNetworkTransport(baseURL: baseURL)
        
        // Just test initialization, not actual connection
        XCTAssertNotNil(transport)
    }
    
    func testNetworkTransportConfiguration() async throws {
        let baseURL = URL(string: "https://example.com")!
        let config = JPIPNetworkTransport.Configuration(
            enableHTTP3: true,
            enableTLS: true,
            connectionTimeout: 15,
            requestTimeout: 30,
            qos: .userInitiated
        )
        let transport = JPIPNetworkTransport(baseURL: baseURL, configuration: config)
        
        XCTAssertNotNil(transport)
    }
    
    func testNetworkTransportConfigurationDefaults() async throws {
        let config = JPIPNetworkTransport.Configuration()
        
        XCTAssertTrue(config.enableHTTP3)
        XCTAssertTrue(config.enableTLS)
        XCTAssertEqual(config.connectionTimeout, 30)
        XCTAssertEqual(config.requestTimeout, 60)
    }
    
    func testNetworkTransportHTTP3Disabled() async throws {
        let baseURL = URL(string: "https://example.com")!
        let config = JPIPNetworkTransport.Configuration(
            enableHTTP3: false,
            enableTLS: true
        )
        let transport = JPIPNetworkTransport(baseURL: baseURL, configuration: config)
        
        XCTAssertNotNil(transport)
    }
    
    func testNetworkTransportTLSDisabled() async throws {
        let baseURL = URL(string: "http://example.com")!
        let config = JPIPNetworkTransport.Configuration(
            enableHTTP3: false,
            enableTLS: false
        )
        let transport = JPIPNetworkTransport(baseURL: baseURL, configuration: config)
        
        XCTAssertNotNil(transport)
    }
    
    // MARK: - QUIC Configuration Tests
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testQUICConfigurationDefaults() throws {
        let config = JPIPQUICConfiguration()
        
        XCTAssertTrue(config.enableZeroRTT)
        XCTAssertEqual(config.maxIdleTimeout, 30)
        XCTAssertEqual(config.initialMaxData, 10 * 1024 * 1024)
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testQUICConfigurationCustom() throws {
        let config = JPIPQUICConfiguration(
            enableZeroRTT: false,
            maxIdleTimeout: 60,
            initialMaxData: 20 * 1024 * 1024
        )
        
        XCTAssertFalse(config.enableZeroRTT)
        XCTAssertEqual(config.maxIdleTimeout, 60)
        XCTAssertEqual(config.initialMaxData, 20 * 1024 * 1024)
    }
    
    // MARK: - HTTP/3 Configuration Tests
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testHTTP3ConfigurationDefaults() throws {
        let config = JPIPHTTP3Configuration()
        
        XCTAssertFalse(config.enableServerPush)
        XCTAssertEqual(config.maxConcurrentStreams, 100)
        XCTAssertTrue(config.enableEarlyData)
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testHTTP3ConfigurationCustom() throws {
        let config = JPIPHTTP3Configuration(
            enableServerPush: true,
            maxConcurrentStreams: 200,
            enableEarlyData: false
        )
        
        XCTAssertTrue(config.enableServerPush)
        XCTAssertEqual(config.maxConcurrentStreams, 200)
        XCTAssertFalse(config.enableEarlyData)
    }
    
    // MARK: - TLS Configuration Tests
    
    func testTLSConfigurationDefaults() throws {
        let config = JPIPTLSConfiguration()
        
        XCTAssertTrue(config.enableSessionResumption)
        XCTAssertTrue(config.verifyServerCertificate)
    }
    
    func testTLSConfigurationCustom() throws {
        let config = JPIPTLSConfiguration(
            minimumVersion: .v13,
            enableSessionResumption: false,
            verifyServerCertificate: false
        )
        
        XCTAssertFalse(config.enableSessionResumption)
        XCTAssertFalse(config.verifyServerCertificate)
    }
    
    func testTLSConfigurationV12() throws {
        let config = JPIPTLSConfiguration(minimumVersion: .v12)
        XCTAssertNotNil(config)
    }
    
    func testTLSConfigurationV13() throws {
        let config = JPIPTLSConfiguration(minimumVersion: .v13)
        XCTAssertNotNil(config)
    }
    
    // MARK: - Background Transfer Service Tests (iOS only)
    
    #if os(iOS)
    @available(iOS 13.0, *)
    func testBackgroundTransferServiceInitialization() async throws {
        let service = JPIPBackgroundTransferService()
        XCTAssertNotNil(service)
    }
    
    @available(iOS 13.0, *)
    func testBackgroundTransferServiceTransferTask() async throws {
        let task = JPIPBackgroundTransferService.TransferTask(
            id: "test-123",
            request: JPIPRequest(target: "test", channelID: nil),
            status: .pending
        )
        
        XCTAssertEqual(task.id, "test-123")
    }
    
    @available(iOS 13.0, *)
    func testBackgroundTransferServiceTransferStatus() async throws {
        let statusPending = JPIPBackgroundTransferService.TransferStatus.pending
        let statusCompleted = JPIPBackgroundTransferService.TransferStatus.completed
        
        // Just verify enum cases exist
        XCTAssertNotNil(statusPending)
        XCTAssertNotNil(statusCompleted)
    }
    #endif
    
    // MARK: - Integration Tests
    
    func testNetworkTransportMultipleInstances() async throws {
        let url1 = URL(string: "https://server1.example.com")!
        let url2 = URL(string: "https://server2.example.com")!
        
        let transport1 = JPIPNetworkTransport(baseURL: url1)
        let transport2 = JPIPNetworkTransport(baseURL: url2)
        
        XCTAssertNotNil(transport1)
        XCTAssertNotNil(transport2)
        
        await transport1.disconnect()
        await transport2.disconnect()
    }
    
    func testNetworkTransportConfigurationVariations() async throws {
        let baseURL = URL(string: "https://example.com")!
        
        // Test various QoS levels
        let qosLevels: [J2KQualityOfService] = [
            .userInteractive,
            .userInitiated,
            .utility,
            .background,
            .default
        ]
        
        for qos in qosLevels {
            let config = JPIPNetworkTransport.Configuration(qos: qos)
            let transport = JPIPNetworkTransport(baseURL: baseURL, configuration: config)
            XCTAssertNotNil(transport)
            await transport.disconnect()
        }
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testQUICConfigurationValidation() throws {
        // Test edge cases
        let config1 = JPIPQUICConfiguration(
            enableZeroRTT: true,
            maxIdleTimeout: 0,
            initialMaxData: 0
        )
        XCTAssertEqual(config1.maxIdleTimeout, 0)
        
        let config2 = JPIPQUICConfiguration(
            enableZeroRTT: false,
            maxIdleTimeout: 3600,
            initialMaxData: 100 * 1024 * 1024
        )
        XCTAssertEqual(config2.maxIdleTimeout, 3600)
    }
    
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
    func testHTTP3ConfigurationValidation() throws {
        // Test edge cases
        let config1 = JPIPHTTP3Configuration(
            enableServerPush: true,
            maxConcurrentStreams: 1,
            enableEarlyData: true
        )
        XCTAssertEqual(config1.maxConcurrentStreams, 1)
        
        let config2 = JPIPHTTP3Configuration(
            enableServerPush: false,
            maxConcurrentStreams: 1000,
            enableEarlyData: false
        )
        XCTAssertEqual(config2.maxConcurrentStreams, 1000)
    }
    
    // MARK: - Performance Tests
    
    func testNetworkTransportInitializationPerformance() throws {
        let baseURL = URL(string: "https://example.com")!
        
        measure {
            for _ in 0..<100 {
                let transport = JPIPNetworkTransport(baseURL: baseURL)
                _ = transport
            }
        }
    }
    
    func testConfigurationCreationPerformance() throws {
        measure {
            for _ in 0..<1000 {
                let config = JPIPNetworkTransport.Configuration(
                    enableHTTP3: true,
                    enableTLS: true,
                    connectionTimeout: 30,
                    requestTimeout: 60,
                    qos: .userInitiated
                )
                _ = config
            }
        }
    }
}
