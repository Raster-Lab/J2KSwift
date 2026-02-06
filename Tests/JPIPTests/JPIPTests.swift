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
    
    // MARK: - JPIPRequest Tests
    
    func testBasicRequestCreation() {
        let request = JPIPRequest(target: "test.jp2")
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertNil(request.fsiz)
        XCTAssertNil(request.rsiz)
        XCTAssertNil(request.roff)
        XCTAssertNil(request.layers)
        XCTAssertNil(request.cid)
    }
    
    func testRequestQueryItems() {
        var request = JPIPRequest(target: "image.jp2")
        request.fsiz = (width: 800, height: 600)
        request.layers = 3
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "image.jp2")
        XCTAssertEqual(items["fsiz"], "800,600")
        XCTAssertEqual(items["layers"], "3")
    }
    
    func testRegionRequest() {
        let request = JPIPRequest.regionRequest(
            target: "test.jp2",
            x: 100,
            y: 200,
            width: 400,
            height: 300,
            layers: 5
        )
        
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.roff?.x, 100)
        XCTAssertEqual(request.roff?.y, 200)
        XCTAssertEqual(request.rsiz?.width, 400)
        XCTAssertEqual(request.rsiz?.height, 300)
        XCTAssertEqual(request.layers, 5)
    }
    
    func testResolutionRequest() {
        let request = JPIPRequest.resolutionRequest(
            target: "test.jp2",
            width: 1024,
            height: 768,
            layers: 2
        )
        
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.fsiz?.width, 1024)
        XCTAssertEqual(request.fsiz?.height, 768)
        XCTAssertEqual(request.layers, 2)
    }
    
    func testRequestWithChannelID() {
        var request = JPIPRequest(target: "image.jp2")
        request.cid = "12345"
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["cid"], "12345")
    }
    
    func testRequestWithChannelNew() {
        var request = JPIPRequest(target: "image.jp2")
        request.cnew = .http
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["cnew"], "http")
    }
    
    func testCompleteRequest() {
        var request = JPIPRequest(target: "complete.jp2")
        request.fsiz = (1920, 1080)
        request.rsiz = (960, 540)
        request.roff = (480, 270)
        request.layers = 4
        request.cid = "session123"
        request.len = 1024000
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "complete.jp2")
        XCTAssertEqual(items["fsiz"], "1920,1080")
        XCTAssertEqual(items["rsiz"], "960,540")
        XCTAssertEqual(items["roff"], "480,270")
        XCTAssertEqual(items["layers"], "4")
        XCTAssertEqual(items["cid"], "session123")
        XCTAssertEqual(items["len"], "1024000")
    }
    
    // MARK: - JPIPResponse Tests
    
    func testResponseCreation() {
        let data = Data([1, 2, 3, 4])
        let headers = ["Content-Type": "application/octet-stream"]
        let response = JPIPResponse(
            channelID: "test123",
            data: data,
            statusCode: 200,
            headers: headers
        )
        
        XCTAssertEqual(response.channelID, "test123")
        XCTAssertEqual(response.data, data)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["Content-Type"], "application/octet-stream")
    }
    
    func testParseChannelID() {
        let header1 = "cid=1942302"
        let cid1 = JPIPResponseParser.parseChannelID(from: header1)
        XCTAssertEqual(cid1, "1942302")
        
        let header2 = "cid=abc123,path=/jp2,transport=http"
        let cid2 = JPIPResponseParser.parseChannelID(from: header2)
        XCTAssertEqual(cid2, "abc123")
        
        let header3 = "path=/jp2,cid=xyz789,transport=http-tcp"
        let cid3 = JPIPResponseParser.parseChannelID(from: header3)
        XCTAssertEqual(cid3, "xyz789")
    }
    
    func testParseChannelIDNotFound() {
        let header = "path=/jp2,transport=http"
        let cid = JPIPResponseParser.parseChannelID(from: header)
        XCTAssertNil(cid)
    }
    
    func testExtractChannelID() {
        let headers = [
            "Content-Type": "application/octet-stream",
            "JPIP-cnew": "cid=session456,path=/image.jp2"
        ]
        let cid = JPIPResponseParser.extractChannelID(from: headers)
        XCTAssertEqual(cid, "session456")
    }
    
    func testExtractChannelIDCaseInsensitive() {
        let headers = [
            "jpip-cnew": "cid=test999"
        ]
        let cid = JPIPResponseParser.extractChannelID(from: headers)
        XCTAssertEqual(cid, "test999")
    }
    
    // MARK: - JPIPDataBin Tests
    
    func testDataBinCreation() {
        let data = Data([1, 2, 3, 4, 5])
        let bin = JPIPDataBin(
            binClass: .mainHeader,
            binID: 0,
            data: data,
            isComplete: true
        )
        
        XCTAssertEqual(bin.binClass, .mainHeader)
        XCTAssertEqual(bin.binID, 0)
        XCTAssertEqual(bin.data, data)
        XCTAssertTrue(bin.isComplete)
    }
    
    func testDataBinClasses() {
        XCTAssertEqual(JPIPDataBinClass.mainHeader.rawValue, 0)
        XCTAssertEqual(JPIPDataBinClass.tileHeader.rawValue, 1)
        XCTAssertEqual(JPIPDataBinClass.precinct.rawValue, 2)
        XCTAssertEqual(JPIPDataBinClass.tile.rawValue, 3)
        XCTAssertEqual(JPIPDataBinClass.extendedPrecinct.rawValue, 4)
        XCTAssertEqual(JPIPDataBinClass.metadata.rawValue, 5)
    }
    
    // MARK: - JPIPSession Tests
    
    func testSessionInitialization() async {
        let session = JPIPSession(sessionID: "init-test")
        let sessionID = await session.sessionID
        let isActive = await session.isActive
        
        XCTAssertEqual(sessionID, "init-test")
        XCTAssertFalse(isActive)
    }
    
    func testSessionActivation() async {
        let session = JPIPSession(sessionID: "active-test")
        await session.activate()
        let isActive = await session.isActive
        XCTAssertTrue(isActive)
    }
    
    func testSessionChannelID() async {
        let session = JPIPSession(sessionID: "channel-test")
        await session.setChannelID("chan123")
        let channelID = await session.channelID
        XCTAssertEqual(channelID, "chan123")
    }
    
    func testSessionTarget() async {
        let session = JPIPSession(sessionID: "target-test")
        await session.setTarget("image.jp2")
        let target = await session.target
        XCTAssertEqual(target, "image.jp2")
    }
    
    func testSessionClose() async throws {
        let session = JPIPSession(sessionID: "close-test")
        await session.setChannelID("chan999")
        await session.setTarget("test.jp2")
        await session.activate()
        
        try await session.close()
        
        let isActive = await session.isActive
        let channelID = await session.channelID
        let target = await session.target
        
        XCTAssertFalse(isActive)
        XCTAssertNil(channelID)
        XCTAssertNil(target)
    }
    
    func testSessionCacheTracking() async {
        let session = JPIPSession(sessionID: "cache-test")
        
        let bin1 = JPIPDataBin(binClass: .mainHeader, binID: 0, data: Data([1, 2, 3]), isComplete: true)
        let bin2 = JPIPDataBin(binClass: .precinct, binID: 5, data: Data([4, 5, 6]), isComplete: false)
        
        await session.recordDataBin(bin1)
        await session.recordDataBin(bin2)
        
        let hasBin1 = await session.hasDataBin(binClass: .mainHeader, binID: 0)
        let hasBin2 = await session.hasDataBin(binClass: .precinct, binID: 5)
        let hasBin3 = await session.hasDataBin(binClass: .tile, binID: 1)
        
        XCTAssertTrue(hasBin1)
        XCTAssertTrue(hasBin2)
        XCTAssertFalse(hasBin3)
    }
    
    // MARK: - JPIPTransport Tests
    
    func testTransportInitialization() async {
        let url = URL(string: "http://example.com:8080")!
        let transport = JPIPTransport(baseURL: url)
        // Just verify it can be created
        await transport.close()
    }
    
    // MARK: - JPIPClient Tests
    
    func testClientInitialization() async {
        let url = URL(string: "http://localhost:8080")!
        let client = JPIPClient(serverURL: url)
        let serverURL = await client.serverURL
        XCTAssertEqual(serverURL, url)
    }
    
    func testClientClose() async throws {
        let url = URL(string: "http://localhost:8080")!
        let client = JPIPClient(serverURL: url)
        try await client.close()
        // Verify no errors are thrown
    }
    
    // MARK: - Integration Tests
    
    func testChannelTypes() {
        XCTAssertEqual(JPIPChannelType.http.rawValue, "http")
        XCTAssertEqual(JPIPChannelType.httpTcp.rawValue, "http-tcp")
    }
    
    // MARK: - Data Streaming Tests (Week 72-74)
    
    func testProgressiveQualityRequest() {
        let request = JPIPRequest.progressiveQualityRequest(target: "test.jp2", upToLayers: 5)
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.layers, 5)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["layers"], "5")
    }
    
    func testResolutionLevelRequest() {
        let request = JPIPRequest.resolutionLevelRequest(target: "test.jp2", level: 2, layers: 3)
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.reslevels, 2)
        XCTAssertEqual(request.layers, 3)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["reslevels"], "2")
        XCTAssertEqual(items["layers"], "3")
    }
    
    func testResolutionLevelRequestWithoutLayers() {
        let request = JPIPRequest.resolutionLevelRequest(target: "test.jp2", level: 1)
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.reslevels, 1)
        XCTAssertNil(request.layers)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["reslevels"], "1")
        XCTAssertNil(items["layers"])
    }
    
    func testComponentRequest() {
        let request = JPIPRequest.componentRequest(target: "test.jp2", components: [0, 1], layers: 2)
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.comps, [0, 1])
        XCTAssertEqual(request.layers, 2)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["comps"], "0,1")
        XCTAssertEqual(items["layers"], "2")
    }
    
    func testComponentRequestWithSingleComponent() {
        let request = JPIPRequest.componentRequest(target: "test.jp2", components: [2])
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.comps, [2])
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["comps"], "2")
    }
    
    func testComponentRequestWithMultipleComponents() {
        let request = JPIPRequest.componentRequest(target: "test.jp2", components: [0, 1, 2])
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.comps, [0, 1, 2])
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["comps"], "0,1,2")
    }
    
    func testMetadataRequest() {
        let request = JPIPRequest.metadataRequest(target: "test.jp2")
        XCTAssertEqual(request.target, "test.jp2")
        XCTAssertEqual(request.metadata, true)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["meta"], "yes")
    }
    
    func testRequestWithAllParameters() {
        var request = JPIPRequest(target: "test.jp2")
        request.fsiz = (1024, 768)
        request.rsiz = (512, 384)
        request.roff = (256, 192)
        request.layers = 4
        request.cid = "channel123"
        request.cnew = .http
        request.len = 65536
        request.comps = [0, 1, 2]
        request.reslevels = 3
        request.metadata = true
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertEqual(items["fsiz"], "1024,768")
        XCTAssertEqual(items["rsiz"], "512,384")
        XCTAssertEqual(items["roff"], "256,192")
        XCTAssertEqual(items["layers"], "4")
        XCTAssertEqual(items["cid"], "channel123")
        XCTAssertEqual(items["cnew"], "http")
        XCTAssertEqual(items["len"], "65536")
        XCTAssertEqual(items["comps"], "0,1,2")
        XCTAssertEqual(items["reslevels"], "3")
        XCTAssertEqual(items["meta"], "yes")
    }
    
    func testEmptyComponentsNotIncludedInQueryItems() {
        var request = JPIPRequest(target: "test.jp2")
        request.comps = []
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertNil(items["comps"])
    }
    
    func testMetadataFalseNotIncludedInQueryItems() {
        var request = JPIPRequest(target: "test.jp2")
        request.metadata = false
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "test.jp2")
        XCTAssertNil(items["meta"])
    }
    
    func testResolutionLevelZero() {
        let request = JPIPRequest.resolutionLevelRequest(target: "test.jp2", level: 0)
        XCTAssertEqual(request.reslevels, 0)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["reslevels"], "0")
    }
    
    func testCompleteProgressiveQualityRequestWithAllOptions() {
        var request = JPIPRequest.progressiveQualityRequest(target: "image.jp2", upToLayers: 8)
        request.fsiz = (2048, 1536)
        request.cid = "session-abc"
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "image.jp2")
        XCTAssertEqual(items["layers"], "8")
        XCTAssertEqual(items["fsiz"], "2048,1536")
        XCTAssertEqual(items["cid"], "session-abc")
    }
    
    func testCompleteResolutionLevelRequestWithRegion() {
        var request = JPIPRequest.resolutionLevelRequest(target: "image.jp2", level: 2, layers: 4)
        request.roff = (100, 200)
        request.rsiz = (400, 300)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "image.jp2")
        XCTAssertEqual(items["reslevels"], "2")
        XCTAssertEqual(items["layers"], "4")
        XCTAssertEqual(items["roff"], "100,200")
        XCTAssertEqual(items["rsiz"], "400,300")
    }
    
    func testCompleteComponentRequestWithResolutionAndRegion() {
        var request = JPIPRequest.componentRequest(target: "image.jp2", components: [0, 2], layers: 3)
        request.reslevels = 1
        request.roff = (50, 50)
        request.rsiz = (200, 200)
        
        let items = request.buildQueryItems()
        XCTAssertEqual(items["target"], "image.jp2")
        XCTAssertEqual(items["comps"], "0,2")
        XCTAssertEqual(items["layers"], "3")
        XCTAssertEqual(items["reslevels"], "1")
        XCTAssertEqual(items["roff"], "50,50")
        XCTAssertEqual(items["rsiz"], "200,200")
    }
}
