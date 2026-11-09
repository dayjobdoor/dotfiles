# Cap'n Web review workflow

Use this for a code review, design review, PR review, or pre-release audit. Report findings by impact and evidence, not by stylistic preference.

## Review order

1. **Boundary and authority:** identify every exported `RpcTarget`, callback, route, session, credential, and returned capability. Verify least authority, authentication, Origin/CORS, runtime validation, and revocation.
2. **Correctness:** inspect batch lifecycle, pipelining dependencies, `.map()` restrictions, error propagation, reconnect/retry semantics, stream cancellation, and server/client call direction.
3. **Lifecycle:** trace ownership of root stubs, returned targets, promises, callbacks, streams, listeners, timers, and WebSockets. Confirm `.dup()` and disposal at every cross-call lifetime.
4. **Transport:** verify the selected runtime adapter, HTTP method/framing, WebSocket upgrade ownership, SSE separation, MessagePort trust, custom transport framing, and native payload limits.
5. **Types:** compare shared interfaces, implementations, session generics, conditional exports, runtime guards, and type fixtures. Check that TypeScript privacy is not being mistaken for runtime privacy.
6. **Performance and operations:** count requests, detect accidental serial awaits, bound fan-out/pipeline work, inspect stream backpressure, CPU/timeouts, queue size, and observability redaction.
7. **Tests and documentation:** require transport integration tests, security cases, disposal/disconnect cases, type tests, reconnect/idempotency tests, and documented runtime/package assumptions.

## Finding priority

- **P0:** unauthenticated authority, cross-origin exposure contrary to policy, injection/unsafe input, unbounded resource exhaustion, or a mutation that can duplicate silently.
- **P1:** broken lifecycle, incorrect batch/pipeline semantics, missing runtime validation, broken reconnect, unsupported transport wiring, or a public capability that fails in normal use.
- **P2:** request amplification, missing backpressure/limits, weak error redaction, missing type coverage, or runtime-specific behavior not tested.
- **P3:** maintainability, naming, docs, or optional simplification after correctness and security are sound.

## Review prompts

Ask explicitly:

- What capability does the caller receive, and what can it reach transitively?
- Which operations are one-shot, retryable, idempotent, or session-scoped?
- Which values are copied, and which remain live references?
- What happens if the response is lost after the server performs the mutation?
- What happens when a client disconnects during a callback or stream?
- Is SSE being used only for one-way notifications, with replay and duplicate-event handling?
- Which limit fires first: proxy/socket, Cap'n Web, application, or CPU budget?
- Can a TypeScript-only declaration accidentally expose a runtime method or accept attacker-controlled data?

## Finding format

Use this compact structure:

```text
P1 — path/to/file.ts:line
Problem: observable failure and affected boundary.
Evidence: request/lifecycle/type/security behavior that proves it.
Fix: smallest concrete correction and regression test.
```

Do not report a generic “best practice” without connecting it to a concrete Cap'n Web failure mode. Re-review changed findings, then run the release gate from `testing.md`.