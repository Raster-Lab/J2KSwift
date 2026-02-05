import XCTest
@testable import JPIP
@testable import J2KCore
@testable import J2KFileFormat

/// Tests for the JPIP module.
final class JPIPTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() async throws {
        // This test verifies that the JPIP module can be imported and basic types are accessible.
        let serverURL = URL(string: "http://localhost:8080")!
        let client = JPIPClient(serverURL: serverURL)
        XCTAssertNotNil(client)
        let actualURL = await client.serverURL
        XCTAssertEqual(actualURL, serverURL)
    }
    
    /// Tests that a JPIP session can be created.
    func testSessionCreation() async throws {
        let session = JPIPSession(sessionID: "test-session")
        XCTAssertNotNil(session)
        let actualID = await session.sessionID
        XCTAssertEqual(actualID, "test-session")
    }
    
    /// Tests that a JPIP server can be instantiated.
    func testServerInstantiation() async throws {
        let server = JPIPServer(port: 9090)
        XCTAssertNotNil(server)
        let actualPort = await server.port
        XCTAssertEqual(actualPort, 9090)
    }
}
