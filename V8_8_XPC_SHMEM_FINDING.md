# V8.8 — xpc_shmem / dispatch_data_t alternative to NSXPCConnection: projected wash

**Status**: PARTIALLY USABLE but PROJECTED WASH. xpc_shmem can be transported through NSXPCConnection but won't reduce the 5 ms client-side overhead because that overhead is NOT in byte movement.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)

## Goal

Workstream 5 of the overnight research: determine whether `xpc_shmem` (the lower-level XPC C API for shared memory) and `dispatch_data_t` (immutable dispatch buffer over shared regions) can bypass NSXPCConnection's bytes-transfer + serialisation overhead while still using XPC's Mach-port-based handoff.

## Verdict

**Partially usable.** `xpc_shmem_t` and `dispatch_data_t` *can* be transported through NSXPCConnection via `setXPCType:forSelector:argumentIndex:ofReply:` (macOS 10.14/10.15+), but doing so will *not* meaningfully reduce the 5 ms client-side overhead because that overhead is the NSXPCInterface proxy machinery (NSSecureCoding archive/unarchive of the *envelope*, continuation bridging, NSXPCDecoder validation), **not** the byte transfer of the 25 MB payload — which is already an OOL Mach copy-on-write handoff under the hood.

## How xpc_shmem actually works

- `xpc_shmem_create(void *region, size_t length)` returns an `xpc_object_t` (typed `XPC_TYPE_SHMEM`) that wraps a Mach memory entry created from a caller-owned VM region (must be `mmap(MAP_SHARED)` — not `malloc`).
- On the receiving side, `xpc_shmem_map(xpc_object_t shmem, void **region)` materialises a fresh page-aligned mapping into the recipient's address space and returns its size; the receiver owns the unmapping (`munmap`).
- Transport itself is a Mach port descriptor — no bytes flow through the message body, only a port right; the kernel sets up COW page-table entries on first touch.
- `dispatch_data_t` allocated with the `DISPATCH_DATA_DESTRUCTOR_MUNMAP` deallocator is the higher-level analog: the XPC runtime detects it via `xpc_data_create_with_dispatch_data` and uses the same OOL Mach-port path for buffers above the inline cutoff (~16 KiB per Quinn's forum post).

## Compatibility with NSXPCConnection

**Works as of macOS 10.14/10.15** via one specific API:
```objc
[interface setXPCType: XPC_TYPE_SHMEM
            forSelector: @selector(decodeFile:reply:)
            argumentIndex: 0
            ofReply: NO];
```

(Declared `API_AVAILABLE(macos(10.14))`, but Quinn the Eskimo confirms the practical floor is 10.15 — 10.14 is a header-availability bug, radar 57736296.)

You declare an argument or reply slot to be `XPC_TYPE_SHMEM` / `XPC_TYPE_FD` / `XPC_TYPE_DATA`, and NSXPCConnection routes the raw `xpc_object_t` through the bridge instead of NSSecureCoding it.

`dispatch_data_t` does **not** need this opt-in — Quinn's documented pattern is to wrap the `mmap`'d region in `DispatchData(bytesNoCopy:deallocator:.unmap)`, bridge to `NSData`, and pass through a normal `Data` reply parameter; the runtime recognises large dispatch_data and elides the copy.

**What does not work**: there is no published precedent on GitHub of any production project using `setXPCType` with `XPC_TYPE_SHMEM` over NSXPCConnection. All real-world large-buffer XPC transports either use plain `Data`-of-mmap-backed-DispatchData, or drop NSXPC and use raw `xpc_connection_t` end-to-end.

## Projected savings

**Under 1 ms; below 3 ms threshold.**

Our own measurements (V8_8_DaemonOverheadDecomposition + V8_8_IPCAlternativesBench) already prove the 25 MB byte movement is **not** where the time goes:

| Primitive               | Combined cost |
|-------------------------|---------------|
| `mach_vm_remap`         | 0.005 ms      |
| Pure `memcpy`           | 0.63 ms       |
| IOSurface (intra-proc)  | 2.19 ms       |
| (Reference: NSXPC OOL)  | ~2.5 ms       |

…yet NSXPCConnection charges 5 ms total. The residual ~4–5 ms is in the **NSXPCInterface proxy**:

- `_methodSignatureForRemoteSelector:` — protocol-method introspection
- `NSXPCEncoder` writing the envelope dictionary
- Queue-hopping the reply continuation
- `NSXPCDecoder` allowed-class validation on the receiving side

These costs do **not** disappear when the payload type is swapped from `Data` to `xpc_shmem_t`, because the message envelope, the `NSInvocation` re-hydration, and the reply-block continuation still go through the same NSXPC path. Best-case savings: ~0.5–1 ms (skipping the NSData copy-into-decoder step on 25 MB).

## What WOULD eliminate the proxy overhead

**Drop NSXPCConnection entirely for raw `xpc_connection_t`.** This would close the gap (no proxy, no NSSecureCoding) but is a 2–3 week engineering effort:

- Hand-rolled message dispatch
- Hand-rolled error / disconnect / restart semantics
- Hand-rolled Swift API surface (no Swift wrapper exists; `SwiftXPC` / `sXPC` wrap NSXPCConnection, not the C API)
- Lose the reconnect/invalidation handlers NSXPCConnection gives free

Plus: `xpc_type_t` is not Swift-importable; you need an `.m` shim that calls the C API, with Swift bridging.

For projected ~3–5 ms wall savings on warm-cache CLI loops only (cold-shot path is dominated by Metal init, which the daemon already avoids), this is below the v7.4 acceptance gate.

## Recommendation

**Close as wash with NSXPCConnection retained.** The IPC layer mirrors the codec hot-path lever-ceiling pattern (10 prior wash investigations across decode + encode + dispatch + Accelerate + AMX): byte movement is fast, residuals are framework overhead that doesn't yield to payload-type swaps.

The cleanest win-condition for IPC overhead reduction would be a future macOS SDK that ships a lower-overhead NSXPCConnection-equivalent, OR a complete rewrite of the daemon plumbing on raw `xpc_connection_t`. Neither qualifies for autonomous-overnight implementation work.

## Sources

- [Apple Developer Forums — Efficiently sending data from an XPC process to the host (Quinn "The Eskimo!")](https://developer.apple.com/forums/thread/126716)
- [Apple Developer Forums — Usage of XPC Framework](https://developer.apple.com/forums/thread/700378)
- [xpc_shmem_create man page](https://www.manpagez.com/man/3/xpc_shmem_create/)
- [xpc_shmem_map man page](https://www.unix.com/man_page/osx/3/xpc_shmem_map/)
- [WWDC 2013 Session 702 — Efficient Design with XPC](https://asciiwwdc.com/2013/sessions/702)
- [objc.io Issue 14 — XPC (dispatch_data + mmap pattern)](https://www.objc.io/issues/14-mac/xpc/)
- [NSXPCConnection.h header — `setXPCType:forSelector:argumentIndex:ofReply:`](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS13.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSXPCConnection.h)

## What stays in tree

- `V8_8_XPC_SHMEM_FINDING.md` — this document.

No code change. No microbench (the API surface review + projection from existing benches is the deliverable).
