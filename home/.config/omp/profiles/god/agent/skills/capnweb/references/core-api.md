# Core API reference

Read this for API design, call semantics, serialization choices, and lifecycle bugs. Confirm details against the installed `capnweb` version and the official docs (`packages/docs/src/content/docs/` in [cloudflare/capnweb](https://github.com/cloudflare/capnweb), published at capnweb.com); the README is only an index to them.

## Minimal shape

```ts
import { RpcTarget, newWorkersRpcResponse } from 'capnweb'

export interface PublicApi extends RpcTarget {
  hello(name: string): string
}

export class Api extends RpcTarget implements PublicApi {
  hello(name: string) {
    return `Hello, ${name}!`
  }
}

export default {
  fetch(request: Request) {
    return newWorkersRpcResponse(request, new Api())
  },
}
```

```ts
import type { PublicApi } from './api'
import { newWebSocketRpcSession } from 'capnweb'

const api = newWebSocketRpcSession<PublicApi>('wss://example.com/api')
console.log(await api.hello('World'))
```

`RpcTarget` marks an object as pass-by-reference. A plain application class is not RPC-compatible. The remote side receives a proxy; methods and properties are resolved remotely rather than copied.

## Pass by value vs reference

Common pass-by-value values include primitives, plain objects, arrays, `Set`, `bigint`, `Date`, `RegExp`, byte containers, `Error` subclasses, `Blob`, `URL`, Fetch `Headers`/`Request`/`Response`, and readable/writable streams. Values are copied and must form a tree; do not rely on cycles or aliases. A `Set` cannot directly contain a promise or `Blob`. Check the installed package source/types before using `Set`, `RegExp`, or other less common platform values, because documentation on the main branch can run ahead of the release. `Map` is not yet supported, and application classes that do not extend `RpcTarget` are intentionally unsupported.

Use a `RpcTarget` when the receiver needs a live capability. Prototype methods and getters are callable. Own instance properties (constructor assignments and class fields) are not exposed, and reading one throws. A setter can never fire over RPC (assigning to a stub throws), so expose writes as methods. TypeScript `private` is erased at runtime and is not a security boundary for methods. Use JavaScript `#private` names for members that must be inaccessible over RPC.

Plain functions also cross by reference as callable stubs. A callback retained after the delivering method returns must be duplicated with `.dup()` on the receiving side.

## `RpcStub` and `RpcPromise`

- `RpcStub<T>` is a proxy for a remote object or function. It is typed by `T` but runtime method existence is discovered only when the call resolves.
- An RPC method returns an `RpcPromise<T>`, a thenable proxy rather than a native `Promise`. It can be awaited, chained with `.then()`, or used as a stub before resolution.
- A property access such as `stub.userId` produces an `RpcPromise`; await it to obtain the value.
- `stub.onRpcBroken(callback)` reports a disconnected session or rejected promise.
- `RpcStub(target)` can make a local object behave like a stub when a uniform local/remote abstraction is useful.

## HTTP batch

```ts
const batch = newHttpBatchRpcSession<PublicApi>('https://example.com/api')
const one = batch.hello('Alice')
const two = batch.hello('Bob')
const [a, b] = await Promise.all([one, two])
```

Calls are collected until the send turn, then sent as one POST. Store every result that should be returned and await or `.then()` them before the batch is sent; only pulled results need to be returned. After the batch completes, its root and remote references are no longer usable. Start a new batch for later work. Do not accidentally await a call early if the goal is one round trip.

## WebSocket and pipelining

A WebSocket session stays open for later calls and permits server-to-client callbacks. It still supports pipelining:

```ts
const user = api.authenticate(cookie)
const profile = await api.getUserProfile(user.id)
```

The second call can be encoded before the first result is delivered. Document the expected round trips in latency-sensitive code and dispose the root stub to close the connection.

## Promise pipelining and `.map()`

A `RpcPromise<T>` may be passed anywhere a `T` is expected, or its properties/methods may be used before awaiting. This builds a dependency graph that the peer evaluates without fetching intermediate values locally.

```ts
const ids = api.listUserIds()
const names = await ids.map(id => [id, api.getUserName(id)])
```

`.map()` is a record/replay operation, not arbitrary code execution. The callback must be synchronous, deterministic, and have no side effects except RPC calls. It cannot await, inspect a not-yet-resolved value, perform meaningful local arithmetic/branching on it, or use arbitrary local state. Captured stubs are sent to the peer, so treat them as capabilities. `null`/`undefined` pass through without invoking the mapper; arrays map element-wise; other values invoke once.

## Streams

`ReadableStream` and `WritableStream` can cross RPC with multiplexing, backpressure, and flow control. Test cancellation, abort, close, and slow consumers. Do not buffer unbounded application data merely because RPC arguments are convenient; enforce application and transport limits.

## Disposal and ownership

Remote references are not reclaimed reliably by local garbage collection. HTTP batch sessions implicitly dispose every stub when the batch ends, so explicit disposal matters most for long-lived sessions (WebSocket, `MessagePort`, custom). Use explicit resource management:

```ts
using api = newWebSocketRpcSession<Api>('wss://example.com/api')
using sessionUser = api.authenticate(token)
const id = await sessionUser.getUserId()
```

The equivalent manual form is `stub[Symbol.dispose]()`; use feature-compatible transpilation/polyfills if the target runtime lacks `using`.

Practical ownership rules:

- The caller disposes stubs it passes as parameters.
- The caller disposes stubs and objects it receives as results.
- A callee that retains a parameter beyond the current call must call `.dup()` and dispose that duplicate later.
- Dispose an unused `RpcPromise`; otherwise it may represent work or a remote reference that is no longer needed.
- Dispose returned objects even when they currently look like plain data; the server may add a nested capability later.
- Use `.dup()` when a stub must outlive a scope or one owner will dispose it.
- Implement `[Symbol.dispose]()` on `RpcTarget` when it owns listeners, timers, retained callbacks, or other resources.

## Errors

Remote throws arrive as rejected promises. Surface stable application errors to clients and keep stack traces/logs private. By default stacks are omitted on the wire, but extra own enumerable properties, `cause`, and `AggregateError.errors` are serialized with the error; use `RpcSessionOptions.onSendError` to log and redact errors before they are sent (a returned `Error` with a `stack` property sends that stack). Test rejected calls, disconnects, cancellation, and calling a disposed or broken stub.
