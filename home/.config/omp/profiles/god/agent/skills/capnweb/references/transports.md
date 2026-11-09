# Transports and runtimes

Choose the smallest built-in adapter that fits the deployment. The official [README runtime examples](https://github.com/cloudflare/capnweb/blob/main/README.md) are the source of truth for current signatures.

## Selection

| Need | Client/session | Server helper |
| --- | --- | --- |
| One request, finite calls | `newHttpBatchRpcSession` | `newHttpBatchRpcResponse` or `nodeHttpBatchRpcResponse` |
| Long-lived calls/callbacks | `newWebSocketRpcSession` | `newWorkersWebSocketRpcResponse` or `newWebSocketRpcSession` |
| iframe/worker/message channel | `newMessagePortRpcSession` | same helper on the other port |
| unusual bidirectional channel | `new RpcSession(transport, localMain)` | implement `RpcTransport` |

## Cloudflare Workers

Use `newWorkersRpcResponse(request, localMain)` to accept POST batch calls and WebSocket upgrades at one route. Route the path yourself before handing the request to Cap'n Web. Create a fresh `RpcTarget` per request/session when it contains user or connection state. For Durable Objects and Service Bindings, read the current Workers RPC interoperability guidance; Cap'n Web stubs can interoperate with Workers RPC stubs, but feature differences and compatibility dates matter.

```ts
export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const url = new URL(request.url)
    if (url.pathname !== '/api') return new Response('Not found', { status: 404 })
    return newWorkersRpcResponse(request, new Api(env))
  },
}
```

`newWorkersRpcResponse` intentionally handles cross-origin-capable requests. Validate `Origin` before calling it when the API is not designed for cross-origin use; see `security.md`.

## Node.js

Use `nodeHttpBatchRpcResponse(request, response, localMain)` for native HTTP requests. Use the `ws` package and call `newWebSocketRpcSession(ws, localMain)` on each accepted socket. Do not let the HTTP handler and WebSocket server both process the upgrade. Configure `ws` payload limits and close/cleanup behavior.

## Deno

Use `Deno.serve`. For POST requests call `newHttpBatchRpcResponse(req, localMain)`. For upgrades call `Deno.upgradeWebSocket(req)`, then initialize `newWebSocketRpcSession(socket, localMain)` on open. Set response CORS headers only when the security model permits it.

## Bun

The Bun export provides Bun-specific WebSocket helpers. Prefer `newBunWebSocketRpcHandler(() => new Api())` as `Bun.serve({ websocket })`; handle POST with `newHttpBatchRpcResponse`. If using lower-level `newBunWebSocketRpcSession`, wire its returned transport callbacks exactly as the installed types require. Configure Bun's maximum payload length.

## Hono

When an application already uses Hono, prefer the maintained `@hono/capnweb` adapter. It adapts Hono's runtime WebSocket upgrade and fetch handling while the RPC implementation remains a `RpcTarget`. Verify the adapter's peer/runtime compatibility and current API before editing; do not copy an old blog snippet blindly.

Typical shape:

```ts
import { newRpcResponse } from '@hono/capnweb'
import { upgradeWebSocket } from 'hono/cloudflare-workers' // runtime-specific

app.all('/api', c => newRpcResponse(c, new Api(), { upgradeWebSocket }))
```

On Node.js, the upgrade needs `createNodeWebSocket({ app })` from `@hono/node-ws` plus `injectWebSocket(server)` after `serve`; import `upgradeWebSocket` from the adapter matching the deployment target (`hono/cloudflare-workers`, `@hono/node-ws`, Deno equivalent). Standard route middleware (`bearerAuth`, CORS, logging) runs before the RPC route.

## MessagePort

Initialize one session on each side of a `MessageChannel` with `newMessagePortRpcSession(port, localMain)`. Transfer a specific port through an authenticated/validated channel before handing it to RPC. Do not use a `Window` object itself as the port: arbitrary window messages are not authenticated by Cap'n Web.

## Custom transports

Implement a bidirectional message stream with `send(message)`, `receive()`, and optional `abort(reason)`, then construct `new RpcSession(transport, localMain)`. Sessions are symmetric. Ensure `receive()` rejects on disconnect so outstanding calls and future calls become broken.

Use the correct `encodingLevel`:

- `string`: transport sends complete JSON strings; default for HTTP/WebSocket.
- `jsonCompatible`: transport serializes Cap'n Web's JSON-compatible tree.
- `jsonCompatibleWithBytes`: preserves `Uint8Array` for binary serializers such as CBOR/MessagePack.
- `structuredClonable`: uses structured-clone values, suitable for `MessagePort`-like channels.

A custom transport must preserve message boundaries, propagate send/receive failures, bound buffering, and support abort. Add round-trip tests for disconnect, concurrent sends, large values, streams, and backpressure before production use.