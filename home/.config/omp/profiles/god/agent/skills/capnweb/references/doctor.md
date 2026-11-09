# Cap'n Web doctor: diagnosis runbook

There is no official `capnweb doctor` command. Use this runbook when a session fails, hangs, makes too many requests, leaks references, rejects types, or behaves differently across runtimes.

## Evidence first

Record the installed `capnweb` version, runtime and adapter, client/server transport, route/method/status or upgrade code, request count, timing, and redacted error. Reproduce with the smallest `RpcTarget` and one call before changing the application API. Never log tokens, raw arguments, serialized bodies, or remote stack traces.

## Symptom → checks → likely fix

### Cannot connect or upgrade

1. Verify the URL scheme and path (`http(s)` for batch, `ws(s)` for WebSocket), route before Cap'n Web handling, and runtime export condition (`workerd`, `bun`, or default).
2. Confirm the server receives POST or a WebSocket upgrade and that Node/Deno/Bun upgrade ownership is not split between two handlers.
3. Confirm the `RpcTarget` is created and the helper receives the local main object.
4. Check Origin/auth policy and proxy upgrade forwarding.

Fix routing/adapter wiring first; do not add retries until one clean connection works.

### Call hangs

1. For HTTP batch, check that the client has explicitly awaited/`then`ed every result it needs before the batch send turn.
2. Check that server code is not awaiting a client-originated call that cannot complete on a one-shot batch.
3. For WebSocket/MessagePort/custom transports, verify `receive()` rejects on close and that frames are delivered one at a time.
4. Check whether the promise was intentionally only pipelined and never pulled.
5. Check for a retained stub that should have been `.dup()`ed or a disposed root/promise.

Use a timeout in tests so a missing pull or transport rejection becomes a failure rather than an indefinite process.

### Too many HTTP requests

1. Count actual POSTs with a real transport.
2. Find early `await`, `.then()`, or `Promise.resolve()` that ends the batch before dependent calls are added.
3. Keep independent results and await them together; pass dependent `RpcPromise`s as parameters or properties.
4. Confirm the batch is not reused after completion; create a new batch for later work.

Do not expect a long-lived WebSocket to behave like one-shot batch scheduling.

### Remote method/property is missing

1. Confirm the exported runtime object extends `RpcTarget`; a TypeScript interface alone does not export implementation behavior.
2. Confirm the method is on the prototype and is not a `#private` name.
3. Do not mistake TypeScript `private` for runtime privacy: it remains remotely callable.
4. Inspect installed declarations and the runtime export for version/condition mismatches.
5. Await the call to surface a remote missing-method error; proxy property access is permissive until resolution.

### Callback or returned capability breaks later

A parameter stub is disposed after the delivering call unless the receiver duplicates it. Call `.dup()` before retaining a callback or remote object, dispose the duplicate when the owner is done, and implement `[Symbol.dispose]()` for targets that own retained resources.

### Memory, socket, or Durable Object state grows

Trace every root stub, returned capability, callback, stream, timer, and listener to an owner and lifetime. Add `using` or explicit disposal, close WebSockets, release listeners on disconnect, and test repeated connect/disconnect cycles. Do not rely on local garbage collection to reclaim remote resources.

### Type errors after an upgrade

1. Run the project’s package-manager typecheck and inspect the installed `dist/*.d.ts` rather than guessing.
2. Verify the interface is compatible with the package’s recursive `RpcCompatible` constraints.
3. Minimize the failing shape: recursive target, callback, `RpcPromise` parameter, union, stream, or runtime-specific value.
4. Check the package `exports` condition and `moduleResolution`.
5. Add a type fixture for the intended public API before weakening types with `any`.

### Large payload, stream, or CPU failure

Compare Cap'n Web limits with native socket/proxy limits. The transport may buffer a complete frame before Cap'n Web checks it. Inspect chunk size, total bytes, backpressure, cancellation, per-operation CPU, and rate limits. Reduce payload or stream it; do not merely increase every limit.

## Doctor completion

Diagnosis is complete when the failure is reproduced with a minimal case, one root cause is supported by transport/type/request evidence, the smallest fix is applied, and a regression test covers the original symptom plus its runtime-specific boundary.