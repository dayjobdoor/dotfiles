# Testing and debugging

Use behavior-focused tests. The official repository's [tests](https://github.com/cloudflare/capnweb/tree/main/__tests__) and [type tests](https://github.com/cloudflare/capnweb/tree/main/__type-tests__) are useful patterns, but test the application's capability and authorization contract too.

## Test layers

1. **Type contract:** compile the shared interface and implementations with the project's TypeScript command. Test recursive interfaces, callbacks, `RpcPromise` parameters, nullable `.map()`, and stream types when used.
2. **Local session:** connect two in-memory endpoints or a `MessageChannel`; test values, errors, stubs, callbacks, property access, disposal, and broken connections without a network.
3. **Transport integration:** run the actual Workers/Node/Deno/Bun/Hono adapter and assert POST, upgrade, CORS/origin, frame limits, and cleanup behavior.
4. **Application contract:** test authentication, capability scoping, runtime input validation, authorization failures, quotas, and redacted errors.
5. **Performance behavior:** count requests and measure dependent calls versus sequential calls. Exercise concurrent batch calls, pipelining, `.map()`, stream backpressure, and cancellation.

## High-value cases

- two batch calls produce one POST and both results;
- a pipelined dependency produces the expected value without an intermediate pull;
- an unused promise is disposed and does not create unnecessary result traffic;
- `.map()` rejects or is not used for asynchronous/side-effectful callbacks;
- WebSocket calls continue after the first response and server callbacks reach the client;
- a returned `RpcTarget` can be called, while a plain unsupported class fails clearly;
- a retained callback or stub is duplicated, remains usable after the original call, then disposes cleanly;
- `using`/manual disposal closes connections and releases server-side resources;
- rejected calls, remote throws, disconnects, cancellation, and malformed frames break predictably;
- unauthorized methods cannot be reached through a returned capability or a stale stub;
- runtime guards reject wrong types and oversized values before sensitive work;
- stream writes honor backpressure and abort on peer disconnect.

## Test harness guidance

Prefer the project's existing test runner (Vitest is used by the upstream repository) and avoid coupling unit tests to private implementation details. Use a real transport for request-count assertions; mocks alone cannot prove framing, batching, or disposal. Keep fixtures deterministic and remove credentials from snapshots/logs.

To exercise a local HTTP server from real browser/mobile clients without deploying, a public tunnel built on Cap'n Web such as `captun` (`npx captun 3000`, programmatic `createCaptunTunnel`) forwards an HTTPS URL to a local port; keep auth enabled when exposing beyond localhost.

When a test hangs:

1. Check whether a batch promise was never explicitly awaited or disposed.
2. Check whether server-side code is awaiting a client call over a one-shot HTTP batch; that direction cannot complete unless the protocol flow supports it.
3. Check that the WebSocket/MessagePort transport rejects `receive()` on close.
4. Check that a retained capability was duplicated before the delivering call completed.
5. Check the selected runtime export and adapter version.

When types fail:

1. Inspect the installed `capnweb` declarations and export condition (`workerd`, `bun`, or default).
2. Ensure the interface satisfies the package's recursive `RpcCompatible` constraints.
3. Replace TypeScript `private` assumptions with `#private` only for runtime privacy; this is a design issue, not a type error fix.
4. Add a minimal type fixture for the exact recursive/callback/promise shape before changing the public API.

## Release gate

Before shipping, record the package/runtime versions and run typecheck, unit tests, transport integration tests, security tests, and a production-like smoke test. Re-run the smoke test after changing the adapter, compatibility date, WebSocket library, proxy, or payload limits.