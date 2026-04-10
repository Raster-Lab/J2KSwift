---
description: "Use when writing Swift 6 code in J2KSwift: strict concurrency, Sendable types, actor isolation, async/await patterns, value types, Swift Package Manager conventions."
applyTo: "**/*.swift"
---

# Swift 6 Conventions for J2KSwift

- Use Swift 6 strict concurrency model at all times
- Mark types as `Sendable` when they are thread-safe
- Use `actor` for mutable shared state, not locks or queues
- Prefer `struct` over `class` for data types
- Use `async`/`await` over completion handlers
- Avoid `@unchecked Sendable` unless documented
- No `fatalError` in production code (only in test placeholders)
- No force unwraps (`!`) in production code

## Naming
- Types/Protocols: `UpperCamelCase` (prefix with `J2K` for public types)
- Functions/Variables: `lowerCamelCase`
- Constants/Enum cases: `lowerCamelCase`

## Error Handling
- Use `throws` for recoverable errors
- Errors go through `J2KError` enum with contextual messages
- Validate at system boundaries (public API entry points)

## Documentation
- All public APIs need `///` doc comments with summary, parameters, returns, throws
- Use `- Parameter name:` format
- Include code examples for complex APIs
