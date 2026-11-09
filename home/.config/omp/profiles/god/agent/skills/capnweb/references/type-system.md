# TypeScript and runtime type guidance

Read this for public API design, upgrade failures, recursive RPC types, and type-focused reviews. The installed `capnweb` declarations are authoritative for the package version in use.

## Public interface shape

Prefer a shared interface that describes only the remote capability:

```ts
import type { RpcTarget, RpcStub, RpcPromise } from 'capnweb'

export interface PublicApi extends RpcTarget {
  authenticate(token: string): AuthedApi
  getProfile(id: string): Promise<Profile>
}

export interface AuthedApi extends RpcTarget {
  getUserId(): number
  getFriendIds(): number[]
}

export type Profile = { name: string; photoUrl: string }
```

Implement the interface with a class extending the runtime `RpcTarget`. On the client, parameterize the session with the shared interface so `RpcStub<T>` and `RpcPromise<T>` provide autocomplete and compile-time shape checking.

Do not expose implementation-only methods through the shared interface. Do not assume a type annotation changes wire behavior: TypeScript is erased and Cap'n Web does not automatically validate application schemas at runtime.

## Promise and callback typing

A remote call returns `RpcPromise<T>`, which is thenable and also supports pipelined properties/methods. Use it as `T` in another RPC parameter when the package's generic constraints accept it; await only at the boundary where a local value is required. Explicitly type callback capabilities as `RpcStub<Fn>` when they are stored or retained, and call `.dup()` when their lifetime crosses a method call.

For recursive targets, callbacks, unions, nullable mapper results, streams, and nested promise parameters, create a small compile-only fixture. Avoid `any` as the first response to `RpcCompatible<T>` errors; it hides a public contract mistake.

## Runtime privacy and validation

- TypeScript `private` is not remotely private.
- JavaScript `#private` names are not exposed through the RPC proxy.
- Own instance properties are not the same as prototype methods and should not be treated as a public state API.
- Validate untrusted input at the RPC boundary, preferably with `capnweb-validate` (derived from the exported types), composed with a schema/guard for value-level constraints — before databases, queries, filesystem, HTML, or resource allocation.
- Keep serialized DTOs plain and versionable; return a target only when live authority is intended.

## Export conditions and upgrades

Inspect `package.json` exports and installed declarations when behavior differs between Workers, Bun, Node, Deno, or browser builds. A type failure can come from the wrong conditional export, TypeScript `moduleResolution`, duplicate package versions, or a changed recursive constraint—not only from application code.

When upgrading:

1. record old/new package and runtime versions;
2. run type tests before changing the API;
3. isolate the smallest failing type shape;
4. inspect the changelog/source for disposal, transport, and compatibility changes;
5. update implementation and integration fixtures together.

## Type-review checklist

- [ ] Session generic matches the actual exported main capability.
- [ ] Every implementation method is intentionally present in the public interface.
- [ ] `RpcPromise` is not confused with a native `Promise` in ownership or disposal logic.
- [ ] Callback and returned-target lifetimes are represented in code/tests.
- [ ] Runtime guards cover values TypeScript cannot enforce.
- [ ] Unsupported/cyclic values are not hidden behind broad types.
- [ ] Conditional runtime exports and adapter types are tested in CI.
- [ ] Type-only imports do not accidentally become runtime dependencies.