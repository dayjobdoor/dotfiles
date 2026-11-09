# Protocol and custom transport reference

Read this only when implementing a custom transport, inspecting wire traffic, analyzing framing, or debugging serialization. Use the official [protocol reference](https://capnweb.com/reference/protocol/) or `packages/docs/src/content/docs/reference/protocol.md` in the repository for exact current details.

## Model

Cap'n Web is fully bidirectional: “client” and “server” are documentation roles, not protocol roles. Each session tracks imports and exports. A reference is identified by an ID and may represent an object, function, or promise. IDs are not reused.

The protocol carries expressions over a bidirectional stream of discrete messages. JSON is the base encoding with preprocessing for non-JSON values. Examples of tagged values include dates, bigints, byte arrays, errors, URLs, Fetch headers/requests/responses, and streams. Arrays need special expression encoding so literal arrays are distinguishable from protocol expressions.

## Top-level messages

Know these when reading a trace:

- `push`: evaluate a call/expression and create a promise result.
- `pull`: request the resolution of a promise when the caller actually needs it.
- `resolve` / `reject`: settle an exported promise.
- `release`: drop an import reference and its refcount.
- `stream`: one-shot pulled operation optimized for stream writes.
- `pipe`: establish a stream pipe before sending a readable end.
- `abort`: terminate a failed session.

A pipelined promise can be used in later expressions without a `pull`; if the application never awaits it, the resolution need not cross the wire. This is why request-count and pull behavior are useful integration assertions.

## Framing

WebSocket and `MessagePort` provide message boundaries. HTTP batch uses newline-delimited JSON messages in the request and response bodies. A custom transport must provide equivalent discrete-message framing; do not split or concatenate JSON arbitrarily.

## Transport contract

The default `RpcTransport` is:

```ts
interface RpcTransport {
  send(message: string): Promise<void>
  receive(): Promise<string>
  abort?(reason: unknown): void
}
```

For custom encoding, use the installed `RpcTransportWithCustomEncoding` type and declare one of `jsonCompatible`, `jsonCompatibleWithBytes`, or `structuredClonable`. Return an encoded byte size when available so stream flow control can estimate in-flight data.

Requirements:

- `send` preserves ordering and propagates failures;
- `receive` resolves exactly one complete message and rejects on disconnect;
- `abort` stops the session and tries to communicate the failure where possible;
- queues and frames have bounded memory;
- concurrent calls and stream writes do not interleave message contents;
- close is distinguishable from malformed input and transport failure.

Create a `RpcSession(transport, localMain, options)` and use `getRemoteMain()` for the peer's root. A custom transport is still responsible for authentication, origin/channel trust, framing, backpressure, and native payload limits.

## Debugging wire behavior

1. Log message metadata, not payload secrets: direction, message kind, byte count, import/export IDs, and timing.
2. Confirm whether a missing `resolve` is intentional because the promise was only pipelined and never pulled.
3. Check that a batch sends after the intended macrotask and that all desired promises were awaited together.
4. Correlate disconnect/`abort` with broken stubs and pending promises.
5. Reproduce large messages, nested values, stream pressure, and malformed frames under limits.

Do not write a second serializer or mutate protocol expressions to work around an application API problem. Fix the transport contract or the capability/interface design.