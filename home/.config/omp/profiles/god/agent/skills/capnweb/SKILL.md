---
name: capnweb
description: Build, integrate, review, test, diagnose, and secure Cap'n Web JavaScript-native RPC systems and real-time integrations. Use whenever a task mentions capnweb, Cap'n Web, RpcTarget, RpcStub, RpcPromise, promise pipelining, remote object capabilities, newHttpBatchRpcSession, newWebSocketRpcSession, newMessagePortRpcSession, WebSocket/WS, SSE/EventSource alongside RPC, Cloudflare Workers RPC interoperability, Hono/@hono/capnweb, captun tunnels, TypeScript type errors, anti-patterns, best practices, doctor/diagnosis, or code/design review.
---

# Cap'n Web

Use Cap'n Web as an object-capability RPC layer for JavaScript runtimes. The official docs under `packages/docs` in the repository (published at capnweb.com) are the source of truth, ahead of the README. Prefer current package types over remembered API details; the project is young and its API evolves.

## Workflow

1. **Inspect Cap'n Web wiring first.** Read the installed `capnweb` declarations (`dist/*.d.ts`), the active export condition (`workerd`, `bun`, or default), and the server adapter in use (`@hono/capnweb`, Workers, Node `ws`, Bun, Deno, or custom `RpcTransport`). Confirm version-specific signatures before changing calls or transports.
2. **Choose the topology.** Decide whether the connection is one-shot HTTP batch, long-lived WebSocket, `MessagePort`, or a custom bidirectional transport. Decide which side exports the main `RpcTarget`; sessions are symmetric even when the application calls one side “server”.
3. **Define the capability surface.** Put the public TypeScript interface in a shared module when client and server share source. Implement exported classes with `extends RpcTarget`; expose only intended prototype methods and use JavaScript `#private` members for methods that must not be remotely callable.
4. **Model latency explicitly.** Use `RpcPromise` for dependent calls and `Promise.all` for batch results. Use `.map()` only for synchronous, RPC-only recordable callbacks. Do not pull intermediate values locally when a pipeline can express the dependency.
5. **Model ownership.** Dispose long-lived stubs, promises, returned objects, and retained callbacks. Use `using` when supported or call `[Symbol.dispose]()` explicitly. Duplicate a stub with `.dup()` before retaining it beyond the call that supplied it.
6. **Secure the boundary.** Treat TypeScript as compile-time only. Authenticate in-band when browser WebSockets prevent reliable custom headers, validate `Origin` when the endpoint is not intentionally cross-origin, validate all untrusted values at runtime, and apply operation, CPU, message-size, and transport payload limits.
7. **Verify behavior.** Run an integration test over the selected transport and assert request counts for batching/pipelining, disposal of retained references, reconnect/error behavior, authorization, malformed inputs, and large payload handling.

## Route to references

Load a reference ONLY when its route matches the task — never preload. For API design or integration work, start with [references/core-api.md](references/core-api.md) — MANDATORY, read entire file (~113 lines) `[freedom: low]`. Other routes are narrow; do not load them unless the task matches:

- **Transports and runtimes (Workers, Node, Deno, Bun, Hono, MessagePort, custom):** read [references/transports.md](references/transports.md) (~71 lines) `[freedom: medium]`. Do not load for API-only or type-only work.
- **WebSocket lifecycle, SSE/EventSource coexistence, reconnect, and Hono real-time routes:** read [references/realtime.md](references/realtime.md) (~28 lines) `[freedom: medium]`. Do not load for HTTP batch-only RPC.
- **Security, authentication, validation, limits, and threat review:** read [references/security.md](references/security.md) (~76 lines) `[freedom: low]`. Do not load until boundary auth or validation is in scope.
- **Custom transport implementation or wire debugging only:** read [references/protocol.md](references/protocol.md) (~61 lines) `[freedom: low]`. Do not load for built-in adapters or application design.
- **A failure or hang — never for design work:** read [references/doctor.md](references/doctor.md) (~68 lines) `[freedom: low]`. Do not load when designing a new API or transport.
- **Review or best-practice audit:** read [references/anti-patterns.md](references/anti-patterns.md) (~35 lines) + [references/review.md](references/review.md) (~45 lines) `[freedom: medium]`. Do not load during initial implementation.
- **TypeScript contracts, export conditions, and upgrade/type failures:** read [references/type-system.md](references/type-system.md) (~63 lines) `[freedom: medium]`. Do not load for runtime-only debugging.
- **Test strategy, fixtures, and release checks:** read [references/testing.md](references/testing.md) (~50 lines) `[freedom: medium]`. Do not load for wire-protocol or security threat modeling alone.

## Design rules

- Treat every remote call as fallible and latency-sensitive; do not hide network calls behind APIs that look purely local without documenting that contract.
- Keep the RPC interface capability-oriented: return the smallest `RpcTarget` or callback capability needed for the next operation rather than a broad ambient service.
- Keep serialization boundaries explicit. Pass data by value when a snapshot is intended; pass an `RpcTarget` or function only when the recipient should retain a callable capability.
- Do not assume arbitrary application classes, cycles, `Map`, or `Set` serialize. Check the installed version and the core reference before choosing a value shape.
- Do not send secrets through logs, error stacks, serialized payloads, or debug traces. Redact RPC arguments and returned errors in observability code.
- Prefer the built-in transport helpers and runtime adapters before implementing `RpcTransport`; custom transports are a protocol and flow-control responsibility, not merely a `send()` wrapper.
