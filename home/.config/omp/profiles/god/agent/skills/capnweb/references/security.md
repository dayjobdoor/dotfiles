# Security and threat review

Read this for any public endpoint, browser client, callback, remote object, custom transport, or security review. The official [README security section](https://github.com/cloudflare/capnweb/blob/main/README.md) and the runtime's current limits take precedence.

## Threat model

Treat every remote caller, callback, stub, argument, and returned capability as untrusted unless the session was authenticated and authorized. Cap'n Web supplies invocation and capability mechanics; it does not provide application identity, authorization policy, or runtime schema validation.

## Authentication

Browser WebSockets allow cross-site connections and do not provide a reliable way to set arbitrary authentication headers. Prefer in-band authentication that consumes a credential and returns a narrowly scoped authenticated `RpcTarget`:

```ts
interface PublicApi extends RpcTarget {
  authenticate(token: string): AuthedApi
}

class Api extends RpcTarget {
  authenticate(token: string) {
    const principal = verifyToken(token)
    if (!principal) throw new Error('unauthorized')
    return new AuthedApi(principal)
  }
}
```

Do not return the broad unauthenticated root after authentication. Bind authorization checks to the returned capability and to each sensitive operation. Expire or revoke long-lived capabilities when the session, user, or resource ends.

HTTP cookies/headers may be usable in a deployment-specific batch flow, but do not assume they protect the WebSocket path. Verify origin, CSRF assumptions, token audience, token lifetime, replay behavior, and whether credentials can appear in URLs or logs.

## Origin and cross-origin policy

WebSockets are inherently cross-origin-capable. `newWorkersRpcResponse` and examples may set permissive CORS headers because in-band authorization is expected. Before exposing an endpoint, decide one of:

1. intentionally cross-origin with strong in-band authentication and narrow capabilities, or
2. same-origin/restricted origin with explicit `Origin` validation before the Cap'n Web helper.

Never add `Access-Control-Allow-Origin: *` casually when browser credentials or ambient identity are involved. Test allowed, missing, and malicious origins and both POST and upgrade paths.

## Runtime validation

TypeScript types disappear at runtime. Validate every untrusted input before using it in database filters, shell commands, file paths, HTML, authorization decisions, or resource allocation. Prefer the companion package `capnweb-validate` per the official [runtime validation guide](https://capnweb.com/guides/validation/): build-time validators are generated from the exported TypeScript types (via `@validateRpc()` and a bundler plugin or CLI — an untransformed decorator throws a configuration error at startup), every method is covered, and it fails closed. Compose it with a schema library such as Zod, ArkType, or typia, or use [ts-runtime-checks](https://github.com/GoogleFeud/ts-runtime-checks) for type-to-check transforms; otherwise use runtime guards at the RPC boundary and return bounded errors. Avoid logging raw credentials or arbitrary remote values.

A TypeScript `private` method is still callable remotely because it is erased. Use `#private` for runtime privacy and expose a small public `RpcTarget` surface.

## Capability discipline

An `RpcTarget` or callback is a bearer capability. Returning or retaining a stub grants the ability to invoke its reachable methods. Apply least authority:

- return resource-scoped targets rather than a global service;
- do not pass unrelated stubs into `.map()` callbacks;
- duplicate a callback only when its later lifetime is intentional;
- dispose/revoke capabilities when access ends;
- document whether a returned capability is single-use, session-scoped, or durable.

A mapper's captured stubs are transmitted to the peer. A malicious peer may invoke captured capabilities in ways the application did not expect.

## Resource exhaustion

Promise pipelining can enqueue substantial work before intermediate results are pulled. Protect expensive methods with authentication, quotas, concurrency controls, pagination, rate limits, timeouts, and idempotency where needed. For Workers, review per-request CPU behavior, especially for long-lived WebSocket sessions and Durable Objects.

Apply size limits before expensive processing. Configure both Cap'n Web receiver limits (`RpcSessionOptions.limits`: message size, nesting depth, bigint digits) and native transport/socket limits (`ws` payload limits, Bun payload limits, proxy/load-balancer limits). Cap'n Web's own message check may run only after a transport has delivered a complete frame, so transport buffering is a separate risk. Limit stream chunk sizes, total bytes, and duration.

## MessagePort and custom transports

Do not hand an arbitrary `Window` to RPC. Transfer a dedicated `MessagePort` only after authenticating the sender and validating the message that transfers it. For custom transports, authenticate the channel before creating the session, preserve message boundaries, reject malformed frames, bound queues, and treat `abort()` as a security-relevant teardown.

## Review checklist

- [ ] Authentication works on every transport path, including WebSocket upgrade.
- [ ] Origin/CORS behavior is intentional and tested.
- [ ] Runtime validation covers every attacker-controlled value.
- [ ] Returned and retained capabilities have least authority and an explicit lifetime.
- [ ] `#private` protects methods that must not be remotely callable.
- [ ] Rate, CPU, message, frame, stream, and queue limits are configured.
- [ ] Errors and traces do not disclose credentials, internal paths, or sensitive data.
- [ ] Disconnect, cancellation, revocation, and disposal are tested.