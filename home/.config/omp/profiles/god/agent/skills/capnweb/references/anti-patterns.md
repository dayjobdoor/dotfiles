# Anti-patterns and best practices

Use this list during design and review. Each item is a concrete Cap'n Web failure mode, not a generic style preference.

## NEVER list

- **NEVER treat a remote stub as a local object.** Every method can fail, block on transport, consume a capability, and have server-side cost. Document latency and failure behavior at the interface boundary.
- **NEVER await each dependent call locally.** Pass the `RpcPromise` or its property into the next RPC to preserve promise pipelining and avoid serial round trips.
- **NEVER reuse a completed HTTP batch.** Its stubs and returned references are broken after the response; create a new batch.
- **NEVER use `.map()` for arbitrary local computation, asynchronous callbacks, side effects, or unreviewed captured state.** It is a synchronous record/replay mechanism that transmits captured capabilities.
- **NEVER rely on TypeScript `private` for RPC privacy.** It is erased; use `#private` or keep the method outside the exported target.
- **NEVER retain a callback or stub without `.dup()`.** Parameter references are disposed after the call; later notifications will fail or silently target a released capability.
- **NEVER rely on garbage collection for remote cleanup.** Dispose roots, returned targets, promises, callbacks, streams, and session resources explicitly.
- **NEVER expose a broad unauthenticated root and “check auth later”.** Return a least-authority authenticated capability and enforce authorization on every sensitive operation.
- **NEVER assume browser WebSocket headers/cookies provide the same authentication as HTTP.** Use in-band auth or a browser-compatible, tested mechanism.
- **NEVER treat SSE as a Cap'n Web transport.** SSE is one-way; use it as a separate notification channel beside RPC, with replay and idempotency.
- **NEVER configure only Cap'n Web's message limit.** Native WebSocket, `ws`, Bun, proxy, and load-balancer buffering can exhaust memory before the library sees a complete message.
- **NEVER log raw RPC payloads, tokens, remote errors, or stack traces in production.** RPC arguments may contain credentials, personal data, or capability-bearing objects.
- **NEVER let reconnect blindly repeat non-idempotent mutations.** Use request IDs, idempotency keys, or explicit recovery semantics.

## Best-practice design

1. **Shape capabilities, not endpoints.** Return a resource-scoped `RpcTarget` or callback with the smallest authority needed for the next operation.
2. **Separate data from authority.** Use plain serializable values for snapshots; use `RpcTarget`/function references only when the receiver needs a live callable capability.
3. **Make lifetime visible.** Pair every returned/retained reference with an owner, disposal point, and disconnect behavior.
4. **Prefer one shared interface.** Keep the public TypeScript contract close to both implementations, but still validate all runtime inputs.
5. **Choose transport by lifetime.** HTTP batch for finite grouped work, WebSocket for ongoing bidirectional interaction, MessagePort for trusted browser contexts, SSE for one-way notifications.
6. **Design for retries and partial failure.** Assign operation IDs where a lost response could cause a duplicate mutation; return stable error categories without internal detail.
7. **Bound work before pipelining.** Authenticate and enforce quotas before allowing expensive fan-out or `.map()` pipelines.
8. **Measure the wire contract.** Test request count, pull/resolve behavior, payload bytes, round-trip latency, stream backpressure, and cleanup rather than relying only on mocked methods.
9. **Keep adapter boundaries explicit.** Hono, Workers, Node, Deno, and Bun own different upgrade/CORS/stream lifecycle details; test each selected adapter instead of copying a runtime snippet.
10. **Read the installed types for version-sensitive behavior.** Export conditions, disposal semantics, Workers compatibility flags, and helper signatures can change.

## Smell test

A design needs review when a method returns a global service, accepts an unbounded array, stores a callback without a lifetime, hides multiple RPCs behind a synchronous-looking function, mixes SSE and RPC framing, or assumes a successful send means a successful mutation.