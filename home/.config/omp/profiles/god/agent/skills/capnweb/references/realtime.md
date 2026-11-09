# WebSocket, SSE, and real-time design

## WebSocket best practices

Use WebSocket when the session is long-lived, the client and server both need to call each other, or the server must push callbacks through Cap'n Web. Keep one intentional root session per logical client, dispose it on logout/unmount/close, and give reconnection a bounded exponential backoff with jitter.

Authenticate the session in-band or with a transport mechanism that is actually available in the target browser. Validate `Origin` when cross-origin access is not intentional. Configure native frame/payload limits in addition to Cap'n Web limits. Handle `close`, `error`, `onRpcBroken()`, cancellation, and server-side resource cleanup as one lifecycle.

Make reconnect-safe methods idempotent or attach request IDs. A reconnect can repeat a call after the caller lost the response; never assume “sent once” means “executed once”. Recreate session-scoped capabilities after reconnect and do not reuse broken stubs. Use pipelining for dependent calls, but do not enqueue unbounded work before applying authorization and quotas.

Do not use WebSocket merely because an occasional request needs low latency; HTTP batch is simpler and cheaper for finite calls. Do not put an independent application framing protocol around Cap'n Web messages unless the transport still preserves one complete RPC message per frame.

## SSE is not a native Cap'n Web transport

Cap'n Web's built-in transports are HTTP batch, WebSocket, and `MessagePort`; SSE is unidirectional server-to-client text streaming and cannot provide the bidirectional `RpcTransport` contract. Do not advertise SSE as a drop-in replacement for a Cap'n Web session or send half of an RPC protocol over an ad-hoc SSE endpoint.

Use SSE beside Cap'n Web when the product needs server-to-browser notifications but client commands can use HTTP batch or another channel:

- `POST /api` or Cap'n Web HTTP batch for commands and queries;
- `GET /events` as a dedicated SSE stream for notifications;
- an event ID and `Last-Event-ID` strategy for reconnect/resume;
- authorization that works for the browser's EventSource constraints;
- heartbeat comments, bounded replay, backpressure policy, and cleanup on disconnect.

Keep event payloads as versioned application data, not internal Cap'n Web expressions. Treat duplicate events as normal and make client handlers idempotent. If the server must invoke a client callback or the client must acknowledge/return data interactively, use WebSocket/Cap'n Web or a separate authenticated request rather than pretending SSE is bidirectional.

## Hono with real-time endpoints

With Hono, route Cap'n Web through the maintained `@hono/capnweb` adapter and keep SSE on a separate route using the current Hono streaming/SSE API for the selected runtime. Do not pass an SSE response into `newRpcResponse`, and do not let wildcard CORS or shared middleware accidentally bypass the auth policy of either channel. Test upgrade, stream cancellation, proxy buffering, heartbeat delivery, reconnect, and origin behavior independently.