---
description: "Use when writing or modifying tests for J2KSwift: XCTest conventions, test naming, Arrange-Act-Assert pattern, edge case testing, performance testing with measure blocks."
applyTo: "Tests/**"
---

# J2KSwift Testing Guidelines

## Test Naming
```swift
func test<Component><Scenario>() throws { }
```
Examples: `testEncoderLosslessRoundtrip`, `testDecoderMultiTile`, `testDWTEdgeTile`

## Pattern: Arrange-Act-Assert
```swift
func testComponentScenario() throws {
    // Arrange
    let input = ...
    
    // Act  
    let result = try component.method(input)
    
    // Assert
    XCTAssertEqual(result, expected)
}
```

## Required Test Coverage
- Every public API method
- Error conditions (invalid input, malformed data)
- Edge cases: empty input, 1x1 images, single component, max dimensions
- Lossless roundtrip: encode → decode → compare (MAE must be 0)
- Multi-tile images
- Both 5/3 and 9/7 DWT modes

## Performance Tests
```swift
func testEncodingPerformance() throws {
    let image = ...
    measure {
        _ = try? encoder.encode(image)
    }
}
```

## Test Resources
Place test data in `Tests/resources/`. Do not hardcode absolute paths.
