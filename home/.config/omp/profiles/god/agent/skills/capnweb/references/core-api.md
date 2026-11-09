# Core API reference

Read this for API design, call semantics, serialization choices, and lifecycle bugs. Confirm details against the installed `capnweb` version and the official [README](https://github.com/cloudflare/capnweb/blob/main/README.md).

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

Common pass-by-value values include primitives, plain objects, arrays, `bigint`, `Date`, `RegExp`, byte containers, `Error` subclasses, `Blob`, `URL`, Fetch `Headers`/`Request`/`Response`, and readable/writable streams. Values are copied and must form a tree; do not rely on cycles or aliases. Check the package source/types before using less common platform values. `Map`, `Set`, and application classes that do not extend `RpcTarget` are not portable assumptions.

Use a `RpcTarget` when the receiver needs a live capability. Own instance properties are not exposed as remote properties; prototype methods are callable. TypeScript `private` is erased at runtime and is not a security boundary. Use JavaScript `#private` names for methods that must be inaccessible over RPC.

Plain functions also cross by reference as callable stubs. A callback retained after the delivering method returns must be duplicated with `.dup()` on the receiving side.

## `RpcStub` and `RpcPromise`

- `RpcStub<T>` is a proxy for a remote object or function. It is typed by `T` but runtime method existence is discovered only when the call resolves.
- An RPC method returns an `RpcPromise<T>`, a thenable proxy rather than a native `Promise`. It can be awaited, chained with `.then()`, or used as a stub before resolution.
- A property access such as `stub.userId` produces an `RpcPromise`; await it to obtain the value.
- `onRpcBroken(callback)` reports a disconnected session or rejected promise.
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

Remote references are not reclaimed reliably by local garbage collection. Use explicit resource management:

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

Remote throws arrive as rejected promises. Surface stable application errors to clients and keep stack traces/logs private. Test rejected calls, disconnects, cancellation, and calling a disposed or broken stub.