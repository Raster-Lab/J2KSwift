---
description: "Use when editing JPIP network streaming code: JPIP client/server, WebSocket transport, HTTP transport, session management, caching, bandwidth throttling, progressive delivery."
applyTo: "Sources/JPIP/**"
---

# JPIP Networking Guidelines

## Actor Isolation
- `JPIPClient` and `JPIPServer` are actors — all mutable state is actor-isolated
- Network callbacks must be `@Sendable`
- Use `async`/`await` for all I/O operations, never blocking calls

## Session Management
- Sessions have unique IDs (channel IDs in JPIP spec)
- Support session persistence across reconnections
- Clean up expired sessions to prevent memory leaks
- Track per-session data-bin delivery state

## Transport
- Support both HTTP and WebSocket transports
- HTTP: stateless request/response with session cookies
- WebSocket: persistent connection with server push
- Handle transport failures with automatic reconnection

## Caching
- Client cache uses data-bin model (precinct, tile-header, main-header bins)
- Server precinct cache should be bounded (evict LRU)
- Cache validation: if client has latest data-bin, don't resend

## Error Handling
- Network errors are expected — handle gracefully
- Implement exponential backoff for reconnection
- Distinguish transient errors (retry) from permanent errors (report)
